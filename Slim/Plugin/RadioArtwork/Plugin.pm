package Slim::Plugin::RadioArtwork::Plugin;

# Logitech Media Server Copyright 2001-2024 Logitech.
# Lyrion Music Server Copyright 2024-2025 Lyrion Community.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

=pod
	This is a simple artwork lookup plugin for radio stations not providing artwork for the tracks they're playing.
	It can be used as a standalone plugin handling the popular "artist - title" metadata format provided in ICY tags,
	or as the base plugin for an enhanced version.

	The plugin is structured in to logical methods which you should be able to selectively override if wanted:

	* handleTrackCover: the entry point which will be called by LMS with client, stream URL and parsed title info
	* validateRequest: run some checks, whether we have an artist and track title etc. Returns falsy if we should
	  ignore the request (eg. only station name provided).
	* requestIsQueued: check whether we already have a lookup going on for this title. Puts the new client on a
	  queue. This is important to avoid parallel lookups if multiple clients are playing the same station.
	* useCachedIfAvailable: use data from an earlier request if available. Return truthy if data has been found.
	* lookupArtwork: go online to find the artwork, evaluate the response, find the one artwork URL we want to use
	* gotArtwork: would be called by useCachedIfAvailable and lookupArtwork, updates all queued clients
	* titleCleanup, artistCleanup: helper to remove unwanted stuff from titles/names
=cut

use strict;
use JSON::XS::VersionOneAndTwo;
use URI::Escape qw(uri_escape_utf8);

use Slim::Formats::RemoteMetadata;
use Slim::Utils::Cache;
use Slim::Utils::Log;

my $cache = Slim::Utils::Cache->new();
my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.radioartwork',
	'defaultLevel' => 'ERROR',
	'description'  => 'PLUGIN_RADIO_ARTWORK',
});

use constant COVER_SEARCH_URL => 'https://api.lms-community.org/music/track/%s/%s/cover';
use constant FALLBACK_ARTWORK => 'https://i1.sndcdn.com/artworks-x8zI2HVC2pnkK7F5-4xKLyA-t1080x1080.jpg';

my %queue;

sub initPlugin {
	my ($class) = @_;
	Slim::Formats::RemoteMetadata->registerArtworkHandler(sub { $class->handleTrackCover(@_) });
}

sub handleTrackCover {
	my $class = shift;
	my ($client, $url, $titleInfo) = @_;

	main::DEBUGLOG && $log->is_debug && $log->debug("Called to get artwork for $titleInfo, $url");

	my $args = $class->validateRequest(@_);
	return unless $args;

	return if $class->requestIsQueued($args, @_);

	return if $class->useCachedIfAvailable($args, @_);

	$class->lookupArtwork($args, @_);
}

sub validateRequest {
	my ($class, $client, $url, $titleInfo) = @_;

	if (!($titleInfo && $url && $client)) {
		main::INFOLOG && $log->is_info && $log->info("Missing titleInfo, url or client");
		return;
	}

	my $track = Slim::Player::Playlist::track($client);
	if (!($track && $track->url eq $url)) {
		main::INFOLOG && $log->is_info && $log->info("Avoiding lookup for track not currently playing");
		return;
	}

	utf8::decode($titleInfo);
	my ($artist, $title) = split(' - ', $titleInfo);

	if (!$artist || !$title) {
		main::INFOLOG && $log->is_info && $log->info("Title info not in expected format 'artist - title': $titleInfo");
		return;
	}

	$artist = $class->artistCleanup($artist);
	$title  = $class->titleCleanup($title);

	my $artworkLookupUrl = sprintf(COVER_SEARCH_URL, uri_escape_utf8($title), uri_escape_utf8($artist));

	return {
		title => $title,
		artist => $artist,
		artworkLookupUrl => $artworkLookupUrl,
	};
}

# check whether we already have a request for the same artwork in the queue
# if so, add the client to the queue and return truthy
sub requestIsQueued {
	my ($class, $args, $client, $url, $titleInfo) = @_;

	my $artworkLookupUrl = $args->{artworkLookupUrl};
	if (scalar @{$queue{$artworkLookupUrl} || []}) {
		main::DEBUGLOG && $log->is_debug && $log->debug("Already looking up artwork for $artworkLookupUrl");
		push @{$queue{$artworkLookupUrl}}, $client;
		return 1;
	}

	$queue{$artworkLookupUrl} = [ $client ];
	return;
}

