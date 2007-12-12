package Slim::Player::Source;

# $Id$

# SqueezeCenter Copyright (c) 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use bytes;
use strict;
use warnings;

use Fcntl qw(SEEK_CUR);
use File::Spec::Functions qw(:ALL);
use FileHandle;
use FindBin qw($Bin);
use IO::Socket qw(:DEFAULT :crlf);
use MP3::Info;
use MPEG::Audio::Frame;
use Scalar::Util qw(blessed);
use Time::HiRes;

use Slim::Formats;
use Slim::Control::Request;
use Slim::Formats::Playlists;
use Slim::Player::Pipeline;
use Slim::Player::ProtocolHandlers;
use Slim::Player::ReplayGain;
use Slim::Player::TranscodingHelper;
use Slim::Utils::Errno;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Network;
use Slim::Utils::OSDetect;
use Slim::Utils::Prefs;

my $TRICKSEGMENTDURATION = 1.0;
my $FADEVOLUME         = 0.3125;

my $log = logger('player.source');

my $prefs = preferences('server');

use constant STATUS_STREAMING => 0;
use constant STATUS_PLAYING   => 1;

sub systell {
	$_[0]->sysseek(0, SEEK_CUR) if $_[0]->can('sysseek');
}

sub init {
	Slim::Player::TranscodingHelper::loadConversionTables();

	Slim::Networking::Slimproto::setEventCallback('STMu', \&underrun);
	Slim::Networking::Slimproto::setEventCallback('STMd', \&decoderUnderrun);
	Slim::Networking::Slimproto::setEventCallback('STMs', \&trackStartEvent);
	Slim::Networking::Slimproto::setEventCallback('STMn', \&notSupported);
	Slim::Networking::Slimproto::setEventCallback('STMo', \&outputUnderrun);
}

# rate can be negative for rew, zero for pause, 1 for playback and greater than one for ffwd
sub rate {
	my $client  = Slim::Player::Sync::masterOrSelf(shift);
	my $newrate = shift;

	unless (defined $newrate) {
		return $client->rate();
	}

	my $oldrate = $client->rate();

	# restart playback if we've changed and we're not pausing or unpauseing
	if ($oldrate != $newrate) {

		$log->info("Switching rate from $oldrate to $newrate");

		if ($log->is_debug) {

			$log->logBacktrace;
		}

		my $time = songTime($client);

		$client->rate($newrate);

	 	if ($newrate == 0) {
			playmode($client, "pausenow");
			return;
		}

		$log->info("Rate change, jumping to the current position in order to restart the stream");

		gototime($client, $time);
	}
}

sub time2offset {
	my $client   = shift;
	my $time     = shift;
	
	my $song     = playingSong($client);
	my $size     = $song->{'totalbytes'};
	my $duration = $song->{'duration'};
	my $align    = $song->{'blockalign'};

	# Short circuit the computation if the time for which we're asking
	# the offset is the duration of the song - in that case, it's just
	# the length of the song.
	if ($time == $duration) {
		return $size;
	}

	my $byterate = $duration ? ($size / $duration) : 0;
	my $offset   = int($byterate * $time);

	if (my $streamClass = streamClassForFormat($client)) {

		$offset  = $streamClass->findFrameBoundaries($client->audioFilehandle, $offset);

	} else {

		$offset -= $offset % $align;
	}

	$log->info("$time to $offset (align: $align size: $size duration: $duration)");

	return $offset;
}

# fractional progress (0 - 1.0) of playback in the current song.
sub progress {

	my $client = Slim::Player::Sync::masterOrSelf(shift);
	
	if (Slim::Player::Source::playmode($client) eq "stop") {
		return 0;
	}

	my $song         = playingSong($client);
	my $songduration = $song->{duration};

	return 0 unless $songduration;
	return songTime($client) / $songduration;
}

sub songTime {

	my $client = Slim::Player::Sync::masterOrSelf(shift);

	my $rate        = $client->rate();
	my $songtime    = $client->songElapsedSeconds();
	my $song     	= playingSong($client);
	my $startStream = $song->{startOffset} || 0;
	my $duration	= $song->{duration};
	
	if (defined($songtime)) {
		$songtime = $startStream + ($songtime * $rate);
		
		# limit check
		if ($songtime < 0) {
			$songtime = 0;
		} elsif ($duration && $songtime > $duration) {
			$songtime = $duration;
		}
		
		return $songtime;
	}
	
	#######
	# All the remaining code is to deal with players which do not report songElapsedSeconds,
	# specifically SliMP3s and SB1s; maybe also web clients?

	# This assumes that remote streaming is real-time - not always true but for the common
	# cases when it is, this will be better than bitrate-based calculations, and we may not
	# actually know the correct bitrate.
	if ($client->audioFilehandleIsSocket() == 1) {

		my $startTime = $client->remoteStreamStartTime();
		my $endTime   = $client->pauseTime() || Time::HiRes::time();
		
		return ($startTime ? $endTime - $startTime : 0);
	}

	if (playingSongIndex($client) == streamingSongIndex($client)) {
		my $byterate	  	= ($song->{bitrate} || 0)/8 || ($duration ? ($song->{totalbytes} / $duration) : 0);
		my $bytesReceived 	= ($client->bytesReceived() || 0) - $client->bytesReceivedOffset();
		my $fullness	  	= $client->bufferFullness() || 0;
		
		$songtime = $byterate ? (($bytesReceived - $fullness) / $byterate * $rate + $startStream) : 0;
		if ( $log->is_debug ) {
			$log->debug("songtime=$songtime from byterate=$byterate, duration=$duration, bytesReceived=$bytesReceived, fullness=$fullness, rate=$rate, startStream=$startStream");
		}
	} elsif ($rate >= 1) {
		# If we're moving forward and have started streaming the next
		# track, the fullness metric can no longer be used to determine
		# how far into the track we are. So say that we're done with it.

		$songtime = $duration || 0;
	} else {
		# we really don't know
		$songtime = 0;
	}

	# limit check
	if ($songtime < 0) {
		$songtime = 0;
	} elsif ($duration && $songtime > $duration) {
		$songtime = $duration;
	}
	

	return $songtime;
}

sub textSongTime {
	my $client = shift;
	my $playingDisplayMode = shift;

	my $delta = 0;
	my $sign  = '';

	if (playmode($client) eq "stop") {
		$delta = 0;
	} else {	
		$delta = songTime($client);
	}
	
	# 2 and 5 display remaining time, not elapsed
	if ($playingDisplayMode % 3 == 2) {
		my $song     = playingSong($client);
		my $duration = $song->{duration} || 0;
		if ($duration) {
			$delta = $duration - $delta;	
			$sign = '-';
		}
	}
	
	my $hrs = int($delta / (60 * 60));
	my $min = int(($delta - $hrs * 60 * 60) / 60);
	my $sec = $delta - ($hrs * 60 * 60 + $min * 60);
	
	my $time;
	if ($hrs) {
		$time = sprintf("%s%d:%02d:%02d", $sign, $hrs, $min, $sec);
	} else {
		$time = sprintf("%s%02d:%02d", $sign, $min, $sec);
	}

	return $time;
}

sub repeatCallback {
	my $request = shift;
	
	my $client = $request->client();
	
	# shor circuit if this client isn't the one in playout
	return unless ($client->playmode =~ /playout/i);
	
	# Check the buffers for the client and reset based on repeat change
	# call playmode function so that sync groups are handled
	if (!Slim::Player::Playlist::repeat($client) &&
		(streamingSongIndex($client) == (Slim::Player::Playlist::count($client) - 1))) {
		
		playmode($client,'playout-stop');
	}
	else {
		
		playmode($client,'playout-play');
	}
}

sub _returnPlayMode {
	my $client = shift;

	my $returnedmode = $client->playmode();
	
	$returnedmode = 'play' if $returnedmode =~ /^play/i;
	
	return $returnedmode;
}

