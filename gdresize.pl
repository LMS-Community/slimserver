#!/usr/bin/perl
#
# Stand-alone interface to ImageResizer
#
# TODO:
# Better error handling
#

use strict;

use constant RESIZER      => 1;
use constant SLIM_SERVICE => 0;
use constant PERFMON      => 0;
use constant SCANNER      => 0;
use constant ISWINDOWS    => ( $^O =~ /^m?s?win/i ) ? 1 : 0;
use constant DEBUG        => ( grep { /--debug/ } @ARGV ) ? 1 : 0;

BEGIN {
	use Slim::bootstrap ();
	Slim::bootstrap->loadModules( ['GD'], [] );
};

use Getopt::Long;

use Slim::Utils::ImageResizer;

my $help;
our ($file, @spec, $cacheroot, $cachekey, $faster, $debug);

my $ok = GetOptions(
	'help|?'      => \$help,
	'file=s'      => \$file,
	'spec=s'      => \@spec,
	'cacheroot=s' => \$cacheroot,
	'cachekey=s'  => \$cachekey,
	'faster'      => \$faster,
	'debug'       => \$debug,
);

if ( !$ok || $help || !$file || !@spec ) {
	require Pod::Usage;
	Pod::Usage::pod2usage(0);
}

# Setup cache
my $cache;
if ( $cacheroot && $cachekey ) {
	require Cache::FileCache;
	
	$cache = Cache::FileCache->new( {
		namespace       => 'Artwork',
		cache_root      => $cacheroot,
		directory_umask => umask(),
	} );
}

if ( @spec > 1 ) {
	# Resize in series
	
	# Construct spec hashes
	my $specs = [];
	for my $s ( @spec ) {
		my ($width, $height, $mode) = $s =~ /^([^x]+)x([^_]+)_(\w)$/;
		
		if ( !$width || !$height || !$mode ) {
			die "Invalid spec: $s\n";
		}
		
		push @{$specs}, {
			width  => $width,
			height => $height,
			mode   => $mode,
		};
	}
		
	my $series = eval {
		Slim::Utils::ImageResizer->resizeSeries(
			file   => $file,
			debug  => $debug,
			faster => $faster,
			series => $specs,
		);
	};
	
	if ( $@ ) {
		die "$@\n";
	}
	
	if ( $cacheroot && $cachekey ) {
		for my $s ( @{$series} ) {
			my $width  = $s->[2];
			my $height = $s->[3];
			my $mode   = $s->[4];
			
			my $ct = 'image/' . $s->[1];
			$ct =~ s/jpg/jpeg/;
		
			my $key = $cachekey;
			$key .= "${width}x${height}_${mode}";
		
			_cache( $key, $s->[0], $ct );
		}
	}
}
else {
	my ($width, $height, $mode) = $spec[0] =~ /^([^x]+)x([^_]+)_(\w)$/;
	
	if ( !$width || !$height || !$mode ) {
		die "Invalid spec: $spec[0]\n";
	}
	
	my ($ref, $format) = eval {
		Slim::Utils::ImageResizer->resize(
			file   => $file,
			debug  => $debug,
			faster => $faster,
			width  => $width,
			height => $height,
			mode   => $mode,
		);
	};
	
	if ( $@ ) {
		die "$@\n";
	}
	
	if ( $cacheroot && $cachekey ) {
		my $ct = 'image/' . $format;
		$ct =~ s/jpg/jpeg/;
		
		$cachekey .= $spec[0];
		
		_cache( $cachekey, $ref, $ct );
	}
}

sub _cache {
	my ( $key, $imgref, $ct ) = @_;
	
	my $cached = {
		orig        => $file,
		mtime       => (stat $file)[9],
		size        => length($$imgref),
		body        => $imgref,
		contentType => $ct,
	};

	$cache->set( $key, $cached, $Cache::Cache::EXPIRES_NEVER );
	
	$debug && warn "Cached $key (" . $cached->{size} . " bytes)\n";
}

__END__

=head1 NAME

gdresize.pl - Standalone artwork resizer

=head1 SYNOPSIS

Resize normal image file or an audio file's embedded tags:

Options:

  --file [ /path/to/image.jpg | /path/to/image.mp3 ]
    Supported file types:
      Images: jpg, jpeg, gif, png
      Audio:  see Audio::Scan documentation

  --spec <width>x<height>_<mode> ...
    Mode is one of:
	  m: max         (default)
	  p: pad         (same as max)
	  s: stretch
	  S: squash
	  f: fitstretch
	  F: fitsquash
	  c: crop
	  o: original
	
	Multiple spec arguments may be specified to resize in series.

  --faster                 Use ugly but fast copyResized function
  --cacheroot [dir]        Cache resulting image in a FileCache called
                           'Artwork' located in dir
  --cachekey [key]         Use this key prefix for the cache data.
                           Spec value will be appended.

=cut
