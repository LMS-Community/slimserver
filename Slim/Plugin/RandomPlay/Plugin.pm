package Slim::Plugin::RandomPlay::Plugin;

# Originally written by Kevin Deane-Freeman (slim-mail (A_t) deane-freeman.com).
# New world order by Dan Sully - <dan | at | slimdevices.com>
# Fairly substantial rewrite by Max Spicer

# This code is derived from code with the following copyright message:
#
# Logitech Media Server Copyright 2005-2016 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Plugin::Base);

use Slim::Buttons::Home;
use Slim::Music::VirtualLibraries;
use Slim::Player::ProtocolHandlers;
use Slim::Utils::Alarm;
use Slim::Utils::Cache;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string cstring);
use Slim::Utils::Prefs;
use Slim::Player::Sync;

use constant MENU_WEIGHT => 60;

# playlist commands that will stop random play
my $stopcommands = [
	'clear',
	'loadtracks', # multiple play
	'playtracks', # single play
	'load',       # old style url load (no play)
	'play',       # old style url play
	'loadalbum',  # old style multi-item load
	'playalbum',  # old style multi-item play
];

# map CLI command args to internal mix types
my %mixTypeMap = (
	'tracks'       => 'track',
	'contributors' => 'contributor',
	'albums'       => 'album',
	'year'         => 'year',
	'artists'      => 'contributor',		
);

my @mixTypes = ('track', 'contributor', 'album', 'year');

# Genres for each client (don't access this directly - use getGenres())
my $genres;

my $functions;
my $htmlTemplate = 'plugins/RandomPlay/list.html';

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.randomplay',
	'defaultLevel' => 'ERROR',
	'description'  => __PACKAGE__->getDisplayName(),
});

my $prefs = preferences('plugin.randomplay');
my $cache;

my $initialized = 0;

$prefs->migrate( 1, sub {

	require Slim::Utils::Prefs::OldPrefs;

	my $newtracks = Slim::Utils::Prefs::OldPrefs->get('plugin_random_number_of_tracks');
	if ( !defined $newtracks ) {
		$newtracks = 10;
	}
	
	my $continuous = Slim::Utils::Prefs::OldPrefs->get('plugin_random_keep_adding_tracks');
	if ( !defined $continuous ) {
		$continuous = 1;
	}

	my $oldtracks = Slim::Utils::Prefs::OldPrefs->get('plugin_random_number_of_old_tracks');
	if ( !defined $oldtracks ) {
		$oldtracks = 10;
	}
	
	$prefs->set( 'newtracks', $newtracks );
	$prefs->set( 'oldtracks', $oldtracks );
	$prefs->set( 'continuous', $continuous );
	$prefs->set( 'exclude_genres', Slim::Utils::Prefs::OldPrefs->get('plugin_random_exclude_genres') || [] );
	
	1;
} );

$prefs->setChange(sub {
	my $new = $_[1];
	my $old = $_[3];

	# let's verify whether the list actually has changed
	my $dirty;
	
	if (scalar @$new != scalar @$old) {
		$dirty = 1;
	}
	else {
		my %old = map { $_ => 1 } @$old;
		foreach (@$new) {
			if (!$old{$_}) {
				$dirty = 1;
				last;
			}
		}
	}

	# only wipe player's idList if the genre list has changed
	_resetCache() if $dirty;

	$genres = undef;
}, 'exclude_genres');

$prefs->setChange(\&_resetCache, 'library');

sub _resetCache {
	return unless $cache;
	
	foreach ( Slim::Player::Client::clients() ) {
		$cache->remove('rnd_idList_' . $_->id);
		$cache->remove('rnd_years_' . $_->id); 
	}
}

$prefs->setValidate({ 'validator' => 'intlimit', 'low' => 1, 'high' => 100 }, 'newtracks' );

sub weight { MENU_WEIGHT }

