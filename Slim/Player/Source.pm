package Slim::Player::Source;

# $Id: Source.pm,v 1.65 2004/03/10 19:20:24 dean Exp $

# SlimServer Copyright (C) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use File::Spec::Functions qw(:ALL);
use FileHandle;
use FindBin qw($Bin);
use IO::Socket qw(:DEFAULT :crlf);
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

use Slim::Control::Command;
use Slim::Display::Display;
use Slim::Utils::Misc;
use Slim::Utils::Scan;
use Slim::Utils::Strings qw(string);

my $TRICKSEGMENTLENGTH = 1.0;
				
my %commandTable = ();

sub systell {
	sysseek($_[0], 0, SEEK_CUR)
}

sub loadConversionTables {
	my @convertFiles;
	$::d_source && msg("loading conversion config files...\n");
	
	push @convertFiles, catdir($Bin, 'convert.conf');
	if (Slim::Utils::OSDetect::OS() eq 'mac') {
		push @convertFiles, $ENV{'HOME'} . "/Library/SlimDevices/convert.conf";
		push @convertFiles, "/Library/SlimDevices/convert.conf";
		push @convertFiles, $ENV{'HOME'} . "/Library/SlimDevices/slimserver-convert.conf";
		push @convertFiles, "/Library/SlimDevices/slimserver-convert.conf";
	}
	push @convertFiles, catdir($Bin, 'slimserver-convert.conf');
	push @convertFiles, catdir($Bin, '.slimserver-convert.conf');
	
	foreach my $convertFileName (@convertFiles) {
		if (open my $convertFile, "<$convertFileName") {
			while (1) {
				my $line = <$convertFile>;
				last if (!defined($line));
				
				my $command = undef;
				
				# get rid of comments and leading and trailing white space
				$line =~ s/#.*$//;
				$line =~ s/^\s//;
				$line =~ s/\s$//;
	
				if ($line =~ /^(\S+)\s+(\S+)\s+(\S+)\s+(\S+)/) {
					my $inputtype = $1;
					my $outputtype = $2;
					my $clienttype = $3;
					my $clientid = lc($4);
					$command = <$convertFile>;
					$command =~ s/^\s//;
					$command =~ s/\s$//;
					$::d_source && msg( "input: '$inputtype' output: '$outputtype' clienttype: '$clienttype': clientid: '$clientid': '$command'\n");					
					if (defined($command)) {
						$commandTable{"$inputtype-$outputtype-$clienttype-$clientid"} = $command;
					}
				}
			}
			close $convertFile;
		}
	}
}

sub init {
	loadConversionTables();
	Slim::Networking::Slimproto::setEventCallback('STMu', \&underrun);
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

		$::d_source && msg("switching rate from $oldrate to $newrate\n") && bt();

	 	if ($newrate != 0) {
	 		$::d_source && msg("rate change, jumping to the current position in order to restart the stream\n");
			gototime($client, "+0");
		}
	}

	$client->rate($newrate);
}

sub time2offset {
	my $client	= shift;
	my $time	= shift;
	
	my $size	= $client->songtotalbytes();
	my $duration	= $client->songduration();
	my $align = $client->songblockalign();
	
	my $byterate	= $duration ? ($size / $duration) : 0;
	
	my $offset	= int($byterate * $time);
	
	$offset -= $offset % $align;
	
	$::d_source && msg( "$time to $offset (align: $align size: $size duration: $duration)\n");
	
	return $offset;
}

# fractional progress (0 - 1.0) of playback in the current song.
sub progress {

	my $client = Slim::Player::Sync::masterOrSelf(shift);
	
	my $songduration = $client->songduration();

	return 0 unless $songduration;
	return songTime($client) / $songduration;
}

