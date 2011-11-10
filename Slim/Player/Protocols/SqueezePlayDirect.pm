package Slim::Player::Protocols::SqueezePlayDirect;

use strict;

use MIME::Base64;

use Slim::Utils::Log;

# protocol handler for the pseudo protocol spdr://

# This is used to allow remote urls to be passed direct to SqueezePlay clients
# SqueezePlay will then use applet handlers to decide how to parse/play the stream
# This allows SqueezePlay applets to extend playback functionality by requesting
# the server to play a url which will then be interpreted by another part of the applet

# urls are of the form:
#
# spdr://<handler>?params...
#
# where handler identifies a specific playback handler within SP

my $log = logger('player.streaming.direct');

sub isRemote { 1 }

sub isAudio { 1 }

sub usePlayerProxyStreaming { 0 } # 0 => do not use player-proxy-streaming

sub contentType { 'spdr' }

sub formatOverride { 'spdr' }

sub slimprotoFlags { 0x10 }

sub canDirectStream {
	my ($class, $client, $url) = @_;

	my ($handler) = $url =~ /spdr:\/\/(.+?)\?/;

	if ($handler && $client->can('spDirectHandlers') && $client->spDirectHandlers =~ /$handler/) {
		return $url;
	}
}

sub requestString {
	my ($class, $client, $url, undef, $seekdata) = @_;
	my $song = $client->streamingSong;

	my ($paramstr) = $url =~ /spdr:\/\/.+\?(.*)/;

	my %params;
	for my $param (split /&/, $paramstr) {
		my ($key, $val) = $param =~ /(.*?)=(.*)/;
		$params{$key} = decode_base64($val) || $val;
	}

	$song->duration($params{dur})                  if exists $params{dur};
	$song->pluginData('icon',    $params{icon})    if exists $params{icon};
	$song->pluginData('title',   $params{title})   if exists $params{title};
	$song->pluginData('artist',  $params{artist})  if exists $params{artist};
	$song->pluginData('album',   $params{album})   if exists $params{album};
	$song->pluginData('type',    $params{type})    if exists $params{type};

	if ($seekdata  && (my $newtime = $seekdata->{'timeOffset'})) {
		$song->startOffset($newtime);
		$client->master->remoteStreamStartTime(Time::HiRes::time() - $newtime);
		$url .= "&start=" . encode_base64($newtime);
	}

	# add version so SqueezePlay client knows our capabilites to parse metadata
	# version 0 (no version) - original 7.5 capability
	# version 1 = ability to set title
	$url .= "&ver=1";

	return $url;
}

sub handlesStreamHeaders {
	my ($class, $client, $headers) = @_;
	$client->sendContCommand(0, 0);
	return 1; # all done
}

sub parseMetadata {
	my ( $class, $client, undef, $metadata ) = @_;
	my $song = $client->streamingSong || return {};

	my %meta;
	for my $param (split /&/, $metadata) {
		my ($key, $val) = $param =~ /(.*?)=(.*)/;
		$meta{$key} = decode_base64($val) || $val;
	}

	# set title, artist and album together so they are cleared if any are set
	if (exists $meta{title} || exists $meta{artist} || exists $meta{album}) {
		$song->pluginData('title', $meta{title});
		$song->pluginData('artist', $meta{artist});
		$song->pluginData('album', $meta{album});
	}

	# set duration, icon and type only when sent - persist across track changes
	$song->duration($meta{dur})                 if exists $meta{dur};
	$song->pluginData('icon',    $meta{icon})   if exists $meta{icon};
	$song->pluginData('type',    $meta{type})   if exists $meta{type};

	Slim::Control::Request::notifyFromArray( $client, [ 'newmetadata' ] );
}

sub canSeek {
	my ($class, $client, $song) = @_;
	return $song->duration ? 1 : 0;
}

sub getSeekData {
	my ($class, $client, $song, $newtime) = @_;
	return { timeOffset => $newtime };
}

sub getMetadataFor {
	my ($class, $client, $url) = @_;

	if (my $song = $client->currentSongForUrl($url)) {

		my $ret = {
			artist => $song->pluginData('artist'),
			album  => $song->pluginData('album'),
			cover  => $song->pluginData('icon'),
			icon   => $song->pluginData('icon'),
			type   => $song->pluginData('type'),
		};

		$ret->{'title'} = $song->pluginData('title') if $song->pluginData('title');

		return $ret;
	}

	# non streaming url - see if we can extract metadata from the url
	my ($paramstr) = $url =~ /spdr:\/\/.+\?(.*)/;

	my %params;
	for my $param (split /&/, $paramstr) {
		my ($key, $val) = $param =~ /(.*?)=(.*)/;
		$params{$key} = decode_base64($val) || $val;
	}
	
	return {
		# omit title here as it prevents connecting status being displayed
		artist => $params{artist},
		album  => $params{album},
		cover  => $params{icon},
		icon   => $params{icon},
		type   => $params{type},
	};
}	

1;
