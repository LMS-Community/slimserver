package Slim::Plugin::TT::Prefs;

# $Id: Prefs.pm 1757 2005-01-18 21:22:50Z dsully $
# SqueezeCenter Copyright (c) 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

# TT wrapper to access prefs, e.g of use:
#
# [% USE Prefs; FOREACH namespace = Prefs.namespaces %] <h3>[% namespace %]</h3>
# [% prefs = Prefs.preferences(namespace) %]
# [% FOREACH pref = prefs.all.keys %] [% pref %] = [% prefs.get(pref) %]<br>[% END %]
# [% END %]

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
