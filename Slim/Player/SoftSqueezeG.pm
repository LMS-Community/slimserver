package Slim::Player::SoftSqueezeG;

# $Id: SoftSqueezeG.pm,v 1.2 2004/12/02 02:36:29 dsully Exp $
#
# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

use strict;
use Slim::Player::SqueezeboxG;
use Slim::Utils::Prefs;

use base qw(Slim::Player::SqueezeboxG);

sub new {
        my $class  = shift;

	my $client = $class->SUPER::new(@_);

	# XXX - Seems like this should be a method on $client
	Slim::Utils::Prefs::clientSet($client, 'autobrightness', 0);

        return $client;
}

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
