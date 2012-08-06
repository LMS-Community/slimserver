package Slim::Control::LocalPlayers::Jive;

# Copyright 2001-2011 Logitech
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;

use POSIX qw(strftime);
use Scalar::Util qw(blessed);
use URI;

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Player::Playlist;
use Slim::Player::Client;
#use Data::Dump;

my $prefs   = preferences("server");

=head1 NAME

Slim::Control::Jive

=head1 SYNOPSIS

CLI commands used by Jive.

=cut

my $log = logger('player.jive');

=head1 METHODS

=head2 init()

=cut
sub init {
	my $class = shift;

	# register our functions
	
       #        |requires Client (2 == set disconnected client to clientid if client does not exist)
       #        |  |is a Query
       #        |  |  |has Tags
       #        |  |  |  |Function to call
       #        C  Q  T  F

	Slim::Control::Request::addDispatch(['alarmsettings', '_index', '_quantity'], 
		[1, 1, 1, \&alarmSettingsQuery]);
	
	Slim::Control::Request::addDispatch(['jiveupdatealarm', '_index', '_quantity'], 
		[1, 1, 1, \&alarmUpdateMenu]);
	
	Slim::Control::Request::addDispatch(['jiveupdatealarmdays', '_index', '_quantity'], 
		[1, 1, 1, \&alarmUpdateDays]);
	
	Slim::Control::Request::addDispatch(['syncsettings', '_index', '_quantity'],
		[1, 1, 1, \&syncSettingsQuery]);
	
	Slim::Control::Request::addDispatch(['sleepsettings', '_index', '_quantity'],
		[1, 1, 1, \&sleepSettingsQuery]);
	
	Slim::Control::Request::addDispatch(['jivetonesettings', '_index', '_quantity'],
		[1, 1, 1, \&toneSettingsQuery]);
	
	Slim::Control::Request::addDispatch(['jivefixedvolumesettings', '_index', '_quantity'],
		[1, 1, 1, \&fixedVolumeSettingsQuery]);
	
	Slim::Control::Request::addDispatch(['jivestereoxl', '_index', '_quantity'],
		[1, 1, 1, \&stereoXLQuery]);
	
	Slim::Control::Request::addDispatch(['jivelineout', '_index', '_quantity'],
		[1, 1, 1, \&lineOutQuery]);
	
	Slim::Control::Request::addDispatch(['crossfadesettings', '_index', '_quantity'],
		[1, 1, 1, \&crossfadeSettingsQuery]);
	
	Slim::Control::Request::addDispatch(['replaygainsettings', '_index', '_quantity'],
		[1, 1, 1, \&replaygainSettingsQuery]);
	
	Slim::Control::Request::addDispatch(['jivealarm'],
		[1, 0, 1, \&jiveAlarmCommand]);
	
	Slim::Control::Request::addDispatch(['jiveendoftracksleep', '_index', '_quantity' ],
		[1, 1, 1, \&endOfTrackSleepCommand]);
	
	Slim::Control::Request::addDispatch(['jivefavorites', '_cmd' ],
		[1, 0, 1, \&jiveFavoritesCommand]);
	
	Slim::Control::Request::addDispatch(['jivepresets', '_index', '_quantity' ],
		[1, 1, 1, \&jivePresetsMenu]);
	
	Slim::Control::Request::addDispatch(['jivealarmvolume'],
		[1, 0, 1, \&jiveAlarmVolumeSlider ]);
	
	Slim::Control::Request::addDispatch(['jiveplayerbrightnesssettings', '_index', '_quantity'],
		[1, 1, 0, \&playerBrightnessMenu]);
	
	Slim::Control::Request::addDispatch(['jiveplayertextsettings', '_whatFont', '_index', '_quantity'],
		[1, 1, 0, \&playerTextMenu]);

	Slim::Control::Request::addDispatch(['jivesync' ],
		[1, 0, 1, \&jiveSyncCommand]);
	
	Slim::Control::Request::addDispatch(['jiveplaylists', '_cmd' ],
		[1, 0, 1, \&jivePlaylistsCommand]);
	
	Slim::Control::Request::addDispatch(['jivedummycommand', '_index', '_quantity'],
		[1, 1, 1, \&jiveDummyCommand]);
	
	if (!main::SLIM_SERVICE) {
		Slim::Control::Request::addDispatch(['service', 'get_nonce'],
		[0, 1, 1, sub {
			my $request = shift;
			$request->addResult( result => 0 );
			$request->setStatusDone();
		}]) ;
	}
}

sub sliceAndShip {
	Slim::Control::Jive::sliceAndShip(@_);
}

sub _notifyJive {
	Slim::Control::Jive::_notifyJive(@_);
}

###############################################################
#
# Methods only relevant for locally-attached players from here on

sub alarmSettingsQuery {

	main::INFOLOG && $log->info("Begin function");
	my $request = shift;
	my $client  = $request->client();

	my @menu = ();
	return \@menu unless $client;

	# All Alarms On/Off

	my $val = $prefs->client($client)->get('alarmsEnabled');

	my @alarmStrings = ('OFF', 'ON');
	my @translatedAlarmStrings = map { ucfirst($client->string($_)) } @alarmStrings;

	my $onOff = {
		text           => $client->string("ALARM_ALL_ALARMS"),
		choiceStrings  => [ @translatedAlarmStrings ],
		selectedIndex  => $val + 1, # 1 is added to make it count like Lua
		actions        => {
			do => { 
				choices => [ 
					{
						player => 0,
						cmd    => [ 'alarm', 'disableall' ],
					},
					{
						player => 0,
						cmd    => [ 'alarm', 'enableall' ],
					},
				], 
			},
		},
	};
	push @menu, $onOff;

	my $setAlarms = _getCurrentAlarms($client);

	if ( scalar(@$setAlarms) ) {
		push @menu, @$setAlarms;
	}

	my $addAlarm = {
		text           => $client->string("ALARM_ADD"),
		input   => {
			initialText  => 25200, # default is 7:00
			title => $client->string('ALARM_ADD'),
			_inputStyle  => 'time',
			len          => 1,
			help         => {
				text => $client->string('JIVE_ALARMSET_HELP')
			},
		},
		actions => {
			do => {
				player => 0,
				cmd    => [ 'alarm', 'add' ],
				params => {
					time => '__TAGGEDINPUT__',	
					enabled => 1,
				},
			},
		},
		nextWindow => 'refresh',
	};
	push @menu, $addAlarm;

	# Bug 9226: don't offer alarm volume setting if player is set for fixed volume
	my $digitalVolumeControl = $prefs->client($client)->get('digitalVolumeControl');
	if ( ! ( defined $digitalVolumeControl && $digitalVolumeControl == 0 ) ) {
		my $defaultVolLevel = Slim::Utils::Alarm->defaultVolume($client);
		my $defaultVolumeLevels = _alarmVolumeSettings($defaultVolLevel, undef, $client->string('ALARM_VOLUME'));
		push @menu, $defaultVolumeLevels;
	}

	my $fadeEnabled = $prefs->client($client)->get('alarmfadeseconds');
	if (!defined ($fadeEnabled) || $fadeEnabled == 0) {
		$fadeEnabled = 0;
	} else {
		$fadeEnabled = 1;
	}

	my $fadeInAlarm = {
		text           => $client->string("ALARM_FADE"),
		checkbox => ($fadeEnabled == 1) + 0,
		actions  => {
			on  => {
				player => 0,
				cmd    => [ 'jivealarm' ],
				params => {
					fadein => 1,
				},
			},
			off => {
				player => 0,
				cmd    => [ 'jivealarm' ],
				params => {
					fadein => 0,
				},
			},
		},		
	};
	push @menu, $fadeInAlarm;

	sliceAndShip($request, $client, \@menu);

}

