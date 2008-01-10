package Slim::Control::Jive;

# SqueezeCenter Copyright 2001-2007 Logitech
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;

use POSIX;
use Scalar::Util qw(blessed);
use File::Spec::Functions qw(:ALL);
use File::Basename;

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Player::Playlist;
use Slim::Buttons::Information;
use Slim::Buttons::Synchronize;
use Slim::Buttons::AlarmClock;
use Slim::Player::Sync;
use Slim::Player::Client;
use Data::Dump;


=head1 NAME

Slim::Control::Jive

=head1 SYNOPSIS

CLI commands used by Jive.

=cut

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'player.jive',
	'defaultLevel' => 'ERROR',
	'description'  => getDisplayName(),
});

# additional top level menus registered by plugins
my %itemsToDelete      = ();
my @pluginMenus        = ();

=head1 METHODS

=head2 init()

=cut
sub init {
	my $class = shift;

	# register our functions
	
#        |requires Client
#        |  |is a Query
#        |  |  |has Tags
#        |  |  |  |Function to call
#        C  Q  T  F

    Slim::Control::Request::addDispatch(['menu', '_index', '_quantity'], 
        [0, 1, 1, \&menuQuery]);

    Slim::Control::Request::addDispatch(['alarmsettings', '_index', '_quantity'], [1, 1, 1, \&alarmSettingsQuery]);
    Slim::Control::Request::addDispatch(['syncsettings', '_index', '_quantity'], [1, 1, 1, \&syncSettingsQuery]);
    Slim::Control::Request::addDispatch(['sleepsettings', '_index', '_quantity'], [1, 1, 1, \&sleepSettingsQuery]);
    Slim::Control::Request::addDispatch(['crossfadesettings', '_index', '_quantity'], [1, 1, 1, \&crossfadeSettingsQuery]);
    Slim::Control::Request::addDispatch(['replaygainsettings', '_index', '_quantity'], [1, 1, 1, \&replaygainSettingsQuery]);
    Slim::Control::Request::addDispatch(['playerinformation', '_index', '_quantity'], [1, 1, 1, \&playerInformationQuery]);
	Slim::Control::Request::addDispatch(['jivefavorites', '_index', '_quantity'], [1, 1, 1, \&jiveFavoritesQuery]);

	Slim::Control::Request::addDispatch(['date'],
		[0, 1, 0, \&dateQuery]);
	Slim::Control::Request::addDispatch(['firmwareupgrade'],
		[0, 1, 1, \&firmwareUpgradeQuery]);

	Slim::Control::Request::addDispatch(['jiveapplets'], [0, 1, 0, \&downloadQuery]);
	Slim::Control::Request::addDispatch(['jivewallpapers'], [0, 1, 0, \&downloadQuery]);
	Slim::Control::Request::addDispatch(['jivesounds'], [0, 1, 0, \&downloadQuery]);
	
	Slim::Web::HTTP::addRawDownload('^jive(applet|wallpaper|sound)/', \&downloadFile, 'binary');

	# setup the menustatus dispatch and subscription
	Slim::Control::Request::addDispatch( ['menustatus', '_data', '_action'], [0, 0, 0, sub { warn "menustatus query\n" }]);
	Slim::Control::Request::subscribe( \&menuNotification, [['menustatus']] );
	
	# Load memory caches to help with menu performance
	buildCaches();
	
	# Re-build the caches after a rescan
	Slim::Control::Request::subscribe( \&buildCaches, [['rescan', 'done']] );
}

sub buildCaches {
	# Pre-cache albums query
	my $numAlbums = Slim::Schema->rs('Album')->count;
	$log->debug( "Pre-caching $numAlbums album items." );
	Slim::Control::Request::executeRequest( undef, [ 'albums', 0, $numAlbums, 'menu:track', 'cache:1' ] );
}

=head2 getDisplayName()

Returns name of module

=cut
sub getDisplayName {
	return 'JIVE';
}

######
# CLI QUERIES

# handles the "menu" query
sub menuQuery {

	my $request = shift;

	$log->debug("Begin menuQuery function");

	if ($request->isNotQuery([['menu']])) {
		$request->setStatusBadDispatch();
		return;
	}

	my $client        = $request->client() || 0;

	# send main menu notification
	mainMenu($client);

	# a single dummy item to keep jive happy with _merge
	my $upgradeText = 
	"BETA TESTERS: Please upgrade your firmware at:\n\nSettings->\nController Settings->\nAdvanced->\nSoftware Update\n\nThere have been updates to better support the communication between your remote and SqueezeCenter, and this requires a newer version of firmware.";
        my $upgradeMessage = {
		text      => 'READ ME',
		weight    => 1,
                offset    => 0,
                count     => 1,
                window    => { titleStyle => 'settings' },
                textArea =>  $upgradeText,
        };

        $request->addResult("count", 1);
	$request->addResult("offset", 0);
	$request->setResultLoopHash('item_loop', 0, $upgradeMessage);
	$request->setStatusDone();

}

