package Slim::Buttons::Home;

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

=head1 NAME

Slim::Buttons::Home

=head1 SYNOPSIS

	Slim::Buttons::Home::addSubMenu('SETTINGS', 'ALARM', {
		'useMode'   => 'alarm',
		'condition' => sub { 1 },
	});
	
	Slim::Buttons::Home::getHomeChoices($client);
	
	Slim::Buttons::Home::jumpToMenu($client,"BROWSE_MUSIC");

=head1 DESCRIPTION

L<Slim::Buttons::Home> is a Logitech Media Server module for creating and
navigating a configurable multilevel menu structure.

=cut

use strict;

use Slim::Buttons::Common;
use Slim::Buttons::Playlist;
use Slim::Buttons::TrackInfo;
use Slim::Buttons::RemoteTrackInfo;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;

my $log = logger('player.menu');

my $prefs = preferences('server');

our %home = ();
our %defaultParams = ();
our %homeChoices;
our %functions = ();

=head1 METHODS

=head2 init( )

Register 'home' mode, the top level navigation menu. Other modules and plugins may add menuitems to the home
menu, allowing users to change the order and selection of items in the home menu.

=cut

sub init {
	Slim::Buttons::Common::addMode('home', getFunctions(), \&setMode);

	# More documentation needed for all this magic.
	%defaultParams = (
		'HOME-MENU' => 1,

		'listRef' => undef,

		'externRef' => sub {
			my $client = shift;
			my $string = shift;

			if (!Slim::Utils::Strings::stringExists($string)) {
				return $string;
			}

			if (defined $client && $client->linesPerScreen() == 1) {
				return $client->doubleString($string);
			}

			return ( uc($string) eq $string ) ? $client->string($string) : $string;
		},

		'externRefArgs' => 'CV',
		'header' => undef,
		'headerAddCount' => 1,
		'callback' => \&homeExitHandler,

		'overlayRef' => sub { return (undef, shift->symbols('rightarrow')) },

		'overlayRefArgs' => 'C',
		'valueRef' => undef,
	);

	# Home menu defaults are presented here, with default categories and menus.
	# Plugins may use the above manipulation functions to create hooks anywhere in the
	# home menu tree. Top level menu items can be chosen per player from the hash below,
	# plus any installed and active plugins
	%home = (

		'NOW_PLAYING' => {
			'useMode' => 'playlist'
		},
	);

	# Align actions as per Bug 8929 - in home menu add and play just go right.
	# When on Now Playing item, preserve the Clear Playlist shortcut
	%functions = (
		'add' => sub  {
			my $client = shift;
		
			if ($client->curSelection($client->curDepth()) eq 'NOW_PLAYING') {

				$client->showBriefly( {
					'line' => [ "", $client->string('CLEARING_PLAYLIST') ]
				});
				$client->execute(['playlist', 'clear']);

			} else {

				Slim::Buttons::Input::List::exitInput($client, 'right');
			}
		},

		'play' => sub  {
			my $client = shift;
			Slim::Buttons::Input::List::exitInput($client, 'right');		
		},
	);

}


=head2 forgetClient ( $client )

Clean up global hash when a client is gone

=cut

sub forgetClient {
	my $client = shift;
	
	delete $homeChoices{ $client };
}

######################################################################
# Home Hash Manipulation Functions
######################################################################

# XXXX - this should all be object based!!

=head2 addSubMenu( $menu,$submenuname,$submenuref)

Adds a submenu item to the supplied menuOption.  A reference to a hash containing the
submenu data must be supplied.  If the supplied menuOption does not exist, a new menuOption 
will be created 

=cut

sub addSubMenu {
	my ($menu, $submenuname, $submenuref) = @_;

	if (!exists $home{$menu} && defined $submenuref) {

		main::INFOLOG && $log->info("$menu does not exist. creating...");

		addMenuOption($menu);
	}

	if (exists $home{$menu}{'useMode'}) {

		$log->warn("Warning: Menu $menu cannot take submenus.");

		return;
	}

	# Don't add/remove submenu if there is no name or its an empty string
	if (!defined $submenuname && $submenuname) {

		return;
	}
	
	$home{$menu}{'submenus'}{$submenuname} = $submenuref;
}

=head2 delSubMenu( $menu,$submenuname)

Takes two strings, deleting the menu indicated by $submenuname from the menu named by $menu.

=cut