sub alarmUpdateMenu {

	my $request = shift;
	my $client  = $request->client();
	my $params;

	my @tags = qw( id enabled days time playlist );
	for my $tag (@tags) {
		$params->{$tag} = $request->getParam($tag);
	}

	my $alarm = Slim::Utils::Alarm->getAlarm($client, $params->{id});
	my @menu = ();

	my $enabled = $alarm->enabled();
	my $onOff = {
		text     => $client->string("ALARM_ALARM_ENABLED"),
		checkbox => ($enabled == 1) + 0,
		onClick  => 'refreshOrigin',
		actions  => {
			on  => {
				player => 0,
				cmd    => [ 'alarm', 'update' ],
				params => {
					id      => $params->{id},
					enabled => 1,
				},
			},
			off => {
				player => 0,
				cmd    => [ 'alarm', 'update' ],
				params => {
					id      => $params->{id},
					enabled => 0,
				},
			},
		},		
	};
	push @menu, $onOff;

	my $setTime = {
		text           => $client->string("ALARM_SET_TIME"),
		input   => {
			initialText  => $params->{time}, # this will need to be formatted correctly
			title => $client->string('ALARM_SET_TIME'),
			_inputStyle  => 'time',
			len          => 1,
			help         => {
				text => $client->string('JIVE_ALARMSET_HELP')
			},
		},
		actions => {
			do => {
				player => 0,
				cmd    => [ 'alarm', 'update' ],
				params => {
					id   => $params->{id},
					time => '__TAGGEDINPUT__',	
				},
			},
		},
		nextWindow => 'parent',
	};
	push @menu, $setTime;


	my $setDays = {
		text      => $client->string("ALARM_SET_DAYS"),
		actions   => {
			go => {
				player => 0,
				cmd    => [ 'jiveupdatealarmdays' ],
				params => {
					id => $params->{id},
				},
			},
		},
	};
	push @menu, $setDays;

	my $playlistChoice = {
		text      => $client->string('ALARM_SELECT_PLAYLIST'),
		actions   => {
			go => {
				player => 0,
				cmd    => [ 'alarm', 'playlists' ],
				params => {
					id   => $params->{id},
					menu => 1
				},
			},
		},
	};
	push @menu, $playlistChoice;

	my $repeat = $alarm->repeat();
	my $repeatOn = {
		text     => $client->string("ALARM_ALARM_REPEAT"),
		radio    => ($repeat == 1) + 0,
		onClick  => 'refreshOrigin',
		actions  => {
			do  => {
				player => 0,
				cmd    => [ 'alarm', 'update' ],
				params => {
					id      => $params->{id},
					repeat => 1,
				},
			},
		},		
	};
	push @menu, $repeatOn;

	my $repeatOff = {
		text     => $client->string("ALARM_ALARM_ONETIME"),
		radio    => ($repeat == 0) + 0,
		onClick  => 'refreshOrigin',
		actions  => {
			do => {
				player => 0,
				cmd    => [ 'alarm', 'update' ],
				params => {
					id      => $params->{id},
					repeat => 0,
				},
			},
		},
	};
	push @menu, $repeatOff;

	my @delete_menu= (
		{
			text    => $client->string('CANCEL'),
			actions => {
				go => {
					player => 0,
					cmd    => [ 'jiveblankcommand' ],
				},
			},
			nextWindow => 'parent',
		},
		{
			text    => $client->string('ALARM_DELETE'),
			actions => {
				go => {
					player => 0,
					cmd    => ['alarm', 'delete'],
					params => {
						id => $params->{id},
					},
				},
			},
			nextWindow => 'grandparent',
		},
	);
	my $removeAlarm = {
		text      => $client->string('ALARM_DELETE'),
		count     => scalar(@delete_menu),
		offset    => 0,
		item_loop => \@delete_menu,
	};
	push @menu, $removeAlarm;

	sliceAndShip($request, $client, \@menu);
}

sub alarmUpdateDays {

	my $request = shift;
	my $client  = $request->client;

	my @params  = qw/ id /;
	my $params;
	for my $key (@params) {
		$params->{$key} = $request->getParam($key);
	}
	my $alarm = Slim::Utils::Alarm->getAlarm($client, $params->{id});

	my @days_menu = ();

	for my $day (0..6) {
		my $dayActive = $alarm->day($day);
		my $string = "ALARM_DAY$day";

		my $day = {
			text       => $client->string($string),
			checkbox   => $dayActive + 0,
			onClick    => 'refreshGrandparent',
			actions => {
				on => {
					player => 0,
					cmd    => [ 'alarm', 'update' ],
					params => {
						id => $params->{id},
						dowAdd => $day,
					},
				},
				off => {
					player => 0,
					cmd    => [ 'alarm', 'update' ],
					params => {
						id => $params->{id},
						dowDel => $day,
					},
				},
	
			},
		};
		push @days_menu, $day;
	}

	sliceAndShip($request, $client, \@days_menu);

	$request->setStatusDone();
}

sub _getCurrentAlarms {
	
	my $client = shift;
	my @return = ();
	my @alarms = Slim::Utils::Alarm->getAlarms($client);
	#Data::Dump::dump(@alarms);
	my $count = 1;
	for my $alarm (@alarms) {
		my @days;
		for (0..6) {
			push @days, $_ if $alarm->day($_);
		}
		my $name = $client->string('ALARM_ALARM') . " $count: " . $alarm->displayStr;
		my $daysString = join(',', @days);
		my $thisAlarm = {
			text           => $name,
			actions        => {
				go => {
					cmd    => ['jiveupdatealarm'],
					params => {
						id       => $alarm->id,
						enabled  => $alarm->enabled || 0,
						days     => $daysString,
						time     => $alarm->time || 0,
						playlist => $alarm->playlist || 0, # don't pass an undef to jive
					},
					player => 0,
				},
			},
		};
		push @return, $thisAlarm;
		$count++;
	}
	return \@return;
}

