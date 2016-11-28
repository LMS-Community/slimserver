package Slim::Plugin::Favorites::Plugin;

# A Favorites implementation which stores favorites as opml files and allows
# the favorites list to be edited from the web interface

# Includes code from the MyPicks plugin by Adrian Smith and Bryan Alton

# This code is derived from code with the following copyright message:
#
# Logitech Media Server Copyright 2005-2016 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use base qw(Slim::Plugin::Base);

use Tie::Cache::LRU;

use Slim::Buttons::Common;
use Slim::Utils::Favorites;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string cstring);
use Slim::Music::Info;
use Slim::Utils::Prefs;

use Slim::Plugin::Favorites::Opml;
use Slim::Plugin::Favorites::OpmlFavorites;

if ( main::WEBUI ) {
 	require Slim::Plugin::Favorites::Settings;
	require Slim::Web::XMLBrowser;
}

use Slim::Plugin::Favorites::Playlist;

use constant MENU_WEIGHT => 55;

my $log = logger('favorites');

my $prefs = preferences('plugin.favorites');

# make sure the value is defined, otherwise it would be enabled again
$prefs->setChange( sub {
	$prefs->set($_[0], 0) unless defined $_[1];
}, 'registerDSTM' );


# support multiple edditing sessions at once - indexed by sessionId.  [Default to favorites editting]
my $nextSession = 2; # session id 1 = favorites
tie my %sessions, 'Tie::Cache::LRU', 4;

sub initPlugin {
	my $class = shift;

	$prefs->init({
		registerDSTM => 1,
	});

	$class->SUPER::initPlugin(@_);
	
	Slim::Plugin::Favorites::OpmlFavorites->migrate();
	
	if ( main::WEBUI ) {
		Slim::Plugin::Favorites::Settings->new;
	}
	
	# register opml based favorites handler
	Slim::Utils::Favorites::registerFavoritesClassName('Slim::Plugin::Favorites::OpmlFavorites');

	# register cli handlers
	Slim::Control::Request::addDispatch(['favorites', 'items', '_index', '_quantity'], [0, 1, 1, \&cliBrowse]);
	Slim::Control::Request::addDispatch(['favorites', 'add'], [0, 0, 1, \&cliAdd]);
	Slim::Control::Request::addDispatch(['favorites', 'addlevel'], [0, 0, 1, \&cliAdd]);
	Slim::Control::Request::addDispatch(['favorites', 'delete'], [0, 0, 1, \&cliDelete]);
	Slim::Control::Request::addDispatch(['favorites', 'rename'], [0, 0, 1, \&cliRename]);
	Slim::Control::Request::addDispatch(['favorites', 'move'], [0, 0, 1, \&cliMove]);
	Slim::Control::Request::addDispatch(['favorites', 'playlist', '_method' ],[1, 1, 1, \&cliBrowse]);
	Slim::Control::Request::addDispatch(['favorites', 'exists', '_id'], [0, 1, 1, \&cliExists]);
	
	# register notifications
	Slim::Control::Request::addDispatch(['favorites', 'changed'], [0, 0, 0, undef]);

	# register new mode for deletion of favorites	
	Slim::Buttons::Common::addMode( 'favorites.delete', {}, \&deleteMode );
	
	# Track Info handler
	Slim::Menu::TrackInfo->registerInfoProvider( favorites => (
		after => 'playitem',
		func  => \&trackInfoHandler,
	) );
	# Album Info handler
	Slim::Menu::AlbumInfo->registerInfoProvider( favorites => (
		after => 'playitem',
		func  => \&albumInfoHandler,
	) );
	# Artist Info handler
	Slim::Menu::ArtistInfo->registerInfoProvider( favorites => (
		after => 'playitem',
		func  => \&artistInfoHandler,
	) );
	# Playlist Info handler
	Slim::Menu::PlaylistInfo->registerInfoProvider( favorites => (
		after => 'playitem',
		func  => \&playlistInfoHandler,
	) );
}

