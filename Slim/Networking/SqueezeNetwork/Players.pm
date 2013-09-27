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
				time() + 2,
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
	
	# Make a list of all apps for the web UI
	my $allApps = {};
	
	# Add 3rd party plugins which have requested to be on the apps menu
	if (my $nonSNApps = Slim::Plugin::Base->nonSNApps) {
		for my $plugin (@$nonSNApps) {
			if ($plugin->can('tag')) {
				$allApps->{ "nonsn_" . $plugin->tag } = { plugin => $plugin };
			}
		}
	}

	# SN can provide string translations for new menu items
	if ( $res->{strings} ) {
		main::DEBUGLOG && $log->is_debug && $log->debug( 'Adding SN-supplied strings: ' . Data::Dump::dump( $res->{strings} ) );
		
		Slim::Utils::Strings::storeExtraStrings( $res->{strings} );
	}
	
	# Update enabled apps for each player
	# This will create new pref entries for players this server has never seen
	for my $player ( @{ $res->{players} }, @{ $res->{inactive_players} } ) {
		if ( exists $player->{apps} ) {
			# Keep a list of all available apps for the web UI
			for my $app ( keys %{ $player->{apps} } ) {
				$allApps->{$app} = $player->{apps}->{$app};
			}
			
			my $cprefs = Slim::Utils::Prefs::Client->new( $prefs, $player->{mac}, 'no-migrate' );
			
			# Compare existing apps to new list
			my $currentApps = complex_to_query( $cprefs->get('apps') || {} );
			my $newApps     = complex_to_query( $player->{apps} );
			
			# Only refresh menus if the list has changed
			if ( $currentApps ne $newApps ) {
				$cprefs->set( apps => $player->{apps} );
			
				# Refresh ip3k and Jive menu
				if ( my $client = Slim::Player::Client::getClient( $player->{mac} ) ) {
					if ( !$client->isa('Slim::Player::SqueezePlay') ) {
						Slim::Buttons::Home::updateMenu($client);
					}
					
					# Clear Jive menu and refresh with new main menu
					Slim::Control::Jive::deleteAllMenuItems($client);
					Slim::Control::Jive::mainMenu($client);
				}
			}
		}
	}
	
	# Setup apps for the web and classic player UI.
	if ( main::WEBUI ) {
		# Clear all existing my_apps items on the web, we'll build a new list
		Slim::Web::Pages->delPageCategory('my_apps');
		
		for my $app ( keys %{$allApps} ) {
			
			# don't initialize if we have a local plugin overriding the mysb.com service
			next if $allApps->{'nonsn_' . $app};
			
			my $info = $allApps->{$app};
			
			# If this app is supported by a local plugin, we'll use the webpage already setup for it
			# and just copy it to the my_apps list
			if ( $info->{plugin} ) {
				if ( my $plugin = Slim::Utils::PluginManager->isEnabled( $info->{plugin} ) ) {
					_updateWebLink($plugin->{name}, $app, $info);
				}
			}
			elsif ( $info->{type} eq 'opml' ) {
				# Setup a generic OPML menu for this app

				my $icon = $info->{icon};
				if ( $icon !~ /^http/ ) {
					$icon = Slim::Networking::SqueezeNetwork->url($icon);
				}
				
				my $feed = $info->{url};
				if ( $feed !~ /^http/ ) {
					$feed = Slim::Networking::SqueezeNetwork->url($feed);
				}
				
				my $tag = lc($app);

				# dynamically create plugin code for mysb.com based apps
				my $subclass = "Slim::Plugin::MySB::$app";

				# don't re-run plugin init if it already exists
				eval { $subclass->getDisplayName() };

				if (!$@) {
					$log->debug("Plugin $subclass already initialized - skipping");
					_updateWebLink($info->{title}, $app);
					next; 
				}

				$log->debug("Initializing plugin for mysqueezebox.com based app '$app': $subclass");
				
				my $code = qq{
					package ${subclass};
					
					use strict;
					use base qw(Slim::Plugin::OPMLBased);
					
					sub initPlugin {
						my \$class = shift;
						
						\$class->SUPER::initPlugin(
							tag    => '$tag',
							menu   => 'apps',
							type   => 'link',
							feed   => '$feed',
							is_app => 1,
						);
					}
					
					sub _pluginDataFor {
						my ( \$class, \$key ) = \@_;
						
						return '$icon' if \$key eq 'icon';
						
						return \$class->SUPER::_pluginDataFor(\$key);
					}

					sub getDisplayName { '$info->{title}' }
					
					sub playerMenu { }
					
					1;				
				};
				
				eval $code;
				
				if ($@) {
					$log->error( "Unable to dynamically create plugin class $subclass: $@" );
				}
				else {
					$subclass->initPlugin();

					_updateWebLink($info->{title}, $app);

					foreach my $client ( Slim::Player::Client::clients() ) {
						if ( !$client->isa('Slim::Player::SqueezePlay') ) {
							Slim::Buttons::Home::updateMenu($client);
						}
					}
				}
			}
		}
	}

	# SN can provide string translations for new menu items
	if ( $res->{search_providers} ) {
		main::DEBUGLOG && $log->is_debug && $log->debug( 'Adding search providers: ' . Data::Dump::dump( $res->{search_providers} ) );

		Slim::Menu::GlobalSearch->registerSearchProviders( $res->{search_providers} );		
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

sub _updateWebLink {
	my $name = shift;
	my $id   = shift;
	my $info = shift;
	
	my $disabled = $prefs->get('sn_disabled_plugins');
	return if $disabled && grep /^$id$/i, @$disabled;
	
	if ($info && $info->{title} && $name && $info->{title} ne $name) {
		my $url = Slim::Web::Pages->getPageLink( 'apps', $name );
		Slim::Web::Pages->addPageLinks( 'my_apps', { $info->{title} => $url } );
		
		# use icon as defined by MySB to allow for white-label solutions
		if ( my $icon = $info->{icon} ) {
			my $pluginData = Slim::Utils::PluginManager->dataForPlugin($info->{plugin});
			$icon = Slim::Networking::SqueezeNetwork->url( $icon, 'external' ) unless $icon =~ /^http/;
			$pluginData->{icon} = $icon;
			
			Slim::Web::Pages->addPageLinks("icons", { $name => $icon });
			Slim::Web::Pages->addPageLinks("icons", { $info->{title} => $icon });
		}
	}
	else {
		my $url = Slim::Web::Pages->getPageLink( 'apps', $name );
		Slim::Web::Pages->addPageLinks( 'my_apps', { $name => $url } );
	}
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
