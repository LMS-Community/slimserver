
package Slim::Player::Source;

# Slim Server Copyright (C) 2001,2002,2003 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use File::Spec::Functions qw(:ALL);
use FileHandle;
use IO::Socket qw(:DEFAULT :crlf);
use Time::HiRes;
use Slim::Control::Command;
use Slim::Display::Display;
use Slim::Utils::Misc;
use Slim::Utils::Scan;
use Slim::Utils::Strings qw(string);

my $CLIENTBUFFERLEN = (128 * 1024);


# rate can be negative for rew, zero for pause, 1 for playback and greater than one for ffwd
sub rate {
	my ($client, $newrate) = @_;
	if (!defined($newrate)) {
		return $client->rate;
	}
	my $oldrate = $client->rate();
	$client->rate($newrate);
	
	$::d_playlist && msg("switching rate from $oldrate to $newrate\n");
	# restart playback if we've changed and we're not pausing or unpauseing
	if ($oldrate != $newrate) {  		
	 	if ($oldrate != 0 && $newrate != 0) {
	 		$::d_playlist && msg("gototime, jumping to here in order to restart the stream\n");
			gototime($client, "+0", 1);
		}
	}
}

sub songTime {
	my ($client) = shift;

	$client = Slim::Player::Sync::masterOrSelf($client);

	if ($client->mp3filehandleIsSocket) {
		my $startTime = $client->remoteStreamStartTime;
		if ($startTime) {
			return Time::HiRes::time() - $startTime;
		} else {
			return 0;
		}
	}

	my $size = $client->songtotalbytes;
	my $duration = $client->songduration;
	my $byterate;
	if (!$duration) {
		$byterate = 0;
	} else {
		$byterate = $size / $duration;
	}

	my $songtime;
	if (!$size) {
		$songtime = 0;
	} else {
		$songtime = (songRealPos($client) / $size * $duration);
	}

	$::d_playlist && msg( "byterate = $byterate, size = $size, songpos = ".songRealPos($client)." songtime = $songtime\n");

	return($songtime);

}	

# the "real" position in the track, accounting for client and server-side buffering
# TODO include server-side buffering
# TODO this won't work when scanning in reverse
#
sub songRealPos {
	my ($client) = shift;

	$client = Slim::Player::Sync::masterOrSelf($client);

	my $realpos = 0;
	if (defined($client->songpos) && defined(Slim::Networking::Stream::fullness($client))) {
		$realpos = $client->songpos - Slim::Networking::Stream::fullness($client);
	}

	if ($realpos<0) {
#		warn("came up with a negative position in the stream: ".
#		     "songpos = ".$client->songpos.", fullness = ".Slim::Networking::Stream::fullness($client)."\n");
		$realpos = 0;
	}
#	$::d_playlist && msg("songRealPos songPos: ". $client->songpos . " realpos: $realpos\n");
	return $realpos;	
}

