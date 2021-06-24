package Slim::Plugin::Podcast::GPodder;

# Logitech Media Server Copyright 2005-2021 Logitech.

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use base qw(Slim::Plugin::Podcast::Provider);

sub new {
	my $self = shift->SUPER::new;

	$self->init_accessor(
		title => 'title',
		feed  => 'url',
		image =>  ['scaled_logo_url', 'logo_url'],
		description => 'description',
		author => 'author',
	);

	return $self;
}

sub getSearchParams {
	return ('https://gpodder.net/search.json?scale_logo=256&q=' . $_[3]);
}

sub getName { 'GPodder' }


1;