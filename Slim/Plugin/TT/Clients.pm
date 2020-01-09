package Slim::Plugin::TT::Clients;

# Logitech Media Server Copyright 2001-2020 Logitech.
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
	my $sortBy = shift;
	my @clients = Slim::Player::Client::clients();
	if ($sortBy && UNIVERSAL::can('Slim::Player::Client',$sortBy)) {
		# Schwartian Transform here
		my @sorted_clients =
		    map { $_->[0] }
		    sort { $b->[1] cmp $a->[1] } 
		    map { [ $_, $_->$sortBy ] } 
		    @clients;
		return \@sorted_clients;
	}
	return \@clients;	
}

sub client {
	my $self = shift;
	my $id = shift;
	return Slim::Player::Client::getClient($id);
}

1;
