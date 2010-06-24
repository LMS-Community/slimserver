package Slim::Plugin::BrowseLibrary::Plugin;

# $Id$


use strict;
use base 'Slim::Plugin::OPMLBased';
use Slim::Utils::Log;
use Slim::Utils::Prefs;

my $prefs = preferences('server');

my $log = Slim::Utils::Log->addLogCategory({
	category     => 'plugin.browse',
	defaultLevel => 'ERROR',
	description  => 'PLUGIN_BROWSE_LIBRARY_MODULE_NAME',
});

sub _pluginDataFor {
	my $class = shift;
	my $key   = shift;

	my $pluginData = $class->pluginData() if $class->can('pluginData');

	if ($pluginData && ref($pluginData) && $pluginData->{$key}) {
		return $pluginData->{$key};
	}

	return __PACKAGE__->SUPER::_pluginDataFor($key);
}

my @submenus = (
	['Albums', 'browsealbums', 'BROWSE_BY_ALBUM', \&_albums, {
		icon => 'plugins/BrowseLibrary/html/images/albums.png',
	}],
	['Artists', 'browseartists', 'BROWSE_BY_ARTIST', \&_artists, {
		icon => 'plugins/BrowseLibrary/html/images/artists.png',
	}],
);

sub _initSubmenu {
	my ($class, %args) = @_;
	$args{'weight'} ||= $class->weight() + 1;
	$args{'is_app'} ||= 0;
	$class->SUPER::initPlugin(%args);
}

sub _initSubmenus {
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
				\$class->SUPER::_initSubmenu(feed => \$feed, tag => '$menu->[1]');
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

	$class->_initSubmenus();
	
    $class->_addSubModes();
}

sub webPages {
	my $class = shift;
	
	$class->SUPER::webPages();
	
	require Slim::Web::XMLBrowser;
	Slim::Web::XMLBrowser->init();
	
	foreach my $node (@{_getNodeList()}) {
		my $url = 'clixmlbrowser/clicmd=browselibrary+items&linktitle=' . $node->{'name'};
		$url .= join('&', ('', map {$_ .'=' . $node->{'params'}->{$_}} keys %{$node->{'params'}}));
		$url .= '/';
		Slim::Web::Pages->addPageLinks("browse", { $node->{'name'} => $url });
		Slim::Web::Pages->addPageLinks('icons', { $node->{'name'} => $node->{'icon'} }) if $node->{'icon'};
	}
}

sub _addSubModes {
	my $class = shift;
	
	foreach my $node (@{_getNodeList()}) {
		Slim::Buttons::Home::addSubMenu('BROWSE_MUSIC', $node->{'name'}, {
			useMode   => $class->modeName,
			header    => $node->{'name'},
			title     => '{' . $node->{'name'} . '}',
			%{$node->{'params'}},
		});
		if ($node->{'homeMenuText'}) {
			Slim::Buttons::Home::addMenuOption($node->{'name'}, {
				useMode   => $class->modeName,
				header    => $node->{'homeMenuText'},
				title     => '{' . $node->{'homeMenuText'} . '}',
				%{$node->{'params'}},
				
			});
		}
	}
}

