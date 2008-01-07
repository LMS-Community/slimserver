package Slim::Web::Settings::Player::Display;

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

$prefs->setValidate('num', qw(scrollRate scrollRateDouble scrollPause scrollPauseDouble));
$prefs->setValidate({ 'validator' => 'intlimit', 'low' => 1, 'high' => 20 }, qw(scrollPixels scrollPixelsDouble));

sub name {
	return Slim::Web::HTTP::protectName('DISPLAY_SETTINGS');
}

sub page {
	return Slim::Web::HTTP::protectURI('settings/player/display.html');
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

	my @prefs = qw(powerOnBrightness powerOffBrightness idleBrightness autobrightness
				   scrollMode scrollPause scrollPauseDouble scrollRate scrollRateDouble
				  );

	if ($client->display->isa("Slim::Display::Graphics")) {

		push @prefs, qw(activeFont_curr idleFont_curr scrollPixels scrollPixelsDouble);

	} else {

		push @prefs, qw(doublesize offDisplaySize largeTextFont);
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

					while (defined $paramRef->{$pref.$i}) {

						if ($paramRef->{$pref.$i} ne "-1") {push @array, $paramRef->{$pref.$i};}

						$i++;
					}

					$prefs->client($client)->set($pref, \@array);
				}
			}

			$paramRef->{'prefs'}->{'activeFont'} = [ @{ $prefs->client($client)->get('activeFont') }, "-1" ];
			$paramRef->{'prefs'}->{'idleFont'}   = [ @{ $prefs->client($client)->get('idleFont') }, "-1" ];
		}

		# Load any option lists for dynamic options.
		$paramRef->{'brightnessOptions' } = getBrightnessOptions($client);
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
		$client->display->brightness($paramRef->{'prefs'}->{ $client->power ? 'powerOnBrightness' : 'powerOffBrightness' });
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

		if ($height && $height == Slim::Display::Lib::Fonts::fontheight("$font.2") &&
			Slim::Display::Lib::Fonts::fontchars("$font.2") > 255 ) {

			$fonts->{$font} = Slim::Utils::Strings::getString($font);
		}
	}

	return $fonts;
}

sub getBrightnessOptions {
	my $client = shift;

	my %brightnesses = (
		0 => '0 ('.string('BRIGHTNESS_DARK').')',
		1 => '1',
		2 => '2',
		3 => '3',
		4 => '4 ('.string('BRIGHTNESS_BRIGHTEST').')',
	);

	if (!defined $client) {

		return \%brightnesses;
	}

	if (defined $client->maxBrightness) {

		$brightnesses{4} = 4;

		$brightnesses{$client->maxBrightness} = sprintf('%s (%s)',
			$client->maxBrightness, string('BRIGHTNESS_BRIGHTEST')
		);
	}

	return \%brightnesses;
}

1;

__END__
