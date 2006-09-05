package Slim::Buttons::Playlist;

# $Id$

# Slim Server Copyright (c) 2001-2006 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

=head1 NAME

Slim::Buttons::Playlist

=head1 SYNOPSIS

Slim::Buttons::Playlist::jump($client,$index);

=head1 DESCRIPTION

L<Slim::Buttons::Playlist> is contains functions for browsing the current playlist, and displaying the information 
on a Slim Devices player display.

=cut

use strict;
use File::Spec::Functions qw(:ALL);
use File::Spec::Functions qw(updir);
use Slim::Buttons::Common;
use Slim::Utils::Misc;

our %functions = ();

=head1 METHODS

=head2 init( )

This method registers the playlist mode with Slimserver, and defines any functions for interaction
 while a player is operating in this mode..

Generally only called from L<Slim::Buttons::Common>

=cut

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

				} elsif ($playlistlen > 0) {

					browseplaylistindex($client, Slim::Player::Source::playingSongIndex($client));
				}

			} else {
				if ($buttonarg && $buttonarg < ($client->prefGetArrayMax('playingDisplayModes') +1)) {
					$pdm = $buttonarg;
				}
			}

			#find mode number at the new index, and save to the prefs
			$client->prefSet("playingDisplayMode", $pdm);
			$client->update();
		},

		'knob' => sub {
				my ($client, $funct, $functarg) = @_;

				my $newindex = $client->knobPos();
				my $oldindex = browseplaylistindex($client);
				my $songcount = Slim::Player::Playlist::count($client);

				# XXXX assume list is long enough for wrapround to only occur when:
				my $wrap = (abs($newindex - $oldindex) > $songcount / 2); 

				if ($oldindex != $newindex && $songcount > 1) {
					browseplaylistindex($client,$newindex);
				}

				$client->param('showingnowplaying', 0);

				$::d_ui && msgf("funct: [$funct] old: $oldindex new: $newindex is after setting: [%s]\n", browseplaylistindex($client));

				if ($songcount < 2) {
					
					if ($newindex < 0) {

						$client->bumpDown;

					} elsif ($newindex > 0) {

						$client->bumpUp;

					}

				} elsif ($oldindex > $newindex && !$wrap || $oldindex < $newindex && $wrap) {

					$client->pushUp;

				} else {

					$client->pushDown;
				}
		},

		'up' => sub  {
			my $client = shift;
			my $button = shift;
			my $inc = shift || 1;

			my ($songcount) = Slim::Player::Playlist::count($client);

			if ($songcount < 2) {

				$client->bumpUp() if ($button !~ /repeat/);

			} else {

				$client->param('showingnowplaying',0);
				$inc = ($inc =~ /\D/) ? -1 : -$inc;

				my $newposition = Slim::Buttons::Common::scroll($client, $inc, $songcount, browseplaylistindex($client));

				if ($newposition != browseplaylistindex($client)) {

					browseplaylistindex($client, $newposition);
					$client->pushUp();
				}
			}
		},

		'down' => sub  {
			my $client = shift;
			my $button = shift;
			my $inc = shift || 1;

			my ($songcount) = Slim::Player::Playlist::count($client);

			if ($songcount < 2) {

				$client->bumpDown() if ($button !~ /repeat/);

			} else {

				$client->param('showingnowplaying',0);

				if ($inc =~ /\D/) {
					$inc = 1;
				}

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

			while (Slim::Buttons::Common::popMode($client, 1)) {};

			Slim::Buttons::Common::pushMode($client, 'home');

			if ($client->display->showExtendedText()) {

				$client->pushRight($oldlines, Slim::Buttons::Common::pushpopScreen2($client, 'playlist') );

			} else {

				$client->pushRight($oldlines, $client->curLines());
			}
		},

		'right' => sub  {
			my $client      = shift;
			my $playlistlen = Slim::Player::Playlist::count($client);

			if ($playlistlen < 1) {

				$client->bumpRight();

			} else {

				Slim::Buttons::Common::pushModeLeft($client, 'trackinfo', {
					'track' => Slim::Player::Playlist::song($client, browseplaylistindex($client)),
					'current' => browseplaylistindex($client) == Slim::Player::Source::playingSongIndex($client)
				});
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

=head2 setMode( $client, [ $how ])

setMode() is a required function for any Slimserver player mode.  This is the entry point for a mode and defines any parameters required for 
a clean starting point. The function may also set up the reference to the applicable lines function for the player display.

Requires: $client

The optional argument $how is a string indicating the method of arrival to this mode: either 'push' or 'pop'.

=cut

sub setMode {
	my $client = shift;
	my $how    = shift;

	$client->lines( $client->customPlaylistLines() || \&lines );

	if ($how ne 'pop') {
		jump($client);
	}

	browseplaylistindex($client);

	# update client every second in this mode
	$client->param('modeUpdateInterval', 1); # seconds
	$client->param('screen2', 'playlist');   # this mode can use screen2
}


=head2 jump( $client, [ $pos ])

Allows an arbitrary jump to any track in the current playist. 

The optional argument, $pos set the zero-based index target for the jump.  If not specified, jump will go to current track.

=cut

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

	my ($parts, $line1, $line2);

	my $nowPlaying = showingNowPlaying($client);

	if ($nowPlaying || (Slim::Player::Playlist::count($client) < 1)) {

		$parts = $client->currentSongLines();

	} else {

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

		$parts = {
			'line'    => [ $line1, $line2 ],
			'overlay' => [ undef, $client->symbols('notesymbol') ],
		};
	}

	if ($client->display->showExtendedText()) {
		my $song = Slim::Player::Playlist::song($client, $nowPlaying ? undef : browseplaylistindex($client) );

		$parts->{'screen2'} ||= {
			'line' => [ 
				Slim::Music::Info::displayText($client, $song, 'ALBUM'),
				Slim::Music::Info::displayText($client, $song, 'ARTIST')
			],
		};

	}

	return $parts;
}

=head2 showingNowPlaying( $client )

Check if the information currently displayed on a player is the currently playing song. Showing the "current track" 
of the current playlist is a special case.  This function can be used to determine whether or not to display the additional
information that might be shown for the current track.

=cut


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


=head2 browseplaylistindex( $client, [ $playlistindex ])

Get and optionally set the currently viewed position in the curren playlist.  The index is zero-based and should only be set
when in playlist mode. Callers outside this module may want to get the current index if they operate on any tracks in the current playlist.

The optional argument, $playlistindex sets the zero-based position for browsing the current playlist.

=cut

sub browseplaylistindex {
	my $client = shift;
	my $playlistindex = shift;

	if ( $::d_playlist && defined($playlistindex) ) {
		bt();
		msg("new playlistindex: $playlistindex\n");
	}
	
	# update list length for the knob.  ### HACK ATTACK ###
	# - only do when we are in mode playlist - see bug: 3561
	# - use length of 1 for both 1 item lists and empty playlists
	if (Slim::Buttons::Common::mode($client) eq 'playlist') {

		$client->param('listLen', Slim::Player::Playlist::count($client) || 1);
	}
	
	# get (and optionally set) the browseplaylistindex parameter that's kept in param stack
	return $client->param('listIndex', $playlistindex);
}

# DEPRECATED: for compatibility only, use $client->nowPlayingModeLines();
sub nowPlayingModeLines {
	shift->nowPlayingModeLines(shift);
}

=head1 SEE ALSO

L<Slim::Buttons::Common>

=cut

1;

__END__
