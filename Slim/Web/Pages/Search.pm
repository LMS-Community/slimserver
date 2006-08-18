package Slim::Web::Pages::Search;

# $Id$

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;

use Date::Parse qw(str2time);
use File::Spec::Functions qw(:ALL);
use Scalar::Util qw(blessed);

use Slim::Player::TranscodingHelper;
use Slim::Utils::DateTime;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Text;
use Slim::Web::Pages;
use Slim::Web::Pages::LiveSearch;

sub init {
	
	Slim::Web::HTTP::addPageFunction( qr/^search\.(?:htm|xml)/, \&basicSearch, 'fork' );
	Slim::Web::HTTP::addPageFunction( qr/^advanced_search\.(?:htm|xml)/, \&advancedSearch, 'fork' );
	
	Slim::Web::Pages->addPageLinks("search", {'SEARCHMUSIC' => "search.html?liveSearch=1"});
	Slim::Web::Pages->addPageLinks("search", {'ADVANCEDSEARCH' => "advanced_search.html"});
}

sub basicSearch {
	my ($client, $params) = @_;

	my $player = $params->{'player'};
	my $query  = $params->{'query'};

	# set some defaults for the template
	$params->{'browse_list'}  = " ";
	$params->{'numresults'}   = -1;
	$params->{'browse_items'} = [];
	$params->{'artwork'}      = 0;

	# short circuit
	if (!defined($query) || ($params->{'manualSearch'} && !$query)) {
		return Slim::Web::HTTP::filltemplatefile("search.html", $params);
	}

	# Don't auto-search for 2 chars, but allow manual search. IE: U2
	if (!$params->{'manualSearch'} && length($query) <= 2) {
		return \'';
	}

	# Don't kill the database - use limit & offsets
	my $types  = [ $params->{'type'} ];
	my $limit  = $params->{'itemPerPage'} || 10;
	my $offset = $params->{'start'} || 0;
	my $search = Slim::Utils::Text::searchStringSplit($query);

	# Default to a valid list of types
	if (!ref($types) || !defined $types->[0]) {

		$types = [ Slim::Schema->searchTypes ];
	}

	my @rsList = ();

	# Create a ResultSet for each of Contributor, Album & Track
	for my $type (@$types) {

		my $rs = Slim::Schema->rs($type)->searchNames($search);
		push @rsList, $rs;
	}

	# The user has hit enter, or has a browser that can't handle the javascript.
	if ($params->{'manualSearch'}) {

		# Tell the template not to do a livesearch request anymore.
		$params->{'liveSearch'} = 0;
		$params->{'path'}       = 'search.html';

		for my $rs (@rsList) {

			fillInSearchResults($params, $rs, [ 'manualSearch=1' ]);
		}

		return Slim::Web::HTTP::filltemplatefile("search.html", $params);

	} else {

		# do it live - and send back the div
		# this should be replaced with a call to filltemplatefile()
		return Slim::Web::Pages::LiveSearch->outputAsXHTML($query, \@rsList, $player);
	}
}

sub advancedSearch {
	my ($client, $params) = @_;

	my $player  = $params->{'player'};
	my %query   = ();
	my @qstring = ();

	# template defaults
	$params->{'browse_list'}  = " ";
	$params->{'liveSearch'}   = 0;
	$params->{'browse_items'} = [];

	# Prep the date format
	$params->{'dateFormat'} = Slim::Utils::DateTime::shortDateF();

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
				$params->{$key} *= 1000;
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
		push @qstring, join('=', $key, Slim::Utils::Misc::escape($params->{$key}));

		# Normalize the string queries
		# 
		# Turn the track_title into track.title for the query.
		# We need the _'s in the form, because . means hash key.
		if ($newKey =~ s/_(titlesearch|namesearch)$/\.$1/) {

			$params->{$key} = { 'like' => Slim::Utils::Text::searchStringSplit($params->{$key}) };
		}

		# Wildcard searches
		if ($newKey =~ /comment/ || $newKey =~ /lyrics/) {

			$params->{$key} = { 'like' => Slim::Utils::Text::searchStringSplit($params->{$key}) };
		}

		$query{$newKey} = $params->{$key};
	}

	# Turn our conversion list into a nice type => name hash.
	my %types  = ();

	for my $type (keys %{ Slim::Player::TranscodingHelper::Conversions() }) {

		$type = (split /-/, $type)[0];

		$types{$type} = string($type);
	}

	$params->{'fileTypes'} = \%types;

	# load up the genres we know about.
	$params->{'genres'}    = Slim::Schema->search('Genre', undef, { 'order_by' => 'namesort' });

	# short-circuit the query
	if (scalar keys %query == 0) {
		$params->{'numresults'} = -1;

		return Slim::Web::HTTP::filltemplatefile("advanced_search.html", $params);
	}

	# Bug: 2479 - Don't include roles if the user has them unchecked.
	my @joins = ();
	my $roles = Slim::Schema->artistOnlyRoles;

	if ($roles || $query{'contributor.namesearch'}) {

		if ($roles) {
			$query{'contributorTracks.role'} = $roles;
		}

		if ($query{'contributor.namesearch'}) {

			push @joins, { 'contributorTracks' => 'contributor' };

		} else {

			push @joins, 'contributorTracks';
		}
	}

	# Pull in the required joins
	if ($query{'genre'}) {

		push @joins, 'genreTracks';
	}

	if ($query{'album.titlesearch'}) {

		push @joins, 'album';
	}

	if ($query{'comments.value'}) {

		push @joins, 'comments';
	}

	# Disambiguate year
	if ($query{'year'}) {
		$query{'me.year'} = delete $query{'year'};
	}

	# XXXX - for some reason, the 'join' key isn't preserved when passed
	# along as a ref. Perl bug because 'join' is a keyword? Use 'joins' as well.
	my %attrs = (
		'order_by' => 'me.disc, me.titlesort',
		'join'     => \@joins,
		'joins'    => \@joins,
	);

	# Create a resultset - have fillInSearchResults do the actual search.
	my $rs  = Slim::Schema->search('Track', \%query, \%attrs);

	if (defined $client && !$params->{'start'}) {

		# stash parameters used to generate this query, so if the user
		# wants to play All Songs, we can run it again, but without
		# keeping all the tracks in memory twice.
		$client->param('searchTrackResults', { 'cond' => \%query, 'attr' => \%attrs });
	}

	fillInSearchResults($params, $rs, \@qstring, 1);

	return Slim::Web::HTTP::filltemplatefile("advanced_search.html", $params);
}

