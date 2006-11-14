package Slim::Web::Settings::Player::Basic;

# $Id: Basic.pm 10633 2006-11-09 04:26:27Z kdf $

# SlimServer Copyright (c) 2001-2006 Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Log;

sub name {
	return 'BASIC_PLAYER_SETTINGS';
}

sub page {
	return 'settings/player/basic.html';
}

sub needsClient {
	return 1;
}

sub handler {
	my ($class, $client, $paramRef) = @_;

	my @prefs = qw(playername titleFormat titleFormatCurr);

	if ($client->isPlayer()) {
		push @prefs, qw(playingDisplayMode playingDisplayModes);
		
		if ($client->display->isa('Slim::Display::Transporter')) {
			push @prefs, qw(visualMode visualModes);
		}
		
		my $savers = Slim::Buttons::Common::hash_of_savers();
		if (scalar(keys %{$savers}) > 0) {
			push @prefs, qw(screensaver idlesaver offsaver screensavertimeout);
		}
	}
	
	# If this is a settings update
	if ($paramRef->{'submit'}) {

		my @changed;

		my $vismodeChange = 0;
		if (${$paramRef->{'visualModes'}}[$paramRef->{'visualMode'}] ne $client->prefGet('visualModes',$paramRef->{'visualMode'})) {
			$vismodeChange = 1;
		}

		for my $pref (@prefs) {

			if ($pref eq 'visualModes' || $pref eq 'playingDisplayModes' || $pref eq 'titleFormat') {

				$client->prefDelete($pref);

				my $i = 0;

				while (defined $paramRef->{$pref.$i}) {

					if ($paramRef->{$pref.$i} eq "-1") {
						last;
					}

					$client->prefPush($pref,$paramRef->{$pref.$i});

					$i++;
				}
			} else {
			
				if ($paramRef->{$pref} ne $client->prefGet($pref)) {
					push @changed, $pref;
				}
			
				$client->prefSet($pref, $paramRef->{$pref} ) if defined $paramRef->{$pref};
			}
		}
		
		if ($vismodeChange) {
			Slim::Buttons::Common::updateScreen2Mode;
		}
		
		$class->_handleChanges($client, \@changed, $paramRef);

	}

	$paramRef->{'titleFormatOptions'}    = { Slim::Web::Setup::hash_of_prefs('titleFormat') };
	$paramRef->{'playingDisplayOptions'} = { %{Slim::Web::Setup::getPlayingDisplayModes($client)} };
	$paramRef->{'visualModeOptions'}     = { %{Slim::Web::Setup::getVisualModes($client)} };
	$paramRef->{'screensavers'}          = Slim::Buttons::Common::hash_of_savers();

	for my $pref (@prefs) {

		if ($pref eq 'visualModes' || $pref eq 'playingDisplayModes' || $pref eq 'titleFormat') {

			$paramRef->{'prefs'}->{$pref} = [$client->prefGetArray($pref)];

			push @{$paramRef->{'prefs'}->{$pref}},"-1";

		} else {

			$paramRef->{'prefs'}->{$pref} = $client->prefGet($pref);
		}
	}

	if (defined($client->revision)) {
		$paramRef->{'versionInfo'} = Slim::Utils::Strings::string("PLAYER_VERSION") . Slim::Utils::Strings::string("COLON") . $client->revision;
	}
	
	$paramRef->{'ipaddress'}      = $client->ipport();
	$paramRef->{'macaddress'}     = $client->macaddress;
	$paramRef->{'signalstrength'} = $client->signalStrength;
	$paramRef->{'voltage'}        = $client->voltage();

	
	return $class->SUPER::handler($client, $paramRef);
}

1;

__END__