sub _alarmVolumeSettings {

	my $current_setting = shift || 50;
	my $id              = shift || 0;
	my $string          = shift;

	my $return = { 
		text      => $string,
		actions   => {
			go => {
				player => 0,
				cmd    => [ 'jivealarmvolume' ],
			},
		},
	};
	return $return;
}

sub jiveAlarmVolumeSlider {

	my $request = shift;
	my $client  = $request->client();

	my $current_setting = Slim::Utils::Alarm->defaultVolume($client) || 50;
	my $id              = shift || 0;
	my $string          = shift;

	my @vol_settings;
	my $slider = {
		slider      => 1,
		min         => 1,
		max         => 100,
		sliderIcons => 'volume',
		initial     => $current_setting,
		actions => {
			do => {
				player => 0,
				cmd    => [ 'alarm', 'defaultvolume' ],
				params => {
					valtag => 'volume',
				},
			},
		},
	};

	$request->addResult('offset', 0);
	$request->addResult('count', 1);
	$request->addResult('item_loop', [ $slider ] );
	$request->setStatusDone();

}


sub syncSettingsQuery {

	main::INFOLOG && $log->info("Begin function");
	my $request           = shift;
	my $client            = $request->client();
	my $synchablePlayers  = _howManyPlayersToSyncWith($client);

	if ( $synchablePlayers > 0 ) {
		my $playersToSyncWith = _getPlayersToSyncWith($client);
		my @menu = @$playersToSyncWith;
		sliceAndShip($request, $client, \@menu);

	# Bug 16030
	# when no sync players present, give message about how adding squeezeboxes could allow you to sync players
	} else {
		
		my $textarea = {
			textarea    => $request->string('SYNC_ABOUT'),
		};
		$request->addResult('window', $textarea);
		$request->addResult("count", 0);
		$request->setStatusDone()
	}


}

sub endOfTrackSleepCommand {

	my $request = shift;
	my $client  = $request->client();

	if ($client->isPlaying()) {

		# calculate the time remaining in seconds 
		my $dur = $client->controller()->playingSongDuration();
		my $remaining = $dur - Slim::Player::Source::songTime($client);
		$client->execute( ['sleep', $remaining ] );
	} else {
		$request->client->showBriefly(
			{ 
			'jive' =>
				{
					'type'    => 'popupplay',
					'text'    => [ $request->string('NOTHING_CURRENTLY_PLAYING') ],
				},
			}
		);
	}
}


sub sleepSettingsQuery {

	main::INFOLOG && $log->info("Begin function");
	my $request = shift;
	my $client  = $request->client();
	my $val     = $client->currentSleepTime();
	my @menu;

	# Bug: 2151 some extra stuff to add the option to sleep after the current song.
	# first make sure we're playing, and its a valid song.
	my $remaining = 0;

	

	if ($val > 0) {
		my $now = Time::HiRes::time();
		my $then = $client->sleepTime();
		my $sleepyTime = int( ($then - $now) / 60 ) + 1;
		my $sleepString = $client->string( 'SLEEPING_IN_X_MINUTES', $sleepyTime );
		push @menu, { text => $sleepString, style => 'itemNoAction' };
		push @menu, sleepInXHash($client, $val, 0);
	}

	#bug 15675 - don't display 'end of song' option for radio streams
	if ($client->isPlaying() && $client->controller()->playingSongDuration()) {

		push @menu, {
			text    => $client->string('SLEEP_AT_END_OF_SONG'),
			actions => {
				go => {
					player => 0,
					cmd => [ 'jiveendoftracksleep' ],
				},
			},
			nextWindow => 'refresh',
			setSelectedIndex => 1,
		};
	}

	push @menu, sleepInXHash($client, $val, 15);
	push @menu, sleepInXHash($client, $val, 30);
	push @menu, sleepInXHash($client, $val, 45);
	push @menu, sleepInXHash($client, $val, 60);
	push @menu, sleepInXHash($client, $val, 90);

	sliceAndShip($request, $client, \@menu);
}

sub stereoXLQuery {

	main::INFOLOG && $log->info("Begin function");
	my $request        = shift;
	my $client         = $request->client();
	my $currentSetting = $client->stereoxl();
	my @strings = qw/ CHOICE_OFF LOW MEDIUM HIGH /;
	my @menu = ();
	for my $i (0..3) {
		my $xlSetting = {
			text    => $client->string($strings[$i]),
			radio   => ($i == $currentSetting) + 0,
			actions => {
				do => {
					player => 0,
					cmd    => [ 'playerpref', 'stereoxl', $i ],
				},
			},
		};
		push @menu, $xlSetting;
	}

	sliceAndShip($request, $client, \@menu);

	$request->setStatusDone();

}

sub lineOutQuery {

	main::INFOLOG && $log->info("Begin function");
	my $request        = shift;
	my $client         = $request->client();
	my $currentSetting = $prefs->client($client)->get('analogOutMode');
	my @strings = qw/ ANALOGOUTMODE_HEADPHONE ANALOGOUTMODE_SUBOUT ANALOGOUTMODE_ALWAYS_ON ANALOGOUTMODE_ALWAYS_OFF /;
	my @menu = ();
	for my $i (0..3) {
		my $lineOutSetting = {
			text    => $client->string($strings[$i]),
			radio   => ($i == $currentSetting) + 0,
			actions => {
				do => {
					player => 0,
					cmd    => [ 'playerpref', 'analogOutMode', $i ],
				},
			},
		};
		push @menu, $lineOutSetting;
	}

	sliceAndShip($request, $client, \@menu);

	$request->setStatusDone();

}


sub fixedVolumeSettingsQuery {

	main::INFOLOG && $log->info("Begin function");
	my $request        = shift;
	my $client         = $request->client();
	my $setting        = $request->getParam('cmd');


	my $digitalVolumeControl = $prefs->client($client)->get('digitalVolumeControl');
	my $currentSetting = 0;
	if ( ( defined $digitalVolumeControl && $digitalVolumeControl == 0 ) ) {
		$currentSetting = 1;
	}

	my @menu = ();
	my $checkbox = {
		text           => $client->string("FIXED_VOLUME_100"),
		checkbox       => $currentSetting,
		actions => {
			on => {
				player => 0,
				cmd    => [ 'playerpref', 'digitalVolumeControl', 0 ],
			},
			off => {
				player => 0,
				cmd    => [ 'playerpref', 'digitalVolumeControl', 1 ],
			},
		},
	};

	push @menu, $checkbox;

	sliceAndShip($request, $client, \@menu);

	$request->setStatusDone();
}