# playmode - start playing, pause or stop
sub playmode {
	my ($client, $newmode, $seekoffset) = @_;

	assert($client);
	
	# Short circuit.
	return _returnPlayMode($client) unless defined $newmode;

	my $master   = Slim::Player::Sync::masterOrSelf($client);

	#
	my $prevmode = $client->playmode();

	if ( $log->is_info ) {
		$log->info($client->id, ": Switching to mode $newmode from $prevmode");
	}

	# don't switch modes if it's the same 
	if ($newmode eq $prevmode && !$seekoffset) {

		$log->info("Already in playmode $newmode : ignoring mode change");

		return _returnPlayMode($client);
	}
	
	my $currentURL = Slim::Player::Playlist::url($client, streamingSongIndex($client));
	
	# Some protocol handlers don't allow pausing of active streams.
	# We check if that's the case before continuing.
	if ($newmode eq "pause" && defined($currentURL)) {

		# Always allow pausing to rebuffer even on protocols that don't allow it (Rhapsody Radio)
		my $caller = (caller(1))[3];
		if ( $caller !~ /outputUnderrun/ ) {
			my $handler = Slim::Player::ProtocolHandlers->handlerForURL($currentURL);

			if ($handler && $handler->can("canDoAction") &&
				!$handler->canDoAction($client, $currentURL, 'pause')) {

				$log->warn("Protocol handler doesn't allow pausing. Let's try stopping.");

				return playmode($client, "stop", $seekoffset);
			}
		}
	}

	if ($newmode eq "play" && $prevmode eq "pause") {
		$newmode = "resume";
	}
	
	# When pausing, we must remember if we were in play or playout mode
	if ( $newmode eq 'pause' ) {
		$master->resumePlaymode($prevmode);
	}
	
	# This function is likely doing too much.
	if ($newmode eq "pause" && $client->rate != 1) {
		$newmode = "pausenow";
	}
	
	# if we're playing, then open the new song the master.		
	if ($newmode eq "resume") {

		# if the player is off, we automatically power on when we start to play
		if (!$client->power()) {
			$client->power(1);
		}
	}

	# if we're playing, then open the new song the master.		
	if ($newmode eq "play") {
		
		# Clear previous metadata title when starting a new track
		$client->metaTitle( undef );

		# if the player is off, we automatically power on when we start to play
		if (!$client->power()) {
			$client->power(1);
		}
		
		# if we couldn't open the song, then stop...
		my $opened = openSong($master, $seekoffset) || do {

			# If there aren't anymore items in the
			# playlist - just return, don't try and play again.
			if (noMoreValidTracks($client)) {

				$log->warn("No more valid tracks on the playlist. Stopping.");

				$newmode = 'stop';

			} else {

				# Otherwise, try and open the next item on the list.
				trackStartEvent($client);

				if (!gotoNext($client,1)) {

					# Still couldn't open? Stop the player.
					logError("Couldn't gotoNext song on playlist, stopping");

					$newmode = 'stop';
				}
			}
		};

		$client->bytesReceivedOffset(0);
	}
	
	# when we change modes, make sure we do it to all the synced clients.
	foreach my $everyclient ($client, Slim::Player::Sync::syncedWith($client)) {

		if ( $log->is_info ) {
			$log->info($everyclient->id, " New play mode: $newmode");
		}

		next if $prefs->client($everyclient)->get('silent');

		# set up a callback to handle repeat changes during buffer drain
		if ($newmode =~ /^playout/) {
			Slim::Control::Request::subscribe(\&repeatCallback,[['playlist'],['repeat']]);
		} else {
			Slim::Control::Request::unsubscribe(\&repeatCallback);
		}

		# when you resume, you go back to play mode
		if (($newmode eq "resume") ||($newmode eq "resumenow")) {

			$everyclient->resume();
			
			my $prevmode = $master->resumePlaymode() || 'play';
			
			if ( $log->is_info ) {
				$log->info($everyclient->id() . ": Resume, resetting mode: $prevmode");
			}
			
			$everyclient->playmode($prevmode);
			
		} elsif ($newmode eq "pausenow") {

			$everyclient->playmode("pause");
			
		} elsif ($newmode =~ /^playout/) {

			closeSong($everyclient);
			# Resume to make sure that we actually start playing
			# what we just finished streaming (it may be too short
			# to have triggered an autostart).
			$everyclient->resume();
			$everyclient->playmode($newmode);

		} else {
			$everyclient->playmode($newmode);
		}

		if ($newmode eq "stop") {

			if ( $log->is_info ) {
				$log->info($everyclient->id, ": Stopping and clearing out old chunks");
			}

			$everyclient->currentplayingsong("");

			@{$everyclient->chunks} = ();

			$everyclient->stop();
			closeSong($everyclient);
			resetSong($everyclient);
			resetSongQueue($everyclient);

		} elsif ($newmode eq "play") {
						
			$everyclient->resumePlaymode(undef);	# Bug 5210
			
			$everyclient->readytosync(0);
			if ($prefs->client($everyclient)->get('syncVolume')) {
				$everyclient->volume($client->volume(),1);
				$everyclient->fade_volume($FADEVOLUME) unless $client->volume();
			}
			else {
				$everyclient->volume($everyclient->volume(),1);
				$everyclient->fade_volume($FADEVOLUME) unless $everyclient->volume();
			}
			$everyclient->streamBytes(0);
			
			my $currentSong = Slim::Player::Playlist::song($client, streamingSongIndex($client));
			
			if ( ref $currentSong ) {

				if ( $currentSong->can('url') ) {
					$currentSong = $currentSong->url;
				}
			}
			
			my $paused = ( Slim::Player::Sync::isSynced($everyclient) ) ? 1 : 0;
			
			$everyclient->play({ 
				'paused'      => $paused, 
				'format'      => $master->streamformat(), 
				'url'         => $currentSong, 
				'reconnect'   => (defined($seekoffset) && $seekoffset > 0), 
				'loop'        => $master->shouldLoop, 
				'replay_gain' => Slim::Player::ReplayGain->fetchGainMode($master)
			});

		} elsif ($newmode eq "pause") {

			# since we can't count on the accuracy of the fade
			# timers, we unfade them all, but the master calls
			# back to pause everybody
			if ($everyclient->id eq $client->id) {
				$everyclient->fade_volume(-$FADEVOLUME, \&pauseSynced, [$client]);
			} else {
				$everyclient->fade_volume(-$FADEVOLUME);
			}				
			
		} elsif ($newmode eq "pausenow") {

			$everyclient->pause();

		} elsif ($newmode eq "resumenow") {

			if ($prefs->client($everyclient)->get('syncVolume')) {
				$everyclient->volume($client->volume(),1);
			}
			else {
				$everyclient->volume($everyclient->volume(),1);
			}
			$everyclient->resume();
			
		} elsif ($newmode eq "resume") {

			# set volume to 0 to make sure fade works properly
			$everyclient->volume(0,1);
			$everyclient->resume();
			$everyclient->fade_volume($FADEVOLUME);
			
		} elsif ($newmode =~ /^playout/) {

			$everyclient->playout();

		} else {

			if ( $log->is_info ) {
				$log->info(" Unknown play mode: ", $everyclient->playmode);
			}

			return $everyclient->playmode();
		}

		if ($newmode eq 'play' && $everyclient->directURL()) {
			if (!Slim::Player::Playlist::repeat($client) &&
				(streamingSongIndex($client) == (Slim::Player::Playlist::count($client) - 1))) {
				
				# buffer into emptying mode, end playback when buffer empty
				$everyclient->playmode('playout-stop');
			}
			else {
				
				# buffer into emptying mode, continue on underrun
				$everyclient->playmode('playout-play');
			}
		}

		Slim::Player::Playlist::refreshPlaylist($everyclient);

	}
	
	if ( $log->is_info ) {
		$log->info($client->id() . ": Current playmode: $newmode\n");
	}

	# if we're doing direct streaming, we want to handle the end of the stream gracefully...

	return _returnPlayMode($client);
}

# If there are no more tracks in the queue, or the track on the queue has
# already been marked as invalid, stop.
sub noMoreValidTracks {
	my $client = shift;

	my $count  = Slim::Player::Playlist::count($client);

	if (streamingSongIndex($client) == ($count - 1) || !$count) {
		return 1;
	}

	return 0;
}

sub decoderUnderrun {
	my $client = shift || return;

	if ( $log->is_info ) {
		$log->info($client->id, ": Decoder underrun while this mode: ", $client->playmode);
	}
	
	# in the case that we're starting up a digital input, 
	# we want to defer until the output underruns, not the decoder
	return if (Slim::Music::Info::isDigitalInput(Slim::Player::Playlist::song($client, nextsong($client))));
	
	my $queue = $client->currentsongqueue();
	
	# If the song that was underrun was not yet playing, mark it as played
	my $song = streamingSong($client);
	if ( $song->{status} == STATUS_STREAMING ) {
		$log->info('Track failed before playback, marking as played');
		
		markStreamingTrackAsPlayed($client);
		
		# If we now have 2 tracks in the queue, pop the failed one off,
		# so we are able to continue with the next track
		if ( scalar @{$queue} > 1 ) {
			pop @{$queue};
		}
		
		# If the track that failed was the final one, stop, unless we're in repeat mode
		if ( noMoreValidTracks($client) && !Slim::Player::Playlist::repeat($client) ) {
			playmode( $client, 'stop' );
		}
	}
	
	# Bug 5103, the firmware can handle only 2 tracks at a time: one playing and one streaming,
	# and on very short tracks we may get multiple decoder underrun events during playback of a single
	# track.  We need to ignore decoder underrun events if there's already a streaming track in the queue
	
	# XXX: This probably breaks the async handling below
	if ( scalar @{$queue} > 1 ) {
		if ( $log->is_info ) {
			$log->info( $client->id, ': Ignoring decoder underrun, player already has 2 tracks' );
		}
		
		# Flag this situation so we know to load the next track on the next track start event
		$client->streamAtTrackStart(1);
		
		return;
	}
	
	# Don't advance if we are sleeping within the next 10 seconds
	if ( $client->currentSleepTime() && $client->currentSleepTime() < 10 ) {
		if ( $log->is_info ) {
			$log->info( $client->id . ": Ignoring decoder underrun, playing is sleeping" );
		}
		return;
	}
	
	streamNextTrack($client);
}

