package Slim::Plugin::Podcast::ProtocolHandler;

# Logitech Media Server Copyright 2005-2020 Logitech.

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use base qw(Slim::Player::Protocols::HTTPS);

use strict;

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Cache;

my $log   = logger('plugin.podcast');
my $prefs = preferences('plugin.podcast');
my $cache = Slim::Utils::Cache->new;

Slim::Player::ProtocolHandlers->registerHandler('podcast', __PACKAGE__);

# remove podcast:// protocol to scan real url
sub scanUrl {
	my ( $class, $url, $args ) = @_;
	
	my $song = $args->{song};
	my ($httpUrl, $startTime) = Slim::Plugin::Podcast::Plugin::unwrapUrl($url);	
	my $cb = $args->{cb};

	# make a unique & clean url with no trailing start time
	$url = Slim::Plugin::Podcast::Plugin::wrapUrl($httpUrl);

	# set seekdata for getNextTrack (once $song->track is updated)
	$song->seekdata({ startTime => $startTime}) if $startTime;
		
	$args->{cb} = sub {
		my $track = shift;

		main::INFOLOG && $log->info("Scanned podcast $url => ", $track->url, " from ($startTime) for title: ", $song->track->title);

		# use the scanned track to get streamable url, ignore scanned title and coverart
		$song->streamUrl($track->url);		
		$track->title(Slim::Music::Info::getCurrentTitle($args->{client}, $url));
		$track->cover(0);

		# reset track's url - from now on all $url-based requests will refer to that track
		$track->url($url);

		# must update playlist time for webUI to refresh - not sure why
		$song->master->currentPlaylistUpdateTime( Time::HiRes::time() );	
		$cb->($track, @_);
	};
	
	$class->SUPER::scanUrl($httpUrl, $args);
}

sub shouldCacheImage { 1 }

sub new {
	my ($class, $args) = @_;
	
	# use streaming url but avoid redirection loop
	$args->{url} = $args->{song}->streamUrl unless $args->{redir};
	return $class->SUPER::new( $args );
}

sub onStop {
    my ($self, $song) = @_;
	my $elapsed = $song->master->controller->playingSongElapsed;
	my ($url) = Slim::Plugin::Podcast::Plugin::unwrapUrl($song->currentTrack->url);

	if ($elapsed > 15 && (!$song->duration || $elapsed < $song->duration - 15)) {
		$cache->set("podcast-$url", int ($elapsed), '30days');
		main::INFOLOG && $log->info("Last position for $url is $elapsed");
	} else {
		$cache->remove("podcast-$url");
	}		
}

sub onStream {
	my ($self, $client, $song) = @_;

	Slim::Plugin::Podcast::Plugin->updateRecentlyPlayed($client, $song);
}

sub getNextTrack {
	my ( $class, $song, $successCb, $errorCb ) = @_;
	my $seekdata = $song->seekdata;

	# set seekdata *after* $song->track has been updated by scanUrl 
	# so that Slim::Music::Info::getBitrate works from unwrapped url
	if (my $startTime = $seekdata->{startTime}) {
		$song->seekdata($song->getSeekData($startTime));
		main::INFOLOG && $log->info("starting from $startTime");
	}
	
	$successCb->();
}		


1;
