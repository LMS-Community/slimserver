package Slim::Player::SqueezeSlave;

# $Id$

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

use strict;
use base qw(Slim::Player::Squeezebox);

use MIME::Base64;
use Scalar::Util qw(blessed);

use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;

my $prefs = preferences('server');

our $defaultPrefs = {
	'replayGainMode'     => 0,
	'remoteReplayGain'   => -5,
	'minSyncAdjust'      => 30, # ms
	'maxBitrate'         => 0,  # no bitrate limiting
};

$prefs->setValidate({ 'validator' => 'numlimit', 'low' => -20, 'high' => 20 }, 'remoteReplayGain');

sub initPrefs {
	my $client = shift;

	# make sure any preferences unique to this client may not have set are set to the default
	$prefs->client($client)->init($defaultPrefs);

	$client->SUPER::initPrefs();
}

sub maxBass { 50 };
sub minBass { 50 };
sub maxTreble { 50 };
sub minTreble { 50 };
sub maxPitch { 100 };
sub minPitch { 100 };

sub model {
	return 'squeezeslave';
}

sub modelName { 'Squeezeslave' }

sub hasIR { 1 }

# in order of preference based on whether we're connected via wired or wireless...
sub formats {
	my $client = shift;
	
	return qw(ogg flc pcm mp3);
}

# The original Squeezebox2 firmware supported a fairly narrow volume range
# below unity gain - 129 levels on a linear scale represented by a 1.7
# fixed point number (no sign, 1 integer, 7 fractional bits).
# From FW 22 onwards, volume is sent as a 16.16 value (no sign, 16 integer,
# 16 fractional bits), significantly increasing our fractional range.
# Rather than test for the firmware level, we send both values in the 
# volume message.

# We thought about sending a dB scale volume to the client, but decided 
# against it. Sending a fixed point multiplier allows us to change 
# the mapping of UI volume settings to gain as we want, without being
# constrained by any scale other than that of the fixed point range allowed
# by the client.

# Old style volume:
# we only have 129 levels to work with now, and within 100 range,
# that's pretty tight.
# this table is optimized for 40 steps (like we have in the current player UI.
my @volume_map = ( 
0, 1, 1, 1, 2, 2, 2, 3,  3,  4, 
5, 5, 6, 6, 7, 8, 9, 9, 10, 11, 
12, 13, 14, 15, 16, 16, 17, 18, 19, 20, 
22, 23, 24, 25, 26, 27, 28, 29, 30, 32, 
33, 34, 35, 37, 38, 39, 40, 42, 43, 44, 
46, 47, 48, 50, 51, 53, 54, 56, 57, 59, 
60, 61, 63, 65, 66, 68, 69, 71, 72, 74, 
75, 77, 79, 80, 82, 84, 85, 87, 89, 90, 
92, 94, 96, 97, 99, 101, 103, 104, 106, 108, 110, 
112, 113, 115, 117, 119, 121, 123, 125, 127, 128
 );

sub dBToFixed {
	my $client = shift;
	my $db = shift;

	# Map a floating point dB value to a 16.16 fixed point value to
	# send as a new style volume to SB2 (FW 22+).
	my $floatmult = 10 ** ($db/20);
	
	# use 8 bits of accuracy for dB values greater than -30dB to avoid rounding errors
	if ($db >= -30 && $db <= 0) {
		return int($floatmult * (1 << 8) + 0.5) * (1 << 8);
	}
	else {
		return int(($floatmult * (1 << 16)) + 0.5);
	}
}

sub canDoReplayGain {
	my $client = shift;
	my $replay_gain = shift;

	if (defined($replay_gain)) {
		return $client->dBToFixed($replay_gain);
	}

	return 0;
}

sub volume {
	my $client = shift;
	my $newvolume = shift;

	my $volume = $client->Slim::Player::Client::volume($newvolume, @_);
	my $preamp = 255 - int(2 * ($prefs->client($client)->get('preampVolumeControl') || 0));

	if (defined($newvolume)) {
		# Old style volume:
		my $oldGain = $volume_map[int($volume)];
		
		my $newGain;
		if ($volume == 0) {
			$newGain = 0;
		}
		else {
			# With new style volume, let's try -49.5dB as the lowest
			# value.
			my $db = ($volume - 100)/2;	
			$newGain = $client->dBToFixed($db);
		}

		my $data = pack('NNCCNN', $oldGain, $oldGain, $prefs->client($client)->get('digitalVolumeControl'), $preamp, $newGain, $newGain);
		$client->sendFrame('audg', \$data);
	}
	return $volume;
}

sub upgradeFirmware {
	
}

sub needsUpgrade {
	return 0;
}

sub requestStatus {
	shift->stream('t');
}

sub stop {
	my $client = shift;
	$client->SUPER::stop(@_);
	# Preemptively set the following state variables
	# to 0, since we rely on them for time display and may
	# have to wait to get a status message with the correct
	# values.
	$client->outputBufferFullness(0);

}

