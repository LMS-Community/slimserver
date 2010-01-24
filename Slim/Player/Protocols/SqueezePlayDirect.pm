package Slim::Player::Protocols::SqueezePlayDirect;

use strict;

use MIME::Base64;

# protocol handler for the pseudo protocol spdr://

# This is used to allow remote urls to be passed direct to SqueezePlay clients
# SqueezePlay will then use applet handlers to decide how to parse/play the stream
# This allows SqueezePlay applets to extend playback functionality by requesting
# the server to play a url which will then be interpreted by another part of the applet

# urls are of the form:
#
# spdr://<hander>?params...
#
# where handler identifies a specific playback handler within SP

sub isRemote { 1 }

sub isAudio { 1 }

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

	$song->duration($params{dur})                if $params{dur};
	$song->pluginData('icon',   $params{icon})   if $params{icon};
	$song->pluginData('artist', $params{artist}) if $params{artist};
	$song->pluginData('album',  $params{album})  if $params{album};

	if ($seekdata  && (my $newtime = $seekdata->{'timeOffset'})) {
		$song->startOffset($newtime);
		$client->master->remoteStreamStartTime(Time::HiRes::time() - $newtime);
		$url .= "&start=" . encode_base64($newtime);
	}

	return $url;
}

sub handlesStreamHeadersFully {
	my ($class, $client, $headers) = @_;
	$client->sendContCommand(0, 0);
}

sub parseMetadata { }

sub canSeek {
	my ($class, $client, $song) = @_;
	return $song->duration ? 1 : 0;
}

sub getSeekData {
	my ($class, $client, $song, $newtime) = @_;
	return { timeOffset => $newtime };
}

sub getMetadataFor {
	my ($class, $client) = @_;
	my $song = $client->streamingSong || return {};
	return {
		artist => $song->pluginData('artist'),
		album  => $song->pluginData('album'),
		cover  => $song->pluginData('icon'),
		icon   => $song->pluginData('icon'),
	};
}	

1;