sub delSubMenu {
	my ($menu, $name) = @_;
	
	main::INFOLOG && $log->info("Deleting $name from $menu");
	
	if (!exists $home{$menu}{'submenus'}) {

		return;
	}

	if (!defined $name) {

		$log->logBacktrace("No submenu information supplied!");

		return;
	}

	if (exists $home{$menu}{'submenus'}{$name}) {

		delete $home{$menu}{'submenus'}{$name};

		if (!keys %{$home{$menu}{'submenus'}}) {

			delete $home{$menu}{'submenus'};

			delSubMenu("PLUGINS",$menu);
		}
	}
}


=head2 addMenuOption( $menu,$menuref)

Create a new menuOption for the top level.  This creates a new menu option at the top level,
which can be enabled or disabled per player. Takes $menu as a string identifying the menu name, and $menuref, 
which is a reference to the hash of menu parameters.

=cut

sub addMenuOption {
	my ($menu, $menuref) = @_;
	
	if (!defined $menu) {

		$log->logBacktrace("No menu information supplied!");

		return;
	}
	
	$home{$menu} = $menuref;
}

=head2 delMenuOption( $option)

Removes the menu named by $option from the list of available menu items to add/remove from the top level.

=cut

sub delMenuOption {
	my $option = shift;

	if (!defined $option) {

		$log->logBacktrace("No menu reference supplied!");

		return;
	}

	delete $home{$option};
}

sub getFunctions {
	return \%functions;
}

sub setMode {
	my $client = shift;
	my $method = shift;
	
	if ($method eq 'pop') {

		Slim::Buttons::Common::popMode($client);
		updateMenu($client);

		$client->curDepth('');

		if (!defined($client->curSelection($client->curDepth()))) {
			$client->curSelection($client->curDepth(),$homeChoices{$client}->[0]);
		}

		return;
	}
	
	updateMenu($client);

	$client->curDepth('');

	if (!defined($client->curSelection($client->curDepth()))) {
		$client->curSelection($client->curDepth(),$homeChoices{$client}->[0]);
	}
	
	my %params          = %defaultParams;

	$params{'header'}   = \&homeheader;
	$params{'listRef'}  = \@{$homeChoices{$client}};
	$params{'valueRef'} = \${$client->curSelection()}{$client->curDepth()};
	$params{'curMenu'}  = $client->curDepth();

	Slim::Buttons::Common::pushMode($client, 'INPUT.List', \%params);
}

#return the reference needed to access the menu one level up.
sub getLastDepth {
	my $client = shift;

	if ($client->curDepth() eq "") {
		return ""
	}

	my @depth = split(/-/,$client->curDepth());

	# Dropping last item in depth reference, gives the previous depth.
	pop @depth;

	my $last = join("-",@depth);
	return $last;
}

# grab the portion of the hash for the next menu down
sub getNextList {
	my $client = shift;
	
	my $next = getCurrentList($client);

	# return chosen Top Level item
	if ($client->curDepth() eq "") {
		return $next->{$client->curSelection($client->curDepth())};

	} else {
		#return sub-level items
		return $next->{'submenus'}->{$client->curSelection($client->curDepth())};
	}
}

# get a clients current menu params
sub getCurrentList {
	my $client = shift;

	return getMenu($client->curDepth());
}

# get a generic menu reference
sub getMenu {
	my $depth = shift;
	
	my $current = \%home;

	if ($depth eq "") {

		return $current;
	}

	my @depth = split(/-/, $depth);
	
	# home reference is "" so drop first item
	shift @depth;
	
	# top level reference
	$current = $current->{shift @depth};
	
	# recursive submenus
	for my $level (@depth) {
		$current = $current->{'submenus'}->{$level};
	}

	return $current;
}

