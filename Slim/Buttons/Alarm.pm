package Slim::Buttons::Alarm;
use strict;

# Max Spicer, May 2008
# This code is derived from code with the following copyright message:
#
# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use Slim::Utils::Alarm;
use Slim::Utils::Log;
use Slim::Utils::Prefs;

#use Data::Dumper;

my $log = logger('player.alarmclock');
my $prefs = preferences('server');

# TODO: Supply unique modeName to INPUT.Choice so it remembers where we are?

# Default mode params for all INPUT.Choice modes
my %choiceBaseParams = (
	callback	=> \&exitHandler,
	name		=> \&getName,
	header		=> \&getHeader,
	overlayRef	=> \&getOverlay,
	headerAddCount => 1,
);

###############################################################################
# Menu definitions
###############################################################################

# Alarm day selection menu (days for which a given alarm should sound)
my @daysMenu = (
	{ title => 'ALARM_EVERY_DAY', type => 'checkbox', checked => \&dayEnabled, toggleFunc => \&toggleDay, params => {day => 'all'} },
	{ title => 'ALARM_DAY1', type => 'checkbox', checked => \&dayEnabled, toggleFunc => \&toggleDay, params => {day => 1} },
	{ title => 'ALARM_DAY2', type => 'checkbox', checked => \&dayEnabled, toggleFunc => \&toggleDay, params => {day => 2} },
	{ title => 'ALARM_DAY3', type => 'checkbox', checked => \&dayEnabled, toggleFunc => \&toggleDay, params => {day => 3} },
	{ title => 'ALARM_DAY4', type => 'checkbox', checked => \&dayEnabled, toggleFunc => \&toggleDay, params => {day => 4} },
	{ title => 'ALARM_DAY5', type => 'checkbox', checked => \&dayEnabled, toggleFunc => \&toggleDay, params => {day => 5} },
	{ title => 'ALARM_DAY6', type => 'checkbox', checked => \&dayEnabled, toggleFunc => \&toggleDay, params => {day => 6} },
	{ title => 'ALARM_DAY0', type => 'checkbox', checked => \&dayEnabled, toggleFunc => \&toggleDay, params => {day => 0} },
);

# Alarm playlist shuffle option menu
my @shuffleModeMenu = (
	{ title => 'SHUFFLE_OFF',       type => 'checkbox', checked => \&shuffleModeSelected, toggleFunc => \&toggleShuffleMode, params => {shuffleMode => 0} },
	{ title => 'SHUFFLE_ON_SONGS',  type => 'checkbox', checked => \&shuffleModeSelected, toggleFunc => \&toggleShuffleMode, params => {shuffleMode => 1} },
	{ title => 'SHUFFLE_ON_ALBUMS', type => 'checkbox', checked => \&shuffleModeSelected, toggleFunc => \&toggleShuffleMode, params => {shuffleMode => 2} },
);

# Menu to confirm removal of an alarm
my @deleteMenu = (
	{
		title		=> 'CANCEL',
		rightFunc	=> sub {
					my $client = shift;

					Slim::Buttons::Common::popModeRight($client);
				},
	},
	{
		title => 'ALARM_DELETE',
		rightFunc	=>  sub {
					my $client = shift;
					my $alarm = shift;

					$alarm->delete;

					# Rebuild the top-level menu to remove the deleted alarm and reset the listIndex to 0
					buildTopMenu($client, 0);

					my $depth = $client->modeParam('alarm_depth');
					$client->showBriefly(
						{
							line => [$client->string('ALARM_DELETING')]
						},
						{
							callback =>  sub {
								for (1 .. $depth) {
									Slim::Buttons::Common::popModeRight($client);
								}
							},
						}
					);
				},
	},
);

