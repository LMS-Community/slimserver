package Slim::Player::Transporter;

# $Id$

# SqueezeCenter Copyright (c) 2001-2007 Logitech.
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
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Unicode;
use Slim::Utils::Prefs;

my $prefs = preferences('server');

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
		PLUGIN_RANDOMPLAY
		FAVORITES
		SAVED_PLAYLISTS
		RADIO
		MUSIC_ON_DEMAND
		PLUGIN_DIGITAL_INPUT
		SETTINGS
		PLUGINS
	)],
};

sub init {
	my $client = shift;

	# make sure any preferences unique to this client may not have set are set to the default
	$prefs->client($client)->init($defaultPrefs);

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
	my $url = $params->{'url'};

	if ($url) {

		if (Slim::Music::Info::isDigitalInput($url)) {

			$client->setDigitalInput($url);
			$client->directURL($url);
			Slim::Player::Source::trackStartEvent($client);

			return 1;

		} else {

			logger('player.source')->info("Setting DigitalInput to 0 for [$url]");

			$client->setDigitalInput(0);
		}
	}

	return $client->SUPER::play($params);
}


sub pause {
	my $client = shift;

	$client->SUPER::pause(@_);

	if (Slim::Music::Info::isDigitalInput(Slim::Player::Playlist::url($client))) {

		$client->setDigitalInput(0);	
	}
}

sub stop {
	my $client = shift;

	$client->SUPER::stop(@_);

	if (Slim::Music::Info::isDigitalInput(Slim::Player::Playlist::url($client))) {

		$client->setDigitalInput(0);	
	}
}

sub resume {
	my $client = shift;

	$client->SUPER::resume(@_);

	if (Slim::Music::Info::isDigitalInput(Slim::Player::Playlist::url($client))) {

		$client->setDigitalInput(Slim::Player::Playlist::url($client));	
	}
}

sub power {
	my ($client, $on) = @_;

	# can't use the result below because power is sometimes called recursively through other display functions
	my $was = $prefs->client($client)->get('power');

	my $result = $client->SUPER::power($on);

	# if we're turning on and the current song is a digital input, then start playing.
	if (defined($on) && $on && !$was) {

		if (Slim::Music::Info::isDigitalInput(Slim::Player::Playlist::url($client))) {

			$client->execute(["play"]);
		}
	}

	return $result;	
}

sub setDigitalInput {
	my $client = shift;
	my $input  = shift;

	my $log    = logger('player.source');

	# convert a source: url to a number, otherwise, just use the number
	if (Slim::Music::Info::isDigitalInput($input)) {
	
		$log->info("Got source: url: [$input]");

		if ($INC{'Slim/Plugin/DigitalInput/Plugin.pm'}) {

			$input = Slim::Plugin::DigitalInput::Plugin::valueForSourceName($input);
		}
	}

	$log->info("Switching to digital input $input");

	$prefs->client($client)->set('digitalInput', $input);
	$client->sendFrame('audp', \pack('C', $input));
}

sub updateClockSource {
	my $client = shift;

	my $data = pack('C', $prefs->client($client)->get('clockSource'));
	$client->sendFrame('audc', \$data);
}

sub updateKnob {
	my $client  = shift;
	my $newList = shift || 0;

	my $listIndex = $client->modeParam('listIndex');
	my $listLen   = $client->modeParam('listLen');

	if (!$listLen) {

		my $listRef = $client->modeParam('listRef');

		if (ref($listRef) eq 'ARRAY') {
			$listLen = scalar(@$listRef);
		}			
	}

	my $knobPos   = $client->knobPos || 0;
	my $knobSync  = $client->knobSync;
	my $flags     = $client->modeParam('knobFlags') || 0;
	my $width     = $client->modeParam('knobWidth') || 0;
	my $height    = $client->modeParam('knobHeight') || 0;
	my $backForce = $client->modeParam('knobBackgroundForce') || 0;

	my $log       = logger('player.ui');

	if (defined $listIndex && (($listIndex != $knobPos) || $newList)) {

		my $parambytes;

		if ($newList) {

			$client->knobSync( (++$knobSync) & 0xFF);

			$parambytes = pack "NNCcncc", $listIndex, $listLen, $knobSync, $flags, $width, $height, $backForce;

			if ( $log->is_debug ) {
				$log->debug(sprintf("Sending new knob position- listIndex: %d with knobPos: %d of %d sync: %d flags: %d",
					$listIndex, $knobPos, $listLen, $knobSync, $flags,
				));
			}

		} else {

			$parambytes = pack "N", $listIndex;

			$log->debug("Sending new knob position- listIndex: $listIndex");
		}

		$client->sendFrame('knob', \$parambytes);

		$client->knobPos($listIndex);

	} else {

		$log->debug("Skipping sending redundant knob position");
	}
}

sub knobListPos {
	my $client  = shift;
	my $curPos  = shift || $client->modeParam('listIndex');
	my $listLen = shift || $client->modeParam('listLen') || scalar @{ $client->modeParam('listRef') };

	my $newPos = $client->knobPos();

	my ($direction, $wrap);

	if ($listLen == 1) {

		# knob return negative value anti-clockwise and +1 for clockwise
		# set direction only if a bump is required otherwise leave as undef
		if ($newPos > 0) {
			$direction = 'up';
		} elsif ($newPos < 0) {
			$direction = 'down';
		}

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
sub modelName { 'Transporter' }

sub hasDigitalIn {
	return 1;
}

sub hasExternalClock {
	return 1;
}

sub hasAesbeu {
    	return 1;
}

sub hasPowerControl {
	return 1;
}

sub hasDisableDac {
	return 0;
}

sub hasPolarityInversion {
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
