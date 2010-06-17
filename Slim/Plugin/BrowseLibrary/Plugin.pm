package Slim::Plugin::BrowseLibrary::Plugin;

# $Id$


use strict;
use base 'Slim::Plugin::OPMLBased';
use Slim::Utils::Log;


my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.browse',
	'defaultLevel' => 'ERROR',
	'description'  => 'PLUGIN_BROWSE_LIBRARY_MODULE_NAME',
});

sub initSubmenu {
	my ($class, %args) = @_;
	$args{'weight'} ||= $class->weight() + 1;
	$args{'is_app'} ||= 0;
	$class->SUPER::initPlugin(%args);
}

my @submenus = (
	['Albums', 'browsealbums', 'BROWSE_BY_ALBUM', \&_albums, {
		icon => 'plugins/BrowseLibrary/html/images/albums.png',
	}],
	['Artists', 'browseartists', 'BROWSE_BY_ARTIST', \&_artists, {
		icon => 'plugins/BrowseLibrary/html/images/artists.png',
	}],
);

sub _pluginDataFor {
	my $class = shift;
	my $key   = shift;

	my $pluginData = $class->pluginData() if $class->can('pluginData');

	if ($pluginData && ref($pluginData) && $pluginData->{$key}) {
		return $pluginData->{$key};
	}

	return __PACKAGE__->SUPER::_pluginDataFor($key);
}


sub initSubmenus {
	my $class = shift;
	my $base  = __PACKAGE__;
	
	foreach my $menu (@submenus) {

		my $packageName = $base . '::' . $menu->[0];
		my $pkg = "{
			package $packageName;
			use base '$base';
			my \$pluginData;
			
			sub init {
				my (\$class, \$feed, \$data) = \@_;
				\$pluginData = \$data;
				\$class->SUPER::initSubmenu(feed => \$feed, tag => '$menu->[1]');
			}
		
			sub getDisplayName {'$menu->[2]'}	
			sub pluginData {\$pluginData}	
		}";
		
		eval $pkg;
		
		$packageName->init($menu->[3], $menu->[4]);
	}
}

sub initPlugin {
	my $class = shift;
	
	main::DEBUGLOG && $log->is_debug && $log->debug('init');
	
	$class->SUPER::initPlugin(
		feed   => \&_topLevel,
		tag    => 'browselibrary',
		menu   => 'plugins',
		weight => 15,
		is_app => 0,
	);

	$class->initSubmenus();
}


sub setMode {
	my ( $class, $client, $method ) = @_;

	if ($method eq 'pop') {

		Slim::Buttons::Common::popMode($client);
		return;
	}

	my $name  = $class->getDisplayName();
	my $title = (uc($name) eq $name) ? $client->string( $name ) : $name;
	
	my %params = (
		header   => $name,
		modeName => $name,
		url      => $class->feed( $client ),
		title    => $title,
		timeout  => 35,
		%{$client->modeParams()},
	);

	Slim::Buttons::Common::pushMode( $client, 'xmlbrowser', \%params );
	
	# we'll handle the push in a callback
	$client->modeParam( handledTransition => 1 );
}

