package Slim::Utils::ArtworkCache;

# Lightweight, efficient, and fast file cache for artwork.
#
# This class is roughly 5x faster for fetching than using Cache::FileCache which imposes
# too much overhead for our artwork needs, for example we don't need any expiration checking code.
# It's even faster if using the get_fh method to return only a filehandle to the cache file, which
# can then be sent out directly to the client without any extra memory or read overhead.
#
# Most of this module is stolen from CHI::Driver::File and CHI::Util, with some memory usage
# improvements.

use common::sense;
use Digest::MD5 ();
use Fcntl qw(:DEFAULT);
use File::Path qw(mkpath);
use File::Spec::Functions qw(catdir catfile);
use Time::HiRes ();

use constant DEPTH       => 2;
use constant DIR_MODE    => oct(775);
use constant FILE_MODE   => oct(666);
use constant FETCH_FLAGS => O_RDONLY | O_BINARY;
use constant STORE_FLAGS => O_WRONLY | O_CREAT | O_BINARY;

{
	if ( $File::Spec::ISA[0] eq 'File::Spec::Unix' ) {
		*fast_catdir = *fast_catfile = sub { join( "/", @_ ) };
	}
	else {
		*fast_catdir  = sub { catdir(@_) };
		*fast_catfile = sub { catfile(@_) };
	}
}

my $singleton;

sub new {
	my $class = shift;
	
	if ( !$singleton ) {
		require Slim::Utils::Prefs;
		my $root = fast_catdir(
			Slim::Utils::Prefs::preferences('server')->get('librarycachedir'),
			'ArtworkCache',
		);
		
		$singleton = bless { root => $root }, $class;
		
		# Update root value if librarycachedir changes
		Slim::Utils::Prefs::preferences('server')->setChange( sub {
			$singleton->{root} = fast_catdir( $_[1], 'ArtworkCache' );
		}, 'librarycachedir' );
	}
	
	return $singleton;
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
	
	my $packed = pack( 'A3LS', $data->{content_type}, $data->{mtime}, length( $data->{original_path} ) )
	 	. $data->{original_path};
	
	# Prepend the packed header to the original data
	substr $$ref, 0, 0, $packed;
	
	my $dir;
	my $file = $self->path_to_key( $key, \$dir );
	
	mkpath( $dir, 0, DIR_MODE ) if !-d $dir;
	
	my $temp_file = $self->generate_temporary_filename( $dir, $file );
    my $store_file = defined($temp_file) ? $temp_file : $file;
	
	# Fast spew, adapted from File::Slurp::write, with unnecessary options removed
	{
		my $write_fh;
		unless (
			sysopen(
				$write_fh,	 $store_file,
				STORE_FLAGS, FILE_MODE
			)
		  )
		{
			die "write_file '$store_file' - sysopen: $!";
		}
		my $size_left = length($$ref);
		my $offset	  = 0;
		do {
			my $write_cnt = syswrite( $write_fh, $$ref, $size_left, $offset );
			unless ( defined $write_cnt ) {
				die "write_file '$store_file' - syswrite: $!";
			}
			$size_left -= $write_cnt;
			$offset += $write_cnt;
		} while ( $size_left > 0 );
	}
	
	if ( defined($temp_file) ) {		
		# Rename can fail in rare race conditions...try multiple times
		#
		for ( my $try = 0 ; $try < 3 ; $try++ ) {
			last if ( rename( $temp_file, $file ) );
		}
		if ( -f $temp_file ) {
			my $error = $!;
			unlink($temp_file);
			die "could not rename '$temp_file' to '$file': $error";
		}
	}
	
	# Remove the packed header
	substr $$ref, 0, length($packed), '';
}

sub get {
	my ( $self, $key ) = @_;
	
	my $file = $self->path_to_key($key);
	return undef unless defined $file && -f $file;
	
	# Fast slurp, adapted from File::Slurp::read, with unnecessary options removed
	my $buf = '';
	my $read_fh;
	unless ( sysopen( $read_fh, $file, FETCH_FLAGS ) ) {
		die "read_file '$file' - sysopen: $!";
	}
	my $size_left = -s $read_fh;
	while (1) {
		my $read_cnt = sysread( $read_fh, $buf, $size_left, length $buf );
		if ( defined $read_cnt ) {
			last if $read_cnt == 0;
			$size_left -= $read_cnt;
			last if $size_left <= 0;
		}
		else {
			die "read_file '$file' - sysread: $!";
		}
	}
	
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

# Return the same data as get(), but with a filehandle to the data.  This filehandle is pre-seeked
# past the cache metadata header, so callers should not call seek on this filehandle.
sub get_fh {
	my ( $self, $key ) = @_;
	
	my $file = $self->path_to_key($key);
	return undef unless defined $file && -f $file;
	
	my $read_fh;
	unless ( sysopen( $read_fh, $file, FETCH_FLAGS ) ) {
		die "read_file '$file' - sysopen: $!";
	}
	
	# unpack data and strip header from data as we go
	# This requires 2 reads, but does not use any extra memory and the 
	# returned filehandle can be streamed out directly to the client
	my $buf = '';
	if ( sysread( $read_fh, $buf, 9 ) != 9 ) {
		die "read_file '$file' - unable to read header";
	}
	
	my ($content_type, $mtime, $pathlen) = unpack( 'A3LS', $buf );
	
	my $original_path;
	if ( sysread( $read_fh, $original_path, $pathlen ) != $pathlen ) {
		die "read_file '$file' - unable to read header";
	}
	
	return {
		content_type  => $content_type,
		mtime         => $mtime,
		original_path => $original_path,
		data_fh       => $read_fh,
	};
}		

sub generate_temporary_filename {
	my ( $self, $dir, $file ) = @_;

	my $unique_id = Digest::MD5::md5_hex( $file . Time::HiRes::time() );
	
	return fast_catfile( $dir, $unique_id );
}

sub path_to_key {
	my ( $self, $key, $dir_ref ) = @_;
	
	my $filename = Digest::MD5::md5_hex($key);
	
	my @paths = (
		$self->{root},
		map { substr( $filename, $_, 1 ) } ( 0 .. DEPTH - 1 )
	);
	
	my $filepath;
	if ( defined $dir_ref && ref $dir_ref ) {
		my $dir = fast_catdir(@paths);
		$filepath = fast_catfile( $dir, $filename );
		$$dir_ref = $dir;
	}
	else {
		$filepath = fast_catfile( @paths, $filename );
	}
	
	return $filepath;
}

1;
