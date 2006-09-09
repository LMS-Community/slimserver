package Slim::Player::Source;

# $Id$

# SlimServer Copyright (C) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use File::Spec::Functions qw(:ALL);
use FileHandle;
use FindBin qw($Bin);
use IO::Socket qw(:DEFAULT :crlf);
use Scalar::Util qw(blessed);
use Time::HiRes;
use Fcntl qw(SEEK_CUR);
use bytes;

BEGIN {
	if ($^O =~ /Win32/) {
		*EWOULDBLOCK = sub () { 10035 };
		*EINPROGRESS = sub () { 10036 };
	} else {
		require Errno;
		import Errno qw(EWOULDBLOCK EINPROGRESS);
	}
}

use Slim::Formats;
use Slim::Control::Request;
use Slim::Formats::Playlists;
use Slim::Player::Pipeline;
use Slim::Player::ProtocolHandlers;
use Slim::Player::ReplayGain;
use Slim::Player::TranscodingHelper;
use Slim::Utils::Misc;
use Slim::Utils::Network;
use Slim::Utils::OSDetect;

my $TRICKSEGMENTDURATION = 1.0;
my $FADEVOLUME         = 0.3125;

use constant STATUS_STREAMING => 0;
use constant STATUS_PLAYING => 1;

sub systell {
	$_[0]->sysseek(0, SEEK_CUR) if $_[0]->can('sysseek');
}

sub init {
	Slim::Player::TranscodingHelper::loadConversionTables();

	Slim::Networking::Slimproto::setEventCallback('STMu', \&underrun);
	Slim::Networking::Slimproto::setEventCallback('STMd', \&decoderUnderrun);
	Slim::Networking::Slimproto::setEventCallback('STMs', \&trackStartEvent);
	Slim::Networking::Slimproto::setEventCallback('STMn', \&notSupported);
}