sub homeExitHandler {
	my ($client,$exittype) = @_;
	$exittype = uc($exittype);

	if ($exittype eq 'LEFT') {

		if ($client->curDepth() ne "") {

			$client->curDepth(getLastDepth($client));
			
			# call jump in case top level has changed.
			#jump($client,$client->curSelection($client->curDepth()));
			Slim::Buttons::Common::popModeRight($client);

		} else {

			# We've hit the home root
			$client->curDepth("");
			updateMenu($client);
			$client->bumpLeft();
		}
	
	} elsif ($exittype eq 'RIGHT') {

		my $nextmenu = $client->curSelection($client->curDepth());
		
		# map default selection in case no onChange was done in INPUT.List
		if (!defined($nextmenu)) { 

			$nextmenu = ${$client->modeParam('valueRef')};

			$client->curSelection($client->curDepth(),$nextmenu);
		}
		
		if (!defined $nextmenu) {

			$client->bumpRight();
			return;
		}
		
		my $nextParams;
		# some menus might need function return values for params, so test here and grab
		
		if (ref(getNextList($client)) eq 'CODE') {

			$nextParams = {&getNextList($client)->($client)};

		} elsif (getNextList($client)) { 

			$nextParams = &getNextList($client);
		}

		if (exists ($nextParams->{'submenus'})) {

			my %params = %defaultParams;
			
			my $containerLevel = $client->curSelection($client->curDepth());
			$params{'header'}  = $client->string($containerLevel);

			# move reference to new depth
			my $curDepth = $client->curDepth();
			$client->curDepth( $curDepth . "-" . $client->curSelection($curDepth) );
			
			# check for disalbed plugins in item list.
			# Bug: 7089 - sort by ranking unless it's the plugins menu
			$params{'listRef'} = createList($client, $nextParams, $containerLevel ne 'PLUGINS' ? 1 : 0);
			$params{'overlayRef'} = undef if scalar @{$params{'listRef'}} == 0;
			$params{'curMenu'} = $client->curDepth();
			
			$params{'valueRef'} = \${$client->curSelection()}{$client->curDepth()};
			
			# If the ExitHandler is changing, backtrack the pointer for when we return home.
			if (exists $nextParams->{'callback'}) {$client->curDepth(getLastDepth($client));}
			
			# merge next list params over the default params where they exist.
			@params{keys %{$nextParams}} = values %{$nextParams};
			
			Slim::Buttons::Common::pushModeLeft($client, 'INPUT.List', \%params);
		
		# if here are no submenus, check for the way out.
		} elsif (exists($nextParams->{'useMode'})) {

			if (ref($nextParams->{'useMode'}) eq 'CODE') {

				$nextParams->{'useMode'}->($client);

			} else {
				my %params = %$nextParams;

				if (($nextParams->{'useMode'} eq 'INPUT.List' || $nextParams->{'useMode'} eq 'INPUT.Bar') && 
					exists($nextParams->{'initialValue'})) {

					# set up valueRef for current pref
					my $value;

					if (ref($nextParams->{'initialValue'}) eq 'CODE') {

						$value = $nextParams->{'initialValue'}->($client);

					} else {

						$value = $prefs->client($client)->get($nextParams->{'initialValue'});
					}

					$params{'valueRef'} = \$value;
				}

				Slim::Buttons::Common::pushModeLeft(
					$client,
					$nextParams->{'useMode'},
					\%params,
				);
			}

		} elsif (Slim::Buttons::Common::validMode($nextmenu)) {

			Slim::Buttons::Common::pushModeLeft($client, $nextmenu);

		} else {

			$client->bumpRight();
		}
	}
}

sub cmpString {
	if ( Slim::Utils::Strings::stringExists($_[1]) ) {
		return Slim::Utils::Strings::cstring($_[0], $_[1]);
	}

	return $_[1];
}

# load the submenu hash keys into an array of valid entries.
sub createList {
	my $client   = shift;
	my $params   = shift;
	my $weighted = shift;

	my @list = ();
	
	# Get sort order for plugins
	my $pluginWeights = Slim::Plugin::Base->getWeights();

	SUB:
	for my $sub (
		sort {
			($weighted && ($pluginWeights->{$a} || 0) <=> ($pluginWeights->{$b} || 0))
			||
			($weighted && ($prefs->get("rank-$b") || 0) <=> ($prefs->get("rank-$a") || 0))
			|| 
			(lc(cmpString($client, $a)) cmp lc(cmpString($client, $b)))
		} keys %{$params->{'submenus'}}) {

		# Leakage of the DigitalInput plugin..
		if ($sub eq 'PLUGIN_DIGITAL_INPUT' && !$client->hasDigitalIn) {
			next;
		}
		
		# Leakage of the LineIn plugin..
		if ($sub eq 'PLUGIN_LINE_IN' && !$client->hasLineIn) {
			next;
		}
		
		# Leakage of the LineOut plugin..
		if ($sub eq 'PLUGIN_LINE_OUT' && !$client->hasHeadSubOut) {
			next;
		}
		
		if ( my $condition = $params->{submenus}->{$sub}->{condition} ) {
			next unless $condition->( $client );
		}

		push @list, $sub;
	}

	return \@list;
}


=head2 jump( $client, $item)

Immediately move to a specific menu item from the list of chosen top level items.
A string, $item identifies the target menu item. If the given item does not exist,
defaults to the first item from the home menu pref for the current player.

