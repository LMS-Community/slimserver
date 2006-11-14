package Slim::Web::Settings::Player::Audio;

# $Id: Basic.pm 10633 2006-11-09 04:26:27Z kdf $

# SlimServer Copyright (c) 2001-2006 Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Log;

sub name {
	return 'AUDIO_SETTINGS';
}

sub page {
	return 'settings/player/audio.html';
}

sub needsClient {
	return 1;
}

sub handler {
	my ($class, $client, $paramRef) = @_;

	my @prefs = qw(powerOnresume lame maxBitrate lameQuality);

	if (Slim::Player::Sync::isSynced($client) || (scalar(Slim::Player::Sync::canSyncWith($client)) > 0))  {
		push @prefs,qw(synchronize syncVolume syncPower);
	} 
	
	if ($client->hasPowerControl()) {
		push @prefs,'powerOffDac';
	}
	
	if ($client->hasDisableDac()) {
		push @prefs,'disableDac';
	}

	if ($client->maxTransitionDuration()) {
		push @prefs,qw(transitionType transitionDuration);
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

	if ($client->hasPolarityInversion()) {
		push @prefs,'polarityInversion';
	}
	
	if ($client->hasDigitalIn()) {
		push @prefs,'wordClockOutput';
	}

	
	if ($client->canDoReplayGain(0)) {
		push @prefs,'replayGainMode';
	}
	
	# If this is a settings update
	if ($paramRef->{'submit'}) {

		my @changed = ();
		for my $pref (@prefs) {

			# parse indexed array prefs.
			if ($paramRef->{$pref} ne $client->prefGet($pref)) {
				push @changed, $pref;
			}
			
			$client->prefSet($pref, $paramRef->{$pref} ) if defined $paramRef->{$pref};
		}
		
		$class->_handleChanges($client, \@changed, $paramRef);
	}

	# Load any option lists for dynamic options.
	$paramRef->{'syncGroups'}    = { %{Slim::Web::Setup::syncGroups($client)} };
	$paramRef->{'lamefound'}     = Slim::Utils::Misc::findbin('lame');
	
	my @formats = $client->formats();
	if ($formats[0] ne 'mp3') { $paramRef->{'allowNoLimit'} = 1; }

	# Set current values for prefs
	# load into prefs hash so that web template can detect exists/!exists
	for my $pref (@prefs) {

		if ($pref eq 'synchronize') {

			$paramRef->{'prefs'}->{$pref} =  -1;
			if (Slim::Player::Sync::isSynced($client)) {
				$paramRef->{'prefs'}->{$pref} = $client->id();
			} elsif ( my $syncgroupid = $client->prefGet('syncgroupid') ) {

				# Bug 3284, we want to show powered off players that will resync when turned on
				my @players = Slim::Player::Client::clients();

				foreach my $other (@players) {
					next if $other eq $client;

					my $othersyncgroupid = Slim::Utils::Prefs::clientGet($other,'syncgroupid');

					if ( $syncgroupid == $othersyncgroupid ) {
						$paramRef->{'prefs'}->{$pref} = $other->id;
					}
				}
			}

		} elsif ($pref eq 'maxBitrate') {
			
			$paramRef->{'prefs'}->{$pref} = Slim::Utils::Prefs::maxRate($client, 1);
			
		} elsif ($pref eq 'powerOnResume') {
			
			$paramRef->{'prefs'}->{$pref} = Slim::Player::Sync::syncGroupPref($client,'powerOnResume') ||
								$client->prefGet('powerOnResume');	
		} else {

			$paramRef->{'prefs'}->{$pref} = $client->prefGet($pref);
		}
	}
	
	return $class->SUPER::handler($client, $paramRef);
}

1;

__END__
