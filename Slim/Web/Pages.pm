package Slim::Web::Pages;

# $Id$

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;

use Date::Parse qw(str2time);
use File::Spec::Functions qw(:ALL);
use POSIX ();

use Slim::Music::LiveSearch;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);

our %additionalLinks = ();

our %fieldInfo = ();

our %hierarchy = (
	'artist' => 'album,track',
	'album'  => 'track',
	'song '  => '',
);

sub init {

	%fieldInfo = (
		'track' => {

			'title' => 'BROWSE_BY_SONG',
			'allTitle' => 'ALL_SONGS',
			'idToName' => sub {
				my $ds  = shift;
				my $id  = shift;
				my $obj = $ds->objectForId('track', $id) || return '';

				return $obj->title();
			},

			'resultToId' => sub {
				my $obj = shift;
				return $obj->id;
			},

			'resultToName' => sub {
				my $obj = shift;
				return $obj->title;
			},

			'resultToSortedName' => sub {
				my $obj = shift;
				return $obj->titlesort;
			},

			'find' => sub {
				my $ds = shift;
				my $level = shift;
				my $findCriteria = shift;
				return $ds->find('track', $findCriteria, exists $findCriteria->{'album'} ? 'tracknum' : 'title');
			},

			'listItem' => sub {
				my $ds   = shift;
				my $form = shift;
				my $item = shift;

				my $webFormat = Slim::Utils::Prefs::getInd("titleFormat",Slim::Utils::Prefs::get("titleFormatWeb"));

				$form->{'text'} = Slim::Music::Info::standardTitle(undef, $item);

				if (my ($contributor) = $item->contributors()) {
					$form->{'artist'}   = $contributor->name();
					$form->{'artistid'} = $contributor->id();
				}

				if (my $album = $item->album()) {
					$form->{'album'}   = $album->title();
					$form->{'albumid'} = $album->id();
				}

				$form->{'includeArtist'}       = ($webFormat !~ /ARTIST/);
				$form->{'includeAlbum'}        = ($webFormat !~ /ALBUM/) ;
				$form->{'item'}	               = $item->id;
				$form->{'itempath'}	       = $item->url;

				if ($item->moodlogic_mixable()) {
					# set up a moodlogic link
					addLinks("mixer", {'MOODLOGIC' => "plugins/MoodLogic/mixerlink.html"},1);
					$form->{'mixable_not_descend'} = 1;
				} else {
					addLinks("mixer", {'MOODLOGIC' => undef});
				}
				if ($item->musicmagic_mixable() && Plugins::MusicMagic::Plugin::canUseMusicMagic()) {
					#set up a musicmagic link
					addLinks("mixer", {'MUSICMAGIC' => "plugins/MusicMagic/mixerlink.html"},1);
					$form->{'mmmixable_not_descend'} = 1;
				} else {
					addLinks("mixer", {'MUSICMAGIC' => undef});
				}
				$form->{'mixerlinks'} = $additionalLinks{'mixer'};

				if ($item->coverArt()) {
					$form->{'coverart'} = 1;
					$form->{'coverartpath'} = $item->url();
				}
			},

			'ignoreArticles' => 1,
		},

		'genre' => {
			'title' => 'BROWSE_BY_GENRE',
			'allTitle' => 'ALL_GENRES',

			'idToName' => sub {
				my $ds  = shift;
				my $id  = shift;
				my $obj = $ds->objectForId('genre', $id) || return '';

				return $obj->name();
			},

			'resultToId' => sub {
				my $obj = shift;
				return $obj->id;
			},

			'resultToName' => sub {
				my $obj = shift;
				return $obj->name;
			},

			'resultToSortedName' => sub {
				my $obj = shift;
				return $obj->namesort;
			},

			'find' => sub {
				my $ds = shift;
				my $level = shift;
				my $findCriteria = shift;

				return $ds->find('genre', $findCriteria, 'genre');
			},

			'listItem' => sub {
				my $ds = shift;
				my $form = shift;
				my $item = shift;
				my $itemname = shift;
				my $descend = shift;

				if ($item->moodlogic_mixable() && ($descend eq "true")) {
					# set up a moodlogic link
					addLinks("mixer", {'MOODLOGIC' => "plugins/MoodLogic/mixerlink.html"},1);
					$form->{'mixable_descend'} = 1;
				} else {
					addLinks("mixer", {'MOODLOGIC' => undef});
				}
				if ($item->musicmagic_mixable() && Plugins::MusicMagic::Plugin::canUseMusicMagic() && ($descend eq "true")) {
					#set up a musicmagic link
					addLinks("mixer", {'MUSICMAGIC' => "plugins/MusicMagic/mixerlink.html"},1);
					$form->{'mmmixable_descend'} = 1;
				} else {
					addLinks("mixer", {'MUSICMAGIC' => undef});
				}
				$form->{'mixerlinks'} = $additionalLinks{'mixer'};
			},

			'ignoreArticles' => 0,
			'alphaPageBar' => 1
		},

		'album' => {
			'title' => 'BROWSE_BY_ALBUM',
			'allTitle' => 'ALL_ALBUMS',

			'idToName' => sub {
				my $ds  = shift;
				my $id  = shift;
				my $obj = $ds->objectForId('album', $id) || return '';

				return $obj->title();
			},

			'resultToId' => sub {
				my $obj = shift;
				return $obj->id;
			},

			'resultToName' => sub {
				my $obj = shift;
				return $obj->title;
			},

			'resultToSortedName' => sub {
				my $obj = shift;
				return $obj->titlesort;
			},

			'find' => sub {
				my $ds = shift;
				my $level = shift;
				my $findCriteria = shift;

				return $ds->find('album', $findCriteria, 'album');
			},

			'listItem' => sub {
				my $ds = shift;
				my $form = shift;
				my $item = shift;
				my $itemname = shift;
				my $descend = shift;

				if (my $showYear = Slim::Utils::Prefs::get('showYear')) {

					$form->{'showYear'} = $showYear;

					if (my ($track) = $item->tracks()) {
						$form->{'year'} = $track->year();
					}
				}
				
				if ($item->musicmagic_mixable() && Plugins::MusicMagic::Plugin::canUseMusicMagic() && ($descend eq "true")) {
					#set up a musicmagic link
					addLinks("mixer", {'MUSICMAGIC' => "plugins/MusicMagic/mixerlink.html"},1);
					$form->{'mmmixable_descend'} = 1;
				} else {
					addLinks("mixer", {'MUSICMAGIC' => undef});
				}
				$form->{'mixerlinks'} = $additionalLinks{'mixer'};
			},

			'ignoreArticles' => 1,
			'alphaPageBar' => 1
		},

		'artwork' => {
			'title' => 'BROWSE_BY_ARTWORK',

			'idToName' => sub {
				my $ds  = shift;
				my $id  = shift;
				my $obj = $ds->objectForId('album', $id) || return '';

				return $obj->title();
			},

			'resultToId' => sub {
				my $obj = shift;
				return $obj->id;
			},

			'resultToName' => sub {
				my $obj = shift;
				return $obj->title;
			},

			'resultToSortedName' => sub {
				my $obj = shift;
				return $obj->titlesort;
			},

			'find' => sub {
				my $ds = shift;
				my $level = shift;
				my $findCriteria = shift;

				if (Slim::Utils::Prefs::get('includeNoArt')) {
					return $ds->find('album', $findCriteria, 'album');
				}
				
				return $ds->albumsWithArtwork()
			},

			'listItem' => sub {
				my $ds   = shift;
				my $form = shift;
				my $item = shift;
				my $itemname = shift;

				if ($item->artwork_path()) {
					$form->{'coverthumb'} = 1;
					$form->{'thumbartpath'} = $item->artwork_path;
				} else {
					$form->{'coverthumb'}   = 0;
				}

				# add the year to artwork browsing if requested.
				if (Slim::Utils::Prefs::get('showYear')) {

					if (my ($track) = $item->tracks()) {
						$form->{'year'} = $track->year();
					}
				}

				$form->{'item'}    = $itemname;
				$form->{'artwork'} = 1;
				$form->{'size'}	   = Slim::Utils::Prefs::get('thumbSize');
			},

			'nameTransform' => 'album',
			'ignoreArticles' => 1,
			'alphaPageBar' => 0,
			'suppressAll' => 1
		},

		'artist' => {
			'title' => 'BROWSE_BY_ARTIST',
			'allTitle' => 'ALL_ARTISTS',

			'idToName' => sub {
				my $ds = shift;
				my $id = shift;
				my $obj = $ds->objectForId('contributor', $id) || return '';

				return $obj->name();
			},

			'resultToId' => sub {
				my $obj = shift;
				return $obj->id;
			},

			'resultToName' => sub {
				my $obj = shift;
				return $obj->name;
			},

			'resultToSortedName' => sub {
				my $obj = shift;
				return $obj->namesort;
			},

			'find' => sub {
				my $ds = shift;
				my $level = shift;
				my $findCriteria = shift;

				return $ds->find('artist', $findCriteria, 'artist');
			},

			'listItem' => sub {
				my $ds   = shift;
				my $form = shift;
				my $item = shift;
				my $itemname = shift;
				my $descend = shift;

				if ($item->moodlogic_mixable() && ($descend eq "true")) {
					# set up a moodlogic link
					addLinks("mixer", {'MOODLOGIC' => "plugins/MoodLogic/mixerlink.html"},1);
					$form->{'mixable_descend'} = 1;
				} else {
					addLinks("mixer", {'MOODLOGIC' => undef});
				}
				if ($item->musicmagic_mixable() && Plugins::MusicMagic::Plugin::canUseMusicMagic() && ($descend eq "true")) {
					#set up a musicmagic link
					addLinks("mixer", {'MUSICMAGIC' => "plugins/MusicMagic/mixerlink.html"},1);
					$form->{'mmmixable_descend'} = 1;
				} else {
					addLinks("mixer", {'MUSICMAGIC' => undef});
				}
				$form->{'mixerlinks'} = $additionalLinks{'mixer'};
			},

			'ignoreArticles' => 1,
			'alphaPageBar' => 1
		},

		'year' => {
			'title' => 'BROWSE_BY_YEAR',
			'allTitle' => 'ALL_YEARS',

			'idToName' => sub {
				my $ds  = shift;
				my $id  = shift;
				return $id;
			},

			'resultToId' => sub {
				my $obj = shift;
				return $obj;
			},

			'resultToName' => sub {
				my $obj = shift;
				return $obj;
			},

			'resultToSortedName' => sub {
				my $obj = shift;
				return $obj;
			},

			'find' => sub {
				my $ds = shift;
				my $level = shift;
				my $findCriteria = shift;

				return $ds->find($level, $findCriteria, $level);
			},

			'listItem' => sub {
				my $ds = shift;
				my $list_form = shift;
				my $item = shift;
				my $itemname = shift;
				my $descend = shift;

				$list_form->{'showYear'} = 0;
			},

			'ignoreArticles' => 1,
			'alphaPageBar' => 0
		},

		'default' => {
			'title' => 'BROWSE',
			'allTitle' => 'ALL',
			'idToName' => sub { my $ds = shift; return shift },
			'resultToId' => sub { return shift },
			'resultToName' => sub { return shift },
			'resultToSortedName' => sub { return shift },

			'find' => sub { 
				my $ds = shift;
				my $level = shift;
				my $findCriteria = shift;
				return $ds->find($level, $findCriteria, $level);
			},

			'listItem' => sub { },
			'ignoreArticles' => 0
		}
	);
}

