package Slim::Player::SoftSqueeze;

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
use File::Spec::Functions qw(:ALL);
use FindBin qw($Bin);
use IO::Socket;
use Slim::Player::Player;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw (string);
use MIME::Base64;

@ISA = ("Slim::Player::Squeezebox");


sub model {
	return 'softsqueeze';
}

sub signalStrength {
	return undef;
}

sub hasDigitalOut {
	return 0;
}

sub needsUpgrade {
	return 0;
}


1;
