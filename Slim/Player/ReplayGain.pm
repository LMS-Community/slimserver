package Slim::Player::ReplayGain;

# $Id$

# SlimServer Copyright (C) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use Scalar::Util qw(blessed);

use Slim::Music::Info;
use Slim::Player::Playlist;
use Slim::Player::Source;
use Slim::Utils::Log;
use Slim::Utils::Prefs;

sub fetchGainMode {
	my $class  = shift;
	my $client = shift;
	my $rgmode = $client->prefGet('replayGainMode');

	# Mode 0 is ignore replay gain
	return undef if !$rgmode;

	my $url = Slim::Player::Playlist::song($client, Slim::Player::Source::streamingSongIndex($client));

	if (!$url) {

		logError("Invalid URL for client song!: [$url]");
		return 0;
	}

	my $track = Slim::Schema->rs('Track')->objectForUrl({
		'url'      => $url,
		'create'   => 1,
		'readTags' => 1,
	});

	if (!blessed($track) || !$track->can('replay_gain')) {

		return 0;
	}

	# Mode 1 is use track gain
	if ($rgmode == 1) {
		return $track->replay_gain();
	}

	my $album = $track->album();

	if (!blessed($album) || !$album->can('replay_gain')) {

		return 0;
	}

	# Mode 2 is use album gain
	if ($rgmode == 2) {
		return $album->replay_gain();
	}

	# Mode 3 is determine dynamically whether to use album or track
	if (defined $album->replay_gain() && ($class->trackAlbumMatch($client, -1) || $class->trackAlbumMatch($client, 1))) {

		return $album->replay_gain();
	}

	return $track->replay_gain();
}

# Based on code from James Sutula's Dynamic Transition Updater plugin,
# this method determines whether tracks at a given offset from each
# other in the playlist are similarly adjacent within the same album.
sub trackAlbumMatch {
	my $class  = shift;
	my $client = shift;
	my $offset = shift;

	my $current_index = Slim::Player::Source::streamingSongIndex($client);
	my $compare_index = Slim::Player::Source::streamingSongIndex($client) + $offset;

	my $count         = Slim::Player::Playlist::count($client);
	my $repeat        = Slim::Player::Playlist::repeat($client);

	# only one song in the playlist, so we match
	if ($count == 1 || $repeat == 1) {
		return 1;
	}

	# Check the case where the track to compare against is
	# at the other end of the playlist.
	if ($compare_index < 0) {
		# No repeat means we don't match around the edges
		return 0 unless $repeat;
		
		return $class->trackAlbumMatch($client, $count - 1);
	}
	elsif ($compare_index >= $count) {
		# No repeat means we don't match around the edges
		return 0 unless $repeat;

		return $class->trackAlbumMatch($client, -$current_index);
	}

	# Get the track objects
	my $current_url   = Slim::Player::Playlist::song($client, $current_index);
	my $current_track = Slim::Schema->rs('Track')->objectForUrl({ 'url' => $current_url, 'create' => 1, 'readTags' => 1 });
	
	my $compare_url   = Slim::Player::Playlist::song($client, $compare_index);
	my $compare_track = Slim::Schema->rs('Track')->objectForUrl({ 'url' => $compare_url, 'create' => 1, 'readTags' => 1 });

	if (!blessed($current_track) || !blessed($compare_track)) {

		logError("Couldn't find object for track: [$current_track] or [$compare_track] !");

		return 0;
	}

	if (!$current_track->can('album') || !$compare_track->can('album')) {

		logError("Couldn't a find valid object for track: [$current_track] or [$compare_track] !");

		return 0;
	}
	
	# Check for album and tracknum matches as expected
	if ($compare_track->album && $current_track->album &&
		$compare_track->album->id && ($compare_track->album->id == $current_track->album->id) && 
		(($current_track->tracknum + $offset) == $compare_track->tracknum)) {

		return 1;
	}

	return 0;
}

1;

__END__
