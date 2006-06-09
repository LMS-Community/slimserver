package Slim::Web::Pages::Search;

# $Id$

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;

use Date::Parse qw(str2time);
use File::Spec::Functions qw(:ALL);
use POSIX ();
use Scalar::Util qw(blessed);

use Slim::Player::TranscodingHelper;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use Slim::Web::Pages;
use Slim::Web::Pages::LiveSearch;

sub init {
	
	Slim::Web::HTTP::addPageFunction(qr/^search\.(?:htm|xml)/,\&basicSearch);
	Slim::Web::HTTP::addPageFunction(qr/^advanced_search\.(?:htm|xml)/,\&advancedSearch);
	
	Slim::Web::Pages->addPageLinks("search", {'SEARCHMUSIC' => "search.html?liveSearch=1"});
	Slim::Web::Pages->addPageLinks("search", {'ADVANCEDSEARCH' => "advanced_search.html"});
}

sub basicSearch {
	my ($client, $params) = @_;

	my $player = $params->{'player'};
	my $query  = $params->{'query'};

	# set some defaults for the template
	$params->{'browse_list'} = " ";
	$params->{'numresults'}  = -1;
	$params->{'itemsPerPage'} ||= Slim::Utils::Prefs::get('itemsPerPage');
	$params->{'browse_items'} = [];

	# short circuit
	if (!defined($query) || ($params->{'manualSearch'} && !$query)) {
		return Slim::Web::HTTP::filltemplatefile("search.html", $params);
	}

	# Don't auto-search for 2 chars, but allow manual search. IE: U2
	if (!$params->{'manualSearch'} && length($query) <= 2) {
		return \'';
	}

	# Don't kill the database - use limit & offsets
	my $data = Slim::Web::Pages::LiveSearch->queryWithLimit($query, [ $params->{'type'} ], $params->{'itemsPerPage'}, $params->{'start'});

	# The user has hit enter, or has a browser that can't handle the javascript.
	if ($params->{'manualSearch'}) {

		# Tell the template not to do a livesearch request anymore.
		$params->{'liveSearch'} = 0;

		my @results = ();
		my $descend = 1;
		my @qstring = ('manualSearch=1');

		for my $item (@$data) {

			$params->{'type'}       = $item->[0];
			$params->{'numresults'} = $item->[1];
			$params->{'path'}       = 'search.html';

			if ($params->{'type'} eq 'track' && $params->{'numresults'}) {

				push @results, $item->[2];

				$descend = undef;
			}

			fillInSearchResults($params, $item->[2], $descend, \@qstring);
		}

		if (defined $client && scalar @results && !$params->{'start'}) {
			# stash the full resultset if not paging through the results
			# assumes that when the start parameter is 0 or undefined that
			# the query has just been run
			my $fulldata = Slim::Web::Pages::LiveSearch->query($query, [ 'track' ]);
			$client->param('searchResults', $fulldata->[0][2]);
		}

		return Slim::Web::HTTP::filltemplatefile("search.html", $params);
	}

	# do it live - and send back the div
	if ($params->{'xmlmode'}) {
		return Slim::Web::Pages::LiveSearch->outputAsXML($query, $data, $player);
	} else {
		return Slim::Web::Pages::LiveSearch->outputAsXHTML($query, $data, $player);
	}
}