sub streamNextTrack {
	my $client = shift;
	
	my $playmode = $client->playmode();
	if ( $playmode eq 'pause' ) {
		$playmode = $client->masterOrSelf()->resumePlaymode() || 'play';
	}

	my $skipaheadCallback = sub {
		if (   !Slim::Player::Sync::isSynced($client)
			&& ( $client->rate() == 0 || $client->rate() == 1 )
			&& ( $playmode eq 'playout-play' )
		) {
			skipahead($client);
		}
	};
		
	# Allow protocol handler to perform async commands after an underrun.  This is used by
	# Rhapsody Direct to set up the next track for playback
	my $nextSong = nextsong($client);
	if ( defined $nextSong ) {
		my $nextURL = Slim::Player::Playlist::url( $client, $nextSong );
		my $handler = Slim::Player::ProtocolHandlers->handlerForURL( $nextURL );
		if ( $handler && $handler->can('onDecoderUnderrun') ) {
			$handler->onDecoderUnderrun(
				$client,
				$nextURL,
				$skipaheadCallback,
			);
			return;
		}
	}

	$skipaheadCallback->();
}

sub underrun {
	my $client = shift || return;
	
	$client->readytosync(-1);
	
	if ( $log->is_info ) {
		$log->info($client->id, ": Underrun while this mode: ", $client->playmode);
	}
	
	# Don't advance if we are sleeping within the next 10 seconds
	if ( $client->currentSleepTime() && $client->currentSleepTime() < 10 ) {
		if ( $log->is_info ) {
			$log->info( $client->id . ": Ignoring underrun, playing is sleeping" );
		}
		$client->stop();
		return;
	}

	# if we're synced, then we tell the player to stop and then let resync restart us.
	
	my $underrunCallback = sub {
		my $playmode = $client->playmode();
		if ( $playmode eq 'pause' ) {
			$playmode = $client->masterOrSelf()->resumePlaymode() || 'play';
		}
		
		if (Slim::Player::Sync::isSynced($client)) {
			if ($playmode =~ /playout/) {
				$client->stop();
			}
		} elsif ($playmode eq 'playout-play') {
			
			skipahead($client);
			
		} elsif ($playmode eq 'playout-stop') {

			playmode($client, 'stop');
			streamingSongIndex($client, 0, 1);

			$client->currentPlaylistChangeTime(Time::HiRes::time());

			Slim::Player::Playlist::refreshPlaylist($client);

			$client->update();
		
			Slim::Control::Request::notifyFromArray($client, ['stop']);
		}
	};
	
	# Allow protocol handler to perform async commands after an underrun.
	my $url     = Slim::Player::Playlist::url( $client );
	my $handler = Slim::Player::ProtocolHandlers->handlerForURL( $url );
	if ( $handler && $handler->can('onUnderrun') ) {
		$handler->onUnderrun(
			$client,
			$url,
			$underrunCallback,
		);
		return;
	}
	
	$underrunCallback->();
}

sub notSupported {
	my $client = shift || return;
	
	logError("Decoder does not support file format, skipping track");
	
	errorOpening($client);
}

sub outputUnderrun {
	my $client = shift;
	
	# STMo is called when the output buffer underruns but the decoder connection is still active.
	# It signals that we need to pause and rebuffer the live audio stream.

	return unless $client->playmode() =~ /play/;
	
	if ( $log->is_info ) {
		my $decoder = $client->bufferFullness();
		my $output  = $client->outputBufferFullness() || 0;
		$log->info($client->id, ": Output buffer underrun (decoder: $decoder / output: $output)" );
	}
	
	# If playing Rhapsody, underrun means getEA may be failing, so log it
	if ( $ENV{SLIM_SERVICE} ) {
		my $url = Slim::Player::Playlist::url($client);
		
		if ( $url =~ /^rhapd:/ ) {
			my $decoder = $client->bufferFullness();
			my $output  = $client->outputBufferFullness();
		
			SDI::Service::EventLog::logEvent( 
				$client->id, 'rhapsody_error', 'UNDERRUN', "decoder: $decoder / output: $output",
			);
		}
	}
	
	playmode( $client, 'pause' );
	
	my ( $line1, $line2 ); 	 

	my $string = 'REBUFFERING'; 	 
	$line1 = $client->string('NOW_PLAYING') . ' (' . $client->string($string) . ' 0%)'; 	 
	if ( $client->linesPerScreen() == 1 ) { 	 
		$line2 = $client->string($string) . ' 0%'; 	 
	} 	 
	else { 	 
		my $url = Slim::Player::Playlist::url($client); 	 
		$line2  = Slim::Music::Info::title($url);
	}
	
	$client->showBriefly( {
		line => [ $line1, $line2 ],
		jive => undef,
		cli  => undef,
	}, 2 ) unless $client->display->sbName();
	
	# Setup a timer to check the buffer and unpause
	$client->bufferStarted( Time::HiRes::time() ); # track when we started rebuffering
	Slim::Utils::Timers::setTimer( $client, Time::HiRes::time() + 1, \&rebuffer );
}

sub rebuffer {
	my $client = shift;
	
	# If the user changes something, stop rebuffering
	return unless $client->playmode() eq 'pause';
	
	$client->requestStatus();
	
	my $threshold = 80 * 1024; # 5 seconds of 128k
	
	my $url = Slim::Player::Playlist::url($client);
	if ( my $bitrate = Slim::Music::Info::getBitrate($url) ) {
		$threshold = 5 * ( int($bitrate / 8) );
	}
	
	# We restart playback based on the decode buffer, 
	# as the output buffer is not updated in pause mode.
	my $fullness = $client->bufferFullness();
	
	$log->debug( "Rebuffering: $fullness / $threshold" );
	
	if ( $fullness >= $threshold ) {
		playmode( $client, 'play' );
		
		$client->update();
	}
	else {
		
		# Only show rebuffering status if no user activity on player or we're on the Now Playing screen
		my $nowPlaying = Slim::Buttons::Playlist::showingNowPlaying($client);
		my $lastIR     = Slim::Hardware::IR::lastIRTime($client) || 0;

		if ( $nowPlaying || $lastIR < $client->bufferStarted() ) {
			my ( $line1, $line2 );
		
			# Bug 1827, display better buffering feedback while we wait for data
			my $percent = sprintf "%d%%", ( $fullness / $threshold ) * 100;

			my $string = 'REBUFFERING';
			$line1 = $client->string('NOW_PLAYING') . ' (' . $client->string($string) . " $percent)"; 	 
			if ( $client->linesPerScreen() == 1 ) { 	 
				$line2 = $client->string($string) . " $percent"; 	 
			} 	 
			else { 	 
				my $url = Slim::Player::Playlist::url($client); 	 
				$line2  = Slim::Music::Info::title($url);
			}

			$client->showBriefly( {
				line => [ $line1, $line2 ],
				jive => undef,
				cli  => undef,
			}, 2 ) unless $client->display->sbName();
		}
		
		Slim::Utils::Timers::setTimer( $client, Time::HiRes::time() + 1, \&rebuffer );
	}
}

sub skipahead {
	my $client = shift;

	if (!$client->reportsTrackStart() || Slim::Player::Sync::isSynced($client)) {

		$log->info("**skipahead: stopping");

		playmode($client, 'stop');
	}

	$log->info("**skipahead: opening next song");

	my $succeeded = gotoNext($client, 0);

	if ($succeeded) {

		$log->info("**skipahead: restarting");

		playmode($client, 'play');
	}
} 

sub nextChunk {
	my $client       = shift;
	my $maxChunkSize = shift;

	my $chunk;
	my $len;

	return if !$client;

	# if there's a chunk in the queue, then use it.
	if (ref($client->chunks) eq 'ARRAY' && scalar(@{$client->chunks})) {

		$chunk = shift @{$client->chunks};

		$len = length($$chunk);

		# A zero length chunk is a marker for the end of the stream.
		# If we see one, close the outgoing connection.
		if (!$len) {

			$log->info("Found an empty chunk on the queue - dropping the streaming connection.");

			Slim::Web::HTTP::forgetClient($client);

			$chunk = undef;
		}

	} else {

		#otherwise, read a new chunk
		my $master = Slim::Player::Sync::masterOrSelf($client);

		$chunk = readNextChunk($master, $maxChunkSize);

		if (defined($chunk)) {

			$len = length($$chunk);

			if ($len) {

				# let everybody I'm synced with use this chunk
				foreach my $buddy (Slim::Player::Sync::syncedWith($client)) {

					push @{$buddy->chunks}, $chunk;
				}
				
				# And save the data for analysis, if we are synced.
				# Only really need to do this if we have any SliMP3s or SB1s in the
				# sync group.
				if (Slim::Player::Sync::isMaster($master)) {
					if (my $buf = $master->initialStreamBuffer()) {
						$$buf .= $$chunk;

						# Safety check - just make sure that we are not in the process
						# of slurping up a perhaps-infinite stream without using it.
						# We assume min frame size of 72 bytes (24kb/s, 48000 samples/s)
						# which gives us at most 45512 frames in the decode buffer (25Mb)
						# and 355 samples in the output buffer (also 25Mb) at 1152 samples/frame
						if (length($$buf) > 3_500_000 ||
							defined($master->frameData) && @{$master->frameData} > 50_000)
						{
							$log->warn('Discarding saved stream & frame data used for synchronization as appear to be collecting it but not using it');
							resetFrameData($master);
						}
					} elsif ($master->streamformat() eq 'mp3' && $master->streamBytes() <= $len) {
						# do we need to save frame data?
						my $needFrameData = 0;
						foreach ($master, Slim::Player::Sync::slaves($master)) {
							my $model = $_->model();
							last if $needFrameData = ($model eq 'slimp3' || $model eq 'squeezebox');
						}
						if ($needFrameData) {		
							my $savedChunk = $$chunk; 	# copy
							$master->initialStreamBuffer(\$savedChunk);
						}
					}
				}
			}
		}
	}
	
	if (defined($chunk) && ($len > $maxChunkSize)) {

		$log->debug("Chunk too big, pushing the excess for later.");

		my $queued = substr($$chunk, $maxChunkSize - $len, $len - $maxChunkSize);

		unshift @{$client->chunks}, \$queued;

		my $returned = substr($$chunk, 0, $maxChunkSize);

		$chunk = \$returned;
	}
	
	return $chunk;
}

