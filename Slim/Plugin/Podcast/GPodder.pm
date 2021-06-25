package Slim::Plugin::Podcast::GPodder;

# Logitech Media Server Copyright 2005-2021 Logitech.

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use base qw(Slim::Plugin::Podcast::Provider);

sub getFeedsIterator {
	my ($self, $feeds) = @_;
	my $index;
	
	# iterator on feeds
	return sub {
		my $feed = $feeds->[$index++];
		return unless $feed;
	
		my ($image) = grep { $feed->{$_} } qw(scaled_logo_url logo_url);
	
		return {
			name         => $feed->{title},
			url          => $feed->{url},
			image        => $feed->{$image},
			description  => $feed->{description},
			author       => $feed->{author},
		};
	};	
}

sub getSearchParams {
	return ('https://gpodder.net/search.json?scale_logo=256&q=' . $_[3]);
}

sub getName { 'GPodder' }


1;