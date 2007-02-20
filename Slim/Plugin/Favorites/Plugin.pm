package Slim::Plugin::Favorites::Plugin;

# $Id$

# A Favorites implementation which stores favorites as opml files and allows
# the favorites list to be edited from the web interface

# Includes code from the MyPicks plugin by Adrian Smith and Bryan Alton

# This code is derived from code with the following copyright message:
#
# SlimServer Copyright (C) 2005 Sean Adams, Slim Devices Inc.
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

use Slim::Plugin::Favorites::Opml;
use Slim::Plugin::Favorites::OpmlFavorites;
use Slim::Plugin::Favorites::Settings;
use Slim::Plugin::Favorites::Playlist;

my $log = logger('favorites');

sub initPlugin {
	my $class = shift;

	$class->SUPER::initPlugin(@_);

	Slim::Plugin::Favorites::Settings->new;

	# register opml based favorites handler
	Slim::Utils::Favorites::registerFavoritesClassName('Slim::Plugin::Favorites::OpmlFavorites');

	# register handler for playing favorites by remote hot button
	Slim::Buttons::Common::setFunction('playFavorite', \&playFavorite);

	# register cli handlers
	Slim::Control::Request::addDispatch(['favorites', '_index', '_quantity'], [0, 1, 1, \&cliBrowse]);
	Slim::Control::Request::addDispatch(['favorites', 'add', '_url', '_title'], [0, 0, 1, \&cliAdd]);
	Slim::Control::Request::addDispatch(['favorites', 'addlevel', '_title'], [0, 0, 1, \&cliAdd]);
	Slim::Control::Request::addDispatch(['favorites', 'delete', '_index'], [0, 0, 0, \&cliDelete]);
}

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
	my $enabled = Slim::Utils::Prefs::get('plugin_favorites_opmleditor');

	Slim::Web::Pages->addPageLinks('plugins', {	'PLUGIN_FAVORITES_PLAYLIST_EDITOR' => $enabled ? 'plugins/Favorites/index.html?new' : undef });
}

my $opml;    # opml hash for current editing session
my $deleted; # any deleted sub tree which may be added back

