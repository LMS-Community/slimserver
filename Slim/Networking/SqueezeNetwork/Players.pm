package Slim::Networking::SqueezeNetwork::Players;

# $Id$

# Keep track of players that are connected to SN

use strict;

use Data::URIEncode qw(complex_to_query);
use JSON::XS::VersionOneAndTwo;

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
my $CONNECTED_PLAYERS = [];
my $INACTIVE_PLAYERS =  [];

# Default polling time
use constant MIN_POLL_INTERVAL => 60;
my $POLL_INTERVAL = MIN_POLL_INTERVAL;

sub init {
	my $class = shift;
	
	fetch_players();
	
	# CLI command for telling a player on SN to connect to us
	Slim::Control::Request::addDispatch(
		['squeezenetwork', 'disconnect', '_id'],
		[0, 1, 0, \&disconnect_player]
	);
	
	# CLI command to trigger a player fetch
	Slim::Control::Request::addDispatch(
		['squeezenetwork', 'fetch_players', '_id'],
		[0, 1, 0, \&fetch_players],
	);

	# Subscribe to player connect/disconnect messages
	Slim::Control::Request::subscribe(
		\&fetch_players,
		[['client'],['new','reconnect']]
	);

	# wait a few seconds before updating to give the player time to connect to SQN
	Slim::Control::Request::subscribe(
		sub {
			Slim::Utils::Timers::setTimer(
				undef,
				time() + 5,
				\&fetch_players,
			);			
		},
		[['client'],['disconnect','forget']]
	);
}

sub shutdown {
	my $class = shift;
	
	$CONNECTED_PLAYERS = [];
	$INACTIVE_PLAYERS  = [];
	
	Slim::Utils::Timers::killTimers( undef, \&fetch_players );
	
	main::INFOLOG && $log->info( "SqueezeNetwork player list shutdown" );
}

sub fetch_players {
	# XXX: may want to improve this for client new/disconnect/reconnect/forget to only fetch
	# player into for that single player
	
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
		$http->error( $@ || 'Invalid JSON response: ' . $http->content );
		return _players_error( $http );
	}
	
	if ( main::DEBUGLOG && $log->is_debug ) {
		$log->debug( "Got list of SN players: " . Data::Dump::dump( $res->{players}, $res->{inactive_players} ) );
		$log->debug( "Got list of active services: " . Data::Dump::dump( $res->{active_services} ));
		$log->debug( "Next player check in " . $res->{next_poll} . " seconds" );
	}
		
	# Update poll interval with advice from SN
	$POLL_INTERVAL = $res->{next_poll};
	
	# Make sure poll interval isn't too small
	if ( $POLL_INTERVAL < MIN_POLL_INTERVAL ) {
		$POLL_INTERVAL = MIN_POLL_INTERVAL;
	}
	
	# Update player list
	$CONNECTED_PLAYERS = $res->{players};
	$INACTIVE_PLAYERS  = $res->{inactive_players};
	
	# Update list of active music services
	if ( $res->{active_services} ) {
		# Avoid updating the pref unless things have changed
		my $new = complex_to_query( $res->{active_services} );
		my $cur = complex_to_query( $prefs->get('sn_active_services') || {} );
		
		if ( $cur ne $new ) {
			main::DEBUGLOG && $log->debug( 'Updating active services from SN' );
			$prefs->set( sn_active_services => $res->{active_services} );
		}
	}
	
	# Make a list of all apps for the web UI
	my $allApps = {};
	
	# Update enabled apps for each player
	# This will create new pref entries for players this server has never seen
	for my $player ( @{ $res->{players} }, @{ $res->{inactive_players} } ) {
		if ( exists $player->{apps} ) {
			my $cprefs = Slim::Utils::Prefs::Client->new( $prefs, $player->{mac}, 'no-migrate' );
			$cprefs->set( apps => $player->{apps} );
			
			for my $app ( keys %{ $player->{apps} } ) {
				$allApps->{$app} = $player->{apps}->{$app};
			}
			
			# Refresh ip3k and Jive menu
			if ( my $client = Slim::Player::Client::getClient( $player->{mac} ) ) {
				if ( !$client->isa('Slim::Player::SqueezePlay') ) {
					Slim::Buttons::Home::updateMenu($client);
				}
				
				Slim::Control::Jive::appMenus($client);
			}
		}
	}
	
	# SN can provide string translations for new menu items
	if ( $res->{strings} ) {
		for my $string ( @{ $res->{strings} } ) {
			Slim::Utils::Strings::storeString( $string->{token}, $string->{strings} );
		}
	}
	
	# Setup apps for the web UI.
	if ( !main::SLIM_SERVICE && !$::noweb ) {
		# Clear all existing my_apps items on the web, we'll build a new list
		Slim::Web::Pages->delPageCategory('my_apps');
		
		for my $app ( keys %{$allApps} ) {
			my $info = $allApps->{$app};
			
			# If this app is supported by a local plugin, we'll use the webpage already setup for it
			# and just copy it to the my_apps list
			if ( $info->{plugin} ) {
				if ( my $plugin = Slim::Utils::PluginManager->isEnabled( $info->{plugin} ) ) {
					my $url = Slim::Web::Pages->getPageLink( 'apps', $plugin->{name} );
					Slim::Web::Pages->addPageLinks( 'my_apps', { $plugin->{name} => $url } );
				}
			}
			elsif ( $info->{type} eq 'opml' ) {
				# Setup a generic OPML menu for this app
				my $url = 'apps/' . $app . '/index.html';
				
				Slim::Web::Pages->addPageLinks( 'my_apps', { $info->{title} => $url } );
				
				my $icon = $info->{icon};
				if ( $icon !~ /^http/ ) {
					# XXX: fix the template to use imageproxy to resize this icon
					$icon = Slim::Networking::SqueezeNetwork->url($icon);
				}
				Slim::Web::Pages->addPageLinks( 'icons', { $info->{title} => $icon } );
				
				my $feed = $info->{url};
				if ( $feed !~ /^http/ ) {
					$feed = Slim::Networking::SqueezeNetwork->url($feed);
				}
				
				Slim::Web::Pages->addPageFunction( $url, sub {
					my $client = $_[0];
					
					warn "Call to $url for $client, using $feed\n";

					Slim::Web::XMLBrowser->handleWebIndex( {
						client  => $client,
						feed    => $feed,
						type    => 'link',
						title   => $info->{title},
						timeout => 35,
						args    => \@_
					} );
				} );
			}
		}
	}
	
	# Clear error count if any
	if ( $prefs->get('snPlayersErrors') ) {
		$prefs->remove('snPlayersErrors');
	}
	
	Slim::Utils::Timers::setTimer(
		undef,
		time() + $POLL_INTERVAL,
		\&fetch_players,
	);
}

sub _players_error {
	my $http  = shift;
	my $error = $http->error;
	
	$prefs->remove('sn_session');
	
	# We don't want a stale list of players, so clear it out on error
	$CONNECTED_PLAYERS = [];
	$INACTIVE_PLAYERS  = [];
	
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
	
	return wantarray ? @{$CONNECTED_PLAYERS} : $CONNECTED_PLAYERS;
}

sub is_known_player {
	my ($class, $client) = @_;
	
	my $mac = ref($client) ? $client->macaddress() : $client;

	return scalar( grep { $mac eq $_->{mac} } @{$CONNECTED_PLAYERS}, @{$INACTIVE_PLAYERS} );	
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
	
	if ( main::DEBUGLOG && $log->is_debug ) {
		$log->debug( "Disconect SN player response: " . Data::Dump::dump( $res ) );
	}
	
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