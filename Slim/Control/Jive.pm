package Slim::Control::Jive;

# Copyright 2001-2011 Logitech
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;

use POSIX qw(strftime);
use Scalar::Util qw(blessed);
use URI;

use Slim::Menu::BrowseLibrary;
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Player::Client;
#use Data::Dump;

{
	if (main::LOCAL_PLAYERS) {
		require Slim::Control::LocalPlayers::Jive;
	}
}

my $prefs   = preferences("server");

=head1 NAME

Slim::Control::Jive

=head1 SYNOPSIS

CLI commands used by Jive.

=cut

my $log = logger('player.jive');

# additional top level menus registered by plugins
my @appMenus           = (); # all available apps
my @pluginMenus        = (); # all non-app plugins
my @recentSearches     = ();

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

	if (main::LOCAL_PLAYERS) {
		Slim::Control::LocalPlayers::Jive::init($class);
	}
	
	Slim::Control::Request::addDispatch(['menu', '_index', '_quantity'], 
		[2, 1, 1, \&menuQuery]);

	Slim::Control::Request::addDispatch(['jivealbumsortsettings'],
		[1, 0, 1, \&albumSortSettingsMenu]);

	Slim::Control::Request::addDispatch(['jivesetalbumsort'],
		[1, 0, 1, \&jiveSetAlbumSort]);

	Slim::Control::Request::addDispatch(['jiverecentsearches'],
		[0, 1, 0, \&jiveRecentSearchQuery]);

	Slim::Control::Request::addDispatch(['date'],
		[0, 1, 1, \&dateQuery]);

	Slim::Control::Request::addDispatch(['firmwareupgrade'],
		[0, 1, 1, \&firmwareUpgradeQuery]);

	Slim::Control::Request::addDispatch(['jiveapplets'],
		[0, 1, 1, \&extensionsQuery]);

	Slim::Control::Request::addDispatch(['jivewallpapers'],
		[0, 1, 1, \&extensionsQuery]);

	Slim::Control::Request::addDispatch(['jivesounds'],
		[0, 1, 1, \&extensionsQuery]);

	Slim::Control::Request::addDispatch(['jivepatches'],
		[0, 1, 1, \&extensionsQuery]);
	
	# setup the menustatus dispatch and subscription
	Slim::Control::Request::addDispatch( ['menustatus', '_data', '_action'],
		[0, 0, 0, sub { warn "menustatus query\n" }]);
	
	if ( $log->is_info ) {
		Slim::Control::Request::subscribe( \&menuNotification, [['menustatus']] );
	}
	
	# setup a cli command for jive that returns nothing; can be useful in some situations
	Slim::Control::Request::addDispatch( ['jiveblankcommand'],
		[0, 0, 0, sub { return 1; }]);
	
}

sub _libraryChanged {
	foreach ( Slim::Player::Client::clients() ) {
		myMusicMenu(0, $_);
	}
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

	main::INFOLOG && $log->info("Begin menuQuery function");

	if ($request->isNotQuery([['menu']])) {
		$request->setStatusBadDispatch();
		return;
	}

	my $client = $request->client() || 0;
	my $disconnected;
	
	if ( !$client ) {
		require Slim::Player::Disconnected;
		
		# Check if this is a disconnected player request
		if ( my $id = $request->disconnectedClientID ) {
			# On SN, if the player does not exist in the database this is a fatal error
			if ( main::SLIM_SERVICE ) {
				my ($player) = SDI::Service::Model::Player->search( { mac => $id } );
				if ( !$player ) {
					main::INFOLOG && $log->is_info && $log->info("Player $id does not exist in SN database");
					$request->setStatusBadDispatch();
					return;
				}
			}
			
			$client = Slim::Player::Disconnected->new($id);
			$disconnected = 1;
			
			main::INFOLOG && $log->is_info && $log->info("Player $id not connected, using disconnected menu mode");
		}
		else {
			# XXX temporary workaround for requests without a playerid
			$client = Slim::Player::Disconnected->new( '_dummy_' . Time::HiRes::time() );
			$disconnected = 1;
			
			$log->error("Menu requests without a client are deprecated, using disconnected menu mode");
		}
	}
	
	my $direct = ( $disconnected || $request->getParam('direct') ) ? 1 : 0;

	# send main menu notification
	my $menu = mainMenu($client, $direct);
	
	# Return results directly and destroy the client if it is disconnected
	# Also return the results directly if param 'direct' is set
	if ( $direct ) {
		$log->is_info && $log->info('Sending direct menu response');
		
		$request->setRawResults( {
			count     => scalar @{$menu},
			offset    => 0,
			item_loop => $menu,
		} );
		
		if ( $disconnected ) {
			$client->forgetClient;
		}
	}
	
	$request->setStatusDone();
}

