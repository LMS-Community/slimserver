package Slim::Web::Settings::Player::Menu;

# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string);

sub name {
	return Slim::Web::HTTP::CSRF->protectName('MENU_SETTINGS');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('settings/player/menu.html');
}

sub needsClient {
	return 1;
}

sub validFor {
	my $class = shift;
	my $client = shift;
	
	return !$client->display->isa('Slim::Display::NoDisplay');
}

sub handler {
	my ($class, $client, $paramRef) = @_;

	if ($client->isPlayer()) {

		my $prefs = preferences('server');
		my @menu  = @{ $prefs->client($client)->get('menuItem') };

		for (my $i = $#menu; $i >= 0; $i--) {

			if (my $action = $paramRef->{'Action' . $i}) {

				if ($action eq 'Remove') {

					splice @menu, $i, 1;

				} elsif ($action eq 'Up' && $i > 0) {

					my $temp = splice @menu, $i, 1;
					splice @menu, $i - 1, 0, $temp;

				} elsif ($action eq 'Down' && $i < $#menu) {

					my $temp = splice @menu, $i, 1;
					splice @menu, $i + 1, 0, $temp;
				}
			}

			if ($paramRef->{'removeItems'} && $paramRef->{'menuItemRemove' . $i}) {

				splice @menu, $i, 1;
			}
		}

		if ($paramRef->{'addItems'}) {

			for my $i (0..$paramRef->{'nonMenuItems'}) {

				if ($paramRef->{'nonMenuItemAdd' . $i}) {

					push @menu, $paramRef->{'nonMenuItemAdd' . $i};
				}
			}

			for my $i (0..$paramRef->{'pluginItems'}) {

				if (exists $paramRef->{'pluginItemAdd' . $i}) {

					push @menu, $paramRef->{'pluginItemAdd' . $i};
				}
			}
		}

		if (!@menu) {

			push @menu, 'NOW_PLAYING';
		}

		$prefs->client($client)->set('menuItem', \@menu);

		Slim::Buttons::Home::updateMenu($client);

		$paramRef->{'menuItems'}     = \@menu;
		$paramRef->{'menuItemNames'} = { map {$_ => menuItemName($client, $_)} @menu };
		$paramRef->{'nonMenuItems'}  = { map {$_ => menuItemName($client, $_)} Slim::Buttons::Home::unusedMenuOptions($client) };
		#$paramRef->{'pluginItems'}   = { map {$_ => menuItemName($client, $_)} Slim::Utils::PluginManager->unusedPluginOptions($client) };

	} else {

		# non-SD player, so no applicable display settings
		$paramRef->{'warning'} = string('SETUP_NO_PREFS');
	}

	return $class->SUPER::handler($client, $paramRef);
}

sub menuItemName {
	my ($client, $value) = @_;

	my %plugins = map {$_ => 1} Slim::Utils::PluginManager->installedPlugins();

	if (Slim::Utils::Strings::stringExists($value)) {

		my $string = $client->string($value);

		if (Slim::Utils::Strings::stringExists($string)) {

			return $client->string($string);
		}

		return $string;

	} elsif ($value && exists $plugins{$value}) {

		return $client->string($value->displayName);
	}

	return $value;
}

1;

__END__
