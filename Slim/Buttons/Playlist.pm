package Slim::Buttons::Playlist;

# $Id: Playlist.pm,v 1.26 2004/01/24 18:50:24 dean Exp $

# Slim Server Copyright (c) 2001, 2002, 2003 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use File::Spec::Functions qw(:ALL);
use File::Spec::Functions qw(updir);
use Slim::Buttons::Common;
use Slim::Buttons::Browse;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);

Slim::Buttons::Common::addMode('playlist',getFunctions(),\&setMode);

# Each button on the remote has a function:

my $displayColumns = 40;

my %functions = (
	'playdisp' => sub {
		# toggle display mod for now playing...
		my $client = shift;
		my $button = shift;
		my $buttonarg = shift;
		my $pdm = Slim::Utils::Prefs::clientGet($client, "playingDisplayMode");
		unless (defined $pdm) { $pdm = 1; };
		unless (defined $buttonarg) { $buttonarg = 'toggle'; };
		if ($button eq 'playdisp_toggle') {
			my $playlistlen = Slim::Player::Playlist::count($client);
			# playingDisplayModes are
			# 0 show nothing
			# 1 show elapsed time
			# 2 show remaining time
			# 3 show progress bar
			# 4 show elapsed time and progress bar
			# 5 show remaining time and progress bar
			if (($playlistlen > 0) && (showingNowPlaying($client))) {
				$pdm = ($pdm + 1) % 6;
			} elsif ($playlistlen > 0) {
				browseplaylistindex($client,Slim::Player::Source::currentSongIndex($client));
			}
		} else {
			if ($buttonarg =~ /[0-5]$/) {
				$pdm = $buttonarg;
			}
		}
		Slim::Buttons::Common::param($client,'animateTop',$pdm);
		Slim::Utils::Prefs::clientSet($client, "playingDisplayMode", $pdm);
		$client->update();
	},
	'up' => sub  {
		my $client = shift;
		my $button = shift;
		my $inc = shift || 1;
		my($songcount) = Slim::Player::Playlist::count($client);
		if ($songcount < 2) {
			Slim::Display::Animation::bumpUp($client);
		} else {
			$inc = ($inc =~ /\D/) ? -1 : -$inc;
			my $newposition = Slim::Buttons::Common::scroll($client, $inc, $songcount, browseplaylistindex($client));
			browseplaylistindex($client, $newposition);
			$client->update();
		}
	},
	'down' => sub  {
		my $client = shift;
		my $button = shift;
		my $inc = shift || 1;
		my($songcount) = Slim::Player::Playlist::count($client);
		if ($songcount < 2) {
			Slim::Display::Animation::bumpDown($client);
		} else {
			if ($inc =~ /\D/) {$inc = 1}
			my $newposition = Slim::Buttons::Common::scroll($client, $inc, $songcount, browseplaylistindex($client));
			browseplaylistindex($client,$newposition);
			$client->update();
		}
	},
	'left' => sub  {
		my $client = shift;
		my @oldlines = Slim::Display::Display::curLines($client);
		Slim::Buttons::Home::jump($client, 'NOW_PLAYING');
		Slim::Buttons::Common::setMode($client, 'home');
		Slim::Display::Animation::pushRight($client, @oldlines, Slim::Display::Display::curLines($client));
	},
	'right' => sub  {
		my $client = shift;
		my $playlistlen = Slim::Player::Playlist::count($client);
		if ($playlistlen < 1) {
			Slim::Display::Animation::bumpRight($client);
		} else {
			my @oldlines = Slim::Display::Display::curLines($client);
			Slim::Buttons::Common::pushMode($client, 'trackinfo', {'track' => Slim::Player::Playlist::song($client, browseplaylistindex($client)) } );
			Slim::Display::Animation::pushLeft($client, @oldlines, Slim::Display::Display::curLines($client));
		}
	},
	'numberScroll' => sub  {
		my $client = shift;
		my $button = shift;
		my $digit = shift;
		my $newposition;
		# do an unsorted jump
		$newposition = Slim::Buttons::Common::numberScroll($client, $digit, Slim::Player::Playlist::shuffleList($client), 0);
		browseplaylistindex($client,$newposition);
		$client->update();	
	},
	'add' => sub  {
		my $client = shift;
		if (Slim::Player::Playlist::count($client) > 0) {
			# rec button deletes an entry if you are browsing the playlist...
			Slim::Display::Animation::showBriefly($client, 
					string('REMOVING_FROM_PLAYLIST'), 
					Slim::Music::Info::standardTitle($client, Slim::Player::Playlist::song($client, browseplaylistindex($client))), undef, 1);
		
			Slim::Control::Command::execute($client, ["playlist", "delete", browseplaylistindex($client)]);	
		}
	},
	
 	'zap' => sub {
 		my $client = shift;
 		my $zapped=catfile(Slim::Utils::Prefs::get('playlistdir'), string('ZAPPED_SONGS') . '.m3u');
		my $currsong = Slim::Player::Playlist::song($client);
		my $currindex = Slim::Player::Source::currentSongIndex($client);
		if (Slim::Player::Playlist::count($client) > 0) {
			Slim::Display::Animation::showBriefly($client,
					string('ZAPPING_FROM_PLAYLIST'),
					Slim::Music::Info::standardTitle($client, $currsong), undef, 1);
			Slim::Control::Command::execute($client, ["playlist", "zap", $currindex]);
		}
	},

	'play' => sub  {
		my $client = shift;
		if (showingNowPlaying($client)) {
			if (Slim::Player::Source::playmode($client) eq 'pause') {
				Slim::Control::Command::execute($client, ["pause"]);
			} elsif (Slim::Player::Source::rate($client) != 1) {
				Slim::Control::Command::execute($client, ["rate", 1]);
			} else {
				Slim::Control::Command::execute($client, ["playlist", "jump", browseplaylistindex($client)]);
			}	
		} else {
			Slim::Control::Command::execute($client, ["playlist", "jump", browseplaylistindex($client)]);
		}
		$client->update();
	}
);

