package Slim::Hardware::i2c;

# $Id: i2c.pm,v 1.1 2003/07/18 19:42:14 dean Exp $

# SliMP3 Server Copyright (C) 2001 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;

use Slim::Utils::Misc;
use Slim::Utils::Timers;
use Time::HiRes qw(time);

my $CHUNKSIZE=512;

my %outstanding_data;
my %outstanding_seq;
my %txqueue;

#
# Queue up data for transmission
#
sub send {
	my ($client, $data) = @_;

	$::d_i2c && msg("i2c: enqueueing ".length($data)." bytes\n");

	$txqueue{$client}.=$data;

	# start transmission unless it's already in progress
	if ( (!defined($outstanding_data{$client})) || !length($outstanding_data{$client})) {
		$::d_i2c && msg("i2c: beginning transmission\n");
		sendnextchunk($client);
	} else {
		$::d_i2c && msg("i2c: already transmitting; ".
			"oustanding: ".length($outstanding_data{$client}).", ".
			"txqueue: ".length($txqueue{$client})."\n");
	}
}

sub sendnextchunk {
	my $client=shift;
	my $chunk;

	if (!length($txqueue{$client})) {
		$outstanding_data{$client}='';
		return;	# done transmitting

	} elsif (length($txqueue{$client}) <= $CHUNKSIZE) {
		$chunk = $txqueue{$client};
		$txqueue{$client}='';

	} else {
		$chunk = substr($txqueue{$client}, 0, $CHUNKSIZE);
		$txqueue{$client} = substr($txqueue{$client}, $CHUNKSIZE);
	}

	if (!defined($outstanding_seq{$client})) {
		$outstanding_seq{$client}=0;
	} else {
		$outstanding_seq{$client}++;
		if ($outstanding_seq{$client} == 256) {
			$outstanding_seq{$client}=0;
		}
	}

	$outstanding_data{$client}=$chunk;

	&retransmit($client);
}

sub gotAck {
	my ($client, $seq) = @_;

	$::d_i2c && msg("i2c: got ack $seq\n");

	if ($seq == $outstanding_seq{$client}) {
		# successful ack, send more
		Slim::Utils::Timers::killTimers($client, \&retransmit);
		sendnextchunk($client);
	} else {
		# wrong ack, ignore
		return;
	}
}

sub retransmit {
	my ($client) = @_;

	my $seqpacked = pack("C", $outstanding_seq{$client});
	my $chunk = $outstanding_data{$client};

	$::d_i2c && msg("i2c: transmitting seq ".$outstanding_seq{$client}.", ".
		length($chunk)." bytes\n");

	Slim::Networking::Protocol::sendClient($client, '2'.$seqpacked.'                '.
				$chunk);

	Slim::Utils::Timers::killTimers($client, \&retransmit);
	Slim::Utils::Timers::setTimer($client, time()+0.250, \&retransmit, ());	
}
1;

__END__
