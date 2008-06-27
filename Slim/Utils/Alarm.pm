package Slim::Utils::Alarm;
use strict;

# Max Spicer, May 2008
# This code is derived from code with the following copyright message:
#
# SqueezeCenter Copyright 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.


################################################################################
=head1 NAME

Slim::Utils::Alarm;

=head1 SYNOPSIS

	# Create a new alarm for 11:30am
	my $alarm = Slim::Utils::Alarm->new($client, 11 * 3600 + 30 * 60);

	# Set it to sound only on Sunday and Saturday
	$alarm->day(0,0);
	$alarm->day(6,0);

	# Set the volume to 80 (don't do this if you just want to use the default volume for all alarms)
	$alarm->volume(80);

	# Enable it
	$alarm->enabled(1);

	# Save and activate it
	$alarm->save;

=head1 DESCRIPTION

This class implements SqueezeCenter alarms (alarm clock functionality) and provides methods for manipulating them.

Two types of alarm are implemented - daily alarms and calendar alarms.  Daily alarms have a time component and a specified subset of weekdays on which to sound e.g. 09:00 on Monday, Saturday and Sunday.  Calendar alarms have a time specified as an epoch value, representing an absolute date and time on which they sound e.g. 09:30 on 21/4/2008.

=cut

#use Data::Dumper;
use Time::HiRes;

use Slim::Player::Client;
use Slim::Utils::DateTime;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;

my $log = logger('player.alarmclock');
my $prefs = preferences('server');

# Period over which to fade volume changes
my $FADE_SECONDS = 20;

# Duration for showBriefly
my $SHOW_BRIEFLY_DUR = 3;

# Screensaver used during alarms
my $alarmScreensaver = 'SCREENSAVER.datetime';

# Hash storing the playlists that alarms can use.  Keys are playlist URLs.  Values are the string descriptions for each URL.
# e.g. 
# {
#	'randomplay://albums' => 'PLUGIN_RANDOM_ALBUMS',
# }
my %alarmPlaylists = (); 

# The possible playlists for alarms.  See docs for getPlaylists()
# Any url in this hash must be a key in %alarmPlayLists.
# Initialise to just contain the current playlist, which is a special case where url is undef.
my %alarmPlaylistTypes = (
	'CURRENT_PLAYLIST'	=> {
		'{CURRENT_PLAYLIST}'	=> undef,	
	},
);


################################################################################
=head1 INSTANCE METHODS

=head2 new( $client, $time )

Creates a new alarm object to sound at the specified time.

$time should be an epoch value to specify a calendar alarm, or the number of seconds since midnight to specify a daily alarm.
Values for $time should be rounded down to the nearest minute - any second values will be ignored.  Daily alarms will default
to sounding every day.

If time is not specified it will be set to undef.  However, the time must be set before the alarm can be saved or scheduled.

=cut

sub new {
	my $class  = shift;	# class to construct
	my $client = shift;	# client to which the alarm applies
	my $time = shift;	# optional time at which alarm should sound

	return unless defined $client;

	# External users: use the accessors!
	my $self = {
		_clientId => $client->id,
		_time => $time, 	
		# For daily alarms, _days is an array of booleans indicating days for which alarm should sound.
		# 0=Sun 6=Sat. undef indicates a calendar alarm
		_days => (! defined $time || $time < 86400) ? [(1) x 7] : undef,
		_enabled => 0,
		_playlist => undef,
		_volume => undef, # Use default volume
		_active => 0,
		_snoozeActive => 0,
		_nextDue => undef,
	};

	bless $self, $class;
	
	return $self;
}

################################################################################
=head2 Accessors

=head3 calendarAlarm( )

Returns whether this is a calendar alarm (i.e. set for a specific date) or a daily alarm.

=cut

sub calendarAlarm {
	my $self = shift;

	return ! defined $self->{_days};
}

=head3 client( [ $client ] )

Sets/returns the client to which this alarm applies.

=cut

sub client {
	my $self = shift;
	my $newValue = shift;
	
	$self->{_clientId} = $newValue->id if defined $newValue;
	
	return Slim::Player::Client::getClient($self->{_clientId});
}

=head3 comment( [ $text ] )

Sets/returns the optional text associated with this alarm.  Comments should be brief and I<may> be displayed on a player's or
controller's screen when the alarm sounds.

=cut

sub comment {
	my $self = shift;
	my $newValue = shift;

	$self->{_comment} = $newValue if defined $newValue;

	return $self->{_comment};
}

=head3 day( $dayNum , [ 0/1 ] ) 

Sets/returns whether the alarm is active on a particular day (0=Sun .. 6=Sat).

=cut

sub day {
	my $self = shift;
	my $day = shift;
	my $newValue = shift;
	
	$self->{_days}->[$day] = $newValue if defined $newValue;
	
	return $self->{_days}->[$day];
}

