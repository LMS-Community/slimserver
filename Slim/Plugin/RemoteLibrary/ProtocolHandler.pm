package Slim::Plugin::RemoteLibrary::ProtocolHandler;

use strict;
use base qw(Slim::Player::Protocols::HTTP);

use JSON::XS::VersionOneAndTwo;

use Slim::Networking::SimpleAsyncHTTP;
use Slim::Utils::Cache;
use Slim::Utils::Log;

my $log = Slim::Utils::Log->addLogCategory( {
	'category'     => 'plugin.remotelibrary',
	'defaultLevel' => 'ERROR',
	'description'  => 'PLUGIN_REMOTE_LIBRARY_MODULE_NAME',
} );

my $cache = Slim::Utils::Cache->new;

sub canSeek { 1 }

sub isRemote { 1 }

# Source for AudioScrobbler
sub audioScrobblerSource {
	# P = Chosen by the user
	return 'P';
}

# Avoid scanning
sub scanUrl {
	my ($class, $url, $args) = @_;
	$args->{cb}->($args->{song}->currentTrack());
}

sub getNextTrack {
	my ( $class, $song, $successCb, $errorCb ) = @_;
	
	my $url = $song->track()->url;
	my ($baseUrl, $id, $file) = _parseUrl($url);

	$url = $baseUrl . join('/', 'music', $id, $file);
	
	main::DEBUGLOG && $log->is_debug && $log->debug("Setting streaming URL: $url");
	
	$song->streamUrl($url);
	
	$successCb->();
}

sub getMetadataFor {
	my ( $class, $client, $url, $forceCurrent ) = @_;
	
	my $meta = $cache->get('remotelibrary_' . $url);
	my $song = $client->playingSong();

	my ($baseUrl, $id, $file) = _parseUrl($url);

	if ($song && $song->streamUrl && $song->streamUrl eq $url) {
		$song->streamUrl($baseUrl . join('/', 'music', $id, $file));
	}
	
	if ( !$meta && !$client->pluginData('fetchingMetadata') ) {
		$song->pluginData( fetchingMetadata => 1 );

		my $postdata = to_json({
			id     => 1,
			method => 'slim.request',
			params => [ '', ['songinfo', 0, 999, 'track_id:' . $id, 'tags:acdgilortyY'] ]
		});

		Slim::Networking::SimpleAsyncHTTP->new(
			\&_gotMetadata,
			sub {
				my $http = shift;
				$log->error( "Failed to get metadata from $url: " . ($http->error || $http->mess || Data::Dump::dump($http)) );
			},
			{
				timeout => 30,
				client  => $client,
				song    => $song,
				url     => $url,
			},
		)->post( $baseUrl . 'jsonrpc.js', $postdata );
	}
	
	if ($meta && keys $meta) {
		$song->duration($meta->{duration}) if $meta->{duration};

		# bitrate is a formatted string (eg. "320kbps") - need to transform into number
		if (my $bitrate = $meta->{bitrate}) {
			$bitrate = $bitrate * 1.0;
			$bitrate *= 1000 if $bitrate !~ /^\d{5,}$/;
			$song->bitrate($bitrate) if $bitrate;
		}
	}
	
	return $meta || {};
}

sub _gotMetadata {
	my $http = shift;
	my $url  = $http->params('url');
	my $song = $http->params('song');
	my $client = $http->params('client');

	my $res = eval { from_json( $http->content ) };

	if ( $@ || ref $res ne 'HASH' ) {
		$log->error( $@ || 'Invalid JSON response: ' . $http->content );
		return;
	}
	
	if ( !$res->{result} && $res->{result}->{songinfo_loop} ) {
		$http->error( 'Unexpected response data: ' . Data::Dump::dump($res) );
	}
	
	my $meta = {
		map {
			my ($k, $v) = each %$_;
			$k => $v;
		} @{ $res->{result}->{songinfo_loop} }
	};

	if ($meta->{coverid}) {
		my ($remote_library) = $url =~ m|lms://(.*?)/music/|;
		$meta->{cover} = Slim::Plugin::RemoteLibrary::Plugin::_proxiedImage({
			'image' => delete $meta->{coverid}
		}, $remote_library);
	}

	if ($song) {
		$song->pluginData( fetchingMetadata => 0 );
	}

	$cache->set('remotelibrary_' . $url, $meta);
	
	# Update the playlist time so the web will refresh, etc
	$client->currentPlaylistUpdateTime( Time::HiRes::time() );
	
	Slim::Control::Request::notifyFromArray( $client, [ 'newmetadata' ] );
}

sub _parseUrl {
	my $url = shift;
	
	my ($uuid, $id, $file) = $url =~ m|lms://(.*?)/music/(\d+?)/(.*)|;
	my $baseUrl = Slim::Networking::Discovery::Server::getWebHostAddress($uuid);
	
	return ($baseUrl || $uuid, $id, $file);
}

1;
