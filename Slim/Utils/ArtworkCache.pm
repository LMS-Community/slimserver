package Slim::Utils::ArtworkCache;

# Lightweight, efficient, and fast file cache for artwork.
#
# This class is roughly 9x faster for get, and 12x faster for set than using Cache::FileCache
# which imposes too much overhead for our artwork needs.  Using a SQLite database also makes
# it much faster to remove the cache.

use strict;

my $singleton;

sub new {
	my $class = shift;
	my $root = shift;
	
	if ( !$singleton ) {
		$singleton = Slim::Utils::DbArtworkCache->new($root, 'artwork');
	}
	
	return $singleton;
}

1;

package Slim::Utils::DbArtworkCache;

use base 'Slim::Utils::DbCache';
use File::Spec::Functions qw(catfile);

sub new {
	my ($self, $root, $namespace, $expires) = @_;

	if ( !defined $root ) {
		require Slim::Utils::Prefs;
		# the artwork cache needs to be in the same place as the library data for TinyLMS
		$root = Slim::Utils::Prefs::preferences('server')->get('librarycachedir');
		
		# Update root value if librarycachedir changes
		Slim::Utils::Prefs::preferences('server')->setChange( sub {
			$self->wipe;
			$self->setRoot( $_[1] );
			$self->_init_db;
		}, 'librarycachedir' );
	}
	
	return $self->SUPER::new({
		root      => $root,
		namespace => $namespace || 'artwork',
		noexpiry  => $expires ? 0 : 1,
		default_expires_in => $expires,
	});
}

sub set {
	my ( $self, $key, $data ) = @_;
	
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
	
	$data->{content_type} ||= '';
	$data->{mtime} ||= 0;
	$data->{original_path} ||= '';
	
	my $packed = pack( 'A3LS', $data->{content_type}, $data->{mtime}, length( $data->{original_path} ) )
	 	. $data->{original_path};
	
	# Prepend the packed header to the original data
	substr $$ref, 0, 0, $packed;
	
	$self->SUPER::set($key, $$ref);
	
	# Remove the packed header
	substr $$ref, 0, length($packed), '';
}

sub get {
	my ( $self, $key ) = @_;
	
	my $buf = $self->SUPER::get($key);
	
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

sub _init_db {
	my $self  = shift;
	my $retry = shift;

	return $self->{dbh} if $self->{dbh};
	
	my $dbfile    = $self->_get_dbfile;
	my $oldDBfile = catfile( $self->{root}, 'ArtworkCache.db' );
	
	if ($self->{namespace} eq 'artwork' && !-f $dbfile && -r $oldDBfile) {
		require File::Copy;
		
		if ( !File::Copy::move( $oldDBfile, $dbfile ) ) {
			warn "Unable to rename $oldDBfile to $dbfile: $!. Please do so manually!";
		}
	}
	
	return $self->SUPER::_init_db($retry);
}

1;
