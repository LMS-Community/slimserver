package Slim::Plugin::Podcast::GPodder;

# Logitech Media Server Copyright 2005-2021 Logitech.

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

Slim::Plugin::Podcast::Plugin::registerProvider(__PACKAGE__, 'GPodder', {
	title => 'title',
	feed  => 'url',
	image =>  ['scaled_logo_url', 'logo_url'],
	description => 'description',
	author => 'author',
});

# just use defaults
sub getItems { [ { } ] }

sub getSearchParams {
	return ('https://gpodder.net/search.json?scale_logo=256&q=' . $_[3]);
}

1;