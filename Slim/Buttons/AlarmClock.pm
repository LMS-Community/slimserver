# AlarmClock.pm by Kevin Deane-Freeman March 2003
# Adapted from code by Lukas Hinsch
# Updated by Dean Blackketter
#
# This code is derived from code with the following copyright message:
#
# SqueezeCenter Copyright 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

=head1 NAME

Slim::Buttons::AlarmClock

=head1 DESCRIPTION

L<Slim::Buttons::AlarmClock> is a module for setting and triggering an
alarm clock function for SqueezeCenter..

=cut

package Slim::Buttons::AlarmClock;

use strict;

use Slim::Player::Playlist;
use Slim::Buttons::Common;
use Slim::Utils::DateTime;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;
use Slim::Utils::Log;

use Scalar::Util qw(blessed);
use Time::HiRes;

#use Data::Dumper; # TODO: Don't go live with this in!

my $prefs = preferences('server');
my $log = logger('player.alarmclock');

my $interval    = 1;  # check every x seconds
my $FADESECONDS = 20; # fade-in of 20 seconds
my $alarmScreensaver = 'SCREENSAVER.datetime';

my %menuSelection;
our %specialPlaylists;
our %menuParams = ();
our %functions = ();

my @defaultAlarmChoices = (
	'ALARM_SET',
	'ALARM_SELECT_PLAYLIST',
	'ALARM_SET_VOLUME',
	'ALARM_OFF',
	'ALARM_WEEKDAYS',
);

# get current weekday, 0 is every day 1-7 is Monday to Sunday respectively
sub weekDay {
	my $client = shift;
	
	return unless $client;
	
	my $day = $client->modeParam('day');

	if (defined $day) {
		return ${$day};
	} else {
		return 0;
	}
}

sub useWeekday {
	my $client = shift;
	my $pref = shift;

	return ref $prefs->client($client)->get($pref) ? weekDay($client) : undef;
}

sub playlistName {
	return exists $specialPlaylists{$_[1]} 
			? $_[0]->string($_[1]) 
			: Slim::Music::Info::standardTitle($_[0],$_[1]->url);
}

=head1 METHODS

=head2 init( )

This method registers the alarm clock mode with SqueezeCenter, and defines the functions for interaction
 while setting the alarm clock.

Generally only called from L<Slim::Buttons::Common>

=cut

