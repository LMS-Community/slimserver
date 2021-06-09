package Slim::Networking::SliMP3::Stream;


# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use bytes;

use Slim::Player::Source;
use Slim::Player::SB1SliMP3Sync;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Timers;
use Slim::Utils::Prefs;

###
### lots o' knobs:
###
my $TIMEOUT               = 0.05;  # timeout
my $ACK_TIMEOUT           = 30.0; # in seconds

my $MAX_PACKET_SIZE       = 1400;
my $BUFFER_SIZE           = 131072; # in bytes
my $UNPAUSE_THRESHOLD     = $BUFFER_SIZE / 2; # fraction of buffer needed full in order to start playing
my $BUFFER_FULL_THRESHOLD = $BUFFER_SIZE - $MAX_PACKET_SIZE * 2; # fraction of buffer to consider full up

my $BUFFER_FULL_DELAY     = 0.05; # seconds to wait until trying to resend packet when the buffer is full
my $WPTR_LIMIT            = $BUFFER_SIZE / 2; # point at which player decode buffer wraps around
my $SEQ_LIMIT             = $WPTR_LIMIT; # pretty arbitray, not really related to wptr or anything else

# for each client:
our %streamState;		# the state of the stream
our %curWptr;			# the highest outstanding wptr we've sent to the client
our %bytesSent;			# bytes sent in this stream
our %seq;				# the next sequence number to send
our %dataPktInFlight;	# hash of references of the data packet in flight to this client
our %emptyPktInFlight;	# hash of references of the empty packet in flight to this client
our %fullness;			# number of bytes in the buffer as of the last packet
our %lastAck;			# timeout in the case that the player disappears completely.
our %lastByte;			# if we get an odd number of bytes from the upper level, hold on to the last one.
our %sentUnderrun;		# have we sent an underrun since the last time we were started or unpaused

# the following are used to track and correct synchronization with other players

our %latencyList;		# array of most-recent packet round-trip-time measures
use constant LATENCY_LIST_SIZELIMIT		=> 20;		# max number of samples to keep
use constant LATENCY_LIST_MINSIZE		=> 7;		# min number of sample for valid measure
our %samplePlayPointAfter;	# next time to sample the play-point
use constant PLAY_POINT_SAMPLE_INTERVAL	=> 0.500;	# how often to check the play-point
our %pauseUntil;		# send 'stop' instead of 'go' until past this time
use constant MIN_DEVIATION_ADJUST		=> 0.030;	# minimum deviation to try and adjust;

my $empty = '';

my $log = logger('network.protocol.slimp3');

#
# things we remember about packets in flight
#	chunkref
#	wptr
#	seq
#	len

###
###  External interface
###

=head1 DESCRIPTION

This module provides the interface for controlling streams to a SliMP3 player.

=head1 CLIENT METHODS

=head2 newStream( $client, $paused )

Start a new stream to the client.

$paused can be 'paused' or 'buffering'.

The caller specifies either 'paused' or 'play', and we decide internally how
to handle the buffering.

=cut

sub newStream {
	my ($client, $paused) = @_;
	
	if ( main::INFOLOG && $log->is_info ) {
		$log->info($client->id, " new stream: ", ($paused ? "paused" : ""));
	}

	if ($paused) {
		$streamState{$client} = 'paused';
	} else {
		$streamState{$client} = 'buffering';
	}
	
	$bytesSent{$client} = 0;
	$curWptr{$client}   = 0;
	$lastByte{$client}  = undef;
	
	if (!defined($seq{$client})) {
		$seq{$client} = 1;
	}

	$fullness{$client} = 0;
	$dataPktInFlight{$client} = undef;
	$emptyPktInFlight{$client} = undef;
	$lastAck{$client} = Time::HiRes::time();
	$sentUnderrun{$client} = 0;
	
	if (!defined($latencyList{$client})) {
		$latencyList{$client} = [];
	}
	
	$client->playPoint(undef);
	$pauseUntil{$client} = 0;
	
	$client->readyToStream(0);
	$client->bufferReady(0);
	$client->bytesReceived(0);

	Slim::Utils::Timers::killOneTimer($client, \&sendNextChunk);
	
	sendNextChunk($client);
}

sub fullness {
	my ($client) = @_;

	return $fullness{$client} || 0;
}

=head2 pause( $client )

