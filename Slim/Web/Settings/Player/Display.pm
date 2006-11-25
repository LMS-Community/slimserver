package Slim::Web::Settings::Player::Display;

# $Id: Basic.pm 10633 2006-11-09 04:26:27Z kdf $

# SlimServer Copyright (c) 2001-2006 Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Log;
use Slim::Utils::Strings qw(string);

sub name {
	return 'DISPLAY_SETTINGS';
}

sub page {
	return 'settings/player/display.html';
}

sub needsClient {
	return 1;
}

sub handler {
	my ($class, $client, $paramRef) = @_;

	my @prefs = ();

	# set up prefs array for all conditions.
	if ($client->isPlayer()) {

		push @prefs, qw(powerOnBrightness powerOffBrightness idleBrightness autobrightness);
		
		if ($client->display->isa("Slim::Display::Graphics")) {

			push @prefs, qw(
				activeFont activeFont_curr
				idleFont idleFont_curr
				scrollMode
				scrollPause scrollPauseDouble
				scrollRate scrollRateDouble
				scrollPixels scrollPixelsDouble
			);

		} else {

			push @prefs, qw(
				doublesize offDisplaySize
				largeTextFont
				scrollMode
				scrollPause scrollPauseDouble
				scrollRate scrollRateDouble
			);
		}

		# If this is a settings update
		if ($paramRef->{'submit'}) {
	
			for my $pref (@prefs) {
	
				# parse indexed array prefs.
				if ($pref eq 'activeFont' || $pref eq 'idleFont') {
	
					$client->prefDelete($pref);
	
					my $i = 0;
	
					while (defined $paramRef->{$pref.$i}) {
	
						if ($paramRef->{$pref.$i} eq "-1") {
							last;
						}
	
						$client->prefPush($pref,$paramRef->{$pref.$i});
	
						$i++;
					}

				} elsif (defined $paramRef->{$pref}) {

					$client->prefSet($pref, $paramRef->{$pref});
				}
				
				if ($pref eq 'doublesize') {
					$client->textSize($paramRef->{'doublesize'});
				}
			}
		}
	
		# Load any option lists for dynamic options.
		$paramRef->{'brightnessOptions' } = getBrightnessOptions($client);
		$paramRef->{'maxBrightness' }     = $client->maxBrightness;
		$paramRef->{'fontOptions'}        = getFontOptions($client);

		# Set current values for prefs
		# load into prefs hash so that web template can detect exists/!exists
		for my $pref (@prefs) {
	
			if ($pref eq 'activeFont' || $pref eq 'idleFont') {
	
				$paramRef->{'prefs'}->{$pref} = [$client->prefGetArray($pref)];
	
				push @{$paramRef->{'prefs'}->{$pref}},"-1";
	
			} elsif ($pref eq 'doubleSize') {
				
				$paramRef->{'prefs'}->{$pref} = $client->textSize;
				
			} else {
	
				$paramRef->{'prefs'}->{$pref} = $client->prefGet($pref);
			}
		}

	} else {

		# non-SD player, so no applicable display settings
		$paramRef->{'warning'} = Slim::Utils::Strings::string('SETUP_NO_PREFS');
	}

	return $class->SUPER::handler($client, $paramRef);
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

		if ($height == Slim::Display::Lib::Fonts::fontheight("$font.2") && 
			Slim::Display::Lib::Fonts::fontchars("$font.2") > 255 ) {

			$fonts->{$font} = $font;
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