# playmode - start playing, pause or stop
sub playmode {
	my($client, $newmode) = @_;

	assert($client);

	if (!defined($newmode)) {
		return $client->playmode;
	}
	
	$::d_playlist && $newmode && msg($client->id() . ": Switching to mode $newmode\n");

	my $prevmode = $client->playmode;

	if ($newmode eq $prevmode) {
		$::d_playlist && msg(" Already in playmode $newmode : ignoring mode change\n");
	} else {

		# if we're playing, then open the new song the master.		
		if ($newmode eq "play") {
			my $opened;
			
			# if the player is off, we automatically power on when we start to play
			if (!$client->power()) {
				$client->power(1);
			}
			
			$opened = openSong(Slim::Player::Sync::masterOrSelf($client));

			# if we couldn't open the song, then stop...
			if (!$opened) {
				$::d_playlist && msg("Couldn't open song.  Stopping.\n");
				$newmode = "stop";
			}
		}
		
		# when we change modes, make sure we do it to all the synced clients.
		foreach my $everyclient ($client, Slim::Player::Sync::syncedWith($client)) {
			$::d_playlist && msg(" New play mode: " . $newmode . "\n");
			
			# wake up the display if we've switched modes.
			if ($everyclient->isPlayer()) { Slim::Buttons::ScreenSaver::wakeup($everyclient); };
			
			# when you resume, you go back to play mode
			if (($newmode eq "resume") ||($newmode eq "resumenow")) {
				$everyclient->playmode("play");
				rate($everyclient, 1);
				
			} elsif ($newmode eq "pausenow") {
				$everyclient->playmode("pause");
				rate($everyclient, 0);
				
			} elsif ($newmode eq "playout") {
				$everyclient->playmode("stop");
				
			} else {
				$everyclient->playmode($newmode);
			}
	
			if ($newmode eq "stop") {
				$everyclient->currentplayingsong("");
			#	$everyclient->songpos(0);
				$::d_playlist && msg("Stopping and clearing out old chunks for client " . $everyclient->id() . "\n");
				@{$everyclient->chunks} = ();

				$everyclient->stop();
				closeSong($everyclient);
			} elsif ($newmode eq "play") {
				$everyclient->readytosync(0);
				rate($everyclient, 1);
				$everyclient->play(Slim::Player::Sync::isSynced($everyclient));				
			} elsif ($newmode eq "pause") {
				# since we can't count on the accuracy of the fade timers, we unfade them all, but the master calls back to unpause everybody
				if ($everyclient eq $client) {
					$everyclient->fade_volume(-0.3125, \&pauseSynced, [$client]);
				} else {
					$everyclient->fade_volume(-0.3125);
				}				
				
			} elsif ($newmode eq "pausenow") {
				$everyclient->pause();
				rate($everyclient,0);
			} elsif ($newmode eq "resumenow") {
				$everyclient->resume();
				rate($everyclient, 1);
				
			} elsif ($newmode eq "resume") {
				# set volume to 0 to make sure fade works properly
				$everyclient->volume(0);
				$everyclient->resume();
				$everyclient->fade_volume(.3125);
				
			} elsif ($newmode eq "playout") {
				$everyclient->playout();
				
			} else {
				$::d_playlist && msg(" Unknown play mode: " . $everyclient->playmode . "\n");
				return $everyclient->playmode();
			}
			
			Slim::Player::Playlist::refreshPlaylist($everyclient);
		}
	}
	$::d_playlist && msg($client->id() . ": Current playmode: " . $client->playmode() . "\n");

	return $client->playmode();
}

sub lastChunk {
	my $client = shift;
	return $client->lastchunk;
}



sub nextChunk {
	my $client = shift;
	my $maxChunkSize = shift;
	my $chunkRef;
	my $i;
		
	# if there's a chunk in the queue, then use it.
	if (scalar(@{$client->chunks})) {
		$chunkRef = shift @{$client->chunks};
	} else {
		#otherwise, read a new chunk
		my $readfrom = Slim::Player::Sync::masterOrSelf($client);

		# if we're at a non-regular rate (not 0 or 1), play for one second 
		# then skip a calculated amount to play back at the apparent rate.
		my $rate = rate($client);
		my $lastskip = $client->lastskip();
		my $now = Time::HiRes::time();
		if (($rate != 0 && $rate != 1) && (($now - $lastskip) > 1.0)) { 
			my $skip = $rate - 1.0;
			if ($skip > 0) { $skip = "+" . $skip; }
			$::d_playlist && msg("non regular play rate ($rate), skipping $skip seconds\n");
			$client->lastskip($now);
			gototime($readfrom, $skip, 1);
			# the gototime above will reload the data, so we should just return;
			return undef;
		}
			
		$chunkRef = readNextChunk($readfrom, $maxChunkSize);
			
		if (defined($chunkRef)) {	
			# let everybody I'm synced with use this chunk
			foreach my $buddy (Slim::Player::Sync::syncedWith($client)) {
				push @{$buddy->chunks}, $chunkRef;
			}
		}
	}
	if (defined($chunkRef)) {
		my $len = length($$chunkRef);
		
		if ($len > $maxChunkSize) {
			push @{$client->chunks}, \substr($$chunkRef, $maxChunkSize - $len, $len - $maxChunkSize);
			$chunkRef = \substr($$chunkRef, 0, $maxChunkSize);
		}
		
		# remember the last chunk we sent
		if (defined($chunkRef)) {
			$client->lastchunk($chunkRef);
		}
	}
	
	return $chunkRef;
}



