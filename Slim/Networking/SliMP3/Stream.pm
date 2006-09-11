package Slim::Networking::SliMP3::Stream;

# $Id4

# SlimServer Copyright (C) 2001-2004 Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;

use Slim::Utils::Timers;
use Slim::Utils::Misc;
use Slim::Player::SLIMP3;
use bytes;

###
### lots o' knobs:
###
my $TIMEOUT      		= 0.05;  # timeout
my $ACK_TIMEOUT			= 30.0; # in seconds

my $MAX_PACKET_SIZE		= 1400;
my $BUFFER_SIZE			= 131072; # in bytes
my $PAUSE_THRESHOLD		= $MAX_PACKET_SIZE; # pause until we refill the buffer
my $UNPAUSE_THRESHOLD 		= $BUFFER_SIZE / 2; # fraction of buffer needed full in order to start playing
my $BUFFER_FULL_THRESHOLD 	= $BUFFER_SIZE - $MAX_PACKET_SIZE * 2; # fraction of buffer to consider full up

my $BUFFER_FULL_DELAY		= 0.05; # seconds to wait until trying to resend packet when the buffer is full

# for each client:
our %streamState;		# the state of the stream
our %curWptr;			# the highest outstanding wptr we've sent to the client
our %bytesSent;			# bytes sent in this stream
our %seq;				# the next sequence number to send
our %packetInFlight;		# hash of references of  the packet in flight to this client
our %fullness;			# number of bytes in the buffer as of the last packet
our %lastAck;			# timeout in the case that the player disappears completely.
our %lastByte;			# if we get an odd number of bytes from the upper level, hold on to the last one.

my $empty = '';

#
# things we remember about packets in flight
#	chunkref
#	wptr
#	seq
#	len

###
###  External interface
###

# This module provides the interface for controlling streams to the player
#

# newStream - start a new stream 
#
#   $client		the client
#
#   initial state	can be 'paused' or 'buffering'
#			the caller specifies either 'paused' or 'play', and we decide internally
# 			how to handle the buffering.
#

sub newStream {
	my ($client, $paused) = @_;
	
	$::d_stream && msg( $client->id() ." new stream " . ($paused ? "paused" : "") . "\n");
		
	if ($paused) {
		$streamState{$client} = 'paused';
	} else {
		$streamState{$client} = 'buffering';

	}
	
	$bytesSent{$client} = 0;
	$curWptr{$client}   = 0;
	
	if (!defined($seq{$client})) {
		$seq{$client} = 1;
	}

	$fullness{$client} = 0;
	$packetInFlight{$client} = undef;
	$lastAck{$client} = Time::HiRes::time();

	Slim::Utils::Timers::killOneTimer($client, \&sendNextChunk);
	
	sendNextChunk($client);
}

sub fullness {
	my ($client) = @_;

	return $fullness{$client} || 0;
}

# 
# Pauses playback (but keep filling the buffer)
#

sub pause {
	my ($client) = @_;
	$::d_stream && msg($client->id() ." pause\n");
	
	if ($streamState{$client} ne 'play' && $streamState{$client} ne 'buffering') {
		$::d_stream && msg("Attempted to pause a " . $streamState{$client} .  " stream.\n");
		return 0;
	}

	$streamState{$client}='paused';

	if ($fullness{$client} > $BUFFER_FULL_THRESHOLD) {
		sendEmptyChunk($client);
	} else {
		sendNextChunk($client);
	}
	
	return 1;
}

#
# Halts playback completely
#

sub stop {
	my ($client) = @_;
		
	$::d_stream && msg( $client->id() ." stream stop\n");
	if (!$streamState{$client} || $streamState{$client}  eq 'stop') {
		$::d_stream && msg("Attempted to stop an already stopped stream.\n");
		return 0;
	}
	$streamState{$client}='stop';
	sendNextChunk($client);	
	$client->bytesReceived(0);
	return 1;
}

