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
		$frame = 'l                 '.$data;
		my $len = pack('n',length($frame));
		$::d_protocol && msg ("sending squeezebox frame, length ".length($frame)."\n");
		$frame = $len.$frame;
		$client->tcpsock->syswrite($frame,length($frame));
	}
}

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

sub i2c {
	my ($client, $data) = @_;

	$::d_i2c && msg("i2c: sending ".length($data)." bytes\n");

	if ($client->model eq 'slimp3') {
		send($client->udpsock, '2                 '.$data, 0, $client->paddr);
	} else {
		assert($client->model eq 'squeezebox');
		#TODO
	}
}




1;
