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
	my ($scanUrl, $startTime) = Slim::Plugin::Podcast::Plugin::unwrapUrl($url);	
	
	my $cb = $args->{cb};
	
	$args->{cb} = sub {
		my $track = shift;

		main::INFOLOG && $log->info("Scanned podcast $url from ($startTime) for title: ", $song->track->title);
		$song->streamUrl($track->url);		

		# reset track's url first otherwise url-based methods will fail
		$track->url($url);

		# set seekdata so they can be used in proxied and direct
		if ($startTime) {
			my $seekdata = $song->getSeekData($startTime);
			$song->seekdata($seekdata);
		}

		# must update playlist time for webUI to refresh - not sure why
		$song->master->currentPlaylistUpdateTime( Time::HiRes::time() );	
		$cb->($track, @_);
	};
	
	$class->SUPER::scanUrl($scanUrl, $args);
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

	# ignore updated title that comes from parsing stream	
	my $title = Slim::Music::Info::getCurrentTitle($client, $song->currentTrack->redir);	
	Slim::Music::Info::setCurrentTitle($song->currentTrack->url, $title, $client);
	$song->currentTrack->title($title);	
	
	Slim::Plugin::Podcast::Plugin->updateRecentlyPlayed($client, $song);
}


1;
