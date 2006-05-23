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

use Slim::DataStores::Base;
use Slim::Music::LiveSearch;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use Slim::Web::Pages;

sub init {
	
	Slim::Web::HTTP::addPageFunction(qr/^search\.(?:htm|xml)/,\&basicSearch);
	Slim::Web::HTTP::addPageFunction(qr/^advanced_search\.(?:htm|xml)/,\&advancedSearch);
	
	Slim::Web::Pages::Home->addPageLinks("search", {'SEARCH' => "search.html?liveSearch=1"});
	Slim::Web::Pages::Home->addPageLinks("search", {'ADVANCEDSEARCH' => "advanced_search.html"});
}

sub basicSearch {
	my ($client, $params) = @_;

	my $player = $params->{'player'};
	my $query  = $params->{'query'};

	# set some defaults for the template
	$params->{'browse_list'} = " ";
	$params->{'numresults'}  = -1;
	$params->{'itemsPerPage'} ||= Slim::Utils::Prefs::get('itemsPerPage');

	# short circuit
	if (!defined($query) || ($params->{'manualSearch'} && !$query)) {
		return Slim::Web::HTTP::filltemplatefile("search.html", $params);
	}

	# Don't auto-search for 2 chars, but allow manual search. IE: U2
	if (!$params->{'manualSearch'} && length($query) <= 2) {
		return \'';
	}

	# Don't kill the database - use limit & offsets
	my $data = Slim::Music::LiveSearch->queryWithLimit($query, [ $params->{'type'} ], $params->{'itemsPerPage'}, $params->{'start'});

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

		if (defined $client && scalar @results) {

			$client->param('searchResults', @results);
		}

		return Slim::Web::HTTP::filltemplatefile("search.html", $params);
	}

	# do it live - and send back the div
	if ($params->{'xmlmode'}) {
		return Slim::Music::LiveSearch->outputAsXML($query, $data, $player);
	} else {
		return Slim::Music::LiveSearch->outputAsXHTML($query, $data, $player);
	}
}

sub advancedSearch {
	my ($client, $params) = @_;

	my $player  = $params->{'player'};
	my %query   = ();
	my @qstring = ();
	my $ds      = Slim::Music::Info::getCurrentDataStore();

	# template defaults
	$params->{'browse_list'} = " ";
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
		push @qstring, join('=', $key, Slim::Utils::Misc::escape($params->{$key}));

		# Normalize the string queries
		# 
		# Turn the track_title into track.title for the query.
		# We need the _'s in the form, because . means hash key.
		if ($newKey =~ s/_(titlesearch|namesearch)$/\.$1/) {

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
	$params->{'genres'}    = $ds->find({
		'field'  => 'genre',
		'sortBy' => 'genre',
	});

	# short-circuit the query
	if (scalar keys %query == 0) {
		$params->{'numresults'}  = -1;
		return Slim::Web::HTTP::filltemplatefile("advanced_search.html", $params);
	}

	# Do the actual search
	my $results = $ds->find({
		'field'  => 'track',
		'find'   =>  \%query,
		'sortBy' => 'title',
	});

	$client->param('searchResults', $results) if defined $client;

	fillInSearchResults($params, $results, undef, \@qstring, $ds);

	return Slim::Web::HTTP::filltemplatefile("advanced_search.html", $params);
}

sub fillInSearchResults {
	my ($params, $results, $descend, $qstring, $ds) = @_;

	my $player = $params->{'player'};
	my $query  = $params->{'query'}  || '';
	my $type   = $params->{'type'}   || 'track';

	$params->{'type'} = $type;
	
	my $otherParams = 'player=' . Slim::Utils::Misc::escape($player) . 
			  '&type=' . ($type ? $type : ''). 
			  '&query=' . Slim::Utils::Misc::escape($query) . '&' .
			  join('&', @$qstring);

	# Make sure that we have something to show.
	if (!defined $params->{'numresults'} && defined $results && ref($results) eq 'ARRAY') {

		$params->{'numresults'} = scalar @$results;
	}

	# put in the type separator
	if ($type && !$ds) {

		$params->{'browse_list'} .= sprintf("<tr><td><hr width=\"75%%\"/><br/>%s \"$query\": %d<br/><br/></td></tr>",
			Slim::Utils::Strings::string(uc($type . 'SMATCHING')), $params->{'numresults'},
		);
	}

	if ($params->{'numresults'}) {

		my ($start, $end);

		if (defined $params->{'nopagebar'}) {

			($start, $end) = Slim::Web::Pages->simpleHeader({
					'itemCount'    => $params->{'numresults'},
					'startRef'     => \$params->{'start'},
					'headerRef'    => \$params->{'browselist_header'},
					'skinOverride' => $params->{'skinOverride'},
					'perPage'        => $params->{'itemsPerPage'},
				}
			);

		} else {

			($start, $end) = Slim::Web::Pages->pageBar({
					'itemCount'    => $params->{'numresults'},
					'path'         => $params->{'path'},
					'otherParams'  => $otherParams,
					'startRef'     => \$params->{'start'},
					'headerRef'    => \$params->{'searchlist_header'},
					'pageBarRef'   => \$params->{'searchlist_pagebar'},
					'skinOverride' => $params->{'skinOverride'},
					'perPage'      => $params->{'itemsPerPage'},
				}
			);
		}
		
		my $itemnumber = 0;
		my $lastAnchor = '';

		for my $item (@$results) {

			next unless defined $item && ref($item);

			# Contributor/Artist uses name, Album & Track uses title.
			my $title     = $item->can('title')     ? $item->title()     : $item->name();
			my $sorted    = $item->can('titlesort') ? $item->titlesort() : $item->namesort();
			my %list_form = %$params;

			$list_form{'attributes'}   = '&' . join('=', $type, $item->id());
			$list_form{'descend'}      = $descend;
			$list_form{'odd'}          = ($itemnumber + 1) % 2;

			if ($type eq 'track') {
				
				# if $ds is undefined here, make sure we have it now.
				$ds = Slim::Music::Info::getCurrentDataStore() unless $ds;
				
				# If we can't get an object for this url, skip it, as the
				# user's database is likely out of date. Bug 863
				my $itemObj = $item;

				if (!blessed($itemObj) || !$itemObj->can('id')) {

					$itemObj = $ds->objectForUrl($item);
				}

				if (!blessed($itemObj) || !$itemObj->can('id')) {

					next;
				}
				
				my $fieldInfo = Slim::DataStores::Base->fieldInfo;
				my $itemname = &{$fieldInfo->{$type}->{'resultToName'}}($itemObj);

				&{$fieldInfo->{$type}->{'listItem'}}($ds, \%list_form, $itemObj, $itemname, 0);

			} else {
				if ($type eq 'artist') {
					$list_form{'hierarchy'}	   = 'artist,album,track';
					$list_form{'level'}        = 1;
				} elsif ($type eq 'album') {
					$list_form{'hierarchy'}	   = 'album,track';
					$list_form{'level'}        = 1;				
				}
				
				$list_form{'text'} = $title;
			}

			$itemnumber++;

			my $anchor = substr($sorted, 0, 1);

			if ($lastAnchor ne $anchor) {
				$list_form{'anchor'} = $lastAnchor = $anchor;
			}

			$params->{'browse_list'} .= ${Slim::Web::HTTP::filltemplatefile("browsedb_list.html", \%list_form)};
			push @{$params->{'browse_items'}}, \%list_form;
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

			push @strings, "\*$string\*";

		} else {

			push @strings, [ "$string\*", "\* $string\*" ];
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