#
# jump to a particular time in the current song
#  should be dead-on for CBR, approximate for VBR
#  third argument determines whether we should range check i.e. whether
#  we should jump to the next or previous song if the newtime is 
#  beyond the range of the current one.
#
sub gototime {
	my $client  = Slim::Player::Sync::masterOrSelf(shift);
	my $newtime = shift;
	my $rangecheck = shift;
	
	return unless Slim::Player::Playlist::song($client);

	if (!defined $client->audioFilehandle()) {
		return unless openSong($client);
	}

	my $song = playingSong($client);
	my $songLengthInBytes = $song->{totalbytes};
	my $duration	      = $song->{duration};

	return if (!$songLengthInBytes || !$duration);

	if ($newtime =~ /^[\+\-]/) {

		my $oldtime = songTime($client);

		$log->info("Relative jump $newtime from current time $oldtime");

		$newtime += $oldtime;
	}

	my $newoffset = time2offset($client, $newtime);

	if ($rangecheck) {

		if ($newoffset > $songLengthInBytes) {
			$newoffset = $songLengthInBytes;
		}
		elsif ($newoffset < 0) {
			$newoffset = 0;
		}
	}

	$log->info("Going to time $newtime");

	# skip to the previous or next track as necessary
	if ($newoffset > $songLengthInBytes) {

		my $rate = rate($client);

		jumpto($client, "+1");
		rate($client, $rate);

		$newtime = ($newoffset - $songLengthInBytes) * $duration / $songLengthInBytes;

		$log->info("Skipping forward to the next track to time $newtime");

		gototime($client, $newtime);

		return;

	} elsif ($newoffset < 0) {

		my $rate = rate($client);

		while ($newtime < 0) {

			jumpto($client, "-1");

			rate($client, $rate);

			$newtime = $song->{duration} - ((-$newoffset) * $duration / $songLengthInBytes);

			$log->info("Skipping backwards to the previous track to time $newtime");
		}

		gototime($client, $newtime);

		return;

	} elsif (playingSongIndex($client) != streamingSongIndex($client)) {

		my $rate = rate($client);

		jumpto($client, playingSongIndex($client));

		rate($client, $rate);

		$log->info("Resetting to the track that's currently playing (but no longer streaming)");

		gototime($client, $newtime, $rangecheck);

		return;
	}

	for my $everybuddy ($client, Slim::Player::Sync::slaves($client)) {

		if ($prefs->client($everybuddy)->get('silent')) {
			next;
		}

		if ( $log->is_info ) {
			$log->info("Stopping playback for ", $everybuddy->id);
		}

		$everybuddy->stop();

		@{$everybuddy->chunks} = ();
	}

	my $dataoffset = $song->{offset};

	$client->songBytes($newoffset);
	$song->{startOffset} = $newtime;
	$client->streamBytes(0);
	$client->bytesReceivedOffset(0);
	$client->trickSegmentRemaining(0);
	resetFrameData($client);

	$client->audioFilehandle()->sysseek($newoffset + $dataoffset, 0);

	for my $everybuddy ($client, Slim::Player::Sync::slaves($client)) {

		if ($prefs->client($everybuddy)->get('silent')) {
			next;
		}

		if ( $log->is_info ) {
			$log->info("Restarting playback for ", $everybuddy->id);
		}

		$everybuddy->readytosync(0);
		
		my $paused = ( Slim::Player::Sync::isSynced($client) ) ? 1 : 0;

		$everybuddy->play({ 
			'paused'      => $paused, 
			'format'      => $client->streamformat(), 
			'url'         => Slim::Player::Playlist::song($client), 
			'replay_gain' => Slim::Player::ReplayGain->fetchGainMode($client)
		});

		$everybuddy->playmode("play");
	}
}

# jumpto - set the current song to a given offset
sub jumpto {
	my $client = Slim::Player::Sync::masterOrSelf(shift);
	my $offset = shift;
	my $noplay = shift;

	my ($songcount) = Slim::Player::Playlist::count($client);

	if ($songcount == 0) {
		return;
	}
	
	my $currentURL = Slim::Player::Playlist::url($client, streamingSongIndex($client));
	my $handler    = Slim::Player::ProtocolHandlers->handlerForURL($currentURL);

	if ($offset && $offset =~ /([\+\-])(\d+)/ && ($1 eq '-' || $2 eq '0')) {

		if ($handler && 
			$handler->can("canDoAction") &&
			!$handler->canDoAction($client, $currentURL, 'rew')) {
			return;
		}
	}
	
	playmode($client, 'stop');

	if ($songcount != 1) {

		my $index;

		if (defined $offset && $offset =~ /[\+\-]\d+/) {

			$index = playingSongIndex($client) + $offset;

			$log->info("Jumping by $offset");

		} else {

			$index = $offset || 0;

			$log->info("Jumping to $index");
		}
	
		if ($songcount && $index >= $songcount) {
			$index = $index % $songcount;
		}

		if ($songcount && $index < 0) {

			$index =  $songcount - ((0 - $index) % $songcount);
		}

		streamingSongIndex($client, $index, 1);

	} else {

		streamingSongIndex($client, 0, 1);
	}

	$client->currentPlaylistChangeTime(Time::HiRes::time());

	Slim::Buttons::Common::syncPeriodicUpdates($client, Time::HiRes::time() + 0.1);

	if (!$noplay) {

		playmode($client, "play");
	}
}


################################################################################
# Private functions below. Do not call from outside this module.
# XXX - should be _ prefixed then!
#
################################################################################

# gotoNext returns 1 if it succeeded opening a new song, 
#                  0 if it stopped at the end of the list or failed to open the current song 
# note: Only call this with a master or solo client
sub gotoNext {
	my $client = shift;
	my $open = shift;
	my $result = 1;

	$log->info("Opening next song..."); 

	my $oldstreamformat = $client->streamformat();
	my $nextsong;

	closeSong($client);

	# we're at the end of a song, let's figure out which song to open up.
	# if we can't open a song, skip over it until we hit the end or a good song...
	do {
	
		if (Slim::Player::Playlist::repeat($client) == 2  && $result) {

			$nextsong = nextsong($client);

		} elsif (Slim::Player::Playlist::repeat($client) == 1 && $result) {

			# play the same song again

		} else {

			# stop at the end of the list or when list is empty
			if (noMoreValidTracks($client)) {

				$nextsong = 0;

				playmode($client, $result ? 'playout-stop' : 'stop');

				# We're done streaming the song, so drop the streaming
				# connection to the client.
				dropStreamingConnection($client);

				$client->update();
				
				return 0;

			} else {

				$nextsong = nextsong($client);
			}
		}

		my ($command, $type, $newstreamformat) = Slim::Player::TranscodingHelper::getConvertCommand(
			$client, Slim::Player::Playlist::song($client, $nextsong)
		);
		
		# Determine the current playmode or if paused, the previous playmode
		my $playmode = $client->playmode();
		if ( $playmode eq 'pause' ) {
			$playmode = $client->resumePlaymode() || 'play';
		}
		
		# here's where we decide whether to start the next song in a new stream after playing out
		# the current song or to just continue streaming
		if (
			( $playmode eq 'play' )
			&& 
			(
				   ( $oldstreamformat ne $newstreamformat )
				|| Slim::Player::Sync::isSynced($client) 
			 	|| $client->isa("Slim::Player::Squeezebox2")
				|| ( $client->rate() != 1 )
			)
		) {

			$log->info(
				"Playing out before starting next song. (old format: ",
				"$oldstreamformat, new: $newstreamformat)"
			);

			if ( $client->playmode() eq 'pause' ) {
				# This may not work, playmode() does lots of other stuff
				$client->resumePlaymode( 'playout-play' );
			}
			else {
				playmode($client, 'playout-play');
			}
			
			# We're done streaming the song, so drop the streaming
			# connection to the client.
			dropStreamingConnection($client);

			return 0;

		} else {
			
			# Reuse the connection for the next song, for SB1, HTTP streaming
			if ( $log->is_info ) {
				$log->info(
					"opening next song (old format: $oldstreamformat, ",
					"new: $newstreamformat) current playmode: ", $client->playmode
				);
			}
			
			streamingSongIndex($client, $nextsong);
			return 1 if !$open;
			$result = openSong($client);
		}

	} while (!$result);

	return $result;
}

