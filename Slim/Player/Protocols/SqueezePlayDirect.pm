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

	$song->duration($params{dur})                  if exists $params{dur};
	$song->pluginData('icon',    $params{icon})    if exists $params{icon};
	$song->pluginData('artist',  $params{artist})  if exists $params{artist};
	$song->pluginData('album',   $params{album})   if exists $params{album};
	$song->pluginData('type',    $params{type})    if exists $params{type};

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

sub parseMetadata {
	my ( $class, $client, undef, $metadata ) = @_;
	my $song = $client->streamingSong || return {};

	my %meta;
	for my $param (split /&/, $metadata) {
		my ($key, $val) = $param =~ /(.*?)=(.*)/;
		$meta{$key} = decode_base64($val) || $val;
	}

	$song->duration($meta{dur})                 if exists $meta{dur};
	$song->pluginData('icon',    $meta{icon})   if exists $meta{icon};
	$song->pluginData('artist',  $meta{artist}) if exists $meta{artist};
	$song->pluginData('album',   $meta{album})  if exists $meta{album};
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
		return {
			artist => $song->pluginData('artist'),
			album  => $song->pluginData('album'),
			cover  => $song->pluginData('icon'),
			icon   => $song->pluginData('icon'),
			type   => $song->pluginData('type'),
		};
	}

	# non streaming url - see if we can extract metadata from the url
	my ($paramstr) = $url =~ /spdr:\/\/.+\?(.*)/;

	my %params;
	for my $param (split /&/, $paramstr) {
		my ($key, $val) = $param =~ /(.*?)=(.*)/;
		$params{$key} = decode_base64($val) || $val;
	}
	
	return {
		artist => $params{artist},
		album  => $params{album},
		cover  => $params{icon},
		icon   => $params{icon},
		type   => $params{type},
	};
}	

1;
