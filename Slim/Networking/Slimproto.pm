package Slim::Networking::Slimproto;

# $Id: Slimproto.pm,v 1.9 2003/08/05 15:41:31 sadams Exp $

# Slim Server Copyright (c) 2001, 2002, 2003 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use FindBin qw($Bin);
use IO::Socket;
use IO::Select;
use FileHandle;
use Net::hostent;              # for OO version of gethostbyaddr
use Sys::Hostname;
use File::Spec::Functions qw(:ALL);
use POSIX qw(:fcntl_h strftime);
use Fcntl qw(F_GETFL F_SETFL);
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);

use Socket;
# qw(IPPROTO_TCP
#TCP_KEEPALIVE
#TCP_MAXRT
#TCP_MAXSEG
#TCP_NODELAY
#TCP_STDURG);

use Errno qw(EWOULDBLOCK EINPROGRESS);

my $SLIMPROTO_ADDR = 0;
my $SLIMPROTO_PORT = 3483;

my $slimproto_socket;
my $slimSelRead  = IO::Select->new();
my $slimSelWrite = IO::Select->new();

my %ipport;		# ascii IP:PORT
my %inputbuffer;  	# inefficiently append data here until we have a full slimproto frame
my %parser_state; 	# 'LENGTH', 'OP', or 'DATA'
my %parser_framelength; # total number of bytes for data frame
my %parser_frametype;   # frame type eg "HELO", "IR  ", etc.
my %sock2client;	# reference to client for each sonnected sock

sub init {
	my ($listenerport, $listeneraddr) = ($SLIMPROTO_PORT, $SLIMPROTO_ADDR);

	$slimproto_socket = IO::Socket::INET ->new(
		Proto => 'tcp',
		LocalAddr => $listeneraddr,
		LocalPort => $listenerport,
		Listen    => SOMAXCONN,
		ReuseAddr     => 1,
		Reuse     => 1,
		Timeout   => 0.001
	) || die "Can't listen on port $listenerport for Slim protocol: $!";

        defined($slimproto_socket->blocking(0))  || die "Cannot set port nonblocking";

	$slimSelRead->add($slimproto_socket);
	$main::selRead->add($slimproto_socket);

	$::d_protocol && msg "Squeezebox protocol listening on port $listenerport\n";	
}

sub idle {

	my $selReadable;
	my $selWriteable;

	($selReadable, $selWriteable) = IO::Select->select($slimSelRead, $slimSelWrite, undef, 0);

	my $sock;
	foreach $sock (@$selReadable) {

		if ($sock eq $slimproto_socket) {
			slimproto_accept();
		} else {
			client_readable($sock);
		}
	}

	foreach $sock (@$selWriteable) {
		next if ($sock == $slimproto_socket);  # never happens, right?
		client_writeable($sock);
	}
}


sub slimproto_accept {
	my $clientsock = $slimproto_socket->accept();

	return unless $clientsock;

        defined($clientsock->blocking(0))  || die "Cannot set port nonblocking";
#	setsockopt($clientsock, SOL_SOCKET, &TCP_NODELAY, 1);  # no nagle
	$clientsock->setsockopt(Socket::IPPROTO_TCP(), Socket::TCP_NODELAY(), 1);

	my $peer = $clientsock->peeraddr;

	if (!($clientsock->connected && $peer)) {
		$::d_protocol && msg ("Slimproto accept failed; couldn't get peer addr.\n");
		return;
	}

	my $tmpaddr = inet_ntoa($peer);

	if ((Slim::Utils::Prefs::get('filterHosts')) &&
		!(Slim::Utils::Misc::isAllowedHost($tmpaddr))) {
		$::d_protocol && msg ("Slimproto unauthorized host, accept denied: $tmpaddr\n");
		$clientsock->close();
		return;
	}

	$ipport{$clientsock} = $tmpaddr.':'.$clientsock->peerport;
	$parser_state{$clientsock} = 'OP';
	$parser_framelength{$clientsock} = 0;
	$inputbuffer{$clientsock}='';

	$slimSelRead->add($clientsock);
#	$slimSelWrite->add($clientsock);      # for now assume it's always writeable.
	$::main::selRead->add($clientsock);
#	$::main::selWrite->add($clientsock);

	$::d_protocol && msg ("Slimproto accepted connection from: $tmpaddr\n");
}

sub slimproto_close {
	my $clientsock = shift;

	# stop selecting	
	$slimSelRead->remove($clientsock);
	$main::selRead->remove($clientsock);
	$slimSelWrite->remove($clientsock);
	$main::selWrite->remove($clientsock);

	# close socket
	$clientsock->close();

	# forget state
	delete($ipport{$clientsock});
	delete($parser_state{$clientsock});
	delete($parser_framelength{$clientsock});
	delete($sock2client{$clientsock});
}		

sub client_writeable {
	my $clientsock = shift;

	# this prevent the "getpeername() on closed socket" error, which
	# is caused by trying to close the file handle after it's been closed during the
	# read pass but it's still in our writeable list. Don't try to close it twice - 
	# just ignore if it shouldn't exist.
	return unless (defined($ipport{$clientsock})); 
	
	$::d_protocol && msg("Slimproto client writeable: ".$ipport{$clientsock}."\n");

	if (!($clientsock->connected)) {
		$::d_protocol && msg("Slimproto connection closed by peer.\n");
		slimproto_close($clientsock);		
		return;
	}		
}

