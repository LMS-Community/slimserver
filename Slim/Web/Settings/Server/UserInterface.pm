package Slim::Web::Settings::Server::UserInterface;

# $Id$

# SlimServer Copyright (c) 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Player::Client;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Prefs;

my $prefs = preferences('server');

sub name {
	return Slim::Web::HTTP::protectName('INTERFACE_SETTINGS');
}

sub page {
	return Slim::Web::HTTP::protectURI('settings/server/interface.html');
}

sub prefs {
	return ($prefs, qw(skin itemsPerPage refreshRate coverArt artfolder thumbSize) );
}

sub handler {
	my ($class, $client, $paramRef, $pageSetup) = @_;

	if ($paramRef->{'saveSettings'} && $paramRef->{'skin'} ne $prefs->get('skin')) {

		$paramRef->{'warning'} .= join(' ', string("SETUP_SKIN_OK"), $paramRef->{'skin'}, string("HIT_RELOAD"));

		for my $client (Slim::Player::Client::clients()) {

			$client->currentPlaylistChangeTime(Time::HiRes::time());
		}
	}

	$paramRef->{'skinoptions'} = { Slim::Web::HTTP::skins(1) };

	return $class->SUPER::handler($client, $paramRef, $pageSetup);
}

1;

__END__