# Add/edit alarm sub-menu
# N.B. The set up of @menu has code which relies on the order of items in this menu.  Do not change the order or add/remove
# items without updating that code!
my @alarmMenu = (
	{
		# Alarm on/off
		title	=> 'ALARM_ALARM',
		type	=> 'onOff',
		checked => sub {
				my $client = shift;
				return $client->modeParam('alarm_alarm')->enabled;
			},
		toggleFunc => sub {  
				my $client = shift;
				my $alarm = $client->modeParam('alarm_alarm');
				$alarm->enabled(! $alarm->enabled);
				saveAlarm($client, $alarm);
			},

	},
	{
		title	=> 'ALARM_SET_TIME',
		type	=> 'time',
		currentValue => sub {
					my $client = shift;
					my $alarm = $client->modeParam('alarm_alarm');
					# If the time hasn't yet been set, default it to 12 noon.
					return defined $alarm->time ? $alarm->time : 43200;
				},
		saveFunc => \&setAlarmTime,
	},
	{
		title	=> 'ALARM_SET_DAYS',
		type	=> 'menu',
		items => \@daysMenu,
	},
	{
		title	=> 'ALARM_SELECT_PLAYLIST',
		type	=> 'menu',
		items => \&buildPlaylistMenu, 
	},
	{
		title	=> 'SHUFFLE',
		type	=> 'menu',
		items => \@shuffleModeMenu,
	},
	{
		title	=> 'ALARM_ALARM_REPEAT',
		type	=> 'checkbox',
		checked => sub {
				my $client = shift;
				return $client->modeParam('alarm_alarm')->repeat;
			},
		toggleFunc => sub {  
				my $client = shift;
				my $alarm = $client->modeParam('alarm_alarm');
				$alarm->repeat(! $alarm->repeat);
				saveAlarm($client, $alarm);
			},

	},
	{
		title	=> 'ALARM_DELETE',
		type	=> 'menu',
		items	=> \@deleteMenu,
	},
);

