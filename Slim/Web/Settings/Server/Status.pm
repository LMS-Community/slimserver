package Slim::Web::Settings::Server::Status;

# $Id: Basic.pm 13299 2007-09-27 08:59:36Z mherger $

# SqueezeCenter Copyright (c) 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Log;
use Slim::Utils::Prefs;

sub name {
	return 'SERVER_STATUS';
}

sub page {
	return 'settings/server/status.html';
}

sub handler {
	my ($class, $client, $paramRef) = @_;

	my @versions = Slim::Utils::Misc::settingsDiagString();

	$paramRef->{server}{'versionInfo'}              = join( "<br />\n", @versions ) . "\n";
	$paramRef->{server}{'INFORMATION_HOSTNAME'}     = Slim::Utils::Network::hostName;
	$paramRef->{server}{'INFORMATION_SERVER_PORT'}  = preferences('server')->get('httpport');
	$paramRef->{server}{'networkProxy'}             = preferences('server')->get('networkproxy');
	$paramRef->{server}{'INFORMATION_CLIENTS'}      = Slim::Player::Client::clientCount;

	$paramRef->{library}{'INFORMATION_TRACKS'}  = Slim::Utils::Misc::delimitThousands(Slim::Schema->count('Track', { 'me.audio' => 1 }));
	$paramRef->{library}{'INFORMATION_ALBUMS'}  = Slim::Utils::Misc::delimitThousands(Slim::Schema->count('Album'));
	$paramRef->{library}{'INFORMATION_ARTISTS'} = Slim::Utils::Misc::delimitThousands(Slim::Schema->rs('Contributor')->browse->count);
	$paramRef->{library}{'INFORMATION_GENRES'}  = Slim::Utils::Misc::delimitThousands(Slim::Schema->count('Genre'));
	$paramRef->{library}{'INFORMATION_TIME'}    = Slim::Buttons::Information::timeFormat(Slim::Schema->totalTime);

	for my $client (Slim::Player::Client::clients()) {
		$paramRef->{clients}{$client->id}{'INFORMATION_PLAYER_NAME_ABBR'}       = $client->name;
		$paramRef->{clients}{$client->id}{'INFORMATION_PLAYER_MODEL_ABBR'}      = Slim::Buttons::Information::playerModel($client);
		$paramRef->{clients}{$client->id}{'INFORMATION_FIRMWARE_ABBR'}          = $client->revision;
		$paramRef->{clients}{$client->id}{'PLAYER_IP_ADDRESS'}                  = $client->ipport;
		$paramRef->{clients}{$client->id}{'PLAYER_MAC_ADDRESS'}                 = $client->macaddress;
		$paramRef->{clients}{$client->id}{'INFORMATION_PLAYER_SIGNAL_STRENGTH'} = $client->signalStrength;
		$paramRef->{clients}{$client->id}{'INFORMATION_PLAYER_VOLTAGE'}         = $client->voltage;
	}
	
	# TODO Get something useful from any Jive devices on the network.
	#$paramRef->{controllers} = undef;

	# skeleton for the progress update
	$paramRef->{progress} = ${ Slim::Web::Pages::Progress::progress($client, {
		ajaxUpdate => 1,
		type       => 'importer',
		webroot    => $paramRef->{webroot}
	}) };

	return Slim::Web::HTTP::filltemplatefile($class->page, $paramRef);
}

1;

__END__
