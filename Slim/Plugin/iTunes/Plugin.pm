package Slim::Plugin::iTunes::Plugin;

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Plugin::iTunes::Common);

if ( main::WEBUI ) {
	require Slim::Plugin::iTunes::Settings;
}

use Slim::Player::ProtocolHandlers;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Prefs;

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.itunes',
	'defaultLevel' => 'ERROR',
});

my $prefs = preferences('plugin.itunes');

$prefs->migrate(1, sub {
	require Slim::Utils::Prefs::OldPrefs;
	$prefs->set('itunes',          Slim::Utils::Prefs::OldPrefs->get('itunes'));
	$prefs->set('scan_interval',   Slim::Utils::Prefs::OldPrefs->get('itunesscaninterval')   || 3600      );
	$prefs->set('ignore_disabled', Slim::Utils::Prefs::OldPrefs->get('ignoredisableditunestracks') || 0   );
	$prefs->set('xml_file',        Slim::Utils::Prefs::OldPrefs->get('itunes_library_xml_path')           );
	$prefs->set('music_path',      Slim::Utils::Prefs::OldPrefs->get('itunes_library_music_path')         );
	$prefs->set('playlist_prefix', Slim::Utils::Prefs::OldPrefs->get('iTunesplaylistprefix') || '');
	$prefs->set('playlist_suffix', Slim::Utils::Prefs::OldPrefs->get('iTunesplaylistsuffix') || ''        );
	1;
});

$prefs->setValidate({ 'validator' => 'intlimit', 'low' => 0 }, 'scan_interval');
$prefs->setValidate('file', 'xml_file');
$prefs->setValidate('dir', 'music_path');

$prefs->setChange(
	sub {
		my $value = $_[1];
		
		Slim::Music::Import->useImporter('Slim::Plugin::iTunes::Importer', $value);
		Slim::Music::Import->useImporter('Slim::Plugin::iTunes::Importer::Artwork::OSX', $value) if main::ISMAC;
		Slim::Music::Import->useImporter('Slim::Plugin::iTunes::Importer::Artwork::Win32', $value) if main::ISWINDOWS;

		for my $c (Slim::Player::Client::clients()) {
			Slim::Buttons::Home::updateMenu($c);
		}
		
		# Default TPE2 as Album Artist pref if using iTunes
		if ( $value ) {
			preferences('server')->set( useTPE2AsAlbumArtist => 1 );
		}
	},
'itunes');

$prefs->setChange(
	sub {
		Slim::Utils::Timers::killTimers(undef, \&Slim::Plugin::iTunes::Plugin::checker);

		my $interval = int( $prefs->get('scan_interval') );

		if ($interval) {
			
			main::INFOLOG && $log->info("re-setting checker for $interval seconds from now.");
	
			Slim::Utils::Timers::setTimer(undef, Time::HiRes::time() + $interval, \&Slim::Plugin::iTunes::Plugin::checker);
		}
		
		else {
			
			main::INFOLOG && $log->info("disabling checker - interval set to '$interval'");
		}
	},
'scan_interval');

$prefs->setChange(
	sub {
		Slim::Control::Request::executeRequest(undef, ['rescan']);
	},
'ignore_playlists');


sub getDisplayName {
	return 'SETUP_ITUNES';
}

sub initPlugin {
	my $class = shift;

	if ( main::WEBUI ) {
		Slim::Plugin::iTunes::Settings->new;
	}

	# register importer, but don't initialize it, as it's only being run in the external scanner
	Slim::Music::Import->addImporter('Slim::Plugin::iTunes::Importer', {
		'type'   => 'file',
		'weight' => 20,
		'use'    => $prefs->get('itunes'),
	});

	return 1 if $class->initialized;

	if (!$class->canUseiTunesLibrary) {
		return;
	}

	Slim::Player::ProtocolHandlers->registerHandler('itunesplaylist', 0);

	$class->initialized(1);
	$class->checker(1);

	return 1;
}

sub shutdownPlugin {
	my $class = shift;

	# turn off checker
	Slim::Utils::Timers::killTimers(undef, \&checker);

	# disable protocol handler
	Slim::Player::ProtocolHandlers->registerHandler('itunesplaylist', 0);

	$class->initialized(0);

	# set importer to not use
	Slim::Music::Import->useImporter($class, 0);
}

sub checker {
	my $class     = shift;
	my $firstTime = shift || 0;

	if (!$prefs->get('itunes')) {

		return 0;
	}

	if (!$firstTime && !Slim::Music::Import->stillScanning && __PACKAGE__->isMusicLibraryFileChanged) {

		Slim::Control::Request::executeRequest(undef, ['rescan']);
	}

	# make sure we aren't doing this more than once...
	Slim::Utils::Timers::killTimers(undef, \&checker);

	my $interval = int( $prefs->get('scan_interval') );

	# the very first time, we do want to scan right away
	if ($firstTime) {
		$interval = 10;
	}

	if ($interval) {
		
		main::INFOLOG && $log->info("setting checker for $interval seconds from now.");
	
		Slim::Utils::Timers::setTimer(undef, Time::HiRes::time() + $interval, \&checker);
	}
}

1;

__END__
