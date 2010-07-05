package Slim::Menu::BrowseLibrary;

# $Id$


use strict;
use Slim::Utils::Log;
use Slim::Utils::Prefs;

my $prefs = preferences('server');
my $log = logger('database.info');

#my %pluginData = (
#	icon => 'html/images/browselibrary.png',
#);
#
#sub _pluginDataFor {
#	my $class = shift;
#	my $key   = shift;
#
#	my $pluginData = $class->pluginData() if $class->can('pluginData');
#
#	if ($pluginData && ref($pluginData) && $pluginData->{$key}) {
#		return $pluginData->{$key};
#	}
#	
#	if ($pluginData{$key}) {
#		return $pluginData{$key};
#	}
#
#	return __PACKAGE__->SUPER::_pluginDataFor($key);
#}
#
#my @submenus = (
#	['Albums', 'browsealbums', 'BROWSE_BY_ALBUM', \&_albums, {
#		icon => 'html/images/albums.png',
#	}],
#	['Artists', 'browseartists', 'BROWSE_BY_ARTIST', \&_artists, {
#		icon => 'html/images/artists.png',
#	}],
#);
#
#sub _initSubmenu {
#	my ($class, %args) = @_;
#	$args{'weight'} ||= $class->weight() + 1;
#	$args{'is_app'} ||= 0;
#	$class->SUPER::initPlugin(%args);
#}
#
#sub _initSubmenus {
#	my $class = shift;
#	my $base  = __PACKAGE__;
#	
#	foreach my $menu (@submenus) {
#
#		my $packageName = $base . '::' . $menu->[0];
#		my $pkg = "{
#			package $packageName;
#			use base '$base';
#			my \$pluginData;
#			
#			sub init {
#				my (\$class, \$feed, \$data) = \@_;
#				\$pluginData = \$data;
#				\$class->SUPER::_initSubmenu(feed => \$feed, tag => '$menu->[1]');
#			}
#		
#			sub getDisplayName {'$menu->[2]'}	
#			sub pluginData {\$pluginData}	
#		}";
#		
#		eval $pkg;
#		
#		$packageName->init($menu->[3], $menu->[4]);
#	}
#}

use constant BROWSELIBRARY => 'browselibrary';

sub init {
	my $class = shift;
	
	main::DEBUGLOG && $log->is_debug && $log->debug('init');
	
	{
		no strict 'refs';
		*{$class.'::'.'feed'}     = sub { \&_topLevel; };
		*{$class.'::'.'tag'}      = sub { BROWSELIBRARY };
		*{$class.'::'.'modeName'} = sub { BROWSELIBRARY };
		*{$class.'::'.'menu'}     = sub { undef };
		*{$class.'::'.'weight'}   = sub { 15 };
		*{$class.'::'.'type'}     = sub { 'link' };
	}

	$class->_initCLI();
	
	if ( main::WEBUI ) {
		$class->_webPages;
	}
	

#	$class->_initSubmenus();
	
    $class->_initModes();
}

sub cliQuery {
 	my $request = shift;
	Slim::Control::XMLBrowser::cliQuery( BROWSELIBRARY, \&_topLevel, $request );
};

sub _initCLI {
	my ( $class ) = @_;
	
	# CLI support
	Slim::Control::Request::addDispatch(
		[ BROWSELIBRARY, 'items', '_index', '_quantity' ],
	    [ 1, 1, 1, \&cliQuery ]
	);
	
	Slim::Control::Request::addDispatch(
		[ BROWSELIBRARY, 'playlist', '_method' ],
		[ 1, 1, 1, \&cliQuery ]
	);
}

