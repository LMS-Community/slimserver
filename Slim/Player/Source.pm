package Slim::Player::Source;

# $Id: Source.pm,v 1.111 2004/09/16 15:34:17 dean Exp $

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
use Slim::Utils::OSDetect;
use Slim::Utils::Scan;
use Slim::Utils::Strings qw(string);
use Slim::Player::Protocols::HTTP;

my $TRICKSEGMENTDURATION = 1.0;
my $FADEVOLUME         = 0.3125;

my %commandTable = ();
my %protocolHandlers = ( 
	http => qw(Slim::Player::Protocols::HTTP),
	icy => qw(Slim::Player::Protocols::HTTP),
);

sub systell {
	sysseek($_[0], 0, SEEK_CUR)
}

sub Conversions {
	return \%commandTable;
}

sub loadConversionTables {

	my @convertFiles = ();

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

		# can't read? next.
		next unless -r $convertFileName;

		open(CONVERT, $convertFileName) || next;

		while (my $line = <CONVERT>) {

			# skip comments and whitespace
			next if $line =~ /^\s*#/;
			next if $line =~ /^\s*$/;

			# get rid of comments and leading and trailing white space
			$line =~ s/#.*$//o;
			$line =~ s/^\s*//o;
			$line =~ s/\s*$//o;
	
			if ($line =~ /^(\S+)\s+(\S+)\s+(\S+)\s+(\S+)$/) {

				my $inputtype  = $1;
				my $outputtype = $2;
				my $clienttype = $3;
				my $clientid   = lc($4);

				my $command = <CONVERT>;

				$command =~ s/^\s*//o;
				$command =~ s/\s*$//o;

				$::d_source && msg(
					"input: '$inputtype' output: '$outputtype' clienttype: " .
					"'$clienttype': clientid: '$clientid': '$command'\n"
				);

				next unless defined $command && $command !~ /^\s*$/;

				$commandTable{"$inputtype-$outputtype-$clienttype-$clientid"} = $command;
			}
		}

		close CONVERT;
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
	
	my $size     = $client->songtotalbytes();
	my $duration = $client->songduration();
	my $align    = $client->songblockalign();
	
	my $byterate = $duration ? ($size / $duration) : 0;

	my $offset   = int($byterate * $time);
	
	if ($client->streamformat() eq 'mp3') {
		($offset, undef) = Slim::Formats::MP3::seekNextFrame($client->audioFilehandle(), $offset, 1);
	} else {
		$offset     -= $offset % $align;
	}
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
		my $endTime   = $client->pauseTime() || Time::HiRes::time();
		
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
			" minus buffer fullness: " . $client->bufferFullness() . "\n");

		$realpos = 0;
	}

	my $songtime = $songLengthInBytes ? (($realpos / $songLengthInBytes * $duration * $rate) + $startStream) : 0;

	if ($songtime && $duration) {
		$::d_source && msg("songTime: [$songtime] = ($realpos(realpos) / $songLengthInBytes(size) * ".
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
		my $duration = $client->songduration() || 0;
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

sub _returnPlayMode {
	my $client = shift;

	my $returnedmode = $client->playmode();
	
	$returnedmode = 'play' if $returnedmode =~ /^play/i;
	
	return $returnedmode;
}

# playmode - start playing, pause or stop
sub playmode {
	my ($client, $newmode) = @_;

	assert($client);

	# Short circuit.
	return _returnPlayMode($client) unless defined $newmode;

	my $master   = Slim::Player::Sync::masterOrSelf($client);

	#
	my $prevmode = $client->playmode();

	$::d_source && bt() && msg($client->id() . ": Switching to mode $newmode from $prevmode\n");

	# don't switch modes if it's the same 
	if ($newmode eq $prevmode) {

		$::d_source && msg(" Already in playmode $newmode : ignoring mode change\n");

		return _returnPlayMode($client);
	}

	if ($newmode eq "play" && $prevmode eq "pause") {
		$newmode = "resume";
	}
	
	# This function is likely doing too much.
	if ($newmode eq "pause" && $client->rate != 1) {
		$newmode = "pausenow";
	}
	
	# if we're playing, then open the new song the master.		
	if ($newmode eq "play") {

		# if the player is off, we automatically power on when we start to play
		if (!$client->power()) {
			$client->power(1);
		}
		
		# if we couldn't open the song, then stop...
		my $opened = openSong($master) || do {

			$::d_source && msg("Couldn't open song.  Stopping.\n");

			$newmode = 'stop' unless openNext($client);
		};

		$client->bytesReceivedOffset(0);
	}
	
	# when we change modes, make sure we do it to all the synced clients.
	foreach my $everyclient ($client, Slim::Player::Sync::syncedWith($client)) {

		$::d_source && msg($everyclient->id() . " New play mode: " . $newmode . "\n");

		next if Slim::Utils::Prefs::clientGet($everyclient,'silent');

		# wake up the display if we've switched modes.
		if ($everyclient->isPlayer()) {
			Slim::Buttons::ScreenSaver::wakeup($everyclient);
		}
		
		# when you resume, you go back to play mode
		if (($newmode eq "resume") ||($newmode eq "resumenow")) {

			$everyclient->playmode("play");
			
		} elsif ($newmode eq "pausenow") {

			$everyclient->playmode("pause");
			
		} elsif ($newmode =~ /^playout/) {

			closeSong($everyclient);
			$everyclient->resume() if $newmode eq 'playout-play';
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
			$everyclient->volume($client->volume(),1);
			$everyclient->streamBytes(0);
			$everyclient->play(Slim::Player::Sync::isSynced($everyclient), $master->streamformat());

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

			$everyclient->volume($everyclient->volume(),1);
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

		Slim::Player::Playlist::refreshPlaylist($everyclient);
	}

	$::d_source && msg($client->id() . ": Current playmode: $newmode\n");

	return _returnPlayMode($client);
}

sub underrun {
	my $client = shift || return;
	
	$client->readytosync(-1);
	
	$::d_source && msg($client->id() . ": Underrun while this mode: " . $client->playmode() . "\n");

	# the only way we'll get an underrun event while stopped is if we were
	# playing out.  so we need to open the next item and play it!
	#
	# if we're synced, then we let resync handle this

	if (($client->playmode eq 'playout-play' || $client->playmode eq 'stop') && !Slim::Player::Sync::isSynced($client)) {

		skipahead($client);

	} elsif (($client->playmode eq 'playout-stop') && !Slim::Player::Sync::isSynced($client)) {

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
	my $client       = shift;
	my $maxChunkSize = shift;

	my $chunk;

	# if there's a chunk in the queue, then use it.
	if (scalar(@{$client->chunks})) {

		$chunk = shift @{$client->chunks};

	} else {
		#otherwise, read a new chunk
		my $readfrom = Slim::Player::Sync::masterOrSelf($client);
			
		$chunk = readNextChunk($readfrom, $maxChunkSize);
			
		if (defined($chunk)) {

			# let everybody I'm synced with use this chunk
			foreach my $buddy (Slim::Player::Sync::syncedWith($client)) {
				push @{$buddy->chunks}, $chunk;
			}
		}
	}
	
	if (defined($chunk)) {

		my $len = length($$chunk);

		if ($len > $maxChunkSize) {
			$::d_source && msg("chunk too big, pushing the excess for later.\n");
			
			my $queued = substr($$chunk, $maxChunkSize - $len, $len - $maxChunkSize);

			unshift @{$client->chunks}, \$queued;
			
			my $returned = substr($$chunk, 0, $maxChunkSize);
			$chunk = \$returned;
		}
	}
	
	return $chunk;
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

	if (!defined $client->audioFilehandle()) {
		return unless openSong($client);
	}

	my $songLengthInBytes = $client->songtotalbytes();
	my $duration	      = $client->songduration();

	return if (!$songLengthInBytes || !$duration);

	if ($newtime =~ /^[\+\-]/) {
		my $oldtime = songTime($client);
		$::d_source && msg("gototime: relative jump $newtime from current time $oldtime\n");
		$newtime += $oldtime;
	}
	
	my $newoffset = time2offset($client, $newtime);
	
	$::d_source && msg("gototime: going to time $newtime\n");

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
		next if (Slim::Utils::Prefs::clientGet($everybuddy,'silent'));
		$everybuddy->stop();
		@{$everybuddy->chunks} = ();
	}

	my $dataoffset = $client->songoffset();

	$client->songBytes($newoffset);
	$client->songStartStreamTime($newtime);

	$client->audioFilehandle()->sysseek($newoffset + $dataoffset, 0);

	foreach my $everybuddy ($client, Slim::Player::Sync::slaves($client)) {

		next if (Slim::Utils::Prefs::clientGet($everybuddy,'silent'));

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
			if (currentSongIndex($client) == (Slim::Player::Playlist::count($client) - 1) ||
				!Slim::Player::Playlist::count($client)) {

				$nextsong = 0;

				currentSongIndex($client, $nextsong);
				playmode($client, $result ? 'playout-stop' : 'stop');

				$client->update();

				return 0;

			} else {

				$nextsong = nextsong($client);
			}
		}

		my ($command, $type, $newstreamformat) = getConvertCommand(
			$client, Slim::Player::Playlist::song($client, $nextsong)
		);
		
		# here's where we decide whether to start the next song in a new stream after playing out
		# the current song or to just continue streaming
		if ((playmode($client) eq 'play') && 
			(($oldstreamformat ne $newstreamformat) || Slim::Player::Sync::isSynced($client)) ||
			$client->rate() != 1) {

			$::d_source && msg(
				"playing out before starting next song. (old format: " .
				"$oldstreamformat, new: $newstreamformat)\n"
			);

			playmode($client, 'playout-play');
			return 0;

		} else {

			$::d_source && msg(
				"opening next song (old format: $oldstreamformat, " .
				"new: $newstreamformat) current playmode: " . playmode($client) . "\n"
			);

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
	$client->songBytes(0);
	$client->songStartStreamTime(0);
	$client->bytesReceivedOffset($client->bytesReceived());
	$client->trickSegmentRemaining(0);
}

sub errorOpening {
	my $client = shift;
	my $line1 = string('PROBLEM_OPENING');
	my $line2 = Slim::Music::Info::standardTitle($client, Slim::Player::Playlist::song($client));
	
	$client->showBriefly($line1, $line2, 1,1);
}

sub openSong {
	my $client = shift;
	
	resetSong($client);
	
	closeSong($client);
	
	my $fullpath = Slim::Player::Playlist::song($client) || return undef;

	$::d_source && msg("openSong on: $fullpath\n");

	####################
	# parse the filetype
	if (Slim::Music::Info::isRemoteURL($fullpath)) {

		my $line1 = string('CONNECTING_FOR');
		my $line2 = Slim::Music::Info::standardTitle($client, Slim::Player::Playlist::song($client));			
		$client->showBriefly($line1, $line2, undef,1);

		# we don't get the content type until after the stream is opened
		my $sock = openRemoteStream($fullpath, $client);

		if ($sock) {

			# if it's an mp3 stream, then let's stream it.
			if (Slim::Music::Info::isSong($fullpath)) {

				$client->audioFilehandle($sock);
				$client->audioFilehandleIsSocket(1);
				$client->streamformat(Slim::Music::Info::contentType($fullpath));
				$client->remoteStreamStartTime(Time::HiRes::time());
				$client->pauseTime(0);
				defined(Slim::Utils::Misc::blocking($sock,0)) || die "Cannot set remote stream nonblocking";

				my $duration  = Slim::Music::Info::durationSeconds($fullpath);
				if (defined($duration)) {
					$client->songduration($duration);
				}

			# if it's one of our playlists, parse it...
			} elsif (Slim::Music::Info::isList($fullpath)) {

				$::d_source && msg("openSong on a remote list!\n");
				# handle the case that we've actually got a playlist in the list,
				# rather than a stream.

				# parse out the list
				my @items = Slim::Formats::Parse::parseList($fullpath, $sock);
				
				# hack to preserve the title of a song redirected through a playlist
				if (scalar(@items) == 1 && defined(Slim::Music::Info::title($fullpath))) {
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

			$client->showBriefly($line1, $line2, 5, 1);

			return undef;
		}

	} elsif (Slim::Music::Info::isSong($fullpath)) {
	
		my $filepath;

		if (Slim::Music::Info::isFileURL($fullpath)) {
			$filepath = Slim::Utils::Misc::pathFromFileURL($fullpath);
		} else {
			$filepath = $fullpath;
		}

		my ($size, $duration, $offset, $samplerate, $blockalign, $endian) = (0, 0, 0, 0, 0, undef);
		
		# don't try and read this if we're a pipe
		unless (-p $filepath) {

			# XXX - endian can be undef here - set to ''.
			$size       = Slim::Music::Info::size($fullpath);
			$duration   = Slim::Music::Info::durationSeconds($fullpath);
			$offset     = Slim::Music::Info::offset($fullpath);
			$samplerate = Slim::Music::Info::samplerate($fullpath);
			$blockalign = Slim::Music::Info::blockalign($fullpath);
			$endian     = Slim::Music::Info::endian($fullpath) || '';

			$::d_source && msg(
				"openSong: getting duration  $duration, size $size, endian " .
				"$endian and offset $offset for $fullpath\n"
			);

			if (!$size || !$duration) {

				$::d_source && msg("openSong: not bothering opening file with zero size or duration\n");
				errorOpening($client);
				return undef;
			}
		}

		# smart bitrate calculations
		my $rate    = (Slim::Music::Info::bitratenum($fullpath) || 0) / 1000;

		# if http client has used the query param, use transcodeBitrate. otherwise we can use maxBitrate.
		my $maxRate = Slim::Utils::Prefs::maxRate($client);

		my ($command, $type, $format) = getConvertCommand($client, $fullpath);
		
		$::d_source && msg("openSong: this is an $type file: $fullpath\n");
		$::d_source && msg("  file type: $type format: $format inrate: $rate maxRate: $maxRate\n");
		$::d_source && msg("  command: $command\n");

		unless (defined($command)) {

			$::d_source && msg(
				"Couldn't create command line for $type playback for $fullpath\n"
			);
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

				$::d_source && msg(" seeking in $offset into $filepath\n");

				if ($offset) {
					if (!defined(sysseek($client->audioFilehandle, $offset, 0))) {
						msg("couldn't seek to $offset for $filepath");
					};
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

			$command = tokenizeConvertCommand($command, $type, $filepath, $fullpath, $samplerate, $maxRate);

			$client->audioFilehandle( FileHandle->new() );
			$client->audioFilehandle->open($command);
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

		$::d_source && msg(
			"Song is of unrecognized type " .
			Slim::Music::Info::contentType($fullpath) .
			"! Stopping! $fullpath\n"
		);
		errorOpening($client);
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

		$client->showBriefly($line1, $line2, 5,1);

		return undef;
	}

	Slim::Player::Playlist::refreshPlaylist($client);
	
	Slim::Control::Command::executeCallback($client,  ['open', $fullpath]);

	# We are starting a new song, lets kill any animation so we see the correct new song.
	foreach my $everyclient ($client, Slim::Player::Sync::syncedWith($client)) { 
		$everyclient->killAnimation();
	}

	return 1;
}

sub enabledFormat {
	my $profile = shift;
	
	$::d_source && msg("Checking to see if $profile is enabled\n");
	
	my $count = Slim::Utils::Prefs::getArrayMax('disabledformats');
	
	return 1 if !defined($count) || $count < 0;

	$::d_source && msg("There are $count disabled formats...\n");
	
	for (my $i = $count; $i >= 0; $i--) {

		my $disabled = Slim::Utils::Prefs::getInd('disabledformats', $i);

		$::d_source && msg("Testing $disabled vs $profile\n");

		if ($disabled eq $profile) {
			$::d_source && msg("!! $profile Disabled!!\n");
			return 0;
		}
	}
	
	return 1;
}

sub checkBin {
	my $profile = shift;
	my $command;
	
	$::d_source && msg("checking formats for: $profile\n");
	
	# if the user's disabled the profile, then skip it...
	return undef unless enabledFormat($profile);
	
	$::d_source && msg("   enabled\n");
	
	# get the command for this profile
	$command = $commandTable{$profile};
	$::d_source && $command && msg("  Found command: $command\n");

	return undef unless $command;
	
	# if we don't have one or more of the requisite binaries, then move on.
	while ($command && $command =~ /\[([^]]+)\]/g) {

		if (!Slim::Utils::Misc::findbin($1)) {
			$command = undef;
			$::d_source && msg("   drat, missing binary $1\n");
		}
	}
			
	return $command;
}


sub underMax {
	my $client = shift;
	my $fullpath = shift;
	my $type = shift;

	$type = Slim::Music::Info::contentType($fullpath) unless defined $type;

	my $maxRate = Slim::Utils::Prefs::maxRate($client);
	# If we're not rate limited, we're under the maximum.
	# If we don't have lame, we can't transcode, so we
	# fall back to saying we're under the maximum.
	return 1 if $maxRate == 0 || (!Slim::Utils::Misc::findbin('lame'));

	# If the input type is mp3, we determine whether the 
	# input bitrate is under the maximum.
	if (defined($type) && $type eq 'mp3') {
		my $rate = (Slim::Music::Info::bitratenum($fullpath) || 0)/1000;
		return ($maxRate >= $rate);
	}
	
	# For now, we assume the output is raw 44.1Khz, 16 bit, stereo PCM
	# in all other cases. In that case, we're over any set maximum. 
	# In the future, we may want to do finer grained testing here - the 
	# PCM may have different parameters  and we may be able to stream other
	# formats.
	return 0;
}

sub getConvertCommand {
	my $client   = shift;
	my $fullpath = shift;
	
	my $type     = Slim::Music::Info::contentType($fullpath);
	my $player   = $client->model();
	my $clientid = $client->id();	
	my $command  = undef;
	my $format   = undef;
	my $lame = Slim::Utils::Misc::findbin('lame');

	my @supportedformats = ();
	my @playergroup      = ($client, Slim::Player::Sync::syncedWith($client));
	my %formatcounter    = ();
	my $audibleplayers   = 0;

	my $undermax = underMax($client,$fullpath,$type);
	$::d_source && msg("undermax = $undermax, type = $type, $player = $clientid, lame = $lame\n");
	
	# make sure we only test formats that are supported.
	foreach my $everyclient (@playergroup) {

		next if Slim::Utils::Prefs::clientGet($everyclient,'silent');

		$audibleplayers++;

		foreach my $supported ($everyclient->formats()) {
			$formatcounter{$supported}++;
		}
	}
	
	foreach my $testformat ($client->formats()) {

		if ($formatcounter{$testformat} == $audibleplayers) {
			push @supportedformats, $testformat;
		}
	}

	foreach my $checkformat (@supportedformats) {
		
		my @profiles = (
			"$type-$checkformat-$player-$clientid",
			"$type-$checkformat-*-$clientid",
			"$type-$checkformat-$player-*",
			"$type-$checkformat-*-*",
		);
		
		foreach my $profile (@profiles) {
			
			$command = checkBin($profile);
			
			last if $command;
		}

		$format = $checkformat;

		# special case for mp3 to mp3 when input is higher than specified max bitrate.
		if (defined $command && $command eq "-" && !$undermax && $type eq "mp3") {
				$command = $commandTable{"$type-lame-*-*"};
				$undermax = 1;
		}

		# only finish if the rate isn't over the limit
		last if ($command && underMax($client,$fullpath,$format));
	}

	if (!defined $command) {
		$::d_source && msg("******* Error:  Didn't find any command matches for type: $type format: $format ******\n");
	} else {
		$::d_source && msg("Matched Format: $format Type: $type Command: $command \n");
	}

	return ($command, $type, $format);
}

sub tokenizeConvertCommand {
	my ($command, $type, $filepath, $fullpath, $samplerate, $maxRate) = @_;

	# XXX what is this?
	my $swap = (unpack('n', pack('s', 1)) == 1) ? "" : "-x";

	# XXX - what is this actually doing? CUE sheet stuff? Ick.
	if ($type eq 'flc') {

		if ($fullpath =~ /#([^-]+)-([^-]+)$/) {

			my ($start, $end) = ($1, $2);

			$command =~ s/\$START\$/Slim::Utils::Misc::fracSecToMinSec($start)/eg;
			$command =~ s/\$END\$/Slim::Utils::Misc::fracSecToMinSec($end)/eg;

		} else {

			$command =~ s/\$START\$/0/g;
			$command =~ s/\$END\$/-0/g;
		}
	}

	# This must come above the FILE substitutions, otherwise it will break
	# files with [] in their names.
	$command =~ s/\[([^\]]+)\]/'"' . Slim::Utils::Misc::findbin($1) . '"'/eg;

	# escape $ and * in file names and URLs.
	$filepath =~ s/([\$\"\`])/\\$1/g;
	$fullpath =~ s/([\$\"\`])/\\$1/g;
	
	$command =~ s/\$FILE\$/"$filepath"/g;
	$command =~ s/\$URL\$/"$fullpath"/g;
	$command =~ s/\$RATE\$/$samplerate/g;
	$command =~ s/\$BITRATE\$/$maxRate/g;
	$command =~ s/\$-x\$/$swap/g;

	$command =~ s/\$([^\$]+)\$/'"' . Slim::Utils::Misc::findbin($1) . '"'/eg;

	$command .= (Slim::Utils::OSDetect::OS() eq 'win') ? '' : ' &';
	$command .= ' |';

	$::d_source && msg("Using command for conversion: $command\n");

	return $command;
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
			my $asilence = Slim::Utils::Prefs::clientGet($buddy,'mp3SilencePrelude');
			$silence = $asilence if ($asilence && ($asilence > $silence));
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

	if ($client->audioFilehandle()) {
	
		if (!$client->audioFilehandleIsSocket) {
			# use the rate to seek to an appropriate place in the file.
			my $rate = rate($client);
			
			# if we're scanning
			if ($rate != 0 && $rate != 1) {
				
				if ($client->trickSegmentRemaining()) {
					# we're in the middle of a trick segment
					$::d_source && msg("still in the middle of a trick segment: ". $client->trickSegmentRemaining() . " bytes remaining\n");
					
				} else {
					# starting a new trick segment, calculate the chunk offset and length
					
					my $now = $client->songBytes();
					
					my $byterate = Slim::Music::Info::bitratenum(Slim::Player::Playlist::song($client)) / 8;
				
					my $howfar = ($rate -  $TRICKSEGMENTDURATION) * $byterate;					
					$howfar -= $howfar % $client->songblockalign();
					$::d_source && msg("trick mode seeking to: $howfar\n");

					my $seekpos = $now + $howfar;

					my $tricksegmentbytes = $byterate * $TRICKSEGMENTDURATION;				

					$tricksegmentbytes -= $tricksegmentbytes % $client->songblockalign();					

					if ($client->streamformat() eq 'mp3') {
						($seekpos, undef) = Slim::Formats::MP3::seekNextFrame($client->audioFilehandle(), $seekpos, 1);
						my (undef, $endsegment) = Slim::Formats::MP3::seekNextFrame($client->audioFilehandle(), $seekpos + $tricksegmentbytes, -1);
						
						if ($seekpos == 0 || $endsegment == 0) {
							$endofsong = 1;
							$::d_source && msg("trick mode couldn't seek: $seekpos/$endsegment\n");
							goto bail;
						} else {
							$tricksegmentbytes = $endsegment - $seekpos + 1;
						}
					}
					
					$::d_source && msg("new trick mode segment offset: $seekpos for length:$tricksegmentbytes\n");

					$client->audioFilehandle->sysseek($seekpos, 0);
					$client->songBytes($client->songBytes() + $seekpos - $now);
					$client->trickSegmentRemaining($tricksegmentbytes);
				}
								
				if ($chunksize > $client->trickSegmentRemaining()) { 
					$chunksize = $client->trickSegmentRemaining(); 
				}
				
			}

			# don't send extraneous ID3 data at the end of the file
			my $songLengthInBytes = $client->songtotalbytes();
			my $pos		      = $client->songBytes();
			
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
					$::d_source && msg("would have blocked, will try again later\n");
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
				"), totalbytes: " . $client->songtotalbytes() . ")\n");

		if (!openNext($client)) {
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
		$client->trickSegmentRemaining($client->trickSegmentRemaining() - $chunkLength) if ($client->trickSegmentRemaining())
	}
	
	return \$chunk;
}

sub pauseSynced {
	my $client = shift;

	foreach my $everyclient ($client, Slim::Player::Sync::syncedWith($client)) {
		next if (Slim::Utils::Prefs::clientGet($everyclient,'silent'));
		$everyclient->pause();
	}
}

sub registerProtocolHandler {
	my $protocol = shift;
	my $class = shift;
	
	$protocolHandlers{$protocol} = $class;
}

sub protocols {
	return keys %protocolHandlers;
}

sub openRemoteStream {
	my $url = shift;
	my $client = shift;
	
	$::d_source && msg("Trying to open protocol stream for $url\n");
	if ($url =~ /^(.*?):\/\//i) {
		my $proto = $1;

		$::d_source && msg("Looking for handler for protocol $proto\n");
		if (my $protoClass = $protocolHandlers{lc $proto}) {
			$::d_source && msg("Found handler for protocol $proto\n");
			return $protoClass->new($url, $client);
		}
	}

	$::d_source && msg("Couldn't find protocol handler for $url\n");
	return undef;
}


1;
__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
