package Slim::Player::Squeezebox;

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
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
use File::Spec::Functions qw(:ALL);
use FindBin qw($Bin);
use IO::Socket;
use Slim::Player::Player;
use Slim::Utils::Misc;
use MIME::Base64;

use Slim::Hardware::mas35x9;

use base qw(Slim::Player::Player);

BEGIN {
	if ($^O =~ /Win32/) {
		*EWOULDBLOCK = sub () { 10035 };
		*EINPROGRESS = sub () { 10036 };
	} else {
		require Errno;
		import Errno qw(EWOULDBLOCK EINPROGRESS);
	}
}

# We inherit new() completely from our parent class.

sub init {
	my $client = shift;

	$client->SUPER::init();
	# Ensure that a new client is stopped
	$client->stop();
}

# squeezebox does not need an update here, so a noop is OK.
sub refresh {
	# my $client = shift;
}

sub reconnect {
	my $client = shift;
	my $paddr = shift;
	my $revision = shift;
	my $tcpsock = shift;
	my $reconnect = shift;
	my $bytes_received = shift;

	$client->tcpsock($tcpsock);
	$client->paddr($paddr);
	$client->revision($revision);	
	
	# tell the client the server version
	if ($revision == 0 || $revision > 39) {
		$client->sendFrame('vers', \$::VERSION);
	}

	# The reconnect bit for Squeezebox means that we're
	# reconnecting after the control connection went down, but we
	# didn't reboot.  For Squeezebox2, it means that we're
	# reconnecting and there is an active data connection. In
	# both cases, we do the same thing:
	# If we were playing previously, either restart the track or
	# resume streaming at the bytes_received point. If we were
	# paused, then stop.

	if (!$reconnect) {
		if ($client->playmode() eq 'play') {
			# If bytes_received was sent and we're dealing 
			# with a seekable source, just resume streaming
			# else stop and restart.    
			if (!$bytes_received ||
			    $client->audioFilehandleIsSocket()) {
				Slim::Player::Source::playmode($client, "stop");
				$bytes_received = 0;
			}
			Slim::Player::Source::playmode($client, "play", $bytes_received);
		} elsif ($client->playmode() eq 'pause') {
			Slim::Player::Source::playmode($client, "stop");
		}
	}

	$client->animating(0);

	$client->brightness(Slim::Utils::Prefs::clientGet($client,$client->power() ? 'powerOnBrightness' : 'powerOffBrightness'));
	$client->update();	
}

sub connected { 
	my $client = shift;

	return ($client->tcpsock() && $client->tcpsock->connected()) ? 1 : 0;
}

sub model {
	return 'squeezebox';
}

sub ticspersec {
	return 1000;
}

sub vfdmodel {
	return 'noritake-european';
}

sub decoder {
	return 'mas35x9';
}

sub play {
	my $client = shift;
	my $paused = shift;
	my $format = shift;
	my $quickstart = shift;
	my $reconnect = shift;

	$client->stream('s', $paused, $format, $reconnect);
	# make sure volume is set, without changing temp setting
	$client->volume($client->volume(),
					defined($client->tempVolume()));

	Slim::Utils::Timers::killTimers($client, \&quickstart);
	if ($quickstart) {
		Slim::Utils::Timers::setTimer($client,Time::HiRes::time() + $quickstart,\&quickstart);
	}
	
	return 1;
}

#
# tell the client to unpause the decoder
#
sub resume {
	my $client = shift;

	Slim::Utils::Timers::killTimers($client, \&quickstart);

	$client->stream('u');
	$client->SUPER::resume();
	return 1;
}

#
# pause
#
sub pause {
	my $client = shift;

	Slim::Utils::Timers::killTimers($client, \&quickstart);

	$client->stream('p');
	$client->SUPER::pause();
	return 1;
}