#
# jump to a particular time in the current song
#  should be dead-on for CBR, approximate for VBR
#  third argument determines whether this is an instant jump or wait until the
#   buffer gets around to it
#
sub gototime {
	my($client, $newtime, $doitnow) = @_;
	my $newoffset;
	my $oldoffset;
	my $oldtime;

	if (Slim::Player::Sync::isSynced($client)) {
		$client = Slim::Player::Sync::master($client);
	}

	return if (!Slim::Player::Playlist::song($client));
	return if !defined($client->mp3filehandle);

	my $size = $client->songtotalbytes;
	my $duration = $client->songduration;

#	$oldoffset = $client->songpos;
	$oldoffset = songRealPos($client);
	
	if ($oldoffset > $size) {
		 warn ("song position > size\n") 
	}

	$oldtime = songTime($client);

	if ($newtime =~ /^[\+\-]/) {
		$newoffset = int($oldoffset + ($newtime / $duration * $size));
		$::d_playlist && msgf("going to time %s, offset %s from old offset %s\n", $newtime, $newoffset, $oldoffset);
		# skip to the previous or next track as necessary
		if ($newoffset > $size) {
			my $rate = rate($client);
			jumpto($client, "+1");
			rate($client, $rate);
			$newtime = ($newoffset - $size) * $duration / $size;
			$::d_playlist && msg("skipping forward to the next track to time $newtime\n");
			gototime($client, $newtime, $doitnow);
			return;
		} elsif ($newoffset < 0) {
			my $rate = rate($client);
			while ($newtime < 0) {
				jumpto($client, "-1");
				rate($client, $rate);
				$newtime = $client->songduration - ((-$newoffset) * $duration / $size);
				$::d_playlist && msg("skipping backwards to the previous track to time $newtime\n");
			}
			gototime($client, $newtime, $doitnow);
			return;
		}
	} else {
		$::d_playlist && msgf("going to time %s\n", $newtime);
		$newoffset = int($newtime / $duration * ($size));
		if ($newoffset > $size) {
			$newoffset = $size;
		} elsif ($newoffset < 0) {
			$newoffset = 0;
		}
	}
	
	$::d_playlist && msgf("oldoffset $oldoffset, old time = %d, newoffset: %d new time = %d\n", $oldtime, $newoffset, $newoffset / $size * $duration);

	if ($doitnow) {
		foreach my $everybuddy ($client, Slim::Player::Sync::slaves($client)) {
			$::d_playlist && msg("gototime: stopping playback\n");
			$everybuddy->stop();
			@{$everybuddy->chunks} = ();
		}
	}
	my $dataoffset =  $client->songoffset;
	$client->songpos($newoffset);
	$client->mp3filehandle->seek($newoffset+$dataoffset, 0);

	if ($doitnow) {
		foreach my $everybuddy ($client, Slim::Player::Sync::slaves($client)) {
			$::d_playlist && msg("gototime: restarting playback\n");
			$everybuddy->readytosync(0);
			$everybuddy->play(Slim::Player::Sync::isSynced($client));
		}
	}	
}