=head3 everyDay( [0/1] )

Sets/returns whether this alarm is active every day.  This is a convenience method to avoid repeated calls to day().

=cut

sub everyDay {
	my $self = shift;
	my $all = shift;

	if (defined $all) {
		foreach my $day (@{$self->{_days}}) {
			$day = $all;
		}
	} else {
		# Look for a day that isn't enabled
		$all = 1;
		foreach my $day (@{$self->{_days}}) {
			if (! $day) {
				$all = 0;
				last;
			}
		}
	}
	return $all;
}

=head3 enabled( [ 0/1 ] )

Sets/returns whether this alarm is enabled.  Disabled alarms will never sound.

=cut

sub enabled {
	my $self = shift;
	my $newValue = shift;
	
	$self->{_enabled} = $newValue if defined $newValue;
	
	return $self->{_enabled};
}

=head3 time( [ $time ] )

Sets/returns the time for this alarm.  If a new time is specified the alarm will be converted to/from calendar type as appropriate.

Warning: for calendar alarms, this time will also include a date component.  Editors should take care not to destroy this when changing just the time.

=cut

sub time {
	my $self = shift;
	my $time = shift;
	
	if (defined $time) {
		$self->{_time} = $time;
		if ($time >= 86400) {
			$self->{_days} = undef;
		}
	}
	
	return $self->{_time};
}

=head3 id( )

Returns the unique id for this alarm.

=cut

sub id {
	my $self = shift;
	
	return $self->{_id};
}

=head3 volume( [ $volume ] )

Sets/returns the volume at which this alarm will sound.

=cut

sub volume {
	my $self = shift;

	if (@_) {
		my $newValue = shift;
	
		$self->{_volume} = $newValue;
	}

	if (defined $self->{_volume}) {
		return $self->{_volume};
	} else {
		# No explicit volume defined so alarm uses default volume
		return ref($self)->defaultVolume($self->client);
	}
}

=head3 usesDefaultVolume( [ 1 ] )

Sets/returns whether this alarm uses the default volume or has it's own volume setting.  Set to 1 to use the default.

To stop an alarm using the default volume, set its volume to something.

=cut

sub usesDefaultVolume {
	my $self = shift;
	my $default = shift;

	if ($default) {
		$self->{_volume} = undef;
	}

	return ! defined $self->{_volume};
}

=head3 playlist( $playlistUrl )

Sets/returns the url for the alarm playlist.  If url is undef, the current playlist will be used.

=cut

sub playlist {
	my $self = shift;

	if (@_) {
		my $newValue = shift;
		
		$self->{_playlist} = $newValue;
	}
	
	return $self->{_playlist};
}

=head3 nextDue( )

Returns the epoch value for when this alarm is next due.

=cut

sub nextDue {
	my $self = shift;

	return $self->{_nextDue};
}


################################################################################
=head2 Methods

=head3 findNextTime( $baseTime )

Returns as an epoch value, the time when this alarm should next sound or undef if no time was found.  Also stores this value
within the alarm object.

$baseTime must be an epoch value for the start time from which the next alarm should be considered and should be the current
time rounded down to the nearest minute.  Any alarm with a time equal to or after this will be considered a candidate for being
next.  This allows multiple alarms to be considered against a common, non-increasing base point.

=cut

sub findNextTime {
	my $self = shift;
	my $baseTime = shift;
	
	if (! $self->{_enabled}) {
		return undef;
	}

	if (defined $self->{_days}) {
		# Convert base time into a weekday number and time
		my ($sec, $min, $hour, $mday, $mon, $year, $wday)  = localtime($baseTime);

		# Find the first enabled alarm starting at baseTime's day num 
		my $day = $wday;
		for (my $i = 0; $i < 7; $i++) {
			if ($self->{_days}[$day]) {
				# alarm is enabled for this day, which is $day days away from $baseTime

				# work out how far $baseTime is from midnight on that day
				my $baseTimeSecs = $min * 60 + $hour * 3600;
				# alarm is next if it's not in the same day as base time or is >= basetime
				if ($i > 0 || $baseTimeSecs <= $self->{_time}) {
					# alarm time in seconds since midnight on base time's day
					my $relAlarmTime = $self->{_time} + $i * 86400;
					my $absAlarmTime = $baseTime - $baseTimeSecs + $relAlarmTime;

					$log->debug(sub {'Potential next time found: ' . _timeStr($absAlarmTime)});

					# Make sure this isn't the alarm that's just sounded or another alarm with the
					# same time.
					my $client = $self->client;
					my $lastAlarmTime = $client->alarmData->{lastAlarmTime};
					defined $lastAlarmTime && $log->debug(sub {'Last alarm due: ' . _timeStr($lastAlarmTime)});
					if (! defined $lastAlarmTime || $absAlarmTime != $lastAlarmTime) {
						$self->{_nextDue} = $absAlarmTime;
						return $absAlarmTime;
					} else {
						$log->debug('Skipping..');
					}

				}
			}
			# Move on to the next day, wrapping round to the start of the week as necessary
			$day = ($day + 1) % 7;
		}

		$log->debug('Alarm has no days enabled');
		return undef;
	} else {
		# This is a calendar alarm so _time is already absolute
		$self->{_nextDue} = $self->{_time};
		return $self->{_time}
	}
}

