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
package Slim::Networking::Sendclient;

use strict;

use IO::Socket;
use IO::Select;

use Slim::Utils::Misc;

sub vfd {
	my $client = shift;
	my $data = shift;

	my $frame;
	if ($client->model eq 'slimp3') {
		assert($client->udpsock);
		$frame = 'l                 '.$data;
		send($client->udpsock, $frame, 0, $client->paddr()); 
	} else {
		assert($client->model eq 'squeezebox');
		assert($client->tcpsock);
		$frame = 'l   '.$data;
		my $len = pack('n',length($frame));
		$::d_protocol && msg ("sending squeezebox frame, length ".length($frame)."\n");
		$frame = $len.$frame;
		$client->tcpsock->syswrite($frame,length($frame));
	}
}

# SliMP3 UDP streaming
#
sub udpstream {
	my ($client, $controlcode, $wptr, $seq, $chunk) = @_;

	assert($client->model eq 'slimp3');
		        
	my $frame = pack 'aCxxxxn xxn xxxxxx', (
		'm',                            # 'm' == mp3 data
		$controlcode,                   # control code   
		$wptr,                          # wptr
		$seq);

        
	$frame .= $chunk;
        
	send($client->udpsock, $frame, 0, $client->paddr());
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

	assert($client->model eq 'squeezebox');

	my $frame = 's   '.pack 'aaaaaaaCaanL', (
		$command,
		'3',
		'm',
		'1',
		'3',
		'1',
		'0',
		5,
		0,
		9000,
		0		# server IP of 0 means use IP of control server
	);

	assert(length($frame) == 4+16);

	my $path = '/test.mp3';
#	my $path = '/music/test.mp3';
	my $request_string = "GET $path HTTP/1.0\n\n";

	print "$request_string";
	
	$frame .= $request_string;

	my $len = pack('n', length($frame));

	$frame = $len.$frame;

	$client->tcpsock->syswrite($frame, length($frame));

}

sub i2c {
	my ($client, $data) = @_;

	$::d_i2c && msg("i2c: sending ".length($data)." bytes\n");

	if ($client->model eq 'slimp3') {
		send($client->udpsock, '2                 '.$data, 0, $client->paddr);
	} else {
		assert($client->model eq 'squeezebox');
		my $frame='2   '.$data;
		my $len = pack('n', length($frame));
		$frame=$len.$frame;
		$client->tcpsock->syswrite($frame, length($frame));
	}
}




1;
