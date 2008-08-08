package Slim::Web::Settings::Player::Audio;

# $Id: Basic.pm 10633 2006-11-09 04:26:27Z kdf $

# SqueezeCenter Copyright 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string);

my $prefs = preferences('server');

sub name {
	return Slim::Web::HTTP::protectName('AUDIO_SETTINGS');
}

sub page {
	return Slim::Web::HTTP::protectURI('settings/player/audio.html');
}

sub needsClient {
	return 1;
}

sub prefs {
	my ($class, $client) = @_;

#	my @prefs = qw(powerOnResume maxBitrate lameQuality);
	my @prefs = qw(powerOnResume lameQuality);

	if ($client->hasPowerControl()) {
		push @prefs,'powerOffDac';
	}
	
	if ($client->hasDisableDac()) {
		push @prefs,'disableDac';
	}

	if ($client->maxTransitionDuration()) {
		push @prefs,qw(transitionType transitionDuration transitionSmart);
	}
	
	if ($client->hasDigitalOut()) {
		push @prefs,qw(digitalVolumeControl mp3SilencePrelude);
	}

	if ($client->hasPreAmp()) {
		push @prefs,'preampVolumeControl';
	}
	
	if ($client->hasAesbeu()) {
		push @prefs,'digitalOutputEncoding';
	}

	if ($client->hasExternalClock()) {
		push @prefs,'clockSource';
	}

	if ($client->hasEffectsLoop()) {
		push @prefs,'fxloopSource';
	}

	if ($client->hasEffectsLoop()) {
		push @prefs,'fxloopClock';
	}

	if ($client->hasPolarityInversion()) {
		push @prefs,'polarityInversion';
	}
	
	if ($client->hasDigitalIn()) {
		push @prefs,'wordClockOutput';
	}
	
	if ($client->canDoReplayGain(0)) {
		push @prefs,'replayGainMode';
	}

	if ($client->isa('Slim::Player::Boom')) {
		push @prefs, 'analogOutMode', 'bass', 'treble', 'stereoxl';
	}
	
	if ( $client->isa('Slim::Player::Squeezebox2') ) {
		push @prefs, 'mp3StreamingMethod';
	}

	return ($prefs->client($client), @prefs);
}


sub handler {
	my ($class, $client, $paramRef) = @_;

	# If this is a settings update
	if ($paramRef->{'saveSettings'}) {
		# maxBitrate can't be handled by the generic handler
		$prefs->client($client)->set('maxBitrate', $paramRef->{maxBitrate}) if defined $paramRef->{maxBitrate};
	}

	# Load any option lists for dynamic options.
	$paramRef->{'lamefound'}  = Slim::Utils::Misc::findbin('lame');
	
	my @formats = $client->formats();

	if ($formats[0] ne 'mp3') {
		$paramRef->{'allowNoLimit'} = 1;
	}

	$paramRef->{'prefs'}->{maxBitrate} = Slim::Utils::Prefs::maxRate($client, 1);
	
	return $class->SUPER::handler($client, $paramRef);
}

1;

__END__
