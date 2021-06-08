package Slim::Web::Pages::Status;


# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;

use File::Spec::Functions qw(:ALL);
use POSIX ();
use Scalar::Util qw(blessed);

use Slim::Player::Playlist;
use Slim::Player::Source;
use Slim::Utils::Strings qw(string);
use Slim::Web::HTTP;
use Slim::Web::Pages;
use Slim::Utils::Prefs;

my $prefs = preferences('server');

sub init {
	
	Slim::Web::Pages->addPageFunction(qr/^status_header\.(?:htm|xml)/,\&status_header);
	Slim::Web::Pages->addPageFunction(qr/^status\.(?:htm|xml)/,\&status);
}

# Send the status page (what we're currently playing, contents of the playlist)
sub status_header {
	my ($client, $params, $callback, $httpClient, $response) = @_;

	$params->{'omit_playlist'} = 1;

	return status(@_);
}

sub status {
	my ($client, $params, $callback, $httpClient, $response) = @_;

	Slim::Web::Pages::Common->addPlayerList($client, $params);

	$params->{'refresh'} = $prefs->get('refreshRate');
	
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
		
		$params->{'player_name'} = $client->name();

		$params->{'shuffle'} = Slim::Player::Playlist::shuffle($client);
	
		$params->{'songtime'} = int(Slim::Player::Source::songTime($client));

		if ($client->controller()->playingSong()) { 
			my $dur = $client->controller()->playingSongDuration();
			if ($dur) { $dur = int($dur); }
			$params->{'durationseconds'} = $dur; 
		}

		$params->{'repeat'} = Slim::Player::Playlist::repeat($client);

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
		
		$params->{'sync'}    = $client->syncedWithNames();
		$params->{'mode'}    = $client->power() ? 'on' : 'off';

		if ($client->isPlayer()) {

			$params->{'sleeptime'} = $client->currentSleepTime();
			$params->{'isplayer'}  = 1;
			$params->{'mute'}      = $prefs->client($client)->get('mute');
			$params->{'volume'}    = int($prefs->client($client)->get('volume') + 0.5);
			$params->{'bass'}      = int($client->bass() + 0.5);
			$params->{'treble'}    = int($client->treble() + 0.5);
			$params->{'pitch'}     = int($client->pitch() + 0.5);

			$params->{'sleep'} = $client->prettySleepTime();
		}
		
		$params->{'fixedVolume'} = !$prefs->client($client)->get('digitalVolumeControl');
		$params->{'player'} = $client->id();
	}
	
	if ($songcount > 0) {
		
		$params->{'currentsong'} = Slim::Player::Source::playingSongIndex($client) + 1;
		$params->{'thissongnum'} = Slim::Player::Source::playingSongIndex($client);
		$params->{'songcount'}   = $songcount;
		Slim::Player::Playlist::track($client)->displayAsHTML($params);
		
		Slim::Web::Pages::Common->addSongInfo($client, $params, 1);

		my ($song, $sourcebitrate, $streambitrate);
		
		if (($song = $client->playingSong())
			&& ($sourcebitrate = $song->bitrate())
			&& ($streambitrate = $song->streambitrate())
			&& $sourcebitrate != $streambitrate)
		{
			$params->{'bitrate'} = sprintf( ' (%s %s%s ABR)', 
				string('CONVERTED_TO'), 
				$streambitrate / 1000,
				string('KBPS')); 
		}

		if (Slim::Utils::Misc::getPlaylistDir()) {
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