sub fillInSearchResults {
	my ($params, $rs, $qstring, $advancedSearch) = @_;

	my $player = $params->{'player'};
	my $query  = $params->{'query'}  || '';
	my $type   = lc($rs->result_source->source_name) || 'track';
	my $count  = $rs->count || return 0;

	# Set some reasonable defaults
	$params->{'numresults'}   = $count;
	$params->{'itemsPerPage'} ||= Slim::Utils::Prefs::get('itemsPerPage');

	# This is handed to pageInfo to generate the pagebar 1 2 3 >> links.
	my $otherParams = 'player=' . Slim::Utils::Misc::escape($player) . 
			  ($type ?'&type='. $type : '') . 
			  ($query ? '&query=' . Slim::Utils::Misc::escape($query) : '' ) . 
			  '&' .
			  join('&', @$qstring);

	# Put in the type separator
	if (!$advancedSearch && $count) {

		# add reduced item for type headings
		push @{$params->{'browse_items'}}, {
			'numresults' => $count,
			'query'      => $query,
			'heading'    => $type,
			'odd'        => 0,
		};
	}

	# Add in ALL
	if ($count > 1) {

		my $attributes = '';

		if ($advancedSearch) {
			$attributes = sprintf('&searchRef=search%sResults', ucfirst($type));
		} else {
			$attributes = sprintf('&%s.%s=%s', $type, $rs->searchColumn, $query);
		}

		push @{$params->{'browse_items'}}, {
			'text'       => string('ALL_SONGS'),
			'player'     => $params->{'player'},
			'attributes' => $attributes,
			'odd'        => 1,
		};
	}

	# No limit or pagebar on advanced search
	if (!$advancedSearch) {

		my $offset = ($params->{'start'} || 0),
		my $limit  = ($params->{'itemsPerPage'} || 10) - 1;

		$params->{'pageinfo'} = Slim::Web::Pages->pageInfo({

			'itemCount'    => $params->{'numresults'},
			'path'         => $params->{'path'},
			'otherParams'  => $otherParams,
			'start'        => $params->{'start'},
			'perPage'      => $params->{'itemsPerPage'},
		});

		$params->{'start'} = $params->{'pageinfo'}{'startitem'};
	
		# Get just the items we need for this loop.
		$rs = $rs->slice($offset, $limit);
	}

	my $itemCount  = 1;
	my $lastAnchor = '';
	my $descend    = $type eq 'track' ? 0 : 1;

	# This is very similar to a loop in Slim::Web::Pages::BrowseDB....
	while (my $obj = $rs->next) {

		my %form = (
			'levelName'    => $type,
			'hreftype'     => 'browseDb',
			'descend'      => $descend,
			'odd'          => ($itemCount + 1) % 2,
			'skinOverride' => $params->{'skinOverride'},
			'player'       => $params->{'player'},
			'itemobj'      => $obj,
			'level'        => 1,
			'artwork'      => 0,
			'attributes'   => sprintf('&%s.id=%d', $type, $obj->id),
			$type          => $obj->id,
		);

		if ($type eq 'contributor') {

			$form{'attributes'} .= '&contributor.role=ALL';
			$form{'hierarchy'}  = 'contributor,album,track';

		} elsif ($type eq 'album') {

			$form{'hierarchy'} = 'album,track';
		}

		$obj->displayAsHTML(\%form, $descend);

		$itemCount++;

		my $anchor = substr($obj->namesort, 0, 1);

		if ($lastAnchor ne $anchor) {
			$form{'anchor'} = $lastAnchor = $anchor;
		}

		push @{$params->{'browse_items'}}, \%form;
	}
}

1;

__END__
