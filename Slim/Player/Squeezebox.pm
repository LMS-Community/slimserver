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
	Slim::Networking::Sendclient::stream($client, 's');
	return 1;
}
#
# tell the client to unpause the decoder
#
sub resume {
	my $client = shift;
	$client->volume(Slim::Utils::Prefs::clientGet($client, "volume"));
	Slim::Networking::Sendclient::stream($client, 'u');
	return 1;
}

#
# pause
#
sub pause {
	my $client = shift;
	Slim::Networking::Sendclient::stream($client, 'p');
	return 1;
}

#
# does the same thing as pause
#
sub stop {
	my $client = shift;
	Slim::Networking::Sendclient::stream($client, 'q');
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

1;