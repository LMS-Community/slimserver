package Slim::Web::Settings::Server::Security;

# $Id$

# SlimServer Copyright (c) 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;

sub name {
	return Slim::Web::HTTP::protectName('SECURITY_SETTINGS');
}

sub page {
	return Slim::Web::HTTP::protectURI('settings/server/security.html');
}

sub prefs {
	return (preferences('server'), qw(filterHosts allowedHosts csrfProtectionLevel authorize username password) );
}

1;

__END__