sub toneSettingsQuery {

	main::INFOLOG && $log->info("Begin function");
	my $request        = shift;
	my $client         = $request->client();
	my $tone           = $request->getParam('cmd');

	my $val     = $client->$tone();

	my @menu = ();
	my $slider = {
		slider  => 1,
		min     => -23 + 0,
		max     => 23,
		adjust  => 24, # slider currently doesn't like a slider starting at or below 0
		initial => $val,
		#help    => NO_HELP_STRING_YET,
		actions => {
			do => {
				player => 0,
				cmd    => [ 'playerpref', $tone ],
				params => {
					valtag => 'value',
				},
			},
		},
	};

	push @menu, $slider;

	sliceAndShip($request, $client, \@menu);

	$request->setStatusDone();
}

sub crossfadeSettingsQuery {

	main::INFOLOG && $log->info("Begin function");
	my $request = shift;
	my $client  = $request->client();
	my $val     = $prefs->client($client)->get('transitionType');
	my @strings = (
		'TRANSITION_NONE', 'TRANSITION_CROSSFADE', 
		'TRANSITION_FADE_IN', 'TRANSITION_FADE_OUT', 
		'TRANSITION_FADE_IN_OUT'
	);
	my @menu;

	push @menu, transitionHash($client, $val, $prefs, \@strings, 0);
	push @menu, transitionHash($client, $val, $prefs, \@strings, 1);
	push @menu, transitionHash($client, $val, $prefs, \@strings, 2);
	push @menu, transitionHash($client, $val, $prefs, \@strings, 3);
	push @menu, transitionHash($client, $val, $prefs, \@strings, 4);

	sliceAndShip($request, $client, \@menu);

}

sub replaygainSettingsQuery {

	main::INFOLOG && $log->info("Begin function");
	my $request = shift;
	my $client  = $request->client();
	my $val     = $prefs->client($client)->get('replayGainMode');
	my @strings = (
		'REPLAYGAIN_DISABLED', 'REPLAYGAIN_TRACK_GAIN', 
		'REPLAYGAIN_ALBUM_GAIN', 'REPLAYGAIN_SMART_GAIN'
	);
	my @menu;

	push @menu, replayGainHash($client, $val, $prefs, \@strings, 0);
	push @menu, replayGainHash($client, $val, $prefs, \@strings, 1);
	push @menu, replayGainHash($client, $val, $prefs, \@strings, 2);
	push @menu, replayGainHash($client, $val, $prefs, \@strings, 3);

	sliceAndShip($request, $client, \@menu);
}

sub playerSettingsMenu {

	main::INFOLOG && $log->info("Begin function");
	my $client = shift;
	my $batch = shift;

	my @menu = ();
	return \@menu unless $client && !$client->isa('Slim::Player::Disconnected');

 	push @menu, {
		text           => $client->string('AUDIO_SETTINGS'),
		id             => 'settingsAudio',
		node           => 'settings',
		isANode        => 1,
		weight         => 35,
	};
	
	# always add repeat
	push @menu, repeatSettings($client, 1);

	# always add shuffle
	push @menu, shuffleSettings($client, 1);

	# add alarm only if this is a slimproto player
	if ($client->isPlayer()) {
		push @menu, {
			text           => $client->string("ALARM"),
			id             => 'settingsAlarm',
			node           => 'settings',
			weight         => 29,
			actions        => {
				go => {
					cmd    => ['alarmsettings'],
					player => 0,
				},
			},
		};
	}

	# bass, if available
	if ( $client->maxBass() - $client->minBass() > 0 ) {
		push @menu, {
			text           => $client->string("BASS"),
			id             => 'settingsBass',
			node           => 'settingsAudio',
			iconStyle      => 'hm_settingsAudio',
			weight         => 10,
			actions        => {
				go => {
					cmd    => ['jivetonesettings'],
					player => 0,
					params => {
						'cmd' => 'bass',
					},
				},
			},
		};
	}

	# send an option for fixed 100% volume setting is sent for any player that has a digital out
	if ( $client->hasDigitalOut() ) {
		push @menu, {
			text           => $client->string("FIXED_VOLUME"),
			id             => 'settingsFixedVolume',
			iconStyle      => 'hm_settingsAudio',
			node           => 'settingsAudio',
			weight         => 100,
			actions        => {
				go => {
					cmd    => ['jivefixedvolumesettings'],
					player => 0,
				},
			},
		};
	}

	# treble, if available
	if ( $client->maxTreble() - $client->minTreble() > 0 ) {
		push @menu, {
			text           => $client->string("TREBLE"),
			id             => 'settingsTreble',
			node           => 'settingsAudio',
			iconStyle      => 'hm_settingsAudio',
			weight         => 20,
			actions        => {
				go => {
					cmd    => ['jivetonesettings'],
					player => 0,
					params => {
						'cmd' => 'treble',
					},
				},
			},
		};
	}

	# stereoXL, if available
	if ( $client->maxXL() - $client->minXL() ) {
		push @menu, {
			text           => $client->string("STEREOXL"),
			id             => 'settingsStereoXL',
			node           => 'settingsAudio',
			iconStyle      => 'hm_settingsAudio',
			weight         => 90,
			actions        => {
				go => {
					cmd    => ['jivestereoxl'],
					player => 0,
				},
			},
		};
	}

	# lineOut, if available
	if ( $client->hasHeadSubOut() ) {
		push @menu, {
			text           => $client->string("SETUP_ANALOGOUTMODE"),
			id             => 'settingsLineOut',
			node           => 'settingsAudio',
			iconStyle      => 'hm_settingsAudio',
			weight         => 80,
			actions        => {
				go => {
					cmd    => ['jivelineout'],
					player => 0,
				},
			},
		};
	}


	# sleep setting (always)
	push @menu, {
		text           => $client->string("SLEEP"),
		id             => 'settingsSleep',
		node           => 'settings',
		weight         => 65,
		actions        => {
			go => {
				cmd    => ['sleepsettings'],
				player => 0,
			},
		},
	};	

	# sync menu
	push @menu, syncMenuItem($client, 1);

	# information, always display
	push @menu, {
		text           => $client->string( 'JIVE_SQUEEZEBOX_INFORMATION' ),
		id             => 'settingsInformation',
		node           => 'advancedSettings',
		weight         => 100,
		actions        => {
				go =>	{
						cmd    => ['systeminfo', 'items'],
						params => {
							menu => 1
						}
					},
				},
	};

	# player name change, always display
	push @menu, {
		text           => $client->string('INFORMATION_PLAYER_NAME'),
		id             => 'settingsPlayerNameChange',
		node           => 'settings',
		weight         => 67,
		input          => {
			initialText  => $client->name(),
			len          => 1, # For those that want to name their player "X"
			allowedChars => $client->string('JIVE_ALLOWEDCHARS_WITHCAPS'),
			help         => {
				           text => $client->string('JIVE_CHANGEPLAYERNAME_HELP')
			},
			softbutton1  => $client->string('INSERT'),
			softbutton2  => $client->string('DELETE'),
		},
                actions        => {
                                do =>   {
                                                cmd    => ['name'],
                                                player => 0,
						params => {
							playername => '__INPUT__',
						},
                                        },
                                  },
	};


	# transition only for Sb2 and beyond (aka 'crossfade')
	if ($client->isa('Slim::Player::Squeezebox2')) {
		push @menu, {
			text           => $client->string("SETUP_TRANSITIONTYPE"),
			id             => 'settingsXfade',
			iconStyle      => 'hm_settingsAudio',
			node           => 'settingsAudio',
			weight         => 30,
			actions        => {
				go => {
					cmd    => ['crossfadesettings'],
					player => 0,
				},
			},
		};	
	}

	# replay gain (aka volume adjustment)
	if ($client->canDoReplayGain(0)) {
		push @menu, {
			text           => $client->string("REPLAYGAIN"),
			id             => 'settingsReplayGain',
			iconStyle      => 'hm_settingsAudio',
			node           => 'settingsAudio',
			weight         => 40,
			actions        => {
				  go => {
					cmd    => ['replaygainsettings'],
					player => 0,
				  },
			},
		};	
	}

	# brightness settings for players with displays 
	if ( $client->isPlayer() && !$client->display->isa('Slim::Display::NoDisplay') ) {
		push @menu, 
		{
			stringToken    => 'JIVE_PLAYER_DISPLAY_SETTINGS',
			id             => 'squeezeboxDisplaySettings',
			iconStyle      => 'hm_advancedSettings',
			isANode        => 1,
			node           => 'advancedSettings',
		},
		{
			text           => $client->string("PLAYER_BRIGHTNESS"),
			id             => 'settingsPlayerBrightness',
			iconStyle      => 'hm_settingsBrightness',
			node           => 'squeezeboxDisplaySettings',
			actions        => {
				  go => {
					cmd    => [ 'jiveplayerbrightnesssettings' ],
					player => 0,
				  },
			},
		},
	}

	# text size settings for players with graphical displays 
	if ( $client->isPlayer() && $client->display->isa('Slim::Display::Graphics') ) {
		push @menu, 
		{
			text           => $client->string("TEXTSIZE"),
			id             => 'settingsPlayerTextsize',
			node           => 'squeezeboxDisplaySettings',
			iconStyle      => 'hm_advancedSettings',
			actions        => {
				  go => {
					cmd    => [ 'jiveplayertextsettings', 'activeFont' ],
					player => 0,
				  },
			},
		},
		{
			text           => $client->string("OFFDISPLAYSIZE"),
			id             => 'settingsPlayerOffTextsize',
			node           => 'squeezeboxDisplaySettings',
			iconStyle      => 'hm_advancedSettings',
			actions        => {
				  go => {
					cmd    => [ 'jiveplayertextsettings', 'idleFont' ],
					player => 0,
				  },
			},
		},
	}
	
	# allow player linked to anonymous user accounts to be assigned to existing/new named user account
	if ( main::SLIM_SERVICE ) {
		push @menu, {
			text           => $client->string("CREATE_PIN"),
			actions => {
				go => {
					cmd    => [ 'get_pin', 0, 100 ],
					player => 0,
				},
			},
			id             => 'get_pin',
			node           => 'advancedSettings',
			weight         => 10,
			window         => {
				'icon-id'  => Slim::Networking::SqueezeNetwork->url( '/static/images/icons/icon_settings_generatepin.png', 'external' ),
			},
		};
		
		if ( $client->hasAnonymousAccount ) {
			push @menu, {
				text           => $client->string("SB_ACCOUNT"),
				actions => {
					go => {
						cmd    => [ 'register', 0, 100, 'service:SN', 'is_anon' ],
						player => 0,
					},
				},
				id             => 'registerPlayer',
				node           => 'developerSettings',
				weight         => 99,
				window         => {
					# XXX - need own icon
					'icon-id'  => Slim::Networking::SqueezeNetwork->url( '/static/images/icons/icon_settings_account.png', 'external' ),
				},
			};
		}
		else {
			_notifyJive([ { id => 'registerPlayer' } ], $client, 'remove');
		}
	}

	if ($batch) {
		return \@menu;
	} else {
		_notifyJive(\@menu, $client);
	}
}