sub getFunctions {
	return \%functions;
}

sub setMode {
	my $client = shift;
	my $how = shift;
	$client->lines(\&lines);
	if ($how ne 'pop') { jump($client); }
}

sub jump {
	my $client = shift;
	my $pos = shift;
	if (Slim::Buttons::Common::mode($client) eq 'playlist') {
		if (!defined($pos)) { 
			$pos = Slim::Player::Source::currentSongIndex($client);
		}
		browseplaylistindex($client,$pos);
	}
}

#
# Display the playlist browser
#		
sub lines {
	my $client = shift;
	my ($line1, $line2, $overlay2);
	
	if (showingNowPlaying($client) || (Slim::Player::Playlist::count($client) < 1)) {
		return currentSongLines($client);
	} else {
		$line1 = sprintf "%s (%d %s %d) ", string('PLAYLIST'), browseplaylistindex($client) + 1, string('OUT_OF'), Slim::Player::Playlist::count($client);
		$line2 = Slim::Music::Info::standardTitle($client, Slim::Player::Playlist::song($client, browseplaylistindex($client)));
		$overlay2 = Slim::Hardware::VFD::symbol('notesymbol');
		return ($line1, $line2, undef, $overlay2);
	}
}

# this is somewhat confusing.
sub showingNowPlaying {
	my $client = shift;
	return (
		(Slim::Buttons::Common::mode($client) eq 'screensaver') || 
		(Slim::Buttons::Common::mode($client) eq 'playlist') && 
			(browseplaylistindex($client) == Slim::Player::Source::currentSongIndex($client))
	);
}

sub currentSongLines {
	my $client = shift;
	my ($line1, $line2, $overlay2);

	my $overlay1 = "";

	my $playlistlen = Slim::Player::Playlist::count($client);

	if ($playlistlen < 1) {

		$line1 = string('NOW_PLAYING');
		$line2 = string('NOTHING');

	} else {

		if (Slim::Player::Source::playmode($client) eq "pause") {

			$line1 = sprintf(
				string('PAUSED')." (%d %s %d) ",
				Slim::Player::Source::currentSongIndex($client) + 1, string('OUT_OF'), $playlistlen
			);

		# for taking photos of the display, comment out the line above, and use this one instead.
		# this will cause the display to show the "Now playing" screen to show when paused.
		# $line1 = "Now playing" . sprintf " (%d %s %d) ", Slim::Player::Source::currentSongIndex($client) + 1, string('OUT_OF'), $playlistlen;

		} elsif (Slim::Player::Source::playmode($client) eq "stop") {

			$line1 = sprintf(
				string('STOPPED')." (%d %s %d) ",
				Slim::Player::Source::currentSongIndex($client) + 1, string('OUT_OF'), $playlistlen
			);

		} else {

			if (Slim::Player::Source::rate($client) != 1) {
				$line1 = string('NOW_SCANNING') . ' ' . Slim::Player::Source::rate($client) . 'x';	
			} else {
				$line1 = string('PLAYING');
			}
				
			if (Slim::Utils::Prefs::clientGet($client, "volume") < 0) {
				$line1 .= " ".string('LCMUTED')
			}

			$line1 = $line1 . sprintf(
				" (%d %s %d) ",
				Slim::Player::Source::currentSongIndex($client) + 1, string('OUT_OF'), $playlistlen
			);
		} 

		$line2 = Slim::Music::Info::standardTitle($client, Slim::Player::Playlist::song($client));
		$overlay2 = Slim::Hardware::VFD::symbol('notesymbol');

		($line1,$overlay1) = nowPlayingModeLines($client, $line1, $overlay1);
	}

	return ($line1, $line2, $overlay1, $overlay2);
}

