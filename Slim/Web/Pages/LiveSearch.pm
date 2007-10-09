package Slim::Web::Pages::LiveSearch;

# $Id$

# This is a class that allows us to query the database with "raw" results -
# don't turn them into objects for speed. For the Web UI, we can then return
# the results as XMLish data stream, to be dynamically displayed in a <div>

use strict;

use Scalar::Util qw(blessed);

use Slim::Music::Info;
use Slim::Utils::Strings qw(string);
use Slim::Web::Pages;
use Slim::Utils::Prefs;

use constant MAXRESULTS => 10;

my $prefs = preferences('server');

sub outputAsXHTML {
	my $class   = shift;
	my $query   = shift;
	my $rsList  = shift;
	my $player  = shift;
	my $params  = shift;

	# count overall results
	my $resultcount = 0;

	my @xml = (
		'<?xml version="1.0" encoding="utf-8" ?>',
		'<div id="browsedbList">',
	);
	
	$params->{'itemsPerPage'} = MAXRESULTS;

	for my $rs (@$rsList) {

		my $total  = $rs->count;
		my $type   = lc($rs->result_source->source_name);

		Slim::Web::Pages::Search::fillInSearchResults($params, $rs, []);

		push @xml, map {
			$params->{item} = $_;
			${Slim::Web::HTTP::filltemplatefile("browsedbitems_list.html", $params)};
		} @{ $params->{browse_items} };

		if ($total && $total > MAXRESULTS) {
			push @xml, 
				sprintf("<div class=\"even\">\n<div class=\"browsedbListItem\"><a href=\"search.html?manualSearch=1\&amp;query=%s\&amp;type=%s\&amp;player=%s\">%s</a></div></div>\n",
				$query, $type, $player, Slim::Utils::Strings::string('MORE_MATCHES')
			);
		}
		
		$resultcount += $total;
		
		$params->{browse_items} = undef;
	}

	#no results found
	if (!$resultcount) {
		push@xml, Slim::Utils::Strings::string("NO_SEARCH_RESULTS");
	}


	push @xml, "</div>\n";

	return \join('', @xml);
}


sub outputAsXML {
	my $class   = shift;
	my $query   = shift;
	my $rsList  = shift;
	my $player  = shift;

	my @xml = (
		'<?xml version="1.0" encoding="utf-8" standalone="yes"?>',
		'<livesearch>',
	);

	for my $rs (@$rsList) {

		my $type   = lc($rs->result_source->source_name);
		my $total  = $rs->count;
		my $count  = 0;
		my @output = ();

		while (my $item = $rs->next) {

			if ($count <= MAXRESULTS) {

				push @output, sprintf('<livesearchitem id="%s">%s</livesearchitem>', $item->id, $item->name);
			}

			$count++;
		}

		push @xml, sprintf("<searchresults type=\"%s\" hierarchy=\"%s\" mstring=\"%s &quot;$query&quot;: $total\">", 
			$type,
			$Slim::Web::Pages::hierarchy{$type} || '',
			Slim::Utils::Strings::string(uc($type . 'SMATCHING'))
		);

		push @xml, @output if $count;

		if ($total && $total > MAXRESULTS) {
			push @xml, "<morematches query=\"$query\"/>";
		}

		push @xml, "</searchresults>";
	}

	push @xml, "</livesearch>\n";

	return \join('', @xml);
}
1;

__END__
