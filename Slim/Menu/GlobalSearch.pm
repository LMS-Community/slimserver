package Slim::Menu::GlobalSearch;

# Squeezebox Server Copyright 2001-2009 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

# Provides OPML-based extensible menu to various search providers
# see https://bugs.slimdevices.com/show_bug.cgi?id=13519

=head1 NAME

Slim::Menu::GlobalSearch

=head1 DESCRIPTION

Provides a dynamic OPML-based search menu to all UIs and allows
plugins to register additional search items.

=cut

use strict;

use base qw(Slim::Menu::Base);

use Slim::Utils::Log;
use Slim::Utils::Strings qw(cstring);

my $log = logger('menu.globalsearch');

sub init {
	my $class = shift;
	$class->SUPER::init();
	
	Slim::Control::Request::addDispatch(
		[ 'globalsearch', 'items', '_index', '_quantity' ],
		[ 1, 1, 1, \&cliQuery ]
	);
	
}

sub name {
	return 'GLOBAL_SEARCH';
}

sub registerDefaultInfoProviders {
	my $class = shift;
	
	$class->SUPER::registerDefaultInfoProviders();

	if ( !main::SLIM_SERVICE ) {
		$class->registerInfoProvider( searchMyMusic => (
			after => 'top',
			func  => \&searchMyMusic,
		) );
	}	
}

sub searchMyMusic {
	my ( $client, $tags ) = @_;
	my $items = [];
	
	my $jive = Slim::Control::Jive::searchMenu(1, $client);

	foreach my $item (@$jive) {
		
		if ($item->{actions} && $item->{actions}->{go} && $item->{actions}->{go}->{params}) {
			 $item->{actions}->{go}->{params}->{search} = $tags->{search};
		}
		
		push @$items, {
			name  => $item->{text},
			jive  => {
				actions => $item->{actions},
				text    => $item->{text},
				weight  => $item->{weight},
				window  => $item->{window},
			},
		};
	}

	return {
		name  => cstring($client, 'MY_MUSIC'),
		items => $items,
		type  => 'opml',
	};
}

sub cliQuery {

	my $request = shift;
	my $client  = $request->client;
	my $search  = $request->getParam('search') || '';
	
	if ( !$search && (my $itemId = $request->getParam('item_id')) ) {
		($search) = $itemId =~ m/_([^.]+)/;
	}
	
	my $tags = {
		menuMode => $request->getParam('menu') || 0,
		search   => $search,
	};

	my $feed = Slim::Menu::GlobalSearch->menu( $client, $tags );
	
	Slim::Control::XMLBrowser::cliQuery( 'globalsearch', $feed, $request );
}

1;
