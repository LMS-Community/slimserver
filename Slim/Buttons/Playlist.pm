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
use Slim::Control::Request;
use Slim::Utils::Misc;

our %functions = ();
my %playlistParams = ();

=head1 METHODS

=head2 init( )

This method registers the playlist mode with Slimserver, and defines any functions for interaction
 while a player is operating in this mode..

Generally only called from L<Slim::Buttons::Common>

=cut

sub init {
	Slim::Buttons::Common::addMode('playlist', getFunctions(), \&setMode, \&exitMode);
	
	Slim::Music::Info::setCurrentTitleChangeCallback(\&Slim::Buttons::Playlist::newTitle);
	
	# Bug 4065, Watch for changes to the playlist that require a knob update
	Slim::Control::Request::subscribe( \&knobPlaylistCallback, [['playlist']] );

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

				my $oldindex = browseplaylistindex($client);
				my $songcount = Slim::Player::Playlist::count($client);

				my ($newindex, $dir, $pushDir, $wrap) = $client->knobListPos($oldindex, $songcount || 1);

				if ($oldindex != $newindex && $songcount > 1) {
					browseplaylistindex($client,$newindex);
					showingNowPlaying($client, 0);
				}

				$::d_ui && msgf("funct: [$funct] old: $oldindex new: $newindex is after setting: [%s]\n", browseplaylistindex($client));

				if ($songcount < 2) {
					
					if ($pushDir) {

						$pushDir eq 'up' ? $client->bumpUp : $client->bumpDown;

					}

				} else {

					$pushDir eq 'up' ? $client->pushUp : $client->pushDown;

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

				$client->modeParam('showingnowplaying',0);
				$inc = ($inc =~ /\D/) ? -1 : -$inc;

				my $newposition = Slim::Buttons::Common::scroll($client, $inc, $songcount, browseplaylistindex($client));

				if ($newposition != browseplaylistindex($client)) {

					browseplaylistindex($client, $newposition);
					showingNowPlaying($client, 0);

					$client->pushUp();
					$client->updateKnob();
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

				if ($inc =~ /\D/) {
					$inc = 1;
				}

				my $newposition = Slim::Buttons::Common::scroll($client, $inc, $songcount, browseplaylistindex($client));

				if ($newposition != browseplaylistindex($client)) {

					browseplaylistindex($client,$newposition);
					showingNowPlaying($client, 0);

					$client->pushDown();
					$client->updateKnob();
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

			# set browse location to the new index, proportional based on the number pressed
			browseplaylistindex($client,$newposition);
			
			# reset showingnowplaying status
			showingNowPlaying($client, 0);

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
	showingNowPlaying($client);
	

	# update client every second in this mode
	$client->modeParam('modeUpdateInterval', 1); # seconds
	$client->modeParam('screen2', 'playlist');   # this mode can use screen2
}

=head2 exitMode( $client, [ $how ])

Requires: $client

The optional argument $how is a string indicating the method of arrival to this mode: either 'push' or 'pop'.

If we are pushing out of the playlist mode, stash a reference to the modeParams so that browseplaylistindex
and showingNowPlaying can reference them.  Delete the reference when playlist mode is removed from the mode
stack.

=cut

sub exitMode {
	my $client = shift;
	my $how    = shift;

	if ($how eq 'push') {
		$playlistParams{$client} = $client->modeParams();
	} else {
		delete $playlistParams{$client};
	}
}

=head2 jump( $client, [ $pos ])

Allows an arbitrary jump to any track in the current playist. 

The optional argument, $pos set the zero-based index target for the jump.  If not specified, jump will go to current track.

=cut

sub jump {
	my $client = shift;
	my $pos = shift;
	
	if (showingNowPlaying($client)) {
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
		
		my ($s2line1, $s2line2);

		my $song = Slim::Player::Playlist::song($client, $nowPlaying ? undef : browseplaylistindex($client) );

		if ($song && $song->isRemoteURL) {

			my $currentTitle = Slim::Music::Info::getCurrentTitle($client, $song->url);
			my $title = Slim::Music::Info::displayText($client, $song, 'TITLE');

			if ( ($currentTitle || '') ne ($title || '') && !Slim::Music::Info::isURL($title) ) {
				$s2line2 = $title;
			}

		} else {

			$s2line1 = Slim::Music::Info::displayText($client, $song, 'ALBUM');
			$s2line2 = Slim::Music::Info::displayText($client, $song, 'ARTIST');

		}

		$parts->{'screen2'} ||= {
			'line' => [ $s2line1, $s2line2 ],
		};

	}

	return $parts;
}

=head2 showingNowPlaying( $client, [$wasshowing] )

Check if the information currently displayed on a player is the currently playing song. Showing the "current track" 
of the current playlist is a special case.  This function can be used to determine whether or not to display the additional
information that might be shown for the current track.

This function will update the showingnowplaying param to match the current state.

If the optional $wasshowing parameter is supplied, it overrides the previous value of the showingnowplaying param.
This prevents being locked onto the currently playing song if a deliberate move is done.

=cut


sub showingNowPlaying {
	my $client = shift;
	my $wasshowing;

	# special case of playlist mode, to indicate when server needs to
	# display the now playing details.  This includes playlist mode and
	# now playing (jump back on wake) screensaver.
	my $nowshowing = ( defined Slim::Buttons::Common::mode($client) && (
			(Slim::Buttons::Common::mode($client) eq 'screensaver') || 
			((Slim::Buttons::Common::mode($client) eq 'playlist') && 
				((browseplaylistindex($client)|| 0) == Slim::Player::Source::playingSongIndex($client)))
		)
	);

	if (defined Slim::Buttons::Common::mode($client) && Slim::Buttons::Common::mode($client) eq 'playlist') {

		$wasshowing = @_ ? shift : $client->modeParam('showingnowplaying');

		if ($wasshowing && !$nowshowing) {
			# make sure listIndex stays at the correct track
			browseplaylistindex($client, Slim::Player::Source::playingSongIndex($client));
		}

		return $client->modeParam('showingnowplaying',$nowshowing || $wasshowing);
	} elsif (defined $playlistParams{$client}) {

		$wasshowing = @_ ? shift : $playlistParams{$client}->{'showingnowplaying'};
		
		if ($nowshowing && !$wasshowing) {
			# make sure listIndex stays at the correct track
			browseplaylistindex($client, Slim::Player::Source::playingSongIndex($client));
		}

		return $playlistParams{$client}->{'showingnowplaying'} = ($nowshowing || $wasshowing);
	} else {
		# if no playlist mode is on the stack, then always claim to be showing now playing
		return 1;
	}
}


=head2 browseplaylistindex( $client, [ $playlistindex ])

Get and optionally set the currently viewed position in the curren playlist.  The index is zero-based and should only be set
when in playlist mode. Callers outside this module may want to get the current index if they operate on any tracks in the current playlist.

The optional argument, $playlistindex sets the zero-based position for browsing the current playlist.

=cut

sub browseplaylistindex {
	my $client = shift;

	if ( $::d_playlist && @_ && defined($_[0])) {
		msg("new playlistindex: $_[0]\n");
	}
	
	# update list length for the knob.  ### HACK ATTACK ###
	# - only do when we are in mode playlist - see bug: 3561
	# - use length of 1 for both 1 item lists and empty playlists
	if (defined Slim::Buttons::Common::mode($client) && Slim::Buttons::Common::mode($client) eq 'playlist') {

		$client->modeParam('listLen', Slim::Player::Playlist::count($client) || 1);
		if (@_ || defined($client->modeParam('listIndex'))) {
			unshift @_, 'listIndex';
			# get (and optionally set) the browseplaylistindex parameter that's kept in param stack
			return $client->modeParam(@_);
		} else {
			return $client->modeParam('listIndex',Slim::Player::Source::playingSongIndex($client));
		}
	} elsif (defined $playlistParams{$client}) {
		return @_ ? $playlistParams{$client}->{'listIndex'} = shift : $playlistParams{$client}->{'listIndex'};
	} else {
		return Slim::Player::Source::playingSongIndex($client);
	}
	
}

=head2 knobPlaylistCallback( $request )

Watches for any playlist changes that require the knob's state to be updated

=cut

sub knobPlaylistCallback {
	my $request = shift;
	my $client  = $request->client();
	
	if (defined $client && defined Slim::Buttons::Common::mode($client) && Slim::Buttons::Common::mode($client) eq 'playlist') {
		browseplaylistindex($client);
		$client->updateKnob(1);
	}
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