=head3 sound( )

Sound this alarm by starting its playlist on its client, adjusting the volume, displaying notifications etc etc.

This method is generally called by a Timer callback that has been set using scheduleNext();

=cut

sub sound {
	my $self = shift;

	my $class = ref $self;

	# Optional, high-res epoch time value for when this alarm should have been triggered.  Passed when
	# the alarm is triggered by a timer.
	my $alarmTime = shift;

	my $client = $self->client;
	
	if (! defined $client) {
		# This can happen if a client is forgotten after an alarm was scheduled for it
		$log->debug('Alarm triggered for unknown client: ' . $self->{_clientId});
		return;
	}

	$log->debug('Alarm triggered for ' . $client->name);

	# Check if this alarm is still current - we could be running really late due to hibernation or similar
	my $soundAlarm = 1;
	if (defined $alarmTime) {
		# Alarms should only ever be late.  Sound them anyway if they are early
		my $delta = CORE::time - $alarmTime;
	
		# Give a 60 second tolerance
		if ($delta > 60) {
			$log->debug("Alarm is $delta seconds late - ignoring");
			$soundAlarm = 0;
		}
	}

	if ($soundAlarm) {
		# Sound an Alarm (HWV 63)
		$log->debug('Sounding alarm');

		$client->alarmData->{lastAlarmTime} = $self->{_nextDue};
		$self->{_active} = 1;
		$client->alarmData->{currentAlarm} = $self;

		my $now = Time::HiRes::time(); 
		# Bug 7818, count this as user interaction, even though it isn't really
		$client->lastActivityTime($now);

		my $request = $client->execute(['stop']);
		$request->source('ALARM');
		$request = $client->execute(['power', 1]);
		$request->source('ALARM');

		$class->pushAlarmScreensaver($client);

		# Set analogOutMode to subwoofer to force output through main speakers even if headphones are plugged in
		# This needs doing a lot more thoroughly.  Bug 8146 
		$client->can('setAnalogOutMode') && $client->setAnalogOutMode(1);

		# Set up volume
		my $currentVolume = $client->volume;
		$log->debug("Current vol: $currentVolume Alarm vol: " . $self->volume);

		if ($currentVolume != $self->volume) {
			$log->debug("Changing volume from $currentVolume to " . $self->volume);
			$client->volume($self->volume);
		}

		# Fade volume change if requested 
		if ( $prefs->client($client)->get('alarmfadeseconds') ) {
			$log->debug('Fading volume');
			$client->fade_volume( $FADE_SECONDS );
		}

		# Play alarm playlist, falling back to the current playlist if undef
		#TODO: check that playlist is still valid
		if (defined $self->playlist) {
			$request = $client->execute(['playlist', 'play', $self->playlist]);
			$request->source('ALARM');
		} else {
			# Check that the current playlist isn't empty
			my $playlistLen = Slim::Player::Playlist::count($client);
			if ($playlistLen) {
				$request = $client->execute(['play']);
				$request->source('ALARM');
			} else {
				$log->debug('Current playlist is empty');

				#TODO: Bug 8499 would be nice here!

				#TODO: Just play something.
			}
		}

		# Allow a slight delay for things to load up then tell the user what's going on
		Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + 2, sub {
			# Show a long-lasting notification unless we've already pushed into an alarm screensaver
			my $showBrieflyDur = 30;
			if (Slim::Buttons::Common::mode($client) eq $class->alarmScreensaver) {
				$showBrieflyDur = $SHOW_BRIEFLY_DUR;
			}

			my $line1 = $client->string('ALARM_NOW_PLAYING');

			my $line2; 
			if (defined $self->playlist) {
				# Get the string that was given when the current playlist url was registered
				$line2 = $alarmPlaylists{$self->playlist};
			} else {
				$line2 = $client->string('CURRENT_PLAYLIST');
			}

			$client->showBriefly({
				line => [ $line1, $line2 ],
				duration => $SHOW_BRIEFLY_DUR,
			});
		} );

		# Set up subscription to end the alarm on user activity
		$class->_setAlarmSubscription($client);
	}

	$self->{_timerRef} = undef;

	$class->scheduleNext($client);
}

=head3

snooze( )

Snooze this alarm, causing it to stop sounding and re-sound after a set period.  The snooze length is determined
by the client pref, alarmSnoozeSeconds.

Does nothing unless this alarm is already active.

