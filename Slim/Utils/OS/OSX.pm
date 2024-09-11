package Slim::Utils::OS::OSX;

# Logitech Media Server Copyright 2001-2024 Logitech.
# Lyrion Music Server Copyright 2024 Lyrion Community.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Utils::OS);

use Config;
use File::Path;
use File::Spec::Functions qw(:ALL);
use FindBin qw($Bin);
use POSIX qw(LC_CTYPE LC_TIME);

# the new menubar item comes as an application in something like "Lyrion Music Server.app/Contents/Resources/server"
use constant IS_MENUBAR_ITEM => $Bin =~ m|app/Contents/Resources/server| ? 1 : 0;

my $canFollowAlias;

sub name {
	return 'mac';
}

sub initDetails {
	my $class = shift;

	if ( !main::RESIZER ) {
		# Once for OS Version, then again for CPU Type.
		open(SYS, '/usr/sbin/system_profiler SPSoftwareDataType SPHardwareDataType 2>&1 |') or return;

		while (<SYS>) {

			if (/System Version: (.+)/) {

				$class->{osDetails}->{'osName'} ||= $1;
				$class->{osDetails}->{'osName'} =~ s/ \(\w+?\)$//;

			} elsif (/Intel/i) {

				$class->{osDetails}->{'osArch'} ||= 'x86_64';

			} elsif (/Chip.*(Apple .*)/) {

				$class->{osDetails}->{'osArch'} ||= 'arm64';

			}

			last if $class->{osDetails}->{'osName'} && $class->{osDetails}->{'osArch'};
		}

		close SYS;
	}

	if ( !$class->{osDetails}->{osArch} ) {
		my $uname = `uname -a`;

		if ($uname =~ /ARM64.*x86_64/i) {
			$class->{osDetails}->{osArch} = 'x86_64 (Rosetta)';
		}
		elsif ($uname =~ /RELEASE_X86_64/) {
			$class->{osDetails}->{osArch} = 'x86_64';
		}
		elsif ($uname =~ /RELEASE_ARM64/) {
			$class->{osDetails}->{osArch} = 'arm64';
		}
	}

	$class->{osDetails}->{'osArch'} ||= 'Unknown';
	$class->{osDetails}->{'os'}  = 'Darwin';
	$class->{osDetails}->{'uid'} = getpwuid($>);

	for my $dir (
		'Library/Application Support/Squeezebox',
		'Library/Application Support/Squeezebox/Plugins',
		'Library/Logs/Squeezebox'
	) {

		eval 'mkpath("$ENV{\'HOME\'}/$dir");';
	}

	unshift @INC, $ENV{'HOME'} . "/Library/Application Support/Squeezebox";

	return $class->{osDetails};
}

sub initPrefs {
	my ($class, $prefs) = @_;

	$prefs->{libraryname} = `scutil --get ComputerName` || '';
	chomp($prefs->{libraryname});

	# Replace fancy apostraphe (’) with ASCII
	utf8::decode( $prefs->{libraryname} ) unless utf8::is_utf8($prefs->{libraryname});
	$prefs->{libraryname} =~ s/\x{2019}/'/;
}

sub canDBHighMem { 1 }

sub canFollowAlias {
	return $canFollowAlias if defined $canFollowAlias;

	eval {
		require Mac::Files;
		require Mac::Resources;
		$canFollowAlias = 1;
	};

	if ( $@ ) {
		$canFollowAlias = 0;
	}
}

sub initSearchPath {
	my $class = shift;

	$class->SUPER::initSearchPath(@_);

	my @paths = ();

	push @paths, $ENV{'HOME'} ."/Library/iTunes/Scripts/iTunes-LAME.app/Contents/Resources/";
	push @paths, (split(/:/, $ENV{'PATH'}), qw(/usr/bin /usr/local/bin /usr/libexec /sw/bin /usr/sbin /opt/local/bin));

	Slim::Utils::Misc::addFindBinPaths(@paths);
}

=head2 dirsFor( $dir )

Return OS Specific directories.

Argument $dir is a string to indicate which of the Lyrion Music Server directories we
need information for.

=cut

