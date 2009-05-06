package Slim::Web::Settings::Server::SqueezeNetwork;

# $Id$

# SqueezeCenter Copyright 2001-2007 Logitech.
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
	return Slim::Web::HTTP::protectName('SQUEEZENETWORK_SETTINGS');
}

sub page {
	return Slim::Web::HTTP::protectURI('settings/server/squeezenetwork.html');
}

sub prefs {
	# NOTE: if you add a pref here, check that the wizard also submits it
	# in HTML/EN/html/wizard.js
	my @prefs = qw(sn_disable_stats);

	return ($prefs, @prefs);
}

sub handler {
	my ($class, $client, $params, $callback, @args) = @_;

	# The hostname for SqueezeNetwork
	my $sn_server = Slim::Networking::SqueezeNetwork->get_server("sn");
	$params->{sn_server} = $sn_server;
	
	$params->{prefs}->{pref_sn_email} = $prefs->get('sn_email');
	$params->{prefs}->{pref_sn_sync}  = $prefs->get('sn_sync');

	if ( $params->{saveSettings} ) {
		
		if ( $params->{pref_sn_email} && $params->{pref_sn_password_sha} ) {
		
			# Verify username/password
			Slim::Control::Request::executeRequest(
				$client,
				[ 
					'setsncredentials', 
					$params->{pref_sn_email}, 
					$params->{pref_sn_password_sha},
					'sync:' . $params->{pref_sn_sync},
				],
				sub {
					my $request = shift;
					
					my $validated = $request->getResult('validated');
					my $warning   = $request->getResult('warning');
			
					if ($params->{'AJAX'}) {
						$params->{'warning'} = $warning;
						$params->{'validated'}->{'valid'} = $validated;
					}
					
					if (!$validated) {
		
						$params->{'warning'} .= $warning . '<br/>' unless $params->{'AJAX'};
		
						delete $params->{pref_sn_email};
						delete $params->{pref_sn_password_sha};
					}

					my $body = $class->SUPER::handler($client, $params);
					$callback->( $client, $params, $body, @args );
				},
			);

			return;
		}

		elsif ( !$params->{pref_sn_email} && !$params->{pref_sn_password_sha} ) {
			# Shut down SN if username/password were removed
			Slim::Networking::SqueezeNetwork->shutdown();
		}
	}

	return $class->SUPER::handler($client, $params);
}

1;

__END__