sub mainMenu {

	my $client = shift;

	unless ($client->isa('Slim::Player::Client')) {
		# if this isn't a player, no menus should get sent
		return;
	}
 
	$log->debug("Begin Function");
 
	# as a convention, make weights => 10 and <= 100; Jive items that want to be below all SS items
	# then just need to have a weight > 100, above SS items < 10

	# for the notification menus, we're going to send everything over "flat"
	# as a result, no item_loops, all submenus (setting, myMusic) are just elements of the big array that get sent

	my @menu = (
		{
			text           => Slim::Utils::Strings::string('MY_MUSIC'),
			weight         => 11,
			displayWhenOff => 0,
			id             => 'myMusic',
			isANode        => 1,
			node           => 'home',
			window         => { titleStyle => 'mymusic', },
		},
		{
			text           => Slim::Utils::Strings::string('RADIO'),
			id             => 'radio',
			node           => 'home',
			displayWhenOff => 0,
			weight         => 20,
			actions        => {
				go => {
					cmd => ['radios'],
					params => {
						menu => 'radio',
					},
				},
			},
			window        => {
					menuStyle => 'album',
					titleStyle => 'internetradio',
			},
		},
		{
			text           => Slim::Utils::Strings::string('MUSIC_SERVICES'),
			id             => 'ondemand',
			node           => 'home',
			weight         => 30,
			displayWhenOff => 0,
			actions => {
				go => {
					cmd => ['music_services'],
					params => {
						menu => 'music_services',
					},
				},
			},
			window        => {
					menuStyle => 'album',
					titleStyle => 'internetradio',
			},
		},

		{
			text           => Slim::Utils::Strings::string('FAVORITES'),
			id             => 'favorites',
			node           => 'home',
			displayWhenOff => 0,
			weight         => 40,
			actions => {
				go => {
					cmd => ['favorites', 'items'],
					params => {
						menu     => 'favorites',
					},
				},
			},
			window        => {
					titleStyle => 'favorites',
			},
		},

		# add the plugin menus
		@pluginMenus,
	);

	if ( blessed($client) && $client->isPlayer() && $client->canPowerOff() ) {
		my $playerPower = playerPower($client, 1);
		@menu = (@menu, @$playerPower);
	}

	my $playerSettings = playerSettingsMenu($client, 1);
	my $myMusic = myMusicMenu(1, $client);
	@menu = (@menu, @$playerSettings, @$myMusic);

	_notifyJive(\@menu, $client);

}

# allow a plugin to add a node to the menu
sub registerPluginNode {
	my $nodeRef = shift;
	my $client = shift || undef;
	unless (ref($nodeRef) eq 'HASH') {
		$log->error("Incorrect data type");
		return;
	}

	$nodeRef->{'isANode'} = 1;
	$log->info("Registering node menu item from plugin");

	# notify this menu to be added
	my $id = _clientId($client);
	Slim::Control::Request::notifyFromArray( $client, [ 'menustatus', $nodeRef, 'add', $id ] );

	# but also remember this structure as part of the plugin menus
	push @pluginMenus, $nodeRef;

}

# send plugin menus array as a notification to Jive
sub refreshPluginMenus {
	my $client = shift || undef;
	_notifyJive(\@pluginMenus, $client);
}

#allow a plugin to add an array of menu entries
sub registerPluginMenu {
	my $menuArray = shift;
	my $node = shift;
	my $client = shift || undef;

	unless (ref($menuArray) eq 'ARRAY') {
		$log->error("Incorrect data type");
		return;
	}

	if ($node) {
		my @menuArray = @$menuArray;
		for my $i (0..$#menuArray) {
			if (!$menuArray->[$i]{'node'}) {
				$menuArray->[$i]{'node'} = $node;
			}
		}
	}

	$log->info("Registering menus from plugin");

	# notify this menu to be added
	my $id = _clientId($client);
	Slim::Control::Request::notifyFromArray( $client, [ 'menustatus', $menuArray, 'add', $id ] );

	# now we want all of the items in $menuArray to go into @pluginMenus, but we also
	# don't want duplicate items (specified by 'id'), 
	# so we want the ids from $menuArray to stomp on ids from @pluginMenus, 
	# thus getting the "newest" ids into the @pluginMenus array of items
	# we also do not allow any hash without an id into the array, and will log an error if that happens

	my %seen; my @new;
	for my $href (@$menuArray, reverse @pluginMenus) {
		my $id = $href->{'id'};
		my $node = $href->{'node'};
		if ($id) {
			if (!$seen{$id}) {
				$log->info("registering menuitem " . $id . " to " . $node );
				push @new, $href;
			}
			$seen{$id}++;
		} else {
			$log->error("Menu items cannot be added without an id");
		}
	}

	# @new is the new @pluginMenus
	# we do this in reverse so we get previously initialized nodes first 
	# you can't add an item to a node that doesn't exist :)
	@pluginMenus = reverse @new;

}

# allow a plugin to delete an item from the Jive menu based on the id of the menu item
sub deleteMenuItem {
	my $menuId = shift;
	my $client = shift || undef;
	return unless $menuId;
	$log->warn($menuId . " menu id slated for deletion");
	# send a notification to delete
	my @menuDelete = ( { id => $menuId } );
	my $id = _clientId($client);
	Slim::Control::Request::notifyFromArray( $client, [ 'menustatus', \@menuDelete, 'remove', $id ] );
	# but also remember that this id is not to be sent
	$itemsToDelete{$menuId}++;
}

sub _purgeMenu {
	my $menu = shift;
	my @menu = @$menu;
	my @purgedMenu = ();
	for my $i (0..$#menu) {
		my $menuId = defined($menu[$i]->{id}) ? $menu[$i]->{id} : $menu[$i]->{text};
		last unless (defined($menu[$i]));
		if ($itemsToDelete{$menuId}) {
			$log->warn("REMOVING " . $menuId . " FROM Jive menu");
		} else {
			push @purgedMenu, $menu[$i];
		}
	}
	return \@purgedMenu;
}

sub alarmSettingsQuery {

	my $request = shift;
	my $client = $request->client();

	# alarm clock, display for slim proto players
	# still need to pick up saved playlists as list items
	# need to figure out how to handle 24h vs. 12h clock format

	# array ref with 5 elements, each of which is a hashref
	my $day0 = populateAlarmElements($client, 0);

	my @weekDays;
	for my $day (1..7) {
		# @weekDays becomes an array of arrayrefs of hashrefs, one element per weekday
		push @weekDays, populateAlarmHash($client, $day);
	}

	my %weekDayAlarms = (
		text      => Slim::Utils::Strings::string("ALARM_WEEKDAYS"),
		count     => scalar(@weekDays),
		offset    => 0,
		item_loop => \@weekDays,
		window    => { titleStyle => 'settings' },
	);

	# one item_loop to rule them all
	my @menu = ( @$day0, \%weekDayAlarms );

	sliceAndShip($request, $client, \@menu);

}

