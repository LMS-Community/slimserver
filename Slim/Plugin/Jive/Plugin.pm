package Slim::Plugin::Jive::Plugin;

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use base qw(Slim::Plugin::Base);

use Scalar::Util qw(blessed);

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Player::Playlist;
use Slim::Buttons::Information;
use Slim::Buttons::Synchronize;
use Slim::Player::Sync;
use Data::Dumper;


=head1 NAME

Plugins::Jive::Plugin

=head1 SYNOPSIS

CLI commands used by Jive.

=cut

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.jive',
	'defaultLevel' => 'WARN',
	'description'  => getDisplayName(),
});

################################################################################
# PLUGIN CODE
################################################################################
=head1 METHODS

=head2 initPlugin()

Plugin init.

=cut
sub initPlugin {
	my $class = shift;

	$class->SUPER::initPlugin();
	
	# register our functions
	
#        |requires Client
#        |  |is a Query
#        |  |  |has Tags
#        |  |  |  |Function to call
#        C  Q  T  F

    Slim::Control::Request::addDispatch(['menu', '_index', '_quantity'], 
        [0, 1, 1, \&menuQuery]);
    Slim::Control::Request::addDispatch(['menusettings', '_index', '_quantity'], 
        [1, 1, 1, \&menusettingsQuery]);

}

=head2 getDisplayName()

Returns plugin name

=cut
sub getDisplayName {
	return 'PLUGIN_JIVE';
}

######
# CLI QUERIES