sub stop {
	my $client = shift;

	Slim::Utils::Timers::killTimers($client, \&quickstart);

	$client->stream('q');
	Slim::Networking::Slimproto::stop($client);
	# disassociate the streaming socket to the client from the client.  HTTP.pm will close the socket on the next select.
	$client->streamingsocket(undef);
}

sub flush {
	my $client = shift;

	Slim::Utils::Timers::killTimers($client, \&quickstart);

	$client->stream('f');
	$client->SUPER::flush();
	return 1;
}

sub quickstart {
	my $client = shift;
	my $fullness = $client->bufferFullness();

	# make sure we have at least 10K before starting with a quickstart.  If not, then check again in a second.
	if ($fullness > 10 * 1024) {
		$client->resume();
	} else {
		$client->requestStatus();
		Slim::Utils::Timers::setTimer($client,Time::HiRes::time() + 1,\&quickstart);
	}
}

#
# playout - play out what's in the buffer
#
sub playout {
	my $client = shift;
	return 1;
}

sub bufferFullness {
	my $client = shift;
	return Slim::Networking::Slimproto::fullness($client);
}

sub bytesReceived {
	return Slim::Networking::Slimproto::bytesReceived(@_);
}

sub signalStrength {
	return Slim::Networking::Slimproto::signalStrength(@_);
}

sub hasDigitalOut {
	return 1;
}

