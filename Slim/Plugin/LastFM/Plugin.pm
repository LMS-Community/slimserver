package Slim::Plugin::LastFM::Plugin;

# $Id$

# Play Last.fm Radio via SqueezeNetwork

use strict;
use base qw(Slim::Plugin::OPMLBased);

use Slim::Networking::SqueezeNetwork;
use Slim::Plugin::LastFM::ProtocolHandler;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(cstring);
use Slim::Utils::Unicode;

use URI::Escape qw(uri_escape_utf8);

my $log = Slim::Utils::Log->addLogCategory( {
	category     => 'plugin.lfm',
	defaultLevel => 'ERROR',
	description  => 'PLUGIN_LFM_MODULE_NAME',
} );

my $prefs = preferences('plugin.audioscrobbler');

sub initPlugin {
	my $class = shift;
	
	Slim::Player::ProtocolHandlers->registerHandler(
		lfm => 'Slim::Plugin::LastFM::ProtocolHandler'
	);
	
	# Track Info item
	Slim::Menu::TrackInfo->registerInfoProvider( lfm => (
		after => 'middle',
		func  => \&trackInfoMenu,
	) );
	
	# Commands init
	Slim::Control::Request::addDispatch(['lfm', 'rate', '_rating'],
		[0, 1, 1, \&rateTrack]);
			
	Slim::Control::Request::addDispatch(['lfm', 'skipTrack'],
		[0, 1, 1, \&skipTrack]);
	
	$class->SUPER::initPlugin(
		feed => undef, # handled in feed() below
		tag  => 'lfm',
		menu => 'music_services',
	);
	
	if ( $ENV{SLIM_SERVICE} ) {
		my $menu = {
			useMode => sub { $class->setMode(@_) },
			header  => 'PLUGIN_LFM_MODULE_NAME',
		};
		
		# Add as top-level item choice
		Slim::Buttons::Home::addMenuOption(
			'PLUGIN_LFM_MODULE_NAME',
			$menu,
		);
	}
	
	if ( !$ENV{SLIM_SERVICE} ) {
		# Add a function to view trackinfo in the web
		Slim::Web::HTTP::addPageFunction( 
			'plugins/lastfm/trackinfo.html',
			sub {
				my $client = $_[0];
				
				my $url = Slim::Player::Playlist::url($client);
				
				Slim::Web::XMLBrowser->handleWebIndex( {
					feed    => Slim::Plugin::LastFM::ProtocolHandler->trackInfoURL( $client, $url ),
					path    => 'plugins/lastfm/trackinfo.html',
					title   => 'Last.fm Track Info',
					timeout => 35,
					args    => \@_
				} );
			},
		);
	}
}

sub getDisplayName () {
	return 'PLUGIN_LFM_MODULE_NAME';
}

sub feed {
	my ( $class, $client ) = @_;
	
	my $url = Slim::Networking::SqueezeNetwork->url('/api/lastfm/v1/opml');
	
	# Add account to URL, if account is not configured SN will provide an error message
	# instructing user to select an account for this player
	if ( $client ) {
		my $account = $prefs->client($client)->get('account');
		
		if ( $account ) {
			$url .= '?account=' . uri_escape_utf8($account);
		}		
	}
	
	return $url;
}

sub rateTrack {
	my $request = shift;
	my $client  = $request->client();
	
	return unless defined $client;
	
	# ignore if user is not using Last.fm
	my $url = Slim::Player::Playlist::url($client) || return;
	return unless $url =~ /^lfm/;
	
	my $rating = $request->getParam('_rating');
	
	if ( $rating !~ /^[LB]$/ ) {
		$log->debug('Invalid Last.fm rating, must be L or B');
		return;
	}
	
	# Get the current track
	my $currentTrack = $client->pluginData('prevTrack') || $client->pluginData('currentTrack');
	return unless $currentTrack;
	
	my ($station) = $url =~ m{^lfm://(.+)};
	
	my $account = $prefs->client($client)->get('account');
	
	# SN URL to submit rating
	my $ratingURL = Slim::Networking::SqueezeNetwork->url(
		  '/api/lastfm/v1/opml/trackinfo/rate?account=' . uri_escape_utf8($account)
		. '&station=' . uri_escape_utf8($station)
		. '&track='   . uri_escape_utf8( $currentTrack->{title} )
		. '&artist='  . uri_escape_utf8( $currentTrack->{creator} )
		. '&rating='  . $rating
	);
	
	$log->debug("Last.fm: rateTrack: $rating ($ratingURL)");
	
	my $http = Slim::Networking::SqueezeNetwork->new(
		\&_rateTrackOK,
		\&_rateTrackError,
		{
			client       => $client,
			request      => $request,
			url          => $url,
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
	my $url          = $http->params('url');
	
	$log->debug('Rating submit OK');
	
	# If rating was ban and skip is allowed, skip the track
	if ( $rating eq 'B' ) {
		$log->debug('Rating was ban, passing to AudioScrobbler');
		$client->execute( [ 'audioscrobbler', 'banTrack', $url, $currentTrack->{canSkip} ] );
	}
	else {
		$log->debug('Rating was love, passing to AudioScrobbler');
		$client->execute( [ 'audioscrobbler', 'loveTrack', $url ] );
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
	
	# ignore if user is not using Last.fm
	my $url = Slim::Player::Playlist::url($client) || return;
	return unless $url =~ /^lfm/;
		
	$log->debug("Last.fm: Skip requested");
	
	# Tell onJump not to display buffering info, so we don't
	# mess up the showBriefly message
	$client->pluginData( banMode => 1 );
	
	$client->execute( [ "playlist", "jump", "+1" ] );
}

sub trackInfoMenu {
	my ( $client, $url, $track, $remoteMeta ) = @_;
	
	if ( !Slim::Networking::SqueezeNetwork->hasAccount( $client, 'lfm' ) ) {
		return;
	}
	
	my $artist = $track->remote ? $remoteMeta->{artist} : ( $track->artist ? $track->artist->name : undef );
	
	my $snURL = Slim::Networking::SqueezeNetwork->url(
		'/api/lastfm/v1/opml/search_artist?q=' . uri_escape_utf8($artist)
	);
	
	if ( $artist ) {
		return {
			type        => 'link',
			name        => cstring($client, 'PLUGIN_LFM_ON_LASTFM'),
			url         => $snURL,
			favorites   => 0,
		};
	}
	
	return;
}

1;
