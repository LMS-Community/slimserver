package Slim::Utils::OSDetect;

# $Id$

# SqueezeCenter Copyright (c) 2001-2007 Logitech.
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
		require Win32::FileSecurity;
		require Win32::TieRegistry;
	}
}

my $detectedOS = undef;
my %osDetails  = ();

=head1 METHODS

=head2 OS( )

returns a string to indicate the detected operating system currently running SqueezeCenter.

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

Argument $dir is a string to indicate which of the SqueezeCenter directories we
need information for.

=cut

sub dirsFor {
	my $dir     = shift;

	my @dirs    = ();
	my $OS      = OS();
	my $details = details();

	if ($dir eq "Plugins") {
		push @dirs, catdir($Bin, 'Slim', 'Plugin');
	}

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

			push @dirs, "$ENV{'HOME'}/Library/Application Support/SqueezeCenter/$dir";
			push @dirs, "/Library/Application Support/SqueezeCenter/$dir";
			push @dirs, "$ENV{'HOME'}/Library/SlimDevices/$dir";
			push @dirs, "/Library/SlimDevices/$dir";
			push @dirs, catdir($Bin, $dir);

		} elsif ($dir eq 'log') {

			# If SqueezeCenter is installed systemwide.
			if (-d "/Library/Application Support/SqueezeCenter") {

				mkpath("/Library/Logs/SqueezeCenter");

			} else {

				mkpath("$ENV{'HOME'}/Library/Logs/SqueezeCenter");
				
			}

			if (-d "/Library/Application Support/SqueezeCenter") {

				push @dirs, "/Library/Logs/SqueezeCenter";

			} elsif (-d "$ENV{'HOME'}/Library/Logs/SqueezeCenter") {

				push @dirs, "$ENV{'HOME'}/Library/Logs/SqueezeCenter";
				
			}

		} elsif ($dir eq 'cache') {

			push @dirs, catdir($ENV{'HOME'}, '/Library/Caches/SqueezeCenter');

		} elsif ($dir eq 'prefs') {

			push @dirs, catdir($ENV{'HOME'}, '/Library/Application Support/SqueezeCenter');

		} else {

			push @dirs, catdir($Bin, $dir);
		}

	# Debian specific paths.
	} elsif (isDebian()) {

		if ($dir =~ /^(?:Firmware|Graphics|HTML|IR|MySQL|SQL|lib|Bin)$/) {

			push @dirs, "/usr/share/slimserver/$dir";

		} elsif ($dir eq 'Plugins') {
			
			push @dirs, "/usr/share/perl5/Slim/Plugin", "/usr/share/slimserver/Plugins";
		
		} elsif ($dir eq 'strings' || $dir eq 'revision') {

			push @dirs, "/usr/share/slimserver";

		} elsif ($dir =~ /^(?:types|convert|prefs)$/) {

			push @dirs, "/etc/slimserver";

		} elsif ($dir eq 'log') {

			push @dirs, "/var/log/slimserver";

		} elsif ($dir eq 'cache') {

			push @dirs, "/var/cache/slimserver";

		} elsif ($dir eq 'MySQL') {

			# Do nothing - use the depended upon MySQL install.

		} else {

			warn "dirsFor: Didn't find a match request: [$dir]\n";
		}

	# Red Hat/Fedora/SUSE RPM specific paths.
	} elsif (isRHorSUSE()) {

		if ($dir =~ /^(?:Firmware|Graphics|HTML|IR|MySQL|SQL|lib|Bin)$/) {

			push @dirs, "/usr/share/squeezecenter/$dir";

		} elsif ($dir eq 'Plugins') {
			
			use Config;
			push @dirs, "/usr/share/squeezecenter/Plugins";
			push @dirs, "/usr/lib/perl5/vendor_perl/Slim/Plugin";
		
		} elsif ($dir eq 'strings' || $dir eq 'revision') {

			push @dirs, "/usr/share/squeezecenter";

		} elsif ($dir =~ /^(?:types|convert)$/) {

			push @dirs, "/etc/squeezecenter";

		} elsif ($dir eq 'prefs') {

			push @dirs, "/var/lib/squeezecenter/prefs";

		} elsif ($dir eq 'log') {

			push @dirs, "/var/log/squeezecenter";

		} elsif ($dir eq 'cache') {

			push @dirs, "/var/lib/squeezecenter/cache";

		} elsif ($dir eq 'MySQL') {

			# Do nothing - use the depended upon MySQL install.

		} else {

			warn "dirsFor: Didn't find a match request: [$dir]\n";
		}

	# all Windows specific stuff
	} elsif ($OS eq 'win') {

		$Win32::TieRegistry::Registry->Delimiter('/');

		if ($dir =~ /^(?:strings|revision|convert|types)$/) {

			push @dirs, $Bin;

		} elsif ($dir eq 'log') {

			push @dirs, winWritablePath('Logs');

		} elsif ($dir eq 'cache') {

			push @dirs, winWritablePath('Cache');

		} elsif ($dir eq 'prefs') {

			push @dirs, winWritablePath('prefs');

		} else {

			push @dirs, catdir($Bin, $dir);
		}

	} else {

		# Everyone else - *nix.
		if ($dir =~ /^(?:strings|revision|convert|types)$/) {

			push @dirs, $Bin;

		} elsif ($dir eq 'log') {

			push @dirs, catdir($Bin, 'Logs');

		} elsif ($dir eq 'cache') {

			push @dirs, catdir($Bin, 'Cache');

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

	if ($details->{'osName'} eq 'Debian' && $0 =~ m{^/usr/sbin/slimserver} ) {
		return 1;
	}

	return 0;
}

sub isRHorSUSE {

	# Initialize
	my $OS      = OS();
	my $details = details();

	if (($details->{'osName'} eq 'Red Hat' || $details->{'osName'} eq 'SUSE') && -d '/usr/share/squeezecenter/Firmware') {
		return 1;
	}

	return 0;
}

sub isVista {

	# Initialize
	my $OS      = OS();
	my $details = details();

	return ($OS eq 'win' && $details->{'osName'} =~ /Vista/) ? 1 : 0;
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

	for my $dir (
		'Library/Application Support/SqueezeCenter',
		'Library/Application Support/SqueezeCenter/Plugins', 
		'Library/Application Support/SqueezeCenter/Graphics',
		'Library/Application Support/SqueezeCenter/html',
		'Library/Application Support/SqueezeCenter/IR',
		'Library/SlimDevices/bin',
		'Library/Logs/SqueezeCenter'
	) {

		eval 'mkpath("$ENV{\'HOME\'}/$dir");';
	}

	unshift @INC, $ENV{'HOME'} . "/Library/SqueezeCenter";
	unshift @INC, "/Library/SlimDevices/";
}

sub initDetailsForLinux {

	$osDetails{'os'} = 'Linux';

	if (-f '/etc/debian_version') {

		$osDetails{'osName'} = 'Debian';

	} elsif (-f '/etc/redhat_release' || -f '/etc/redhat-release') {

		$osDetails{'osName'} = 'Red Hat';

	} elsif (-f '/etc/SuSE-release') {

		$osDetails{'osName'} = 'SUSE';

	} else {

		$osDetails{'osName'} = 'Linux';
	}

	$osDetails{'uid'}    = getpwuid($>);
	$osDetails{'osArch'} = $Config{'myarchname'};

	# package specific addition to @INC to cater for plugin locations
	if (isDebian()) {

		unshift @INC, '/usr/share/slimserver';
	}
}

sub initDetailsForUnix {

	$osDetails{'os'}     = 'Unix';
	$osDetails{'osName'} = $Config{'osname'} || 'Unix';
	$osDetails{'uid'}    = getpwuid($>);
	$osDetails{'osArch'} = $Config{'myarchname'};
}


# Return a path which is expected to be writable by all users on Windows without virtualisation on Vista
# this should mean that the server always sees consistent versions of files under this path

sub winWritablePath {
	my $folder = shift;
	my ($root, $path);

	# use the "Common Application Data" folder to store SqueezeCenter configuration etc.
	# c:\documents and settings\all users\application data - on Windows 2000/XP
	# c:\ProgramData - on Vista
	my $swKey = $Win32::TieRegistry::Registry->Open(
		'LMachine/Software/Microsoft/Windows/CurrentVersion/Explorer/Shell Folders/', 
		{ 
			Access => Win32::TieRegistry::KEY_READ(), 
			Delimiter =>'/' 
		}
	);

	if (defined $swKey) {
		$root = catdir($swKey->{'Common AppData'}, 'SqueezeCenter');
	}
	else {
		$root = $Bin;
	}

	$path = catdir($root, $folder);

	return $path if -d $path;

	if (! -d $root) {
		mkdir $root;
	}

	mkdir $path;

	return $path;
}

# legacy call: this used to do what winWritablePath() does now
# keep it for backwards compatibility
sub vistaWritablePath {
	my $folder = shift;
	Slim::Utils::Log::logger('os.paths')->warn('Slim::Utils::OSDetect::vistaWritablePath() is a legacy call - please use winWritablePath() instead.');
	return winWritablePath($folder);
}

1;

__END__