sub postinitPlugin {
	# if user has the Don't Stop The Music plugin enabled, register ourselves
	if ( Slim::Utils::PluginManager->isEnabled('Slim::Plugin::DontStopTheMusic::Plugin') ) {
		require Slim::Plugin::DontStopTheMusic::Plugin;
		
		registerFavoritesAsDSTMProvider();
		
		$prefs->setChange(sub {
			unregisterFavoritesAsDSTMProvider();
			registerFavoritesAsDSTMProvider();
		}, 'registerDSTM');
		
		Slim::Control::Request::subscribe(\&registerFavoritesAsDSTMProvider, [['favorites'], ['changed']]);
	}
}

sub registerFavoritesAsDSTMProvider {
	if ( $prefs->get('registerDSTM') && (my $favsObject = Slim::Utils::Favorites->new()) ) {
		foreach my $fav (@{$favsObject->all}) {
			Slim::Plugin::DontStopTheMusic::Plugin->registerHandler($fav->{title}, sub {
				$_[1]->($_[0], [$fav->{url}]);
			});
		}
	}
}

sub unregisterFavoritesAsDSTMProvider {
	if (my $favsObject = Slim::Utils::Favorites->new()) {
		foreach my $fav (@{$favsObject->all}) {
			Slim::Plugin::DontStopTheMusic::Plugin->unregisterHandler($fav->{title});
		}
	}
}


sub modeName { 'FAVORITES' };

sub weight { MENU_WEIGHT }

sub setMode {
	my $class = shift;
	my $client = shift;
	my $method = shift;

	if ( $method eq 'pop' ) {
		Slim::Buttons::Common::popMode($client);
		return;
	}
	
	my $opml = Slim::Plugin::Favorites::OpmlFavorites->new($client)->xmlbrowser;

	# use INPUT.Choice to display the list of feeds
	my %params = (
		header   => 'PLUGIN_FAVORITES_LOADING',
		modeName => 'Favorites.Browser',
		opml     => $opml,
		title    => $client->string('FAVORITES'),
	);

	Slim::Buttons::Common::pushMode($client, 'xmlbrowser', \%params);

	# we'll handle the push in a callback
	$client->modeParam('handledTransition',1)
}

sub deleteMode {
	my ( $client, $method ) = @_;
	
	if ( $method eq 'pop' ) {
		Slim::Buttons::Common::popMode($client);
		return;
	}
	
	my $title = $client->modeParam('title'); # title to display
	my $index = $client->modeParam('index'); # favorite index to delete
	my $depth = $client->modeParam('depth'); # number of levels to pop out of when done
	
	# Bug 6177, Menu to confirm favorite removal
	Slim::Buttons::Common::pushMode( $client, 'INPUT.Choice', {
		header   => '{PLUGIN_FAVORITES_REMOVE}',
		title    => $title,
		favorite => $index,
		listRef  => [
			{
				name    => "{PLUGIN_FAVORITES_CANCEL}",
				onRight => sub {
					Slim::Buttons::Common::popModeRight(shift);
				},
			},
			{
				name    => "{FAVORITES_RIGHT_TO_DELETE}",
				onRight => sub {
					my $client = shift;
					my $index  = $client->modeParam('favorite');
					
					my $favorites = Slim::Utils::Favorites->new($client);					
					$favorites->deleteIndex($index);
					
					$client->modeParam( 'favorite', undef );
					
					$client->showBriefly( {
						line => [ $client->string('FAVORITES_DELETING'), $title ],
					},
					{
						callback     => sub {
							my $client = shift || return;
							
							# Pop back until we're out of Favorites
							for ( 1 .. $depth ) {
								Slim::Buttons::Common::popModeRight($client);
							}
							
							$client->update;
						},
						callbackargs => $client,
					} );
				},
			},
		],
		overlayRef => [ undef, $client->symbols('rightarrow') ],
	} );
}

sub webPages {
	my $class = shift;

	Slim::Web::Pages->addPageFunction('plugins/Favorites/favcontrol.html', \&toggleButtonHandler);
	Slim::Web::Pages->addPageFunction('plugins/Favorites/index.html', \&indexHandler);

	Slim::Web::Pages->addPageLinks('browse', { 'FAVORITES' => 'plugins/Favorites/index.html' });

	addEditLink();
}

