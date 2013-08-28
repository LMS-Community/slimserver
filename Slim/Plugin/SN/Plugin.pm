package Slim::Plugin::SN::Plugin;

# $Id$

# Logitech Media Server Copyright 2001-2011 Logitech
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use Scalar::Util 'blessed';

use Slim::Utils::Prefs;
use Slim::Player::ProtocolHandlers;
use Slim::Plugin::SN::ProtocolHandler;
use Slim::Utils::Log;


my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.sn',
	'defaultLevel' => 'ERROR',
	'description'  => 'PLUGIN_SN',
});

my @defaultServices = (qw(
	classical
	deezer
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

	my $prefs = preferences('server');
	my $services = \@defaultServices;
	
	if ( my $announcedServices = $prefs->get('sn_protocolhandlers') ) {
		$services =	$announcedServices if (ref $announcedServices eq 'ARRAY' && scalar @$announcedServices);
	}
	
	_registerHandlers($class, $services);
	
	$prefs->setChange( sub {
		my $services = $_[1];
		main::INFOLOG && $log->is_info && $log->info("Got services update: ", join(', ', @$services));
		if (ref $services eq 'ARRAY' && scalar @$services) {
			
			# Clean out previous handlers
			foreach (Slim::Player::ProtocolHandlers->registeredHandlers) {
				if (Slim::Player::ProtocolHandlers->handlerForProtocol($_) eq 'Slim::Plugin::SN::ProtocolHandler') {
					Slim::Player::ProtocolHandlers->registerHandler($_ => 0);
				}
			}
			
			# register updated set
			_registerHandlers($class, $services);
		}
	}, 'sn_protocolhandlers' );
	
	return 1;
}

sub _registerHandlers {
	my ($class, $services) = @_;
	
	foreach (@$services) {
		if (!Slim::Player::ProtocolHandlers->isValidHandler($_)) {
			Slim::Player::ProtocolHandlers->registerHandler(
				$_ => 'Slim::Plugin::SN::ProtocolHandler'
			);
		}
	}
	
	my $join  = join('|', @$services);
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
