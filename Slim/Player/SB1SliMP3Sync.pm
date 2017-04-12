package Slim::Player::SB1SliMP3Sync;

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# $Id$
#

use strict;

use Slim::Utils::Log;
use Slim::Utils::Misc;

my $log = logger('player.sync');

# Only works for SliMP3s and (maybe) SB1s
sub apparentStreamStartTime {
	my ($client, $statusTime) = @_;

	my $bytesPlayed = $client->bytesReceived()
						- $client->bufferFullness()
						- ($client->model() eq 'slimp3' ? 2000 : 2048);

	my $format = $client->master()->streamformat() || '';

	my $timePlayed;

	if ( $format eq 'mp3' ) {
		$timePlayed = _findTimeForOffset($client, $bytesPlayed) or return;
	}
	elsif ( $format =~ /wav|aif|pcm/ ) {
		$timePlayed = $bytesPlayed * 8 / ($client->streamingSong()->streambitrate() or return);
	}
	else {
		return;
	}

	my $apparentStreamStartTime = $statusTime - $timePlayed;

	if (main::DEBUGLOG && $log->is_debug ) {
		$log->debug(
			$client->id()
			. " apparentStreamStartTime: $apparentStreamStartTime @ $statusTime \n"
			. "timePlayed:$timePlayed (bytesReceived:" . $client->bytesReceived()
			. " bufferFullness:" . $client->bufferFullness()
			.")"
		);
	}

	return $apparentStreamStartTime;
}

use constant FRAME_BYTE_OFFSET => 0;
use constant FRAME_TIME_OFFSET => 1;

sub purgeOldFrames {
	my $frames     = $_[0] or return;
	my $timeOffset = $_[1];

	my ($i, $j, $k) = (0, @{$frames} - 1);

	# sanity checks
	return if $timeOffset < $frames->[$i][FRAME_TIME_OFFSET];
	if ( $timeOffset > $frames->[$j][FRAME_TIME_OFFSET] ) {
		main::DEBUGLOG && $log->debug("timeOffset $timeOffset beyond last entry: $frames->[$j][FRAME_TIME_OFFSET]");
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
	
	if ( main::DEBUGLOG && $log->is_debug ) {
		$log->debug(
			"timeOffset $timeOffset; removing "
			. ($j+1) . " frames from total " . scalar(@{$frames}) 
		);
	}
	
	splice @{$frames}, 0, $j+1;	
}

sub _findTimeForOffset {
	my $controller = $_[0]->master()->controller();
	my $byteOffset = $_[1];
	my $buffer     = $controller->initialStreamBuffer() or return;
	my $frames     = $controller->frameData();

	return unless $byteOffset;

	# check if there are any frames to analyse
	if ( length($$buffer) > 1500 ) { # make it worth our while
	
		my $pos = 0;
		
		# XXX: MPEG::Audio::Frame use here is not ideal, but it's the only place
		# we use it, and it's not a trivial amount of work to port this to Audio::Scan
		require MPEG::Audio::Frame;
		
		while ( my ($length, $nextPos, $seconds) = MPEG::Audio::Frame->read_ref($buffer, $pos) ) {
			last unless ($length);
			# Note: $length may not equal ($nextPos - $pos) if tag data has been skipped
			if ( !defined($frames) ) {
				$controller->frameData( $frames = [[$nextPos - $length, 0]] );
				push @{$frames}, [$nextPos, $seconds];
			}
			else {
				my $off = $frames->[-1][FRAME_BYTE_OFFSET] + $nextPos - $pos;
				my $tim = $frames->[-1][FRAME_TIME_OFFSET] + $seconds;
				push @{$frames}, [$off, $tim];
			}
			
			if (main::INFOLOG &&  $log->is_info && ($length != $nextPos - $pos) ) {
				$log->info("recordFrameOffset: ", $nextPos - $pos - $length, " bytes skipped");
			}
			$pos = $nextPos;

			if ( main::DEBUGLOG && $log->is_debug ) {
				$log->debug("recordFrameOffset: $frames->[-1][FRAME_BYTE_OFFSET] -> $frames->[-1][FRAME_TIME_OFFSET]");
			}
		}

		if ($pos) {
			my $newBuffer = substr $$buffer, $pos;
			$controller->initialStreamBuffer(\$newBuffer);
		} else {
			main::INFOLOG && $log->info("recordFrameOffset: found no frames in buffer length ", length($$buffer));
		}
	}

	return unless ( $frames && @{$frames} && @{$frames} > 1 );

	my ($i, $j, $k) = (0, @{$frames} - 1);

	# sanity check
	unless ($frames->[$i][FRAME_BYTE_OFFSET] <= $byteOffset && $byteOffset <= $frames->[$j][FRAME_BYTE_OFFSET]) {
		main::DEBUGLOG && $log->debug("byteOffset $byteOffset outside frame range: $frames->[$i][FRAME_BYTE_OFFSET] .. $frames->[$j][FRAME_BYTE_OFFSET]");
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

	main::DEBUGLOG && $log->debug("$byteOffset -> $timeOffset");

	return $timeOffset;
}

sub saveStreamData {
	my ($controller, $chunkref) = @_;
	
	return unless ($controller->activePlayers() > 1);
	
	my $master = $controller->master();

	if (my $buf = $controller->initialStreamBuffer()) {
		$$buf .= $$chunkref;
		
		# Safety check - just make sure that we are not in the process
		# of slurping up a perhaps-infinite stream without using it.
		# We assume min frame size of 72 bytes (24kb/s, 48000 samples/s)
		# which gives us at most 45512 frames in the decode buffer (25Mb)
		# and 355 samples in the output buffer (also 25Mb) at 1152 samples/frame
		if (length($$buf) > 3_500_000 ||
			defined($controller->frameData) && @{$controller->frameData} > 50_000)
		{
			$log->warn('Discarding saved stream & frame data used for synchronization as appear to be collecting it but not using it');
			$controller->resetFrameData();
		}
	} elsif ($master->streamformat() eq 'mp3' && $master->streamBytes() <= length($$chunkref)) {
		# do we need to save frame data?
		my $needFrameData = 0;
		foreach ($controller->activePlayers()) {
			my $model = $_->model();
			last if $needFrameData = ($model eq 'slimp3' || $model eq 'squeezebox');
		}
		if ($needFrameData) {		
			my $savedChunk = $$chunkref; 	# copy
			$controller->initialStreamBuffer(\$savedChunk);
		}
	}
}


1;

__END__