sub home {
	my ($client, $params) = @_;

	my %listform = %$params;

	if (defined $params->{'forget'}) {
		Slim::Player::Client::forgetClient($params->{'forget'});
	}

	$params->{'nosetup'} = 1   if $::nosetup;
	$params->{'newVersion'} = $::newVersion if $::newVersion;

	if (!exists $additionalLinks{"browse"}) {
		# Uncomment these lines and comment the ones following to enable
		# the new web interface scheme using browsedb. Look a few lines
		# below for cover art related browsing.
		addLinks("browse",{'BROWSE_BY_ARTIST' => "browsedb.html?hierarchy=artist,album,track&level=0"});
		addLinks("browse",{'BROWSE_BY_GENRE'  => "browsedb.html?hierarchy=genre,artist,album,track&level=0"});
		addLinks("browse",{'BROWSE_BY_ALBUM'  => "browsedb.html?hierarchy=album,track&level=0"});
		addLinks("browse",{'BROWSE_BY_YEAR'   => "browsedb.html?hierarchy=year,album,track&level=0"});
		#addLinks("browse",{'BROWSE_BY_ARTIST' => "browseid3.html?genre=*"});
		#addLinks("browse",{'BROWSE_BY_GENRE'  => "browseid3.html"});
		#addLinks("browse",{'BROWSE_BY_ALBUM'  => "browseid3.html?genre=*&artist=*"});
	}

	if (!exists $additionalLinks{"search"}) {
		addLinks("search", {'SEARCH' => "livesearch.html"});
		addLinks("search", {'ADVANCEDSEARCH' => "advanced_search.html"});
		#addLinks("search",{'SEARCHFOR_ARTIST' => "search.html?type=artist"});
		#addLinks("search",{'SEARCHFOR_ALBUM' => "search.html?type=album"});
		#addLinks("search",{'SEARCHFOR_SONGTITLE' => "search.html?type=song"});
	}

	if (!exists $additionalLinks{"help"}) {
		addLinks("help",{'GETTING_STARTED' => "html/docs/quickstart.html"});
		addLinks("help",{'PLAYER_SETUP' => "html/docs/ipconfig.html"});
		addLinks("help",{'USING_REMOTE' => "html/docs/interface.html"});
		addLinks("help",{'HELP_REMOTE' => "html/help_remote.html"});
		addLinks("help",{'HELP_RADIO' => "html/docs/radio.html"});
		addLinks("help",{'REMOTE_STREAMING' => "html/docs/remotestreaming.html"});
		addLinks("help",{'FAQ' => "html/docs/faq.html"});
		addLinks("help",{'SOFTSQUEEZE' => "html/softsqueeze/index.html"});
		addLinks("help",{'TECHNICAL_INFORMATION' => "html/docs/index.html"});
	}

	if (Slim::Utils::Prefs::get('lookForArtwork')) {
		# Uncomment the next lines and comment the one following to enable
		# the new web interface scheme using browsedb.
		addLinks("browse",{'BROWSE_BY_ARTWORK' => "browsedb.html?hierarchy=artwork,track&level=0"});
		#addLinks("browse",{'BROWSE_BY_ARTWORK' => "browseid3.html?genre=*&artist=*&artwork=1"});
	} else {
		addLinks("browse",{'BROWSE_BY_ARTWORK' => undef});
		$params->{'noartwork'} = 1;
	}
	
	if (Slim::Utils::Prefs::get('audiodir')) {
		addLinks("browse",{'BROWSE_MUSIC_FOLDER' => "browse.html?dir="});
	} else {
		addLinks("browse",{'BROWSE_MUSIC_FOLDER' => undef});
		$params->{'nofolder'}=1;
	}
	
	if (Slim::Utils::Prefs::get('playlistdir') || Slim::Music::Import::countImporters()) {
		addLinks("browse",{'SAVED_PLAYLISTS' => "browse.html?dir=__playlists"});
	} else {
		addLinks("browse",{'SAVED_PLAYLISTS' => undef});
	}
	
	# fill out the client setup choices
	for my $player (sort { $a->name() cmp $b->name() } Slim::Player::Client::clients()) {

		# every player gets a page.
		# next if (!$player->isPlayer());
		$listform{'playername'}   = $player->name();
		$listform{'playerid'}     = $player->id();
		$listform{'player'}       = $params->{'player'};
		$listform{'skinOverride'} = $params->{'skinOverride'};
		$params->{'player_list'} .= ${Slim::Web::HTTP::filltemplatefile("homeplayer_list.html", \%listform)};
	}

	Slim::Buttons::Plugins::addSetupGroups();
	$params->{'additionalLinks'} = \%additionalLinks;

	_addPlayerList($client, $params);
	
	addLibraryStats($params);

	my $template = $params->{"path"}  =~ /home\.(htm|xml)/ ? 'home.html' : 'index.html';
	
	return Slim::Web::HTTP::filltemplatefile($template, $params);
}

sub addLinks {
	my ($category, $links,$noquery) = @_;

	return if (ref($links) ne 'HASH');

	while (my ($title, $path) = each %$links) {
		if (defined($path)) {
			$additionalLinks{$category}->{$title} = $path . 
				($noquery ? '' : (($path =~ /\?/) ? '&' : '?'));
		} else {
			delete($additionalLinks{$category}->{$title});
		}
	}
}

# Check to make sure the ref is valid, and not a wildcard.
sub _refCheck {
	my $ref = shift;

	return defined $ref && scalar @$ref && $ref->[0] && $ref->[0] ne '*' ? 1 : 0;
}

sub _lcPlural {
	my ($count, $singular, $plural) = @_;

	return sprintf("%s %s", $count, lc(($count == 1 ? string($singular) : string($plural))));
}

sub addLibraryStats {
	my ($params, $genre, $artist, $album) = @_;
	
	return if Slim::Utils::Misc::stillScanning();

	my $ds    = Slim::Music::Info::getCurrentDataStore();
	my $find  = {};

	$find->{'genre'}       = $genre  if _refCheck($genre);
	$find->{'contributor'} = $artist if _refCheck($artist);
	$find->{'album'}       = $album  if _refCheck($album);

	$params->{'song_count'}   = _lcPlural($ds->count('track', $find), 'SONG', 'SONGS');
	$params->{'artist_count'} = _lcPlural($ds->count('contributor', $find), 'ARTIST', 'ARTISTS');
	$params->{'album_count'}  = _lcPlural($ds->count('album', $find), 'ALBUM', 'ALBUMS');
	$params->{'genre_count'}  = _lcPlural($ds->count('genre', $find), 'GENRE', 'GENRES');
}