=cut

sub snooze {
	my $self = shift;

	$log->debug('Snooze called for alarm id ' . $self->{_id});
	
	return unless $self->{_active};

	my $client = $self->client;
	my $class = ref $self;

	# don't snooze again if we're already snoozing.
	if ($self->{_snoozeActive}) {
		$log->debug('Already snoozing');
	} else {
		my $snoozeSeconds = $prefs->client($client)->alarmSnoozeSeconds;
		$log->debug("Snoozing for $snoozeSeconds seconds");

		# Pause the music
		my $request = $client->execute(['pause', 1]);
		$request->source('ALARM');

		$self->{_snoozeActive} = 1;

		# Set timer for snooze expiry 
		Slim::Utils::Timers::setTimer($self, Time::HiRes::time + $snoozeSeconds, \&stopSnooze);

		# Set up snooze subscription to end snooze on user activity
		$class->_setAlarmSubscription($client, 1);

		$client->showBriefly({
			line => [$client->string('ALARM_SNOOZE')],
			duration => $SHOW_BRIEFLY_DUR,
		});
	}

	$class->pushAlarmScreensaver($client);
}

=head3

stopSnooze( )

Stop this alarm from snoozing.  Has no effect if the alarm isn't snoozing.

=cut

sub stopSnooze {
	my $self = shift;

	$log->debug('Snooze expired');

	return unless $self->{_snoozeActive};

	my $class = ref $self;
	my $client = $self->client;

	$self->{_snoozeActive} = 0;
	
	# Resume music
	my $request = $client->execute(['pause', 0]);
	$request->source('ALARM');

	$client->showBriefly({
		line     => [$client->string('ALARM_SNOOZE_ENDED')],
		duration => $SHOW_BRIEFLY_DUR,
	});
	
	# Reset the subscription to end the alarm on user activity
	$class->_setAlarmSubscription($client);
}


=head3

stop( )

Stop this alarm from sounding.  Has no effect if the alarm is not sounding.

=cut

sub stop {
	my $self = shift;

	my $client = $self->client;

	return unless $self->{_active};

	if (defined $client->alarmData->{currentAlarm} && $client->alarmData->{currentAlarm} == $self) {
		$client->alarmData->{currentAlarm} = undef;
	}
	$self->{_active} = 0;
	$self->{_snoozeActive} = 0;

	# Restore analogOutMode to previous setting
	$client->can('setAnalogOutMode') && $client->setAnalogOutMode();

	my $class = ref $self;
	$class->popAlarmScreensaver($client);

	$client->showBriefly({
		line => [$client->string('ALARM_STOPPED')],
		duration => $SHOW_BRIEFLY_DUR,
	});
}

=head3

displayStr( )

Returns a short, single-line string describing this alarm.  e.g. 09:00 Mo Sa Sj

=cut

sub displayStr {
	my $self = shift;

	my $displayStr = Slim::Utils::DateTime::secsToPrettyTime($self->{_time});

	if ($self->everyDay) {
		$displayStr .= ' ' . $self->client->string('ALARM_EVERY_DAY');
	} else {
		foreach my $day (1 .. 6, 0) { 
			if ($self->day($day)) {
				$displayStr .= ' ' . $self->client->string('ALARM_SHORT_DAY_' . $day);
			}
		}
	}

	return $displayStr;
}

=head3 timeStr( )

Returns the formatted time string for this alarm.

=cut

sub timeStr {
	my $self = shift;

	return Slim::Utils::DateTime::secsToPrettyTime($self->{_time});
}

=head3 active( )

Returns whether this alarm is currently active.

=cut

sub active {
	my $self = shift;

	return $self->{_active};
}

=head3 snoozeActive( )

Returns whether this alarm currently has an active snooze.

A snooze can only be active if the alarm is active i.e. snoozeActive => active.

=cut

sub snoozeActive {
	my $self = shift;

	return $self->{_snoozeActive};
}

################################################################################
# Persistence management
################################################################################

=head3 save( )

Save/update alarm.  This must be called on an alarm once changes have finished being made to it. 
Changes to existing alarms will not be persisted unless this method is called.  New alarms will
not be scheduled unless they have first been saved.

=cut

sub save {
	my $self = shift;

	my $class = ref $self;
	my $client = $self->client;

	$log->debug('Saving alarm.');

	my $alarmPref = $self->_createSaveable;

	my $prefAlarms = $prefs->client($client)->alarms;
	$prefAlarms->{$self->{_id}} = $alarmPref;
	$prefs->client($client)->alarms($prefAlarms);

	# There's a new/updated alarm so reschedule
	$log->debug('Alarm saved with id ' . $self->{_id} .  ' Rescheduling alarms...');
	$class->scheduleNext($client);
}

