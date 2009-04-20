package Slim::Web::Settings::Server::Security;

# $Id$

# SqueezeCenter Copyright 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use Digest::SHA1 qw(sha1_base64);
use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;

my $prefs = preferences('server');

sub name {
	return Slim::Web::HTTP::protectName('SECURITY_SETTINGS');
}

sub page {
	return Slim::Web::HTTP::protectURI('settings/server/security.html');
}

sub prefs {
	return (preferences('server'), qw(filterHosts allowedHosts csrfProtectionLevel authorize username) );
}

sub handler {
	my ($class, $client, $paramRef, $pageSetup) = @_;

	# disable authorization if no username is set
	$paramRef->{'authorize'} = 0 unless $paramRef->{'username'};

	# pre-process password to avoid saving clear text
	if ($paramRef->{'saveSettings'} && $paramRef->{'pref_password'}) {

		my $val = $paramRef->{'pref_password'};

		if ($val ne $paramRef->{'pref_password_repeat'}) {

			$paramRef->{'warning'} .= Slim::Utils::Strings::string('SETUP_PASSWORD_MISMATCH');
			$paramRef->{'pref_authorize'} = 0;

		}

		else {

			my $currentPassword = preferences('server')->get('password');
		
			if (defined($val) && $val ne '' && ($currentPassword eq '' || sha1_base64($val) ne $currentPassword)) {
				$prefs->set('password', sha1_base64($val));
			}
			
		}
	}

	return $class->SUPER::handler($client, $paramRef, $pageSetup);
}


1;

__END__
