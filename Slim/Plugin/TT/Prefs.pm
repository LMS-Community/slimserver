package Slim::Plugin::TT::Prefs;

# $Id: Prefs.pm 1757 2005-01-18 21:22:50Z dsully $
# SlimServer Copyright (c) 2001-2004 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use base qw(Template::Plugin);

sub load {
	my ($class, $context) = @_;

	return $class;
}

sub new {
	my ($class, $context, @params) = @_;
	bless {}, $class;
}

sub get {
	my $self = shift;
	return Slim::Utils::Prefs::get(@_);
}

sub getInd {
	my $self = shift;
	return Slim::Utils::Prefs::getInd(@_);
}

sub clientGet {
	my $self = shift;
	return Slim::Utils::Prefs::clientGet(@_);
}

1;
