package Slim::Player::Squeezebox2;

# $Id: Squeezebox2.pm 12808 2007-08-31 04:08:54Z andy $

# SlimServer Copyright (c) 2001-2007 Logitech.
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

use File::Spec::Functions qw(:ALL);
use File::Temp;
use IO::Socket;
use MIME::Base64;
use Scalar::Util qw(blessed);

use Slim::Formats::Playlists;
use Slim::Player::Player;
use Slim::Player::ProtocolHandlers;
use Slim::Player::Protocols::HTTP;
use Slim::Player::Protocols::MMS;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Unicode;
use Slim::Utils::Prefs;

my $prefs = preferences('server');

our $defaultPrefs = {
	'replayGainMode'     => 0,
	'minSyncAdjust'      => 30,	# ms
};

# Keep track of direct stream redirects
our $redirects = {};


sub new {
	my $class = shift;

	my $client = $class->SUPER::new(@_);

	bless $client, $class;

	return $client;
}

sub init {
	my $client = shift;

	# make sure any preferences unique to this client may not have set are set to the default
	$prefs->client($client)->init($defaultPrefs);

	$client->SUPER::init();
}

sub reconnect {
	my $client = shift;
	$client->SUPER::reconnect(@_);

	$client->getPlayerSetting('playername');
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

# in order of preference based on whether we're connected via wired or wireless...
sub formats {
	my $client = shift;
	
	return qw(ogg flc wav mp3);
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

sub volume {
	my $client = shift;
	my $newvolume = shift;

	my $volume = $client->Slim::Player::Client::volume($newvolume, @_);
	my $preamp = 255 - int(2 * $prefs->client($client)->get('preampVolumeControl'));

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
			$newGain = dBToFixed($db);
		}

		my $data = pack('NNCCNN', $oldGain, $oldGain, $prefs->client($client)->get('digitalVolumeControl'), $preamp, $newGain, $newGain);
		$client->sendFrame('audg', \$data);
	}
	return $volume;
}

sub periodicScreenRefresh {
    # noop for this player - not required
}    

sub upgradeFirmware {
	
}

sub needsUpgrade {
	return 0;
}

sub reportsTrackStart {
	return 1;
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
	$client->songElapsedSeconds(0);
	$client->outputBufferFullness(0);

}

sub songElapsedSeconds {
	my $client = shift;

	# Ignore values sent by the client if we're in the stopped
	# state, since they may be out of sync.
	if (defined($_[0]) && 
	    Slim::Player::Source::playmode($client) eq 'stop') {
		$client->SUPER::songElapsedSeconds(0);
	}

	return $client->SUPER::songElapsedSeconds(@_);
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
				 88200 => '10',
				 96000 => '9',
				 );

	my $rate = $pcm_sample_rates{$track->samplerate()};

	return defined $rate ? $rate : '3';
}

sub playPoint {
	my $client = shift;

	my ($jiffies, $elapsedMilliseconds) = Slim::Networking::Slimproto::getPlayPointData($client);

	return unless $elapsedMilliseconds;

	my $statusTime = $client->jiffiesToTimestamp($jiffies);
	my $apparentStreamStartTime = $statusTime - ($elapsedMilliseconds / 1000);

	0 && logger('player.sync')->debug($client->id() . " playPoint: jiffies=$jiffies, epoch="
		. ($client->jiffiesEpoch) . ", statusTime=$statusTime, elapsedMilliseconds=$elapsedMilliseconds");

	return [$statusTime, $apparentStreamStartTime];
}


sub packetLatency {
	my $client = shift;
	
	return (
		Slim::Networking::Slimproto::getLatency($client) / 1000
		||
		$client->SUPER::packetLatency()
	);
}

1;
