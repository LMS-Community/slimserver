package Slim::Buttons::Playlist;

# $Id$

# Slim Server Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use File::Spec::Functions qw(:ALL);
use File::Spec::Functions qw(updir);
use Slim::Buttons::Common;
use Slim::Utils::Misc;

our %functions = ();

sub init {
	Slim::Buttons::Common::addMode('playlist', getFunctions(), \&setMode);
	
	Slim::Music::Info::setCurrentTitleChangeCallback(\&Slim::Buttons::Playlist::newTitle);

	# Each button on the remote has a function:
	%functions = (
		'playdisp' => sub {
			# toggle display mod for now playing...
			my $client = shift;
			my $button = shift;
			my $buttonarg = shift;
			my $pdm = $client->prefGet('playingDisplayModes',$client->prefGet("playingDisplayMode"));
			my $index = -1;
			
			#find index of the existing display mode in the pref array
			for ($client->prefGetArray('playingDisplayModes')) {
				$index++;
				last if $pdm == $_;
			}
			$pdm = $index unless $index == -1;
				
			unless (defined $pdm) { $pdm = 1; };
			unless (defined $buttonarg) { $buttonarg = 'toggle'; };
			if ($button eq 'playdisp_toggle') {
				my $playlistlen = Slim::Player::Playlist::count($client);

				if (($playlistlen > 0) && (showingNowPlaying($client))) {
					$pdm = ($pdm + 1) % ($client->prefGetArrayMax('playingDisplayModes') +1);
					print "display mode: $pdm\n";
				} elsif ($playlistlen > 0) {
					browseplaylistindex($client,Slim::Player::Source::playingSongIndex($client));
				}
			} else {
				if ($buttonarg && $buttonarg < ($client->prefGetArrayMax('playingDisplayModes') +1)) {
					$pdm = $buttonarg;
				}
			}
			
			#find mode number at the new index, and save to the prefs
			$client->param('animateTop',${[$client->prefGetArray('playingDisplayModes')]}[$pdm]);
			$client->prefSet("playingDisplayMode", $pdm);
			$client->update();
		},
		'knob' => sub {
				my ($client,$funct,$functarg) = @_;
				
				my $newindex = $client->knobPos();
				my $oldindex = browseplaylistindex($client);
				
				if ($oldindex != $newindex) {
					browseplaylistindex($client,$newindex);
				}
				
				$client->param('showingnowplaying',0);

				msg("old: $oldindex new: $newindex is after setting:" . browseplaylistindex($client) . "\n");

				if ($oldindex > $newindex) {
					$client->pushUp();
				} elsif ($oldindex < $newindex) {
					$client->pushDown();
				}
		},
		'up' => sub  {
			my $client = shift;
			my $button = shift;
			my $inc = shift || 1;
			my($songcount) = Slim::Player::Playlist::count($client);
			if ($songcount < 2) {
				$client->bumpUp() if ($button !~ /repeat/);
			} else {
				$client->param('showingnowplaying',0);
				$inc = ($inc =~ /\D/) ? -1 : -$inc;
				my $newposition = Slim::Buttons::Common::scroll($client, $inc, $songcount, browseplaylistindex($client));
				if ($newposition != browseplaylistindex($client)) {
					browseplaylistindex($client,$newposition);
					$client->pushUp();
				}
			}
		},
		'down' => sub  {
			my $client = shift;
			my $button = shift;
			my $inc = shift || 1;
			my($songcount) = Slim::Player::Playlist::count($client);
			if ($songcount < 2) {
				$client->bumpDown() if ($button !~ /repeat/);
			} else {
				$client->param('showingnowplaying',0);
				if ($inc =~ /\D/) {$inc = 1}
				my $newposition = Slim::Buttons::Common::scroll($client, $inc, $songcount, browseplaylistindex($client));
				if ($newposition != browseplaylistindex($client)) {
					browseplaylistindex($client,$newposition);
					$client->pushDown();
				}
			}
		},
		'left' => sub  {
			my $client = shift;
			my $oldlines = $client->curLines();
			Slim::Buttons::Home::jump($client, 'NOW_PLAYING');
			Slim::Buttons::Common::setMode($client, 'home');
			$client->pushRight($oldlines, $client->curLines());
		},
		'right' => sub  {
			my $client = shift;
			my $playlistlen = Slim::Player::Playlist::count($client);
			if ($playlistlen < 1) {
				$client->bumpRight();
			} else {
				my $oldlines = $client->curLines();

				Slim::Buttons::Common::pushMode($client, 'trackinfo', {
					'track' => Slim::Player::Playlist::song($client, browseplaylistindex($client)),
					'current' => browseplaylistindex($client) == Slim::Player::Source::playingSongIndex($client)
				} );

				$client->pushLeft($oldlines, $client->curLines());
			}
		},
		'numberScroll' => sub  {
			my $client = shift;
			my $button = shift;
			my $digit = shift;
			my $newposition;
			
			# do an unsorted jump
			$newposition = Slim::Buttons::Common::numberScroll($client, $digit, Slim::Player::Playlist::shuffleList($client), 0);
			
			# reset showingnowplaying status, since this command overrides the automatic states
			$client->param('showingnowplaying',0);
			
			# set browse location to the new index, proportional based on the number pressed
			browseplaylistindex($client,$newposition);
			$client->update();	
		},
		'add' => sub  {
			my $client = shift;
			if (Slim::Player::Playlist::count($client) > 0) {
				# rec button deletes an entry if you are browsing the playlist...
				my $songtitle = Slim::Music::Info::standardTitle($client, 
					Slim::Player::Playlist::song($client, browseplaylistindex($client))
				);

				$client->execute(["playlist", "delete", browseplaylistindex($client)]);	
				$client->showBriefly( $client->string('REMOVING_FROM_PLAYLIST'), $songtitle, undef, 1);
			}
		},
		
		'zap' => sub {
			my $client = shift;
			my $zapped = catfile(Slim::Utils::Prefs::get('playlistdir'), $client->string('ZAPPED_SONGS') . '.m3u');

			if (Slim::Player::Playlist::count($client) > 0) {

				$client->showBriefly(
					$client->string('ZAPPING_FROM_PLAYLIST'),
					Slim::Music::Info::standardTitle($client, 
					Slim::Player::Playlist::song($client, browseplaylistindex($client))), undef, 1
				);

				$client->execute(["playlist", "zap", browseplaylistindex($client)]);
			}
		},

		'play' => sub  {
			my $client = shift;
			if (showingNowPlaying($client)) {
				if (Slim::Player::Source::playmode($client) eq 'pause') {
					$client->execute(["pause"]);
				} elsif (Slim::Player::Source::rate($client) != 1) {
					$client->execute(["rate", 1]);
				} else {
					$client->execute(["playlist", "jump", browseplaylistindex($client)]);
				}	
			} else {
				$client->execute(["playlist", "jump", browseplaylistindex($client)]);
			}
			$client->update();
		}
	);
	
}

