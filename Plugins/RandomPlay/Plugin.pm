package Plugins::RandomPlay::Plugin;

# $Id$
#
# Originally written by Kevin Deane-Freeman (slim-mail (A_t) deane-freeman.com).
#
# New world order by Dan Sully - <dan | at | slimdevices.com>

# This code is derived from code with the following copyright message:
#
# SlimServer Copyright (C) 2005 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use Slim::Buttons::Common;
use Slim::Buttons::Home;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);

my %safeCommands = ();
my $listRefName  = 'randomPlayListRef';

sub getDisplayName {
	return 'PLUGIN_RANDOM';
}

sub playRandom {
	my ($client, $addOnly) = @_;

	unless ($client) {

		msg("RandomPlay: I need a client to generate a random mix!\n");
		return ;
	}

	# disable this during the course of this function, since we don't want
	# to retrigger on commands we send from here.
	Slim::Control::Command::clearExecuteCallback(\&commandCallback);
	
	unless ($addOnly) {
		Slim::Control::Command::execute($client, [qw(stop)]);
		Slim::Control::Command::execute($client, [qw(power 1)]);
	}

	my $ds    = Slim::Music::Info::getCurrentDataStore();
	my $items = $ds->find({

		'field'  => 'track',
		'find'   => { 'audio' => 1 },
		'sortBy' => 'random',
		'limit'  => (Slim::Utils::Prefs::get('plugin_random_number_of_tracks') || 10),
		'cache'  => 0,
	});

	# Pull the first track off to add / play it if needed.
	my $item = shift @{$items};

	if ($item && ref($item)) {

		$::d_plugins && msgf("RandomPlay: %s: (id: %d) %s\n", ($addOnly ? 'Adding' : 'Playing'), $item->id, $item->title);

		Slim::Player::Playlist::shuffle($client, 0);
		
		unless ($addOnly) {

			$client->showBriefly($client->string('PLUGIN_RANDOM_PLAYING'));
		}

		# Add the items to a client param so we can check on them later.
		$client->param($listRefName, $items);

		# Add the item / track to the playlist
		$client->execute(['playlist', $addOnly ? 'addtracks' : 'loadtracks', sprintf('track=%d', $item->id)]);

		$client->execute(['playlist', 'addtracks', 'listRef', $listRefName]);

		checkContinuousPlay($client);
	}
}

sub checkContinuousPlay {
	my $client = shift;

	if (my $cycle = Slim::Utils::Prefs::get('plugin_random_continuous_play')) {

		$::d_plugins && msg("RandomPlay: starting callback for continuous random play.\n");

		Slim::Control::Command::setExecuteCallback(\&commandCallback);

		$::d_plugins && msgf("RandomPlay: Playing %s mode with %d items\n", ($cycle ? 'continuous ' : ''), Slim::Player::Playlist::count($client));
	}
}

sub setMode {
	my $client = shift;
	my $method = shift;
	
	$client->lines(\&lines);

	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}

	playRandom($client);

	# Change to Now Playing
	Slim::Buttons::Common::pushModeLeft($client, 'playlist');
}

sub commandCallback {
	my ($client, $paramsRef) = @_;

	my $slimCommand = $paramsRef->[0];

	# we dont care about generic ir blasts
	return if $slimCommand eq 'ir';

	if (!defined $client) {

		$::d_plugins && msg("RandomPlay: No client!\n");
		bt();
		return;
	}

	$::d_plugins && msgf("RandomPlay: recieved command $slimCommand from %s\n", $client->name);

	my $songIndex = Slim::Player::Source::streamingSongIndex($client);

	if ($slimCommand eq 'newsong' && $songIndex) {

		return unless Slim::Utils::Prefs::get('plugin_random_continuous_play');

		Slim::Control::Command::clearExecuteCallback(\&commandCallback);

		$::d_plugins && msg("RandomPlay: new song detected, stripping off completed track\n");

		$client->execute(['playlist', 'delete', ($songIndex - 1)]);

		playRandom($client, 1);
	}

	if (($slimCommand eq 'stop' || $slimCommand eq 'power')
		 && $paramsRef->[1] == 0 || (($slimCommand eq 'playlist') && !exists $safeCommands{ $paramsRef->[1]} )) {

		$::d_plugins && msgf("RandomPlay: cyclic mode ended due to playlist: %s command\n", join(' ', @$paramsRef));

		Slim::Control::Command::clearExecuteCallback(\&commandCallback);
	}
}