sub mainMenu {

	main::INFOLOG && $log->info("Begin function");
	my $client = shift;
	my $direct = shift;
	
	unless ($client && $client->isa('Slim::Player::Client')) {
		# if this isn't a player, no menus should get sent
		return;
	}
 
	# as a convention, make weights => 10 and <= 100; Jive items that want to be below all SS items
	# then just need to have a weight > 100, above SS items < 10

	# for the notification menus, we're going to send everything over "flat"
	# as a result, no item_loops, all submenus (setting, myMusic) are just elements of the big array that get sent

	my @menu = map {
		_localizeMenuItemText( $client, $_ );
	}(
		main::SLIM_SERVICE ? () : {
			stringToken    => 'MY_MUSIC',
			weight         => 11,
			id             => 'myMusic',
			isANode        => 1,
			node           => 'home',
		},
		!main::LOCAL_PLAYERS ? () : {
			stringToken    => 'FAVORITES',
			id             => 'favorites',
			node           => 'home',
			weight         => 100,
			actions => {
				go => {
					cmd => ['favorites', 'items'],
					params => {
						menu     => 'favorites',
					},
				},
			},
		},

		@{pluginMenus($client)},
		!main::LOCAL_PLAYERS ? () : @{Slim::Control::LocalPlayers::Jive::playerPower($client, 1)},
		!main::LOCAL_PLAYERS ? () : @{Slim::Control::LocalPlayers::Jive::playerSettingsMenu($client, 1)},
		!main::LOCAL_PLAYERS ? () : @{
			# The Digital Input plugin could be disabled
			if( Slim::Utils::PluginManager->isEnabled('Slim::Plugin::DigitalInput::Plugin')) {
				Slim::Plugin::DigitalInput::Plugin::digitalInputItem($client);
			} else {
				[];
			}
		},
		!main::LOCAL_PLAYERS ? () : @{
			# The Line In plugin could be disabled
			if( Slim::Utils::PluginManager->isEnabled('Slim::Plugin::LineIn::Plugin')) {
				Slim::Plugin::LineIn::Plugin::lineInItem($client, 0);
			} else {
				[];
			}
		},
		!main::LOCAL_PLAYERS ? () : @{
			# The Audioscrobbler plugin could be disabled
			if( Slim::Utils::PluginManager->isEnabled('Slim::Plugin::AudioScrobbler::Plugin')) {
				Slim::Plugin::AudioScrobbler::Plugin::jiveSettings($client);
			} else {
				[];
			}
		},
		main::SERVICES ? @{internetRadioMenu($client)} : (),
		main::SLIM_SERVICE ? () : @{albumSortSettingsItem($client, 1)},
		main::SLIM_SERVICE ? () : @{myMusicMenu(1, $client)},
		main::SLIM_SERVICE ? () : @{recentSearchMenu($client, 1)},
		main::SERVICES ? @{appMenus($client, 1)} : (),

		main::SERVICES ? @{globalSearchMenu($client)} : (),		
	);
	
	# Don't send the TuneIn My Presets item if the user doesn't have a TuneIn account
	# XXX LMS support
	if ( main::SLIM_SERVICE && !Slim::Plugin::InternetRadio::Plugin->radiotimeUsername($client) ) {
		@menu = grep { $_->{id} ne 'opmlpresets' } @menu;
	}

	if ( !$direct ) {
		_notifyJive(\@menu, $client);
	}
	
	return \@menu;
}

sub jiveSetAlbumSort {
	my $request = shift;
	my $client  = $request->client;
	my $sort = $request->getParam('sortMe');
	$prefs->set('jivealbumsort', $sort);
	$request->setStatusDone();
}



