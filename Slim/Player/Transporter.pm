package Slim::Player::Transporter;

# $Id$

# SlimServer Copyright (c) 2001-2005 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#

use strict;
use base qw(Slim::Player::Squeezebox2);

use File::Spec::Functions qw(:ALL);
use FindBin qw($Bin);
use IO::Socket;
use MIME::Base64;

use Slim::Player::Player;
use Slim::Utils::Misc;
use Slim::Utils::Unicode;


our $defaultPrefs = {
	'clockSource'  => 0,
	'digitalInput' => 0,
};

sub init {
	my $client = shift;

	# make sure any preferences unique to this client may not have set are set to the default
	Slim::Utils::Prefs::initClientPrefs($client, $defaultPrefs);

	$client->SUPER::init();
}

sub reconnect {
	my $client = shift;
	$client->SUPER::reconnect(@_);

	$client->updateClockSource();

	# Update the knob in reconnect - as that's the last function that is
	# called when a new or pre-existing client connects to the server.
	$client->updateKnob(1);
}

sub updateClockSource {
	my $client = shift;

	my $data = pack('C', $client->prefGet("clockSource"));
	$client->sendFrame('audc', \$data);	
}

sub updateKnob {
	my $client    = shift;
	my $forceSend = shift || 0;

	my $listIndex = $client->param('listIndex');
	my $listLen   = $client->param('listLen');

	if (!$listLen) {

		my $listRef = $client->param('listRef');

		if (ref($listRef) eq 'ARRAY') {
			$listLen = scalar(@$listRef);
		}			
	}

	my $knobPos  = $client->knobPos || 0;
	my $knobSync = $client->knobSync;
	my $flags    = $client->param('knobFlags') || 0;

	if (defined $listIndex && (($listIndex == $knobPos) || $forceSend)) {

		my $parambytes;

		if (defined $listLen) {
		    	my $width  = 0;
		    	my $height = 0;

			$client->knobSync( (++$knobSync) & 0xFF);

			$parambytes = pack "NNCcnc", $listIndex, $listLen, $knobSync, $flags, $width, $height;

			$::d_ui && msgf("sending new knob position- listIndex: %d with knobPos: %d of %d sync: %d flags: %d\n",
				$listIndex, $knobPos, $listLen, $knobSync, $flags,
			);

		} else {

			$parambytes = pack "N", $listIndex;

			$::d_ui && msg("sending new knob position- listIndex: $listIndex\n");
		}

		$client->sendFrame('knob', \$parambytes);

	} else {

		$::d_ui && msg("skipping sending redundant knob position\n");
	}
}

sub model {
	return 'transporter';
}

sub hasExternalClock {
	return 1;
}

sub hasPreAmp {
        return 0;
}

1;

__END__