# some initialization code, adding modes for this module
sub init {

	%functions = (
		'play' => sub  {
			my ($client,$funct,$functarg) = @_;
			
			# nothing to be done, so play is same as right
			alarmExitHandler($client,'RIGHT');
		},

		'add'  => sub  {
			my ($client,$funct,$functarg) = @_;
			
			# nothing to be done, so add is same as right
			alarmExitHandler($client,'RIGHT');
		},
	);

	Slim::Buttons::Common::addMode('alarm', \%functions, \&setMode);
	
	Slim::Buttons::Home::addSubMenu('SETTINGS', 'ALARM', {
		'useMode'   => 'alarm',
		'condition' => sub { 1 },
	});
	
	Slim::Buttons::Home::addMenuOption('ALARM', {
		'useMode'   => 'alarm',
		'condition' => sub { 1 },
	});

	setTimer();

	# add option for the current playlist
	$specialPlaylists{'CURRENT_PLAYLIST'} = 0;
	
	%menuParams = (

		'alarm' => {
			'listRef'        => \@defaultAlarmChoices,
			'externRef'      => sub {
				my ($client, $value) = @_;
				
				# If the current menu item is alarm on/off, show the current on/off state otherwise just
				# return the appropriate string for that menu item
				if ($prefs->client($client)->get('alarm')->[ weekDay($client) ] && $value eq 'ALARM_OFF') {
					return $client->string('ALARM_ON');
				
				} else {
					return $client->string($value);
				}
			},
			'externRefArgs'  => 'CV',
			'header'         => \&alarmHeader,
			'headerArgs'     => 'CI',
			'stringHeader'   => 1,
			'headerAddCount' => 1,
			'callback'       => \&alarmExitHandler,
			'overlayRef'     => \&overlayFunc,
			'overlayRefArgs' => 'CV',
		},
		
		'alarm/ALARM_OFF'  => {
			'useMode'      => 'boolean',
			'pref'         => 'alarm',
			'initialValue' => sub { $prefs->client($_[0])->get('alarm')->[ weekDay($_[0]) ] },
			'onchange'     => sub { setTimer($_[0]) },
			'onChangeArgs' => 'C',
		},

		'alarm/ALARM_FADE' => {
			'useMode'      => 'boolean',
			'pref'         => 'alarmfadeseconds',
			'initialValue' => sub { $prefs->client($_[0])->get('alarmfadeseconds') },
		},
		
		'alarm/ALARM_SET'  => {
			'useMode'      => 'INPUT.Time',
			'header'       => 'ALARM_SET',
			'stringHeader' => 1,
			'initialValue' => sub { $prefs->client($_[0])->get('alarmtime')->[ weekDay($_[0]) ] },
			'cursorPos'    => 0,
			'callback'     => \&exitSetHandler,
		},

		'alarm/ALARM_SET_VOLUME' => {
			'useMode'       => 'INPUT.Bar',
			'header'        => sub {
				($_[0]->linesPerScreen == 1) ? 
				$_[0]->string('ALARM_SET_VOLUME_SHORT') : 
				$_[0]->string('ALARM_SET_VOLUME');
			},
			'stringHeader' => 1,
			'headerArgs'   => 'C',
			'increment'    => 1,
			'headerValue'  => sub { return $_[0]->volumeString($_[1]) },
			'onChange'     => sub { 
				my ($client, $val) = @_;
				my $volumes = $prefs->client($client)->get('alarmvolume');
				$volumes->[ weekDay($client) ] = $volumes->[ weekDay($client) ] + $val;
				$prefs->client($client)->set('alarmvolume', $volumes);
			},
			'initialValue' => sub { $prefs->client($_[0])->get('alarmvolume')->[ weekDay($_[0]) ] },
		},

		'alarm/ALARM_SELECT_PLAYLIST' => {
			'useMode'        => 'INPUT.Choice',
			'listRef'        => undef,
			'header'         => '{ALARM_SELECT_PLAYLIST} {count}',
			'stringHeader'   => 1,
			'name'           => sub { playlistName(@_) },
			'onRight'        => sub { 
				my ( $client, $item ) = @_;

				my $playlist = $prefs->client($client)->get('alarmplaylist');
				$playlist->[ weekDay($client) ] = exists $specialPlaylists{$item} ? $item : $item->url;
				$prefs->client($client)->set('alarmplaylist', $playlist);

				$client->update();
			},
			'onPlay'        => sub { 
				my ( $client, $item ) = @_;

				my $playlist = $prefs->client($client)->get('alarmplaylist');
				$playlist->[ weekDay($client) ] = exists $specialPlaylists{$item} ? $item : $item->url;
				$prefs->client($client)->set('alarmplaylist', $playlist);

				$client->update();
			},
			'onAdd'        => sub { 
				my ( $client, $item ) = @_;

				my $playlist = $prefs->client($client)->get('alarmplaylist');
				$playlist->[ weekDay($client) ] = exists $specialPlaylists{$item} ? $item : $item->url;
				$prefs->client($client)->set('alarmplaylist', $playlist);

				$client->update();
			},
			'initialValue'   => sub { $prefs->client($_[0])->get('alarmplaylist')->[ weekDay($_[0]) ]; },
			'overlayRef'     => sub {
				my ( $client, $item ) = @_;
				my $overlay;
				
				$item = ( ref $item ) ? $item->url : $item;

				if ( $item eq $prefs->client($client)->get('alarmplaylist')->[ weekDay($_[0]) ] ) {
					$overlay = Slim::Buttons::Common::radioButtonOverlay( $client, 1 );
				} else {
					$overlay = Slim::Buttons::Common::radioButtonOverlay( $client, 0 );
				}
				
				return [undef, $overlay];
			},
		},
		
		'alarm/ALARM_WEEKDAYS' => {
			'useMode'          => 'INPUT.List',
			'listRef'          => [ 0..7 ],
			'externRef'        => sub { 
				my $client    = shift;
				my $dayOfWeek = shift;

				my $dowString = $client->string("ALARM_DAY$dayOfWeek");

				if ($prefs->client($client)->get('alarm')->[ $dayOfWeek ]) {

					$dowString .= sprintf(" (%s)",
						Slim::Buttons::Input::Time::timeString( 
							$client,
							Slim::Utils::DateTime::timeDigits(
								$prefs->client($client)->get('alarmtime')->[ $dayOfWeek ]
							),
							-1  # hide the cursor
						) 
					);
				
				} else {
					$dowString .= sprintf(" (%s)", $client->string('MCOFF'));
				}

				return $dowString;
			},
			'externRefArgs'    => 'CI',
			'header'           => 'ALARM_WEEKDAYS',
			'headerAddCount'   => 1,
			'stringHeader'     => 1,
			'callback'         => \&weekdayExitHandler,
			'overlayRef'       => \&weekdayOverlay,
			'overlayRefArgs'   => 'CI',
		},
	);
	
}

