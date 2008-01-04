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
	
	my $realURL = $client->pluginData('audioURL');

	if ( $url =~ m{^live365://} && $realURL ) {

		$log->info("Requested: $url, streaming real URL $realURL");

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
		handleError( $client->string('PLUGIN_LIVE365_NO_URL'), $client );
	}

	return $self;
}

sub getFormatForURL () { 'mp3' }

sub isAudioURL () { 1 }

# Source for AudioScrobbler (R = Radio)
sub audioScrobblerSource () { 'R' }

# Perform processing before scan
sub onCommand {
	my ( $class, $client, $cmd, $url, $callback ) = @_;
	
	if ( $cmd eq 'play' ) {	
		# Get the user's session ID from SN, this is so we
		# don't have to worry about old session ID's in favorites
		
		# Remove any existing session id
		$url =~ s/\?+//;
		
		my $getAudioURL = Slim::Networking::SqueezeNetwork->url(
			'/api/live365/v1/playback/getAudioURL?url=' . uri_escape($url)
		);

		my $http = Slim::Networking::SqueezeNetwork->new(
			\&gotURL,
			\&gotURLError,
			{
				client   => $client,
				url      => $url,
				callback => $callback,
			},
		);
		
		$log->debug( "Getting audio URL for $url from SN" );
	
		$http->get( $getAudioURL );
	}
	else {
		return $callback->();
	}
}

sub gotURL {
	my $http     = shift;
	my $client   = $http->params->{client};
	my $url      = $http->params->{url};
	my $callback = $http->params->{callback};
	
	my $info = eval { from_json( $http->content ) };
	if ( $@ || $info->{error} ) {
		$http->error( $@ || $info->{error} );
		return gotURLError( $http );
	}
	
	$log->debug( "Got Live365 URL from SN: " . $info->{url} );
	
	$client->pluginData( audioURL => $info->{url} );
	
	$callback->();
}

sub gotURLError {
	my $http     = shift;
	my $client   = $http->params->{client};
	my $url      = $http->params->{url};
	my $callback = $http->params->{callback};
	
	if ( $log->is_error ) {
		$log->error( "Error getting Live365 URL: " . $http->error );
	}
	
	handleError( $http->error, $client );
	
	# Make sure we re-enable readNextChunkOk
	$client->readNextChunkOk(1);
}

sub handleError {
    my ( $error, $client ) = @_;

	if ( $client ) {
		$client->unblock;
		
		Slim::Buttons::Common::pushModeLeft( $client, 'INPUT.Choice', {
			header  => '{PLUGIN_LIVE365_ERROR}',
			listRef => [ $error ],
		} );
		
		if ( $ENV{SLIM_SERVICE} ) {
		    logError( $client, $error );
		}
		
		# XXX: log to SC event log
	}
}

# On skip, get the audio URL before playback
sub onJump {
    my ( $class, $client, $nextURL, $callback ) = @_;
	
	# Remove any existing session id
	$nextURL =~ s/\?+//;
	
	my $getAudioURL = Slim::Networking::SqueezeNetwork->url(
		'/api/live365/v1/playback/getAudioURL?url=' . uri_escape($nextURL)
	);

	my $http = Slim::Networking::SqueezeNetwork->new(
		\&gotURL,
		\&gotURLError,
		{
			client   => $client,
			url      => $nextURL,
			callback => $callback,
		},
	);
	
	$log->debug( "Getting audio URL for $nextURL from SN" );

	$http->get( $getAudioURL );
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
	
	my $audioURL = $client->pluginData('audioURL');
	return 0 unless $audioURL;
		
	Slim::Utils::Timers::setTimer(
		$client,
		Time::HiRes::time(),
		\&getPlaylist,
		$url,
	);

	return $audioURL;
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
	
	# Delay the title set depending on buffered data
	Slim::Music::Info::setDelayedTitle( $client, $url, $newTitle );
	
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
	
	my $icon = Slim::Plugin::Live365::Plugin->_pluginDataFor('icon');
	
 	return {
		artist  => ( !ref $track->{artist} ? $track->{artist} : undef ),
		album   => ( !ref $track->{album} ? $track->{album} : undef ),
		title   => $track->{title} || $track->{desc},
		cover   => $icon,
		icon    => $icon,
		type    => 'MP3 (Live365)',
	};
	
}

1;