sub songElapsedSeconds {
	my $client = shift;
	
	return 0 if $client->isStopped() || defined $_[0];

	my ($jiffies, $elapsedMilliseconds, $elapsedSeconds) = Slim::Networking::Slimproto::getPlayPointData($client);

	return 0 unless $elapsedMilliseconds || $elapsedSeconds;
	
	# Use milliseconds for the song-elapsed-time if has not suffered truncation
	my $songElapsed;
	if (defined $elapsedMilliseconds) {
		$songElapsed = $elapsedMilliseconds / 1000;
		if ($songElapsed < $elapsedSeconds) {
			$songElapsed = $elapsedSeconds + ($elapsedMilliseconds % 1000) / 1000;
		}
	} else {
		$songElapsed = $elapsedSeconds;
	}
	
	if ($client->isPlaying(1)) {
		my $timeDiff = Time::HiRes::time() - $client->jiffiesToTimestamp($jiffies);
		#logBacktrace($client->id, ": songElapsed=$songElapsed, jiffies=$jiffies, timeDiff=$timeDiff");
		$songElapsed += $timeDiff if ($timeDiff > 0);
	}
	
	return $songElapsed;
}

sub canDirectStream {
	return undef;
}
	
sub hasPreAmp {
	return 1;
}
sub hasDigitalOut {
	return 0;
}
sub hasPowerControl {
	return 0;
}

sub pcm_sample_rates {
	my $client = shift;
	my $track = shift;

    	my %pcm_sample_rates = ( 8000 => '5',
				 11025 => '0',
				 12000 => '6',
				 22050 => '1',
				 24000 => '8',
				 32000 => '2',
				 44100 => '3',
				 48000 => '4',
				 16000 => '7',
				 88200 => ':',
				 96000 => '9',
				 );

	my $rate = $pcm_sample_rates{$track->samplerate()};

	return defined $rate ? $rate : '3';
}

sub statHandler {
	my ($client, $code) = @_;
	
	if ($code eq 'STMd') {
		$client->readyToStream(1);
		$client->controller()->playerReadyToStream($client);
	} elsif ($code eq 'STMn') {
		$client->readyToStream(1);
		logError($client->id(). ": Decoder does not support file format");
		$client->controller()->playerStreamingFailed($client, 'PROBLEM_OPENING');
	} elsif ($code eq 'STMl') {
		$client->bufferReady(1);
		$client->controller()->playerBufferReady($client);
	} elsif ($code eq 'STMu') {
		$client->readyToStream(1);
		$client->controller()->playerStopped($client);
	} elsif ($code eq 'STMa') {
		$client->bufferReady(1);
	} elsif ($code eq 'STMc') {
		$client->readyToStream(0);
		$client->bufferReady(0);
		$client->connecting(1); # reset in Slim::Networking::Slimproto::_http_response_handler() upon connection establishment
	} elsif ($code eq 'STMs') {
		$client->controller()->playerTrackStarted($client);
	} elsif ($code eq 'STMo') {
		$client->controller()->playerOutputUnderrun($client);
	} elsif ($code eq 'EoS') {
		$client->controller()->playerEndOfStream($client);
	} else {		
		if ( !$client->bufferReady() && ($client->outputBufferFullness() > 40_000) && $client->isSynced(1) ) {
			# Fake up buffer ready (0.25s audio)
			$client->bufferReady(1);	# to stop multiple starts 
			$client->controller()->playerBufferReady($client);
		} else {
			$client->controller->playerStatusHeartbeat($client);
		}
	}	
	
}

#
# tell the client to unpause the decoder
#
sub resume {
	my ($client, $at) = @_;
	
	if ($at) {
		Slim::Utils::Timers::setHighTimer(
			$client,
			$at - $client->packetLatency(),
			\&_unpauseAfterInterval
		);
	} else {
		$client->stream('u');
	}
	
	$client->SUPER::resume();
	return 1;
}

sub startAt {
	my ($client, $at) = @_;

	Slim::Utils::Timers::killTimers($client, \&_buffering);
	Slim::Utils::Timers::setHighTimer(
			$client,
			$at - $client->packetLatency(),
			\&_unpauseAfterInterval
		);
	return 1;
}

sub _unpauseAfterInterval {
	my $client = shift;
	$client->stream('u');
	$client->playPoint(undef);
	return 1;
}

# Need to use weighted play-point
sub needsWeightedPlayPoint { 1 }

sub playPoint {
	return Slim::Player::Client::playPoint(@_);
}


# We need to implement this to allow us to receive SETD commands
# and we need SETD to support custom display widths
sub directBodyFrame { 
	return 1;
}

# Allow the player to define it's display width
sub playerSettingsFrame {
	my $client   = shift;
	my $data_ref = shift;
	
	my $value;
	my $id = unpack('C', $$data_ref);
        
	# New SETD command 0xfe for display width
	if ($id == 0xfe) { 
		$value = (unpack('CC', $$data_ref))[1];
		if ($value > 10 && $value < 200) {
			$client->display->widthOverride(1, $value);
			$client->update;
		} 
	}
}

1;