# Return a saveable version of the alarm and add the alarm to the client object.
# Exists solely in order to allow the alarm pref migration code to create migrated versions
# of old alarms in one batch and save them straight to the preferences.  This is necessary as
# reading prefs within the migration code causes a loop.  This sub therefore mustn't read prefs!
sub _createSaveable {
	my $self = shift;

	my $client = $self->client;

	if (! defined $self->{_time}) {
		$log->debug('Alarm hasn\'t had a time set.  Not saving.');
		return;
	}
	
	# Add alarm to client object if it hasn't been saved before
	if (! defined $self->{_id}) {
		# Create unique id for alarm
		$self->{_id} = Slim::Utils::Misc::createUUID();

		$client->alarmData->{alarms}->{$self->{_id}} = $self;
	}

	# Create a persistent version for the prefs
	return {
		_time => $self->{_time},
		_days => $self->{_days},
		_enabled => $self->{_enabled},
		_playlist => $self->{_playlist},
		_volume => $self->{_volume},
		_comment => $self->{_comment},
		_id => $self->{_id},
	};
}

=head3 delete( )

Delete alarm.  Alarm will be removed from the list of alarms for the current client and will no longer be scheduled.

=cut

sub delete {
	my $self = shift;

	my $class = ref $self;
	my $client = $self->client;

	# Only delete if alarm has actually been saved
	if (defined $self->{_id}) {
		$log->debug('Deleting alarm, id: ' . $self->{_id});

		my $prefAlarms = $prefs->client($client)->alarms;
		delete $prefAlarms->{$self->{_id}};
		$prefs->client($client)->alarms($prefAlarms);

		delete $client->alarmData->{alarms}->{$self->{_id}};

		# Alarm deleted so reschedule
		$log->debug('Rescheduling alarms...');
		$class->scheduleNext($client);
	}
};


################################################################################
=head1 CLASS METHODS

=head2 init

Initialise SqueezeCenter alarm functionality.  This must be called on server startup (probably from slimserver.pl).

=cut

sub init {
	my $class = shift;

	$log->debug('Alarm initing...');

	# Set up subscriptions to track new clients
	Slim::Control::Request::subscribe(\&_clientManager, [['client'], ['new']]);
}

# Subscribe to commands that should stop the alarm
sub _setAlarmSubscription {
	my $class = shift;
	my $client = shift;
	my $snooze = shift;

	# Remove any subscription for this client
	Slim::Control::Request::unsubscribe(\&_alarmEnd, $client);

	my $currentAlarm = $client->alarmData->{currentAlarm};

	return unless defined $currentAlarm;

	$log->debug('Adding ' . ($snooze ? 'snooze' : 'alarm') . ' subscription');

	my $stopCommands;

	if ($snooze) {
		# The snooze should be cancelled on anything the user does that results in music playing and also on any
		# "off" action:
		# power needs to be caught on its own as the music is paused
		# pause/play when paused results in pause
		# fwd/rew and (hopefully) commands that load a new playlist result in 'playlist jump'
		$stopCommands = ['power', 'pause', 'stop', 'playlist'];
	} else {
		# The alarm should be cancelled on anything the user does that would stop the music:
		# power results in pause or stop depending on prefs
		$stopCommands =  ['pause', 'stop'];
	}
	Slim::Control::Request::subscribe(\&_alarmEnd, [$stopCommands], $client);
}

=head2 getCurrentAlarm( $client )

Return the current alarm for a client.  A client only has a current alarm if an alarm is currently active for that client.  Otherwise, returns undef.

=cut

sub getCurrentAlarm {
	my $class = shift;
	my $client = shift;

	return $client->alarmData->{currentAlarm};
}

=head2 getNextAlarm( $client )

Return the next alarm that will sound for a client.  If there is no next alarm, returns undef.

=cut

sub getNextAlarm {
	my $class = shift;
	my $client = shift;

	return $client->alarmData->{nextAlarm};
}

=head2 getAlarms( $client, [ $excludeCalAlarms = 0 ] )

Return an unordered list of the alarms for a client.
#TODO: Make it ordered!

If $excludeCalAlarms is true, only daily alarms will be returned. 

=cut

sub getAlarms {
	my $class = shift;
	my $client = shift;
	my $excludeCalAlarms = shift;

	my @alarms;
	for my $alarm ( keys %{$client->alarmData->{alarms}} ) { 
		$alarm = $client->alarmData->{alarms}->{$alarm};
		if ($excludeCalAlarms && $alarm->calendarAlarm) {
			next;
		}
		push @alarms, $alarm;
	}
	return @alarms;
}

=head2 getAlarm( $client, $id )

Returns a specific alarm for a given client, specified by alarm id.  If no such alarm exists, undef is returned.

=cut

sub getAlarm {
	my $class = shift;
	my $client = shift;
	my $id = shift;

	return $client->alarmData->{alarms}->{$id};
}

=head2 loadAlarms( $client )

