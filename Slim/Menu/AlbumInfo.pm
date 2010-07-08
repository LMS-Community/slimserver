package Slim::Menu::AlbumInfo;

# Squeezebox Server Copyright 2001-2009 Logitech.
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

	$class->registerInfoProvider( addalbum => (
		menuMode  => 1,
		after    => 'top',
		func      => \&addAlbumEnd,
	) );

	$class->registerInfoProvider( addalbumnext => (
		menuMode  => 1,
		after    => 'addalbum',
		func      => \&addAlbumNext,
	) );

	$class->registerInfoProvider( playitem => (
		menuMode  => 1,
		after    => 'addalbumnext',
		func      => \&playAlbum,
	) );

#	$class->registerInfoProvider( artwork => (
#		menuMode  => 1,
#		after     => 'addalbum',
#		func      => \&showArtwork,
#	) );

	if ( !main::SLIM_SERVICE ) {
		$class->registerInfoProvider( contributors => (
			after => 'top',
			func  => \&infoContributors,
		) );
	}
	if ( !main::SLIM_SERVICE ) {
		$class->registerInfoProvider( year => (
			after => 'top',
			func  => \&infoYear,
		) );
	}

	$class->registerInfoProvider( duration => (
		after    => 'year',
		func     => \&infoDuration,
	) );

	$class->registerInfoProvider( replaygain => (
		after    => 'year',
		func     => \&infoReplayGain,
	) );

	if ( !main::SLIM_SERVICE ) {
		$class->registerInfoProvider( disc => (
			after => 'year',
			func  => \&infoDisc,
		) );
	}

	if ( !main::SLIM_SERVICE ) {
		$class->registerInfoProvider( compilation => (
			after => 'year',
			func  => \&infoCompilation,
		) );
	}
	
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
				$log->error( 'AlbumInfo menu item "' . $ref->{name} . '" failed: not an arrayref or hashref' );
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
		cover => '/music/' . $album->artwork . '/cover.jpg',
	};
}

sub infoContributors {
	my ( $client, $url, $album, $remoteMeta ) = @_;
	
	my $items = [];
	
	if ( $remoteMeta->{artist} ) {
		push @{$items}, {
			type =>  'text',
			name =>  $remoteMeta->{artist},
			label => 'ARTIST',
		};
	}
	else {
		# Loop through the contributor types and append
		for my $role ( sort Slim::Schema::Contributor->contributorRoles ) {
			for my $contributor ( $album->artistsForRoles($role) ) {
				my $id = $contributor->id;
				
				
				my %actions = (
					allAvailableActionsDefined => 1,
					items => {
						command     => ['browselibrary', 'items'],
						fixedParams => { mode => 'albums', artist_id => $id },
					},
					play => {
						command     => ['playlistcontrol'],
						fixedParams => {cmd => 'load', artist_id => $id},
					},
					add => {
						command     => ['playlistcontrol'],
						fixedParams => {cmd => 'add', artist_id => $id},
					},
					insert => {
						command     => ['playlistcontrol'],
						fixedParams => {cmd => 'insert', artist_id => $id},
					},								
				);
				$actions{'playall'} = $actions{'play'};
				$actions{'addall'} = $actions{'add'};
				
				my $item = {
					type    => 'playlist',
					url     => 'blabla',
					name    => $contributor->name,
					label   => uc $role,
					itemActions => \%actions,
				};
				push @{$items}, $item;
			}
		}
	}
	
	return $items;
}

