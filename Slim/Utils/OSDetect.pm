package Slim::Utils::OSDetect;

# $Id$

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use Config;
use Slim::Utils::Misc;

my $detectedOS = undef;
my %osDetails  = ();

sub OS {
	if (!$detectedOS) { init(); }
	return $detectedOS;
}

# Figures out where the preferences file should be on our platform, and loads it.
# also sets the global $detectedOS to 'unix' 'win'
sub init {
	if (!$detectedOS) {

		$::d_os && msg("Auto-detecting OS: $^O\n");

		if ($^O =~/darwin/i) {

			$detectedOS = 'mac';

			initDetailsForOSX();

		} elsif ($^O =~ /^m?s?win/i) {

			$detectedOS = 'win';

			initDetailsForWin32();

		} elsif ($^O =~ /linux/i) {

			$detectedOS = 'unix';

			initDetailsForLinux();

		} else {

			$detectedOS = 'unix';

			initDetailsForUnix();
		}

		$::d_os && msg("I think it's \"$detectedOS\".\n");

	} else {

		$::d_os && msg("OS detection skipped, using \"$detectedOS\".\n");
	}
}

sub details {
	return \%osDetails;
}

sub initDetailsForWin32 {

	%osDetails = (
		'os'     => 'Windows',

		'osName' => (Win32::GetOSName())[0],

		'osArch' => Win32::GetChipName(),

		'uid'    => Win32::LoginName(),

		'fsType' => (Win32::FsType())[0],
	);

	# Do a little munging for pretty names.
	$osDetails{'osName'} =~ s/Win/Windows /;
	$osDetails{'osName'} =~ s/\/.Net//;
	$osDetails{'osName'} =~ s/2003/Server 2003/;
}

sub initDetailsForOSX {

	open(SYS, '/usr/sbin/system_profiler SPSoftwareDataType |') or return;

	while (<SYS>) {

		if (/System Version: (.+)/) {

			$osDetails{'osName'} = $1;
			last;
		}
	}

	close SYS;

	$osDetails{'os'}     = 'Macintosh';
	$osDetails{'uid'}    = getpwuid($>);
	$osDetails{'osArch'} = $Config{'myarchname'};
}

sub initDetailsForLinux {

	$osDetails{'os'}     = 'Linux';

	if (-f '/etc/debian_version') {

		$osDetails{'osName'} = 'Debian';

	} elsif (-f '/etc/redhat_release') {

		$osDetails{'osName'} = 'RedHat';

	} else {

		$osDetails{'osName'} = 'Linux';
	}

	$osDetails{'uid'}    = getpwuid($>);
	$osDetails{'osArch'} = $Config{'myarchname'};
}

sub initDetailsForUnix {

	$osDetails{'os'}     = 'Unix';
	$osDetails{'osName'} = $Config{'osname'} || 'Unix';
	$osDetails{'uid'}    = getpwuid($>);
	$osDetails{'osArch'} = $Config{'myarchname'};
}

1;

__END__