sub songTime {

	my $client = Slim::Player::Sync::masterOrSelf(shift);

	# this used to check against == 1, however, we can't properly
	# calculate duration for non-native formats (pcm, mp3) unless we treat
	# the file as streaming. do this for all files right now.
	if ($client->audioFilehandleIsSocket()) {

		my $startTime = $client->remoteStreamStartTime();
		my $endTime = $client->pauseTime() || Time::HiRes::time();
		
		if ($startTime) {
			return $endTime - $startTime;
		} else {
			return 0;
		}
	}

	my $songLengthInBytes	= $client->songtotalbytes();
	my $duration	  	= $client->songduration();
	my $byterate	  	= $duration ? ($songLengthInBytes / $duration) : 0;

	my $bytesReceived 	= ($client->bytesReceived() || 0) - $client->bytesReceivedOffset();
	my $fullness	  	= $client->bufferFullness() || 0;
	my $realpos	  	= $bytesReceived - $fullness;
	my $rate	  	= $client->rate();
	my $startStream	  	= $client->songStartStreamTime();

	#
	if ($realpos < 0) {
		$::d_source && msg("Negative position calculated, we are still playing out the previous song.\n");	
		$::d_source && msg("realpos $realpos calcuated from bytes received: " . 
			$client->bytesReceived() . 
			" minus bytes offset: " . $client->bytesReceivedOffset() . 
			" minus buffer fullness: " . $client->bufferFullness() . "\n");

		$realpos = 0;
	}

	my $songtime = $songLengthInBytes ? (($realpos / $songLengthInBytes * $duration * $rate) + $startStream) : 0;

	$::d_source && msg("songTime: [$songtime] = ($realpos(realpos) / $songLengthInBytes(size) * $duration(duration) " . 
		"* $rate(rate)) + $startStream(time offset of started stream)\n");

	return $songtime;
}	

# playmode - start playing, pause or stop
sub playmode {
	my($client, $newmode) = @_;

	assert($client);
	my $master = Slim::Player::Sync::masterOrSelf($client);

	if (defined($newmode)) {
	
		$::d_source && $newmode && msg($client->id() . ": Switching to mode $newmode\n");
	
		my $prevmode = $client->playmode;
	
		if ($newmode eq $prevmode) {
			$::d_source && msg(" Already in playmode $newmode : ignoring mode change\n");
		} else {
			if ($newmode eq "pause" && $client->rate != 1) {
				$newmode = "pausenow";
			}
			
			# if we're playing, then open the new song the master.		
			if ($newmode eq "play") {
				my $opened;
				
				# if the player is off, we automatically power on when we start to play
				if (!$client->power()) {
					$client->power(1);
				}
				
				$opened = openSong($master);
	
				# if we couldn't open the song, then stop...
				if (!$opened) {
					$::d_source && msg("Couldn't open song.  Stopping.\n");
					if (!openNext($client)) {$newmode = "stop";}
				}
			}
			
			# when we change modes, make sure we do it to all the synced clients.
			foreach my $everyclient ($client, Slim::Player::Sync::syncedWith($client)) {
				$::d_source && msg($everyclient->id() . " New play mode: " . $newmode . "\n");
				
				# wake up the display if we've switched modes.
				if ($everyclient->isPlayer()) { Slim::Buttons::ScreenSaver::wakeup($everyclient); };
				
				# when you resume, you go back to play mode
				if (($newmode eq "resume") ||($newmode eq "resumenow")) {
					$everyclient->playmode("play");
					
				} elsif ($newmode eq "pausenow") {
					$everyclient->playmode("pause");
					
				} elsif ($newmode =~ /^playout/) {
					closeSong($everyclient);
					if ($newmode eq 'playout-play') { $everyclient->resume() };
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
				} elsif ($newmode eq "play") {
					$everyclient->readytosync(0);
					$everyclient->volume(Slim::Utils::Prefs::clientGet($everyclient, "volume"));
					$everyclient->play(Slim::Player::Sync::isSynced($everyclient), $master->streamformat());				
				} elsif ($newmode eq "pause") {
					# since we can't count on the accuracy of the fade timers, we unfade them all, but the master calls back to pause everybody
					if ($everyclient eq $client) {
						$everyclient->fade_volume(-0.3125, \&pauseSynced, [$client]);
					} else {
						$everyclient->fade_volume(-0.3125);
					}				
					
				} elsif ($newmode eq "pausenow") {
					$everyclient->pause();
				} elsif ($newmode eq "resumenow") {
					$everyclient->volume(Slim::Utils::Prefs::clientGet($everyclient, "volume"));
					$everyclient->resume();
					
				} elsif ($newmode eq "resume") {
					# set volume to 0 to make sure fade works properly
					$everyclient->volume(0);
					$everyclient->resume();
					$everyclient->fade_volume(.3125);
					
				} elsif ($newmode =~ /^playout/) {
					$everyclient->playout();
				} else {
					$::d_source && msg(" Unknown play mode: " . $everyclient->playmode . "\n");
					return $everyclient->playmode();
				}
				Slim::Player::Playlist::refreshPlaylist($everyclient);
			}
		}
	$::d_source && msg($client->id() . ": Current playmode: " . $client->playmode() . "\n");
	}
	my $returnedmode = $client->playmode();
	
	$returnedmode = 'play' if ($returnedmode =~ /^play/);
	
	return $returnedmode;
}

