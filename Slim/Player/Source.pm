package Slim::Player::Source;

# $Id$

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use bytes;
use strict;

use Fcntl qw(SEEK_CUR);
use Time::HiRes;

use Slim::Formats;
use Slim::Formats::Playlists;
use Slim::Utils::Errno;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;

my $log = logger('player.source');

my $prefs = preferences('server');

sub systell {
	$_[0]->sysseek(0, SEEK_CUR) if $_[0]->can('sysseek');
}

# fractional progress (0 - 1.0) of playback in the current song.
sub progress {

	my $client = shift->master();
	
	if (Slim::Player::Source::playmode($client) eq "stop") {
		return 0;
	}

	my $songduration = playingSongDuration($client);

	return 0 unless $songduration;

	my $songtime = songTime($client);

	return 0 unless defined($songtime);

	return $songtime / $songduration;
}

sub songTime {
	return shift->controller->playingSongElapsed();
}

sub _returnPlayMode {
	my $controller = $_[0];
	
	# Should reall find out if the player is active in the sync-group but too expensive
	return 'stop' if !$_[1]->power();
	
	my $returnedmode = $controller->isStopped ? 'stop'
						: $controller->isPaused ? 'pause' : 'play';
	return $returnedmode;
}

# playmode - start playing, pause or stop
sub playmode {
	my ($client, $newmode, $seekdata, $reconnect, $fadeIn) = @_;
	my $controller = $client->controller();

	assert($controller);
	
	# Short circuit.
	return _returnPlayMode($controller, $client) unless defined $newmode;
	
	if ($newmode eq 'stop') {
		$controller->stop();
	} elsif ($newmode eq 'play') {
		if (!$client->power()) {$client->power(1);}
		$controller->play(undef, $seekdata, $reconnect, $fadeIn);
	} elsif ($newmode eq 'pause') {
		$controller->pause();
	} elsif ($newmode eq 'resume') {
		if (!$client->power()) {$client->power(1);}
		$controller->resume($fadeIn);
	} else {
		logBacktrace($client->id . " unknown playmode: $newmode");
	}
	
	# bug 6971
	# set the player power item on Jive to whatever our power setting now is
	Slim::Control::Jive::playerPower($client);
	
	my $return = _returnPlayMode($controller, $client);
	
	if ( main::INFOLOG && $log->is_info ) {
		$log->info($client->id() . ": Current playmode: $return\n");
	}
		
	return $return;
}

use constant QUEUED_CHUNKS_HWM => 10;
use constant QUEUED_CHUNKS_LWM => 3;

