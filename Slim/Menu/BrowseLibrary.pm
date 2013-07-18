package Slim::Menu::BrowseLibrary;

# $Id$

=head1 NAME

Slim::Menu::BrowseLibrary

=head1 SYNOPSIS

	use Slim::Menu::BrowseLibrary;
	
	Slim::Menu::BrowseLibrary->registerNode({
		type         => 'link',
		name         => 'MYMUSIC_MENU_ITEM_TITLE',
		params       => {mode => 'myNewMode'},
		feed         => \&myFeed,
		icon         => 'html/images/someimage.png',
		homeMenuText => 'HOMEMENU_MENU_ITEM_TITLE',
		condition    => sub {my ($client, $nodeId) = @_; return 1;}
		id           => 'myNewModeId',
		weight       => 30,
	});
	
	Slim::Menu::BrowseLibrary->deregisterNode('someNodeId');
	
	Slim::Menu::BrowseLibrary->registerNodeFilter(\&nodeFilter);
	
	Slim::Menu::BrowseLibrary->deregisterNodeFilter(\&nodeFilter);

=head1 DESCRIPTION

Register or deregister menu items for the My Music menu.

Register or deregister filter functions used to determine if a menu
item should be included in the My Music menu, possibly for a specific client.

=head2 registerNode()

The new menu item is specified using a HASH-ref as follows (mandatory items marked with *):

=over

=item C<type>*

C<link> | C<search>

=item C<id>*

Unique identifier for the menu item

=item C<name>*

Unique string name for the menu item title when used in the My Music menu

=item C<homeMenuText>

Unique string name for the menu item title when used in the Home menu

=item C<feed>*

reference to a function that is invoked in the manner of an XMLBrowser function feed

=item C<icon>

Icon to be used with menu item

=item C<condition>

function to determine dynamically whether this menu item should be shown in the menu

=item C<weight>

Hint as to relative position of item in menu

=item C<params>

HASH-ref containing:

=over

=item C<mode>

This will default to the value of the C<id> of the menu item.
If one of C<artists, albums, genres, years, tracks, playlists, playlistTracks, bmf>
is used then it will override the default method from BrowseLibrary - use with caution.

=item C<sort track_id artist_id genre_id album_id playlist_id year folder_id>

When browsing to a deeper level in the menu hierarchy,
then any of these values (and only these values)
will be passed in the C<params> value of the I<args> HASH-ref passed as the third parameter
to the C<feed> function as part of the (re)navigation to the sub-menu(s).

Any search-input string will also be so passed as the C<search> value.

=back

All values of this C<params> HASH will be passed in the C<params> value
of the I<args> HASH-ref passed as the third parameter to the C<feed> function
when it is invoked at the top level.

=back

Note that both C<id> and C<name> should be unique 
and should not be one of the standard IDs or name strings used by BrowseLibrary.
That means that if, for example, one wants to replace the B<Artists> menu item,
one cannot use C<BROWSE_BY_ARTIST> as the C<name> string;
one must supply one's own string with a unique name,
but quite possibly using the same localized string values.

=head2 deregisterNode()

Remove a previously registered menu item specified by its C<id>.

I<Caution:> will not restore any default BrowseLibrary handlers that had been overridden
using a C<params =E<gt> mode> value of one of the default handlers.

=head2 registerNodeFilter()

Register a function to be called when a menu is being displayed to determine whether that 
menu item should be included.

Passed the Slim::Player::Client for which the menu is being built, if it is a client-specific menu,
and the C<id> of the menu item.

Multiple filter functions can be registered.

If the condition associated with a menu item itself (if any),
or any of the registered filter functions,
return false then the menu item will not be included;
otherwise it will be included.

=head2 deregisterNodeFilter()

Deregister a menu-item filter.
If this method is going to be called then both registerNodeFilter() & deregisterNodeFilter()
should be passed a reference to a real sub (not an anonymous one).

=cut


use strict;
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(cstring);

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

my $_initialized = 0;
my $_pendingChanges = 0;
my %nodes;
my @addedNodes;
my @deletedNodes;

my %browseLibraryModeMap = (
	tracks => \&_tracks,				# needs to be here because no top-level menu added via registerNode()
	playlistTracks => \&_playlistTracks,# needs to be here because no top-level menu added via registerNode()
);

my %nodeFilters;

sub registerNodeFilter {
	my ($class, $filter) = @_;
	
	if (!ref $filter eq 'CODE') {
		$log->error("Invalid filter: must be a CODE ref");
		return;
	}
	
	$nodeFilters{$filter} = $filter;
}

sub deregisterNodeFilter {
	my ($class, $filter) = @_;
	
	delete $nodeFilters{$filter};
}

sub registerNode {
	my ($class, $node) = @_;
	
	return unless $node->{'id'};
	
	if (!$node->{'id'} || ref $node->{'feed'} ne 'CODE') {
		logBacktrace('Invalid node specification');
		return 0;
	}
	
	if ($nodes{$node->{'id'}}) {
		logBacktrace('Duplicate node id: ', $node->{'id'});
		return 0;
	}
	
	$node->{'params'}->{'mode'} ||= $node->{'id'};
	$nodes{$node->{'id'}} = $node;
	$browseLibraryModeMap{$node->{'params'}->{'mode'}} = $node->{'feed'};

	# browse menu can contain a mix of browselibrary nodes and plugin nodes
	# ensure they are sorted consistently on all interfaces by always comparing weights
	Slim::Plugin::Base->getWeights()->{ $node->{'name'} } = $node->{'weight'};

	$class->_scheduleMenuChanges($node, undef);
	
	return 1;
}

