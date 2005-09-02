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

use Slim::Buttons::Home;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);

my %functions    = ();
my %safecommands = ();
my %type         = ();
my %count        = ();
my $htmlTemplate = 'plugins/RandomPlay/randomplay_list.html';

sub getDisplayName {
	return 'PLUGIN_RANDOM';
}

sub playRandom {
	my ($client, $type, $addOnly) = @_;
	
	# disable this during the course of this function, since we don't want
	# to retrigger on commands we send from here.
	Slim::Control::Command::clearExecuteCallback(\&commandCallback);
	
	unless ($addOnly) {
		Slim::Control::Command::execute($client, [qw(stop)]);
		Slim::Control::Command::execute($client, [qw(power 1)]);
	}

	$type ||= 'track';
	$type   = lc($type);
	
	$type{$client} = $type;

	my $ds    = Slim::Music::Info::getCurrentDataStore();
	my $find  = {};
	my $limit = 1;

	$::d_plugins && msg("Starting random selection for type: [$type]\n");

	if ($type eq 'track') {

		$find->{'audio'} = 1;

		$limit = Slim::Utils::Prefs::get('plugin_random_number_of_tracks') || 10;
	}

	my $items = $ds->find({

		'field'  => $type,
		'find'   => $find,
		'sortBy' => 'random',
		'limit'  => $limit,
		'cache'  => 0,
	});

	# Pull the first track off to add / play it if needed.
	my $item = shift @{$items};

	if ($item && ref($item)) {

		my $string = $item;

		if ($type eq 'artist') {
			$string = $item->name;
		} else {
			$string = $item->title;
		}

		$::d_plugins && msgf("RandomPlay: %s %s: %s, %d\n", ($addOnly ? 'Adding' : 'Playing'), $type, $string, $item->id);

		Slim::Player::Playlist::shuffle($client, 0);
		
		unless ($addOnly) {

			$client->showBriefly(string('NOW_PLAYING'), string(sprintf('PLUGIN_RANDOM_%s', uc($type))));
		}

		# Add the item / track to the playlist
		$client->execute(['playlist', $addOnly ? 'addtracks' : 'loadtracks', sprintf('%s=%d', $type, $item->id)]);

		$client->execute(['playlist', 'addtracks', 'listRef', $items]) unless $addOnly;

		# Set the Now Playing title.
		$client->currentPlaylist($client->string('PLUGIN_RANDOM'));

		$::d_plugins && msg("RandomPlay: starting callback for continuous random play.\n");

		Slim::Control::Command::setExecuteCallback(\&commandCallback);

		$count{$client} = Slim::Player::Playlist::count($client);

		$::d_plugins && msgf("RandomPlay: Playing continuous $type mode with $count{$client} items\n");
	}
}

sub setMode {
	my $client = shift;
	my $method = shift;

	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}

	# use INPUT.List to display the list of feeds
	my %params = (
		header          => 'PLUGIN_RANDOM_PRESS_PLAY',
		stringHeader    => 1,
		listRef         => [qw(track album artist)],
		overlayRef 		=> sub { return (undef, shift->symbols('notesymbol')) },
		externRef       => [qw(PLUGIN_RANDOM_TRACK PLUGIN_RANDOM_ALBUM PLUGIN_RANDOM_ARTIST)],
		stringExternRef => 1,
		valueRef        => \$type{$client},
	);

	Slim::Buttons::Common::pushModeLeft($client, 'INPUT.List', \%params);
}

sub commandCallback {
	my ($client, $paramsRef) = @_;
	
	my $slimCommand = $paramsRef->[0];
	
	# we dont care about generic ir blasts
	return if $slimCommand eq 'ir';
	
	$::d_plugins && msg("RandomPlay: recieved command $slimCommand\n");
	
	# let warnings from undef type show for now, until it's more stable.
	if (1 || defined $type{$client}) {

		$::d_plugins && msg("RandomPlay: while in mode: $type{$client}\n");
	}

	if (!defined $client || !defined $type{$client}) {

		$::d_plugins && msg("RandomPlay: No client!\n");
		bt();
		return;
	}

	$::d_plugins && msgf("\tfrom from %s\n", $client->name);

	my $songIndex = Slim::Player::Source::streamingSongIndex($client);

	if ($slimCommand eq 'newsong' && $songIndex) {

		Slim::Control::Command::clearExecuteCallback(\&commandCallback);

		$::d_plugins && msg("RandomPlay: new song detected, stripping off completed track\n");

		Slim::Control::Command::execute($client, ['playlist', 'delete', $songIndex - 1]);
			
		if ($type{$client} eq 'track') {

			playRandom($client, $type{$client}, 1);

		} elsif (defined $type{$client}) {

			$count{$client}--;

			unless ($count{$client} > 1) {

				playRandom($client, $type{$client}, 1);

			} else {

				Slim::Control::Command::setExecuteCallback(\&commandCallback);

				$::d_plugins && msg("RandomPlay: $count{$client} items remaining\n");
			}
		}
	}

	if (($slimCommand eq 'stop' || $slimCommand eq 'power')
		 && $paramsRef->[1] == 0 || (($slimCommand eq 'playlist') && !exists $safecommands{ $paramsRef->[1]} )) {

		$type{$client} = undef;

		$::d_plugins && msgf("RandomPlay: cyclic mode ended due to playlist: %s command\n", join(' ', @$paramsRef));

		Slim::Control::Command::clearExecuteCallback(\&commandCallback);
	}
}

