package Slim::Plugin::Podcast::Plugin;

# Logitech Media Server Copyright 2005-2020 Logitech.

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use base qw(Slim::Plugin::OPMLBased);

use XML::Simple;

use Slim::Plugin::Podcast::Parser;
use Slim::Utils::Cache;
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string cstring);
use Slim::Utils::Timers;

use Slim::Plugin::Podcast::ProtocolHandler;

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

sub updateRecentlyPlayed {
	my ($class, $client, $song) = @_;
	my ($url) = unwrapUrl($song->originUrl);

	$recentlyPlayed{$url} ||= { 
			url      => $url,
			title    => $song->track->title,
			cover    => Slim::Player::ProtocolHandlers->iconForURL($url, $client),
			duration => $song->duration,
	};	
}

sub unwrapUrl {
	return shift =~ m|^podcast://([^{]+)(?:{from=(\d+)}$)?|;	
}

sub wrapUrl {
	my ($url, $from) = @_;
	
	return 'podcast://' . $url . ($from ? "&from=$from" : '');
}

sub handleFeed {
	my ($client, $cb, $params, $args) = @_;

	my $items = [];
	my @feeds = @{$prefs->get('feeds')}; 

	foreach ( @feeds ) {
		my $url = $_->{value};
		my $image = $cache->get('podcast-rss-' . $url);

		push @$items, {
			name => $_->{name},
			url  => $url,
			parser => 'Slim::Plugin::Podcast::Parser',
			image => $image || __PACKAGE__->_pluginDataFor('icon'),
		};

		Slim::Networking::SimpleAsyncHTTP->new(
			sub { 
				eval {
					my $xml = XMLin(shift->content);
					my $image = $xml->{channel}->{image}->{url} || $xml->{channel}->{'itunes:image'}->{href};
					$cache->set('podcast-rss-' . $url, $image, '90days') if $image;
				};
			},
			sub {
				$log->warn("can't get RSS feed icon ", shift->error);
			},
		)->get($_->{value}) unless $image;
	}
	
	push @$items, {
		name  => cstring($client, 'PLUGIN_PODCAST_RECENTLY_PLAYED'),
		url   => \&recentHandler,
		type  => 'link',
		image => __PACKAGE__->_pluginDataFor('icon'),
	};
	
	$cb->({
		items => $items,
	});
}

sub recentHandler {
	my ($client, $cb) = @_;
	my @menu;

	foreach my $item(reverse values %recentlyPlayed) {
		my $from = $cache->get('podcast-' . $item->{url});
		
		# every entry here has a remote_image_ cached item so we can have
		# a direct play entry all the time, even if it has played fully
		my $entry = {
			title => $item->{title},
			image => $item->{cover},
			type  => 'audio',			
			play  => wrapUrl($item->{url}),			
			on_select => 'play',
		};

		if ( $from && $from < $item->{duration} - 15 ) {
			my $position = Slim::Utils::DateTime::timeFormat($from);
			$position =~ s/^0+[:\.]//;		

			$entry->{type} = 'link',
			
			$entry->{items} = [ {
				title => cstring($client, 'PLUGIN_PODCAST_PLAY_FROM_POSITION_X', $position),
				cover => $item->{cover},									
				enclosure => {
					type  => 'audio',
					url   => wrapUrl($item->{url}, $from),
				},	
			},{
				title => cstring($client, 'PLUGIN_PODCAST_PLAY_FROM_BEGINNING'),
				cover => $item->{cover},				
				enclosure => {
					type  => 'audio',
					url   => wrapUrl($item->{url}),
				},	
			}],
		}	
		
		unshift @menu, $entry;
	}

	$cb->({ items => \@menu });
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