sub addSpecialPlaylist {
	my $class = shift;
	my $name  = shift;
	my $value = shift;

	$specialPlaylists{$name} = $value;
}

# the routines
sub setMode {
	my $client = shift;
	my $method = shift;

	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}

	my $weekDay = weekDay($client);
	
	my %params = %{$menuParams{'alarm'}};
	
	my @alarmChoices = @defaultAlarmChoices;
	
	# entering alarm settings, add the fade timing global pref unless already there
	if (!defined $client->modeParam('day')) {
		push @alarmChoices, 'ALARM_FADE' unless $alarmChoices[-1] eq 'ALARM_FADE';
	
	# remove for weekday pref menus
	} elsif( $alarmChoices[-1] eq 'ALARM_FADE') {
		pop @alarmChoices;

	} elsif ($alarmChoices[-1] eq 'ALARM_WEEKDAYS') {
		pop @alarmChoices;
	}

	$params{'listRef'} = \@alarmChoices;
	$params{'day'} = $client->modeParam('day');
	
	Slim::Buttons::Common::pushMode($client,'INPUT.List',\%params);
}

# on exiting the weekday list, this handler will deal the exit left to the previous 
# menu, or right into that days setting options list.
sub weekdayExitHandler {
	my ($client, $exittype) = @_;

	$exittype = uc($exittype);

	if ($exittype eq 'LEFT') {

		Slim::Buttons::Common::popModeRight($client);

	} elsif ($exittype eq 'RIGHT') {

		my %params = (
			'day' => $client->modeParam('valueRef'),
		);
		
		if (${$client->modeParam('valueRef')}) {
			Slim::Buttons::Common::pushModeLeft($client,'alarm', \%params);

		} else {
			$client->bumpRight();
		}
	}
}

sub weekdayOverlay {
	my $client = shift;
	my $index  = shift;

	if ($index) {
		return (undef,$client->symbols('rightarrow'));
	} else {
		return;
	}
};


# handler for exiting the time setting input mode.  stores the time as a pref.
sub exitSetHandler {
	my ($client, $exittype) = @_;

	$exittype = uc($exittype);

	if ($exittype eq 'LEFT' || $exittype eq 'RIGHT') {

		my $times = $prefs->client($client)->get('alarmtime');
		$times->[ weekDay($client) ] = ${$client->modeParam('valueRef')};
		$prefs->client($client)->set('alarmtime', $times);
		$client->showBriefly({line=>[$client->string('ALARM_SAVING')]});

		Slim::Buttons::Common::popMode($client);

	}
}

# handler for controlling the exit from the main alarm menu
# fill in live params and track selected day
sub alarmExitHandler {
	my ($client,$exittype) = @_;
	$exittype = uc($exittype);

	if ($exittype eq 'LEFT') {
		Slim::Buttons::Common::popModeRight($client);
		

	} elsif ($exittype eq 'RIGHT') {
		my $nextmenu = 'alarm/' . $client->modeParam('listRef')->[$client->modeParam('listIndex')];

		if (exists($menuParams{$nextmenu})) {
			my %nextParams = %{$menuParams{$nextmenu}};
			
			if ($nextParams{'useMode'} eq 'boolean') {

				if ($nextParams{'pref'}) {

					my $newval;

					if (ref($nextParams{'initialValue'}) eq 'CODE' && $nextParams{'initialValue'}->($client)) {
						$newval = 0;
					} else {
						$newval = 1;
					}
					
					my $tmp = $prefs->client($client)->get($nextParams{'pref'});
					if (ref $tmp) {
						$tmp->[ useWeekday($client,$nextParams{'pref'}) ] = $newval;
						$prefs->client($client)->set($nextParams{'pref'}, $tmp);
					} else {
						$prefs->client($client)->set($nextParams{'pref'}, $newval);
					}
				}
				
				if (ref($nextParams{'onChange'}) eq 'CODE') {
					$nextParams{'onChange'}->($client);
				}
				
				$client->update();

				return;
				
			} elsif ($nextParams{'useMode'} =~ /INPUT\./ && exists($nextParams{'initialValue'})) {
				
				if ($nextmenu eq 'alarm/ALARM_SELECT_PLAYLIST') {

					my @playlists = Slim::Schema->rs('Playlist')->getPlaylists;
					
					# This is ugly, add a value item to each playlist object so INPUT.Choice remembers selection
					for my $playlist (@playlists) {
						$playlist->{'value'} = $playlist->url;
					}

					$nextParams{'listRef'} = [ @playlists, keys %specialPlaylists];
				}
				
				#set up valueRef for current pref
				my $value;

				if (ref($nextParams{'initialValue'}) eq 'CODE') {
					$value = $nextParams{'initialValue'}->($client);
					
				} else {
					$value = $prefs->client($client)->get($nextParams{'initialValue'});
				}

				$nextParams{'valueRef'} = \$value;
				
				if ($nextmenu eq 'alarm/ALARM_WEEKDAYS') {
					my $day = 0;

					$nextParams{'valueRef'} = \$day;
				}
			}
			
			$nextParams{'day'} = \weekDay($client),

			Slim::Buttons::Common::pushModeLeft(
				$client,
				$nextParams{'useMode'},
				\%nextParams
			);

		} else {
			$client->bumpRight();
		}
	}
}

