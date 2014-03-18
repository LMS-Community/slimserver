package Slim::Plugin::Pandora::Plugin;

# $Id$

# Play Pandora via mysqueezebox.com

use strict;
use base qw(Slim::Plugin::OPMLBased);

use URI::Escape qw(uri_escape_utf8);

use Slim::Networking::SqueezeNetwork;
use Slim::Plugin::Pandora::ProtocolHandler;
use Slim::Utils::Unicode;

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.pandora',
	'defaultLevel' => $ENV{PANDORA_DEV} ? 'DEBUG' : 'ERROR',
	'description'  => 'PLUGIN_PANDORA_MODULE_NAME',
});

sub initPlugin {
	my $class = shift;
	
	Slim::Player::ProtocolHandlers->registerHandler(
		pandora => 'Slim::Plugin::Pandora::ProtocolHandler'
	);
	
	# Track Info item
	Slim::Menu::TrackInfo->registerInfoProvider( pandora => (
		after => 'middle',
		func  => \&trackInfoMenu,
	) );

	# Artist Info item
	# FIXME: this adds an onPandora item to artistinfo menus, 
	# but on squeezeplay when pressed the item just locks and doesn't load a menu
#	Slim::Menu::ArtistInfo->registerInfoProvider( pandora => (
#		after => 'middle',
#		func  => \&artistInfoMenu,
#	) );
	
	# Commands init
	Slim::Control::Request::addDispatch(['pandora', 'rate', '_rating'],
		[0, 1, 1, \&rateTrack]);
			
	Slim::Control::Request::addDispatch(['pandora', 'skipTrack'],
		[0, 1, 1, \&skipTrack]);
	
	Slim::Control::Request::addDispatch(['pandora', 'stationDeleted', '_stationId'],
		[0, 1, 1, \&stationDeleted]);

	$class->SUPER::initPlugin(
		feed      => Slim::Networking::SqueezeNetwork->url('/api/pandora/v1/opml'),
		tag       => 'pandora',
		menu      => 'music_services',
		weight    => 10,
		is_app    => 1,
	);
	
	if ( main::WEBUI ) {
		# Add a function to view trackinfo in the web
		Slim::Web::Pages->addPageFunction( 
			'plugins/pandora/trackinfo.html',
			sub {
				my $client = $_[0];
				
				my $url = Slim::Player::Playlist::url($client);
				
				Slim::Web::XMLBrowser->handleWebIndex( {
					client  => $client,
					feed    => Slim::Plugin::Pandora::ProtocolHandler->trackInfoURL( $client, $url ),
					path    => 'plugins/pandora/trackinfo.html',
					title   => 'Pandora Track Info',
					timeout => 35,
					args    => \@_
				} );
			},
		);
	}
}

sub getDisplayName () {
	return 'PLUGIN_PANDORA_MODULE_NAME';
}

# Don't add this item to any menu
sub playerMenu { }

sub rateTrack {
	my $request = shift;
	my $client  = $request->client();
	
	return unless defined $client;
	
	my $song = $client->playingSong() || return;
	
	# ignore if user is not using Pandora
	my $url = $song->currentTrack()->url;
	return unless $url =~ /^pandora/;
	
	my $rating = $request->getParam('_rating');
	
	if ( $rating !~ /^[01]$/ ) {
		main::DEBUGLOG && $log->debug('Invalid Pandora rating, must be 0 or 1');
		return;
	}
	
	my ($stationId) = $url =~ m{^pandora://([^.]+)\.mp3};
	
	# Get the current track
	my $currentTrack = $song->pluginData() || return;
	
	my $trackId = $currentTrack->{trackToken};
	
	# SN URL to submit rating
	my $ratingURL = Slim::Networking::SqueezeNetwork->url(
		  '/api/pandora/v1/opml/trackinfo/rate?stationId=' . $stationId 
		. '&trackId=' . $currentTrack->{trackToken}
		. '&rating=' . $rating
	);
	
	main::DEBUGLOG && $log->debug("Pandora: rateTrack: $rating ($ratingURL)");
	
	my $http = Slim::Networking::SqueezeNetwork->new(
		\&_rateTrackOK,
		\&_rateTrackError,
		{
			client       => $client,
			request      => $request,
			currentTrack => $currentTrack,
			timeout      => 35,
		},
	);
	
	$http->get( $ratingURL );
	
	$request->setStatusProcessing();
}

sub _rateTrackOK {
	my $http    = shift;
	my $client  = $http->params('client');
	my $request = $http->params('request');
	
	my $rating       = $request->getParam('_rating');
	my $currentTrack = $http->params('currentTrack');
	
	main::DEBUGLOG && $log->debug('Rating submit OK');
	
	# If rating was negative and skip is allowed, skip the track
	if ( !$rating && $currentTrack->{canSkip} ) {
		main::DEBUGLOG && $log->debug('Rating was negative, skipping track');
		$client->execute( [ "playlist", "jump", "+1" ] );
	}
	elsif ( !$rating ) {
		main::DEBUGLOG && $log->debug('Rating was negative but no more skips allowed');
	}
	
	# Parse the text out of the JSON
	my ($text) = $http->content =~ m/"text":"([^"]+)/;
	utf8::decode($text);	
	$request->addResult( $text );
	
	$request->setStatusDone();
}