sub initPlugin {
	my $class = shift;

	$genres = undef;
	
	# Regenerate the genre map after a rescan.
	Slim::Control::Request::subscribe(\&_libraryChanged, [['library','rescan'], ['changed','done']]);
	
	return if $initialized || !Slim::Schema::hasLibrary();
	
	$initialized = 1;

	# create function map
	if (!$functions) {
		foreach (keys %mixTypeMap) {
			my $type = $mixTypeMap{$_};
			$functions->{$_} = sub { playRandom(shift, $type); }
		}
	}

	$class->SUPER::initPlugin();

	# set up our subscription
	Slim::Control::Request::subscribe(\&commandCallback, 
		[['playlist'], ['newsong', 'delete', @$stopcommands]]);

#        |requires Client
#        |  |is a Query
#        |  |  |has Tags
#        |  |  |  |Function to call
#        C  Q  T  F
	Slim::Control::Request::addDispatch(['randomplay', '_mode'],
        [1, 0, 1, \&cliRequest]);
	Slim::Control::Request::addDispatch(['randomplaygenrelist', '_index', '_quantity'],
        [1, 1, 0, \&chooseGenresMenu]);
	Slim::Control::Request::addDispatch(['randomplaychoosegenre', '_genre', '_value'],
        [1, 0, 0, \&chooseGenre]);
	Slim::Control::Request::addDispatch(['randomplaylibrarylist', '_index', '_quantity'],
        [1, 1, 0, \&chooseLibrariesMenu]);
	Slim::Control::Request::addDispatch(['randomplaychooselibrary', '_library'],
        [1, 0, 0, \&chooseLibrary]);
	Slim::Control::Request::addDispatch(['randomplaygenreselectall', '_value'],
        [1, 0, 0, \&genreSelectAllOrNone]);
	Slim::Control::Request::addDispatch(['randomplayisactive'],
		[1, 1, 0, \&cliIsActive]);
			
	Slim::Player::ProtocolHandlers->registerHandler(
		randomplay => 'Slim::Plugin::RandomPlay::ProtocolHandler'
	);

	# register handler for starting mix of last type on remote button press [Default is press and hold shuffle]
	Slim::Buttons::Common::setFunction('randomPlay', \&buttonStart);

	my @item = (
		{
			stringToken    => 'PLUGIN_RANDOM_TRACK',
			id      => 'randomtracks',
			weight  => 10,
			style   => 'itemplay',
			nextWindow => 'nowPlaying',
			node    => 'randomplay',
			actions => {
				play => {
					player => 0,
					cmd    => [ 'randomplay', 'tracks' ],
				},
				go => {
					player => 0,
					cmd    => [ 'randomplay', 'tracks' ],
				},
			},
		},
		{
			stringToken    => 'PLUGIN_RANDOM_ALBUM',
			id      => 'randomalbums',
			weight  => 20,
			style   => 'itemplay',
			nextWindow => 'nowPlaying',
			node    => 'randomplay',
			actions => {
				play => {
					player => 0,
					cmd    => [ 'randomplay', 'albums' ],
				},
				go => {
					player => 0,
					cmd    => [ 'randomplay', 'albums' ],
				},
			},
		},
		{
			stringToken    => 'PLUGIN_RANDOM_CONTRIBUTOR',
			id      => 'randomartists',
			weight  => 30,
			style   => 'itemplay',
			nextWindow => 'nowPlaying',
			node    => 'randomplay',
			actions => {
				play => {
					player => 0,
					cmd    => [ 'randomplay', 'contributors' ],
				},
				go => {
					player => 0,
					cmd    => [ 'randomplay', 'contributors' ],
				},
			},
		},
		{
			stringToken    => 'PLUGIN_RANDOM_YEAR',
			id      => 'randomyears',
			weight  => 40,
			style   => 'itemplay',
			nextWindow => 'nowPlaying',
			node    => 'randomplay',
			actions => {
				play => {
					player => 0,
					cmd    => [ 'randomplay', 'year' ],
				},
				go => {
					player => 0,
					cmd    => [ 'randomplay', 'year' ],
				},
			},
		},
		{
			stringToken    => 'PLUGIN_RANDOM_CHOOSE_GENRES',
			id      => 'randomchoosegenres',
			weight  => 50,
			window  => { titleStyle => 'random' },
			node    => 'randomplay',
			actions => {
				go => {
					player => 0,
					cmd    => [ 'randomplaygenrelist' ],
				},
			},
		},
		{
			stringToken    => 'PLUGIN_RANDOM_LIBRARY_FILTER',
			id      => 'randomchooselibrary',
			weight  => 55,
			window  => { titleStyle => 'random' },
			node    => 'randomplay',
			actions => {
				go => {
					player => 0,
					cmd    => [ 'randomplaylibrarylist' ],
				},
			},
		},
		{
			stringToken    => 'PLUGIN_RANDOM_DISABLE',
			id      => 'randomdisable',
			weight  => 100,
			style   => 'itemplay',
			nextWindow => 'refresh',
			node    => 'randomplay',
			actions => {
				play => {
					player => 0,
					cmd    => [ 'randomplay', 'disable' ],
				},
				go => {
					player => 0,
					cmd    => [ 'randomplay', 'disable' ],
				},
			},
		},
		{
			stringToken    => $class->getDisplayName(),
			weight         => MENU_WEIGHT,
			id             => 'randomplay',
			node           => 'myMusic',
			isANode        => 1,
			windowStyle    => 'text_list',
			window         => { titleStyle => 'random' },
		},
	);

	Slim::Control::Jive::registerPluginMenu(\@item);

	Slim::Menu::GenreInfo->registerInfoProvider( randomPlay => (
		after => 'top',
		func  => \&_genreInfoMenu,
	) );
	
	Slim::Utils::Alarm->addPlaylists('PLUGIN_RANDOMPLAY',
		[
			{ title => '{PLUGIN_RANDOM_TRACK}', url => 'randomplay://track' },
			{ title => '{PLUGIN_RANDOM_CONTRIBUTOR}', url => 'randomplay://contributor' },
			{ title => '{PLUGIN_RANDOM_ALBUM}', url => 'randomplay://album' },
			{ title => '{PLUGIN_RANDOM_YEAR}', url => 'randomplay://year' },
		]
	);
	
	$cache = Slim::Utils::Cache->new();
}

sub postinitPlugin {
	my $class = shift;
	
	# if user has the Don't Stop The Music plugin enabled, register ourselves
	if ( Slim::Utils::PluginManager->isEnabled('Slim::Plugin::DontStopTheMusic::Plugin') ) {
		require Slim::Plugin::DontStopTheMusic::Plugin;
		
		my $mixWithGenres = sub {
			my ($type, $client, $cb) = @_;
		
			return unless $client;
		
			my %genres;
			foreach my $track (@{ Slim::Player::Playlist::playList($client) }) {
				if ( $track->remote ) {
					$genres{$track->genre}++ if $track->genre;
				}
				else {
					foreach ( $track->genres ) {
						$genres{$_->name}++
					}
				}
			}
			
			# don't seed from radio stations - only do if we're playing from some track based source
			if (keys %genres) {
				# reset all genres to only use those present in our queue
				$client->execute(['randomplaygenreselectall', 0]);
				
				foreach (keys %genres) {
					$client->execute(['randomplaychoosegenre', $_, 1]);
				}
			}
		
			$cb->($client, ['randomplay://' . $type]);
		};
		
		Slim::Plugin::DontStopTheMusic::Plugin->registerHandler('PLUGIN_RANDOM_TITLEMIX_WITH_GENRES', sub {
			$mixWithGenres->('track', @_);
		});

		Slim::Plugin::DontStopTheMusic::Plugin->registerHandler('PLUGIN_RANDOM_TRACK', sub {
			my ($client, $cb) = @_;
			$client->execute(['randomplaygenreselectall', 0]);
			$cb->($client, ['randomplay://track']);
		});
		
		Slim::Plugin::DontStopTheMusic::Plugin->registerHandler('PLUGIN_RANDOM_ALBUM_MIX_WITH_GENRES', sub {
			$mixWithGenres->('album', @_);
		});

		Slim::Plugin::DontStopTheMusic::Plugin->registerHandler('PLUGIN_RANDOM_ALBUM_ITEM', sub {
			my ($client, $cb) = @_;
			$client->execute(['randomplaygenreselectall', 0]);
			$cb->($client, ['randomplay://album']);
		});

		Slim::Plugin::DontStopTheMusic::Plugin->registerHandler('PLUGIN_RANDOM_CONTRIBUTOR_ITEM', sub {
			my ($client, $cb) = @_;
			$client->execute(['randomplaygenreselectall', 0]);
			$cb->($client, ['randomplay://contributor']);
		});

		Slim::Plugin::DontStopTheMusic::Plugin->registerHandler('PLUGIN_RANDOM_YEAR_ITEM', sub {
			my ($client, $cb) = @_;
			$client->execute(['randomplaygenreselectall', 0]);
			$cb->($client, ['randomplay://year']);
		});
	}
}

