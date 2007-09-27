package Slim::Plugin::Favorites::Plugin;

# $Id$

# A Favorites implementation which stores favorites as opml files and allows
# the favorites list to be edited from the web interface

# Includes code from the MyPicks plugin by Adrian Smith and Bryan Alton

# This code is derived from code with the following copyright message:
#
# SqueezeCenter Copyright (C) 2005 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use base qw(Slim::Plugin::Base);

use Slim::Buttons::Common;
use Slim::Web::XMLBrowser;
use Slim::Utils::Favorites;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use Slim::Music::Info;
use Slim::Utils::Prefs;

use Slim::Plugin::Favorites::Opml;
use Slim::Plugin::Favorites::OpmlFavorites;
use Slim::Plugin::Favorites::Settings;
use Slim::Plugin::Favorites::Playlist;

my $log = logger('favorites');

my $prefs = preferences('plugin.favorites');

sub initPlugin {
	my $class = shift;

	$class->SUPER::initPlugin(@_);

	Slim::Plugin::Favorites::Settings->new;

	# register opml based favorites handler
	Slim::Utils::Favorites::registerFavoritesClassName('Slim::Plugin::Favorites::OpmlFavorites');

	# register handler for playing favorites by remote hot button
	Slim::Buttons::Common::setFunction('playFavorite', \&playFavorite);

	# register cli handlers
	Slim::Control::Request::addDispatch(['favorites', 'items', '_index', '_quantity'], [0, 1, 1, \&cliBrowse]);
	Slim::Control::Request::addDispatch(['favorites', 'add'], [0, 0, 1, \&cliAdd]);
	Slim::Control::Request::addDispatch(['favorites', 'addlevel'], [0, 0, 1, \&cliAdd]);
	Slim::Control::Request::addDispatch(['favorites', 'delete'], [0, 0, 1, \&cliDelete]);
	Slim::Control::Request::addDispatch(['favorites', 'rename'], [0, 0, 1, \&cliRename]);
	Slim::Control::Request::addDispatch(['favorites', 'move'], [0, 0, 1, \&cliMove]);
	Slim::Control::Request::addDispatch(['favorites', 'playlist', '_method' ],[1, 1, 1, \&cliBrowse]);
	
	# register notifications
	Slim::Control::Request::addDispatch(['favorites', 'changed'], [0, 0, 0, undef]);
}

sub modeName { 'FAVORITES' };

sub setMode {
	my $class = shift;
	my $client = shift;
	my $method = shift;

	if ( $method eq 'pop' ) {
		Slim::Buttons::Common::popMode($client);
		return;
	}

	# use INPUT.Choice to display the list of feeds
	my %params = (
		header   => 'PLUGIN_FAVORITES_LOADING',
		modeName => 'Favorites.Browser',
		url      => Slim::Plugin::Favorites::OpmlFavorites->new($client)->fileurl,
		title    => $client->string('FAVORITES'),
	);

	Slim::Buttons::Common::pushMode($client, 'xmlbrowser', \%params);

	# we'll handle the push in a callback
	$client->modeParam('handledTransition',1)
}

sub playFavorite {
	my $client = shift;
	my $button = shift;
	my $digit  = shift;

	my $entry = Slim::Plugin::Favorites::OpmlFavorites->new($client)->entry($digit);

	if (defined $entry && $entry->{'type'} && $entry->{'type'} eq 'audio') {

		my $url   = $entry->{'URL'} || $entry->{'url'};
		my $title = $entry->{'title'};

		$log->info("Playing favorite number $digit $title $url");

		Slim::Music::Info::setTitle($url, $title);

		$client->execute(['playlist', 'play', $url]);

	} else {

		$log->info("Can't play favorite number $digit - not an audio entry");

		$client->showBriefly({
			 'line' => [ sprintf($client->string('FAVORITES_NOT_DEFINED'), $digit) ],
		});
	}
}

sub webPages {
	my $class = shift;

	Slim::Web::HTTP::addPageFunction('plugins/Favorites/index.html', \&indexHandler);

	Slim::Web::Pages->addPageLinks('browse', { 'FAVORITES' => 'plugins/Favorites/index.html?fav' });

	addEditLink();
}

sub addEditLink {
	my $enabled = $prefs->get('opmleditor');

	Slim::Web::Pages->addPageLinks('plugins', {	'PLUGIN_FAVORITES_PLAYLIST_EDITOR' => $enabled ? 'plugins/Favorites/index.html?new' : undef });
}

my $opml;    # opml hash for current editing session
my $deleted; # any deleted sub tree which may be added back
my $autosave;# save each change

