package Slim::Buttons::Home;

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use File::Spec::Functions qw(:ALL);

use Slim::Buttons::BrowseID3;
use Slim::Buttons::Common;
use Slim::Buttons::Playlist;
use Slim::Utils::Strings qw (string);

my %home = ();

Slim::Buttons::Common::addMode('home',getFunctions(),\&setMode);

my %defaultParams = (
	'listRef' => undef
	,'externRef' => sub {
		my $client = $_[0];
		my $line2;
		$line2 = (defined $client && $client->linesPerScreen() == 1) ? Slim::Utils::Strings::doubleString($_[1]) : string($_[1]);
		return $line2;
	}
	,'onChange' => sub {
		my ($client, $value) = @_;
		my $curMenu = Slim::Buttons::Common::param($client,'curMenu');
		$client->curSelection($curMenu,$value);
	}
	,'onChangeArgs' => 'CV'
	,'externRefArgs' => 'CV'
	,'stringExternRef' => 0
	,'header' => undef
	,'headerAddCount' => 1
	,'callback' => \&homeExitHandler
	,'overlayRef' => sub {return (undef,Slim::Display::Display::symbol('rightarrow'));}
	,'overlayRefArgs' => ''
	,'valueRef' => undef
);
	
########################################################################
#
# Home Menu Hash
#
# Home menu defaults are presented here, with default categories and menus.
# Plugins may use the above manipulation functions to create hooks anywhere in the
# home menu tree. Top level menu items can be chosen per player from the hash below,
# plus any installed and active plugins
###########################################################################
sub initHomeConfig {
	%home = (
		'NOW_PLAYING' => {
			'useMode' => 'playlist'
		}
		,'SETTINGS' => {
			'useMode' => 'settings'
		}
	)
}

initHomeConfig();

######################################################################
# Home Hash Manipulation Functions
######################################################################
#
# Adds a submenu item to the supplied menuOption.  A reference to a hash containing the
# submenu data must be supplied.  If the supplied menuOption does not exist, a new menuOption 
# will be created 
sub addSubMenu {
	my ($menu,$submenuname,$submenuref) = @_;
	unless (exists $home{$menu}) {
		#warn "menu $menu does not exist\n";
		addMenuOption($menu);
	}
	if (exists $home{$menu}{'useMode'}) {
		warn "Menu $menu cannot take submenus\n";
		return;
	}
	unless (defined $submenuname && defined $submenuref) {
		warn "No submenu information supplied!\n";
		return;
	}
	$home{$menu}{'submenus'}{$submenuname} = $submenuref;
	return;
}

# Deletes a subMenu from a menuOption
sub delSubMenu {
	my ($menu,$submenuname) = @_;
	unless (exists $home{$menu}{'submenus'}) {
		warn "submenu of $menu does not exist\n";
		return;
	}
	unless (defined $submenuname) {
		warn "No submenu information supplied!\n";
		return;
	}
	if (exists $home{$menu}{'submenus'}{$submenuname}) {
			delete $home{$menu}{'submenus'}{$submenuname};
			if (!scalar keys %{$home{$menu}{'submenus'}}) {delete $home{$menu};}
	}
	return;
}

# Create a new menuOption for the top level.  This creates a new menu option at the top level,
# which can be enabled of disabled per player.
sub addMenuOption {
	my ($menu,$menuref) = @_;
	
	unless (defined $menu) {
		warn "No menu information supplied!\n";
		return;
	}
	
	$home{$menu} = $menuref;
}

sub delMenuOption {
	my $option = shift;

	unless (defined $option) {
		warn "No menu reference supplied!\n";
		return;
	}

	delete $home{$option};
}

my %homeChoices;