sub _shutdown {
	
	$initialized = 0;
	
	$genres = undef;
	
	# unsubscribe
	Slim::Control::Request::unsubscribe(\&commandCallback);
	
	# remove Jive menus
	Slim::Control::Jive::deleteMenuItem('randomplay');
	
	# remove player-UI mode
	Slim::Buttons::Common::setFunction('randomPlay', sub {});
	
	# remove web menus
	webPages();
	
}

sub shutdownPlugin {
	my $class = shift;

	# unsubscribe
	Slim::Control::Request::unsubscribe(\&_libraryChanged);
	
	_shutdown();	
}

sub _libraryChanged {
	my $request = shift;
	
	if ( $request->getParam('_newvalue') || $request->isCommand([['rescan'],['done']]) ) {
		__PACKAGE__->initPlugin();
	} else {
		_shutdown();
	}
}


sub _genreInfoMenu {
	my ($client, $url, $genre, $remoteMeta, $tags) = @_;
	
	if ($genre) {
		my $params = {'genre_id'=> $genre->id};
		my @items;
		my $action;
		
		$action = {
			command     => [ 'randomplay', 'track' ],
			fixedParams => $params,
		};
		push @items, {
			itemActions => {
				play  => $action,
				items => $action,
			},
			nextWindow  => 'nowPlaying',
			type        => 'play',
			name        => sprintf('%s %s %s %s', 
				cstring($client, 'PLUGIN_RANDOMPLAY'),
				cstring($client, 'GENRE'),
				cstring($client, 'SONGS'),
				$genre->name),
		};

		$action = {
			command     => [ 'randomplay', 'album' ],
			fixedParams => $params,
		};
		push @items, {
			itemActions => {
				play  => $action,
				items => $action,
			},
			nextWindow  => 'nowPlaying',
			type        => 'play',
			name        => sprintf('%s %s %s %s', 
				cstring($client, 'PLUGIN_RANDOMPLAY'),
				cstring($client, 'GENRE'),
				cstring($client, 'ALBUMS'),
				$genre->name),
		};
		
		return \@items;
	}
	else {
		return {
			type => 'text',
			name => cstring($client, 'UNMIXABLE', cstring($client, 'PLUGIN_RANDOMPLAY')),
		};
	}
}

sub genreSelectAllOrNone {
	my $request = shift;

 	if (!$initialized) {
 		$request->setStatusBadConfig();
 		return;
 	}
 	
	my $client  = $request->client();
	my $enable  = $request->getParam('');
	my $value   = $request->getParam('_value');
	my $genres  = getGenres($client);

	my @excluded = ();
	for my $genre (keys %$genres) {
		$genres->{$genre}->{'enabled'} = $value;
		if ($value == 0) {
			push @excluded, $genre;
		}
	}
	# set the exclude_genres pref to either all genres or none
	$prefs->set('exclude_genres', [@excluded]);

	$request->setStatusDone();
}

sub chooseGenre {
	my $request   = shift;

 	if (!$initialized) {
 		$request->setStatusBadConfig();
 		return;
 	}
 	
	my $client    = $request->client();
	my $genre     = $request->getParam('_genre');
	my $value     = $request->getParam('_value');
	my $genres    = getGenres($client);

	# in $genres, an enabled genre returns true for $genres->{'enabled'}
	# so we set enabled to 0 for this genre, then
	$genres->{$genre}->{'enabled'} = $value;
	my @excluded = ();
	for my $genre (keys %$genres) {
		push @excluded, $genre if $genres->{$genre}->{'enabled'} == 0;
	}
	# set the exclude_genres pref to all disabled genres 
	$prefs->set('exclude_genres', [@excluded]);

	$request->setStatusDone();
}

# create the Choose Genres menu for a given player
sub chooseGenresMenu {
	my $request = shift;

 	if (!$initialized) {
 		$request->setStatusBadConfig();
 		return;
 	}
 	
	my $client = $request->client();
	my $genres = getGenres($client);	

	my @menu = ();

	# first a "choose all" item
	push @menu, {
		text => $client->string('PLUGIN_RANDOM_SELECT_ALL'),
		nextWindow => 'refresh',
		actions => {
			go => {
				player => 0,
				cmd    => [ 'randomplaygenreselectall', 1 ],
			},
		},
	};
	
	# then a "choose none" item
	push @menu, {
		text => $client->string('PLUGIN_RANDOM_SELECT_NONE'),
		nextWindow => 'refresh',
		actions => {
			go => {
				player => 0,
				cmd    => [ 'randomplaygenreselectall', 0 ],
			},
		},
	};
	
	for my $genre ( getSortedGenres($client) ) {
		my $val = $genres->{$genre}->{'enabled'};

		push @menu, {
			text => $genre,
			checkbox => ($val == 1) + 0,
                        actions  => {
                                on  => {
                                        player => 0,
                                        cmd    => ['randomplaychoosegenre', $genre, 1],
                                },
                                off => {
                                        player => 0,
                                        cmd    => ['randomplaychoosegenre', $genre, 0],
                                },
                        },
		};
	}
	
	Slim::Control::Jive::sliceAndShip($request, $client, \@menu);
}