# jumpto - set the current song to a given offset
sub jumpto {
	my($client, $offset) = @_;
	my($songcount) = Slim::Player::Playlist::count($client);
	if ($songcount == 0) {
		return;
	}

	playmode($client,"stop");
	if ($songcount != 1) {
		if ($offset =~ /[\+\-]\d+/) {
			currentSongIndex($client, currentSongIndex($client) + $offset);
			$::d_playlist && msgf("jumping by %s\n", $offset);
		} else {
			currentSongIndex($client, $offset);
			$::d_playlist && msgf("jumping to %s\n", $offset);
		}
	
		if ($songcount && currentSongIndex($client) >= $songcount) {
			currentSongIndex($client, currentSongIndex($client) % $songcount);
		}
		if ($songcount && currentSongIndex($client) < 0) {
			currentSongIndex($client, $songcount - ((0 - currentSongIndex($client)) % $songcount));
		}
	} else {
		currentSongIndex($client, 0);
	}
	playmode($client,"play");
}


################################################################################
# Private functions below. Do not call from outside this module.
################################################################################

# openNext returns 1 if it succeeded opening a new song, 
#                  0 if it stopped at the end of the list or failed to open the current song 
# note: Only call this with a master or solo client
sub openNext {
	$::d_playlist && msg("opening next song...\n"); 
	my $client = shift;
	my $result = 1;
		
	closeSong($client);

	# we're at the end of a song, let's figure out which song to open up.
	# if we can't open a song, skip over it until we hit the end or a good song...
	do {
	
		if (Slim::Player::Playlist::repeat($client) == 2  && $result) {
			# play the next song and start over if necessary
			skipsong($client);
		} elsif (Slim::Player::Playlist::repeat($client) == 1 && $result) {
			#play the same song again
		} else {
			#stop at the end of the list
			if (currentSongIndex($client) == (Slim::Player::Playlist::count($client) - 1)) {
				playmode($client, $result ? 'playout' : 'stop');
				currentSongIndex($client, 0);
				return 0;
			} else {
				skipsong($client);
			}
		}
		
		$result = openSong($client);
		
	} while (!$result);
	
	# this is
	if ($result && Slim::Player::Sync::isSynced($client)) {
		my $silence = Slim::Web::HTTP::getStaticContent("html/silentpacket.mp3");
		my $count = int($CLIENTBUFFERLEN / length($silence)) + 1;
		my @fullbufferofsilence =  (\$silence) x $count;
		$::d_playlist && msg("stuffing " . scalar(@fullbufferofsilence) . " of silence into the buffers to sync.\n"); 
		# stuff silent packets to fill the buffers for each player
		foreach my $buddy ($client, Slim::Player::Sync::syncedWith($client)) {
			push @{$buddy->chunks}, (@fullbufferofsilence);
		}
		$client->resync(1); 
	}
	
	return $result;
}


sub currentSongIndex {
	my $client = shift;
	my $newindex = shift;

	$client = Slim::Player::Sync::masterOrSelf($client);
	
	if (defined($newindex)) {
		$client->currentsong($newindex);
	}
	
	return $client->currentsong;
}

# skipsong is just for playing the next song when the current one ends
sub skipsong {
	my ($client) = @_;
	# mark htmlplaylist invalid so the current song changes
	$client->htmlstatusvalid(0);

	currentSongIndex($client, currentSongIndex($client) + 1);

	if (currentSongIndex($client) >= Slim::Player::Playlist::count($client)) {
		if (Slim::Player::Playlist::shuffle($client) && Slim::Utils::Prefs::get('reshuffleOnRepeat')) {
			my $playmode = playmode($client);
			playmode($client,'stop');
			Slim::Player::Playlist::reshuffle($client);
			playmode($client,$playmode);
		}
		currentSongIndex($client, 0);
	}
}

sub closeSong {
	my $client = shift;

	# close the previous handle to prevent leakage.
	if (defined $client->mp3filehandle()) {
		$client->mp3filehandle->close();
		$client->mp3filehandle(undef);
		$client->mp3filehandleIsSocket(0);
	}	
}