sub indexHandler {
	my $client = shift;
	my $params = shift;

	my $edit;     # index of entry to edit if set
	my $changed;  # opml has been changed

	# Debug:
	#for my $key (keys %$params) {
	#	print "Key: $key, Val: ".$params->{$key}."\n";
	#}

	if ($params->{'fav'}) {

		$log->info("opening favorites edditing session");

		$opml = Slim::Plugin::Favorites::OpmlFavorites->new($client);
		$deleted  = undef;
		$autosave = 1;
	}

	if (my $url = $params->{'new'}) {

		if (Slim::Music::Info::isURL($url)) {

			$log->info("opening $url in opml edittor");

			$opml = Slim::Plugin::Favorites::Opml->new({ 'url' => $url });

		} else {

			$log->info("new opml editting session");

			$opml = Slim::Plugin::Favorites::Opml->new();
		}

		$autosave = $params->{'autosave'};
		$deleted = undef;
	}

	# get the level to operate on - this is the level containing the index if action is set, otherwise the level specified by index
	my ($level, $indexLevel, @indexPrefix) = $opml->level($params->{'index'}, defined $params->{'action'});

	if (!defined $level) {
		# favorites editor cannot follow remote links, so pass through to xmlbrowser as index does not appear to be edittable
		$log->info("passing through to xmlbrowser");

		return Slim::Web::XMLBrowser->handleWebIndex( {
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

		if ($action =~ /^play$|^add$/ && $client) {

			my $entry = $opml->entry($params->{'index'});
			my $stream = $entry->{'URL'} || $entry->{'url'};
			my $title  = $entry->{'text'};

			Slim::Music::Info::setTitle($stream, $title);
			$client->execute(['playlist', $action, $stream]);
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

					if ($entry->{'type'} eq 'check') {

						if ($url !~ /^http:/) {

							if ($url !~ /\.(xml|opml|rss)$/) {

								$entry->{'type'} = 'audio';

							} else {

								delete $entry->{'type'};
							}

						} elsif (!$params->{'fetched'}) {

							$log->info("checking content type for $url");

							Slim::Networking::Async::HTTP->new()->send_request( {
								'request'     => HTTP::Request->new( GET => $url ),
								'onHeaders'   => \&asyncCBContentType,
								'onError'     => \&asyncCBContentTypeError,
								'passthrough' => [ $client, $params, @_ ],
							} );

							return;

						} elsif (my $type = $params->{'fetchedtype'}) {

							if (Slim::Music::Info::isSong(undef, $type) || Slim::Music::Info::isPlaylist(undef, $type)) {

								$log->info("  got content type $type - treating as audio");
																
								$entry->{'type'} = 'audio';

							} else {

								$log->info("  got content type $type - treating as non audio");
															
								delete $entry->{'type'};
							}
								
						} else {

							$log->info("  error fetching content type - treating as non audio");
													
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
			'type' => 'check',
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

	# save each change if autosave set
	if ($changed && $opml && $autosave) {
		$opml->save;
	}

	# set params for page build
	if (defined $opml) {
		$params->{'autosave'}  = $autosave;
		$params->{'favorites'} = !$favs;
		$params->{'title'}     = $opml->title;
		$params->{'filename'}  = $opml->filename;
	}

	$params->{'deleted'}  = defined $deleted ? $deleted->{'text'} : undef;
	$params->{'editmode'} = defined $edit;

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
			'audio'   => (defined $opmlEntry->{'type'} && $opmlEntry->{'type'} eq 'audio'),
			'outline' => $opmlEntry->{'outline'},
			'edit'    => (defined $edit && $edit == $i),
			'index'   => join '.', (@indexPrefix, $i++),
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
		'href'  => 'href="index.html?index="',
	};

	# add remaining levels up to current level to pwd_list
	for (my $i = 0; $i <= $#indexPrefix; ++$i) {

		my @ind = @indexPrefix[0..$i];
		push @{$params->{'pwd_list'}}, {
			'title' => $opml->entry(\@ind)->{'text'},
			'href'  => 'href="index.html?index=' . (join '.', @ind) . '"',
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
	$params->{'fetchedtype'} = Slim::Music::Info::mimeToType( $http->response->content_type ) || $http->response->content_type;

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

	my $favs = Slim::Plugin::Favorites::OpmlFavorites->new($client);

	Slim::Buttons::XMLBrowser::cliQuery('favorites', $favs->xmlbrowser, $request);
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
	my $index  = $request->getParam('item_id');

	my $favs = Slim::Plugin::Favorites::OpmlFavorites->new($client);

	my ($level, $i) = $favs->level($index, 'contains');

	if ($level) {

		my $entry;

		if ($command eq 'add' && defined $title && defined $url) {

			$log->info("adding entry $title $url at index $index");

			$entry = {
				'text' => $title,
				'URL'  => $url,
				'type' => 'audio',
			};
			
			$request->addResult('count', 1);

		} elsif ($command eq 'addlevel' && defined $title) {

			$log->info("adding new level $title at index $index");

			$entry = {
				'text'    => $title,
				'outline' => [],
			};

			$request->addResult('count', 1);

		} else {

			$log->info("can't perform $command bad title or url");

			$request->setStatusBadParams();
			return;
		}

		splice @$level, $i, 0, $entry;

		$favs->save;

		$request->setStatusDone();

	} else {

		$log->info("index $index invalid");

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

	my $favs = Slim::Plugin::Favorites::OpmlFavorites->new($client);

	if (!defined $index || !defined $favs->entry($index)) {
		$request->setStatusBadParams();
		return;
	}

	$favs->deleteIndex($index);

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

	$log->info("rename index $index to $title");

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

	$log->info("moving item from index $from to index $to");

	splice @$toLevel, $toIndex, 0, (splice @$fromLevel, $fromIndex, 1);
	
	$favs->save;
	
	$request->setStatusDone();
}


1;