sub chooseLibrary {
	my $request = shift;

 	if (!$initialized) {
 		$request->setStatusBadConfig();
 		return;
 	}

	$prefs->set('library', $request->getParam('_library') || '');

	$request->setStatusDone();
}

# create the Choose Library menu for a given player
sub chooseLibrariesMenu {
	my $request = shift;

 	if (!$initialized) {
 		$request->setStatusBadConfig();
 		return;
 	}
 	
	my $client = $request->client();

	my $library_id = $prefs->get('library');
	my $libraries  = _getLibraries();

	my @menu = ({
		text     => cstring($client, 'ALL_LIBRARY'),
		radio    => ($library_id ? 0 : 1),
		actions  => {
			'do' => {
				player => 0,
				cmd	=> ['randomplaychooselibrary', 0, 1],
			},
		},
	});
	
	foreach my $id ( sort { lc($libraries->{$a}) cmp lc($libraries->{$b}) } keys %$libraries ) {
		push @menu, {
			text     => $libraries->{$id},
			radio    => ($id eq $library_id ? 1 : 0),
			actions  => {
				'do' => {
					player => 0,
					cmd	=> ['randomplaychooselibrary', $id, 1],
				},
			},
		};
	}
	
	Slim::Control::Jive::sliceAndShip($request, $client, \@menu);
}

# Find tracks matching parameters and add them to the playlist
sub findAndAdd {
	my ($client, $type, $limit, $addOnly) = @_;

	my $idList = $cache->get('rnd_idList_' . $client->id) || [];

	if ( main::INFOLOG && $log->is_info ) {
		$log->info(sprintf("Starting random selection of %s items for type: $type", defined($limit) ? $limit : 'unlimited'));
	}

	if ( !scalar @$idList ) {
		main::DEBUGLOG && $log->debug('Initialize ID list to be randomized');
		
		# Search the database for all items of $type which match find criteria
		my @joins = ();

		# Initialize find to only include user's selected genres.  If they've deselected
		# all genres, this clause will be ignored by find, so all genres will be used.
		my $filteredGenres = getFilteredGenres($client);
		my $excludedGenres = getFilteredGenres($client, 1);
		
		my %categories = (
			album       => ['albums', 0, 999_999, 'tags:t'],
			contributor => ['artists', 0, 999_999],
			track       => ['titles', 0, 999_999, 'tags:t']
		);
		$categories{year}    = $categories{track};
		$categories{artist} = $categories{contributor};

		my $query = $categories{$type};

		# Only look for genre tracks if we have some, but not all
		# genres selected. Or no genres selected.
		if ( (scalar @$filteredGenres > 0 && scalar @$excludedGenres != 0) || 
		     scalar @$filteredGenres != 0 && scalar @$excludedGenres > 0 ) {

			push @$query, "genre_id:" . join(',', @$filteredGenres);

		}

		if ( my $library_id = $prefs->get('library') || Slim::Music::VirtualLibraries->getLibraryIdForClient($client) ) {
			push @$query, 'library_id:' . $library_id;
		}
		
		if ($type eq 'year') {
			push @$query, 'year:' . getRandomYear($client, $filteredGenres);
			$type = 'track';
		}

		my $request = Slim::Control::Request::executeRequest($client, $query);

		my $loop = "${type}s_loop";
		$loop = 'artists_loop' if $type eq 'contributor';
		$loop = 'titles_loop' if $type eq 'track';
		
		$idList = [ map { $_->{id} } @{ $request->getResult($loop) || [] } ];
		
		# shuffle ID list
		Slim::Player::Playlist::fischer_yates_shuffle($idList);
	}
	elsif ($type eq 'year') {
		$type = 'track';
	}

	# get first ID from our randomized list	
	my @randomIds = splice @$idList, 0, $limit;
	
	$cache->set('rnd_idList_' . $client->id, $idList, 'never');

	if (!scalar @randomIds) {

		logWarning("Didn't get a valid object for findAndAdd()!");

		return undef;
	}

	# Add the items to the end
	foreach my $id (@randomIds) {

		if ( main::INFOLOG && $log->is_info ) {
			$log->info(sprintf("%s %s: #%d",
				$addOnly ? 'Adding' : 'Playing', $type, $id
			));
		}
	
		# Replace the current playlist with the first item / track or add it to end
		my $request = $client->execute([
			'playlist', $addOnly ? 'addtracks' : 'loadtracks', sprintf('%s.id=%d', $type, $id)
		]);
	
		# indicate request source
		$request->source('PLUGIN_RANDOMPLAY');
		
		$addOnly++;
	}
}

# Returns a hash whose keys are the genres in the db
sub getGenres {
	my $client = shift;
	
	my $library_id = $prefs->get('library') || Slim::Music::VirtualLibraries->getLibraryIdForClient($client);
	
	$genres ||= {};
	
	return $genres->{$library_id} if keys %$genres && $genres->{$library_id};
	
	$genres->{$library_id} ||= {};
	
	my $query = ['genres', 0, 999_999];
	
	push @$query, 'library_id:' . $library_id if $library_id;

	my $request = Slim::Control::Request::executeRequest($client, $query);
	
	# Extract each genre name into a hash
	my %exclude = map { $_ => 1 } @{ $prefs->get('exclude_genres') };

	my $i = 0;
	foreach my $genre ( @{ $request->getResult('genres_loop') || [] } ) {

		my $name = $genre->{genre};

		# Put the name here as well so the hash can be passed to
		# INPUT.Choice as part of listRef later on
		$genres->{$library_id}->{$name} = {
			'name'    => $name,
			'id'      => $genre->{id},
			'enabled' => !$exclude{$name},
			'sort'    => $i++,
		};
	}

	return $genres->{$library_id};
}