sub _topLevel {
	my ($client, $callback, $args) = @_;
	my $params = $args->{'params'};
	
	if ($params) {
		my %args;

		if ($params->{'query'} && $params->{'query'} =~ /(\w+)=(.*)/) {
			$params->{$1} = $2;
		}

		my @searchTags;
		for (qw(track_id artist_id genre_id album_id)) {
			push (@searchTags, $_ . ':' . $params->{$_}) if $params->{$_};
		}
		$args{'searchTags'} = \@searchTags if scalar @searchTags;

		$args{'sort'} = 'sort:' . $params->{'sort'} if $params->{'sort'};
		
		if ($params->{'mode'}) {
			no strict "refs";
			
			my %entryParams;
			for (qw(track_id artist_id genre_id album_id sort mode)) {
				$entryParams{$_} = $params->{$_} if $params->{$_};
			}
			main::INFOLOG && $log->is_info && $log->info('params=>', join('&', map {$_ . '=' . $entryParams{$_}} keys(%entryParams)));
			
			my $func = '_' . $params->{'mode'};
			&$func($client,
				sub {
					my $opml = shift;
					$opml->{'query'} = \%entryParams;
					$callback->($opml, @_);
				},
				$args, \%args);
			return;
		}
	}
	
	my %topLevel = (
		url   => \&_topLevel,
		name  => _clientString($client, getDisplayName()),
		items => [
			{
				type => 'link',
				name => _clientString($client, 'BROWSE_BY_ARTIST'),
				url  => \&_artists,
				icon => '/plugins/BrowseLibrary/html/images/artists.png',
			},
			{
				type => 'link',
				name => _clientString($client, 'BROWSE_BY_ALBUM'),
				url  => \&_albums,
				icon => '/plugins/BrowseLibrary/html/images/albums.png',
			},
			{
				type => 'link',
				name => _clientString($client, 'BROWSE_BY_GENRE'),
				url  => \&_genres,
				icon => '/plugins/BrowseLibrary/html/images/genres.png',
			},
			{
				type => 'link',
				name => _clientString($client, 'BROWSE_BY_YEAR'),
				url  => \&_years,
				icon => '/plugins/BrowseLibrary/html/images/years.png',
			},
			{
				type => 'link',
				name => _clientString($client, 'BROWSE_NEW_MUSIC'),
				url  => \&_albums,
				passthrough => [ { sort => 'sort:new' } ],
				icon => '/plugins/BrowseLibrary/html/images/newmusic.png',
			},
			{
				type => 'link',
				name => _clientString($client, 'BROWSE_MUSIC_FOLDER'),
				url  => \&_bmf,
				icon => '/plugins/BrowseLibrary/html/images/musicfolder.png',
			},
			{
				type => 'link',
				name => _clientString($client, 'PLAYLISTS'),
				url  => \&_playlists,
				icon => '/plugins/BrowseLibrary/html/images/playlists.png',
			},
			{
				name  => _clientString($client, 'SEARCH'),
				icon => '/plugins/BrowseLibrary/html/images/search.png',
				items => [
					{
						type => 'search',
						name => _clientString($client, 'BROWSE_BY_ARTIST'),
						icon => '/plugins/BrowseLibrary/html/images/search.png',
						url  => \&_artists,
					},
					{
						type => 'search',
						name => _clientString($client, 'BROWSE_BY_ALBUM'),
						icon => '/plugins/BrowseLibrary/html/images/search.png',
						url  => \&_albums,
					},
					{
						type => 'search',
						name => _clientString($client, 'BROWSE_BY_SONG'),
						icon => '/plugins/BrowseLibrary/html/images/search.png',
						url  => \&_tracks,
					},
					{
						type => 'search',
						name => _clientString($client, 'PLAYLISTS'),
						icon => '/plugins/BrowseLibrary/html/images/search.png',
						url  => \&_playlists,
					},
				],
			},
		],
	);

	$callback->( \%topLevel );
}

sub _clientString {
	my ($client, $string) = @_;
	return Slim::Utils::Strings::clientString($client, $string);
}

sub _generic {
	my ($client,
		$callback,		# func ref:  Callback function to XMLbowser: callback(hashOrArray_ref)
		$query,			# string:    CLI query, single verb or array-ref;
						#            command takes _index, _quantity and tagged params
		$loopName,		# string:    name of loop variable in CLI result; usually <query>_loop
		$queryTags,		# array ref: tagged params to pass to CLI query
		$resultsFunc	# func ref:  func(ARRAYref cliLoop) returns (ARRAYref items, Bool unsorted default FALSE);
						#            function to process results loop from CLI and generate XMLBrowser items
	) = @_;
	
	my $index = 0;
	my $quantity = 0;
	
	main::INFOLOG && $log->is_info && $log->info("$query: tags ->", join(', ', @$queryTags));
	
	my $request = Slim::Control::Request->new( $client ? $client->id() : undef,
		[ (ref $query ? @$query : $query), $index, $quantity || 100000, @$queryTags ] );
	$request->execute();
	
	if ( $request->isStatusError() ) {
		$log->error($request->getStatusText());
	}

#	$log->error(Data::Dump::dump($request->getResults()));
	
	my $loop = $request->getResults()->{$loopName};
	
	my ($result, $unsorted, $extraAtEnd, $itemsContextMenu) = $resultsFunc->($loop);
	
#	$log->error(Data::Dump::dump($result));
	
	$callback->({
		total => $request->getResults()->{count} + ($extraAtEnd || 0),
		items => $result,
		sorted => !$unsorted,
		itemsContextMenu => $itemsContextMenu,
	});
	
	if ($@) {logBacktrace('$callback=', ($callback ? ref $callback : 'invalid'), ', $request=', ($request ? ref $request : 'invalid'));}
}