sub playerInformationQuery {
	return;
}

sub syncSettingsQuery {

	my $request           = shift;
	my $client            = $request->client();
	my $playersToSyncWith = getPlayersToSyncWith($client);

	my @menu = @$playersToSyncWith;

	sliceAndShip($request, $client, \@menu);

}

sub sleepSettingsQuery {

	my $request = shift;
	my $client  = $request->client();
	my $val     = $client->currentSleepTime();
	my @menu;

	if ($val > 0) {
		my $sleepString = sprintf(Slim::Utils::Strings::string('SLEEPING_IN_X_MINUTES'), $val);
		push @menu, { text => $sleepString, style => 'itemNoAction' };
	}
	push @menu, sleepInXHash($val, 0);
	push @menu, sleepInXHash($val, 15);
	push @menu, sleepInXHash($val, 30);
	push @menu, sleepInXHash($val, 45);
	push @menu, sleepInXHash($val, 60);
	push @menu, sleepInXHash($val, 90);

	sliceAndShip($request, $client, \@menu);
}

sub crossfadeSettingsQuery {

	my $request = shift;
	my $client  = $request->client();
	my $prefs   = preferences("server");
	my $val     = $prefs->client($client)->get('transitionType');
	my @strings = (
		'TRANSITION_NONE', 'TRANSITION_CROSSFADE', 
		'TRANSITION_FADE_IN', 'TRANSITION_FADE_OUT', 
		'TRANSITION_FADE_IN_OUT'
	);
	my @menu;

	push @menu, transitionHash($val, $prefs, \@strings, 0);
	push @menu, transitionHash($val, $prefs, \@strings, 1);
	push @menu, transitionHash($val, $prefs, \@strings, 2);
	push @menu, transitionHash($val, $prefs, \@strings, 3);
	push @menu, transitionHash($val, $prefs, \@strings, 4);

	sliceAndShip($request, $client, \@menu);

}

sub replaygainSettingsQuery {
	my $request = shift;
	my $client  = $request->client();
	my $prefs   = preferences("server");
	my $val     = $prefs->client($client)->get('replayGainMode');
	my @strings = (
		'REPLAYGAIN_DISABLED', 'REPLAYGAIN_TRACK_GAIN', 
		'REPLAYGAIN_ALBUM_GAIN', 'REPLAYGAIN_SMART_GAIN'
	);
	my @menu;

	push @menu, replayGainHash($val, $prefs, \@strings, 0);
	push @menu, replayGainHash($val, $prefs, \@strings, 1);
	push @menu, replayGainHash($val, $prefs, \@strings, 2);
	push @menu, replayGainHash($val, $prefs, \@strings, 3);

	sliceAndShip($request, $client, \@menu);
}


sub sliceAndShip {
	my ($request, $client, $menu) = @_;
	my $numitems = scalar(@$menu);
	my $index    = $request->getParam('_index');
	my $quantity = $request->getParam('_quantity');

	$request->addResult("count", $numitems);
	my ($valid, $start, $end) = $request->normalize(scalar($index), scalar($quantity), $numitems);

	if ($valid) {
		my $cnt = 0;
		$request->addResult('offset', $start);

		for my $eachmenu (@$menu[$start..$end]) {
			$request->setResultLoopHash('item_loop', $cnt, $eachmenu);
			$cnt++;
		}
	}
	$request->setStatusDone()
}

