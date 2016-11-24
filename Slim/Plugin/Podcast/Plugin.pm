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

use constant PROGRESS_INTERVAL => 5;     # update progress tracker every x seconds

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.podcast',
	'defaultLevel' => 'ERROR',
	'description'  => getDisplayName(),
});

my $prefs = preferences('plugin.podcast');
my $cache;

$prefs->init({
	feeds => [],
	skipSecs => 15,
});

# migrate old prefs across
$prefs->migrate(1, sub {
	require Slim::Utils::Prefs::OldPrefs;
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
	
	# Track Info item: jump back X seconds
	Slim::Menu::TrackInfo->registerInfoProvider( podcastRew => (
		before => 'top',
		func   => \&trackInfoMenu,
	) );

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

	if ( $request->isCommand([['playlist'], ['newsong']]) && !($client->pluginData('goto') && $client->pluginData('goto') eq $url) && Slim::Music::Info::isRemoteURL($url) ) {
		$client->pluginData( goto => $url );

		if ( my $newPos = $cache->get("podcast-$url") ) {
			Slim::Player::Source::gototime($client, $newPos);
		}
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

		main::DEBUGLOG && $log->is_debug && $log->debug('Updating podcast progress state ' . Data::Dump::dump({
			player => $client->name,
			url => $url,
			playtime => Slim::Player::Source::songTime($client),
		}));
	
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

sub trackInfoMenu {
	my ( $client, $url, $track, $remoteMeta ) = @_;
	
	return unless $url && $client && $client->isPlaying;
	
	my $song = Slim::Player::Source::playingSong($client);
	return unless $song && $song->canSeek;

	if ( $url && defined $cache->get('podcast-' . $url) ) {
		my $title = $client->string('PLUGIN_PODCAST_SKIP_BACK', $prefs->get('skipSecs'));
		
		return [{
			name => $title,
			url  => sub {
				my ($client, $cb, $params) = @_;
				
				my $position = Slim::Player::Source::songTime($client);
				my $newPos   = $position > $prefs->get('skipSecs') ? $position - $prefs->get('skipSecs') : 0;
				
				main::DEBUGLOG && $log->is_debug && $log->debug(sprintf("Skipping from position %s back to %s", $position, $newPos));

				Slim::Player::Source::gototime($client, $newPos);
			
				$cb->({
					items => [{
						name        => $title,
						showBriefly => 1,
						nowPlaying  => 1, # then return to Now Playing
					}]
				});
			},
			nextWindow => 'parent',
		}];
	}
	
	return;
}

1;