sub _artists {
	my ($client, $callback, $args, $pt) = @_;
	my @searchTags = $pt->{searchTags} ? @{$pt->{searchTags}} : ();
	my $search     = $pt->{'search'};
	
	_generic($client, $callback, 'artists', 'artists_loop',
		['tags:s', @searchTags, ($search ? 'search:' . $search : undef)],
		sub {
			my $loop = shift;
			my $addAll = 0;
			my @result = ( map {
				name        => $_->{artist},
				textkey     => $_->{textkey},
				type        => 'playlist',
				playlist    => \&_tracks,
				url         => \&_albums,
				passthrough => [ { searchTags => [@searchTags, "artist_id:" . $_->{id}] } ],
				contextMenuParams=> { artist_id =>  $_->{id} },
				
			}, @$loop );
			if ($pt->{addAllAlbums} && scalar @result > 1) {
				push @result, {
					name        => _clientString($client, 'ALL_ALBUMS'),
					type        => 'playlist',
					playlist    => \&_tracks,
					url         => \&_albums,
					passthrough => [{ searchTags => \@searchTags }],
				};
				$addAll = 1;
			}
			return \@result, 0, $addAll, ['artistinfo', 'items'];
		},
	);
}

sub _genres {
	my ($client, $callback, $args, $pt) = @_;
	my @searchTags = $pt->{searchTags} ? @{$pt->{searchTags}} : ();

	_generic($client, $callback, 'genres', 'genres_loop', ['tags:s', @searchTags],
		sub {
			my $loop = shift;
			my @result = ( map {
				name        => $_->{genre},
				textkey     => $_->{textkey},
				type        => 'playlist',
				playlist    => \&_tracks,
				url         => \&_artists,
				passthrough => [ { searchTags => [@searchTags, "genre_id:" . $_->{id}], addAllAlbums => 1 } ],
				contextMenuParams=> { genre_id =>  $_->{id} },
			}, @$loop );
			return \@result, 0, 0, ['genreinfo', 'items'];
		},
	);
}

sub _years {
	my ($client, $callback, $args, $pt) = @_;
	my @searchTags = $pt->{searchTags} ? @{$pt->{searchTags}} : ();
	
	_generic($client, $callback, 'years', 'years_loop', \@searchTags,
		sub {
			my $loop = shift;
			return [ map {
				name        => $_->{year},
				type        => 'playlist',
				playlist    => \&_tracks,
				url         => \&_albums,
				passthrough => [ { searchTags => [@searchTags, 'year:' . $_->{year}] } ],
			}, @$loop ];
		},
	);
}

sub _albums {
	my ($client, $callback, $args, $pt) = @_;
	my @searchTags = $pt->{searchTags} ? @{$pt->{searchTags}} : ();
	my $sort       = $pt->{'sort'};
	my $search     = $pt->{'search'};
	
	_generic($client, $callback, 'albums', 'albums_loop',
		['tags:ljs', @searchTags, ($sort ? $sort : ()), ($search ? 'search:' . $search : undef)],
		sub {
			my $loop = shift;
			my $addAll = 0;
			my @result = ( map {
				name        => $_->{album},
				textkey     => $_->{textkey},
				image       => ($_->{artwork_track_id} ? '/music/' . $_->{artwork_track_id} . '/cover' : undef),
				type        => 'playlist',
				playlist    => \&_tracks,
				url         => \&_tracks,
				passthrough => [{ searchTags => [ @searchTags, 'album_id:' . $_->{id} ], sort => 'sort:tracknum', }],
				contextMenuParams=> { album_id =>  $_->{id} },
			}, @$loop );
			if (scalar @result > 1 && scalar @searchTags) {
				push @result, {
					name        => _clientString($client, 'ALL_SONGS'),
					image       => '/music/all_items/cover',
					type        => 'playlist',
					playlist    => \&_tracks,
					url         => \&_tracks,
					passthrough => [{ searchTags => \@searchTags, sort => 'sort:title', menuStyle => 'allSongs' }],
				};
				$addAll = 1;
			}
			return \@result, (($sort && $sort =~ /:new/) ? 1 : 0), $addAll, ['albuminfo', 'items'];
		},
	);
}

sub _tracks {
	my ($client, $callback, $args, $pt) = @_;
	my @searchTags = $pt->{searchTags} ? @{$pt->{searchTags}} : ();
	my $sort       = $pt->{'sort'} || 'sort:albumtrack';
	my $menuStyle  = $pt->{'menuStyle'} || 'menuStyle:album';
	my $search     = $pt->{'search'};
	
	_generic($client, $callback, 'titles', 'titles_loop',
		['tags:dtux', $sort, $menuStyle, @searchTags, ($search ? 'search:' . $search : undef)],
		sub {
			my $loop = shift;
			my @result;
			for (@$loop) {
				my $tracknum = $_->{tracknum} ? $_->{tracknum} . '. ' : '';
				my %item = (
					name        => $tracknum . $_->{title},
					type        => 'link',
					url         => \&_track,
					on_select   => 'play',
					duration    => $_->{duration},
					play        => $_->{url},
					playall     => 1,
					passthrough => [ $_->{'remote'} ? { track_url => $_->{url} } : { track_id => $_->{id} } ],
				);
				push @result, \%item;
			}
			return \@result;
		},
	);
}

