package Slim::Utils::ArtworkCache;

# Lightweight, efficient, and fast file cache for artwork.
#
# This class is roughly 9x faster for get, and 12x faster for set than using Cache::FileCache
# which imposes too much overhead for our artwork needs.  Using a SQLite database also makes
# it much faster to remove the cache.

use strict;

use DBD::SQLite;
use Digest::MD5 ();
use File::Spec::Functions qw(catfile);
use Time::HiRes ();

use constant DB_FILENAME => 'ArtworkCache.db';

{
	if ( $File::Spec::ISA[0] eq 'File::Spec::Unix' ) {
		*fast_catfile = sub { join( "/", @_ ) };
	}
	else {
		*fast_catfile = sub { catfile(@_) };
	}
}

my $singleton;

sub new {
	my $class = shift;
	my $root = shift;
	
	if ( !$singleton ) {
		if ( !defined $root ) {
			require Slim::Utils::Prefs;
			$root = Slim::Utils::Prefs::preferences('server')->get('librarycachedir');
			
			# Update root value if librarycachedir changes
			Slim::Utils::Prefs::preferences('server')->setChange( sub {
				$singleton->wipe;
				$singleton->setRoot( $_[1] );
				$singleton->_init_db;
			}, 'librarycachedir' );
		}
		
		$singleton = bless { root => $root }, $class;
	}
	
	return $singleton;
}

sub getRoot {
	return shift->{root};
}

sub setRoot {
	my ( $self, $root ) = @_;
	
	$self->{root} = $root;
}

sub wipe {
	my $self = shift;
	
	if ( $self->{dbh} ) {
		$self->_close_db;
	}
	
	my $dbfile = fast_catfile( $self->{root}, DB_FILENAME );
	
	unlink $dbfile if -e $dbfile;
}

sub set {
	my ( $self, $key, $data ) = @_;
	
	if ( !$self->{dbh} ) {
		$self->_init_db;
	}
	
	# packed data is stored as follows:
	# 3 bytes type (jpg/png/gif)
	# 32-bit mtime
	# 16-bit length of original file path
	# original file path
	# data
	
	# To save memory and avoid copying the data, we add the header to the original data reference
	# After writing the file, we remove the header so callers don't have to worry about their
	# data being modified
	
	my $ref = $data->{data_ref};
	
	my $packed = pack( 'A3LS', $data->{content_type}, $data->{mtime}, length( $data->{original_path} ) )
	 	. $data->{original_path};
	
	# Prepend the packed header to the original data
	substr $$ref, 0, 0, $packed;
	
	# XXX: bug in DBD::SQLite, if utf-8 flag is on for the string
	# the data is converted to UTF-8 even if it's in a SQL_BLOB field
	utf8::downgrade($$ref);
	
	# Get a 60-bit unsigned int from MD5 (SQLite uses 64-bit signed ints for the key)
	# Have to concat 2 values here so it works on a 32-bit machine
	my $md5 = Digest::MD5::md5_hex($key);
	my $id = hex( substr($md5, 0, 8) ) . hex( substr($md5, 8, 7) );
	
	# Insert or replace the value
	my $set = $self->{set_sth};
	$set->bind_param( 1, $id );
	$set->bind_param( 2, $$ref, DBI::SQL_BLOB );
	$set->execute;
	
	# Remove the packed header
	substr $$ref, 0, length($packed), '';
}

sub get {
	my ( $self, $key ) = @_;
	
	if ( !$self->{dbh} ) {
		$self->_init_db;
	}
	
	# Get a 60-bit unsigned int from MD5 (SQLite uses 64-bit signed ints for the key)
	# Have to concat 2 values here so it works on a 32-bit machine
	my $md5 = Digest::MD5::md5_hex($key);
	my $id = hex( substr($md5, 0, 8) ) . hex( substr($md5, 8, 7) );
	
	my $get = $self->{get_sth};
	$get->execute($id);
	
	my ($buf) = $get->fetchrow_array;
	
	return unless defined $buf;
	
	# unpack data and strip header from data as we go
	my ($content_type, $mtime, $pathlen) = unpack( 'A3LS', substr( $buf, 0, 9, '' ) );
	my $original_path = substr $buf, 0, $pathlen, '';
	
	return {
		content_type  => $content_type,
		mtime         => $mtime,
		original_path => $original_path,
		data_ref      => \$buf, # This saves memory by not copying the data
	};
}

sub pragma {
	my ( $self, $pragma ) = @_;
	
	my $dbh = $self->{dbh} || $self->_init_db;
	
	$dbh->do("PRAGMA $pragma");
	
	if ( $pragma =~ /locking_mode/ ) {
		# if changing the locking_mode we need to run a statement to change the lock
		$dbh->do('SELECT 1 FROM cache LIMIT 1');
	}
}

sub _init_db {
	my $self = shift;
	my $retry = shift;
	
	my $dbfile = fast_catfile( $self->{root}, DB_FILENAME );
	
	my $dbh;
	
	eval {
		$dbh = DBI->connect( "dbi:SQLite:dbname=$dbfile", '', '', {
			AutoCommit => 1,
			PrintError => 0,
			RaiseError => 1,
		} );
		
		$dbh->do('PRAGMA journal_mode = OFF');
		$dbh->do('PRAGMA synchronous = OFF');
		$dbh->do('PRAGMA locking_mode = EXCLUSIVE');
	
		# Create the table, note that using an integer primary key
		# is much faster than any other kind of key, such as a char
		# because it doesn't have to create an index
		$dbh->do('CREATE TABLE IF NOT EXISTS cache (k INTEGER PRIMARY KEY, v BLOB)');
	};
	
	if ( $@ ) {
		if ( $retry ) {
			# Give up after 2 tries
			die "Unable to read/create $dbfile\n";
		}
		
		# Something was wrong with the database, delete it and try again
		$self->wipe;
		
		return $self->_init_db(1);
	}
	
	# Prepare statements we need
	$self->{set_sth} = $dbh->prepare('INSERT OR REPLACE INTO cache (k, v) VALUES (?, ?)');
	$self->{get_sth} = $dbh->prepare('SELECT v FROM cache WHERE k = ?');
	
	$self->{dbh} = $dbh;
	
	return $dbh;
}

sub _close_db {
	my $self = shift;
	
	$self->{dbh}->disconnect;
	
	delete $self->{$_} for qw(set_sth get_sth dbh);
}

1;