sub playerSettingsMenu {

	my $client = shift;
	my $batch = shift;

	my @menu = ();
	return \@menu unless $client;
 
	$log->debug("Begin Function");
 

	# always add repeat
	my $repeat_setting = Slim::Player::Playlist::repeat($client);
	my @repeat_strings = ('OFF', 'SONG', 'PLAYLIST',);
	my @translated_repeat_strings = map { ucfirst(Slim::Utils::Strings::string($_)) } @repeat_strings;
	my @repeatChoiceActions;
	for my $i (0..$#repeat_strings) {
		push @repeatChoiceActions, 
		{
			player => 0,
			cmd    => ['playlist', 'repeat', "$i"],
		};
	}
	push @menu, {
		text           => Slim::Utils::Strings::string("REPEAT"),
		id             => 'settingsRepeat',
		node           => 'settings',
		displayWhenOff => 0,
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

	# always add shuffle
	my $shuffle_setting = Slim::Player::Playlist::shuffle($client);
	my @shuffle_strings = ( 'OFF', 'SONG', 'ALBUM',);
	my @translated_shuffle_strings = map { ucfirst(Slim::Utils::Strings::string($_)) } @shuffle_strings;
	my @shuffleChoiceActions;
	for my $i (0..$#repeat_strings) {
		push @shuffleChoiceActions, 
		{
			player => 0,
			cmd => ['playlist', 'shuffle', "$i"],
		};
	}
	push @menu, {
		text           => Slim::Utils::Strings::string("SHUFFLE"),
		id             => 'settingsShuffle',
		node           => 'settings',
		selectedIndex  => $shuffle_setting + 1,
		displayWhenOff => 0,
		weight         => 10,
		choiceStrings  => [ @translated_shuffle_strings ],
		actions        => {
			do => {
				choices => [
					@shuffleChoiceActions
				],
			},
		},
		window         => { titleStyle => 'settings' },
	};

	# add alarm only if this is a slimproto player
	if ($client->isPlayer()) {
		push @menu, {
			text           => Slim::Utils::Strings::string("ALARM"),
			id             => 'settingsAlarm',
			node           => 'settings',
			displayWhenOff => 0,
			weight         => 30,
			actions        => {
				go => {
					cmd    => ['alarmsettings'],
					player => 0,
				},
			},
			window         => { titleStyle => 'settings' },
		};
	}

	# sleep setting (always)
	push @menu, {
		text           => Slim::Utils::Strings::string("SLEEP"),
		id             => 'settingsSleep',
		node           => 'settings',
		displayWhenOff => 0,
		weight         => 40,
		actions        => {
			go => {
				cmd    => ['sleepsettings'],
				player => 0,
			},
		},
		window         => { titleStyle => 'settings' },
	};	

	# synchronization. only if numberOfPlayers > 1
	my $synchablePlayers = howManyPlayersToSyncWith($client);
	if ($synchablePlayers > 0) {
		push @menu, {
			text           => Slim::Utils::Strings::string("SYNCHRONIZE"),
			id             => 'settingsSync',
			node           => 'settings',
			displayWhenOff => 0,
			weight         => 70,
			actions        => {
				go => {
					cmd    => ['syncsettings'],
					player => 0,
				},
			},
			window         => { titleStyle => 'settings' },
		};	
	}

	# information, always display
	my $playerInfoText = sprintf(Slim::Utils::Strings::string('INFORMATION_SPECIFIC_PLAYER'), $client->name());
	my $playerInfoTextArea = 
			Slim::Utils::Strings::string("INFORMATION_PLAYER_NAME_ABBR") . ": " . 
			$client->name() . "\n\n" . 
			Slim::Utils::Strings::string("INFORMATION_PLAYER_MODEL_ABBR") . ": " .
			Slim::Buttons::Information::playerModel($client) . "\n\n" .
			Slim::Utils::Strings::string("INFORMATION_FIRMWARE_ABBR") . ": " . 
			$client->revision() . "\n\n" .
			Slim::Utils::Strings::string("INFORMATION_PLAYER_IP_ABBR") . ": " .
			$client->ip() . "\n\n" .
			Slim::Utils::Strings::string("INFORMATION_PLAYER_PORT_ABBR") . ": " .
			$client->port() . "\n\n" .
			Slim::Utils::Strings::string("INFORMATION_PLAYER_MAC_ABBR") . ": " .
			uc($client->macaddress());
	push @menu, {
		text           => $playerInfoText,
		id             => 'settingsPlayerInformation',
		node           => 'advancedSettings',
		displayWhenOff => 0,
		textArea       => $playerInfoTextArea,
		weight         => 4,
		window         => { titleStyle => 'settings' },
		actions        => {
				go =>	{
						# this is a dummy command...doesn't do anything but is required
						cmd    => ['playerinformation'],
						player => 0,
					},
				},
	};


	# player name change, always display
	push @menu, {
		text           => Slim::Utils::Strings::string('INFORMATION_PLAYER_NAME'),
		id             => 'settingsPlayerNameChange',
		node           => 'advancedSettings',
		displayWhenOff => 0,
		input          => {	
			initialText  => $client->name(),
			len          => 1, # For those that want to name their player "X"
			allowedChars => Slim::Utils::Strings::string('JIVE_ALLOWEDCHARS_WITHCAPS'),
			help         => {
				           text => Slim::Utils::Strings::string('JIVE_CHANGEPLAYERNAME_HELP')
			},
			softbutton1  => Slim::Utils::Strings::string('INSERT'),
			softbutton2  => Slim::Utils::Strings::string('DELETE'),
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
		window         => { titleStyle => 'settings' },
	};


	# transition only for Sb2 and beyond (aka 'crossfade')
	if ($client->isa('Slim::Player::Squeezebox2')) {
		push @menu, {
			text           => Slim::Utils::Strings::string("SETUP_TRANSITIONTYPE"),
			id             => 'settingsXfade',
			node           => 'advancedSettings',
			displayWhenOff => 0,
			actions        => {
				go => {
					cmd    => ['crossfadesettings'],
					player => 0,
				},
			},
			window         => { titleStyle => 'settings' },
		};	
	}

	# replay gain (aka volume adjustment)
	if ($client->canDoReplayGain(0)) {
		push @menu, {
			displayWhenOff => 0,
			text           => Slim::Utils::Strings::string("REPLAYGAIN"),
			id             => 'settingsReplayGain',
			node           => 'advancedSettings',
			actions        => {
				  go => {
					cmd    => ['replaygainsettings'],
					player => 0,
				  },
			},
			window         => { titleStyle => 'settings' },
		};	
	}


	if ($batch) {
		return \@menu;
	} else {
		_notifyJive(\@menu, $client);
	}
}

sub _clientId {
	my $client = shift;
	my $id = 'all';
	if ( blessed($client) && $client->id() ) {
		$id = $client->id();
	}
	return $id;
}
	
sub _notifyJive {
	my $menu = shift;
	my $client = shift || undef;
	my $id = _clientId($client);
	my $menuForExport = _purgeMenu($menu);
	Slim::Control::Request::notifyFromArray( $client, [ 'menustatus', $menuForExport, 'add', $id ] );
}

sub howManyPlayersToSyncWith {
	my $client = shift;
	my @playerSyncList = Slim::Player::Client::clients();
	my $synchablePlayers = 0;
	for my $player (@playerSyncList) {
		# skip ourself
		next if ($client eq $player);
		# we only sync slimproto devices
		next if (!$player->isPlayer());
		$synchablePlayers++;
	}
	return $synchablePlayers;
}

sub getPlayersToSyncWith() {
	my $client = shift;
	my @playerSyncList = Slim::Player::Client::clients();
	my @return = ();
	for my $player (@playerSyncList) {
		# skip ourself
		next if ($client eq $player);
		# we only sync slimproto devices
		next if (!$player->isPlayer());
		my $val = Slim::Player::Sync::isSyncedWith($client, $player); 
		push @return, { 
			text => $player->name(), 
			checkbox => ($val == 1) + 0,
			actions  => {
				on  => {
					player => 0,
					cmd    => ['sync', $player->id()],
				},
				off => {
					player => $player->id(),
					cmd    => ['sync', '-'],
				},
			},		
		};
	}
	return \@return;
}

sub dateQuery {
	my $request = shift;

	if ( $request->isNotQuery([['date']]) ) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# Calculate the time zone offset, taken from Time::Timezone
	my $time = time();
	my @l    = localtime($time);
	my @g    = gmtime($time);

	my $off 
		= $l[0] - $g[0]
		+ ( $l[1] - $g[1] ) * 60
		+ ( $l[2] - $g[2] ) * 3600;

	# subscript 7 is yday.

	if ( $l[7] == $g[7] ) {
		# done
	}
	elsif ( $l[7] == $g[7] + 1 ) {
		$off += 86400;
	}
	elsif ( $l[7] == $g[7] - 1 ) {
			$off -= 86400;
	} 
	elsif ( $l[7] < $g[7] ) {
		# crossed over a year boundry!
		# localtime is beginning of year, gmt is end
		# therefore local is ahead
		$off += 86400;
	}
	else {
		$off -= 86400;
	}

	my $hour = int($off / 3600);
	if ( $hour > -10 && $hour < 10 ) {
		$hour = "0" . abs($hour);
	}
	else {
		$hour = abs($hour);
	}

	my $tzoff = ( $off >= 0 ) ? '+' : '-';
	$tzoff .= sprintf( "%s:%02d", $hour, int( $off % 3600 / 60 ) );

	# Return time in http://www.w3.org/TR/NOTE-datetime format
	$request->addResult( 'date', strftime("%Y-%m-%dT%H:%M:%S", localtime) . $tzoff );

	$request->setStatusDone();
}

sub firmwareUpgradeQuery {
	my $request = shift;

	if ( $request->isNotQuery([['firmwareupgrade']]) ) {
		$request->setStatusBadDispatch();
		return;
	}

	my $firmwareVersion = $request->getParam('firmwareVersion');
	
	# always send the upgrade url this is also used if the user opts to upgrade
	if ( my $url = Slim::Utils::Firmware->jive_url() ) {
		$request->addResult( firmwareUrl => $url );
	}
	
	if ( Slim::Utils::Firmware->jive_needs_upgrade( $firmwareVersion ) ) {
		# if this is true a firmware upgrade is forced
		$request->addResult( firmwareUpgrade => 1 );
	}
	else {
		$request->addResult( firmwareUpgrade => 0 );
	}
	
	$request->setStatusDone();
}

sub alarmOnHash {
	my ($client, $prefs, $day) = @_;
	my $val = $prefs->client($client)->get('alarm')->[ $day ];
	my %return = (
		text     => Slim::Utils::Strings::string("ENABLED"),
		checkbox => ($val == 1) + 0,
		actions  => {
			on  => {
				player => 0,
				cmd    => ['alarm'],
				params => { 
					cmd     => 'set',
					dow     => $day,
					enabled => 1,
				},
			},
			off => {
				player => 0,
				cmd    => ['alarm'],
				params => { 
					cmd     => 'set',
					dow     => $day,
					enabled => 0,
				},
			},
		},
	);
	return \%return;
}

sub alarmSetHash {
	my ($client, $prefs, $day) = @_;
	my $current_setting = $prefs->client($client)->get('alarmtime')->[ $day ];
	my %return = 
	( 
		text    => Slim::Utils::Strings::string("ALARM_SET"),
		input   => {
			initialText  => $current_setting, # this will need to be formatted correctly
			_inputStyle  => 'time',
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
					dow =>	$day,
					time => '__TAGGEDINPUT__',	
				},
			},
		},
	);
	return \%return;
}