# The top-level menu items.
my %menu = (
	# Prevent any alarm from sounding
	alarmsEnabled => 
	{
		title		=> 'ALARM_ALL_ALARMS',
		type		=> 'onOff',
		checked		=> sub {
					my $client = shift;

					return Slim::Utils::Alarm->alarmsEnabled($client);
				},
		toggleFunc	 => sub {  
					my $client = shift;
					Slim::Utils::Alarm->alarmsEnabled($client, ! Slim::Utils::Alarm->alarmsEnabled($client));
				},
	},

	# Add new alarm
	addAlarm => 
	{
		title		=> 'ALARM_ADD',
		type		=> 'menu',
		# Move Enabled to end of item list for a new alarm - it's normally at the top.  Set Time will now be first.
		# Discard the Remove Alarm option, which is at the end.
		items		=> [@alarmMenu[1 .. $#alarmMenu - 1, 0]],
	},

	# Volume level to use for all alarms
	volume =>
	{
		title		=> 'ALARM_VOLUME',
		type 		=> 'volume',
		initialValue	=> sub {
					my $client = shift;
					return Slim::Utils::Alarm->defaultVolume($client);
				},
		changeFunc => sub {
			my $client = shift;
			my $delta = shift; # will be +1, -1 etc
			Slim::Utils::Alarm->defaultVolume($client, Slim::Utils::Alarm->defaultVolume($client) + $delta);
		},
	},
);


sub setAlarmTime {
	my $alarm = shift;
	my $time = shift;

	my $client = $alarm->client;
	$client->showBriefly({line=>[$client->string('ALARM_SAVING')]});
	$alarm->time($time);

	# The user has explicitly set a time now, so make sure the alarm is enabled and saved
	$alarm->enabled(1);
	saveAlarm($client, $alarm);
}

sub saveAlarm {
	my $client = shift;

	my $alarm = shift || $client->modeParam('alarm_alarm');

	main::DEBUGLOG && $log->debug('Saving alarm...');

	if (defined $alarm->time) {
		my $newAlarm = ! $alarm->id; # Unsaved alarms don't have an id
		$alarm->save;

		# Rebuild top-level menu to reflect changes but preserve selected alarm
		buildTopMenu($client, $alarm->id);

	} else {
		main::DEBUGLOG && $log->debug('Alarm has no time set.  Not saving');
	}
}

# Toggle whether the current alarm is enabled for a given day
sub toggleDay {
	my $client = shift;
	my $item = shift;

	my $alarm = $client->modeParam('alarm_alarm');
	my $day = $item->{params}->{day};

	main::DEBUGLOG && $log->debug("toggleDay called for day: $day");

	if ($day eq 'all') {
		$alarm->everyDay($alarm->everyDay() ? 0 : 1); 
	} else {
		# $day should be [0-6]
		$alarm->day($day, $alarm->day($day) ? 0 : 1); 
	}
	saveAlarm($client, $alarm);
}

# Return whether the current alarm is enabled for a given day
sub dayEnabled {
	my $client = shift;
	my $item = shift;

	my $alarm = $client->modeParam('alarm_alarm');
	my $day = $item->{params}->{day};

	if ($day eq 'all') {
		return $alarm->everyDay;  
	} else {
		# $day should be [0-6]
		return $alarm->day($day);  
	}
}

sub toggleShuffleMode {
	my $client = shift;
	my $item = shift;

	my $alarm = $client->modeParam('alarm_alarm');
	my $shuffleMode = $item->{params}->{shuffleMode};

	main::DEBUGLOG && $log->debug("toggleShuffleMode called for mode: $shuffleMode");

	$alarm->shufflemode($shuffleMode);
	saveAlarm($client, $alarm);
}

# Return whether the current alarm shuffle mode is set to a specific mode
sub shuffleModeSelected {
	my $client = shift;
	my $item = shift;

	my $alarm = $client->modeParam('alarm_alarm');
	my $shuffleMode = $item->{params}->{shuffleMode};

	return $alarm->shufflemode == $shuffleMode;
}

sub init {
	Slim::Buttons::Common::addMode('alarm', undef, \&setMode);

	# Add an alarm menu under settings and as a potential item for the home menu
	# Some other bit of code is responsible for making this appear by default
	Slim::Buttons::Home::addSubMenu('SETTINGS', 'ALARM', {
		useMode   => 'alarm',
		condition => sub { 1 },
	});
	
	Slim::Buttons::Home::addMenuOption('ALARM', {
		useMode   => 'alarm',
		condition => sub { 1 },
	});
}

sub setMode {
	my $client = shift;
	my $method = shift;
	
	main::DEBUGLOG && $log->debug("setMode called.  method is $method");

	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}

	# Add saved alarms to the top menu
	my @topMenu;
	buildTopMenu($client, undef, \@topMenu);

	# Push into the top-level menu
	my %params = (
		%choiceBaseParams,
		listRef		=> \@topMenu,
		alarm_menuTitle	=> '{ALARM}',
		# How many sub-menus deep we are in the alarm button mode
		alarm_depth	=> 0,
		#modeName	=> 'alarm',
	);
	Slim::Buttons::Common::pushMode($client, 'INPUT.Choice', \%params);
}

# Rebuild the listref for the supplied top menu to include all the currently defined alarms
sub buildTopMenu {
	my $client = shift;
	my $selectedId = shift; # ID of the alarm to select in the top menu
	my $listRef = shift;

	my $mode;
	if (! $listRef) {
		my $depth = $client->modeParam('alarm_depth');
		$mode = $client->modeParameterStack->[-1 - $depth];
		$listRef = $mode->{listRef};
	}

	@$listRef = ();

	# Get any existing alarms and add them to the menu 
	my @alarms = Slim::Utils::Alarm->getAlarms($client);
	my $count = 0;
	foreach my $alarm (@alarms) {
		$count++;
		my $name = $client->string('ALARM_ALARM') . " $count";
		my $item = {
				title		=> $name . ' (' . $alarm->displayStr . ')',
				stringTitle	=> 1,
				headerTitle	=> $name,
				type		=> 'menu',
				items		=> \@alarmMenu,
				alarm		=> $alarm,
			};
		push @$listRef, $item;
		if (defined $selectedId && defined $mode && $alarm->id eq $selectedId) {
			$mode->{listIndex} = $count;
		}
	}

	# Add alarm comes next
	push @$listRef, $menu{addAlarm};
	
	# Alarm volume
	unless (defined $prefs->client($client)->get('digitalVolumeControl')
		&& !$prefs->client($client)->get('digitalVolumeControl')) {
			
		push @$listRef, $menu{volume};
	}

	# Alarm clock on/off goes at the top, unless there are no defined
	# alarms, in which case it goes to the bottom
	if (scalar @alarms) {
		unshift @$listRef, $menu{alarmsEnabled};
	} else {
		push @$listRef, $menu{alarmsEnabled};
	}

}

# Dynamically builds the alarm playlist menu and returns it as an arrayref
sub buildPlaylistMenu {
	my $client = shift;
	my $alarm = shift;

	#TODO: Handle a saved playlist no longer being valid.  Just display a selected entry of Unknown, but remove entry the
	# moment something else is selected?

	# Get playlists, with titles stringified for this client
	my $playlistTypes = Slim::Utils::Alarm->getPlaylists($client);

	my @menu;

	# Loop through the playlist types and add them to the menu
	foreach my $type (@$playlistTypes) {
		my @subMenu;
		# Get the playlist names for this type and build up a sub-menu of the playlists
		foreach my $playlist (@{$type->{items}}) {
			push @subMenu, {
					title		=> $playlist->{title},
					stringTitle	=> 1,
					type		=> 'radio',
					checked		=> sub {
								return (! defined $alarm->playlist && ! defined $playlist->{url})
									|| (defined $alarm->playlist
										&& defined $playlist->{url}
										&& $alarm->playlist eq $playlist->{url}
									);
							},
					toggleFunc	=> sub {
								$alarm->playlist($playlist->{url});
								saveAlarm($client, $alarm);
							},
				};
		}

		if (scalar @subMenu == 1 && $type->{singleItem}) {
			# Special single-item playlist so put it at the top-level not in a sub-menu
			push @menu, $subMenu[0];
		} else {
			# For types with more than one entry, create a sub-menu
			push @menu, {
				title		=> $type->{type},
				stringTitle	=> 1,
				type		=> 'menu',
				items		=> \@subMenu,
			};
		}
	}

	return \@menu;
}

# Return the name for a menu item with INPUT.Choice
sub getName {
	my $client = shift;
	my $item = shift;

	my $name = $item->{title};

	if (ref $name eq 'CODE') {
		$name = $name->();
	
	} elsif (! $item->{stringTitle}) {
		# Tell INPUT.Choice to pass the title through string()
		$name = '{' . $name . '}';
	}
	return $name;
}

# Return the header string for a menu
sub getHeader {
	my $client = shift;
	my $item = shift;

	my $menuTitle = $client->modeParam('alarm_menuTitle');

	if (ref $menuTitle eq 'CODE') {
		$menuTitle = $menuTitle->();
	}

	return $menuTitle;
}

sub getOverlay {
	my $client = shift;
	my $item = shift;

	my $type = $item->{type};

	if (defined $type && ($type eq 'checkbox' || $type eq 'radio' || $type eq 'onOff')) {
		my $checked = $item->{checked};
		if (ref $checked eq 'CODE') {
			$checked = $checked->($client, $item);
		}

		if ($type eq 'checkbox') {
			return [ undef, Slim::Buttons::Common::checkBoxOverlay($client, $checked ? 1 : 0) ];  
		} elsif ($type eq 'onOff') {
			return [ undef, $client->string( $checked ? 'ALARM_ON' : 'ALARM_OFF' ) ];
		} else { 
			return [ undef, Slim::Buttons::Common::radioButtonOverlay($client, $checked ? 1 : 0) ];  
		}
	} else {
		return [ undef, $client->symbols('rightarrow') ];
	}
}

# Exit handler to override INPUT.Choice's default exit handler in order to allow callbacks on non-right exits 
sub exitHandler {
	my $client = shift;
	my $exitType = shift;

	main::DEBUGLOG && $log->debug("exitHandler called with exit type $exitType");

	if ($exitType eq 'right') {
		my $valueRef = $client->modeParam('valueRef');

		if (! defined $valueRef) {
			warn 'valueRef is unexpectedly undef.';
			return;
		}
		exitRightHandler($client, $$valueRef);

	} elsif ($exitType eq 'left') {
		my $callback = $client->modeParam('alarm_exitFunc');

		# Call callback if requested
		if (defined $callback) {
			main::DEBUGLOG && $log->debug('Calling callback');
			$callback->($client);
		}
		Slim::Buttons::Common::popModeRight($client);

	} else {
		Slim::Buttons::Common::popMode($client);

	}
}

# Generic handler for exiting right from menus
sub exitRightHandler {
	my $client = shift;
	my $item = shift;

	my $type = $item->{type};
	if (defined $type) {
		main::DEBUGLOG && $log->debug("Menu item type: '$type'");
		my $nextMode;
		my %modeParams = ();
		if ($type eq 'menu') {	
			$nextMode = 'INPUT.Choice';
			%modeParams = %choiceBaseParams;	

			if (ref $item->{items} eq 'CODE') {
				$modeParams{listRef} = $item->{items}->($client, $client->modeParam('alarm_alarm'));
			} else {
				$modeParams{listRef} = $item->{items};
			}

			# Set the header for the next menu
			if ($item->{headerTitle}) {
				$modeParams{alarm_menuTitle} = $item->{headerTitle};
			} else {
				$modeParams{alarm_menuTitle} = sub { return getName($client, $item) };
			}

			# If an exit function has been requested for the next mode, store it in the new mode so it can be called
			if (defined $item->{exitFunc}) {
				$modeParams{alarm_exitFunc} = $item->{exitFunc};
			}

			# Add the alarm to which this menu will apply (if any)
			if (defined $item->{alarm}) {
				$modeParams{alarm_alarm} = $item->{alarm};
			} elsif (defined $client->modeParam('alarm_alarm')) {
				# Pass on alarm from current mode
				$modeParams{alarm_alarm} = $client->modeParam('alarm_alarm');
			} else {
				# TODO: Create new alarm only when entering Add Alarm and probably do it elsewhere
				main::DEBUGLOG && $log->debug('creating new alarm');
				$modeParams{alarm_alarm} = Slim::Utils::Alarm->new($client);
			}

			# Supply a unique mode name to INPUT.Choice so it can keep track of where the user is
			#$modeParams{modeName} = 'alarm_' . $item->{title} . $client->modeParam('alarm_depth');

		} elsif ($type eq 'time') {
			$nextMode = 'INPUT.Time';

			my $alarm = $client->modeParam('alarm_alarm');

			# Use menu title for the time mode's header
			$modeParams{header} = $item->{title};
			$modeParams{stringHeader} = 1;
			$modeParams{cursorPos} = 0;

			# Man in the middle callback to handle INPUT.Time's vaguaries
			$modeParams{callback} = \&timeExitHandler;
			# timeExitHandler will call the requested callback when done
			$modeParams{alarm_timeCallback} = $item->{saveFunc};

			my $initialValue = $item->{currentValue}->($client);
			$modeParams{valueRef} = \$initialValue;

			$modeParams{alarm_alarm} = $alarm;

		} elsif ($type eq 'volume') {
			$nextMode = 'INPUT.Bar';

			my $alarm = $client->modeParam('alarm_alarm');

			# Use menu title for volume mode's header
			$modeParams{header} = $item->{title};
			$modeParams{stringHeader} = 1;
			$modeParams{headerValue} = 'unscaled';
			$modeParams{increment} = 1;

			$modeParams{onChange} = $item->{changeFunc};
			$modeParams{onChangeArgs} = 'CV';

			my $initialValue = $item->{initialValue}->($client);
			$modeParams{valueRef} = \$initialValue;

			$modeParams{alarm_alarm} = $alarm;

		} elsif ($type eq 'checkbox' || $type eq 'radio' || $type eq 'onOff') {
			# Invoke the item's toggle function
			my $toggleFunc = $item->{toggleFunc};
			if (defined $toggleFunc && ref $toggleFunc eq 'CODE') {
				$toggleFunc->($client, $item);
				$client->update;
			}
		}

		if (defined $nextMode) {
			main::DEBUGLOG && $log->debug("Pushing into $nextMode");
			$modeParams{alarm_depth} = $client->modeParam('alarm_depth') + 1;
			Slim::Buttons::Common::pushModeLeft($client, $nextMode, \%modeParams); 
		}
	} else {
		main::DEBUGLOG && $log->debug('Undefined menu item type');

		# Call any requested right handler
		my $rightFunc = $item->{rightFunc};
		if (defined $rightFunc && ref $rightFunc eq 'CODE') {
			$rightFunc->($client, $client->modeParam('alarm_alarm'));
		} else {
			$client->bumpRight();
		}
	}
}

# Exit handler for INPUT.Time
# Exits INPUT.Time on a right or left and then calls a callback function, passing the alarm object and the new time.
# Callback function is specified via a mode parameter called timeCallback
sub timeExitHandler {
	my ($client, $exittype) = @_;

	main::DEBUGLOG && $log->debug("exit type: $exittype");
	
	my $callbackFunct = $client->modeParam('alarm_timeCallback');
	my $alarm = $client->modeParam('alarm_alarm');

	$exittype = uc($exittype); # Is this necessary?

	if ($exittype eq 'LEFT' || $exittype eq 'RIGHT') {
		my $time = ${$client->modeParam('valueRef')};
		Slim::Buttons::Common::popMode($client);
		$client->update;
		&$callbackFunct($alarm, $time);
	}
}

1;