sub browser {
	my ($client, $params, $callback, $httpClient, $response) = @_;

	my $dir = defined($params->{'dir'}) ? $params->{'dir'} : "";

	my ($item, $itempath, $playlist, $current_player);
	my  $items = [];

	my $fulldir = Slim::Utils::Misc::virtualToAbsolute($dir);

	$::d_http && msg("browse virtual path: " . $dir . "\n");
	$::d_http && msg("with absolute path: " . $fulldir . "\n");

	if (defined($client)) {
		$current_player = $client->id();
	}

	if ($dir =~ /^__playlists/) {

		$playlist = 1;
		$params->{'playlist'} = 1;

		if (!Slim::Utils::Prefs::get("playlistdir") && !Slim::Music::Import::countImporters()) {
			$::d_http && msg("no valid playlists directory!!\n");
			return Slim::Web::HTTP::filltemplatefile("badpath.html", $params);
		}

		if ($dir =~ /__current.m3u$/) {

			# write out the current playlist to a file with the special name __current
			if (defined($client)) {
				my $count = Slim::Player::Playlist::count($client);
				$::d_http && msg("Saving playlist of $count items to $fulldir\n");
				Slim::Control::Command::execute($client, ['playlist', 'save', '__current']) if $count;

			} else {
				$::d_http && msg("no client, so we can't save a file!!\n");
				return Slim::Web::HTTP::filltemplatefile("badpath.html", $params);
			}
		}

	} else {

		if (!Slim::Utils::Prefs::get("audiodir")) {
			$::d_http && msg("no audiodir, so we can't save a file!!\n");
			return Slim::Web::HTTP::filltemplatefile("badpath.html", $params);
		}
	}

	if (!$fulldir || !Slim::Music::Info::isList($fulldir)) {

		# check if we're just showing external playlists
		if (Slim::Music::Import::countImporters()) {
			browser_addtolist_done($current_player, $callback, $httpClient, $params, [], $response);
			return undef;
		} else {
			$::d_http && msg("the selected playlist $fulldir isn't good!!.\n");
			return Slim::Web::HTTP::filltemplatefile("badpath.html", $params);
		}
	}

	my $suffix = Slim::Formats::Parse::getPlaylistSuffix($fulldir);

	# if they are renaming the playlist, let 'em.
	if ($playlist && $params->{'newname'}) {

		my $newname = $params->{'newname'};

		# don't allow periods, colons, control characters, slashes, backslashes, just to be safe.
		$newname =~ tr|.:\x00-\x1f\/\\| |s;

		if (defined($suffix)) {
			$newname .= $suffix;
		};
		
		if ($newname) {

			my @newpath = splitdir(Slim::Utils::Misc::pathFromFileURL($fulldir));
			pop @newpath;

			my $container = Slim::Utils::Misc::fileURLFromPath(catdir(@newpath));

			push @newpath, $newname;

			my $newfullname = Slim::Utils::Misc::fileURLFromPath(catdir(@newpath));

			$::d_http && msg("renaming $fulldir to $newfullname\n");

			if ($newfullname ne $fulldir && (!-e Slim::Utils::Misc::pathFromFileURL($newfullname) || defined $params->{'overwrite'}) && rename(Slim::Utils::Misc::pathFromFileURL($fulldir), Slim::Utils::Misc::pathFromFileURL($newfullname))) {

				Slim::Music::Info::clearCache($container);
				Slim::Music::Info::clearCache($fulldir);

				$fulldir = $newfullname;

				$dir = Slim::Utils::Misc::descendVirtual(Slim::Utils::Misc::ascendVirtual($dir), $newname);

				$params->{'dir'} = $dir;
				$::d_http && msg("new dir value: $dir\n");

			} else {

				$::d_http && msg("Rename failed!\n");
				$params->{'RENAME_WARNING'} = 1;
			}
		}

	} elsif ($playlist && $params->{'delete'} ) {

		my $path = Slim::Utils::Misc::pathFromFileURL($fulldir);
		
		if ($path && -f $path && unlink $path) {

			$::d_http && msg("deleted playlist: $path\n");

			my @newpath  = splitdir(Slim::Utils::Misc::pathFromFileURL($fulldir));
			pop @newpath;
	
			my $container = Slim::Utils::Misc::fileURLFromPath(catdir(@newpath));
	
			Slim::Music::Info::clearCache($container);
			Slim::Music::Info::clearCache($fulldir);
	
			$dir = Slim::Utils::Misc::ascendVirtual($dir);
			$params->{'dir'} = $dir;
			$fulldir = Slim::Utils::Misc::virtualToAbsolute($dir);
			$suffix = Slim::Formats::Parse::getPlaylistSuffix($fulldir);

		} else {

			$::d_http && msg("couldn't delete playlist: $path\n");
		}
	}

	#
	# Make separate links for each component of the pwd
	#
	my %list_form = %$params;
	
	$list_form{'player'}        = $current_player;
	$list_form{'myClientState'} = $client;
	$list_form{'skinOverride'}  = $params->{'skinOverride'};
	$params->{'pwd_list'} = " ";

	my $lastpath;
	my $aggregate = $playlist ? "__playlists" : "";

	for my $c (splitdir($dir)) {

		if ($c ne "" && $c ne "__playlists" && $c ne "__current.m3u") {

			# incrementally build the path for each link
			$aggregate = (defined($aggregate) && $aggregate ne '') ? catdir($aggregate, $c) : $c;

			$list_form{'dir'} = Slim::Web::HTTP::escape($aggregate);
			
			$list_form{'shortdir'} = Slim::Music::Info::standardTitle(undef, Slim::Utils::Misc::virtualToAbsolute($c));

			$params->{'pwd_list'} .= ${Slim::Web::HTTP::filltemplatefile("browse_pwdlist.html", \%list_form)};
		}

		$lastpath = $c if $c;
	}

	if (defined($suffix)) {

		$::d_http && msg("lastpath equals $lastpath\n");

		if ($lastpath eq "__current.m3u") {
			$params->{'playlistname'}   = string("UNTITLED");
			$params->{'savebuttonname'} = string("SAVE");
		} else {

			$lastpath =~ s/(.*)\.(.*)$/$1/;
			$params->{'playlistname'}   = $lastpath;
			$params->{'savebuttonname'} = string("RENAME");
			$params->{'titled'} = 1;
		}
	}

	# Scan the directories - don't recurse
	Slim::Utils::Scan::addToList(
		$items, $fulldir, 0, undef,  
		\&browser_addtolist_done, $current_player, $callback, 
		$httpClient, $params, $items, $response
	);

	# when this finishes, it calls the next function, browser_addtolist_done:
	#
	# return undef means we'll take care of sending the output to the
	# client (special case because we're going into the background)
	return undef;
}

sub browser_addtolist_done {
	my ($current_player, $callback, $httpClient, $params, $itemsref, $response) = @_;

	if (defined $params->{'dir'} && $params->{'dir'} eq '__playlists' && (Slim::Music::Import::countImporters())) {

		$::d_http && msg("just showing imported playlists\n");

		push @$itemsref, @{Slim::Music::Info::playlists()};

		if (Slim::Music::Import::stillScanning()) {
			$params->{'warn'} = 1;
		}
	}
	
	my $numitems = scalar @{$itemsref};
	my $ds = Slim::Music::Info::getCurrentDataStore();
	
	$::d_http && msg("browser_addtolist_done with $numitems items (". scalar @{ $itemsref } . " " . $params->{'dir'} . ")\n");

	$params->{'browse_list'} = " ";

	if ($numitems) {

		my ($start, $end, $cover, $thumb, $lastAnchor) = '';

		my $otherparams = '&';
		
		$otherparams .= 'dir=' . Slim::Web::HTTP::escape($params->{'dir'}) . '&' if ($params->{'dir'});
		$otherparams .= 'player=' . Slim::Web::HTTP::escape($current_player) . '&' if ($current_player);

		if (defined $params->{'nopagebar'}) {

			($start, $end) = simpleHeader(
				$numitems,
				 \$params->{'start'},
				\$params->{'browselist_header'},
				$params->{'skinOverride'},
				$params->{'itemsPerPage'},
				0,
			);

		} else {

			($start, $end) = pageBar(
				$numitems,
				$params->{'path'},
				0,
				$otherparams,
				\$params->{'start'},
				\$params->{'browselist_header'},
				\$params->{'browselist_pagebar'},
				$params->{'skinOverride'},
				$params->{'itemsPerPage'},
			);
		}

		my $itemnumber = $start;
		my $offset     = $start % 2 ? 0 : 1;
		my $filesort   = Slim::Utils::Prefs::get('filesort');

		# don't look up cover art info if we're browsing a playlist.
		if ($params->{'dir'} && $params->{'dir'} =~ /^__playlists/) {

			$thumb = 1;
			$cover = 1;

		} else {

			if (scalar(@{$itemsref}) > 1) {

				my %list_form = %$params;

				$list_form{'title'}        = string('ALL_SUBFOLDERS');
				$list_form{'nobrowse'}     = 1;
				$list_form{'itempath'}     = Slim::Utils::Misc::virtualToAbsolute($params->{'dir'});
				$list_form{'player'}       = $current_player;
				$list_form{'descend'}      = 1;
				$list_form{'odd'}	   = 0;
				$list_form{'skinOverride'} = $params->{'skinOverride'};

				$itemnumber++;
				$params->{'browse_list'} .= ${Slim::Web::HTTP::filltemplatefile("browse_list.html", \%list_form)};
			}
		}
		
		for my $item (@{$itemsref}[$start..$end]) {
			
			# make sure the players get some time...
			::idleStreams();
			
			# don't display and old unsaved playlist
			next if $item =~ /__current.m3u$/;

			my %list_form = %$params;
			
			# There are different templates for directories and playlist items:
			my $shortitem = Slim::Utils::Misc::descendVirtual($params->{'dir'}, $item, $itemnumber);

			my $obj       = $ds->objectForUrl($item, 0);

			if (Slim::Music::Info::isList($obj)) {

				$list_form{'descend'} = $shortitem;

			} elsif (Slim::Music::Info::isSong($obj)) {

				$list_form{'descend'} = 0;

				if (!defined $cover) {

					if ($obj->coverArt()) {
						$params->{'coverart'} = 1;
						$params->{'coverartpath'} = $shortitem;
					}

					$cover = $item;
				}

				if (!defined $thumb) {

					if ($obj->coverArt('thumb')) {
						$params->{'coverthumb'} = 1;
						$params->{'thumbpath'} = $shortitem;
					}

					$thumb = $item;
				}
			}

			if ($filesort) {

				$list_form{'title'}  = Slim::Music::Info::fileName($item);

			} else {

				my $webFormat = Slim::Utils::Prefs::getInd("titleFormat",Slim::Utils::Prefs::get("titleFormatWeb"));

				$list_form{'includeArtist'} = ($webFormat !~ /ARTIST/);
				$list_form{'includeAlbum'}  = ($webFormat !~ /ALBUM/) ;
				$list_form{'title'}         = Slim::Music::Info::standardTitle(undef, $item);
			}
			
			$list_form{'item'}		  = $obj;
			$list_form{'itempath'}            = Slim::Utils::Misc::virtualToAbsolute($item);
			$list_form{'odd'}	  	  = ($itemnumber + $offset) % 2;
			$list_form{'player'}	          = $current_player;
			$list_form{'mixable_not_descend'} = $obj->moodlogic_mixable() if ($obj && $obj->can('moodlogic_mixable'));

			my $anchor = anchor(Slim::Utils::Text::getSortName($list_form{'title'}),1);

			if ($lastAnchor && $lastAnchor ne $anchor) {
				$list_form{'anchor'} = $lastAnchor = $anchor;
			}

			$list_form{'skinOverride'} = $params->{'skinOverride'};

			$params->{'browse_list'} .= ${Slim::Web::HTTP::filltemplatefile(
				($params->{'playlist'} ? "browse_playlist_list.html" : "browse_list.html"), \%list_form
			)};

			$itemnumber++;
		}

	} else {

		$params->{'browse_list'} = ${Slim::Web::HTTP::filltemplatefile(
			"browse_list_empty.html", {'skinOverride' => $params->{'skinOverride'}}
		)};
	}

	my $output = Slim::Web::HTTP::filltemplatefile(($params->{'playlist'} ? "browse_playlist.html" : "browse.html"), $params);

	$callback->($current_player, $params, $output, $httpClient, $response);
}

