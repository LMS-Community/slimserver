package Slim::Plugin::Podcast::ProtocolHandler;

# Logitech Media Server Copyright 2005-2020 Logitech.

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

=comment

- how is image/icon/cover passed from the OPML item to the track 

When a $url from an OPML item is added to current playlist, a $track object is created 
and its image is obtained by calling handlerForUrl($url)->getMetadataFor($url). 
If this protocol handler is HTTP, it needs to find the image just by using this $url, 
there is no other information. XMLBrowser(s), when adding the url to the playlist, 
call setRemoteMetadata which caches the OPML items's image link as "remote_image_$url". 
Then the getMetadataFor uses this as one of the image sources. 
Now, when playing the $track, a scanUrl is done and if there are redirections, the 
$track->url is modified to $newurl which will then be used in further getMetadataFor calls.
As this $newurl has no image's link entry in the cache, the "remote_entry_$url" is copied
upon each redirection to "remote_image_newurl" during the scan. Ultimately, when the actual
image is cached, getMetadataFor will get a local link to the image proxy

- How scanUrl works

For HTTP(S) protocol handler, the scanUrl calls Slim::Utils::Scanner::Remote::scanURL when
a track starts to play to acquire all necessary informations. The scanUrl is called with 
the $url to scan and a $song object in the $args. 
That $song has a $track object that is created from the original $url set when OPML item 
is added in the playlist. When scanning $url, the Slim::Utils::Scanner::Remote::scanURL
creates a new $track object everytime the final URI returned by the GET is different from 
the $url argument. This happens on HTTP redirection and/or if the $url argument differs 
from $args->{'song'}->track->url. When it finally returns, scanUrl provides the final $track
that is then replaced in the $song object and in the playlist
The podcast plugin is using a "thin" type of protocol handler which simply encapsulate HTTPS(s).
It is convenient to still capture some of the protocol handler's methods and quickly default
to HTTP(S) built-in handling. Typically, the scanUrl de-encapsulate the $url into an HTTP(S)
one (like myph://http://$url) and then relies on normal handling, but there are a few catches. 

1- When a $track object has changed after scanUrl, the required protocol handler is re-evaluated
and replaced by what matches the actual $track->url (there are many protocol handlers but that's
too difficult to describe here). That means that the thin protocol handler would loose control
if the $track->url has been reset to HTTP(S). To avoid that, an optional songHandler() method
is called to see if the thin protocol handler still wants control.

3- Now, not every thin protocol handler's methods will be called after this scan because some
portion of LMS will always call handlerForUrl($track->url) and not use the protocol handler
that is stored inside the $song object. This is a feature or a bug, your choice but for example, 
getMetadataFor will use the $track->url protocol handler, so thin protocol handler will not 
see their getMetadataFor method called after the track has started to play. Note that it will 
be called before, when the track has not been scanned and just sits in the playlist.
	
NB: Before calling scanUrl, do not try to replace manually the $args->{'song'}->{'track'}->url 
with the de-encapsulated $url that is passed an argument, that will mess the whole scanning 
process

=cut

use base qw(Slim::Player::Protocols::HTTPS);

use strict;

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Cache;

my $log   = logger('plugin.podcast');
my $prefs = preferences('plugin.podcast');
my $cache = Slim::Utils::Cache->new;
my $cachePrefix;

Slim::Player::ProtocolHandlers->registerHandler('podcast', __PACKAGE__);

# remove podcast:// protocol to scan real url
sub scanUrl {
	my ( $class, $url, $args ) = @_;
	my $track = $args->{song}->track;
	my ($scanUrl, $from) = Slim::Plugin::Podcast::Plugin::unwrapUrl($url);	
	
	main::INFOLOG && $log->info("Scanning podcast $url for title ", $track->title);

	# as for redirect, need to port to new url the cover/icon set in XMLBrowser
	if ( my $icon = $cache->get($cachePrefix . $url) ) {
		$cache->set($cachePrefix . $scanUrl, $icon, '30 days');
	}
	
	$args->{song}->seekdata( { timeOffset => $from } ) if $from;
	$class->SUPER::scanUrl($scanUrl, $args);
}

# we want to always be the protocol handler for the $song (not track)
sub getSongHandler {
	return __PACKAGE__;
}

# we want the image to be cached for us
sub cacheImage {
	$cachePrefix = $_1;
	return $cachePrefix;
}

sub new {
	my ($class, $args) = @_;
	my $song = $args->{song};	
	my $startTime = $song->seekdata->{timeOffset} if $song->seekdata;
	
	main::INFOLOG && $log->info( "Streaming podcast $args->{url} from $startTime" );
	
	# erase last position from cache
	my ($url) = Slim::Plugin::Podcast::Plugin::unwrapUrl($song->originUrl);
	$cache->remove('podcast-' . $url) if $url;
	
	if ($startTime) {
		my $seekdata = $song->getSeekData($startTime);
		$song->seekdata($seekdata);
	}
	
	return $class->SUPER::new( $args );
}

sub onStop {
    my ($self, $song) = @_;
	my $elapsed = $song->master->controller->playingSongElapsed;
	my ($url) = Slim::Plugin::Podcast::Plugin::unwrapUrl($song->originUrl);

	if ($elapsed > 15 && (!$song->duration || $elapsed < $song->duration - 15)) {
		$cache->set("podcast-$url", int ($elapsed), '30days');
		main::INFOLOG && $log->info("Last position for $url is $elapsed");
	} else {
		$cache->remove("podcast-$url");
	}		
}

sub onStream {
	my ($self, $client, $song) = @_;
	
	Slim::Plugin::Podcast::Plugin->updateRecentlyPlayed( $client, $song );
}


1;