Pauses playback (but keep filling the buffer)

=cut

sub pause {
	my ($client, $interval) = @_;

	if ( main::INFOLOG && $log->is_info ) {
		$log->info( $client->id, " pause" . ($interval ? " for $interval" : '') );
	}
	
	if ($interval) {
		if ($streamState{$client} ne 'play' && $streamState{$client} ne 'eof') {
			$::d_stream && msg("Attempted to pause a " . $streamState{$client} .  " stream.\n");
			return 0;
		}
		if ($interval > MIN_DEVIATION_ADJUST) {
			$interval -= 0.005;	# safety
			# need to force drain of internal buffer
			my $bitrate = $client->streamingSong()->streambitrate() || 128000;
			$interval += 1000 * 8 / $bitrate;
			$::d_stream && msg($client->id() ." actual interval: $interval \n");
			$pauseUntil{$client} = Time::HiRes::time() + $interval;
			sendEmptyChunk($client);
			$samplePlayPointAfter{$client} = $pauseUntil{$client} + PLAY_POINT_SAMPLE_INTERVAL;
			$client->playPoint(undef);
			return 1;
		} else {
			return 0;
		}
	}

	if ($streamState{$client} ne 'play' && $streamState{$client} ne 'buffering') {

		main::INFOLOG && $log->info("Attempted to pause a $streamState{$client} stream.");

		return 0;
	}

	$streamState{$client} = 'paused';

	if ($fullness{$client} > $BUFFER_FULL_THRESHOLD) {
		sendEmptyChunk($client);
	} else {
		sendNextChunk($client);
	}
	$client->playPoint(undef);
	
	return 1;
}

=head2 stop( $client )

Halts playback completely

=cut

sub stop {
	my ($client) = @_;

	if ( main::INFOLOG && $log->is_info ) {
		$log->info($client->id, " stream stop");
	}

	if (!$streamState{$client} || $streamState{$client}  eq 'stop') {

		main::INFOLOG && $log->info("Attempted to stop an already stopped stream.");

		return 0;
	}

	$streamState{$client} = 'stop';

	sendEmptyChunk($client);	

	$client->bytesReceived(0);
	$client->readyToStream(1);
	
	$fullness{$client} = 0;
	$client->playPoint(undef);

	return 1;
}

=head2 unpause( $client )

Unpauses a paused stream. If the buffer is too low to unpause, this does not
take effect until it has filled sufficiently.

=cut

