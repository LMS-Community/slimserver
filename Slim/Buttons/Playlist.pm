package Slim::Buttons::Playlist;

# $Id$

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

=head1 NAME

Slim::Buttons::Playlist

=head1 SYNOPSIS

Slim::Buttons::Playlist::jump($client,$index);

=head1 DESCRIPTION

L<Slim::Buttons::Playlist> contains functions for browsing the current playlist, and displaying the information 
on a player display.

=cut

use strict;
use Slim::Buttons::Common;
use Slim::Control::Request;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;

my $prefs = preferences('server');

my $log         = logger('player.ui');
my $playlistlog = logger('player.playlist');

our %functions = ();
my %playlistParams = ();

=head1 METHODS

=head2 init( )

This method registers the playlist mode with Logitech Media Server, and defines any functions for interaction
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
		'playdisp' => \&playdisp,

		'knob' => sub {
				my ($client, $funct, $functarg) = @_;

				my $oldindex = browseplaylistindex($client);
				my $songcount = Slim::Player::Playlist::count($client);

				my ($newindex, $dir, $pushDir, $wrap) = $client->knobListPos($oldindex, $songcount || 1);

				if ($oldindex != $newindex && $songcount > 1) {
					browseplaylistindex($client,$newindex);
					playlistNowPlaying($client, 0);
				}

				if ( main::DEBUGLOG && $log->is_debug ) {
					$log->debug(
						"funct: [$funct] old: $oldindex new: $newindex is after setting: [%s]",
						browseplaylistindex($client)
					);
				}

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

				$inc = ($inc =~ /\D/) ? -1 : -$inc;

				my $newposition = Slim::Buttons::Common::scroll($client, $inc, $songcount, browseplaylistindex($client));

				if ($newposition != browseplaylistindex($client)) {

					browseplaylistindex($client, $newposition);
					playlistNowPlaying($client, 0);

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
					playlistNowPlaying($client, 0);

					$client->pushDown();
					$client->updateKnob();
				}
			}
		},

		'left' => sub  {
			my $client = shift;

			Slim::Buttons::Common::popModeRight($client);
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
			playlistNowPlaying($client, 0);

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
				$client->showBriefly( {
					'line' => [ $client->string('REMOVING_FROM_PLAYLIST'), $songtitle ]
				}, {
					'firstline' => 1
				});
			}
		},
		
		'play' => sub  {
			my $client = shift;

			if (showingNowPlaying($client)) {

				if (Slim::Player::Source::playmode($client) eq 'pause') {

					$client->execute(["pause"]);

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

=head2 playdisp ( $client, $button, $buttonarg )

Handler for the now playing display mode so it can be accessed from S:B:Screensaver as well as here

=cut

sub playdisp {
	my $client = shift;
	my $button = shift;
	my $buttonarg = shift;
	my $pdm = $prefs->client($client)->get('playingDisplayModes')->[ $prefs->client($client)->get('playingDisplayMode') ];
	my $index = -1;
	
	#find index of the existing display mode in the pref array
	for (@{ $prefs->client($client)->get('playingDisplayModes') }) {
		$index++;
		last if $pdm == $_;
	}
	
	$pdm = $index unless $index == -1;
	
	unless (defined $pdm) { $pdm = 1; };
	unless (defined $buttonarg) { $buttonarg = 'toggle'; };
	
	if ($button eq 'playdisp_toggle') {
		
		my $playlistlen = Slim::Player::Playlist::count($client);
		
		if (($playlistlen > 0) && (showingNowPlaying($client))) {
			
			$pdm = ($pdm + 1) % (scalar @{ $prefs->client($client)->get('playingDisplayModes') });
			
		} elsif ($playlistlen > 0) {
			
			browseplaylistindex($client, Slim::Player::Source::playingSongIndex($client));
		}
		
	} else {
		if ($buttonarg && $buttonarg < scalar @{ $prefs->client($client)->get('playingDisplayModes') }) {
			$pdm = $buttonarg;
		}
	}
	
	#find mode number at the new index, and save to the prefs
	$prefs->client($client)->set('playingDisplayMode', $pdm);
	$client->update();
}

=head2 forgetClient ( $client )

Clean up global hash when a client is gone

=cut

sub forgetClient {
	my $client = shift;
	
	delete $playlistParams{ $client };
}

sub getFunctions {
	return \%functions;
}

=head2 setMode( $client, [ $how ])

setMode() is a required function for any Logitech Media Server player mode.  This is the entry point for a mode and defines any parameters required for 
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
	playlistNowPlaying($client);
	

	# update client every second in this mode
	$client->modeParam('modeUpdateInterval', 1); # seconds
	$client->modeParam('screen2', 'playlist');   # this mode can use screen2
}

=head2 exitMode( $client, [ $how ])

Requires: $client

The optional argument $how is a string indicating the method of arrival to this mode: either 'push' or 'pop'.

If we are pushing out of the playlist mode, stash a reference to the modeParams so that browseplaylistindex
and playlistNowPlaying can reference them.  Delete the reference when playlist mode is removed from the mode
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
	
	if (playlistNowPlaying($client)) {
		if (!defined($pos)) { 
			$pos = Slim::Player::Source::playingSongIndex($client);
		}
	
		main::INFOLOG && $playlistlog->info("Jumping to song index: $pos");
	
		browseplaylistindex($client,$pos);
	}
}

sub newTitle {
	my $url = shift;
	
	my @clients = Slim::Player::Client::clients();

	for my $client ( @clients ) {
		next unless $client && $client->controller();
		if ( (Slim::Player::Playlist::url($client) || '') eq $url ) {
			jump($client);
			$client->currentPlaylistChangeTime( Time::HiRes::time() );
		}
	}
}

#
# Display the playlist browser
#		
sub lines {
	my $client = shift;
	my $args   = shift;

	my $parts;

	my $nowPlaying = showingNowPlaying($client);

	if ($nowPlaying || (Slim::Player::Playlist::count($client) < 1)) {

		$parts = $client->currentSongLines($args);

	} elsif ($args->{'periodic'} && $client->animateState) {

		return undef;

	} else {

		if ( browseplaylistindex($client) + 1 > Slim::Player::Playlist::count($client)) {
			browseplaylistindex($client,Slim::Player::Playlist::count($client)-1)
		}

		my $line1 = $client->string('CURRENT_PLAYLIST');
		my $overlay1;

		if ($args->{'trans'} || $prefs->client($client)->get('alwaysShowCount')) {
			$overlay1 = ' ' . (browseplaylistindex($client) + 1) . ' ' . $client->string('OUT_OF') . ' ' . 
				Slim::Player::Playlist::count($client);
		}

		my $song = Slim::Player::Playlist::song($client, browseplaylistindex($client) );
		
		my $title;
		my $meta;
		
		# Get remote metadata for other tracks in the playlist if available
		if ( $song->isRemoteURL ) {
			my $handler = Slim::Player::ProtocolHandlers->handlerForURL($song->url);

			if ( $handler && $handler->can('getMetadataFor') ) {
				$meta = $handler->getMetadataFor( $client, $song->url );
				
				if ( $meta->{title} ) {
					$title = Slim::Music::Info::getCurrentTitle( $client, $song->url, 0, $meta );
				}
			}
		}
		
		if ( !$title ) {
			$title = Slim::Music::Info::standardTitle($client, $song);
		}
		
		$parts = {
			'line'    => [ $line1, $title ],
			'overlay' => [ $overlay1, $client->symbols('notesymbol') ],
		};

		if ($client->display->showExtendedText()) {
			
			if ($song && !($song->isRemoteURL)) {

				$parts->{'screen2'} = {
					'line' => [ 
					   Slim::Music::Info::displayText($client, $song, 'ALBUM'),
					   Slim::Music::Info::displayText($client, $song, 'ARTIST'),
					]
				};

			} elsif ($song && $meta) {

				$parts->{'screen2'} = {
					'line' => [ 
					   Slim::Music::Info::displayText($client, $song, 'ALBUM', $meta),
					   Slim::Music::Info::displayText($client, $song, 'ARTIST', $meta),
					]
				};

			} else {

				$parts->{'screen2'} = {};

			}

		}

	}

	return $parts;
}

=head2 showingNowPlaying( $client )

Check if the information currently displayed on a player is the currently playing song.

=cut

sub showingNowPlaying {
	my $client = shift;

	my $mode = Slim::Buttons::Common::mode($client);

	return (
		defined $mode &&
		( $mode eq 'screensaver' || 
		 ($mode eq 'playlist' && ((browseplaylistindex($client) || 0) == Slim::Player::Source::playingSongIndex($client)) ) )
	);
}


=head2 playlistNowPlaying( $client, [ $wasshowing ] )

Internal function used by jump and other functions which manipulate the currently playing song in this mode.  Returns whether player is currently showing now playing or was showing it previously.

This function will update the showingnowplaying param to match the current state. If the optional $wasshowing parameter is supplied, it overrides the previous value of the nowplaying param. This prevents being locked onto the currently playing song if a deliberate move is done.

=cut

sub playlistNowPlaying {
	my $client = shift;
	my $wasshowing;

	my $nowshowing = showingNowPlaying($client);

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

Get and optionally set the currently viewed position in the current playlist.  The index is zero-based and should only be set
when in playlist mode. Callers outside this module may want to get the current index if they operate on any tracks in the current playlist.

The optional argument, $playlistindex sets the zero-based position for browsing the current playlist.

=cut

sub browseplaylistindex {
	my $client = shift;

	if ( main::DEBUGLOG && @_ && $playlistlog->is_debug ) {
		$log->debug("New playlistindex: $_[0]");
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

=head1 SEE ALSO

L<Slim::Buttons::Common>

=cut

1;

__END__
