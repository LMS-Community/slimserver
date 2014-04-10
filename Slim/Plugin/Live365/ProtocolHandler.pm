package Slim::Plugin::Live365::ProtocolHandler;

# $Id$

use strict;
use base qw( Slim::Player::Protocols::HTTP );

use JSON::XS::VersionOneAndTwo;
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
	my $song   = $args->{'song'};
	my $self;
	
	my $realURL = $args->{'song'}->streamUrl();

	if ( $url =~ m{^live365://} && $realURL ) {

		main::INFOLOG && $log->info("Requested: $url, streaming real URL $realURL");

		$self = $class->SUPER::new( { 
			url     => $realURL,
			song    => $song, 
			client  => $client, 
			infoUrl => $url,
			create  => 1,
		} );
		
		Slim::Utils::Timers::killTimers( $song, \&getPlaylist );

		Slim::Utils::Timers::setTimer(
			$song,
			Time::HiRes::time(),
			\&getPlaylist,
		);

	}
	else {
		if ( $log->is_error ) {
			$log->error( $client->string('PLUGIN_LIVE365_NO_URL') );
		}
	}

	return $self;
}

sub getFormatForURL () { 'mp3' }

# Source for AudioScrobbler (R = Radio)
sub audioScrobblerSource () { 'R' }

sub isRemote { 1 }

sub gotURL {
	my $http     = shift;
	my $params   = $http->params;
	my $song     = $params->{'song'};
	
	my $info = eval { from_json( $http->content ) };
	if ( $@ || $info->{error} ) {
		$http->error( $@ || $info->{error} );
		return gotURLError( $http );
	}
	
	main::DEBUGLOG && $log->debug( "Got Live365 URL from SN: " . $info->{url} );
	
	$song->streamUrl($info->{url});
	
	$params->{callback}->();
}

sub gotURLError {
	my $http     = shift;
	
	if ( $log->is_error ) {
		$log->error( "Error getting Live365 URL: " . $http->error );
	}
	
	$http->params->{errorCallback}->('PLUGIN_LIVE365_ERROR', $http->error);	
}

sub scanUrl {
	my ($class, $url, $args) = @_;
	$args->{'cb'}->($args->{'song'}->currentTrack());
}

sub getNextTrack {
	my ($class, $song, $successCb, $errorCb) = @_;
	
	my $nextURL = $song->currentTrack()->url;
	# Remove any existing session id
	$nextURL =~ s/\?+//;
	
	# Talk to SN and get the channel info for this station
	my $getAudioURL = Slim::Networking::SqueezeNetwork->url(
		'/api/live365/v1/playback/getAudioURL?url=' . uri_escape($nextURL)
	);
	
	my $http = Slim::Networking::SqueezeNetwork->new(
		\&gotURL,
		\&gotURLError,
		{
			client        => $song->master(),
			url           => $nextURL,
			song          => $song,
			callback      => $successCb,
			errorCallback => $errorCb,
		},
	);
	
	main::DEBUGLOG && $log->debug( "Getting audio URL for $nextURL from SN" );

	$http->get( $getAudioURL );
}

sub canDirectStreamSong {
	my ( $class, $client, $song ) = @_;
	
	my $streamUrl = $song->streamUrl() || return undef;
	
	# We need to check with the base class (HTTP) to see if we
	# are synced or if the user has set mp3StreamingMethod
	$class->SUPER::canDirectStream( $client, $streamUrl ) || return undef;
	
	Slim::Utils::Timers::killTimers( $song, \&getPlaylist );

	Slim::Utils::Timers::setTimer(
		$song,
		Time::HiRes::time(),
		\&getPlaylist,
	);

	return $streamUrl;
}

sub getPlaylist {
	my ( $song ) = @_;

	my $client = $song->master();
	my $url    = $song->currentTrack()->url;

	if ( $song != $client->streamingSong() || $client->isStopped() || $client->isPaused() ) {
		main::DEBUGLOG && $log->debug( "Track changed, stopping playlist fetch" );
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
			song   => $song,
		},
	);
	
	main::DEBUGLOG && $log->debug("Getting playlist from SqueezeNetwork");
	
	$http->get( $playlistURL );
}

sub gotPlaylist {
	my $http   = shift;
	my $client = $http->params->{client};
	my $url    = $http->params->{url};
	my $song   = $http->params->{'song'};
	
	my $track = eval { from_json( $http->content ) };
	
	if ( main::DEBUGLOG && $log->is_debug ) {
		$log->debug( "Got current track: " . Data::Dump::dump($track) );
	}
	
	if ( $@ || $track->{error} ) {
		$log->error( "Error getting current track: " . ( $@ || $track->{error} ) );
		
		# Display the station name
		my $title = Slim::Music::Info::title($url);
		Slim::Music::Info::setCurrentTitle( $url, $title );
		
		return;
	}
	
	$song->pluginData($track);

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
		$song,
		Time::HiRes::time() + $track->{refresh},
		\&getPlaylist,
	);
}

sub gotPlaylistError {
	my $http  = shift;
	my $error = $http->error;
	
	my $url    = $http->params->{url};
	my $song   = $http->params->{'song'};
		
	$log->error( "Error getting current track: $error, will retry in 30 seconds" );
	
	$song->pluginData(undef);
	
	# Display the station name
	my $title = Slim::Music::Info::title($url);
	Slim::Music::Info::setCurrentTitle( $url, $title );
	
	# Try again
	Slim::Utils::Timers::setTimer(
		$song,
		Time::HiRes::time() + 30,
		\&getPlaylist,
	);
}

sub getMetadataFor {
	my ( $class, $client, $url, $forceCurrent ) = @_;
	
	my $song = $client->currentSongForUrl($url);
	my $track = $song->pluginData() if $song;
	
	my $icon = $class->getIcon();
	
 	return {
		artist  => ( $track && !ref $track->{artist} ? $track->{artist} : undef ),
		album   => ( $track && !ref $track->{album} ? $track->{album} : undef ),
		title   => ( $track ) ? ( $track->{title} || $track->{desc} ) : undef,
		cover   => $icon,
		icon    => $icon,
		type    => 'MP3 (Live365)',
	};
	
}

sub getIcon {
	my ( $class, $url ) = @_;

	return Slim::Plugin::Live365::Plugin->_pluginDataFor('icon');
}

1;
