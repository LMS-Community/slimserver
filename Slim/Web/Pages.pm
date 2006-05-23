package Slim::Web::Pages;

# $Id$

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;

use File::Spec::Functions qw(:ALL);
use POSIX ();
use Scalar::Util qw(blessed);

use Slim::DataStores::Base;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);

use Slim::Web::Pages::Search;
use Slim::Web::Pages::BrowseDB;
use Slim::Web::Pages::BrowseTree;
use Slim::Web::Pages::Home;
use Slim::Web::Pages::Status;
use Slim::Web::Pages::Playlist;
use Slim::Web::Pages::History;
use Slim::Web::Pages::EditPlaylist;


our %additionalLinks = ();

our %hierarchy = (
	'artist' => 'album,track',
	'album'  => 'track',
	'song '  => '',
);

sub init {

	Slim::Web::HTTP::addPageFunction(qr/^firmware\.(?:html|xml)/,\&firmware);
	Slim::Web::HTTP::addPageFunction(qr/^songinfo\.(?:htm|xml)/,\&songInfo);
	Slim::Web::HTTP::addPageFunction(qr/^setup\.(?:htm|xml)/,\&Slim::Web::Setup::setup_HTTP);
	Slim::Web::HTTP::addPageFunction(qr/^tunein\.(?:htm|xml)/,\&tuneIn);
	Slim::Web::HTTP::addPageFunction(qr/^update_firmware\.(?:htm|xml)/,\&update_firmware);

	# pull in the memory usage module if requested.
	if ($::d_memory) {

		eval "use Slim::Utils::MemoryUsage";

		if ($@) {
			print "Couldn't load Slim::Utils::MemoryUsage - error: [$@]\n";
		} else {
			Slim::Web::HTTP::addPageFunction(qr/^memoryusage\.html.*/,\&memory_usage);
		}
	}

	Slim::Web::Pages::Home->init();
	Slim::Web::Pages::BrowseDB::init();
	Slim::Web::Pages::BrowseTree::init();
	Slim::Web::Pages::Search::init();
	Slim::Web::Pages::Status::init();
	Slim::Web::Pages::EditPlaylist::init(); # must precede Playlist::init();
	Slim::Web::Pages::Playlist::init();
	Slim::Web::Pages::History::init();
}

### DEPRECATED stub for third party plugins
sub addLinks {
	msg("Slim::Web::Pages::addLinks() has been deprecated in favor of 
	     Slim::Web::Pages->addPageLinks. Please update your calls!\n");
	Slim::Utils::Misc::bt();
	
	return Slim::Web::Pages->addPageLinks(@_);
}

sub _lcPlural {
	my ($class, $count, $singular, $plural) = @_;

	# only convert to lowercase if our language does not wand uppercase (default lc)
	my $word = ($count == 1 ? string($singular) : string($plural));
	$word = (string('MIDWORDS_UPPER', '', 1) ? $word : lc($word));
	return sprintf("%s %s", $count, $word);
}

sub addPageLinks {
	my ($class, $category, $links, $noquery) = @_;

	return if (ref($links) ne 'HASH');

	while (my ($title, $path) = each %$links) {
		if (defined($path)) {
			$additionalLinks{$category}->{$title} = $path . 
				($noquery ? '' : (($path =~ /\?/) ? '&' : '?' )); #'
		} else {
			delete($additionalLinks{$category}->{$title});
		}
	}

	if (not keys %{$additionalLinks{$category}}) {
		delete($additionalLinks{$category});
	}
}

sub addLibraryStats {
	my ($class,$params, $genre, $artist, $album) = @_;
	
	if (Slim::Music::Import->stillScanning) {
		$params->{'warn'} = 1;
		return;
	}

	my $ds   = Slim::Music::Info::getCurrentDataStore();
	my $find = {};

	$find->{'genre'}       = $genre  if $genre  && !$album;
	$find->{'contributor'} = $artist if $artist && !$album;
	$find->{'album'}       = $album  if $album;

	if (Slim::Utils::Prefs::get('disableStatistics')) {
		$params->{'song_count'}   = 0;
		$params->{'album_count'}  = 0;
		$params->{'artist_count'} = 0;
	} else {
		$params->{'song_count'}   = $class->_lcPlural($ds->count('track', $find), 'SONG', 'SONGS');
		$params->{'album_count'}  = $class->_lcPlural($ds->count('album', $find), 'ALBUM', 'ALBUMS');
	
		# Bug 1913 - don't put counts for contributor & tracks when an artist
		# is a composer on a different artist's tracks.
		if ($artist && $artist eq $ds->variousArtistsObject->id) {
	
			delete $find->{'contributor'};
	
			$find->{'album.compilation'} = 1;
	
			# Don't display wonked or zero counts when we're working on the meta VA object
			delete $params->{'song_count'};
			delete $params->{'album_count'};
		}
	
		$params->{'artist_count'} = $class->_lcPlural($ds->count('contributor', $find), 'ARTIST', 'ARTISTS');
	}
}

sub addPlayerList {
	my ($class,$client, $params) = @_;

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

		$params->{'player_chooser_list'} = $class->options($client->id(), \%clientlist, $params->{'skinOverride'});
	}
}

