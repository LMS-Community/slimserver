package Slim::Web::Settings::Server::SqueezeNetwork;

# $Id$

# SlimServer Copyright (c) 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Networking::SqueezeNetwork;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Misc;
use Slim::Utils::Prefs;

my $prefs = preferences('server');

sub name {
	return 'SQUEEZENETWORK_SETTINGS';
}

sub page {
	return 'settings/server/squeezenetwork.html';
}

sub prefs {
	my @prefs = qw(sn_email sn_password sn_sync);

	return ($prefs, @prefs);
}

sub handler {
	my ($class, $client, $params) = @_;

	if ( $params->{saveSettings} ) {

		if ( $params->{sn_password} ) {
			$params->{sn_password} = MIME::Base64::encode_base64( $params->{sn_password}, '' );
		}
		
		# XXX: Verify username/password
			
	}
	
	if (   $params->{sn_email}
		&& $params->{sn_password}
		&& defined $params->{sn_sync} 
		&& $params->{sn_sync} ne $prefs->get('sn_sync')
	) {
		# Shut down all SN activity
		Slim::Networking::SqueezeNetwork->shutdown();
		
		# Start it up again if the user enabled it
		if ( $params->{sn_sync} ) {
			Slim::Networking::SqueezeNetwork->init();
		}
	}

	return $class->SUPER::handler($client, $params);
}

1;

__END__
