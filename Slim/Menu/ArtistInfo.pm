package Slim::Menu::ArtistInfo;

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

# Provides OPML-based extensible menu for artist info
=head1 NAME

Slim::Menu::ArtistInfo

=head1 DESCRIPTION

Provides a dynamic OPML-based artist info menu to all UIs and allows
plugins to register additional menu items.

=cut

use strict;

use base qw(Slim::Menu::Base);

use Scalar::Util qw(blessed);

use Slim::Utils::Log;
use Slim::Utils::Strings qw(cstring);

my $log = logger('menu.artistinfo');

sub init {
	my $class = shift;
	$class->SUPER::init();
	
	Slim::Control::Request::addDispatch(
		[ 'artistinfo', 'items', '_index', '_quantity' ],
		[ 0, 1, 1, \&cliQuery ]
	);
	
	Slim::Control::Request::addDispatch(
		[ 'artistinfo', 'playlist', '_method' ],
		[ 1, 1, 1, \&cliQuery ]
	);
}

sub name {
	return 'ARTIST_INFO';
}

##
# Register all the information providers that we provide.
# This order is defined at http://wiki.slimdevices.com/index.php/UserInterfaceHierarchy
#
sub registerDefaultInfoProviders {
	my $class = shift;
	
	$class->SUPER::registerDefaultInfoProviders();

	$class->registerInfoProvider( addartist => (
		menuMode  => 1,
		after    => 'top',
		func      => \&addArtistEnd,
	) );
	$class->registerInfoProvider( addartistnext => (
		menuMode  => 1,
		after    => 'addartist',
		func      => \&addArtistNext,
	) );
	$class->registerInfoProvider( playitem => (
		menuMode  => 1,
		after    => 'addartistnext',
		func      => \&playArtist,
	) );


}

sub menu {
	my ( $class, $client, $url, $artist, $tags ) = @_;
	$tags ||= {};

	# If we don't have an ordering, generate one.
	# This will be triggered every time a change is made to the
	# registered information providers, but only then. After
	# that, we will have our ordering and only need to step
	# through it.
	my $infoOrdering = $class->getInfoOrdering;
	
	# $remoteMeta is an empty set right now. adding to allow for parallel construction with trackinfo
	my $remoteMeta = {};

	# Get artist object if necessary
	if ( !blessed($artist) ) {
		$artist = Slim::Schema->rs('Contributor')->objectForUrl( {
			url => $url,
		} );
		if ( !blessed($artist) ) {
			$log->error( "No artist object found for $url" );
			return;
		}
	}
	
	# Function to add menu items
	my $addItem = sub {
		my ( $ref, $items ) = @_;
		
		if ( defined $ref->{func} ) {
			
			my $item = eval { $ref->{func}->( $client, $url, $artist, $remoteMeta, $tags ) };
			if ( $@ ) {
				$log->error( 'Artist menu item "' . $ref->{name} . '" failed: ' . $@ );
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
				return if $ref->{menuMode} && !$tags->{menuMode};
				if ( scalar keys %{$item} ) {
					push @{$items}, $item;
				}
			}
			else {
				$log->error( 'Artistinfo menu item "' . $ref->{name} . '" failed: not an arrayref or hashref' );
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
		name  => $artist->name,
		type  => 'opml',
		items => $items,
		menuComplete => 1,
	};
}


sub playArtist {
	my ( $client, $url, $artist, $remoteMeta, $tags) = @_;

	my $items = [];
	my $jive;
	
	return $items if !blessed($client);

	my $play_string   = cstring($client, 'PLAY');

	my $actions = {
		go => {
			player => 0,
			cmd => [ 'playlistcontrol' ],
			params => {
				artist_id => $artist->id,
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

sub addArtistEnd {
	my ( $client, $url, $artist, $remoteMeta, $tags ) = @_;
	my $add_string   = cstring($client, 'ADD_TO_END');
	my $cmd = 'add';
	addArtist( $client, $url, $artist, $remoteMeta, $tags, $add_string, $cmd );
}


sub addArtistNext {
	my ( $client, $url, $artist, $remoteMeta, $tags ) = @_;
	my $add_string   = cstring($client, 'PLAY_NEXT');
	my $cmd = 'insert';
	addArtist( $client, $url, $artist, $remoteMeta, $tags, $add_string, $cmd );
}

sub addArtist {
	my ( $client, $url, $artist, $remoteMeta, $tags, $add_string, $cmd ) = @_;

	my $items = [];
	my $jive;
	
	return $items if !blessed($client);

	my $actions = {
		go => {
			player => 0,
			cmd => [ 'playlistcontrol' ],
			params => {
				artist_id => $artist->id,
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

sub _findDBCriteria {
	my $db = shift;
	
	my $findCriteria = '';
	foreach (keys %{$db->{findCriteria}}) {
		$findCriteria .= "&amp;$_=" . $db->{findCriteria}->{$_};
	}
	
	return $findCriteria;
}

# keep a very small cache of feeds to allow browsing into a artist info feed
# we will be called again without $url or $artistId when browsing into the feed
tie my %cachedFeed, 'Tie::Cache::LRU', 2;

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
	my $artistId        = $request->getParam('artist_id');
	my $menuMode       = $request->getParam('menu') || 0;
	my $menuContext    = $request->getParam('context') || 'normal';
	my $playlist_index = defined( $request->getParam('playlist_index') ) ?  $request->getParam('playlist_index') : undef;
	my $connectionId   = $request->connectionID || '';

	my $tags = {
		menuMode      => $menuMode,
		menuContext   => $menuContext,
		playlistIndex => $playlist_index,
	};

	my $feed;
	
	# Default menu
	if ( $url ) {
		$feed = Slim::Menu::ArtistInfo->menu( $client, $url, undef, $tags );
	}
	elsif ( $artistId ) {
		my $artist = Slim::Schema->find( Contributor => $artistId );
		$feed     = Slim::Menu::ArtistInfo->menu( $client, $artist->url, $artist, $tags );
	}
	elsif ( $cachedFeed{ $connectionId } ) {
		$feed = $cachedFeed{ $connectionId };
	}
	else {
		$request->setStatusBadParams();
		return;
	}
	
	$cachedFeed{ $connectionId } = $feed if $feed;

	Slim::Control::XMLBrowser::cliQuery( 'artistinfo', $feed, $request );
}

1;