sub addSongInfo {
	my ($class, $client, $params, $getCurrentTitle) = @_;

	# 
	my $url = $params->{'itempath'};
	my $id  = $params->{'item'};

	# kinda pointless, but keeping with compatibility
	if (!defined $url && !defined $id) {
		return;
	}

	if (ref($url) && !$url->can('id')) {
		return;
	}

	my $ds = Slim::Music::Info::getCurrentDataStore();
	my $track;

	if ($url) {

		$track = $ds->objectForUrl($url, 1, 1);

	} elsif ($id) {

		$track = $ds->objectForId('track', $id);
		$url   = $track->url() if $track;
	}

	if (blessed($track) && $track->can('filesize')) {

		# let the template access the object directly.
		$params->{'itemobj'}    = $track unless $params->{'itemobj'};

		$params->{'filelength'} = Slim::Utils::Misc::delimitThousands($track->filesize());
		$params->{'bitrate'}    = $track->bitrate();

		if ($getCurrentTitle) {
			$params->{'songtitle'} = Slim::Music::Info::getCurrentTitle(undef, $track);
		} else {
			$params->{'songtitle'} = Slim::Music::Info::standardTitle(undef, $track);
		}

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
			$params->{'coverThumb'} = $track->id;
		}

		if (Slim::Music::Info::isRemoteURL($url)) {

			$params->{'download'} = $url;

		} else {

			$params->{'download'} = sprintf('%smusic/%d/download', $params->{'webroot'}, $track->id());
		}
	}
}