sub infoYear {
	my ( $client, $url, $album ) = @_;
	
	my $item;
	
	if ( my $year = $album->year ) {
		
		my %actions = (
			allAvailableActionsDefined => 1,
			items => {
				command     => ['browselibrary', 'items'],
				fixedParams => { mode => 'albums', year => $year },
			},
			play => {
				command     => ['playlistcontrol'],
				fixedParams => {cmd => 'load', year => $year},
			},
			add => {
				command     => ['playlistcontrol'],
				fixedParams => {cmd => 'add', year => $year},
			},
			insert => {
				command     => ['playlistcontrol'],
				fixedParams => {cmd => 'insert', year => $year},
			},								
		);
		$actions{'playall'} = $actions{'play'};
		$actions{'addall'} = $actions{'add'};

		$item = {
			type    => 'playlist',
			url     => 'blabla',
			name    => $year,
			label   => 'YEAR',
			itemActions => \%actions,
		};
	}
	
	return $item;
}

sub infoDisc {
	my ( $client, $url, $album ) = @_;
	
	my $item;
	my ($disc, $discc);
	
	if ( blessed($album) && ($disc = $album->disc) && ($discc = $album->discc) ) {
		$item = {
			type  => 'text',
			label => 'DISC',
			name  => "$disc/$discc",
		};
	}
	
	return $item;
}

sub infoDuration {
	my ( $client, $url, $album ) = @_;
	
	my $item;
	
	if ( my $duration = $album->duration ) {
		$item = {
			type  => 'text',
			label => 'ALBUMLENGTH',
			name  => $duration,
		};
	}
	
	return $item;
}

sub infoCompilation {
	my ( $client, $url, $album ) = @_;
	
	my $item;
	
	if ( $album->compilation ) {
		$item = {
			type  => 'text',
			label => 'COMPILATION',
			name  => cstring($client,'YES'),
		};
	}
	
	return $item;
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
		name => cstring($client, 'SHOW_ARTWORK_SINGLE'),
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
	};
	$actions->{play} = $actions->{go};

	$jive->{actions} = $actions;
	$jive->{style} = 'itemplay';

	push @{$items}, {
		type => 'text',
		name => $play_string,
		jive => $jive, 
	};
	
	return $items;
}
	
sub addAlbumEnd {
	my ( $client, $url, $album, $remoteMeta, $tags ) = @_;
	my $add_string = cstring($client, 'ADD_TO_END');
	my $cmd = 'add';
	addAlbum( $client, $url, $album, $remoteMeta, $tags, $add_string, $cmd );
}

sub addAlbumNext {
	my ( $client, $url, $album, $remoteMeta, $tags ) = @_;
	my $add_string = cstring($client, 'PLAY_NEXT');
	my $cmd = 'insert';
	addAlbum( $client, $url, $album, $remoteMeta, $tags, $add_string, $cmd );
}

sub addAlbum {
	my ( $client, $url, $album, $remoteMeta, $tags, $add_string, $cmd ) = @_;

	my $items = [];
	my $jive;
	
	my $actions = {
		go => {
			player => 0,
			cmd => [ 'playlistcontrol' ],
			params => {
				album_id => $album->id,
				cmd => $cmd,
			},
			nextWindow => 'parent',
		},
	};
	$actions->{play} = $actions->{go};
	$actions->{add}  = $actions->{go};

	$jive->{actions} = $actions;

	push @{$items}, {
		type => 'text',
		name => $add_string,
		jive => $jive, 
	};
	
	return $items;
}

sub infoReplayGain {
	my ( $client, $url, $album ) = @_;
	
	if ( blessed($album) && $album->can('replay_gain') ) {
		if ( my $albumreplaygain = $album->replay_gain ) {
			my $noclip = Slim::Player::ReplayGain::preventClipping( $albumreplaygain, $album->replay_peak );
			my %item = (
				type  => 'text',
				label => 'ALBUMREPLAYGAIN',
				name  => sprintf( "%2.2f dB", $albumreplaygain),
			);
			if ( $noclip < $albumreplaygain ) {
				# Gain was reduced to avoid clipping
				$item{'name'} .= sprintf( " (%s)",
						cstring( $client, 'REDUCED_TO_PREVENT_CLIPPING', sprintf( "%2.2f dB", $noclip ) ) ); 
			}
			return \%item;
		}
	}
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
