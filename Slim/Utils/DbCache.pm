package Slim::Utils::DbCache;

# Lightweight, efficient, and fast cache
#
# This class is roughly 9x faster for get, and 12x faster for set than using Cache::FileCache.
# Using a SQLite database also makes it much faster to remove the cache.

use strict;

use DBD::SQLite;
use Digest::MD5 ();
use File::Spec::Functions qw(catfile);
use Storable qw(freeze thaw);

use constant DEFAULT_EXPIRES_TIME => 60 * 60;

sub new {
	my ( $self, $args ) = @_;

	return unless $args->{namespace};

	if ( !defined $args->{root} ) {
		require Slim::Utils::Prefs;
		$args->{root} = Slim::Utils::Prefs::preferences('server')->get('cachedir');
		
		# Update root value if librarycachedir changes
		Slim::Utils::Prefs::preferences('server')->setChange( sub {
			$self->wipe;
			$self->setRoot( $_[1] );
			$self->_init_db;
		}, 'cachedir' );
	}
	
	$args->{default_expires_in} ||= DEFAULT_EXPIRES_TIME;
	
	return bless $args, $self;
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
	
	if ( my $dbh = $self->_init_db ) {
		$dbh->do('DELETE FROM cache'); # truncate
		$self->_close_db;
	}
}
*clear = \&wipe;

sub set {
	my ( $self, $key, $data, $expiry ) = @_;
	
	$self->_init_db;
	
	$expiry = _canonicalize_expiration_time(defined $expiry ? $expiry : $self->{default_expires_in});

	my $id = _key($key);
	
	if (ref $data) {
		$data = freeze( $data );
	}
	
	# Insert or replace the value
	my $set = $self->{set_sth};
	$set->bind_param( 1, $id );
	$set->bind_param( 2, $data, DBI::SQL_BLOB );
	$set->bind_param( 3, $expiry ) unless $self->{noexpiry};
	$set->execute;
}

sub get {
	my ( $self, $key ) = @_;
	
	$self->_init_db;

	my $id = _key($key);

	my $get = $self->{get_sth};
	$get->execute($id);

	my ($data, $expiry) = $get->fetchrow_array;
	
	if ($expiry && !$self->{noexpiry} && $expiry >= 0 && $expiry < time()) {
		$data = undef;
#		$self->{delete_sth}->execute($id);
	}
	
	eval {
		$data = thaw($data);
	} if $data;
	
	return $data;
}

sub remove {
	my ( $self, $key ) = @_;

	$self->_init_db;
	
	my $id = _key($key);
	$self->{delete_sth}->execute($id);
}

sub purge {
	my ( $self ) = @_;
	
	my $dbh = $self->_init_db;
	
	$dbh->do('DELETE FROM cache WHERE t >= 0 AND t < ' . time());
}

sub _key {
	my ( $key ) = @_;
	
	# Get a 60-bit unsigned int from MD5 (SQLite uses 64-bit signed ints for the key)
	# Have to concat 2 values here so it works on a 32-bit machine
	my $md5 = Digest::MD5::md5_hex($key);
	return hex( substr($md5, 0, 8) ) . hex( substr($md5, 8, 7) );
}

sub pragma {
	my ( $self, $pragma ) = @_;
	
	if ( my $dbh = $self->_init_db ) {
		$dbh->do("PRAGMA $pragma");

		if ( $pragma =~ /locking_mode/ ) {
			# if changing the locking_mode we need to run a statement to change the lock
			$dbh->do('SELECT 1 FROM cache LIMIT 1');
		}
	}
}

sub close {
	my $self = shift;
	
	$self->_close_db;
}

# The following function is mostly borrowed from Cache::BaseCache

# map of expiration formats to their respective time in seconds
my %_Expiration_Units = ( map(($_,             1), qw(s second seconds sec)),
                          map(($_,            60), qw(m minute minutes min)),
                          map(($_,         60*60), qw(h hour hours)),
                          map(($_,      60*60*24), qw(d day days)),
                          map(($_,    60*60*24*7), qw(w week weeks)),
                          map(($_,   60*60*24*30), qw(M month months)),
                          map(($_,  60*60*24*365), qw(y year years)) );

# turn a string in the form "[number] [unit]" into an explicit number
# of seconds from the present.  E.g, "10 minutes" returns "600"
sub _canonicalize_expiration_time {
	my ( $expiry ) = @_;
	
	if ( lc( $expiry ) eq 'now' ) {
		$expiry = 0;
	}
	elsif ( lc( $expiry ) eq 'never' ) {
		$expiry = -1;
	}
	elsif ( $expiry =~ /^\s*([+-]?(?:\d+|\d*\.\d*))\s*$/ ) {
		$expiry = $1;
	}
	elsif ( $expiry =~ /^\s*([+-]?(?:\d+|\d*\.\d*))\s*(\w*)\s*$/ && $_Expiration_Units{ $2 } ) {
		$expiry = ( $_Expiration_Units{ $2 } ) * $1;
	}
	else {
		$expiry = DEFAULT_EXPIRES_TIME;
	}

	# "If value is less than 60*60*24*30 (30 days), time is assumed to be
	# relative from the present. If larger, it's considered an absolute Unix time."
	if ( $expiry <= 2592000 && $expiry > -1 ) {
		$expiry += time();
	}
	
	return $expiry;
}