sub albumSortSettingsMenu {
	main::INFOLOG && $log->info("Begin function");
	my $request = shift;
	my $client = $request->client;
	my $sort    = $prefs->get('jivealbumsort');
	my %sortMethods = (
		artistalbum =>	'SORT_ARTISTALBUM',
		artflow =>	'SORT_ARTISTYEARALBUM',
		album =>	'ALBUM',
	);
	$request->addResult('count', scalar(keys %sortMethods));
	$request->addResult('offset', 0);
	my $i = 0;
	for my $key (sort keys %sortMethods) {
		$request->addResultLoop('item_loop', $i, 'text', $client->string($sortMethods{$key}));
		my $selected = ($sort eq $key) + 0;
		$request->addResultLoop('item_loop', $i, 'radio', $selected);
		my $actions = {
			do => {
				player => 0,
				cmd    => ['jivesetalbumsort'],
				params => {
					'sortMe' => $key,
				},
			},
		};
		$request->addResultLoop('item_loop', $i, 'actions', $actions);
		$i++;
	}
	
}

sub albumSortSettingsItem {
	main::INFOLOG && $log->info("Begin function");
	my $client = shift;
	my $batch = shift;

	my @menu = ();
	push @menu,
	{
		text           => $client->string('ALBUMS_SORT_METHOD'),
		id             => 'settingsAlbumSettings',
		node           => 'advancedSettings',
		iconStyle      => 'hm_advancedSettings',
		weight         => 105,
			actions        => {
			go => {
				cmd => ['jivealbumsortsettings'],
				params => {
					menu => 'radio',
				},
			},
		},
	};

	if ($batch) {
		return \@menu;
	} else {
		_notifyJive(\@menu, $client);
	}

}

# allow a plugin to add a node to the menu
# XXX what uses this?
sub registerPluginNode {
	main::INFOLOG && $log->info("Begin function");
	my $nodeRef = shift;
	my $client = shift || undef;
	unless (ref($nodeRef) eq 'HASH') {
		$log->error("Incorrect data type");
		return;
	}

	$nodeRef->{'isANode'} = 1;
	main::INFOLOG && $log->info("Registering node menu item from plugin");

	# notify this menu to be added
	my $id = _clientId($client);
	Slim::Control::Request::notifyFromArray( $client, [ 'menustatus', $nodeRef, 'add', $id ] );

	# but also remember this structure as part of the plugin menus
	push @pluginMenus, $nodeRef;

}

sub registerAppMenu {
	my $menuArray = shift;
	
	# now we want all of the items in $menuArray to go into @pluginMenus, but we also
	# don't want duplicate items (specified by 'id'), 
	# so we want the ids from $menuArray to stomp on ids from @pluginMenus, 
	# thus getting the "newest" ids into the @pluginMenus array of items
	# we also do not allow any hash without an id into the array, and will log an error if that happens

	my $isInfo = $log->is_info;

	my %seen;
	my @new;

	for my $href (@$menuArray, reverse @appMenus) {
		my $id = $href->{id};
		if ($id) {
			if ( !$seen{$id} ) {
				main::INFOLOG && $isInfo && $log->info("registering app menu " . $id);
				push @new, $href;
			}
			$seen{$id}++;
		}
		else {
			$log->error("Menu items cannot be added without an id");
		}
	}

	# @new is the new @appMenus
	# we do this in reverse so we get previously initialized nodes first 
	# you can't add an item to a node that doesn't exist :)
	@appMenus = reverse @new;
}

