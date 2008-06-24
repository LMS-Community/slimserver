package Slim::Menu::TrackInfo;

# $Id$

# SqueezeCenter Copyright 2001-2008 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

# Provides OPML-based extensible menu for track info
# Based on a patch from Justin Fletcher <gerph@gerph.org> (Bug 6930)

=head1 NAME

Slim::Menu::TrackInfo

=head1 DESCRIPTION

Provides a dynamic OPML-based track info menu to all UIs and allows
plugins to register additional menu items.

=cut

use strict;

use Scalar::Util qw(blessed);

use Slim::Utils::Log;

my $log = logger('menu.trackinfo');

my %infoProvider;
my @infoOrdering;

sub init {
	my $class = shift;
	
	# Our information providers are pluggable, call the 
	# registerInfoProvider function to extend the details
	# provided in the track info menu.
	$class->registerDefaultInfoProviders();
}

##
# Register all the information providers that we provide.
# This order is defined at http://wiki.slimdevices.com/index.php/UserInterfaceHierarchy
#
sub registerDefaultInfoProviders {
	my $class = shift;
	
	# The 'top', 'middle' and 'bottom' groups
	# so that we can add items in absolute positions
    $class->registerInfoProvider( top    => ( isa => '' ) );
    $class->registerInfoProvider( middle => ( isa => '' ) );
    $class->registerInfoProvider( bottom => ( isa => '' ) );

	$class->registerInfoProvider( playtrack => (
		menuMode  => 1,
		before    => 'addtrack',
		func      => \&playTrack,
	) );

	$class->registerInfoProvider( addtrack => (
		menuMode  => 1,
		before    => 'contributors',
		func      => \&addTrack,
	) );

	$class->registerInfoProvider( artwork => (
		menuMode  => 1,
		after     => 'year',
		func      => \&showArtwork,
	) );

	$class->registerInfoProvider( contributors => (
		after => 'top',
		func  => \&infoContributors,
	) );

	$class->registerInfoProvider( album => (
		after => 'contributors',
		func  => \&infoAlbum,
	) );

	$class->registerInfoProvider( genres => (
		after => 'album',
		func  => \&infoGenres,
	) );

	$class->registerInfoProvider( year => (
		after => 'genres',
		func  => \&infoYear,
	) );
	
	# XXX: Show Artwork (Jive only)
	
	$class->registerInfoProvider( comment => (
		after => 'year',
		func  => \&infoComment,
	) );
	
	$class->registerInfoProvider( moreinfo => (
		after => 'comment',
		func  => \&infoMoreInfo,
	) );
	
	$class->registerInfoProvider( tracknum => (
		parent => 'moreinfo',
		after  => 'moreinfo',
		func   => \&infoTrackNum,
	) );

	$class->registerInfoProvider( type => (
		parent => 'moreinfo',
		after  => 'tracknum',
		func   => \&infoContentType,
	) );

	$class->registerInfoProvider( duration => (
		parent => 'moreinfo',
		after  => 'type',
		func   => \&infoDuration,
	) );

	$class->registerInfoProvider( replaygain => (
		parent => 'moreinfo',
		after  => 'duration',
		func   => \&infoReplayGain,
	) );

	$class->registerInfoProvider( rating => (
		parent => 'moreinfo',
		after  => 'replaygain',
		func   => \&infoRating,
	) );

	$class->registerInfoProvider( bitrate => (
		parent => 'moreinfo',
		after  => 'rating',
		func   => \&infoBitrate,
	) );
	
	$class->registerInfoProvider( samplerate => (
		parent => 'moreinfo',
		after  => 'bitrate',
		func   => \&infoSampleRate,
	) );
	
	$class->registerInfoProvider( samplesize => (
		parent => 'moreinfo',
		after  => 'samplerate',
		func   => \&infoSampleSize,
	) );

	$class->registerInfoProvider( filesize => (
		parent => 'moreinfo',
		after  => 'samplesize',
		func   => \&infoFileSize,
	) );

	$class->registerInfoProvider( url => (
		parent => 'moreinfo',
		after  => 'filesize',
		func   => \&infoUrl,
	) );

	$class->registerInfoProvider( modtime => (
		parent => 'moreinfo',
		after  => 'url',
		func   => \&infoFileModTime,
	) );
	
	$class->registerInfoProvider( tagversion => (
		parent => 'moreinfo',
		after  => 'modtime',
		func   => \&infoTagVersion,
	) );
	
	# XXX: Create Mix (from MusicIP plugin)
}

