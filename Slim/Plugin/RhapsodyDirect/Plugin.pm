package Slim::Plugin::RhapsodyDirect::Plugin;

# Browse Rhapsody Direct via SqueezeNetwork

use strict;
use base 'Slim::Plugin::OPMLBased';

use Slim::Networking::SqueezeNetwork;
use Slim::Plugin::RhapsodyDirect::ProtocolHandler;

use URI::Escape qw(uri_escape_utf8);

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
		qr|mysqueezebox\.com.*/api/rhapsody/|, 
		sub { Slim::Plugin::RhapsodyDirect::ProtocolHandler->getIcon(); }
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
		is_app => 1,
	);
	
	if ( main::WEBUI ) {
		# Add a function to view trackinfo in the web
		Slim::Web::Pages->addPageFunction( 
			'plugins/rhapsodydirect/trackinfo.html',
			sub {
				my $client = $_[0];
				my $params = $_[1];
				
				my $url;
				
				my $id = $params->{sess} || $params->{item};
				
				if ( $id ) {
					# The user clicked on a different URL than is currently playing
					if ( my $track = Slim::Schema->find( Track => $id ) ) {
						$url = $track->url;
					}
					
					# Pass-through track ID as sess param
					$params->{sess} = $id;
				}
				else {
					$url = Slim::Player::Playlist::url($client);
				}
				
				Slim::Web::XMLBrowser->handleWebIndex( {
					client  => $client,
					feed    => Slim::Plugin::RhapsodyDirect::ProtocolHandler->trackInfoURL( $client, $url ),
					path    => 'plugins/rhapsodydirect/trackinfo.html',
					title   => 'Napster Direct Track Info',
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

sub getDisplayName () {
	return 'PLUGIN_RHAPSODY_DIRECT_MODULE_NAME';
}

# Don't add this item to any menu
sub playerMenu { }

sub handleError {
	my ( $error, $client ) = @_;
	
	main::DEBUGLOG && $log->debug("Error during request: $error");
	
	# Strip long number string from front of error
	$error =~ s/\d+( : )?//;
	
	# XXX: Need to give error feedback for web requests

	if ( $client ) {
		$client->unblock;
		
		Slim::Buttons::Common::pushModeLeft( $client, 'INPUT.Choice', {
			header  => '{PLUGIN_RHAPSODY_DIRECT_ERROR}',
			listRef => [ $error ],
		} );
	}
}

sub createPlaylist {
	my $request = shift;
	my $client  = $request->client || return;
	
	my $name     = $request->getParam('_name');
	my @trackIds = split /,/, $request->getParam('_trackIds');
	
	if ( !$name || !scalar @trackIds ) {
		main::DEBUGLOG && $log->debug( 'createplaylist requires name and trackIds params' );
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
	
	main::DEBUGLOG && $log->debug('Playlist created OK');
	
	$request->setStatusDone();
}

sub gotCreatePlaylistError {
	my $http    = shift;
	my $request = $http->params->{request};
	my $error   = $http->error;
	
	main::DEBUGLOG && $log->debug( "Playlist creation failed: $error" );
	
	$request->setStatusBadParams();
}

sub trackInfoMenu {
	my ( $client, $url, $track, $remoteMeta ) = @_;
	
	return unless $client;
	
	my $label;
	if ($client->isAppEnabled('rhapsodydirect')) {
		$label = 'PLUGIN_RHAPSODY_DIRECT_ON_RHAPSODY';
	}
	elsif ($client->isAppEnabled('rhapsodyeu')) {
		$label = 'PLUGIN_RHAPSODY_DIRECT_ON_RHAPSODY_EU';
	}
	
	# Only show if in the app list
	return unless $label;
	
	my $artist = $track->remote ? $remoteMeta->{artist} : $track->artistName;
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
			name      => $client->string($label),
			url       => $snURL,
			favorites => 0,
		};
	}
}
	
1;
