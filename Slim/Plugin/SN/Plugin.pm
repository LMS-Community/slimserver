package Slim::Plugin::SN::Plugin;

# $Id$

# Squeezebox Server Copyright 2001-2009 Logitech
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use Scalar::Util 'blessed';

use Slim::Player::ProtocolHandlers;
use Slim::Plugin::SN::ProtocolHandler;
use Slim::Utils::Log;


my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.sn',
	'defaultLevel' => 'ERROR',
});

my @defaultServices = (qw(
	classical
	deezer
	mediafly
	napster
	pandora
	rhapd
	slacker
));

my $match;

sub shutdownPlugin {

	# disable protocol handler?
}

# We use postinitPlugin so that all the other handlers will have had a chance to register first
sub postinitPlugin {
	my $class = shift;

	# XXX get up-to-date list of services from SN
	my @services = @defaultServices;
	
	foreach (@services) {
		if (!Slim::Player::ProtocolHandlers->isValidHandler($_)) {
			Slim::Player::ProtocolHandlers->registerHandler(
				$_ => 'Slim::Plugin::SN::ProtocolHandler'
			);
		}
	}
	
	my $join  = join('|', @services);
	$match = qr/^$join:/;

	return 1;
}

# The idea here is to filter out tracks that cannot be handled by SN
# It might also be possible to mutate the URL into a SbS-relative one, once
# SN supports that and we have a means of SN initiating a switch back to SbS.

sub filterTrack {
	my $url = shift;
	
	$url = $url->url if (blessed $url);
	
	return $url if $url =~ $match;
}

1;

__END__