sub playout {
	my ($client) = @_;
	$::d_stream && msg( $client->id() ." stream play out\n");
	$streamState{$client}='eof';
}
	
#
# Unpauses a paused stream. If the buffer is too low to unpause, this
# does not take effect until it has filled sufficiently.
#
sub unpause {
	my ($client) = @_;
	$::d_stream && msg($client->id() ." unpause\n");
	if ($streamState{$client} eq 'buffering') {
		return 0;  # can't force unpause while in buffering state.
	} elsif ($streamState{$client} eq 'stop') {
		msg( "Attempted to unpause a stopped stream.\n");
		bt();
	} elsif ($streamState{$client} eq 'play') {
		return 0;
	} elsif  ($streamState{$client} eq 'paused') {
		$streamState{$client} = 'play';
		sendNextChunk($client);
		return 1;	
	} else {
		msg( "Bogus streamstate for unpause\n");
		bt();
	}
	return 0;
}

#####
#####  Internal state
#####

#  A stream can be in one of the following states: 
#
#  'buffering'		We fill the client's buffer until it passes the low water mark,
#			then we automatically start the decoder.
#
#  'paused'		Same as 'buffering', except we don't start the stream until we're told
#
#  'play'		The decoder is running. We keep feeding data until we're either told
#			stop, or the client buffer runs empty. If the buffer runs empty, we 
#			go back to the 'buffering' state (this will eventually be configurable).
#
#  'stop'		The decoder is stopped, and there's no data for us to send.
#
#  'eof'		There is no more data. Leave the decoder running until the buffer runs empty
#
#  Initially a client is in the 'stop' state. A new stream is normally started in 
#  the 'buffering' state, but streams can also be started in the 'paused' state, to
#  allow synchronization of multiple players.
#

# The stream control code is included with every packet of data
#
my %streamControlCodes = (
        'go' 	=> 0,   # Run the decoder
        'stop'	=> 1,   # Halt decoder but don't reset rptr
        'reset'	=> 3  # Halt decoder and reset rptr  
	);

#
# send a packet
#
sub sendStreamPkt {
	my ($client, $pkt) = @_;	
	
	my $seq  = $pkt->{'seq'};
	my $len  = $pkt->{'len'};
	my $wptr = $pkt->{'wptr'};
	
	$::d_stream_v && msg($client->id() . " " . Time::HiRes::time() .
		" sending stream, seq = $seq len = $len wptr = $wptr state=". 
		$streamState{$client}.
		" inflight=" . defined($packetInFlight{$client}) . "\n"
	);

	my $control;
	my $streamState = $streamState{$client};
	
	if (($streamState eq 'stop') || ($bytesSent{$client} == 0)) {
		$::d_stream_v && msg(ms()." reset\n");
		$control = $streamControlCodes{'reset'};
		
	} elsif ($streamState eq 'buffering') {
		$control = $streamControlCodes{'reset'};
		
	} elsif ($streamState eq 'paused') {
		$control = $streamControlCodes{'stop'};
		
	} elsif ($streamState eq 'play') {
		$control = $streamControlCodes{'go'};
		
	} elsif ($streamState eq 'eof') {
		$control = $streamControlCodes{'go'};
	} else {
		msg( "bogus streamstate $streamState");
		bt();
	}

	my $measuredlen = length(${$pkt->{'chunkref'}});

	if ($len == $measuredlen && $len < 4097 ) {
		$client->udpstream($control, $wptr, $seq, ${$pkt->{'chunkref'}});
	
		if ($::d_stream && $packetInFlight{$client}) {
			msg("Sending packet when we have one in queue!!!!!!\n"); 
			bt();
		};
		
		$packetInFlight{$client} = $pkt;
		$bytesSent{$client} += $len;

	} else {
		msg("Bogus length $len, measured: $measuredlen\n");
		bt();
	}

	# restart the timeout
	Slim::Utils::Timers::setTimer($client, Time::HiRes::time()+$TIMEOUT, \&timeout, ($seq));
}