# send plugin menus array as a notification to Jive
sub refreshPluginMenus {
	main::INFOLOG && $log->info("Begin function");
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
	
	my $isInfo = $log->is_info;

	if ($node) {
		my @menuArray = @$menuArray;
		for my $i (0..$#menuArray) {
			if (!$menuArray->[$i]{'node'}) {
				$menuArray->[$i]{'node'} = $node;
			}
		}
	}

	main::INFOLOG && $isInfo && $log->info("Registering menus from plugin");

	if ( $client ) {
		# notify this menu to be added
		_notifyJive($menuArray, $client);
	}

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
				main::INFOLOG && $isInfo && $log->info("registering menuitem " . $id . " to " . $node );
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
# if the item is a node, then delete its immediate children too
sub deleteMenuItem {
	my $menuId = shift;
	my $client = shift || undef;
	return unless $menuId;
	main::INFOLOG && $log->is_warn && $log->warn($menuId . " menu id slated for deletion");
	
	# send a notification to delete
	# but also remember that this id is not to be sent
	my @menuDelete;
	my @new;
	for my $href (reverse @pluginMenus) {
		next if !$href;
		if (($href->{'id'} && $href->{'id'} eq $menuId)
			|| ($href->{'node'} && $href->{'node'} eq $menuId))
		{
			main::INFOLOG && $log->info("deregistering menuitem ",  $href->{'id'});
			push @menuDelete, $href;
		} else {
			push @new, $href;
		}
	}
	
	push @menuDelete, { id => $menuId };

	_notifyJive(\@menuDelete, $client, 'remove');

	@pluginMenus = reverse @new;
}

# delete all menus items listed in @pluginMenus and @appMenus
# This used to do menu refreshes when apps may have been removed
sub deleteAllMenuItems {
	my $client = shift || return;
	
	my @menuDelete;
	
	for my $menu ( @pluginMenus, @appMenus ) {
		push @menuDelete, { id => $menu->{id} };
	}
	
	main::INFOLOG && $log->is_info && $log->info( $client->id . ' removing menu items: ' . Data::Dump::dump(\@menuDelete) );
	
	_notifyJive( \@menuDelete, $client, 'remove' );
}

sub _purgeMenu {
	my $menu = shift;
	my @menu = @$menu;
	my @purgedMenu = ();
	for my $i (0..$#menu) {
		last unless (defined($menu[$i]));
		push @purgedMenu, $menu[$i];
	}
	return \@purgedMenu;
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

# returns a single item for the homeMenu if radios is a valid command
sub internetRadioMenu {
	main::INFOLOG && $log->info("Begin function");
	my $client = shift;
	
	return () if !main::SERVICES;
	
	my @command = ('radios', 0, 200, 'menu:radio');

	my $test_request = Slim::Control::Request::executeRequest($client, \@command);
	my $validQuery = $test_request->isValidQuery();

	my @menu = ();
	
	if ($validQuery && $test_request->getResult('count')) {
		push @menu,
		{
			text           => $client->string('RADIO'),
			id             => 'radios',
			node           => 'home',
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
			},
		};
	}

	return \@menu;

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
	my ($menu, $client, $action) = @_;
	$action ||= 'add';
	
	my $id = _clientId($client);
	my $menuForExport = $action eq 'add' ? _purgeMenu($menu) : $menu;
	
	$menuForExport = [ map { _localizeMenuItemText( $client, $_ ) } @{$menuForExport} ];
	
	Slim::Control::Request::notifyFromArray( $client, [ 'menustatus', $menuForExport, $action, $id ] );
}

sub dateQuery_filter {
	my ($self, $request) = @_;

	# if time is to be set, pass along the new time value to the listeners
	if (my $newTime = $request->getParam('set')) {
		$self->privateData($newTime);
		return 1;
	}

	$self->privateData(0);
	return 0;
}

sub dateQuery {
	# XXX dateQuery uses registerAutoExecute which is called for every notification!
	# (See Request.pm "send the notification to all filters...")
	# An easy workaround here is to abort on any more params in @_
	return if @_ > 1;
	
	my $request = shift;

	if ( $request->isNotQuery([['date']]) ) {
		$request->setStatusBadDispatch();
		return;
	}
	
	my $newTime = $request->getParam('set') || 0;

	# it time is expliciely set, we'll have to notify our listeners
	if ($newTime) {
		$request->notify();
	}
	else {
		$newTime = $request->privateData() || 0;
		$request->privateData(0);
	}

	# 7.5+ SP devices use epoch time now, much simpler
	$request->addResult( 'date_epoch', $newTime || time() );

	# This is the field 7.3 and earlier players expect.
	#  7.4 is smart enough to take no action when missing
	#  the date_utc field it expects.
	# If they are hitting 7.5 SN/SC code, they're about to
	#  be upgraded anyways, but we should avoid mucking
	#  with their clock in the meantime.  These crafted "all-zeros"
	#  responses will avoid Lua errors, but the "date"
	#  command implemented by busybox will fail out on this
	#  data and take no action due to it resulting in a
	#  negative time_t value.
	$request->addResult( 'date', '0000-00-00T00:00:00+00:00' );

	# manage the subscription
	if (defined(my $timeout = $request->getParam('subscribe'))) {
		$request->registerAutoExecute($timeout, \&dateQuery_filter);		
	}

	$request->setStatusDone();
}

sub firmwareUpgradeQuery_filter {
	my $self = shift;
	my $request = shift;

	# update the query if new firmware downloaded for this machine type
	if ($request->isCommand([['fwdownloaded']]) && 
		(($request->getParam('machine') || 'jive') eq ($self->getParam('_machine') || 'jive')) ) {
		return 1;
	}

	return 0;
}

sub firmwareUpgradeQuery {
	my $request = shift;
	
	if ( !main::LOCAL_PLAYERS ) {
		$request->setStatusDone();
		return;
	}
	
	if ( $request->isNotQuery([['firmwareupgrade']]) ) {
		$request->setStatusBadDispatch();
		return;
	}

	my $firmwareVersion = $request->getParam('firmwareVersion');
	my $model           = $request->getParam('machine') || 'jive';
	
	# always send the upgrade url this is also used if the user opts to upgrade
	if ( my $url = Slim::Utils::Firmware->url($model) ) {
		# Bug 6828, Send relative firmware URLs for Jive versions which support it
		my ($cur_rev) = $firmwareVersion =~ m/\sr(\d+)/;
		
		# return full url when running SqueezeOS - we'll serve the direct download link from squeezenetwork
		if ( $cur_rev >= 1659 && !Slim::Utils::OSDetect->getOS()->directFirmwareDownload() ) {
			$request->addResult( relativeFirmwareUrl => URI->new($url)->path );
		}
		else {
			$request->addResult( firmwareUrl => $url );
		}
	}
	
	if ( Slim::Utils::Firmware->need_upgrade( $firmwareVersion, $model ) ) {
		# if this is true a firmware upgrade is forced
		$request->addResult( firmwareUpgrade => 1 );
	}
	else {
		$request->addResult( firmwareUpgrade => 0 );
	}

	# manage the subscription
	if (defined(my $timeout = $request->getParam('subscribe'))) {
		$request->registerAutoExecute($timeout, \&firmwareUpgradeQuery_filter);
	}

	$request->setStatusDone();

}

my %allMyMusicMenuItems;

sub myMusicMenu {
	main::INFOLOG && $log->info("Begin function: ", (Slim::Schema::hasLibrary() ? 'library' : 'no library'));
	my $batch = shift;
	my $client = shift;

	my $myMusicMenu = Slim::Menu::BrowseLibrary::getJiveMenu($client, 'myMusic', \&_libraryChanged);
	
	
	if (!$batch) {
		my %newMenuItems = map {$_->{'id'} => 1} @$myMusicMenu;
		my @myMusicMenuDelete = map +{id => $_, node => 'myMusic'}, (grep {!$newMenuItems{$_}} keys %allMyMusicMenuItems);
			
		_notifyJive(\@myMusicMenuDelete, $client, 'remove');
	}
	
	foreach (@$myMusicMenu) {
		$allMyMusicMenuItems{$_->{'id'}} = 1;
	}
	
	if ($batch) {
		return $myMusicMenu;
	} else {
		_notifyJive($myMusicMenu, $client);
	}
}

sub pluginMenus {
	my $client = shift;
	
	# UE Smart Radio can't handle plugins which try to deal with the client object directly
	return [ grep {
		$_->{ canDisconnectedMode } ? $_ : undef;
	} @pluginMenus ] unless $client->isLocalPlayer;

	return \@pluginMenus;
}


# send a notification for menustatus
sub menuNotification {
	# the lines below are needed as menu notifications are done via notifyFromArray, but
	# if you wanted to debug what's getting sent over the Comet interface, you could do it here
	my $request  = shift;
	my $dataRef          = $request->getParam('_data')   || return;
	my $action   	     = $request->getParam('_action') || 'add';
	my $client           = $request->clientid();
	main::INFOLOG && $log->is_info && $log->info("Menustatus notification sent:", $action, '->', ($client || 'all'));
	main::DEBUGLOG && $log->is_debug && $log->debug(Data::Dump::dump($dataRef));
}


sub _jiveNoResults {
	my $request = shift;
	$request->addResult('count', '1');
	$request->addResult('offset', 0);
	$request->addResultLoop('item_loop', 0, 'text', $request->string('EMPTY'));
	$request->addResultLoop('item_loop', 0, 'style', 'itemNoAction');
	$request->addResultLoop('item_loop', 0, 'action', 'none');
}

sub cacheSearch {
	my $request = shift;
	my $search  = shift;
	
	# Don't cache searches on SN
	return if main::SLIM_SERVICE;

	if (defined($search) && $search->{text} && $search->{actions}{go}{cmd}) {
		unshift (@recentSearches, $search);
	}
	recentSearchMenu($request->client, 0);
}

sub recentSearchMenu {
	my $client  = shift;
	my $batch   = shift;

	my @recentSearchMenu = ();
	return \@recentSearchMenu unless $client;

	if (scalar(@recentSearches) == 1) {
		push @recentSearchMenu,
		{
			text           => $client->string('RECENT_SEARCHES'),
			id             => 'homeSearchRecent',
			node           => 'home',
			weight         => 111,
			actions => {
				go => {
					cmd => ['jiverecentsearches'],
       	                 },
			},
			window => {
				text => $client->string('RECENT_SEARCHES'),
			},
		};
		push @recentSearchMenu,
		{
			text           => $client->string('RECENT_SEARCHES'),
			id             => 'myMusicSearchRecent',
			node           => 'myMusicSearch',
			noCustom       => 1,
			weight         => 50,
			actions => {
				go => {
					cmd => ['jiverecentsearches'],
       	                 	},
			},
			window => {
				text => $client->string('RECENT_SEARCHES'),
			},
		};	
		if (!$batch) {
			_notifyJive(\@recentSearchMenu, $client);
		}
	}
	return \@recentSearchMenu;

}

sub jiveRecentSearchQuery {

	my $request = shift;
	main::INFOLOG && $log->info("Begin Function");

	# check this is the correct query.
	if ($request->isNotQuery([['jiverecentsearches']])) {
		$request->setStatusBadDispatch();
		return;
	}

	my $totalCount = scalar(@recentSearches);
	if ($totalCount == 0) {
		# this is an empty resultset
		_jiveNoResults($request);
	} else {
		my $maxCount = 200;
		$totalCount = $totalCount > $maxCount ? ($maxCount - 1) : $totalCount;
		$request->addResult('count', $totalCount);
		$request->addResult('offset', 0);
		for my $i (0..$totalCount) {
			last unless $recentSearches[$i];
			my $href = $recentSearches[$i];
			for my $key (keys %$href) {
				$request->addResultLoop('item_loop', $i, $key, $href->{$key});
			}
		}
	}
	$request->setStatusDone();
}


# The following allow download of extensions (applets, wallpaper and sounds) from SC to jive

# hash of providers for extension information
my %extensionProviders = ();

sub registerExtensionProvider {
	my $name     = shift;
	my $provider = shift;
	my $optstr   = shift;

	main::INFOLOG && $log->info("adding extension provider $name" . ($optstr ? " optstr: $optstr" : ""));

	$extensionProviders{ $name } = { provider => $provider, optstr => $optstr };
}

sub removeExtensionProvider {
	my $name = shift;

	main::INFOLOG && $log->info("deleting extension provider $name");

	delete $extensionProviders{ $name };
}

# return all extensions available for a specific type, version and target
# uses extension providers to provide a list of extensions available for the query criteria
# these are async so they can fetch and parse data to build a list of extensions
sub extensionsQuery {
	my $request = shift;
 
	my ($type) = $request->getRequest(0) =~ /jive(applet|wallpaper|sound|patche)s/; # S:P:Extensions always appends 's' to type
	my $version= $request->getParam('version');
	my $target = $request->getParam('target');
	my $optstr = $request->getParam('optstr');

	if (!defined $type) {
		$request->setStatusBadDispatch();
		return;
	}

	my @providers;
	my $language  = $Slim::Utils::Strings::currentLang;

	# remove optional providers if key is included in the query and it does not match
	# this allows SP to select whether optional providers are used to build the list
	for my $provider (keys %extensionProviders) {
		if (!$optstr || !defined $extensionProviders{$provider}->{'optstr'} || $optstr =~ /$extensionProviders{$provider}->{optstr}/) {
			push @providers, $provider;
		}
	}

	if (scalar @providers) {

		$request->privateData( { remaining => scalar @providers, results => [] } );

		$request->setStatusProcessing;

		for my $provider (@providers) {

			$extensionProviders{$provider}->{'provider'}->( {
				'name'   => $provider, 
				'type'   => $type, 
				'target' => $target,
				'version'=> $version, 
				'lang'   => $language,
				'details'=> 1,
				'cb'     => \&_extensionsQueryCB,
				'pt'     => [ $request ]
			});
		}

	} else {

		$request->addResult("count", 0);

		$request->setStatusDone();
	}
}

sub _extensionsQueryCB {
	my $request= shift;
	my $res    = shift;
	my $data   = $request->privateData;

	splice @{$data->{'results'}}, 0, 0, @$res;

	if ( ! --$data->{'remaining'} ) {

		# create a list of entries with the duplicates removed, favoring higher version numbers

		# pass 1 - find max versions
		my $max = {};

		for my $entry (@{$data->{'results'}}) {

			my $name = $entry->{'name'};

			if (!defined $max->{$name} || Slim::Utils::Versions->compareVersions($entry->{'version'}, $max->{$name}) > 0) {

				$max->{$name} = $entry->{'version'};
			}
		}

		# pass 2 - build list containing single entry for per extension
		my @results = ();

		for my $entry (@{$data->{'results'}}) {

			my $name = $entry->{'name'};

			if (exists $max->{$name} && (!defined $max->{$name} || $max->{$name} eq $entry->{'version'})) {

				push @results, $entry;

				delete $max->{$name};
			}
		}

		my $cnt = 0;

		for my $entry ( sort { $a->{'title'} cmp $b->{'title'} } @results ) {

			$request->setResultLoopHash('item_loop', $cnt++, $entry);
		}

		$request->addResult("count", $cnt);

		$request->setStatusDone();
	}
}

sub appMenus {
	my $client = shift;
	my $batch  = shift;
	
	my $isInfo = main::INFOLOG && $log->is_info;
	
	return () if !main::SERVICES;
	
	my $apps = $client->apps;
	my $menu = [];
	
	my $disabledPlugins = Slim::Utils::PluginManager->disabledPlugins();
	my @disabled = map { $disabledPlugins->{$_}->{name} } keys %{$disabledPlugins};
	
	# We want to add nodes for the following items:
	# My Apps (node = null)
	# Home menu apps (node = home)
	# If a home menu app is not already defined in @appMenus,
	# i.e. pure OPML apps such as SomaFM
	# create one for it using the generic OPML handler
	
	for my $app ( keys %{$apps} ) {
		next unless ref $apps->{$app} eq 'HASH'; # XXX don't crash on old style
		
		# Is this app supported by a local plugin?
		if ( my $plugin = $apps->{$app}->{plugin} ) {
			# Make sure it's enabled
			if ( my $pluginInfo = Slim::Utils::PluginManager->isEnabled($plugin) ) {
				
				# Get the predefined menu for this plugin
				if ( my ($globalMenu) = grep {
					( $_->{uuid} && lc($_->{uuid}) eq lc($pluginInfo->{id}) )
					|| ( $_->{text} && $_->{text} eq $pluginInfo->{name} )
				} @appMenus ) {				
					main::INFOLOG && $isInfo && $log->info( "App: $app, using plugin $plugin" );
				
					# Clone the existing menu and set the node
					my $clone = Storable::dclone($globalMenu);

					# Set node to home or null
					$clone->{node} = $apps->{$app}->{home_menu} == 1 ? 'home' : '';

					# Use title from app list
					$clone->{stringToken} = $apps->{$app}->{title};

					# flag as an app
					$clone->{isApp} = 1;
					
					# use icon as defined by MySB to allow for white-label solutions
					if ( my $icon = $apps->{$app}->{icon} ) {
						$icon = Slim::Networking::SqueezeNetwork->url( $icon, 'external' ) unless $icon =~ /^http/;
						$clone->{window}->{'icon-id'} = $icon ;
					}
					
					if ( my $icon_tile = $apps->{$app}->{icon_tile} ) {
						$icon_tile = Slim::Networking::SqueezeNetwork->url( $icon_tile, 'external' ) unless $icon_tile =~ /^http/;
						$clone->{window}->{'icon-tile'} = $icon_tile;
					}

					push @{$menu}, $clone;
				}
			}
			else {
				# Bug 13627, Make sure the app is not for a plugin that has been disabled.
				# We could browse menus for a disabled plugin like Last.fm, but playback
				# would be impossible.
				main::INFOLOG && $isInfo && $log->info( "App: $app, not displaying because plugin is disabled" );
				next;
			}
		}
		else {
			# For type=opml, use generic handler
			if ( $apps->{$app}->{type} eq 'opml' ) {
				main::INFOLOG && $isInfo && $log->info( "App: $app, using generic OPML handler" );
				
				my $url = $apps->{$app}->{url} =~ /^http/
					? $apps->{$app}->{url} 
					: Slim::Networking::SqueezeNetwork->url( $apps->{$app}->{url} );
				
				my $icon = $apps->{$app}->{icon} =~ /^http/
					? $apps->{$app}->{icon} 
					: Slim::Networking::SqueezeNetwork->url( $apps->{$app}->{icon}, 'external' );
				
				my $icon_tile = '';
				if ( $apps->{$app}->{icon_tile} ) {
					$icon_tile = $apps->{$app}->{icon_tile} =~ /^http/
						? $apps->{$app}->{icon_tile} 
						: Slim::Networking::SqueezeNetwork->url( $apps->{$app}->{icon_tile}, 'external' );
				}
				
				my $node = $apps->{$app}->{home_menu} == 1 ? 'home' : '';
				
				my $newService = {
					actions => {
						go => {
							cmd    => [ 'opml_generic', 'items' ],
							params => {
								menu     => 'opml_generic',
								opml_url => $url,
							},
							player => 0,
						},
					},
					displayWhenOff => 0,
					id             => 'opml' . $app,
					isApp		=> 1,
					node           => $node,
					text           => $apps->{$app}->{title},
					window         => {
						'icon-id'   => $icon,
						'icon-tile' => $icon_tile,
					},
				};
				
				push (@{$menu}, $newService);
				push (@appMenus, $newService);
			}
		}
	}
	
	return [] if !scalar @{$menu};
	
	# Alpha sort and add weighting
	my $weight = 25; # After Search
	
	my @sorted =
	 	map { $_->{weight} = $weight++; $_ } 
		sort { $a->{text} cmp $b->{text} }
		@{$menu};
		
	if ( $batch ) {
		return \@sorted;
	}
	else {
		_notifyJive(\@sorted, $client);
	}
}

sub _localizeMenuItemText {
	my ( $client, $item ) = @_;
	
	return unless $client;
	
	# Don't alter the global data
	my $clone = Storable::dclone($item);
	
	if ( $clone->{stringToken} ) {
		if ( $clone->{stringToken} eq uc( $clone->{stringToken} ) && Slim::Utils::Strings::stringExists( $clone->{stringToken} ) ) {
			$clone->{text} = $client->string( delete $clone->{stringToken} );
		}
		else {
			$clone->{text} = delete $clone->{stringToken};
		}
	}
	elsif ( $clone->{text} && $clone->{text} eq uc( $clone->{text} ) && Slim::Utils::Strings::stringExists( $clone->{text} ) ) {
		$clone->{text} = $client->string( $clone->{text} );
	}
	
	# call string() for screensaver titles
	if ( $clone->{screensavers} ) {
		for my $s ( @{ $clone->{screensavers} } ) {
			$s->{text} = $client->string( delete $s->{stringToken} ) if $s->{stringToken};
		}
	}
	
	# call string() for input text if necessary
	if ( my $input = $clone->{input} ) {
		if ( $input->{title} && $input->{title} eq uc( $input->{title} ) ) {
			$input->{title}        = $client->string( $input->{title} );
			$input->{help}->{text} = $client->string( $input->{help}->{text} );
			$input->{processingPopup}->{text} = $client->string( $input->{processingPopup}->{text} );
			$input->{softbutton1}  = $client->string( $input->{softbutton1} );
			$input->{softbutton2}  = $client->string( $input->{softbutton2} );
		}
	}
	
	return $clone;
}

sub globalSearchMenu {
	my $client = shift || undef;

	my @searchMenu = ({
		stringToken	   => 'SEARCH',
		text           => $client->string('SEARCH'),
		homeMenuText   => $client->string('SEARCH'),
		id             => 'globalSearch',
		node           => 'home',
		weight         => 22, # after internet radio
		input => {
			len  => 1, #bug 5318
			processingPopup => {
				text => $client->string('SEARCHING'),
			},
			help => {
				text => $client->string('JIVE_SEARCHFOR_HELP')
			},
		},
		actions => {
			go => {
				cmd => ['globalsearch', 'items'],
				params => {
					menu     => 'globalsearch',
					search   => '__TAGGEDINPUT__',
				},
			},
		},
		window => {
			text => $client->string('SEARCH'),
		},
	});

	return \@searchMenu;	
}

#sub simpleServiceButton {
#	my ($client, $icon, $service, $name) = @_;
#	
#	return {
#		icon    => $icon,
#		command => [ $service, 'items' ],
#		params  => [ 'menu:1' ],
#		window  => {
#			title      => $client->string($name),
#			nextWindow => 'menu',
#		},
#	};
#}

1;
