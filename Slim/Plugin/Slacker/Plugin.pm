package Slim::Plugin::Slacker::Plugin;

# $Id$

use strict;
use base qw(Slim::Plugin::OPMLBased);

use URI::Escape qw(uri_escape_utf8);

use Slim::Plugin::Slacker::ProtocolHandler;
use Slim::Networking::SqueezeNetwork;

my $log = Slim::Utils::Log->addLogCategory( {
	category     => 'plugin.slacker',
	defaultLevel => 'ERROR',
	description  => 'PLUGIN_SLACKER_MODULE_NAME',
} );

sub initPlugin {
	my $class = shift;

	Slim::Player::ProtocolHandlers->registerHandler(
		slacker => 'Slim::Plugin::Slacker::ProtocolHandler'
	);
	
	Slim::Player::ProtocolHandlers->registerIconHandler(
		qr|mysqueezebox\.com.*/api/slacker/|, 
		sub { Slim::Plugin::Slacker::Plugin->_pluginDataFor('icon'); }
	);

	# Track Info item
	Slim::Menu::TrackInfo->registerInfoProvider( slacker => (
		after => 'middle',
		func  => \&trackInfoMenu,
	) );
	
	# Commands init
	Slim::Control::Request::addDispatch(['slacker', 'rate', '_rating'],
		[0, 1, 1, \&rateTrack]);
		
	Slim::Control::Request::addDispatch(['slacker', 'skipTrack'],
		[0, 1, 1, \&skipTrack]);
	
	Slim::Control::Request::addDispatch(['slacker', 'play', '_url', '_title'],
		[0, 1, 1, \&playStation]);
	
	Slim::Control::Request::addDispatch(['slacker', 'delete', '_sid'],
		[0, 1, 1, \&deleteStation]);
	
	$class->SUPER::initPlugin(
		feed   => Slim::Networking::SqueezeNetwork->url('/api/slacker/v1/opml'),
		tag    => 'slacker',
		menu   => 'music_services',
		weight => 30,
		is_app => 1,
	);
	
	if ( main::WEBUI ) {
		# Add a function to view trackinfo in the web
		Slim::Web::Pages->addPageFunction( 
			'plugins/slacker/trackinfo.html',
			sub {
				my $client = $_[0];
				
				my $url = Slim::Player::Playlist::url($client);
				
				Slim::Web::XMLBrowser->handleWebIndex( {
					client  => $client,
					feed    => Slim::Plugin::Slacker::ProtocolHandler->trackInfoURL( $client, $url ),
					path    => 'plugins/slacker/trackinfo.html',
					title   => 'Slacker Track Info',
					timeout => 35,
					args    => \@_
				} );
			},
		);
	}
}

sub getDisplayName () {
	return 'PLUGIN_SLACKER_MODULE_NAME';
}

# Don't add this item to any menu
sub playerMenu { }

sub rateTrack {
	my $request = shift;
	my $client  = $request->client();
	
	return unless defined $client;
	
	# ignore if user is not using Slacker
	my $url = Slim::Player::Playlist::url($client) || return;
	return unless $url =~ /^slacker/;
	
	my $rating = $request->getParam('_rating');
	
	if ( $rating !~ /^[FUB]$/ ) {
		main::DEBUGLOG && $log->debug('Invalid Slacker rating, must be F, U, or B');
		return;
	}
	
	my ($stationId) = $url =~ m{^slacker://([^.]+)\.mp3};
	
	# Get the current track
	my $currentTrack = $client->master->pluginData('prevTrack') || $client->master->pluginData('currentTrack');
	return unless $currentTrack;
	
	my $trackId = $currentTrack->{tid};
	
	# SN URL to submit rating
	my $ratingURL = Slim::Networking::SqueezeNetwork->url(
		  '/api/slacker/v1/opml/trackinfo/rate?trackId=' . $trackId
		. '&rating=' . $rating
	);
	
	main::DEBUGLOG && $log->debug("Slacker: rateTrack: $rating ($ratingURL)");
	
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
	if ( $rating eq 'B' && $currentTrack->{skip} eq 'yes' ) {
		main::DEBUGLOG && $log->debug('Rating was negative, skipping track');
		$client->execute( [ "playlist", "jump", "+1" ] );
	}
	elsif ( $rating eq 'B' ) {
		main::DEBUGLOG && $log->debug('Rating was negative but no more skips allowed');
	}
	
	# For a change in rating, adjust our cached track data
	if ( $rating =~ /[FU]/ ) {
		$currentTrack = $client->master->pluginData('prevTrack') || $client->master->pluginData('currentTrack');
		$currentTrack->{trate} = ( $rating eq 'F' ) ? 100 : 0;
		
		# Use prevTrack so we don't clobber any current track data
		$client->master->pluginData( prevTrack => $currentTrack );
		
		# Web UI should auto-refresh the metadata after this,
		# so it will get the new icon
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
	
	# ignore if user is not using Slacker
	my $url = Slim::Player::Playlist::url($client) || return;
	return unless $url =~ /^slacker/;
	
	$client->execute( [ 'playlist', 'jump', '+1' ] );
}

sub playStation {
	my $request = shift;
	my $client  = $request->client();
	
	return unless defined $client;

	my $url   = $request->getParam('_url');
	my $title = $request->getParam('_title');
	
	main::DEBUGLOG && $log->debug("Playing Slacker station $url - $title"); 
	
	Slim::Music::Info::setTitle( $url, $title );
	
	$client->execute( [ 'playlist', 'play', $url ] );
}

sub deleteStation {
	my $request = shift;
	my $client  = $request->client();
	
	return unless defined $client;

	my $sid = $request->getParam('_sid');
	
	# If the deleted station is playing, stop it
	my $url = Slim::Player::Playlist::url($client) || return;
	
	if ( $url =~ /$sid/ ) {
		main::DEBUGLOG && $log->debug( 'Station was deleted, stopping' );
		$client->execute( [ 'playlist', 'clear' ] );
	}
}

sub trackInfoMenu {
	my ( $client, $url, $track, $remoteMeta ) = @_;

	return unless $client;
	
	# Only show if in the app list
	return unless $client->isAppEnabled('slacker');
	
	my $artist = $track->remote ? $remoteMeta->{artist} : $track->artistName;
	
	my $snURL = Slim::Networking::SqueezeNetwork->url(
		'/api/slacker/v1/opml/search?q=' . uri_escape_utf8($artist)
	);
	
	if ( $artist ) {
		return {
			type      => 'link',
			name      => $client->string('PLUGIN_SLACKER_ON_SLACKER'),
			url       => $snURL,
			favorites => 0,
		};
	}
}

1;
