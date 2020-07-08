package Slim::Plugin::Podcast::Plugin;

# Logitech Media Server Copyright 2005-2020 Logitech.

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use base qw(Slim::Plugin::OPMLBased);

use Slim::Plugin::Podcast::Parser;
use Slim::Utils::Cache;
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string cstring);
use Slim::Utils::Timers;

use constant PROGRESS_INTERVAL => 5;     # update progress tracker every x seconds

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.podcast',
	'defaultLevel' => 'ERROR',
	'description'  => getDisplayName(),
});

tie my %recentlyPlayed, 'Tie::Cache::LRU', 50;

my $prefs = preferences('plugin.podcast');
my $cache;

$prefs->init({
	feeds => [],
	skipSecs => 15,
	recent => [],
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
	
	%recentlyPlayed = map { $_->{url} => $_ } reverse @{$prefs->get('recent')};

	$class->SUPER::initPlugin(
		feed   => \&handleFeed,
		tag    => 'podcasts',
		menu   => 'apps',
	);
		
	$class->addNonSNApp();
}

sub shutdownPlugin {
	my @played = values %recentlyPlayed;
	$prefs->set('recent', \@played);
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
	
	push @$items, {
		name  => cstring($client, 'PLUGIN_PODCAST_RECENTLY_PLAYED'),
		url   => \&recentHandler,
		type  => 'link',
	};
	
	$cb->({
		items => $items,
	});
}

sub recentHandler {
	my ($client, $cb) = @_;
	my @menu;

	foreach my $item(reverse values %recentlyPlayed) {
		my $entry;
		my $position = $cache->get("podcast-$item->{url}");

		if ( $position && $position < $item->{duration} - 15 ) {

			$position = Slim::Utils::DateTime::timeFormat($position);
			$position =~ s/^0+[:\.]//;		

			$entry = {
				title => $item->{title},
				image => $item->{cover},
				type => 'link',
				items => [ {
					title => cstring($client, 'PLUGIN_PODCAST_PLAY_FROM_POSITION_X', $position),
					enclosure => {
						type   => 'audio',
						url   => $item->{url},
					},	
					url => sub { 
							my ($client, $cb) = @_;
							$client->pluginData(goto => 1);
							delete $entry->{items}->[0]->{play};
							$cb->( $entry->{items}->[0] );
					},
					#duration => $item->{duration},					
				},{
					title => cstring($client, 'PLUGIN_PODCAST_PLAY_FROM_BEGINNING'),
					url   => $item->{url},
					type  => 'audio',
					#duration => $item->{duration},
				}],
			};		
		}	
		else {
			$entry = {
				title => $item->{title},
				image => $item->{cover},
				url   => $item->{url},				
				type  => 'audio',
			};
		}	
		
		unshift @menu, $entry;
	}

	$cb->({ items => \@menu });
}


sub songChangeCallback {
	my $request = shift;

	my $client = $request->client() || return;
	
	# If synced, only listen to the master
	if ( $client->isSynced() ) {
		return unless Slim::Player::Sync::isMaster($client);
	}

	return unless $client->streamingSong;
	my $url = $client->streamingSong->streamUrl;

	if ( defined $cache->get("podcast-$url") && $request->isCommand([['playlist'], ['newsong']]) ) {
		if ( $client->pluginData('goto') ) {
			$client->pluginData( goto => 0 );
			Slim::Player::Source::gototime($client, $cache->get("podcast-$url") || 0);
		}
		
		my $song = $client->streamingSong;
		$recentlyPlayed{$url} ||=  { 
					url      => $url,
					title    => $song->track->title,
					cover    => $song->icon,
					duration => $song->duration,
				};		
		
		main::DEBUGLOG && $log->debug('Setting up timer to track podcast progress...' . Data::Dump::dump($recentlyPlayed{$url}));	
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
	my $key = 'podcast-' . $url;

	Slim::Utils::Timers::killTimers( $client, \&_trackProgress );
	return unless (($client->streamingSong && $client->streamingSong->streamUrl eq $url) || 
				   ($client->playingSong && $client->playingSong->streamUrl eq $url)) && 
				    defined $cache->get($key);

	# start recording position once we are actually playing
	if ($client->isPlaying && $client->playingSong && $client->playingSong->streamUrl eq $url) {	
		$cache->set($key, Slim::Player::Source::songTime($client), '30days');
		
		# track objects aren't persistent across server restarts - keep our own list of podcast durations in the cache
		$cache->set("$key-duration", Slim::Player::Source::playingSongDuration($client), '30days') unless $cache->get("$key-duration");

		main::DEBUGLOG && $log->is_debug && $log->debug('Updating podcast progress state ' . Data::Dump::dump({
			player => $client->name,
			url => $url,
			playtime => Slim::Player::Source::songTime($client),
		}));
	}	

	Slim::Utils::Timers::setTimer(
		$client,
		time() + PROGRESS_INTERVAL,
		\&_trackProgress,
		$url,
	) if $client->isPlaying;
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