sub deregisterNode {
	my ($class, $id) = @_;
	
	if (my $node = delete $nodes{$id}) {
		if ($browseLibraryModeMap{$node->{'params'}->{'mode'}} == $node->{'feed'}) {
			delete $browseLibraryModeMap{$node->{'params'}->{'mode'}};
		}
		delete Slim::Plugin::Base->getWeights()->{ $node->{'name'} };
		$class->_scheduleMenuChanges(undef, $node);
	}
}


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
	
	$class->_registerBaseNodes();

	$class->_initCLI();
	
	if ( main::WEBUI ) {
		$class->_webPages;
	}

#	$class->_initSubmenus();
	
    $class->_initModes();
    
    Slim::Menu::GlobalSearch->registerInfoProvider( searchMyMusic => (
			isa  => 'top',
			func => \&_globalSearchMenu,
	) );
    
    Slim::Control::Request::subscribe(\&_libraryChanged, [['library'], ['changed']]);
    
    $_initialized = 1;
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
	    [ 0, 1, 1, \&cliQuery ]
	);
	
	Slim::Control::Request::addDispatch(
		[ BROWSELIBRARY, 'playlist', '_method' ],
		[ 1, 1, 1, \&cliQuery ]
	);
}

sub _addWebLink {
	my ($class, $node) = @_;

	my $url = 'clixmlbrowser/clicmd=' . $class->tag() . '+items&linktitle=' . $node->{'name'};
	$url .= join('&', ('', map {$_ .'=' . $node->{'params'}->{$_}} keys %{$node->{'params'}}));
	$url .= '/';
	Slim::Web::Pages->addPageLinks("browse", { $node->{'name'} => $url });
	Slim::Web::Pages->addPageCondition($node->{'name'} => sub {
		return _conditionWrapper(shift, $node->{'id'}, $node->{'condition'})
	});
	Slim::Web::Pages->addPageLinks('icons', { $node->{'name'} => $node->{'icon'} }) if $node->{'icon'};
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
		$class->_addWebLink($node);
	}
}

