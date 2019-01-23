package Slim::Plugin::RandomPlay::DontStopTheMusic;

# Originally written by Kevin Deane-Freeman (slim-mail (A_t) deane-freeman.com).
# New world order by Dan Sully - <dan | at | slimdevices.com>
# Fairly substantial rewrite by Max Spicer

# This code is derived from code with the following copyright message:
#
# Logitech Media Server Copyright 2005-2019 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use URI::Escape qw(uri_escape_utf8);

use Slim::Plugin::DontStopTheMusic::Plugin;
use Slim::Plugin::RandomPlay::Plugin;
use Slim::Utils::Cache;
use Slim::Utils::Log;
use Slim::Utils::Prefs;

my $cache = Slim::Utils::Cache->new();
my $log = logger('plugin.randomplay');
my $prefs = preferences('plugin.randomplay');

sub init {
	Slim::Plugin::DontStopTheMusic::Plugin->registerHandler('PLUGIN_RANDOM_TITLEMIX_WITH_GENRES', sub {
		mixWithGenres('track', @_);
	});

	Slim::Plugin::DontStopTheMusic::Plugin->registerHandler('PLUGIN_RANDOM_TRACK', sub {
		my ($client, $cb) = @_;
		$client->execute(['randomplaygenreselectall', 0]);
		$cb->($client, ['randomplay://track']);
	});

	Slim::Plugin::DontStopTheMusic::Plugin->registerHandler('PLUGIN_RANDOM_ALBUM_MIX_WITH_GENRES', sub {
		mixWithGenres('album', @_);
	});

	Slim::Plugin::DontStopTheMusic::Plugin->registerHandler('PLUGIN_RANDOM_ALBUM_ITEM', sub {
		my ($client, $cb) = @_;
		$client->execute(['randomplaygenreselectall', 0]);
		$cb->($client, ['randomplay://album']);
	});

	Slim::Plugin::DontStopTheMusic::Plugin->registerHandler('PLUGIN_RANDOM_CONTRIBUTOR_ITEM', sub {
		my ($client, $cb) = @_;
		$client->execute(['randomplaygenreselectall', 0]);
		$cb->($client, ['randomplay://contributor']);
	});

	Slim::Plugin::DontStopTheMusic::Plugin->registerHandler('PLUGIN_RANDOM_YEAR_ITEM', sub {
		my ($client, $cb) = @_;
		$client->execute(['randomplaygenreselectall', 0]);
		$cb->($client, ['randomplay://year']);
	});
}

sub mixWithGenres {
	my ($type, $client, $cb) = @_;

	return unless $client;

	my %genres;
	foreach my $track (@{ Slim::Player::Playlist::playList($client) }) {
		if ( $track->remote ) {
			$genres{$track->genre}++ if $track->genre;
		}
		else {
			foreach ( $track->genres ) {
				$genres{$_->name}++
			}
		}
	}

	my $genres = '';
	if (keys %genres) {
		$genres = '?genres=' . join(',', map {
			uri_escape_utf8($_);
		} keys %genres);
	}

	$cb->($client, ['randomplay://' . $type . $genres]);
}


1;