sub dropStreamingConnection {
	my $client = shift;

	if (!scalar(@{$client->chunks})) {

		$log->info("No pending chunks - we're dropping the streaming connection");

		Slim::Web::HTTP::forgetClient($client);

	} else {

		$log->info(
			"There are pending chunks - queue an empty chunk and wait ",
			"till the chunk queue is empty before dropping the connection."
		);

		push @{$client->chunks}, \'';
	}

	for my $buddy (Slim::Player::Sync::syncedWith($client)) {

		push @{$buddy->chunks}, \'';
	}
}

# For backwards compatability
sub currentSongIndex {

	return streamingSongIndex(@_);
}

sub streamingSongIndex {
	my $client = Slim::Player::Sync::masterOrSelf(shift);
	my $index = shift;
	my $clear = shift;
	my $song = shift;

	my $queue = $client->currentsongqueue();
	if (defined($index)) {

		$log->info("Adding song index $index to song queue");

		if (!$client->reportsTrackStart() || $clear || Slim::Player::Sync::isSynced($client)) {

			$log->info("Clearing out song queue first");

			$#{$queue} = -1;
		}
		
		if (defined($song)) {

			unshift(@{$queue}, $song);

		} else {

			unshift(@{$queue}, {
				'index'  => $index, 
				'status' => STATUS_STREAMING,
			});
		}

		if ( $log->is_info ) {
			$log->info("Song queue is now " . join(',', map { $_->{'index'} } @$queue));
		}
	}

	$song = $client->currentsongqueue()->[0];

	if (!defined($song)) {
		return 0;
	}

	return $song->{'index'};
}

sub streamingSong {
	my $client = Slim::Player::Sync::masterOrSelf(shift);

	if (!scalar(@{$client->currentsongqueue()})) {
		streamingSongIndex($client, 0);
	}

	return $client->currentsongqueue()->[0];
}

sub playingSongIndex {
	my $client = Slim::Player::Sync::masterOrSelf(shift);

	my $song = playingSong($client);

	if (!defined($song)) {
		return 0;
	}

	return $song->{'index'};
}

sub playingSong {
	my $client = Slim::Player::Sync::masterOrSelf(shift);

	return $client->currentsongqueue()->[-1];
}

sub playingSongDuration {
	my $client = shift;
	my $song = playingSong($client);
	
	return defined($song) ? $song->{duration} : 0;
}

sub resetSongQueue {
	my $client = Slim::Player::Sync::masterOrSelf(shift);
	my $queue = $client->currentsongqueue();

	$log->info("Resetting song queue");

	my $playingsong = $client->currentsongqueue()->[-1];

	$playingsong->{'status'} = STATUS_STREAMING;

	$#{$queue} = -1;

	push @$queue, $playingsong;

	if ( $log->is_info ) {
		$log->info("Song queue is now " . join(',', map { $_->{'index'} } @$queue));
	}
	
	# update CURTRACK of a known playlist back to start
	#my $request = Slim::Control::Request->new( (blessed($client) ? $client->id() : undef));
	#$request->addParam('reset',1);

	Slim::Player::Playlist::newSongPlaylist($client, 1);
}

sub markStreamingTrackAsPlayed {
	my $client = shift;

	my $song = streamingSong($client);
	if (defined($song)) {
		$song->{status} = STATUS_PLAYING;
	}
}

sub trackStartEvent {
	my $client = shift;
	
	# Keep client and master separate so that the playlist newsong notification
	# uses the correct client.
	my $master = Slim::Player::Sync::masterOrSelf($client) || return;

	$log->info("Got a track starting event");

	my $queue     = $master->currentsongqueue();
	my $last_song = $queue->[-1];

	while (defined($last_song) && $last_song->{status} == STATUS_PLAYING && scalar(@$queue) > 1) {

		$log->info("Song " . $last_song->{'index'} . " had already started, so it's not longer in the queue");

		pop @{$queue};

		$last_song = $queue->[-1];
	}
	
	if (defined($last_song)) {

		$log->info("Song " . $last_song->{'index'} . " has now started playing");

		$last_song->{'status'} = STATUS_PLAYING;
	}

	$master->currentPlaylistChangeTime(Time::HiRes::time());

	Slim::Player::Playlist::refreshPlaylist($master);
	Slim::Control::Request::notifyFromArray($client,
		[
			'playlist', 
			'newsong', 
			Slim::Music::Info::standardTitle(
				$master, 
				Slim::Player::Playlist::song(
					$master,
					$last_song->{'index'}
				)
			),
			$last_song->{'index'}
		]
	);

	if ( $log->is_info ) {
		$log->info("Song queue is now " . join(',', map { $_->{'index'} } @$queue));
	}
	
	# Bug 5103
	# We can now start streaming the next track, if the player was already handling
	# 2 tracks the last time we got a decoder underrun event
	if ( $master->streamAtTrackStart() ) {
		
		streamNextTrack($master);
		
		$master->streamAtTrackStart(0);
	}
}

# nextsong is for figuring out what the next song will be.
sub nextsong {
	my $client = shift;

	my $nextsong;
	my $currsong = streamingSongIndex($client);

	if (Slim::Player::Playlist::count($client) == 0) {
		return 0;
	}

	my $direction = 1;

	if ($client->rate() < 0) {
		$direction = -1;
	}

	$nextsong = streamingSongIndex($client) + $direction;

	if ($nextsong >= Slim::Player::Playlist::count($client)) {

		# play the next song and start over if necessary
		if (Slim::Player::Playlist::shuffle($client) && 
			Slim::Player::Playlist::repeat($client) == 2 &&
			$prefs->get('reshuffleOnRepeat')) {
			
			Slim::Player::Playlist::reshuffle($client, 1);
		}

		$nextsong = 0;
	}
	
	if ($nextsong < 0) {
		$nextsong = Slim::Player::Playlist::count($client) - 1;
	}
	
	$log->info("The next song is number $nextsong, was $currsong");

	return $nextsong;
}

sub flushStreamingSong {
	my $client = shift;
	
	closeSong($client);

	if (streamingSongIndex($client) != playingSongIndex($client)) {

		my $queue = $client->currentsongqueue();

		shift @{$queue};

		playmode($client, 'playout-play');
	}

	$client->flush();
}

sub closeSong {
	my $client = shift;

	# close the previous handle to prevent leakage.
	if (defined $client->audioFilehandle()) {

		$client->audioFilehandle->close();
		$client->audioFilehandle(undef);
		$client->audioFilehandleIsSocket(0);
	}

	$client->directURL(undef);
}

sub resetSong {
	my $client = shift;

	$log->info("Resetting song buffer.");

	# at the end of a song, reset the song time
	$client->songBytes(0);
	$client->bytesReceivedOffset($client->bytesReceived());
	$client->trickSegmentRemaining(0);
	resetFrameData($client);
}

sub errorOpening {
	my ( $client, $error ) = @_;

	if ($client->reportsTrackStart()) {

		$log->logBacktrace("While opening current track, so mark it as already played!");

		markStreamingTrackAsPlayed($client);
	}
	
	my $line1;
	$error ||= 'PROBLEM_OPENING';
	
	my $line2 = Slim::Music::Info::standardTitle($client, Slim::Player::Playlist::song($client, streamingSongIndex($client)));
	
	my $url = Slim::Player::Playlist::url($client, streamingSongIndex($client));
	Slim::Control::Request::notifyFromArray($client, ['playlist', 'cant_open', $url, $error]);
	
	if ( uc($error) eq $error ) {
		$line1 = $client->string($error);
	}
	else {
		$line1 = $error;
	}
	
	# Show an error message
	$client->showBriefly({
		'line' => [ $line1, $line2 ]
	}, { 'scroll' => 1, 'firstline' => 1 });
}

sub explodeSong {
	my $client = shift;
	my $tracks = shift;

	# insert the list onto the playlist
	splice @{Slim::Player::Playlist::playList($client)}, streamingSongIndex($client), 1, @{$tracks};

	# update the shuffle list only if we have more than 1 track
	if ( scalar @{$tracks} > 1 ) {
		Slim::Player::Playlist::reshuffle($client);
	}
}