sub getSortedGenres {
	my $client = shift;
	
	my $genres = getGenres($client);
	return sort { 
		$genres->{$a}->{sort} <=> $genres->{$b}->{sort};
	} keys %$genres;
}

# Returns an array of the non-excluded genres in the db
sub getFilteredGenres {
	my ($client, $returnExcluded, $namesOnly) = @_;
	
	# use second arg to set what values we return. we may need list of ids or names
	my $value = $namesOnly ? 'name' : 'id';

	my $genres = getGenres($client);
	
	return [ map {
		$genres->{$_}->{$value};
	} grep {
		($genres->{$_}->{'enabled'} && !$returnExcluded) || ($returnExcluded && !$genres->{$_}->{'enabled'})
	} keys %$genres ];
}

sub getRandomYear {
	my $client = shift;
	my $filteredGenres = shift;

	main::DEBUGLOG && $log->debug("Starting random year selection");
	
	my $years = $cache->get('rnd_years_' . $client->id) || [];
	
	if (!scalar @$years) {
		my %cond = ();
		my %attr = ( 
			'order_by' => Slim::Utils::OSDetect->getOS()->sqlHelperClass()->randomFunction(),
			'group_by' => 'me.year',
		);
	
		if (ref($filteredGenres) eq 'ARRAY' && scalar @$filteredGenres > 0) {
	
			$cond{'genreTracks.genre'} = $filteredGenres;
			$attr{'join'}              = ['genreTracks'];
		}

		if ( my $library_id = $prefs->get('library') || Slim::Music::VirtualLibraries->getLibraryIdForClient($client) ) {

			$cond{'libraryTracks.library'} = $library_id;
			$attr{'join'}                ||= [];
			push @{$attr{'join'}}, 'libraryTracks';
			
		}
	
		$years = [ Slim::Schema->rs('Track')->search(\%cond, \%attr)->get_column('me.year')->all ];
	}
	
	my $year = shift @$years;
	
	$cache->set('rnd_years_' . $client->id, $years, 'never'); 

	main::DEBUGLOG && $log->debug("Selected year $year");

	return $year;
}

# Add random tracks to playlist if necessary
sub playRandom {
	# If addOnly, then track(s) are appended to end.  Otherwise, a new playlist is created.
	my ($client, $type, $addOnly) = @_;
	
	$client = $client->master;

	main::DEBUGLOG && $log->debug("Called with type $type");

	$client->pluginData('type', '') unless $client->pluginData('type');
	
	$type ||= 'track';
	$type = lc($type);

	# Whether to keep adding tracks after generating the initial playlist
	my $continuousMode = $prefs->get('continuous');

	if ($type ne $client->pluginData('type')) {
		$cache->remove('rnd_idList_' . $client->id);
	}

	my $songIndex = Slim::Player::Source::streamingSongIndex($client);
	my $songsRemaining = Slim::Player::Playlist::count($client) - $songIndex - 1;

	main::DEBUGLOG && $log->debug("$songsRemaining songs remaining, songIndex = $songIndex");

	# Work out how many items need adding
	my $numItems = 0;

	if ($type =~ /track|year/) {

		# Add new tracks if there aren't enough after the current track
		my $numRandomTracks = $prefs->get('newtracks');

		if (!$addOnly) {

			$numItems = $numRandomTracks;

		} elsif ($songsRemaining < $numRandomTracks) {

			$numItems = $numRandomTracks - $songsRemaining;

		} else {

			main::DEBUGLOG && $log->debug("$songsRemaining items remaining so not adding new track");
		}

	} elsif ($type ne 'disable' && ($type ne $client->pluginData('type') || !$addOnly || $songsRemaining <= 0)) {

		# Old artist/album/year is finished or new random mix started.  Add a new one
		$numItems = 1;
	}

	if ($numItems) {

		# String to show with showBriefly
		my $string = '';

		if ($type ne 'track') {
			$string = $client->string('PLUGIN_RANDOM_' . uc($type) . '_ITEM') . ': ';
		}

		# If not track mode, add tracks then go round again to check whether the playlist only
		# contains one track (i.e. the artist/album/year only had one track in it).  If so,
		# add another artist/album/year or the plugin would never add more when the first finished in continuous mode.
		for (my $i = 0; $i < 2; $i++) {

			if ($i == 0 || ($type =~ /track|year/ && Slim::Player::Playlist::count($client) == 1 && $continuousMode)) {

				if ($i == 1) {
					$string .= ' // ';
				}

				# Get the tracks.  year is a special case as we do a find for all tracks that match
				# the previously selected year
				findAndAdd($client,
				    $type,
				    $numItems,
					# 2nd time round just add tracks to end
					$i == 0 ? $addOnly : 1
				);
			}
		}

		# Do a show briefly the first time things are added, or every time a new album/artist/year is added
		if (!$addOnly || $type ne $client->pluginData('type') || $type !~ /track|year/) {

			if ($type eq 'track') {
				$string = $client->string("PLUGIN_RANDOM_TRACK");
			}

			# Don't do showBrieflys if visualiser screensavers are running as the display messes up
			if (Slim::Buttons::Common::mode($client) !~ /^SCREENSAVER./) {

				$client->showBriefly( {
					jive   => undef,
					'line' => [ string($addOnly ? 'ADDING_TO_PLAYLIST' : 'NOW_PLAYING'), $string ]
				}, 2, undef, undef, 1);
			}
		}
		
		# Never show random as modified, since its a living playlist
		$client->currentPlaylistModified(0);
	}

	if ($type eq 'disable') {

		main::INFOLOG && $log->info("Cyclic mode ended");

		# Don't do showBrieflys if visualiser screensavers are running as 
		# the display messes up
		if (Slim::Buttons::Common::mode($client) !~ /^SCREENSAVER./ && !$client->pluginData('disableMix')) {

			$client->showBriefly( {
				jive => string('PLUGIN_RANDOM_DISABLED'),
				'line' => [ string('PLUGIN_RANDOMPLAY'), string('PLUGIN_RANDOM_DISABLED') ]
			} );
			
		}

		$client->pluginData('disableMix', 0);
		$client->pluginData('type', '');

	} else {

		if ( main::INFOLOG && $log->is_info ) {
			$log->info(sprintf(
				"Playing %s %s mode with %i items",
				$continuousMode ? 'continuous' : 'static', $type, Slim::Player::Playlist::count($client)
			));
		}

		#BUG 5444: store the status so that users re-visiting the random mix 
		#          will see a continuous mode state.
		if ($continuousMode) {
			$client->pluginData('type', $type);
		}
	}
}

