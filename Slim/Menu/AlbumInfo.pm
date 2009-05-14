package Slim::Menu::AlbumInfo;

# SqueezeCenter Copyright 2001-2009 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

# Provides OPML-based extensible menu for album info
=head1 NAME

Slim::Menu::AlbumInfo

=head1 DESCRIPTION

Provides a dynamic OPML-based album info menu to all UIs and allows
plugins to register additional menu items.

=cut

use strict;

use base qw(Slim::Menu::Base);

use Scalar::Util qw(blessed);

use Slim::Utils::Log;
use Slim::Utils::Strings qw(cstring);

my $log = logger('menu.albuminfo');

sub init {
	my $class = shift;
	$class->SUPER::init();
	
	Slim::Control::Request::addDispatch(
		[ 'albuminfo', 'items', '_index', '_quantity' ],
		[ 1, 1, 1, \&cliQuery ]
	);
	
	Slim::Control::Request::addDispatch(
		[ 'albuminfo', 'playlist', '_method' ],
		[ 1, 1, 1, \&cliQuery ]
	);
}

sub name {
	return 'ALBUM_INFO';
}

##
# Register all the information providers that we provide.
# This order is defined at http://wiki.slimdevices.com/index.php/UserInterfaceHierarchy
#
sub registerDefaultInfoProviders {
	my $class = shift;
	
	$class->SUPER::registerDefaultInfoProviders();

	$class->registerInfoProvider( playalbum => (
		menuMode  => 1,
		after    => 'top',
		func      => \&playAlbum,
	) );

	$class->registerInfoProvider( addalbum => (
		menuMode  => 1,
		after    => 'playalbum',
		func      => \&addAlbum,
	) );

#	$class->registerInfoProvider( artwork => (
#		menuMode  => 1,
#		after     => 'addalbum',
#		func      => \&showArtwork,
#	) );

	$class->registerInfoProvider( replaygain => (
		menuMode => 1,
		after    => 'addalbum',
		func     => \&infoReplayGain,
	) );

}