sub openSong {
	my $client = shift;
	my $seekoffset = shift || 0;

	my $directStream = 0;

	resetSong($client);
	
	closeSong($client);

	my $song     = streamingSong($client);
	$song->{startOffset} = 0; # (logically) used to be in resetSong
	
	my $objOrUrl = Slim::Player::Playlist::song($client, streamingSongIndex($client)) || return undef;

	# Bug: 3390 - reload the track if it's changed.
	my $url      = blessed($objOrUrl) && $objOrUrl->can('url') ? $objOrUrl->url : $objOrUrl;

	my $track    = Slim::Schema->rs('Track')->objectForUrl({
		'url'      => $url,
		'readTags' => 1
	});

	if (!blessed($track) || !$track->can('url')) {

		# Try and create the track if we weren't able to fetch it.
		$track = Slim::Schema->rs('Track')->objectForUrl({
			'url'      => $url,
			'create'   => 1,
			'readTags' => 1
		});

		if (!blessed($track) || !$track->can('url')) {

			logError("Couldnt' find an object for [$objOrUrl]!");

			return undef;
		}
	}

	my $fullpath = $track->url;

	$log->info("Trying to open: $fullpath");

	####################
	# parse the filetype
	if (Slim::Music::Info::isRemoteURL($fullpath)) {

		if ($client->canDirectStream($fullpath)) {

			$directStream = 1;
			$client->streamformat(Slim::Music::Info::contentType($track));
		}

		if (!$directStream) {

			$log->info("URL is remote (no direct streaming) [$fullpath]");

			my $sock = Slim::Player::ProtocolHandlers->openRemoteStream($fullpath, $client);
	
			if ($sock) {
				
				my $contentType = Slim::Music::Info::mimeToType($sock->contentType) || $sock->contentType;
	
				# if it's an audio stream, try to stream,
				# either directly, or via transcoding.
				if (Slim::Music::Info::isSong($track, $contentType)) {
	
					$log->info("remoteURL is a song (audio): $fullpath");
	
					if ($sock->opened() && !defined(Slim::Utils::Network::blocking($sock, 0))) {

						logError("Can't set remote stream nonblocking for url: [$fullpath]");

						errorOpening($client);

						return undef;
					}
	
					# XXX: getConvertCommand is already called above during canDirectStream
					# We shouldn't run it twice...
					my ($command, $type, $format) = Slim::Player::TranscodingHelper::getConvertCommand(
						$client, $track, $contentType,
					);

					if (!defined $command) {

						logError("Couldn't create command line for $type playback for [$fullpath]");

						errorOpening($client);

						return undef;
					}

					$log->info("remoteURL command $command type $type format $format");
					$log->info("remoteURL stream format : $contentType");

					$client->streamformat($format);
	
					# this case is when we play the file through as-is
					if ($command eq '-') {

						$client->audioFilehandle($sock);
						$client->audioFilehandleIsSocket(1);

					} else {

						my $maxRate = Slim::Utils::Prefs::maxRate($client);
						my $quality = $prefs->client($client)->get('lameQuality');
						
						$command = Slim::Player::TranscodingHelper::tokenizeConvertCommand(
							$command, $type, '-', $fullpath, 0 , $maxRate, 1, $quality
						);

						if (!defined($command)) {

							logError("Couldn't create command line for $type playback for [$fullpath]");

							errorOpening($client);
							
							return undef;
						}

						$log->info("Tokenized command $command");

						my $pipeline = Slim::Player::Pipeline->new($sock, $command);

						if (!defined($pipeline)) {

							logError("While creating conversion pipeline for: [$fullpath]");

							errorOpening($client);

							return undef;
						}
		
						$client->audioFilehandle($pipeline);
						$client->audioFilehandleIsSocket(2);
					}

					$client->remoteStreamStartTime(Time::HiRes::time());
					$client->pauseTime(0);

				# if it's one of our playlists, parse it...
				} elsif (Slim::Music::Info::isList($track, $contentType)) {
	
					# handle the case that we've actually
					# got a playlist in the list, rather
					# than a stream.
	
					# parse out the list
					my @items = Slim::Formats::Playlists->parseList($fullpath, $sock);

					# hack to preserve the title of a song redirected through a playlist
					if (scalar(@items) == 1 && $items[0] && defined($track->title)) {

						Slim::Music::Info::setTitle($items[0], $track->title);
					}

					# close the socket
					$sock->close();
					$sock = undef;
					$client->audioFilehandle(undef);
	
					explodeSong($client, \@items);
	
					# try to open the first item in the list, if there is one.
					return openSong($client);

				} else {
	
					logWarning("Don't know how to handle content for [$fullpath] type: $contentType");

					$sock->close();
					$sock = undef;

					$client->audioFilehandle(undef);
				}

			} else { 

				logWarning("Remote stream failed to open [$fullpath].");

				$client->audioFilehandle(undef);

				# XXX - this should be moved elsewhere!
				# Source.pm shouldn't be setting the display!
				my $line1 = $client->string('PROBLEM_CONNECTING');
				my $line2 = Slim::Music::Info::standardTitle($client, $track);
	
				$client->showBriefly( {
					'line' => [ $line1, $line2 ]
				}, 5, 1);
	
				return undef;
			}
		}

	} elsif (Slim::Music::Info::isSong($track)) {
	
		my $filepath = $track->path;

		my ($size, $duration, $offset, $bitrate, $samplerate, $samplesize, $channels, $blockalign, $endian, $drm) =
			(0, 0, 0, undef, 0, 0, 0, 0, undef, undef);
			
		# don't try and read this if we're a pipe
		if (!-p $filepath) {

			# XXX - endian can be undef here - set to ''.
			$size       = $track->audio_size() || -s $filepath;
			$duration   = $track->durationSeconds();
			$offset     = $track->audio_offset() || 0 + $seekoffset;
			$samplerate = $track->samplerate() || 0;
			$samplesize = $track->samplesize() || 0;
			$channels   = $track->channels() || 0;
			$blockalign = $track->block_alignment() || 1;
			$endian     = $track->endian() || '';
			$drm        = $track->drm();

			$log->info("duration: [$duration] size: [$size] endian [$endian] offset: [$offset] for $fullpath");

			if ($drm) {

				logWarning("[$fullpath] has DRM. Skipping.");

				errorOpening($client);
				return undef;
			}

			if (!$size && !$duration) {

				logWarning("[$fullpath] not bothering opening file with zero size or duration");

				errorOpening($client);
				return undef;
			}
		}

		# smart bitrate calculations
		my $rate    = ($track->bitrate || 0) / 1000;

		# if http client has used the query param, use transcodeBitrate. otherwise we can use maxBitrate.
		my $maxRate = Slim::Utils::Prefs::maxRate($client);

		my ($command, $type, $format) = Slim::Player::TranscodingHelper::getConvertCommand($client, $track);

		$log->info("This is an $type file: $fullpath");
		$log->info("  file type: $type format: $format inrate: $rate maxRate: $maxRate");
		$log->info("  command: $command");

		if (!defined($command)) {

			logError("Couldn't create command line for $type playback for [$fullpath]");

			errorOpening($client);

			return undef;
		}

		# this case is when we play the file through as-is
		if ($command eq '-') {
			$bitrate = $track->bitrate();

			# hack for little-endian aiff.
			if ($format eq 'aif' && defined($endian) && !$endian) {

				$format = 'wav';
			}

			$client->audioFilehandle( FileHandle->new() );

			$log->info("Opening file $filepath");

			if ($client->audioFilehandle->open($filepath)) {

				$log->info("Seeking in $offset into $filepath");

				if ($offset) {

					if (!defined(sysseek($client->audioFilehandle, $offset, 0))) {

						logError("couldn't seek to $offset for $filepath");
					};

					$offset -= $seekoffset;
				}
				
				if ( $format eq 'mp3' ) {

					# report whether the track should play back gapless or not
					my $streamClass = streamClassForFormat($client, 'mp3');
					my $frame       = $streamClass->getFrame( $client->audioFilehandle );
					
					# Look for the LAME header and delay data in the frame
					if ( $frame ) {
						my $io = IO::String->new( \$frame->asbin );
					
						if ( my $info = MP3::Info::get_mp3info($io) ) {
							
							if ( $log->is_debug ) {
								if ( $info->{LAME} ) {

									$log->info("MP3 file was encoded with $info->{'LAME'}->{'encoder_version'}");
							
									if ( $info->{LAME}->{start_delay} ) {

										$log->info(sprintf("MP3 contains encoder delay information (%d/%d), will be played gapless",
											$info->{LAME}->{start_delay},
											$info->{LAME}->{end_padding},
										));
									}
									else {
										$log->info("MP3 doesn't contain encoder delay information, won't play back gapless");
									}
								}
								else {
									$log->info("MP3 wasn't encoded with LAME, won't play back gapless");
								}
							}
							
							if ( $info->{BITRATE} ) {
								if ($log->is_debug && $bitrate && $info->{BITRATE}*1000 != $bitrate) {
									$log->debug(
										"Track bitrate $bitrate differs from MP3::Info rate ".
										($info->{BITRATE}*1000)
									);
							    }
								$bitrate ||= $info->{BITRATE}*1000;
							}
							
							if ( $info->{FREQUENCY} ) {
								my $frequency = int($info->{FREQUENCY} * 1000);
								if ($log->is_debug && $samplerate && $frequency != $samplerate) {
									$log->debug("Track samplerate $samplerate differs from MP3::Info rate $frequency");
								}
								$samplerate ||= $frequency;
							}
							
							$channels ||= $info->{STEREO} ? 2 : 1;
						}
					}
					else {
						$log->warn('Unable to find MP3 frame in file!');
					}
				}

				# pipe is a socket
				if (-p $filepath) {
					$client->audioFilehandleIsSocket(1);
				} else {
					$client->audioFilehandleIsSocket(0);
				}

			} else { 

				$client->audioFilehandle(undef);
			}
						
		} else {

			my $quality = $prefs->client($client)->get('lameQuality');

			$command = Slim::Player::TranscodingHelper::tokenizeConvertCommand(
				$command, $type, $filepath, $fullpath, $samplerate, $maxRate, undef, $quality
			);

			$client->audioFilehandle( FileHandle->new() );

			# Bug: 4318
			# On windows ensure a child window is not opened if $command includes transcode processes
			if (Slim::Utils::OSDetect::OS() eq 'win') {

				Win32::SetChildShowWindow(0);

				$client->audioFilehandle->open($command);

				Win32::SetChildShowWindow();

			} else {

				$client->audioFilehandle->open($command);
			}

			$client->audioFilehandleIsSocket(1);
			$client->remoteStreamStartTime(Time::HiRes::time());
			$client->pauseTime(0);
			
			# XXX: This will reset size and thus $song->{totalbytes} to 0
			# if not using bitrate limiting, is this what we want?? -andy
			$bitrate = $maxRate * 1000;
			$size    = $duration * $bitrate / 8;
			$offset  = 0;
		}
		
		if ( $bitrate && $duration && $size && abs($bitrate / 8 * $duration - $size) / $size > 0.05 ) {
			warn "openSong: bitrate $bitrate does not concur with duration $duration and size $size";
		}

		$song->{'bitrate'}    = $bitrate if ($bitrate);
		$song->{'samplerate'} = $samplerate if ($samplerate);
		$song->{'samplesize'} = $samplesize if ($samplesize);
		$song->{'channels'}   = $channels if ($channels);

		$song->{'totalbytes'} = $size;
		$song->{'duration'}   = $duration;
		$song->{'offset'}     = $offset;
		$song->{'blockalign'} = $blockalign;

		$client->streamformat($format);

		$log->info("Streaming with format: $format");

		# Deal with the case where we are rewinding and get to
		# this song. In this case, we should jump to the end of
		# the newly opened song.
		if (rate($client) < 0 && !$client->audioFilehandleIsSocket()) {
			# Clear out the song queue to just include this song
			streamingSongIndex($client, streamingSongIndex($client), 1, $song);
			gototime($client, $duration, 1);
			return 1;
		}

	} else {

		logError("[$fullpath] Unrecognized type " . Slim::Music::Info::contentType($fullpath));

		errorOpening($client);
		return undef;
	}

	######################
	# make sure the filehandle was actually set
	if ($client->audioFilehandle() || $directStream) {

		if ($client->audioFilehandle() && $client->audioFilehandle()->opened()) {
			binmode($client->audioFilehandle());
		}

		# XXXX - this really needs to happen in the caller!
		# No database access here. - dsully
		# keep track of some stats for this track
		$track->set('playcount'  => ($track->playcount() || 0) + 1);
		$track->set('lastplayed' => time());
		$track->update();

		Slim::Schema->forceCommit();

	} else {

		# XXX - need to propagate an exception to the caller!
		logError("Can't open [$fullpath] : $!");

		my $line1 = $client->string('PROBLEM_OPENING');
		my $line2 = Slim::Music::Info::standardTitle($client, $track);

		$client->showBriefly( {
			'line' => [$line1, $line2 ]
		}, 5, 1);

		return undef;
	}

	if (!$client->reportsTrackStart()) {

		$client->currentPlaylistChangeTime(Time::HiRes::time());
		Slim::Player::Playlist::refreshPlaylist($client);
	}

	Slim::Control::Request::notifyFromArray($client, ['playlist', 'open', $fullpath]);

	# make sure newsong comes after open, like it does for sbs
	if (!$client->reportsTrackStart()) {

		Slim::Control::Request::notifyFromArray($client, ['playlist', 'newsong', Slim::Music::Info::standardTitle($client, $track), playingSongIndex($client)]);
	}

	return 1;
}

