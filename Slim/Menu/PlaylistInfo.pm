package Slim::Menu::PlaylistInfo;

# SqueezeCenter Copyright 2001-2009 Logitech.
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
		[ 1, 1, 1, \&cliQuery ]
	);
	
	Slim::Control::Request::addDispatch(
		[ 'playlistinfo', 'playlist', '_method' ],
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

	$class->registerInfoProvider( playplaylist => (
		menuMode  => 1,
		after    => 'top',
		func      => \&playPlaylist,
	) );

	$class->registerInfoProvider( addplaylist => (
		menuMode  => 1,
		after    => 'playplaylist',
		func      => \&addPlaylist,
	) );

}

sub menu {
	my ( $class, $client, $url, $playlist, $tags ) = @_;
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
		$playlist = Slim::Schema->rs('Playlist')->objectForUrl( {
			url => $url,
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
			
			my $item = eval { $ref->{func}->( $client, $url, $playlist, $remoteMeta, $tags ) };
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
	};
}


sub playPlaylist {
	my ( $client, $url, $playlist, $remoteMeta, $tags) = @_;

	my $items = [];
	my $jive;
	
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
		add => {
			player => 0,
			cmd => [ 'playlistcontrol' ],
			params => {
				playlist_id => $playlist->id,
				cmd => 'add',
			},
			nextWindow => 'parent',
		},
		'add-hold' => {
			player => 0,
			cmd => [ 'playlistcontrol' ],
			params => {
				playlist_id => $playlist->id,
				cmd => 'insert',
			},
			nextWindow => 'parent',
		},
	};
	$actions->{play} = $actions->{go};

	$jive->{actions} = $actions;
	$jive->{style}   = 'itemplay';
	push @{$items}, {
		type => 'text',
		name => $play_string,
		jive => $jive, 
	};
	
	return $items;
}
	
sub addPlaylist {
	my ( $client, $url, $playlist, $remoteMeta, $tags ) = @_;

	my $items = [];
	my $jive;
	
	my $add_string   = cstring($client, 'ADD');

	my $actions = {
		go => {
			player => 0,
			cmd => [ 'playlistcontrol' ],
			params => {
				playlist_id => $playlist->id,
				cmd => 'add',
			},
			nextWindow => 'parent',
		},
		'add-hold' => {
			player => 0,
			cmd => [ 'playlistcontrol' ],
			params => {
				playlist_id => $playlist->id,
				cmd => 'insert',
			},
			nextWindow => 'parent',
		},
	};
	$actions->{play} = $actions->{go};
	$actions->{add}  = $actions->{go};

	$jive->{actions} = $actions;
	$jive->{style}   = 'itemadd';

	push @{$items}, {
		type => 'text',
		name => $add_string,
		jive => $jive, 
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

sub cliQuery {
	$log->debug('cliQuery');
	my $request = shift;
	
	my $client         = $request->client;
	my $url            = $request->getParam('url');
	my $playlistId        = $request->getParam('playlist_id');
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
		$feed = Slim::Menu::PlaylistInfo->menu( $client, $url, undef, $tags );
	}
	else {
		my $playlist = Slim::Schema->find( Playlist => $playlistId );
		$feed     = Slim::Menu::PlaylistInfo->menu( $client, $playlist->url, $playlist, $tags );
	}
	
	Slim::Control::XMLBrowser::cliQuery( 'playlistinfo', $feed, $request );
}

1;