sub setTimer {
	# timer to check alarms on an interval
	Slim::Utils::Timers::setTimer(undef, Time::HiRes::time() + $interval, \&checkAlarms);
}

=head2 checkAlarms ( )

This function periodically compares the alarm clock preferences for each client. If a match is found,
then the alarm is triggered to match the user specified preferences for playlist, and volume.  If the preferred
playlist fails, the alarm will attempt to play the current playlist (if any) as a failsafe.  Two seconds after the
trigger, the server will display a short visual message to indicate that an alarm has begun the playback.

=cut

sub checkAlarms {
	my ($sec,$min,$hour,$mday,$mon,$year,$wday) = localtime(time);

	my $time = $hour * 60 * 60 + $min * 60;
	
	# bug 2300: prefs refers to sunday as day 7, so correct this here for localtime
	$wday = 7 if !$wday;
	
	# once we've reached the beginning of a minute, only check every 60s
	if ($sec == 0) {
		$interval = 60;
	}

	# if we end up falling behind, go back to checking each second
	if ($sec >= 50) {
		$interval = 1;
	}

	foreach my $client (Slim::Player::Client::clients()) {

		for my $day (0, $wday) {

			# don't bother for inactive alarms.
			next unless $prefs->client($client)->get('alarm')->[ $day ];

			my $alarmtime = $prefs->client($client)->get('alarmtime')->[ $day ] || next;

			if ($time == ($alarmtime + 60)) {

				# alarm is done, so reset to find the beginning of a minute
				$interval = 1;
			}

			if ($time == $alarmtime) {
				# Sound an Alarm (HWV 63)
				$log->debug('Alarm starting');
				
				my $now = Time::HiRes::time(); 
				# Bug 7818, count this as user interaction, even though it isn't really
				$client->lastActivityTime($now);

				$client->alarmActive($now);

				my $request = $client->execute(['stop']);
				$request->source('ALARM');
				$request = $client->execute(['power', 1]);
				$request->source('ALARM');

				pushDateTime($client);

				# Set analogOutMode to subwoofer to force output through main speakers even if headphones are plugged in
				$client->can('setAnalogOutMode') && $client->setAnalogOutMode(1);
				
				my $volume = $prefs->client($client)->get('alarmvolume')->[ $day ];
				my $currentVolume = $client->volume;
				$log->debug("Current vol: $currentVolume Alarm vol: $volume");

				if (defined ($volume) && $currentVolume != $volume) {
					$log->debug("Changing volume from $currentVolume to $volume");
					$client->volume($volume);
				}

				# fade volume over 20s if enabled.
				if ( $prefs->client($client)->get('alarmfadeseconds') ) {
					$log->debug('Fading volume');
					$client->fade_volume( $FADESECONDS );
				}

				my $playlist = $prefs->client($client)->get('alarmplaylist')->[ $day ];
				
				# if a random playlist option is chosen, make sure that the plugin is installed and enabled.
				# TODO: This doesn't seem to check!
				if ($specialPlaylists{$playlist}) {
					$log->debug('Playing random mix');
					
					# Random mix will turn player on
					Slim::Plugin::RandomPlay::Plugin::playRandom($client,$specialPlaylists{$playlist});
					
				# handle a chosen playlist that is not the current playlist.
				# TODO: How do we get here?
				} elsif (defined $playlist && $playlist ne 'CURRENT_PLAYLIST') {
					$log->debug('Playing playlist');

					Slim::Buttons::Block::block($client, alarmLines($client));
					
					my $playlistObj = Slim::Schema->rs('Playlist')->objectForUrl({
						'url' => $playlist,
					});

					if (blessed($playlistObj) && $playlistObj->can('id')) {

						$request = $client->execute(['playlist', 'playtracks', 'playlist=' . $playlistObj->id], \&playDone, [$client]);
						$request->source('ALARM');
						setTimer();
						return;
					
					#if all else fails, just try to play the current playlist.
					} else {
						$log->debug('Can\'t use playlist obj.  Falling back to current playlist');
						# no object, so try to play the current playlist
						$request = $client->execute(['play'], \&playDone, [$client]);
						$request->source('ALARM');
					}

				#fallback to current playlist if all else fails.
				} else {
					$log->debug('Using current playlist');

					$request = $client->execute(['play']);
					$request->source('ALARM');

				}
				
				# slight delay for things to load up before showing the temporary alarm lines.
				Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + 2, \&visibleAlarm, $client);
				setAlarmSubscription($client);
			}
		}
	}

	setTimer();
}