=head1 METHODS

=head2 Slim::Menu::TrackInfo->registerInfoProvider( $name, %details )

Register a new menu provider to be displayed in Track Info.

  Slim::Menu::TrackInfo->registerInfoProvider( album => (
      after => 'artist',
      func  => \&infoAlbum,
  ) );

=over 4

=item $name

The name of the menu provider.  This must be unique within the server, so
you should prefix it with your plugin's namespace.

=item %details

after: Place this menu after the given menu item.

before: Place this menu before the given menu item.

func: Callback to produce the menu.  Is passed $client, $url, $track, $remoteMeta.

The special values 'top', 'middle', and 'bottom' may be used if you don't
want exact placement in the menu.

=back

=cut

sub registerInfoProvider {
	my ( $class, $name, %details ) = @_;

	$details{name} = $name; # For diagnostic purposes
	
	if (
		   !defined $details{after}
		&& !defined $details{before}
		&& !defined $details{isa}
	) {
		# If they didn't say anything about where it goes,
		# place it in the middle.
		$details{isa} = 'middle';
	}
	
	$infoProvider{$name} = \%details;

	# Clear the array to force it to be rebuilt
	@infoOrdering = ();
}

=head2 Slim::Menu::TrackInfo->deregisterInfoProvider( $name )

Removes the given menu from Track Info.  Core menus can be removed,
but you should only do this if you know what you are doing.

=cut

sub deregisterInfoProvider {
	my ( $class, $name ) = @_;
	
	delete $infoProvider{$name};

	# Clear the array to force it to be rebuilt
	@infoOrdering = ();
}