sub getJiveMenu {
	my ($client, $baseNode, $albumSort) = @_;
	
	my @myMusicMenu;
	
	foreach my $node (@{_getNodeList()}) {
		my %menu = (
			text => $client->string($node->{'name'}),
			id   => $node->{'id'},
			node => $baseNode,
			weight => $node->{'weight'},
			actions => {
				go => {
					cmd    => ['browselibrary', 'items'],
					params => {
						menu => 1,
						%{$node->{'params'}},
					},
					
				},
			}
		);
		
		if ($node->{'homeMenuText'}) {
			$menu{'homeMenuText'} = $client->string($node->{'homeMenuText'});
		}
		
		push @myMusicMenu, \%menu;
	}
	
	return \@myMusicMenu;
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

my %modeMap = (
	albums => \&_albums,
	artists => \&_artists,
	genres => \&_genres,
	bmf => \&_bmf,
	tracks => \&_tracks,
	years => \&_years,
	playlists => \&_playlists,
	playlistTracks => \&_playlistTracks,
);

my @topLevelArgs = qw(track_id artist_id genre_id album_id playlist_id year folder_id);

sub _topLevel {
	my ($client, $callback, $args) = @_;
	my $params = $args->{'params'};
	
	if ($params) {
		my %args;

		if ($params->{'query'} && $params->{'query'} =~ /(\w+)=(.*)/) {
			$params->{$1} = $2;
		}

		my @searchTags;
		for (@topLevelArgs) {
			push (@searchTags, $_ . ':' . $params->{$_}) if $params->{$_};
		}
		$args{'searchTags'} = \@searchTags if scalar @searchTags;

		$args{'sort'} = 'sort:' . $params->{'sort'} if $params->{'sort'};
		$args{'search'} = $params->{'search'} if $params->{'search'};
		
		if ($params->{'mode'}) {
			my %entryParams;
			for (@topLevelArgs, qw(sort search mode)) {
				$entryParams{$_} = $params->{$_} if $params->{$_};
			}
			main::INFOLOG && $log->is_info && $log->info('params=>', join('&', map {$_ . '=' . $entryParams{$_}} keys(%entryParams)));
			
			my $func = $modeMap{$params->{'mode'}};
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
				icon => 'plugins/BrowseLibrary/html/images/artists.png',
			},
			{
				type => 'link',
				name => _clientString($client, 'BROWSE_BY_ALBUM'),
				url  => \&_albums,
				icon => 'plugins/BrowseLibrary/html/images/albums.png',
			},
			{
				type => 'link',
				name => _clientString($client, 'BROWSE_BY_GENRE'),
				url  => \&_genres,
				icon => 'plugins/BrowseLibrary/html/images/genres.png',
			},
			{
				type => 'link',
				name => _clientString($client, 'BROWSE_BY_YEAR'),
				url  => \&_years,
				icon => 'plugins/BrowseLibrary/html/images/years.png',
			},
			{
				type => 'link',
				name => _clientString($client, 'BROWSE_NEW_MUSIC'),
				url  => \&_albums,
				passthrough => [ { sort => 'sort:new' } ],
				icon => 'plugins/BrowseLibrary/html/images/newmusic.png',
			},
			{
				type => 'link',
				name => _clientString($client, 'BROWSE_MUSIC_FOLDER'),
				url  => \&_bmf,
				icon => 'plugins/BrowseLibrary/html/images/musicfolder.png',
			},
			{
				type => 'link',
				name => _clientString($client, 'PLAYLISTS'),
				url  => \&_playlists,
				icon => 'plugins/BrowseLibrary/html/images/playlists.png',
			},
			{
				name  => _clientString($client, 'SEARCH'),
				icon => 'plugins/BrowseLibrary/html/images/search.png',
				items => [
					{
						type => 'search',
						name => _clientString($client, 'BROWSE_BY_ARTIST'),
						icon => 'plugins/BrowseLibrary/html/images/search.png',
						url  => \&_artists,
					},
					{
						type => 'search',
						name => _clientString($client, 'BROWSE_BY_ALBUM'),
						icon => 'plugins/BrowseLibrary/html/images/search.png',
						url  => \&_albums,
					},
					{
						type => 'search',
						name => _clientString($client, 'BROWSE_BY_SONG'),
						icon => 'plugins/BrowseLibrary/html/images/search.png',
						url  => \&_tracks,
					},
					{
						type => 'search',
						name => _clientString($client, 'PLAYLISTS'),
						icon => 'plugins/BrowseLibrary/html/images/search.png',
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

sub _getNodeList {
	my ($albumsSort) = @_;
	$albumsSort ||= 'album';
	
	my @topLevel = (
		{
			type => 'link',
			name => 'BROWSE_BY_ARTIST',
			params => {mode => 'artists'},
			icon => 'plugins/BrowseLibrary/html/images/artists.png',
			homeMenuText => 'BROWSE_ARTISTS',
			id           => 'myMusicArtists',
			weight       => 10,
		},
		{
			type => 'link',
			name => 'BROWSE_BY_ALBUM',
			params => {mode => 'albums', sort => $albumsSort},
			icon => 'plugins/BrowseLibrary/html/images/albums.png',
			homeMenuText => 'BROWSE_ALBUMS',
			id           => 'myMusicAlbums',
			weight       => 20,
		},
		{
			type => 'link',
			name => 'BROWSE_BY_GENRE',
			params => {mode => 'genres'},
			icon => 'plugins/BrowseLibrary/html/images/genres.png',
			homeMenuText => 'BROWSE_GENRES',
			id           => 'myMusicGenres',
			weight       => 30,
		},
		{
			type => 'link',
			name => 'BROWSE_BY_YEAR',
			params => {mode => 'years'},
			icon => 'plugins/BrowseLibrary/html/images/years.png',
			homeMenuText => 'BROWSE_YEARS',
			id           => 'myMusicYears',
			weight       => 40,
		},
		{
			type => 'link',
			name => 'BROWSE_NEW_MUSIC',
			
			icon => 'plugins/BrowseLibrary/html/images/newmusic.png',
			params => {mode => 'albums', sort => 'new'},
			id           => 'myMusicNewMusic',
			weight       => 50,
		},
		{
			type => 'link',
			name => 'BROWSE_MUSIC_FOLDER',
			params => {mode => 'bmf'},
			icon => 'plugins/BrowseLibrary/html/images/musicfolder.png',
			condition => sub {$prefs->get('audiodir');},
			id           => 'myMusicMusicFolder',
			weight       => 70,
		},
		{
			type => 'link',
			name => 'SAVED_PLAYLISTS',
			params => {mode => 'playlists'},
			icon => 'plugins/BrowseLibrary/html/images/playlists.png',
			condition => sub {
				$prefs->get('playlistdir') ||
				 (Slim::Schema::hasLibrary && Slim::Schema->rs('Playlist')->getPlaylists->count);
			},
			id           => 'myMusicPlaylists',
			weight       => 80,
		},
#		{
#			name  => _clientString($client, 'SEARCH'),
#			icon => 'plugins/BrowseLibrary/html/images/search.png',
#			items => [
#				{
#					type => 'search',
#					name => _clientString($client, 'BROWSE_BY_ARTIST'),
#					icon => 'plugins/BrowseLibrary/html/images/search.png',
#					url  => \&_artists,
#				},
#				{
#					type => 'search',
#					name => _clientString($client, 'BROWSE_BY_ALBUM'),
#					icon => 'plugins/BrowseLibrary/html/images/search.png',
#					url  => \&_albums,
#				},
#				{
#					type => 'search',
#					name => _clientString($client, 'BROWSE_BY_SONG'),
#					icon => 'plugins/BrowseLibrary/html/images/search.png',
#					url  => \&_tracks,
#				},
#				{
#					type => 'search',
#					name => _clientString($client, 'PLAYLISTS'),
#					icon => 'plugins/BrowseLibrary/html/images/search.png',
#					url  => \&_playlists,
#				},
#			],
#		},
	);
	
	my @nodes;
	
	if (!Slim::Schema::hasLibrary) {
		return \@nodes;
	}
	
	foreach my $item (@topLevel) {
		if ($item->{'condition'} && !$item->{'condition'}->()) {
			next;
		}
		push @nodes, $item;
	}
	return \@nodes;
}

sub _generic {
	my ($client,
		$callback,		# func ref:  Callback function to XMLbowser: callback(hashOrArray_ref)
		$args,          # hash ref:  Additional parameters from XMLBrowser
		$query,			# string:    CLI query, single verb or array-ref;
						#            command takes _index, _quantity and tagged params
		$loopName,		# string:    name of loop variable in CLI result; usually <query>_loop
		$queryTags,		# array ref: tagged params to pass to CLI query
		$resultsFunc	# func ref:  func(ARRAYref cliLoop) returns (ARRAYref items, Bool unsorted default FALSE);
						#            function to process results loop from CLI and generate XMLBrowser items
	) = @_;
	
	my $index = $args->{'index'} || 0;
	my $quantity = $args->{'quantity'} || 0;
	
	main::INFOLOG && $log->is_info && $log->info("$query ($index, $quantity): tags ->", join(', ', @$queryTags));
	
	my $request = Slim::Control::Request->new( $client ? $client->id() : undef,
		[ (ref $query ? @$query : $query), $index, $quantity || 100000, @$queryTags ] );
	$request->execute();
	
	if ( $request->isStatusError() ) {
		$log->error($request->getStatusText());
	}

#	$log->error(Data::Dump::dump($request->getResults()));
	
	my $loop = $request->getResults()->{$loopName};
	
	my ($result, $unsorted, $extraAtEnd, $actions) = $resultsFunc->($loop);
	
	
	my %results = (
		total  => $request->getResults()->{'count'} + ($extraAtEnd || 0),
		offset => $index,
		items  => $result,
		sorted => !$unsorted,
	);
	$results{'actions'} = $actions if $actions;

#	$log->error(Data::Dump::dump(\%results));

	$callback->(\%results);
}

sub _tagsToParams {
	my $tags = shift;
	my %p;
	foreach (@$tags) {
		my ($k, $v) = /([^:]+):(.+)/;
		$p{$k} = $v;
	}
	return \%p;
}

sub _artists {
	my ($client, $callback, $args, $pt) = @_;
	my @searchTags = $pt->{'searchTags'} ? @{$pt->{'searchTags'}} : ();
	my $search     = $pt->{'search'};

	if (!$search && !scalar @searchTags && $args->{'search'}) {
		$search = $args->{'search'};
	}
	
	_generic($client, $callback, $args, 'artists', 'artists_loop',
		['tags:s', @searchTags, ($search ? 'search:' . $search : undef)],
		sub {
			my $loop = shift;
			my $addAll = 0;
			my @result = ( map {
				name        => $_->{'artist'},
				textkey     => $_->{'textkey'},
				type        => 'playlist',
				playlist    => \&_tracks,
				url         => \&_albums,
				passthrough => [ { searchTags => [@searchTags, "artist_id:" . $_->{'id'}] } ],
				id          =>  $_->{'id'},
				
			}, @$loop );
			if ($pt->{'addAllAlbums'} && scalar @result > 1) {
				push @result, {
					name        => _clientString($client, 'ALL_ALBUMS'),
					type        => 'playlist',
					playlist    => \&_tracks,
					url         => \&_albums,
					passthrough => [{ searchTags => \@searchTags }],
				};
				$addAll = 1;
			}
			return \@result, 0, $addAll,
				{
					commonVariables	=> [artist_id => 'id'],
					info => {
						command     => ['artistinfo', 'items'],
					},
					items => {
						command     => ['browselibrary', 'items'],
						fixedParams => {
							mode       => 'albums',
							%{&_tagsToParams(\@searchTags)},
						},
					},
					play => {
						command     => ['playlistcontrol'],
						fixedParams => {cmd => 'load', %{&_tagsToParams(\@searchTags)}},
					},
					playall => {
						command     => ['playlistcontrol'],
						fixedParams => {cmd => 'load', %{&_tagsToParams(\@searchTags)}},
					},
					add => {
						command     => ['playlistcontrol'],
						fixedParams => {cmd => 'add', %{&_tagsToParams(\@searchTags)}},
					},
					addall => {
						command     => ['playlistcontrol'],
						fixedParams => {cmd => 'add', %{&_tagsToParams(\@searchTags)}},
					},
					insert => {
						command     => ['playlistcontrol'],
						fixedParams => {cmd => 'insert', %{&_tagsToParams(\@searchTags)}},
					},
				};
			
		},
	);
}

sub _genres {
	my ($client, $callback, $args, $pt) = @_;
	my @searchTags = $pt->{'searchTags'} ? @{$pt->{'searchTags'}} : ();

	_generic($client, $callback, $args, 'genres', 'genres_loop', ['tags:s', @searchTags],
		sub {
			my $loop = shift;
			my @result = ( map {
				name        => $_->{'genre'},
				textkey     => $_->{'textkey'},
				type        => 'playlist',
				playlist    => \&_tracks,
				url         => \&_artists,
				passthrough => [ { searchTags => [@searchTags, "genre_id:" . $_->{'id'}], addAllAlbums => 1 } ],
				id          =>  $_->{'id'},
			}, @$loop );
			return \@result, 0, 0,
				{
					commonVariables	=> [genre_id => 'id'],
					info => {
						command     => ['genreinfo', 'items'],
					},
					items => {
						command     => ['browselibrary', 'items'],
						fixedParams => {
							mode         => 'artists',
							addAllAlbums => 1,
						},
					},
					play => {
						command     => ['playlistcontrol'],
						fixedParams => {cmd => 'load'},
					},
					playall => {
						command     => ['playlistcontrol'],
						fixedParams => {cmd => 'load'},
					},
					add => {
						command     => ['playlistcontrol'],
						fixedParams => {cmd => 'add'},
					},
					addall => {
						command     => ['playlistcontrol'],
						fixedParams => {cmd => 'add'},
					},
					insert => {
						command     => ['playlistcontrol'],
						fixedParams => {cmd => 'insert'},
					},
				};
		},
	);
}

sub _years {
	my ($client, $callback, $args, $pt) = @_;
	my @searchTags = $pt->{'searchTags'} ? @{$pt->{'searchTags'}} : ();
	
	_generic($client, $callback, $args, 'years', 'years_loop', \@searchTags,
		sub {
			my $loop = shift;
			return [ map {
				name        => $_->{'year'},
				type        => 'playlist',
				playlist    => \&_tracks,
				url         => \&_albums,
				passthrough => [ { searchTags => [@searchTags, 'year:' . $_->{'year'}] } ],
			}, @$loop ], 0, 0,
				{
					commonVariables	=> [year => 'name'],
					info => {
						command     => ['yearinfo', 'items'],
					},
					items => {
						command     => ['browselibrary', 'items'],
						fixedParams => {
							mode       => 'albums',
						},
					},
					play => {
						command     => ['playlistcontrol'],
						fixedParams => {cmd => 'load'},
					},
					playall => {
						command     => ['playlistcontrol'],
						fixedParams => {cmd => 'load'},
					},
					add => {
						command     => ['playlistcontrol'],
						fixedParams => {cmd => 'add'},
					},
					addall => {
						command     => ['playlistcontrol'],
						fixedParams => {cmd => 'add'},
					},
					insert => {
						command     => ['playlistcontrol'],
						fixedParams => {cmd => 'insert'},
					},
				};
		},
	);
}

sub _albums {
	my ($client, $callback, $args, $pt) = @_;
	my @searchTags = $pt->{'searchTags'} ? @{$pt->{'searchTags'}} : ();
	my $sort       = $pt->{'sort'};
	my $search     = $pt->{'search'};
	my $getMetadata= $args->{'wantMetadata'}; 
	my $tags       = 'ljsa';

	if (!$search && !scalar @searchTags && $args->{'search'}) {
		$search = $args->{'search'};
	}
	
	$tags .= 'ywXiq' if $getMetadata;
	
	my @artistIds = grep /artist_id:/, @searchTags;
	my ($artistId) = ($artistIds[0] =~ /artist_id:(\d+)/) if @artistIds;

	$tags .= 'S' if ($artistId || $getMetadata);
	
	_generic($client, $callback, $args, 'albums', 'albums_loop',
		["tags:$tags", @searchTags, ($sort ? $sort : ()), ($search ? 'search:' . $search : undef)],
		sub {
			my $loop = shift;
			my $addAll = 0;
			my @result;
			foreach (@$loop) {
				my %item = (
					name        => $_->{'album'},
					textkey     => $_->{'textkey'},
					image       => ($_->{'artwork_track_id'} ? 'music/' . $_->{'artwork_track_id'} . '/cover' : undef),
					type        => 'playlist',
					playlist    => \&_tracks,
					url         => \&_tracks,
					passthrough => [{ searchTags => [ @searchTags, 'album_id:' . $_->{'id'} ], sort => 'sort:tracknum', }],
					id          =>  $_->{'id'},
				);
				
				# If an artist was not used in the selection criteria or if one was
				# used but is different to that of the primary artist, then provide 
				# the primary artist name in name2.
				if (!$artistId || $artistId != $_->{'artist_id'}) {
					$item{'name2'} = $_->{'artist'};
				}
				if ($getMetadata) {
					$item{'metadata'}->{'year'} = $_->{'year'} if $_->{'year'};
					$item{'metadata'}->{'disc'} = $_->{'disc'} if $_->{'disc'};
					$item{'metadata'}->{'disccount'} = $_->{'disccount'} if $_->{'disccount'};
					$item{'metadata'}->{'album'} = {
							name         => $_->{'album'},
							id           => $_->{'id'},
							replay_gain  => $_->{'replay_gain'},
							compilation  => $_->{'compilation'},
						};
					$item{'metadata'}->{'contributors'} =	{
							ARTIST => [
								{
									name => $_->{'artist'},
									id   => $_->{'artist_id'},
								},
							],
						} if $_->{'artist_id'};
				}
				push @result, \%item;
			}
			if (scalar @result > 1 && scalar @searchTags) {
				push @result, {
					name        => _clientString($client, 'ALL_SONGS'),
					image       => 'music/all_items/cover',
					type        => 'playlist',
					playlist    => \&_tracks,
					url         => \&_tracks,
					passthrough => [{ searchTags => \@searchTags, sort => 'sort:title', menuStyle => 'allSongs' }],
				};
				$addAll = 1;
			}
			return \@result, (($sort && $sort =~ /:new/) ? 1 : 0), $addAll,
				{
					commonVariables	=> [album_id => 'id'],
					info => {
						command     => ['albuminfo', 'items'],
					},
					items => {
						command     => ['browselibrary', 'items'],
						fixedParams => {
							mode       => 'tracks',
							%{&_tagsToParams(\@searchTags)},
						},
					},
					play => {
						command     => ['playlistcontrol'],
						fixedParams => {cmd => 'load'},
					},
					playall => {
						command     => ['playlistcontrol'],
						fixedParams => {cmd => 'load'},
					},
					add => {
						command     => ['playlistcontrol'],
						fixedParams => {cmd => 'add'},
					},
					addall => {
						command     => ['playlistcontrol'],
						fixedParams => {cmd => 'add'},
					},
					insert => {
						command     => ['playlistcontrol'],
						fixedParams => {cmd => 'insert'},
					},
				};
		},
	);
}

sub _tracks {
	my ($client, $callback, $args, $pt) = @_;
	my @searchTags = $pt->{'searchTags'} ? @{$pt->{'searchTags'}} : ();
	my $sort       = $pt->{'sort'} || 'sort:albumtrack';
	my $menuStyle  = $pt->{'menuStyle'} || 'menuStyle:album';
	my $search     = $pt->{'search'};
	my $offset     = $args->{'index'} || 0;
	
	if (!$search && !scalar @searchTags && $args->{'search'}) {
		$search = $args->{'search'};
	}

	_generic($client, $callback, $args, 'titles', 'titles_loop',
		['tags:dtux', $sort, $menuStyle, @searchTags, ($search ? 'search:' . $search : undef)],
		sub {
			my $loop = shift;
			my @result;
			for (@$loop) {
				my $tracknum = $_->{'tracknum'} ? $_->{'tracknum'} . '. ' : '';
				my %item = (
					name        => $tracknum . $_->{'title'},
					type        => 'link',
					url         => \&_track,
					on_select   => 'play',
					duration    => $_->{'duration'},
					play        => $_->{'url'},
					playall     => 1,
					passthrough => [ $_->{'remote'} ? { track_url => $_->{'url'} } : { track_id => $_->{'id'} } ],
					id          => $_->{'id'},
					play_index  => $offset++,
				);
				push @result, \%item;
			}
			return \@result, 0, 0,
				{
					commonVariables	=> [track_id => 'id'],
					info => {
						command     => ['trackinfo', 'items'],
					},
					items => {
						command     => ['trackinfo', 'items'],
					},
					play => {
						command     => ['playlistcontrol'],
						fixedParams => {cmd => 'load'},
					},
					playall => {
						command     => ['playlistcontrol'],
						fixedParams => {cmd => 'load', %{&_tagsToParams([@searchTags, $sort])}},
						variables	=> [play_index => 'play_index'],
					},
					add => {
						command     => ['playlistcontrol'],
						fixedParams => {cmd => 'add'},
					},
					addall => {
						command     => ['playlistcontrol'],
						variables	=> [],
						fixedParams => {cmd => 'add', %{&_tagsToParams([@searchTags, $sort])}},
					},
					insert => {
						command     => ['playlistcontrol'],
						fixedParams => {cmd => 'insert'},
					},
				};
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
		$feed  = Slim::Menu::TrackInfo->menu( $client, $pt->{'track_url'}, undef, $tags );
	}
	if ($pt->{'track_id'}) {
		my $track = Slim::Schema->find( Track => $pt->{'track_id'} );
		$feed  = Slim::Menu::TrackInfo->menu( $client, $track->url, $track, $tags ) if $track;
	}
	
	$callback->($feed);
	return;
}

sub _bmf {
	my ($client, $callback, $args, $pt) = @_;
	my @searchTags = $pt->{'searchTags'} ? @{$pt->{'searchTags'}} : ();
	
	_generic($client, $callback, $args, 'musicfolder', 'folder_loop', ['tags:dus', @searchTags],
		sub {
			my $loop = shift;
			my @result;
			my $gotsubfolder = 0;
			for (@$loop) {
				my %item;
				if ($_->{'type'} eq 'folder') {
					%item = (
						type        => 'link',
						url         => \&_bmf,
						passthrough => [{ searchTags => [ "folder_id:" . $_->{'id'} ] }],
						itemActions => {
							info => {
								command     => ['folderinfo', 'items'],
								fixedParams => {folder_id =>  $_->{'id'}},
							},
						},
					);
					$gotsubfolder = 1;
				}  elsif ($_->{'type'} eq 'track') {
					%item = (
						type        => 'link',
						url         => \&_track,
						on_select   => 'play',
						duration    => $_->{'duration'},
						play        => $_->{'url'},
						playall     => 1,
						passthrough => [{ track_id => $_->{'id'} }],
						itemActions => {
							info => {
								command     => ['trackinfo', 'items'],
								fixedParams => {track_id =>  $_->{'id'}},
							},
						},
					);
				}  elsif ($_->{'type'} eq 'playlist') {
					
				}  elsif ($_->{'type'} eq 'unknown') {
					%item = (
						type => 'text',
					);
				}
				$item{'name'} = $_->{'filename'};
				$item{'textkey'} = $_->{'textkey'};
				push @result, \%item;
			}
			return \@result;
		},
	);
}

sub _playlists {
	my ($client, $callback, $args, $pt) = @_;
	my @searchTags = $pt->{'searchTags'} ? @{$pt->{'searchTags'}} : ();
	my $search     = $pt->{'search'};
	
	if (!$search && !scalar @searchTags && $args->{'search'}) {
		$search = $args->{'search'};
	}

	_generic($client, $callback, $args, 'playlists', 'playlists_loop',
		['tags:s', @searchTags, ($search ? 'search:' . $search : undef)],
		sub {
			my $loop = shift;
			my @result = ( map {
				name        => $_->{'playlist'},
				textkey     => $_->{'textkey'},
				type        => 'playlist',
				playlist    => \&_playlistTracks,
				url         => \&_playlistTracks,
				passthrough => [{ searchTags => [ @searchTags, 'playlist_id:' . $_->{'id'} ], }],
				id          =>  $_->{'id'},
			}, @$loop );
			return \@result, 0, 0,
				{
					commonVariables	=> [playlist_id => 'id'],
					info => {
						command     => ['playlistinfo', 'items'],
					},
					items => {
						command     => ['browselibrary', 'items'],
						fixedParams => {
							mode       => 'playlistTracks',
							%{&_tagsToParams(\@searchTags)},
						},
					},
					play => {
						command     => ['playlistcontrol'],
						fixedParams => {cmd => 'load'},
					},
					playall => {
						command     => ['playlistcontrol'],
						fixedParams => {cmd => 'load'},
					},
					add => {
						command     => ['playlistcontrol'],
						fixedParams => {cmd => 'add'},
					},
					addall => {
						command     => ['playlistcontrol'],
						fixedParams => {cmd => 'add'},
					},
					insert => {
						command     => ['playlistcontrol'],
						fixedParams => {cmd => 'insert'},
					},
				};
			
		},
	);
}

sub _playlistTracks {
	my ($client, $callback, $args, $pt) = @_;
	my @searchTags = $pt->{'searchTags'} ? @{$pt->{'searchTags'}} : ();
	my $menuStyle  = $pt->{'menuStyle'} || 'menuStyle:album';
	
	_generic($client, $callback, $args, ['playlists', 'tracks'], 'playlisttracks_loop',
		['tags:dtu', $menuStyle, @searchTags],
		sub {
			my $loop = shift;
			my @result;
			for (@$loop) {
				my $tracknum = $_->{'tracknum'} ? $_->{'tracknum'} . '. ' : '';
				my %item = (
					name        => $tracknum . $_->{'title'},
					type        => 'link',
					url         => \&_track,
					on_select   => 'play',
					duration    => $_->{'duration'},
					play        => $_->{'url'},
					playall     => 1,
					passthrough => [{ track_id => $_->{'id'} }],
					id          => $_->{'id'},
				);
				push @result, \%item;
			}
			return \@result, 1, 0, 
				{
					info => {
						command     => ['trackinfo', 'items'],
						variables	=> [track_id => 'id'],
					},
				};
		},
	);
}

sub getDisplayName () {
	return 'PLUGIN_BROWSE_LIBRARY_MODULE_NAME';
}

sub playerMenu {'PLUGINS'}


1;
