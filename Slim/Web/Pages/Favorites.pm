package Slim::Web::Pages::Favorites;

# $Id$
#
# Copyright (C) 2005-2006 Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use Slim::Utils::Favorites;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);

sub init {

	Slim::Web::HTTP::addPageFunction("favorites_list\.htm", \&handleWebIndex);

	Slim::Web::Pages->addPageLinks("browse", { 'FAVORITES' => "favorites_list.html" });
}

sub handleWebIndex {
	my ($client, $params) = @_;
	
	$params->{'favList'} = {};

	my $favs   = Slim::Utils::Favorites->new($client);
	my @titles = $favs->titles;
	my @urls   = $favs->urls;
	my $i      = 0;

	if (scalar @titles) {

		$params->{'titles'} = \@titles;
		$params->{'urls'}   = \@urls;

		for (@titles) {
			$params->{'faves'}{$_} = $urls[$i++];
		}

	} else {

		$params->{'warning'} = string('FAVORITES_NONE_DEFINED');
	}

	return Slim::Web::HTTP::filltemplatefile('favorites_list.html', $params);
}

1;

__END__
