package Slim::Hardware::i2c;

# $Id: i2c.pm,v 1.3 2003/07/28 22:28:17 sadams Exp $

# Slim Server Copyright (c) 2001, 2002, 2003 Sean Adams, Slim Devices Inc.
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

	$::d_i2c && msg("i2c: sending ".length($data)." bytes\n");

	if (!defined($outstanding_seq{$client})) {
		$outstanding_seq{$client}=0;
	} else {
		$outstanding_seq{$client}++;
		if ($outstanding_seq{$client} == 256) {
			$outstanding_seq{$client}=0;
		}
	}

	my $seqpacked = pack("C", $outstanding_seq{$client});
	Slim::Networking::Protocol::sendClient($client, '2'.$seqpacked.'                '.
				$data);

}

1;
