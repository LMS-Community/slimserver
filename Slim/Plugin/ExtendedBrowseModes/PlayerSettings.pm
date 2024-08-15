package Slim::Plugin::ExtendedBrowseModes::PlayerSettings;

# Logitech Media Server Copyright 2001-2024 Logitech.
# Lyrion Music Server Copyright 2024 Lyrion Community.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Plugin::ExtendedBrowseModes::Settings);

use Slim::Utils::Prefs;

my $prefs = preferences('plugin.extendedbrowsemodes');
my $serverPrefs = preferences('server');

sub name {
	return Slim::Web::HTTP::CSRF->protectName('PLUGIN_EXTENDED_BROWSEMODES');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('plugins/ExtendedBrowseModes/settings/browsemodesplayer.html');
}

sub needsClient { 1 }

sub handler {
	my ($class, $client, $params) = @_;

	my $clientPrefs = $serverPrefs->client($client);

	if ($params->{'saveSettings'}) {
		my $menus = $prefs->get('additionalMenuItems');

		for (my $i = 1; defined $params->{"id$i"}; $i++) {
			my ($menu) = $params->{"id$i"} eq '_new_' ? {} : grep { $_->{id} eq $params->{"id$i"} } @$menus;

			if ($clientPrefs) {
				$clientPrefs->set('disabled_' . $params->{"id$i"}, $params->{"enabled$i"} ? 0 : 1);
				delete $menu->{enabled};
			}
		}
	}

	$class->SUPER::handler($client, $params);
}

1;

__END__