sub dirsFor {
	my ($class, $dir) = @_;

	my @dirs = $class->SUPER::dirsFor($dir);

	# These are all at the top level.
	if ($dir =~ /^(?:strings|revision|convert|types|repositories)$/) {

		push @dirs, $Bin;

	} elsif ($dir =~ /^(?:Graphics|HTML|IR|Plugins|MySQL)$/) {

		push @dirs, "$ENV{'HOME'}/Library/Application Support/Squeezebox/$dir";
		push @dirs, catdir($Bin, $dir);

	} elsif ($dir eq 'log') {

		push @dirs, $::logdir || catdir($ENV{'HOME'}, '/Library/Logs/Squeezebox');

	} elsif ($dir eq 'cache') {

		push @dirs, $::cachedir || catdir($ENV{'HOME'}, '/Library/Caches/Squeezebox');

	} elsif ($dir eq 'oldprefs') {

		if ($::prefsfile && -r $::prefsfile) {

			push @dirs, $::prefsfile;
		}

		elsif (-r catdir($ENV{'HOME'}, 'Library', 'SlimDevices', 'slimserver.pref')) {

			push @dirs, catdir($ENV{'HOME'}, 'Library', 'SlimDevices', 'slimserver.pref');
		}

	} elsif ($dir eq 'prefs') {

		push @dirs, $::prefsdir || catdir($ENV{'HOME'}, '/Library/Application Support/Squeezebox');

	} elsif ($dir eq 'music') {

		my $mediaDir = catdir($ENV{'HOME'}, 'Music');

		# bug 1361 expand music folder if it's an alias, or SC won't start
		if ( my $alias = $class->pathFromMacAlias($mediaDir) ) {
			$mediaDir = $alias;
		}

		push @dirs, $mediaDir;

	} elsif ($dir eq 'playlists') {

		push @dirs, catdir(scalar $class->dirsFor('music'), 'Playlists');

	# We might get called from some helper script (update checker)
	} elsif ($dir eq 'libpath' && $Bin =~ m|Bin/darwin|) {

		push @dirs, "$Bin/../..";

	# we don't want these values to return a value
	} elsif ($dir =~ /^(?:libpath|mysql-language)$/) {

	} else {

		push @dirs, catdir($Bin, $dir);
	}

	return wantarray() ? @dirs : $dirs[0];
}

# Bug 8682, always decode on OSX
sub decodeExternalHelperPath {
	return Slim::Utils::Unicode::utf8decode_locale($_[1]);
}

sub localeDetails {
	# I believe this is correct from reading:
	# http://developer.apple.com/documentation/MacOSX/Conceptual/SystemOverview/FileSystem/chapter_8_section_6.html
	my $lc_ctype = 'utf8';

	# Now figure out what the locale is - something like en_US
	my $locale = 'en_US';
	if (open(LOCALE, "/usr/bin/defaults read 'Apple Global Domain' AppleLocale |")) {

		chomp($locale = <LOCALE>);
		close(LOCALE);
	}

	# On OSX - LC_TIME doesn't get updated even if you change the
	# language / formatting. Set it here, so we don't need to do a
	# system call for every clock second update.
	my $lc_time = POSIX::setlocale(LC_TIME, $locale);

	return ($lc_ctype, $lc_time);
}


# macOS doesn't sort correctly using LC_COLLATE - use a temporary database table to do the job...
sub sortFilename {
	my $class = shift;

	my $dbh = Slim::Schema->dbh();

	$dbh->do('DROP TABLE IF EXISTS sort_filenames');
	$dbh->do('CREATE TEMPORARY TABLE sort_filenames (name TEXT)');

	my $sth = $dbh->prepare_cached("INSERT INTO sort_filenames (name) VALUES (?)");
	foreach (@_) {
		$sth->execute($_);
	};

	my $collate = $class->sqlHelperClass()->collate();

	my $ret = $dbh->selectall_arrayref("SELECT name FROM sort_filenames ORDER BY name $collate");
	$dbh->do('DROP TABLE IF EXISTS sort_filenames');

	return map { $_->[0] } @$ret;
}


sub getSystemLanguage {
	my $class = shift;

	# Will return something like:
	# (en, ja, fr, de, es, it, nl, sv, nb, da, fi, pt, "zh-Hant", "zh-Hans", ko)
	# We want to use the first value. See:
	# http://gemma.apple.com/documentation/MacOSX/Conceptual/BPInternational/Articles/ChoosingLocalizations.html
	my $language = 'en';
	if (open(LANG, "/usr/bin/defaults read 'Apple Global Domain' AppleLanguages |")) {

		for (<LANG>) {
			if (/\b(\w\w)\b/) {
				$language = $1;
				last;
			}
		}

		close(LANG);
	}

	return $class->_parseLanguage($language);
}

sub ignoredItems {
	return (
		# Items we should ignore on a mac volume
		'Icon' => '/',
		'TheVolumeSettingsFolder' => 1,
		'TheFindByContentFolder' => 1,
		'Network Trash Folder' => 1,
		'Temporary Items' => 1,
		'.Trashes'  => 1,
		'.AppleDB'  => 1,
		'.AppleDouble' => 1,
		'.Metadata' => 1,
		'.DS_Store' => 1,
		# Dean: "Essentially hide anything you can't see in the finder or explorer"
		'automount' => 1,
		'cores'     => '/',
		'bin'       => '/',
		'dev'       => '/',
		'etc'       => '/',
		'home'      => '/',
		'net'       => '/',
		'Network'   => '/',
		'private'   => '/',
		'sbin'      => 1,
		'tmp'       => 1,
		'usr'       => 1,
		'var'       => '/',
		'opt'       => '/',
	);
}

