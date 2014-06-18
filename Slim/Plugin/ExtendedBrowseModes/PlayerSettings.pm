package Slim::Plugin::ExtendedBrowseModes::PlayerSettings;

# Logitech Media Server Copyright 2001-2014 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Plugin::ExtendedBrowseModes::Settings);

use Slim::Utils::Prefs;

sub name {
	return Slim::Web::HTTP::CSRF->protectName('PLUGIN_EXTENDED_BROWSEMODES');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('plugins/ExtendedBrowseModes/settings/browsemodesplayer.html');
}

sub needsClient { 1 }

sub getServerPrefs {
	my ($class, $client) = @_;
	return preferences('server')->client($client);
}

1;

__END__
