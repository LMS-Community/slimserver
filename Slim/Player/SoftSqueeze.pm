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

use strict;
use Slim::Player::Squeezebox2;
use Slim::Utils::Prefs;

use base qw(Slim::Player::Squeezebox2);

sub new {
        my $class = shift;

	my $client = $class->SUPER::new(@_);

	$client->prefSet('autobrightness', 0);

	return $client;
}

sub model {
	return 'softsqueeze';
}

# SoftSqueeze can't handle WMA
sub formats {
	my $client = shift;

	return qw(flc aif wav mp3);
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

sub maxTransitionDuration {
	return 0;
}

sub canDirectStream {
	my $client = shift;
	my $url = shift;

	my $handler = Slim::Player::Source::protocolHandlerForURL($url);

	if ($handler && $handler->can("canDirectStream") && !$handler->isa("Slim::Player::Protocols::MMS")) {
		return $handler->canDirectStream($url);
	}
	
	return undef;
}

1;

__END__
