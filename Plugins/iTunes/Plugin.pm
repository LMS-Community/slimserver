package Plugins::iTunes::Plugin;

# SlimServer Copyright (C) 2001-2005 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Plugins::iTunes::Common);

use Slim::Player::ProtocolHandlers;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);

sub getDisplayName {
	return 'SETUP_ITUNES';
}

sub enabled {
	return ($::VERSION ge '6.1');
}

sub getFunctions {
	return '';
}

sub initPlugin {
	my $class = shift;

	addGroups();

	return 1 if $class->initialized;

	if (!$class->canUseiTunesLibrary) {
		return;
	}

	Slim::Player::ProtocolHandlers->registerHandler('itunesplaylist', 0);

	$class->initialized(1);

	$class->setPodcasts;

	return 1;
}

sub shutdownPlugin {
	my $class = shift;

	# disable protocol handler
	Slim::Player::ProtocolHandlers->registerHandler('itunesplaylist', 0);

	$class->initialized(0);

	# delGroups, categories and prefs
	Slim::Web::Setup::delCategory('ITUNES');
	Slim::Web::Setup::delGroup('SERVER_SETTINGS','itunes',1);

	# set importer to not use
	Slim::Utils::Prefs::set('itunes', 0);
}

sub addGroups {
	Slim::Web::Setup::addChildren('SERVER_SETTINGS','ITUNES',3);
	Slim::Web::Setup::addCategory('ITUNES',&setupCategory);

	my ($groupRef,$prefRef) = setupUse();

	Slim::Web::Setup::addGroup('SERVER_SETTINGS', 'itunes', $groupRef, 2, $prefRef);
}

sub setupUse {
	my $client = shift;

	my %setupGroup = (
		'PrefOrder' => ['itunes'],
		'PrefsInTable' => 1,
		'Suppress_PrefHead' => 1,
		'Suppress_PrefDesc' => 1,
		'Suppress_PrefLine' => 1,
		'Suppress_PrefSub' => 1,
		'GroupHead' => 'SETUP_ITUNES',
		'GroupDesc' => 'SETUP_ITUNES_DESC',
		'GroupLine' => 1,
		'GroupSub' => 1,
	);

	my %setupPrefs = (

		'itunes' => {

			'validate' => \&Slim::Utils::Validate::trueFalse,
			'changeIntro' => "",
			'options' => {
				'1' => string('USE_ITUNES'),
				'0' => string('DONT_USE_ITUNES'),
			},

			'onChange' => sub {
				my ($client, $changeref, $paramref, $pageref) = @_;

				foreach my $tempClient (Slim::Player::Client::clients()) {
					Slim::Buttons::Home::updateMenu($tempClient);
				}

				#XXXX - need to be fixed for the new scanner world.
				Slim::Music::Import->useImporter('ITUNES',$changeref->{'itunes'}{'new'});
			},

			'optionSort' => 'KR',
			'inputTemplate' => 'setup_input_radio.html',
		}
	);

	return (\%setupGroup, \%setupPrefs);
}

sub setupCategory {

	my %setupCategory = (

		'title' => string('SETUP_ITUNES'),

		'parent' => 'SERVER_SETTINGS',

		'GroupOrder' => [qw(Default iTunesPlaylistFormat)],

		'Groups' => {

			'Default' => {
				'PrefOrder' => [qw(
					itunesscaninterval
					ignoredisableditunestracks
					itunes_library_xml_path
					itunes_library_music_path
				)]
			},

			'iTunesPlaylistFormat' => {
				'PrefOrder' => ['iTunesplaylistprefix','iTunesplaylistsuffix'],
				'PrefsInTable' => 1,
				'Suppress_PrefHead' => 1,
				'Suppress_PrefDesc' => 1,
				'Suppress_PrefLine' => 1,
				'Suppress_PrefSub' => 1,
				'GroupHead' => 'SETUP_ITUNESPLAYLISTFORMAT',
				'GroupDesc' => 'SETUP_ITUNESPLAYLISTFORMAT_DESC',
				'GroupLine' => 1,
				'GroupSub' => 1,
			}
		},

		'Prefs' => {

			'itunesscaninterval' => {
				'validate' => \&Slim::Utils::Validate::number,
				'validateArgs' => [0,undef,1000],
			},

			'iTunesplaylistprefix' => {
				'validate' => \&Slim::Utils::Validate::acceptAll,
				'PrefSize' => 'large'
			},

			'iTunesplaylistsuffix' => {
				'validate' => \&Slim::Utils::Validate::acceptAll,
				'PrefSize' => 'large'
			},

			'ignoredisableditunestracks' => {

				'validate' => \&Slim::Utils::Validate::trueFalse,
				'options' => {
					'1' => string('SETUP_IGNOREDISABLEDITUNESTRACKS_1'),
					'0' => string('SETUP_IGNOREDISABLEDITUNESTRACKS_0'),
				},
			},

			'itunes_library_xml_path' => {
				'validate' => \&Slim::Utils::Validate::isFile,
				'validateArgs' => [1],
				'changeIntro' => string('SETUP_OK_USING'),
				'rejectMsg' => string('SETUP_BAD_FILE'),
				'PrefSize' => 'large',
			},

			'itunes_library_music_path' => {
				'validate' => \&Slim::Utils::Validate::isDir,
				'validateArgs' => [1],
				'changeIntro' => string('SETUP_OK_USING'),
				'rejectMsg' => string('SETUP_BAD_DIRECTORY'),
				'PrefSize' => 'large',
			},
		}
	);

	return \%setupCategory;
}

sub strings {
	return '';
}

1;

__END__