# Send the status page (what we're currently playing, contents of the playlist)
sub status_header {
	my ($client, $params, $callback, $httpClient, $response) = @_;

	$params->{'omit_playlist'} = 1;

	return status(@_);
}

sub status {
	my ($client, $params, $callback, $httpClient, $response) = @_;

	_addPlayerList($client, $params);

	$params->{'refresh'} = Slim::Utils::Prefs::get('refreshRate');
	
	if (!defined($client)) {

		# fixed faster rate for noclients
		$params->{'refresh'} = 10;
		return Slim::Web::HTTP::filltemplatefile("status_noclients.html", $params);

	} elsif ($client->needsUpgrade()) {

		$params->{'player_needs_upgrade'} = 1;
		$params->{'modestop'} = 'Stop';
		return Slim::Web::HTTP::filltemplatefile("status_needs_upgrade.html", $params);
	}

	my $current_player;
	my $songcount = 0;
	 
	if (defined($client)) {

		$songcount = Slim::Player::Playlist::count($client);
		
		if ($client->defaultName() ne $client->name()) {
			$params->{'player_name'} = $client->name();
		}

		if (Slim::Player::Playlist::shuffle($client) == 1) {
			$params->{'shuffleon'} = "on";
		} elsif (Slim::Player::Playlist::shuffle($client) == 2) {
			$params->{'shufflealbum'} = "album";
		} else {
			$params->{'shuffleoff'} = "off";
		}
	
		$params->{'songtime'} = int(Slim::Player::Source::songTime($client));

		if (Slim::Player::Playlist::song($client)) { 
			my $dur = $client->songduration;
			if ($dur) { $dur = int($dur); }
			$params->{'durationseconds'} = $dur; 
		}

		#
		if (!Slim::Player::Playlist::repeat($client)) {
			$params->{'repeatoff'} = "off";
		} elsif (Slim::Player::Playlist::repeat($client) == 1) {
			$params->{'repeatone'} = "one";
		} else {
			$params->{'repeatall'} = "all";
		}

		#
		if (Slim::Player::Source::playmode($client) eq 'play') {

			$params->{'modeplay'} = "Play";

			if (defined($params->{'durationseconds'}) && defined($params->{'songtime'})) {

				my $remaining = $params->{'durationseconds'} - $params->{'songtime'};

				if ($remaining < $params->{'refresh'}) {	
					$params->{'refresh'} = ($remaining < 5) ? 5 : $remaining;
				}
			}

		} elsif (Slim::Player::Source::playmode($client) eq 'pause') {

			$params->{'modepause'} = "Pause";
		
		} else {
			$params->{'modestop'} = "Stop";
		}

		#
		if (Slim::Player::Source::rate($client) > 1) {
			$params->{'rate'} = 'ffwd';
		} elsif (Slim::Player::Source::rate($client) < 0) {
			$params->{'rate'} = 'rew';
		} else {
			$params->{'rate'} = 'norm';
		}
		
		$params->{'rateval'} = Slim::Player::Source::rate($client);
		$params->{'sync'}    = Slim::Player::Sync::syncwith($client);
		$params->{'mode'}    = Slim::Buttons::Common::mode($client);

		if ($client->isPlayer()) {

			$params->{'sleeptime'} = $client->currentSleepTime();
			$params->{'isplayer'}  = 1;
			$params->{'volume'}    = int($client->volume() + 0.5);
			$params->{'bass'}      = int($client->bass() + 0.5);
			$params->{'treble'}    = int($client->treble() + 0.5);
			$params->{'pitch'}     = int($client->pitch() + 0.5);

			my $sleep = $client->sleepTime() - Time::HiRes::time();
			$params->{'sleep'} = $sleep < 0 ? 0 : int($sleep/60);
		}
		
		$params->{'fixedVolume'} = !Slim::Utils::Prefs::clientGet($client, 'digitalVolumeControl');
		$params->{'player'} = $client->id();
	}
	
	if ($songcount > 0) {
		my $song = Slim::Player::Playlist::song($client);

		$params->{'currentsong'} = Slim::Player::Source::currentSongIndex($client) + 1;
		$params->{'thissongnum'} = Slim::Player::Source::currentSongIndex($client);

		$params->{'songcount'}   = $songcount;
		$params->{'itempath'}    = $song;

		_addSongInfo($client, $params);

		# for current song, display the playback bitrate instead.
		my $undermax = Slim::Player::Source::underMax($client,$song);
		if (defined $undermax && !$undermax) {
			$params->{'bitrate'} = string('CONVERTED_TO')." ".Slim::Utils::Prefs::maxRate($client).Slim::Utils::Strings::string('KBPS').' CBR';
		}
		if (Slim::Utils::Prefs::get("playlistdir")) {
			$params->{'cansave'} = 1;
		}
	}
	
	if (!$params->{'omit_playlist'}) {

		$params->{'callback'} = $callback;

		$params->{'playlist'} = playlist($client, $params, \&status_done, $httpClient, $response);

		if (!$params->{'playlist'}) {
			# playlist went into background, stash $callback and exit
			return undef;
		} else {
			$params->{'playlist'} = ${$params->{'playlist'}};
		}
	} else {
		# Special case, we need the playlist info even if we don't want
		# the playlist itself
		if ($client && $client->currentPlaylist()) {
			$params->{'current_playlist'} = $client->currentPlaylist();
			$params->{'current_playlist_modified'} = $client->currentPlaylistModified();
			$params->{'current_playlist_name'} = Slim::Music::Info::standardTitle($client, $client->currentPlaylist());
		}
	}

	$params->{'nosetup'} = 1   if $::nosetup;

	return Slim::Web::HTTP::filltemplatefile($params->{'omit_playlist'} ? "status_header.html" : "status.html" , $params);
}

sub status_done {
	my ($client, $params, $bodyref, $httpClient, $response) = @_;

	$params->{'playlist'} = $$bodyref;

	my $output = Slim::Web::HTTP::filltemplatefile("status.html" , $params);

	$params->{'callback'}->($client, $params, $output, $httpClient, $response);
}

