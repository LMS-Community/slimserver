#!/usr/bin/perl
#
# Stand-alone interface to ImageResizer
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
use constant ISWINDOWS    => ( $^O =~ /^m?s?win/i ) ? 1 : 0;
use constant DEBUG        => ( grep { /--debug/ } @ARGV ) ? 1 : 0;

BEGIN {
	use Slim::bootstrap ();
	Slim::bootstrap->loadModules( ['GD'], [] );
};

use Getopt::Long;

use Slim::Utils::ImageResizer;

my $help;
our ($file, $url, @spec, $cacheroot, $cachekey, $faster, $debug);

my $ok = GetOptions(
	'help|?'      => \$help,
	'cacheroot=s' => \$cacheroot,
	'faster'      => \$faster,
	'debug'       => \$debug,
);

if ( !$ok || $help ) {
	require Pod::Usage;
	Pod::Usage::pod2usage(1);
}

# Setup cache
my $cache;
if ( $cacheroot ) {
	require Cache::FileCache;
	
	$cache = Cache::FileCache->new( {
		namespace       => 'Artwork',
		cache_root      => $cacheroot,
		directory_umask => umask(),
	} );
}

binmode(STDIN);
binmode(STDOUT);

while (1) {
	
	# XXX get command
	my $buf;
	read (STDIN, $buf, 5) == 5 or	die 'No command';

	my ($c, $l) = unpack 'CL', $buf;
	
	$debug && warn("command data length $l");
	
	read(STDIN, $buf, $l) == $l or die 'Bad command';
	
	my ($file, $spec, $cachekey) = unpack 'Z*Z*Z*', $buf;
	$debug && warn("file=$file, spec=$spec, cachekey=$cachekey");
	
	@spec = split(',', $spec);
	
	# do resize
	eval {
		Slim::Utils::ImageResizer->gdresize(
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
	
	# XXX send result
	
	$buf = 'K';
	syswrite(STDOUT, $buf, 1);
	
}

exit 0;


__END__

=head1 NAME

gdresized.pl - Artwork resizer daemon

=head1 SYNOPSIS

Resize normal image file or an audio file's embedded tags:

Options:

  --faster                 Use ugly but fast copyResized function
  --cacheroot [dir]        Cache resulting image in a FileCache called
                           'Artwork' located in dir

=cut
