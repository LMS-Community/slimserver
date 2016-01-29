package Slim::Menu::GenreInfo;

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

# Provides OPML-based extensible menu for genre info
=head1 NAME

Slim::Menu::GenreInfo

=head1 DESCRIPTION

Provides a dynamic OPML-based genre info menu to all UIs and allows
plugins to register additional menu items.

=cut

use strict;

use base qw(Slim::Menu::Base);

use Scalar::Util qw(blessed);

use Slim::Utils::Log;
use Slim::Utils::Strings qw(cstring);

my $log = logger('menu.genreinfo');

sub init {
	my $class = shift;
	$class->SUPER::init();
	
	Slim::Control::Request::addDispatch(
		[ 'genreinfo', 'items', '_index', '_quantity' ],
		[ 0, 1, 1, \&cliQuery ]
	);
	
	Slim::Control::Request::addDispatch(
		[ 'genreinfo', 'playlist', '_method' ],
		[ 1, 1, 1, \&cliQuery ]
	);
}

sub name {
	return 'GENRE_INFO';
}

##
# Register all the information providers that we provide.
# This order is defined at http://wiki.slimdevices.com/index.php/UserInterfaceHierarchy
#
sub registerDefaultInfoProviders {
	my $class = shift;
	
	$class->SUPER::registerDefaultInfoProviders();

	$class->registerInfoProvider( addgenre => (
		menuMode  => 1,
		after    => 'top',
		func      => \&addGenreEnd,
	) );

	$class->registerInfoProvider( addgenrenext => (
		menuMode  => 1,
		after    => 'addgenre',
		func      => \&addGenreNext,
	) );


	$class->registerInfoProvider( playitem => (
		menuMode  => 1,
		after    => 'addgenrenext',
		func      => \&playGenre,
	) );


}

sub menu {
	my ( $class, $client, $url, $genre, $tags ) = @_;
	$tags ||= {};

	# If we don't have an ordering, generate one.
	# This will be triggered every time a change is made to the
	# registered information providers, but only then. After
	# that, we will have our ordering and only need to step
	# through it.
	my $infoOrdering = $class->getInfoOrdering;
	
	# $remoteMeta is an empty set right now. adding to allow for parallel construction with trackinfo
	my $remoteMeta = {};

	# Get genre object if necessary
	if ( !blessed($genre) ) {
		$genre = Slim::Schema->rs('Genre')->objectForUrl( {
			url => $url,
		} );
		if ( !blessed($genre) ) {
			$log->error( "No genre object found for $url" );
			return;
		}
	}
	
	# Function to add menu items
	my $addItem = sub {
		my ( $ref, $items ) = @_;
		
		if ( defined $ref->{func} ) {
			
			my $item = eval { $ref->{func}->( $client, $url, $genre, $remoteMeta, $tags ) };
			if ( $@ ) {
				$log->error( 'GenreInfo menu item "' . $ref->{name} . '" failed: ' . $@ );
				return;
			}
			
			return unless defined $item;
			
			# skip jive-only items for non-jive UIs
			return if $ref->{menuMode} && !$tags->{menuMode};
			
			if ( ref $item eq 'ARRAY' ) {
				if ( scalar @{$item} ) {
					push @{$items}, @{$item};
				}
			}
			elsif ( ref $item eq 'HASH' ) {
				return if $item->{menuMode} && !$tags->{menuMode};
				if ( scalar keys %{$item} ) {
					push @{$items}, $item;
				}
			}
			else {
				$log->error( 'GenreInfo menu item "' . $ref->{name} . '" failed: not an arrayref or hashref' );
			}				
		}
	};
	
	# Now run the order, which generates all the items we need
	my $items = [];
	
	for my $ref ( @{ $infoOrdering } ) {
		# Skip items with a defined parent, they are handled
		# as children below
		next if $ref->{parent};
		
		# Add the item
		$addItem->( $ref, $items );
		
		# Look for children of this item
		my @children = grep {
			$_->{parent} && $_->{parent} eq $ref->{name}
		} @{ $infoOrdering };
		
		if ( @children ) {
			my $subitems = $items->[-1]->{items} = [];
			
			for my $child ( @children ) {
				$addItem->( $child, $subitems );
			}
		}
	}
	
	return {
		name  => $genre->name,
		type  => 'opml',
		items => $items,
		menuComplete => 1,
	};
}


