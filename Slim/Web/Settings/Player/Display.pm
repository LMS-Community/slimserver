package Slim::Web::Settings::Player::Display;

# Logitech Media Server Copyright 2001-2020 Logitech.
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
	return Slim::Web::HTTP::CSRF->protectName('DISPLAY_SETTINGS');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('settings/player/display.html');
}

sub needsClient {
	return 1;
}

sub validFor {
	my $class = shift;
	my $client = shift;
	
	return !$client->display->isa('Slim::Display::NoDisplay');
}

sub prefs {
	my $class  = shift;
	my $client = shift;

	if (!$client || !$client->isPlayer) {
		return ();
	}

	my @prefs = qw(powerOnBrightness powerOffBrightness idleBrightness 
				scrollMode scrollPause scrollPauseDouble scrollRate scrollRateDouble alwaysShowCount
				);

	if ($client->display->isa("Slim::Display::Graphics")) {

		push @prefs, qw(activeFont_curr idleFont_curr scrollPixels scrollPixelsDouble);

	} else {

		push @prefs, qw(doublesize offDisplaySize largeTextFont);
	}

	if ($client->isa('Slim::Player::Boom')) {
		push @prefs, 'minAutoBrightness';
		push @prefs, 'sensAutoBrightness';
	}

	return ($prefs->client($client), @prefs);
}

sub handler {
	my ($class, $client, $paramRef) = @_;

	if ($client && $client->isPlayer) {

		if ($client->display->isa('Slim::Display::Graphics')) {

			if ($paramRef->{'saveSettings'}) {

				# activeFont and idleFont handled here, all other prefs by SUPER::handler
				for my $pref (qw(activeFont idleFont)) {

					my @array;
					my $i = 0;

					while (defined $paramRef->{'pref_'.$pref.$i}) {

						if ($paramRef->{'pref_'.$pref.$i} ne "-1") {push @array, $paramRef->{'pref_'.$pref.$i};}

						$i++;
					}

					$prefs->client($client)->set($pref, \@array);
				}
			}

			$paramRef->{'prefs'}->{'pref_activeFont'} = [ @{ $prefs->client($client)->get('activeFont') }, "-1" ];
			$paramRef->{'prefs'}->{'pref_idleFont'}   = [ @{ $prefs->client($client)->get('idleFont') }, "-1" ];
		}

		# Load any option lists for dynamic options.
		$paramRef->{'brightnessOptions' } = $client->display->getBrightnessOptions();
		$paramRef->{'maxBrightness' }     = $client->maxBrightness;
		$paramRef->{'fontOptions'}        = getFontOptions($client);

	} else {

		# non-SD player, so no applicable display settings
		$paramRef->{'warning'} = Slim::Utils::Strings::string('SETUP_NO_PREFS');
	}

	my $page = $class->SUPER::handler($client, $paramRef);

	# update the player display after changing any settings
	if ($paramRef->{'saveSettings'}) {
		$client->display->resetDisplay;
		$client->display->update;
	}

	return $page;
}

sub getFontOptions {
	my $client = shift;

	if (!$client || !exists &Slim::Display::Lib::Fonts::fontnames) {

		return {};
	}

	my $height = $client->displayHeight;
	my $fonts  = {
		'-1' => '',
	};

	for my $font (@{Slim::Display::Lib::Fonts::fontnames()}) {

		my $fontHeight = Slim::Display::Lib::Fonts::fontheight("$font.2");
		my $fontChars  = Slim::Display::Lib::Fonts::fontchars("$font.2");

		if ($height && $fontHeight && $height == $fontHeight &&
			$fontChars && $fontChars > 255 ) {

			$fonts->{$font} = Slim::Utils::Strings::getString($font);
		}
	}

	return $fonts;
}

1;

__END__