sub _get_dbfile {
	my $self = shift;
	
	my $namespace = $self->{namespace};
	
	# namespace should not be longer than 8 characters on Windows, as it was causing DB corruption
	if ( main::ISWINDOWS && length($namespace) > 8 ) {
		$namespace = lc(substr($namespace, 0, 4)) . substr(Digest::MD5::md5_hex($namespace), 0, 4);
	}
	# some plugins use paths in their namespace - which was compatible with FileCache, but no longer is
	elsif ( !main::ISWINDOWS ) {
		$namespace =~ s/\//-/g;
	}
	
	return catfile( $self->{root}, $namespace . '.db' );
}

# only try to re-build once
my $rebuilt;

sub _init_db {
	my $self  = shift;
	my $retry = shift;
	
	return $self->{dbh} if $self->{dbh};
	
	my $dbfile = $self->_get_dbfile;
	
	my $dbh;
	
	eval {
		$dbh = DBI->connect( "dbi:SQLite:dbname=$dbfile", '', '', {
			AutoCommit => 1,
			PrintError => 0,
			RaiseError => 1,
			sqlite_use_immediate_transaction => 1,
		} );

		# caches do see a lot of updates/writes/deletes - enable auto_vacuum
		if ( !$dbh->selectrow_array('PRAGMA auto_vacuum') ) {
			$dbh->do('PRAGMA auto_vacuum = FULL');
			# XXX - running a vacuum automatically might take a long time on larger cache files
			# only enable auto_vacuum when a file is newly created
			#$dbh->do('VACUUM');
		}
		
		$dbh->do('PRAGMA synchronous = OFF');
		$dbh->do('PRAGMA journal_mode = WAL');
		# scanner is heavy on writes, server on reads - tweak accordingly
		$dbh->do('PRAGMA wal_autocheckpoint = ' . (main::SCANNER ? 10000 : 200));

		my ($dbhighmem, $dbjournalsize);
		if (main::RESIZER) {
			require Slim::Utils::Light;
			$dbhighmem = Slim::Utils::Light::getPref('dbhighmem');
			$dbjournalsize = Slim::Utils::Light::getPref('dbjournalsize');
		}
		else {
			require Slim::Utils::Prefs;
			my $prefs = Slim::Utils::Prefs::preferences('server');
			$dbhighmem = $prefs->get('dbhighmem');
			$dbjournalsize = $prefs->get('dbjournalsize');
		}

		$dbh->do('PRAGMA journal_size_limit = ' . ($dbjournalsize * 1024 * 1024)) if defined $dbjournalsize;
	
		# Increase cache size when using dbhighmem, and reduce it to 300K otherwise
		if ( $dbhighmem ) {
			$dbh->do('PRAGMA cache_size = 20000');
			$dbh->do('PRAGMA temp_store = MEMORY');
		}
		else {
			$dbh->do('PRAGMA cache_size = 300');
		}
	
		# Create the table, note that using an integer primary key
		# is much faster than any other kind of key, such as a char
		# because it doesn't have to create an index
		if ($self->{noexpiry}) {
			$dbh->do('CREATE TABLE IF NOT EXISTS cache (k INTEGER PRIMARY KEY, v BLOB)');
		}
		else {
			$dbh->do('CREATE TABLE IF NOT EXISTS cache (k INTEGER PRIMARY KEY, v BLOB, t INTEGER)');
			$dbh->do('CREATE INDEX IF NOT EXISTS expiry ON cache (t)');
		}
	};
	
	if ( $@ ) {
		if ( $retry ) {
			# Give up after 2 tries
			die "Unable to read/create $dbfile\n";
		}
		
		warn "$@Delete the file $dbfile and start from scratch.\n";
		
		# Make sure cachedir exists
		Slim::Utils::Prefs::makeCacheDir() unless main::RESIZER;
		
		# Something was wrong with the database, delete it and try again
		unlink $dbfile;
		
		return $self->_init_db(1);
	}

	# set up error handler to log the db file causing problems
	$dbh->{HandleError} = sub {
		my ($msg, $handle, $value) = @_;

		my $dbfile = $self->_get_dbfile;
		
		require Slim::Utils::Log;
		Slim::Utils::Log::logBacktrace($msg);
		Slim::Utils::Log::logError($dbfile);
		
		if ( $msg =~ /SQLite.*(?:database disk image is malformed|is not a database)/i ) {
			# we've already tried to recover - give up
			if ($rebuilt++) {
				Slim::Utils::Log::logError("Please stop the server, delete $dbfile and restart.");
			}
			else {
				Slim::Utils::Log::logError("Trying to re-build $dbfile from scratch.");
				$self->close();
				unlink $dbfile;
				$self->_init_db(1);
			}
		}
	};
	
	# Prepare statements we need
	if ($self->{noexpiry}) {
		$self->{set_sth} = $dbh->prepare('INSERT OR REPLACE INTO cache (k, v) VALUES (?, ?)');
		$self->{get_sth} = $dbh->prepare('SELECT v FROM cache WHERE k = ?');
	}
	else {
		$self->{set_sth} = $dbh->prepare('INSERT OR REPLACE INTO cache (k, v, t) VALUES (?, ?, ?)');
		$self->{get_sth} = $dbh->prepare('SELECT v, t FROM cache WHERE k = ?');
	}
	$self->{delete_sth} = $dbh->prepare('DELETE FROM cache WHERE k = ?');
	
	$self->{dbh} = $dbh;
	
	return $dbh;
}

sub _close_db {
	my $self = shift;
	
	if ( $self->{dbh} ) {
		$self->{set_sth}->finish;
		$self->{get_sth}->finish;
		$self->{delete_sth}->finish;
		
		$self->{dbh}->disconnect;
	
		delete $self->{$_} for qw(set_sth get_sth dbh);
	}
}

1;