sub openSong {
	my $client = shift;

	# at the end of a song, reset the song time
	$client->songtotalbytes(0);
	$client->songduration(0);
	$client->songpos(0);

	# reset shoutcast variables
	$client->shoutMetaInterval(0);
	$client->shoutMetaPointer(0);

	# mark htmlplaylist invalid so the current song changes
	$client->htmlstatusvalid(0);
	my $fullpath = '';

	# We are starting a new song, lets kill any animation so we see the correct new song.
	foreach my $everyclient ($client, Slim::Player::Sync::syncedWith($client)) { 
		Slim::Display::Animation::killAnimation($everyclient);
	}
	
	closeSong($client);
	
	$fullpath = Slim::Player::Playlist::song($client);

	unless ($fullpath) {
		return undef;
	}


	$::d_playlist && msg("openSong on: $fullpath\n");
	####################
	# parse the filetype

	if (Slim::Music::Info::isHTTPURL($fullpath)) {
		my $line1 = string('CONNECTING_FOR');
		my $line2 = Slim::Music::Info::standardTitle($client, Slim::Player::Playlist::song($client));			
		Slim::Display::Animation::showBriefly($client, $line1, $line2, undef,1);

		# we don't get the content type until after the stream is opened
		my $sock = Slim::Web::RemoteStream::openRemoteStream($fullpath, $client);
		if ($sock) {
			# if it's an mp3 stream, then let's stream it.
			if (Slim::Music::Info::isSong($fullpath)) {
				$client->mp3filehandle($sock);
				$client->mp3filehandleIsSocket(1);
				$client->remoteStreamStartTime(time());
			# if it's one of our playlists, parse it...
			} elsif (Slim::Music::Info::isList($fullpath)) {
				$::d_playlist && msg("openSong on a remote list!\n");
				my @items;
				# handle the case that we've actually got a playlist in the list,
				# rather than a stream.

				# parse out the list
				@items = Slim::Formats::Parse::parseList($fullpath, $sock);
				
				# hack to preserve the title of a song redirected through a playlist
				if ( scalar(@items) == 1 && defined(Slim::Music::Info::title($fullpath))) {
				    Slim::Music::Info::setTitle($items[0], Slim::Music::Info::title($fullpath));
				} 
				
				# close the socket
				$sock->close();
				$sock = undef;
				$client->mp3filehandle(undef);

				# insert the list onto the playlist
				splice @{playList($client)}, currentSongIndex($client), 1, @items;

				# update the shuffle list
				Slim::Player::Playlist::reshuffle($client);

				# try to open the first item in the list, if there is one.
				return openSong($client);
			} else {
				$::d_playlist && msg("don't know how to handle content for $fullpath\n");
				$sock->close();
				$sock = undef;
				$client->mp3filehandle(undef);
			}
		} 
		
		if (!$sock) {
			$::d_playlist && msg("Remote stream failed to open, showing message.\n");
			$client->mp3filehandle(undef);
			
			my $line1 = string('PROBLEM_CONNECTING');
			my $line2 = Slim::Music::Info::standardTitle($client, Slim::Player::Playlist::song($client));			
			Slim::Display::Animation::showBriefly($client, $line1, $line2, 5, 1);
			return undef;
		}
	} elsif (Slim::Music::Info::isSong($fullpath)) {
	
		my $filepath;
		if (Slim::Music::Info::isFileURL($fullpath)) {
			$filepath = Slim::Utils::Misc::pathFromFileURL($fullpath);
		} else {
			$filepath = $fullpath;
		}
		
		my $size = Slim::Music::Info::size($fullpath);
		my $duration = Slim::Music::Info::durationSeconds($fullpath);
		my $offset = Slim::Music::Info::offset($fullpath);
		$::d_playlist && msg("openSong: getting duration  $duration, size $size, and offset $offset for $fullpath\n");

		if (!$size || !$duration)  {
			$::d_playlist && msg("openSong: not bothering opening file with zero size or duration\n");
			return undef;
		}

		if (Slim::Music::Info::isMP3($fullpath)) {
			$::d_playlist && msg("openSong: this is an MP3 file: $fullpath\n");
			
			
			$client->mp3filehandle( FileHandle->new() );
	
			$::d_playlist && msg("openSong: opening file $filepath\n");
			if ($client->mp3filehandle->open($filepath)) {
				
				$::d_playlist && msg(" seeking in $offset into $filepath\n");
				if ($offset) {
					if (!seek ($client->mp3filehandle, $offset, 0) ) {
						msg("couldn't seek to $offset for $filepath");
					};
				}
							
			} else { 
				$client->mp3filehandle(undef);
			}
		} elsif(Slim::Music::Info::isMOV($fullpath)) {
			$::d_playlist && msg("openSong: this is an MOV file: $fullpath\n");
			my $samplerate = Slim::Utils::Prefs::get("wavmp3samplerate");
			my $movbin = Slim::Utils::Misc::findbin('mov123');
			my $lamebin = Slim::Utils::Misc::findbin('lame');
			if (!$movbin || !$lamebin) { return undef; }

			my $mov_cmd = "\"$movbin\" \"$filepath\"";

			my $lame_cmd = "\"$lamebin\" --silent -b 320 -r - - &";
	
			$client->mp3filehandle( FileHandle->new() );
	
			$client->mp3filehandle->open("$mov_cmd | $lame_cmd |");
			$client->mp3filehandleIsSocket(1);
			$client->remoteStreamStartTime(time());
		} elsif (Slim::Music::Info::isOgg($fullpath) && Slim::Utils::Prefs::get("transcode-ogg")) {
			# Note we have to put the path in double quotes so that
			# spaces in file names are handled properly.
			my $oggbin = Slim::Utils::Misc::findbin('ogg123');
			my $lamebin = Slim::Utils::Misc::findbin('lame');
			if (!$oggbin || !$lamebin) { return undef; }

			my $rate = Slim::Music::Info::samplerate($fullpath);
			if ($rate) {
				$rate = "-s $rate";
			} else {
				$rate = '';
			}
			
			my $ogg_cmd = "\"$oggbin\" -q -p 5 -d raw -f - \"$filepath\"";
			# Added -x option to fix ogg output problem reported by users
			my $lame_cmd = "\"$lamebin\" -r $rate -b 320 -x --quiet - - &";
			$client->mp3filehandle( FileHandle->new() );
	
			$client->mp3filehandle->open("$ogg_cmd | $lame_cmd |");
			$client->mp3filehandleIsSocket(1);
			$client->remoteStreamStartTime(time());
		} elsif((Slim::Music::Info::isWav($fullpath) || Slim::Music::Info::isAIFF($fullpath)) && Slim::Utils::Prefs::get("transcode-wav")) {
			$::d_playlist && msg("openSong: this is an WAV or AIFF file: $fullpath\n");
			my $samplerate = Slim::Utils::Prefs::get("wavmp3samplerate");
			my $lamebin = Slim::Utils::Misc::findbin('lame');
			if (!$lamebin) { return undef; }

			my $lame_cmd = qq("$lamebin" --silent -h -b $samplerate "$filepath" -) . (Slim::Utils::OSDetect::OS() eq 'win' ? "" : " &");
	
			$client->mp3filehandle( FileHandle->new() );
			$client->mp3filehandle->open( "$lame_cmd |");
			$client->mp3filehandleIsSocket(1);
			$client->remoteStreamStartTime(time());
		} else {
			$::d_playlist && msg("Song is of unrecognized type " . Slim::Music::Info::contentType($fullpath) . "! Stopping! $fullpath\n");
			return undef;
		}
		$client->songtotalbytes($size);
		$client->songduration($duration);
		$client->songoffset($offset);

	} else {
		$::d_playlist && msg("Next item is of unrecognized type! Stopping! $fullpath\n");
		return undef;
	}

	######################
	# make sure the filehandle was actually set
	if ($client->mp3filehandle()) {
		binmode($client->mp3filehandle());
		Slim::Web::History::record(Slim::Player::Playlist::song($client));
	} else {
		$::d_playlist && msg("Can't open [$fullpath] : $!");

		my $line1 = string('PROBLEM_OPENING');
		my $line2 = Slim::Music::Info::standardTitle($client, Slim::Player::Playlist::song($client));		
		Slim::Display::Animation::showBriefly($client, $line1, $line2, 5,1);
		return undef;
	}

	Slim::Player::Playlist::refreshPlaylist($client);
	
	Slim::Control::Command::executeCallback($client,  ['open', $fullpath]);

	return 1;
}