sub client_readable {
	my $s = shift;

	$::d_protocol && msg("Slimproto client readable: ".$ipport{$s}."\n");

	my $total_bytes_read=0;

GETMORE:
	if (!($s->connected)) {
		$::d_protocol && msg("Slimproto connection closed by peer.\n");
		slimproto_close($s);		
		return;
	}			

	my $bytes_remaining;

	$::d_protocol && msg(join(', ', 
		"state: ".$parser_state{$s},
		"framelen: ".$parser_framelength{$s},
		"inbuflen: ".length($inputbuffer{$s})
		)."\n");

	if ($parser_state{$s} eq 'OP') {
		$bytes_remaining = 4 - length($inputbuffer{$s});
                assert ($bytes_remaining <= 4);
	} elsif ($parser_state{$s} eq 'LENGTH') {
		$bytes_remaining = 4 - length($inputbuffer{$s});
		assert ($bytes_remaining <= 4);
	} else {
		assert ($parser_state{$s} eq 'DATA');
		$bytes_remaining = $parser_framelength{$s} - length($inputbuffer{$s});
	}
	assert ($bytes_remaining > 0);

	$::d_protocol && msg("attempting to read $bytes_remaining bytes\n");

	my $indata;
	my $bytes_read = $s->sysread($indata, $bytes_remaining);
	if (defined($bytes_read)) {
		$total_bytes_read += $bytes_read;
	}

	if (!defined($bytes_read) || ($bytes_read == 0)) {
		if ($total_bytes_read == 0) {
			$::d_protocol && msg("Slimproto half-close from client: ".$ipport{$s}."\n");
			slimproto_close($s);
			return;
		}

		$::d_protocol && msg("no more to read.\n");
		return;

	}


	$inputbuffer{$s}.=$indata;
	$bytes_remaining -= $bytes_read;

	$::d_protocol && msg ("Got $bytes_read bytes from client, $bytes_remaining remaining\n");

	assert ($bytes_remaining>=0);

	if ($bytes_remaining == 0) {
		if ($parser_state{$s} eq 'OP') {
			assert(length($inputbuffer{$s}) == 4);
			$parser_frametype{$s} = $inputbuffer{$s};
			$inputbuffer{$s} = '';
			$parser_state{$s} = 'LENGTH';

			$d::protocol && msg("got op: ". $parser_frametype{$s}."\n");

		} elsif ($parser_state{$s} eq 'LENGTH') {
			assert(length($inputbuffer{$s}) == 4);
			$parser_framelength{$s} = unpack('N', $inputbuffer{$s});
			$parser_state{$s} = 'DATA';
			$inputbuffer{$s} = '';

			if ($parser_framelength{$s} > 1000) {
				$::d_protocol && msg ("Client gave us insane length ".$parser_framelength{$s}." for slimproto frame. Disconnecting him.\n");
				slimproto_close($s);
				return;
			}

		} else {
			assert($parser_state{$s} eq 'DATA');
			assert(length($inputbuffer{$s}) == $parser_framelength{$s});
			&process_slimproto_frame($s, $parser_frametype{$s}, $inputbuffer{$s});
			$inputbuffer{$s} = '';
			$parser_frametype{$s} = '';
			$parser_framelength{$s} = 0;
			$parser_state{$s} = 'OP';
		}
	}

	$::d_protocol && msg("new state: ".$parser_state{$s}."\n");
	goto GETMORE;
}


sub process_slimproto_frame {
	my ($s, $op, $data) = @_;

	my $len = length($data);

	$::d_protocol && msg("Got Slimptoto frame, op $op, length $len\n");

	if ($op eq 'HELO') {
		if ($len != 8) {
			$::d_protocol && msg("bad length $len for HELO. Ignoring.\n");
			return;
		}
		my ($deviceid, $revision, @mac) = unpack("CCH2H2H2H2H2H2", $data);
		$revision = int($revision / 16) + ($revision % 16)/10.0;
		my $mac = join(':', @mac);
		$::d_protocol && msg("Squeezebox says hello. Deviceid: $deviceid, revision: $revision, mac: $mac\n");

		my $id=$mac;
		my $paddr = sockaddr_in($s->peerport, $s->peeraddr);

		$::d_protocol && msg("creating new client, id:$id ipport: $ipport{$s}\n");
		my $client=Slim::Player::Client::newClient(
			$id, 		# mac
			$paddr,		# sockaddr_in
			$ipport{$s},	# ascii ip:port
			$deviceid,	# devieid
			$revision,	# rev
			undef,		# udp sock
			$s		# tcp sock
		);

		$sock2client{$s}=$client;
		return;
	} 

	my $client=$sock2client{$s};
	assert($client);

	if ($op eq 'IR  ') {
		# format for IR:
		# [4]   time since startup in ticks (1KHz)
		# [1]	code format
		# [1]	number of bits 
		# [4]   the IR code, up to 32 bits      
		if ($len != 10) {
			$::d_protocol && msg("bad length $len for IR. Ignoring\n");
			return;
		}

		my ($irTime, $irCode) =unpack 'NxxH8', $data;
		Slim::Hardware::IR::enqueue($client, $irCode, $irTime);
	} elsif ($op eq 'RESP') {
		# HTTP stream headers
		print "Squeezebox got HTTP response:\n$data";
	}
}

1;