sub advancedSearch {
	my ($client, $params) = @_;

	my $player  = $params->{'player'};
	my %query   = ();
	my @qstring = ();

	# template defaults
	$params->{'browse_list'} = " ";
	$params->{'liveSearch'}  = 0;
	$params->{'browse_items'} = [];
	$params->{'itemsPerPage'} ||= Slim::Utils::Prefs::get('itemsPerPage');

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

			$params->{$key} = { 'like' => searchStringSplit($params->{$key}) };
		}

		# Wildcard comment searches
		if ($newKey =~ /comment/) {

			$params->{$key} = "\*$params->{$key}\*";
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
		$params->{'numresults'}  = -1;
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

	if ($query{'album.titlesearch'}) {

		push @joins, 'album';
	}

	# Do the actual search
	my $rs    = Slim::Schema->search('Track',
		\%query,
		{ 'order_by' => 'titlesort', 'join' => \@joins }
	);

	my $count = $rs->count;

	my $start = ($params->{'start'} || 0),
	my $end   = $params->{'itemsPerPage'};

	if (defined $client && !$params->{'start'}) {

		# stash the full resultset if not paging through the results
		# assumes that when the start parameter is 0 or undefined that
		# the query has just been run
		$client->param('searchResults', [ $rs->all ]);

		$rs->reset;
	}

	if ($count == $params->{'itemsPerPage'}) {

		$params->{'numresults'} = $count;
	}
	
	fillInSearchResults($params, [ $rs->slice($start, $end) ], undef, \@qstring, 1);

	return Slim::Web::HTTP::filltemplatefile("advanced_search.html", $params);
}

sub fillInSearchResults {
	my ($params, $results, $descend, $qstring, $typeSeparator) = @_;

	my $player = $params->{'player'};
	my $query  = $params->{'query'}  || '';
	my $type   = $params->{'type'}   || 'track';

	$params->{'type'} = $type;
	
	my $otherParams = 'player=' . Slim::Utils::Misc::escape($player) . 
			  ($type ?'&type='. $type : '') . 
			  ($query ? '&query=' . Slim::Utils::Misc::escape($query) : '' ) . 
			  '&' .
			  join('&', @$qstring);

	# Make sure that we have something to show.
	if (!defined $params->{'numresults'} && defined $results && ref($results) eq 'ARRAY') {

		$params->{'numresults'} = scalar @$results;
	}

	# put in the type separator
	if ($type && !$typeSeparator) {

		# add reduced item for type headings
		push @{$params->{'browse_items'}}, {
			'numresults' => $params->{'numresults'},
			'query'   => $query,
			'heading' => $type,
		};
	}

	my ($start, $end);

	if ($params->{'numresults'}) {

		$params->{'pageinfo'} = Slim::Web::Pages->pageInfo({

			'itemCount'    => $params->{'numresults'},
			'path'         => $params->{'path'},
			'otherParams'  => $otherParams,
			'start'        => $params->{'start'},
			'perPage'      => $params->{'itemsPerPage'},
		});

		$start = $params->{'start'} = $params->{'pageinfo'}{'startitem'};
		$end   = $params->{'pageinfo'}{'enditem'};
		
		my $itemnumber = 1;
		my $lastAnchor = '';

		for my $item (@$results) {

			next unless defined $item && ref($item);

			# Contributor/Artist uses name, Album & Track uses title.
			my %form = %$params;

			$form{'attributes'} = '&' . join('.id=', $type, $item->id);
			$form{'descend'}    = $descend;
			$form{'odd'}        = ($itemnumber) % 2;

			if ($type eq 'track') {
				
				# If we can't get an object for this url, skip it, as the
				# user's database is likely out of date. Bug 863
				my $itemObj = $item;

				if (!blessed($itemObj) || !$itemObj->can('id')) {

					$itemObj = Slim::Schema->rs('Track')->objectForUrl($item);
				}

				if (!blessed($itemObj) || !$itemObj->can('id')) {

					next;
				}

				$itemObj->displayAsHTML(\%form, 0);

			} else {

				if ($type eq 'contributor') {

					$form{'hierarchy'} = 'contributor,album,track';
					$form{'level'}     = 1;
					$form{'hreftype'}  = 'browseDb';

				} elsif ($type eq 'album') {

					$form{'hierarchy'} = 'album,track';
					$form{'level'}     = 1;
					$form{'hreftype'}  = 'browseDb';
				}
				
				$form{'text'} = $item->name;
			}

			$itemnumber++;

			my $anchor = substr($item->namesort, 0, 1);

			if ($lastAnchor ne $anchor) {
				$form{'anchor'} = $lastAnchor = $anchor;
			}

			push @{$params->{'browse_items'}}, \%form;
		}
	}
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

			push @strings, "\%$string\%";

		} else {

			push @strings, [ "$string\%", "\% $string\%" ];
		}
	#}

	return \@strings;
}

1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