sub _addMode {
	my ($class, $node) = @_;
	
	Slim::Buttons::Home::addSubMenu('BROWSE_MUSIC', $node->{'name'}, {
		useMode   => $class->modeName(),
		header    => $node->{'name'},
		condition => sub {return _conditionWrapper(shift, $node->{'id'}, $node->{'condition'});},
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

sub _initModes {
	my $class = shift;
	
	Slim::Buttons::Common::addMode($class->modeName(), {}, sub { $class->setMode(@_) });
	
	foreach my $node (@{_getNodeList()}) {
		$class->_addMode($node);
	}
}

my $jiveUpdateCallback = undef;

sub _libraryChanged {
	if ($jiveUpdateCallback) {
		$jiveUpdateCallback->();
	}
}

sub _scheduleMenuChanges {
	my $class = shift;
	
	my ($add, $del) = @_;
	
	return if !$_initialized;
	
	push @addedNodes, $add if $add;
	push @deletedNodes, $del if $del;
	
	return if $_pendingChanges;
	
	Slim::Utils::Timers::setTimer($class, Time::HiRes::time() + 1, \&_handleMenuChanges);

	$_pendingChanges = 1;
}

sub _handleMenuChanges {
	my $class = shift;
	# do deleted first, then added
	
	foreach my $node (@deletedNodes) {

		Slim::Buttons::Home::delSubMenu('BROWSE_MUSIC', $node->{'name'});
		if ($node->{'homeMenuText'}) {
			Slim::Buttons::Home::delMenuOption($node->{'name'});
		}
	
		if ( main::WEBUI ) {
			Slim::Web::Pages->delPageLinks("browse", $node->{'name'});
			Slim::Web::Pages->delPageLinks('icons', $node->{'name'}) if $node->{'icon'};
		}
	}
	
	foreach my $node (@addedNodes) {
		$class->_addMode($node);
		$class->_addWebLink($node) if main::WEBUI;
	}
	
	@addedNodes = ();
	@deletedNodes = ();
	$_pendingChanges = 0;

	_libraryChanged();
}

sub _conditionWrapper {
	my ($client, $id, $baseCondition) = @_;
	
	if ($baseCondition && !$baseCondition->($client, $id)) {
		return 0;
	}
	
	foreach my $filter (values %nodeFilters) {
		my $status;
		
		eval {
			$status = $filter->($client, $id)
		};
		
		if ($@) {
			$log->warn("Couldn't call menu-filter", Slim::Utils::PerlRunTime::realNameForCodeRef($filter), ": $@");
			# Assume true
			next;
		}
		
		if (!$status) {
			return 0;
		}
	}
	
	return 1;
}

sub _getNodeList {
	return [values %nodes];
}

sub _registerBaseNodes {
	my $class = shift;
	
	my @topLevel = (
		{
			type         => 'link',
			name         => 'BROWSE_BY_ARTIST',
			params       => {mode => 'artists'},
			feed         => \&_artists,
			icon         => 'html/images/artists.png',
			homeMenuText => 'BROWSE_ARTISTS',
			condition    => \&Slim::Schema::hasLibrary,
			id           => 'myMusicArtists',
			weight       => 10,
		},
		{
			type         => 'link',
			name         => 'BROWSE_BY_ALBUM',
			params       => {mode => 'albums'},
			feed         => \&_albums,
			icon         => 'html/images/albums.png',
			homeMenuText => 'BROWSE_ALBUMS',
			condition    => \&Slim::Schema::hasLibrary,
			id           => 'myMusicAlbums',
			weight       => 20,
		},
		{
			type         => 'link',
			name         => 'BROWSE_BY_GENRE',
			params       => {mode => 'genres'},
			feed         => \&_genres,
			icon         => 'html/images/genres.png',
			homeMenuText => 'BROWSE_GENRES',
			condition    => \&Slim::Schema::hasLibrary,
			id           => 'myMusicGenres',
			weight       => 30,
		},
		{
			type         => 'link',
			name         => 'BROWSE_BY_YEAR',
			params       => {mode => 'years'},
			feed         => \&_years,
			icon         => 'html/images/years.png',
			homeMenuText => 'BROWSE_YEARS',
			condition    => \&Slim::Schema::hasLibrary,
			id           => 'myMusicYears',
			weight       => 40,
		},
		{
			type         => 'link',
			name         => 'BROWSE_NEW_MUSIC',
			icon         => 'html/images/newmusic.png',
			params       => {mode => 'albums', sort => 'new', wantMetadata => 1},
			                                                  # including wantMetadata is a hack for ip3k
			feed         => \&_albums,
			homeMenuText => 'BROWSE_NEW_MUSIC',
			condition    => \&Slim::Schema::hasLibrary,
			id           => 'myMusicNewMusic',
			weight       => 50,
		},
		{
			type         => 'link',
			name         => 'BROWSE_MUSIC_FOLDER',
			params       => {mode => 'bmf'},
			feed         => \&_bmf,
			icon         => 'html/images/musicfolder.png',
			homeMenuText => 'BROWSE_MUSIC_FOLDER',
			condition    => sub {return Slim::Schema::hasLibrary && scalar @{ Slim::Utils::Misc::getAudioDirs() };},
			id           => 'myMusicMusicFolder',
			weight       => 70,
		},
		{
			type         => 'link',
			name         => 'SAVED_PLAYLISTS',
			params       => {mode => 'playlists'},
			feed         => \&_playlists,
			icon         => 'html/images/playlists.png',
			condition    => \&Slim::Schema::hasLibrary,
			condition    => sub {
								return Slim::Utils::Misc::getPlaylistDir() ||
									# this might be expensive - perhaps need to cache this somehow
					 				(Slim::Schema::hasLibrary && Slim::Schema->rs('Playlist')->getPlaylists->count);
							},
			id           => 'myMusicPlaylists',
			weight       => 80,
		},
		{
			type         => 'link',
			name         => 'SEARCH',
			params       => {mode => 'search'},
			feed         => \&_search,
			icon         => 'html/images/search.png',
			condition    => \&Slim::Schema::hasLibrary,
			id           => 'myMusicSearch',
			weight       => 90,
		},
	);
	
	foreach (@topLevel) {
		$class->registerNode($_);
	}
}

sub getJiveMenu {
	my ($client, $baseNode, $updateCallback) = @_;
	
	$jiveUpdateCallback = $updateCallback if $updateCallback;
	
	my @myMusicMenu;
	
	foreach my $node (@{_getNodeList()}) {
		if (!_conditionWrapper($client, $node->{'id'}, $node->{'condition'})) {
			next;
		}
		
		my %menu = (
			text => cstring($client, $node->{'name'}),
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
			$menu{'homeMenuText'} = cstring($client, $node->{'homeMenuText'});
		}
		
		# Default nodes use id to automatically set iconStyle on squeezeplay clients
		# The following allow nodes to set the iconStyle or icon explicity
		if ($node->{'iconStyle'}) {
			$menu{'iconStyle'} = $node->{'iconStyle'};
		}

		if ($node->{'jiveIcon'}) {
			$menu{'icon'} = $node->{'jiveIcon'};
		}

		push @myMusicMenu, \%menu;
	}
	
	return \@myMusicMenu;
}

sub setMode {
	my ( $class, $client, $method, $mode, $name ) = @_;

	if ($method eq 'pop') {

		Slim::Buttons::Common::popMode($client);
		return;
	}

	my $modeName = $class->getDisplayName();
	$name ||= $modeName;
	my $title = (uc($name) eq $name) ? cstring($client,  $name ) : $name;
	
	my %params = (
		header   => $name,
		modeName => $modeName,
		url      => $class->feed( $client ),
		title    => $title,
		timeout  => 35,
		mode     => $mode,
		%{$client->modeParams()},
	);
	Slim::Buttons::Common::pushModeLeft( $client, 'xmlbrowser', \%params );
	
	# we'll handle the push in a callback
	$client->modeParam( handledTransition => 1 );
}

my @topLevelArgs = qw(track_id artist_id genre_id album_id playlist_id year folder_id);

sub _topLevel {
	my ($client, $callback, $args) = @_;
	my $params = $args->{'params'};
	
	if ($params) {
		my %args;

		if ($params->{'query'} && $params->{'query'} =~ /C<$1>=(.*)/) {
			$params->{$1} = $2;
		}

		my @searchTags;
		for (@topLevelArgs) {
			push (@searchTags, $_ . ':' . $params->{$_}) if $params->{$_};
		}
		$args{'searchTags'}   = \@searchTags if scalar @searchTags;
		$args{'sort'}         = 'sort:' . $params->{'sort'} if $params->{'sort'};
		$args{'orderBy'}      = 'sort:' . $params->{'orderBy'} if $params->{'orderBy'};
		$args{'search'}       = $params->{'search'} if $params->{'search'};
		$args{'wantMetadata'} = $params->{'wantMetadata'} if $params->{'wantMetadata'};
		$args{'wantIndex'}    = $params->{'wantIndex'} if $params->{'wantIndex'};
		
		if ($params->{'mode'}) {
			my %entryParams;
			for (@topLevelArgs, qw(sort search mode)) {
				$entryParams{$_} = $params->{$_} if $params->{$_};
			}
			main::INFOLOG && $log->is_info && $log->info('params=>', join('&', map {$_ . '=' . $entryParams{$_}} keys(%entryParams)));
			
			my $func = $browseLibraryModeMap{$params->{'mode'}};
			
			if (ref $func ne 'CODE') {
				$log->error('No feed method for mode: ', $params->{'mode'});
				return;
			}
			
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
	
	$log->error("Routing failure: node mode param");
}

sub _generic {
	my ($client,
		$callback,      # func ref:  Callback function to XMLbowser: callback(hashOrArray_ref)
		$args,          # hash ref:  Additional parameters from XMLBrowser
		$query,         # string:    CLI query, single verb or array-ref;
                        #            command takes _index, _quantity and tagged params
		$queryTags,     # array ref: tagged params to pass to CLI query
		$resultsFunc,   # func ref:  func(HASHref cliResult) returns (HASHref result, ARRAYref extraItems);
						#            function to process results loop from CLI and generate XMLBrowser items
		$tags,          # string:    (optional) the value of the 'tags'	parameter to use - added to queryTags
		$getIndexList   # boolean:   (optional)
	) = @_;
	
	if (!Slim::Schema::hasLibrary()) {
	
		$log->warn('Database not fully initialized yet - return dummy placeholder');
	
		logBacktrace('no callback') unless $callback;
	
		$callback->({
			items => [ {
				type  => 'text',
				title => cstring($client, 'LIBRARY_NOT_READY'),
			} ],
			total => 1
		});
		
		return;
	}
	
	my $index = $args->{'index'} || 0;
	my $quantity = $args->{'quantity'};
	
	my $indexList;
	
	if ($getIndexList && $quantity && $quantity != 1) {
		# quantity == 1 is special and only used when (re)traversing the tree before getting to the desired leaf
		
		# Get the page-bar and update quantity if necessary so that all of the last category is returned
		
		my @newTags = @$queryTags;
		push @newTags, 'tags:' . ($tags || '') . 'ZZ';
		
		main::INFOLOG && $log->is_info && $log->info("$query (0, 1): tags ->", join(', ', @newTags));
		
		my $request = Slim::Control::Request->new( $client ? $client->id() : undef,
			[ (ref $query ? @$query : $query), 0, 1, @newTags ] );
		$request->execute();
		if ( $request->isStatusError() ) {
			$log->error($request->getStatusText());
		}

		# find where our index starts and then where it needs to end
		if ($indexList = $request->getResult('indexList')) {
			my $total = 0;
			foreach (@$indexList) {
				$total += $_->[1];
				if ($total >= $index + $quantity) {
					$quantity = $total - $index;
					last;
				}
			}
		}
	}
	
	push @$queryTags, 'tags:' . $tags if defined $tags;
	
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

	$result->{'indexList'} = $indexList if defined $indexList;
	$result->{'offset'}    = $index;
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
			push @{$result->{'items'}}, @$extraItems[$usedAlready..$#$extraItems];
		} elsif ($quantity && $nResults < $quantity) {
			my $spaceLeft = $quantity - $nResults;
			$spaceLeft = scalar @$extraItems if scalar @$extraItems < $spaceLeft;
			push @{$result->{'items'}}, @$extraItems[0..($spaceLeft-1)];
		} else {
			# just add them all
			push @{$result->{'items'}}, @$extraItems;
		}
	}
	
	if ( !$args->{search} && (!$result->{items} || !scalar @{ $result->{items} }) ) {
		$result->{items} = [ {
			type  => 'text',
			title => cstring($client, 'EMPTY'),
		} ];
		
		$result->{total} = 1;
	}
		
#	$log->error(Data::Dump::dump($result));

	logBacktrace('no callback') unless $callback;

	$callback->($result);
}

sub _search {
	my ($client, $callback, $args, $pt) = @_;

	my %feed = (
		name  => cstring($client, 'SEARCH'),
		icon => 'html/images/search.png',
		items => searchItems($client),
	);
	
	$callback->( \%feed );
}

sub _globalSearchMenu {
	my ( $client, $tags ) = @_;
	
	my $items = searchItems($client);
	
	foreach (@$items) {$_->{'type'} = 'link'; $_->{'searchParam'} = $tags->{search};}

	return {
		name  => cstring($client, 'MY_MUSIC'),
		items => $items,
		type  => 'opml',
	};
}

sub searchItems {
	my $client = shift;
	
	return [
		{
			type => 'search',
			name => cstring($client, 'BROWSE_BY_ARTIST'),
			icon => 'html/images/search.png',
			url  => $browseLibraryModeMap{'artists'},
			cachesearch => 'ARTISTS',
		},
		{
			type => 'search',
			name => cstring($client, 'BROWSE_BY_ALBUM'),
			icon => 'html/images/search.png',
			url  => $browseLibraryModeMap{'albums'},
			cachesearch => 'ALBUMS',
		},
		{
			type => 'search',
			name => cstring($client, 'BROWSE_BY_SONG'),
			icon => 'html/images/search.png',
			url  => $browseLibraryModeMap{'tracks'},
			cachesearch => 'SONGS',
		},
		{
			type => 'search',
			name => cstring($client, 'PLAYLISTS'),
			icon => 'html/images/search.png',
			url  => $browseLibraryModeMap{'playlists'},
			cachesearch => 'PLAYLISTS',
		},
	];
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

=cut
# Untested
sub _combinedSearch {
	my ($client, $callback, $args, $pt) = @_;
	my $search     = $pt->{'search'} || $args->{'search'};

	_generic($client, $callback, $args, 'search', 
		['term:' . $search],
		sub {
			my $results = shift;
			my @items;
			
			# Artists, Genres, Albums, Songs, Playlists: see Slim::Schema->searchTypes()
			
			my %types = (
				contributor => ['ARTISTS',    'artist_id',    'artistinfo',    \&_tracks,         \&_albums],
				genre       => ['GENRES',     'genre_id',     'genreinfo',     \&_tracks,         \&_albums],
				album       => ['ALBUMS',     'album_id',     'albuminfo',     \&_tracks,         \&_tracks],
				playlist    => ['PLAYLISTS',  'playlist_id',  'playlistinfo',  \&_playlistTracks, \&_playlistTracks],
			);
			
			while (my($type, $params) = each %types) {
				if (exists $results->{$type . 's_count'}) {
					push @items, {type => 'text', name => cstring($client, $params->[0])};
					my $type_id = $type . '_id';
					foreach (@{$results->{$type . 's_loop'}}) {
						my %item = (
							name          => $_->{$type},
							type          => 'playlist',
							playlist      => $params->[3],
							url           => $params->[4],
							passthrough   => [ { searchTags => [$params->[1] . ':' . $_->{$type_id}] } ],
							itemActions   => {
								info => {
									command     => [$params->[2], 'items'],
									fixedParams => {$params->[1] => $_->{$type_id}},	
								},
							}
						);
						push @items, \%item;
					}
				}
				
			}

			
			if (exists $results->{'tracks_count'}) {
				push @items, {type => 'text', name => cstring($client, 'SONGS')};
				foreach (@{$results->{'tracks_loop'}}) {
					my %item = (
						name          => $_->{'track'},
						type          => 'audio',
						itemActions   => {
							info => {
								command     => ['trackinfo', 'items'],
								fixedParams => {track_id => $_->{'track_id'}},	
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
						}
					);
					push @items, \%item;
				}
			}
			
			# override the total as index/offset will not work for repeat calls
			$results->{'count'} = scalar @items;
			
			return ({items => \@items, sorted => 0});
		},
	);
}
=cut

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
		[@searchTags, ($search ? 'search:' . $search : undef)],
		sub {
			my $results = shift;
			my $items = $results->{'artists_loop'};
			foreach (@$items) {
				$_->{'name'}          = $_->{'artist'};
				$_->{'type'}          = 'playlist';
				$_->{'playlist'}      = \&_tracks;
				$_->{'url'}           = \&_albums;
				$_->{'passthrough'}   = [ { searchTags => [@ptSearchTags, "artist_id:" . $_->{'id'}] } ];
				$_->{'favorites_url'} = 'db:contributor.name=' .
						URI::Escape::uri_escape_utf8( $_->{'name'} );
			}
			my $extra;
			if (scalar @searchTags) {
				my $params = _tagsToParams(\@searchTags);
				$extra = [ {
					name        => cstring($client, 'ALL_ALBUMS'),
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
						remove => {
							command     => ['playlistcontrol'],
							fixedParams => {cmd => 'delete', %$params},
						},
					},					
				} ];
			}
			
			elsif ($search) {
				my $strings = Slim::Utils::Text::searchStringSplit($search)->[0];

				my $sql;
				if ( ref $strings eq 'ARRAY' ) {
					$_ =~ s/'/''/g foreach @$strings;
					$sql = '(' . join( ' OR ', map { "contributors.namesearch LIKE '" . $_ . "'"} @$strings ) . ')';
				} else {
					$strings =~ s/'/''/g;		
					$sql = "contributors.namesearch LIKE '" . $strings . "'";
				}
				
				my %params = (
					mode       => 'tracks',
					sort       => 'albumtrack',
					menuStyle  => 'menuStyle:allSongs',
					search     => 'sql=' . $sql,
				);
					
				my %actions = (
					allAvailableActionsDefined => 1,
					info   => {
						command => [BROWSELIBRARY, 'items'],
						fixedParams => {mode => 'artists', search => $search, item_id => $results->{'count'}},
					},
					items  => {command => [BROWSELIBRARY, 'items'],              fixedParams => \%params},
					play   => {command => [BROWSELIBRARY, 'playlist', 'play'],   fixedParams => \%params},
					add    => {command => [BROWSELIBRARY, 'playlist', 'add'],    fixedParams => \%params},
					insert => {command => [BROWSELIBRARY, 'playlist', 'insert'], fixedParams => \%params},
					remove => {command => [BROWSELIBRARY, 'playlist', 'delete'], fixedParams => \%params},
				);

				$extra = [ {
					name        => cstring($client, 'ALL_SONGS'),
					type        => 'playlist',
					playlist    => \&_tracks,
					url         => \&_tracks,
					passthrough => [{ search => 'sql=' . $sql, sort => 'sort:albumtrack', menuStyle => 'menuStyle:allSongs' }],
					itemActions => \%actions,
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
				remove => {
					command     => ['playlistcontrol'],
					fixedParams => {cmd => 'delete', %$params},
				},
			);
			$actions{'playall'} = $actions{'play'};
			$actions{'addall'} = $actions{'add'};
			
			return {items => $items, actions => \%actions, sorted => 1}, $extra;
		},
		's', $pt->{'wantIndex'},
	);
}

sub _genres {
	my ($client, $callback, $args, $pt) = @_;
	my @searchTags = $pt->{'searchTags'} ? @{$pt->{'searchTags'}} : ();
	my $search     = $pt->{'search'};

	if (!$search && !scalar @searchTags && $args->{'search'}) {
		$search = $args->{'search'};
	}
		
	_generic($client, $callback, $args, 'genres', 
		[@searchTags, ($search ? 'search:' . $search : undef)],
		sub {
			my $results = shift;
			my $items = $results->{'genres_loop'};
			foreach (@$items) {
				$_->{'name'}          = $_->{'genre'};
				$_->{'type'}          = 'playlist';
				$_->{'playlist'}      = \&_tracks;
				$_->{'url'}           = \&_artists;
				$_->{'passthrough'}   = [ { searchTags => [@searchTags, "genre_id:" . $_->{'id'}] } ];
				$_->{'favorites_url'} = 'db:genre.name=' .
						URI::Escape::uri_escape_utf8( $_->{'name'} );
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
		's', $pt->{'wantIndex'},
	);
}

sub _years {
	my ($client, $callback, $args, $pt) = @_;
	my @searchTags = $pt->{'searchTags'} ? @{$pt->{'searchTags'}} : ();
	
	_generic($client, $callback, $args, 'years', [ 'hasAlbums:1', @searchTags ],
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

my %orderByList = (
	ALBUM                => 'album',
	SORT_YEARALBUM       => 'yearalbum',
	SORT_YEARARTISTALBUM => 'yearartistalbum',
	SORT_ARTISTALBUM     => 'artistalbum',
	SORT_ARTISTYEARALBUM => 'artflow',
);

my %mapArtistOrders = (
	album            => 'album',
	yearalbum        => 'yearalbum',
	yearartistalbum  => 'yearalbum',
	artistalbum      => 'album',
	artflow          => 'yearalbum'
);

sub _albums {
	my ($client, $callback, $args, $pt) = @_;
	my @searchTags = $pt->{'searchTags'} ? @{$pt->{'searchTags'}} : ();
	my $sort       = $pt->{'sort'};
	my $search     = $pt->{'search'};
	my $wantMeta   = $pt->{'wantMetadata'};
	my $tags       = 'ljsaS';
	
	if (!$sort || $sort ne 'sort:new') {
		$sort = $pt->{'orderBy'} || $args->{'orderBy'} || $sort;
	}

	if (!$search && !scalar @searchTags && $args->{'search'}) {
		$search = $args->{'search'};
	}
	
	my @artistIds = grep /artist_id:/, @searchTags;
	my $artistId;
	if (scalar @artistIds) {
		$artistIds[0] =~ /artist_id:(\d+)/;
		$artistId = $1;
	}
	
	$tags .= 'y' unless grep {/^year:/} @searchTags;
	
	# Remove artist from sort order if selection includes artist
	if ($sort && $sort =~ /sort:(.*)/) {
		my $mapped;
		if ($artistId && ($mapped = $mapArtistOrders{$1})) {
			$sort = 'sort:' . $mapped;
		}
		$sort = undef unless grep {$_ eq $1} ('new', values %orderByList);
	} 
	
	_generic($client, $callback, $args, 'albums',
		[@searchTags, ($sort ? $sort : ()), ($search ? 'search:' . $search : undef)],
		sub {
			my $results = shift;
			my $items = $results->{'albums_loop'};
			foreach (@$items) {
				$_->{'name'}          = $_->{'album'};
				$_->{'image'}         = 'music/' . $_->{'artwork_track_id'} . '/cover' if $_->{'artwork_track_id'};
				$_->{'type'}          = 'playlist';
				$_->{'playlist'}      = \&_tracks;
				$_->{'url'}           = \&_tracks;
				$_->{'passthrough'}   = [ { searchTags => [@searchTags, "album_id:" . $_->{'id'}], sort => 'sort:tracknum' } ];
				# the favorites url is the album title here
				# album id would be (much) better, but that would screw up the favorite on a rescan
				# title is a really stupid thing to use, since there's no assurance it's unique
				$_->{'favorites_url'} = 'db:album.title=' .
						URI::Escape::uri_escape_utf8( $_->{'name'} );
				
				# If an artist was not used in the selection criteria or if one was
				# used but is different to that of the primary artist, then provide 
				# the primary artist name in name2.
				if (!$artistId || $artistId != $_->{'artist_id'}) {
					$_->{'name2'} = $_->{'artist'};
				}

				if (!$wantMeta) {
					delete $_->{'artist'};
				}
				
				$_->{'hasMetadata'}   = 'album'
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
					remove => {
						command     => ['playlistcontrol'],
						fixedParams => {cmd => 'delete', %$params},
					},
				);
				$actions{'playall'} = $actions{'play'};
				$actions{'addall'} = $actions{'add'};
				
				$extra = [ {
					name        => cstring($client, 'ALL_SONGS'),
					icon        => 'html/images/albums.png',
					type        => 'playlist',
					playlist    => \&_tracks,
					url         => \&_tracks,
					passthrough => [{ searchTags => \@searchTags, sort => 'sort:title', menuStyle => 'menuStyle:allSongs' }],
					itemActions => \%actions,
				} ];
			}
			elsif ($search) {
				my $strings = Slim::Utils::Text::searchStringSplit($search)->[0];

				my $sql;
				if ( ref $strings eq 'ARRAY' ) {
					$_ =~ s/'/''/g foreach @$strings;
					$sql = '(' . join( ' OR ', map { "albums.titlesearch LIKE '" . $_ . "'"} @$strings ) . ')';
				} else {
					$strings =~ s/'/''/g;		
					$sql = "albums.titlesearch LIKE '" . $strings . "'";
				}
				
				my %params = (
					mode       => 'tracks',
					sort       => 'albumtrack',
					menuStyle  => 'menuStyle:allSongs',
					search     => 'sql=' . $sql,
				);
					
				my %actions = (
					allAvailableActionsDefined => 1,
					info   => {
						command => [BROWSELIBRARY, 'items'],
						fixedParams => {mode => 'albums', search => $search, item_id => $results->{'count'}},
					},
					items  => {command => [BROWSELIBRARY, 'items'],              fixedParams => \%params},
					play   => {command => [BROWSELIBRARY, 'playlist', 'play'],   fixedParams => \%params},
					add    => {command => [BROWSELIBRARY, 'playlist', 'add'],    fixedParams => \%params},
					insert => {command => [BROWSELIBRARY, 'playlist', 'insert'], fixedParams => \%params},
					remove => {command => [BROWSELIBRARY, 'playlist', 'delete'], fixedParams => \%params},
				);

				$extra = [ {
					name        => cstring($client, 'ALL_SONGS'),
					icon        => 'html/images/albums.png',
					type        => 'playlist',
					playlist    => \&_tracks,
					url         => \&_tracks,
					passthrough => [{ search => 'sql=' . $sql, sort => 'sort:albumtrack', menuStyle => 'menuStyle:allSongs' }],
					itemActions => \%actions,
				} ];
			}
			
			my $params = _tagsToParams(\@searchTags);
			my %actions = (
				allAvailableActionsDefined => 1,
				commonVariables	=> [album_id => 'id'],
				info => {
					command     => ['albuminfo', 'items'],
					fixedParams => $params,
				},
				items => {
					command     => [BROWSELIBRARY, 'items'],
					fixedParams => {
						mode       => 'tracks',
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
				remove => {
					command     => ['playlistcontrol'],
					fixedParams => {cmd => 'delete', %$params},
				},
			);
			$actions{'playall'} = $actions{'play'};
			$actions{'addall'} = $actions{'add'};
			
			return {
				items       => $items,
				actions     => \%actions,
				sorted      => (($sort && $sort eq 'sort:new') ? 0 : 1),
				orderByList => (($sort && $sort eq 'sort:new') ? undef : \%orderByList),
			}, $extra;
		},
		$tags, $pt->{'wantIndex'},
	);
}

sub _tracks {
	my ($client, $callback, $args, $pt) = @_;
	my @searchTags = $pt->{'searchTags'} ? @{$pt->{'searchTags'}} : ();
	my $sort       = $pt->{'sort'} || 'sort:albumtrack';
	my $menuStyle  = $pt->{'menuStyle'} || 'menuStyle:album';
	my $search     = $pt->{'search'};
	my $offset     = $args->{'index'} || 0;
	my $getMetadata= $pt->{'wantMetadata'} && grep {/album_id:/} @searchTags;
	my $tags       = 'dtuxgaAliqyorf';
	
	if (!defined $search && !scalar @searchTags && defined $args->{'search'}) {
		$search = $args->{'search'};
	}
	
	# Sanity check
	if ((!defined $search || !length($search)) && !scalar @searchTags) {
		$log->error('Invalid request: no search term or album/artist/genre tags');
		$callback->({title => 'Invalid request: no search term or album/artist/genre tags'});
	}

	$tags .= 'k' if $pt->{'wantMetadata'};
	
	my ($addAlbumToName2, $addArtistToName2);
	if ($addAlbumToName2  = !(grep {/album_id:/} @searchTags)) {
		$addArtistToName2 = !(grep {/artist_id:/} @searchTags);
		$tags            .= 'cJK'; # artwork
	}
	
	_generic($client, $callback, $args, 'titles',
		["tags:$tags", $sort, $menuStyle, @searchTags, ($search ? 'search:' . $search : undef)],
		sub {
			my $results = shift;
			my $items   = $results->{'titles_loop'};
			
			foreach (@$items) {
				# Map a few items that get different tags to those expected for TitleFormatter
				# Currently missing composer, conductor, band because of additional cost of 'A' tag query
				$_->{'ct'}            = $_->{'type'};
				if (my $secs = $_->{'duration'}) {
					$_->{'secs'}      = $secs;
					$_->{'duration'}  = sprintf('%d:%02d', int($secs / 60), $secs % 60);
				}
				$_->{'discc'}         = delete $_->{'disccount'} if defined $_->{'disccount'};
				$_->{'fs'}            = $_->{'filesize'};
				$_->{'hasMetadata'}   = 'track';
				
				$_->{'name'}          = $_->{'title'};

				$_->{'type'}          = 'audio';
				$_->{'playall'}       = 1;
				$_->{'play_index'}    = $offset++;
				
				# bug 17340 - in track lists we give the trackartist precedence over the artist
				$_->{'artist'} = $_->{'trackartist'} if $_->{'trackartist'};
				
				my $name2;
				$name2 = $_->{'artist'} if $addArtistToName2;
				if ($addAlbumToName2 && $_->{'album'}) {
					$name2 .= ' - ' if $name2;
					$name2 .= $_->{'album'};
				}
				if ($name2) {
					if ( $_->{'coverid'} ) {
						$_->{'artwork_track_id'} = $_->{'coverid'};
					}

					$_->{'name2'}     = $name2;
					$_->{'image'}     = 'music/' . $_->{'artwork_track_id'} . '/cover' if $_->{'artwork_track_id'};
					$_->{'image'}   ||= $_->{'artwork_url'} if $_->{'artwork_url'};
				}
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
				remove => {
					command     => ['playlistcontrol'],
					fixedParams => {cmd => 'delete'},
				},
			);
			$actions{'items'} = $actions{'info'};	# XXX, not sure about this, probably harmless but unnecessary

			if ($search) {
				$actions{'playall'} = $actions{'play'};
				$actions{'addall'} = $actions{'all'};
			}
			
			my $extra;
			if ($search && $search !~ /^sql=/) {
				my $strings = Slim::Utils::Text::searchStringSplit($search)->[0];

				my $sql;
				if ( ref $strings eq 'ARRAY' ) {
					$_ =~ s/'/''/g foreach @$strings;
					$sql = '(' . join( ' OR ', map { "tracks.titlesearch LIKE '" . $_ . "'"} @$strings ) . ')';
				} else {
					$strings =~ s/'/''/g;		
					$sql = "tracks.titlesearch LIKE '" . $strings . "'";
				}
				
				my %params = (
					mode       => 'tracks',
					sort       => 'albumtrack',
					menuStyle  => 'menuStyle:allSongs',
					search     => 'sql=' . $sql,
				);
					
				my %allSongsActions = (
					allAvailableActionsDefined => 1,
					
					# relies on side-effect of context menu, really should implement a searchTracksinfo command
					info   => {
						command => [BROWSELIBRARY, 'items'],
						fixedParams => {mode => 'tracks', search => $search, item_id => $results->{'count'}},
					},
					
					# no 'items' item as no need to browse into this item
					play   => {command => [BROWSELIBRARY, 'playlist', 'play'],   fixedParams => \%params},
					add    => {command => [BROWSELIBRARY, 'playlist', 'add'],    fixedParams => \%params},
					insert => {command => [BROWSELIBRARY, 'playlist', 'insert'], fixedParams => \%params},
				);

				$extra = [ {
					name        => cstring($client, 'ALL_SONGS'),
					icon        => 'html/images/albums.png',
					type        => 'playlist',
					# No url as we no not want to be able to browse this item,
					# but cannot use type=text because this would stop Slim::Control::XMLBrowser
					# adding play-control items in a context menu (see side-effect above for 'info' action)
					playlist    => \&_tracks,
					passthrough => [{ search => 'sql=' . $sql, sort => 'sort:albumtrack', menuStyle => 'menuStyle:allSongs' }],
					itemActions => \%allSongsActions,
				} ];
			
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
			
			my $albumMetadata;
			my $albumInfo;
			my $image;
			if ($getMetadata) {
				my ($albumId) = grep {/album_id:/} @searchTags;
				$albumId =~ s/album_id:// if $albumId;
				my $album = Slim::Schema->find( Album => $albumId );
				my $feed  = Slim::Menu::AlbumInfo->menu( $client, $album->url, $album, undef ) if $album;
				$albumMetadata = $feed->{'items'} if $feed;
				
				$image = 'music/' . $album->artwork . '/cover' if $album && $album->artwork;

				$albumInfo = { 
					info => { 
						command =>   ['albuminfo', 'items'], 
						variables => [ 'album_id', 'id' ],
					},
				};
			}

			return {items => $items, actions => \%actions, sorted => 0, albumData => $albumMetadata, albumInfo => $albumInfo, 
					cover => $image}, $extra;
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
					$_->{'type'}        = 'playlist';
					$_->{'url'}         = \&_bmf;
					$_->{'passthrough'} = [ { searchTags => [ "folder_id:" . $_->{'id'} ] } ];
					$_->{'itemActions'} = {
						info => {
							command     => ['folderinfo', 'items'],
							fixedParams => {folder_id =>  $_->{'id'}},
						},
						play => {
							command     => ['playlistcontrol'],
							fixedParams => {cmd => 'load', folder_id =>  $_->{'id'}},
						},
						add => {
							command     => ['playlistcontrol'],
							fixedParams => {cmd => 'add', folder_id =>  $_->{'id'}},
						},
						insert => {
							command     => ['playlistcontrol'],
							fixedParams => {cmd => 'insert', folder_id =>  $_->{'id'}},
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
				}
				# Cannot do anything useful with a playlist in BMF
#				elsif ($_->{'type'} eq 'playlist') {
#					$_->{'type'}        = 'text';
#					$_->{'favorites_url'} =	$_->{'url'};
#					$_->{'playlist'}	  = \&_playlistTracks;
#					$_->{'url'}           = \&_playlistTracks;
#					$_->{'passthrough'}   = [ { searchTags => [ "playlist_id:" . $_->{'id'} ] } ];					
#				}
				else # if ($_->{'type'} eq 'unknown') 
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
		['tags:su', @searchTags, ($search ? 'search:' . $search : undef)],
		sub {
			my $results = shift;
			my $items = $results->{'playlists_loop'};
			foreach (@$items) {
				$_->{'name'}          = $_->{'playlist'};
				$_->{'type'}          = 'playlist';
				$_->{'favorites_url'} =	$_->{'url'};			
				$_->{'playlist'}      = \&_playlistTracks;
				$_->{'url'}           = \&_playlistTracks;
				$_->{'passthrough'}   = [ { searchTags => [ @searchTags, 'playlist_id:' . $_->{'id'} ], } ];
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
		['tags:dtuxgaliqykorfcJK', $menuStyle, @searchTags],
		sub {
			my $results = shift;
			my $items = $results->{'playlisttracks_loop'};
			foreach (@$items) {
				# Map a few items that get different tags to those expected for TitleFormatter
				# Currently missing composer, conductor, band because of additional cost of 'A' tag query
				$_->{'ct'}            = $_->{'type'};
				if (my $secs = $_->{'duration'}) {
					$_->{'secs'}      = $secs;
					$_->{'duration'}  = sprintf('%d:%02d', int($secs / 60), $secs % 60);
				}
				$_->{'discc'}         = delete $_->{'disccount'} if defined $_->{'disccount'};
				$_->{'fs'}            = $_->{'filesize'};
				$_->{'hasMetadata'}   = 'track';
				
				$_->{'name'}          = $_->{'title'};
				$_->{'name2'}		  = $_->{'artist'} . ' - ' . $_->{'album'};
				
				if ( $_->{'coverid'} ) {
					$_->{'artwork_track_id'} = $_->{'coverid'};
				}
				
				$_->{'image'}         = ($_->{'artwork_track_id'}
										? 'music/' . $_->{'artwork_track_id'} . '/cover'
										: $_->{'artwork_url'} ? $_->{'artwork_url'} : undef);

				$_->{'type'}          = 'audio';
				$_->{'playall'}       = 1;
				$_->{'play_index'}    = $offset++;
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
			
			my %hash = (
				items       => $items,
				actions     => \%actions,
				sorted      => 0,
				playlist_id => (&_tagsToParams(\@searchTags))->{'playlist_id'},
			);
			$hash{'playlistTitle'} = $results->{'__playlistTitle'} if defined $results->{'__playlistTitle'};

			return \%hash, undef;
		}
	);
}

sub getDisplayName () {
	return 'MY_MUSIC';
}

sub playerMenu {'PLUGINS'}


1;
