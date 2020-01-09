package Slim::Hardware::BacklightLED;

# Logitech Media Server Copyright (c) 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

=head1 NAME

Slim::Hardware::BacklightLED

=head1 DESCRIPTION

L<Slim::Hardware::BacklightLED>

=cut

use strict;

use Slim::Utils::Log;
use Slim::Utils::Prefs;

my $log = logger('player.backlightled');

my $prefs = preferences('server');

=head2 setBacklightLED( $client, $led_bits)

Sets the 16 backlight LEDs

=cut

# ----------------------------------------------------------------------------
# LED_PRESET_1		0x8000
# LED_PRESET_2		0x4000
# LED_PRESET_3		0x2000
# LED_PRESET_4		0x1000
# LED_PRESET_5		0x0800
# LED_PRESET_6		0x0400
# LED_POWER		0x0200
# LED_BACK		0x0100
# LED_PLAY		0x0080
# LED_REW		0x0040
# LED_PAUSE		0x0020
# LED_FWD		0x0010
# LED_ADD		0x0008
# LED_VOLUME_DOWN	0x0004
# LED_VOLUME_UP		0x0002
# LED_RIGHT		0x0001
# LED_ALL		0xffff

sub setBacklightLED {

	my $client = shift;
	my $led_bits = shift || 0xFFFF;	#all on

	my $cmd = pack( 'n', $led_bits);
	$client->sendFrame( 'bled', \$cmd);
}

1;
