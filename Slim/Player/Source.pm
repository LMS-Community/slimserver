package Slim::Player::Source;

# $Id$

# SqueezeCenter Copyright 2001-2007 Logitech.
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
use MPEG::Audio::Frame;
use Time::HiRes;

use Slim::Formats;
use Slim::Control::Request;
use Slim::Formats::Playlists;
use Slim::Player::TranscodingHelper;
use Slim::Utils::Errno;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Network;
use Slim::Utils::OSDetect;
use Slim::Utils::Prefs;

my $log = logger('player.source');

my $prefs = preferences('server');

sub systell {
	$_[0]->sysseek(0, SEEK_CUR) if $_[0]->can('sysseek');
}

sub init {
	Slim::Player::TranscodingHelper::loadConversionTables();
}


# fractional progress (0 - 1.0) of playback in the current song.
sub progress {

	my $client = shift->master();
	
	if (Slim::Player::Source::playmode($client) eq "stop") {
		return 0;
	}

	my $songduration = playingSongDuration($client);

	return 0 unless $songduration;
	return songTime($client) / $songduration;
}

sub songTime {

	my $client = shift->master();

	my $songtime    = $client->songElapsedSeconds();
	my $song     	= playingSong($client) || return 0;
	my $startStream = $song->{startOffset} || 0;
	my $duration	= $song->duration();
	
	if (defined($songtime)) {
		$songtime = $startStream + $songtime;
		
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

	my $byterate	  	= ($song->bitrate() || 0)/8 || ($duration ? ($song->{totalbytes} / $duration) : 0);
	my $bytesReceived 	= ($client->bytesReceived() || 0) - $client->bytesReceivedOffset();
	my $fullness	  	= $client->bufferFullness() || 0;
		
	# If $fullness > $bytesReceived, then we are playing out previous song
	my $bytesPlayed = $bytesReceived - $fullness;
	
	# If negative, then we are playing out previous song
	if ($bytesPlayed < 0) {
		if ($duration && $byterate) {
			$songtime = $duration + $bytesPlayed / $byterate;
		} else {
			# not likley to happen as it would mean that we are streaming one song after another
			# without knowing the duration and bitrate of the previous song
			$songtime = 0;
		}
	} else {
		
		$songtime = $byterate ? ($bytesPlayed / $byterate + $startStream) : 0;
	}
	
	# This assumes that remote streaming is real-time - not always true but, for the common
	# cases when it is, it will be better than nothing.
	if ($songtime == 0) {

		my $startTime = $client->remoteStreamStartTime();
		my $endTime   = $client->pauseTime() || Time::HiRes::time();
		
		$songtime = ($startTime ? $endTime - $startTime : 0);
	}

	if ( $log->is_debug ) {
		$log->debug("songtime=$songtime from byterate=$byterate, duration=$duration, bytesReceived=$bytesReceived, fullness=$fullness, startStream=$startStream");
	}

	# limit check
	if ($songtime < 0) {
		$songtime = 0;
	} elsif ($duration && $songtime > $duration) {
		$songtime = $duration;
	}

	return $songtime;
}

sub _returnPlayMode {
	my $controller = $_[0];
	
	# Should reall find out if the player is active in the sync-group but too expensive
	return 'stop' if !$_[1]->power();
	
	my $returnedmode = $controller->isPaused ? 'pause'
						: $controller->isStopped ? 'stop' : 'play';
	return $returnedmode;
}

# playmode - start playing, pause or stop
sub playmode {
	my ($client, $newmode, $seekdata, $reconnect) = @_;
	my $controller = $client->controller();

	assert($controller);
	
	# Short circuit.
	return _returnPlayMode($controller, $client) unless defined $newmode;
	
	if ($newmode eq 'stop') {
		$controller->stop();
	} elsif ($newmode eq 'play') {
		if (!$client->power()) {$client->power(1);}
		$controller->play(undef, $seekdata, $reconnect);
	} elsif ($newmode eq 'pause') {
		$controller->pause();
	} elsif ($newmode eq 'resume') {
		if (!$client->power()) {$client->power(1);}
		$controller->resume();
	} else {
		$log->error($client->id . " unknown playmode: $newmode");
		bt();
	}
	
	# bug 6971
	# set the player power item on Jive to whatever our power setting now is
	Slim::Control::Jive::playerPower($client);
	
	my $return = _returnPlayMode($controller, $client);
	
	if ( $log->is_info ) {
		$log->info($client->id() . ": Current playmode: $return\n");
	}
		
	return $return;
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

# TODO - move to some stream-handler
sub nextChunk {
	my $client       = shift;
	my $maxChunkSize = shift;
	my $callback     = shift;

	my $chunk;
	my $len;

	return if !$client;

	# if there's a chunk in the queue, then use it.
	if (ref($client->chunks) eq 'ARRAY' && scalar(@{$client->chunks})) {

		$chunk = shift @{$client->chunks};

		$len = length($$chunk);
		
	} else {

		#otherwise, read a new chunk
		my $controller = $client->controller();
		my $master = $controller->master();

		$chunk = _readNextChunk($master, $maxChunkSize, defined($callback));

		if (defined($chunk)) {

			$len = length($$chunk);

			if ($len) {

				# let everybody I'm synced with use this chunk
				foreach my $buddy ($controller->activePlayers()) {
					next if $client == $buddy;
					push @{$buddy->chunks}, $chunk;
				}
				
				# And save the data for analysis, if we are synced.
				# Only really need to do this if we have any SliMP3s or SB1s in the
				# sync group.
				
				if ($controller->activePlayers() > 1) {
					if (my $buf = $controller->initialStreamBuffer()) {
						$$buf .= $$chunk;

						# Safety check - just make sure that we are not in the process
						# of slurping up a perhaps-infinite stream without using it.
						# We assume min frame size of 72 bytes (24kb/s, 48000 samples/s)
						# which gives us at most 45512 frames in the decode buffer (25Mb)
						# and 355 samples in the output buffer (also 25Mb) at 1152 samples/frame
						if (length($$buf) > 3_500_000 ||
							defined($controller->frameData) && @{$controller->frameData} > 50_000)
						{
							$log->warn('Discarding saved stream & frame data used for synchronization as appear to be collecting it but not using it');
							resetFrameData($master);
						}
					} elsif ($master->streamformat() eq 'mp3' && $master->streamBytes() <= $len) {
						# do we need to save frame data?
						my $needFrameData = 0;
						foreach ($controller->activePlayers()) {
							my $model = $_->model();
							last if $needFrameData = ($model eq 'slimp3' || $model eq 'squeezebox');
						}
						if ($needFrameData) {		
							my $savedChunk = $$chunk; 	# copy
							$controller->initialStreamBuffer(\$savedChunk);
						}
					}
				}
			}
		} else {
			if ($callback) {
				$client->streamReadableCallback($callback);
			}
		}
	}
	
	if (defined($chunk) && ($len > $maxChunkSize)) {

		0 && $log->debug("Chunk too big, pushing the excess for later.");

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
	my $client  = shift;
	my $newtime = shift;
	
	$client->controller()->jumpToTime($newtime);
}

sub streamingSongIndex {
	my $client = shift->master();
	my $index = shift;
	my $clear = shift;
	my $song = shift;

	my $queue = $client->currentsongqueue();
	if (defined($index)) {

		$log->info("Adding song index $index to song queue");

		if ($clear || $client->isSynced()) {

			$log->info("Clearing out song queue first");

			$#{$queue} = -1;
		}
		
		if (defined($song)) {
			$log->info("adding existing song: index=", ($song->{'index'} ? $song->{'index'} : 'undef'));
			unshift(@{$queue}, $song);

		} else {
			
			$song  = Slim::Player::Song->new($client->controller, $index);
			unshift(@{$queue}, $song) unless (!$song);
			
		}

		if ( $log->is_info ) {
			$log->info("Song queue is now " . join(',', map { $_->{'index'} } @$queue));
		}
		
	}

	$song = $client->controller()->streamingSong();

	if (!defined($song)) {
		return 0;
	}

	return $song->{'index'};
}

sub playingSongIndex {
	my $song = playingSong($_[0]);
	if (!defined($song)) {
		return 0;
	}
	return $song->{'index'};
}

sub playingSong {
	return $_[0]->controller()->playingSong();
}

sub playingSongDuration {
	return $_[0]->controller()->playingSongDuration();
}

sub flushStreamingSong {
	my $client = shift;
	$client->controller()->flush($client);
}


################################################################################
# Private functions below. Do not call from outside this module.
# XXX - should be _ prefixed then!
#
################################################################################

sub _markStreamingTrackAsPlayed {
	my $client = shift->master();
	my $song = $client->controller()->streamingSong();
	if (defined($song)) {
		$client->controller()->playerTrackStarted($client);
	}
}


sub errorOpening {
	my ( $client, $error ) = @_;
	
	$error ||= 'PROBLEM_OPENING';
		
	$client->controller()->playerStreamingFailed($client, $error);
}

sub explodeSong {
	my $client = shift->master();
	my $tracks = shift;

	# insert the list onto the playlist
	splice @{Slim::Player::Playlist::playList($client)}, streamingSongIndex($client), 1, @{$tracks};

	# update the shuffle list only if we have more than 1 track
	if ( scalar @{$tracks} > 1 ) {
		Slim::Player::Playlist::reshuffle($client);
	}
}


sub _readNextChunk {
	my $client = shift;
	my $givenChunkSize = shift;
	my $callback = shift;
	
	if (!defined($givenChunkSize)) {
		$givenChunkSize = $prefs->get('udpChunkSize') * 10;
	} 

	my $chunksize = $givenChunkSize;

	my $chunk  = '';

	my $endofsong = undef;

	if ($client->streamBytes() == 0 && $client->master()->streamformat() eq 'mp3') {
	
		my $silence = 0;
		# use the maximum silence prelude for the whole sync group...
		foreach my $buddy ($client->syncGroupActiveMembers()) {

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

	my $fd = $client->controller()->songStreamController() ? $client->controller()->songStreamController()->streamHandler() : undef;
	
	if ($fd) {

		if ($chunksize > 0) {

			my $readlen = $fd->sysread($chunk, $chunksize);

			if (!defined($readlen)) { 
				if ($! == EWOULDBLOCK) {
					# $log->debug("Would have blocked, will try again later.");
					if ($callback) {
						# This is a hack but I hesitate to use isa(Pileline) or similar.
						# Suggestions for better, efficient implementation welcome
						Slim::Networking::Select::addRead(${*$fd}{'pipeline_reader'} || $fd, sub {_wakeupOnReadable(shift, $client);}, 1);
					}
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
		0 && $log->debug($client->id, ": No filehandle to read from, returning no chunk.");
		return undef;
	}

	# if nothing was read from the filehandle, then we're done with it,
	# so open the next filehandle.
bail:
	if ($endofsong) {

		if ( $log->is_info ) {
			my $msg = "end of file or error on socket, song pos: " . $client->songBytes;
			$msg .= ", tell says: " . systell($fd) . ", totalbytes: "
					 . $client->controller()->songStreamController()->song()->{'totalbytes'}
				if $fd->isa('Slim::Player::Protocols::File');
			$log->info($msg);
		}

		if ($client->streamBytes() == 0 && $client->reportsTrackStart()) {

			# If we haven't streamed any bytes, then we can't rely on 
			# the player to tell us when the next track has started,
			# so we manually mark the track as played.

			$log->info("Didn't stream any bytes for this song, so just mark it as played");

			_markStreamingTrackAsPlayed($client);
		}
		
		# Mark the end of stream
		for my $buddy ($client->syncGroupActiveMembers()) {
			$log->info($buddy->id() . " mark end of stream");
			push @{$buddy->chunks}, \'';
		}

		$client->controller()->localEndOfStream();
		
		return undef;
	}

	my $chunkLength = length($chunk);

	if ($chunkLength > 0) {
		$client->songBytes($client->songBytes() + $chunkLength);
		$client->streamBytes($client->streamBytes() + $chunkLength);
	}

	return \$chunk;
}

sub _wakeupOnReadable {
	my ($fd, $master) = @_;
	my $cb;
	
	$log->debug($master->id);
	
	Slim::Networking::Select::removeRead($fd);
	
	foreach my $client ($master->syncGroupActiveMembers()) {
		if ($cb = $client->streamReadableCallback) {
			&$cb($client);
			$client->streamReadableCallback(undef);
		}
	}
}

use constant FRAME_BYTE_OFFSET => 0;
use constant FRAME_TIME_OFFSET => 1;

sub streamBitrate {
	my $controller = $_[0]->controller();
	my $client = $controller->master();

	# Only do this for sync play, although there is no real reason not to do it otherwise
	# Need to change this if we allow clients to join in mid song.
	if( !$client->isSynced(1) ) {
		return 0;
	}

	my $song = $controller->streamingSong();

	# already know the answer
	my $rate = $song->{'bitrate'};
	if ( defined $rate ) {
		return $rate;
	}

	my $format = $client->streamformat();
	
	if ( $format eq 'mp3' ) {
		my $frames = $controller->frameData();
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

	$client->controller()->initialStreamBuffer(undef);
	$client->controller()->frameData(undef);
}
	
sub purgeOldFrames {
	my $frames     = $_[0]->controller()->frameData() or return;
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
	my $client     = $_[0]->master();
	my $byteOffset = $_[1];
	my $buffer     = $client->controller()->initialStreamBuffer() or return;
	my $frames     = $client->controller()->frameData();

	return unless $byteOffset;

	# check if there are any frames to analyse
	if ( length($$buffer) > 1500 ) { # make it worth our while
	
		my $pos = 0;

		while ( my ($length, $nextPos, $seconds) = MPEG::Audio::Frame->read_ref($buffer, $pos) ) {
			last unless ($length);
			# Note: $length may not equal ($nextPos - $pos) if tag data has been skipped
			if ( !defined($frames) ) {
				$client->controller()->frameData( $frames = [[$nextPos - $length, 0]] );
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
			$client->controller()->initialStreamBuffer(\$newBuffer);
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
