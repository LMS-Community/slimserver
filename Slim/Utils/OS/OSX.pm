package Slim::Utils::OS::OSX;

# SqueezeCenter Copyright 2001-2009 Logitech.
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

my $canFollowAlias;

sub name {
	return 'mac';
}

sub initDetails {
	my $class = shift;

	eval {
		require Mac::Files;
		require Mac::Resources;
		$canFollowAlias = 1;
	};
	
	# Once for OS Version, then again for CPU Type.
	open(SYS, '/usr/sbin/system_profiler SPSoftwareDataType |') or return;

	while (<SYS>) {

		if (/System Version: (.+)/) {

			$class->{osDetails}->{'osName'} = $1;
			last;
		}
	}

	close SYS;

	# CPU Type / Processor Name
	open(SYS, '/usr/sbin/system_profiler SPHardwareDataType |') or return;

	while (<SYS>) {

		if (/Intel/i) {

			$class->{osDetails}->{'osArch'} = 'x86';
			last;

		} elsif (/PowerPC/i) {

			$class->{osDetails}->{'osArch'} = 'ppc';
		}
	}

	close SYS;

	$class->{osDetails}->{'os'}  = 'Darwin';
	$class->{osDetails}->{'uid'} = getpwuid($>);

	for my $dir (
		'Library/Application Support/SqueezeCenter',
		'Library/Application Support/SqueezeCenter/Plugins', 
		'Library/Application Support/SqueezeCenter/Graphics',
		'Library/Application Support/SqueezeCenter/html',
		'Library/Application Support/SqueezeCenter/IR',
		'Library/Logs/SqueezeCenter'
	) {

		eval 'mkpath("$ENV{\'HOME\'}/$dir");';
	}

	unshift @INC, $ENV{'HOME'} . "/Library/Application Support/SqueezeCenter";
	unshift @INC, "/Library/Application Support/SqueezeCenter";
	
	return $class->{osDetails};
}

sub canFollowAlias { $canFollowAlias };

sub initSearchPath {
	my $class = shift;
	
	$class->SUPER::initSearchPath();

	my @paths = ();

	push @paths, $ENV{'HOME'} ."/Library/iTunes/Scripts/iTunes-LAME.app/Contents/Resources/";
	push @paths, (split(/:/, $ENV{'PATH'}), qw(/usr/bin /usr/local/bin /usr/libexec /sw/bin /usr/sbin));
	
	Slim::Utils::Misc::addFindBinPaths(@paths);
}

=head2 dirsFor( $dir )

Return OS Specific directories.

Argument $dir is a string to indicate which of the SqueezeCenter directories we
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

		push @dirs, "$ENV{'HOME'}/Library/Application Support/SqueezeCenter/$dir";
		push @dirs, "/Library/Application Support/SqueezeCenter/$dir";
		push @dirs, catdir($Bin, $dir);

	} elsif ($dir eq 'log') {

		push @dirs, $::logdir || catdir($ENV{'HOME'}, '/Library/Logs/SqueezeCenter');

	} elsif ($dir eq 'cache') {

		push @dirs, $::cachedir || catdir($ENV{'HOME'}, '/Library/Caches/SqueezeCenter');

	} elsif ($dir eq 'oldprefs') {

		if ($::prefsfile && -r $::prefsfile) {

			push @dirs, $::prefsfile;
		} 
		
		elsif (-r catdir($ENV{'HOME'}, 'Library', 'SlimDevices', 'slimserver.pref')) {

			push @dirs, catdir($ENV{'HOME'}, 'Library', 'SlimDevices', 'slimserver.pref');
		}

	} elsif ($dir eq 'prefs') {

		push @dirs, $::prefsdir || catdir($ENV{'HOME'}, '/Library/Application Support/SqueezeCenter');
			
	} elsif ($dir eq 'music') {

		my $musicDir = catdir($ENV{'HOME'}, 'Music');

		# bug 1361 expand music folder if it's an alias, or SC won't start
		if ($class->isMacAlias($musicDir)) {
			$musicDir = $class->pathFromMacAlias($musicDir);
		}

		push @dirs, $musicDir;

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

Return the filepath for a given Mac Alias

=cut

sub pathFromMacAlias {
	my ($class, $fullpath) = @_;
	my $path = '';

	return $path unless $fullpath && $canFollowAlias;

	if ($class->isMacAlias($fullpath)) {

		$fullpath = Slim::Utils::Misc::pathFromFileURL($fullpath) unless $fullpath =~ m|^/|;

		if (my $rsc = Mac::Resources::FSpOpenResFile($fullpath, 0)) {
			
			if (my $alis = Mac::Resources::GetIndResource('alis', 1)) {
				
				$path = Mac::Files::ResolveAlias($alis);

				Mac::Resources::ReleaseResource($alis);
			}

			Mac::Resources::CloseResFile($rsc);
		}
	}

	return $path;
}

=head2 isMacAlias( $path )

Return the filepath for a given Mac Alias

=cut

sub isMacAlias {
	my ($class, $fullpath) = @_;
	my $isAlias  = 0;

	return unless $fullpath && $canFollowAlias;

	$fullpath = Slim::Utils::Misc::pathFromFileURL($fullpath) unless $fullpath =~ m|^/|;

	if (-f $fullpath && -r _ && (my $rsc = Mac::Resources::FSpOpenResFile($fullpath, 0))) {

		if (my $alis = Mac::Resources::GetIndResource('alis', 1)) {

			$isAlias = 1;

			Mac::Resources::ReleaseResource($alis);
		}

		Mac::Resources::CloseResFile($rsc);
	}

	return $isAlias;
}


sub initUpdate {
	require Slim::Utils::Update;
	
	Slim::Utils::Update::getUpdate({
		os   => 'osx',
	});
}

sub canAutoUpdate { 1 }

sub canRestartServer { 1 }


1;