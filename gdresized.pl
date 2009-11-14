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
use constant ISWINDOWS    => ( $^O =~ /^m?s?win/i ) ? 1 : 0;
use constant DEBUG        => ( grep { /--debug/ } @ARGV ) ? 1 : 0;

# Copied from Slim::bootstrap to reduce memory overhead of unnecessary stuff
BEGIN {
	use Config;
	use File::Spec::Functions qw(catdir);
	use Slim::Utils::OSDetect;	# XXX would be nice to do without this
	
	my $libPath = $Bin;
	my @SlimINC = ();
	
	Slim::Utils::OSDetect::init();
	
	if (my $libs = Slim::Utils::OSDetect::dirsFor('libpath')) {
		# On Debian, RH and SUSE, our CPAN directory is located in the same dir as strings.txt
		$libPath = $libs;
	}

	# NB: The user may be on a platform who's perl reports a
	# different x86 version than we've supplied - but it may work
	# anyways.
	my $arch = $Config::Config{'archname'};
	   $arch =~ s/^i[3456]86-/i386-/;
	   $arch =~ s/gnu-//;
	
	# Some ARM platforms use different arch strings, just assume any arm*linux system
	# can run our binaries, this will fail for some people running invalid versions of Perl
	# but that's OK, they'd be broken anyway.
	if ( $arch =~ /^arm.*linux/ ) {
		$arch = 'arm-linux-gnueabi-thread-multi';
	}
	
	# Same thing with PPC
	if ( $arch =~ /^(?:ppc|powerpc).*linux/ ) {
		$arch = 'powerpc-linux-thread-multi';
	}

	my $perlmajorversion = $Config{'version'};
	   $perlmajorversion =~ s/\.\d+$//;

	@SlimINC = (
		catdir($libPath,'CPAN','arch',$perlmajorversion, $arch),
		catdir($libPath,'CPAN','arch',$perlmajorversion, $arch, 'auto'),
		catdir($libPath,'CPAN','arch',$Config{'version'}, $Config::Config{'archname'}),
		catdir($libPath,'CPAN','arch',$Config{'version'}, $Config::Config{'archname'}, 'auto'),
		catdir($libPath,'CPAN','arch',$perlmajorversion, $Config::Config{'archname'}),
		catdir($libPath,'CPAN','arch',$perlmajorversion, $Config::Config{'archname'}, 'auto'),
		catdir($libPath,'CPAN','arch',$Config::Config{'archname'}),
		catdir($libPath,'lib'), 
		catdir($libPath,'CPAN'), 
		$libPath,
	);

	# This works like 'use lib'
	# prepend our directories to @INC so we look there first.
	unshift @INC, @SlimINC;
};

use Slim::Utils::GDResizer;

our ($cacheroot, $faster, $debug);

while ($_ = shift @ARGV) {
	if ($_ eq '--cacheroot') {
		$cacheroot = shift @ARGV;
	} elsif ($_ eq '--faster') {
		$faster = 1;
	} elsif ($_ eq '--debug') {
		$debug = 1;
	} else {
		require Pod::Usage;
		Pod::Usage::pod2usage(1);
	}
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
	
	# get command
	my $buf;
	if (read (STDIN, $buf, 5) != 5) {
		if (eof(STDIN)) {
			exit 0;
		} else {
			die 'No command';
		}
	}	

	my ($c, $l) = unpack 'CL', $buf;
	
	$debug && warn("command data length $l");
	
	read(STDIN, $buf, $l) == $l or die 'Bad command';
	
	my ($file, $spec, $cachekey) = unpack 'Z*Z*Z*', $buf;
	$debug && warn("file=$file, spec=$spec, cachekey=$cachekey");
	
	my @spec = split(',', $spec);
	
	# do resize
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
		# For now, just die
		die "$@\n";
	}
	
	# send result
	$buf = 'K';		# K ==> 'OK'
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