sub _webPages {
	my $class = shift;
	
	require Slim::Web::XMLBrowser;
	Slim::Web::XMLBrowser->init();
	
	Slim::Web::Pages->addPageFunction( $class->tag(), sub {
		my $client = $_[0];
		
		Slim::Web::XMLBrowser->handleWebIndex( {
			client  => $client,
			feed    => $class->feed( $client ),
			type    => $class->type( $client ),
			title   => $class->getDisplayName(),
			timeout => 35,
			args    => \@_
		} );
	} );
	
	
	foreach my $node (@{_getNodeList()}) {
		my $url = 'clixmlbrowser/clicmd=' . $class->tag() . '+items&linktitle=' . $node->{'name'};
		$url .= join('&', ('', map {$_ .'=' . $node->{'params'}->{$_}} keys %{$node->{'params'}}));
		$url .= '/';
		Slim::Web::Pages->addPageLinks("browse", { $node->{'name'} => $url });
		Slim::Web::Pages->addPageLinks('icons', { $node->{'name'} => $node->{'icon'} }) if $node->{'icon'};
	}
}

sub _initModes {
	my $class = shift;
	
	Slim::Buttons::Common::addMode($class->modeName(), {}, sub { $class->setMode(@_) });
	
	foreach my $node (@{_getNodeList()}) {
		Slim::Buttons::Home::addSubMenu('BROWSE_MUSIC', $node->{'name'}, {
			useMode   => $class->modeName(),
			header    => $node->{'name'},
			title     => '{' . $node->{'name'} . '}',
			%{$node->{'params'}},
		});
		if ($node->{'homeMenuText'}) {
			Slim::Buttons::Home::addMenuOption($node->{'name'}, {
				useMode   => $class->modeName(),
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
	
	foreach my $node (@{_getNodeList($albumSort)}) {
		my %menu = (
			text => $client->string($node->{'name'}),
			id   => $node->{'id'},
			node => $baseNode,
			weight => $node->{'weight'},
			actions => {
				go => {
					cmd    => [BROWSELIBRARY, 'items'],
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
	search => \&_search,
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
		$args{'searchTags'}   = \@searchTags if scalar @searchTags;
		$args{'sort'}         = 'sort:' . $params->{'sort'} if $params->{'sort'};
		$args{'search'}       = $params->{'search'} if $params->{'search'};
		$args{'wantMetadata'} = $params->{'wantMetadata'} if $params->{'wantMetadata'};
		
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
				icon => 'html/images/artists.png',
			},
			{
				type => 'link',
				name => _clientString($client, 'BROWSE_BY_ALBUM'),
				url  => \&_albums,
				icon => 'html/images/albums.png',
			},
			{
				type => 'link',
				name => _clientString($client, 'BROWSE_BY_GENRE'),
				url  => \&_genres,
				icon => 'html/images/genres.png',
			},
			{
				type => 'link',
				name => _clientString($client, 'BROWSE_BY_YEAR'),
				url  => \&_years,
				icon => 'html/images/years.png',
			},
			{
				type => 'link',
				name => _clientString($client, 'BROWSE_NEW_MUSIC'),
				url  => \&_albums,
				passthrough => [ { sort => 'sort:new' } ],
				icon => 'html/images/newmusic.png',
			},
			{
				type => 'link',
				name => _clientString($client, 'BROWSE_MUSIC_FOLDER'),
				url  => \&_bmf,
				icon => 'html/images/musicfolder.png',
			},
			{
				type => 'link',
				name => _clientString($client, 'PLAYLISTS'),
				url  => \&_playlists,
				icon => 'html/images/playlists.png',
			},
			{
				name  => _clientString($client, 'SEARCH'),
				icon => 'html/images/search.png',
				items => [
					{
						type => 'search',
						name => _clientString($client, 'BROWSE_BY_ARTIST'),
						icon => 'html/images/search.png',
						url  => \&_artists,
					},
					{
						type => 'search',
						name => _clientString($client, 'BROWSE_BY_ALBUM'),
						icon => 'html/images/search.png',
						url  => \&_albums,
					},
					{
						type => 'search',
						name => _clientString($client, 'BROWSE_BY_SONG'),
						icon => 'html/images/search.png',
						url  => \&_tracks,
					},
					{
						type => 'search',
						name => _clientString($client, 'PLAYLISTS'),
						icon => 'html/images/search.png',
						url  => \&_playlists,
					},
				],
			},
		],
	);

	# Proably should never get here, but just in case
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
			type         => 'link',
			name         => 'BROWSE_BY_ARTIST',
			params       => {mode => 'artists'},
			icon         => 'html/images/artists.png',
			homeMenuText => 'BROWSE_ARTISTS',
			id           => 'myMusicArtists',
			weight       => 10,
		},
		{
			type         => 'link',
			name         => 'BROWSE_BY_ALBUM',
			params       => {mode => 'albums', sort => $albumsSort},
			icon         => 'html/images/albums.png',
			homeMenuText => 'BROWSE_ALBUMS',
			id           => 'myMusicAlbums',
			weight       => 20,
		},
		{
			type         => 'link',
			name         => 'BROWSE_BY_GENRE',
			params       => {mode => 'genres'},
			icon         => 'html/images/genres.png',
			homeMenuText => 'BROWSE_GENRES',
			id           => 'myMusicGenres',
			weight       => 30,
		},
		{
			type         => 'link',
			name         => 'BROWSE_BY_YEAR',
			params       => {mode => 'years'},
			icon         => 'html/images/years.png',
			homeMenuText => 'BROWSE_YEARS',
			id           => 'myMusicYears',
			weight       => 40,
		},
		{
			type         => 'link',
			name         => 'BROWSE_NEW_MUSIC',
			icon         => 'html/images/newmusic.png',
			params       => {mode => 'albums', sort => 'new'},
			id           => 'myMusicNewMusic',
			weight       => 50,
		},
		{
			type         => 'link',
			name         => 'BROWSE_MUSIC_FOLDER',
			params       => {mode => 'bmf'},
			icon         => 'html/images/musicfolder.png',
			condition    => sub {$prefs->get('audiodir');},
			id           => 'myMusicMusicFolder',
			weight       => 70,
		},
		{
			type         => 'link',
			name         => 'SAVED_PLAYLISTS',
			params       => {mode => 'playlists'},
			icon         => 'html/images/playlists.png',
			condition    => sub {
								$prefs->get('playlistdir') ||
				 				(Slim::Schema::hasLibrary && Slim::Schema->rs('Playlist')->getPlaylists->count);
							},
			id           => 'myMusicPlaylists',
			weight       => 80,
		},
		{
			type         => 'link',
			name         => 'SEARCH',
			params       => {mode => 'search'},
			icon         => 'html/images/search.png',
			id           => 'myMusicSearch',
			weight       => 90,
		},
	);
	
	
	if (!Slim::Schema::hasLibrary) {
		return [];
	}
	
	my @nodes;
	
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
		$queryTags,		# array ref: tagged params to pass to CLI query
		$resultsFunc	# func ref:  func(HASHref cliResult) returns (HASHref result, ARRAYref extraItems);
						#            function to process results loop from CLI and generate XMLBrowser items
	) = @_;
	
	my $index = $args->{'index'} || 0;
	my $quantity = $args->{'quantity'};
	
	main::INFOLOG && $log->is_info && $log->info("$query ($index, $quantity): tags ->", join(', ', @$queryTags));
	
	my $request = Slim::Control::Request->new( $client ? $client->id() : undef,
		[ (ref $query ? @$query : $query), $index, $quantity, @$queryTags ] );
	$request->execute();
	
	$quantity ||= 0;
	
	if ( $request->isStatusError() ) {
		$log->error($request->getStatusText());
	}

#	$log->error(Data::Dump::dump($request->getResults()));
	
	
	my ($result, $extraItems) = $resultsFunc->($request->getResults());
	
	$result->{'offset'} = $index;
	my $total = $result->{'total'} = $request->getResults()->{'count'};
	
	# We only add extra-items (typically all-songs) if the total is 2 or more
	if ($extraItems && $total > 1) {
		my $n = scalar @$extraItems;
		$result->{'total'} += $n;
		
		my $nResults = scalar @{$result->{'items'}};
		
		# Work out whether this result block should have the extra items added
		if ($quantity && $index && !$nResults) {
			# Only extra items in this result
			my $usedAlready = $index - $total;
			push @{$result->{'items'}}, @$extraItems[$usedAlready..-1];
		} elsif ($quantity && $nResults < $quantity) {
			my $spaceLeft = $quantity - $nResults;
			push @{$result->{'items'}}, @$extraItems[0..($spaceLeft-1)];
		} else {
			# just add them all
			push @{$result->{'items'}}, @$extraItems;
		}
	}
	
	
#	$log->error(Data::Dump::dump($result));

	$callback->($result);
}

sub _search {
	my ($client, $callback, $args, $pt) = @_;

	my %feed = (
		name  => _clientString($client, 'SEARCH'),
		icon => 'html/images/search.png',
		items => [
			{
				type => 'search',
				name => _clientString($client, 'BROWSE_BY_ARTIST'),
				icon => 'html/images/search.png',
				url  => \&_artists,
			},
			{
				type => 'search',
				name => _clientString($client, 'BROWSE_BY_ALBUM'),
				icon => 'html/images/search.png',
				url  => \&_albums,
			},
			{
				type => 'search',
				name => _clientString($client, 'BROWSE_BY_SONG'),
				icon => 'html/images/search.png',
				url  => \&_tracks,
			},
			{
				type => 'search',
				name => _clientString($client, 'PLAYLISTS'),
				icon => 'html/images/search.png',
				url  => \&_playlists,
			},
		],
	);
	
	$callback->( \%feed );
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
	
	my @ptSearchTags;
	if ($prefs->get('noGenreFilter')) {
		@ptSearchTags = grep {$_ !~ /^genre_id:/} @searchTags;
	} else {
		@ptSearchTags = @searchTags;
	}

	_generic($client, $callback, $args, 'artists', 
		['tags:s', @searchTags, ($search ? 'search:' . $search : undef)],
		sub {
			my $results = shift;
			my $items = $results->{'artists_loop'};
			foreach (@$items) {
				$_->{'name'}          = $_->{'artist'};
				$_->{'type'}          = 'playlist';
				$_->{'playlist'}      = \&_tracks;
				$_->{'url'}           = \&_albums;
				$_->{'passthrough'}   = [ { searchTags => [@ptSearchTags, "artist_id:" . $_->{'id'}] } ];
				$_->{'favorites_url'} = 'db:contributor.namesearch=' .
						URI::Escape::uri_escape_utf8( Slim::Utils::Text::ignoreCaseArticles($_->{'name'}) );
			}
			my $extra;
			if (scalar @searchTags) {
				my $params = _tagsToParams(\@searchTags);
				$extra = [ {
					name        => _clientString($client, 'ALL_ALBUMS'),
					type        => 'playlist',
					playlist    => \&_tracks,
					url         => \&_albums,
					passthrough => [{ searchTags => \@searchTags }],
					itemActions => {
						allAvailableActionsDefined => 1,
						info => {
							command     => [],
						},
						items => {
							command     => [BROWSELIBRARY, 'items'],
							fixedParams => {
								mode       => 'albums',
								%$params,
							},
						},
						play => {
							command     => ['playlistcontrol'],
							fixedParams => {cmd => 'load', %$params},
						},
						add => {
							command     => ['playlistcontrol'],
							fixedParams => {cmd => 'add', %$params},
						},
						insert => {
							command     => ['playlistcontrol'],
							fixedParams => {cmd => 'insert', %$params},
						},
					},					
				} ];
			}
			
			my $params = _tagsToParams(\@ptSearchTags);
			my %actions = (
				allAvailableActionsDefined => 1,
				commonVariables	=> [artist_id => 'id'],
				info => {
					command     => ['artistinfo', 'items'],
				},
				items => {
					command     => [BROWSELIBRARY, 'items'],
					fixedParams => {
						mode       => 'albums',
						%$params,
					},
				},
				play => {
					command     => ['playlistcontrol'],
					fixedParams => {cmd => 'load', %$params},
				},
				add => {
					command     => ['playlistcontrol'],
					fixedParams => {cmd => 'add', %$params},
				},
				insert => {
					command     => ['playlistcontrol'],
					fixedParams => {cmd => 'insert', %$params},
				},
			);
			$actions{'playall'} = $actions{'play'};
			$actions{'addall'} = $actions{'add'};
			
			return {items => $items, actions => \%actions, sorted => 1}, $extra;
		},
	);
}

sub _genres {
	my ($client, $callback, $args, $pt) = @_;
	my @searchTags = $pt->{'searchTags'} ? @{$pt->{'searchTags'}} : ();

	_generic($client, $callback, $args, 'genres', ['tags:s', @searchTags],
		sub {
			my $results = shift;
			my $items = $results->{'genres_loop'};
			foreach (@$items) {
				$_->{'name'}          = $_->{'genre'};
				$_->{'type'}          = 'playlist';
				$_->{'playlist'}      = \&_tracks;
				$_->{'url'}           = \&_artists;
				$_->{'passthrough'}   = [ { searchTags => [@searchTags, "genre_id:" . $_->{'id'}] } ];
				$_->{'favorites_url'} = 'db:genre.namesearch=' .
						URI::Escape::uri_escape_utf8( Slim::Utils::Text::ignoreCaseArticles($_->{'name'}) );
			};
			
			my %actions = (
				allAvailableActionsDefined => 1,
				commonVariables	=> [genre_id => 'id'],
				info => {
					command     => ['genreinfo', 'items'],
				},
				items => {
					command     => [BROWSELIBRARY, 'items'],
					fixedParams => {mode => 'artists'},
				},
				play => {
					command     => ['playlistcontrol'],
					fixedParams => {cmd => 'load'},
				},
				add => {
					command     => ['playlistcontrol'],
					fixedParams => {cmd => 'add'},
				},
				insert => {
					command     => ['playlistcontrol'],
					fixedParams => {cmd => 'insert'},
				},
			);
			$actions{'playall'} = $actions{'play'};
			$actions{'addall'} = $actions{'add'};
			
			return {items => $items, actions => \%actions, sorted => 1}, undef;
		},
	);
}

sub _years {
	my ($client, $callback, $args, $pt) = @_;
	my @searchTags = $pt->{'searchTags'} ? @{$pt->{'searchTags'}} : ();
	
	_generic($client, $callback, $args, 'years', \@searchTags,
		sub {
			my $results = shift;
			my $items = $results->{'years_loop'};
			foreach (@$items) {
				$_->{'name'}          = $_->{'year'};
				$_->{'type'}          = 'playlist';
				$_->{'playlist'}      = \&_tracks;
				$_->{'url'}           = \&_albums;
				$_->{'passthrough'}   = [ { searchTags => [@searchTags, "year:" . $_->{'year'}] } ];
				$_->{'favorites_url'} = 'db:year.id=' . ($_->{'name'} || 0 );
			};
			
			my %actions = (
				allAvailableActionsDefined => 1,
				commonVariables	=> [year => 'name'],
				info => {
					command     => ['yearinfo', 'items'],
				},
				items => {
					command     => [BROWSELIBRARY, 'items'],
					fixedParams => {
						mode       => 'albums',
					},
				},
				play => {
					command     => ['playlistcontrol'],
					fixedParams => {cmd => 'load'},
				},
				add => {
					command     => ['playlistcontrol'],
					fixedParams => {cmd => 'add'},
				},
				insert => {
					command     => ['playlistcontrol'],
					fixedParams => {cmd => 'insert'},
				},
			);
			$actions{'playall'} = $actions{'play'};
			$actions{'addall'} = $actions{'add'};
			
			return {items => $items, actions => \%actions, sorted => 1}, undef;
		},
	);
}

sub _albums {
	my ($client, $callback, $args, $pt) = @_;
	my @searchTags = $pt->{'searchTags'} ? @{$pt->{'searchTags'}} : ();
	my $sort       = $pt->{'sort'};
	my $search     = $pt->{'search'};
	my $getMetadata= $pt->{'wantMetadata'}; 
	my $tags       = 'ljsa';

	if (!$search && !scalar @searchTags && $args->{'search'}) {
		$search = $args->{'search'};
	}
	
	$tags .= 'ywXiq' if $getMetadata;
	
	my @artistIds = grep /artist_id:/, @searchTags;
	my ($artistId) = ($artistIds[0] =~ /artist_id:(\d+)/) if @artistIds;

	$tags .= 'S' if ($artistId || $getMetadata);
	
	_generic($client, $callback, $args, 'albums',
		["tags:$tags", @searchTags, ($sort ? $sort : ()), ($search ? 'search:' . $search : undef)],
		sub {
			my $results = shift;
			my $items = $results->{'albums_loop'};
			foreach (@$items) {
				$_->{'name'}          = $_->{'album'};
				$_->{'image'}         = ($_->{'artwork_track_id'} ? 'music/' . $_->{'artwork_track_id'} . '/cover' : undef);
				$_->{'type'}          = 'playlist';
				$_->{'playlist'}      = \&_tracks;
				$_->{'url'}           = \&_tracks;
				$_->{'passthrough'}   = [ { searchTags => [@searchTags, "album_id:" . $_->{'id'}], sort => 'sort:tracknum' } ];
				# the favorites url is the album title here
				# album id would be (much) better, but that would screw up the favorite on a rescan
				# title is a really stupid thing to use, since there's no assurance it's unique
				$_->{'favorites_url'} = 'db:album.titlesearch=' .
						URI::Escape::uri_escape_utf8( Slim::Utils::Text::ignoreCaseArticles($_->{'name'}) );
				
				# If an artist was not used in the selection criteria or if one was
				# used but is different to that of the primary artist, then provide 
				# the primary artist name in name2.
				if (!$artistId || $artistId != $_->{'id'}) {
					$_->{'name2'} = $_->{'artist'};
				}
				if ($getMetadata) {
					$_->{'metadata'}->{'year'} = {
							name		=> $_->{'year'},
							id			=> $_->{'year'},
						} if $_->{'year'};
					$_->{'metadata'}->{'disc'} = $_->{'disc'} if $_->{'disc'};
					$_->{'metadata'}->{'disccount'} = $_->{'disccount'} if $_->{'disccount'};
					$_->{'metadata'}->{'album'} = {
							name         => $_->{'album'},
							id           => $_->{'id'},
							replay_gain  => $_->{'replay_gain'},
							compilation  => $_->{'compilation'},
						};
					$_->{'metadata'}->{'contributors'} = {
							ARTIST => [
								{
									name => $_->{'artist'},
									id   => $_->{'artist_id'},
								},
							],
						} if $_->{'artist_id'};
				}
			}
			my $extra;
			if (scalar @searchTags) {
				my $params = _tagsToParams(\@searchTags);
				my %actions = (
					allAvailableActionsDefined => 1,
					info => {
						command     => [],
					},
					items => {
						command     => [BROWSELIBRARY, 'items'],
						fixedParams => {
							mode       => 'tracks',
							%{&_tagsToParams(\@searchTags)},
						},
					},
					play => {
						command     => ['playlistcontrol'],
						fixedParams => {cmd => 'load', %$params},
					},
					add => {
						command     => ['playlistcontrol'],
						fixedParams => {cmd => 'add', %$params},
					},
					insert => {
						command     => ['playlistcontrol'],
						fixedParams => {cmd => 'insert', %$params},
					},
				);
				$actions{'playall'} = $actions{'play'};
				$actions{'addall'} = $actions{'add'};
				
				$extra = [ {
					name        => _clientString($client, 'ALL_SONGS'),
					image       => 'music/all_items/cover',
					type        => 'playlist',
					playlist    => \&_tracks,
					url         => \&_tracks,
					passthrough => [{ searchTags => \@searchTags, sort => 'sort:title', menuStyle => 'allSongs' }],
					itemActions => \%actions,
				} ];
			}
			
			my %actions = (
				allAvailableActionsDefined => 1,
				commonVariables	=> [album_id => 'id'],
				info => {
					command     => ['albuminfo', 'items'],
				},
				items => {
					command     => [BROWSELIBRARY, 'items'],
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
			);
			$actions{'playall'} = $actions{'play'};
			$actions{'addall'} = $actions{'add'};
			
			return {
				items   => $items,
				actions => \%actions,
				sorted  => (($sort && $sort =~ /:new/) ? 0 : 1),
			}, $extra;
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

	_generic($client, $callback, $args, 'titles',
		['tags:dtux', $sort, $menuStyle, @searchTags, ($search ? 'search:' . $search : undef)],
		sub {
			my $results = shift;
			my $items = $results->{'titles_loop'};
			foreach (@$items) {
				my $tracknum = $_->{'tracknum'} ? $_->{'tracknum'} . '. ' : '';
				$_->{'name'}          = $tracknum . $_->{'title'};
				$_->{'type'}          = 'audio';
				$_->{'playall'}       = 1;
				$_->{'play_index'}    = $offset++;
			}
			
			my %actions = (
				commonVariables	=> [track_id => 'id'],
				allAvailableActionsDefined => 1,
				
				info => {
					command     => ['trackinfo', 'items'],
				},
				play => {
					command     => ['playlistcontrol'],
					fixedParams => {cmd => 'load'},
				},
				add => {
					command     => ['playlistcontrol'],
					fixedParams => {cmd => 'add'},
				},
				insert => {
					command     => ['playlistcontrol'],
					fixedParams => {cmd => 'insert'},
				},
			);
			$actions{'items'} = $actions{'info'};

			if ($search) {
				$actions{'playall'} = $actions{'play'};
				$actions{'addall'} = $actions{'all'};
			} else {
				$actions{'playall'} = {
					command     => ['playlistcontrol'],
					fixedParams => {cmd => 'load', %{&_tagsToParams([@searchTags, $sort])}},
					variables	=> [play_index => 'play_index'],
				};
				$actions{'addall'} = {
					command     => ['playlistcontrol'],
					variables	=> [],
					fixedParams => {cmd => 'add', %{&_tagsToParams([@searchTags, $sort])}},
				};
			}
			
			return {items => $items, actions => \%actions, sorted => 0}, undef;
		},
	);
}


sub _bmf {
	my ($client, $callback, $args, $pt) = @_;
	my @searchTags = $pt->{'searchTags'} ? @{$pt->{'searchTags'}} : ();
	
	_generic($client, $callback, $args, 'musicfolder', ['tags:dus', @searchTags],
		sub {
			my $results = shift;
			my $gotsubfolder = 0;
			my $items = $results->{'folder_loop'};
			foreach (@$items) {
				$_->{'name'} = $_->{'filename'};
				if ($_->{'type'} eq 'folder') {
					$_->{'type'}        = 'link';
					$_->{'url'}         = \&_bmf;
					$_->{'passthrough'} = [ { searchTags => [ "folder_id:" . $_->{'id'} ] } ];
					$_->{'itemActions'} = {
						info => {
							command     => ['folderinfo', 'items'],
							fixedParams => {folder_id =>  $_->{'id'}},
						},
					};
					$gotsubfolder = 1;
				}  elsif ($_->{'type'} eq 'track') {
					$_->{'type'}        = 'audio';
					$_->{'playall'}     = 1;
					$_->{'itemActions'} = {
						info => {
							command     => ['trackinfo', 'items'],
							fixedParams => {track_id =>  $_->{'id'}},
						},
					};
					$_->{'itemActions'}->{'items'} = $_->{'itemActions'}->{'info'};
				}  elsif ($_->{'type'} eq 'playlist') {
					$_->{'type'}        = 'text';
				}  else # if ($_->{'type'} eq 'unknown') 
				{
					$_->{'type'}        = 'text';
				}
			}
			return {items => $items, sorted => 1}, undef;
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

	_generic($client, $callback, $args, 'playlists',
		['tags:s', @searchTags, ($search ? 'search:' . $search : undef)],
		sub {
			my $results = shift;
			my $items = $results->{'playlists_loop'};
			foreach (@$items) {
				$_->{'name'}        = $_->{'playlist'};
				$_->{'type'}        = 'playlist';
				$_->{'playlist'}    = \&_playlistTracks;
				$_->{'url'}         = \&_playlistTracks;
				$_->{'passthrough'} = [ { searchTags => [ @searchTags, 'playlist_id:' . $_->{'id'} ], } ];
			};
			
			my %actions = (
				allAvailableActionsDefined => 1,
				commonVariables	=> [playlist_id => 'id'],
				info => {
					command     => ['playlistinfo', 'items'],
				},
				items => {
					command     => [BROWSELIBRARY, 'items'],
					fixedParams => {
						mode       => 'playlistTracks',
						%{&_tagsToParams(\@searchTags)},
					},
				},
				play => {
					command     => ['playlistcontrol'],
					fixedParams => {cmd => 'load'},
				},
				add => {
					command     => ['playlistcontrol'],
					fixedParams => {cmd => 'add'},
				},
				insert => {
					command     => ['playlistcontrol'],
					fixedParams => {cmd => 'insert'},
				},
			);
			$actions{'playall'} = $actions{'play'};
			$actions{'addall'} = $actions{'add'};
			
			return {items => $items, actions => \%actions, sorted => 1}, undef;
			
		},
	);
}

sub _playlistTracks {
	my ($client, $callback, $args, $pt) = @_;
	my @searchTags = $pt->{'searchTags'} ? @{$pt->{'searchTags'}} : ();
	my $menuStyle  = $pt->{'menuStyle'} || 'menuStyle:album';
	my $offset     = $args->{'index'} || 0;
	
	_generic($client, $callback, $args, ['playlists', 'tracks'], 
		['tags:dtu', $menuStyle, @searchTags],
		sub {
			my $results = shift;
			my $items = $results->{'playlisttracks_loop'};
			foreach (@$items) {
				my $tracknum = $_->{'tracknum'} ? $_->{'tracknum'} . '. ' : '';
				$_->{'name'}        = $tracknum . $_->{'title'};
				$_->{'type'}        = 'audio';
				$_->{'playall'}     = 1;
				$_->{'play_index'}  = $offset++;
			}

			my %actions = (
					commonVariables	=> [track_id => 'id', url => 'url'],
					info => {
						command     => ['trackinfo', 'items'],
					},
					playall => {
						command     => ['playlistcontrol'],
						fixedParams => {cmd => 'load', %{&_tagsToParams(\@searchTags)}},
						variables	=> [play_index => 'play_index'],
					},
					addall => {
						command     => ['playlistcontrol'],
						variables	=> [],
						fixedParams => {cmd => 'add', %{&_tagsToParams(\@searchTags)}},
					},
				);
			$actions{'items'} = $actions{'info'};

			# Maybe add delete-item and add-to-favourites
			
			return {items => $items, actions => \%actions, sorted => 0}, undef;
		}
	);
}

sub getDisplayName () {
	return 'MY_MUSIC';
}

sub playerMenu {'PLUGINS'}


1;
