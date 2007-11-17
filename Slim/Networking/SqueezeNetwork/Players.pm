package Slim::Networking::SqueezeNetwork::Players;

# $Id$

# Keep track of players that are connected to SN

use strict;

use JSON::XS qw(from_json);

use Slim::Control::Request;
use Slim::Networking::SqueezeNetwork;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Network;
use Slim::Utils::Prefs;
use Slim::Utils::Timers;

my $log   = logger('network.squeezenetwork');

my $prefs = preferences('server');

# List of players we see on SN
my $PLAYERS = [];

# Default polling time
my $POLL_INTERVAL = 300;

sub init {
	my $class = shift;
	
	fetch_players();
	
	# CLI command for telling a player on SN to connect to us
	Slim::Control::Request::addDispatch(
		['squeezenetwork', 'disconnect', '_id'],
		[0, 1, 0, \&disconnect_player]
	);
}

sub shutdown {
	my $class = shift;
	
	$PLAYERS = [];
	
	Slim::Utils::Timers::killTimers( undef, \&fetch_players );
	
	$log->info( "SqueezeNetwork player list shutdown" );
}

sub fetch_players {
	
	Slim::Utils::Timers::killTimers( undef, \&fetch_players );
	
	# Get the list of players for our account that are on SN
	my $http = Slim::Networking::SqueezeNetwork->new(
		\&_players_done,
		\&_players_error,
	);
	
	$http->get( $http->url( '/api/v1/players' ) );
}

sub _players_done {
	my $http = shift;
	
	my $res = eval { from_json( $http->content ) };
	if ( $@ || ref $res ne 'HASH' || $res->{error} ) {
		$http->error( $@ || 'Invalid JSON response' );
		return _players_error( $http );
	}
	
	if ( $log->is_debug ) {
		$log->debug( "Got list of SN players: " . Data::Dump::dump( $res->{players} ) );
		$log->debug( "Next player check in " . $res->{next_poll} . " seconds" );
	}
		
	# Update poll interval with advice from SN
	$POLL_INTERVAL = $res->{next_poll};
	
	# Make sure poll interval isn't too small
	if ( $POLL_INTERVAL < 300 ) {
		$POLL_INTERVAL = 300;
	}
	
	# Update player list
	$PLAYERS = $res->{players};
	
	# Clear error count if any
	$prefs->remove('snPlayersErrors');
	
	Slim::Utils::Timers::setTimer(
		undef,
		time() + $POLL_INTERVAL,
		\&fetch_players,
	);
}

sub _players_error {
	my $http  = shift;
	my $error = $http->error;
	
	# We don't want a stale list of players, so clear it out on error
	$PLAYERS = [];
	
	# Backoff if we keep getting errors
	my $count = $prefs->get('snPlayersErrors') || 0;
	$prefs->set( snPlayersErrors => $count + 1 );
	my $retry = $POLL_INTERVAL * ( $count + 1 );
	
	$log->error( "Unable to get players from SN: $error, retrying in $retry seconds" );
	
	Slim::Utils::Timers::setTimer(
		undef,
		time() + $retry,
		\&fetch_players,
	);
}

sub get_players {
	my $class = shift;
	
	return wantarray ? @{$PLAYERS} : $PLAYERS;
}

sub disconnect_player {
	my $request = shift;
	my $id      = $request->getParam('_id') || return;
	
	$request->setStatusProcessing();
	
	# Tell an SN player to reconnect to our IP
	my $http = Slim::Networking::SqueezeNetwork->new(
		\&_disconnect_player_done,
		\&_disconnect_player_error,
		{
			request => $request,
		}
	);
	
	my $ip = Slim::Utils::Network::serverAddr();
	
	$http->get( $http->url( '/api/v1/players/disconnect/' . $id . '/' . $ip ) );
}

sub _disconnect_player_done {
	my $http    = shift;
	my $request = $http->params('request');
	
	my $res = eval { from_json( $http->content ) };
	if ( $@ || ref $res ne 'HASH' ) {
		$http->error( $@ || 'Invalid JSON response' );
		return _disconnect_player_error( $http );
	}
	
	if ( $res->{error} ) {
		$http->error( $res->{error} );
		return _disconnect_player_error( $http );
	}
	
	if ( $log->is_debug ) {
		$log->debug( "Disconect SN player response: " . Data::Dump::dump( $res ) );
	}
	
	# Refresh the list of players
	fetch_players();
	
	$request->setStatusDone();
}

sub _disconnect_player_error {
	my $http    = shift;
	my $error   = $http->error;
	my $request = $http->params('request');
	
	$log->error( "Disconnect SN player error: $error" );
	
	$request->addResult( error => $error );
	
	$request->setStatusDone();
}	

1;