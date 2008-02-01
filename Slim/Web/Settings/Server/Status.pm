package Slim::Web::Settings::Server::Status;

# $Id: Basic.pm 13299 2007-09-27 08:59:36Z mherger $

# SqueezeCenter Copyright 2001-2007 Logitech.
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
	my $osDetails = Slim::Utils::OSDetect::details();
	
	$paramRef->{'versionInfoString'}    = join( "<br />\n", @versions ) . "\n";
	
	$paramRef->{server} = [
		{INFORMATION_ARCHITECTURE => ($osDetails->{'osArch'} ? $osDetails->{'osArch'} : 'unknown')},
		{INFORMATION_HOSTNAME     => Slim::Utils::Network::hostName},
		{INFORMATION_SERVER_PORT  => preferences('server')->get('httpport')},
		#{networkProxy             => preferences('server')->get('networkproxy');
		{INFORMATION_CLIENTS      => Slim::Player::Client::clientCount},
		{INFORMATION_CACHEDIR     => preferences('server')->get('cachedir')},
		{INFORMATION_PREFSDIR     => preferences('server')->get('prefsdir')},
		{INFORMATION_PLUGINDIRS   => join(", ",Slim::Utils::OSDetect::dirsFor('Plugins'))},
	];

	$paramRef->{library} =  [
		{INFORMATION_TRACKS  => Slim::Utils::Misc::delimitThousands(Slim::Schema->count('Track', { 'me.audio' => 1 }))},
		{INFORMATION_ALBUMS  => Slim::Utils::Misc::delimitThousands(Slim::Schema->count('Album'))},
		{INFORMATION_ARTISTS => Slim::Utils::Misc::delimitThousands(Slim::Schema->rs('Contributor')->browse->count)},
		{INFORMATION_GENRES  => Slim::Utils::Misc::delimitThousands(Slim::Schema->count('Genre'))},
		{INFORMATION_TIME    => Slim::Buttons::Information::timeFormat(Slim::Schema->totalTime)},
	];

	$paramRef->{logs} = [
		{SERVER  => Slim::Utils::Log->serverLogFile},
		{SCANNER => Slim::Utils::Log->scannerLogFile},
		{PERFMON => ($::perfmon ? Slim::Utils::Log->perfmonLogFile : undef )},
	];

	for my $client (Slim::Player::Client::clients()) {
		$paramRef->{clients}{$client->id} = [
			{ INFORMATION_PLAYER_NAME_ABBR       => $client->name },
			{ INFORMATION_PLAYER_MODEL_ABBR      => Slim::Buttons::Information::playerModel($client) },
			{ INFORMATION_FIRMWARE_ABBR          => $client->revision },
			{ PLAYER_IP_ADDRESS                  => $client->ipport },
			{ PLAYER_MAC_ADDRESS                 => $client->macaddress },
			{ INFORMATION_PLAYER_SIGNAL_STRENGTH => $client->signalStrength },
			{ INFORMATION_PLAYER_VOLTAGE         => $client->voltage },
		];
	}

	# TODO Get something useful from any Jive devices on the network.
	#$paramRef->{controllers} = undef;

	# skeleton for the progress update
	$paramRef->{progress} = ${ Slim::Web::Pages::Progress::progress($client, {
		ajaxUpdate => 1,
		type       => 'importer',
		webroot    => $paramRef->{webroot}
	}) };

	return $class->SUPER::handler($client, $paramRef);
}

1;

__END__
