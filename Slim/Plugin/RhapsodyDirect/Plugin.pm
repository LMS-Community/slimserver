package Slim::Plugin::RhapsodyDirect::Plugin;

# $Id$

# Browse Rhapsody Direct via SqueezeNetwork

use strict;
use base 'Slim::Plugin::OPMLBased';

use Slim::Networking::SqueezeNetwork;
use Slim::Plugin::RhapsodyDirect::ProtocolHandler;
use Slim::Plugin::RhapsodyDirect::RPDS ();

use URI::Escape qw(uri_escape_utf8);

use constant SN_DEBUG => 0;

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.rhapsodydirect',
	'defaultLevel' => $ENV{RHAPSODY_DEV} ? 'DEBUG' : 'ERROR',
	'description'  => 'PLUGIN_RHAPSODY_DIRECT_MODULE_NAME',
});

sub initPlugin {
	my $class = shift;
	
	Slim::Player::ProtocolHandlers->registerHandler(
		rhapd => 'Slim::Plugin::RhapsodyDirect::ProtocolHandler'
	);

	Slim::Player::ProtocolHandlers->registerIconHandler(
		qr|squeezenetwork\.com.*/api/rhapsody/|, 
		sub { Slim::Plugin::RhapsodyDirect::ProtocolHandler->getIcon(); }
	);
	
	Slim::Networking::Slimproto::addHandler( 
		RPDS => \&Slim::Plugin::RhapsodyDirect::RPDS::rpds_handler
	);
	
	# Track Info item
	Slim::Menu::TrackInfo->registerInfoProvider( rhapsody => (
		after => 'middle',
		func  => \&trackInfoMenu,
	) );

	$class->SUPER::initPlugin(
		feed   => Slim::Networking::SqueezeNetwork->url('/api/rhapsody/v1/opml'),
		tag    => 'rhapsodydirect',
		menu   => 'music_services',
		weight => 20,
	);
	
	if ( main::SLIM_SERVICE ) {
		# Also add to the My Music menu
		my $my_menu = {
			useMode => sub { $class->myLibraryMode(@_) },
			header  => 'PLUGIN_RHAPSODY_DIRECT_MY_RHAPSODY_LIBRARY',
		};
		
		Slim::Buttons::Home::addSubMenu( 
			'MY_MUSIC',
			'PLUGIN_RHAPSODY_DIRECT_MY_RHAPSODY_LIBRARY',
			$my_menu,
		);
		
		# Add as top-level item choice
		Slim::Buttons::Home::addMenuOption(
			'PLUGIN_RHAPSODY_DIRECT_MY_RHAPSODY_LIBRARY',
			$my_menu,
		);
		
		# Setup additional CLI methods for this menu
		$class->initCLI(
			feed         => Slim::Networking::SqueezeNetwork->url('/api/mp3tunes/v1/opml/library/getLastDateLibraryUpdated'),
			tag          => 'rhapsody_library',
			menu         => 'my_music',
			display_name => 'PLUGIN_RHAPSODY_DIRECT_MY_RHAPSODY_LIBRARY',
		);
	}
	
	if ( !main::SLIM_SERVICE ) {
		# Add a function to view trackinfo in the web
		Slim::Web::HTTP::addPageFunction( 
			'plugins/rhapsodydirect/trackinfo.html',
			sub {
				my $client = $_[0];
				my $params = $_[1];
				
				my $url;
				
				if ( $params->{item} ) {
					# The user clicked on a different URL than is currently playing
					if ( my $track = Slim::Schema->find( Track => $params->{item} ) ) {
						$url = $track->url;
					}
				}
				else {
					$url = Slim::Player::Playlist::url($client);
				}
				
				Slim::Web::XMLBrowser->handleWebIndex( {
					client  => $client,
					feed    => Slim::Plugin::RhapsodyDirect::ProtocolHandler->trackInfoURL( $client, $url ),
					path    => 'plugins/rhapsodydirect/trackinfo.html',
					title   => 'Rhapsody Direct Track Info',
					timeout => 35,
					args    => \@_
				} );
			},
		);
	}
	
	# CLI-only command to create a Rhapsody playlist given a set of trackIds
	Slim::Control::Request::addDispatch(
		[ 'rhapsodydirect', 'createplaylist', '_name', '_trackIds' ],
		[ 1, 1, 0, \&createPlaylist ]
	);
}

sub playerMenu () {
	return 'MUSIC_SERVICES';
}