sub addEditLink {
	my $enabled = $prefs->get('opmleditor');

	Slim::Web::Pages->addPageLinks('plugins', { 'PLUGIN_FAVORITES_PLAYLIST_EDITOR' => $enabled ? 'plugins/Favorites/index.html?new' : undef });
}

sub toggleButtonHandler {
	my $client = shift;
	my $params = shift;

	my $favs = Slim::Utils::Favorites->new($client);

	$params->{favoritesEnabled} = 1;
	$params->{itemobj} = {
		url => $params->{url}, 
		title => $params->{title},
	};

	if ($favs && $params->{url}) {

		if (defined $favs->findUrl($params->{url})) {

			$favs->deleteUrl( $params->{'url'} );
			$params->{item}->{isFavorite} = 0;
		}

		else {

			$favs->add( $params->{url}, $params->{title} || $params->{url} );
			$params->{item}->{isFavorite} = defined $favs->findUrl($params->{url});
		}
	}

	return Slim::Web::HTTP::filltemplatefile('plugins/Favorites/favcontrol.html', $params);
}

sub indexHandler {
	my $client = shift;
	my $params = shift;

	# Debug:
	#for my $key (keys %$params) {
	#	print "Key: $key, Val: ".$params->{$key}."\n";
	#}

	my $opml;     # opml hash for current editing session
	my $deleted;  # any deleted sub tree which may be added back
	my $autosave; # save each change
	my $sessId;   # current editing session id

	my $edit;     # index of entry to edit if set
	my $changed;  # opml has been changed

	if ($params->{'sess'} && $sessions{ $params->{'sess'} }) {

		$sessId = $params->{'sess'};

		main::INFOLOG && $log->info("existing editing session [$sessId]");

		$opml     = $sessions{ $sessId }->{'opml'};
		$deleted  = $sessions{ $sessId }->{'deleted'};
		$autosave = $sessions{ $sessId }->{'autosave'};

	} elsif ($params->{'sess'} && $params->{'sess'} > 1 || $params->{'new'}) {

		my $url   = $params->{'new'};

		$sessId   = $nextSession++;
		$deleted  = undef;
		$autosave = $params->{'autosave'};

		if (Slim::Music::Info::isURL($url)) {

			main::INFOLOG && $log->info("new opml editting session [$sessId] - opening $url");

			$opml = Slim::Plugin::Favorites::Opml->new({ 'url' => $url });

		} else {

			main::INFOLOG && $log->info("new opml editing session [$sessId]");

			$opml = Slim::Plugin::Favorites::Opml->new();
		}

	} else {

		main::INFOLOG && $log->info("new favorites editing session");

		$opml = Slim::Plugin::Favorites::OpmlFavorites->new($client);
		$deleted  = undef;
		$autosave = 1;
		$sessId   = 1;
	}

	# get the level to operate on - this is the level containing the index if action is set, otherwise the level specified by index
	my ($level, $indexLevel, @indexPrefix) = $opml->level($params->{'index'}, defined $params->{'action'});

	if (!defined $level || $params->{'action'} =~ /^(?:play|add|insert)/) {

		# favorites editor cannot follow remote links, so pass through to xmlbrowser as index does not appear to be edittable
		# also pass through play/add to reuse xmlbrowser handling of playall etc
		main::INFOLOG && $log->info("passing through to xmlbrowser");
			
		return Slim::Web::XMLBrowser->handleWebIndex( {
			client => $client,
			feed   => $opml->xmlbrowser,
			args   => [$client, $params, @_],
		} );
	}

	# if not editting favorites create favs class so we can add or delete urls from favorites
	my $favs = $opml->isa('Slim::Plugin::Favorites::OpmlFavorites') ? undef : Slim::Plugin::Favorites::OpmlFavorites->new($client);

	if ($params->{'loadfile'}) {

		my $url = $params->{'filename'};

		if (Slim::Music::Info::isRemoteURL($url)) {

			if (!$params->{'fetched'}) {
				Slim::Networking::SimpleAsyncHTTP->new(
					\&asyncCBContent, \&asyncCBContent, { 'args' => [$client, $params, @_] }
				)->get( $url );
				return;
			}

			$opml->load({ 'url' => $url, 'content' => $params->{'fetchedcontent'} });

		} else {

			$opml->load({ 'url' => $url });
		}

		($level, $indexLevel, @indexPrefix) = $opml->level(undef, undef);
		$deleted = undef;
	}

	if ($params->{'savefile'} || $params->{'savechanged'}) {

		$opml->filename($params->{'filename'}) if $params->{'savefile'};

		$opml->save;

		$changed = undef unless $opml->error;

		if ($favs && $opml != $favs && $opml->filename eq $favs->filename) {
			# overwritten the favorites file - force favorites to be reloaded
			$favs->load;
		}
	}

	if ($params->{'importfile'}) {

		my $url = $params->{'filename'};
		my $playlist;

		if ($url =~ /\.opml$/) {

			if (Slim::Music::Info::isRemoteURL($url)) {

				if (!$params->{'fetched'}) {
					Slim::Networking::SimpleAsyncHTTP->new(
						\&asyncCBContent, \&asyncCBContent,	{ 'args' => [$client, $params, @_] }
					)->get( $url );
					return;
				}

				$playlist = Slim::Plugin::Favorites::Opml->new({ 'url' => $url, 'content' => $params->{'fetchedcontent'} })->toplevel;

			} else {

				$playlist = Slim::Plugin::Favorites::Opml->new({ 'url' => $url })->toplevel;
			}

		} else {

			$playlist = Slim::Plugin::Favorites::Playlist->read($url);
		}

		if ($playlist && scalar @$playlist) {

			for my $entry (@$playlist) {
				push @$level, $entry;
			}

			$changed = 1;

		} else {

			$params->{'errormsg'} = string('PLUGIN_FAVORITES_IMPORTERROR') . " " . $url;
		}
	}

	if ($params->{'title'}) {
		$opml->title( $params->{'title'} );
	}

	if (my $action = $params->{'action'}) {

		if ($action eq 'edit') {
			$edit = $indexLevel;
		}

		if ($action eq 'delete') {

			$deleted = splice @$level, $indexLevel, 1;

			$changed = 1;
		}

		if ($action eq 'move' && defined $params->{'to'} && $params->{'to'} < scalar @$level) {

			my $entry = splice @$level, $indexLevel, 1;

			splice @$level, $params->{'to'}, 0, $entry;

			$changed = 1;
		}

		if ($action eq 'move' && defined $params->{'tolevel'}) {

			my ($dest, undef, undef) = $opml->level($params->{'tolevel'});

			if ($dest) {
				push @$dest, splice @$level, $indexLevel, 1;
			}

			$changed = 1;
		}

		if ($action eq 'move' && defined $params->{'into'}) {

			if (my $dest = @$level[$params->{'into'}]->{'outline'}) {

				push @$dest, splice @$level, $indexLevel, 1;
			}
				
			$changed = 1;
		}

		if ($action eq 'movedown') {

			my $entry = splice @$level, $indexLevel, 1;

			splice @$level, $indexLevel + 1, 0, $entry;

			$changed = 1;
		}

		if ($action eq 'moveup' && $indexLevel > 0) {

			my $entry = splice @$level, $indexLevel, 1;

			splice @$level, $indexLevel - 1, 0, $entry;

			$changed = 1;
		}

		if ($action eq 'editset' && defined $params->{'index'}) {

			if ($params->{'cancel'} && $params->{'removeoncancel'}) {

				# cancel on a new item - remove it
				splice @$level, $indexLevel, 1;

			} elsif ($params->{'entrytitle'}) {

				# editted item - modify including possibly changing type
				my $entry = @$level[$indexLevel];

				$entry->{'text'} = $params->{'entrytitle'};

				if (defined $params->{'entryurl'} && $params->{'entryurl'} ne $entry->{'URL'}) {

					my $url = $params->{'entryurl'};

					if ($url !~ /^http:/) {

						if ($url !~ /\.(xml|opml|rss)$/) {
							
							$entry->{'type'} = 'audio';
							
						} else {
							
							delete $entry->{'type'};
						}
						
					} elsif (!$params->{'fetched'}) {
						
						main::INFOLOG && $log->info("checking content type for $url");
						
						Slim::Networking::Async::HTTP->new()->send_request( {
							'request'     => HTTP::Request->new( GET => $url ),
							'onHeaders'   => \&asyncCBContentType,
							'onError'     => \&asyncCBContentTypeError,
							'passthrough' => [ $client, $params, @_ ],
						} );
						
						return;
						
					} else {

						my $mime = $params->{'fetchedtype'} || 'error';
						my $type = Slim::Music::Info::mimeToType($mime);

						if ($type) {

							main::INFOLOG && $log->info("got mime type $mime");

						} else {

							main::INFOLOG && $log->info("unknown mime type $mime, inferring from url");

							$type = Slim::Music::Info::typeFromPath($url);
						}

						if (Slim::Music::Info::isSong(undef, $type) || Slim::Music::Info::isPlaylist(undef, $type)) {
							
							main::INFOLOG && $log->info("content type $type - treating as audio");
							
							$entry->{'type'} = 'audio';
							
						} else {
							
							main::INFOLOG && $log->info("content type $type - treating as non audio");

							delete $entry->{'type'};
						}
					}

					$entry->{'URL'} = $url;
				}
			}

			$changed = 1;
		}

		if ($action eq 'favadd' && defined $params->{'index'} && $favs) {

			my $entry = @$level[$indexLevel];

			$favs->add( $entry->{'URL'}, $entry->{'text'}, $entry->{'type'}, $entry->{'parser'} );
		}

		if ($action eq 'favdel' && defined $params->{'index'} && $favs) {

			my $entry = @$level[$indexLevel];

			$favs->deleteUrl( $entry->{'URL'} );
		}
	}

	if ($params->{'forgetdelete'}) {

		$deleted = undef;
	}

	if ($params->{'insert'} && $deleted) {

		push @$level, $deleted;

		$deleted = undef;
		$changed = 1;
	}

	if ($params->{'newentry'}) {

		push @$level,{
			'text' => string('PLUGIN_FAVORITES_NAME'),
			'URL'  => string('PLUGIN_FAVORITES_URL'),
		};

		$edit = scalar @$level - 1;
		$params->{'removeoncancel'} = 1;
		$changed = 1;
	}

	if ($params->{'newlevel'}) {

		push @$level, {
			'text'   => string('PLUGIN_FAVORITES_NAME'),
			'outline'=> [],
		};

		$edit = scalar @$level - 1;
		$params->{'removeoncancel'} = 1;
		$changed = 1;
	}

	# save session data for next call
	$sessions{ $sessId } = {
		'opml'     => $opml,
		'deleted'  => $deleted,
		'autosave' => $autosave,
	};

	# save each change if autosave set
	if ($changed && $opml && $autosave) {
		$opml->save;
	}

	# set params for page build
	$params->{'sess'}      = $sessId;
	$params->{'favorites'} = !$favs;
	$params->{'title'}     = $opml->title;
	$params->{'filename'}  = $opml->filename;
	$params->{'deleted'}   = defined $deleted ? $deleted->{'text'} : undef;
	$params->{'editmode'}  = defined $edit;
	$params->{'autosave'}  = $autosave;

	if ($opml && $opml->error) {
		$params->{'errormsg'} = string('PLUGIN_FAVORITES_' . $opml->error) . " " . $opml->filename;
		$opml->clearerror;
	}

	# add the entries for current level
	my @entries;
	my $i = 0;

	foreach my $opmlEntry (@$level) {
		my $entry = {
			'title'   => $opmlEntry->{'text'} || '',
			'url'     => $opmlEntry->{'URL'} || $opmlEntry->{'url'} || '',
			'audio'   => (defined $opmlEntry->{'type'} && $opmlEntry->{'type'} =~ /audio|playlist/) ? 1 : 0,
			'outline' => $opmlEntry->{'outline'},
			'edit'    => (defined $edit && $edit == $i) ? 1 : 0,
			'index'   => join('.', (@indexPrefix, $i++)),
			'icon'    => $opmlEntry->{'icon'},
		};

		if ($favs && $entry->{'url'}) {
			$entry->{'favorites'} = $favs->hasUrl($entry->{'url'}) ? 2 : 1;
		}

		push @entries, $entry;
	}

	$params->{'entries'}       = \@entries;
	$params->{'levelindex'}    = join '.', @indexPrefix;
	$params->{'indexOnLevel'}  = $indexLevel;

	# add the top level title to pwd_list
	push @{$params->{'pwd_list'}}, {
		'title' => $opml && $opml->title || string('PLUGIN_FAVORITES_EDITOR'),
		'href'  => 'href="index.html?index=&sess=' . $sessId . '"',
	};

	# add remaining levels up to current level to pwd_list
	for (my $i = 0; $i <= $#indexPrefix; ++$i) {

		my @ind = @indexPrefix[0..$i];
		push @{$params->{'pwd_list'}}, {
			'title' => $opml->entry(\@ind)->{'text'},
			'href'  => 'href="index.html?index=' . (join '.', @ind) . '&sess=' . $sessId . '"',
		};
	}

	# fill template and send back response
	my $callback = shift;
	my $output = Slim::Web::HTTP::filltemplatefile('plugins/Favorites/index.html', $params);

	$callback->($client, $params, $output, @_);
}

