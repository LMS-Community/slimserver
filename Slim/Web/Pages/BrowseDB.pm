package Slim::Web::Pages::BrowseDB;

# $Id$

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use Scalar::Util qw(blessed);
use Storable;

use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use Slim::Web::Pages;

sub init {

	Slim::Web::HTTP::addPageFunction( qr/^browsedb\.(?:htm|xml)/, \&browsedb, 'fork' );
	Slim::Web::HTTP::addPageFunction( qr/^browseid3\.(?:htm|xml)/, \&browseid3, 'fork' );

	Slim::Web::Pages->addPageLinks("browse", {'BROWSE_BY_ARTIST' => "browsedb.html?hierarchy=contributor,album,track&level=0" });
	Slim::Web::Pages->addPageLinks("browse", {'BROWSE_BY_GENRE'  => "browsedb.html?hierarchy=genre,contributor,album,track&level=0" });
	Slim::Web::Pages->addPageLinks("browse", {'BROWSE_BY_ALBUM'  => "browsedb.html?hierarchy=album,track&level=0" });
	Slim::Web::Pages->addPageLinks("browse", {'BROWSE_BY_YEAR'   => "browsedb.html?hierarchy=year,album,track&level=0" });
	Slim::Web::Pages->addPageLinks("browse", {'BROWSE_NEW_MUSIC' => "browsedb.html?hierarchy=age,track&level=0" });
}