sub syncMenuItem {
	my $client = shift;
	my $batch = shift;

	my $return = {
		text           => $client->string("SYNCHRONIZE"),
		id             => 'settingsSync',
		node           => 'settings',
		weight         => 70,
		actions        => {
			go => {
				cmd    => ['syncsettings'],
				player => 0,
			},
		},
	};

	if ($batch) {
		return $return;
	} else {
		_notifyJive( [ $return ], $client);
	}
}


sub _minAutoBrightness {
	my $current_setting = shift;
	my $string          = shift;

	my @brightness_settings;

	my $slider = {
		slider      => 1,
		min         => 1,
		max         => 5,
		initial     => $current_setting + 0,
		#help    => NO_HELP_STRING_YET,
		actions => {
			do => {
				player => 0,
				cmd    => [ 'playerpref', 'minAutoBrightness' ],
				params => {
					valtag => 'value',
				},
			},
		},
	};

	push @brightness_settings, $slider;

	my $return = { 
		text      => $string,
		count     => scalar(@brightness_settings),
		offset    => 0,
		item_loop => \@brightness_settings,
	};
	return $return;
}

sub _sensAutoBrightness {
	my $current_setting = shift;
	my $string          = shift;

	my @brightness_settings;

	my $slider = {
		slider      => 1,
		min         => 1,
		max         => 20,
		initial     => $current_setting + 0,
		#help    => NO_HELP_STRING_YET,
		actions => {
			do => {
				player => 0,
				cmd    => [ 'playerpref', 'sensAutoBrightness' ],
				params => {
					valtag => 'value',
				},
			},
		},
	};

	push @brightness_settings, $slider;

	my $return = { 
		text      => $string,
		count     => scalar(@brightness_settings),
		offset    => 0,
		item_loop => \@brightness_settings,
	};
	return $return;
}

