package Slim::Plugin::Podcast::GPodder;

# Logitech Media Server Copyright 2005-2021 Logitech.

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

__PACKAGE__->Slim::Plugin::Podcast::Plugin::registerProvider('GPodder', {
		title => 'title',
		feed  => 'url',
		image =>  ['scaled_logo_url', 'logo_url'],
});

# just use defaults
sub getItems { [ { } ] }

sub getSearchParams {
	return ('https://gpodder.net/search.json?q=' . $_[2]);
}


1;