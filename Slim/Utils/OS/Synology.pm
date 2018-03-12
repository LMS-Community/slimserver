package Slim::Utils::OS::Synology;

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.
#
# This module written by Philippe Kehl <phkehl at gmx dot net>
#
# Synology DiskStation (DS) include a wide range of NAS devices based on
# several architectures (PPC, ARM, PPCe500v2, ARMv5, and maybe others). They
# all use a custom and minimal Linux system (Linux 2.6 based). There are (to my
# knowledge) three options to run Logitech Media Server on these devices:
#
# 1) flipflip's SlimServer on DiskStation (SSODS) provides a system
#    (libc, Perl, tools etc.) spcifically to run Logitech Media Server.
# 2) Synology recently added Perl to its standard system and provides an
#    add-on Logitech Media Server package (via the DSM Package Management).
# 3) "Optware", a package for feed for numerous add-on packages from the
#    NSLU2-Linux project, provides a Logitech Media Server package and its dependencies.
#
# This module is trying to provide customisations for all these options.

use strict;

use Config;
use File::Spec::Functions qw(:ALL);
use FindBin qw($Bin);

use base qw(Slim::Utils::OS::Linux);

use constant MAX_LOGSIZE => 1024*1024*1; # maximum log size: 1 MB


sub initDetails
{
	my $class = shift;

	$class->{osDetails} = $class->SUPER::initDetails();
	$class->{osDetails}->{osArch} ||= $Config{'archname'};

	$class->{osDetails}->{isDiskStation} = 1;

	# check how this Logitech Media Server is run on the DiskStation
	if (-f '/volume1/SSODS/etc/ssods/ssods.conf'
		&& "@INC" =~ m{/volume1/SSODS/lib/perl})
	{
		$class->{osDetails}->{isSSODS} = 1;
		$class->{osDetails}->{osName} .= ' (SSODS)';
	}
	elsif (-d '/opt/share/squeezecenter'
		&& "@INC" =~ m{/opt/lib/perl})
	{
		$class->{osDetails}->{isOptware} = 1;
		$class->{osDetails}->{osName} .= ' (NSLU2-Linux Optware)';
	}
	elsif (-d '/volume1/@appstore/SqueezeCenter'
		&& "@INC" =~ m{/usr/lib/perl})
	{
		$class->{osDetails}->{isSynology} = 1;
		$class->{osDetails}->{osName} .= ' (DSM Package Management)';
	}

	return $class->{osDetails};
}

sub localeDetails {
	my $lc_ctype = 'utf8';
	my $lc_time = 'C';

	return ($lc_ctype, $lc_time);
}


sub logRotate
{
	my $class   = shift;
	my $dir     = shift || Slim::Utils::OSDetect::dirsFor('log');

    # only keep small log files (1MB) because they are displayed
    # (if at all) in a web interface
    Slim::Utils::OS->logRotate($dir, MAX_LOGSIZE);
}


sub ignoredItems
{
	return (
            '@eaDir'       => 1,   # media indexer meta data
            '@spool'       => 1,   # mail/print/.. spool
            '@tmp'         => 1,   # system temporary files
            '@appstore'    => 1,   # Synology package manager
            '@database'    => 1,   # databases store
            '@optware'     => 1,   # NSLU2-Linux Optware system
            'upd@te'       => 1,   # firmware update temporary directory
            '#recycle'     => 1,
            # system paths in the fs root which will not contain any music
            'bin'          => '/',
            'config'       => '/',
            'dev'          => '/',
            'etc'          => '/',
            'etc.defaults' => '/',
            'home'         => '/',
            'initrd'       => '/',
            'lib'          => '/',
            'linuxrc'      => '/',
            'lost+found'   => 1,
            'mnt'          => '/',
            'opt'          => '/',
            'proc'         => '/',
            'root'         => '/',
            'run'         => '/',
            'sbin'         => '/',
            'sys'          => '/',
            'tmp'          => '/',
            'usr'          => '/',
            'var'          => '/',
            'var.defaults' => '/',
            # now only the data partition mount points /volume(|USB)[0-9]
            # should remain
           );
}

1;