# if an update is required, return the version of the appropriate upgrade image
#
sub needsUpgrade {
	my $client = shift;
	my $from = $client->revision;
	return 0 unless $from;
	my $model = $client->model;
	
	my $versionFilePath = catdir($Bin, "Firmware", $model . ".version");
	my $versionFile;

	if (!open($versionFile, "<$versionFilePath")) {
		warn("can't open $versionFilePath\n");
		return 0;
	}

	my $to;
	my $default;
	while (<$versionFile>) {
		chomp;
		next if /^\s*(#.*)?$/;
		if (/^(\d+)\s*\.\.\s*(\d+)\s+(\d+)\s*$/) {
			next unless $from >= $1 && $from <= $2;
			$to = $3;
		} elsif (/^(\d+)\s+(\d+)\s*$/) {
			next unless $1 == $from;
			$to = $2;
		} elsif (/^\*\s+(\d+)\s*$/) {
			$default = $1;
		} else {
			msg("Garbage in $versionFilePath at line $.: $_\n");
		}
		last;
	}

	close($versionFile);

	if (!defined $to) {
		if ($default) {
			# use the default value in case we need to go back from the future.
			$::d_firmware && msg ("No target found, using default version: $default\n");
			$to = $default;
		} else {
			$::d_firmware && msg ("No upgrades found for $model v. $from\n");
			return 0;
		}
	}

	if ($to == $from) {
		$::d_firmware && msg ("$model firmware is up-to-date, v. $from\n");
		return 0;
	}

	# skip upgrade if file doesn't exist

	my $file = shift || catdir($Bin, "Firmware", $model . "_$to.bin");

	unless (-r $file && -s $file) {
		$::d_firmware && msg ("$model v. $from could be upgraded to v. $to if the file existed.\n");
		return 0;
	}

	$::d_firmware && msg ("$model v. $from requires upgrade to $to\n");
	return $to;

}

# the new way: use slimproto
sub upgradeFirmware_SDK5 {
	use bytes;
	my ($client, $filename) = @_;

	$::d_firmware && msg("Updating firmware with file: $filename\n");

	my $frame;

	Slim::Utils::Prefs::clientSet($client, "powerOnBrightness", 4);
	Slim::Utils::Prefs::clientSet($client, "powerOffBrightness", 1);
	
	$client->textSize(0);

#	Slim::Utils::Misc::blocking($client->tcpsock, 1);

	open FS, $filename || return("Open failed for: $filename\n");

	binmode FS;
	
	my $size = -s $filename;	
	
	$::d_firmware && msg("Updating firmware: Sending $size bytes\n");
	
	my $bytesread=0;
	my $totalbytesread=0;
	my $buf;
	my $byteswritten;
	my $bytesleft;
	my $lastFraction = -1;
	
	while ($bytesread=read(FS, $buf, 1024)) {
		assert(length($buf) == $bytesread);

		$client->sendFrame('upda', \$buf);
		
		$totalbytesread += $bytesread;
		$::d_firmware && msg("Updating firmware: $totalbytesread / $size\n");
		
		my $fraction = $totalbytesread/$size;
		
		if (($fraction - $lastFraction) > (1/20)) {
			$client->showBriefly(
				$client->string('UPDATING_FIRMWARE_' . uc($client->model())),
				Slim::Display::Display::progressBar($client, $client->displayWidth(), $totalbytesread/$size)
			);
			$lastFraction = $fraction;
		}
	}
	
	$client->showBriefly(
		$client->string('UPDATING_FIRMWARE_' . uc($client->model())),
				
		Slim::Display::Display::progressBar($client, $client->displayWidth(), 1)
	);
	$client->sendFrame('updn'); # upgrade done

	$::d_firmware && msg("Firmware updated successfully.\n");
	
#	Slim::Utils::Misc::blocking($client->tcpsock, 0);
	
	return undef;
}

# the old way: connect to 31337 and dump the file
sub upgradeFirmware_SDK4 {
	use bytes;
	my ($client, $filename) = @_;
	my $ip;
	if (ref $client ) {
		$ip = $client->ip;
		Slim::Utils::Prefs::clientSet($client, "powerOnBrightness", 4);
		Slim::Utils::Prefs::clientSet($client, "powerOffBrightness", 1);
	} else {
		$ip = $client;
	}
	
	my $port = 31337;  # upgrade port
	
	my $iaddr   = inet_aton($ip) || return("Bad IP address: $ip\n");
	
	my $paddr   = sockaddr_in($port, $iaddr);
	
	my $proto   = getprotobyname('tcp');

	socket(SOCK, PF_INET, SOCK_STREAM, $proto)	|| return("Couldn't open socket: $!\n");
	binmode SOCK;

	connect(SOCK, $paddr) || return("Connect failed $!\n");
	
	open FS, $filename || return("can't open $filename");
	binmode FS;
	
	my $size = -s $filename;	
	
	$::d_firmware && msg("Updating firmware: Sending $size bytes\n");
	
	my $bytesread=0;
	my $totalbytesread=0;
	my $buf;

	while ($bytesread=read(FS, $buf, 256)) {
		syswrite SOCK, $buf;
		$totalbytesread += $bytesread;
		$::d_firmware && msg("Updating firmware: $totalbytesread / $size\n");
	}
	
	$::d_firmware && msg("Firmware updated successfully.\n");
	
	close (SOCK) || return("Couldn't close socket to player.");
	
	return undef; 
}

sub upgradeFirmware {
	my $client = shift;

	my $to_version;

	if (ref $client ) {
		$to_version = $client->needsUpgrade();
	} else {
		# for the "upgrade by ip address" web form:
		$to_version = 10;
	}

	# if no upgrade path is given, then "upgrade" the client to itself.

	$to_version = $client->revision unless $to_version;

	my $filename = catdir($Bin, "Firmware", "squeezebox_$to_version.bin");

	if (!-f$filename) {
		warn("file does not exist: $filename\n");
		return(0);
	}

	my $err;

	if ((!ref $client) || ($client->revision <= 10)) {
		$::d_firmware && msg("using old update mechanism\n");
		$err = $client->upgradeFirmware_SDK4($filename);
	} else {
		$::d_firmware && msg("using new update mechanism\n");
		$err = $client->upgradeFirmware_SDK5($filename);
	}

	if (defined($err)) {
		msg("upgrade failed: $err");
	} else {
		$client->forgetClient();
	}
}

# in order of preference based on whether we're connected via wired or wireless...
sub formats {
	my $client = shift;
	
	return qw(aif wav mp3);
}

sub vfd {
	my $client = shift;
	my $data = shift;

	if ($client->opened()) {
		$client->sendFrame('vfdc', \$data);
	} 
}

sub opened {
	my $client = shift;
	if ($client->tcpsock) {
		if (fileno $client->tcpsock && $client->tcpsock->connected) {
			return $client->tcpsock;
		} else {
			$client->tcpsock(undef);
		}
	}
	return undef;
}

# Squeezebox control for tcp stream
#
#	u8_t command;		// [1]	's' = start, 'p' = pause, 'u' = unpause, 'q' = stop, 't' = status
#	u8_t autostart;		// [1]	'0' = don't auto-start, '1' = auto-start
#	u8_t mode;		// [1]	'm' = mpeg bitstream, 'p' = PCM
#	u8_t pcm_sample_size;	// [1]	'0' = 8, '1' = 16, '2' = 24, '3' = 32
#	u8_t pcm_sample_rate;	// [1]	'0' = 11kHz, '1' = 22, '2' = 32, '3' = 44.1, '4' = 48
#	u8_t pcm_channels;	// [1]	'1' = mono, '2' = stereo
#	u8_t pcm_endianness;	// [1]	'0' = big, '1' = little
#	u8_t threshold;		// [1]	Kb of input buffer data before we autostart or notify the server of buffer fullness
#	u8_t spdif_enable;	// [1]  '0' = auto, '1' = on, '2' = off
#	u8_t transition_period;	// [1]	seconds over which transition should happen
#	u8_t transition_type;	// [1]	'0' = none, '1' = crossfade, '2' = fade in, '3' = fade out, '4' fade in & fade out
#	u8_t flags;		// [1]	0x80 - loop infinitely, 0x40 - stream
#                               //      without restarting decoder
#	u16_t visualizer_port;	// [2]	visualizer's port - leave port 0 for no vis
#	u32_t visualizer_ip;	// [4]	visualizer's ip - leave server 0 to use slim server's ip
#	u16_t server_port;	// [2]	server's port
#	u32_t server_ip;	// [4]	server's IP
#				// ____
#				// [24]
#
sub stream {
	my ($client, $command, $paused, $format, $reconnect) = @_;

	if ($client->opened()) {
		$::d_slimproto && msg("*************stream called: $command\n");
		my $autostart;
		
		# autostart off when pausing or stopping, otherwise 75%
		if ($paused || $command =~ /^[pq]$/) {
			$autostart = 0;
		} else {
			$autostart = 1;
		}

		my $bufferThreshold;
		if ($paused) {
			$bufferThreshold = Slim::Utils::Prefs::clientGet($client, 'syncBufferThreshold');
		}
		else {
			$bufferThreshold = Slim::Utils::Prefs::clientGet($client, 'bufferThreshold');
		}
		
		my $formatbyte;
		my $pcmsamplesize;
		my $pcmsamplerate;
		my $pcmendian;
		my $pcmchannels;
		
		# default to mp3
		$format ||= 'mp3';
		
		if ($format eq 'wav') {
			$formatbyte = 'p';
			$pcmsamplesize = '1';
			$pcmsamplerate = '3';
			$pcmendian = '1';
			$pcmchannels = '2';
		} elsif ($format eq 'aif') {
			$formatbyte = 'p';
			$pcmsamplesize = '1';
			$pcmsamplerate = '3';
			$pcmendian = '0';
			$pcmchannels = '2';
		} elsif ($format eq 'flc') {
			$formatbyte = 'f';
			$pcmsamplesize = '?';
			$pcmsamplerate = '?';
			$pcmendian = '?';
			$pcmchannels = '?';
		} else { # assume MP3
			$formatbyte = 'm';
			$pcmsamplesize = '?';
			$pcmsamplerate = '?';
			$pcmendian = '?';
			$pcmchannels = '?';
		}

		$::d_slimproto && msg("starting with decoder with options: format: $formatbyte samplesize: $pcmsamplesize samplerate: $pcmsamplerate endian: $pcmendian channels: $pcmchannels\n");
		
		my $frame = pack 'aaaaaaaCCCaCnLnL', (
			$command,	# command
			$autostart,
			$formatbyte,
			$pcmsamplesize,
			$pcmsamplerate,
			$pcmchannels,
			$pcmendian,
			$bufferThreshold,
			0,		# s/pdif auto
			Slim::Utils::Prefs::clientGet($client, 'transitionDuration') || 0,
			Slim::Utils::Prefs::clientGet($client, 'transitionType') || 0,
			$reconnect ? 0x40 : 0,		# flags	     
			0,		# vis port - call IANA!!!  :)
			0,		# use slim server's IP
			Slim::Utils::Prefs::get('httpport'),		# port
			0,		# server IP of 0 means use IP of control server
		);
	
		assert(length($frame) == 24);
	
		my $path = '/stream.mp3?player='.$client->id;
	
		my $request_string = "GET $path HTTP/1.0\n";
		
		if (Slim::Utils::Prefs::get('authorize')) {
			$client->password(generate_random_string(10));
			
			my $password = encode_base64('squeezebox:' . $client->password);
			
			$request_string .= "Authorization: Basic $password\n";
		}
		
		$request_string .= "\n";
		if (length($request_string) % 2) {
			$request_string .= "\n";
		}

		$frame .= $request_string;

		$client->sendFrame('strm',\$frame);
		
		if ($client->pitch() != 100 && $command eq 's') {
			$client->sendPitch($client->pitch());
		}
	}
}

sub sendFrame {
	my $client = shift;
	my $type = shift;
	my $dataRef = shift;
	my $empty = '';
	
	return if (!defined($client->tcpsock));  # don't try to send if the player has disconnected.
	
	if (!defined($dataRef)) { $dataRef = \$empty; }

	my $len = length($$dataRef);

	assert(length($type) == 4);
	
	my $frame = pack('n', $len + 4) . $type . $$dataRef;

	$::d_slimproto && msg ("sending squeezebox frame: $type, length: $len\n");

	Slim::Networking::Select::writeNoBlock($client->tcpsock, \$frame);
}

# This function generates random strings of a given length
sub generate_random_string
{
	# the length of the random string to generate
        my $length_of_randomstring = shift;

        my @chars = ('a'..'z','A'..'Z','0'..'9','_');
        my $random_string;

        foreach (1..$length_of_randomstring) {
                #rand @chars will generate a random number between 0 and scalar @chars
                $random_string .= $chars[rand @chars];
        }

        return $random_string;
}

sub i2c {
	my ($client, $data) = @_;

	if ($client->opened()) {
		$::d_i2c && msg("i2c: sending ".length($data)." bytes\n");
		$client->sendFrame('i2cc', \$data);
	}
}

#
# set the mas35x9 pitch rate as a percentage of the normal rate, where 100% is 100.
#
sub pitch {
	my $client = shift;
	my $newpitch = shift;
	
	my $pitch = $client->SUPER::pitch($newpitch, @_);

	if (defined($newpitch)) {
		$client->sendPitch($pitch, 1);
	}

	return $pitch;
}

sub sendPitch {
	my $client = shift;
	my $pitch = shift;
	my $pause = shift;
	
	my $freq = int(18432 / ($pitch / 100));
	my $freqHex = sprintf('%05X', $freq);
	$::d_control && msg("Pitch frequency set to $freq ($freqHex), pause: $pause\n");

	if ($client->streamformat()) {
		if ($client->streamformat() eq 'mp3') {
			$client->i2c(
				Slim::Hardware::mas35x9::masWrite('OfreqControl', $freqHex).
					Slim::Hardware::mas35x9::masWrite('OutClkConfig', '00001').
					Slim::Hardware::mas35x9::masWrite('IOControlMain', '00015')     # MP3
			);
		} else {
			if ($pause && ($client->playmode() =~ /^play/)) {
				if (Slim::Utils::Timers::killTimers($client, \&resume) == 0) {
					$client->pause();
				}	
			}
			
			$client->i2c(
				Slim::Hardware::mas35x9::masWrite('OfreqControl', $freqHex).
					Slim::Hardware::mas35x9::masWrite('OutClkConfig', '00001').
					Slim::Hardware::mas35x9::masWrite('IOControlMain', '00101')     # PCM
			);

			if ($pause && ($client->playmode()  =~ /^play/)) {
				Slim::Utils::Timers::setTimer($client,Time::HiRes::time() + 0.5,\&resume,$client);
			}
		}	
	}
}
	
sub maxPitch {
	return 120;
}

sub minPitch {
	return 80;
}

sub volume {
	my $client = shift;
	my $newvolume = shift;

	my $volume = $client->SUPER::volume($newvolume, @_);

	if (defined($newvolume)) {
		# really the only way to make everyone happy will be use a combination of digital and analog volume controls as the 
		# default, but then have knobs so you can tune it for max headphone power, lowest noise at low volume, 
		# fixed/variable s/pdif, etc.
	
		if (Slim::Utils::Prefs::clientGet($client, 'digitalVolumeControl')) {
			# here's one way to do it: adjust digital gains, leave fixed 3db boost on the main volume control
			# this does achieve good analog output voltage (important for headphone power) but is not optimal
			# for low volume levels. If only the analog outputs are being used, and digital gain is not required, then 
			# use the other method.
			#
			# When the main volume control is set to +3db (0x7600), there is no clipping at the analog outputs 
			# at max volume, for the loudest 1KHz sine wave I could record.
			#
			# At +12db, the clipping level is around 23/40 (on our thermometer bar).
			#
			# The higher the analog gain is set, the closer it can "match" (3v pk-pk) the max S/PDIF level. 
			# However, at any more than +3db it starts to get noisy, so +3db is the max we should use without 
			# some clever tricks to combine the two gain controls.
			#
	
			my $level = sprintf('%05X', 0x80000 * (($volume / $client->maxVolume)**2));
			$client->i2c(
				Slim::Hardware::mas35x9::masWrite('out_LL', $level)
				.Slim::Hardware::mas35x9::masWrite('out_RR', $level)
				.Slim::Hardware::mas35x9::masWrite('VOLUME', '7600')
			);
	
		} else {
			# or: leave the digital controls always at 0db and vary the main volume:
			# much better for the analog outputs, but this does force the S/PDIF level to be fixed.
	
			my $level = sprintf('%02X00', 0x73 * ($volume / $client->maxVolume)**0.1);
	
			$client->i2c(
				Slim::Hardware::mas35x9::masWrite('out_LL',  '80000')
				.Slim::Hardware::mas35x9::masWrite('out_RR', '80000')
				.Slim::Hardware::mas35x9::masWrite('VOLUME', $level)
			);
		}
	}
	return $volume;
}

sub bass {
	my $client = shift;
	my $newbass = shift;

	my $bass = $client->SUPER::bass($newbass);
	$client->i2c( Slim::Hardware::mas35x9::masWrite('BASS', Slim::Hardware::mas35x9::getToneCode($bass,'bass'))) if (defined($newbass));	

	return $bass;
}

sub treble {
	my $client = shift;
	my $newtreble = shift;

	my $treble = $client->SUPER::treble($newtreble);
	$client->i2c( Slim::Hardware::mas35x9::masWrite('TREBLE', Slim::Hardware::mas35x9::getToneCode($treble,'treble'))) if (defined($newtreble));	

	return $treble;
}

sub requestStatus {
	shift->sendFrame('i2cc');
}
1;