# Returns the display text for the currently selected item in the menu
sub getDisplayText {
	my ($client, $item) = @_;
	
	$client = $client->master;
	
	my $string = 'PLUGIN_RANDOM_' . ($item eq 'genreFilter' ? 'GENRE_FILTER' : uc($item));
	$string =~ s/S$//; 

	# if showing the current mode, show altered string
	if ($item eq ($client->pluginData('type') || '')) {

		return string($string . '_PLAYING');
		
	# if a mode is active, handle the temporarily added disable option
	} elsif ($item eq 'disable' && $client->pluginData('type')) {

		return join(' ',
			string('PLUGIN_RANDOM_PRESS_RIGHT'),
			string('PLUGIN_RANDOM_' . uc($client->pluginData('type')) . '_DISABLE')
		);

	} else {

		return string($string);
	}
}

# Returns the overlay to be display next to items in the menu
sub getOverlay {
	my ($client, $item) = @_;

	# Put the right arrow by genre filter and notesymbol by mixes
	if ($item =~ /^(?:genreFilter|library_filter)$/) {
		return [undef, $client->symbols('rightarrow')];
	
	} elsif (ref $item && ref $item eq 'HASH') {
		my $value = $item->{value} || '';
		my $library_id = $prefs->get('library') || '';
		
		return [undef, Slim::Buttons::Common::radioButtonOverlay($client, ($value eq $library_id) ? 1 : 0)];
		
	} elsif ($item ne 'disable') {
		return [undef, $client->symbols('notesymbol')];
	
	} else {
		return [undef, undef];
	}
}

# Returns the overlay for the select genres mode i.e. the checkbox state
sub getGenreOverlay {
	my ($client, $item) = @_;

	my $rv     = 0;
	my $genres = getGenres($client);	

	if ($item->{'selectAll'}) {

		# This item should be ticked if all the genres are selected
		my $genresEnabled = 0;

		for my $genre (keys %{$genres}) {

			if ($genres->{$genre}->{'enabled'}) {
				$genresEnabled++;
			}
		}

		$rv = $genresEnabled == scalar keys %{$genres};
		$item->{'enabled'} = $rv;

	} else {

		$rv = $genres->{$item->{'name'}}->{'enabled'};
	}

	return [undef, Slim::Buttons::Common::checkBoxOverlay($client, $rv)];
}

# Toggle the exclude state of a genre in the select genres mode
sub toggleGenreState {
	my ($client, $item) = @_;
	
	my $genres = getGenres($client);
	
	if ($item->{'selectAll'}) {

		$item->{'enabled'} = ! $item->{'enabled'};

		# Enable/disable every genre
		foreach my $genre (keys %$genres) {
			$genres->{$genre}->{'enabled'} = $item->{'enabled'};
		}

	} else {

		# Toggle the selected state of the current item
		$genres->{$item->{'name'}}->{'enabled'} = ! $genres->{$item->{'name'}}->{'enabled'};
	}

	$prefs->set('exclude_genres', getFilteredGenres($client, 1, 1) );

	$client->update;
}

sub toggleLibrarySelection {
	my ($client, $item) = @_;
	
	return unless $item && ref $item;
	
	$prefs->set('library', $item->{value} || '');
}

# Do what's necessary when play or add button is pressed
sub handlePlayOrAdd {
	my ($client, $item, $add) = @_;

	if ( main::DEBUGLOG && $log->is_debug ) {
		$log->debug(sprintf("RandomPlay: %s button pushed on type %s", $add ? 'Add' : 'Play', $item));
	}

	# reconstruct the list of options, adding and removing the 'disable' option where applicable
	if ($item ne 'genreFilter') {

		my $listRef = $client->modeParam('listRef');

		if ($item eq 'disable') {

			pop @$listRef;

		} elsif (!$client->pluginData('type')) {

			# only add disable option if starting a mode from idle state
			push @$listRef, 'disable';
		}

		$client->modeParam('listRef', $listRef);

		# Go go go!
		playRandom($client, $item, $add);
	}
}

