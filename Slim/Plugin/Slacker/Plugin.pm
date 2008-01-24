package Slim::Plugin::Slacker::Plugin;

# $Id$

use strict;
use base qw(Slim::Plugin::OPMLBased);

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
	);
	
	if ( !$ENV{SLIM_SERVICE} ) {
		# Add a function to view trackinfo in the web
		Slim::Web::HTTP::addPageFunction( 
			'plugins/slacker/trackinfo.html',
			sub {
				my $client = $_[0];
				
				my $url = Slim::Player::Playlist::url($client);
				
				Slim::Web::XMLBrowser->handleWebIndex( {
					feed    => Slim::Plugin::Slacker::ProtocolHandler->trackInfoURL( $client, $url ),
					path    => 'trackinfo.html',
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

sub rateTrack {
	my $request = shift;
	my $client  = $request->client();
	
	return unless defined $client;
	
	# ignore if user is not using Slacker
	my $url = Slim::Player::Playlist::url($client) || return;
	return unless $url =~ /^slacker/;
	
	my $rating = $request->getParam('_rating');
	
	if ( $rating !~ /^[FUB]$/ ) {
		$log->debug('Invalid Slacker rating, must be F, U, or B');
		return;
	}
	
	my ($stationId) = $url =~ m{^slacker://([^.]+)\.mp3};
	
	# Get the current track
	my $currentTrack = $client->pluginData('prevTrack') || $client->pluginData('currentTrack');
	return unless $currentTrack;
	
	my $trackId = $currentTrack->{tid};
	
	# SN URL to submit rating
	my $ratingURL = Slim::Networking::SqueezeNetwork->url(
		  '/api/slacker/v1/opml/trackinfo/rate?trackId=' . $trackId
		. '&rating=' . $rating
	);
	
	$log->debug("Slacker: rateTrack: $rating ($ratingURL)");
	
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
	if ( $rating eq 'B' && $currentTrack->{skip} eq 'yes' ) {
		$log->debug('Rating was negative, skipping track');
		$client->execute( [ "playlist", "jump", "+1" ] );
	}
	elsif ( $rating eq 'B' ) {
		$log->debug('Rating was negative but no more skips allowed');
	}
	elsif ( $rating eq 'F' ) {
		# Notify AudioScrobbler of the rating
		my $url = Slim::Player::Playlist::url($client);
		$client->execute( [ 'audioscrobbler', 'loveTrack', $url ] );
	}
	
	# For a change in rating, adjust our cached track data
	if ( $rating =~ /[FU]/ ) {
		$currentTrack = $client->pluginData('prevTrack') || $client->pluginData('currentTrack');
		$currentTrack->{trate} = ( $rating eq 'F' ) ? 100 : 0;
		
		# Use prevTrack so we don't clobber any current track data
		$client->pluginData( prevTrack => $currentTrack );
		
		# Web UI should auto-refresh the metadata after this,
		# so it will get the new icon
	}
	
	# Parse the text out of the OPML
	my ($text) = $http->content =~ m/text="([^"]+)/;	
	$request->addResult( text => Slim::Utils::Unicode::utf8on($text) );
	
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
	
	# ignore if user is not using Slacker
	my $url = Slim::Player::Playlist::url($client) || return;
	return unless $url =~ /^slacker/;
	
	# Tell onJump not to display buffering info, so we don't
	# mess up the showBriefly message
	$client->pluginData( banMode => 1 );
	
	$client->execute( [ 'playlist', 'jump', '+1' ] );
}

sub playStation {
	my $request = shift;
	my $client  = $request->client();
	
	return unless defined $client;

	my $url   = $request->getParam('_url');
	my $title = $request->getParam('_title');
	
	$log->debug("Playing Slacker station $url - $title"); 
	
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
		$log->debug( 'Station was deleted, stopping' );
		$client->execute( [ 'playlist', 'clear' ] );
	}
}

1;