sub alarmPlaylistHash {
	my ($client, $prefs, $day) = @_;
	my $alarm_playlist = $prefs->client($client)->get('alarmplaylist')->[ $day ];
	my @allPlaylists = (
		{
			text    => Slim::Utils::Strings::string("CURRENT_PLAYLIST"),
			radio	=> ($alarm_playlist == -1) + 0, # 0 is added to force the data type to number
			actions => {
				do => {
					player => 0,
					cmd    => ['alarms'],
					params => {
						playlist_id => '-1',
						dow         => $day,
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
						dow         => $day,
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
						dow         => $day,
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
						dow         => $day,
					},
				},
			},
		},
	);
	## here we need to figure out how to populate the remaining playlist items from saved playlists
	push @allPlaylists, getCustomPlaylists($client);

	my %return = 
	( 
		text => Slim::Utils::Strings::string("ALARM_SELECT_PLAYLIST"),
		count     => 4,
		offset    => 0,
		item_loop => \@allPlaylists,
	);
	return \%return;
}

sub getCustomPlaylists {
	my @return = ();
	return \@return;
}

sub alarmVolumeHash {
	my ($client, $prefs, $day) = @_;
	my $current_setting = $prefs->client($client)->get('alarmvolume')->[ $day ];
	my @vol_settings;
	for (my $i = 10; $i <= 100; $i = $i + 10) {
		my %hash = (
			text    => $i,
			radio   => ($i == $current_setting) + 0,
			actions => {
				do => {
					player => 0,
					cmd    => ['alarm'],
					params => {
						cmd => 'set',
						volume => $i,
						dow => $day,
					},
				},
			},
		);
		push @vol_settings, \%hash;
	}
	my %return = 
	( 
		text      => Slim::Utils::Strings::string("ALARM_SET_VOLUME"),
		count     => 10,
		offset    => 0,
		item_loop => \@vol_settings,
	);
	return \%return;
}

sub alarmFadeHash {
	my ($client, $prefs, $day) = @_;
	my $current_setting = $prefs->client($client)->get('alarmfadeseconds');
	my %return = 
	( 
		text     => Slim::Utils::Strings::string("ALARM_FADE"),
		checkbox => ($current_setting > 0) + 0,
		actions  => {
			on  => {
				player => 0,
				cmd    => ['alarm'],
				params => { 
					cmd     => 'set',
					dow     => 0,
					fade    => 1,
				},
			},
			off  => {
				player => 0,
				cmd    => ['alarm'],
				params => { 
					cmd     => 'set',
					dow     => 0,
					fade    => 0,
				},
			},
		},
	);
	return \%return;
}

