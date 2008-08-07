package Slim::Plugin::LineIn::Settings;

# SqueezeCenter Copyright 2001-2008 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;
my $prefs = preferences('server');

sub name {
	return Slim::Web::HTTP::protectName('PLUGIN_LINE_IN');
}

sub page {
	return Slim::Web::HTTP::protectURI('plugins/LineIn/settings/player.html');
}

sub validFor {
	my $class = shift;
	my $client = shift;
	
	return $client->isa('Slim::Player::Boom');
}

sub needsClient {
	return 1;
}

sub prefs {
	my ($class, $client) = @_;

	return ($prefs->client($client), qw(lineInLevel lineInAlwaysOn) );
}

1;

__END__
