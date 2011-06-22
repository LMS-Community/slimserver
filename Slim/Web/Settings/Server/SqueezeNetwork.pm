package Slim::Web::Settings::Server::SqueezeNetwork;

# $Id$

# Logitech Media Server Copyright 2001-2011 Logitech.
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
	return Slim::Web::HTTP::CSRF->protectName('SQUEEZENETWORK_SETTINGS');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('settings/server/squeezenetwork.html');
}

sub prefs {
	# NOTE: if you add a pref here, check that the wizard also submits it
	# in HTML/EN/html/wizard.js
	my @prefs = qw(sn_disable_stats);

	return ($prefs, @prefs);
}

sub handler {
	my ($class, $client, $params, $callback, @args) = @_;

	# The hostname for mysqueezebox.com
	my $sn_server = Slim::Networking::SqueezeNetwork->get_server("sn");
	$params->{sn_server} = $sn_server;
	
	$params->{prefs}->{pref_sn_email} = $prefs->get('sn_email');
	$params->{prefs}->{pref_sn_sync}  = $prefs->get('sn_sync');

	if ( $params->{saveSettings} ) {
		
		if ( defined $params->{pref_sn_sync} ) {
			$prefs->set( 'sn_sync', $params->{pref_sn_sync} );

			Slim::Networking::SqueezeNetwork::PrefSync->shutdown();
			if ( $params->{pref_sn_sync} ) {
				Slim::Networking::SqueezeNetwork::PrefSync->init();
			}
			
			$params->{prefs}->{pref_sn_sync} = $params->{pref_sn_sync};
		}

		# set credentials if mail changed or a password is defined and it has changed
		if ( $params->{pref_sn_email} ne $params->{prefs}->{pref_sn_email}
			|| ( $params->{pref_sn_password_sha} && sha1_base64($params->{pref_sn_password_sha}) ne $prefs->get('sn_password_sha') ) ) {
	
			# Verify username/password
			Slim::Control::Request::executeRequest(
				$client,
				[ 
					'setsncredentials', 
					$params->{pref_sn_email}, 
					$params->{pref_sn_password_sha},
				],
				sub {
					my $request = shift;
					
					my $validated = $request->getResult('validated');
					my $warning   = $request->getResult('warning');

					$params->{prefs}->{pref_sn_email} = $prefs->get('sn_email');
			
					if ($params->{'AJAX'}) {
						$params->{'warning'} = $warning;
						$params->{'validated'}->{'valid'} = $validated;
					}
					
					if (!$validated) {
		
						$params->{'warning'} .= $warning . '<br/>' unless $params->{'AJAX'};
		
						$params->{prefs}->{pref_sn_email} = $params->{pref_sn_email};

						delete $params->{pref_sn_email};
						delete $params->{pref_sn_password_sha};
					}


					my $body = $class->SUPER::handler($client, $params);
					$callback->( $client, $params, $body, @args );
				},
			);

			return;
		}
	}

	return $class->SUPER::handler($client, $params);
}

1;

__END__