=cut

sub jump {
	my $client = shift;
	my $item = shift;
	
	# force top level
	$client->curDepth("");
	$client->curSelection($client->curDepth(),undef);
	
	for my $menuitem (@{$homeChoices{$client}}) {
		next unless $menuitem eq $item;
		
		$client->curSelection($client->curDepth(),$item);
	}
	
	if (!defined($client->curSelection($client->curDepth()))) {
		$client->curSelection($client->curDepth(),$homeChoices{$client}->[0]);
	}
}

=head2 jumpToMenu( $client, $menu, $depth)

Forces a pushMode to a  specific target menu item within the home menu tree 
disregarding home menu settings.  $menu is a string identifying the unique menu 
node, while $depth is a string made up of the path of menu items taken, joined by "-".

This operates on the player given by the $client structure provided.

=cut

sub jumpToMenu {
	my $client = shift;
	my $menu   = shift;
	my $depth  = shift;

	if (!defined $depth) {
		$depth = '';
	}

	$client->curDepth($depth);
	$client->curSelection($client->curDepth, $menu);
	
	my $nextParams = Slim::Buttons::Home::getNextList($client);

	if (exists $nextParams->{'listRef'}) {

		Slim::Buttons::Common::pushModeLeft($client, 'INPUT.List', $nextParams);

	} else {

		homeExitHandler($client,"RIGHT");

	}
}

=head2 homeheader( $client )

Set top line text for home menu, based on player model.
Requires $client object.

=cut

sub homeheader {
	my $client = $_[0];

	if ($client->isa("Slim::Player::SLIMP3")) {

		return $client->string('SLIMP3_HOME');

	} elsif ($client->isa("Slim::Player::SoftSqueeze")) {

		return $client->string('SOFTSQUEEZE_HOME');

	} elsif ($client->isa("Slim::Player::Transporter")) {

		return $client->string('TRANSPORTER_HOME');

	} elsif ($client->isa("Slim::Player::Boom")) {

		return $client->string('HOMEMENU');

	} else {

		return $client->string('SQUEEZEBOX_HOME');
	}
}

#######
#	Routines for generating settings options.
#######

=head2 menuOptions( $client )

Return a hash of the currently available menu options for the home menu of the supplied $client.

=cut

sub menuOptions {
	my $client = shift;

	my %menuChoices = ();

	$menuChoices{""} = "";
	
	# Exclude SN-disabled plugins
	my $sn_disabled = $prefs->get('sn_disabled_plugins');
	
	MENU:
	for my $menuOption (sort keys %home) {

		if ($menuOption eq 'BROWSE_MUSIC_FOLDER' && !scalar @{ Slim::Utils::Misc::getAudioDirs() }) {
			next;
		}

		if ($menuOption eq 'SAVED_PLAYLISTS' && !Slim::Utils::Misc::getPlaylistDir()) {
			next;
		}
		
		if ( $sn_disabled ) {
			for my $plugin ( @{$sn_disabled} ) {
				next MENU if $menuOption =~ /$plugin/i;
			}
		}

		$menuChoices{$menuOption} = $menuOption;
	}

	return %menuChoices;
}

=head2 unusedMenuOptions( $client )

Return a sorted list of menu item names that are available but not currently
chosen for the home menu of the provided $client.

=cut

sub unusedMenuOptions {
	my $client = shift;

	my %menuChoices = menuOptions($client);

	delete $menuChoices{""};

	my %plugins = map { $_ => 1 } Slim::Utils::PluginManager->installedPlugins();

	for my $plugin (keys %plugins ) {
		
		delete $menuChoices{$plugin} if defined $menuChoices{$plugin};
	}

	# Leakage from Digital Input Plugin
	if (defined $menuChoices{'PLUGIN_DIGITAL_INPUT'} && !$client->hasDigitalIn) {
		delete $menuChoices{'PLUGIN_DIGITAL_INPUT'};
	}

	# Leakage from Line In Plugin
	if (defined $menuChoices{'PLUGIN_LINE_IN'} && !$client->hasLineIn) {
		delete $menuChoices{'PLUGIN_LINE_IN'};
	}

	# Leakage from Sub/Head Out Plugin
	if (defined $menuChoices{'PLUGIN_LINE_OUT'} && !$client->hasHeadSubOut) {
		delete $menuChoices{'PLUGIN_LINE_OUT'};
	}
	
	for my $usedOption (@{$homeChoices{$client}}) {
		delete $menuChoices{$usedOption};
	}

	return sort { $menuChoices{$a} cmp $menuChoices{$b} } keys %menuChoices;
}