Load the alarms for a given client and schedule the next alarm.  This should be called
whenever a new client is detected.

=cut

sub loadAlarms {
	my $class = shift;
	my $client = shift;	
	
	$log->debug('Loading saved alarms from prefs for ' . $client->name);
	my $prefAlarms = $prefs->client($client)->alarms;

	foreach my $prefAlarm (keys %$prefAlarms) {
		$prefAlarm = $prefAlarms->{$prefAlarm};
		my $alarm = $class->new($client, $prefAlarm->{_time});
		$alarm->{_days} = $prefAlarm->{_days};
		$alarm->{_enabled} = $prefAlarm->{_enabled};
		$alarm->{_playlist} = $prefAlarm->{_playlist};
		$alarm->{_volume} = $prefAlarm->{_volume};
		$alarm->{_comment} = $prefAlarm->{_comment};
		$alarm->{_id} = $prefAlarm->{_id};

		$client->alarmData->{alarms}->{$alarm->{_id}} = $alarm; 
	}

	$log->debug('Alarms loaded.  Rescheduling...');
	$class->scheduleNext($client);
}

=head2 scheduleNext( $client )

Set a timer to sound the next due alarm for a given client at its alarm time.

This method is called automatically when new alarms are added or re-scheduling is needed for any other reason.

=cut

sub scheduleNext {
	my $class = shift;
	my $client = shift;

	$log->debug('Asked to schedule next alarm for ' . $client->name);
	my $alarms = $client->alarmData->{alarms};

	my $nextAlarm = $client->alarmData->{nextAlarm};
	if ($nextAlarm) {
		if (defined $nextAlarm->{_timerRef}) {
			$log->debug('Previous scheduled alarm wasn\'t triggered.  Clearing nextAlarm and killing timer');
			Slim::Utils::Timers::killSpecific($nextAlarm->{_timerRef});

			# As the next alarm hasn't actually sounded, do a complete reschedule.  This allows
			# the same alarm to be scheduled again if it's still next
			$client->alarmData->{nextAlarm} = undef;
		}
	}

	if ($class->alarmsEnabled($client)) {
		# Work out current time rounded down to the nearest minute
		my $now = CORE::time;
		$now = $now - $now % 60;

		# Find the next alarm
		my $nextAlarmSecs = undef;
		my $nextAlarm = undef;

		foreach my $alarm (keys %$alarms) {
			my $secs = $alarms->{$alarm}->findNextTime($now);
			if (defined $secs && (! defined $nextAlarmSecs || $secs < $nextAlarmSecs)) {
				$nextAlarmSecs = $secs;
				$nextAlarm = $alarms->{$alarm};
			}
		}

		if (defined $nextAlarm) {
			$log->debug(sub {'Next alarm is at ' . _timeStr($nextAlarm->{'_nextDue'})});

			if ($nextAlarm->{_nextDue} == $now) {
				# The alarm is for this minute - sound it immediately
				$log->debug('Sounding alarm immediately');
				$nextAlarm->sound;
			} else {
				# TODO: schedule a bit early to allow for timers firing late.  Once this is done and the early
				# timer fires, check every second to see if the alarm should sound.  10 secs early should be more
				# than enough.  This is only really needed for SqueezeNetwork where 1000s of clients can lead
				# to timers firing a few seconds late.
				my $alarmTime = $nextAlarm->{_nextDue};
				$log->debug('Scheduling alarm');
				$nextAlarm->{_timerRef} = Slim::Utils::Timers::setTimer($nextAlarm, $alarmTime, \&sound, $alarmTime);

				$client->alarmData->{nextAlarm} = $nextAlarm;
			}
		} else {
			$log->debug('No future alarms found');
		}

	} else {
		$log->debug('Alarms are disabled');
	}

	# Set/clear the client's RTC alarm if supported
	$class->setRTCAlarm($client);
}

=head2 setRTCAlarm( $client )

Sets a given client's RTC alarm clock if the client has an alarm within the next 24 hours, otherwise clears it.  Does nothing 
if the client does not have an RTC alarm clock.  The next alarm for the client should already have been scheduled before this is called.

Once called, this sub will schedule itself to be called again in 24 hours.

=cut

