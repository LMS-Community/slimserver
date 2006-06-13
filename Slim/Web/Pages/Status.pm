package Slim::Web::Pages::Status;

# $Id$

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;

use File::Spec::Functions qw(:ALL);
use POSIX ();
use Scalar::Util qw(blessed);

use Slim::Player::Playlist;
use Slim::Player::Source;
use Slim::Player::TranscodingHelper;
use Slim::Utils::Strings qw(string);
use Slim::Web::HTTP;
use Slim::Web::Pages;

sub init {
	
	Slim::Web::HTTP::addPageFunction(qr/^status_header\.(?:htm|xml)/,\&status_header);
	Slim::Web::HTTP::addPageFunction(qr/^status\.(?:htm|xml)/,\&status);
}

# Send the status page (what we're currently playing, contents of the playlist)
sub status_header {
	my ($client, $params, $callback, $httpClient, $response) = @_;

	$params->{'omit_playlist'} = 1;

	return status(@_);
}

sub status {
	my ($client, $params, $callback, $httpClient, $response) = @_;

	Slim::Web::Pages->addPlayerList($client, $params);

	$params->{'refresh'} = Slim::Utils::Prefs::get('refreshRate');
	
	if (!defined($client)) {

		# fixed faster rate for noclients
		$params->{'refresh'} = 10;
		return Slim::Web::HTTP::filltemplatefile("status_noclients.html", $params);

	} elsif ($client->needsUpgrade()) {

		$params->{'player_needs_upgrade'} = 1;
		$params->{'modestop'} = 'Stop';
		return Slim::Web::HTTP::filltemplatefile("status_needs_upgrade.html", $params);
	}

	my $current_player;
	my $songcount = 0;
	 
	if (defined($client)) {

		$songcount = Slim::Player::Playlist::count($client);
		
		if ($client->defaultName() ne $client->name()) {
			$params->{'player_name'} = $client->name();
		}

		$params->{'shuffle'} = Slim::Player::Playlist::shuffle($client);
		if (Slim::Player::Playlist::shuffle($client) == 1) {
			$params->{'shuffleon'} = "on";
		} elsif (Slim::Player::Playlist::shuffle($client) == 2) {
			$params->{'shufflealbum'} = "album";
		} else {
			$params->{'shuffleoff'} = "off";
		}
	
		$params->{'songtime'} = int(Slim::Player::Source::songTime($client));

		if (Slim::Player::Source::playingSong($client)) { 
			my $dur = Slim::Player::Source::playingSongDuration($client);
			if ($dur) { $dur = int($dur); }
			$params->{'durationseconds'} = $dur; 
		}

		#
		$params->{'repeat'} = Slim::Player::Playlist::repeat($client);
		if (!Slim::Player::Playlist::repeat($client)) {
			$params->{'repeatoff'} = "off";
		} elsif (Slim::Player::Playlist::repeat($client) == 1) {
			$params->{'repeatone'} = "one";
		} else {
			$params->{'repeatall'} = "all";
		}

		#
		if (Slim::Player::Source::playmode($client) eq 'play') {

			$params->{'modeplay'} = "Play";

			if (defined($params->{'durationseconds'}) && defined($params->{'songtime'})) {

				my $remaining = $params->{'durationseconds'} - $params->{'songtime'};

				if ($remaining < $params->{'refresh'}) {	
					$params->{'refresh'} = ($remaining < 5) ? 5 : $remaining;
				}
			}

		} elsif (Slim::Player::Source::playmode($client) eq 'pause') {

			$params->{'modepause'} = "Pause";
		
		} else {
			$params->{'modestop'} = "Stop";
		}

		#
		if (Slim::Player::Source::rate($client) > 1) {
			$params->{'rate'} = 'ffwd';
		} elsif (Slim::Player::Source::rate($client) < 0) {
			$params->{'rate'} = 'rew';
		} else {
			$params->{'rate'} = 'norm';
		}
		
		$params->{'rateval'} = Slim::Player::Source::rate($client);
		$params->{'sync'}    = Slim::Player::Sync::syncwith($client);
		$params->{'mode'}    = $client->power() ? 'on' : 'off';

		if ($client->isPlayer()) {

			$params->{'sleeptime'} = $client->currentSleepTime();
			$params->{'isplayer'}  = 1;
			$params->{'mute'}      = $client->prefGet('mute');
			$params->{'volume'}    = int($client->prefGet("volume") + 0.5);
			$params->{'bass'}      = int($client->bass() + 0.5);
			$params->{'treble'}    = int($client->treble() + 0.5);
			$params->{'pitch'}     = int($client->pitch() + 0.5);

			my $sleep = $client->sleepTime() - Time::HiRes::time();
			$params->{'sleep'} = $sleep < 0 ? 0 : int($sleep/60);
		}
		
		$params->{'fixedVolume'} = !$client->prefGet('digitalVolumeControl');
		$params->{'player'} = $client->id();
	}
	
	if ($songcount > 0) {
		my $song = Slim::Player::Playlist::song($client);
		
		$params->{'currentsong'} = Slim::Player::Source::playingSongIndex($client) + 1;
		$params->{'thissongnum'} = Slim::Player::Source::playingSongIndex($client);
		$params->{'songcount'}   = $songcount;
		$params->{'itempath'}    = $song;
		
		Slim::Web::Pages->addSongInfo($client, $params, 1);

		# for current song, display the playback bitrate instead.
		my $undermax = Slim::Player::TranscodingHelper::underMax($client,Slim::Player::Playlist::song($client));

		if (defined $undermax && !$undermax) {
			$params->{'bitrate'} = string('CONVERTED_TO')." ".Slim::Utils::Prefs::maxRate($client).string('KBPS').' ABR';
		}

		if (Slim::Utils::Prefs::get("playlistdir")) {
			$params->{'cansave'} = 1;
		}
	}
	
	if (!$params->{'omit_playlist'}) {

		$params->{'callback'} = $callback;

		$params->{'playlist'} = Slim::Web::Pages::Playlist::playlist($client, $params, \&status_done, $httpClient, $response);

		if (!$params->{'playlist'}) {
			# playlist went into background, stash $callback and exit
			return undef;
		} else {
			$params->{'playlist'} = ${$params->{'playlist'}};
		}

	} else {
		# Special case, we need the playlist info even if we don't want
		# the playlist itself
		if ($client && blessed($client->currentPlaylist) && !Slim::Music::Info::isRemoteURL($client->currentPlaylist)) {

			$params->{'current_playlist'} = $client->currentPlaylist;
			$params->{'current_playlist_modified'} = $client->currentPlaylistModified;
			$params->{'current_playlist_name'} = Slim::Music::Info::standardTitle($client, $client->currentPlaylist);
		}
	}

	return Slim::Web::HTTP::filltemplatefile($params->{'omit_playlist'} ? "status_header.html" : "status.html" , $params);
}

sub status_done {
	my ($client, $params, $bodyref, $httpClient, $response) = @_;

	$params->{'playlist'} = $$bodyref;

	my $output = Slim::Web::HTTP::filltemplatefile("status.html" , $params);

	$params->{'callback'}->($client, $params, $output, $httpClient, $response);
}

1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