sub getFunctions {
	return \%functions;
}

sub setMode {
	my $client = shift;
	my $how = shift;
	$client->lines(\&lines);
	if ($how ne 'pop') { jump($client); }

	browseplaylistindex($client);

	# update client every second in this mode
	$client->param('modeUpdateInterval', 1); # seconds
}

sub jump {
	my $client = shift;
	my $pos = shift;
	
	if (showingNowPlaying($client) || ! defined browseplaylistindex($client)) {
		if (!defined($pos)) { 
			$pos = Slim::Player::Source::playingSongIndex($client);
		}
		
		$::d_playlist && msg("Playlist: Jumping to song index: $pos\n");

		browseplaylistindex($client,$pos);
	}
}

sub newTitle {
	my $url = shift;

	for my $client (Slim::Player::Client::clients()) {
		jump($client) if ((Slim::Player::Playlist::url($client) || '') eq $url);
	}
}

#
# Display the playlist browser
#		
sub lines {
	my $client = shift;

	my ($line1, $line2);

	if (showingNowPlaying($client) || (Slim::Player::Playlist::count($client) < 1)) {
		return $client->currentSongLines();
	}

	if ( browseplaylistindex($client) + 1 > Slim::Player::Playlist::count($client)) {
		browseplaylistindex($client,Slim::Player::Playlist::count($client)-1)
	}

	$line1 = sprintf("%s (%d %s %d) ", 
		$client->string('PLAYLIST'),
		browseplaylistindex($client) + 1,
		$client->string('OUT_OF'),
		Slim::Player::Playlist::count($client)
	);

	$line2 = Slim::Music::Info::standardTitle(
		$client,
		Slim::Player::Playlist::song($client, browseplaylistindex($client))
	);

	return {
		'line'    => [ $line1, $line2 ],
		'overlay' => [ undef, $client->symbols('notesymbol') ]
	};
}

sub showingNowPlaying {
	my $client = shift;

	# special case of playlist mode, to indicate when server needs to
	# display the now playing details.  This includes playlist mode and
	# now playing (jump back on wake) screensaver.
	my $nowshowing = ( defined Slim::Buttons::Common::mode($client) && (
			(Slim::Buttons::Common::mode($client) eq 'screensaver') || 
			((Slim::Buttons::Common::mode($client) eq 'playlist') && 
				((browseplaylistindex($client)|| 0) == Slim::Player::Source::playingSongIndex($client)))
		)
	);

	my $wasshowing = $client->param('showingnowplaying');

	return $client->param('showingnowplaying',$nowshowing || $wasshowing);
}

sub browseplaylistindex {
	my $client = shift;
	my $playlistindex = shift;

	if (defined($playlistindex)) {
		bt();
		msg("new playlistindex: $playlistindex\n");
	}
	
	# update list length for the knob.  ### HACK ATTACK ###
	$client->param('listLen', Slim::Player::Playlist::count($client));
	
	# get (and optionally set) the browseplaylistindex parameter that's kept in param stack
	return $client->param('listIndex', $playlistindex);
}

# DEPRECATED: for compatibility only, use $client->nowPlayingModeLines();
sub nowPlayingModeLines {
	shift->nowPlayingModeLines(shift);
}

1;

__END__