sub populateAlarmElements {
	my $client = shift;
	my $day = shift;
	my $prefs = preferences("server");

	my $alarm_on       = alarmOnHash($client, $prefs, $day);
	my $alarm_set      = alarmSetHash($client, $prefs, $day);
	my $alarm_playlist = alarmPlaylistHash($client, $prefs, $day);
	my $alarm_volume   = alarmVolumeHash($client, $prefs, $day);
	my $alarm_fade     = alarmFadeHash($client, $prefs, $day);

	my @return = ( 
		$alarm_on,
		$alarm_set,
		$alarm_playlist,
		$alarm_volume,
	);
	push @return, $alarm_fade if $day == 0;
	#Data::Dump::dump(@return) if $day == 1;
	return \@return;
}

sub populateAlarmHash {
	my $client = shift;
	my $day = shift;
	my $elements = populateAlarmElements($client, $day);
	my $string = 'ALARM_DAY' . $day;
	my %return = (
		text      => Slim::Utils::Strings::string($string),
		count     => scalar(@$elements),
		offset    => 0,
		item_loop => $elements,
	);
	return \%return;
}

sub playerPower {

	my $client = shift;
	my $batch = shift;
	my $name  = $client->name();
	my $power = $client->power();
	my @return; 
	my ($text, $action);

	if ($power == 1) {
		$text = sprintf(Slim::Utils::Strings::string('JIVE_TURN_PLAYER_OFF'), $name);
		$action = 0;
	} else {
		$text = sprintf(Slim::Utils::Strings::string('JIVE_TURN_PLAYER_ON'), $name);
		$action = 1;
	}

	push @return, {
		text           => $text,
		id             => 'playerpower',
		node           => 'home',
		displayWhenOff => 1,
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
	my ($val, $sleepTime) = @_;
	my $minutes = Slim::Utils::Strings::string('MINUTES');
	my $text = $sleepTime == 0 ? 
		Slim::Utils::Strings::string("SLEEP_CANCEL") :
		$sleepTime . " " . $minutes;
	my %return = ( 
		text    => $text,
		radio	=> ($val == ($sleepTime*60)) + 0, # 0 is added to force the data type to number
		actions => {
			do => {
				player => 0,
				cmd => ['sleep', $sleepTime*60 ],
			},
		},
	);
	return \%return;
}

sub repeatHash {
	my ($val, $strings, $thisValue) = @_;
	my %return = (
		text    => Slim::Utils::Strings::string($strings->[$thisValue]),
		radio	=> ($val == $thisValue) + 0, # 0 is added to force data type to number
		actions => {
			do => {
				player => 0,
				cmd => ['playlist', 'repeat', "$thisValue" ],
			},
		},
	);
	return \%return;
}

sub transitionHash {
	
	my ($val, $prefs, $strings, $thisValue) = @_;
	my %return = (
		text    => Slim::Utils::Strings::string($strings->[$thisValue]),
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
	
	my ($val, $prefs, $strings, $thisValue) = @_;
	my %return = (
		text    => Slim::Utils::Strings::string($strings->[$thisValue]),
		radio	=> ($val == $thisValue) + 0, # 0 is added to force the data type to number
			actions => {
			do => {
				player => 0,
				cmd => ['replayGainMode', "$thisValue"],
			},
		},
	);
	return \%return;
}

sub myMusicMenu {
	my $batch = shift;
	my $client = shift || undef;
	my @myMusicMenu = (
			{
				text           => Slim::Utils::Strings::string('BROWSE_BY_ARTIST'),
				id             => 'myMusicArtists',
				node           => 'myMusic',
				displayWhenOff => 0,
				weight         => 10,
				actions        => {
					go => {
						cmd    => ['artists'],
						params => {
							menu => 'album',
						},
					},
				},
				window        => {
					titleStyle => 'artists',
				},
			},		
			{
				text           => Slim::Utils::Strings::string('BROWSE_BY_ALBUM'),
				id             => 'myMusicAlbums',
				node           => 'myMusic',
				weight         => 20,
				displayWhenOff => 0,
				actions        => {
					go => {
						cmd    => ['albums'],
						params => {
							menu     => 'track',
						},
					},
				},
				window         => {
					menuStyle => 'album',
					menuStyle => 'album',
					titleStyle => 'albumlist',
				},
			},
			{
				text           => Slim::Utils::Strings::string('BROWSE_BY_GENRE'),
				id             => 'myMusicGenres',
				node           => 'myMusic',
				displayWhenOff => 0,
				weight         => 30,
				actions        => {
					go => {
						cmd    => ['genres'],
						params => {
							menu => 'artist',
						},
					},
				},
				window        => {
					titleStyle => 'genres',
				},
			},
			{
				text           => Slim::Utils::Strings::string('BROWSE_BY_YEAR'),
				id             => 'myMusicYears',
				node           => 'myMusic',
				displayWhenOff => 0,
				weight         => 40,
				actions        => {
					go => {
						cmd    => ['years'],
						params => {
							menu => 'album',
						},
					},
				},
				window        => {
					titleStyle => 'years',
				},
			},
			{
				text           => Slim::Utils::Strings::string('BROWSE_NEW_MUSIC'),
				id             => 'myMusicNewMusic',
				node           => 'myMusic',
				displayWhenOff => 0,
				weight         => 50,
				actions        => {
					go => {
						cmd    => ['albums'],
						params => {
							menu => 'track',
							sort => 'new',
						},
					},
				},
				window        => {
					menuStyle => 'album',
					titleStyle => 'newmusic',
				},
			},
			{
				text           => Slim::Utils::Strings::string('BROWSE_MUSIC_FOLDER'),
				id             => 'myMusicMusicFolder',
				node           => 'myMusic',
				displayWhenOff => 0,
				weight         => 70,
				actions        => {
					go => {
						cmd    => ['musicfolder'],
						params => {
							menu => 'musicfolder',
						},
					},
				},
				window        => {
					titleStyle => 'musicfolder',
				},
			},
			{
				text           => Slim::Utils::Strings::string('SAVED_PLAYLISTS'),
				id             => 'myMusicPlaylists',
				node           => 'myMusic',
				displayWhenOff => 0,
				weight         => 80,
				actions        => {
					go => {
						cmd    => ['playlists'],
						params => {
							menu => 'track',
						},
					},
				},
				window        => {
					titleStyle => 'playlist',
				},
			},
			{
				text           => Slim::Utils::Strings::string('SEARCH'),
				id             => 'myMusicSearch',
				node           => 'myMusic',
				isANode        => 1,
				displayWhenOff => 0,
				weight         => 90,
				window         => { titleStyle => 'search', },
			},
		);
	# add the items for under mymusicSearch
	my $searchMenu = searchMenu(1);
	@myMusicMenu = (@myMusicMenu, @$searchMenu);

	if ($batch) {
		return \@myMusicMenu;
	} else {
		_notifyJive(\@myMusicMenu, $client);
	}

}

sub searchMenu {
	my $batch = shift;
	my $client = shift || undef;
	my @searchMenu = (
	{
		text           => Slim::Utils::Strings::string('ARTISTS'),
		id             => 'myMusicSearchArtists',
		node           => 'myMusicSearch',
		displayWhenOff => 0,
		weight         => 10,
		input => {
			len  => 1, #bug 5318
			help => {
				text => Slim::Utils::Strings::string('JIVE_SEARCHFOR_HELP')
			},
		},
		actions => {
			go => {
				cmd => ['artists'],
				params => {
					menu     => 'album',
					menu_all => '1',
					search   => '__TAGGEDINPUT__',
					_searchType => 'artists',
				},
                        },
		},
                window => {
                        text => Slim::Utils::Strings::string('SEARCHFOR_ARTISTS'),
                        titleStyle => 'search',
                },
	},
	{
		text           => Slim::Utils::Strings::string('ALBUMS'),
		id             => 'myMusicSearchAlbums',
		node           => 'myMusicSearch',
		displayWhenOff => 0,
		weight         => 20,
		input => {
			len  => 1, #bug 5318
			help => {
				text => Slim::Utils::Strings::string('JIVE_SEARCHFOR_HELP')
			},
		},
		actions => {
			go => {
				cmd => ['albums'],
				params => {
					menu     => 'track',
					search   => '__TAGGEDINPUT__',
					_searchType => 'albums',
				},
			},
		},
		window => {
			text => Slim::Utils::Strings::string('SEARCHFOR_ALBUMS'),
			titleStyle => 'search',
			menuStyle  => 'album',
		},
	},
	{
		text           => Slim::Utils::Strings::string('SONGS'),
		id             => 'myMusicSearchSongs',
		node           => 'myMusicSearch',
		displayWhenOff => 0,
		weight         => 30,
		input => {
			len  => 1, #bug 5318
			help => {
				text => Slim::Utils::Strings::string('JIVE_SEARCHFOR_HELP')
			},
		},
		actions => {
			go => {
				cmd => ['tracks'],
				params => {
					menu     => 'track',
					menu_all => '1',
					search   => '__TAGGEDINPUT__',
					_searchType => 'tracks',
				},
                        },
		},
		window => {
			text => Slim::Utils::Strings::string('SEARCHFOR_SONGS'),
			titleStyle => 'search',
		},
	},
	{
		text           => Slim::Utils::Strings::string('PLAYLISTS'),
		id             => 'myMusicSearchPlaylists',
		node           => 'myMusicSearch',
		displayWhenOff => 0,
		weight         => 40,
		input => {
			len  => 1, #bug 5318
			help => {
				text => Slim::Utils::Strings::string('JIVE_SEARCHFOR_HELP')
			},
		},
		actions => {
			go => {
				cmd => ['playlists'],
				params => {
					menu     => 'track',
					search   => '__TAGGEDINPUT__',
				},
                        },
		},
		window => {
			text => Slim::Utils::Strings::string('SEARCHFOR_PLAYLISTS'),
			titleStyle => 'search',
		},
	},
	);

	if ($batch) {
		return \@searchMenu;
	} else {
		_notifyJive(\@searchMenu, $client);
	}

}

# The following allow download of applets, wallpaper and sounds from SC to jive
# Files may be packaged in a plugin or can be added individually via the api below.
#
# In the case of downloads packaged as a plugin, each downloadable file should be 
# available in the 'jive' folder of a plugin and the plugin install.xml file should refer
# to it in the following format:
#
# <jive>
#    <applet>
#       <version>0.1</version>
#       <name>Applet1</name>
#       <file>Applet1.zip</file>
#    </applet>
#    <wallpaper>
#       <name>Wallpaper1</name>
#       <file>Wallpaper1.png</file>
#    </wallpaper>			
#    <wallpaper>
#       <name>Wallpaper2</name>
#       <file>Wallpaper2.png</file>
#    </wallpaper>	
#    <sound>
#       <name>Sound1</name>
#       <file>Sound1.wav</file>
#    </sound>	
# </jive>
#
# Alternatively individual wallpaper and sound files may be registered by the 
# registerDownload and deleteDownload api calls.

# file types allowed for downloading to jive
my %filetypes = (
	applet    => qr/\.zip$/,
	wallpaper => qr/\.(bmp|jpeg|png)$/,
	sound     => qr/\.wav$/,
);

# addditional downloads
my %extras = (
	wallpaper => {},
	sound     => {},
);

=head2 registerDownload()

Register a local file or url for downloading to jive as a wallpaper or sound file.
$type : either 'wallpaper' or 'sound'
$name : description to show on jive
$path : fullpath for file on server or http:// url

=cut

sub registerDownload {
	my $type = shift;
	my $name = shift;
	my $path = shift;

	my $file = basename($path);

	if ($type =~ /wallpaper|sound/ && $file =~ $filetypes{$type} && (-r $path || $path =~ /^http:\/\//)) {

		$log->info("registering download for $type $file $path");

		$extras{$type}->{$file} = {
			'name'    => $name,
			'path'    => $path,
			'file'    => $file,
		};

	} else {
		$log->warn("unable to register download for $type $file");
	}
}

=head2 deleteDownload()

Remove previously registered download entry.
$type : either 'wallpaper' or 'sound'
$path : fullpath for file on server or http:// url

=cut

sub deleteDownload {
	my $type = shift;
	my $path = shift;

	my $file = basename($path);

	if ($type =~ /wallpaper|sound/ && $extras{$type}->{$file}) {

		$log->info("removing download for $type $file");
		delete $extras{$type}->{$file};

	} else {
		$log->warn("unable remove download for $type $file");
	}
}

# downloadable file info from the plugin instal.xml and any registered additions
sub _downloadInfo {
	my $type = shift;

	my $plugins = Slim::Utils::PluginManager::allPlugins();
	my $ret = {};

	for my $key (keys %$plugins) {

		if ($plugins->{$key}->{'jive'} && $plugins->{$key}->{'jive'}->{$type}) {

			my $info = $plugins->{$key}->{'jive'}->{$type};
			my $dir  = $plugins->{$key}->{'basedir'};

			if ($info->{'name'}) {

				my $file = $info->{'file'};

				if ( $file =~ $filetypes{$type} && -r catdir($dir, 'jive', $file) ) {

					if ($ret->{$file}) {
						$log->warn("duplicate filename for download: $file");
					}

					$ret->{$file} = {
						'name'    => $info->{'name'},
						'path'    => catdir($dir, 'jive', $file),
						'file'    => $file,
						'version' => $info->{'version'},
					};

				} else {
					$log->warn("unable to make $key:$file available for download");
				}

			} elsif (ref $info eq 'HASH') {

				for my $name (keys %$info) {

					my $file = $info->{$name}->{'file'};

					if ( $file =~ $filetypes{$type} && -r catdir($dir, 'jive', $file) ) {

						if ($ret->{$file}) {
							$log->warn("duplicate filename for download: $file [$key]");
						}

						$ret->{$file} = {
							'name'    => $name,
							'path'    => catdir($dir, 'jive', $file),
							'file'    => $file,
							'version' => $info->{$name}->{'version'},
						};

					} else {
						$log->warn("unable to make $key:$file available for download");
					}
				}
			}
		}
	}

	# add extra downloads as registered via api
	for my $key (keys %{$extras{$type}}) {
		$ret->{$key} = $extras{$type}->{$key};
	}

	return $ret;
}

sub jiveFavoritesQuery {

	# work-in-progress; not called from anywhere yet
	my $request = shift;
	my $title   = $request->getParam('title');
	my $url     = $request->getParam('url');
	
	$log->warn('BENDEBUG: ' . $title . "|" . $url);
	my $actions = {
		'go' => {
			player => 0,
			cmd    => [ 'favorites', 'add' ],
			params => {
					title => $title,
					url   => 'file://' . $url
			},
		},
	};
	$request->addResult('count', 2);
	$request->addResult('offset', 0);
	$request->addResultLoop('item_loop', 0, 'text', Slim::Utils::Strings::string('JIVE_ADD_TO_FAVORITES'));
	$request->addResultLoop('item_loop', 0, 'actions', $actions);
	$request->addResultLoop('item_loop', 1, 'text', Slim::Utils::Strings::string('CANCEL'));

	$request->setStatusDone();

}


# return all files available for download based on query type
sub downloadQuery {
	my $request = shift;
 
	$log->debug("Begin Function");
 
	my ($type) = $request->getRequest(0) =~ /jive(applet|wallpaper|sound)s/;

	if (!defined $type) {
		$request->setStatusBadDispatch();
		return;
	}

	my $prefs = preferences("server");

	my $cnt = 0;
	my $urlBase = 'http://' . Slim::Utils::Network::serverAddr() . ':' . $prefs->get('httpport') . "/jive$type/";

	for my $val ( sort { $a->{'name'} cmp $b->{'name'} } values %{_downloadInfo($type)} ) {

		my $url = $val->{'path'} =~ /^http:\/\// ? $val->{'path'} : $urlBase . $val->{'file'};

		my $entry = {
			$type     => $val->{'name'},
			'name'    => Slim::Utils::Strings::getString($val->{'name'}),
			'url'     => $url,
			'file'    => $val->{'file'},
		};

		if ($type eq 'applet') {
			$entry->{'version'} = $val->{'version'};
		}
		$request->setResultLoopHash('item_loop', $cnt++, $entry);
	}	

	$request->addResult("count", $cnt);

	$request->setStatusDone();
}

# convert path to location for download
sub downloadFile {
	my $path = shift;

	my ($type, $file) = $path =~ /^jive(applet|wallpaper|sound)\/(.*)/;

	my $info = _downloadInfo($type);

	if ($info->{$file}) {

		return $info->{$file}->{'path'};

	} else {

		$log->warn("unable to find file: $file for type: $type");
	}
}

# send a notification for menustatus
sub menuNotification {
	$log->warn("Menustatus notification sent.");
	# the lines below are needed as menu notifications are done via notifyFromArray, but
	# if you wanted to debug what's getting sent over the Comet interface, you could do it here
	my $request  = shift;
	my $dataRef          = $request->getParam('_data')   || return;
	my $action   	     = $request->getParam('_action') || 'add';
#	$log->warn(Data::Dump::dump($dataRef));
}

1;