sub initPlugin {

	%safeCommands = (
		'jump' => 1,
	);
}

sub shutdownPlugin {
	Slim::Control::Command::clearExecuteCallback(\&commandCallback);
}

sub lines {

	return {
		'line1' => string('PLUGIN_RANDOM'),
	};
}

sub getFunctions {
	return {};
}

sub webPages {

	# Just create a playlist and let it go..
	my %pages = (
		"randomplay_mix\.(?:htm|xml)" => sub {
			my ($client, $params, $prepared, $httpClient, $response) = @_;

			playRandom($client);

			# Don't do anything
			$response->code(304);

			# And send back a scalar reference, which is what the
			# HTTP code wants.
			my $body = "";

			return \$body;
		},
	);

	my $value = 'plugins/RandomPlay/randomplay_mix.html';

	if (grep { /^Random$/ } Slim::Utils::Prefs::getArray('disabledplugins')) {

		$value = undef;
	}

	Slim::Web::Pages::addLinks("browse", { 'PLUGIN_RANDOM' => $value });

	return \%pages;
}

sub setupGroup {

	my %setupGroup = (

		PrefOrder => [qw(plugin_random_number_of_tracks plugin_random_continuous_play)],
		GroupHead => string('PLUGIN_RANDOM'),
		GroupDesc => string('PLUGIN_RANDOM_DESC'),
		GroupLine => 1,
		GroupSub  => 1,
		Suppress_PrefSub  => 1,
		Suppress_PrefLine => 1,
	);

	my %setupPrefs = (

		'plugin_random_number_of_tracks' => {

			'validate'     => \&Slim::Web::Setup::validateInt,
			'validateArgs' => [1, undef, 1],
		},

		'plugin_random_continuous_play' => {

			'validate' => \&Slim::Web::Setup::validateTrueFalse  ,

			'options'  => {

				'1' => string('SETUP_PLUGIN_RANDOM_CONTINUOUS_PLAY'),
				'0' => string('SETUP_PLUGIN_RANDOM_SINGLE_PLAY'),
			}
		},
	);

	checkDefaults();

	return (\%setupGroup,\%setupPrefs);
}

sub checkDefaults {

	if (!Slim::Utils::Prefs::isDefined('plugin_random_number_of_tracks')) {

		Slim::Utils::Prefs::set('plugin_random_number_of_tracks', 10)
	}

	if (!Slim::Utils::Prefs::isDefined('plugin_random_continuous_play')) {

		Slim::Utils::Prefs::set('plugin_random_continuous_play', 1)
	}
}

sub strings {
	return <<EOF;
PLUGIN_RANDOM
	EN	Random Mix
	DE	Zufallswiedergabe

PLUGIN_RANDOM_DESC
	EN	Play random tracks from your library. 
	DE	Wiedergabe von zufälligen Liedern aus der Musikdatenbank.

PLUGIN_RANDOM_PRESS_PLAY
	EN	Press PLAY to start random playlist
	DE	Drücke PLAY zum Starten der Zufallswiedergabe

PLUGIN_RANDOM_PLAYING
	EN	Playing random tracks...
	DE	Zufallswiedergabe...

SETUP_PLUGIN_RANDOM_NUMBER_OF_TRACKS
	EN	Choose number of tracks
	DE	Wähle Anzahl der Lieder

SETUP_PLUGIN_RANDOM_CONTINUOUS_PLAY
	EN	Add new random track after each song
	DE	Nach jedem Lied ein neues Zufallslied hinzufügen
	
SETUP_PLUGIN_RANDOM_SINGLE_PLAY
	EN	Keep original random tracks
	DE	Ursprüngliche Zufallslieder behalten
EOF

}

1;

__END__