sub songInfo {
	my ($client, $params) = @_;

	_addSongInfo($client, $params, 0);

	return Slim::Web::HTTP::filltemplatefile("songinfo.html", $params);
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

		my $info = $fieldInfo->{$field} || $fieldInfo->{'default'};

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
	# Don't show stats when only showing playlists - extra queries that
	# aren't needed.
	if (!grep { /playlist/ } @levels) {
		addLibraryStats($params, $params->{'genre'}, $params->{'artist'}, $params->{'album'});
	}

	# This pulls the appropriate anonymous function list out of the
	# fieldInfo hash, which we then retrieve data from.
	my $firstLevelInfo = $fieldInfo->{$levels[0]} || $fieldInfo->{'default'};
	my $title = $params->{'browseby'} = $firstLevelInfo->{'title'};

	for my $key (keys %{$fieldInfo}) {

		if (defined($params->{$key})) {

			# Populate the find criteria with all query parameters in the URL
			$findCriteria{$key} = $params->{$key};

			# Skip this for the top level
			next if $key eq 'album.compilation';

			# Pre-populate the attrs list with all query parameters that 
			# are not part of the hierarchy. This allows a URL to put
			# query constraints on a hierarchy using a field that isn't
			# necessarily part of the hierarchy.
			if (!grep {$_ eq $key} @levels) {
				push @attrs, $key . '=' . Slim::Utils::Misc::escape($params->{$key});
			}
		}
	}
	# This gets reused later, during the main item list build
	my %list_form = (
		'player'       => $player,
		'pwditem'      => string($title),
		'skinOverride' => $params->{'skinOverride'},
		'title'	       => $title,
		'hierarchy'    => $hierarchy,
		'level'	       => 0,
		'attributes'   => (scalar(@attrs) ? ('&' . join("&", @attrs)) : ''),
	);

	push @{$params->{'pwd_list'}}, {
		'hreftype'     => 'browseDb',
		'title'	       => string($title),
		'hierarchy'    => $hierarchy,
		'level'	       => 0,
		'attributes'   => (scalar(@attrs) ? ('&' . join("&", @attrs)) : ''),
	};

	# We want to include Compilations in the pwd, so we need the artist,
	# but not in the actual search.
	if ($findCriteria{'artist'} && $findCriteria{'album.compilation'}) {

		delete $findCriteria{'artist'};

		push @attrs, 'album.compilation=1';
	}

	for (my $i = 0; $i < $level ; $i++) {

		my $attr = $levels[$i];

		# XXX - is this the right thing to do?
		# For artwork browsing - we want to display the album.
		if (my $transform = $firstLevelInfo->{'nameTransform'}) {
			$attr = $transform;
		}

		# browsetree might pass this along - we want to keep it in the attrs
		# for the breadcrumbs so cue sheets aren't edited. See bug: 1360
		if (defined $params->{'noEdit'}) {

			push @attrs, join('=', 'noEdit', $params->{'noEdit'});
		}

		if ($params->{$attr}) {

			push @attrs, $attr . '=' . Slim::Utils::Misc::escape($params->{$attr});

			push @{$params->{'pwd_list'}}, {
				 'hreftype' => 'browseDb',
				 'title'      => $names{$attr},
				 'hierarchy'	=> $hierarchy,
				 'level'	=> $i+1,
				 'attributes'   => (scalar(@attrs) ? ('&' . join("&", @attrs)) : ''),
			};

			# Send down the attributes down to the template
			#
			# These may be overwritten below.
			# This is useful/needed for the playlist case where we
			# want access to the containing playlist object.
			$params->{$attr} = $ds->objectForId($attr, $params->{$attr});
		}
	}

	my $otherparams = join('&',
		'player=' . Slim::Utils::Misc::escape($player || ''),
		"hierarchy=$hierarchy",
		"level=$level",
		@attrs,
	);

	my $levelInfo = $fieldInfo->{$levels[$level]} || $fieldInfo->{'default'};
	my $items     = &{$levelInfo->{'find'}}($ds, $levels[$level], \%findCriteria);

	if ($items && scalar(@$items)) {

		my ($start, $end);

		my $ignoreArticles = $levelInfo->{'ignoreArticles'};

		if (defined $params->{'nopagebar'}) {

			($start, $end) = simpleHeader(
				scalar(@$items),
				\$params->{'start'},
				\$params->{'browselist_header'},
				$params->{'skinOverride'},
				$params->{'itemsPerPage'},
				$ignoreArticles ? (scalar(@$items) > 1) : 0,
			);

		} elsif (&{$levelInfo->{'alphaPageBar'}}(\%findCriteria)) {

			my $alphaitems = [ map &{$levelInfo->{'resultToSortedName'}}($_), @$items ];

			($start, $end) = alphaPageBar(
				$alphaitems,
				$params->{'path'},
				$otherparams,
				\$params->{'start'},
				\$params->{'browselist_pagebar'},
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

		#$params->{'browse_list'} .= ${Slim::Web::HTTP::filltemplatefile("browsedb_list.html", \%list_form)};

		$descend = ($level >= $maxLevel) ? undef : 'true';

		if (scalar(@$items) > 1 && !$levelInfo->{'suppressAll'}) {

			if ($params->{'includeItemStats'} && !Slim::Utils::Misc::stillScanning()) {
				# XXX include statistics
			}

			my $nextLevelInfo;

			if ($descend) {
				$nextLevelInfo = $fieldInfo->{ $levels[$level+1] } || $fieldInfo->{'default'};
			} else {
				$nextLevelInfo = $fieldInfo->{'track'};
			}

			if ($level == 0) {

				# Sometimes we want a special transform for
				# the 'All' case - such as New Music.
				#
				# Otherwise we might have a regular descend
				# transform, such as the artwork case.
				if ($levelInfo->{'allTransform'}) {

					 $list_form{'hierarchy'} = $levelInfo->{'allTransform'};

				} elsif ($levelInfo->{'descendTransform'}) {

					 $list_form{'hierarchy'} = $levelInfo->{'descendTransform'};

				} else {

					 $list_form{'hierarchy'} = join(',', @levels[1..$#levels]);
				}

				$list_form{'level'} = 0;

			} else {

				$list_form{'hierarchy'}	= $hierarchy;
				$list_form{'level'}	= $descend ? $level+1 : $level;
			}

			if ($nextLevelInfo->{'allTitle'}) {
				$list_form{'text'} = string($nextLevelInfo->{'allTitle'});
			}

			$list_form{'descend'}      = 1;
			$list_form{'player'}       = $player;
			$list_form{'odd'}	   = ($itemnumber + 1) % 2;
			$list_form{'skinOverride'} = $params->{'skinOverride'};
			$list_form{'attributes'}   = (scalar(@attrs) ? ('&' . join("&", @attrs)) : '');

			# For some queries - such as New Music - we want to
			# get the list of tracks to play from the fieldInfo
			if ($levels[$level] eq 'age' && $levelInfo->{'allTransform'}) {

				$list_form{'attributes'} .= sprintf('&fieldInfo=%s', $levelInfo->{'allTransform'});
			}

			$itemnumber++;

			$params->{'browse_list'} .= ${Slim::Web::HTTP::filltemplatefile("browsedb_list.html", \%list_form)};
		}

		# Dynamic VA/Compilation listing
		if ($levels[$level] eq 'artist' && Slim::Utils::Prefs::get('variousArtistAutoIdentification')) {

			my %list_form  = %$params;
			my $vaObj      = $ds->variousArtistsObject;
			my @attributes = (@attrs, 'album.compilation=1', sprintf('artist=%d', $vaObj->id));

			# Only show VA item if there's valid listings below
			# the current level.
			my %find = map { split /=/ } @attrs, 'album.compilation=1';

			if ($ds->count('album', \%find)) {

				$list_form{'text'}        = $vaObj->name;
				$list_form{'descend'}     = $descend;
				$list_form{'hiearchy'}    = $hierarchy;
				$list_form{'level'}	  = $level + 1;
				$list_form{'odd'}	  = ($itemnumber + 1) % 2;
				$list_form{'attributes'}  = (scalar(@attributes) ? ('&' . join("&", @attributes, )) : '');

				$params->{'browse_list'} .= ${Slim::Web::HTTP::filltemplatefile("browsedb_list.html", \%list_form)};

				$itemnumber++;
			}
		}

		# Don't bother with idle streams if we only have SB2 clients
		my $needIdleStreams = Slim::Player::Client::needIdleStreams();

		for my $item ( @{$items}[$start..$end] ) {

			my %list_form = %$params;

			my $attrName  = $levelInfo->{'nameTransform'} || $levels[$level];

			# We might not be inflated yet...(but skip for years)
			if (!blessed($item) && $item =~ /^\d+$/ && $levels[$level] ne 'year') {

				$item = $ds->objectForId($attrName, $item);
			}

			# The track might have been deleted out from under us.
			# XXX - should we have some sort of error message here?
			if (!defined $item || (blessed($item) && !$item->can('id'))) {

				next;
			}

			my $itemid   = &{$levelInfo->{'resultToId'}}($item);
			my $itemname = &{$levelInfo->{'resultToName'}}($item);
			my $itemsort = &{$levelInfo->{'resultToSortedName'}}($item);

			$list_form{'hierarchy'}	    = $hierarchy;
			$list_form{'level'}	    = $level + 1;
			$list_form{'attributes'}    = (scalar(@attrs) ? ('&' . join("&", @attrs)) : '') . '&' .
				$attrName . '=' . Slim::Utils::Misc::escape($itemid);

			$list_form{'levelName'}	    = $attrName;
			$list_form{'text'}	    = $itemname;
			$list_form{'descend'}	    = $descend;
			$list_form{'odd'}	    = ($itemnumber + 1) % 2;
			$list_form{$levelInfo->{'nameTransform'} || $levels[$level]} = $itemid;
			$list_form{'skinOverride'}  = $params->{'skinOverride'};
			$list_form{'itemnumber'}    = $itemnumber;
			$list_form{'itemobj'}	    = $item;

			# This is calling into the %fieldInfo hash
			&{$levelInfo->{'listItem'}}($ds, \%list_form, $item, $itemname, $descend, \%findCriteria);

			if (defined $itemsort) {

				my $anchor = substr($itemsort, 0, 1);

				if ($lastAnchor ne $anchor) {
					$list_form{'anchor'} = $lastAnchor = $anchor;
				}
			}

			$itemnumber++;

			if ($levels[$level] eq 'artwork') {
				$params->{'browse_list'} .= ${Slim::Web::HTTP::filltemplatefile("browsedb_artwork.html", \%list_form)};
			} else {
				$params->{'browse_list'} .= ${Slim::Web::HTTP::filltemplatefile("browsedb_list.html", \%list_form)};
			}

			if ($needIdleStreams) {
				main::idleStreams();
			}
		}

		if ($level == $maxLevel && $levels[$level] eq 'track') {

			my $track = $items->[$start];

			if ($track->can('coverArt') && $track->coverArt) {

				$params->{'coverArt'} = $track->id;
			}
		}
	}

	# Give players a bit of time.
	main::idleStreams();

	$params->{'descend'} = $descend;

	# override the template for the playlist case.
	my $template = $levelInfo->{'browseBodyTemplate'} || 'browsedb.html';

	return Slim::Web::HTTP::filltemplatefile($template, $params);
}

sub browsetree {
	my ($client, $params) = @_;

	my $hierarchy  = $params->{'hierarchy'} || '';
	my $player     = $params->{'player'};
	my $itemsPer   = $params->{'itemsPerPage'} || Slim::Utils::Prefs::get('itemsPerPage');

	my $ds         = Slim::Music::Info::getCurrentDataStore();
	my @levels     = split(/\//, $hierarchy);
	my $itemnumber = 0;

	# Pull the directory list, which will be used for looping.
	my ($topLevelObj, $items, $count) = Slim::Utils::Misc::findAndScanDirectoryTree(\@levels);

	# Page title
	$params->{'browseby'} = 'MUSIC';

	for (my $i = 0; $i < scalar @levels; $i++) {

		my $obj = $ds->objectForId('track', $levels[$i]);

		if (blessed($obj) && $obj->can('title')) {

			push @{$params->{'pwd_list'}}, {
				'hreftype'     => 'browseTree',
				'title'        => $i == 0 ? string('MUSIC') : $obj->title,
				'hierarchy'    => join('/', @levels[0..$i]),
			};
		}
	}

	my ($start, $end) = (0, $count);

	# Create a numeric pagebar if we need to.
	if ($count > $itemsPer) {

		($start, $end) = pageBar(
			$count,
			$params->{'path'},
			0,
			"hierarchy=$hierarchy&player=$player",
			\$params->{'start'},
			\$params->{'browselist_header'},
			\$params->{'browselist_pagebar'},
			$params->{'skinOverride'},
			$params->{'itemsPerPage'},
		);
	}

	# Setup an 'All' button.
	# I believe this will play only songs, and not playlists.
	if ($count) {
		my %list_form = %$params;

		$list_form{'hierarchy'}	    = undef;
		$list_form{'descend'}	    = 1;
		$list_form{'text'}	    = string('ALL_SONGS');
		$list_form{'itemobj'}	    = $topLevelObj;

		$params->{'browse_list'} .= ${Slim::Web::HTTP::filltemplatefile("browsetree_list.html", \%list_form)};
	}

	#
	my $topPath = $topLevelObj->path;
	my $osName  = Slim::Utils::OSDetect::OS();

	for my $relPath (@$items[$start..$end]) {

		my $url  = Slim::Utils::Misc::fixPath($relPath, $topPath) || next;

		# Amazingly, this just works. :)
		# Do the cheap compare for osName first - so non-windows users
		# won't take the penalty for the lookup.
		if ($osName eq 'win' && Slim::Music::Info::isWinShortcut($url)) {
			$url = Slim::Utils::Misc::fileURLFromWinShortcut($url);
		}

		my $item = $ds->objectForUrl($url, 1, 1, 1);

		if (!blessed($item) || !$item->can('content_type')) {

			next;
		}

		# Bug: 1360 - Don't show files referenced in a cuesheet
		next if ($item->content_type eq 'cur');

		my %list_form = %$params;

		# Turn the utf8 flag on for proper display - since this is
		# coming directly from the filesystem.
		$list_form{'text'}	    = Slim::Utils::Unicode::utf8decode_locale($relPath);

		$list_form{'hierarchy'}	    = join('/', @levels, $item->id);
		$list_form{'descend'}	    = Slim::Music::Info::isList($item) ? 1 : 0;
		$list_form{'odd'}	    = ($itemnumber + 1) % 2;
		$list_form{'itemobj'}	    = $item;

		# Don't display the edit dialog for cue sheets.
		if ($item->isCUE) {
			$list_form{'noEdit'} = '&noEdit=1';
		}

		$itemnumber++;

		$params->{'browse_list'} .= ${Slim::Web::HTTP::filltemplatefile("browsetree_list.html", \%list_form)};

		if (!$params->{'coverArt'} && $item->coverArt) {
			$params->{'coverArt'} = $item->id;
		}
	}

	$params->{'descend'} = 1;
	
	if (Slim::Music::Import->stillScanning) {
		$params->{'warn'} = 1;
	}

	# we might have changed - flush to the db to be in sync.
	$topLevelObj->update;
	
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

	my %queryMap = (
		'genre'  => 'genre.name',
		'artist' => 'artist.name',
		'album'  => 'album.title',
		'track'  => 'track.title'
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
			my $cat = $params->{$category} = (@{$ds->find({

				'field' => $category,
				'find'  => { $queryMap{$category} => $params->{$category} },

			})})[0];

			return browsedb($client, $params) unless $cat;

			$params->{$category} = $cat->id;
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
	my ($class, $item, $suppressArticles) = @_;
	
	if ($suppressArticles) {
		$item = Slim::Utils::Text::ignoreCaseArticles($item) || return '';
	}

	return Slim::Utils::Text::matchCase(substr($item, 0, 1));
}

sub options {
	my ($class, $selected, $option, $skinOverride) = @_;

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
	my ($class, $args) = @_;
	
	my $itemCount    = $args->{'itemCount'};
	my $startRef     = $args->{'startRef'};
	my $headerRef    = $args->{'headerRef'};
	my $skinOverride = $args->{'skinOverride'};
	my $count		 = $args->{'perPage'} || Slim::Utils::Prefs::get('itemsPerPage');
	my $offset		 = $args->{'offset'} || 0;

	my $start = (defined($$startRef) && $$startRef ne '') ? $$startRef : 0;

	if ($start >= $itemCount) {
		$start = $itemCount - $count;
	}

	$$startRef = $start;

	my $end    = $start + $count - 1 - $offset;

	if ($end >= $itemCount) {
		$end = $itemCount - 1;
	}

	# Don't bother with a pagebar on a non-pagable item.
	if ($itemCount < $count) {
		return ($start, $end);
	}

	$$headerRef = ${Slim::Web::HTTP::filltemplatefile("pagebarheader.html", {
		"start"        => $start,
		"end"          => $end,
		"itemcount"    => $itemCount - 1,
		'skinOverride' => $skinOverride
	})};

	return ($start, $end);
}

# Return a hashref with paging information, all list indexes are zero based

# named arguments:
# itemsRef : reference to the list of items
# itemCount : number of items in the list, not needed if itemsRef supplied
# otherParams : used to build the query portion of the url
# path : used to build the path portion of the url
# start : starting index of the displayed page in the list of items
# perPage : items per page to display, preference used by default
# addAlpha : flag determining whether to build the alpha map, requires itemsRef
# currentItem : the index of the "current" item in the list, 
#                if start not supplied this will be used to determine starting page

# Hash keys set:
# startitem : index in list of first item on page
# enditem : index in list of last item on page
# totalitems : number of items in the list
# itemsperpage : number of items on each page
# currentpage : index of current page in list of pages
# totalpages : number of pages of items
# otherparams : as above
# path : as above
# alphamap : hash relating first character of sorted list to the index of the
#             first appearance of that character in the list.
# totalalphapages : total number of pages in alpha pagebar

sub pageInfo {
	my ($class, $args) = @_;
	
	my $itemsref     = $args->{'itemsRef'};
	my $otherparams  = $args->{'otherParams'};
	my $start        = $args->{'start'};
	my $itemsperpage = $args->{'perPage'} || Slim::Utils::Prefs::get('itemsPerPage');

	my %pageinfo = ();
	my $end;
	my $itemcount;

	if ($itemsref && ref($itemsref) eq 'ARRAY') {
		$itemcount = scalar(@$itemsref);
	} else {
		$itemcount = $args->{'itemCount'} || 0;
	}

	if (!$itemsperpage || $itemsperpage > $itemcount) {
		# we divide by this, so make sure it will never be 0
		$itemsperpage = $itemcount || 1;
	}

	if (!defined($start) || $start eq '') {
		if ($args->{'currentItem'}) {
			$start = int($args->{'currentItem'} / $itemsperpage) * $itemsperpage;
		
		} else {
			$start = 0;
		}
	}

	if ($start >= $itemcount) {
		$start = $itemcount - $itemsperpage;
		if ($start < 0) {
			$start = 0;
		}
	}
	
	$end = $start + $itemsperpage - 1;

	if ($end >= $itemcount) {
		$end = $itemcount - 1;
	}

	$pageinfo{'enditem'}      = $end;
	$pageinfo{'totalitems'}   = $itemcount;
	$pageinfo{'itemsperpage'} = $itemsperpage;
	$pageinfo{'currentpage'}  = int($start/$itemsperpage);
	$pageinfo{'totalpages'}   = POSIX::ceil($itemcount/$itemsperpage);
	$pageinfo{'otherparams'}  = defined($otherparams) ? $otherparams : '';
	$pageinfo{'path'}         = $args->{'path'};
	
	if ($args->{'addAlpha'} && $itemcount && $itemsref && ref($itemsref) eq 'ARRAY') {
		my %alphamap = ();
		for my $index (reverse(0..$#$itemsref)) {
			my $curletter = substr($itemsref->[$index],0,1);
			if (defined($curletter) && $curletter ne '') {
				$alphamap{$curletter} = $index;
			}
		}
		my @letterstarts = sort {$a <=> $b} values(%alphamap);
		my @pagestarts = (@letterstarts[0]);
		
		# some cases of alphamap shift the start index from 0, trap this.
		$start = @letterstarts[0] unless $args->{'start'} ;
		
		my $newend = $end;
		for my $nextend (@letterstarts) {
			if ($nextend > $end && $newend == $end) {
				$newend = $nextend - 1;
			}
			if ($pagestarts[0] + $itemsperpage < $nextend) {
				# build pagestarts in descending order
				unshift @pagestarts, $nextend;
			}
		}
		$pageinfo{'enditem'} = $newend;
		$pageinfo{'totalalphapages'} = scalar(@pagestarts);
		KEYLOOP: for my $alphakey (keys %alphamap) {
			my $alphavalue = $alphamap{$alphakey};
			for my $pagestart (@pagestarts) {
				if ($alphavalue >= $pagestart) {
					$alphamap{$alphakey} = $pagestart;
					next KEYLOOP;
				}
			}
		}
		$pageinfo{'alphamap'} = \%alphamap;
	}
	
	# set the start index, accounding for alpha cases
	$pageinfo{'startitem'} = $start;

	return \%pageinfo;
}

# Build a bar of links to multiple pages of items
# Deprecated, use pageInfo instead, and [% PROCESS pagebar %] in the page
sub pageBar {
	my ($class, $args) = @_;
	
	my $itemcount    = $args->{'itemCount'};
	my $path         = $args->{'path'};
	my $currentitem  = $args->{'currentItem'} || 0;
	my $otherparams  = $args->{'otherParams'};
	my $startref     = $args->{'startRef'}; #will be modified
	my $headerref    = $args->{'headerRef'}; #will be modified
	my $pagebarref   = $args->{'pageBarRef'}; #will be modified
	my $skinOverride = $args->{'skinOverride'};
	my $count        = $args->{'PerPage'} || Slim::Utils::Prefs::get('itemsPerPage');

	my $start = (defined($$startref) && $$startref ne '') ? $$startref : (int($currentitem/$count)*$count);

	if ($start >= $itemcount) {
		$start = $itemcount - $count;
	}

	$$startref = $start;

	my $end = $start+$count-1;

	if ($end >= $itemcount) {
		$end = $itemcount - 1;
	}

	# Don't bother with a pagebar on a non-pagable item.
	if ($itemcount < $count) {
		return ($start, $end);
	}

	if ($itemcount > $count) {

		$$headerref = ${Slim::Web::HTTP::filltemplatefile("pagebarheader.html", {
			"start"        => ($start+1),
			"end"          => ($end+1),
			"itemcount"    => $itemcount,
			'skinOverride' => $skinOverride
		})};

		my %pagebar = ();

		my $numpages  = POSIX::ceil($itemcount/$count);
		my $curpage   = int($start/$count);
		my $pagesperbar = 25; #make this a preference
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

# Deprecated, use pageInfo instead, and [% PROCESS pagebar %] in the page
sub alphaPageBar {
	my ($class, $args) = @_;
	
	my $itemsref     = $args->{'itemsRef'};
	my $path         = $args->{'path'};
	my $otherparams  = $args->{'otherParams'};
	my $startref     = $args->{'startRef'}; #will be modified
	my $pagebarref   = $args->{'pageBarRef'}; #will be modified
	my $skinOverride = $args->{'skinOverride'};
	my $maxcount     = $args->{'PerPage'} || Slim::Utils::Prefs::get('itemsPerPage');

	my $itemcount = scalar(@$itemsref);

	my $start = $$startref;

	if (!$start) { 
		$start = 0;
	}

	if ($start >= $itemcount) { 
		$start = $itemcount - $maxcount; 
	}

	$$startref = $start;

	my $end = $itemcount - 1;

	# Don't bother with a pagebar on a non-pagable item.
	if ($itemcount < $maxcount) {
		return ($start, $end);
	}

	if ($itemcount > ($maxcount / 2)) {

		my $lastLetter = '';
		my $lastLetterIndex = 0;
		my $pageslist = '';

		$end = -1;

		# This could be more efficient.
		for (my $j = 0; $j < $itemcount; $j++) {

			my $curLetter = substr($itemsref->[$j], 0, 1);
			$curLetter = '' if (!defined($curLetter));

			if ($lastLetter ne $curLetter) {

				if ($curLetter ne '') {
					
					if (($j - $lastLetterIndex) > $maxcount) {
						if ($end == -1 && $j > $start) {
							$end = $j - 1;
						}
						$lastLetterIndex = $j;
					}

					$pageslist .= ${Slim::Web::HTTP::filltemplatefile('alphapagebarlist.html', {
						'currpage'     => ($lastLetterIndex == $start),
						'itemnum0'     => $lastLetterIndex,
						'itemnum1'     => ($lastLetterIndex + 1),
						'pagenum'      => $curLetter,
						'fragment'     => ("#" . $curLetter),
						'otherparams'  => ($otherparams || ''),
						'skinOverride' => $skinOverride,
						'path'         => $path
						})};
					
					$lastLetter = $curLetter;

				}

			}
		}

		if ($end == -1) {
			$end = $itemcount - 1;
		}

		my %pagebar_params = (
			'otherparams'  => ($otherparams || ''),
			'pageslist'    => $pageslist,
			'skinOverride' => $skinOverride,
		);

		$$pagebarref = ${Slim::Web::HTTP::filltemplatefile("pagebar.html", \%pagebar_params)};
	}
	
	return ($start, $end);
}

## The following are smaller web page handlers, and are not class methods.
##
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

sub songInfo {
	my ($client, $params) = @_;

	Slim::Web::Pages->addSongInfo($client, $params, 0);

	return Slim::Web::HTTP::filltemplatefile("songinfo.html", $params);
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

sub tuneIn {
	my ($client, $params) = @_;
	return Slim::Web::HTTP::filltemplatefile('tunein.html', $params);
}

1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
