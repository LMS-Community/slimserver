package Slim::Utils::OS::OSX;

# Logitech Media Server Copyright 2001-2011 Logitech.
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

use constant GROWLINTERVAL => 60*60;

my $canFollowAlias;

sub name {
	return 'mac';
}

sub initDetails {
	my $class = shift;
	
	if ( !main::RESIZER ) {
		# Once for OS Version, then again for CPU Type.
		open(SYS, '/usr/sbin/system_profiler SPSoftwareDataType |') or return;

		while (<SYS>) {

			if (/System Version: (.+)/) {

				$class->{osDetails}->{'osName'} = $1;
				$class->{osDetails}->{'osName'} =~ s/ \(\w+?\)$//;
				last;
			}
		}

		close SYS;

		# CPU Type / Processor Name
		open(SYS, '/usr/sbin/system_profiler SPHardwareDataType |') or return;

		while (<SYS>) {

			if (/Intel/i) {

				# Determine if we are running as 32-bit or 64-bit
				my $bits = length( pack 'L!', 1 ) == 8 ? 64 : 32;
			
				$class->{osDetails}->{'osArch'} = 'x86';
			
				if ( $bits == 64 ) {
					$class->{osDetails}->{'osArch'} = 'x86_64';
				}
			
				last;

			} elsif (/PowerPC/i) {

				$class->{osDetails}->{'osArch'} = 'ppc';
			}
		}

		close SYS;
	}

	$class->{osDetails}->{'os'}  = 'Darwin';
	$class->{osDetails}->{'uid'} = getpwuid($>);

	# XXX - do we still need this? They're empty on my system, and created if needed in some other place anyway
	for my $dir (
		'Library/Application Support/Squeezebox',
		'Library/Application Support/Squeezebox/Plugins', 
		'Library/Application Support/Squeezebox/Graphics',
		'Library/Application Support/Squeezebox/html',
		'Library/Application Support/Squeezebox/IR',
		'Library/Logs/Squeezebox'
	) {

		eval 'mkpath("$ENV{\'HOME\'}/$dir");';
	}

	unshift @INC, $ENV{'HOME'} . "/Library/Application Support/Squeezebox";
	unshift @INC, "/Library/Application Support/Squeezebox";
	
	return $class->{osDetails};
}

sub initPrefs {
	my ($class, $prefs) = @_;
	
	$prefs->{libraryname} = `scutil --get ComputerName` || '';
	chomp($prefs->{libraryname});

	# Replace fancy apostraphe (’) with ASCII
	utf8::decode( $prefs->{libraryname} ) unless utf8::is_utf8($prefs->{libraryname});
	$prefs->{libraryname} =~ s/\x{2019}/'/;
		
	# we now have a binary preference pane - don't show the wizard
	$prefs->{wizardDone} = 1;
}

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
	
	$class->SUPER::initSearchPath();

	my @paths = ();

	push @paths, $ENV{'HOME'} ."/Library/iTunes/Scripts/iTunes-LAME.app/Contents/Resources/";
	push @paths, (split(/:/, $ENV{'PATH'}), qw(/usr/bin /usr/local/bin /usr/libexec /sw/bin /usr/sbin /opt/local/bin));
	
	Slim::Utils::Misc::addFindBinPaths(@paths);
}

=head2 dirsFor( $dir )

Return OS Specific directories.

Argument $dir is a string to indicate which of the Logitech Media Server directories we
need information for.

=cut

