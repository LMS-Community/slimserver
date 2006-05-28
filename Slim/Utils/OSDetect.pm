package Slim::Utils::OSDetect;

# $Id$

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use Config;
use File::Spec::Functions qw(:ALL);
use FindBin qw($Bin);

BEGIN {

	if ($^O =~ /Win32/) {
		require Win32;
	}
}

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

		$::d_os && Slim::Utils::Misc::msg("Auto-detecting OS: $^O\n");

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

		$::d_os && Slim::Utils::Misc::msg("I think it's \"$detectedOS\".\n");

	} else {

		$::d_os && Slim::Utils::Misc::msg("OS detection skipped, using \"$detectedOS\".\n");
	}
}

# Return OS Specific directories.
sub dirsFor {
	my $dir     = shift;

	my @dirs    = ();
	my $OS      = OS();
	my $details = details();

	if ($OS eq 'mac') {

		if ($dir =~ /^(?:Graphics|HTML|IR|Plugins|MySQL)$/) {

			# For some reason the dir is lowercase on OS X.
			if ($dir eq 'HTML') {
				$dir = lc($dir);
			}

			push @dirs, $ENV{'HOME'} . "/Library/SlimDevices/$dir";
			push @dirs, "/Library/SlimDevices/$dir";
			push @dirs, catdir($Bin, $dir);

		} else {

			push @dirs, catdir($Bin, $dir);
		}

		# These are all at the top level.
		if ($dir =~ /^(?:strings|convert|types)$/) {

			push @dirs, $Bin;
		}

	# Debian specific paths.
	} elsif (isDebian()) {

		if ($dir =~ /^(?:Plugins|Firmware|Graphics|HTML|IR|MySQL|SQL|lib|Bin)$/) {

			push @dirs, "/usr/share/slimserver/$dir";

		} elsif ($dir eq 'strings') {

			push @dirs, "/usr/share/slimserver";

		} elsif ($dir =~ /^(?:types|convert|pref)$/) {

			push @dirs, "/etc/slimserver";

		} elsif ($dir eq 'log') {

			push @dirs, "/var/log/slimserver";

		} elsif ($dir eq 'cache') {

			push @dirs, "/var/cache/slimserver";

		} elsif ($dir eq 'MySQL') {

			# Do nothing - use the depended upon MySQL install.

		} else {

			Slim::Utils::Misc::errorMsg("dirsFor: Didn't find a match request: [$dir]\n");
		}

	} else {

		# Everyone else - Windows, and *nix.
		if ($dir =~ /^(?:strings|convert|types)$/) {

			push @dirs, $Bin;

		} else {

			push @dirs, catdir($Bin, $dir);
		}
	}

	return wantarray() ? @dirs : $dirs[0];
}

sub details {
	return \%osDetails;
}

sub isDebian {

	# Initialize
	my $OS      = OS();
	my $details = details();

	if ($details->{'osName'} eq 'Debian' && -d '/usr/share/slimserver/Firmware') {
		return 1;
	}

	return 0;
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
