package Slim::Menu::TrackInfo;

# $Id$

# Logitech Media Server Copyright 2001-2011 Logitech.
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

use base qw(Slim::Menu::Base);

use Scalar::Util qw(blessed);

use Slim::Utils::Log;
use Slim::Utils::Strings qw(cstring);
use Slim::Utils::Prefs;

my $log = logger('menu.trackinfo');
my $prefs = preferences('server');

sub init {
	my $class = shift;
	$class->SUPER::init();
	
	Slim::Control::Request::addDispatch(
		[ 'trackinfo', 'items', '_index', '_quantity' ],
		[ 0, 1, 1, \&cliQuery ]
	);
	
	Slim::Control::Request::addDispatch(
		[ 'trackinfo', 'playlist', '_method' ],
		[ 1, 1, 1, \&cliPlaylistCmd ]
	);
}

sub name {
	return 'SONG_INFO';
}

my $emptyItemList = [{ignore => 1}];

##
# Register all the information providers that we provide.
# This order is defined at http://wiki.slimdevices.com/index.php/UserInterfaceHierarchy
#
sub registerDefaultInfoProviders {
	my $class = shift;
	
	$class->SUPER::registerDefaultInfoProviders();

	$class->registerInfoProvider( addtrack => (
		menuMode  => 1,
		after     => 'top',
		func      => \&addTrackEnd,
	) );

	$class->registerInfoProvider( addtracknext => (
		menuMode  => 1,
		before    => 'playitem',
		func      => \&addTrackNext,
	) );

	$class->registerInfoProvider( playitem => (
		menuMode  => 1,
		before    => 'contributors',
		func      => \&playTrack,
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

	if ( !main::SLIM_SERVICE ) {
		$class->registerInfoProvider( album => (
			after => 'contributors',
			func  => \&infoAlbum,
		) );

		$class->registerInfoProvider( genres => (
			after => 'album',
			func  => \&infoGenres,
		) );
	}

	$class->registerInfoProvider( remotetitle => (
		after => main::SLIM_SERVICE ? 'top' : 'album',
		func  => \&infoRemoteTitle,
	) );
	
	if ( !main::SLIM_SERVICE ) {
		$class->registerInfoProvider( year => (
			after => 'genres',
			func  => \&infoYear,
		) );

		$class->registerInfoProvider( comment => (
			after => 'year',
			func  => \&infoComment,
		) );

		$class->registerInfoProvider( lyrics => (
			after => 'comment',
			func  => \&infoLyrics,
		) );
	}
	
	$class->registerInfoProvider( moreinfo => (
		after => main::SLIM_SERVICE ? 'remotetitle' : 'comment',
		func  => \&infoMoreInfo,
	) );
	
	$class->registerInfoProvider( tracknum => (
		parent => 'moreinfo',
		after  => 'moreinfo',
		func   => \&infoTrackNum,
	) );
	
	$class->registerInfoProvider( disc => (
		parent => 'moreinfo',
		after  => 'moreinfo',
		func   => \&infoDisc,
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
	
	$class->registerInfoProvider( tagdump => (
		parent => 'moreinfo',
		after  => 'tagversion',
		func   => \&infoTagDump,
	) );	
}

sub menu {
	my ( $class, $client, $url, $track, $tags ) = @_;
	$tags ||= {};
	
	# Protocol Handlers can define their own track info OPML menus
	if ( $url ) {
		my $handler = Slim::Player::ProtocolHandlers->handlerForURL( $url );
		if ( $handler && $handler->can('trackInfoURL') ) {
			my $feed = $handler->trackInfoURL( $client, $url );
			return $feed if $feed;
		}
	}
	
	# If we don't have an ordering, generate one.
	# This will be triggered every time a change is made to the
	# registered information providers, but only then. After
	# that, we will have our ordering and only need to step
	# through it.
	my $infoOrdering = $class->getInfoOrdering;
	
	# Get track object if necessary
	if ( !blessed($track) ) {
		$track = Slim::Schema->objectForUrl( {
			url => $url,
		} );
		if ( !blessed($track) ) {
			$log->error( "No track object found for $url" );
			return;
		}
	}
	
	# Get plugin metadata for remote tracks
	my $remoteMeta = {};
	if ( $track->remote && blessed($client) ) {
		my $handler = Slim::Player::ProtocolHandlers->handlerForURL($url);
		if ( $handler && $handler->can('getMetadataFor') ) {
			$remoteMeta = $handler->getMetadataFor( $client, $url );
		}
	}
	
	# Function to add menu items
	my $addItem = sub {
		my ( $ref, $items ) = @_;
		
		if ( defined $ref->{func} ) {
			
			# skip jive-only items for non-jive UIs
			return if $ref->{menuMode} && !$tags->{menuMode};
			
			# show artwork item to jive only if artwork exists
			return if $ref->{menuMode} && $tags->{menuMode} && $ref->{name} eq 'artwork' && !$track->coverArtExists;
			
			my $item = eval { $ref->{func}->( $client, $url, $track, $remoteMeta, $tags ) };
			if ( $@ ) {
				$log->error( 'TrackInfo menu item "' . $ref->{name} . '" failed: ' . $@ );
				return;
			}
			
			return unless defined $item;
			
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
		name  => $track->title || Slim::Music::Info::getCurrentTitle( $client, $url, 1 ),
		type  => 'opml',
		items => $items,
		play  => $track->url,
		cover => $remoteMeta->{cover} || $remoteMeta->{icon} || '/music/' . ($track->coverid || 0) . '/cover.jpg',
		menuComplete => 1,
	};
}


sub infoContributors {
	my ( $client, $url, $track, $remoteMeta ) = @_;
	
	my $items = [];
	
	if ( $remoteMeta->{artist} ) {
		push @{$items}, {
			type =>  'text',
			name =>  $remoteMeta->{artist},
			label => 'ARTIST',
		};
	}
	else {
		return if main::SLIM_SERVICE;
		
		my @roles = Slim::Schema::Contributor->contributorRoles;
		
		# Loop through each pref to see if the user wants to link to that contributor role.
		my %linkRoles = map {$_ => $prefs->get(lc($_) . 'InArtists')} @roles;
		$linkRoles{'ARTIST'} = 1;
		$linkRoles{'TRACKARTIST'} = 1;
		$linkRoles{'ALBUMARTIST'} = 1;
		
		# Loop through the contributor types and append
		for my $role ( @roles ) {
			for my $contributor ( $track->contributorsOfType($role) ) {
				if ($linkRoles{$role}) {
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
						info => {
							command     => ['artistinfo', 'items'],
							fixedParams => {artist_id => $id},
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
				} else {
					my $item = {
						type    => 'text',
						name    => $contributor->name,
						label   => uc $role,
					};
					push @{$items}, $item;
				}
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
		name => cstring($client, 'SHOW_ARTWORK_SINGLE'),
		jive => $jive, 
	};
	
	return $items;
}

sub playTrack {
	my ( $client, $url, $track, $remoteMeta, $tags ) = @_;
	my $items = [];
	my $jive;
	
	return $items if !blessed($client);
	
	my $play_string = cstring($client, 'PLAY');

	my $actions;

	# "Play Song" in current playlist context is 'jump'
	if ( $tags->{menuContext} eq 'playlist' ) {
		
		# do not add item if this is current track and already playing
		return $emptyItemList if $tags->{playlistIndex} == Slim::Player::Source::playingSongIndex($client)
					&& $client->isPlaying();
		
		$actions = {
			go => {
				player => 0,
				cmd => [ 'playlist', 'jump', $tags->{playlistIndex} ],
				nextWindow => 'parent',
			},
		};
		# play, add and add-hold all have the same behavior for this item
		$actions->{play} = $actions->{go};
		$actions->{add} = $actions->{go};
		$actions->{'add-hold'} = $actions->{go};

	# typical "Play Song" item
	} else {

		$actions = {
			go => {
				player => 0,
				cmd => [ 'playlistcontrol' ],
				params => {
					cmd => 'load',
					track_id => $track->id,
				},
				nextWindow => 'nowPlaying',
			},
		};
		# play is go
		$actions->{play} = $actions->{go};
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

sub addTrackNext {
	my ( $client, $url, $track, $remoteMeta, $tags ) = @_;
	my $string = cstring($client, 'PLAY_NEXT');
	my ($cmd, $playcontrol);
	if ($tags->{menuContext} eq 'playlist') {
		$cmd         = 'playlistnext';
	} else {
		$cmd         = 'insert';
		$playcontrol = 'insert'
	}
	
	return addTrack( $client, $url, $track, $remoteMeta, $tags, $string, $cmd, $playcontrol );
}

sub addTrackEnd {
	my ( $client, $url, $track, $remoteMeta, $tags ) = @_;

	my ($string, $cmd, $playcontrol);

	# "Add Song" in current playlist context is 'delete'
	if ( $tags->{menuContext} eq 'playlist' ) {
		$string      = cstring($client, 'REMOVE_FROM_PLAYLIST');
		$cmd         = 'delete';
	} else {
		$string      = cstring($client, 'ADD_TO_END');
		$cmd         = 'add';
		$playcontrol = 'add'
	}
	
	return addTrack( $client, $url, $track, $remoteMeta, $tags, $string, $cmd, $playcontrol );
}

sub addTrack {
	my ( $client, $url, $track, $remoteMeta, $tags , $string, $cmd, $playcontrol ) = @_;

	my $items = [];
	my $jive;

	return $items if !blessed($client);
	
	my $actions;
	# remove from playlist
	if ( $cmd eq 'delete' ) {
		
		# Do not add this item if only one item in playlist
		return $emptyItemList if Slim::Player::Playlist::count($client) < 2;

		$actions = {
			go => {
				player     => 0,
				cmd        => [ 'playlist', 'delete', $tags->{playlistIndex} ],
				nextWindow => 'parent',
			},
		};
		# play, add and add-hold all have the same behavior for this item
		$actions->{play} = $actions->{go};
		$actions->{add} = $actions->{go};
		$actions->{'add-hold'} = $actions->{go};

	# play next in the playlist context
	} elsif ( $cmd eq 'playlistnext' ) {
		
		# Do not add this item if only one item in playlist
		return $emptyItemList if Slim::Player::Playlist::count($client) < 2;

		my $moveTo = Slim::Player::Source::playingSongIndex($client) || 0;
		
		# do not add item if this is current track or already the next track
		return $emptyItemList if $tags->{playlistIndex} == $moveTo || $tags->{playlistIndex} == $moveTo+1;
		
		if ( $tags->{playlistIndex} > $moveTo ) {
			$moveTo = $moveTo + 1;
		}
		$actions = {
			go => {
				player     => 0,
				cmd        => [ 'playlist', 'move', $tags->{playlistIndex}, $moveTo ],
				nextWindow => 'parent',
			},
		};
		# play, add and add-hold all have the same behavior for this item
		$actions->{play} = $actions->{go};
		$actions->{add} = $actions->{go};
		$actions->{'add-hold'} = $actions->{go};


	# typical "Add Song" item
	} else {

		$actions = {
			add => {
				player => 0,
				cmd => [ 'playlistcontrol' ],
				params => {
					cmd => $cmd,
					track_id => $track->id,
				},
				nextWindow => 'parent',
			},
		};
		# play and go have same behavior as go here
		$actions->{play} = $actions->{add};
		$actions->{go} = $actions->{add};
	}

	$jive->{actions} = $actions;

	push @{$items}, {
		type        => 'text',
		playcontrol => $playcontrol,
		name        => $string,
		jive        => $jive,
	};
	
	return $items;
}

sub infoAlbum {
	my ( $client, $url, $track, $remoteMeta ) = @_;
	
	my $item;
	
	if ( $remoteMeta->{album} ) {
		$item = {
			type =>  'text',
			name =>  $remoteMeta->{album},
			label => 'ALBUM',
		};
	}
	elsif ( my $album = $track->album ) {
		my $id = $album->id;

		my %actions = (
			allAvailableActionsDefined => 1,
			items => {
				command     => ['browselibrary', 'items'],
				fixedParams => { mode => 'tracks', album_id => $id },
			},
			play => {
				command     => ['playlistcontrol'],
				fixedParams => {cmd => 'load', album_id => $id},
			},
			add => {
				command     => ['playlistcontrol'],
				fixedParams => {cmd => 'add', album_id => $id},
			},
			insert => {
				command     => ['playlistcontrol'],
				fixedParams => {cmd => 'insert', album_id => $id},
			},								
			info => {
				command     => ['albuminfo', 'items'],
				fixedParams => {album_id => $id},
			},								
		);
		$actions{'playall'} = $actions{'play'};
		$actions{'addall'} = $actions{'add'};

		$item = {
			type    => 'playlist',
			url     => 'blabla',
			name    => $album->name,
			label   => 'ALBUM',
			itemActions => \%actions,
		};
	}
	
	return $item;
}

sub infoGenres {
	my ( $client, $url, $track ) = @_;
	
	my $items = [];
	
	for my $genre ( $track->genres ) {
		my $id = $genre->id;
		
		my %actions = (
			allAvailableActionsDefined => 1,
			items => {
				command     => ['browselibrary', 'items'],
				fixedParams => { mode => 'artists', genre_id => $id },
			},
			play => {
				command     => ['playlistcontrol'],
				fixedParams => {cmd => 'load', genre_id => $id},
			},
			add => {
				command     => ['playlistcontrol'],
				fixedParams => {cmd => 'add', genre_id => $id},
			},
			insert => {
				command     => ['playlistcontrol'],
				fixedParams => {cmd => 'insert', genre_id => $id},
			},								
			info => {
				command     => ['genreinfo', 'items'],
				fixedParams => {genre_id => $id},
			},								
		);
		$actions{'playall'} = $actions{'play'};
		$actions{'addall'} = $actions{'add'};

		my $item = {
			type    => 'playlist',
			url     => 'blabla',
			name    => $genre->name,
			label   => 'GENRE',
			itemActions => \%actions,
		};
		push @{$items}, $item;
	}
	
	return $items;
}

sub infoYear {
	my ( $client, $url, $track ) = @_;
	
	my $item;
	
	if ( my $year = $track->year ) {
		
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
			info => {
				command     => ['yearinfo', 'items'],
				fixedParams => {year => $year},
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

sub infoComment {
	my ( $client, $url, $track ) = @_;
	
	my $item;
	my $comment;

	# make urls in comments into links
	for my $c ($track->comment) {

		next unless defined $c && $c !~ /^\s*$/;

		if (!($c =~ s!\b(http://[A-Za-z0-9\-_\.\!~*'();/?:@&=+$,]+)!<a href=\"$1\" target=\"_blank\">$1</a>!igo)) {

			# handle emusic-type urls which don't have http://
			$c =~ s!\b(www\.[A-Za-z0-9\-_\.\!~*'();/?:@&=+$,]+)!<a href=\"http://$1\" target=\"_blank\">$1</a>!igo;
		}

		$comment .= $c;
	}
	
	if ( $comment ) {

		$comment =~ s/\r\n/\n/g;
		$comment =~ s/\r/\n/g;
		$comment =~ s/\n\n+/\n\n/g;

		$item = {
			name  => cstring($client, 'COMMENT'),
			items => [
				{
					type => 'text',
					wrap => 1,
					name => $comment,
					label => 'COMMENT',
					
				},
			],
			
			unfold => 1,
		};
	}
	
	return $item;
}

sub infoLyrics {
	my ( $client, $url, $track ) = @_;
	
	my $item;
	
	if ( my $lyrics = $track->lyrics ) {

		$lyrics =~ s/\r\n/\n/g;
		$lyrics =~ s/\r/\n/g;
		$lyrics =~ s/\n\n+/\n\n/g;

		$item = {
			name  => cstring($client, 'LYRICS'),
			items => [
				{
					type => 'text',
					wrap => 1,
					name => $lyrics,
					label => 'LYRICS',
				},
			],
			
			unfold => 1,
		};
	}
	
	return $item;
}

sub infoMoreInfo {
	my ( $client, $url, $track ) = @_;
	
	return {
		name => cstring($client, 'MOREINFO'),
		isContextMenu => 1,
		unfold => 1,

	};
}

sub infoTrackNum {
	my ( $client, $url, $track ) = @_;
	
	my $item;
	
	if ( my $tracknum = $track->tracknum ) {
		$item = {
			type  => 'text',
			label => 'TRACK_NUMBER',
			name  => $tracknum,
		};
	}
	
	return $item;
}

sub infoDisc {
	my ( $client, $url, $track ) = @_;
	
	my $item;
	my ($disc, $discc);
	my $album = $track->album;
	
	if ( blessed($album) && ($disc = ($track->disc || $album->disc)) && ($discc = $album->discc) ) {
		$item = {
			type  => 'text',
			label => 'DISC',
			name  => "$disc/$discc",
		};
	}
	
	return $item;
}

sub infoContentType {
	my ( $client, $url, $track ) = @_;
	
	my $item;
	
	if ( my $ct = Slim::Schema->contentType($track) ) {
		if ( blessed($client) && $track->remote && Slim::Music::Info::isPlaylist( $track, $ct ) )  {
			if ( my $url = $client->master()->currentTrackForUrl( $track->url ) ) {
				$ct = Slim::Schema->contentType($url);
			}
		}
		
		if ($ct eq 'unk' && $track->remote) {
			my $handler = Slim::Player::ProtocolHandlers->handlerForURL( $url );
			if ( $handler && $handler->can('getMetadataFor') ) {
				my $meta = $handler->getMetadataFor( $client, $url );
				if ($meta && $meta->{type}) {
					$ct = $meta->{type};
				}
			}
		}

		# some plugin protocol handlers return a ct string which is not a string token
		my $ctString = Slim::Utils::Strings::stringExists($ct) ? cstring($client, uc($ct)) : $ct;

		$item = {
			type  => 'text',
			label => 'TYPE',
			name  => $ctString,
		};
	}
	
	return $item;
}

sub infoDuration {
	my ( $client, $url, $track ) = @_;
	
	my $item;
	
	if ( my $duration = $track->duration ) {
		$item = {
			type  => 'text',
			label => 'LENGTH',
			name  => $duration,
		};
	}
	
	return $item;
}

sub infoReplayGain {
	my ( $client, $url, $track ) = @_;
	
	my $items = [];
	
	my $album = $track->album;
	
	if ( my $replaygain = $track->replay_gain ) {
		push @{$items}, _replainGainItem($client, $replaygain, $track->replay_peak, 'REPLAYGAIN');
	}
	
	if ( blessed($album) && $album->can('replay_gain') ) {
		if ( my $albumreplaygain = $album->replay_gain ) {
			push @{$items}, _replainGainItem($client, $albumreplaygain, $album->replay_peak, 'ALBUMREPLAYGAIN');
		}
	}
	
	return $items;
}

sub _replainGainItem {
	my ($client, $replaygain, $replaygainpeak, $tag) = @_;
	
	my $noclip = Slim::Player::ReplayGain::preventClipping( $replaygain, $replaygainpeak );
	my %item = (
		type  => 'text',
		label => $tag,
		name  => sprintf( "%2.2f dB", $replaygain),
	);
	if ( $noclip < $replaygain ) {
		# Gain was reduced to avoid clipping
		$item{'name'} .= sprintf( " (%s)",
				cstring( $client, 'REDUCED_TO_PREVENT_CLIPPING', sprintf( "%2.2f dB", $noclip ) ) ); 
	}
	return \%item;
}

sub infoRating {
	my ( $client, $url, $track ) = @_;
	
	if ( main::SLIM_SERVICE ) {
		return;
	}
	
	my $item;
	
	if ( my $rating = Slim::Schema->rating($track) ) {
		$item = {
			type  => 'text',
			label => 'RATING',
			name  => $rating,
		};
	}
	
	return $item;
}

sub infoBitrate {
	my ( $client, $url, $track, $remoteMeta ) = @_;
	
	my $item;
	
	if ( my $bitrate = ( Slim::Music::Info::getCurrentBitrate($track->url) || $track->prettyBitRate ) ) {
		
		# A bitrate of -1 is set by Scanner::scanBitrate or Formats::*::scanBitrate when the
		# bitrate of a remote stream can't be determined
		if ( $bitrate && $bitrate ne '-1' ) {
			
			my ($song, $sourcebitrate, $streambitrate);
			my $convert = '';
			
			if (blessed($client) && ($song = $client->currentSongForUrl($track->url))
				&& ($sourcebitrate = $song->bitrate())
				&& ($streambitrate = $song->streambitrate())
				&& $sourcebitrate != $streambitrate)
			{
					$convert = sprintf( ' (%s %s%s %s)', 
						cstring($client, 'CONVERTED_TO'), 
						sprintf( "%d", $streambitrate / 1000 ),
						cstring($client, 'KBPS'),
						cstring($client, $song->streamformat())
					); 
			}
			
			$item = {
				type  => 'text',
				label => 'BITRATE',
				name  => sprintf( "%s%s", $bitrate, $convert),
			};
		}
	}
	elsif ( $remoteMeta->{bitrate} ) {
		$item = {
			type  => 'text',
			label => 'BITRATE',
			name  => $remoteMeta->{bitrate},
		}
	}
	
	return $item;
}

sub infoSampleRate {
	my ( $client, $url, $track ) = @_;
	
	my $item;
	
	if ( my $sampleRate = $track->samplerate ) {
		$item = {
			type  => 'text',
			label => 'SAMPLERATE',
			name  => sprintf('%.1f kHz', $sampleRate / 1000),
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
			type  => 'text',
			label => 'SAMPLESIZE',
			name  => $samplesize . cstring($client, 'BITS'),
		};
	}
	
	return $item;
}

sub infoFileSize {
	my ( $client, $url, $track ) = @_;
	
	my $item;
	
	if ( my $len = $track->filesize ) {
		$item = {
			type  => 'text',
			label => 'FILELENGTH',
			name  => Slim::Utils::Misc::delimitThousands($len),
		};
	}
	
	return $item;
}

sub infoRemoteTitle {
	my ( $client, $url, $track, $remoteMeta ) = @_;
	
	my $item;
	
	if ( $track->remote && $remoteMeta->{title} ) {
		$item = {
			type  => 'text',
			label => 'TITLE',
			name  => $remoteMeta->{title},
		};
	}
	
	return $item;
}

sub infoUrl {
	my ( $client, $url, $track ) = @_;
	
	my $item;
	
	if ( my $turl = $track->url ) {
		my ($tag, $name);
		if ($track->isRemoteURL($turl)) {
			$item = {
				type  => 'text',
				name  => Slim::Utils::Misc::unescape($turl),
				label => 'URL',	
			};
		} else {
			my $weblink = '/music/' . $track->id . '/download';

			if ( $track->path && $track->path =~ m|(/[^/\\]+)$| ) {
				$weblink .= $1;
			}

			$item = {
				type  => 'text',
				name  => Slim::Utils::Unicode::utf8decode_locale( Slim::Utils::Misc::pathFromFileURL($turl) ),
				label => 'LOCATION',	
				weblink => $weblink,
			};
		}
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
				label => 'MODTIME',	
				name => $age,
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
			label => 'TAGVERSION',	
			name => $ver,
		};
	}
	
	return $item;
}

sub infoTagDump {
	my ( $client, $url, $track ) = @_;
	
	my $item;
	
	if ( $track->audio ) {
		$item = {
			name        => cstring($client, 'VIEW_TAGS'),
			url         => \&tagDump,
			passthrough => [ $track->path ],
			isContextMenu => 1,
		};
	}
	
	return $item;
}

sub tagDump {
	my ( $client, $callback, undef, $path ) = @_;
	
	return unless $callback && $path;
	
	my $menu = [];
	
	require Audio::Scan;
	my $s = eval { Audio::Scan->scan_tags($path) };
	
	if ( $@ ) {
		$menu = {
			type => 'text',
			name => $@,
		};
	}
	else {	
		my $tags = $s->{tags};
		
		# Recursive handler for array-based tags
		my $array_tag;
		$array_tag = sub {
			my $tag = shift;
			
			my @array;
			
			for my $x ( @{$tag} ) {
				if ( ref $x eq 'ARRAY' ) {
					my $a = $array_tag->($x);
					$x = '[ ' . join( ', ', @{$a} ) . ' ]';
				}
				
				if ( length($x) > 256 ) {
					$x = '(' . length($x) . ' ' . cstring($client, 'BYTES') . ')';
				}
				
				push @array, $x;
			}
			
			return \@array;
		};
	
		for my $k ( sort keys %{$tags} ) {
			my $v = $tags->{$k};
		
			if ( ref $v eq 'ARRAY' ) {
				my $a = $array_tag->($v);
							
				push @{$menu}, {
					type => 'text',
					name => $k . ': [ ' . join( ', ', @{$a} ) . ' ]',
				};
			}
			else {
				if ( length($v) > 256 ) {
					$v = '(' . length($v) . ' ' . cstring($client, 'BYTES') . ')';
				}
			
				push @{$menu}, {
					type => 'text',
					name => $k . ': ' . $v,
				};
			}
		}
	
		if ( !scalar @{$menu} ) {
			$menu = {
				type => 'text',
				name => cstring($client, 'NO_TAGS_FOUND'),
			};
		}
	}
	
	$callback->( $menu );
}

my $cachedFeed;

sub cliQuery {
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
	my $trackId        = $request->getParam('track_id');
	my $menuMode       = $request->getParam('menu') || 0;
	my $menuContext    = $request->getParam('context') || 'normal';
	my $playlist_index = $request->getParam('playlist_index');
	
	# special case-- playlist_index given but no trackId
	if (defined($playlist_index) && ! $trackId ) {
		if (my $song = Slim::Player::Playlist::song( $client, $playlist_index )) {
			$trackId = $song->id;
			$url     = $song->url;
			$request->addParam('track_id', $trackId);
			$request->addParam('url', $url);
		}
	}
		
	my $tags = {
		menuMode      => $menuMode,
		menuContext   => $menuContext,
		playlistIndex => $playlist_index,
	};

	my $feed;
	
	if ( $trackId && (my $track = Slim::Schema->find( Track => $trackId )) ) {
		$feed = Slim::Menu::TrackInfo->menu( $client, $track->url, $track, $tags );
	} elsif ( $url ) {
		$feed = Slim::Menu::TrackInfo->menu( $client, $url, undef, $tags );
	}

	# sometimes we get a $trackId which wouldn't return a valid track object
	# try the song based on the playlist_index instead
	if ( !$feed && $playlist_index && (my $song = Slim::Player::Playlist::song( $client, $playlist_index )) ) {
		$feed = Slim::Menu::TrackInfo->menu( $client, $song->url, $song, $tags);
	} 
	
	if ( !$feed ) {
		$log->error("Didn't get either valid trackId or url.");
		$request->setStatusBadParams();
		return;
	}
	
	$cachedFeed = $feed if $feed;
	
	Slim::Control::XMLBrowser::cliQuery( 'trackinfo', $feed, $request );
}

sub cliPlaylistCmd {
	my $request = shift;
	
	my $client  = $request->client;
	my $method  = $request->getParam('_method');

	unless ($client && $method && $cachedFeed) {
		$request->setStatusBadParams();
		return;
	}
	
	return 	Slim::Control::XMLBrowser::cliQuery( 'trackinfo', $cachedFeed, $request );
}

1;
