package Slim::Networking::SqueezeNetwork::Players;

# $Id$

# Keep track of players that are connected to SN

use strict;

use JSON::XS qw(from_json);

use Slim::Networking::SqueezeNetwork;
use Slim::Utils::Log;
use Slim::Utils::Misc;
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
	if ( $@ || ref $res ne 'HASH' ) {
		$http->error( $@ || 'Invalid JSON response' );
		return _players_error( $http );
	}
	
	if ( $log->is_debug ) {
		$log->debug( "Got list of SN players: " . Data::Dump::dump( $res->{players} ) );
	}
	
	# Update poll interval with advice from SN
	$POLL_INTERVAL = $res->{next_poll};
	
	# Update player list
	$PLAYERS = $res->{players};
	
	# Clear error count if any
	$prefs->remove('snPlayersErrors');
	
	Slim::Utils::Timers::setTimer(
		undef,
		time() + $POLL_INTERVAL,
		\&init,
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
		\&init,
	);
}

sub get_players {
	my $class = shift;
	
	return wantarray ? @{$PLAYERS} : $PLAYERS;
}

1;