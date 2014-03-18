package Slim::Menu::GlobalSearch;

# Logitech Media Server Copyright 2001-2011 Logitech.
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
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(cstring);

my $log = logger('menu.globalsearch');

sub init {
	my $class = shift;
	$class->SUPER::init();
	
	Slim::Control::Request::addDispatch(
		[ 'globalsearch', 'items', '_index', '_quantity' ],
		[ 1, 1, 1, \&cliQuery ]
	);
	
	Slim::Control::Request::addDispatch(
		[ 'globalsearch', 'playlist', '_method' ],
		[ 1, 1, 1, \&cliQuery ]
	);
}

sub name {
	return 'GLOBAL_SEARCH';
}

sub registerSearchProviders {
	my ($class, $search_providers) = @_;
	
	main::DEBUGLOG && $log->is_debug && $log->debug( 'Registering search providers: ' . Data::Dump::dump( $search_providers ) );

	my %existing_providers;

	# get a list of external search providers so we can purge items which have been disabled since last update
	while (my ($key, $value) = each %{ $class->getInfoProvider() }) {
		$existing_providers{$key} = 1 if $value->{remote_search};
	}

	foreach my $provider ( @{ $search_providers } ) {
			
		delete $existing_providers{$provider->{text}};

		$class->registerInfoProvider( $provider->{text} => (
			isa    => $provider->{isa},
			before => $provider->{before},
			after  => $provider->{after},
			app    => lc($provider->{text}),
			
			func   => sub {
				my ( $client, $tags ) = @_;

				if ($provider->{app} && !(grep /$provider->{app}/, @{ $tags->{apps} }) ) {
					
					main::DEBUGLOG && $log->is_debug && $log->debug( 'Skipping app - not enabled on this player: ' . cstring($client, $provider->{text}) );
					return;
				}

				my $menuItem = {
					name   => cstring($client, $provider->{text}),
					url    => $provider->{URL} || $provider->{url},
					search => $tags->{search},
					type   => $provider->{slideshow} ? 'slideshow' : undef,
				};

				$menuItem->{url} =~ s/{QUERY}/$tags->{search}/ if $menuItem->{url};

				if ($provider->{outline}) {
						
					$menuItem->{items} = [];
						
					foreach my $item (@{ $provider->{outline} }) {
						my $url = $item->{URL} || $item->{url};
						$url =~ s/{QUERY}/$tags->{search}/;
							
						push @{ $menuItem->{items} }, {
							name   => cstring($client, $item->{text}),
							url    => $url,
							search => $tags->{search},
							type   => $item->{slideshow} ? 'slideshow' : undef,
						};
					}
				}

				return $menuItem;
			},
				
			remote_search => 1
		) ) 			
	}
		
	# remove search providers which have been disabled since last update
	foreach (keys %existing_providers) {
		$class->deregisterInfoProvider($_);
	}
}

sub menu {
	my ( $class, $client, $tags ) = @_;

	$tags->{apps} = [ keys %{$client->apps} ];

	my $menu = $class->SUPER::menu($client, $tags);

	$menu->{name} = cstring($client, 'GLOBAL_SEARCH_IN', $tags->{search});
	
	return $menu;
}

sub cliQuery {

	my $request = shift;
	my $client  = $request->client;
	my $search  = $request->getParam('search') || '';

	if ( !$search && (my $itemId = $request->getParam('item_id')) ) {
		($search) = $itemId =~ m/_([^.]+)/;
	}

	$search = Slim::Utils::Misc::unescape($search);
	
	my $tags = {
		menuMode => $request->getParam('menu') || 0,
		search   => $search,
	};

	my $feed = __PACKAGE__->menu( $client, $tags );

	Slim::Control::XMLBrowser::cliQuery( 'globalsearch', $feed, $request );
}

1;