sub playerBrightnessMenu {

	my $request    = shift;
	my $client     = $request->client();

	my @menu = ();

	# WHILE ON, WHILE OFF, IDLE
	my @options = (
		{
			string => 'SETUP_POWERONBRIGHTNESS_ABBR',
			pref   => 'powerOnBrightness',
		},
		{
			string => 'SETUP_POWEROFFBRIGHTNESS_ABBR',
			pref   => 'powerOffBrightness',
		},
		{
			string => 'SETUP_IDLEBRIGHTNESS_ABBR',
			pref   => 'idleBrightness',
		},
	);

	for my $href (@options) {
		my @radios = ();
		my $currentSetting = $prefs->client($client)->get($href->{pref});

		# assemble radio buttons based on what's available for that player
		my $hash  = $client->display->getBrightnessOptions();
		for my $setting (sort { $b <=> $a } keys %$hash) {
			my $item = {
				text => $hash->{$setting},
				radio => ($currentSetting == $setting) + 0,
				actions => {
					do    => {
						cmd    => [ 'playerpref', $href->{pref}, $setting ],
						player => 0,
					},
				},
			};
			push @radios, $item;
		}

		my $item = {
			text    => $client->string($href->{string}),
			count   => scalar(@radios),
			offset  => 0,
			item_loop => \@radios,
		};
		push @menu, $item;
	}

	if( $client->isa( 'Slim::Player::Boom')) {
		my $mab = _minAutoBrightness( $prefs->client( $client)->get( 'minAutoBrightness'), $client->string( 'SETUP_MINAUTOBRIGHTNESS'));
		push @menu, $mab;

		my $sab = _sensAutoBrightness( $prefs->client( $client)->get( 'sensAutoBrightness'), $client->string( 'SETUP_SENSAUTOBRIGHTNESS'));
		push @menu, $sab;
	}

	sliceAndShip($request, $client, \@menu);

	$request->setStatusDone();

}

sub playerTextMenu {

	my $request    = shift;
	my $client     = $request->client();
	my $whatFont   = $request->getParam('_whatFont');

	my @menu = ();

	my @fonts = ();
	my $i = 0;

	for my $font ( @{ $prefs->client($client)->get($whatFont) } ) {
		push @fonts, {
			name  => $client->string($font),
			value => $i++,
		};
	}

	my $currentSetting = $prefs->client($client)->get($whatFont . '_curr');
	for my $font (@fonts) {
		my $item = {
			text => $font->{name},
			radio => ($font->{value} == $currentSetting) + 0,
			actions => {
				do    => {
					cmd    => [ 'playerpref', $whatFont . '_curr', $font->{value} ],
					player => 0,
				},
			},
		};
		push @menu, $item;
	}

	sliceAndShip($request, $client, \@menu);

	$request->setStatusDone();

}

sub repeatSettings {
	my $client = shift;
	my $batch = shift;

	my $repeat_setting = Slim::Player::Playlist::repeat($client);
	my @repeat_strings = ('OFF', 'SONG', 'PLAYLIST_SHORT',);
	my @translated_repeat_strings = map { ucfirst($client->string($_)) } @repeat_strings;
	my @repeatChoiceActions;
	for my $i (0..$#repeat_strings) {
		push @repeatChoiceActions, 
		{
			player => 0,
			cmd    => ['playlist', 'repeat', "$i"],
		};
	}
	my $return = {
		text           => $client->string("REPEAT"),
		id             => 'settingsRepeat',
		node           => 'settings',
		weight         => 20,
		choiceStrings  => [ @translated_repeat_strings ],
		selectedIndex  => $repeat_setting + 1, # 1 is added to make it count like Lua
		actions        => {
			do => { 
				choices => [ 
					@repeatChoiceActions 
				], 
			},
		},
	};
	if ($batch) {
		return $return;
	} else {
		_notifyJive( [ $return ], $client);
	}
}

sub shuffleSettings {
	my $client = shift;
	my $batch = shift;

	my $shuffle_setting = Slim::Player::Playlist::shuffle($client);
	my @shuffle_strings = ( 'OFF', 'SONG', 'ALBUM',);
	my @translated_shuffle_strings = map { ucfirst($client->string($_)) } @shuffle_strings;
	my @shuffleChoiceActions;
	for my $i (0..$#shuffle_strings) {
		push @shuffleChoiceActions, 
		{
			player => 0,
			cmd => ['playlist', 'shuffle', "$i"],
		};
	}
	my $return = {
		text           => $client->string("SHUFFLE"),
		id             => 'settingsShuffle',
		node           => 'settings',
		selectedIndex  => $shuffle_setting + 1,
		weight         => 10,
		choiceStrings  => [ @translated_shuffle_strings ],
		actions        => {
			do => {
				choices => [
					@shuffleChoiceActions
				],
			},
		},
	};

	if ($batch) {
		return $return;
	} else {
		_notifyJive( [ $return ], $client);
	}
}

sub _howManyPlayersToSyncWith {
	my $client = shift;
	return 0 if $client->isa('Slim::Player::Disconnected');
	
	my @playerSyncList = Slim::Player::Client::clients();
	my $synchablePlayers = 0;
	
	# Restrict based on players with same userid on SN
	my $userid;
	if ( main::SLIM_SERVICE ) {
		$userid = $client->playerData->userid;
	}
	
	for my $player (@playerSyncList) {
		# skip ourself
		next if ($client eq $player);
		# we only sync slimproto devices
		next if (!$player->isPlayer());
		
		# On SN, only sync with players on the current account
		if ( main::SLIM_SERVICE ) {
			next if $userid == 1;
			next if $userid != $player->playerData->userid;
			
			# Skip players with old firmware
			if (
				( $player->model eq 'squeezebox2' && $player->revision < 82 )
				||
				( $player->model eq 'transporter' && $player->revision < 32 )
			) {
				next;
			}
		}
		
		$synchablePlayers++;
	}
	return $synchablePlayers;
}