sub _rateTrackError {
	my $http    = shift;
	my $error   = $http->error;
	my $client  = $http->params('client');
	my $request = $http->params('request');
	
	main::DEBUGLOG && $log->debug( "Rating submit error: $error" );
	
	# Not sure what status to use here
	$request->setStatusBadParams();
}

sub skipTrack {
	my $request = shift;
	my $client  = $request->client();
	
	return unless defined $client;
	
	# ignore if user is not using Pandora
	my $song = $client->playingSong() || return;
	my $url = $song->currentTrack()->url;
	return unless $url =~ /^pandora/;
		
	main::DEBUGLOG && $log->debug("Pandora: Skip requested");
		
	$client->execute( [ "playlist", "jump", "+1" ] );
	
	$request->setStatusDone();
}

sub trackInfoMenu {
	my ( $client, $url, $track, $remoteMeta ) = @_;
	
	return unless $client;
	
	# Only show if in the app list
	return unless $client->isAppEnabled('pandora');
	
	my $artist = $track->remote ? $remoteMeta->{artist} : $track->artistName;
	my $title  = $track->remote ? $remoteMeta->{title}  : $track->title;
	
	my $snURL = Slim::Networking::SqueezeNetwork->url(
		'/api/pandora/v1/opml/context?artist='
			. uri_escape_utf8($artist)
			. '&track='
			. uri_escape_utf8($title)
	);
	
	if ( $artist && $title ) {
		return {
			type      => 'link',
			name      => $client->string('PLUGIN_PANDORA_ON_PANDORA'),
			url       => $snURL,
			favorites => 0,
		};
	}
}

sub artistInfoMenu {
	my ( $client, $url, $artist, $remoteMeta ) = @_;
	
	return unless $client;
	
	# Only show if in the app list
	return unless $client->isAppEnabled('pandora');
	
	my $snURL = Slim::Networking::SqueezeNetwork->url(
		'/api/pandora/v1/opml/search?q='
			. uri_escape_utf8($artist->namesearch)
			. '&noauto=1'
	);
	
	if ( $artist && $artist->name ) {
		return {
			type      => 'link',
			name      => $client->string('PLUGIN_PANDORA_ON_PANDORA'),
			url       => $snURL,
			favorites => 0,
		};
	}
}

sub stationDeleted {
	my $request = shift;
	my $client  = $request->client();
	
	return unless defined $client;
	
	# ignore if user is not using Pandora
	my $url = Slim::Player::Playlist::url($client) || return;
	return unless $url =~ /^pandora/;
	
	my $stationId = $request->getParam('_stationId');
	
	# If user was playing this station, stop the player
	if ( $url eq "pandora://${stationId}.mp3" ) {
		main::DEBUGLOG && $log->debug( 'Currently playing station was deleted, stopping playback' );
		
		Slim::Player::Source::playmode( $client, 'stop' );
	}
	
	$request->setStatusDone();
}

1;
