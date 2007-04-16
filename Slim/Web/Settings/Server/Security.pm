package Slim::Web::Settings::Server::Security;

# $Id$

# SlimServer Copyright (c) 2001-2006 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;

sub name {
	return 'SECURITY_SETTINGS';
}

sub page {
	return 'settings/server/security.html';
}

sub prefs {
	return (preferences('server'), qw(filterHosts allowedHosts csrfProtectionLevel authorize username password) );
}

1;

__END__