sub underrun {
	my $client = shift;
	
	$client->readytosync(-1);
	
	$::d_source && msg($client->id() . ": Underrun while this mode: " . $client->playmode() . "\n");

	# the only way we'll get an underrun event while stopped is if we were playing out.  so we need to open the next item and play it!
	# if we're synced, then we let resync handle this
	if ($client && ($client->playmode eq 'playout-play' || $client->playmode eq 'stop') && !Slim::Player::Sync::isSynced($client)) {
		skipahead($client);
	} elsif ($client && ($client->playmode eq 'playout-stop') && !Slim::Player::Sync::isSynced($client)) {
		playmode($client, 'stop');
		$client->update();
	}
}

sub skipahead {
	my $client = shift;
	$::d_source && msg("**skipahead: stopping\n");
	playmode($client, 'stop');
	$::d_source && msg("**skipahead: opening next song\n");
	openNext($client);
	$::d_source && msg("**skipahead: restarting after underrun\n");
	playmode($client, 'play');
} 

sub nextChunk {
	my $client = shift;
	my $maxChunkSize = shift;
	my $chunkRef;

	# if there's a chunk in the queue, then use it.
	if (scalar(@{$client->chunks})) {
		$chunkRef = shift @{$client->chunks};

	} else {
		#otherwise, read a new chunk
		my $readfrom = Slim::Player::Sync::masterOrSelf($client);
			
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
			$::d_source && msg("chunk too big, pushing the excess for later.\n");
			
			my $queued = substr($$chunkRef, $maxChunkSize - $len, $len - $maxChunkSize);

			unshift @{$client->chunks}, \$queued;
			
			my $returned = substr($$chunkRef, 0, $maxChunkSize);
			$chunkRef = \$returned;
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

	my $client  = Slim::Player::Sync::masterOrSelf(shift);
	my $newtime = shift;
	
	return unless Slim::Player::Playlist::song($client);
	return unless defined $client->audioFilehandle();

	my $songLengthInBytes   = $client->songtotalbytes();
	my $duration		= $client->songduration();

	return if (!$songLengthInBytes || !$duration);

	my $oldtime = songTime($client);

	if ($newtime =~ /^[\+\-]/) {
		$::d_source && msg("gototime: relative jump $newtime from current time $oldtime\n");
		$newtime += $oldtime;
	}
	
	my $newoffset = time2offset($client, $newtime);
	
	$::d_source && msg("gototime: going to time $newtime, offset $newoffset from old time: $oldtime\n");

	# skip to the previous or next track as necessary
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
			$newtime = $client->songduration - ((-$newoffset) * $duration / $songLengthInBytes);
			$::d_source && msg("gototime: skipping backwards to the previous track to time $newtime\n");
		}

		gototime($client, $newtime);
		return;
	}

	foreach my $everybuddy ($client, Slim::Player::Sync::slaves($client)) {
		$::d_source && msg("gototime: stopping playback\n");
		$everybuddy->stop();
		@{$everybuddy->chunks} = ();
	}

	my $dataoffset =  $client->songoffset;
	$client->songBytes($newoffset);
	$client->lastskip($newoffset);
	$client->audioFilehandle->sysseek($newoffset+$dataoffset, 0);
	$client->songStartStreamTime($newtime);

	foreach my $everybuddy ($client, Slim::Player::Sync::slaves($client)) {
		$::d_source && msg("gototime: restarting playback\n");
		$everybuddy->readytosync(0);
		$everybuddy->play(Slim::Player::Sync::isSynced($client), $client->streamformat());
	}
}

