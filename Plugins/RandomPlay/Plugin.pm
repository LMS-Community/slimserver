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

use FindBin qw($Bin);
use File::Spec::Functions qw(catfile);

use Slim::Buttons::Home;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);

my @menuChoices  = ();
my %functions    = ();
my %safecommands = ();
my %type         = ();
my %count        = ();
my $menuAction;

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

	#
	$type = lc($type);
	
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

		$::d_plugins && msgf("RandomPlay: %s $type: $item, %d\n", ($addOnly ? 'Adding' : 'Playing'), $item->id);

		Slim::Player::Playlist::shuffle($client, 0);
		
		unless ($addOnly) {

			$client->showBriefly(string('PLUGIN_RANDOM'), string('PLUGIN_RANDOM_PLAYING'));
		}

		# Add the item / track to the playlist
		Slim::Control::Command::execute($client, ['playlist', $addOnly ? 'addtracks' : 'loadtracks', sprintf('%s=%d', $type, $item->id)]);

		Slim::Control::Command::execute($client, ['playlist', 'addtracks', 'listRef', $items]);

		checkContinuousPlay($client, $type);
	}
}

sub checkContinuousPlay {
	my ($client, $type) = @_;

	if (my $cycle = Slim::Utils::Prefs::get('plugin_random_continuous_play')) {

		$::d_plugins && msg("RandomPlay: starting callback for continuous random play.\n");

		Slim::Control::Command::setExecuteCallback(\&commandCallback);

		$count{$client} = Slim::Player::Playlist::count($client);

		$::d_plugins && msgf("RandomPlay: Playing %s $type mode with %d items\n", ($cycle ? 'continuous ' : ''), $count{$client});
	}
}

sub setMode {
	my $client = shift;
	my $method = shift;
	
	$client->lines(\&lines);

	if (!defined $menuAction) {
		$menuAction = 0;
	}

	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}

	# use INPUT.Choice to display the list of feeds
	my %params = (
		header          => 'PLUGIN_RANDOM',
		stringHeader    => 1,
		listRef         => \@menuChoices,
		externRef       => [qw(TRACK ALBUM ARTIST)],
		stringExternRef => 1,
		valueRef        => \$type{$client},
		onPlay          => \&playRandom,
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
	
	if ($slimCommand eq 'newsong' && Slim::Player::Source::streamingSongIndex($client)) {

		return unless Slim::Utils::Prefs::get('plugin_random_continuous_play');
	
		Slim::Control::Command::clearExecuteCallback(\&commandCallback);

		$::d_plugins && msg("RandomPlay: new song detected, stripping off completed track\n");

		Slim::Control::Command::execute($client, ['playlist', 'delete', Slim::Player::Source::streamingSongIndex($client) - 1]);
			
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

		'left' => sub {
			my $client = shift;

			Slim::Buttons::Common::popModeRight($client);
		},

		'right' => sub {
			my $client = shift;

			$client->bumpRight($client);
		},

		'play' => sub {
			my $client = shift;

			if ($menuAction == 0) {
				playRandom($client, ${$client->param('valueRef')});
			} else {
				Slim::Buttons::Common::popModeRight($client);
			}
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

	@menuChoices = qw(track album artist);
}

sub shutdownPlugin {
	Slim::Control::Command::clearExecuteCallback(\&commandCallback);
}

sub lines {

	return {
		'line1' => string('PLUGIN_RANDOM'),
		'line2' => $menuChoices[$menuAction],
	};
}

sub getFunctions {
	return \%functions;
}

sub webPages {

	my %pages = (
		"randomplay_mix\.(?:htm|xml)" => \&handleWebIndex,
	);

	my $value = 'plugins/RandomPlay/randomplay_mix.html';

	if (grep { /^Random$/ } Slim::Utils::Prefs::getArray('disabledplugins')) {

		$value = undef;
	}

	Slim::Web::Pages::addLinks("browse", { 'PLUGIN_RANDOM' => $value });

	return \%pages;
}

sub handleWebIndex {
	my ($client, $params) = @_;

	my $type          = 'track';
	my $ds            = Slim::Music::Info::getCurrentDataStore();

	my $totalItems    = $ds->count($type);

	my $fieldInfo     = Slim::DataStores::Base->fieldInfo;

	my $levelInfo     = $fieldInfo->{$type} || $fieldInfo->{'default'};

	my $maximumTracks = Slim::Utils::Prefs::get('plugin_random_number_of_tracks') || 10;
	my $trackCount    = 0;

	my $listRefName   = 'randomPlayListRef';

	if ($type eq 'track') {

		my $items = $ds->find({

			'field'  => 'track',
			'find'   => { 'audio' => 1 },
			'sortBy' => 'random',
			'limit'  => $maximumTracks,
			'cache'  => 0,
		});

		#$params->{'pwd_list'}    = [ { 'text' => 'Random' } ];
		#$params->{'pwdOverride'} = 1;

		$params->{'browseby'} = 'PLUGIN_RANDOM';
		$params->{'pwd_list'} .= sprintf(' / <a href="">%s</a>', string('PLUGIN_RANDOM'));

		if (ref($items) && ref($items) eq 'ARRAY') {

			# Store the list so that the client has access to it.
			if ($client) {

				$client->param($listRefName, $items);
			}

			# Create an 'ALL' link that points to a client listRef
			# Soon..
			if (0) {
				push @{$params->{'browse_list'}}, {

					'text'       => string('THIS_ENTIRE_PLAYLIST'),
					'attributes' => "&listRef=$listRefName",
				};

			} else {

				$params->{'browse_list'} .= ${Slim::Web::HTTP::filltemplatefile('browsedb_list.html', {

					'text'         => string('THIS_ENTIRE_PLAYLIST'),
					'attributes'   => "&listRef=$listRefName",
					'webroot'      => $params->{'webroot'},
					'skinOverride' => $params->{'skinOverride'},
				})};
			}

			my $itemCount = 0;

			for my $item (@{$items}) {

				my $itemname = &{$levelInfo->{'resultToName'}}($item);

				my $view = {
					'text'         => $itemname,
					'itemobj'      => $item,
					'attributes'   => '&' . join('=', $type, $item->id),

					# These can go away once the new
					# template stuff is finished.
					'webroot'      => $params->{'webroot'},
					'skinOverride' => $params->{'skinOverride'},
					'odd'          => ($itemCount + 1) % 2,
				};

				# This is calling into the %fieldInfo hash
				&{$levelInfo->{'listItem'}}($ds, $view, $item, $itemname, 0, {});

				#push @{$params->{'browse_list'}}, $view;

				$params->{'browse_list'} .= ${Slim::Web::HTTP::filltemplatefile('browsedb_list.html', $view)};

				$itemCount++;
			}
		}
	}

	return Slim::Web::HTTP::filltemplatefile('browsedb.html', $params);
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
	EN	Play random tracks, album or artist from your library. 
	DE	Wiedergabe von zufälligen Liedern, Alben oder Interpreten aus der Musikdatenbank.

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
