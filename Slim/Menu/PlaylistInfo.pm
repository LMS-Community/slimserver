package Slim::Menu::PlaylistInfo;

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

# Provides OPML-based extensible menu for playlist info
=head1 NAME

Slim::Menu::PlaylistInfo

=head1 DESCRIPTION

Provides a dynamic OPML-based playlist info menu to all UIs and allows
plugins to register additional menu items.

=cut

use strict;

use base qw(Slim::Menu::Base);

use Scalar::Util qw(blessed);

use Slim::Utils::Log;
use Slim::Utils::Strings qw(cstring);

my $log = logger('menu.playlistinfo');

sub init {
	my $class = shift;
	$class->SUPER::init();
	
	Slim::Control::Request::addDispatch(
		[ 'playlistinfo', 'items', '_index', '_quantity' ],
		[ 0, 1, 1, \&cliQuery ]
	);
	
	Slim::Control::Request::addDispatch(
		[ 'playlistinfo', 'playlist', '_method' ],
		[ 1, 1, 1, \&cliQuery ]
	);
}

sub name {
	return 'PLAYLIST_INFO';
}

##
# Register all the information providers that we provide.
# This order is defined at http://wiki.slimdevices.com/index.php/UserInterfaceHierarchy
#
sub registerDefaultInfoProviders {
	my $class = shift;
	
	$class->SUPER::registerDefaultInfoProviders();

	$class->registerInfoProvider( playlistitemcount => (
		after    => 'top',
		func      => \&playlistItemCount,
	) );

	$class->registerInfoProvider( addplaylist => (
		menuMode  => 1,
		after    => 'playlistitemcount',
		func      => \&addPlaylistEnd,
	) );

	$class->registerInfoProvider( addplaylistnext => (
		menuMode  => 1,
		after    => 'addplaylist',
		func      => \&addPlaylistNext,
	) );

	$class->registerInfoProvider( playitem => (
		menuMode  => 1,
		after    => 'addplaylistnext',
		func      => \&playPlaylist,
	) );

	$class->registerInfoProvider( deleteplaylist => (
		menuMode  => 1,
		after    => 'favorites',
		func      => \&deletePlaylist,
	) );

}

