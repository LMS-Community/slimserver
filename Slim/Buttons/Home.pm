package Slim::Buttons::Home;

# SlimServer Copyright (c) 2001-2006 Sean Adams, Slim Devices Inc.
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

L<Slim::Buttons::Home> is a SlimServer module for creating and
navigating a configurable multilevel menu structure.

=cut

use strict;
use File::Spec::Functions qw(:ALL);

use Slim::Buttons::BrowseDB;
use Slim::Buttons::BrowseTree;
use Slim::Buttons::Common;
use Slim::Buttons::Playlist;
use Slim::Buttons::TrackInfo;
use Slim::Buttons::RemoteTrackInfo;
use Slim::Utils::Log;
use Slim::Utils::Misc;

my $log = logger('player.menu');

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

			return $client->string($string);
		},

		'externRefArgs' => 'CV',
		'stringExternRef' => 1,
		'header' => undef,
		'headerAddCount' => 1,
		'callback' => \&homeExitHandler,

		'overlayRef' => sub { return (undef, Slim::Display::Display::symbol('rightarrow')) },

		'overlayRefArgs' => '',
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

	# This is also a big source of the inconsistency in "play" and "add" functions.
	# We might want to make this a simple...'add' = clear playlist, 'play' = play everything
	%functions = (
		'add' => sub  {
			my $client = shift;
		
			if ($client->curSelection($client->curDepth()) eq 'NOW_PLAYING') {

				$client->showBriefly($client->string('CLEARING_PLAYLIST'), '');
				$client->execute(['playlist', 'clear']);

			} else {

				Slim::Buttons::Common::pushModeLeft($client,'playlist');
			}	
		},

		'play' => sub  {
			my $client = shift;

			my $selection = $client->curSelection($client->curDepth());
			if ($selection eq 'NOW_PLAYING') {

				$client->execute(['play']);

				Slim::Buttons::Common::pushModeLeft($client, 'playlist');

			} elsif ($selection eq 'SAVED_PLAYLISTS'
						|| ($selection =~ /^BROWSE_/
							&& $selection ne 'BROWSE_MUSIC')) {
							
				# If we're in a Browse mode and the user
				# presses play, just go right, per Dean
				Slim::Buttons::Input::List::exitInput($client, 'right');

			} else {

				Slim::Buttons::Common::pushModeLeft($client, 'playlist');
			}
		},
	);
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

		$log->info("$menu does not exist. creating...");

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
	
	$log->info("Deleting $name from $menu");
	
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
			
			$params{'header'} = $client->string($client->curSelection($client->curDepth()));

			# move reference to new depth
			$client->curDepth($client->curDepth()."-".$client->curSelection($client->curDepth()));
			
			# check for disalbed plugins in item list.
			$params{'listRef'} = createList($client, $nextParams);
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

						$value = $client->prefGet($nextParams->{'initialValue'});
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
	my $client = shift;
	my $string = shift;

	if (Slim::Utils::Strings::stringExists($string)) {

		return $client->string($string);
	}

	return $string;
}

# load the submenu hash keys into an array of valid entries.
sub createList {
	my $client = shift;
	my $params = shift;

	my @list = ();

	my %disabledplugins = map { $_ => 1 } Slim::Utils::Prefs::getArray('disabledplugins');
	
	for my $sub (sort {((Slim::Utils::Prefs::get("rank-$b") || 0) <=> 
		(Slim::Utils::Prefs::get("rank-$a") || 0)) || 
		(lc(cmpString($client, $a)) cmp lc(cmpString($client, $b)))} 
		keys %{$params->{'submenus'}}) {

		if (exists $disabledplugins{$sub}) {
			next;
		}

		# Leakage of the DigitalInput plugin..
		if ($sub eq 'PLUGIN_DIGITAL_INPUT' && !$client->hasDigitalIn) {
			next;
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
	
	for my $menuOption (sort keys %home) {

		if ($menuOption eq 'BROWSE_MUSIC_FOLDER' && !Slim::Utils::Prefs::get('audiodir')) {
			next;
		}

		if ($menuOption eq 'SAVED_PLAYLISTS' && !Slim::Utils::Prefs::get('playlistdir')) {
			next;
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

	my $pluginsRef = Slim::Utils::PluginManager->installedPlugins();

	for my $plugin (values %{$pluginsRef}) {
		next unless defined $plugin;

		delete $menuChoices{$plugin} if defined $menuChoices{$plugin};
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
	
	for my $menuItem ($client->prefGetArray('menuItem')) {

		my $plugin = Slim::Utils::PluginManager->dataForPlugin($menuItem);

		if (!exists $home{$menuItem} && !defined $plugin) {

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

	$homeChoices{$client} = \@home;

	$client->modeParam('listRef', \@home);
}
 
=head1 SEE ALSO

L<Slim::Buttons::Common>

=cut

1;

__END__