#
# Retransmit timed out packet

sub timeout {
	my $client = shift;
	my $seq = shift;
		
	Slim::Utils::Timers::killOneTimer($client, \&timeout);

	return unless $packetInFlight{$client};

	my $packet = $packetInFlight{$client};

	$::d_stream && msg($client->id() . " " . Time::HiRes::time() . " Timeout on seq: " . $packet->{'seq'} . "\n");

	$packetInFlight{$client} = undef;

	if (($lastAck{$client} + $ACK_TIMEOUT) < Time::HiRes::time()) {
		# we haven't gotten an ack in a long time.  shut it down and don't bother resending.
		Slim::Player::Sync::unsync($client);
		$client->execute(["stop"]);
	} else {
		sendStreamPkt($client, $packet);
	}
}

#
# receive an ack, then send one or two more packets
#
sub gotAck {
	my ($client, $wptr, $rptr, $seq) = @_;
	my $pkt;
	my $pkt2;
	my $eachpkt;

	if (!defined($streamState{$client})) {
		$::d_stream && msg($client->id() . ": received a stray ack from an unknown client - ignoring.\n");
		return;
	}

	$::d_stream_v && msg($client->id() . " ".Time::HiRes::time() .  " gotAck for seq: $seq ");
	$::d_stream_v && msg("ack: wptr:$wptr, rptr:$rptr, seq:$seq, ");

	# calculate buffer usage
	# todo: optimize usage calculations
	my $bytesInFlight = 0;

	if ($packetInFlight{$client}) {
		$bytesInFlight += $packetInFlight{$client}->{'len'};
	}

	my $fullness = $curWptr{$client} - $rptr;  

	if ($fullness < 0) {
		$fullness += $UNPAUSE_THRESHOLD;
	} 

	$fullness = $fullness * 2 + $bytesInFlight;
	
	$fullness{$client} = $fullness;
	
	$::d_stream_v && msg("bytesinflight:$bytesInFlight fullness:" . $fullness{$client} . "\n");
	
	if (!$packetInFlight{$client}) {
		$::d_stream && msg("***Missing packet acked: $seq\n");
	} elsif ($packetInFlight{$client}->{'seq'} != $seq) { 
		$::d_stream && msg("***Unexpected packet acked: $seq, was expecting " . $packetInFlight{$client}->{'seq'} . "\n");
	} else {
		$client->bytesReceived($client->bytesReceived + $packetInFlight{$client}->{'len'});
		$packetInFlight{$client} = undef;
		Slim::Utils::Timers::killOneTimer($client, \&timeout);
		$lastAck{$client} = Time::HiRes::time();
	}

	if ($fullness <= 512) { 
		$::d_stream && msg("***Stream underrun: $fullness\n");
		Slim::Player::Source::underrun($client);
		if ($streamState{$client} eq 'eof') { 
			$streamState{$client} = 'stop'; 
		};
	}

	my $state = $streamState{$client};

	if ($state eq 'stop') {
		# don't bother sending anything.
	} else {
		sendNextChunk($client);
	}
}