sub indexHandler {
	my $client = shift;
	my $params = shift;

	my $edit;     # index of entry to edit if set
	my $errorMsg; # error message to display at top of page
	my $changed;  # opml has been changed

	# Debug:
	#for my $key (keys %$params) {
	#	print "Key: $key, Val: ".$params->{$key}."\n";
	#}

	if ($params->{'fav'}) {

		$log->info("opening favorites edditing session");

		$opml = Slim::Plugin::Favorites::OpmlFavorites->new($client);
		$deleted = undef;
	}

	if ($params->{'new'}) {

		$log->info("new opml editting session");

		$opml = Slim::Plugin::Favorites::Opml->new;
		$deleted = undef;
	}

	# get the level to operate on - this is the level containing the index if action is set, otherwise the level specified by index
	my ($level, $indexLevel, @indexPrefix) = $opml->level($params->{'index'}, defined $params->{'action'});

	if (!defined $level) {
		# favorites editor cannot follow remote links, so pass through to xmlbrowser as index does not appear to be edittable
		$log->info("passing through to xmlbrowser");

		return Slim::Web::XMLBrowser->handleWebIndex( {
			feed   => Slim::Formats::XML::parseOPML( $opml->xmlbrowser ),
			args   => [$client, $params, @_],
		} );
	}

	if ($params->{'loadfile'}) {

		$opml->load($params->{'filename'});

		($level, $indexLevel, @indexPrefix) = $opml->level(undef, undef);
		$deleted = undef;
	}

	if ($params->{'savefile'} || $params->{'savechanged'}) {

		$opml->filename($params->{'filename'}) if $params->{'savefile'};

		$opml->save;

		$changed = undef unless $opml->error;

		my $favorites = Slim::Plugin::Favorites::OpmlFavorites->new($client);

		if ($favorites && $opml != $favorites && $opml->filename eq $favorites->filename) {
			# overwritten the favorites file - force favorites to be reloaded
			$favorites->load;
		}
	}

	if ($params->{'importfile'}) {

		my $filename = $params->{'filename'};
		my $playlist;

		if ($filename =~ /\.opml$/) {

			$playlist = Slim::Plugin::Favorites::Opml->new($filename)->toplevel;

		} else {

			$playlist = Slim::Plugin::Favorites::Playlist->read($filename);
		}

		if ($playlist) {

			for my $entry (@$playlist) {
				push @$level, $entry;
			}

			$changed = 1;

		} else {

			$params->{'errormsg'} = string('PLUGIN_FAVORITES_IMPORTERROR') . " " . $filename;
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

		if ($action =~ /play|add/ && $client) {

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

				if (defined $params->{'entryurl'}) {

					$entry->{'URL'} = $params->{'entryurl'};

					if ($params->{'entryurl'} =~ /\.opml$/) {
						delete $entry->{'type'};
					} else {
						$entry->{'type'} = 'audio';
					}
				}
			}

			$changed = 1;
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
			'type' => 'audio',
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

	# save each change if in favorites mode
	if ($changed && $opml && $opml->isa('Slim::Plugin::Favorites::OpmlFavorites')) {
		$opml->save;
	}

	# set params for page build
	if (defined $opml) {
		$params->{'favorites'} = $opml->isa('Slim::Plugin::Favorites::OpmlFavorites');
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
		push @entries, {
			'title'   => $opmlEntry->{'text'} || '',
			'url'     => $opmlEntry->{'URL'} || $opmlEntry->{'url'} || '',
			'audio'   => (defined $opmlEntry->{'type'} && $opmlEntry->{'type'} eq 'audio'),
			'outline' => $opmlEntry->{'outline'},
			'edit'    => (defined $edit && $edit == $i),
			'index'   => join '.', (@indexPrefix, $i++),
		};
	}

	$params->{'entries'} = \@entries;
	$params->{'levelindex' } = join '.', @indexPrefix;

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

	return Slim::Web::HTTP::filltemplatefile('plugins/Favorites/index.html', $params);
}

sub cliBrowse {
	my $request = shift;

	if ($request->isNotQuery([['favorites']])) {
		$request->setStatusBadDispatch();
		return;
	}

	my $client   = $request->client();
	my $index    = $request->getParam('_index');
	my $quantity = $request->getParam('_quantity');

	if (my $item_id  = $request->getParam('item_id')) {
		$index = $item_id . '.' . $index;
	}

	my ($level, $start, $prefix) = Slim::Plugin::Favorites::OpmlFavorites->new($client)->level($index, 'contains');

	my $count = $level ? scalar @$level : 0;

	$request->addResult('count', $count);

	if (defined $start) {

		$log->info("found start index $index in favorites, returning entries");

		my $ind = $start;
		my $cnt = 0;

		while ($level->[$ind] && $cnt < $quantity) {

			my $entry = $level->[$ind];

			$request->addResultLoop('@favorites', $cnt, 'id',    $prefix . $ind );
			$request->addResultLoop('@favorites', $cnt, 'title', $entry->{'text'});
			$request->addResultLoop('@favorites', $cnt, 'url',   $entry->{'URL'} || $entry->{'url'});

			if ($entry->{'outline'} && ref $entry->{'outline'} eq 'ARRAY') {
				$request->addResultLoop('@favorites', $cnt, 'hasitems',  scalar @{$entry->{'outline'}} );
			}

			++$ind;
			++$cnt;
		}

	} else {

		$log->info("start index $index does not exist in favorites");
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
	my $url    = $request->getParam('_url');
	my $title  = $request->getParam('_title');
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

		} elsif ($command eq 'addlevel' && defined $title) {

			$log->info("adding new level $title at index $index");

			$entry = {
				'text'    => $title,
				'outline' => [],
			};

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
	my $index  = $request->getParam('_index');

	if (!defined $index) {
		$request->setStatusBadParams();
		return;
	}

	Slim::Plugin::Favorites::OpmlFavorites->new($client)->deleteIndex($index);

	$request->setStatusDone();
}


1;