=head2 getHomeChoices( $client )

Takes a $client object as an argument and returns a array reference to the currently selected 
menu items for the home menu of the supplied client.

=cut

sub getHomeChoices {
	my $client = shift;
	return \@{$homeChoices{$client}};
}

=head2 updateMenu( $client )

This function takes a $client object and refreshes that clients menu options.  Called
from setup when menu options are changed, or when some prefs may affect available menu options.

=cut

sub updateMenu {
	my $client = shift;
	my @home = ();
	
	my $menuItem = $prefs->client($client)->get('menuItem');
	if ( !ref $menuItem ) {
		$menuItem = [ $menuItem ];
	}
	
	for my $menuItem ( @{$menuItem} ) {
		if ($menuItem eq 'BROWSE_MUSIC' && !Slim::Schema::hasLibrary()) {
			next;
		}
		
		# more leakage of the LineIn plugin..
		if ($menuItem eq 'PLUGIN_LINE_IN' && !($client->hasLineIn && $client->lineInConnected)) {
			next;
		}

		# more leakage of the Line Out plugin..
		if ($menuItem eq 'PLUGIN_LINE_OUT' && !($client->hasHeadSubOut && $client->lineOutConnected)) {
			next;
		}
		
		my $plugin = Slim::Utils::PluginManager->dataForPlugin($menuItem);

		if (!exists $home{$menuItem} && !defined $plugin) {

			next;
		}
		
		# Skip home menu items that contain no submenus
		if ( ref $home{$menuItem} eq 'HASH' && !scalar keys %{ $home{$menuItem} } ) {
			next;
		}

		if (defined $plugin) {

			$menuItem = $plugin->{'name'};
		}
		
		push @home, $menuItem;
	}

	if (!scalar @home) {

		push @home, 'NOW_PLAYING';
	}
	
	# Add home menu apps between Internet Radio and My Apps
	my $apps    = $client->apps;
	my $appMenu = [];
	
	for my $app ( keys %{$apps} ) {
		# Skip non home-menu apps
		next unless $apps->{$app}->{home_menu} && $apps->{$app}->{home_menu} == 1;
		
		my $title = $apps->{$app}->{title};
		next unless $title;
		
		if ( $title eq uc($title) ) {
			$title = $client->string($title);
		}
		
		# Is this app supported by a built-in plugin?
		if ( my $plugin = $apps->{$app}->{plugin} ) {
			# Make sure it's enabled
			if ( my $pluginInfo = Slim::Utils::PluginManager->isEnabled($plugin) ) {
				push @{$appMenu}, {
					mode => $pluginInfo->{name},
					text => $title,
				};
			}
		}
		elsif ( $apps->{$app}->{type} eq 'opml' ) {
			# for type=opml without a mode, use generic OPML plugin
			push @{$appMenu}, {
				mode => $title,
				text => $title,
			};
			
			my $url = ( main::NOMYSB || $apps->{$app}->{url} =~ /^http/ )
				? $apps->{$app}->{url} 
				: Slim::Networking::SqueezeNetwork->url( $apps->{$app}->{url} );
			
			# Create new XMLBrowser mode for this item
			if ( !exists $home{$title} ) {
				addMenuOption( $title => {
					useMode => sub {
						my $client = shift;
					
						my %params = (
							header   => $title,
							modeName => $title,
							url      => $url,
							title    => $title,
							timeout  => 35,
						);
					
						Slim::Buttons::Common::pushMode( $client, 'xmlbrowser', \%params );
					
						$client->modeParam( handledTransition => 1 );
					},
				} );
			}
		}
	}
	
	# Sort app menu after localization
	my @sorted =
	 	map { $_->{mode} } 
		sort { $a->{text} cmp $b->{text} }
		@{$appMenu};
	
	# Insert app menu after radio
	splice @home, 3, 0, @sorted;

	$homeChoices{$client} = \@home;

	# this is only for top level, so shortcut out if player is not at top level
	# Bug 14134, this used to check $client->curDepth() but it does not really return the current depth
	# modeStack is a better way to determine where you are.  This checks for > 2 because on the home
	# menu the modeStack is ["home", "INPUT.List"]
	if ( scalar @{ $client->modeStack || [] } > 2 ) {
		$client->update();
		return;
	}
	
	$client->modeParam('listRef', \@home);
}
 
=head1 SEE ALSO

L<Slim::Buttons::Common>

=cut

1;

__END__