=head2 pathFromMacAlias( $path )

Return the filepath for a given Mac Alias. Returns undef if $path is not an alias.

=cut

# Keep a cache of alias lookups to avoid double-lookup during scan
# INIT block is needed because this module is loaded before CPAN dir is setup
my %aliases;
INIT {
	require Tie::Cache::LRU;
	tie %aliases, 'Tie::Cache::LRU', 128;
}

sub pathFromMacAlias {
	my ($class, $fullpath) = @_;

	return unless $fullpath && canFollowAlias();

	my $path;

	$fullpath = Slim::Utils::Misc::pathFromFileURL($fullpath) unless $fullpath =~ m|^/|;

	if ( exists $aliases{$fullpath} ) {
		return $aliases{$fullpath};
	}

	if (-f $fullpath && -r _ && (my $rsc = Mac::Resources::FSpOpenResFile($fullpath, 0))) {

		if (my $alis = Mac::Resources::GetIndResource('alis', 1)) {

			$path = $aliases{$fullpath} = Mac::Files::ResolveAlias($alis);

			Mac::Resources::ReleaseResource($alis);
		}

		Mac::Resources::CloseResFile($rsc);
	}

	return $path;
}

sub getDefaultGateway {
	my $route = `route -n get default`;
	if ($route =~ /gateway:\s*(\d+\.\d+\.\d+\.\d+)/s ) {
		if ( Slim::Utils::Network::ip_is_private($1) ) {
			return $1;
		}
	}

	return;
}

my $updateCheckInitialized;
my $plistLabel = "com.slimdevices.updatecheck";

sub initUpdate { if (!IS_MENUBAR_ITEM) {
	return if $updateCheckInitialized;

	my $log = Slim::Utils::Log::logger('server.update');
	$log->error(IS_MENUBAR_ITEM ? 'menu item' : 'nope');

	return if IS_MENUBAR_ITEM;

	my $err = "Failed to install LaunchAgent for the update checker";

	my $launcherPlist = catfile($ENV{HOME}, 'Library', 'LaunchAgents', $plistLabel . '.plist');

	if ( open(UPDATE_CHECKER, ">$launcherPlist") ) {
		my $script = Slim::Utils::Misc::findbin('check-update.pl');
		my $logDir = Slim::Utils::Log::serverLogFile();
		my $interval = Slim::Utils::Prefs::preferences('server')->get('checkVersionInterval') || 86400;

		# don't nag too often...
		$interval = 6*3600 if $interval < 6*3600;

		require File::Basename;
		my $folder = File::Basename::dirname($script);

		print UPDATE_CHECKER qq(<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$plistLabel</string>
	<key>ProgramArguments</key>
	<array>
		<string>$script</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>WorkingDirectory</key>
	<string>$folder</string>
	<key>StandardOutPath</key>
	<string>$logDir</string>
	<key>StandardErrorPath</key>
	<string>$logDir</string>
	<key>StartInterval</key>
	<integer>$interval</integer>
</dict>
</plist>);

		close UPDATE_CHECKER;

		$err = `launchctl unload $launcherPlist; launchctl load $launcherPlist`;
	}

	if ($err) {
		$log->error($err);
	}
	else {
		$updateCheckInitialized = 1;
	}

	# disable the update checker in case the check is disabled by the user
	Slim::Utils::Prefs::preferences('server')->setChange( sub {
		`launchctl unload $plistLabel`;
		unlink($launcherPlist);
		$updateCheckInitialized = 0;
	}, 'checkVersion' );
} }

sub getUpdateParams {
	return {
		cb => sub { if (!IS_MENUBAR_ITEM) {
			# let's kick the update checker
			if ( my $err = `launchctl start $plistLabel` ) {
				Slim::Utils::Log::logger('server.update')->error($err);
			}
		} }
	};
}

sub canAutoUpdate { 1 }

sub installerExtension {
	my $updateFolder = $_[0]->dirsFor('updates');

	# remove installer from old installation
	Slim::Utils::Misc::deleteFiles($updateFolder, qr/^LogitechMediaServer.*\.pkg$/i);

	if (IS_MENUBAR_ITEM) {
		# remove pref pane installer
		Slim::Utils::Misc::deleteFiles($updateFolder, qr/^LyrionMusicServer.*\.pkg$/i);
		return 'dmg';
	};

	# remove menu bar item installer
	Slim::Utils::Misc::deleteFiles($updateFolder, qr/^LyrionMusicServer.*\.zip$/i);
	return 'pkg';
};

sub installerOS { IS_MENUBAR_ITEM ? 'macos' : 'osx' }

sub canRestartServer { 1 }

sub restartServer {
	my $class  = shift;
	my $helper = Slim::Utils::Misc::findbin('restart-server.sh');

	if ($helper) {
		system("'$helper' &");
		# XXX - the restart helper doesn't validate its success
		return 1;
	}

	return 0;
}

1;
