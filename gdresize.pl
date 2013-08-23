#!/usr/bin/perl
#
# Stand-alone interface to GDResizer
#
# TODO:
# Better error handling
#

use strict;
use FindBin qw($Bin);
use lib $Bin;

use constant RESIZER      => 1;
use constant SLIM_SERVICE => 0;
use constant PERFMON      => 0;
use constant SCANNER      => 0;
use constant WEBUI        => 0;
use constant ISWINDOWS    => ( $^O =~ /^m?s?win/i ) ? 1 : 0;
use constant DEBUG        => ( grep { /--debug/ } @ARGV ) ? 1 : 0;
use constant LOCALFILE    => 0;

BEGIN {
	use Slim::bootstrap ();
	Slim::bootstrap->loadModules( ['Image::Scale'], [] );
};

use Getopt::Long;

use Slim::Utils::GDResizer;

my $help;
our ($file, $url, @spec, $cacheroot, $cachekey, $faster, $debug);

my $ok = GetOptions(
	'help|?'      => \$help,
	'file=s'      => \$file,
	'url=s'       => \$url,
	'spec=s'      => \@spec,
	'cacheroot=s' => \$cacheroot,
	'cachekey=s'  => \$cachekey,
	'faster'      => \$faster,
	'debug'       => \$debug,
);

if ( !$ok || $help || ( !$file && !$url ) || !@spec ) {
	require Pod::Usage;
	Pod::Usage::pod2usage(1);
}

# Download URL to a temp file
my $fh;
if ( $url ) {
	require File::Temp;
	require LWP::UserAgent;
	
	$fh = File::Temp->new();
	$file = $fh->filename;
	
	my $ua = LWP::UserAgent->new( timeout => 5 );
	
	$debug && warn "Downloading URL to $file\n";
	
	my $res = $ua->get( $url, ':content_file' => $file );
	
	if ( !$res->is_success ) {
		die "Unable to download $url: " . $res->status_line . "\n";
	}
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

eval {
	Slim::Utils::GDResizer->gdresize(
		file     => $file,
		debug    => $debug,
		faster   => $faster,
		cache    => $cache,
		cachekey => $cachekey,
		spec     => \@spec,
	);
};

if ( $@ ) {
	die "$@\n";
}

exit 0;


__END__

=head1 NAME

gdresize.pl - Standalone artwork resizer

=head1 SYNOPSIS

Resize normal image file or an audio file's embedded tags:

Options:

  --file [ /path/to/image.jpg | /path/to/image.mp3 ]
    Supported file types:
      Images: jpg, jpeg, gif, png, bmp
      Audio:  see Audio::Scan documentation

  --url http://...

  --spec <width>x<height>_<mode>[.ext] ...
    Mode is one of:
	  m: max         (default)
	  p: pad         (same as max)
	  o: original
	
	Multiple spec arguments may be specified to resize in series.

  --cacheroot [dir]        Cache resulting image in a FileCache called
                           'Artwork' located in dir
  --cachekey [key]         Use this key for the cached data.
                           Note: spec value will be appended to the cachekey
                           if multiple spec values were supplied.

=cut