# rate can be negative for rew, zero for pause, 1 for playback and greater than one for ffwd
sub rate {
	my ($client, $newrate) = @_;

	unless (defined $newrate) {
		return $client->rate();
	}

	my $oldrate = $client->rate();

	# restart playback if we've changed and we're not pausing or unpauseing
	if ($oldrate != $newrate) {

		if ($::d_source || $::d_source_v) {

			msg("switching rate from $oldrate to $newrate\n");

			bt() if $::d_source_v;
		}

		my $time = songTime($client);

		$client->rate($newrate);

	 	if ($newrate == 0) {
			playmode($client, "pausenow");
		} else {
			$::d_source && msg("rate change, jumping to the current position in order to restart the stream\n");
			gototime($client, $time);
		}
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

	$::d_source && msg("time2offset: $time to $offset (align: $align size: $size duration: $duration)\n");

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
	my $startStream = $client->songStartStreamTime();
	
	$::d_source_v && msg("songTime: rate:$rate -songtime:$songtime -startStream:$startStream\n");

	return $songtime+$startStream if $rate == 1 && defined($songtime);

	# this used to check against == 1, however, we can't properly
	# calculate duration for non-native formats (pcm, mp3) unless we treat
	# the file as streaming. do this for all files right now.
	if ($client->audioFilehandleIsSocket()) {

		my $startTime = $client->remoteStreamStartTime();
		my $endTime   = $client->pauseTime() || Time::HiRes::time();
		
		if ($startTime) {
			return $endTime - $startTime;
		} else {
			return 0;
		}
	}

	my $song     		= playingSong($client);
	my $songLengthInBytes	= $song->{totalbytes};
	my $duration	  	= $song->{duration};
	my $byterate	  	= $duration ? ($songLengthInBytes / $duration) : 0;

	my $bytesReceived 	= ($client->bytesReceived() || 0) - $client->bytesReceivedOffset();
	my $fullness	  	= $client->bufferFullness() || 0;
	my $realpos		= 0;
	my $outputBufferSeconds = 0;

	if (playingSongIndex($client) == streamingSongIndex($client)) {
		$realpos = $bytesReceived - $fullness;

		# XXX We use outputBufferFullness to compute the number of
		# seconds of the current track left in the output
		# buffer. However, we can only trust this value if we haven't
		# yet started streaming the next track. This is bad, since the
		# songtime we display will be pegged to the duration of the
		# track from the time we start streaming the next song till we
		# play out the current song. This can be fixed by adjusting
		# the protocol to give us the remaining seconds for the
		# currently playing track.

		my $outputBufferFullness = $client->outputBufferFullness();
		if (defined($outputBufferFullness)) {
			# Assume 44.1KHz output sample rate. This will be slightly
			# off for anything that's 48Khz, but it's a guesstimate anyway.
			$outputBufferSeconds = (($outputBufferFullness / (44100 * 8)) * $rate);
		}
	}
	# If we're moving forward and have started streaming the next
	# track, the fullness metric can no longer be used to determine
	# how far into the track we are. So say that we're done with it.
	elsif ($rate >= 1) {
		$realpos = $songLengthInBytes;
		$rate = 1;
		$startStream = 0;
	}

	if ($realpos < 0) {
		$::d_source && msg("Negative position calculated, we are still playing out the previous song.\n");	
		$::d_source && msg("realpos $realpos calcuated from bytes received: " . 
			$client->bytesReceived() . 
			" minus buffer fullness: " . $client->bufferFullness() . "\n");

		$realpos = 0;
	}

	$songtime = $songLengthInBytes ? (($realpos / $songLengthInBytes * $duration * $rate) + $startStream - $outputBufferSeconds) : 0;

	# The songtime should never be negative
	if ($songtime < 0) {
		$songtime = 0;
	}

	if ($songtime && $duration) {
		0 && $::d_source && msg("songTime: [$songtime] = ($realpos(realpos) / $songLengthInBytes(size) * ".
			"$duration(duration) * $rate(rate)) + $startStream(time offset of started stream)\n");
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

	if ($::d_source || $::d_source_v) {

		msg($client->id() . ": Switching to mode $newmode from $prevmode\n");

		bt() if $::d_source_v;
	}

	# don't switch modes if it's the same 
	if ($newmode eq $prevmode && !$seekoffset) {

		$::d_source && msg(" Already in playmode $newmode : ignoring mode change\n");

		return _returnPlayMode($client);
	}
	
	my $currentURL = Slim::Player::Playlist::url($client, streamingSongIndex($client));
	# Some protocol handlers don't allow pausing of active streams.
	# We check if that's the case before continuing.
	if ($newmode eq "pause" && defined($currentURL)) {

		my $handler = Slim::Player::ProtocolHandlers->handlerForURL($currentURL);

		if ($handler && $handler->can("canDoAction") &&
			!$handler->canDoAction($client, $currentURL, 'pause')) {

			$::d_source && msg("Protocol handler doesn't allow pausing.  Let's try stopping.\n");
			return playmode($client, "stop", $seekoffset);
		}
	}

	if ($newmode eq "play" && $prevmode eq "pause") {
		$newmode = "resume";
	}
	
	# This function is likely doing too much.
	if ($newmode eq "pause" && $client->rate != 1) {
		$newmode = "pausenow";
	}
	
	# notify parent of new playmode
	$client->sendParent( {
		command  => 'playmode',
		playmode => $newmode,
	} );
	
	# if we're playing, then open the new song the master.		
	if ($newmode eq "resume") {

		# if the player is off, we automatically power on when we start to play
		if (!$client->power()) {
			$client->power(1);
		}
	}

	# if we're playing, then open the new song the master.		
	if ($newmode eq "play") {

		# if the player is off, we automatically power on when we start to play
		if (!$client->power()) {
			$client->power(1);
		}
		
		# if we couldn't open the song, then stop...
		my $opened = openSong($master, $seekoffset) || do {

			# If there aren't anymore items in the
			# playlist - just return, don't try and play again.
			if (noMoreValidTracks($client)) {

				$::d_source && msg("playmode: No more valid tracks on the playlist. Stopping.\n");

				$newmode = 'stop';

			} else {

				# Otherwise, try and open the next item on the list.
				trackStartEvent($client);

				if (!gotoNext($client,1)) {

					# Still couldn't open? Stop the player.
					errorMsg("playmode: Couldn't gotoNext song on playlist, stopping\n");
					$newmode = 'stop';
				}
			}
		};

		$client->bytesReceivedOffset(0);
	}
	
	# when we change modes, make sure we do it to all the synced clients.
	foreach my $everyclient ($client, Slim::Player::Sync::syncedWith($client)) {

		$::d_source && msg($everyclient->id() . " New play mode: " . $newmode . "\n");

		next if $everyclient->prefGet('silent');

		# set up a callback to handle repeat changes during buffer drain
		if ($newmode =~ /^playout/) {
			Slim::Control::Request::subscribe(\&repeatCallback,[['playlist'],['repeat']]);
		} else {
			Slim::Control::Request::unsubscribe(\&repeatCallback);
		}

		# when you resume, you go back to play mode
		if (($newmode eq "resume") ||($newmode eq "resumenow")) {

			$everyclient->resume();
			
			my $song = Slim::Player::Source::streamingSong($client);
			my $songLengthInBytes = $song->{totalbytes};
			my $pos		      = $client->songBytes() || 0; 
			
			$::d_source && msg("resume: (pos: " . $client->songBytes() . ", totalbytes: " . $song->{totalbytes} . ")\n");
			
			# if song pos matches totalbytes, previous playmode was playout-play
			if ($songLengthInBytes - $pos == 0) {
				$everyclient->playmode("playout-play");
			} else {
				$everyclient->playmode("play");
			}
			
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

			$everyclient->currentplayingsong("");

			$::d_source && msg("Stopping and clearing out old chunks for client " . $everyclient->id() . "\n");

			@{$everyclient->chunks} = ();

			$everyclient->stop();
			closeSong($everyclient);
			resetSong($everyclient);
			resetSongQueue($everyclient);

		} elsif ($newmode eq "play") {

			$everyclient->readytosync(0);
			if ($everyclient->prefGet('syncVolume')) {
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
			
			$everyclient->play(
				$paused,
				$master->streamformat(),
				$currentSong,
				(defined($seekoffset) && $seekoffset > 0),
				$master->shouldLoop,
				Slim::Player::ReplayGain->fetchGainMode($master),
			);

		} elsif ($newmode eq "pause") {

			# since we can't count on the accuracy of the fade
			# timers, we unfade them all, but the master calls
			# back to pause everybody
			if ($everyclient eq $client) {
				$everyclient->fade_volume(-$FADEVOLUME, \&pauseSynced, [$client]);
			} else {
				$everyclient->fade_volume(-$FADEVOLUME);
			}				
			
		} elsif ($newmode eq "pausenow") {

			$everyclient->pause();

		} elsif ($newmode eq "resumenow") {

			if ($everyclient->prefGet('syncVolume')) {
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

			$::d_source && msg(" Unknown play mode: " . $everyclient->playmode . "\n");
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
	
	$::d_source && msg($client->id() . ": Current playmode: $newmode\n");
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

	$::d_source && msg($client->id() . ": Decoder underrun while this mode: " . $client->playmode() . "\n");
	
	if (!Slim::Player::Sync::isSynced($client) &&
		($client->rate() == 0 || $client->rate() == 1) &&
		($client->playmode eq 'playout-play')) {
		skipahead($client);
	}
}

sub underrun {
	my $client = shift || return;
	
	$client->readytosync(-1);
	
	$::d_source && msg($client->id() . ": Underrun while this mode: " . $client->playmode() . "\n");

	# if we're synced, then we tell the player to stop and then let resync restart us.

	if (Slim::Player::Sync::isSynced($client)) {
		if ($client->playmode =~ /playout/) {
			$client->stop();
		}
	} elsif ($client->playmode eq 'playout-play') {

		skipahead($client);

	} elsif ($client->playmode eq 'playout-stop') {

		playmode($client, 'stop');
		streamingSongIndex($client, 0, 1);
		$client->currentPlaylistChangeTime(time());
		Slim::Player::Playlist::refreshPlaylist($client);
		$client->update();
		
		Slim::Control::Request::notifyFromArray($client, ['stop']);
	}
}

sub notSupported {
	my $client = shift || return;
	
	$::d_source && msg("Error: Decoder does not support file format, skipping track\n");
	
	errorOpening($client);
}

sub skipahead {
	my $client = shift;

	if (!$client->reportsTrackStart() || 
		Slim::Player::Sync::isSynced($client)) {
		$::d_source && msg("**skipahead: stopping\n");
		playmode($client, 'stop');
	}

	$::d_source && msg("**skipahead: opening next song\n");
	my $succeeded = gotoNext($client, 0);

	if ($succeeded) {
		$::d_source && msg("**skipahead: restarting\n");
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
			$::d_source && msg("Found an empty chunk on the queue - this means we should drop the streaming connection.\n");
			Slim::Web::HTTP::forgetClient($client);
			$chunk = undef;
		}

	} else {
		#otherwise, read a new chunk
		my $readfrom = Slim::Player::Sync::masterOrSelf($client);
			
		$chunk = readNextChunk($readfrom, $maxChunkSize);
			
		if (defined($chunk)) {

			$len = length($$chunk);

			if ($len) {
				# let everybody I'm synced with use this chunk
				foreach my $buddy (Slim::Player::Sync::syncedWith($client)) {
					push @{$buddy->chunks}, $chunk;
				}
			}
		}
	}
	
	if (defined($chunk) && ($len > $maxChunkSize)) {
		0 && $::d_source && msg("chunk too big, pushing the excess for later.\n");

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
		$::d_source && msg("gototime: relative jump $newtime from current time $oldtime\n");
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

	$::d_source && msg("gototime: going to time $newtime\n");

	# skip to the previous or next track as necessary
	# XXXX FIXME
	# Fred Sept 1 2006: does not seem to be possible for time2offset to return
	# an offset outside the song. (Apparently, findFrameBoundaries can't do
	# that), so the code below is useless.
	if ($newoffset > $songLengthInBytes) {

		my $rate = rate($client);
		jumpto($client, "+1");
		rate($client, $rate);
		$newtime = ($newoffset - $songLengthInBytes) * $duration / $songLengthInBytes;
		$::d_source && msg("gototime: skipping forward to the next track to time $newtime\n");
		gototime($client, $newtime);
		return;

	} elsif ($newoffset < 0) {

		my $rate = rate($client);

		while ($newtime < 0) {
			jumpto($client, "-1");
			rate($client, $rate);
			$newtime = $song->{duration} - ((-$newoffset) * $duration / $songLengthInBytes);
			$::d_source && msg("gototime: skipping backwards to the previous track to time $newtime\n");
		}

		gototime($client, $newtime);
		return;

	} elsif (playingSongIndex($client) != streamingSongIndex($client)) {

		my $rate = rate($client);
		jumpto($client, playingSongIndex($client));
		rate($client, $rate);
		$::d_source && msg("gototime: resetting to the track that's currently playing (but no longer streaming)\n");
		gototime($client, $newtime, $rangecheck);
		return;
	}

	foreach my $everybuddy ($client, Slim::Player::Sync::slaves($client)) {
		$::d_source && msg("gototime: stopping playback\n");
		next if ($everybuddy->prefGet('silent'));
		$everybuddy->stop();
		@{$everybuddy->chunks} = ();
	}

	my $dataoffset = $song->{offset};

	$client->songBytes($newoffset);
	$client->songStartStreamTime($newtime);
	$client->bytesReceivedOffset(0);
	$client->trickSegmentRemaining(0);

	$client->audioFilehandle()->sysseek($newoffset + $dataoffset, 0);

	foreach my $everybuddy ($client, Slim::Player::Sync::slaves($client)) {

		next if ($everybuddy->prefGet('silent'));

		$::d_source && msg("gototime: restarting playback\n");

		$everybuddy->readytosync(0);
		
		my $paused = ( Slim::Player::Sync::isSynced($client) ) ? 1 : 0;

		$everybuddy->play(
			$paused,
			$client->streamformat(),
			Slim::Player::Playlist::song($client),
			0,
			$client->shouldLoop,
			Slim::Player::ReplayGain->fetchGainMode($client),
		);

		$everybuddy->playmode("play");
	}
}

# jumpto - set the current song to a given offset
sub jumpto {
	my $client = Slim::Player::Sync::masterOrSelf(shift);
	my ($offset, $noplay) = @_;

	my ($songcount) = Slim::Player::Playlist::count($client);

	if ($songcount == 0) {
		return;
	}
	
	if ($offset && $offset =~ /([\+\-])(\d+)/ && ($1 eq '-' || $2 eq '0')) {

		my $currentURL = Slim::Player::Playlist::url($client, streamingSongIndex($client));
		my $handler = Slim::Player::ProtocolHandlers->handlerForURL($currentURL);

		if ($handler && 
			$handler->can("canDoAction") &&
			!$handler->canDoAction($client, $currentURL, 'rew')) {
			return;
		}
	}

	playmode($client,"stop");

	if ($songcount != 1) {

		my $index;

		if (defined $offset && $offset =~ /[\+\-]\d+/) {
			$index = playingSongIndex($client) + $offset;
			$::d_source && msgf("jumping by %s\n", $offset);
		} else {
			$index = $offset || 0;
			$::d_source && msgf("jumping to %s\n", $offset);
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

	$client->currentPlaylistChangeTime(time());
	Slim::Buttons::Common::syncPeriodicUpdates($client, Time::HiRes::time() + 0.1);
	
	playmode($client,"play") unless $noplay;
}


################################################################################
# Private functions below. Do not call from outside this module.
################################################################################

# gotoNext returns 1 if it succeeded opening a new song, 
#                  0 if it stopped at the end of the list or failed to open the current song 
# note: Only call this with a master or solo client
sub gotoNext {
	$::d_source && msg("opening next song...\n"); 
	my $client = shift;
	my $open = shift;
	my $result = 1;
	
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
		
		# here's where we decide whether to start the next song in a new stream after playing out
		# the current song or to just continue streaming
		if (($client->playmode() eq 'play') && 
			(($oldstreamformat ne $newstreamformat) || 
			Slim::Player::Sync::isSynced($client) || 
			 $client->isa("Slim::Player::Squeezebox2") ||
			($client->rate() != 1))) {

			$::d_source && msg(
				"playing out before starting next song. (old format: " .
				"$oldstreamformat, new: $newstreamformat)\n"
			);

			playmode($client, 'playout-play');
			
			# We're done streaming the song, so drop the streaming
			# connection to the client.
			dropStreamingConnection($client);

			return 0;

		} else {
			
			# Reuse the connection for the next song, for SB1, HTTP streaming

			$::d_source && msg(
				"opening next song (old format: $oldstreamformat, " .
				"new: $newstreamformat) current playmode: " . playmode($client) . "\n"
			);
			
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
		$::d_source && msg("No pending chunks - we're dropping the streaming connection\n");
		Slim::Web::HTTP::forgetClient($client);
	}
	else {
		$::d_source && msg("There are pending chunks - queue an empty chunk and wait till the chunk queue is empty before dropping the connection.\n");
		push @{$client->chunks}, \'';
	}
	foreach my $buddy (Slim::Player::Sync::syncedWith($client)) {
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
		$::d_source && msg("Adding song index $index to song queue\n");
		if (!$client->reportsTrackStart() || $clear || Slim::Player::Sync::isSynced($client)) {
			$::d_source && msg("Clearing out song queue first\n");
			$#{$queue} = -1;
		}
		
		if (defined($song)) {
			unshift(@{$queue}, $song);
		}
		else {
			unshift(@{$queue}, { index => $index, 
								 status => STATUS_STREAMING});
		}
		$::d_source && msg("Song queue is now " . join(',', map { $_->{index} } @$queue) . "\n");
		
		# notify parent of new queue
		$client->sendParent( {
			command => 'currentsongqueue',
			queue   => $client->currentsongqueue(),
		} );
	}

	$song = $client->currentsongqueue()->[0];
	return 0 if !defined($song);

	return $song->{index};
}

sub streamingSong {
	my $client = Slim::Player::Sync::masterOrSelf(shift);
	unless (scalar(@{$client->currentsongqueue()})) {
		streamingSongIndex($client, 0);
	}
	return $client->currentsongqueue()->[0];
}

sub playingSongIndex {
	my $client = Slim::Player::Sync::masterOrSelf(shift);

	my $song = playingSong($client);
	return 0 if !defined($song);

	return $song->{index};
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

	$::d_source && msg("Resetting song queue\n");
	my $playingsong = $client->currentsongqueue()->[-1];
	$playingsong->{status} = STATUS_STREAMING;
	$#{$queue} = -1;
	push @$queue, $playingsong;
	$::d_source && msg("Song queue is now " . join(',', map { $_->{index} } @$queue) . "\n");
	
	# update CURTRACK of a known playlist back to start
	my $request = Slim::Control::Request->new( 
					(blessed($client) ? $client->id() : undef));
	$request->addParam('reset',1);
	Slim::Player::Playlist::newSongPlaylistCallback($request);
	
	$client->sendParent( {
		command => 'currentsongqueue',
		queue   => $client->currentsongqueue(),
	} );
}

sub markStreamingTrackAsPlayed {
	my $client = shift;

	my $song = streamingSong($client);
	if (defined($song)) {
		$song->{status} = STATUS_PLAYING;
	}
	
	$client->sendParent( {
		command => 'currentsongqueue',
		queue   => $client->currentsongqueue(),
	} );
}

sub trackStartEvent {
	my $client = Slim::Player::Sync::masterOrSelf(shift) || return;

	$::d_source && msg("Got a track starting event\n");
	my $queue = $client->currentsongqueue();
	my $last_song = $queue->[-1];

	while (defined($last_song) && $last_song->{status} == STATUS_PLAYING && 
		   scalar(@$queue) > 1) {
		$::d_source && msg("Song " . $last_song->{index} . " had already started, so it's not longer in the queue\n");
		pop @{$queue};
		$last_song = $queue->[-1];

		# reset value used to calculate time in song if we change song.
		# This works because gototime cannot skip song, otherwise it wouldn't.
		$client->songStartStreamTime(0);
	}
	
	if (defined($last_song)) {
		$::d_source && msg("Song " . $last_song->{index} . " has now started playing\n");
		$last_song->{status} = STATUS_PLAYING;
	}

	$client->currentPlaylistChangeTime(time());
	Slim::Player::Playlist::refreshPlaylist($client);
	Slim::Control::Request::notifyFromArray($client, ['playlist', 'newsong']);

	$::d_source && msg("Song queue is now " . join(',', map { $_->{index} } @$queue) . "\n");
}

# nextsong is for figuring out what the next song will be.
sub nextsong {
	my $client = shift;

	my $nextsong;
	my $currsong = streamingSongIndex($client);
	
	return 0 if (Slim::Player::Playlist::count($client) == 0);
	
	my $direction = 1;
	
	if ($client->rate() < 0) { $direction = -1; }
	 
	$nextsong = streamingSongIndex($client) + $direction;

	if ($nextsong >= Slim::Player::Playlist::count($client)) {

		# play the next song and start over if necessary
		if (Slim::Player::Playlist::shuffle($client) && 
			Slim::Player::Playlist::repeat($client) == 2 &&
			Slim::Utils::Prefs::get('reshuffleOnRepeat')) {
			
				Slim::Player::Playlist::reshuffle($client, 1);
		}

		$nextsong = 0;
	}
	
	if ($nextsong < 0) {
		$nextsong = Slim::Player::Playlist::count($client) - 1;
	}
	
	$::d_source && msg("the next song is number $nextsong, was $currsong\n");
	
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

# this is called by opensong before opening the new song. Because of the 
# buffer, this happens 20 secs or so before the new song can be heard. All
# counters used for "time display" should not be cleared at that time.
sub resetSong {
	my $client = shift;

	$::d_source && msg("resetSong\n");

	$client->songBytes(0);
	$client->bytesReceivedOffset($client->bytesReceived());
	$client->trickSegmentRemaining(0);
	
	$client->sendParent( {
		command => 'resetSong',
	} );
}

sub errorOpening {
	my $client = shift;

	if ($client->reportsTrackStart()) {
		$::d_source && msg("Error opening current track, so mark it as already played\n");
		markStreamingTrackAsPlayed($client);
	}
	
	my $line1 = shift || $client->string('PROBLEM_OPENING');
	my $line2 = Slim::Music::Info::standardTitle($client, Slim::Player::Playlist::song($client, streamingSongIndex($client)));
	
	$client->showBriefly($line1, $line2, 5, 1, 1);
}

sub explodeSong {
	my $client = shift;
	my $tracks = shift;

	# insert the list onto the playlist
	splice @{Slim::Player::Playlist::playList($client)}, streamingSongIndex($client), 1, @{$tracks};

	# update the shuffle list
	Slim::Player::Playlist::reshuffle($client);
}

sub openSong {
	my $client = shift;
	my $seekoffset = shift || 0;

	my $directStream = 0;

	resetSong($client);
	
	closeSong($client);

	my $song     = streamingSong($client);
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

			errorMsg("openSong: Error finding an object for [$objOrUrl]!\n");

			return undef;
		}
	}

	my $fullpath = $track->url;

	$::d_source && msg("openSong on: $fullpath\n");

	####################
	# parse the filetype
	if (Slim::Music::Info::isRemoteURL($fullpath)) {

		if ($client->canDirectStream($fullpath)) {

			$directStream = 1;
			$client->streamformat(Slim::Music::Info::contentType($track));
		}

		if (!$directStream) {

			$::d_source && msg("openSong: URL is remote [$fullpath]\n");
			
			my $sock = Slim::Player::ProtocolHandlers->openRemoteStream($fullpath, $client);
	
			if ($sock) {
				
				my $contentType = Slim::Music::Info::mimeToType($sock->contentType) || $sock->contentType;
	
				# if it's an audio stream, try to stream,
				# either directly, or via transcoding.
				if (Slim::Music::Info::isSong($track, $contentType)) {
	
					$::d_source && msg("openSong: remoteURL is a song : $fullpath\n");
	
					if ($sock->opened() && !defined(Slim::Utils::Network::blocking($sock, 0))) {

						$::d_source && msg("openSong: Cannot set remote stream nonblocking for url: [$fullpath]\n");

						errorOpening($client);

						return undef;
					}
	
					# XXX: getConvertCommand is already called above during canDirectStream
					# We shouldn't run it twice...
					my ($command, $type, $format) = Slim::Player::TranscodingHelper::getConvertCommand(
						$client, $track, $contentType,
					);

					if (!defined $command) {

						$::d_source && msg("openSong: Couldn't create command line for $type playback for [$fullpath]\n");

						errorOpening($client);

						return undef;
					}

					if ($::d_source) {
						msg("openSong: remoteURL command $command type $type format $format\n");
						msg("openSong: remoteURL stream format : $contentType\n");
					}

					$client->streamformat($format);
	
					# this case is when we play the file through as-is
					if ($command eq '-') {

						$client->audioFilehandle($sock);
						$client->audioFilehandleIsSocket(1);

					} else {

						my $maxRate = Slim::Utils::Prefs::maxRate($client);
						my $quality = $client->prefGet('lameQuality');
						
						$command = Slim::Player::TranscodingHelper::tokenizeConvertCommand(
							$command, $type, '-', $fullpath, 0 , $maxRate, 1, $quality
						);

						if (!defined($command)) {

							$::d_source && msg("openSong: Couldn't create command line for $type playback for [$fullpath]\n");

							errorOpening($client);
							
							return undef;
						}

						$::d_source && msg("openSong: Tokenized command $command\n");

						my $pipeline = Slim::Player::Pipeline->new($sock, $command);

						if (!defined($pipeline)) {

							$::d_source && msg("openSong: Error creating conversion pipeline for: [$fullpath]\n");
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
	
					$::d_source && msg("openSong: don't know how to handle content for [$fullpath]\n");

					$sock->close();
					$sock = undef;

					$client->audioFilehandle(undef);
				}

			} else { 

				$::d_source && msg("openSong: Remote stream failed to open [$fullpath].\n");

				$client->audioFilehandle(undef);

				# XXX - this should be moved elsewhere!
				# Source.pm shouldn't be setting the display!
				my $line1 = $client->string('PROBLEM_CONNECTING');
				my $line2 = Slim::Music::Info::standardTitle($client, $track);
	
				$client->showBriefly($line1, $line2, 5, 1);
	
				return undef;
			}
		}

	} elsif (Slim::Music::Info::isSong($track)) {
	
		my $filepath = $track->path;

		my ($size, $duration, $offset, $samplerate, $blockalign, $endian,$drm) = (0, 0, 0, 0, 0, undef,undef);
		
		# don't try and read this if we're a pipe
		if (!-p $filepath) {

			# XXX - endian can be undef here - set to ''.
			$size       = $track->audio_size() || -s $filepath;
			$duration   = $track->durationSeconds();
			$offset     = $track->audio_offset() || 0 + $seekoffset;
			$samplerate = $track->samplerate();
			$blockalign = $track->block_alignment() || 1;
			$endian     = $track->endian() || '';
			$drm        = $track->drm();

			$::d_source && msg("openSong: duration: [$duration] size: [$size] endian [$endian] offset: [$offset] for $fullpath\n");

			if ($drm) {

				$::d_source && msg("openSong: [$fullpath] is rights protected. skipping.\n");
				errorOpening($client);
				return undef;
			}

			if (!$size && !$duration) {

				$::d_source && msg("openSong: [$fullpath] not bothering opening file with zero size or duration\n");
				errorOpening($client);
				return undef;
			}
		}

		# smart bitrate calculations
		my $rate    = ($track->bitrate || 0) / 1000;

		# if http client has used the query param, use transcodeBitrate. otherwise we can use maxBitrate.
		my $maxRate = Slim::Utils::Prefs::maxRate($client);

		my ($command, $type, $format) = Slim::Player::TranscodingHelper::getConvertCommand($client, $track);

		if ($::d_source) {
			msg("openSong: this is an $type file: $fullpath\n");
			msg("  file type: $type format: $format inrate: $rate maxRate: $maxRate\n");
			msg("  command: $command\n");
		}

		if (!defined($command)) {

			$::d_source && msg("openSong: Couldn't create command line for $type playback for [$fullpath]\n");

			errorOpening($client);

			return undef;
		}

		# this case is when we play the file through as-is
		if ($command eq '-') {

			# hack for little-endian aiff.
			$format = "wav" if $format eq "aif" && defined($endian) && !$endian;

			$client->audioFilehandle( FileHandle->new() );		

			$::d_source && msg("openSong: opening file $filepath\n");

			if ($client->audioFilehandle->open($filepath)) {

				$::d_source && msg("openSong: seeking in $offset into $filepath\n");

				if ($offset) {
					if (!defined(sysseek($client->audioFilehandle, $offset, 0))) {
						msg("openSong: couldn't seek to $offset for $filepath");
					};
					$offset -= $seekoffset;
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

			my $quality = $client->prefGet('lameQuality');

			$command = Slim::Player::TranscodingHelper::tokenizeConvertCommand(
				$command, $type, $filepath, $fullpath, $samplerate, $maxRate, undef, $quality
			);

			$client->audioFilehandle( FileHandle->new() );
			$client->audioFilehandle->open($command);
			$client->audioFilehandleIsSocket(1);
			
			$client->remoteStreamStartTime(Time::HiRes::time());
			$client->pauseTime(0);
			
			$size   = $duration * ($maxRate * 1000) / 8;
			$offset = 0;
		}

		$song->{'totalbytes'} = $size;
		$song->{'duration'}   = $duration;
		$song->{'offset'}     = $offset;
		$song->{'blockalign'} = $blockalign;
		
		# Notify the parent of new song queue, and start/pause times
		$client->sendParent( {
			command   => 'currentsongqueue',
			queue     => $client->currentsongqueue(),
			remoteSST => $client->remoteStreamStartTime(),
			pauseTime => $client->pauseTime(),
		} );

		$client->streamformat($format);

		$::d_source && msg("openSong: Streaming with format: $format\n");

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

		errorMsg("openSong: [$fullpath] Unrecognized type " . Slim::Music::Info::contentType($fullpath) . "!\n");

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
		$::d_source && msg("openSong: Can't open [$fullpath] : $!\n");

		my $line1 = $client->string('PROBLEM_OPENING');
		my $line2 = Slim::Music::Info::standardTitle($client, $track);

		$client->showBriefly($line1, $line2, 5, 1);

		return undef;
	}

	if (!$client->reportsTrackStart()) {

		$client->currentPlaylistChangeTime(time());
		Slim::Player::Playlist::refreshPlaylist($client);
	}

	Slim::Control::Request::notifyFromArray($client, ['playlist', 'open', $fullpath]);

	# make sure newsong comes after open, like it does for sbs
	if (!$client->reportsTrackStart()) {

		Slim::Control::Request::notifyFromArray($client, ['playlist', 'newsong']);
	}

	return 1;
}

sub readNextChunk {
	my $client = shift;
	my $givenChunkSize = shift;

	if (!defined($givenChunkSize)) {
		$givenChunkSize = Slim::Utils::Prefs::get('udpChunkSize') * 10;
	} 

	my $chunksize = $givenChunkSize;

	my $chunk  = '';

	my $endofsong = undef;

	if ($client->streamBytes() == 0 && $client->streamformat() eq 'mp3') {
	
		my $silence = 0;
		# use the maximum silence prelude for the whole sync group...
		foreach my $buddy (Slim::Player::Sync::syncedWith($client), $client) {

			my $asilence = $buddy->prefGet('mp3SilencePrelude');

			if ($asilence && ($asilence > $silence)) {
				$silence = $asilence;
			}
		}
		
		$::d_source && msg("We need to send $silence seconds of silence...\n");
		
		while ($silence > 0) {
			$chunk .=  ${Slim::Web::HTTP::getStaticContent("html/lbrsilence.mp3")};
			$silence -= (1152 / 44100);
		}
		
		my $len = length($chunk);
		
		$::d_source && msg("sending $len bytes of silence\n");
		
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
					$::d_source && msgf("still in the middle of a trick segment: %d bytes remaining\n",
						$client->trickSegmentRemaining
					);

				} else {

					# starting a new trick segment, calculate the chunk offset and length
					my $now   = $client->songBytes() + $song->{offset};
					my $url   = Slim::Player::Playlist::song($client, streamingSongIndex($client));
					my $track = Slim::Schema->rs('Track')->objectForUrl($url);

					if (!blessed($track) || !$track->can('bitrate')) {

						errorMsg("readNextChunk: Couldn't find object for: [$url]\n");
						return undef;
					}

					my $byterate = $track->bitrate / 8;

					my $howfar   = int(($rate - $TRICKSEGMENTDURATION) * $byterate);					
					   $howfar  -= $howfar % $song->{blockalign};

					$::d_source && msg("trick mode seeking: $howfar from: $now\n");

					my $seekpos = $now + $howfar;

					if ($seekpos < 0) {
						$::d_source && msg("trick mode reached beginning of song: $seekpos\n");
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
							$::d_source && msg("trick mode couldn't seek: $start/$end\n");
							goto bail;
						}

						$seekpos  = $start;
						$seekpos += 1 if $streamClass eq 'Slim::Formats::MP3';

						$tricksegmentbytes = $end - $seekpos;
					}

					$::d_source && msg("new trick mode segment offset: [$seekpos] for length: [$tricksegmentbytes]\n");

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
				$::d_source && msg(
					"Reduced chunksize to $chunksize at end of file ($songLengthInBytes - $pos)\n"
				);

				if ($chunksize <= 0) {
					$endofsong = 1;
				}
			}

			if ($pos > $songLengthInBytes) {
				$::d_source && msg( "Trying to read past the end of file, skipping to next file\n");
				$chunksize = 0;
				$endofsong = 1;
			}
		}

		if ($chunksize > 0) {

			my $readlen = $client->audioFilehandle()->sysread($chunk, $chunksize);

			if (!defined($readlen)) { 

				if ($! != EWOULDBLOCK) {
					$::d_source && msg("readlen undef: ($!)" . ($! + 0) . "\n"); 
					$endofsong = 1; 
				} else {
					$::d_source_v && msg("would have blocked, will try again later\n");
					return undef;	
				}	

			} elsif ($readlen == 0) { 

				$::d_source && msg("Read to end of file or pipe\n");  

				$endofsong = 1;

			} else {
				$::d_source_v && msg("Read $readlen bytes from source\n");
			}		
		}
	} else {
		$::d_source && msg($client->id() . ": No filehandle to read from, returning no chunk.\n");
		return undef;
	}

	# if nothing was read from the filehandle, then we're done with it,
	# so open the next filehandle.
bail:
	if ($endofsong) {
		$::d_source && msg("end of file or error on socket, opening next song, (song pos: " .
				$client->songBytes() . "(tell says: . " . systell($client->audioFilehandle()).
				"), totalbytes: " . $song->{totalbytes} . ")\n");

		if ($client->streamBytes() == 0 && $client->reportsTrackStart()) {
			# If we haven't streamed any bytes, then we can't rely on 
			# the player to tell us when the next track has started,
			# so we manually mark the track as played.
			$::d_source && msg("Didn't stream any bytes for this song, so just mark it as played\n");
			markStreamingTrackAsPlayed($client);
		}

		if (!gotoNext($client, 1)) {
			$::d_source && msg($client->id() . ": Can't opennext, returning no chunk.\n");
		}
		
		# we'll have to be called again to get a chunk from the next song.
		return undef;
	}

	my $chunkLength = length($chunk);

	if ($chunkLength > 0) {

		$::d_source_v && msg("read a chunk of $chunkLength length\n");
		$client->songBytes($client->songBytes() + $chunkLength);
		$client->streamBytes($client->streamBytes() + $chunkLength);

		if ($client->trickSegmentRemaining) {
			$client->trickSegmentRemaining($client->trickSegmentRemaining - $chunkLength);
		}
	}
	
	return \$chunk;
}

sub streamClassForFormat {
	my $client = shift;

	my $streamFormat = $client->streamformat;

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

		next if ($everyclient->prefGet('silent'));

		$everyclient->pause();

		# Bug 2314 - restore the volume
		$everyclient->volume($everyclient->prefGet("volume"));
	}
}

sub openRemoteStream {
	warn "Slim::Player::openRemoteStream is deprecated. Please use Slim::Player::ProtocolHandlers->openRemoteStream()\n";

	return Slim::Player::ProtocolHandlers->openRemoteStream(@_);
}

1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