#
# sends the next packet of data in the stream
#
sub sendNextChunk {
	my $client   = shift;

	my $fullness = $fullness{$client};
	my $curWptr  = $curWptr{$client};

	Slim::Utils::Timers::killOneTimer($client, \&sendNextChunk);

	# if there's a packet in flight, come back later and try again...
	if ($packetInFlight{$client}) {
		Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + $BUFFER_FULL_DELAY, \&sendNextChunk);
		return 0;
	}

	my $streamState = $streamState{$client};
	
	if (($streamState eq 'stop')) { 
		sendEmptyChunk($client);
		# there is no more data to send
		return 0;
	}
	
	if ($fullness > $BUFFER_FULL_THRESHOLD) {
		$::d_stream_v && msg($client->id() . "- $streamState -  Buffer full, need to poll to see if there is space\n");
		# if client's buffer is full, poll it every 50ms until there's room if we're playing
		# otherwise, we can't send a chunk.
		if ($streamState eq 'play' || $streamState eq 'eof') {
			Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + $BUFFER_FULL_DELAY, \&sendEmptyChunk);
		} 
		return 0;
	}

	my $requestedChunkSize = Slim::Utils::Prefs::get('udpChunkSize');
	
	my $remainingSpace = $client->bufferSize() - ($curWptr * 2);
	
	if ($remainingSpace && $requestedChunkSize > $remainingSpace) {
		$requestedChunkSize = $remainingSpace;
	}

	if (defined($lastByte{$client})) {
		$requestedChunkSize--;
	}

	my $chunkRef = Slim::Player::Source::nextChunk($client, $requestedChunkSize);
	
	if (!defined($chunkRef)) {

		$::d_stream && msg("stream not readable\n");

		if ($streamState eq 'eof') {

			$::d_stream && msg("sending empty chunk...\n");
			# we're going to poll after BUFFER_FULL_DELAY with an empty chunk so we can know when the player runs out.
			Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + $BUFFER_FULL_DELAY, \&sendEmptyChunk);

		} else {
				Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + $TIMEOUT, \&sendNextChunk);
		}

		return 0;
	}
	
	if (defined($lastByte{$client})) {
		$$chunkRef = $lastByte{$client} . $$chunkRef;
		delete($lastByte{$client});	
	}
	
	my $len = length($$chunkRef) || 0;
	
	# We must send an even number of bytes.
	if (($len % 2) != 0) {

		$lastByte{$client} = substr($$chunkRef, -1, 1);
		$$chunkRef = substr($$chunkRef, 0, -1);
		$len--;
	} 

	if (($fullness > $UNPAUSE_THRESHOLD) && ($streamState eq 'buffering')) {
		$streamState{$client}='play';
		$::d_stream && msg($client->id() . " Buffer full, starting playback\n");
		$client->currentplayingsong(Slim::Player::Playlist::song($client));
		$client->remoteStreamStartTime(time());

	} elsif (($fullness < $PAUSE_THRESHOLD) && ($streamState eq 'play')) {
		$::d_stream && msg($client->id() . "Buffer drained, pausing playback\n");
		$streamState{$client}='buffering';
	}
	
	my $pkt = {
		'wptr'     => $curWptr,
		'len'      => $len,
		'chunkref' => $chunkRef,
	};
	
	$curWptr = $curWptr + $len/2;

	if ($curWptr >= $UNPAUSE_THRESHOLD) {
		$curWptr -= $UNPAUSE_THRESHOLD;
	};
	
	$curWptr{$client} = $curWptr;
	
	sendPkt($client, $pkt);

	return 1;
}

#
# send a stream packet with no data. Used to update the stream control code
# and also to effect a poll of the client's buffer usage. 
#

sub sendEmptyChunk {

	my ($client) = @_;

	$::d_stream_v && msg($client->id() . " sendEmptyChunk\n");

	my $pkt = {};

	$pkt->{'wptr'}     = $curWptr{$client};
	$pkt->{'len'}      = 0;
	$pkt->{'chunkref'} = \$empty;

	sendPkt($client, $pkt);
}

sub sendPkt {
	my $client = shift;
	my $pkt    = shift;

	my $seq = $seq{$client};
	$pkt->{'seq'} = $seq;

	sendStreamPkt($client, $pkt);
	
	$seq++;

	if ($seq >= $UNPAUSE_THRESHOLD) {
		$seq -= $UNPAUSE_THRESHOLD;
	};

	$seq{$client} = $seq;
}

# returns a time stamp for debugging
sub ms {
	return (int(Time::HiRes::time()*10000)%100000/10);
}


1;
__END__