sub _getPlayersToSyncWith() {
	my $client = shift;
	my @return = ();
	
	# Restrict based on players with same userid on SN
	my $userid;
	if ( main::SLIM_SERVICE ) {
		$userid = $client->playerData->userid;
	}
	
	# first add a descriptive line for this player
	push @return, {
		text  => $client->string('SYNC_X_TO', $client->name()),
		style => 'itemNoAction',
	};

	# come up with a list of players and/or sync groups to sync with
	# callback command also has to remove player from whatever it was previously synced to, if anything
	my $cnt      = 0;
	my @players  = Slim::Player::Client::clients();

	# construct the list
	my @syncList;
	my $currentlySyncedWith = 0;
	
	# the logic is a little tricky here...first make a pass at any sync groups that include $client
	if ($client->isSynced()) {
		if (_syncSNCheck($userid, $client)) {
			$syncList[$cnt] = {};
			$syncList[$cnt]->{'id'}           = $client->id();
			$syncList[$cnt]->{'name'}         = $client->syncedWithNames(0);
			$currentlySyncedWith                = $client->syncedWithNames(0);
			$syncList[$cnt]->{'isSyncedWith'} = 1;
			$cnt++;
		}
	}

	# then grab groups or players that are not currently synced with $client
        if (scalar(@players) > 0) {
		for my $eachclient (@players) {
			next if !$eachclient->isPlayer();
			next if $eachclient->isSyncedWith($client);
			next unless _syncSNCheck($userid, $eachclient);
			if ($eachclient->isSynced() && Slim::Player::Sync::isMaster($eachclient)) {
				$syncList[$cnt] = {};
				$syncList[$cnt]->{'id'}           = $eachclient->id();
				$syncList[$cnt]->{'name'}         = $eachclient->syncedWithNames(1);
				$syncList[$cnt]->{'isSyncedWith'} = 0;
				$cnt++;

			# then players which are not synced
			} elsif (! $eachclient->isSynced && $eachclient != $client ) {
				$syncList[$cnt] = {};
				$syncList[$cnt]->{'id'}           = $eachclient->id();
				$syncList[$cnt]->{'name'}         = $eachclient->name();
				$syncList[$cnt]->{'isSyncedWith'} = 0;
				$cnt++;

			}
		}
	}

	for my $syncOption (sort { $a->{name} cmp $b->{name} } @syncList) {
		push @return, { 
			text  => $syncOption->{name},
			radio => ($syncOption->{isSyncedWith} == 1) + 0,
			actions  => {
				do  => {
					player => 0,
					cmd    => [ 'jivesync' ],
					params => {
						syncWith              => $syncOption->{id},
						syncWithString        => $syncOption->{name},
						unsyncWith            => $currentlySyncedWith,
					},
				},
			},		
			nextWindow => 'refresh',
		};	
	}
	
	if ( $client->isSynced() ) {
		push @return, { 
			text  => $client->string('DO_NOT_SYNC'),
			radio => 0,
			actions  => {
				do  => {
					player => 0,
					cmd    => ['jivesync' ],
					params => {
						syncWith              => 0,
						syncWithString        => 0,
						unsyncWith            => $currentlySyncedWith,
					},
				},
			},		
			nextWindow => 'refresh',
		};	
	}

	return \@return;
}

sub _syncSNCheck {
	my ($userid, $player) = @_;
	# On SN, only sync with players on the current account
	if ( main::SLIM_SERVICE ) {
		return undef if $userid == 1;
		return undef if $userid != $player->playerData->userid;
		
		# Skip players with old firmware
		if (
			( $player->model eq 'squeezebox2' && $player->revision < 82 )
			||
			( $player->model eq 'transporter' && $player->revision < 32 )
		) {
			return undef;
		}
	}
	return 1;
}
	
sub jiveSyncCommand {
	my $request = shift;
	my $client  = $request->client();

	my $syncWith         = $request->getParam('syncWith');
	my $syncWithString   = $request->getParam('syncWithString');
	my $unsyncWith       = $request->getParam('unsyncWith') || undef;

	# first unsync if necessary
	my @messages = ();
	if ($unsyncWith) {
		$client->execute( [ 'sync', '-' ] );
		push @messages, $request->string('UNSYNCING_FROM', $unsyncWith);
	}
	# then sync if requested
	if ($syncWith) {
		my $otherClient = Slim::Player::Client::getClient($syncWith);
		$otherClient->execute( [ 'sync', $client->id ] );
			
		push @messages, $request->string('SYNCING_WITH', $syncWithString);
	}
	my $message = join("\n", @messages);

	$client->showBriefly(
		{ 'jive' =>
			{
				'type'    => 'popupplay',
				'text'    => [ $message ],
			},
		}
	);

	$request->setStatusDone();
}

sub playerPower {

	my $client = shift;
	my $batch = shift;

	return [] unless blessed($client)
		&& $client->isPlayer() && $client->canPowerOff();

	my $name  = $client->name();
	my $power = $client->power();
	my @return; 
	my ($text, $action);

	if ($power == 1) {
		$text = sprintf($client->string('JIVE_TURN_PLAYER_OFF'), $name);
		$action = 0;
	} else {
		$text = sprintf($client->string('JIVE_TURN_PLAYER_ON'), $name);
		$action = 1;
	}

	push @return, {
		text           => $text,
		id             => 'playerpower',
		node           => 'home',
		weight         => 100,
		actions        => {
			do  => {
				player => 0,
				cmd    => ['power', $action],
				},
			},
	};

	if ($batch) {
		return \@return;
	} else {
		# send player power info by notification
		_notifyJive(\@return, $client);
	}

}

sub sleepInXHash {
	main::INFOLOG && $log->info("Begin function");
	my ($client, $val, $sleepTime) = @_;
	my $text = $sleepTime == 0 ? 
		$client->string("SLEEP_CANCEL") :
		$client->string('X_MINUTES', $sleepTime);
	my %return = ( 
		text    => $text,
		actions => {
			go => {
				player => 0,
				cmd => ['sleep', $sleepTime*60 ],
			},
		},
		nextWindow => 'refresh',
		setSelectedIndex => '1',
	);
	return \%return;
}

sub transitionHash {
	
	my ($client, $val, $prefs, $strings, $thisValue) = @_;
	my %return = (
		text    => $client->string($strings->[$thisValue]),
		radio	=> ($val == $thisValue) + 0, # 0 is added to force the data type to number
		actions => {
			do => {
				player => 0,
				cmd => ['playerpref', 'transitionType', "$thisValue" ],
			},
		},
	);
	return \%return;
}

sub replayGainHash {
	
	my ($client, $val, $prefs, $strings, $thisValue) = @_;
	my %return = (
		text    => $client->string($strings->[$thisValue]),
		radio	=> ($val == $thisValue) + 0, # 0 is added to force the data type to number
		actions => {
			do => {
				player => 0,
				cmd => ['playerpref', 'replayGainMode', "$thisValue"],
			},
		},
	);
	return \%return;
}


sub jivePlaylistsCommand {

	main::INFOLOG && $log->info("Begin function");
	my $request    = shift;
	my $client     = $request->client || return;
	my $title      = $request->getParam('title');
	my $url        = $request->getParam('url');
	my $command    = $request->getParam('_cmd');
	my $playlistID = $request->getParam('playlist_id');
	my $token      = uc($command); 
	my @delete_menu= (
		{
			text    => $client->string('CANCEL'),
			actions => {
				go => {
					player => 0,
					cmd    => [ 'jiveblankcommand' ],
				},
			},
			nextWindow => 'parent',
		}
	);
	my $actionItem = {
		text    => $client->string($token) . ' ' . $title,
		actions => {
			go => {
				player => 0,
				cmd    => ['playlists', 'delete'],
				params => {
					playlist_id    => $playlistID,
					title          => $title,
					url            => $url,
				},
			},
		},
		nextWindow => 'grandparent',
	};
	push @delete_menu, $actionItem;

	$request->addResult('offset', 0);
	$request->addResult('count', 2);
	$request->addResult('item_loop', \@delete_menu);

	$request->setStatusDone();

}

