package Slim::Music::LiveSearch;

# $Id$

# This is a class that allows us to query the database with "raw" results -
# don't turn them into objects for speed. For the Web UI, we can then return
# the results as XMLish data stream, to be dynamically displayed in a <div>
#
# Todo - call filltemplate stuff instead? May be too slow.
# Use LIMIT - but then we don't get our "total matches" correct.

use strict;

use Slim::Music::Info;
use Slim::Web::Pages;

use constant MAXRESULTS => 10;

our %queries = (
	'artist' => [qw(contributor contributor.name)],
	'album'  => [qw(album album.title)],
	'track'   => [qw(track track.title)],
);

sub query {
	my $class = shift;
	my $query = shift;
	my $limit = shift;

	my @data  = ();
	my $ds    = Slim::Music::Info->getCurrentDataStore();

	my $search = Slim::Web::Pages::searchStringSplit($query, 0);

	for my $type (keys %queries) {

		push @data, [ $type, [$ds->find($queries{$type}->[0], { $queries{$type}->[1] => $search }, undef, $limit, 0)] ];
	}

	return \@data;
}

sub queryWithLimit {
	my $class = shift;
	my $query = shift;

	return $class->query($query, MAXRESULTS);
}

sub outputAsXHTML { 
	my $class   = shift;
	my $query   = shift;
	my $results = shift;
	my $player  = shift;

	my @xml = (
		'<?xml version="1.0" encoding="utf-8" ?>',
		'<table cellspacing="0" cellpadding="4">',
	);

	for my $result (@$results) {

		my $type    = $result->[0];
		my $data    = $result->[1];
		my $count   = 0;
		my @results = ();

		for my $item (@{$data}) {

			my $rowType = $count % 2 ? 'even' : 'odd';

			if ($count <= MAXRESULTS) {

				push @results, renderItem(
					$rowType,
					$type,
					$item,
					$player
				);
			}

			$count++;
		}

		push @xml, sprintf("<tr><td><hr width=\"75%%\"/><br/>%s \"$query\": $count<br/><br/></td></tr>", 
			Slim::Utils::Strings::string(uc($type . 'SMATCHING'))
		);

		push @xml, @results if $count;

		if ($count && $count > MAXRESULTS) {
			my $rowType = $count % 2 ? 'even' : 'odd';
			push @xml, sprintf("<tr><td class=\"%s\"> <p> <a href=\"search.html?liveSearch=0&amp;query=%s&amp;type=%s&amp;player=%s\">more matches...</a></p><br/></td></tr>\n",
				$rowType, $query, $type, $player
			);
		}
	}

	push @xml, "</table>\n";
	my $string = join('', @xml);

	return \$string;
}

sub renderItem {
	my ($rowType, $type, $item, $player) = @_;

	my $hierarchy = $Slim::Web::Pages::hierarchy{$type} || '';
	my $id = $item->id(),
	my @xml = ();
	
	my $name;
	
	if ($item->can('url')) {
		$name = Slim::Music::Info::standardTitle(undef,$item);
		
		# Starting work on the standard track list format, but its a work in progress.
		#my $webFormat = Slim::Utils::Prefs::getInd("titleFormat",Slim::Utils::Prefs::get("titleFormatWeb"));

		#$name .= ($webFormat !~ /ARTIST/ && $item->can('artist')) ? " by ".$item->artist() : "";
		#$name .= ($webFormat !~ /ALBUM/ && $item->can('album')) ? " from ".$item->album() : "";

	} elsif ($item->can('title')) {
		$name = $item->title();

	} else {
		$name = $item->name();
	}
	
	# We need to handle the different urls that are needed for different result types
	my $url = ($type eq 'track') ? "songinfo.html?item=$id"
		: "browsedb.html?hierarchy=$hierarchy\&amp;level=0\&amp;$type=$id";
	
	push @xml,"<tr>
		<td width=\"100%\" class=\"$rowType\">
			<a href=\"$url\&amp;player=$player\">$name</a>  
		</td>";
		
	push @xml,"<td align=\"right\" class=\"$rowType\"></td>\n
		<td align=\"right\" width=\"13\" class=\"$rowType\">\n

		<nobr><a href=\"status_header.html?command=playlist&amp;sub=loadtracks\&amp;$type=$id\&amp;player=$player\" target=\"status\">\n
		<img src=\"html/images/b_play.gif\" width=\"13\" height=\"13\" alt=\"Play\" title=\"Play\"/></a></nobr>\n\n

		</td>
		<td  align=\"right\" width=\"13\" class=\"$rowType\">\n
			<nobr><a href=\"status_header.html?command=playlist&amp;sub=addtracks\&amp;$type=$id\&amp;player=$player\" target=\"status\">\n
			<img src=\"html/images/b_add.gif\" width=\"13\" height=\"13\" alt=\"Add to playlist\" title=\"Add to playlist\"/></a></nobr> \n
		</td>\n
		</tr>\n";

	my $string = join('', @xml);

	return $string;
}

sub outputAsXML { 
	my $class   = shift;
	my $query   = shift;
	my $results = shift;
	my $player  = shift;

	my @xml = (
		'<?xml version="1.0" encoding="utf-8" standalone="yes"?>',
		'<livesearch>',
	);

	for my $result (@$results) {

		my $type    = $result->[0];
		my $data    = $result->[1];
		my $count   = 0;
		my @results = ();

		for my $item (@{$data}) {

			my $rowType = $count % 2 ? 'even' : 'odd';
			if ($count <= MAXRESULTS) {

				push @results, sprintf('<livesearchitem id="%s">%s</livesearchitem>',
					$item->id(),
					($item->can('title') ? $item->title() : $item->name()),
				);
			}

			$count++;
		}


		push @xml, sprintf("<searchresults type=\"%s\" hierarchy=\"%s\" mstring=\"%s &quot;$query&quot;: $count\">", 
			$type,
			$Slim::Web::Pages::hierarchy{$type} || '',
			Slim::Utils::Strings::string(uc($type . 'SMATCHING'))
		);

		push @xml, @results if $count;

		if ($count && $count > MAXRESULTS) {
			push @xml, "<morematches query=\"$query\"/>";
		}

		push @xml, "</searchresults>";
	}

	push @xml, "</livesearch>\n";
	my $string = join('', @xml);

	return \$string;
}

1;

__END__