sub playlist {
	my ($client, $params, $callback, $httpClient, $response) = @_;
	
	if (defined($client) && $client->needsUpgrade()) {

		$params->{'player_needs_upgrade'} = '1';
		return Slim::Web::HTTP::filltemplatefile("playlist_needs_upgrade.html", $params);
	}

	$params->{'playercount'} = Slim::Player::Client::clientCount();
	
	my $songcount = 0;

	if (defined($client)) {
		$songcount = Slim::Player::Playlist::count($client);
	}

	$params->{'playlist_items'} = '';
	if ($client && $client->currentPlaylist()) {
		$params->{'current_playlist'} = $client->currentPlaylist();
		$params->{'current_playlist_modified'} = $client->currentPlaylistModified();
		$params->{'current_playlist_name'} = Slim::Music::Info::standardTitle($client,$client->currentPlaylist());
	}

	if ($songcount > 0) {

		my %listBuild = ();
		my $item;
		my %list_form;

		if (Slim::Utils::Prefs::get("playlistdir")) {
			$params->{'cansave'} = 1;
		}
		
		my ($start, $end);
		
		if (defined $params->{'nopagebar'}) {

			($start, $end) = simpleHeader(
				$songcount,
				\$params->{'start'},
				\$params->{'playlist_header'},
				$params->{'skinOverride'},
				$params->{'itemsPerPage'},
				0
			);

		} else {

			($start, $end) = pageBar(
				$songcount,
				$params->{'path'},
				Slim::Player::Source::currentSongIndex($client),
				"player=" . Slim::Web::HTTP::escape($client->id()) . "&", 
				\$params->{'start'}, 
				\$params->{'playlist_header'},
				\$params->{'playlist_pagebar'},
				$params->{'skinOverride'}
				,$params->{'itemsPerPage'}
			);
		}

		$listBuild{'start'} = $start;
		$listBuild{'end'}   = $end;

		$listBuild{'offset'} = $listBuild{'start'} % 2 ? 0 : 1; 

		my $webFormat = Slim::Utils::Prefs::getInd("titleFormat",Slim::Utils::Prefs::get("titleFormatWeb"));

		$listBuild{'includeArtist'} = ($webFormat !~ /ARTIST/);
		$listBuild{'includeAlbum'}  = ($webFormat !~ /ALBUM/) ;
		$listBuild{'currsongind'}   = Slim::Player::Source::currentSongIndex($client);
		$listBuild{'item'}          = $listBuild{'start'};

		# So we only do this once per page request.
		$listBuild{'noArtist'}      = Slim::Utils::Strings::string('NO_ARTIST');
		$listBuild{'noAlbum'}       = Slim::Utils::Strings::string('NO_ALBUM');

		if (buildPlaylist($client, $params, $callback, $httpClient, $response, \%listBuild)) {

			Slim::Utils::Scheduler::add_task(
				\&buildPlaylist,
				$client,
				$params,
				$callback,
				$httpClient,
				$response,
				\%listBuild,
			);
		}

		return undef;
	}

	return Slim::Web::HTTP::filltemplatefile("playlist.html", $params);
}

sub _addPlayerList {
	my ($client, $params) = @_;

	$params->{'playercount'} = Slim::Player::Client::clientCount();
	
	my @players = Slim::Player::Client::clients();

	if (scalar(@players) > 1) {

		my %clientlist = ();

		for my $eachclient (@players) {

			$clientlist{$eachclient->id()} =  $eachclient->name();

			if (Slim::Player::Sync::isSynced($eachclient)) {
				$clientlist{$eachclient->id()} .= " (".string('SYNCHRONIZED_WITH')." ".
					Slim::Player::Sync::syncwith($eachclient).")";
			}	
		}

		$params->{'player_chooser_list'} = options($client->id(), \%clientlist, $params->{'skinOverride'});
	}
}

sub buildPlaylist {
	my ($client, $params, $callback, $httpClient, $response, $listBuild) = @_;

	my $itemCount    = 0;
	my $itemsPerPass = Slim::Utils::Prefs::get('itemsPerPass');
	my $starttime    = Time::HiRes::time();

	my $ds           = Slim::Music::Info::getCurrentDataStore();

	while ($listBuild->{'item'} < ($listBuild->{'end'} + 1) && $itemCount < $itemsPerPass) {

		my %list_form = %$params;

		$list_form{'myClientState'} = $client;
		$list_form{'num'}           = $listBuild->{'item'};
		$list_form{'odd'}           = ($listBuild->{'item'} + $listBuild->{'offset'}) % 2;

		if ($listBuild->{'item'} == $listBuild->{'currsongind'}) {
			$list_form{'currentsong'} = "current";
		} else {
			$list_form{'currentsong'} = undef;
		}

		$list_form{'nextsongind'} = $listBuild->{'currsongind'} + (($listBuild->{'item'} > $listBuild->{'currsongind'}) ? 1 : 0);

		my $song = Slim::Player::Playlist::song($client, $listBuild->{'item'});

		$list_form{'player'}   = $params->{'player'};
		$list_form{'title'}    = Slim::Music::Info::standardTitle(undef,$song);

		my $track = $ds->objectForUrl($song) || do {
			$::d_info && Slim::Utils::Misc::msg("Couldn't retrieve objectForUrl: [$song] - skipping!\n");
			$listBuild->{'item'}++;
			$itemCount++;
			next;
		};

		$list_form{'itempath'} = $song;
		$list_form{'item'}     = $track->id();

		$list_form{'artists'}  = $listBuild->{'includeArtist'} ? $track->contributors() : undef;
		$list_form{'album'}    = $listBuild->{'includeAlbum'}  ? $track->album() : undef;

		$list_form{'start'}	   = $params->{'start'};
		$list_form{'skinOverride'} = $params->{'skinOverride'};

		push @{$listBuild->{'playlist_items'}}, ${Slim::Web::HTTP::filltemplatefile("status_list.html", \%list_form)};

		$listBuild->{'item'}++;
		$itemCount++;

		# don't neglect the streams for over 0.25 seconds
		if ((Time::HiRes::time() - $starttime) > 0.25) {
			::idleStreams() ;
		}
	}

	if ($listBuild->{'item'} < $listBuild->{'end'} + 1) {

		return 1;

	} else {

		if (defined $listBuild->{'playlist_items'}) {
			$params->{'playlist_items'} = join('', @{$listBuild->{'playlist_items'}});
		}

		undef %$listBuild;

		playlist_done($client, $params, $callback, $httpClient, $response);

		return 0;
	}
}

sub playlist_done {
	my ($client, $params, $callback, $httpClient, $response) = @_;
	$params->{'playercount'} = Slim::Player::Client::clientCount();
	my $body = Slim::Web::HTTP::filltemplatefile("playlist.html", $params);

	if (ref($callback) eq 'CODE') {

		$callback->($client, $params, $body, $httpClient, $response);
	}
}

# Call into the memory usage class - this will return live data about memory
# usage, opcodes, and more. Note that loading this takes up memory itself!
sub memory_usage {
	my ($client, $params) = @_;

	my $item    = $params->{'item'};
	my $type    = $params->{'type'};
	my $command = $params->{'command'};

	unless ($item && $command) {

		return Slim::Utils::MemoryUsage->status_memory_usage();
	}

	if (defined $item && defined $command && Slim::Utils::MemoryUsage->can($command)) {

		return Slim::Utils::MemoryUsage->$command($item, $type);
	}
}

sub livesearch {
	my ($client, $params) = @_;

	my $player = $params->{'player'};
	my $query  = $params->{'query'};

	# set some defaults for the template
	$params->{'browse_list'} = " ";
	$params->{'numresults'}  = -1;
	$params->{'liveSearch'}  = 1;

	# short circuit
	unless ($query) {
		return Slim::Web::HTTP::filltemplatefile("search.html", $params);
	}

	return unless length($query) > 2;

	my $data = Slim::Music::LiveSearch->query($query);

	# The user has hit enter, or has a browser that can't handle the javascript.
	if ($params->{'manualSearch'}) {

		# Tell the template not to do a livesearch request anymore.
		$params->{'liveSearch'} = 0;

		for my $item (@$data) {

			$params->{'type'} = $item->[0];

			_fillInSearchResults($params, $item->[1], undef, []);
		}

		return Slim::Web::HTTP::filltemplatefile("search.html", $params);
	}

	# do it live - and send back the div
	return Slim::Music::LiveSearch->renderAsXML($query, $data, $player);
}

sub advancedSearch {
	my ($client, $params) = @_;

	my $player  = $params->{'player'};
	my %query   = ();
	my @qstring = ();
	my $ds      = Slim::Music::Info::getCurrentDataStore();

	# template defaults
	$params->{'browse_list'} = " ";
	$params->{'numresults'}  = -1;
	$params->{'liveSearch'}  = 0;

	# Prep the date format
	$params->{'dateFormat'} = Slim::Utils::Misc::shortDateF();

	# Check for valid search terms
	for my $key (keys %$params) {
		
		next unless $key =~ /^search\.(\S+)/;
		next unless $params->{$key};

		my $newKey = $1;

		# Stuff the requested item back into the params hash, under
		# the special "search" hash. Because Template Toolkit uses '.'
		# as a delimiter for hash access.
		$params->{'search'}->{$newKey}->{'value'} = $params->{$key};

		# Apply the logical operator to the item in question.
		if ($key =~ /\.op$/) {

			my $op = $params->{$key};

			$key    =~ s/\.op$//;
			$newKey =~ s/\.op$//;

			next unless $params->{$key};

			# Do the same for 'op's
			$params->{'search'}->{$newKey}->{'op'} = $params->{$key};

			# add these onto the query string. kinda jankey.
			push @qstring, join('=', "$key.op", $op);
			push @qstring, join('=', $key, $params->{$key});

			# Bitrate needs to changed a bit
			if ($key =~ /bitrate$/) {
				$params->{$key} *= 100;
			}

			# Duration is also special
			if ($key =~ /age$/) {
				$params->{$key} = str2time($params->{$key});
			}

			# Map the type to the query
			# This will be handed to SQL::Abstract
			$query{$newKey} = { $op => $params->{$key} };

			delete $params->{$key};

			next;
		}

		# Append to the query string
		push @qstring, join('=', $key, Slim::Web::HTTP::escape($params->{$key}));

		# Normalize the string queries
		# 
		# Turn the track_title into track.title for the query.
		# We need the _'s in the form, because . means hash key.
		if ($newKey =~ s/_(title|name)$/\.$1/) {

			$params->{$key} = searchStringSplit($params->{$key});
		}

		# Wildcard comment searches
		if ($newKey =~ /comment/) {

			$params->{$key} = "\*$params->{$key}\*";
		}

		$query{$newKey} = $params->{$key};
	}

	# Turn our conversion list into a nice type => name hash.
	my %types  = ();

	for my $type (keys %{ Slim::Player::Source::Conversions() }) {

		$type = (split /-/, $type)[0];

		$types{$type} = string($type);
	}

	$params->{'fileTypes'} = \%types;

	# load up the genres we know about.
	$params->{'genres'}    = $ds->find('genre', {}, 'genre');

	# short-circuit the query
	if (scalar keys %query == 0) {

		return Slim::Web::HTTP::filltemplatefile("advanced_search.html", $params);
	}

	# Do the actual search
	my $results = $ds->find('track', \%query, 'title');

	_fillInSearchResults($params, $results, undef, \@qstring, $ds);

	return Slim::Web::HTTP::filltemplatefile("advanced_search.html", $params);
}

