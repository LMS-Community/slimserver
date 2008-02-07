package Slim::Web::Settings::Server::SqueezeNetwork;

# $Id$

# SqueezeCenter Copyright 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Digest::SHA1 qw(sha1_base64);

use Slim::Networking::SqueezeNetwork;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Misc;
use Slim::Utils::Prefs;

my $prefs = preferences('server');

sub name {
	return Slim::Web::HTTP::protectName('SQUEEZENETWORK_SETTINGS');
}

sub page {
	return Slim::Web::HTTP::protectURI('settings/server/squeezenetwork.html');
}

sub prefs {
	# NOTE: if you add a pref here, check that the wizard also submits it
	# in HTML/EN/html/wizard.js
	my @prefs = qw(sn_email sn_password_sha sn_sync sn_disable_stats);

	return ($prefs, @prefs);
}

sub handler {
	my ($class, $client, $params, $callback, @args) = @_;

	my $sn_server = Slim::Networking::SqueezeNetwork->get_server("sn");

	if ( $params->{saveSettings} ) {
		
		if ( defined $params->{sn_disable_stats} ) {
			Slim::Utils::Timers::setTimer(
				$params->{sn_disable_stats},
				time() + 30,
				\&reportStatsDisabled,
			);
		}

		if ( $params->{sn_email} && $params->{sn_password_sha} ) {
			
			if ( length( $params->{sn_password_sha} ) != 27 ) {
				$params->{sn_password_sha} = sha1_base64( $params->{sn_password_sha} );
			}
		
			# Verify username/password
			Slim::Networking::SqueezeNetwork->login(
				username => $params->{sn_email},
				password => $params->{sn_password_sha},
				client   => $client,
				cb       => sub {
					my $body = $class->saveSettings( $client, $params );

					if ($params->{'AJAX'}) {
						$params->{'warning'} = Slim::Utils::Strings::string('SETUP_SN_VALID_LOGIN');
						$params->{'validated'}->{'valid'} = 1;
					}
					$callback->( $client, $params, $body, @args );
				},
				ecb      => sub {
					if ($params->{'AJAX'}) {
						$params->{'warning'} = Slim::Utils::Strings::string('SETUP_SN_INVALID_LOGIN', $sn_server); 
						$params->{'validated'}->{'valid'} = 0;
					}
					else {
						$params->{warning} .= Slim::Utils::Strings::string('SETUP_SN_INVALID_LOGIN', $sn_server) . '<br/>';						
					}
					
					delete $params->{sn_email};
					delete $params->{sn_password_sha};
					
					my $body = $class->saveSettings( $client, $params );
					$callback->( $client, $params, $body, @args );
				},
			);
		
			return;
		}
		else {
			if ($params->{'AJAX'}) {
				$params->{'warning'} = Slim::Utils::Strings::string('SETUP_SN_INVALID_LOGIN', $sn_server); 
				$params->{'validated'}->{'valid'} = 0;
			}
			else {
				$params->{warning} .= Slim::Utils::Strings::string('SETUP_SN_INVALID_LOGIN', $sn_server) . '<br/>';						
			}
			delete $params->{'saveSettings'};
		}
	}

	return $class->SUPER::handler($client, $params);
}

sub saveSettings {
	my ( $class, $client, $params ) = @_;
	
	if (   $params->{sn_email}
		&& $params->{sn_password_sha}
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

sub reportStatsDisabled {
	my $isDisabled = shift;
	
	my $http = Slim::Networking::SqueezeNetwork->new(
		sub {},
		sub {},
	);
	
	$http->get( $http->url( '/api/v1/stats/mark_disabled/' . $isDisabled ) );
}

1;

__END__
