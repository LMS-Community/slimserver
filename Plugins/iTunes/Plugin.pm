package Plugins::iTunes::Plugin;

# SlimServer Copyright (C) 2001-2005 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Class::Data::Inheritable);

use Plugins::iTunes::Common;

use Slim::Player::Source;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);

__PACKAGE__->mk_classdata('initialized');

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

	return 1 if $class->initialized;

	addGroups();

	if (!Plugins::iTunes::Common->canUseiTunesLibrary) {
		return;
	}

	Slim::Player::Source::registerProtocolHandler("itunesplaylist", "0");

	$class->initialized(1);

	Plugins::iTunes::Common->setPodcasts;

	return 1;
}

sub shutdownPlugin {
	my $class = shift;

	# disable protocol handler
	Slim::Player::Source::registerProtocolHandler("itunesplaylist", "0");

	$class->initialized(0);

	# delGroups, categories and prefs
	Slim::Web::Setup::delCategory('itunes');
	Slim::Web::Setup::delGroup('server','itunes',1);

	# set importer to not use
	Slim::Utils::Prefs::set('itunes', 0);
}

sub addGroups {
	Slim::Web::Setup::addChildren('server','itunes',3);
	Slim::Web::Setup::addCategory('itunes',&setupCategory);

	my ($groupRef,$prefRef) = setupUse();

	Slim::Web::Setup::addGroup('server','itunes',$groupRef,2,$prefRef);
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
		'GroupHead' => string('SETUP_ITUNES'),
		'GroupDesc' => string('SETUP_ITUNES_DESC'),
		'GroupLine' => 1,
		'GroupSub' => 1,
	);

	my %setupPrefs = (

		'itunes' => {

			'validate' => \&Slim::Web::Setup::validateTrueFalse,
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
				Slim::Music::Import->startScan('ITUNES');
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

		'parent' => 'server',

		'GroupOrder' => [qw(Default iTunesPlaylistFormat)],

		'Groups' => {

			'Default' => {
				'PrefOrder' => ['itunesscaninterval','ignoredisableditunestracks',
					'itunes_library_autolocate','itunes_library_xml_path','itunes_library_music_path']
			},

			'iTunesPlaylistFormat' => {
				'PrefOrder' => ['iTunesplaylistprefix','iTunesplaylistsuffix'],
				'PrefsInTable' => 1,
				'Suppress_PrefHead' => 1,
				'Suppress_PrefDesc' => 1,
				'Suppress_PrefLine' => 1,
				'Suppress_PrefSub' => 1,
				'GroupHead' => string('SETUP_ITUNESPLAYLISTFORMAT'),
				'GroupDesc' => string('SETUP_ITUNESPLAYLISTFORMAT_DESC'),
				'GroupLine' => 1,
				'GroupSub' => 1,
			}
		},

		'Prefs' => {

			'itunesscaninterval' => {
				'validate' => \&Slim::Web::Setup::validateNumber,
				'validateArgs' => [0,undef,1000],
			},

			'iTunesplaylistprefix' => {
				'validate' => \&Slim::Web::Setup::validateAcceptAll,
				'PrefSize' => 'large'
			},

			'iTunesplaylistsuffix' => {
				'validate' => \&Slim::Web::Setup::validateAcceptAll,
				'PrefSize' => 'large'
			},

			'ignoredisableditunestracks' => {

				'validate' => \&Slim::Web::Setup::validateTrueFalse,
				'options' => {
					'1' => string('SETUP_IGNOREDISABLEDITUNESTRACKS_1'),
					'0' => string('SETUP_IGNOREDISABLEDITUNESTRACKS_0'),
				},
			},

			'itunes_library_xml_path' => {
				'validate' => \&Slim::Web::Setup::validateIsFile,
				'changeIntro' => string('SETUP_OK_USING'),
				'rejectMsg' => string('SETUP_BAD_FILE'),
				'PrefSize' => 'large',
			},

			'itunes_library_music_path' => {
				'validate' => \&Slim::Web::Setup::validateIsDir,
				'changeIntro' => string('SETUP_OK_USING'),
				'rejectMsg' => string('SETUP_BAD_DIRECTORY'),
				'PrefSize' => 'large',
			},

			'itunes_library_autolocate' => {
				'validate' => \&Slim::Web::Setup::validateTrueFalse,
				'options' => {
					'1' => string('SETUP_ITUNES_LIBRARY_AUTOLOCATE_1'),
					'0' => string('SETUP_ITUNES_LIBRARY_AUTOLOCATE_0'),
				},
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