sub setMode {
	my $class  = shift;
	my $client = shift;
	my $method = shift;
	
	if (!$initialized) {
		$client->bumpRight();
		return;
	}
	
	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}

	# use INPUT.Choice to display the list of feeds
	my %params = (
		header     => '{PLUGIN_RANDOMPLAY}',
		headerAddCount => 1,
		listRef    => [qw(track album contributor year genreFilter library_filter)],
		name       => \&getDisplayText,
		overlayRef => \&getOverlay,
		modeName   => 'RandomPlay',
		onPlay     => sub { handlePlayOrAdd(@_[0,1], 0) },
		onAdd      => sub {	handlePlayOrAdd(@_[0,1], 1) },
		onRight    => sub {
			my ($client, $item) = @_;

			if ($item eq 'genreFilter') {

				my $genres = getGenres($client);

				# Insert Select All option at top of genre list
				my @listRef = ({
					name => $client->string('PLUGIN_RANDOM_SELECT_ALL'),
					# Mark the fact that isn't really a genre
					selectAll => 1,
					value     => 1,
				});

				# Add the genres
				foreach my $genre ( getSortedGenres($client) ) {
					
					# HACK: add 'value' so that INPUT.Choice won't complain as much. nasty setup there.
					$genres->{$genre}->{'value'} = $genres->{$genre}->{'id'};
					push @listRef, $genres->{$genre};
				}

				Slim::Buttons::Common::pushModeLeft($client, 'INPUT.Choice', {
					header     => '{PLUGIN_RANDOM_GENRE_FILTER}',
					headerAddCount => 1,
					listRef    => \@listRef,
					modeName   => 'RandomPlayGenreFilter',
					overlayRef => \&getGenreOverlay,
					onRight    => \&toggleGenreState,
				});

			} elsif ($item eq 'library_filter') {
				my $library_id = $prefs->get('library');
				my $libraries  = _getLibraries();
			
				my @listRef = ({
					name => cstring($client, 'ALL_LIBRARY'),
				});
				
				foreach my $id ( sort { lc($libraries->{$a}) cmp lc($libraries->{$b}) } keys %$libraries ) {
					push @listRef, {
						name => $libraries->{$id},
						value => $id
					};
				}

				Slim::Buttons::Common::pushModeLeft($client, 'INPUT.Choice', {
					header     => '{PLUGIN_RANDOM_LIBRARY_FILTER}',
					headerAddCount => 1,
					listRef    => \@listRef,
					modeName   => 'RandomPlayLibraryFilter',
					overlayRef => \&getOverlay,
					onRight    => \&toggleLibrarySelection,
				});

			} elsif ($item eq 'disable') {
				handlePlayOrAdd($client, $item, 0);
			} else {
				$client->bumpRight();
			}
		},
	);

	# if we have an active mode, temporarily add the disable option to the list.
	if ($client->master->pluginData('type')) {
		push @{$params{'listRef'}}, 'disable';
	}

	Slim::Buttons::Common::pushMode($client, 'INPUT.Choice', \%params);
}

sub commandCallback {
	my $request = shift;
	my $client  = $request->client();

	# Don't respond to callback for ourself or for requests originating from the alarm clock.  This is necessary,
	# as the alarm clock uses a playlist play command to start random mixes and we then get notified of them so
	# could end up stopping immediately.
	if ($request->source && ($request->source eq 'PLUGIN_RANDOMPLAY' || $request->source eq 'ALARM')) {
		return;
	}

	if (!defined $client || !$client->master->pluginData('type') || !$prefs->get('continuous')) {
		return;
	}
	
	$client = $client->master;
	
	# Bug 8652, ignore playlist play commands for our randomplay:// URL
	if ( $request->isCommand( [['playlist'], ['play']] ) ) {
		my $url  = $request->getParam('_item');
		my $type = $client->pluginData('type');
		if ( $url eq "randomplay://$type" ) {
			return;
		}
	}

	if ( main::DEBUGLOG && $log->is_debug ) {
		$log->debug(sprintf("Received command %s", $request->getRequestString));
		$log->debug(sprintf("While in mode: %s, from %s", $client->pluginData('type'), $client->name));
	}

	my $songIndex = Slim::Player::Source::streamingSongIndex($client);

	if ($request->isCommand([['playlist'], ['newsong']]) || 
	    $request->isCommand([['playlist'], ['delete']]) && 
	    $request->getParam('_index') > $songIndex) {

		if (main::INFOLOG && $log->is_info) {

			if ($request->isCommand([['playlist'], ['newsong']])) {

				if (Slim::Player::Sync::isSlave($client)) {
					main::DEBUGLOG && $log->debug(sprintf("Ignoring new song notification for slave player"));
					return;
				} else {
					$log->info(sprintf("New song detected ($songIndex)"));
				}
				
			} else {

				$log->info(sprintf("Deletion detected (%s)", $request->getParam('_index')));
			}
		}

		my $songsToKeep = $prefs->get('oldtracks');
		my $playlistCount = Slim::Player::Playlist::count($client);

		if ($songIndex && $songsToKeep ne '' && $songIndex > $songsToKeep) {

			if ( main::INFOLOG && $log->is_info ) {
				$log->info(sprintf("Stripping off %i completed track(s)", $songIndex - $songsToKeep));
			}

			# Delete tracks before this one on the playlist
			for (my $i = 0; $i < $songIndex - $songsToKeep; $i++) {

				my $request = $client->execute(['playlist', 'delete', 0]);
				$request->source('PLUGIN_RANDOMPLAY');
			}
		}

		Slim::Utils::Timers::killTimers($client, \&_addTracksLater);

		# Bug: 16890 only defer adding tracks if we are not nearing end of the playlist
		# this avoids repeating the playlist due to the user skipping tracks
		if ($playlistCount - $songIndex > $prefs->get('newtracks') / 2) {

			Slim::Utils::Timers::setTimer($client, time() + 10, \&_addTracksLater);

		} else {

			playRandom($client, $client->pluginData('type'), 1);
		}

	} elsif ($request->isCommand([['playlist'], $stopcommands])) {

		if ( main::INFOLOG && $log->is_info ) {
			$log->info(sprintf("Cyclic mode ending due to playlist: %s command", $request->getRequestString));
		}

		Slim::Utils::Timers::killTimers($client, \&_addTracksLater);

		playRandom($client, 'disable');
	}
}

sub _addTracksLater {
	my $client = shift;
	
	if ($client->pluginData('type')) {
		playRandom($client, $client->pluginData('type'), 1);
	}
}