sub readNextChunk {
	my $client = shift;
	my $givenChunkSize = shift;
	
	if ( !$client->readNextChunkOk ) {
		# We're waiting for an async callback, return nothing
		return;
	}

	if (!defined($givenChunkSize)) {
		$givenChunkSize = $prefs->get('udpChunkSize') * 10;
	} 

	my $chunksize = $givenChunkSize;

	my $chunk  = '';

	my $endofsong = undef;

	if ($client->streamBytes() == 0 && $client->masterOrSelf->streamformat() eq 'mp3') {
	
		my $silence = 0;
		# use the maximum silence prelude for the whole sync group...
		foreach my $buddy (Slim::Player::Sync::syncedWith($client), $client) {

			my $asilence = $prefs->client($buddy)->get('mp3SilencePrelude');

			if ($asilence && ($asilence > $silence)) {
				$silence = $asilence;
			}
		}
		
		0 && $log->debug("We need to send $silence seconds of silence...");
		
		while ($silence > 0) {
			$chunk .=  ${Slim::Web::HTTP::getStaticContent("html/lbrsilence.mp3")};
			$silence -= (1152 / 44100);
		}
		
		my $len = length($chunk);
		
		$log->debug("Sending $len bytes of silence.");
		
		$client->streamBytes($len);
		
		return \$chunk if ($len);
	}

	my $song = streamingSong($client);

	if ($client->audioFilehandle()) {

		if (!$client->audioFilehandleIsSocket) {

			# use the rate to seek to an appropriate place in the file.
			my $rate = rate($client);
			
			# if we're scanning
			if ($rate != 0 && $rate != 1) {
				
				if ($client->trickSegmentRemaining()) {

					# we're in the middle of a trick segment
					if ( $log->is_debug ) {
						$log->debug(sprintf("Still in the middle of a trick segment: %d bytes remaining",
							$client->trickSegmentRemaining
						));
					}

				} else {

					# starting a new trick segment, calculate the chunk offset and length
					my $now   = $client->songBytes() + $song->{offset};
					my $url   = Slim::Player::Playlist::song($client, streamingSongIndex($client));
					my $track = Slim::Schema->rs('Track')->objectForUrl($url);

					if (!blessed($track) || !$track->can('bitrate')) {

						logError("Couldn't find object for: [$url]");
						return undef;
					}

					my $byterate = $track->bitrate / 8;

					my $howfar   = int(($rate - $TRICKSEGMENTDURATION) * $byterate);					
					   $howfar  -= $howfar % $song->{blockalign};

					$log->info("Trick mode seeking: $howfar from: $now");

					my $seekpos = $now + $howfar;

					if ($seekpos < 0) {

						$log->info("Trick mode reached beginning of song: $seekpos");

						$endofsong = 1;

						goto bail;						
					}

					my $tricksegmentbytes = int($byterate * $TRICKSEGMENTDURATION);				

					$tricksegmentbytes -= $tricksegmentbytes % $song->{blockalign};

					# Find the frame boundaries for the streaming format, and seek to them.
					if (my $streamClass = streamClassForFormat($client)) {

						my ($start, $end) = $streamClass->findFrameBoundaries(
							$client->audioFilehandle, $seekpos, $tricksegmentbytes
						);

						if ($start == 0 || $end == 0 || $start == $end) {

							$endofsong = 1;

							$log->info("Trick mode couldn't seek: $start/$end");

							goto bail;
						}

						$seekpos  = $start;
						$end += 1 if $streamClass eq 'Slim::Formats::MP3';

						$tricksegmentbytes = $end - $seekpos;
					}

					$log->info("New trick mode segment offset: [$seekpos] for length: [$tricksegmentbytes]");

					$client->audioFilehandle->sysseek($seekpos, 0);
					$client->songBytes($client->songBytes() + $seekpos - $now);
					$client->trickSegmentRemaining($tricksegmentbytes);
				}
								
				if ($chunksize > $client->trickSegmentRemaining()) { 
					$chunksize = $client->trickSegmentRemaining(); 
				}
			}

			# don't send extraneous ID3 data at the end of the file
			my $songLengthInBytes = $song->{'totalbytes'};
			my $pos		      = $client->songBytes() || 0;
			
			if ($pos + $chunksize > $songLengthInBytes) {

				$chunksize = $songLengthInBytes - $pos;

				$log->info("Reduced chunksize to $chunksize at end of file ($songLengthInBytes - $pos)");

				if ($chunksize <= 0) {
					$endofsong = 1;
				}
			}

			if ($pos > $songLengthInBytes) {

				$log->warn("Trying to read past the end of file, skipping to next file.");

				$chunksize = 0;
				$endofsong = 1;
			}
		}

		if ($chunksize > 0) {

			my $readlen = $client->audioFilehandle()->sysread($chunk, $chunksize);

			if (!defined($readlen)) { 

				if ($! == EWOULDBLOCK) {

					#$log->debug("Would have blocked, will try again later.");

					return undef;	

				} elsif ($! == EINTR) {

					$log->debug("Got EINTR, will try again later.");
					return undef;
				} elsif ($! == ECHILD) {
					$log->debug("Got ECHILD - will try again later.");
					return undef;
				} else {

					$log->debug("readlen undef: ($!) " . ($! + 0));

					$endofsong = 1; 
				}	

			} elsif ($readlen == 0) { 

				$log->debug("Read to end of file or pipe");  

				$endofsong = 1;

			} else {

				# too verbose
				# $log->debug("Read $readlen bytes from source");
			}
		}

	} else {

		$log->debug($client->id, ": No filehandle to read from, returning no chunk.");

		return undef;
	}

	# if nothing was read from the filehandle, then we're done with it,
	# so open the next filehandle.
bail:
	if ($endofsong) {

		if ( $log->is_info ) {
			$log->info("end of file or error on socket, opening next song, (song pos: " .
				$client->songBytes . "(tell says: . " . systell($client->audioFilehandle).
				"), totalbytes: " . $song->{totalbytes} . ")"
			);
		}

		if ($client->streamBytes() == 0 && $client->reportsTrackStart()) {

			# If we haven't streamed any bytes, then we can't rely on 
			# the player to tell us when the next track has started,
			# so we manually mark the track as played.

			$log->info("Didn't stream any bytes for this song, so just mark it as played");

			markStreamingTrackAsPlayed($client);
		}
		
		if ( !$client->reportsTrackStart ) {
			# For older players, this is basically the same as a decoder underrun
			# Allow plugins that have onDecoderUnderrun callbacks to be called here
			# for these players
			
			my $callback = sub {
				$client->readNextChunkOk(1);
				if (!gotoNext($client, 1)) {

					if ( $log->is_info ) {
						$log->info($client->id, ": Can't opennext, returning no chunk.");
					}
				}
			};
			
			my $nextSong = nextsong($client);
			if ( defined $nextSong ) {
				my $nextURL = Slim::Player::Playlist::url( $client, $nextSong );
				my $handler = Slim::Player::ProtocolHandlers->handlerForURL( $nextURL );
				if ( $handler && $handler->can('onDecoderUnderrun') ) {
					$handler->onDecoderUnderrun(
						$client,
						$nextURL,
						$callback,
					);
					
					# Flag that we don't want to try to read any more chunks
					# until our callback is called.
					$client->readNextChunkOk(0);
					
					return;
				}
			}
			
			$callback->();
			
			return;
		}
		else {

			if (!gotoNext($client, 1)) {

				if ( $log->is_info ) {
					$log->info($client->id, ": Can't opennext, returning no chunk.");
				}
			}
		
			# we'll have to be called again to get a chunk from the next song.
			return undef;
		}
	}

	my $chunkLength = length($chunk);

	if ($chunkLength > 0) {

		# too verbose
		# $log->debug("Read a chunk of $chunkLength length");

		$client->songBytes($client->songBytes() + $chunkLength);
		$client->streamBytes($client->streamBytes() + $chunkLength);

		if ($client->trickSegmentRemaining) {

			$client->trickSegmentRemaining($client->trickSegmentRemaining - $chunkLength);
		}
	}

	return \$chunk;
}