sub menu {
	my ( $class, $client, $url, $album, $tags ) = @_;
	$tags ||= {};

	# If we don't have an ordering, generate one.
	# This will be triggered every time a change is made to the
	# registered information providers, but only then. After
	# that, we will have our ordering and only need to step
	# through it.
	my $infoOrdering = $class->getInfoOrdering;
	
	# $remoteMeta is an empty set right now. adding to allow for parallel construction with trackinfo
	my $remoteMeta = {};

	# Get album object if necessary
	if ( !blessed($album) ) {
		$album = Slim::Schema->rs('Album')->objectForUrl( {
			url => $url,
		} );
		if ( !blessed($album) ) {
			$log->error( "No album object found for $url" );
			return;
		}
	}
	
	# Function to add menu items
	my $addItem = sub {
		my ( $ref, $items ) = @_;
		
		if ( defined $ref->{func} ) {
			
			my $item = eval { $ref->{func}->( $client, $url, $album, $remoteMeta, $tags ) };
			if ( $@ ) {
				$log->error( 'Album menu item "' . $ref->{name} . '" failed: ' . $@ );
				return;
			}
			
			return unless defined $item;
			
			# skip jive-only items for non-jive UIs
			return if $ref->{menuMode} && !$tags->{menuMode};
			
			# show artwork item to jive only if artwork exists
			return if $ref->{menuMode} && $tags->{menuMode} && $ref->{name} eq 'artwork' && !$album->coverArtExists;
			
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
				$log->error( 'TrackInfo menu item "' . $ref->{name} . '" failed: not an arrayref or hashref' );
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
		name  => $album->title || Slim::Music::Info::getCurrentTitle( $client, $url, 1 ),
		type  => 'opml',
		items => $items,
		cover => '/music/' . $album->id . '/cover.jpg',
	};
}


sub showArtwork {
	my ( $client, $url, $album, $remoteMeta, $tags ) = @_;
	my $items = [];
	my $jive;
	my $actions = {
		do => {
			cmd => [ 'artwork', $album->id ],
		},
	};
	$jive->{actions} = $actions;
	$jive->{showBigArtwork} = 1;

	push @{$items}, {
		type => 'text',
		name => cstring($client, 'SHOW_ARTWORK'),
		jive => $jive, 
	};
	
	return $items;
}

sub playAlbum {
	my ( $client, $url, $album, $remoteMeta, $tags) = @_;

	my $items = [];
	my $jive;
	
	my $play_string   = cstring($client, 'PLAY');

	my $actions = {
		go => {
			player => 0,
			cmd => [ 'playlistcontrol' ],
			params => {
				album_id => $album->id,
				cmd => 'load',
			},
			nextWindow => 'nowPlaying',
		},
		add => {
			player => 0,
			cmd => [ 'playlistcontrol' ],
			params => {
				album_id => $album->id,
				cmd => 'add',
			},
			nextWindow => 'parent',
		},
		'add-hold' => {
			player => 0,
			cmd => [ 'playlistcontrol' ],
			params => {
				album_id => $album->id,
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
	
sub addAlbum {
	my ( $client, $url, $album, $remoteMeta, $tags ) = @_;

	my $items = [];
	my $jive;
	
	my $add_string   = cstring($client, 'ADD');

	my $actions = {
		go => {
			player => 0,
			cmd => [ 'playlistcontrol' ],
			params => {
				album_id => $album->id,
				cmd => 'add',
			},
			nextWindow => 'parent',
		},
		'add-hold' => {
			player => 0,
			cmd => [ 'playlistcontrol' ],
			params => {
				album_id => $album->id,
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

sub infoReplayGain {
	my ( $client, $url, $album ) = @_;
	
	my $items = [];
	
	if ( blessed($album) && $album->can('replay_gain') ) {
		if ( my $albumreplaygain = $album->replay_gain ) {
			my $noclip = Slim::Player::ReplayGain::preventClipping( $albumreplaygain, $album->replay_peak );
			if ( $noclip < $albumreplaygain ) {
				# Gain was reduced to avoid clipping
				push @{$items}, {
					type => 'text',
					name => cstring($client, 'ALBUMREPLAYGAIN') . cstring($client, 'COLON') . ' ' 
						. sprintf( "%2.2f", $albumreplaygain ) . ' dB (' 
						. cstring( $client, 'REDUCED_TO_PREVENT_CLIPPING', sprintf( "%2.2f dB", $noclip ) ) . ')',
				};
			}
			else {
				push @{$items}, {
					type => 'text',
					name => cstring($client, 'ALBUMREPLAYGAIN') . cstring($client, 'COLON') . ' ' . sprintf( "%2.2f", $albumreplaygain ) . ' dB',
				};
			}
		}
	}
	
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
	my $albumId        = $request->getParam('album_id');
	my $menuMode       = $request->getParam('menu') || 0;
	my $menuContext    = $request->getParam('context') || 'normal';
	my $playlist_index = defined( $request->getParam('playlist_index') ) ?  $request->getParam('playlist_index') : undef;
	

	my $tags = {
		menuMode      => $menuMode,
		menuContext   => $menuContext,
		playlistIndex => $playlist_index,
	};

	unless ( $url || $albumId ) {
		$request->setStatusBadParams();
		return;
	}
	
	my $feed;
	
	# Default menu
	if ( $url ) {
		$feed = Slim::Menu::AlbumInfo->menu( $client, $url, undef, $tags );
	}
	else {
		my $album = Slim::Schema->find( Album => $albumId );
		$feed     = Slim::Menu::AlbumInfo->menu( $client, $album->url, $album, $tags );
	}
	
	Slim::Control::XMLBrowser::cliQuery( 'albuminfo', $feed, $request );
}

1;
