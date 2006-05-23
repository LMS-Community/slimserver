package Slim::Web::Pages::BrowseDB;

# $Id$

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;

use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use Slim::Web::Pages;

sub init {

	Slim::Web::HTTP::addPageFunction(qr/^browsedb\.(?:htm|xml)/,\&browsedb);
	Slim::Web::HTTP::addPageFunction(qr/^browseid3\.(?:htm|xml)/,\&browseid3);

	Slim::Web::Pages->addPageLinks("browse", {'BROWSE_BY_ARTIST' => "browsedb.html?hierarchy=contributor,album,track&level=0" });
	Slim::Web::Pages->addPageLinks("browse", {'BROWSE_BY_GENRE'  => "browsedb.html?hierarchy=genre,contributor,album,track&level=0" });
	Slim::Web::Pages->addPageLinks("browse", {'BROWSE_BY_ALBUM'  => "browsedb.html?hierarchy=album,track&level=0" });
	Slim::Web::Pages->addPageLinks("browse", {'BROWSE_BY_YEAR'   => "browsedb.html?hierarchy=year,album,track&level=0" });
	Slim::Web::Pages->addPageLinks("browse", {'BROWSE_NEW_MUSIC' => "browsedb.html?hierarchy=age,track&level=0" });
}

sub browsedb {
	my ($client, $params) = @_;

	# XXX - why do we default to genre?
	my $hierarchy = $params->{'hierarchy'} || "genre";
	my $level     = $params->{'level'} || 0;
	my $player    = $params->{'player'};

	$::d_info && msg("browsedb - hierarchy: $hierarchy level: $level\n");

	# Turn any artist into a contributor
	my @levels = map {
		$_ = ($_ eq 'artist' ? 'contributor' : $_);
	} split(',', $hierarchy);

	# Make sure we're not out of bounds.
	my $maxLevel = scalar(@levels) - 1;

	if ($level > $maxLevel)	{
		$level = $maxLevel;
	}

	my $itemCount = 0;

	# Hold the real name of the level for the breadcrumb list.
	my %names    = ();

	# Build up a list of params to include in the href links.
	my @attrs    = ();

	# Pass these to the ->descend method
	my %find     = ();
	#my %sort     = ();

	# Filters builds up the list of params passed that we want to filter
	# on. They are massaged into the %find hash.
	my %filters  = ();
	my @sources  = map { lc($_) } Slim::Schema->sources;

	my $rs       = Slim::Schema->rs($levels[$level]);
	my $topRS    = Slim::Schema->rs($levels[0]);
	my $title    = $params->{'browseby'} = $topRS->title;

	# Create a map pointing to the previous RS for each level.
	# 
	# Example: For the navigation from Genres to Contributors, the
	# hierarchy would be:
	# 
	# genre,contributor,album,track
	# 
	# we want the key in the level above us in order to descend.
	#
	# Which would give us: $find->{'genre'} = { 'contributor.id' => 33 }
	my %levelMap = ();

	for (my $i = 1; $i < scalar @levels; $i++) {

		$levelMap{ lc($levels[$i-1]) } = lc($levels[$i]);
	}

	# Build up the list of valid parameters we may pass to the db.
	while (my ($param, $value) = each %{$params}) {

		if (!grep { $param =~ /^$_(\.\w+)?$/ } @sources) {

			next;
		}

		$filters{$param} = $value;
	}

	print Data::Dumper::Dumper(\%levelMap);
	print Data::Dumper::Dumper(\%filters);

	# Turn parameters in the form of: album.sort into the appropriate sort
	# string. We specify a sortMap to turn something like:
	# tracks.timestamp desc, tracks.disc, tracks.titlesort
	while (my ($param, $value) = each %filters) {

		if ($param =~ /^(\w+)\.sort$/) {

			#$sort{$1} = $sortMap{$value} || $value;
			#$sort{$1} = $value;

			delete $filters{$param};
		}
	}

	# Now turn each filter we have into the find hash ref we'll pass to ->descend
	while (my ($param, $value) = each %filters) {

		my ($levelName) = ($param =~ /^(\w+)\.\w+$/);

		# Turn into me.* for the top level
		if ($param =~ /^$levels[0]\.(\w+)$/) {
			$param = sprintf('%s.%s', $topRS->{'attrs'}{'alias'}, $1);
		}

		# Turn into me.* for the current level
		if ($param =~ /^$levels[$level]\.(\w+)$/) {
			$param = sprintf('%s.%s', $rs->{'attrs'}{'alias'}, $1);
		}

		msg("working on levelname: [$levelName]\n");

		if (my $mapKey = $levelMap{$levelName}) {

			$find{$mapKey} = { $param => $value };
		}

		# Pre-populate the attrs list with all query parameters that 
		# are not part of the hierarchy. This allows a URL to put
		# query constraints on a hierarchy using a field that isn't
		# necessarily part of the hierarchy.
		if (!grep { $_ eq $levelName } @levels) {

			push @attrs, join('=', $param, $value);
		}
	}

	# Build up the names we use for the breadcrumb list
	for my $field (@levels) {

		my $levelRS = Slim::Schema->rs($field) || next;

		# XXX - is this the right thing to do?
		# For artwork browsing - we want to display the album.
		if (my $transform = $levelRS->nameTransform) {
			push @levels, $transform;
		}

		my $attrKey = sprintf('%s.id', $field);

		# If we don't have this check, we'll create a massive query
		# for each level in the hierarchy, even though it's not needed
		next unless defined $params->{$attrKey};

		if (my $obj = $levelRS->find($params->{$attrKey})) {

			$names{$field} = $obj->name;
		}
	}

	# Just go directly to the params.
	# Don't show stats when only showing playlists - extra queries that
	# aren't needed.
	if (!grep { /playlist/ } @levels) {
		Slim::Web::Pages->addLibraryStats($params, $params->{'genre.id'}, $params->{'contributor.id'}, $params->{'album.id'});
	}

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
		'attributes'   => (scalar(@attrs) ? ('&' . join("&", @attrs)) : ''),
	};

	# We want to include Compilations in the pwd, so we need the artist,
	# but not in the actual search.
	if ($find{'contributor.id'} && $find{'album.compilation'}) {

		delete $find{'contributor.id'};

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

		# XXX - is this the right thing to do?
		# For artwork browsing - we want to display the album.
		if (my $transform = $topRS->nameTransform) {
			$attr = $transform;
		}

		my $lcKey   = lc($attr);
		my $attrKey = sprintf('%s.id', $lcKey);

		if ($params->{$attrKey}) {

			push @attrs, join('=', $attrKey, $params->{$attrKey});

			push @{$params->{'pwd_list'}}, {
				 'hreftype'     => 'browseDb',
				 'title'        => $names{$lcKey},
				 'hierarchy'    => $hierarchy,
				 'level'        => $i+1,
				 'sort'         => $sort,
				 'attributes'   => (scalar(@attrs) ? ('&' . join("&", @attrs)) : ''),
			};

			# Send down the attributes down to the template
			#
			# These may be overwritten below.
			# This is useful/needed for the playlist case where we
			# want access to the containing playlist object.
			$params->{$attr} = Slim::Schema->find(ucfirst($attr), $params->{$attrKey});
		}
	}

	my $otherparams = join('&',
		'player=' . Slim::Utils::Misc::escape($player || ''),
		"hierarchy=$hierarchy",
		"level=$level",
		@attrs,
	);

	if (defined $sort) {
		$otherparams .= '&' . "sort=$sort";
	}

	msg("find:\n");
	print Data::Dumper::Dumper(\%find);
	msg("running resultset on: $levels[$level]\n");

	#my $browseRS = $topRS->descend(\%find, \%sort, @levels[0..$level])->distinct;
	my $browseRS = $topRS->descend(\%find, {}, @levels[0..$level])->distinct;
	my $count    = 0;
	my $start    = 0;
	my $end      = 0;

	my $descend  = ($level >= $maxLevel) ? undef : 'true';

	if ($browseRS) {
		$count = $browseRS->count;
	}

	# Don't bother with idle streams if we only have SB2 clients
	my $needIdleStreams = Slim::Player::Client::needIdleStreams();

	# This will get filled in with our returned data from the DB, and handed to the Templates
	$params->{'browse_items'} = [];

	if ($count) {
		my $alphaitems;

		if (!defined $params->{'nopagebar'} && $rs->alphaPageBar) {

			$alphaitems = $browseRS->pageBarResults;
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

		# Generate the 'All $noun' link based on the next level down.
		if ($count > 1 && !$rs->suppressAll) {

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

				# Sometimes we want a special transform for
				# the 'All' case - such as New Music.
				#
				# Otherwise we might have a regular descend
				# transform, such as the artwork case.
				if ($rs->allTransform) {

			$form{'hierarchy'} = $hierarchy;
			$form{'level'}	   = $descend ? $level+1 : $level;
		}

		if ($nextLevelRS->allTitle) {
			$form{'text'} = string($nextLevelRS->allTitle);
		}

		$form{'descend'}      = 1;
		$form{'hreftype'}     = 'browseDb';
		$form{'player'}       = $player;
		$form{'sort'}         = $sort;
		$form{'odd'}          = ($itemCount + 1) % 2;
		$form{'skinOverride'} = $params->{'skinOverride'};
		$form{'attributes'}   = (scalar(@attrs) ? ('&' . join("&", @attrs)) : '');

		# For some queries - such as New Music - we want to
		# get the list of tracks to play from the fieldInfo
		if ($levels[$level] eq 'age' && $rs->allTransform) {

			$form{'attributes'} .= sprintf('&fieldInfo=%s', $rs->allTransform);
		}

		$itemCount++;

		push @{$params->{'browse_items'}}, \%form;
	}

				$form{'hierarchy'} = $hierarchy;
				$form{'level'}	   = $descend ? $level+1 : $level;
			}

		my $vaObj      = Slim::Schema->variousArtistsObject;
		my @attributes = (@attrs, 'album.compilation=1', sprintf('artist=%d', $vaObj->id));

		# Only show VA item if there's valid listings below
		# the current level.
		my %find = map { split /=/ } @attrs, 'me.compilation=1';

		if (Slim::Schema->count('Album', \%find)) {

			push @{$params->{'browse_items'}}, {
				'text'        => $vaObj->name,
				'descend'     => $descend,
				'hreftype'    => 'browseDb',
				'hierarchy'   => $hierarchy,
				'level'       => $level + 1,
				'sort'        => $sort,
				'odd'         => ($itemCount + 1) % 2,
				'attributes'  => (scalar(@attributes) ? ('&' . join("&", @attributes, )) : ''),
			};

			$itemCount++;
		}
	}

	if ($count) {

		my $lastAnchor      = '';

		for my $item ($browseRS->slice($start, $end)) {

			# The track might have been deleted out from under us.
			# XXX - should we have some sort of error message here?
			if (!$item->in_storage) {
				next;
			}

			my $attrName = $rs->nameTransform || lc($levels[$level]);
			my $itemid   = $item->id;

			my %form = (
				'hierarchy'    => $hierarchy,
				'level'        => $level + 1,
				'sort'         => $sort,
				'levelName'    => $attrName,
				'text'         => $item->name,
				'hreftype'     => 'browseDb',
				'descend'      => $descend,
				'odd'          => ($itemCount + 1) % 2,
				'skinOverride' => $params->{'skinOverride'},
				'itemobj'      => $item,
				$attrName      => $itemid,
			);

			# XXXX - need to generate attributes for the current
			# RS's value. So album.year - not year.id
			$form{'attributes'}    = (scalar(@attrs) ? ('&' . join('&', @attrs)) : '') . '&' .
				sprintf('%s.id=%d', $attrName, $itemid);

			$item->displayAsHTML(\%form, $descend, $sort);

			if (my $itemsort = $item->namesort) {

				my $anchor = substr($itemsort, 0, 1);

				if ($lastAnchor ne $anchor) {
					$form{'anchor'} = $lastAnchor = $anchor;
				}
			}

			$itemCount++;

			push @{$params->{'browse_items'}}, \%form;

			if ($needIdleStreams) {
				main::idleStreams();
			}
		}

		# If we're at the track level, and it's at the bottom of the
		# hierarchy, display cover art if we have it.
		if ($level == $maxLevel && $levels[$level] eq 'track') {

			my $track = $browseRS->first;

			if ($track->can('coverArt') && $track->coverArt) {

				$params->{'coverArt'} = $track->id;
			}
		}
	}

	# Give players a bit of time.
	main::idleStreams();

	$params->{'descend'} = $descend;

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
			my $cat = $params->{$category} = Slim::Schema->search($category, {
				$queryMap{$category} => $params->{$category},
			})->single;

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
