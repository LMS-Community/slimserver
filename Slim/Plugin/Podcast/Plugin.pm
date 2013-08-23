package Slim::Plugin::Podcast::Plugin;

# Copyright 2005-2013 Logitech

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use base qw(Slim::Plugin::OPMLBased);

use Slim::Plugin::Podcast::Parser;
use Slim::Utils::Cache;
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Timers;

use constant PROGRESS_INTERVAL => main::SLIM_SERVICE ? 15 : 5;     # update progress tracker every x seconds

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.podcast',
	'defaultLevel' => 'ERROR',
	'description'  => getDisplayName(),
});

my $prefs = preferences('plugin.podcast');
my $cache;

$prefs->init({
	feeds => [],
});

# migrate old prefs across
$prefs->migrate(1, sub {
	my @names  = @{Slim::Utils::Prefs::OldPrefs->get('plugin_podcast_names') || [] };
	my @values = @{Slim::Utils::Prefs::OldPrefs->get('plugin_podcast_feeds') || [] };
	my @feeds;

	for my $name (@names) {
		push @feeds, { 'name' => $name, 'value' => shift @values };
	}

	if (@feeds) {
		$prefs->set('feeds', \@feeds);
	}

	1;
});

sub initPlugin {
	my $class = shift;

	$cache = Slim::Utils::Cache->new();
		
	if (main::WEBUI) {
		require Slim::Plugin::Podcast::Settings;
		Slim::Plugin::Podcast::Settings->new();
	}

	$class->SUPER::initPlugin(
		feed   => \&handleFeed,
		tag    => 'podcasts',
		menu   => 'apps',
	);
	
	$class->addNonSNApp();
}

sub handleFeed {
	my ($client, $cb, $params, $args) = @_;

	# hook in to new song event - show "jump to last position" menu if matching a podcast
	Slim::Control::Request::subscribe(\&songChangeCallback, [['playlist'], ['newsong', 'pause', 'stop']]);

	my $items = [];
	
#	my @feeds = main::SLIM_SERVICE ? feedsForClient($client) : @{$prefs->get('feeds')}; 
	my @feeds = @{$prefs->get('feeds')}; 
	
	foreach ( @feeds ) {
		push @$items, {
			name => $_->{name},
			url  => $_->{value},
			parser => 'Slim::Plugin::Podcast::Parser',
		}
	}
	
	$cb->({
		items => $items,
	});
}

sub songChangeCallback {
	my $request = shift;

	my $client = $request->client() || return;
	
	# If synced, only listen to the master
	if ( $client->isSynced() ) {
		return unless Slim::Player::Sync::isMaster($client);
	}

	my $url = Slim::Player::Playlist::url($client);
	
	if ( $url =~ /#slimpodcast/ && $request->isCommand([['playlist'], ['newsong']]) ) {
		my $key = 'podcast-position-' . $url;
		if ( my $newPos = $cache->get($key) ) {
			$cache->remove($key);
			Slim::Player::Source::gototime($client, $newPos);
		}
		
		$url =~ s/#slimpodcast.*//;
	}

	if ( defined $cache->get('podcast-' . $url) ) {
		main::DEBUGLOG && $log->debug('Setting up timer to track podcast progress...');	
		Slim::Utils::Timers::killTimers( $client, \&_trackProgress );
		Slim::Utils::Timers::setTimer(
			$client,
			time() + PROGRESS_INTERVAL,
			\&_trackProgress,
			$url,
		);
	}
}

# if this is a podcast, set up a timer to track progress
sub _trackProgress {
	my $client = shift || return;
	my $url    = shift || return;

	return unless Slim::Player::Playlist::url($client) =~ /$url/;

	Slim::Utils::Timers::killTimers( $client, \&_trackProgress );

	my $key = 'podcast-' . $url;
	if ( defined $cache->get($key) ) {
		$cache->set($key, Slim::Player::Source::songTime($client), '30days');
		
		# track objects aren't persistent across server restarts - keep our own list of podcast durations in the cache
		$cache->set("$key-duration", Slim::Player::Source::playingSongDuration($client), '30days') unless $cache->get("$key-duration");

		main::DEBUGLOG && $log->is_debug && $log->debug('Updating podcast progress state for ' . $client->name . ': ' . Slim::Player::Source::songTime($client));
	
		Slim::Utils::Timers::setTimer(
			$client,
			time() + PROGRESS_INTERVAL,
			\&_trackProgress,
			$url,
		) if $client->isPlaying;
	}
}

sub getDisplayName {
	return 'PLUGIN_PODCAST';
}

# SN only
# XXX - do we still run this plugin on SN?
=pod
sub feedsForClient { if (main::SLIM_SERVICE) {
	my $client = shift;
	
	my $userid = $client->playerData->userid->id;
	
	my @f = SDI::Service::Model::FavoritePodcast->search(
		userid => $userid,
		{ order_by => 'num' }
	);
													  
	my @feeds = map { 
		{ 
			name  => $_->title, 
			value => $_->url,
		}
	} @f;
	
	# check if the user deleted feeds so we don't load the defaults
	my $deletedFeeds = preferences('server')->client($client)->get('deleted_podcasts');
	
	# Populate with all default feeds
	if ( !scalar @feeds && !$deletedFeeds ) {
		@feeds = map { 
			{ 
				name  => $_->title, 
				value => $_->url,
			}
		} SDI::Service::Model::FavoritePodcast->addDefaults( $userid );
	}
	
	return @feeds;
} }
=cut

1;