sub playGenre {
	my ( $client, $url, $genre, $remoteMeta, $tags) = @_;

	my $items = [];
	my $jive;

	return $items if !blessed($client);
	
	my $play_string   = cstring($client, 'PLAY');

	my $actions = {
		go => {
			player => 0,
			cmd => [ 'playlistcontrol' ],
			params => {
				genre_id => $genre->id,
				cmd => 'load',
			},
			nextWindow => 'nowPlaying',
		},
	};
	$actions->{play} = $actions->{go};

	$jive->{actions} = $actions;
	$jive->{style} = 'itemplay';
	push @{$items}, {
		type        => 'text',
		playcontrol => 'play',
		name        => $play_string,
		jive        => $jive, 
	};
	
	return $items;
}
	
sub addGenreEnd {
	my ( $client, $url, $genre, $remoteMeta, $tags ) = @_;
	my $add_string   = cstring($client, 'ADD_TO_END');
	my $cmd = 'add';
	addGenre ( $client, $url, $genre, $remoteMeta, $tags, $add_string, $cmd );
}

sub addGenreNext {
	my ( $client, $url, $genre, $remoteMeta, $tags ) = @_;
	my $add_string   = cstring($client, 'PLAY_NEXT');
	my $cmd = 'insert';
	addGenre ( $client, $url, $genre, $remoteMeta, $tags, $add_string, $cmd );
}


sub addGenre {
	my ( $client, $url, $genre, $remoteMeta, $tags, $add_string, $cmd ) = @_;

	my $items = [];
	my $jive;
	
	return $items if !blessed($client);

	my $actions = {
		go => {
			player => 0,
			cmd => [ 'playlistcontrol' ],
			params => {
				genre_id => $genre->id,
				cmd => $cmd,
			},
			nextWindow => 'parent',
		},
	};
	$actions->{play} = $actions->{go};
	$actions->{add}  = $actions->{go};

	$jive->{actions} = $actions;

	push @{$items}, {
		type        => 'text',
		playcontrol => $cmd,
		name        => $add_string,
		jive        => $jive, 
	};
	
	return $items;
}

sub cliQuery {
	main::DEBUGLOG && $log->is_debug && $log->debug('cliQuery');
	my $request = shift;
	
	# WebUI or newWindow param from SP side results in no
	# _index _quantity args being sent, but XML Browser actually needs them, so they need to be hacked in
	# here and the tagged params mistakenly put in _index and _quantity need to be re-added
	# to the $request params
	my $index      = $request->getParam('_index');
	my $quantity   = $request->getParam('_quantity');
	if ( $index =~ /:/ ) {
		$request->addParam(split (/:/, $index));
		$index = 0;
		$request->addParam('_index', $index);
	}
	if ( $quantity =~ /:/ ) {
		$request->addParam(split(/:/, $quantity));
		$quantity = 200;
		$request->addParam('_quantity', $quantity);
	}
	
	my $client         = $request->client;
	my $url            = $request->getParam('url');
	my $genreId        = $request->getParam('genre_id');
	my $menuMode       = $request->getParam('menu') || 0;
	

	my $tags = {
		menuMode      => $menuMode,
	};

	unless ( $url || $genreId ) {
		$request->setStatusBadParams();
		return;
	}
	
	my $feed;
	
	# Default menu
	if ( $url ) {
		$feed = Slim::Menu::GenreInfo->menu( $client, $url, undef, $tags );
	}
	else {
		my $genre = Slim::Schema->find( Genre => $genreId );
		$feed     = Slim::Menu::GenreInfo->menu( $client, $genre->url, $genre, $tags );
	}
	
	Slim::Control::XMLBrowser::cliQuery( 'genreinfo', $feed, $request );
}

1;
