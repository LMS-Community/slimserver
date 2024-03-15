package Slim::Plugin::Sounds::ProtocolHandler;
# Handler for forcing loop mode

use strict;
use base 'Slim::Player::Protocols::HTTP';
use Slim::Utils::Log;

my $log = logger('plugin.sounds');

# No scrobbling
sub audioScrobblerSource { }

# Loop mode only works with direct streaming
sub canDirectStream {
	my ( $class, $client, $url ) = @_;

	return $url;
}

sub shouldLoop { 1 }

# Some sounds are small, use a small buffer threshold
sub bufferThreshold { 10 }

sub canSeek { 0 }

sub isAudioURL { 1 }

sub isRemote { 0 }

sub getNextTrack {
	my ( $class, $song, $successCb, $errorCb ) = @_;

	my $url = $song->track()->url;
	my $client = $song->master();

	$url =~ s/^loop:\/\///;
	$url = Slim::Plugin::Sounds::Plugin->getStreamUrl($client, $url);

	main::INFOLOG && $log->is_info && $log->info("Stream loop URL: " . $url =~ s/squeez.*?:.*?@/***:***@/r);

	$song->streamUrl($url);

	$successCb->();
}

sub getMetadataFor {
	my ( $class, $client, $url ) = @_;

	my $icon = Slim::Plugin::Sounds::Plugin->_pluginDataFor('icon');

	return {
		title    => Slim::Plugin::Sounds::Plugin->getSoundName($url),
		cover    => $icon,
		icon     => $icon,
		bitrate  => '128k CBR',
		type     => 'MP3 (Sounds & Effects)',
	};
}

1;