sub cliRequest {
	my $request = shift;
 
 	if (!$initialized) {
 		$request->setStatusBadConfig();
 		return;
 	}
 	
	# get our parameters
	my $mode   = $request->getParam('_mode');

	# try mapping CLI plural values on singular values used internally (eg. albums -> album)
	$mode      = $mixTypeMap{$mode} || $mode;

	my $client = $request->client();

	# return quickly if we lack some information	
	if ($mode && $mode eq 'disable' && $client) {
		
		# nothing to do here unless a mix is going on
		if ( !$client->pluginData('type') ) {
			$request->setStatusDone();
			return;
		}
		
		$client->pluginData('disableMix', 1);
	}
	elsif (!defined $mode || !(scalar grep /$mode/, @mixTypes) || !$client) {
		$request->setStatusBadParams();
		return;
	}

	if (my $genre = $request->getParam('genre_id')){
		my $name = Slim::Schema->find('Genre', $genre)->name;
		
		my $genres = getGenres($client);
	
		# in $genres, an enabled genre returns true for $genres->{'enabled'}
		my @excluded = ();
		for (keys %$genres) {
			push @excluded, $_ unless $_ eq $name;
		}
		# set the exclude_genres pref to all disabled genres 
		$prefs->set('exclude_genres', [@excluded]);
		$genres->{$name}->{'enabled'} = 1;
	}

	playRandom($client, $mode);
	
	$request->setStatusDone();
}

sub cliIsActive {
	my $request = shift;
  	my $client = $request->client();

	$request->addResult('_randomplayisactive', active($client) );
	$request->setStatusDone();
}


# legacy method to allow mapping to remote buttons
sub getFunctions {

	return $functions;
}

sub buttonStart {
	my $client = shift;

	playRandom($client, $client->pluginData('type') || 'track');
}

sub webPages {
	my $class = shift;

	my $urlBase = 'plugins/RandomPlay';

	if ($initialized) {
		Slim::Web::Pages->addPageLinks("browse", { 'PLUGIN_RANDOMPLAY' => $htmlTemplate });
	} else {
		Slim::Web::Pages->delPageLinks("browse", 'PLUGIN_RANDOMPLAY');
		return;
	}

	Slim::Web::Pages->addPageFunction("$urlBase/list.html", \&handleWebList);
	Slim::Web::Pages->addPageFunction("$urlBase/mix.html", \&handleWebMix);
	Slim::Web::Pages->addPageFunction("$urlBase/settings.html", \&handleWebSettings);

	Slim::Web::HTTP::CSRF->protectURI("$urlBase/list.html");
	Slim::Web::HTTP::CSRF->protectURI("$urlBase/mix.html");
	Slim::Web::HTTP::CSRF->protectURI("$urlBase/settings.html");
}

# Draws the plugin's web page
sub handleWebList {
	my ($client, $params) = @_;

	if ($client) {
		# Pass on the current pref values and now playing info
		my $genres = getGenres($client);
		$params->{'pluginRandomGenreList'}     = $genres;
		$params->{'pluginRandomGenreListSort'} = [ getSortedGenres($client) ];
		$params->{'pluginRandomNumTracks'}     = $prefs->get('newtracks');
		$params->{'pluginRandomNumOldTracks'}  = $prefs->get('oldtracks');
		$params->{'pluginRandomContinuousMode'}= $prefs->get('continuous');
		$params->{'pluginRandomNowPlaying'}    = $client->master->pluginData('type');
		$params->{'pluginRandomUseLibrary'}    = $prefs->get('library');

		$params->{'mixTypes'}                  = \@mixTypes;
		$params->{'favorites'}                 = {};

		map { 
			$params->{'favorites'}->{$_} = 
				Slim::Utils::Favorites->new($client)->findUrl("randomplay://$_")
				|| Slim::Utils::Favorites->new($client)->findUrl("randomplay://$mixTypeMap{$_}")
				|| 0;
		} keys %mixTypeMap, @mixTypes;
		
		$params->{'libraries'} ||= _getLibraries();
	}
	
	return Slim::Web::HTTP::filltemplatefile($htmlTemplate, $params);
}

# Handles play requests from plugin's web page
sub handleWebMix {
	my ($client, $params) = @_;

	if (defined $client && $params->{'type'}) {
		playRandom($client, $params->{'type'}, $params->{'addOnly'});
	}

	handleWebList($client, $params);
}

# Handles settings changes from plugin's web page
sub handleWebSettings {
	my ($client, $params) = @_;

	my $genres = getGenres($client);

	# %$params will contain a key called genre_<genre id> for each ticked checkbox on the page
	for my $genre (keys %{$genres}) {

		if ($params->{'genre_'.$genres->{$genre}->{'id'}}) {
			delete($genres->{$genre});
		}
	}

	$prefs->set('exclude_genres', [keys %{$genres}]);
 	$prefs->set('newtracks', $params->{'numTracks'});
 	$prefs->set('oldtracks', $params->{'numOldTracks'});
	$prefs->set('continuous', $params->{'continuousMode'} ? 1 : 0);
	$prefs->set('library', $params->{'useLibrary'});
	
	# Pass on to check if the user requested a new mix as well
	handleWebMix($client, $params);
}

sub _getLibraries {
	my $libraries = Slim::Music::VirtualLibraries->getLibraries();
	my %libraries;

	%libraries = map {
		$_ => $libraries->{$_}->{name}
	} keys %$libraries if keys %$libraries;
	
	return \%libraries;
}

sub active {
	my $client = shift;
	
	return $client->master->pluginData('type');
}

# Called by Slim::Utils::Alarm to get the playlists that should be presented as options
# for an alarm playlist.
sub getAlarmPlaylists {
	my $class = shift;

	return [ {
		type => 'PLUGIN_RANDOMPLAY',
		items => [
			{ title => '{PLUGIN_RANDOM_TRACK}', url	=> 'randomplay://track' },
			{ title => '{PLUGIN_RANDOM_ALBUM}', url	=> 'randomplay://album' },
			{ title => '{PLUGIN_RANDOM_CONTRIBUTOR}', url => 'randomplay://contributor' },
			{ title => '{PLUGIN_RANDOM_YEAR}', url => 'randomplay://year' },
		]
	} ];
}

1;

__END__