sub dirsFor {
	my ($class, $dir) = @_;

	my @dirs = $class->SUPER::dirsFor($dir);
	
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

		push @dirs, "$ENV{'HOME'}/Library/Application Support/Squeezebox/$dir";
		push @dirs, "/Library/Application Support/Squeezebox/$dir";
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
			
	} elsif ($dir =~ /^(?:music|videos|pictures)$/) {

		my $mediaDir;
		
		if ($dir eq 'music') {
			# DHG wants LMS to default to the full Music folder, not only iTunes
#			$mediaDir = catdir($ENV{'HOME'}, 'Music', 'iTunes');
#			if (!-d $mediaDir) {
				$mediaDir = catdir($ENV{'HOME'}, 'Music');
#			}
		}
		elsif ($dir eq 'videos') {
			$mediaDir = catdir($ENV{'HOME'}, 'Movies');
		}
		elsif ($dir eq 'pictures') {
			$mediaDir = catdir($ENV{'HOME'}, 'Pictures');
		}

		# bug 1361 expand music folder if it's an alias, or SC won't start
		if ( my $alias = $class->pathFromMacAlias($mediaDir) ) {
			$mediaDir = $alias;
		}

		push @dirs, $mediaDir;

	} elsif ($dir eq 'playlists') {
		
		push @dirs, catdir($class->dirsFor('music'), 'Playlists');

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

sub initUpdate {
	Slim::Utils::Timers::setTimer(undef, Time::HiRes::time() + 30, \&signalUpdateReady);
}

sub getUpdateParams {
	return {
		cb => \&signalUpdateReady
	};
}

sub signalUpdateReady {
			
	my $updater = Slim::Utils::Update::getUpdateInstaller();
	my $log     = Slim::Utils::Log::logger('server.update');
			
	unless ($updater && -e $updater) {	
		if ($updater) {
			$log->info("Updater file '$updater' not found!");
		}
		else {
			$log->info("No updater file found!");
		}
		return;
	}

	$log->debug("Notify '$updater' is ready to be installed");
		
	Slim::Utils::Timers::killTimers(undef, \&signalUpdateReady);
	Slim::Utils::Timers::killTimers(undef, \&_signalUpdateReady);
		
	# don't run the signal immediately, as the prefs are written delayed
	Slim::Utils::Timers::setTimer(undef, Time::HiRes::time() + 15, \&_signalUpdateReady);
}

# don't re-try Growl if it fails to be called
my $hasGrowl = 1;

sub _signalUpdateReady {
	my $log = Slim::Utils::Log::logger('server.update');
	my $osa = Slim::Utils::Misc::findbin('osascript');
	my ($script, $growlScript);
	
	my $osDetails = Slim::Utils::OSDetect::details();
	
	# try to use Growl on 10.5+
	if ($hasGrowl && $osDetails->{'osName'} =~ /X 10\.(\d)\./ && $1 > 4) {
		$growlScript = Slim::Utils::Misc::findbin('signalupdate.scpt');
	}
	
	$script ||= Slim::Utils::Misc::findbin('openprefs.scpt');
	
	if ($osa && $growlScript) {

		$growlScript = sprintf("%s '%s' %s &", $osa, $growlScript, Slim::Utils::Strings::string('PREFPANE_UPDATE_AVAILABLE'));

		$log->debug("Running notification:\n$growlScript");
		
		# script will return true if Growl is installed
		if (`$growlScript`) {
			# as Growl notifications are temporary only, retrigger them every hour
			Slim::Utils::Timers::setTimer(undef, Time::HiRes::time() + GROWLINTERVAL, \&_signalUpdateReady);
		}
		else {
			$growlScript = undef;
		}
	}
	
	if ($osa && $script && !$growlScript) {
		$script = sprintf("%s '%s' &", $osa, $script);
		
		$log->debug("Running notification:\n$script");
		system($script);

		$hasGrowl = 0;
	}
	
	if (!$osa || !$script) {
		$log->warn("AppleScript interpreter osascript or notification script not found!");
	}
}

sub canAutoUpdate { 1 }

sub installerExtension { 'pkg' }; 
sub installerOS { 'osx' }

sub restartServer {
	my $class  = shift;
	my $helper = Slim::Utils::Misc::findbin('restart-server.sh');

	system("'$helper' &") if $helper;
}


1;