sub nowPlayingModeLines {
	my ($client,$line1,$overlay1) = @_;

	unless (defined $overlay1) {
		$overlay1 = '';
	};

	my $fractioncomplete   = 0;
	my $playingDisplayMode = Slim::Utils::Prefs::clientGet($client, "playingDisplayMode");

	Slim::Buttons::Common::param(
		$client,
		'animateTop',
		(Slim::Player::Source::playmode($client) ne "stop") ? $playingDisplayMode : 0
	);

	unless (defined $playingDisplayMode) {
		$playingDisplayMode = 1;
	};

	# check if we're streaming...
	if (Slim::Music::Info::isHTTPURL(Slim::Player::Playlist::song($client)) &&
	   !Slim::Utils::Prefs::get('showbufferfullness')) {

		# no progress bar, remaining time is meaningless
		$playingDisplayMode = ($playingDisplayMode % 3) ? 1 : 0;

	} else {

		if (Slim::Utils::Prefs::get('showbufferfullness')) {
			$fractioncomplete = $client->usage();
		} else {
			$fractioncomplete = Slim::Player::Source::progress($client);
		}
	}

	my $songtime = songTime($client, $playingDisplayMode);

	my $line1LineLength = Slim::Hardware::VFD::lineLength($line1);
	my $songLineLength  = Slim::Hardware::VFD::lineLength($songtime);
	my $overlay1Length  = Slim::Hardware::VFD::lineLength($overlay1);

	if ($playingDisplayMode == 1 || $playingDisplayMode == 2) {

		# just show the song time
		$line1 .= " " x $displayColumns;
		$line1  = Slim::Hardware::VFD::subString(
			$line1, 0, $displayColumns - $songLineLength - $overlay1Length
		) . $songtime;

	} elsif ($playingDisplayMode == 3) {

		# just show the bar
		my $barlen = $displayColumns - $line1LineLength - $overlay1Length;
		my $bar    = Slim::Display::Display::progressBar($client, $barlen, $fractioncomplete);	

		$line1 .= " " x $displayColumns;
		$line1  = Slim::Hardware::VFD::subString($line1, 0, $displayColumns - $barlen - $overlay1Length) . $bar;

	} elsif ($playingDisplayMode == 4 || $playingDisplayMode == 5) {

		# show both the bar and the time
		my $barlen = $displayColumns - $line1LineLength - $songLineLength - 1 - $overlay1Length;
		my $bar    = Slim::Display::Display::progressBar($client, $barlen, $fractioncomplete);	

		my $barLineLength = Slim::Hardware::VFD::lineLength($bar);

		$line1 .= " " x $displayColumns;
		$line1  = Slim::Hardware::VFD::subString(
			$line1, 0, $displayColumns - $barLineLength - $songLineLength - 1 - $overlay1Length
		) . $bar . " " . $songtime;
	}

	return ($line1,$overlay1);
}

sub songTime {
	my $client = shift;
	my $playingDisplayMode = shift;

	my $delta = 0;
	my $sign  = '';

	if (Slim::Player::Source::playmode($client) eq "stop") {
		$delta = 0;
	} else {	
		$delta = Slim::Player::Source::songTime($client);
	}
	
	# 2 and 5 display remaining time, not elapsed
	if ($playingDisplayMode % 3 == 2) {
		my $duration = $client->songduration() || 0;
		$delta = $duration - $delta;

		$sign = '-';
	}

	my $time = sprintf("%s%02d:%02d", $sign, $delta / 60, $delta % 60);

	return $time;
}

sub browseplaylistindex {
	my $client = shift;
	my $playlistindex = shift;
	
	# get (and optionally set) the browseplaylistindex parameter that's kept in param stack
	return Slim::Buttons::Common::param($client, 'browseplaylistindex', $playlistindex);
}

1;

__END__