sub unpause {
	my ($client, $at) = @_;

	if ( main::INFOLOG && $log->is_info ) {
		$log->info($client->id, " unpause");
	}

	if ($streamState{$client} eq 'buffering') {

		# can't force unpause while in buffering state.
		return 0;

	} elsif ($streamState{$client} eq 'stop') {

		$log->logBacktrace("Attempted to unpause a stopped stream.");

	} elsif ($streamState{$client} eq 'play') {

		return 0;

	} elsif  ($streamState{$client} eq 'paused') {

		$streamState{$client} = 'play';
		$sentUnderrun{$client} = 0;
		
		if ($at) {
			$pauseUntil{$client} = $at - 0.010;
		}
		
		sendEmptyChunk($client);
		return 1;	

	} else {

		logBacktrace("Bogus streamstate for unpause.");
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
my %streamControlCodes = (
        'go' 	=> 0, # Run the decoder
        'stop'	=> 1, # Halt decoder but don't reset rptr
        'reset'	=> 3  # Halt decoder and reset rptr  
);

sub isPlaying {
	my $client = shift;
	my $state = $streamState{$client};
	return $state && $state eq 'play';
}

# send a packet
sub sendStreamPkt {
	my ($client, $pkt) = @_;	
	
	my $seq  = $pkt->{'seq'};
	my $len  = $pkt->{'len'};
	my $wptr = $pkt->{'wptr'};

	my $control;
	my $streamState = $streamState{$client};
	my $now         = Time::HiRes::time();
	
	if (($streamState eq 'stop') || ($bytesSent{$client} == 0)) {

		main::DEBUGLOG && $log->debug("reset");

		$control = $streamControlCodes{'reset'};
		
	} elsif ($streamState eq 'buffering') {

		$control = $streamControlCodes{'reset'};
		$pauseUntil{$client} = 0;

	} elsif ($streamState eq 'paused') {

		$control = $streamControlCodes{'stop'};
		$pauseUntil{$client} = 0;

	} elsif ($streamState eq 'play') {

		$control = $streamControlCodes{'go'};

	} elsif ($streamState eq 'eof') {

		$control = $streamControlCodes{'go'};

	} else {

		$log->logBacktrace("Bogus streamstate $streamState");
	}
	
	if ($control == $streamControlCodes{'go'} && $pauseUntil{$client} > $now) {
		$control = $streamControlCodes{'stop'};
	}
	
	if ( main::DEBUGLOG && $log->is_debug ) {
		$log->debug(
			$client->id() . 
			" sending stream: seq:$seq, len:$len, wptr:$wptr, state:". 
			$streamState{$client}.
			", control:$control, inflight:" . (0 + defined($dataPktInFlight{$client}) + defined($emptyPktInFlight{$client}))
		);
	}

	my $measuredlen = length(${$pkt->{'chunkref'}});

	if ($len == $measuredlen && $len < 4097 ) {

		$client->udpstream($control, $wptr, $seq, ${$pkt->{'chunkref'}});
		$pkt->{'sendTimeStamp'} = $now;
	
		if ($log->is_warn && $len && $dataPktInFlight{$client}) {
			$log->logBacktrace("Sending data packet when we have one in queue!!!!!!"); 
		};
		
		if ($len) {
			$dataPktInFlight{$client}  = $pkt;
			$bytesSent{$client}       += $len;
		} else {
			$emptyPktInFlight{$client} = $pkt;
		}

	} else {

		$log->logBacktrace("Bogus length $len, measured: $measuredlen");
	}

	# restart the timeout
	Slim::Utils::Timers::setTimer(
		$client,
		make_timeout($client, $TIMEOUT, $now),
		\&timeout,
		($seq)
	);
}

# Retransmit timed out packet
sub timeout {
	my ($client, $seq) = @_;
		
	Slim::Utils::Timers::killOneTimer($client, \&timeout);

	return unless ($dataPktInFlight{$client} || $emptyPktInFlight{$client});

	if ( main::DEBUGLOG && $log->is_debug ) {
		$log->debug($client->id, " Timeout on seq: $seq");
	}
	
	if (($lastAck{$client} + $ACK_TIMEOUT) < Time::HiRes::time()) {

		# we haven't gotten an ack in a long time.  shut it down and don't bother resending.
		$client->controller()->playerInactive($client);
		$dataPktInFlight{$client}  = undef;
		$emptyPktInFlight{$client} = undef;
		$client->execute(["stop"]);

	} else {
		# Resend the packet
		my $packet;
		if ($dataPktInFlight{$client}) {
			$packet = $dataPktInFlight{$client};
			$dataPktInFlight{$client}  = undef;
			$emptyPktInFlight{$client} = undef;	# forget about retrying it
			sendStreamPkt($client, $packet);
		}
		else {
			$packet = $emptyPktInFlight{$client};
			$emptyPktInFlight{$client} = undef;
			sendStreamPkt($client, $packet);
		}
	}
}

# receive an ack, then send one or two more packets
sub gotAck {
	my ($client, $wptr, $rptr, $seq, $msgTimeStamp) = @_;

	if (!defined($streamState{$client})) {

		if ( $log->is_warn ) {
			$log->warn($client->id, ": received a stray ack from an unknown client - ignoring.");
		}

		return;
	}

	# calculate buffer usage
	# todo: optimize usage calculations
	my $bytesInFlight = $dataPktInFlight{$client} ? $dataPktInFlight{$client}->{'len'} : 0;

	# is this an expected packet?
	my $packet;
	if ($dataPktInFlight{$client} && $dataPktInFlight{$client}->{'seq'} == $seq) {
		$packet = $dataPktInFlight{$client};
		$dataPktInFlight{$client} = undef;
	}
	elsif ($emptyPktInFlight{$client} && $emptyPktInFlight{$client}->{'seq'} == $seq) {
		$packet = $emptyPktInFlight{$client};
		$emptyPktInFlight{$client} = undef;
	}

	my $fullness = (($curWptr{$client} - $rptr + $WPTR_LIMIT) % $WPTR_LIMIT) * 2;
	$fullness{$client} = $fullness;

	my $pktLatency = $packet
		? int(($msgTimeStamp - $packet->{'sendTimeStamp'})*1000000/2) : -1;

	if ( main::DEBUGLOG && $log->is_debug ) {
		$log->debug(
			$client->id() . " gotAck: wptr:$wptr rptr:$rptr seq:$seq " .
			"inflight:$bytesInFlight fullness:$fullness{$client} latency:$pktLatency us"
		);
	}

	if ( !$packet ) {
		if ( main::DEBUGLOG && $log->is_debug ) {
			if ( ($seq{$client} - $seq) % $SEQ_LIMIT > 2) {
				$log->debug($client->id() . " ***Missing or unexpected packet acked: $seq");
			}
		}
		
	} else {
		# Keep track of effective network delay to this client;
		# assume packet latency is half round-trip-time; stored in microseconds.
		# Keep set of recent entries and assume that only values below the median are representative
		my $latencyList = $latencyList{$client};
		push(@{$latencyList}, $pktLatency); shift @{$latencyList} if (@{$latencyList} > LATENCY_LIST_SIZELIMIT);

		Slim::Utils::Timers::killOneTimer($client, \&timeout);

		$client->bytesReceived($client->bytesReceived + $packet->{'len'});
		$lastAck{$client} = $msgTimeStamp;

		# Calculate and publish playPoint
		#
		# The following calculations are costly, so only do when necessary, and not too frequently.
		my $medianLatency;
		if (   $client->isSynced(1)
			&& ($streamState{$client} eq 'play' || $streamState{$client} eq 'eof')
			&& $msgTimeStamp > ($samplePlayPointAfter{$client} || 0)
			&& defined($medianLatency = getMedianLatencyMicroSeconds($client))
		) {
			if ($pktLatency <= $medianLatency) {
				my $statusTime = $msgTimeStamp - $pktLatency / 1000000;
				my $apparentStreamStartTime = Slim::Player::SB1SliMP3Sync::apparentStreamStartTime($client, $statusTime);

				$client->publishPlayPoint($statusTime, $apparentStreamStartTime, $pauseUntil{$client}) if $apparentStreamStartTime;

				# only do this again after a short interval
				$samplePlayPointAfter{$client} = $msgTimeStamp + PLAY_POINT_SAMPLE_INTERVAL;
			}
		}
	}
	
	my $state = $streamState{$client};

	if ( $fullness <= 512 && !$sentUnderrun{$client} && ($state eq 'play' || $state eq 'eof') ) {
		main::DEBUGLOG && $log->debug("***Stream underrun: $fullness");
		$sentUnderrun{$client} = 1;	
		$client->underrun(); # xxx - need to send this only once
	}
	elsif ($fullness > $UNPAUSE_THRESHOLD) {
		if	($state eq 'buffering') {

			$streamState{$client} ='play';
	
			main::INFOLOG && $log->info($client->id, " Buffer full, starting playback");
	
			$client->currentplayingsong(Slim::Player::Playlist::track($client));
			$client->remoteStreamStartTime(time());
			
			$client->bufferReady(1);
			$client->autostart();
			
		} elsif ($state eq 'paused') {
			if (!$client->bufferReady()) {
				$client->bufferReady(1);
				$client->controller()->playerBufferReady($client);
			}
		} else {
			$client->heartbeat();
		}
	} else {
		$client->heartbeat() if $state eq 'play';
	}
	
	sendNextChunk($client) unless ($state eq 'stop');
}

sub make_timeout {
	my ($client, $delta, $now) = @_;

	$now = Time::HiRes::time() unless defined($now);

	my $pauseUntil = $pauseUntil{$client};

	if ($pauseUntil > $now) {
		my $timeout = $now + $delta;
		return $timeout > $pauseUntil ? $pauseUntil : $timeout;
	}
	else {
		return $now + $delta;
	}
}

# sends the next packet of data in the stream
sub sendNextChunk {
	my $client   = $_[0];

	my $fullness = $fullness{$client};
	my $curWptr  = $curWptr{$client};

	Slim::Utils::Timers::killOneTimer($client, \&sendNextChunk);
	
	my $streamState = $streamState{$client};

	# if there's a packet in flight, come back later and try again...
	if ($dataPktInFlight{$client} || $emptyPktInFlight{$client}) {
		if ( main::DEBUGLOG && $log->is_debug ) {
			$log->debug(
				$client->id() . "- $streamState - " .
				($dataPktInFlight{$client} ? "data" : "empty") 
				. " packet already in flight"
			);
		}
		
		Slim::Utils::Timers::setTimer(
			$client, 
			make_timeout($client, $BUFFER_FULL_DELAY),
			\&sendNextChunk
		);
		
		return 0;
	}
	
	if (($streamState eq 'stop')) { 

		sendEmptyChunk($client);

		# there is no more data to send
		return 0;
	}
	
	if ($fullness > $BUFFER_FULL_THRESHOLD) {

		if ( main::DEBUGLOG && $log->is_debug ) {
			$log->debug($client->id, "- $streamState - Buffer full, need to poll to see if there is space");
		}

		# if client's buffer is full, poll it every 50ms until there's room 
		# Note: already dealt with 'stop' case above; previous test for 'play' || 'eof' may have missed certain race conditions
		Slim::Utils::Timers::setTimer(
			$client, 
			make_timeout($client, $BUFFER_FULL_DELAY),
			\&sendEmptyChunk
		);

		return 0;
	}

	my $requestedChunkSize = preferences('server')->get('udpChunkSize');

	my $remainingSpace = $client->bufferSize() - ($curWptr * 2);

	if ($remainingSpace && $requestedChunkSize > $remainingSpace) {

		$requestedChunkSize = $remainingSpace;
	}

	if (defined($lastByte{$client})) {

		$requestedChunkSize--;
	}
	
	## TODO - if we are just about to unpause, then send an empty packet rather than waste time
	# getting another chunk.

	my $chunkRef = $client->nextChunk($requestedChunkSize)
		unless $streamState{$client} eq 'eof';
	
	if (!defined($chunkRef)) {

		0 && $log->warn("Stream not readable");

		# we're going to poll after BUFFER_FULL_DELAY with an empty chunk so we can know when the player runs out.
		Slim::Utils::Timers::setTimer($client, make_timeout($client, $BUFFER_FULL_DELAY), \&sendEmptyChunk);

		return 0;
	}
	
	elsif (!length($$chunkRef)) {
		main::INFOLOG && $log->info($client->id, " stream play out");
		$streamState{$client} = 'eof';
	}
	
	if (defined($lastByte{$client})) {
		
		# need to copy in case another client has reference to the same chunk (unlikely)
		my $newChunk = $lastByte{$client} . $$chunkRef;
		$chunkRef = \$newChunk;
		
		delete($lastByte{$client});	
	}

	my $len = length($$chunkRef) || 0;

	# We must send an even number of bytes.
	if (($len % 2) != 0) {

		$lastByte{$client} = substr($$chunkRef, -1, 1);
		$$chunkRef = substr($$chunkRef, 0, -1);
		$len--;
	} 

	my $pkt = {
		'wptr'     => $curWptr,
		'len'      => $len,
		'chunkref' => $chunkRef,
	};

	$curWptr{$client} = ($curWptr + $len/2) % $WPTR_LIMIT;
	
	sendPkt($client, $pkt);

	return 1;
}

# send a stream packet with no data. Used to update the stream control code
# and also to effect a poll of the client's buffer usage. 
sub sendEmptyChunk {
	my $client = shift;

	if ( main::DEBUGLOG && $log->is_debug ) {
		$log->debug($client->id, ' sendEmptyChunk');
	}
	
	Slim::Utils::Timers::killOneTimer($client, \&sendEmptyChunk);

	my $pkt = {
		'wptr'     => $curWptr{$client},
		'len'      => 0,
		'chunkref' => \$empty,
	};

	sendPkt($client, $pkt);
}

sub sendPkt {
	my ($client, $pkt) = @_;

	my $seq = $seq{$client};

	$pkt->{'seq'} = $seq;

	sendStreamPkt($client, $pkt);

	$seq{$client} = ($seq + 1) % $SEQ_LIMIT;
}

sub getMedianLatencyMicroSeconds {
	my $client      = $_[0];
	my $latencyList = $latencyList{$client};
	
	if ( @{$latencyList} > LATENCY_LIST_MINSIZE ) {
		return (sort {$a <=> $b} @{$latencyList})[ int(@{$latencyList} / 2) ];
	}
	else {
		return;
	}
}

1;