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
use File::Spec::Functions qw(:ALL);
use FindBin qw($Bin);
use IO::Socket;
use Slim::Player::Player;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw (string);
use MIME::Base64;

@ISA = ("Slim::Player::Player");

BEGIN {
	if ($^O =~ /Win32/) {
		*EWOULDBLOCK = sub () { 10035 };
		*EINPROGRESS = sub () { 10036 };
	} else {
		require Errno;
		import Errno qw(EWOULDBLOCK EINPROGRESS);
	}
}

sub new {
	my (
		$class,
		$id,
		$paddr,			# sockaddr_in
		$revision,
		$tcpsock,		# defined only for squeezebox
	) = @_;
	
	my $client = Slim::Player::Player->new($id, $paddr, $revision);

	bless $client, $class;

	return $client;
}

sub reconnect {
	my $client = shift;
	my $paddr = shift;
	my $revision = shift;
	my $tcpsock = shift;

	$client->tcpsock($tcpsock);
	$client->paddr($paddr);
	$client->revision($revision);	
	
	# tell the client the server version
#	$client->sendFrame('vers', \$::VERSION);
	
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

	Slim::Hardware::Decoder::reset($client, $format);
	$client->stream('s', $paused, $format);
	$client->volume(Slim::Utils::Prefs::clientGet($client, "volume"));
	return 1;
}
#
# tell the client to unpause the decoder
#
sub resume {
	my $client = shift;
	$client->stream('u');
	$client->SUPER::resume();
	return 1;
}

#
# pause
#
sub pause {
	my $client = shift;
	$client->stream('p');
	$client->SUPER::pause();
	return 1;
}

sub stop {
	my $client = shift;
	$client->stream('q');
	Slim::Networking::Slimproto::stop($client);
	# disassociate the streaming socket to the client from the client.  HTTP.pm will close the socket on the next select.
	$client->streamingsocket(undef);
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
	my $versionFilePath = catdir($Bin, "Firmware", "squeezebox.version");
	my $versionFile;

	if (!open($versionFile, "<$versionFilePath")) {
		warn("can't open $versionFilePath\n");
		return 0;
	}

	my $line;
	my ($from, $to);
	while ($line = <$versionFile>) {
		$line=~/^(\d+)\s+(\d+)\s*$/ || next;
		($from, $to) = ($1, $2);
		#print "\"$from\"\t\"$to\"\n";
		$from == $client->revision && last;
	}

	close($versionFile);

	if ((!defined $from) || ($from != $client->revision)) {
		$::d_firmware && msg ("No upgrades found for squeezebox v. ". $client->revision."\n");
		return 0;
	}

	# skip upgrade if file doesn't exist

	my $file = shift || catdir($Bin, "Firmware", "squeezebox_$to.bin");

	if (!-f$file) {
		$::d_firmware && msg ("squeezebox v. ".$client->revision." could be upgraded to v. $to if the file existed.\n");
		return 0;
	}

	$::d_firmware && msg ("squeezebox v. ".$client->revision." requires upgrade to $to\n");
	return $to;

}

# the new way: use slimproto
sub upgradeFirmware_SDK5 {
	use bytes;
	my ($client, $filename) = @_;

	my $frame;

	Slim::Utils::Prefs::clientSet($client, "powerOnBrightness", 4);
	Slim::Utils::Prefs::clientSet($client, "powerOffBrightness", 1);

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
				string('UPDATING_FIRMWARE'),
				
				Slim::Display::Display::progressBar($client, $client->displayWidth(), $totalbytesread/$size)
			);
			$lastFraction = $fraction;
		}
	}
	
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
		$err = upgradeFirmware_SDK4($client, $filename);
	} else {
		$::d_firmware && msg("using new update mechanism\n");
		$err = upgradeFirmware_SDK5($client, $filename);
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
	
	return ('aif','wav','mp3');
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
		if ($client->tcpsock->connected) {
			return $client->tcpsock;
		} else {
			$client->tcpsock(undef);
		}
	}
	return undef;
}

