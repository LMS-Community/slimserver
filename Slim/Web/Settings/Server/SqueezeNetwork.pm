package Slim::Web::Settings::Server::SqueezeNetwork;


# Logitech Media Server Copyright 2001-2020 Logitech.
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

	if ( $params->{pref_logout} ) {
		Slim::Control::Request::executeRequest(
			$client,
			[
				'setsncredentials',
			],
		);
	}
	elsif ( $params->{saveSettings} ) {

		if ( defined $params->{pref_sn_sync} ) {
			$prefs->set( 'sn_sync', $params->{pref_sn_sync} );
		}

		# set credentials if mail changed or a password is defined and it has changed
		if ( $params->{pref_sn_email} && $params->{sn_password} ) {
			# Verify username/password
			Slim::Control::Request::executeRequest(
				$client,
				[
					'setsncredentials',
					$params->{pref_sn_email},
					Slim::Utils::Unicode::utf8encode($params->{sn_password}),
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

						delete $params->{pref_sn_email};
						delete $params->{sn_password};
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

sub beforeRender {
	my ($class, $params, $client) = @_;

	# The hostname for mysqueezebox.com
	my $sn_server = Slim::Networking::SqueezeNetwork->get_server("sn");
	$params->{sn_server} = $sn_server;

	$params->{prefs}->{pref_sn_email} = $prefs->get('sn_email');
	$params->{prefs}->{pref_sn_sync}  = $prefs->get('sn_sync');
	$params->{has_session}            = $prefs->get('sn_session');
}

1;

__END__