sub search {
	my ($client, $params) = @_;

	my $player = $params->{'player'};
	my $query  = $params->{'query'};
	my $type   = $params->{'type'};
	my $results;
	my $descend = 'true';

	# template defaults
	$params->{'browse_list'} = " ";
	$params->{'numresults'}  = -1;
	$params->{'liveSearch'}  = 0;

	# short circuit
	unless ($query) {
		return Slim::Web::HTTP::filltemplatefile("search.html", $params);
	}

	my $ds = Slim::Music::Info::getCurrentDataStore();

	my $searchStrings = searchStringSplit($query, $params->{'searchSubString'});

	# Search for each type of data we have
	if ($type eq 'artist') {

		$results = $ds->find('contributor', { "contributor.name" => $searchStrings }, 'contributor');

	} elsif ($type eq 'album') {

		$results = $ds->find('album', { "album.title" => $searchStrings }, 'album');

	} elsif ($type eq 'song') {

		my $sortBy = 'title';
		my %find   = ();

		for my $string (@{$searchStrings}) {
			push @{$find{'track.title'}}, [ $string ];
		}

		$results = $ds->find('track', \%find, $sortBy);

		$descend = undef;
	}

	_fillInSearchResults($params, $results, $descend, [], $ds);

	return Slim::Web::HTTP::filltemplatefile("search.html", $params);
}

sub _fillInSearchResults {
	my ($params, $results, $descend, $qstring, $ds) = @_;

	my $player = $params->{'player'};
	my $query  = $params->{'query'}  || '';
	my $type   = $params->{'type'}   || 'song';

	my $otherParams = 'player=' . Slim::Web::HTTP::escape($player) . 
			  '&type=' . ($type ? $type : ''). 
			  '&query=' . Slim::Web::HTTP::escape($query) . '&' .
			  join('&', @$qstring);

	# set some defaults for the template
	$params->{'browse_list'} = " ";
	$params->{'numresults'}  = -1;
	$params->{'liveSearch'}  = 0;

	# Make sure that we have something to show.
	if (defined $results && ref($results) eq 'ARRAY') {

		$params->{'numresults'} = scalar @$results;
	}

	if ($params->{'numresults'}) {

		my ($start, $end);

		if (defined $params->{'nopagebar'}){

			($start, $end) = simpleHeader(
				$params->{'numresults'},
				\$params->{'start'},
				\$params->{'browselist_header'},
				$params->{'skinOverride'},
				$params->{'itemsPerPage'},
				0
			);

		} else {

			($start, $end) = pageBar(
				$params->{'numresults'},
				$params->{'path'},
				0,
				$otherParams,
				\$params->{'start'},
				\$params->{'searchlist_header'},
				\$params->{'searchlist_pagebar'},
				$params->{'skinOverride'},
				$params->{'itemsPerPage'},
			);
		}
		
		my $webFormat  = Slim::Utils::Prefs::getInd("titleFormat", Slim::Utils::Prefs::get("titleFormatWeb"));
		my $itemnumber = 0;
		my $lastAnchor = '';

		for my $item (@$results[$start..$end]) {

			# Contributor/Artist uses name, Album & Track uses title.
			my $title     = $item->can('title') ? $item->title() : $item->name();
			my %list_form = %$params;

			$list_form{'includeArtist'} = ($webFormat !~ /ARTIST/);
			$list_form{'includeAlbum'}  = ($webFormat !~ /ALBUM/) ;

			if ($type eq 'song') {

				$list_form{'title'}	= Slim::Music::Info::standardTitle(undef, $item);
				$list_form{'artist'}	= $item->artist();
				$list_form{'album'}	= $item->album();
				$list_form{'item'}	= $item->id();
				$list_form{'itempath'}	= $item->url();

			} else {

				$list_form{'title'} = $item->can('title') ? $item->title() : $item->name();
			}

			$list_form{'attributes'}   = '&' . join('=', $type, $item->id());
			$list_form{'hierarchy'}    = $hierarchy{$type};
			$list_form{'level'}        = 0;
			$list_form{'text'}         = $title;
			$list_form{'descend'}      = $descend;

			$list_form{'descend'}      = $descend;
			$list_form{'player'}       = $player;
			$list_form{'odd'}	   = ($itemnumber + 1) % 2;
			$list_form{'skinOverride'} = $params->{'skinOverride'};

			$itemnumber++;

			my $anchor = anchor(Slim::Utils::Text::getSortName($title), 1) || '';

			if ($lastAnchor ne $anchor) {
				$list_form{'anchor'} = $lastAnchor = $anchor;
			}

			$params->{'browse_list'} .= ${Slim::Web::HTTP::filltemplatefile("browsedb_list.html", \%list_form)};
		}
	}
}

