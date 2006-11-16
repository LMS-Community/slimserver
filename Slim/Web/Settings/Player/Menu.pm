package Slim::Web::Settings::Player::Menu;

# $Id: Basic.pm 10633 2006-11-09 04:26:27Z kdf $

# SlimServer Copyright (c) 2001-2006 Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Log;

sub name {
	return 'MENU_SETTINGS';
}

sub page {
	return 'settings/player/menu.html';
}

sub needsClient {
	return 1;
}

sub handler {
	my ($class, $client, $paramRef) = @_;

	if ($client->isPlayer()) {

		my @prefs = ('menuItem');
	
		# If this is a settings update
		my $i;
		for ($i = $client->prefGetArrayMax('menuItem'); $i >= 0; $i--) {
			if (exists $paramRef->{'Action' . $i}) {
	
				my $newval = $paramRef->{'Action' . $i};
				my $tempItem = $client->prefGet('menuItem',$i);
				if (defined $newval) {
					if ($newval eq 'Remove') {
					
						$client->prefDelete('menuItem',$i);
					} elsif ($newval eq 'Up' && $i > 0) {
						
						$client->prefSet('menuItem',$client->prefGet('menuItem',$i - 1),$i);
						$client->prefSet('menuItem',$tempItem,$i - 1);
					} elsif ($newval eq 'Down' && $i < $client->prefGetArrayMax('menuItem')) {
					
						$client->prefSet('menuItem',$client->prefGet('menuItem',$i + 1),$i);
						$client->prefSet('menuItem',$tempItem,$i + 1);
					}
				}
			}
		}
		
		if ($client->prefGetArrayMax('menuItem') < 0) {
			$client->prefSet('menuItem','NOW_PLAYING',0);
		}
		
		if ($paramRef->{'removeItems'}) {
			for ($i = $client->prefGetArrayMax('menuItem'); $i >= 0; $i--) {
				if ($paramRef->{'menuItemRemove' . $i}) {
					$client->prefDelete('menuItem',$i);
				}
			}
		}
		
		if ($paramRef->{'addItems'}) {
			
			for my $i (0..$paramRef->{'nonMenuItems'}) {
				if ($paramRef->{'nonMenuItemAdd' . $i}) {
					$client->prefPush('menuItem',$paramRef->{'nonMenuItemAdd' . $i});
				}
			}
	
			for my $i (0..$paramRef->{'pluginItems'}) {
			
				if (exists $paramRef->{'pluginItemAdd' . $i}) {
					$client->prefPush('menuItem',$paramRef->{'pluginItemAdd' . $i});
				}
			}
	
		}
	
		Slim::Buttons::Home::updateMenu($client);
	
		$paramRef->{'menuItems'}     = [ $client->prefGetArray('menuItem') ];
		$paramRef->{'menuItemNames'} = { map {$_ => Slim::Web::Setup::menuItemName($client, $_)} $client->prefGetArray('menuItem') };
		$paramRef->{'nonMenuItems'}  = { map {$_ => Slim::Web::Setup::menuItemName($client, $_)} Slim::Buttons::Home::unusedMenuOptions($client) };
		$paramRef->{'pluginItems'}   = { map {$_ => Slim::Web::Setup::menuItemName($client, $_)} Slim::Utils::PluginManager::unusedPluginOptions($client) };

	} else {
		# non-SD player, so no applicable display settings
		$paramRef->{'warning'} = Slim::Utils::Strings::string('SETUP_NO_PREFS');
	}
	

	return $class->SUPER::handler($client, $paramRef);
}

1;

__END__
