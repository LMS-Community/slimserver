package Slim::Plugin::TT::Prefs;

# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

# TT wrapper to access prefs, e.g of use:
#
#	[% USE Prefs; USE Clients %]
#	<h1>Global Preferences</h1>
#	[% FOREACH namespace = Prefs.namespaces %]<b>Namespace: [%	namespace %]</b><br />
#	[% prefs = Prefs.preferences(namespace) %]
#	[% FOREACH pref = prefs.all.keys %] [% pref %] = [%	prefs.get(pref) %]<br />[% END %]
#	<br />
#	[% END %]
#	[% client = Clients.client(player) %]
#	<h1>Client Preferences [% client.name %]</h1>
#	[% FOREACH namespace = Prefs.namespaces %]<b>Namespace: [% namespace %]</b><br />
#	[% clientprefs = Prefs.preferences(namespace).client(client) %]
#	[% FOREACH clientpref = clientprefs.all.keys %] [% clientpref %] = [% clientprefs.get(clientpref) %]<br />[% END %]
#	<br />
#	[% END %]

use strict;
use base qw(Template::Plugin);

sub namespaces {
	return Slim::Utils::Prefs::namespaces();
}

sub preferences {
	my $self = shift;
	return Slim::Utils::Prefs::preferences(@_);
}

1;
