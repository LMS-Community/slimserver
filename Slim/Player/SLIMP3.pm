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
package Slim::Player::SLIMP3;

use Slim::Player::Player;
use Slim::Utils::Misc;

@ISA = ("Slim::Player::Player");

sub new {
	my (
		$class,
		$id,
		$paddr,			# sockaddr_in
		$revision,
		$udpsock,		# defined only for Slimp3
	) = @_;
	
	my $client = Slim::Player::Player->new( $id, $paddr, $revision);

	$client->udpsock($udpsock);

	bless $client, $class;
	
	return $client;
}

sub model {
	return 'slimp3';
}

sub type {
	return 'player';
}

sub ticspersec {
	return 625000;
}

sub decoder {
	return 'mas3507d';
}

sub vfdmodel {
	my $client = shift;
	if ($client->revision >= 2.2) {
		my $mac = $client->macaddress();
		if ($mac eq '00:04:20:03:04:e0') {
			return 'futaba-latin1';
		} elsif ($mac eq '00:04:20:02:07:6e' ||
				$mac =~ /^00:04:20:04:1/ ||
				$mac =~ /^00:04:20:00:/	) {
			return 'noritake-european';
		} else {
			return 'noritake-katakana';
		}
	} else {
		return 'noritake-katakana';
	}		
}

sub play {
	my $client = shift;
	my $paused = shift;
	my $pcm = shift;

	assert(!$pcm);
	
	$client->volume(Slim::Utils::Prefs::clientGet($client, "volume"));
	Slim::Hardware::Decoder::reset($client, $pcm);
	Slim::Networking::Stream::newStream($client, $paused);
	return 1;
}

#
# tell the client to unpause the decoder
#
sub resume {
	my $client = shift;
	$client->volume(Slim::Utils::Prefs::clientGet($client, "volume"));
	Slim::Networking::Stream::unpause($client);
	return 1;
}

#
# pause
#
sub pause {
	my $client = shift;
	Slim::Networking::Stream::pause($client);
	return 1;
}

#
# does the same thing as pause
#
sub stop {
	my $client = shift;
	Slim::Networking::Stream::stop($client);
}

#
# playout - play out what's in the buffer
#
sub playout {
	my $client = shift;
	Slim::Networking::Stream::playout($client);
	return 1;
}

sub bufferFullness {
	my $client = shift;
	return Slim::Networking::Stream::fullness($client);
}

sub bytesReceived {
	return shift->songpos;
}
1;