# check whether we have a cached result - return truthy if we did
sub useCachedIfAvailable {
	my ($class, $args, $client, $url, $titleInfo) = @_;

	my $cached = $cache->get($class->getCacheKey($args, @_));
	if (defined $cached) {
		main::INFOLOG && $log->is_info && $log->info("Using cached title cover: $cached");

		$class->gotArtwork($args, $client, $url, $titleInfo);

		return 1;
	}

	return;
}

sub cacheFoundArtwork {
	my ($class, $args, $client, $url, $titleInfo) = @_;
	$cache->set($class->getCacheKey($args, @_), $args->{imageUrl}, 86400 * 30);
}

sub getCacheKey {
	my ($class, $args, $client, $url, $titleInfo) = @_;
	return 'rart_' . ($args->{artworkLookupUrl} || $titleInfo);
}

# do the actual lookup for artwork and evaluation of the result returned by the lookup
# call $class->gotArtwork($args) with the image url in $args->{imageUrl} on success
sub lookupArtwork {
	my ($class, $args, $client, $url, $titleInfo) = @_;

	my $title = $args->{title};
	my $artist = $args->{artist};
	my $artworkLookupUrl = $args->{artworkLookupUrl};

	main::INFOLOG && $log->is_info && $log->info("Getting artwork for $title by $artist");

	my $headers = $class->getHeaders($args, $client, $url, $titleInfo);

	Slim::Networking::SimpleAsyncHTTP->new(
		sub {
			my $response = shift;

			my $json = eval { from_json($response->content) };

			$log->warn($@) if $@;

			if ( $json && $json->{picture} && $json->{picture} ne FALLBACK_ARTWORK ) {
				main::DEBUGLOG && $log->is_debug && $log->debug("Found title artwork: " . $json->{picture});
				$args->{imageUrl} = $json->{picture};

				$class->cacheFoundArtwork($args, $client, $url, $titleInfo);

				return $class->gotArtwork($args, $client, $url, $titleInfo);
			}
			elsif ( $json ) {
				main::DEBUGLOG && $log->is_debug && $log->debug("Nothing found: " . $response->content);
			}
			else {
				main::DEBUGLOG && $log->is_debug && $log->debug(Data::Dump::dump($response));
			}

			delete $queue{$artworkLookupUrl};
		},
		sub {
			delete $queue{$artworkLookupUrl};
			$log->error("HTTP error looking up artwork for $artworkLookupUrl");
			main::INFOLOG && $log->error(Data::Dump::dump(shift));
		}
	)->get($artworkLookupUrl, %$headers);
}

sub getHeaders {
	my ($class, $args, $client, $url, $titleInfo) = @_;
	return {
		'X-LMS-Plugin-ID' => $class,
		'X-LMS-Radio-URL' => $url,
	};
}

# called when we have artwork to set - will update all clients waiting for the same artwork
sub gotArtwork {
	my ($class, $args, $client, $url, $titleInfo) = @_;

	my $imageUrl = $args->{imageUrl} || return;
	my $artworkLookupUrl = $args->{artworkLookupUrl};

	while ( my $c = shift @{$queue{$artworkLookupUrl} || []} ) {
		my $song = $c->playingSong() || next();

		$song->pluginData( httpCover => $imageUrl );
		$c->playingSong->pluginData( wmaMeta => {
			icon   => $imageUrl,
			cover  => $imageUrl,
			artist => $args->{artist},
			title  => $args->{title},
		} );

		Slim::Control::Request::notifyFromArray( $c, [ 'newmetadata' ] );
	}
}

# keep these two apart, so we could have optimized versions for each, if we wanted
sub artistCleanup { $_[0]->cleanup($_[1]) }
sub titleCleanup { $_[0]->cleanup($_[1]) }

# simple, generic cleanup of track and artist names - remove additions like "remaster" etc.
sub cleanup {
	my ($class, $text) = @_;

	# music services add too many appendices
	$text =~ s/[([][^)\]]*?(deluxe|edition|remaster|live|anniversary)[^)\]]*?[)\]]//ig;
	$text =~ s/ -[^-]*(deluxe|edition|remaster|live|anniversary).*//ig;

	# specific rule for the "[E]"xplicit flag - it's too specific/short to fit in with the above
	$text =~ s/\[E\]//g;

	# remove trailing non-word characters
	$text =~ s/[\s\W]{2,}$//;
	$text =~ s/\s*$//;

	return $text;
}

1;