sub menu {
	my ( $class, $client, $url, $track, $tags ) = @_;
	$tags ||= {};

	# If we don't have an ordering, generate one.
	# This will be triggered every time a change is made to the
	# registered information providers, but only then. After
	# that, we will have our ordering and only need to step
	# through it.
	if ( !scalar @infoOrdering ) {
		# We don't know what order the entries should be in,
		# so work that out.
		$class->generateInfoOrderingItem( 'top' );
		$class->generateInfoOrderingItem( 'middle' );
		$class->generateInfoOrderingItem( 'bottom' );
	}
	
	# Get track object if necessary
	if ( !blessed($track) ) {
		$track = Slim::Schema->rs('Track')->objectForUrl( {
			url => $url,
		} );
		if ( !blessed($track) ) {
			$log->error( "No track object found for $url" );
			return;
		}
	}
	
	# Get plugin metadata for remote tracks
	my $remoteMeta = {};
	if ( $track->remote ) {
		my $handler = Slim::Player::ProtocolHandlers->handlerForURL($url);
		if ( $handler && $handler->can('getMetadataFor') ) {
			$remoteMeta = $handler->getMetadataFor( $client, $url );
		}
	}
	
	# Function to add menu items
	my $addItem = sub {
		my ( $ref, $items ) = @_;
		
		if ( defined $ref->{func} ) {
			
			my $item = eval { $ref->{func}->( $client, $url, $track, $remoteMeta, $tags ) };
			if ( $@ ) {
				$log->error( 'TrackInfo menu item "' . $ref->{name} . '" failed: ' . $@ );
				next;
			}
			
			next unless defined $item;
			# skip jive-only items for non-jive UIs
			next if $ref->{menuMode} && !$tags->{menuMode};
			# show artwork item to jive only if artwork exists
			next if $ref->{menuMode} && $tags->{menuMode} && $ref->{name} eq 'artwork' && !$track->coverArtExists;
			
			if ( ref $item eq 'ARRAY' ) {
				if ( scalar @{$item} ) {
					push @{$items}, @{$item};
				}
			}
			elsif ( ref $item eq 'HASH' ) {
				next if $ref->{menuMode} && !$tags->{menuMode};
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
	
	for my $ref ( @infoOrdering ) {
		# Skip items with a defined parent, they are handled
		# as children below
		next if $ref->{parent};
		
		# Add the item
		$addItem->( $ref, $items );
		
		# Look for children of this item
		my @children = grep {
			$_->{parent} && $_->{parent} eq $ref->{name}
		} @infoOrdering;
		
		if ( @children ) {
			my $subitems = $items->[-1]->{items} = [];
			
			for my $child ( @children ) {
				$addItem->( $child, $subitems );
			}
		}
	}
	
	return {
		name  => Slim::Music::Info::getCurrentTitle( $client, $url ),
		type  => 'opml',
		items => $items,
		cover => $remoteMeta->{cover} || $remoteMeta->{icon} || '/music/' . $track->id . '/cover.jpg',
	};
}

##
# Adds an item to the ordering list, following any
# 'after', 'before' and 'isa' requirements that the
# registered providers have requested.
#
# @param[in]  $client   The client we're ordering for
# @param[in]  $name     The name of the item to add
# @param[in]  $previous The item before this one, for 'before' processing
sub generateInfoOrderingItem {
	my ( $class, $name, $previous ) = @_;

	# Check for the 'before' items which are 'after' the last item
	if ( defined $previous ) {
		for my $item (
			sort { $a cmp $b }
			grep {
				   defined $infoProvider{$_}->{after}
				&& $infoProvider{$_}->{after} eq $previous
				&& defined $infoProvider{$_}->{before}
				&& $infoProvider{$_}->{before} eq $name
			} keys %infoProvider
		) {
			$class->generateInfoOrderingItem( $item, $previous );
		}
	}

	# Now the before items which are just before this item
	for my $item (
		sort { $a cmp $b }
		grep {
			   !defined $infoProvider{$_}->{after}
			&& defined $infoProvider{$_}->{before}
			&& $infoProvider{$_}->{before} eq $name
		} keys %infoProvider
	) {
		$class->generateInfoOrderingItem( $item, $previous );
	}

	# Add the item itself
	push @infoOrdering, $infoProvider{$name};

	# Now any items that are members of the group
	for my $item (
		sort { $a cmp $b }
		grep {
			   defined $infoProvider{$_}->{isa}
			&& $infoProvider{$_}->{isa} eq $name
		} keys %infoProvider
	) {
		$class->generateInfoOrderingItem( $item );
	}

	# Any 'after' items
	for my $item (
		sort { $a cmp $b }
		grep {
			   defined $infoProvider{$_}->{after}
			&& $infoProvider{$_}->{after} eq $name
			&& !defined $infoProvider{$_}->{before}
		} keys %infoProvider
	) {
		$class->generateInfoOrderingItem( $item, $name );
	}
}

# XXX: No MusicIP support here (play-hold)

sub infoContributors {
	my ( $client, $url, $track, $remoteMeta ) = @_;
	
	my $items = [];
	
	if ( $remoteMeta->{artist} ) {
		push @{$items}, {
			type => 'text',
			name => $client->string('ARTIST') . ': ' . $remoteMeta->{artist},
		};
	}
	else {
		# Loop through the contributor types and append
		for my $role ( sort $track->contributorRoles ) {
			for my $contributor ( $track->contributorsOfType($role) ) {
				my $id = $contributor->id;
				
				# XXX: Ideally this would point to another OPML provider like
				# Slim::Menu::Library::Contributor
				push @{$items}, {
					type => 'db',
					name => $client->string( uc $role ) . ': ' . $contributor->name,
					db   => {
						hierarchy         => 'contributor,album,track',
						level             => 1,
						findCriteria      => {
							'contributor.id'   => $id,
							'contributor.role' => $role,
						},
						selectionCriteria => {
							'track.id'       => $track->id,
							'album.id'       => ( blessed $track->album ) ? $track->album->id : undef,
							'contributor.id' => $id,
						},
					},
					jive => {
						actions => {
							go => {
								cmd    => [ 'albums' ],
								params => {
									menu      => 'track',
									menu_all  => 1,
									artist_id => $id,
								},
							},
							play => {
								player => 0,
								cmd    => [ 'playlistcontrol' ],
								params => {
									cmd       => 'load',
									artist_id => $id,
								},
							},
							add => {
								player => 0,
								cmd    => [ 'playlistcontrol' ],
								params => {
									cmd       => 'add',
									artist_id => $id,
								},
							},
							'add-hold' => {
								player => 0,
								cmd    => [ 'playlistcontrol' ],
								params => {
									cmd       => 'insert',
									artist_id => $id,
								},
							},
						},
						window => {
							titleStyle => 'artists',
							menuStyle  => 'album',
							text       => $contributor->name,
						},
					},
				};
			}
		}
	}
	
	return $items;
}

sub showArtwork {
	my ( $client, $url, $track, $remoteMeta, $tags ) = @_;
	my $items = [];
	my $jive;
	my $actions = {
		do => {
			cmd => [ 'artwork', $track->id ],
		},
	};
	$jive->{actions} = $actions;
	$jive->{showBigArtwork} = 1;

	push @{$items}, {
		type => 'text',
		name => $client->string('SHOW_ARTWORK'),
		jive => $jive, 
	};
	
	return $items;
}

sub playTrack {
	my ( $client, $url, $track, $remoteMeta, $tags ) = @_;
	playAddTrack( $client, $url, $track, $remoteMeta, $tags, 'play');
}
	
sub addTrack {
	my ( $client, $url, $track, $remoteMeta, $tags ) = @_;
	playAddTrack( $client, $url, $track, $remoteMeta, $tags, 'add');
}

sub playAddTrack {
	my ( $client, $url, $track, $remoteMeta, $tags, $action ) = @_;
	my $items = [];
	my $jive;
	
	my ($play_string, $add_string, $delete_string, $jump_string);
	if ( $track->remote ) {
		$play_string   = $client->string('PLAY');
		$add_string    = $client->string('ADD');
		$delete_string = $client->string('REMOVE_FROM_PLAYLIST');
		$jump_string   = $client->string('PLAY');
	} else {
		$play_string   = $client->string('JIVE_PLAY_THIS_SONG');
		$add_string    = $client->string('JIVE_ADD_THIS_SONG');
		$delete_string = $client->string('REMOVE_FROM_PLAYLIST');
		$jump_string   = $client->string('JIVE_PLAY_THIS_SONG');
	}	

	# setup hash for different items between play and add
	my $menuItems = {
		play => {
			string  => $play_string,
			style   => 'itemplay',
			command => [ 'playlistcontrol' ],
			cmd     => 'load',
		},
		add => {
			string  => $add_string,
			style   => 'itemadd',
			command => [ 'playlistcontrol' ],
			cmd     => 'add',
		},
		'add-hold' => {
			string  => $add_string,
			style   => 'itemadd',
			command => [ 'playlistcontrol' ],
			cmd     => 'insert',
		},
		delete => {
			string  => $delete_string,
			style   => 'item',
			command => [ 'playlist', 'delete', $tags->{playlistIndex} ],
		},
		jump => {
			string  => $jump_string,
			style   => 'itemplay',
			command => [ 'playlist', 'jump', $tags->{playlistIndex} ],
		},
	};

	if ( $tags->{menuContext} eq 'playlist' ) {
		if ( $action eq 'play' ) {
			$action = 'jump';
		} elsif ( $action eq 'add' ) {
			$action = 'delete';
		}
	}

	my $actions = {
		do => {
			player => 0,
			cmd => $menuItems->{$action}{command},
		},
		play => {
			player => 0,
			cmd => $menuItems->{$action}{command},
		},
		add => {
			player => 0,
			cmd    => $menuItems->{add}{command},
		},
	};
	# tagged params are sent for play and add, not delete/jump
	if ($action ne 'delete' && $action ne 'jump') {
		$actions->{'add-hold'} = {
			player => 0,
			cmd => $menuItems->{'add-hold'}{command},
		};
		$actions->{'add'}{'params'} = {
			cmd => $menuItems->{add}{cmd},
			track_id => $track->id,
		};
		$actions->{'add-hold'}{'params'} = {
			cmd => $menuItems->{'add-hold'}{cmd},
			track_id => $track->id,
		};
		$actions->{'do'}{'params'} = {
			cmd => $menuItems->{$action}{cmd},
			track_id => $track->id,
		};
		$actions->{'play'}{'params'} = {
			cmd => $menuItems->{$action}{cmd},
			track_id => $track->id,
		};
	
	} else {
		$jive->{nextWindow} = 'playlist';
	}
	$jive->{actions} = $actions;
	$jive->{style} = $menuItems->{$action}{style};

	push @{$items}, {
		type => 'text',
		name => $menuItems->{$action}{string},
		jive => $jive, 
	};
	
	return $items;
}

sub infoAlbum {
	my ( $client, $url, $track, $remoteMeta ) = @_;
	
	my $item;
	
	if ( $remoteMeta->{album} ) {
		$item = {
			type => 'text',
			name => $client->string('ALBUM') . ': ' . $remoteMeta->{album},
		};
	}
	elsif ( my $album = $track->album ) {
		my $id = $album->id;
		
		$item = {
			type => 'db',
			name => $client->string('ALBUM') . ': ' . $album->name,
			db   => {
				hierarchy         => 'album,track',
				level             => 1,
				findCriteria      => { 
					'album.id'       => $id,
					'contributor.id' => ( blessed $track->artist ) ? $track->artist->id : undef,
				},
				selectionCriteria => {
					'track.id'       => $track->id,
					'album.id'       => $id,
					'contributor.id' => ( blessed $track->artist ) ? $track->artist->id : undef,
				},
			},
			jive => {
				actions => {
					go => {
						cmd    => [ 'tracks' ],
						params => {
							menu     => 'songinfo',
							menu_all => 1,
							album_id => $id,
							sort     => 'tracknum',
						},
					},
					play => {
						player => 0,
						cmd    => [ 'playlistcontrol' ],
						params => {
							cmd      => 'load',
							album_id => $id,
						},
					},
					add => {
						player => 0,
						cmd    => [ 'playlistcontrol' ],
						params => {
							cmd      => 'add',
							album_id => $id,
						},
					},
					'add-hold' => {
						player => 0,
						cmd    => [ 'playlistcontrol' ],
						params => {
							cmd      => 'insert',
							album_id => $id,
						},
					},
				},
				window => {
					titleStyle => 'album',
					'icon-id'  => $track->id,
					text       => $album->name,
				},
			},
		};
	}
	
	return $item;
}

sub infoGenres {
	my ( $client, $url, $track ) = @_;
	
	my $items = [];
	
	for my $genre ( $track->genres ) {
		my $id = $genre->id;
		
		push @{$items}, {
			type => 'db',
			name => $client->string('GENRE') . ': ' . $genre->name,
			db   => {
				hierarchy         => 'genre,contributor,album,track',
				level             => 1,
				findCriteria      => {
					'genre.id' => $id,
				},
				selectionCriteria => {
					'track.id'       => $track->id,
					'album.id'       => ( blessed $track->album ) ? $track->album->id : undef,
					'contributor.id' => ( blessed $track->artist ) ? $track->artist->id : undef,
				},
			},
			jive => {
				actions => {
					go => {
						cmd    => [ 'artists' ],
						params => {
							menu     => 'album',
							menu_all => 1,
							genre_id => $id,
						},
					},
					play => {
						player => 0,
						cmd    => [ 'playlistcontrol' ],
						params => {
							cmd      => 'load',
							genre_id => $id,
						},
					},
					add => {
						player => 0,
						cmd    => [ 'playlistcontrol' ],
						params => {
							cmd      => 'add',
							genre_id => $id,
						},
					},
				},
				window => {
					titleStyle => 'genres',
					text       => $genre->name,
				}, 
			},
		};
	}
	
	return $items;
}

sub infoYear {
	my ( $client, $url, $track ) = @_;
	
	my $item;
	
	if ( my $year = $track->year ) {
		$item = {
			type => 'db',
			name => $client->string('YEAR') . ": $year",
			db   => {
				hierarchy         => 'year,album,track',
				level             => 1,
				findCriteria      => {
					'year.id' => $year,
				},
				selectionCriteria => {
					'track.id'       => $track->id,
					'album.id'       => ( blessed $track->album ) ? $track->album->id : undef,
					'contributor.id' => ( blessed $track->artist ) ? $track->artist->id : undef,
				},
			},
			jive => {
				actions => {
					go => {
						cmd         => [ 'albums' ],
						itemsParams => 'params',
						params => {
							year     => $year,
							menu     => 'track',
							menu_all => 1,
						},
					},
					play => {
						player      => 0,
						itemsParams => 'params',
						cmd         => [ 'playlistcontrol' ],
						params      => {
							year => $year,
							cmd  => 'load',
						},
					},
					add => {
						player      => 0,
						itemsParams => 'params',
						cmd         => [ 'playlistcontrol' ],
						params      => {
							year => $year,
							cmd  => 'add',
						},
					},
					'add-hold' => {
						player      => 0,
						itemsParams => 'params',
						cmd         => [ 'playlistcontrol' ],
						params      => {
							year => $year,
							cmd  => 'insert',
						},
					},
				},
				window => {
					menuStyle  => 'album',
					titleStyle => 'years',
				},
			},
		};
	}
	
	return $item;
}

sub infoComment {
	my ( $client, $url, $track ) = @_;
	
	my $item;
	
	if ( my $comment = $track->comment ) {
		$item = {
			name  => $client->string('COMMENT'),
			items => [
				{
					type => 'text',
					wrap => 1,
					name => $comment,
				},
			],
		};
	}
	
	return $item;
}

sub infoMoreInfo {
	my ( $client, $url, $track ) = @_;
	
	return {
		name => $client->string('MOREINFO'),
	};
}

sub infoTrackNum {
	my ( $client, $url, $track ) = @_;
	
	my $item;
	
	if ( my $tracknum = $track->tracknum ) {
		$item = {
			type => 'text',
			name => $client->string('TRACK') . ": $tracknum",
		};
	}
	
	return $item;
}
			
sub infoContentType {
	my ( $client, $url, $track ) = @_;
	
	my $item;
	
	if ( my $ct = Slim::Schema->contentType($track) ) {
		if ( $track->remote && Slim::Music::Info::isPlaylist( $track, $ct ) )  {
			if ( my $entry = $client->masterOrSelf->remotePlaylistCurrentEntry ) {
				$ct = $entry->content_type;
			}
		}
		
		$item = {
			type => 'text',
			name => $client->string('TYPE') . ': ' . $client->string( uc($ct) ),
		};
	}
	
	return $item;
}

sub infoDuration {
	my ( $client, $url, $track ) = @_;
	
	my $item;
	
	if ( my $duration = $track->duration ) {
		$item = {
			type => 'text',
			name => $client->string('LENGTH') . ": $duration",
		};
	}
	
	return $item;
}

sub infoReplayGain {
	my ( $client, $url, $track ) = @_;
	
	my $items = [];
	
	my $album = $track->album;
	
	if ( my $replaygain = $track->replay_gain ) {
		push @{$items}, {
			type => 'text',
			name => $client->string('REPLAYGAIN') . ': ' . sprintf( "%2.2f", $replaygain ) . ' dB',
		};
	}
	
	if ( blessed($album) && $album->can('replay_gain') ) {
		if ( my $albumreplaygain = $album->replay_gain ) {
			push @{$items}, {
				type => 'text',
				name => $client->string('ALBUMREPLAYGAIN') . ': ' . sprintf( "%2.2f", $albumreplaygain ) . ' dB',
			};
		}
	}
	
	return $items;
}

sub infoRating {
	my ( $client, $url, $track ) = @_;
	
	my $item;
	
	if ( my $rating = $track->rating ) {
		$item = {
			type => 'text',
			name => $client->string('RATING') . ': ' . sprintf( "%d", $rating ) . ' /100',
		};
	}
	
	return $item;
}

sub infoBitrate {
	my ( $client, $url, $track ) = @_;
	
	my $item;
	
	if ( my $bitrate = ( Slim::Music::Info::getCurrentBitrate($track->url) || $track->prettyBitRate ) ) {
		
		# A bitrate of -1 is set by Scanner::scanBitrate or Formats::*::scanBitrate when the
		# bitrate of a remote stream can't be determined
		if ( $bitrate ne '-1' ) {
			my $undermax = Slim::Player::TranscodingHelper::underMax($client, $track->url);
			my $rate     = $bitrate;
			my $convert  = '';

			if ( !$undermax ) {

				$rate = Slim::Utils::Prefs::maxRate($client) . $client->string('KBPS') . " ABR";
			}

			# XXX: used to be shown only if modeParam 'current' was set
			if ( defined $undermax && !$undermax ) { 
				$convert = sprintf( '(%s %s)', $client->string('CONVERTED_TO'), $rate );
			}
			
			$item = {
				type => 'text',
				name => sprintf( "%s: %s %s",
					$client->string('BITRATE'), $bitrate, $convert,
				),
			};
		}
	}
	
	return $item;
}

sub infoSampleRate {
	my ( $client, $url, $track ) = @_;
	
	my $item;
	
	if ( $track->samplerate ) {
		$item = {
			type => 'text',
			name => $client->string('SAMPLERATE') . ': ' . $track->prettySampleRate,
		};
	}
	
	return $item;
}

# XXX: never stored??
sub infoSampleSize {
	my ( $client, $url, $track ) = @_;
	
	my $item;
	
	if ( my $samplesize = $track->samplesize ) {
		$item = {
			type => 'text',
			name => $client->string('SAMPLESIZE') . ": $samplesize " . $client->string('BITS'),
		};
	}
	
	return $item;
}

sub infoFileSize {
	my ( $client, $url, $track ) = @_;
	
	my $item;
	
	if ( my $len = $track->filesize ) {
		$item = {
			type => 'text',
			name => $client->string('FILELENGTH') . ': ' . Slim::Utils::Misc::delimitThousands($len),
		};
	}
	
	return $item;
}

sub infoUrl {
	my ( $client, $url, $track ) = @_;
	
	my $item;
	
	if ( my $turl = $track->url ) {
		$item = {
			type => 'text',
			name => 'URL: ' . Slim::Utils::Misc::unescape($turl),
		};
	}
	
	return $item;
}

sub infoFileModTime {
	my ( $client, $url, $track ) = @_;
	
	my $item;
	
	if ( !$track->remote ) {
		if ( my $age = $track->modificationTime ) {
			$item = {
				type => 'text',
				name => $client->string('MODTIME') . ": $age",
			};
		}
	}
	
	return $item;
}

sub infoTagVersion {
	my ( $client, $url, $track ) = @_;
	
	my $item;
	
	if ( my $ver = $track->tagversion ) {
		$item = {
			type => 'text',
			name => $client->string('TAGVERSION') . ": $ver",
		};
	}
	
	return $item;
}

=head1 CREATING MENUS

Menus must be returned in the internal hashref format used for representing OPML.  Each
provider may also return more than one menu item by returning an arrayref.

=head2 EXAMPLES

=over 4

=item Text item, no actions

  {
      type => 'text',
      name => 'Rating: *****',
  }

=item Item with submenu containing one text item

  {
      name => 'More Info',
      items => [
          {
	          type => 'text',
	          name => 'Bitrate: 128kbps',
	      },
	  ],
  }

=item Item using a callback to perform some action in a plugin

  {
      name        => 'Perform Some Action',
      url         => \&myAction,
      passthrough => [ $foo, $bar ], # optional
  }

  sub myAction {
      my ( $client, $callback, $foo, $bar ) = @_;

      my $menu = {
          type => 'text',
          name => 'Results: ...',
      };
	
      return $callback->( $menu );
  }

=back

=cut

1;