sub _addSongInfo {
	my ($client, $params) = @_;

	# 
	my $song = $params->{'itempath'};
	my $id   = $params->{'item'};

	# kinda pointless, but keeping with compatibility
	return unless $song || $id;

	my $ds = Slim::Music::Info::getCurrentDataStore();
	my $track;

	if ($song) {

		$track = $ds->objectForUrl($song, 0);

	} elsif ($id) {

		$track = $ds->objectForId('track', $id);
		$song  = $track->url() if $track;
	}

	if ($track) {

		# let the template access the object directly.
		$params->{'track'}     = $track;

		$params->{'filelength'} = Slim::Utils::Misc::delimitThousands($track->filesize());
		$params->{'songtitle'}  = Slim::Music::Info::standardTitle(undef, $track);
		$params->{'mixable'}	= $track->moodlogic_mixable;

		# make urls in comments into links
		for my $comment ($track->comment()) {

			next unless defined $comment && $comment !~ /^\s*$/;

			if (!($comment =~ s!\b(http://[\-~A-Za-z0-9_/\.]+)!<a href=\"$1\" target=\"_blank\">$1</a>!igo)) {

				# handle emusic-type urls which don't have http://
				$comment =~ s!\b(www\.[\-~A-Za-z0-9_/\.]+)!<a href=\"http://$1\" target=\"_blank\">$1</a>!igo;
			}

			$params->{'comment'} .= $comment;
		}
	
		# handle artwork bits
		if ($track->coverArt('thumb')) {
			$params->{'coverthumb'} = 1;
		}
	}
	
	my $downloadurl;

	if (Slim::Music::Info::isHTTPURL($song)) {

		$downloadurl = $song;

	} else {

		my $loc  = $song;

		if (Slim::Music::Info::isFileURL($song)) {
			$loc = Slim::Utils::Misc::pathFromFileURL($loc);
		}

		# We need to turn the utf8 flag back on, after it's been
		# stripped, so the url encoding will be correct.
		if ($Slim::Utils::Misc::locale eq 'utf8') {
			$loc = Slim::Utils::Misc::utf8decode($loc);
		}

		my $curdir = Slim::Utils::Prefs::get('audiodir');

		if (!$curdir) {
			$downloadurl = undef;
		} elsif ($loc =~ /^\Q$curdir\E(.*)/i) {

			$downloadurl = '/music';

			for my $item (splitdir($1)) {
				$downloadurl .= '/' . Slim::Web::HTTP::escape($item);
			}

			$downloadurl =~ s/\/\//\//;

		} else {

			$downloadurl = $loc;
		}
	}

	$params->{'itempath'} = $song;
	$params->{'download'} = $downloadurl;
}

sub songInfo {
	my ($client, $params) = @_;

	_addSongInfo($client, $params);

	return Slim::Web::HTTP::filltemplatefile("songinfo.html", $params);
}

# XXX FIXME The fieldInfo type structure, at some level, is going to
# be needed here, in the command code (for playlist commands), and in
# the browse menu code. The following method is a placeholder till we
# figure out how to share it.
sub queryFields {
	return keys %fieldInfo;
}

# XXX FIXME queryFields is used, but other methods might need full access to the hash.
sub fieldInfo {
	return \%fieldInfo;
}

sub browsedb {
	my ($client, $params) = @_;

	# XXX - why do we default to genre?
	my $hierarchy = $params->{'hierarchy'} || "genre";
	my $level     = $params->{'level'} || 0;
	my $player    = $params->{'player'};

	$::d_info && msg("browsedb - hierarchy: $hierarchy level: $level\n");

	my @levels = split(",", $hierarchy);

	my $maxLevel = scalar(@levels) - 1;

	if ($level > $maxLevel)	{
		$level = $maxLevel;
	}

	my $ds = Slim::Music::Info::getCurrentDataStore();

	my $itemnumber = 0;
	my $lastAnchor = '';
	my $descend;
	my %names = ();
	my @attrs = ();
	my %findCriteria = ();	

	for my $field (@levels) {

		my $info = $fieldInfo{$field} || $fieldInfo{'default'};

		# XXX - is this the right thing to do?
		# For artwork browsing - we want to display the album.
		if (my $transform = $info->{'nameTransform'}) {
			push @levels, $transform;
		}

		# If we don't have this check, we'll create a massive query
		# for each level in the hierarchy, even though it's not needed
		next unless defined $params->{$field};

		$names{$field} = &{$info->{'idToName'}}($ds, $params->{$field});
	}

	# Just go directly to the params.
	addLibraryStats($params, [$params->{'genre'}], [$params->{'artist'}], [$params->{'album'}], [$params->{'song'}]);

	# warn the user if the scanning isn't complete.
	if (Slim::Utils::Misc::stillScanning()) {
		$params->{'warn'} = 1;
	}

	# This pulls the appropriate anonymous function list out of the
	# fieldInfo hash, which we then retrieve data from.
	my $firstLevelInfo = $fieldInfo{$levels[0]} || $fieldInfo{'default'};
	my $title = $params->{'browseby'} = $firstLevelInfo->{'title'};

	for my $key (keys %fieldInfo) {

		if (defined($params->{$key})) {

			# Populate the find criteria with all query parameters in the URL
			$findCriteria{$key} = $params->{$key};

			# Pre-populate the attrs list with all query parameters that 
			# are not part of the hierarchy. This allows a URL to put
			# query constraints on a hierarchy using a field that isn't
			# necessarily part of the hierarchy.
			if (!grep {$_ eq $key} @levels) {
				push @attrs, $key . '=' . Slim::Web::HTTP::escape($params->{$key});
			}
		}
	}

	my %list_form = (
		'player'       => $player,
		'pwditem'      => string($title),
		'skinOverride' => $params->{'skinOverride'},
		'title'	       => $title,
		'hierarchy'    => $hierarchy,
		'level'	       => 0,
		'attributes'   => (scalar(@attrs) ? ('&' . join("&", @attrs)) : ''),
	);

	$params->{'pwd_list'} .= ${Slim::Web::HTTP::filltemplatefile("browsedb_pwdlist.html", \%list_form)};

	for (my $i = 0; $i < $level ; $i++) {

		my $attr = $levels[$i];

		# XXX - is this the right thing to do?
		# For artwork browsing - we want to display the album.
		if (my $transform = $firstLevelInfo->{'nameTransform'}) {
			$attr = $transform;
		}

		if ($params->{$attr}) {

			push @attrs, $attr . '=' . Slim::Web::HTTP::escape($params->{$attr});

			my %list_form = (
				 'player'       => $player,
				 'pwditem'      => $names{$attr},
				 'skinOverride' => $params->{'skinOverride'},
				 'title'	=> $title,
				 'hierarchy'	=> $hierarchy,
				 'level'	=> $i+1,
				 'attributes'   => (scalar(@attrs) ? ('&' . join("&", @attrs)) : ''),
			 );
			
			$params->{'pwd_list'} .= ${Slim::Web::HTTP::filltemplatefile("browsedb_pwdlist.html", \%list_form)};
		}
	}

	my $otherparams = join('&',
		'player=' . Slim::Web::HTTP::escape($player || ''),
		"hierarchy=$hierarchy",
		"level=$level",
		@attrs,
	);

	my $levelInfo = $fieldInfo{$levels[$level]} || $fieldInfo{'default'};
	my $items     = &{$levelInfo->{'find'}}($ds, $levels[$level], \%findCriteria);

	if ($items && scalar(@$items)) {

		my ($start, $end);

		my $ignoreArticles = $levelInfo->{'ignoreArticles'};
		my $alpha = $levelInfo->{'alphaPageBar'};

		if (defined $params->{'nopagebar'}) {

			($start, $end) = simpleHeader(
				scalar(@$items),
				\$params->{'start'},
				\$params->{'browselist_header'},
				$params->{'skinOverride'},
				$params->{'itemsPerPage'},
				$ignoreArticles ? (scalar(@$items) > 1) : 0,
			);

		} elsif ($alpha) {
			
			my $alphaitems = [ map &{$levelInfo->{'resultToSortedName'}}($_), @$items ];

			($start, $end) = alphaPageBar(
				$alphaitems,
				$params->{'path'},
				$otherparams,
				\$params->{'start'},
				\$params->{'browselist_pagebar'},
				$ignoreArticles, 
				$params->{'skinOverride'},
				$params->{'itemsPerPage'},
			);

		} else {

			($start, $end) = pageBar(
				scalar(@$items),
				$params->{'path'},
				0,
				$otherparams,
				\$params->{'start'},
				\$params->{'browselist_header'},
				\$params->{'browselist_pagebar'},
				$params->{'skinOverride'},
				$params->{'itemsPerPage'},
			);
		}

		$descend = ($level >= $maxLevel) ? undef : 'true';

		if (scalar(@$items) > 1 && !$levelInfo->{'suppressAll'}) {

			if ($params->{'includeItemStats'} && !Slim::Utils::Misc::stillScanning()) {
				# XXX include statistics
			}

			my $nextLevelInfo;

			if ($descend) {
				my $nextLevel  = $levels[$level+1];
				$nextLevelInfo = $fieldInfo{$nextLevel} || $fieldInfo{'default'};
			} else {
				$nextLevelInfo = $fieldInfo{'track'};
			}

			if ($level == 0) {
				$list_form{'hierarchy'}	= join(',', @levels[1..$#levels]);
				$list_form{'level'}	= 0;
			} else {
				$list_form{'hierarchy'}	= $hierarchy;
				$list_form{'level'}	= $descend ? $level+1 : $level;
			}

			$list_form{'text'} = string($nextLevelInfo->{'allTitle'});

			$list_form{'descend'}      = 1;
			$list_form{'player'}       = $player;
			$list_form{'odd'}	   = ($itemnumber + 1) % 2;
			$list_form{'skinOverride'} = $params->{'skinOverride'};
			$list_form{'attributes'}   = (scalar(@attrs) ? ('&' . join("&", @attrs)) : '');
				
			$itemnumber++;
				
			$params->{'browse_list'} .= ${Slim::Web::HTTP::filltemplatefile("browsedb_list.html", \%list_form)};
		}

		for my $item ( @{$items}[$start..$end] ) {

			my %list_form = %$params;

			my $itemid   = &{$levelInfo->{'resultToId'}}($item);
			my $itemname = &{$levelInfo->{'resultToName'}}($item);
			my $attrName = $levelInfo->{'nameTransform'} || $levels[$level];

			$list_form{'hierarchy'}	    = $hierarchy;
			$list_form{'level'}	    = $level + 1;
			$list_form{'attributes'}    = (scalar(@attrs) ? ('&' . join("&", @attrs)) : '') . '&' .
				$attrName . '=' . Slim::Web::HTTP::escape($itemid);

			$list_form{'levelName'}	    = $attrName;
			$list_form{'text'}	    = $itemname;
			$list_form{'descend'}	    = $descend;
			$list_form{'player'}	    = $player;
			$list_form{'odd'}	    = ($itemnumber + 1) % 2;
			$list_form{$levels[$level]} = $itemid;
			$list_form{'skinOverride'}  = $params->{'skinOverride'};
			$list_form{'itemnumber'}    = $itemnumber;

			# This is calling into the %fieldInfo hash
			&{$levelInfo->{'listItem'}}($ds, \%list_form, $item, $itemname, $descend);

			my $anchor = Slim::Web::Pages::anchor(Slim::Utils::Text::getSortName($itemname), $ignoreArticles);

			if ($lastAnchor && $lastAnchor ne $anchor) {
				$list_form{'anchor'} = $lastAnchor = $anchor;
			}

			$itemnumber++;

			if ($levels[$level] eq 'artwork') {
				$params->{'browse_list'} .= ${Slim::Web::HTTP::filltemplatefile("browsedb_artwork.html", \%list_form)};
			} else {
				$params->{'browse_list'} .= ${Slim::Web::HTTP::filltemplatefile("browsedb_list.html", \%list_form)};
			}

			main::idleStreams();
		}

		if ($level == $maxLevel && $levels[$level] eq 'track') {

			if ($items->[$start]->coverArt()) {
				$params->{'coverart'} = 1;
				$params->{'coverartpath'} = $items->[$start]->url;
			}
		}
	}

	$params->{'descend'} = $descend;
	
	return Slim::Web::HTTP::filltemplatefile("browsedb.html", $params);
}

# Implement browseid3 in terms of browsedb.
sub browseid3 {
	my ($client, $params) = @_;

	my @hierarchy  = ();
	my %categories = (
		'genre'  => 'genre',
		'artist' => 'artist',
		'album'  => 'album',
		'song'   => 'track'
	);

	my $ds = Slim::Music::Info::getCurrentDataStore();

	$params->{'level'} = 0;

	# Turn the browseid3 params into something browsedb can use.
	for my $category (keys %categories) {

		next unless $params->{$category};

		$params->{ $categories{$category} } = $params->{$category};
	}

	# These must be in order.
	for my $category (qw(genre artist album track)) {

		if (!defined $params->{$category}) {

			push @hierarchy, $category;

		} elsif ($params->{$category} eq '*') {

			delete $params->{$category};

		} elsif ($params->{$category}) {

			# Search for each real name - normalize the query,
			# then turn it into the ID suitable for browsedb()
			$params->{$category} = (@{$ds->search(
				$category,
				[ Slim::Utils::Text::ignoreCaseArticles($params->{$category}) ]
			)})[0]->id();
		}
	}

	$params->{'hierarchy'} = join(',', @hierarchy);

	return browsedb($client, $params);
}

sub searchStringSplit {
	my $search  = shift;
	my $searchSubString = shift;
	
	$searchSubString = defined $searchSubString ? $searchSubString : Slim::Utils::Prefs::get('searchSubString');

	# normalize the string
	$search = Slim::Utils::Text::ignoreCaseArticles($search);
	
	my @strings = ();

	# Don't split - causes an explict AND, which is what we want.. I think.
	# for my $string (split(/\s+/, $search)) {
	my $string = $search;

		if ($searchSubString) {

			push @strings, "\*$string\*";

		} else {

			push @strings, [ "$string\*", "\* $string\*" ];
		}
	#}

	return \@strings;
}

sub anchor {
	my $item = shift;
	my $suppressArticles = shift;
	
	if ($suppressArticles) {
		$item = Slim::Utils::Text::ignoreCaseArticles($item);
	}

	return Slim::Utils::Text::matchCase(substr($item, 0, 1));
}

sub options {
	my ($selected, $option, $skinOverride) = @_;

	# pass in the selected value and a hash of value => text pairs to get the option list filled
	# with the correct option selected.

	my $optionlist = '';

	for my $curroption (sort { $option->{$a} cmp $option->{$b} } keys %{$option}) {

		$optionlist .= ${Slim::Web::HTTP::filltemplatefile("select_option.html", {
			'selected'     => ($curroption eq $selected),
			'key'          => $curroption,
			'value'        => $option->{$curroption},
			'skinOverride' => $skinOverride,
		})};
	}

	return $optionlist;
}

# Build a simple header 
sub simpleHeader {
	my ($itemCount, $startRef, $headerRef, $skinOverride, $count, $offset) = @_;

	$count ||= Slim::Utils::Prefs::get('itemsPerPage');

	my $start = (defined($$startRef) && $$startRef ne '') ? $$startRef : 0;

	if ($start >= $itemCount) {
		$start = $itemCount - $count;
	}

	$$startRef = $start;

	my $end    = $start + $count - 1 - $offset;

	if ($end >= $itemCount) {
		$end = $itemCount - 1;
	}

	$$headerRef = ${Slim::Web::HTTP::filltemplatefile("pagebarheader.html", {
		"start"        => $start,
		"end"          => $end,
		"itemcount"    => $itemCount - 1,
		'skinOverride' => $skinOverride
	})};

	return ($start, $end);
}

# Build a bar of links to multiple pages of items
sub pageBar {
	my $itemcount = shift;
	my $path = shift;
	my $currentitem = shift;
	my $otherparams = shift;
	my $startref = shift; #will be modified
	my $headerref = shift; #will be modified
	my $pagebarref = shift; #will be modified
	my $skinOverride = shift;

	my $count = shift || Slim::Utils::Prefs::get('itemsPerPage');

	my $start = (defined($$startref) && $$startref ne '') ? $$startref : (int($currentitem/$count)*$count);
	if ($start >= $itemcount) { $start = $itemcount - $count; }
	$$startref = $start;
	my $end = $start+$count-1;
	if ($end >= $itemcount) { $end = $itemcount - 1;}
	if ($itemcount > $count) {
		$$headerref = ${Slim::Web::HTTP::filltemplatefile("pagebarheader.html", { "start" => ($start+1), "end" => ($end+1), "itemcount" => $itemcount, 'skinOverride' => $skinOverride})};

		my %pagebar = ();

		my $numpages  = POSIX::ceil($itemcount/$count);
		my $curpage   = int($start/$count);
		my $pagesperbar = 10; #make this a preference
		my $pagebarstart = (($curpage - int($pagesperbar/2)) < 0 || $numpages <= $pagesperbar) ? 0 : ($curpage - int($pagesperbar/2));
		my $pagebarend = ($pagebarstart + $pagesperbar) > $numpages ? $numpages : ($pagebarstart + $pagesperbar);

		$pagebar{'pagesstart'} = ($pagebarstart > 0);

		if ($pagebar{'pagesstart'}) {
			$pagebar{'pagesprev'} = ($curpage - $pagesperbar) * $count;
			if ($pagebar{'pagesprev'} < 0) { $pagebar{'pagesprev'} = 0; };
		}

		if ($pagebarend < $numpages) {
			$pagebar{'pagesend'} = ($numpages -1) * $count;
			$pagebar{'pagesnext'} = ($curpage + $pagesperbar) * $count;
			if ($pagebar{'pagesnext'} > $pagebar{'pagesend'}) { $pagebar{'pagesnext'} = $pagebar{'pagesend'}; }
		}

		$pagebar{'pageprev'} = $curpage > 0 ? (($curpage - 1) * $count) : undef;
		$pagebar{'pagenext'} = ($curpage < ($numpages - 1)) ? (($curpage + 1) * $count) : undef;
		$pagebar{'otherparams'} = defined($otherparams) ? $otherparams : '';
		$pagebar{'skinOverride'} = $skinOverride;
		$pagebar{'path'} = $path;

		for (my $j = $pagebarstart;$j < $pagebarend;$j++) {
			$pagebar{'pageslist'} .= ${Slim::Web::HTTP::filltemplatefile('pagebarlist.html'
							,{'currpage' => ($j == $curpage)
							,'itemnum0' => ($j * $count)
							,'itemnum1' => (($j * $count) + 1)
							,'pagenum' => ($j + 1)
							,'otherparams' => $otherparams
							,'skinOverride' => $skinOverride
							,'path' => $path})};
		}
		$$pagebarref = ${Slim::Web::HTTP::filltemplatefile("pagebar.html", \%pagebar)};
	}
	return ($start, $end);
}

sub alphaPageBar {
	my $itemsref = shift;
	my $path = shift;
	my $otherparams = shift;
	my $startref = shift; #will be modified
	my $pagebarref = shift; #will be modified
	my $ignorearticles = shift;
	my $skinOverride = shift;
	my $maxcount = shift || Slim::Utils::Prefs::get('itemsPerPage');
	my $itemcount = scalar(@$itemsref);
	my $start = $$startref;
	if (!$start) { 
		$start = 0;
	}
	
	if ($start >= $itemcount) { 
		$start = $itemcount - $maxcount; 
	}
	
	$$startref = $start;
	
	my $end = $itemcount-1;
	if ($itemcount > $maxcount/2) {

		my %pagebar_params = ();
		if (!defined($otherparams)) {
			$otherparams = '';
		}
		$pagebar_params{'otherparams'} =  $otherparams;
		
		my $lastLetter = '';
		my $lastLetterIndex = 0;
		my $pageslist = '';
		$end = -1;

		# This seems very inefficient - we're calling into anchor()
		# and getSortName() more times than we need to be.
		for (my $j = 0; $j < $itemcount; $j++) {

			my $curLetter = anchor(Slim::Utils::Text::getSortName($itemsref->[$j]), $ignorearticles);

			if ($lastLetter ne $curLetter) {

				if (($j - $lastLetterIndex) > $maxcount) {
					if ($end == -1 && $j > $start) {
						$end = $j - 1;
					}
					$lastLetterIndex = $j;
				}

				$pageslist .= ${Slim::Web::HTTP::filltemplatefile('alphapagebarlist.html', {
					'currpage' => ($lastLetterIndex == $start),
					'itemnum0' => $lastLetterIndex,
					'itemnum1' => ($lastLetterIndex + 1),
					'pagenum' => $curLetter,
					'fragment' => ("#" . $curLetter),
					'otherparams' => $otherparams,
					'skinOverride' => $skinOverride,
					'path' => $path
				})};
				
				$lastLetter = $curLetter;
			}
		}
		
		if ($end == -1) {
			$end = $itemcount - 1;
		}

		$pagebar_params{'pageslist'} = $pageslist;
		$pagebar_params{'skinOverride'} = $skinOverride;
		$$pagebarref = ${Slim::Web::HTTP::filltemplatefile("pagebar.html", \%pagebar_params)};
	}
	
	return ($start, $end);
}

sub firmware {
	my ($client, $params) = @_;

	return Slim::Web::HTTP::filltemplatefile("firmware.html", $params);
}

# This is here just to support SDK4.x (version <=10) clients
# so it always sends an upgrade to version 10 using the old upgrade method.
sub update_firmware {
	my ($client, $params) = @_;

	$params->{'warning'} = Slim::Player::Squeezebox::upgradeFirmware($params->{'ipaddress'}, 10) 
		|| string('UPGRADE_COMPLETE_DETAILS');
	
	return Slim::Web::HTTP::filltemplatefile("update_firmware.html", $params);
}

1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