sub menu {
	my ( $class, $client, $url, $playlist, $tags, $filter ) = @_;
	$tags ||= {};

	# If we don't have an ordering, generate one.
	# This will be triggered every time a change is made to the
	# registered information providers, but only then. After
	# that, we will have our ordering and only need to step
	# through it.
	my $infoOrdering = $class->getInfoOrdering;
	
	# $remoteMeta is an empty set right now. adding to allow for parallel construction with trackinfo
	my $remoteMeta = {};

	# Get playlist object if necessary
	if ( !blessed($playlist) ) {
		$playlist = Slim::Schema->objectForUrl( {
			url => $url,
			playlist => 1,
		} );
		if ( !blessed($playlist) ) {
			$log->error( "No playlist object found for $url" );
			return;
		}
	}
	
	# Function to add menu items
	my $addItem = sub {
		my ( $ref, $items ) = @_;
		
		if ( defined $ref->{func} ) {
			
			my $item = eval { $ref->{func}->( $client, $url, $playlist, $remoteMeta, $tags, $filter ) };
			if ( $@ ) {
				$log->error( 'PlaylistInfo menu item "' . $ref->{name} . '" failed: ' . $@ );
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
				$log->error( 'PlaylistInfo menu item "' . $ref->{name} . '" failed: not an arrayref or hashref' );
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
		name  => $playlist->name,
		type  => 'opml',
		items => $items,
		menuComplete => 1,
	};
}

sub playlistItemCount {
	my ( $client, $url, $playlist, $remoteMeta, $tags, $filter) = @_;
	
	my $items = [];
	my $jive;
	
	return $items if !blessed($client) || !blessed($playlist);
	
	my $library_id = $filter->{library_id} || Slim::Music::VirtualLibraries->getLibraryIdForClient($client);
	
	push @{$items}, {
		type => 'text',
		name => cstring($client, 'INFORMATION_TRACKS') . cstring('COLON') . ' ' 
			. Slim::Utils::Misc::delimitThousands($playlist->tracks($library_id)->count),
	};
	
	return $items;
}

sub playPlaylist {
	my ( $client, $url, $playlist, $remoteMeta, $tags, $filter) = @_;

	my $items = [];
	my $jive;
	
	return $items if !blessed($client);

	my $play_string   = cstring($client, 'PLAY');

	my $actions = {
		go => {
			player => 0,
			cmd => [ 'playlistcontrol' ],
			params => {
				playlist_id => $playlist->id,
				cmd => 'load',
			},
			nextWindow => 'nowPlaying',
		},
	};
	$actions->{play} = $actions->{go};
	
	if ( my $library_id = $filter->{library_id} || Slim::Music::VirtualLibraries->getLibraryIdForClient($client) ) {
		$actions->{go}->{params}->{library_id} = $library_id;
	}

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

sub addPlaylistEnd {
	my ( $client, $url, $playlist, $remoteMeta, $tags, $filter ) = @_;
	my $add_string   = cstring($client, 'ADD_TO_END');
	my $cmd = 'add';
	addPlaylist( $client, $url, $playlist, $remoteMeta, $tags, $add_string, $cmd, $filter );

}

sub addPlaylistNext {
	my ( $client, $url, $playlist, $remoteMeta, $tags, $filter ) = @_;
	my $add_string   = cstring($client, 'PLAY_NEXT');
	my $cmd = 'insert';
	addPlaylist( $client, $url, $playlist, $remoteMeta, $tags, $add_string, $cmd, $filter );

}

sub addPlaylist {
	my ( $client, $url, $playlist, $remoteMeta, $tags, $add_string, $cmd, $filter ) = @_;

	my $items = [];
	my $jive;

	return $items if !blessed($client);
	
	my $actions = {
		go => {
			player => 0,
			cmd => [ 'playlistcontrol' ],
			params => {
				playlist_id => $playlist->id,
				cmd => $cmd,
			},
			nextWindow => 'parent',
		},
	};
	$actions->{play} = $actions->{go};
	$actions->{add}  = $actions->{go};
	
	if ( my $library_id = $filter->{library_id} || Slim::Music::VirtualLibraries->getLibraryIdForClient($client) ) {
		$actions->{go}->{params}->{library_id} = $library_id;
	}

	$jive->{actions} = $actions;

	push @{$items}, {
		type        => 'text',
		playcontrol => $cmd,
		name        => $add_string,
		jive        => $jive, 
	};
	
	return $items;
}

sub deletePlaylist {
	my ( $client, $url, $playlist, $remoteMeta, $tags) = @_;

	return [] if !blessed($client);

	###
	# FIXME: bug 8670. This is the 7.1 workaround to deal with the %s in the EN string
	my $string = cstring($client, 'JIVE_DELETE_PLAYLIST', $playlist->name);
	$string =~ s/\\n/ /g;

	return [ {
		type => 'text',
		name => $string,
		jive => {
			actions => {
				'go' => {
					player => 0,
					cmd    => [ 'jiveplaylists', 'delete' ],
					params => {
						url	        => $url,
						playlist_id => $playlist->id,
						title       => $playlist->name,
						menu        => 'track',
						menu_all    => 1,
					},
				},
			},
			style   => 'item',
		}, 
	} ];
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
	my $playlistId     = $request->getParam('playlist_id');
	my $menuMode       = $request->getParam('menu') || 0;
	

	my $tags = {
		menuMode      => $menuMode,
	};

	unless ( $url || $playlistId ) {
		$request->setStatusBadParams();
		return;
	}
	
	my $feed;
	
	# Default menu
	if ( $url ) {
		$feed = Slim::Menu::PlaylistInfo->menu( $client, $url, undef, $tags, {
			library_id => $request->getParam('library_id')
		} );
	}
	else {
		my $playlist = Slim::Schema->find( Playlist => $playlistId );
		$feed = Slim::Menu::PlaylistInfo->menu( $client, $playlist->url, $playlist, $tags, {
			library_id => $request->getParam('library_id')
		}  );
	}
	
	Slim::Control::XMLBrowser::cliQuery( 'playlistinfo', $feed, $request );
}

1;