sub setRTCAlarm {
	my $class = shift;
	my $client = shift;

	$log->debug('Asked to set rtc alarm for ' . $client->name);

	return if ! $client->hasRTCAlarm;

	# Clear any existing timer to call this sub
	my $timerRef = $client->alarmData->{_rtcTimerRef};
	if (defined $timerRef) {
		# Kill previous rtc alarm timer
		Slim::Utils::Timers::killSpecific($timerRef);
	}

	my $nextAlarm = $class->getNextAlarm($client);

	my $clearRTCAlarm = 1;
	my $now = Time::HiRes::time;

	if (defined $nextAlarm) {
		my $nextDue = $nextAlarm->nextDue;

		my $secsToAlarm = $now - $nextDue;
		if ($secsToAlarm && $secsToAlarm < 86400) {
			# Alarm due in next 24 hours

			my $alarmTime;
			if ($nextAlarm->calendarAlarm) {
				$alarmTime = $nextAlarm->time % 86400;
			} else {
				$alarmTime = $nextAlarm->time;
			}

			# Alarm times are "floating" so no need to adjust for local time
			$log->debug('Setting RTC alarm');
			$client->setRTCAlarm($alarmTime);

			$clearRTCAlarm = 0;
		}
	}

	if ($clearRTCAlarm) {
		# Next alarm not defined or not within next 24 hours
		$log->debug('Clearing RTC alarm');
		$client->setRTCAlarm(undef);
	}

	# Set a timer to check again in 24 hours
	$client->alarmData->{_rtcTimerRef} = Slim::Utils::Timers::setTimer($class, $now + 86400, \&setRTCAlarm, $client);
}

=head2 defaultVolume( [ $volume ] )

Sets/returns the volume level that is used for all alarms on a given client that don't have an explicit volume level set.

=cut

sub defaultVolume {
	my $class = shift;
	my $client = shift;
	my $volume = shift;

	if (defined $volume) {
		$prefs->client($client)->alarmDefaultVolume($volume);
	}

	return $prefs->client($client)->alarmDefaultVolume;
}

=head2 enabled( [0/1] )

Sets/returns whether alarms are enabled for a given client.

This enables all alarms to be quickly enabled/disabled, whilst still retaining their settings for the future.

=cut

sub alarmsEnabled {
	my $class = shift;
	my $client = shift;
	my $enabled = shift;

	if (defined $enabled) {
		$prefs->client($client)->alarmsEnabled($enabled);
		
		# Reschedule to enable/disable
		$log->debug('Alarms enabled state changed - rescheduling alarms...');
		$class->scheduleNext($client);
	}

	return $prefs->client($client)->alarmsEnabled;
}

=head2 addPlaylists( $type, $playlists )

Adds playlists to the list of possible playlists that alarms can play when sounding.  This method should be called by modules
that offer new playlist types and wish to register them for alarms e.g. random mix, favorites etc.

$type is a string identifying the type of playlist that is being added.  It may be displayed to the user, for example as a
a heading to group multiple playlists of the same type.  $type will be passed through string().

$playlists is a hash reference whose keys are the display names for the playlists and whose values are the urls for the playlists.
If the keys are to be passed through string, they should be enclosed in curly braces.

For example, the RandomPlay plugin would register its mixes as possible alarm playlists as follows:

	Slim::Utils::Alarm->addPlaylists('PLUGIN_RANDOMPLAY',
		{
			'{PLUGIN_RANDOM_TRACK}'		=> 'randomplay:track',
			'{PLUGIN_RANDOM_CONTRIBUTOR}'	=> 'randomplay:contributor',
			'{PLUGIN_RANDOM_ALBUM}'		=> 'randomplay:album',
			'{PLUGIN_RANDOM_YEAR}'		=> 'randomplay:year',
		}
	);

This could result in the user being presented with four new alarm playlists to chose from, all grouped under the heading of
PLUGIN_RANDOMPLAY.

=cut

sub addPlaylists {
	my $class = shift;
	my $type = shift;
	my $playlists = shift;

	foreach my $playlist (keys %$playlists) {
		# Create a mapping from the url to its display name
		$alarmPlaylists{$playlist} = $playlists->{$playlist}; 		

		# Create a mapping from the playlist type to its associated playlists
		#TODO: Allow already defined types to be added to?
		$alarmPlaylistTypes{$type} = $playlists;
	}
}

=head2 getPlaylists( )

Return the current possible alarm playlists with names stringified for the given client.

The returned value is a hash of hashes, mapping playlist types to the URLs available under that type. 
e.g.
	{
		'Random Mix' => {
			'Random Song Mix' => 'randomplay://albums',
			'Random Artist Mix' => 'randomplay://artists',
		},
		'Playlists' => {
			...,
		},
	}

=cut

sub getPlaylists {
	my $class = shift;
	my $client = shift;

	# Add the current saved playlists
	my @playlists = Slim::Schema->rs('Playlist')->getPlaylists;
	my %playlistHash;
	foreach my $playlist (@playlists) {
		$playlistHash{Slim::Music::Info::standardTitle($client, $playlist->url)} = $playlist->url;
	}
	$class->addPlaylists('PLAYLISTS', \%playlistHash);

	# Reconstruct %alarmPlaylistType, stringifying keys for client as necessary
	my %stringified;
	foreach my $type (keys %alarmPlaylistTypes) {
		my $playlists = {};
		foreach my $playlist (keys %{$alarmPlaylistTypes{$type}}) {
			# Stringify keys that are enclosed in curly braces
			my ($stringKey) = $playlist =~ /^{(.*)}$/; 
			if (defined $stringKey) {
				$stringKey = $client->string($stringKey);
			} else {
				$stringKey = $playlist;
			}
			$playlists->{$stringKey} = $alarmPlaylistTypes{$type}->{$playlist};
		}
		$stringified{$client->string($type)} = $playlists;
	}

	return %stringified;
}