sub getDisplayName () {
	return 'PLUGIN_RHAPSODY_DIRECT_MODULE_NAME';
}

# SLIM_SERVICE
sub myLibraryMode {
	my ( $class, $client, $method ) = @_;

	if ($method eq 'pop') {

		Slim::Buttons::Common::popMode($client);
		return;
	}

	# use INPUT.Choice to display the list of feeds
	my $name = 'PLUGIN_RHAPSODY_DIRECT_MY_RHAPSODY_LIBRARY';
	
	my %params = (
		header   => $name,
		modeName => $name,
		url      => $class->feed() . '/library/getLastDateLibraryUpdated',
		title    => $client->string( $name ),
		timeout  => 35,
	);

	Slim::Buttons::Common::pushMode( $client, 'xmlbrowser', \%params );

	# we'll handle the push in a callback
	$client->modeParam( handledTransition => 1 );
}
# /SLIM_SERVICE

sub handleError {
	my ( $error, $client ) = @_;
	
	$log->debug("Error during request: $error");
	
	# Strip long number string from front of error
	$error =~ s/\d+( : )?//;
	
	# Allow status updates again
	$client->suppressStatus(0);
	
	# XXX: Need to give error feedback for web requests

	if ( $client ) {
		$client->unblock;
		
		Slim::Buttons::Common::pushModeLeft( $client, 'INPUT.Choice', {
			header  => '{PLUGIN_RHAPSODY_DIRECT_ERROR}',
			listRef => [ $error ],
		} );
		
		if ( main::SLIM_SERVICE ) {
		    logError( $client, $error );
		}
	}
}

sub logError {
	my ( $client, $error ) = @_;
	
	return unless SN_DEBUG;
	
	SDI::Service::EventLog->log( 
		$client, 'rhapsody_error', $error,
	);
}

sub createPlaylist {
	my $request = shift;
	my $client  = $request->client || return;
	
	my $name     = $request->getParam('_name');
	my @trackIds = split /,/, $request->getParam('_trackIds');
	
	if ( !$name || !scalar @trackIds ) {
		$log->debug( 'createplaylist requires name and trackIds params' );
		$request->setStatusBadParams();
		return;
	}
	
	my $url = Slim::Networking::SqueezeNetwork->url(
		"/api/rhapsody/v1/opml/library/createMemberPlaylistFromTracks"
	);
	
	my $http = Slim::Networking::SqueezeNetwork->new(
		\&gotCreatePlaylist,
		\&gotCreatePlaylistError,
		{
			request => $request,
			client  => $client,
			timeout => 60,
		},
	);
	
	my $post 
		= 'name=' . uri_escape_utf8($name)
		. '&trackIds=' . join( ',', @trackIds );

	$http->post(
		$url,
		'Content-Type' => 'application/x-www-form-urlencoded',
		$post,
	);
	
	$request->setStatusProcessing();
}

sub gotCreatePlaylist {
	my $http    = shift;
	my $request = $http->params->{request};
	
	$log->debug('Playlist created OK');
	
	$request->setStatusDone();
}

sub gotCreatePlaylistError {
	my $http    = shift;
	my $request = $http->params->{request};
	my $error   = $http->error;
	
	$log->debug( "Playlist creation failed: $error" );
	
	$request->setStatusBadParams();
}

sub trackInfoMenu {
	my ( $client, $url, $track, $remoteMeta ) = @_;
	
	# can't access rhapsody without a player
	return unless $client;
	
	if ( !Slim::Networking::SqueezeNetwork->hasAccount( $client, 'rhapsody' ) ) {
		return;
	}
	
	my $artist = $track->remote ? $remoteMeta->{artist} : ( $track->artist ? $track->artist->name : undef );
	my $album  = $track->remote ? $remoteMeta->{album}  : ( $track->album ? $track->album->name : undef );
	my $title  = $track->remote ? $remoteMeta->{title}  : $track->title;
	
	my $snURL = Slim::Networking::SqueezeNetwork->url(
		'/api/rhapsody/v1/opml/context?artist='
			. uri_escape_utf8($artist)
			. '&album='
			. uri_escape_utf8($album)
			. '&track='
			. uri_escape_utf8($title)
	);
	
	if ( $artist && ( $album || $title ) ) {
		return {
			type      => 'link',
			name      => $client->string('PLUGIN_RHAPSODY_DIRECT_ON_RHAPSODY'),
			url       => $snURL,
			favorites => 0,
		};
	}
}

1;
