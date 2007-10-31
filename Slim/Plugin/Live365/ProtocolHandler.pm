package Slim::Plugin::Live365::ProtocolHandler;

# $Id$

use strict;
use base qw( Slim::Player::Protocols::HTTP );

use JSON::XS qw(from_json);
use URI::Escape qw(uri_escape);

use Slim::Player::Playlist;
use Slim::Player::Source;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Timers;

my $log = logger('plugin.live365');

sub new {
	my $class = shift;
	my $args  = shift;
	
	my $url    = $args->{url};
	my $client = $args->{client};
	my $self   = $args->{self};

	if ( $url =~ m{^live365://} ) {

		$log->info("Requested: $url");

		my $realURL = $url;
		$realURL =~ s/^live365/http/;

		$self = $class->SUPER::new( { 
			url     => $realURL, 
			client  => $client, 
			infoUrl => $url,
			create  => 1,
		} );
		
		Slim::Utils::Timers::killTimers( $client, \&getPlaylist );

		Slim::Utils::Timers::setTimer(
			$client,
			Time::HiRes::time(),
			\&getPlaylist,
			$url,
		);

	}
	else {
		
		$log->info("Not a Live365 station URL: $url");
	}

	return $self;
}

# Perform processing before scan
sub onScan {
	my ( $class, $client, $url, $callback ) = @_;
	
	# Get the user's session ID from SN, this is so we
	# don't have to worry about old session ID's in favorites
	my $sessionURL = Slim::Networking::SqueezeNetwork->url(
		'/api/live365/v1/sessionid?url=' . uri_escape($url)
	);

	my $http = Slim::Networking::SqueezeNetwork->new(
		\&gotSession,
		\&gotSessionError,
		{
			client   => $client,
			url      => $url,
			callback => $callback,
		},
	);
	
	$http->get( $sessionURL );
}

sub gotSession {
	my $http     = shift;
	my $client   = $http->params->{client};
	my $url      = $http->params->{url};
	my $callback = $http->params->{callback};
	
	my $session = eval { from_json( $http->content ) };
	if ( $@ ) {
		$http->error( $@ );
		return gotSessionError( $http, $@ );
	}
	
	$log->debug( "Got Live365 sessionid from SN: " . $session->{session_id} );
	
	# Remove any existing session id
	$url =~ s/\?sessionid.+//;
	
	# Transfer the title to the new URL
	my $title = Slim::Music::Info::title( $url );
	
	# Add the current session id
	$url .= '?sessionid=' . uri_escape( $session->{session_id} );

	if ( !$title ) {
		# No title, go get one from SN
		getTitle( $client, $url );
	}
	else {
		$log->debug( "Setting title for $url to $title" );
		Slim::Music::Info::setTitle( $url, $title );
	}
	
	$callback->( $url );
}

sub gotSessionError {
	my $http     = shift;
	my $url      = $http->params->{url};
	my $callback = $http->params->{callback};
	
	if ( $log->is_error ) {
		$log->error( "Error getting Live365 session ID: " . $http->error );
	}
	
	# Callback to scanner with unchanged URL
	$callback->( $url );
}

sub getTitle {
	
}

sub notifyOnRedirect {
	my ( $class, $client, $originalURL, $redirURL ) = @_;
	
	# Live365 redirects like so:
	# http://www.live365.com/play/rocklandusa?sessionid=foo:bar ->
	# http://216.235.81.102:15072/play?membername=foo&session=...
	
	# Scanner calls this method with the new URL so we can cache it
	# for use in canDirectStream
	
	$log->debug("Caching redirect URL: $redirURL");
	
	$client->pluginData( redirURL => $redirURL );
}

sub canDirectStream {
	my ( $class, $client, $url ) = @_;
	
	# We need to check with the base class (HTTP) to see if we
	# are synced or if the user has set mp3StreamingMethod
	my $base = $class->SUPER::canDirectStream( $client, $url );
	if ( !$base ) {
		return 0;
	}

	Slim::Utils::Timers::killTimers( $client, \&getPlaylist );
		
	Slim::Utils::Timers::setTimer(
		$client,
		Time::HiRes::time(),
		\&getPlaylist,
		$url,
	);
	
	my $redirURL = $client->pluginData('redirURL') || 0;

	return $redirURL;
}

sub getPlaylist {
	my ( $client, $url ) = @_;

	if ( !defined $client ) {
		return;
	}

	my $currentSong = Slim::Player::Playlist::url($client);
	my $currentMode = Slim::Player::Source::playmode($client);
	 
	if ( $currentSong ne $url || $currentMode ne 'play' ) {
		$log->debug( "Track changed, stopping playlist fetch" );
		return;
	}
	
	# Talk to SN and get the playlist info
	my ($station) = $url =~ m{play/([^/?]+)};
	
	my $playlistURL = Slim::Networking::SqueezeNetwork->url(
		'/api/live365/v1/playlist/' . uri_escape($station),
	);
	
	my $http = Slim::Networking::SqueezeNetwork->new(
		\&gotPlaylist,
		\&gotPlaylistError,
		{
			client => $client,
			url    => $url,
		},
	);
	
	$log->debug("Getting playlist from SqueezeNetwork");
	
	$http->get( $playlistURL );
}

sub gotPlaylist {
	my $http   = shift;
	my $client = $http->params->{client};
	my $url    = $http->params->{url};
	
	my $track = eval { from_json( $http->content ) };
	
	if ( $log->is_debug ) {
		$log->debug( "Got current track: " . Data::Dump::dump($track) );
	}
	
	if ( $@ || $track->{error} ) {
		$log->error( "Error getting current track: " . ( $@ || $track->{error} ) );
		
		# Display the station name
		my $title = Slim::Music::Info::title($url);
		Slim::Music::Info::setCurrentTitle( $url, $title );
		
		return;
	}
	
	$client->pluginData( currentTrack => $track );

	my $newTitle = $track->{title};
	
	if ( !ref $track->{artist} ) {
		$newTitle .= ' ' . $client->string('BY') . ' ' . $track->{artist};
	}
	
	if ( !ref $track->{album} ) {
		$newTitle .= ' ' . $client->string('FROM') . ' ' . $track->{album};
	}
	
	if ( $newTitle eq 'NONE' ) {
		# No title means it's an ad, use the desc field
		$newTitle = $track->{desc};
	}
	
	Slim::Music::Info::setCurrentTitle( $url, $newTitle);
	
	Slim::Utils::Timers::setTimer(
		$client,
		Time::HiRes::time() + $track->{refresh},
		\&getPlaylist,
		$url,
	);
}

sub gotPlaylistError {
	my $http  = shift;
	my $error = $http->error;
	
	my $client = $http->params->{client};
	my $url    = $http->params->{url};
	
	$log->error( "Error getting current track: $error, will retry in 30 seconds" );
	
	$client->pluginData( currentTrack => 0 );
	
	# Display the station name
	my $title = Slim::Music::Info::title($url);
	Slim::Music::Info::setCurrentTitle( $url, $title );
	
	# Try again
	Slim::Utils::Timers::setTimer(
		$client,
		Time::HiRes::time() + 30,
		\&getPlaylist,
		$url,
	);
}

sub getMetadataFor {
	my ( $class, $client, $url, $forceCurrent ) = @_;
	
	my $track = $client->pluginData('currentTrack');
	
	return unless $track;
	
 	return {
		artist  => ( !ref $track->{artist} ? $track->{artist} : undef ),
		album   => ( !ref $track->{album} ? $track->{album} : undef ),
		title   => $track->{title} || $track->{desc},
		cover   => 'html/images/ServiceProviders/live365.png',
		type    => 'MP3 (Live365)',
	};
	
}

1;