sub readNextChunk {
	my $client = shift;
	my $givenChunkSize = shift;
	
	if (!defined($givenChunkSize)) {
		$givenChunkSize = Slim::Utils::Prefs::get('udpChunkSize') * 10;
	} 
	
	my $chunksize = $givenChunkSize;
	
	my $chunk  = 0;

	if ($client->mp3filehandle()) {
	
		my $isRemoteStream = $client->mp3filehandleIsSocket && Slim::Music::Info::isHTTPURL(Slim::Player::Playlist::song($client));
		
		if ($isRemoteStream) {
			# If the MP3 file handle is a remote stream and it's not readable,
			# just return instead of blocking here. The client will repeat the
			# request.
			#
			my $selRead = IO::Select->new();
			$selRead->add($client->mp3filehandle);
			my ($selCanRead,$selCanWrite)=IO::Select->select($selRead,undef,undef,0);
			if (!$selCanRead) {
				#$::d_playlist && msg("remote stream not readable\n");
				return undef;
			} else {
				#$::d_playlist && msg("remote stream readable.\n");
			}

			# adjust chunksize to lie on metadata boundary (for shoutcast/icecast)
			if ($client->shoutMetaInterval() &&
				($client->shoutMetaPointer() + $chunksize) > $client->shoutMetaInterval()) {
	
				$chunksize = $client->shoutMetaInterval() - $client->shoutMetaPointer();
			}
		} else {
			# don't send extraneous ID3 data at the end of the file
			my $size = $client->songtotalbytes();
			my $pos = $client->songpos();
			
			if ($pos + $chunksize > $size) {
				$chunksize = $size - $pos;
				$::d_playlist && msg( "Reduced chunksize to $chunksize at end of file");
			}
		}

		$client->mp3filehandle()->read($chunk, $chunksize);
		
		if ($isRemoteStream) {
			$client->shoutMetaPointer($client->shoutMetaPointer() + length($chunk));
	
			# handle instream metadata for shoutcast/icecast
			if ($client->shoutMetaPointer() == $client->shoutMetaInterval()) {
	
				Slim::Web::RemoteStream::readMetaData($client);
				$client->shoutMetaPointer(0);
			}
		}
	} else {
		$::d_playlist && msg($client->id() . ": No filehandle to read from, returning no chunk.\n");
		$::d_playlist && bt();
		return undef;
	}

	# if nothing was read from the filehandle, then we're done with it,
	# so open the next filehandle.
	if (length($chunk) == 0 ||
		(!$client->mp3filehandleIsSocket && $client->songtotalbytes() != 0 && ($client->songpos()) > $client->songtotalbytes())) {
		$::d_playlist && msg("opening next song: chunk length" . length($chunk) . ", song pos: " .
				$client->songpos() . "(tell says: . " . tell($client->mp3filehandle()). "), totalbytes: " . $client->songtotalbytes() . "\n");
		if (!openNext($client)) {
			$::d_playlist && msg("Can't opennext, returning no chunk.");
			return undef;
		}
		
		$client->mp3filehandle()->read($chunk, $givenChunkSize);
		
		if ($client->mp3filehandleIsSocket) {
			$client->shoutMetaPointer(length($chunk));
		}
	}
	
	$client->songpos($client->songpos + length($chunk));
	
	$::d_playlist_verbose && msg("read a chunk of " . length($chunk) . " length\n");
	
	return \$chunk;
}

sub pauseSynced {
	my $client = shift;
	foreach my $everyclient ($client, Slim::Player::Sync::syncedWith($client)) {
		$everyclient->pause();
		rate($everyclient, 0);
	}
}

1;
__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