# TODO: some of this is obvious cruft.  'MUSIC' doesn't seem to exist an a menu option any more.
# This is also a big source of the inconsistency in "play" and "add" functions.
# We might want to make this a simple...'add' = clear playlist, 'play' = play everything
my %functions = (
	'add' => sub  {
		my $client = shift;
	
		if ($client->curSelection($client->curDepth()) eq 'MUSIC') {
			# add the whole of the music folder to the playlist!
			Slim::Buttons::Block::block($client, string('ADDING_TO_PLAYLIST'), string('MUSIC'));
			Slim::Control::Command::execute($client, ['playlist', 'add', Slim::Utils::Prefs::get('audiodir')], \&Slim::Buttons::Block::unblock, [$client]);
		} elsif($client->curSelection($client->curDepth()) eq 'NOW_PLAYING') {
			$client->showBriefly(string('CLEARING_PLAYLIST'), '');
			Slim::Control::Command::execute($client, ['playlist', 'clear']);
		} else {
			Slim::Buttons::Common::pushModeLeft($client,'playlist');
		}	
	},
	'play' => sub  {
		my $client = shift;
	
		if ($client->curSelection($client->curDepth()) eq 'MUSIC') {
			# play the whole of the music folder!
			if (Slim::Player::Playlist::shuffle($client)) {
				Slim::Buttons::Block::block($client, string('PLAYING_RANDOMLY_FROM'), string('MUSIC'));
			} else {
				Slim::Buttons::Block::block($client, string('NOW_PLAYING_FROM'), string('MUSIC'));
			}
			Slim::Control::Command::execute($client, ['playlist', 'load', Slim::Utils::Prefs::get('audiodir')], \&Slim::Buttons::Block::unblock, [$client]);
		} elsif($client->curSelection($client->curDepth()) eq 'NOW_PLAYING') {
			Slim::Control::Command::execute($client, ['play']);
			#The address of the %functions hash changes from compile time to run time
			#so it is necessary to get a reference to it from a function outside of the hash
			Slim::Buttons::Common::pushModeLeft($client,'playlist');
		} elsif (($client->curSelection($client->curDepth()) eq 'BROWSE_BY_GENRE')  ||
				  ($client->curSelection($client->curDepth()) eq 'BROWSE_BY_ARTIST') ||
				  ($client->curSelection($client->curDepth()) eq 'BROWSE_BY_ALBUM')  ||
				  ($client->curSelection($client->curDepth()) eq 'BROWSE_BY_SONG')) {
			if (Slim::Player::Playlist::shuffle($client)) {
				Slim::Buttons::Block::block($client, string('PLAYING_RANDOMLY'), string('EVERYTHING'));
			} else {
				Slim::Buttons::Block::block($client, string('NOW_PLAYING'), string('EVERYTHING'));
			}
			Slim::Control::Command::execute($client, ["playlist", "loadalbum", "*", "*", "*"], \&Slim::Buttons::Block::unblock, [$client]);
		} else {
			Slim::Buttons::Common::pushModeLeft($client,'playlist');
		}
	},
);

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
			$client->curSelection($client->curDepth(),'NOW_PLAYING');
		}
		return;
	}
	
	updateMenu($client);
	$client->curDepth('');
	if (!defined($client->curSelection($client->curDepth()))) {
		$client->curSelection($client->curDepth(),'NOW_PLAYING');
	}
	my %params = %defaultParams;
	$params{'header'} = \&homeheader;
	$params{'listRef'} = \@{$homeChoices{$client}};
	$params{'valueRef'} = \$client->curSelection($client->curDepth());
	$params{'curMenu'} = $client->curDepth();
	Slim::Buttons::Common::pushMode($client,'INPUT.List',\%params);
	$client->update();
}

#return the reference needed to access the menu one level up.
sub getLastDepth {
	my $client = shift;
	if ($client->curDepth() eq "") {
		return ""
	}
	
	my @depth = split(/-/,$client->curDepth());
	#dropping last item in depth reference, gives the previous depth.
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
	return $current if $depth eq "";
	my @depth = split(/-/,$depth);
	#home reference is "" so drop first item
	shift @depth;
	#top level reference
	$current = $current->{shift @depth};
	# recursive submenus
	foreach my $level (@depth) {
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
			$nextmenu = ${Slim::Buttons::Common::param($client,'valueRef')};
			$client->curSelection($client->curDepth(),$nextmenu);
		}
		unless (defined $nextmenu) {
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
			
			$params{'header'} = string($client->curSelection($client->curDepth()));
			# move reference to new depth
			$client->curDepth($client->curDepth()."-".$client->curSelection($client->curDepth()));
			
			# check for disalbed plugins in item list.
			$params{'listRef'} = &createList($nextParams);
			$params{'overlayRef'} = undef if scalar @{$params{'listRef'}} == 0;
			$params{'curMenu'} = $client->curDepth();
			
			$params{'valueRef'} = \$client->curSelection($client->curDepth());
			# If the ExitHandler is changing, backtrack the pointer for when we return home.
			if (exists $nextParams->{'callback'}) {$client->curDepth(getLastDepth($client));}
			# merge next list params over the default params where they exist.
			@params{keys %{$nextParams}} = values %{$nextParams};
			Slim::Buttons::Common::pushModeLeft(
				$client
				,'INPUT.List'
				,\%params
			);
		# if here are no submenus, check for the way out.
		} elsif (exists($nextParams->{'useMode'})) {
			if (ref($nextParams->{'useMode'}) eq 'CODE') {
				$nextParams->{'useMode'}->($client);
			} else {
				if (($nextParams->{'useMode'} eq 'INPUT.List' || $nextParams->{'useMode'} eq 'INPUT.Bar')  && exists($nextParams->{'initialValue'})) {
					#set up valueRef for current pref
					my $value;
					if (ref($nextParams->{'initialValue'}) eq 'CODE') {
						$value = $nextParams->{'initialValue'}->($client);
					} else {
						$value = Slim::Utils::Prefs::clientGet($client,$nextParams->{'initialValue'});
					}
					$nextParams->{'valueRef'} = \$value;
				}
				Slim::Buttons::Common::pushModeLeft(
					$client
					,$nextParams->{'useMode'}
					,$nextParams
				);
			}
		} elsif (Slim::Buttons::Common::validMode("PLUGIN.".$nextmenu)){
			Slim::Buttons::Common::pushModeLeft($client,"PLUGIN.".$nextmenu);
		} else {
			$client->bumpRight();
		}
	} else {
		return;
	}
}