# on a playlist load, call this after the playlist loading is complete to set the timer for the visible alert 2 seconds in the future.
sub playDone {
	my $client = shift;

	Slim::Buttons::Block::unblock($client);

	# show the alarm screen after a couple of seconds when the song has started playing and the display is updated
	Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + 2, \&visibleAlarm, $client);	
}

# Called when the alarm is no longer active.  An alarm ceases to be active when user activity occurs after the alarm
# begins.  When an alarm is active, the screensaver and active outputs can change.  This resets such changes.
sub alarmEnd {
	my $request = shift;

	my $client = $request->client;

	$log->debug(sub {'alarmEnd called with request: ' . $request->getRequestString});

	# Don't respond to requests that we created ourselves
	my $source = $request->source;
	if ($source && ($source eq 'ALARM' || $source eq 'PLUGIN_RANDOMPLAY')) {
		$log->debug('Ignoring self-created request');
		return;
	}

	# When snoozing we should end on 'playlist jump' but can only filter on playlist
	if ($request->getRequest(0) eq 'playlist' && $request->getRequest(1) ne 'jump') {
		$log->debug('Ignoring playlist command that isn\'t jump');
		return;
	}

	$log->debug('Stopping alarm');

	Slim::Control::Request::unsubscribe(\&alarmEnd, $client);

	popDateTime($client);

	# Restore analogOutMode to previous setting
	$client->can('setAnalogOutMode') && $client->setAnalogOutMode();

	$client->alarmActive(undef);
	if ($client->snoozeActive) {
		$log->debug('Stopping snooze');
		$client->snoozeActive(undef);
		Slim::Utils::Timers::killTimers($client, \&snoozeEnd);
		$client->showBriefly({line=>[$client->string('ALARM_SNOOZE_STOPPED')]});
	} else {
		$client->showBriefly({line=>[$client->string('ALARM_STOPPED')]});
	}
}

sub snooze {
	my $client = shift;

	$log->debug('Snooze called');
	# don't snooze again if we're already snoozing.
	if ($client->snoozeActive) {
		$log->debug('Already snoozing');
	} else {
		my $request = $client->execute(['pause', 1]);
		$request->source('ALARM');

		my $time = Time::HiRes::time();
		$client->snoozeActive($time);

		# set up 9m snooze
		Slim::Utils::Timers::setTimer($client, $time + (9 * 60), \&snoozeEnd);

		setSnoozeSubscription($client);

		$client->showBriefly({line=>[$client->string('ALARM_SNOOZE')]});
	}

	if ($client->alarmActive) {
		pushDateTime($client);
	}
}

sub snoozeEnd {
	my $client = shift;
	
	$log->debug('Snooze ending');

	$client->snoozeActive(undef);
	
	my $request = $client->execute(['pause', 0]);
	$request->source('ALARM');

	# TODO: Bring in line with other notifications
	$client->showBriefly({
		'line'     => [$client->string('ALARM_NOW_PLAYING'),$client->string('ALARM_WAKEUP')],
		'duration' => 3,
		'block'    => 1,
	});
	
	Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + 2, \&visibleAlarm, $client);

	setAlarmSubscription($client);
}