# Squeezebox control for tcp stream
#
#	u8_t command;		// [1]	's' = start, 'p' = pause, 'u' = unpause, 'q' = stop 
#	u8_t autostart_threshold;// [1]	'0' = don't auto-start, '1' = 25%, '2' = 50%, '3'= 75%, '4' = 100%
#	u8_t mode;		// [1]	'm' = mpeg bitstream, 'p' = PCM
#	u8_t pcm_sample_size;	// [1]	'0' = 8, '1' = 16, '2' = 20, '3' = 32
#	u8_t pcm_sample_rate;	// [1]	'0' = 11kHz, '1' = 22, '2' = 32, '3' = 44.1, '4' = 48
#	u8_t pcm_channels;	// [1]	'1' = mono, '2' = stereo
#	u8_t pcm_endianness;	// [1]	'0' = big, '1' = little
#	u8_t reserved;	// [1]	reserved
#	u8_t spdif_enable;	// [1]  '0' = auto, '1' = on, '2' = off
#	u8_t reserved;		// [1]	reserved
#	u16_t server_port;	// [2]	server's port
#	u32_t server_ip;	// [4]	server's IP
#				// ____
#				// [16]
#
sub stream {
	my ($client, $command, $paused, $format) = @_;

	if ($client->opened()) {
		$::d_slimproto && msg("*************stream called: $command\n");
		my $autostart;
		
		 # autostart off when pausing or stopping, otherwise 75%
		if ($paused || $command =~ /^[pq]$/) {
			$autostart = 0;
		} else {
			$autostart = 3;
		}
		
		my $formatbyte;
		my $pcmsamplesize;
		my $pcmsamplerate;
		my $pcmendian;
		my $pcmchannels;
		
		$format = 'mp3'	if (!$format); 
		
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
		} else { # assume MP3
			$formatbyte = 'm';
			$pcmsamplesize = '?';
			$pcmsamplerate = '?';
			$pcmendian = '?';
			$pcmchannels = '?';
		}
		$::d_slimproto && msg("starting with decoder with options: format: $formatbyte samplesize: $pcmsamplesize samplerate: $pcmsamplerate endian: $pcmendian channels: $pcmchannels\n");
		
		my $frame = pack 'aaaaaaaCCCnL', (
			$command,	# command
			$autostart,
			$formatbyte,
			$pcmsamplesize,
			$pcmsamplerate,
			$pcmchannels,
			$pcmendian,
			0,		# reserved
			0,		# s/pdif auto
			0,		# reserved
			Slim::Utils::Prefs::get('httpport'),		# port
			0		# server IP of 0 means use IP of control server
		);
	
		assert(length($frame) == 16);
	
		my $path = '/stream.mp3?player='.$client->id;
	
		my $request_string = "GET $path HTTP/1.0\n";
		
		if (Slim::Utils::Prefs::get('authorize')) {
			$client->password(generate_random_string(10));
			
			my $password = encode_base64('squeezebox:' . $client->password);
			
			$request_string .= "Authorization: Basic $password\n";
		}
		
		$request_string .= "\n";

		$frame .= $request_string;

		$client->sendFrame('strm',\$frame);
	}
}

sub sendFrame {
	my $client = shift;
	my $type = shift;
	my $dataRef = shift;
	my $empty = '';
	
	if (!defined($dataRef)) { $dataRef = \$empty; }
	
	my $len = length($$dataRef);

	assert(length($type) == 4);
	
	my $frame = pack('n', $len + 4) . $type . $$dataRef;

	$::d_slimproto_v && msg ("sending squeezebox frame: $type, length: $len\n");

	Slim::Networking::Select::writeNoBlock($client->tcpsock, \$frame);
}

# This function generates random strings of a given length
sub generate_random_string
{
		#the length of the random string to generate
        my $length_of_randomstring=shift;

        my @chars=('a'..'z','A'..'Z','0'..'9','_');
        my $random_string;
        foreach (1..$length_of_randomstring) 
        {
                #rand @chars will generate a random number between 0 and scalar @chars
                $random_string.=$chars[rand @chars];
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

1;