sub initPlugin {
	%functions = (
		'play' => sub {
			my $client = shift;
			playRandom($client, ${$client->param('valueRef')});
		},

		'tracks' => sub {
			my $client = shift;

			playRandom($client, 'track');
		},

		'albums' => sub {
			my $client = shift;

			playRandom($client, 'album');
		},

		'artists' => sub {
			my $client = shift;

			playRandom($client, 'artist');
		},
	);

	%safecommands = (
		'jump' => 1,
	);
}

sub shutdownPlugin {
	Slim::Control::Command::clearExecuteCallback(\&commandCallback);
}

sub getFunctions {
	return \%functions;
}

sub webPages {

	my %pages = (
		"randomplay_list\.(?:htm|xml)" => \&handleWebList,
		"randomplay_mix\.(?:htm|xml)"  => \&handleWebMix,
	);

	my $value = $htmlTemplate;

	if (grep { /^RandomPlay::Plugin$/ } Slim::Utils::Prefs::getArray('disabledplugins')) {

		$value = undef;
	}

	Slim::Web::Pages::addLinks("browse", { 'PLUGIN_RANDOM' => $value });

	return \%pages;
}

sub handleWebList {
	my ($client, $params) = @_;

	return Slim::Web::HTTP::filltemplatefile($htmlTemplate, $params);
}

sub handleWebMix {
	my ($client, $params) = @_;

	if ($params->{'type'}) {
		playRandom($client, $params->{'type'});
	}

	return Slim::Web::HTTP::filltemplatefile($htmlTemplate, $params);
}

sub setupGroup {

	my %setupGroup = (

		PrefOrder => [qw(plugin_random_number_of_tracks)],
		GroupHead => string('PLUGIN_RANDOM'),
		GroupDesc => string('SETUP_PLUGIN_RANDOM_DESC'),
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
	);

	checkDefaults();

	return (\%setupGroup,\%setupPrefs);
}

sub checkDefaults {

	if (!Slim::Utils::Prefs::isDefined('plugin_random_number_of_tracks')) {

		Slim::Utils::Prefs::set('plugin_random_number_of_tracks', 10)
	}
}

sub strings {
	return <<EOF;
PLUGIN_RANDOM
	DE	Zufälliger Mix
	EN	Random Mix

PLUGIN_RANDOM_TRACK
	DE	Zufällige Songs
	EN	Random Songs

PLUGIN_RANDOM_ALBUM
	DE	Zufälliges Album
	EN	Random Album

PLUGIN_RANDOM_ARTIST
	DE	Zufälliger Artist
	EN	Random Artist

PLUGIN_RANDOM_PRESS_PLAY
	DE	Zufälliger Mix
	EN	Random Mix (Press PLAY to start)

PLUGIN_RANDOM_CHOOSE_DESC
	DE	Wählen Sie eine Zufallsmix-Methode:
	EN	Choose a random mix below:

PLUGIN_RANDOM_SONG_DESC
	DE	Zufälliger Song aus Ihrer Sammlung
	EN	Random songs from your whole library.

PLUGIN_RANDOM_ARTIST_DESC
	DE	Zufälliger Artist aus Ihrer Sammlung
	EN	Random artists from your whole library.

PLUGIN_RANDOM_ALBUM_DESC
	DE	Zufälliges Album aus Ihrer Sammlung
	EN	Random album from your whole library.

SETUP_PLUGIN_RANDOM_DESC
	DE	Sie können zufällig Musik aus Ihrer Sammlung zusammenstellen lassen. Geben Sie hier an, wieviele Songs jeweils zufällig der Playlist hinzugefügt werden sollen.
	EN	The Random Mix plugin let's SlimServer create a random mix of songs from your entire library. When creating a random mix of songs, you can specify how many tracks should stay on your Now Playing playlist.

SETUP_PLUGIN_RANDOM_NUMBER_OF_TRACKS
	DE	Anzahl Songs für Zufallsmix
	EN	Number of songs in a random mix.
EOF

}

1;

__END__
