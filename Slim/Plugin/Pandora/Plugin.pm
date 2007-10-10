package Slim::Plugin::Pandora::Plugin;

# $Id$

# Play Pandora via SqueezeNetwork

use strict;
use base qw(Slim::Plugin::OPMLBased);

use Slim::Networking::SqueezeNetwork;
use Slim::Plugin::Pandora::ProtocolHandler;

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.pandora',
	'defaultLevel' => $ENV{PANDORA_DEV} ? 'DEBUG' : 'WARN',
	'description'  => 'PLUGIN_PANDORA_MODULE_NAME',
});

sub initPlugin {
	my $class = shift;
	
	Slim::Player::ProtocolHandlers->registerHandler(
		pandora => 'Slim::Plugin::Pandora::ProtocolHandler'
	);
	
	# Commands init
	Slim::Control::Request::addDispatch(['pandora', 'rate', '_rating'],
		[0, 1, 1, \&rateTrack]);
			
	Slim::Control::Request::addDispatch(['pandora', 'skipTrack'],
		[0, 1, 1, \&skipTrack]);

	$class->SUPER::initPlugin(
		feed => Slim::Networking::SqueezeNetwork->url('/api/pandora/opml'),
		tag  => 'pandora',
		'icon-id' => 'html/images/ServiceProviders/pandora_56x56_p.png',
		menu => 'radio',
	);
}

sub getDisplayName () {
	return 'PLUGIN_PANDORA_MODULE_NAME';
}

sub rateTrack {
	my $request = shift;
	my $client  = $request->client();
	
	return unless defined $client;
	
	# ignore if user is not using Pandora
	my $url = Slim::Player::Playlist::url($client) || return;
	return unless $url =~ /^pandora/;
	
	my $rating = $request->getParam('_rating');
	
	if ( $rating !~ /^[01]$/ ) {
		$log->debug('Invalid Pandora rating, must be 0 or 1');
		return;
	}
	
	my ($stationId) = $url =~ m{^pandora://([^.]+)\.mp3};
	
	# Get the current track
	my $currentTrack = $client->pluginData('prevTrack') || $client->pluginData('currentTrack');
	return unless $currentTrack;
	
	my $trackId = $currentTrack->{trackToken};
	
	# SN URL to submit rating
	my $ratingURL = Slim::Networking::SqueezeNetwork->url(
		  '/api/pandora/opml/trackinfo/rate?stationId=' . $stationId 
		. '&trackId=' . $currentTrack->{trackToken}
		. '&rating=' . $rating
	);
	
	$log->debug("Pandora: rateTrack: $rating ($ratingURL)");
	
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
	
	$log->debug('Rating submit OK');
	
	# If rating was negative and skip is allowed, skip the track
	if ( !$rating && $currentTrack->{canSkip} ) {
		$log->debug('Rating was negative, skipping track');
		$client->execute( [ "playlist", "jump", "+1" ] );
	}
	elsif ( !$rating ) {
		$log->debug('Rating was negative but no more skips allowed');
	}
	
	# Parse the text out of the OPML
	my ($text) = $http->content =~ m/text="([^"]+)/;	
	$request->addResult( text => $text );
	
	$request->setStatusDone();
}

sub _rateTrackError {
	my $http    = shift;
	my $error   = $http->error;
	my $client  = $http->params('client');
	my $request = $http->params('request');
	
	$log->debug( "Rating submit error: $error" );
	
	# Not sure what status to use here
	$request->setStatusBadParams();
}

sub skipTrack {
	my $request = shift;
	my $client  = $request->client();
	
	return unless defined $client;
	
	# ignore if user is not using Pandora
	my $url = Slim::Player::Playlist::url($client) || return;
	return unless $url =~ /^pandora/;
		
	$log->debug("Pandora: Skip requested");
	
	# Tell onJump not to display buffering info, so we don't
	# mess up the showBriefly message
	$client->pluginData( banMode => 1 );
	
	$client->execute( [ "playlist", "jump", "+1" ] );
}

1;
