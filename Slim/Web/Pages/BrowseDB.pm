package Slim::Web::Pages::BrowseDB;

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
use Slim::Web::Pages;

our $fieldInfo;

sub init {
	
	$fieldInfo = Slim::DataStores::Base->fieldInfo;
	
	Slim::Web::HTTP::addPageFunction(qr/^browsedb\.(?:htm|xml)/,\&browsedb);
	Slim::Web::HTTP::addPageFunction(qr/^browseid3\.(?:htm|xml)/,\&browseid3);
	
	Slim::Web::Pages::Home->addPageLinks("browse",{'BROWSE_BY_ARTIST' => "browsedb.html?hierarchy=artist,album,track&level=0"});
	Slim::Web::Pages::Home->addPageLinks("browse",{'BROWSE_BY_GENRE'  => "browsedb.html?hierarchy=genre,artist,album,track&level=0"});
	Slim::Web::Pages::Home->addPageLinks("browse",{'BROWSE_BY_ALBUM'  => "browsedb.html?hierarchy=album,track&level=0"});
	Slim::Web::Pages::Home->addPageLinks("browse",{'BROWSE_BY_YEAR'   => "browsedb.html?hierarchy=year,album,track&level=0"});
	Slim::Web::Pages::Home->addPageLinks("browse",{'BROWSE_NEW_MUSIC' => "browsedb.html?hierarchy=age,track&level=0"});
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
		Slim::Web::Pages->addLibraryStats($params, $params->{'genre'}, $params->{'artist'}, $params->{'album'});
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
	
			($start, $end) = Slim::Web::Pages->simpleHeader({
					'itemCount'    => scalar(@$items),
					'startRef'     => \$params->{'start'},
					'headerRef'    => \$params->{'browselist_header'},
					'skinOverride' => $params->{'skinOverride'},
					'perPage'        => $params->{'itemsPerPage'},
					'offset'       => $ignoreArticles ? (scalar(@$items) > 1) : 0,
				}
			);

		} elsif (&{$levelInfo->{'alphaPageBar'}}(\%findCriteria)) {

			my $alphaitems = [ map &{$levelInfo->{'resultToSortedName'}}($_), @$items ];

			($start, $end) = Slim::Web::Pages->alphaPageBar({
					'itemsRef'    => $alphaitems,,
					'path'         => $params->{'path'},
					'otherParams'  => $otherparams,
					'startRef'     => \$params->{'start'},
					'pageBarRef'   => \$params->{'browselist_pagebar'},
					'skinOverride' => $params->{'skinOverride'},
					'perPage'      => $params->{'itemsPerPage'},
				}
			);

		} else {

			($start, $end) = Slim::Web::Pages->pageBar({
					'itemCount'    => scalar(@$items),
					'path'         => $params->{'path'},
					'otherParams'  => $otherparams,
					'startRef'     => \$params->{'start'},
					'headerRef'    => \$params->{'browselist_header'},
					'pageBarRef'   => \$params->{'browselist_pagebar'},
					'skinOverride' => $params->{'skinOverride'},
					'perPage'      => $params->{'itemsPerPage'},
				}
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
			$list_form{'hreftype'}     = 'browseDb';
			$list_form{'player'}       = $player;
			$list_form{'odd'}          = ($itemnumber + 1) % 2;
			$list_form{'skinOverride'} = $params->{'skinOverride'};
			$list_form{'attributes'}   = (scalar(@attrs) ? ('&' . join("&", @attrs)) : '');

			# For some queries - such as New Music - we want to
			# get the list of tracks to play from the fieldInfo
			if ($levels[$level] eq 'age' && $levelInfo->{'allTransform'}) {

				$list_form{'attributes'} .= sprintf('&fieldInfo=%s', $levelInfo->{'allTransform'});
			}

			$itemnumber++;

			push @{$params->{'browse_items'}}, \%list_form;
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
				$list_form{'hreftype'}    = 'browseDb';
				$list_form{'hiearchy'}    = $hierarchy;
				$list_form{'level'}       = $level + 1;
				$list_form{'odd'}         = ($itemnumber + 1) % 2;
				$list_form{'attributes'}  = (scalar(@attributes) ? ('&' . join("&", @attributes, )) : '');

				push @{$params->{'browse_items'}}, \%list_form;

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

			$list_form{'hierarchy'}     = $hierarchy;
			$list_form{'level'}         = $level + 1;
			$list_form{'levelName'}     = $attrName;
			$list_form{'text'}          = $itemname;
			$list_form{'hreftype'}      = 'browseDb';
			$list_form{'descend'}       = $descend;
			$list_form{'odd'}	        = ($itemnumber + 1) % 2;
			$list_form{'skinOverride'}  = $params->{'skinOverride'};
			$list_form{'itemnumber'}    = $itemnumber;
			$list_form{'itemobj'}       = $item;
			$list_form{'attributes'}    = (scalar(@attrs) ? ('&' . join("&", @attrs)) : '') . '&' .
				$attrName . '=' . Slim::Utils::Misc::escape($itemid);

			$list_form{$levelInfo->{'nameTransform'} || $levels[$level]} = $itemid;

			# This is calling into the %fieldInfo hash
			&{$levelInfo->{'listItem'}}($ds, \%list_form, $item, $itemname, $descend, \%findCriteria);

			if (defined $itemsort) {

				my $anchor = substr($itemsort, 0, 1);

				if ($lastAnchor ne $anchor) {
					$list_form{'anchor'} = $lastAnchor = $anchor;
				}
			}

			$itemnumber++;

			push @{$params->{'browse_items'}}, \%list_form;

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

1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