# handles the "menu" query
sub menuQuery {
	my $request = shift;
 
	$log->debug("Begin Function");
 
	if ($request->isNotQuery([['menu']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get our parameters
	my $index         = $request->getParam('_index');
	my $quantity      = $request->getParam('_quantity');

	my @menu = (
		{
			text      => Slim::Utils::Strings::string('MY_MUSIC'),
			count     => 9,
			offset    => 0,
			item_loop => [
			{
				text    => Slim::Utils::Strings::string('BROWSE_BY_ALBUM'),
				actions => {
					go => {
						cmd    => ['albums'],
						params => {
							menu => 'track',
						},
					},
				},
				window => {
					menuStyle => 'album',
				},
			},
			{
				text    => Slim::Utils::Strings::string('BROWSE_BY_ARTIST'),
				actions => {
					go => {
						cmd    => ['artists'],
						params => {
							menu => 'album',
						},
					},
				},
			},
			{
				text    => Slim::Utils::Strings::string('BROWSE_BY_GENRE'),
				actions => {
					go => {
						cmd    => ['genres'],
						params => {
							menu => 'artist',
						},
					},
				},
			},
			{
				text    => Slim::Utils::Strings::string('BROWSE_BY_YEAR'),
				actions => {
					go => {
						cmd    => ['years'],
						params => {
							menu => 'album',
						},
					},
				},
			},
			{
				text    => Slim::Utils::Strings::string('BROWSE_NEW_MUSIC'),
				actions => {
					go => {
						cmd    => ['albums'],
						params => {
							menu => 'track',
							sort => 'new',
						},
					},
				},
				window => {
					menuStyle => 'album',
				},
			},
			{
				text    => Slim::Utils::Strings::string('FAVORITES'),
				actions => {
					go => {
						cmd    => ['favorites', 'items'],
						params => {
							menu => 'favorites',
						},
					},
				},
			},
			{
				text    => Slim::Utils::Strings::string('BROWSE_MUSIC_FOLDER'),
				actions => {
					go => {
						cmd    => ['musicfolder'],
						params => {
							menu => 'musicfolder',
						},
					},
				},
			},
			{
				text    => Slim::Utils::Strings::string('SAVED_PLAYLISTS'),
				actions => {
					go => {
						cmd    => ['playlists'],
						params => {
							menu => 'track',
						},
					},
				},
			},
			{
				text      => Slim::Utils::Strings::string('SEARCH'),
				count     => 4,
				offset    => 0,
				item_loop => [
					{
						text  => Slim::Utils::Strings::string('ARTISTS'),
						input => {
							len  => 2, # Richard says "we can't search for U2!"
							help => {
								text => Slim::Utils::Strings::string('JIVE_SEARCHFOR_HELP')
							},
						},
						actions => {
							go => {
								cmd => ['artists'],
								params => {
									menu => 'album',
									search => '__TAGGEDINPUT__',
								},
							},
						},
						window => {
							text => Slim::Utils::Strings::string('SEARCHFOR_ARTISTS'),
						},
					},
					{
						text  => Slim::Utils::Strings::string('ALBUMS'),
						input => {
							len => 3,
							help => {
								text => Slim::Utils::Strings::string('JIVE_SEARCHFOR_HELP')
							},
						},
						actions => {
							go => {
								cmd => ['albums'],
								params => {
									menu => 'track',
									search => '__TAGGEDINPUT__',
								},
							},
						},
						window => {
							text => Slim::Utils::Strings::string('SEARCHFOR_ALBUMS'),
							menuStyle => 'album',
						},
					},
					{
						text  => Slim::Utils::Strings::string('SONGS'),
						input => {
							len => 3,
							help => {
								text => Slim::Utils::Strings::string('JIVE_SEARCHFOR_HELP')
							},
						},
						actions => {
							go => {
								cmd => ['tracks'],
								params => {
									menu => 'track',
									search => '__TAGGEDINPUT__',
								},
							},
						},
						window => {
							'text' => Slim::Utils::Strings::string('SEARCHFOR_SONGS'),
						},
					},
					{
						text  => Slim::Utils::Strings::string('PLAYLISTS'),
						input => {
							len => 3,
							help => {
								text => Slim::Utils::Strings::string('JIVE_SEARCHFOR_HELP')
							},
						},
						actions => {
							go => {
								cmd => ['playlists'],
								params => {
									menu => 'track',
									search => '__TAGGEDINPUT__',
								},
							},
						},
						window => {
							text => Slim::Utils::Strings::string('SEARCHFOR_PLAYLISTS'),
						},
					},
				],
			},
			],
		},
		{
			text    => Slim::Utils::Strings::string('RADIO'),
			actions => {
				go => {
					cmd => ['radios'],
					params => {
						menu => 'radio',
					},
				},
			},
		},
		{
			text    => Slim::Utils::Strings::string('MUSIC_ON_DEMAND'),
			actions => {
				go => {
					cmd => ['music_on_demand'],
					params => {
						menu => 'music_on_demand',
					},
				},
			},
		},
		{
			text    => Slim::Utils::Strings::string('FAVORITES'),
			actions => {
				go => {
					cmd => ['favorites', 'items'],
					params => {
						menu => 'favorites',
					},
				},
			},
		},
		{
			text    => Slim::Utils::Strings::string('PLAYER_SETTINGS'),
			actions => {
				go => {
					cmd    => ['menusettings'],
					player => 0,
					params => {
						menu => 'settings',
					},
				},
			},
		},
	);

	my $numitems = scalar(@menu);

	$request->addResult("count", $numitems);

	my ($valid, $start, $end) = $request->normalize(scalar($index), scalar($quantity), $numitems);

	if ($valid) {
		
		my $cnt = 0;
		$request->addResult('offset', $start);

		for my $eachmenu (@menu[$start..$end]) {			
			$request->setResultLoopHash('item_loop', $cnt, $eachmenu);
			$cnt++;
		}
	}

	$request->setStatusDone();
}

sub menusettingsQuery {
	my $request = shift;
 
	$log->debug("Begin Function");
 
	if ($request->isNotQuery([['menusettings']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get our parameters
	my $client        = $request->client();
	my $index         = $request->getParam('_index');
	my $quantity      = $request->getParam('_quantity');

	my $prefs = preferences('server');

	my @menu;
	
	
	# always add repeat
	my $val = Slim::Player::Playlist::repeat($client);
	push @menu, {
		text      => Slim::Utils::Strings::string('REPEAT'),
		count     => 3,
		offset    => 0,
		item_loop => [
			{
				text    => Slim::Utils::Strings::string("REPEAT_OFF"),
				radio	=> ($val == 0) + 0, # 0 is added to force data type to number
				actions => {
					do => {
						player => 0,
						cmd => ['playlist', 'repeat', '0'],
					},
				},
			},
			{
				text    => Slim::Utils::Strings::string("REPEAT_ONE"),
				radio	=> ($val == 1) + 0, # 0 is added to force the data type to number
				actions => {
					do => {
						player => 0,
						cmd => ['playlist', 'repeat', '1'],
					},
				},
			},
			{
				text    => Slim::Utils::Strings::string("REPEAT_ALL"),
				radio	=> ($val == 2) + 0, # 0 is added to force the data type to number
				actions => {
					do => {
						player => 0,
						cmd => ['playlist', 'repeat', '2'],
					},
				},
			},
		],
	};
	

	# always add shuffle
	$val = Slim::Player::Playlist::shuffle($client);
	push @menu, {
		text      => Slim::Utils::Strings::string('SHUFFLE'),
		count     => 3,
		offset    => 0,
		item_loop => [
			{
				text    => Slim::Utils::Strings::string("SHUFFLE_OFF"),
				radio	=> ($val == 0) + 0, # 0 is added to force the data type to number
				actions => {
					do => {
						player => 0,
						cmd => ['playlist', 'shuffle', '0'],
					},
				},
			},
			{
				text    => Slim::Utils::Strings::string("SHUFFLE_ON_SONGS"),
				radio	=> ($val == 1) + 0, # 0 is added to force the data type to number
				radio	=> 1,
				actions => {
					do => {
						player => 0,
						cmd => ['playlist', 'shuffle', '1'],
					},
				},
			},
			{
				text    => Slim::Utils::Strings::string("SHUFFLE_ON_ALBUMS"),
				radio	=> ($val == 2) + 0, # 0 is added to force the data type to number
				actions => {
					do => {
						player => 0,
						cmd => ['playlist', 'shuffle', '2'],
					},
				},
			},
		],
	};

# disable for now
if (0) {
	# always add sleep (?)
	$val = $client->currentSleepTime();
	my $sleeping_in = Slim::Utils::Strings::string('SLEEPING_IN');
	my $minutes = Slim::Utils::Strings::string('MINUTES');
	push @menu, {
		text      => Slim::Utils::Strings::string('SLEEP'),
		count     => 6,
		offset    => 0,
		item_loop => [
			{
				text    => Slim::Utils::Strings::string("NONE"),
				radio	=> ($val == 0) + 0, # 0 is added to force the data type to number
				actions => {
					do => {
						player => 0,
						cmd => ['sleep', '0'],
					},
				},
			},
			{
				text    => $sleeping_in . ' 15 ' . $minutes,
				radio	=> ($val == (15*60)) + 0, # 0 is added to force the data type to number
				actions => {
					do => {
						player => 0,
						cmd => ['sleep', 15*60 ],
					},
				},
			},
			{
				text    => $sleeping_in . ' 30 ' . $minutes,
				radio	=> ($val == (30*60)) + 0, # 0 is added to force the data type to number
				actions => {
					do => {
						player => 0,
						cmd => ['sleep', 30*60],
					},
				},
			},
			{
				text    => $sleeping_in . ' 45 ' . $minutes,
				radio	=> ($val == (45*60)) + 0, # 0 is added to force the data type to number
				actions => {
					do => {
						player => 0,
						cmd => ['sleep', 45*60],
					},
				},
			},
			{
				text    => $sleeping_in . ' 60 ' . $minutes,
				radio	=> ($val == (60*60)) + 0, # 0 is added to force the data type to number
				actions => {
					do => {
						player => 0,
						cmd => ['sleep', 60*60],
					},
				},
			},
			{
				text    => $sleeping_in . ' 90 ' . $minutes,
				radio	=> ($val == (90*60)) + 0, # 0 is added to force the data type to number
				actions => {
					do => {
						player => 0,
						cmd => ['sleep', 90*60],
					},
				},
			},
		],
	};
}

# disable for now
if (0) {
	# alarm clock, always display (all platforms support alarms? softsqueeze? stream.mp3?)
	$val = $prefs->client($client)->get('alarm')->[ 0 ];
	my $alarm_playlist = 1;

	push @menu, {
		text      => Slim::Utils::Strings::string("ALARM"),
		count     => 6,
		offset    => 0,
		item_loop => [
			{ 
				text     => Slim::Utils::Strings::string("ON"),
				checkbox => ($val == 1) + 0,
				actions  => {
						on  => {
							player => 0,
							cmd    => ['alarm'],
							params => { 
								cmd     => 'set',
								dow     => 0,
								enabled => 1,
							},
						},
						off => {
							player => 0,
							cmd    => ['alarm'],
							params => { 
								cmd     => 'set',
								dow     => 0,
								enabled => 0,
							},
						},
				},
			},
			{ 
				text    => Slim::Utils::Strings::string("ALARM_SET"),
				input   => {
					inputType    => 'time',
					len          => 1,
					help         => {
							text => Slim::Utils::Strings::string('JIVE_ALARMSET_HELP')
					},
				},
				actions => {
					do => {
						player => 0,
						cmd    => ['alarm'],
						params => {
							cmd => 'set',
							dow =>	0,
							time => '__TAGGEDINPUT__',	
						},
					},
				},
			},
			{ 
				text => Slim::Utils::Strings::string("ALARM_SELECT_PLAYLIST"),
				count     => 4,
				offset    => 0,
				item_loop => [
					{
						text    => Slim::Utils::Strings::string("CURRENT_PLAYLIST"),
						radio	=> ($alarm_playlist == -1) + 0, # 0 is added to force the data type to number
						actions => {
							do => {
								player => 0,
								cmd    => ['alarms'],
								params => {
									playlist_id => '-1',
								},
							},
						},
					},
					{
						text    => Slim::Utils::Strings::string("PLUGIN_RANDOM_TRACK"),
						radio	=> ($alarm_playlist == -2) + 0, # 0 is added to force the data type to number
						actions => {
							do => {
								player => 0,
								cmd    => ['alarms'],
								params => {
									playlist_id => '-2',
								},
							},
						},
					},
					{
						text    => Slim::Utils::Strings::string("PLUGIN_RANDOM_ALBUM"),
						radio	=> ($alarm_playlist == -3) + 0, # 0 is added to force the data type to number
						actions => {
							do => {
								player => 0,
								cmd    => ['alarms'],
								params => {
									playlist_id => '-3',
								},
							},
						},
					},
					{
						text    => Slim::Utils::Strings::string("PLUGIN_RANDOM_CONTRIBUTOR"),
						radio	=> ($alarm_playlist == -4) + 0, # 0 is added to force the data type to number
						actions => {
							do => {
								player => 0,
								cmd    => ['alarms'],
								params => {
									playlist_id => '-4',
								},
							},
						},
					},
				],
			},
			{ 
				text => Slim::Utils::Strings::string("ALARM_SET_VOLUME"),
			},
			{ 
				text => Slim::Utils::Strings::string("ALARM_WEEKDAYS"),
			},
			{ 
				text => Slim::Utils::Strings::string("ALARM_FADE"),
			},
		],
	};
}

# disable for now
if (0) {
	# synchronization. only if numberOfPlayers > 1
	my $playerCount = scalar(Slim::Player::Sync::canSyncWith($client));
	if (scalar($playerCount > 0)) {
		my $playersToSyncWith = getPlayersToSyncWith($client);
		push @menu, {
			text      => Slim::Utils::Strings::string("SYNCHRONIZE"),
			count     => $playerCount,
			offset    => 0,
			item_loop => [ @$playersToSyncWith ],
		};
	}
}

	# replay gain (volume adjustment)
	if ($client->canDoReplayGain(0)) {
		$val = $prefs->client($client)->get('replayGainMode');
		push @menu, {
			text      => Slim::Utils::Strings::string("REPLAYGAIN"),
			count     => 4,
			offset    => 0,
			item_loop => [
				{
					text    => Slim::Utils::Strings::string("REPLAYGAIN_DISABLED"),
					radio	=> ($val == 0) + 0, # 0 is added to force the data type to number
					actions => {
						do => {
							player => 0,
							cmd => ['replayGainMode', '0'],
						},
					},
				},
				{
					text    => Slim::Utils::Strings::string("REPLAYGAIN_TRACK_GAIN"),
					radio	=> ($val == 1) + 0, # 0 is added to force the data type to number
					actions => {
						do => {
							player => 0,
							cmd => ['replayGainMode', '1'],
						},
					},
				},
				{
					text    => Slim::Utils::Strings::string("REPLAYGAIN_ALBUM_GAIN"),
					radio	=> ($val == 2) + 0, # 0 is added to force the data type to number
					actions => {
						do => {
							player => 0,
							cmd => ['replayGainMode', '2'],
						},
					},
				},
				{
					text    => Slim::Utils::Strings::string("REPLAYGAIN_SMART_GAIN"),
					radio	=> ($val == 3) + 0, # 0 is added to force the data type to number
					actions => {
						do => {
							player => 0,
							cmd => ['replayGainMode', '3'],
						},
					},
				},
			],
		};
	}

	# transition only for Sb2 and beyond
	if ($client->isa('Slim::Player::Squeezebox2')) {
		$val = $prefs->client($client)->get('transitionType');
		push @menu, {
			text      => Slim::Utils::Strings::string('SETUP_TRANSITIONTYPE'),
			count     => 5,
			offset    => 0,
			item_loop => [
				{
					text    => Slim::Utils::Strings::string("TRANSITION_NONE"),
					radio	=> ($val == 0) + 0, # 0 is added to force the data type to number
					actions => {
						do => {
							player => 0,
							cmd => ['playerpref', 'transitionType', '0'],
						},
					},
				},
				{
					text    => Slim::Utils::Strings::string("TRANSITION_CROSSFADE"),
					radio	=> ($val == 1) + 0, # 0 is added to force the data type to number
					actions => {
						do => {
							player => 0,
							cmd => ['playerpref', 'transitionType', '1'],
						},
					},
				},
				{
					text    => Slim::Utils::Strings::string("TRANSITION_FADE_IN"),
					radio	=> ($val == 2) + 0, # 0 is added to force the data type to number
					actions => {
						do => {
							player => 0,
							cmd => ['playerpref', 'transitionType', '2'],
						},
					}
				},
				{
					text    => Slim::Utils::Strings::string("TRANSITION_FADE_OUT"),
					radio	=> ($val == 3) + 0, # 0 is added to force the data type to number
					actions => {
						do => {
							player => 0,
							cmd => ['playerpref', 'transitionType', '3'],
						},
					},
				},
				{
					text    => Slim::Utils::Strings::string("TRANSITION_FADE_IN_OUT"),
					radio	=> ($val == 4) + 0,
					actions => {
						do => {
							player => 0,
							cmd => ['playerpref', 'transitionType', '4'],
						},
					},
				},
			],
		};
	}

	# information, always display
	push @menu, {
		text      => Slim::Utils::Strings::string('INFORMATION'),
		count     => 12,
		offset    => 0,
		item_loop => [
			{
				text    => Slim::Utils::Strings::string("INFORMATION_PLAYER_NAME") . ":",
			},
			{
				text    => $client->name(),
			},
			{
				text    => Slim::Utils::Strings::string("INFORMATION_PLAYER_MODEL") . ":",
			},
			{
				text    => Slim::Buttons::Information::playerModel($client),
			},
			{
				text    => Slim::Utils::Strings::string("INFORMATION_FIRMWARE") . ":",
			},
			{
				text    => $client->revision(),
			},
			{
				text    => Slim::Utils::Strings::string("INFORMATION_PLAYER_IP") . ":",
			},
			{
				text    => $client->ip(),
			},
			{
				text    => Slim::Utils::Strings::string("INFORMATION_PLAYER_PORT") . ":",
			},
			{
				text    => $client->port(),
			},
			{
				text    => Slim::Utils::Strings::string("INFORMATION_PLAYER_MAC") . ":",
			},
			{
				text    => uc($client->macaddress()),
			},
		],

	};

# skip for now
if (0) {
	# player name change, always display
	push @menu, {
		text      => Slim::Utils::Strings::string('CHANGE_PLAYER_NAME'),
		input => {
			len          => 1, # For those that want to name their player "X"
			allowedChars => 'AaBbCcDdEeFfGgHhIiJjKkLlMmNnOoPpQqRrSsTtUuVvWwXxYyZz!@#$%^&*()_+{}|:\"\'<>?-=,./~`[];0123456789',
			help         => {
				           text => Slim::Utils::Strings::string('JIVE_CHANGEPLAYERNAME_HELP')
			},
		},
		actions => {
			do => {
				player => 0,
				cmd    => ['playerpref', 'playername'],
				params => {
					playername => '__INPUT__',
				},
			},
		},
	};
}
	# now slice and ship
	my $numitems = scalar(@menu);

	$request->addResult("count", $numitems);

	my ($valid, $start, $end) = $request->normalize(scalar($index), scalar($quantity), $numitems);

	if ($valid) {
		
		my $cnt = 0;
		$request->addResult('offset', $start);

		for my $eachmenu (@menu[$start..$end]) {			
			$request->setResultLoopHash('item_loop', $cnt, $eachmenu);
			$cnt++;
		}
	}

	$request->setStatusDone();
}

sub getPlayersToSyncWith() {
	my $client = shift;
	@{$client->syncSelections} = Slim::Player::Sync::canSyncWith($client);
#	my @array = Slim::Player::Sync::canSyncWith($client);
	warn @{$client->syncSelections};
	my @return;
	# go through available players to sync with and return a LoH with the correct values
#	my $listRef = Slim::Buttons::Synchronize::lines;
	for my $player (@{$client->syncSelections}) {
		warn $player;
		push @return, {
			{
				text => $player,
			},
		};
	}
	return \@return;
}

1;