# load the submenu hash keys into an array of valid entries.
sub createList {
	my $paramsref = shift;
	my @list;
	my %disabledplugins = map {$_ => 1} Slim::Utils::Prefs::getArray('disabledplugins');
	
	foreach my $sub (sort {((Slim::Utils::Prefs::get("rank-$b") || 0) <=> 
				(Slim::Utils::Prefs::get("rank-$a") || 0)) || 
				    (lc(string($a)) cmp lc(string($b)))} 
			 keys %{$paramsref->{'submenus'}}) {
		next if (exists $disabledplugins{$sub});
		push @list, $sub;
	}
	return \@list;
}

# Set a specific home position
sub jump {
	my $client = shift;
	my $item = shift;
	my $depth = shift;
	
	$depth = "" unless defined $depth;
	$client->curDepth($depth);
	$client->curSelection($client->curDepth(),$item);
}

# PushMode to a  specific target pointer within the home menu tree.
sub jumpToMenu {
	my $client = shift;
	my $menu = shift;
	my $depth = shift;
	
	$depth = "" unless defined $depth;
	Slim::Buttons::Home::jump($client,$menu,$depth);
	my $nextParams = Slim::Buttons::Home::getNextList($client);
	Slim::Buttons::Common::pushModeLeft(
		$client
		,'INPUT.List'
		,$nextParams
	);
}

sub homeheader {
	my $client = $_[0];
	my $line1;
	
	if ($client->isa("Slim::Player::SLIMP3")) {
		$line1 = string('SLIMP3_HOME');
	} elsif ($client->isa("Slim::Player::Softsqueeze")) {
		$line1 = string('SOFTSQUEEZE_HOME');
	} else {
		$line1 = string('SQUEEZEBOX_HOME');
	}
	return $line1;
}

#######
#	Routines for generating settings options.
#######
sub menuOptions {
	my $client = shift;
	my %menuChoices = ();
	$menuChoices{""} = "";
	
	foreach my $menuOption (sort keys %home) {
		if ($menuOption eq 'BROWSE_MUSIC_FOLDER' && !Slim::Utils::Prefs::get('audiodir')) {
			next;
		}
		if ($menuOption eq 'SAVED_PLAYLISTS' && !Slim::Utils::Prefs::get('playlistdir')) {
			next;
		}
		$menuChoices{$menuOption} = string($menuOption);
	}
	return %menuChoices;
}

sub unusedMenuOptions {
	my $client = shift;
	my %menuChoices = menuOptions($client);
	delete $menuChoices{""};
	
	foreach my $usedOption (@{$homeChoices{$client}}) {
		delete $menuChoices{$usedOption};
	}
	return sort { $menuChoices{$a} cmp $menuChoices{$b} } keys %menuChoices;
}

sub getHomeChoices {
	my $client = shift;
	return \@{$homeChoices{$client}};
}

sub updateMenu {
	my $client = shift;
	my @home = ();
	
	my %disabledplugins = map {$_ => 1} Slim::Utils::Prefs::getArray('disabledplugins');
	my $pluginsRef = Slim::Buttons::Plugins::installedPlugins();
	foreach my $menuItem (Slim::Utils::Prefs::clientGetArray($client,'menuItem')) {
		next if (exists $disabledplugins{$menuItem});
		next if (!exists $home{$menuItem} && !exists $pluginsRef->{$menuItem});
		push @home, $menuItem;
	}
	if (!scalar @home) {
		push @home, 'NOW_PLAYING';
	}
	$homeChoices{$client} = \@home;
	Slim::Buttons::Common::param($client,'listRef',\@home);
}
 

1;

__END__