sub jiveAlarmCommand {
	main::INFOLOG && $log->info("Begin function");

	my $request    = shift;
	my $client     = $request->client || return;

	# this command can issue either a snooze or a cancel
	my $snooze      = $request->getParam('snooze') ? 1 : undef;
	my $stop        = $request->getParam('stop')   ? 1 : undef;
	my $fadein      = $request->getParam('fadein');

	my $alarm       = Slim::Utils::Alarm->getCurrentAlarm($client);

	if ( defined($alarm) ) {
		if ( defined($snooze) ) {
			$alarm->snooze();
		} elsif ( defined ($stop) ) {
			$alarm->stop();
		}
	}

	# a fadein:1 tag needs to set a clientpref for alarmfadeseconds
	if ( defined($fadein) ) {
		$log->error('Fade in alarm being set to ', $fadein);
		$prefs->client($client)->set('alarmfadeseconds', $fadein);
	}
	$request->setStatusDone();
}


sub jivePresetsMenu {
	main::INFOLOG && $log->info("Begin function");
	my $request = shift;
	my $client  = $request->client || shift;

	my $index    = $request->getParam('_index');
	my $quantity = $request->getParam('_quantity');

	my $title   = $request->getParam('title');
	my $url     = $request->getParam('url');
	my $type    = $request->getParam('type');
	my $icon    = $request->getParam('icon');
	my $preset = $request->getParam('key');
	my $parser = $request->getParam('parser');
	my $action = 'grandparent';

	# if playlist_index is sent, that's for the current NP track, derive everything you need from it
	my $playlist_index = $request->getParam('playlist_index');
	if ( defined($playlist_index) ) {
		my $song = Slim::Player::Playlist::song( $client, $playlist_index );
		$url     = $song->url;
		$type    = 'audio';
		$title   = $song->title;
	}

	# preset needs to be saved as either a playlist or default to audio
	if ( defined($type) && $type ne 'playlist' ) {
		$type = 'audio';
	}
	if ( ! defined $title || ! defined $url ) {
		$request->setStatusBadDispatch();
		return;
	}

	my $presets = $prefs->client($client)->get('presets');
	my @presets_menu;
	for my $preset (0..5) {
		my $jive_preset = $preset + 1;
		# is this preset currently set?
		my $set = ref($presets) eq 'ARRAY' && defined $presets->[$preset] ? 1 : 0;
		my $item;

		if ($set) {
			my $currentPreset = $presets->[$preset]->{'text'};
			$log->error($currentPreset);
			$item = {
				text    => $request->string('JIVE_SET_PRESET_X', $jive_preset),
				count   => 2,
				offset   => 0,
				isContextMenu => 1,
				item_loop => [
					{
						text    => $client->string('CANCEL'),
						actions => {
							go => {
								player => 0,
								cmd    => [ 'jiveblankcommand' ],
							},
						},
						nextWindow => 'parent',
					},
					{
						text    => $client->string('JIVE_OVERWRITE_PRESET_X', $currentPreset),
						actions => {
							go => {
								player => 0,
								cmd    => [ 'jivefavorites', 'set_preset', ],
								params => {
									key	=> $jive_preset,
									favorites_url	=> $url,
									favorites_title	=> $title,
									favorites_type	=> $type,
									parser	=> $parser,
								},
							},
						},
						nextWindow => 'presets',
					},

				],
			};
		} else {
			$item = {
				text    => $request->string('JIVE_SET_PRESET_X', $jive_preset),
				actions => {
					go => {
						player => 0,
						cmd    => [ 'jivefavorites', 'set_preset', ],
						params => {
							key	=> $jive_preset,
							favorites_url	=> $url,
							favorites_title	=> $title,
							favorites_type	=> $type,
							parser	=> $parser,
						},
					},
				},
				nextWindow => 'presets',
			};
		}
		push @presets_menu, $item;
	}

	$request->addResult('offset', 0);
	$request->addResult('count', scalar(@presets_menu));
	$request->addResult('item_loop', \@presets_menu);
	$request->setStatusDone();
		
} 


sub jiveFavoritesCommand {

	main::INFOLOG && $log->info("Begin function");
	my $request = shift;
	my $client  = $request->client || shift;
	my $title   = $request->getParam('title');
	my $url     = $request->getParam('url');
	my $type    = $request->getParam('type');
	my $icon    = $request->getParam('icon');
	my $parser  = $request->getParam('parser');
	my $command = $request->getParam('_cmd');
	my $token   = uc($command); # either ADD or DELETE
	my $action = 'grandparent';
	my $favIndex = defined($request->getParam('item_id'))? $request->getParam('item_id') : undef;

	if ( $command eq 'set_preset' ) {
		# XXX: why do we use a favorites_ prefix here but not above?
		my $preset = $request->getParam('key');
		my $title  = $request->getParam('favorites_title');
		my $url    = $request->getParam('favorites_url');
		my $type   = $request->getParam('favorites_type');

		# if playlist_index is sent, that's for the current NP track, derive everything you need from it
		my $playlist_index = $request->getParam('playlist_index');
		if ( defined($playlist_index) ) {
			my $song = Slim::Player::Playlist::song( $client, $playlist_index );
			$url     = $song->url;
			$type    = 'audio';
			$title   = $song->title;
		}

		# favorite needs to be saved as either a playlist or default to audio
		if ( defined($type) && $type ne 'playlist' ) {
			$type = 'audio';
		}
		if ( ! defined $title || ! defined $url ) {
			$request->setStatusBadDispatch();
			return;
		}
		
		$client->setPreset( {
			slot   => $preset,
			URL    => $url,
			text   => $title,
			type   => $type,
			parser => $parser,
		} );

		$client->showBriefly({
			jive => {
				type     => 'popupplay',
				text     => [ $client->string('PRESET_ADDING', $preset), $title ],
			},
		});
	} else {

		my @favorites_menu = (
			{
				text    => $client->string('CANCEL'),
				actions => {
					go => {
						player => 0,
						cmd    => [ 'jiveblankcommand' ],
					},
				},
				nextWindow => 'parent',
			}
		);
		my $actionItem = {
			text    => $client->string($token) . ' ' . $title,
			actions => {
				go => {
					player => 0,
					cmd    => ['favorites', $command ],
					params => {
						title  => $title,
						url    => $url,
						type   => $type,
						parser => $parser,
						icon   => $icon,
					},
				},
			},
			nextWindow => $action,
		};
		$actionItem->{'actions'}{'go'}{'params'}{'icon'} = $icon if $icon;
		$actionItem->{'actions'}{'go'}{'params'}{'item_id'} = $favIndex if defined($favIndex);
		push @favorites_menu, $actionItem;
	
		$request->addResult('offset', 0);
		$request->addResult('count', 2);
		$request->addResult('item_loop', \@favorites_menu);
	}
	
	
	$request->setStatusDone();
		
} 

sub jiveDummyCommand {
	return;
}


1;