=head2 alarmScreensaver( $modeName )

Gets/sets the screensaver mode name that is used during an active alarm.  This mode will be pushed into at the start of an alarm
and will for the duration of the alarm override any other defined screensaver.

Setting $modeName to undef will disable the alarm screensaver.

=cut

sub alarmScreensaver {
	my $class = shift;
	
	if (@_) {
		$alarmScreensaver = shift;
	}

	return $alarmScreensaver;
}

=head2 pushAlarmScreensaver( $client )

Push into the alarm screensaver (if any) on the given client.  Generally done automatically when an alarm is sounded.

=cut

sub pushAlarmScreensaver {
	my $class = shift;
	my $client = shift;

	my $currentMode = Slim::Buttons::Common::mode($client);
	my $alarmScreensaver = $class->alarmScreensaver;

	$log->debug('Attempting to push into alarm screensaver: ' . (defined $alarmScreensaver ? $alarmScreensaver : undef)
			. ". Current mode: $currentMode");
	if (defined $alarmScreensaver
		&& Slim::Buttons::Common::validMode($alarmScreensaver)
		&& $currentMode ne $alarmScreensaver) {

		$log->debug('Pushing alarm screensaver');
		Slim::Buttons::Common::pushMode($client, $alarmScreensaver);
		$client->update();
	}
}

=head2 

popAlarmScreensaver( $client )

Pop out of the alarm screensaver if it's being displayed on the given client.

=cut

sub popAlarmScreensaver {
	my $class = shift;
	my $client = shift;

	my $currentMode = Slim::Buttons::Common::mode($client);
	$log->debug("Attempting to pop alarm screensaver.  Current mode: $currentMode");
	if ($currentMode eq $class->alarmScreensaver) {
		$log->debug('Popping alarm screensaver');
		Slim::Buttons::Common::popMode($client);
	}
}


################################################################################
# PACKAGE METHODS

# Format a given time in a human readable way.  Used for debug only.
sub _timeStr {
	my $time = shift;

	if ($time < 86400) {
		my ($sec, $min, $hour, $mday, $mon, $year, $wday)  = gmtime($time);
		return "$hour:$min:$sec";
	} else {
		my ($sec, $min, $hour, $mday, $mon, $year, $wday)  = localtime($time);
		return "$hour:$min:$sec $mday/" . ($mon + 1) . '/' . ($year + 1900);
	}

}

# Callback handlers.  (These have to be package methods as can only take $request as their argument)

# Handle new client notifications by loading alarms for that client.  Called as a callback
# function for Slim::Control::Request::subscribe
sub _clientManager {
	my $request = shift;

	my $client = $request->client;
	my $class = __PACKAGE__;

	$log->debug('_clientManager callback called for cmd: ' . $request->getRequestString);

	if ($request->isCommand([['client'], ['new']])) {
		$log->debug('New client: ' . $client->name . ' (' . $client->id . ')');
		$class->loadAlarms($client);	
	}
}

# Handle events that should stop the alarm/snooze.  This doesn't cover the case of the snooze timer firing.
sub _alarmEnd {
	my $request = shift;

	my $client = $request->client;

	$log->debug(sub {'_alarmEnd called with request: ' . $request->getRequestString});

	my $currentAlarm = $client->alarmData->{currentAlarm};
	if (! defined $currentAlarm) {
		$log->debug('No current alarm.  Doing nothing.');
		return;
	}

	# Don't respond to requests that we created ourselves
	my $source = $request->source;
	if ($source && ($source eq 'ALARM' || $source eq 'PLUGIN_RANDOMPLAY')) {
		$log->debug('Ignoring self-created request');
		return;
	}

	Slim::Control::Request::unsubscribe(\&_alarmEnd, $client);

	if ($currentAlarm->{_snoozeActive}) {
		# When snoozing we should end on 'playlist jump' but can only filter on playlist
		if ($request->getRequest(0) eq 'playlist' && $request->getRequest(1) ne 'jump') {
			$log->debug('Ignoring playlist command that isn\'t jump');
			return;
		}

		# Stop the snooze expiry timer, resume music and set a new alarm subscription
		# for events that should end the alarm
		$log->debug('Stopping snooze');
		Slim::Utils::Timers::killTimers($currentAlarm, \&stopSnooze);
		$currentAlarm->stopSnooze();
	} else {
		$log->debug('Stopping alarm');
		$currentAlarm->stop;
	}
}

1;

__END__