sub streamClassForFormat {
	my ( $client, $streamFormat ) = @_;

	$streamFormat ||= $client->streamformat;

	if (Slim::Formats->loadTagFormatForType($streamFormat)) {

		my $streamClass = Slim::Formats->classForFormat($streamFormat);

		if ($streamClass && $streamClass->can('findFrameBoundaries')) {

			return $streamClass;
		}
	}
}

sub pauseSynced {
	my $client = shift;

	foreach my $everyclient ($client, Slim::Player::Sync::syncedWith($client)) {

		next if ($prefs->client($everyclient)->get('silent'));

		$everyclient->pause();

	}
}

use constant FRAME_BYTE_OFFSET => 0;
use constant FRAME_TIME_OFFSET => 1;

sub streamBitrate {
	my $client = Slim::Player::Sync::masterOrSelf($_[0]);

	# Only do this for sync play, although there is no real reason not to do it otherwise
	# Need to change this if we allow clients to join in mid song.
	if( !Slim::Player::Sync::isSynced($client) ) {
		return 0;
	}

	my $song = streamingSong($client);

	# already know the answer
	my $rate = $song->{'bitrate'};
	if ( defined $rate ) {
		return $rate;
	}

	my $format = $client->streamformat();
	
	if ( $format eq 'mp3' ) {
		my $frames = $client->frameData();
		if ( @{$frames} > 1 ) {
			$rate = $frames->[-1][FRAME_BYTE_OFFSET] / $frames->[-1][FRAME_TIME_OFFSET] * 8;
		}
	}
	elsif ( $format eq 'wav' ) {
		# assume 44.1k, 16-bit, stereo
		$rate = ($song->{'samplerate'} || 44100) * ($song->{'samplesize'} || 16) 
				* ($song->{'channels'} || 2);
		$song->{'bitrate'} = $rate; # save for later
	}

	return $rate;
}


sub resetFrameData {
	my ($client) = @_;
	return unless Slim::Player::Sync::isMaster($client);

	$client->initialStreamBuffer(undef);
	$client->frameData(undef);
}
	
sub purgeOldFrames {
	my $frames     = $_[0]->frameData() or return;
	my $timeOffset = $_[1];

	my ($i, $j, $k) = (0, @{$frames} - 1);

	# sanity checks
	return if $timeOffset < $frames->[$i][FRAME_TIME_OFFSET];
	if ( $timeOffset > $frames->[$j][FRAME_TIME_OFFSET] ) {
		$log->debug("purgeOldFrames: timeOffset $timeOffset beyond last entry: $frames->[$j][FRAME_TIME_OFFSET]");
		return;
	}

	# weighted binary chop
	while ( ($j - $i) > 1 ) {
		$k = int ( ($i + $j) / 2 );
		# $k = $i + (int(($timeOffset - $frames->[$i][FRAME_TIME_OFFSET]) / ($frames->[$j][FRAME_TIME_OFFSET] - $frames->[$i][FRAME_TIME_OFFSET]) * ($j - $i)) || 1);
		if ( $timeOffset < $frames->[$k][FRAME_TIME_OFFSET] ) {
			$j = $k;
		}
		else {
			$i = $k;
		}
	}
	
	if ( $log->is_debug ) {
		$log->debug(
			"purgeOldFrames: timeOffset $timeOffset; removing "
			. ($j+1) . " frames from total " . scalar(@{$frames}) 
		);
	}
	
	splice @{$frames}, 0, $j+1;	
}

sub findTimeForOffset {
	my $client     = Slim::Player::Sync::masterOrSelf($_[0]);
	my $byteOffset = $_[1];
	my $buffer     = $client->initialStreamBuffer() or return;
	my $frames     = $client->frameData();

	return unless $byteOffset;

	# check if there are any frames to analyse
	if ( length($$buffer) > 1500 ) { # make it worth our while
	
		my $pos = 0;

		while ( my ($length, $nextPos, $seconds) = MPEG::Audio::Frame->read_ref($buffer, $pos) ) {
			last unless ($length);
			# Note: $length may not equal ($nextPos - $pos) if tag data has been skipped
			if ( !defined($frames) ) {
				$client->frameData( $frames = [[$nextPos - $length, 0]] );
				push @{$frames}, [$nextPos, $seconds];
			}
			else {
				my $off = $frames->[-1][FRAME_BYTE_OFFSET] + $nextPos - $pos;
				my $tim = $frames->[-1][FRAME_TIME_OFFSET] + $seconds;
				push @{$frames}, [$off, $tim];
			}
			
			if ( $log->is_info && ($length != $nextPos - $pos) ) {
				$log->info("recordFrameOffset: ", $nextPos - $pos - $length, " bytes skipped");
			}
			$pos = $nextPos;

			if ( $log->is_debug ) {
				$log->debug("recordFrameOffset: $frames->[-1][FRAME_BYTE_OFFSET] -> $frames->[-1][FRAME_TIME_OFFSET]");
			}
		}

		if ($pos) {
			my $newBuffer = substr $$buffer, $pos;
			$client->initialStreamBuffer(\$newBuffer);
		} else {
			$log->info("recordFrameOffset: found no frames in buffer length ", length($$buffer));
		}
	}

	return unless ( defined @{$frames} && @{$frames} > 1 );

	my ($i, $j, $k) = (0, @{$frames} - 1);

	# sanity check
	unless ($frames->[$i][FRAME_BYTE_OFFSET] <= $byteOffset && $byteOffset <= $frames->[$j][FRAME_BYTE_OFFSET]) {
		$log->debug("findTimeForOffset: byteOffset $byteOffset outside frame range: $frames->[$i][FRAME_BYTE_OFFSET] .. $frames->[$j][FRAME_BYTE_OFFSET]");
		return;
	}

	# weighted binary chop
	while ( ($j - $i) > 1 ) {
		$k = int ( ($i + $j) / 2 );
		use integer;
		# $k = $i + (int(($j - $i) * ($byteOffset - $frames->[$i][FRAME_BYTE_OFFSET]) / ($frames->[$j][FRAME_BYTE_OFFSET] - $frames->[$i][FRAME_BYTE_OFFSET])) || 1);
		if ( $byteOffset < $frames->[$k][FRAME_BYTE_OFFSET] ) {
			$j = $k;
		}
		else {
			$i = $k;
		}
	}
	
	my $frameByteOffset = $frames->[$i][FRAME_BYTE_OFFSET];
	my $timeOffset = $frames->[$i][FRAME_TIME_OFFSET];
	if ( $byteOffset > $frameByteOffset && @{$frames} - 1 > $i ) {
		# interpolate within a frame
		$timeOffset += ($byteOffset - $frameByteOffset) /
			  ($frames->[$i+1][FRAME_BYTE_OFFSET] - $frameByteOffset)
			* ($frames->[$i+1][FRAME_TIME_OFFSET] - $timeOffset);
	}

	$log->debug("findTimeForOffset: $byteOffset -> $timeOffset");

	return $timeOffset;
}

1;