sub browsedb {
	my ($client, $params) = @_;

	my $hierarchy = $params->{'hierarchy'} || 'track';
	my $level     = $params->{'level'} || 0;
	my $orderBy   = $params->{'orderBy'};
	my $player    = $params->{'player'};
	my $artwork   = $params->{'artwork'};

	# validate hierarchy, converting invalid hierarchies to 'track'
	my $validHierarchies = Slim::Schema->validHierarchies;

	if (!exists $validHierarchies->{lc($hierarchy)}) {

		$hierarchy = 'track';

		$::d_info && msg("browsedb - invalid hierarchy: $hierarchy\n");
	}

	$::d_info && msg("browsedb - hierarchy: $hierarchy level: $level\n");

	# code further down expects the lcfirst version of the levels
	my @levels = map { lcfirst($_) } split(',', $validHierarchies->{lc($hierarchy)});

	# Make sure we're not out of bounds.
	my $maxLevel = scalar(@levels) - 1;

	if ($level > $maxLevel)	{
		$level = $maxLevel;
	}

	my $itemCount = 0;
	my $levelName = $levels[$level];

	# Set the orderBy if requested
	if ($levelName eq 'album') {

		if (Slim::Utils::Prefs::get('sortBrowseArt') && !$orderBy) {

			$orderBy = Slim::Utils::Prefs::get('sortBrowseArt');
		}

	} elsif ($levelName ne 'track') {

		$orderBy = '';
	}

	# Build up a list of params to include in the href links.
	my @attrs    = ();

	my $rs       = Slim::Schema->rs($levelName);
	my $topRS    = Slim::Schema->rs($levels[0]);
	my $title    = $params->{'browseby'} = $topRS->title;

	# XXXX - sort is not currently generated or used.
	# The orderBy is used by the artwork/album sorting feature.
	my ($filters, $cond, $sort) = $topRS->generateConditionsFromFilters({
		'rs'      => $rs,
		'level'   => $level,
		'levels'  => \@levels,
		'params'  => $params,
	});

	# This hash is reused later, during the main item list build
	my %form = (
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
		'orderBy'      => $orderBy,
		'attributes'   => (scalar(@attrs) ? ('&' . join("&", @attrs)) : ''),
	};

	# We want to include Compilations in the pwd, so we need the artist,
	# but not in the actual search.
	if (defined $filters->{'contributor.id'} && 
	    defined $filters->{'album.compilation'} && $filters->{'album.compilation'} == 1) {

		delete $filters->{'contributor.id'};

		push @attrs, 'album.compilation=1';
	}

	# browsetree might pass this along - we want to keep it in the attrs
	# for the breadcrumbs so cue sheets aren't edited. See bug: 1360
	if (defined $params->{'noEdit'}) {

		push @attrs, join('=', 'noEdit', $params->{'noEdit'});
	}

	# editplaylist might pass this along - we want to keep it in the attrs
	# for the pagebar and pwd_list so that we don't go into edit mode. Bug 2870
	if (defined $params->{'saveCurrentPlaylist'}) {

		push @attrs, join('=', 'saveCurrentPlaylist', $params->{'saveCurrentPlaylist'});
	}

	# Generate the breadcrumb list for the current level.
	for (my $i = 0; $i < $level ; $i++) {

		my $attr = $levels[$i];

		# XXXX ick.
		if ($attr eq 'year') {
			$attr = 'album.year';
		}

		for my $levelKey (grep { /^$attr/ } keys %{$params}) {

			# Bug 3776 - because album & year are the same view,
			# skip the album.year key when we're at the album level.
			if ($levels[$i] eq 'album' && $levelKey eq 'album.year') {
				next;
			}

			# Send down the attributes down to the template
			#
			# These may be overwritten below.
			# This is useful/needed for the playlist case where we
			# want access to the containing playlist object.
			my $value = $params->{$levelKey};

			# Don't search for years, we just use the string.
			if ($levelKey eq 'album.year') {

				# Special case Unknown Years
				if (!$value) {
					$value = string('UNK');
				}

			} else {

				my $searchKey = $levelKey;
				my $rs        = Slim::Schema->rs($attr);

				if ($searchKey =~ /^(\w+)\.(\w+)$/) {

					$searchKey = sprintf('%s.%s', $rs->{'attrs'}{'alias'}, $2);
				}

				my $obj = $rs->search({ $searchKey => $value })->single;

				if (blessed($obj) && $obj->can('name')) {
					$params->{$attr} = $obj;
					$value           = $obj->name;
				}
			}

			push @attrs, join('=', $levelKey, $params->{$levelKey});

			push @{$params->{'pwd_list'}}, {
				 'hreftype'     => 'browseDb',
				 'title'        => $value,
				 'hierarchy'    => $hierarchy,
				 'level'        => $i+1,
				 'orderBy'      => $orderBy,
				 'attributes'   => (scalar(@attrs) ? ('&' . join("&", @attrs)) : ''),
			}
		}
	}
	
	# Bug 3311, disable editing for iTunes, MoodLogic, and MusicMagic playlists
	if (ref $params->{'playlist'}) {

		if ($params->{'playlist'}->content_type =~ /(?:itu|mlp|mmp)/) {

			$params->{'noEdit'} = 1;
		}
	}

	my $otherparams = join('&',
		'player=' . Slim::Utils::Misc::escape($player || ''),
		"hierarchy=$hierarchy",
		"level=$level",
		@attrs,
	);

	if (defined $orderBy) {
		$otherparams .= '&' . "orderBy=$orderBy";
	}

	if (defined $artwork) {
		$otherparams .= '&' . "artwork=$artwork";
	}

	my $browseRS = $topRS->descend($filters, $cond, $orderBy, @levels[0..$level])->distinct;
	my $count    = 0;
	my $start    = 0;
	my $end      = 0;

	my $descend  = ($level >= $maxLevel) ? undef : 'true';

	if ($browseRS) {

		# Force the limit if we're going by age.
		if ($levelName eq 'age') {
			$browseRS = $browseRS->slice(0, (Slim::Utils::Prefs::get('browseagelimit') - 1));
		}

		$count = $browseRS->count;
	}

	# This will get filled in with our returned data from the DB, and handed to the Templates
	$params->{'browse_items'} = [];

	if ($count) {
		my $alphaitems;

		if (!defined $params->{'nopagebar'} && $rs->alphaPageBar($orderBy)) {

			$alphaitems = $browseRS->pageBarResults($orderBy);
		}

		$params->{'pageinfo'} = Slim::Web::Pages->pageInfo({
			'results'      => $alphaitems ? $alphaitems : $browseRS,
			'addAlpha'     => defined $alphaitems,
			'path'         => $params->{'path'},
			'otherParams'  => $otherparams,
			'start'        => $params->{'start'},
			'perPage'      => $params->{'itemsPerPage'},
		});

		$start = $params->{'start'} = $params->{'pageinfo'}{'startitem'};
		$end   = $params->{'pageinfo'}{'enditem'};
	}

	# Generate the 'All $noun' link based on the next level down.
	if ($count && $count > 1 && !$rs->suppressAll) {

		my $nextLevelRS;

		if ($descend) {
			$nextLevelRS = Slim::Schema->rs($levels[$level+1]);
		} else {
			$nextLevelRS = Slim::Schema->rs('Track');
		}

		if ($level == 0) {

			# Sometimes we want a special transform for
			# the 'All' case - such as New Music.
			#
			# Otherwise we might have a regular descend
			# transform, such as the artwork case.
			if ($rs->allTransform) {

				$form{'hierarchy'} = $rs->allTransform;

			} elsif ($rs->descendTransform) {

				$form{'hierarchy'} = $rs->descendTransform;

			} else {

				$form{'hierarchy'} = join(',', @levels[1..$#levels]);
			}

			$form{'level'} = 0;

		} else {

			$form{'hierarchy'} = $hierarchy;
			$form{'level'}	   = $descend ? $level+1 : $level;
		}

		if ($nextLevelRS->allTitle) {
			$form{'text'} = string($nextLevelRS->allTitle);
		}

		$form{'descend'}      = 1;
		$form{'hreftype'}     = 'browseDb';
		$form{'player'}       = $player;
		$form{'orderBy'}      = $nextLevelRS->orderBy;
		$form{'odd'}          = ($itemCount + 1) % 2;
		$form{'skinOverride'} = $params->{'skinOverride'};
		$form{'attributes'}   = (scalar(@attrs) ? ('&' . join("&", @attrs)) : '');

		# For some queries - such as New Music - we want to
		# get the list of tracks to play from the fieldInfo
		if ($levelName eq 'age' && $rs->allTransform) {

			$form{'attributes'} .= sprintf('&fieldInfo=%s', $rs->allTransform);
		}

		$itemCount++;

		push @{$params->{'browse_items'}}, \%form;
	}

	# Dynamic VA/Compilation listing
	if ($levelName eq 'contributor' && Slim::Utils::Prefs::get('variousArtistAutoIdentification')) {

		# Only show VA item if there's valid listings below the current level.
		my %find = map { split /=/ } @attrs;

		if (Slim::Schema->variousArtistsAlbumCount(\%find)) {

			my $vaObj      = Slim::Schema->variousArtistsObject;
			my @attributes = (@attrs, 'album.compilation=1', sprintf('contributor.id=%d', $vaObj->id));

			push @{$params->{'browse_items'}}, {
				'text'        => $vaObj->name,
				'descend'     => $descend,
				'hreftype'    => 'browseDb',
				'hierarchy'   => $hierarchy,
				'level'       => $level + 1,
				'orderBy'     => $orderBy,
				'odd'         => ($itemCount + 1) % 2,
				'attributes'  => (scalar(@attributes) ? ('&' . join("&", @attributes, )) : ''),
			};

			$itemCount++;
		}
	}

	main::idleStreams();

	if ($count) {

		my $lastAnchor = '';
		my $attrName   = lc($levelName);
		my $firstItem  = undef;

		for my $item ($browseRS->slice($start, $end)) {

			main::idleStreams();

			# The track might have been deleted out from under us.
			# XXX - should we have some sort of error message here?
			if (!$item->in_storage) {
				next;
			}

			my $itemid = $item->id;

			my %form = (
				'hierarchy'    => $hierarchy,
				'level'        => $level + 1,
				'orderBy'      => $orderBy,
				'levelName'    => $attrName,
				'text'         => $item->name,
				'hreftype'     => 'browseDb',
				'descend'      => $descend,
				'odd'          => ($itemCount + 1) % 2,
				'skinOverride' => $params->{'skinOverride'},
				'itemobj'      => $item,
				$attrName      => $itemid,
			);

			# If we're at the track level - only append the track
			# id for each item - it's a unique value and doesn't
			# need any joins.
			if (lc($levelName) eq 'track') {

				$form{'attributes'}    = sprintf('&%s.id=%d', $attrName, $itemid);

			} elsif (lc($levelName) eq 'year') {

				$form{'attributes'}    = sprintf('&album.year=%d', ($item->year || 0));

			} else {

				$form{'attributes'}    = (scalar(@attrs) ? ('&' . join('&', @attrs)) : '') . '&' .
					sprintf('%s.id=%d', $attrName, $itemid);
			}

			$item->displayAsHTML(\%form, $descend, $orderBy);

			if (my $itemsort = $item->namesort) {

				my $anchor = substr($itemsort, 0, 1);

				if ($lastAnchor ne $anchor) {
					$form{'anchor'} = $lastAnchor = $anchor;
				}
			}

			$itemCount++;

			# Save the first item so we don't need to refetch it for artwork.
			$firstItem ||= $item;

			push @{$params->{'browse_items'}}, \%form;
		}

		# If we're at the track level, and it's at the bottom of the
		# hierarchy, display cover art if we have it.
		if ($level == $maxLevel && $levelName eq 'track' && defined $firstItem 
			&& (defined $params->{'album.id'} || defined $params->{'age.id'})
		) {

			if ($firstItem->can('coverArt') && $firstItem->coverArt) {

				$params->{'coverArt'} = $firstItem->id;
			}
		}
	}

	# Give players a bit of time.
	main::idleStreams();

	$params->{'descend'}   = $descend;
	$params->{'levelName'} = lc($levelName);

	# Don't show stats when only showing playlists - extra queries that aren't needed.
	#
	# Pass in the current result set, and the previous level.
	if (!grep { /playlist/ } @levels) {

		Slim::Web::Pages->addLibraryStats($params, $browseRS, $levels[$level-1]);
	}

	# override the template for the playlist case.
	my $template = $rs->browseBodyTemplate || 'browsedb.html';

	return Slim::Web::HTTP::filltemplatefile($template, $params);
}

# Implement browseid3 in terms of browsedb.
sub browseid3 {
	my ($client, $params) = @_;

	my @hierarchy  = ();
	my %categories = (
		'genre'  => 'genre',
		'artist' => 'contributor',
		'album'  => 'album',
		'song'   => 'track'
	);

	my %queryMap = (
		'genre'       => 'me.name',
		'contributor' => 'me.name',
		'album'       => 'me.title',
		'track'       => 'me.title',
	);

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
			my $cat = $params->{$category} = Slim::Schema->single($category, {
				$queryMap{$category} => $params->{$category},
			});

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
