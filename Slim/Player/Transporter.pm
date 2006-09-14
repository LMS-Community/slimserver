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
	'audioSource' => 0,
	'digitalOutputEncoding' => 0,
	'wordClockOutput' => 0,
	'powerOffDac' => 0,
	'polarityInversion' => 0,
	'menuItem'             => [qw(
		NOW_PLAYING
		BROWSE_MUSIC
		SEARCH
		RandomPlay::Plugin
		FAVORITES
		SAVED_PLAYLISTS
		RADIO
		DigitalInput::Plugin
		SETTINGS
		PLUGINS
	)],
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

	$client->getPlayerSetting('digitalOutputEncoding');
	$client->getPlayerSetting('wordClockOutput');
	$client->getPlayerSetting('powerOffDac');

	$client->updateClockSource();

	# Update the knob in reconnect - as that's the last function that is
	# called when a new or pre-existing client connects to the server.
	$client->updateKnob(1);
}

sub play {
	my ($client, $params) = @_;

	# If the url to play is a source: value, that means the Digital Inputs
	# are being used. The DigitalInput plugin handles setting the audp
	# value for those. If the user then goes and pressed play on a
	# standard file:// or http:// URL, we need to set the value back to 0,
	# IE: input from the network.
	if ($params->{'url'}) {

		if ($params->{'url'} =~ /^source:/) {

			$::d_source && msg("Transporter::play - Got source: url [$params->{'url'}]\n");

			if ($INC{'Plugins/DigitalInput/Plugin.pm'}) {

				my $value = Plugins::DigitalInput::Plugin::valueForSourceName($params->{'url'});

				$::d_source && msg("Transporter::play - Setting DigitalInput to $value\n");

				$client->prefSet('digitalInput', $value);
				$client->sendFrame('audp', \pack('C', $value));
				Slim::Player::Source::trackStartEvent($client);
			}

			return 1;

		} else {

			$::d_source && msg("Transporter::play - setting DigitalInput to 0 for [$params->{'url'}]\n");

			$client->prefSet('digitalInput', 0);
			$client->sendFrame('audp', \pack('C', 0));
		}
	}

	return $client->SUPER::play($params);
}

sub updateClockSource {
	my $client = shift;

	my $data = pack('C', $client->prefGet("clockSource"));
	$client->sendFrame('audc', \$data);	
}

sub updateDigitalOutputEncoding {
}

sub updateWordClockOutput {
}

sub updatePowerOffDac {
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
	my $width    = $client->param('knobWidth') || 0;
	my $height   = $client->param('knobHeight') || 0;
	my $backForce = $client->param('knobBackgroundForce') || 0;

	if (defined $listIndex && (($listIndex == $knobPos) || $forceSend)) {

		my $parambytes;

		if (defined $listLen) {
			$client->knobSync( (++$knobSync) & 0xFF);

			$parambytes = pack "NNCcncc", $listIndex, $listLen, $knobSync, $flags, $width, $height, $backForce;

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

sub knobListPos {
	my $client = shift;
	my $curPos = shift || $client->param('listIndex');
	my $listLen = shift || $client->param('listLen') || scalar @{ $client->param('listRef') };

	my $newPos = $client->knobPos();

	my ($direction, $wrap);

	if ($listLen == 1) {

		# knob return negative value anti-clockwise and +1 for clockwise
		$direction = $newPos > 0 ? 'up' : 'down';
		$newPos = $curPos;

	} elsif ($listLen == 2) {

		# knob returns pos + 2 for list of 2 items when moving anti-clockwise
		if ($newPos > 1) {
			$newPos = $newPos - 2;
			$direction = 'up';
		} else {
			$direction = 'down';
		}

	} else {

		# assume movement of more than 1/2 of list means wrapping round
		my $wrap = (abs($newPos - $curPos) > $listLen / 2); 
		
		if ($newPos > $curPos && !$wrap || $newPos < $curPos && $wrap) {
			$direction = 'down';
		} else {
			$direction = 'up';
		}
		
	}

	return ($newPos, $newPos - $curPos, $direction, $wrap);
}

sub model {
	return 'transporter';
}

sub hasVolumeControl {
	my $client = shift;
	
	return ( !Slim::Music::Info::isDigitalInput(Slim::Player::Playlist::song($client)) );

}

sub hasDigitalIn {
	return 1;
}

sub hasExternalClock {
	return 1;
}

sub hasAesbeu() {
    	return 1;
}

sub hasPowerControl() {
	return 1;
}

sub hasPolarityInversion() {
	return 1;
}

sub hasPreAmp {
        return 0;
}

sub voltage {
	return Slim::Networking::Slimproto::voltage(@_);
}

sub volumeString {
	my ($client, $volume) = @_;

	if ($client->display->isa('Slim::Display::Transporter')) {

		if ($volume <= 0) {

			return sprintf(' (%s)', $client->string('MUTED'));
		}

		return sprintf(' (%.2f dB)', -abs(($volume / 2) - 50));

	} else {

		return $client->SUPER::volumeString($volume);

	}

}

1;

__END__