sub asyncCBContent {
	# callback for async http content fetching
	# causes indexHandler to be processed again with stored params + fetched content
	my $http = shift;
	my ($client, $params, $callback, $httpClient, $response) = @{ $http->params('args') };

	$params->{'fetched'}        = 1;
	$params->{'fetchedcontent'} = $http->content;

	indexHandler($client, $params, $callback, $httpClient, $response);
}

sub asyncCBContentType {
	# callback for establishing content type
	# causes indexHandler to be processed again with stored params + fetched content type
	my ($http, $client, $params, $callback, $httpClient, $response) = @_;

	$params->{'fetched'} = 1;
	$params->{'fetchedtype'} = $http->response->content_type;

	$http->disconnect;

	indexHandler($client, $params, $callback, $httpClient, $response);
}

sub asyncCBContentTypeError {
	# error callback for establishing content type - causes indexHandler to be processed again with stored params
	my ($http, $error, $client, $params, $callback, $httpClient, $response) = @_;

	$params->{'fetched'} = 1;

	indexHandler($client, $params, $callback, $httpClient, $response);
}

sub cliBrowse {
	my $request = shift;
	my $client  = $request->client;

	if ($request->isNotQuery([['favorites'], ['items', 'playlist']])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	my $feed = Slim::Plugin::Favorites::OpmlFavorites->new($client)->xmlbrowser;

	Slim::Control::XMLBrowser::cliQuery('favorites', $feed, $request);
}

sub cliExists {
	my $request = shift;

	my $client = $request->client();
	my $id     = $request->getParam('_id');
	my $url;
	
	my $favs = Slim::Utils::Favorites->new($client);
	
	if ( $id =~ /^\d+$/ ) {
		my $obj = Slim::Schema->rs('Track')->find($id);
		if ( !$obj ) {
			$request->setStatusBadParams();
			return;
		}
		
		$url = $obj->url;
	}
	else {
		$url = $id;
	}
	
	my $index = $favs->findUrl($url);
	
	if ( defined $index ) {
		$request->addResult( exists => 1 );
		$request->addResult( index  => $index );
	}
	else {
		$request->addResult( exists => 0 );
	}
	
	$request->setStatusDone();
}

sub cliAdd {
	my $request = shift;

	if ($request->isNotCommand([['favorites'], ['add', 'addlevel']])) {
		$request->setStatusBadDispatch();
		return;
	}

	my $client = $request->client();
	my $command= $request->getRequest(1);
	my $url    = $request->getParam('url');
	my $title  = $request->getParam('title');
	my $icon   = $request->getParam('icon');
	my $index  = $request->getParam('item_id');
	my $type   = $request->getParam('type');
	my $parser = $request->getParam('parser');
	my $hotkey = $request->getParam('hotkey');

	my $favs = Slim::Plugin::Favorites::OpmlFavorites->new($client);

	my ($level, $i) = $favs->level($index, 'contains');

	if ($level) {

		my $entry;

		if ($command eq 'add' && defined $title && defined $url) {

			main::INFOLOG && $log->info("adding entry $title $url at index $index");

			$entry = {
				'text' => $title,
				'URL'  => $url,
				'type' => $type || 'audio',
				'icon' => $icon || $favs->icon($url),
			};
			$entry->{'parser'} = $parser if $parser;
			
			$request->addResult('count', 1);

		} elsif ($command eq 'addlevel' && defined $title) {

			main::INFOLOG && $log->info("adding new level $title at index $index");

			$entry = {
				'text'    => $title,
				'outline' => [],
			};

			$request->addResult('count', 1);

		} else {

			main::INFOLOG && $log->info("can't perform $command bad title or url");

			$request->setStatusBadParams();
			return;
		}

		if (defined $i) {

			splice @$level, $i, 0, $entry;

		} else { # with no specific index, place automatically at the end

			push @$level, $entry;
		}

		$favs->save;

		# XXX: leave this around in case people are using this to set hotkeys
		if (defined $hotkey ) {
			$log->error('hotkeys (presets) can no longer be set with this command');
		}

		# show feedback to jive
		$client->showBriefly({
			jive => { 
			type => 'mixed',
			style => 'favorite',
			#'icon-id' => $icon ? $icon : '/html/images/cover.png',
			'icon' => $icon || $favs->icon($url),
			text => [ $client->string('FAVORITES_ADDING'),
					$title,
				   ],
			},
		});

		$request->setStatusDone();

	} else {

		main::INFOLOG && $log->info("index $index invalid");

		$request->setStatusBadParams();
	}
}

sub cliDelete {
	my $request = shift;

	if ($request->isNotCommand([['favorites'], ['delete']])) {
		$request->setStatusBadDispatch();
		return;
	}

	my $client = $request->client();
	my $index  = $request->getParam('item_id');
	my $url    = $request->getParam('url');
	my $title  = $request->getParam('title');

	# XXX: refactor to use Slim::Utils::Favorites
	my $favs = Slim::Plugin::Favorites::OpmlFavorites->new($client);

	if (!defined $index || !defined $favs->entry($index)) {
		if ($url) {
			$favs->deleteUrl($url);
		} else {
			$request->setStatusBadParams();
			return;
		}
	}

	$favs->deleteIndex($index);

	# show feedback if this action came from jive cometd session
	if ($request->source && $request->source =~ /\/slim\/request/) {
		my $deleteMsg = $title?$title:$url;
		$client->showBriefly({
			'jive' => { 
			'text' => [ $client->string('FAVORITES_DELETING'),
						$deleteMsg ],
			}
		});
	}

	$request->setStatusDone();
}

sub cliRename {
	my $request = shift;

	if ($request->isNotCommand([['favorites'], ['rename']])) {
		$request->setStatusBadDispatch();
		return;
	}

	my $client = $request->client();
	my $index  = $request->getParam('item_id');
	my $title  = $request->getParam('title');

	my $favs = Slim::Plugin::Favorites::OpmlFavorites->new($client);

	if (!defined $index || !defined $favs->entry($index)) {
		$request->setStatusBadParams();
		return;
	}

	main::INFOLOG && $log->info("rename index $index to $title");

	$favs->entry($index)->{'text'} = $title;
	$favs->save;

	$request->setStatusDone();
}

sub cliMove {
	my $request = shift;

	if ($request->isNotCommand([['favorites'], ['move']])) {
		$request->setStatusBadDispatch();
		return;
	}

	my $client = $request->client();
	my $from = $request->getParam('from_id');
	my $to   = $request->getParam('to_id');

	my $favs = Slim::Plugin::Favorites::OpmlFavorites->new($client);

	my ($fromLevel, $fromIndex) = $favs->level($from, 1);
	my ($toLevel,   $toIndex  ) = $favs->level($to, 1);

	if (!$fromLevel || !$toLevel) {
		$request->setStatusBadParams();
		return;
	}

	main::INFOLOG && $log->info("moving item from index $from to index $to");

	splice @$toLevel, $toIndex, 0, (splice @$fromLevel, $fromIndex, 1);
	
	$favs->save;
	
	$request->setStatusDone();
}

sub trackInfoHandler {
	my $return = _objectInfoHandler( @_, 'track');
	return $return;
}

sub albumInfoHandler {
	my $return = _objectInfoHandler( @_, 'album');
	return $return;
}

sub artistInfoHandler {
	my $return = _objectInfoHandler( @_, 'artist');
	return $return;
}

sub playlistInfoHandler {
	my $return = _objectInfoHandler( @_, 'playlist');
	return $return;
}

sub _objectInfoHandler {
	my ( $client, $url, $obj, $remoteMeta, $tags, $objectType ) = @_;
	$tags ||= {};
	
	my $index = Slim::Utils::Favorites->new($client)->findUrl($url);
	
	my $jive = {
		style => ($client && $client->revision !~ /^7\.[0-7]/) ? 'item_fav' : 'itemNoAction'
	};
	
	my $title;
	if ($objectType && $objectType eq 'artist') {
		$title = $obj->name;
	} else {
		$title = $obj->title;
	}
	if ( !defined $index ) {

		main::DEBUGLOG && $log->debug( "Item is not a favorite [$url]" );

		if ( $tags->{menuMode} ) {
			my $actions = {
				go => {
					player => 0,
					cmd    => [ 'jivefavorites', 'add' ],
					params => {
						title   => $title,
						url     => $obj->url,
						isContextMenu => 1,
					},
				},
			};
			$jive->{actions} = $actions;
			return {
				type        => 'text',
				name        => cstring($client, 'JIVE_SAVE_TO_FAVORITES'),
				jive        => $jive,
			};
		} else {
			return {
				type        => 'link',
				name        => cstring($client, 'PLUGIN_FAVORITES_SAVE'),
				url         => \&objectInfoAddFavorite,
				passthrough => [ $obj ],
				favorites   => 0,
			};
		}
	}
	else {

		main::DEBUGLOG && $log->debug( "Item is a favorite [$url]" );

		if ( $tags->{menuMode} ) {
			my $actions = {
				go => {
					player => 0,
					cmd    => [ 'jivefavorites', 'delete' ],
					params => {
						title   => $title,
						url     => $obj->url,
						item_id => $index,
						isContextMenu => 1,
					},
				},
			};
			$jive->{actions} = $actions;
			return {
				type        => 'text',
				name        => cstring($client, 'JIVE_DELETE_FROM_FAVORITES'),
				jive        => $jive,
			};
	
		} else {
			return {
				type        => 'link',
				name        => cstring($client, 'PLUGIN_FAVORITES_REMOVE'),
				url         => \&objectInfoRemoveFavorite,
				passthrough => [ $obj ],
				favorites   => 0,
			};
		}
	}
	
	return;
}

sub objectInfoAddFavorite {
	my ( $client, $callback, undef, $obj ) = @_;
	
	my $favorites = Slim::Utils::Favorites->new($client);
	
	my $favIndex = $favorites->add(
		$obj,
		$obj->name || $obj->url,
		undef,
		undef,
		undef,
	);
	
	my $menu = {
		type        => 'text',
		name        => cstring($client, 'FAVORITES_ADDING'),
		showBriefly => 1,
		refresh     => 1,
		favorites   => 0,
	};
	
	$callback->( [$menu] );
}

sub objectInfoRemoveFavorite {
	my ( $client, $callback, $params, $obj ) = @_;
	
	my $menu = [
		{
			type => 'link',
			name => cstring($client, 'PLUGIN_FAVORITES_CANCEL'),
			url  => sub {
				my $callback = $_[1];
				
				$callback->( [{
					type        => 'text',
					name        => cstring($client, 'PLUGIN_FAVORITES_CANCELLING'),
					showBriefly => 1,
					popback     => 2,
					favorites   => 0,
				}] );
			},
		},
		{
			type => 'link',
			name => cstring($client, 'FAVORITES_RIGHT_TO_DELETE'),
			url  => sub {
				my $callback = $_[1];
				
				my $favorites = Slim::Utils::Favorites->new($client);
				my $index = Slim::Utils::Favorites->new($client)->findUrl( $obj->url );
				
				$favorites->deleteIndex($index);
				
				my $menu2 = {
					type        => 'text',
					name        => cstring($client, 'FAVORITES_DELETING'),
					showBriefly => 1,
					popback     => 2,
					refresh     => 1,
					favorites   => 0,
				};
				
				$callback->( [$menu2] );
			},
		},
	];
	
	$callback->( $menu );
}

1;