sub _track {
	my ($client, $callback, $args, $pt) = @_;

	my $tags = {
		menuMode      => 0,
		menuContext   => 'normal',
	};
	my $feed;
	
	if ($pt->{'track_url'}) {
		$feed  = Slim::Menu::TrackInfo->menu( $client, $pt->{track_url}, undef, $tags );
	}
	if ($pt->{'track_id'}) {
		my $track = Slim::Schema->find( Track => $pt->{track_id} );
		$feed  = Slim::Menu::TrackInfo->menu( $client, $track->url, $track, $tags ) if $track;
	}
	
	$callback->($feed);
	return;
}

sub _bmf {
	my ($client, $callback, $args, $pt) = @_;
	my @searchTags = $pt->{searchTags} ? @{$pt->{searchTags}} : ();
	
	_generic($client, $callback, 'musicfolder', 'folder_loop', ['tags:dus', @searchTags],
		sub {
			my $loop = shift;
			my @result;
			my $gotsubfolder = 0;
			for (@$loop) {
				my %item;
				if ($_->{type} eq 'folder') {
					%item = (
						type        => 'link',
						url         => \&_bmf,
						passthrough => [{ searchTags => [ "folder_id:" . $_->{id} ] }],
						contextMenuParams=> { folder_id =>  $_->{id} },
					);
					$gotsubfolder = 1;
				}  elsif ($_->{type} eq 'track') {
					%item = (
						type        => 'link',
						url         => \&_track,
						on_select   => 'play',
						duration    => $_->{duration},
						play        => $_->{url},
						playall     => 1,
						passthrough => [{ track_id => $_->{id} }],
					);
				}  elsif ($_->{type} eq 'playlist') {
					
				}  elsif ($_->{type} eq 'unknown') {
					%item = (
						type => 'text',
					);
				}
				$item{name} = $_->{filename};
				$item{textkey} = $_->{textkey};
				push @result, \%item;
			}
			return \@result, 0, 0, ($gotsubfolder ? ['folderinfo', 'items'] : undef);
		},
	);
}

sub _playlists {
	my ($client, $callback, $args, $pt) = @_;
	my @searchTags = $pt->{searchTags} ? @{$pt->{searchTags}} : ();
	my $search     = $pt->{'search'};
	
	_generic($client, $callback, 'playlists', 'playlists_loop',
		['tags:s', @searchTags, ($search ? 'search:' . $search : undef)],
		sub {
			my $loop = shift;
			my @result = ( map {
				name        => $_->{playlist},
				textkey     => $_->{textkey},
				type        => 'playlist',
				playlist    => \&_playlistTracks,
				url         => \&_playlistTracks,
				passthrough => [{ searchTags => [ @searchTags, 'playlist_id:' . $_->{id} ], }],
				contextMenuParams=> { playlist_id =>  $_->{id} },
			}, @$loop );
			return \@result, 0, 0, ['playlistinfo', 'items'];
		},
	);
}

sub _playlistTracks {
	my ($client, $callback, $args, $pt) = @_;
	my @searchTags = $pt->{searchTags} ? @{$pt->{searchTags}} : ();
	my $menuStyle  = $pt->{'menuStyle'} || 'menuStyle:album';
	
	_generic($client, $callback, ['playlists', 'tracks'], 'playlisttracks_loop',
		['tags:dtu', $menuStyle, @searchTags],
		sub {
			my $loop = shift;
			my @result;
			for (@$loop) {
				my $tracknum = $_->{tracknum} ? $_->{tracknum} . '. ' : '';
				my %item = (
					name        => $tracknum . $_->{title},
					type        => 'link',
					url         => \&_track,
					on_select   => 'play',
					duration    => $_->{duration},
					play        => $_->{url},
					playall     => 1,
					passthrough => [{ track_id => $_->{id} }],
				);
				push @result, \%item;
			}
			return \@result;
		},
	);
}

sub getDisplayName () {
	return 'PLUGIN_BROWSE_LIBRARY_MODULE_NAME';
}

sub playerMenu {'PLUGINS'}

	
1;
