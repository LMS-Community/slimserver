package Slim::Utils::OSDetect;

# $Id$

# SlimServer Copyright (c) 2001-2006 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

=head1 NAME

Slim::Utils::OSDetect

=head1 DESCRIPTION

L<Slim::Utils::OSDetect> handles Operating System Specific details.

=head1 SYNOPSIS

	for my $baseDir (Slim::Utils::OSDetect::dirsFor('types')) {

		push @typesFiles, catdir($baseDir, 'types.conf');
		push @typesFiles, catdir($baseDir, 'custom-types.conf');
	}
	
	if (Slim::Utils::OSDetect::OS() eq 'win') {

=cut

use strict;
use Config;
use File::Path;
use File::Spec::Functions qw(:ALL);
use FindBin qw($Bin);

BEGIN {

	if ($^O =~ /Win32/) {
		require Win32;
	}
}

my $detectedOS = undef;
my %osDetails  = ();

=head1 METHODS

=head2 OS( )

returns a string to indicate the detected operating system currently running slimserver.

=cut

sub OS {
	if (!$detectedOS) { init(); }
	return $detectedOS;
}

=head2 init( $newBin)

 Figures out where the preferences file should be on our platform, and loads it.
 also sets the global $detectedOS to 'unix' 'win', or 'mac'

=cut

sub init {
	my $newBin = shift;

	# Allow the caller to pass in a new base dir (for test cases);
	if (defined $newBin && -d $newBin) {
		$Bin = $newBin;
	}

	if ($detectedOS) {
		return;
	}

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
}

=head2 dirsFor( $dir )

Return OS Specific directories.

Argument $dir is a string to indicate which of the slimserver directories we
need information for.

=cut

sub dirsFor {
	my $dir     = shift;

	my @dirs    = ();
	my $OS      = OS();
	my $details = details();

	if ($OS eq 'mac') {

		# These are all at the top level.
		if ($dir =~ /^(?:strings|revision|convert|types)$/) {

			push @dirs, $Bin;

		} elsif ($dir =~ /^(?:Graphics|HTML|IR|Plugins|MySQL)$/) {

			# For some reason the dir is lowercase on OS X.
			# FRED: it may have been eons ago but today it is HTML; most of
			# the time anyway OS X is not case sensitive so it does not really
			# matter...
			#if ($dir eq 'HTML') {
			#	$dir = lc($dir);
			#}

			push @dirs, "$ENV{'HOME'}/Library/SlimDevices/$dir";
			push @dirs, "/Library/SlimDevices/$dir";
			push @dirs, catdir($Bin, $dir);

		} elsif ($dir eq 'log') {

			# If SlimServer is installed systemwide.
			if (-d "/Library/SlimDevices") {

				mkpath("/Library/Logs/SlimServer");

			} else {

				mkpath("$ENV{'HOME'}/Library/Logs/SlimServer");
			}

			if (-d "/Library/SlimDevices") {

				push @dirs, "/Library/Logs/SlimServer";

			} elsif (-d "$ENV{'HOME'}/Library/Logs/SlimServer") {

				push @dirs, "$ENV{'HOME'}/Library/Logs/SlimServer";
			}

		} else {

			push @dirs, catdir($Bin, $dir);
		}

	# Debian specific paths.
	} elsif (isDebian()) {

		if ($dir =~ /^(?:Plugins|Firmware|Graphics|HTML|IR|MySQL|SQL|lib|Bin)$/) {

			push @dirs, "/usr/share/slimserver/$dir";

		} elsif ($dir eq 'strings' || $dir eq 'revision') {

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

	# RedHat/Fedora specific paths.
	} elsif (isRHELorFC()) {

		if ($dir =~ /^(?:Plugins|Firmware|Graphics|HTML|IR|MySQL|SQL|lib|Bin)$/) {

			push @dirs, "/usr/share/slimserver/$dir";

		} elsif ($dir eq 'strings' || $dir eq 'revision') {

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
		if ($dir =~ /^(?:strings|revision|convert|types)$/) {

			push @dirs, $Bin;

		} elsif ($dir eq 'log') {

			push @dirs, catdir($Bin, 'Logs');

		} else {

			push @dirs, catdir($Bin, $dir);
		}
	}

	return wantarray() ? @dirs : $dirs[0];
}

sub details {
	return \%osDetails;
}

=head2 isDebian( )

 The Debian package has some specific differences for file locations.
 This routine needs no args, and returns 1 if Debian distro is detected, with
 a clear sign that the .deb package has been installed, 0 if not.

=cut

sub isDebian {

	# Initialize
	my $OS      = OS();
	my $details = details();

	if ($details->{'osName'} eq 'Debian' && -d '/usr/share/slimserver/Firmware') {
		return 1;
	}

	return 0;
}

sub isRHELorFC {

	# Initialize
	my $OS      = OS();
	my $details = details();

	if (($details->{'osName'} eq 'Fedora Core' || $details->{'osName'} eq 'RedHat') && -d '/usr/share/slimserver/Firmware') {
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

	# Once for OS Version, then again for CPU Type.
	open(SYS, '/usr/sbin/system_profiler SPSoftwareDataType |') or return;

	while (<SYS>) {

		if (/System Version: (.+)/) {

			$osDetails{'osName'} = $1;
			last;
		}
	}

	close SYS;

	# CPU Type / Processor Name
	open(SYS, '/usr/sbin/system_profiler SPHardwareDataType |') or return;

	while (<SYS>) {

		if (/Intel/i) {

			$osDetails{'osArch'} = 'x86';
			last;

		} elsif (/PowerPC/i) {

			$osDetails{'osArch'} = 'ppc';
		}
	}

	close SYS;

	$osDetails{'os'}  = 'Darwin';
	$osDetails{'uid'} = getpwuid($>);

	for my $dir (qw(
		Library/SlimDevices/Plugins Library/SlimDevices/Graphics Library/SlimDevices/html
		Library/SlimDevices/IR Library/SlimDevices/bin Library/Logs/SlimServer
	)) {

		mkpath("$ENV{'HOME'}/$dir");
	}

	unshift @INC, $ENV{'HOME'} . "/Library/SlimDevices";
	unshift @INC, "/Library/SlimDevices/";
}

sub initDetailsForLinux {

	$osDetails{'os'} = 'Linux';

	if (-f '/etc/debian_version') {

		$osDetails{'osName'} = 'Debian';

	} elsif (-f '/etc/redhat_release' || -f '/etc/redhat-release') {

		$osDetails{'osName'} = 'RedHat';

	} elsif (-f '/etc/fedora-release') {

		$osDetails{'osName'} = 'Fedora Core';

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
