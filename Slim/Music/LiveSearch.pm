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
	'song'   => [qw(track track.title)],
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

sub renderAsXML { 
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
					$item->id(),
					($item->can('title') ? $item->title() : $item->name()),
					$player
				);
			}

			$count++;
		}

		push @xml, sprintf("<tr><td><hr width=\"75%%\"><br>%s \"$query\": $count<br><br></td></tr>", 
			Slim::Utils::Strings::string(uc($type . 'SMATCHING'))
		);

		push @xml, @results if $count;

		if ($count && $count > MAXRESULTS) {

			push @xml, sprintf("<tr><td><p>&nbsp;&nbsp;<a href=\"search.html?liveSearch=0&query=%s&type=%s&player=%s\">more matches...</a></p><br></td></tr>\n",
				$query, $type, $player
			);
		}
	}

	push @xml, "</table><br><br>\n";
	my $string = join('', @xml);

	return \$string;
}

sub renderItem {
	my ($rowType, $type, $id, $name, $player) = @_;

	my $hierarchy = $Slim::Web::Pages::hierarchy{$type} || '';

	return <<EOF;
	<tr>
	<td width="100%" class="$rowType">
		<a href="browsedb.html?hierarchy=$hierarchy\&level=0\&$type=$id\&player=$player">$name</a>  
	</td>

	<td align="right" class="$rowType"></td>
	<td align="right" width="13" class="$rowType">

	      <nobr><a href="status_header.html?command=playlist&sub=loadtracks\&$type=$id\&player=$player" target="status">
			<img src="html/images/b_play.gif" width=13 height=13 alt="Play" title="Play"></a></nobr> 

	</td>
	<td  align="right" width="13" class="$rowType">
	      <nobr><a href="status_header.html?command=playlist&sub=addtracks\&$type=$id\&player=$player" target="status">
			<img src="html/images/b_add.gif" width=13 height=13 alt="Add to playlist" title="Add to playlist"></a></nobr> 
	</td>
	</tr>
EOF

}

1;

__END__
