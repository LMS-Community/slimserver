package Slim::Player::Squeezebox;

# Slim Server Copyright (c) 2001, 2002, 2003 Sean Adams, Slim Devices Inc.
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

@ISA = ("Slim::Player::Player");

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

	$client->reconnect($paddr, $revision, $tcpsock);
		
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
	
	$client->update();	
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
	my $pcm = shift;

 	$client->volume(Slim::Utils::Prefs::clientGet($client, "volume"));
	Slim::Hardware::Decoder::reset($client, $pcm);
	$client->stream('s');
	return 1;
}
#
# tell the client to unpause the decoder
#
sub resume {
	my $client = shift;
	$client->volume(Slim::Utils::Prefs::clientGet($client, "volume"));
	$client->stream('u');
	return 1;
}

#
# pause
#
sub pause {
	my $client = shift;
	$client->stream('p');
	return 1;
}

sub stop {
	my $client = shift;
	$client->stream('q');
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

sub buffersize {
	return 131072;
}

sub bytesReceived {
	return Slim::Networking::Slimproto::bytesReceived(@_);
}

sub needsUpgrade {
	my $client = shift;
	my $versionFilePath = catdir($Bin, "Firmware", "squeezebox.version");
	my $versionFile;
	return 0 if !open $versionFile, "<$versionFilePath";
	my $version = <$versionFile>;
	close $versionFile;
	chomp $version;
	if ($version != $client->revision) {
		return 1;
	} else {
		return 0;
	}
}

sub upgradeFirmware {
	my $client = shift;
	my $ip = $client->ip;
	
	# give the player a chance to get into upgrade mode
	sleep(2);
	
	my $port = 31337;  # upgrade port
	
	my $file = shift || catdir($Bin, "Firmware", "squeezebox.bin");

	my $iaddr   = inet_aton($ip) || return("Bad IP address: $ip\n");
	
	my $paddr   = sockaddr_in($port, $iaddr);
	
	my $proto   = getprotobyname('tcp');

	socket(SOCK, PF_INET, SOCK_STREAM, $proto)	|| return("Couldn't open socket: $!\n");

	connect(SOCK, $paddr) || return("Connect failed $!\n");
	
	open FS, $file || return("Open failed for: $file\n");
	
	binmode FS;
	
	my $size = -s $file;	
	
	!$::d_firmware && msg("Updating firmware: Sending $size bytes\n");
	
	my $bytesread=0;
	my $totalbytesread=0;
	my $buf;
	
	while ($bytesread=read(FS, $buf, 256)) {
		print SOCK $buf;
		$totalbytesread += $bytesread;
		$::d_firmware && msg("Updating firmware: $totalbytesread / $size\n");
	}
	
	$::d_firmware && msg("Firmware updated successfully.\n");
	
	close (SOCK) || return("Couldn't close socket to player.");
	
	return undef; 
}

sub formats {
	return ('mp3');
}

sub vfd {
	my $client = shift;
	my $data = shift;

	if ($client->opened()) {
		$frame = 'l   '.$data;
		my $len = pack('n',length($frame));
		$::d_protocol_verbose && msg ("sending squeezebox frame, length ".length($frame)."\n");
		$frame = $len.$frame;
		$client->tcpsock->syswrite($frame,length($frame));
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
#	u8_t prebuffer_silence;	// [1]	number of mpeg frames
#	u8_t spdif_enable;	// [1]  '0' = auto, '1' = on, '2' = off
#	u8_t reserved;		// [1]	reserved
#	u16_t server_port;	// [2]	server's port
#	u32_t server_ip;	// [4]	server's IP
#				// ____
#				// [16]
#
sub stream {

	my ($client, $command) = @_;
	if ($client->opened()) {
		$::d_slimproto && msg("*************stream called: $command\n");
	
		my $frame = 's   '.pack 'aaaaaaaCCCnL', (
			$command,	# command
			($command =~ /^[pq]$/)
				?'0'
				:'3', # autostart off when pausing or stopping, otherwise 75%
			'm',		# mpeg
			'1',		# pcm 16-bit (pcm options are ignored for mpeg)
			'3',		# pcm 44.1
			'1',		# pcm mono
			'0',		# pcm big endian
			5,		# mpeg pre-buffer 5 frames of silence
			0,		# s/pdif auto
			0,		# reserved
			Slim::Utils::Prefs::get('httpport'),		# port
			0		# server IP of 0 means use IP of control server
		);
	
		assert(length($frame) == 4+16);
	
	#	my $path='/music/AC-DC/Back%20In%20Black/07%20You%20Shook%20Me%20All%20Night%20Long.mp3';
		my $path = '/stream.mp3?player='.$client->id;
	
		my $request_string = "GET $path HTTP/1.0\n\n";
	
		$frame .= $request_string;
	
		my $len = pack('n', length($frame));
	
		$frame = $len.$frame;
	
		$client->tcpsock->syswrite($frame, length($frame));
	}
}

sub i2c {
	my ($client, $data) = @_;
	if ($client->opened()) {
		$::d_i2c && msg("i2c: sending ".length($data)." bytes\n");
	
		my $frame='2   '.$data;
		my $len = pack('n', length($frame));
		$frame=$len.$frame;
		$client->tcpsock->syswrite($frame, length($frame));
	}
}

1;