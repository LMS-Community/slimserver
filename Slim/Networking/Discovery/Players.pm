package Slim::Networking::Discovery::Players;

# $Id: Players.pm 18532 2008-04-07 23:10:43Z andy $

# SqueezeCenter Copyright 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

# Keep track of players that are connected to other servers

use strict;

use JSON::XS::VersionOneAndTwo;

use Slim::Control::Request;
use Slim::Networking::Discovery::Server;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Network;
use Slim::Utils::Timers;

my $log = logger('network.protocol');

# List of players we see
my $players = {};

=head1 NAME

Slim::Networking::Discovery::Player

=head1 DESCRIPTION

This module implements methods to get player lists from other servers.


=head1 FUNCTIONS

=head2 init()

initialise the listeners which will update the remote player list when players are connected/disconnected

=cut

sub init {

	# Subscribe to player connect/disconnect messages
	Slim::Control::Request::subscribe(
		\&Slim::Networking::Discovery::Server::fetch_servers,
		[['client'],['new','reconnect']]
	);

	# wait a few seconds before updating to give the player time to connect to other server
	Slim::Control::Request::subscribe(
		sub {
			Slim::Utils::Timers::setTimer(
				undef,
				time() + 5,
				\&Slim::Networking::Discovery::Server::fetch_servers,
			);			
		},
		[['client'],['disconnect','forget']]
	);
}

=head2 getPlayerList()

Remove any player connected to the given server from oure list

=cut

sub getPlayerList {
	return $players;
}

=head2 fetch_players()

Poll the SqueezeCenter/SlimServers in our network for lists of connected players

=cut

sub fetch_players {
	my $server = shift;
	my $url = Slim::Networking::Discovery::Server::getWebHostAddress($server);

	my $http = Slim::Networking::SimpleAsyncHTTP->new(
		\&_players_done,
		\&_players_error,
		{ 
			timeout => 10,
			server  => $server,
		}
	);

	my $postdata = to_json({
		id     => 1,
		method => 'slim.request',
		params => [ '', ['players', 0, 999] ]
	});

	$http->get( $url . 'jsonrpc.js', $postdata);
}

sub _players_done {
	my $http   = shift;
	my $server = $http->params('server');

	my $res = eval { from_json( $http->content ) };

	if ( $@ || ref $res ne 'HASH' || $res->{error} ) {
		$http->error( $@ || 'Invalid JSON response: ' . $http->content );
		return _players_error( $http );
	}
	
	if ( $log->is_debug ) {
		$log->debug( "Got list of players: " . Data::Dump::dump( $res->{result}->{players_loop} ) );
	}

	_purge_player_list($server);

	foreach my $player (@{$res->{result}->{players_loop}}) {
		$players->{$player->{playerid}} = {
			name   => $player->{name},
			server => $server,
			model  => $player->{model},
		}
	}
}

sub _players_error {
	my $http  = shift;
	my $error = $http->error;
	
	$log->error( "Unable to get players: $error" );
}


=head2 _purge_player_list()

Remove any player connected to the given server from oure list

=cut

sub _purge_player_list {
	my $server = shift;

	foreach my $player (keys %{$players}) {
		if ($players->{$player}->{server} eq $server) {
			delete $players->{$player};
		}
	}
}