# TODO - move to some stream-handler
sub nextChunk {
	my $client       = shift;
	my $maxChunkSize = shift;
	my $callback     = shift;

	my $chunk;
	my $len;

	return if !$client;
	
	my $queued_chunks = $client->chunks;

	# if there's a chunk in the queue, then use it.
	if (ref($queued_chunks) eq 'ARRAY' && scalar(@$queued_chunks)) {

		$chunk = shift @$queued_chunks;

		$len = length($$chunk);
		
	} else {
		
		# Bug 14117
		# If any client in sync-group has exceeded the high water-mark, then just sleep
		# until the queue gets drained.
		foreach ($client->syncGroupActiveMembers()) {
			if (ref($_->chunks) eq 'ARRAY' && scalar(@{$_->chunks}) >= QUEUED_CHUNKS_HWM) {
				main::DEBUGLOG && $log->is_debug && $log->debug('Waiting for queue to drain for ', $_->id);
				$client->streamReadableCallback($callback) if $callback;
				return undef;
			}
		}

		# otherwise, read a new chunk
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
				main::SB1SLIMP3SYNC && Slim::Player::SB1SliMP3Sync::saveStreamData($controller, $chunk);
			}
		} else {
			if ($callback) {
				$client->streamReadableCallback($callback);
			}
		}
	}
	
	$client->streamReadableCallback(undef) if defined($chunk);
	
	if (defined($chunk) && ($len > $maxChunkSize)) {

		0 && $log->debug("Chunk too big, pushing the excess for later.");

		my $queued = substr($$chunk, $maxChunkSize - $len, $len - $maxChunkSize);

		unshift @$queued_chunks, \$queued;

		my $returned = substr($$chunk, 0, $maxChunkSize);

		$chunk = \$returned;
	}
	
	# Bug 14117
	# If we just dropped back to the low-water-mark, then signal waiting clients in sync-group
	elsif (defined($chunk) && ref($queued_chunks) eq 'ARRAY' && scalar(@$queued_chunks) == QUEUED_CHUNKS_LWM) {
		
		# This is important. We must only signal the waiting streams that they may try again so
		# long as no client is above the HWM. It is possible that a callback is still registered
		# for an old stream connection for a client in this sync-group. We do not want to fire that (old)
		# callback because it will steal a chunk. However, we can be pretty sure that, if this client
		# has just reached the LWM, then any other client which has not yet started streaming will
		# have its queue full and it can correctly reset its callback registration before we signal
		# the waiters.
		foreach ($client->syncGroupActiveMembers()) {
			if (ref($_->chunks) eq 'ARRAY' && scalar(@{$_->chunks}) >= QUEUED_CHUNKS_HWM) {
				main::DEBUGLOG && $log->is_debug && $log->debug('Still waiting for queue to drain for ', $_->id);
				return $chunk;
			}
		}
		
		main::DEBUGLOG && $log->is_debug && $log->debug('Wake up queued clients as have drained queue for ', $client->id);
		_wakeupOnReadable(undef, $client->controller()->master());
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
	my $song = $_[0]->controller()->streamingSong();

	return $song ? $song->index() : 0;
}

sub playingSongIndex {
	my $song = $_[0]->controller()->playingSong();

	return $song ? $song->index() : 0;
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

	if ($client->streamBytes() == 0 && $client->streamformat() eq 'mp3') {
	
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
		
		main::DEBUGLOG && $log->debug("Sending $len bytes of silence.");
		
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
					main::DEBUGLOG && $log->debug("Got EINTR, will try again later.");
					return undef;
				} elsif ($! == ECHILD) {
					main::DEBUGLOG && $log->debug("Got ECHILD - will try again later.");
					return undef;
				} else {
					main::DEBUGLOG && $log->debug("readlen undef: ($!) " . ($! + 0));
					$endofsong = 1; 
				}	
			} elsif ($readlen == 0) { 
				main::DEBUGLOG && $log->debug("Read to end of file or pipe");  
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

		if ( main::INFOLOG && $log->is_info ) {
			my $msg = "end of file or error on socket, song pos: " . $client->songBytes;
			$msg .= ", tell says: " . systell($fd) . ", totalbytes: "
					 . $client->controller()->songStreamController()->song()->totalbytes()
				if $fd->isa('Slim::Player::Protocols::File');
			$log->info($msg);
		}

		# Mark the end of stream
		for my $buddy ($client->syncGroupActiveMembers()) {
			main::INFOLOG && $log->info($buddy->id() . " mark end of stream");
			push @{$buddy->chunks}, \'';
		}

		if ($client->streamBytes() == 0 && $client->reportsTrackStart()) {

			# If we haven't streamed any bytes, then it is most likely an error

			main::INFOLOG && $log->info("Didn't stream any bytes for this song; mark it as failed");
			$client->controller()->playerStreamingFailed($client);
			return;
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
	
	main::DEBUGLOG && $log->debug($master->id);
	
	Slim::Networking::Select::removeRead($fd) if defined $fd;
	
	foreach ($master->syncGroupActiveMembers()) {
		if (my $cb = $_->streamReadableCallback) {
			$_->streamReadableCallback(undef);
			&$cb($_);
		}
	}
}


1;