# temporary lines shown after alarm triggers, just to let the user know why the music started.
sub alarmLines {
	my $client = shift;

	my $line1 = $client->string('ALARM_NOW_PLAYING');
	my $line2 = '';

	my $playlist = $prefs->client($client)->get('alarmplaylist')->[ weekDay($client) ];
	
	# special playlists, just show the localised string for the option
	if (exists $specialPlaylists{$playlist}) {
		$line2 = $client->string($playlist);
		
	} else {

		# show the standard title for the loaded playlist item
		$line2 = Slim::Music::Info::standardTitle($client, $playlist);
	}

	return {
		'line' => [ $line1, $line2 ]
	};
}

sub visibleAlarm {
	my $client = shift;

	my $showBrieflyDur = 30;
	# Datetime screensaver already provides alarm info so don't need a long showBriefly
	if (Slim::Buttons::Common::mode($client) eq $alarmScreensaver) {
		$showBrieflyDur = 3;
	}
	$client->showBriefly(alarmLines($client), $showBrieflyDur);
}

# Push into the datetime screensaver if it's available
sub pushDateTime {
	my $client = shift;

	my $currentMode = Slim::Buttons::Common::mode($client);

	$log->debug("Attempting to push alarm screensaver.  Current mode: $currentMode");
	if (Slim::Buttons::Common::validMode($alarmScreensaver) && $currentMode ne $alarmScreensaver) {
		$log->debug('Pushing alarm screensaver');
		Slim::Buttons::Common::pushMode($client, $alarmScreensaver);
		$client->update();
	}
}

# Pop out of datetime screensaver if it's being displayed
sub popDateTime {
	my $client = shift;

	my $currentMode = Slim::Buttons::Common::mode($client);
	$log->debug("Attempting to pop alarm screensaver.  Current mode: $currentMode");
	if ($currentMode eq $alarmScreensaver) {
		$log->debug('Popping alarm screensaver');
		Slim::Buttons::Common::popMode($client);
	}
}

sub overlayFunc {
	my $client = shift;
	
	my $nextmenu = 'alarm/' . $client->modeParam('listRef')->[$client->modeParam('listIndex')];

	if (exists($menuParams{$nextmenu})) {
		my %nextParams = %{$menuParams{$nextmenu}};
		
		if ($nextParams{'useMode'} eq 'boolean') {
			my $pref = $prefs->client($client)->get($nextParams{'pref'});
			return (
				undef,
				Slim::Buttons::Common::checkBoxOverlay($client,
					ref $pref ? $pref->[ useWeekday($client, $nextParams{'pref'}) ] : $pref
				),
			);
		}
	}
	
	return (undef,$client->symbols('rightarrow'));
}

sub alarmHeader {
	my $client = shift;
	my $index = shift;
	
	my $weekDay = weekDay($client);
	my $line1;

	# create line 1, showing the chosen weekday if applicable
	if ($weekDay) {
		$line1 = sprintf('%s - %s', $client->string('ALARM_WEEKDAYS'), $client->string("ALARM_DAY$weekDay"));

	} else {
		$line1 = $client->string('ALARM');
	}
	
	return $line1;
}

# Subscribe to commands that should stop the alarm
sub setAlarmSubscription {
	my $client = shift;

	if ($client->snoozeActive) {
		$log->debug('Removing snooze subscription');
		Slim::Control::Request::unsubscribe(\&alarmEnd, $client);
	}

	$log->debug('Adding alarm subscription');
	# The alarm should be cancelled on anything the user does that would stop the music:
	# pause and stop both result in power
	Slim::Control::Request::subscribe(\&alarmEnd, [['pause', 'stop']], $client);
}

# Subscribe to commands that should cancel the snooze
sub setSnoozeSubscription {
	my $client = shift;

	Slim::Control::Request::unsubscribe(\&alarmEnd, $client);

	$log->debug('Adding snooze subscription');
	# The snooze should be cancelled on anything the user does that results in music playing and also on any
	# "off" action:
	# power needs to be caught on its own as the music is paused
	# pause/play when paused results in pause
	# fwd/rew and (hopefully) commands that load a new playlist result in 'playlist jump'
	Slim::Control::Request::subscribe(\&alarmEnd, [['power', 'pause', 'stop', 'playlist']], $client);
}

=head1 SEE ALSO

L<Slim::Buttons::Common>

L<Slim::Utils::Timers>

=cut

1;

__END__