# jumpto - set the current song to a given offset
sub jumpto {
	my ($client, $offset) = @_;

	my ($songcount) = Slim::Player::Playlist::count($client);

	if ($songcount == 0) {
		return;
	}

	playmode($client,"stop");

	if ($songcount != 1) {

		if ($offset =~ /[\+\-]\d+/) {
			currentSongIndex($client, currentSongIndex($client) + $offset);
			$::d_source && msgf("jumping by %s\n", $offset);
		} else {
			currentSongIndex($client, $offset);
			$::d_source && msgf("jumping to %s\n", $offset);
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
	$::d_source && msg("opening next song...\n"); 
	my $client = shift;
	my $result = 1;
	
	my $oldstreamformat = $client->streamformat;
	my $nextsong;
	closeSong($client);

	# we're at the end of a song, let's figure out which song to open up.
	# if we can't open a song, skip over it until we hit the end or a good song...
	do {
	
		if (Slim::Player::Playlist::repeat($client) == 2  && $result) {
			$nextsong = nextsong($client);
		} elsif (Slim::Player::Playlist::repeat($client) == 1 && $result) {
			#play the same song again
		} else {
			#stop at the end of the list or when list is empty
			if (currentSongIndex($client) == (Slim::Player::Playlist::count($client) - 1) || !Slim::Player::Playlist::count($client)) {
				$nextsong = 0;
				currentSongIndex($client, $nextsong);
				playmode($client, $result ? 'playout-stop' : 'stop');
				$client->update();
				return 0;
			} else {
				$nextsong = nextsong($client);
			}
		}

		my ($command, $type, $newstreamformat) = getCommand($client, Slim::Player::Playlist::song($client, $nextsong));
		
		if ((playmode($client) eq 'play') && (($oldstreamformat ne $newstreamformat) || Slim::Player::Sync::isSynced($client))) {
			$::d_source && msg("playing out before starting next song. (old format: $oldstreamformat, new: $newstreamformat)\n");
			playmode($client, 'playout-play');
			return 0;
		} else {
			currentSongIndex($client, $nextsong);
			$result = openSong($client);
		}

	} while (!$result);
	return $result;
}

sub currentSongIndex {
	my $client = shift;
	my $newindex = shift;

	$client = Slim::Player::Sync::masterOrSelf($client);
	
	if (defined($newindex)) {
		$client->currentsong($newindex);
	}
	
	return $client->currentsong() || 0;
}

# nextsong is for figuring out what the next song will be.
sub nextsong {
	my $client = shift;

	my $nextsong;
	my $currsong = currentSongIndex($client);
	
	return 0 if (Slim::Player::Playlist::count($client) == 0);
	
	my $direction = 1;
	
	if ($client->rate() < 0) { $direction = -1; }
	 
	$nextsong = currentSongIndex($client) + $direction;

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

sub closeSong {
	my $client = shift;

	# close the previous handle to prevent leakage.
	if (defined $client->audioFilehandle()) {
		$client->audioFilehandle->close();
		$client->audioFilehandle(undef);
		$client->audioFilehandleIsSocket(0);
	}	
}

sub resetSong {
	my $client = shift;

	# at the end of a song, reset the song time
	$client->songtotalbytes(0);
	$client->songduration(0);
	$client->bytesReceivedOffset($client->bytesReceived());
	$client->songBytes(0);
	$client->lastskip(0);
	$client->songStartStreamTime(0);
	
	# reset shoutcast variables
	$client->shoutMetaInterval(0);
	$client->shoutMetaPointer(0);
}

sub openSong {
	my $client = shift;
	
	resetSong($client);
	
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

	$::d_source && msg("openSong on: $fullpath\n");
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

				$client->audioFilehandle($sock);
				$client->audioFilehandleIsSocket(1);
				$client->streamformat(Slim::Music::Info::contentType($fullpath));
				$client->remoteStreamStartTime(Time::HiRes::time());
				$client->pauseTime(0);
				defined(Slim::Utils::Misc::blocking($sock,0)) || die "Cannot set remote stream nonblocking";

			# if it's one of our playlists, parse it...
			} elsif (Slim::Music::Info::isList($fullpath)) {

				$::d_source && msg("openSong on a remote list!\n");
				# handle the case that we've actually got a playlist in the list,
				# rather than a stream.

				# parse out the list
				my @items = Slim::Formats::Parse::parseList($fullpath, $sock);
				
				# hack to preserve the title of a song redirected through a playlist
				if ( scalar(@items) == 1 && defined(Slim::Music::Info::title($fullpath))) {
				    Slim::Music::Info::setTitle($items[0], Slim::Music::Info::title($fullpath));
				} 
				
				# close the socket
				$sock->close();
				$sock = undef;
				$client->audioFilehandle(undef);

				# insert the list onto the playlist
				splice @{Slim::Player::Playlist::playList($client)}, currentSongIndex($client), 1, @items;

				# update the shuffle list
				Slim::Player::Playlist::reshuffle($client);

				# try to open the first item in the list, if there is one.
				return openSong($client);

			} else {

				$::d_source && msg("don't know how to handle content for $fullpath\n");
				$sock->close();
				$sock = undef;
				$client->audioFilehandle(undef);
			}
		} 
		
		if (!$sock) {
			$::d_source && msg("Remote stream failed to open, showing message.\n");
			$client->audioFilehandle(undef);
			
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

		my ($size, $duration, $offset, $samplerate, $blockalign) = (0, 0, 0, 0, 0);
		
		# don't try and read this if we're a pipe
		unless (-p $fullpath) {

			$size       = Slim::Music::Info::size($fullpath);
			$duration   = Slim::Music::Info::durationSeconds($fullpath);
			$offset     = Slim::Music::Info::offset($fullpath);
			$samplerate = Slim::Music::Info::samplerate($fullpath);
			$blockalign = Slim::Music::Info::blockalign($fullpath);
			$::d_source && msg("openSong: getting duration  $duration, size $size, and offset $offset for $fullpath\n");
			if (!$size || !$duration) {
				$::d_source && msg("openSong: not bothering opening file with zero size or duration\n");
				return undef;
			}
		}
		# smart bitrate calculations
		my $rate = Slim::Music::Info::bitratenum($fullpath)/1000;
		my $maxRate = Slim::Utils::Prefs::clientGet($client,'transcodeBitrate') 
				|| Slim::Utils::Prefs::clientGet($client,'maxBitrate');
		if (!defined $maxRate) {$maxRate = 0;}
		my ($command, $type, $format) = getCommand($client, $fullpath,(($maxRate > $rate)||($maxRate == 0)));
		
		$::d_source && msg("openSong: this is an $type file: $fullpath\n");
		$::d_source && msg("  file type: $type format: $format inrate: $rate maxRate: $maxRate\n");
		$::d_source && msg("  command: $command\n");
		if (defined($command)) {
			# this case is when we play the file through as-is
			if ($command eq '-') {
				$client->audioFilehandle( FileHandle->new() );		
				$::d_source && msg("openSong: opening file $filepath\n");
				if ($client->audioFilehandle->open($filepath)) {

					$::d_source && msg(" seeking in $offset into $filepath\n");

					if ($offset) {
						if (!defined(sysseek($client->audioFilehandle, $offset, 0))) {
							msg("couldn't seek to $offset for $filepath");
						};
					}

					# pipe is a socket
					if (-p $fullpath) {
						$client->audioFilehandleIsSocket(1);
					} else {
						$client->audioFilehandleIsSocket(0);
					}

				} else { 
					$client->audioFilehandle(undef);
				}
							
			} else {
				
				my $fullCommand = $command;
	
				$fullCommand =~ s/\$FILE\$/"$filepath"/g;
				$fullCommand =~ s/\$URL\$/"$fullpath"/g;
				$fullCommand =~ s/\$RATE\$/$samplerate/g;
				
				my $swap = (unpack('n', pack('s', 1)) == 1) ? "" : "-x";
				$fullCommand =~ s/\$-x\$/$swap/g;
				
				#if player setting is 0 or we have no birate defined, use the server fallback of 320
				if ((!defined $maxRate) || !$maxRate) {$maxRate = Slim::Utils::Prefs::get('maxBitrate');}				
				$fullCommand =~ s/\$BITRATE\$/$maxRate/g;
				
				$fullCommand =~ s/\$([^\$]+)\$/'"' . Slim::Utils::Misc::findbin($1) . '"'/eg;

				$fullCommand .= (Slim::Utils::OSDetect::OS() eq 'win') ? "" : " &";

				$fullCommand .= ' |';
				
				$::d_source && msg("Using command for conversion: $fullCommand\n");

				$client->audioFilehandle( FileHandle->new() );
				$client->audioFilehandle->open($fullCommand);
				$client->audioFilehandleIsSocket(2);
				
				$client->remoteStreamStartTime(Time::HiRes::time());
				$client->pauseTime(0);
				
				$size   = $duration * ($maxRate * 1000) / 8;
				$offset = 0;
			}
		
			$client->songtotalbytes($size);
			$client->songduration($duration);
			$client->songoffset($offset);
			$client->streamformat($format);
			$client->songblockalign($blockalign);
			$::d_source && msg("Streaming with format: $format\n");
		
		} else {

			$::d_source && msg("Couldn't create command line for $type playback (command: $command) for $fullpath\n");
			return undef;
		}

	} else {

		$::d_source && msg("Song is of unrecognized type " . Slim::Music::Info::contentType($fullpath) . "! Stopping! $fullpath\n");
		return undef;
	}

	######################
	# make sure the filehandle was actually set
	if ($client->audioFilehandle()) {
		binmode($client->audioFilehandle());
		Slim::Web::History::record(Slim::Player::Playlist::song($client));
	} else {
		$::d_source && msg("Can't open [$fullpath] : $!\n");

		my $line1 = string('PROBLEM_OPENING');
		my $line2 = Slim::Music::Info::standardTitle($client, Slim::Player::Playlist::song($client));		
		Slim::Display::Animation::showBriefly($client, $line1, $line2, 5,1);
		return undef;
	}

	Slim::Player::Playlist::refreshPlaylist($client);
	
	Slim::Control::Command::executeCallback($client,  ['open', $fullpath]);

	return 1;
}

sub getCommand {
	my $client = shift;
	my $fullpath = shift;
	my $undermax = shift || 0;
	
	my $type = Slim::Music::Info::contentType($fullpath);
	my $player = $client->model();
	my $clientid = $client->id();	
	my $command = undef;
	my $format = undef;
	my @supportedformats;
	my @playergroup = ($client, Slim::Player::Sync::syncedWith($client));
	my %formatcounter;
	
	# make sure we only test formats that are supported.
	foreach my $everyclient (@playergroup) {
		foreach my $supported ($everyclient->formats()) {
			$formatcounter{$supported}++;
		}
	}
	
	foreach my $testformat ($client->formats()) {
		if ($formatcounter{$testformat} == scalar(@playergroup)) {
			push @supportedformats, $testformat;
		}
	}

	foreach my $checkformat (@supportedformats) {

		$::d_source && msg("checking formats for: $type-$checkformat-$player-$clientid\n");

		# TODO: match partial wildcards in IP addresses.
		# todo: pre-check to see if the necessary  binaries are installed.
		# use Data::Dumper; print Dumper(\%commandTable);
		$command = $commandTable{"$type-$checkformat-$player-$clientid"};
		if (defined($command)) {
			$::d_source && msg("Matched $type-$checkformat-$player-$clientid\n");
		} else {
			$command = $commandTable{"$type-$checkformat-*-$clientid"};
		}
		if (defined $command) {
			$::d_source && msg("Matched $type-$checkformat-$player-*\n");
		} else {
			$command = $commandTable{"$type-$checkformat-$player-*"};
		}
		if (defined($command)) {
			$::d_source && msg("Matched $type-$checkformat-$player-*\n");
		} else {
			$command = $commandTable{"$type-$checkformat-*-*"};
		}

		$format = $checkformat;
		#special case for mp3 to mp3.
		if (defined $command && $command eq "-" && !$undermax && $type eq "mp3") {
				$command = $commandTable{"$type-$checkformat-downsample-*"};;
				$undermax = 1;
		}
		#only finish if the rate isn't over the limit, or the file is set to transcode to mp3 (which gets set to maxRate)
		last if ($command && ($undermax || ($format eq "mp3")))
	}

	if (!defined $command) {
		$::d_source && msg("******* Error:  Didn't find any command matches ******\n");
	}

	return ($command, $type, $format);
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

	if ($client->audioFilehandle()) {
	
		if ($client->audioFilehandleIsSocket) {

			# adjust chunksize to lie on metadata boundary (for shoutcast/icecast)
			if ($client->shoutMetaInterval() &&
				($client->shoutMetaPointer() + $chunksize) > $client->shoutMetaInterval()) {
	
				$chunksize = $client->shoutMetaInterval() - $client->shoutMetaPointer();
				$::d_source && msg("reduced chunksize to $chunksize for metadata\n");
			}

		} else {
		
			# use the rate to seek to an appropriate place in the file.
			my $rate = rate($client);
			
			# if we're scanning
			if ($rate != 0 && $rate != 1) {
				
				my $lastskip = $client->lastskip();
				
				my $now = $client->songBytes();
				
				my $byterate = Slim::Music::Info::bitratenum(Slim::Player::Playlist::song($client)) / 8;
				
				my $tricksegmentbytes = $byterate * $TRICKSEGMENTLENGTH;
				
				$tricksegmentbytes -= $tricksegmentbytes % $client->songblockalign();
				
				# check to see if we've played tricksgementlength seconds worth of audio
				$::d_source && msg("trick mode rate: $rate:  songbytes: $now lastskip: $lastskip byterate: $byterate tricksegmentbytes: $tricksegmentbytes\n");
				if (($now - $lastskip) >= $tricksegmentbytes) { 
					# if so, seek to the appropriate place.  (
					# TODO: make this align on frame and sample boundaries as appropriate)
					# TODO: Make the seek go into the next song, as appropriate.
					my $howfar = ($rate -  $TRICKSEGMENTLENGTH) * $byterate;
					
					$howfar -= $howfar % $client->songblockalign();
					$::d_source && msg("trick mode seeking to: $howfar\n");
					my $seekpos = $now + $howfar;
					
					if ($seekpos < 0) {
						# trying to seek past the beginning, let's let opennext do it's job
						$chunksize = 0;
					} else {
						$client->audioFilehandle->sysseek($seekpos, 0);
						$client->songBytes($client->songBytes() + $howfar);
						$client->lastskip($client->songBytes());
					}
				}
				
				if ($chunksize > $tricksegmentbytes) { $chunksize = $tricksegmentbytes; }
			}

			# don't send extraneous ID3 data at the end of the file
			my $songLengthInBytes = $client->songtotalbytes();
			my $pos		      = $client->songBytes();
			
			if ($pos + $chunksize > $songLengthInBytes) {

				$chunksize = $songLengthInBytes - $pos;
				$::d_source && msg( "Reduced chunksize to $chunksize at end of file ($songLengthInBytes - $pos)\n");

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
		
		if ($chunksize) {

			my $readlen = $client->audioFilehandle()->sysread($chunk, $chunksize);
			
			if (!defined($readlen)) { 

				if ($! != EWOULDBLOCK) {
					$::d_source && msg("readlen undef $!" . ($! + 0) . "\n"); 
					$endofsong = 1; 
				} else {
					$::d_source && msg("would have blocked, will try again later\n");
					return undef;	
				}	

			} elsif ($readlen == 0) { 
				$::d_source && msg("Read to end of file or pipe\n");  
				$endofsong = 1;
			} else {
				$::d_source && msg("Read $readlen bytes from source\n");
			}
			
			if ($client->shoutMetaInterval()) {
				$client->shoutMetaPointer($client->shoutMetaPointer() + $readlen);
				# handle instream metadata for shoutcast/icecast
				if ($client->shoutMetaPointer() == $client->shoutMetaInterval()) {
		
					Slim::Web::RemoteStream::readMetaData($client);
					$client->shoutMetaPointer(0);
				}
				elsif ($client->shoutMetaPointer() > $client->shoutMetaInterval()) {
					msg("Problem: the shoutcast metadata overshot the interval.\n");
				}	
			}
		}
	} else {
		$::d_source && msg($client->id() . ": No filehandle to read from, returning no chunk.\n");
		return undef;
	}

	# if nothing was read from the filehandle, then we're done with it,
	# so open the next filehandle.
	if ($endofsong) {
		$::d_source && msg("end of file or error on socket, opening next song, (song pos: " .
				$client->songBytes() . "(tell says: . " . systell($client->audioFilehandle()).
				"), totalbytes: " . $client->songtotalbytes() . ")\n");

		if (!openNext($client)) {
			$::d_source && msg($client->id() . ": Can't opennext, returning no chunk.\n");
		}
		
		# we'll have to be called again to get a chunk from the next song.
		return undef;
	}
	
	$::d_source_v && msg("read a chunk of " . length($chunk) . " length\n");
	$::d_source_v && msg( "metadata now: " . $client->shoutMetaPointer . "\n");
	$client->songBytes($client->songBytes + length($chunk));
	
	return \$chunk;
}

sub pauseSynced {
	my $client = shift;

	foreach my $everyclient ($client, Slim::Player::Sync::syncedWith($client)) {
		$everyclient->pause();
	}
}

1;
__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
