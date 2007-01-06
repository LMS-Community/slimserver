package Slim::Web::Settings::Server::Security;

# $Id$

# SlimServer Copyright (c) 2001-2006 Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

sub name {
	return 'SECURITY_SETTINGS';
}

sub page {
	return 'settings/server/security.html';
}

sub handler {
	my ($class, $client, $paramRef, $pageSetup) = @_;

	my @prefs = qw(filterHosts allowedHosts csrfProtectionLevel authorize username password);

	for my $pref (@prefs) {

		if ($paramRef->{'saveSettings'}) {

			Slim::Utils::Prefs::set($pref, $paramRef->{$pref});
		}

		$paramRef->{$pref} = Slim::Utils::Prefs::get($pref);
	}

	return $class->SUPER::handler($client, $paramRef, $pageSetup);
}

1;

__END__
