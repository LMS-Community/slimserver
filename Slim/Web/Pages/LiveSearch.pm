package Slim::Web::Pages::LiveSearch;

# $Id$

# This is a class that allows us to query the database with "raw" results -
# don't turn them into objects for speed. For the Web UI, we can then return
# the results as XMLish data stream, to be dynamically displayed in a <div>
#
# Todo - call filltemplate stuff instead? May be too slow.
# Use LIMIT - but then we don't get our "total matches" correct.

use strict;

use Slim::Music::Info;
use Slim::Utils::Strings qw(string);
use Slim::Web::Pages;

use constant MAXRESULTS => 10;

my @allTypes = qw(artist album track);

our %queries = (
	'artist' => [qw(contributor me.namesearch)],
	'album'  => [qw(album me.titlesearch)],
	'track'  => [qw(track me.titlesearch)],
);

sub query {
	my ($class, $query, $types, $limit, $offset) = @_;

	my @data   = ();
	my $search = Slim::Web::Pages::Search::searchStringSplit($query);

	# Default to a valid list of types
	if (!ref($types) || !defined $types->[0]) {

		$types = \@allTypes;
	}

	for my $type (@$types) {

		my $find = {
			$queries{$type}->[1] => $search,
		};

		# Don't do an unneeded join for albums & tracks.
		# Also we want to search across all artists - so don't limit
		# based on the compilation bit.
		if ($type eq 'artist') {

			if (my $roles = Slim::Schema->artistOnlyRoles) {

				#$find->{'contributor.role'} = $roles;
			}

			# $find->{'album.compilation'} = undef;
		}

		my $rs      = Slim::Schema->rs($queries{$type}->[0])->search_like($find);
		my $count   = $rs->count;
		my @results = ();

		if ($count) {

			@results = $rs->slice($offset, $limit);
		}

		push @data, [ $type, $count, \@results ];
	}

	return \@data;
}

sub queryWithLimit {
	my ($class, $query, $types, $limit, $offset) = @_;

	return $class->query($query, $types, ($limit || MAXRESULTS), ($offset || 0));
}

sub outputAsXHTML { 
	my $class   = shift;
	my $query   = shift;
	my $results = shift;
	my $player  = shift;

	my @xml = (
		'<?xml version="1.0" encoding="utf-8" ?>',
		'<div id="browsedbList">',
	);

	for my $result (@$results) {

		my $type   = $result->[0];
		my $total  = $result->[1];
		my $data   = $result->[2];
		my $count  = 0;
		my @output = ();

		next unless ref($data);

		for my $item (@{$data}) {

			if ($count <= MAXRESULTS) {

				my $rowType = $count % 2 ? 'even' : 'odd';

				push @output, renderItem(
					$rowType,
					$type,
					$item,
					$player
				);
			}

			$count++;
		}

		push @xml, sprintf("<div class=\"even\">\n<div class=\"browsedbListItem\"><hr width=\"75%%\"/><br/>%s \"$query\": $total<br/><br/></div></div>", 
			Slim::Utils::Strings::string(uc($type . 'SMATCHING'))
		);

		push @xml, @output if $count;

		if ($total && $total > MAXRESULTS) {
			push @xml, sprintf("<div class=\"even\">\n<div class=\"browsedbListItem\"><a href=\"search.html?manualSearch=1&amp;query=%s&amp;type=%s&amp;player=%s\">%s</a></p></div></div>\n",
				$query, $type, $player, Slim::Utils::Strings::string('MORE_MATCHES')
			);
		}
	}

	push @xml, "</div>\n";
	my $string = join('', @xml);

	return \$string;
}

sub renderItem {
	my ($rowType, $type, $item, $player) = @_;

	my $id = $item->id(),
	my @xml = ();
	
	my $name   = '';
	my $album  = '';
	my $artist = '';

	# Track case, followed by album & artist.
	if ($item->can('url')) {

		$name = Slim::Music::Info::standardTitle(undef, $item) || '';
		
		# Starting work on the standard track list format, but its a work in progress.
		my $webFormat = Slim::Utils::Prefs::getInd("titleFormat",Slim::Utils::Prefs::get("titleFormatWeb")) || '';

		# This is rather redundant from Pages.pm
		if ($webFormat !~ /ARTIST/ && $item->can('artist') && $item->artist) {

			$artist = sprintf(
				' %s <a href="browsedb.html?hierarchy=contributor,album,track&level=1&contributor.id=%d\&amp;player=%s">%s</a>',
				string('BY'), $item->artist->id(), $player, $item->artist()
			);
		}

		if ($webFormat !~ /ALBUM/ && $item->can('album') && $item->album) {

			$album = sprintf(
				' %s <a href="browsedb.html?hierarchy=album,track&level=1&album.id=%d\&amp;player=%s">%s</a>',
				string('FROM'), $item->album->id(), $player, $item->album()
			);
		}

	} else {

		$name = $item->name;
	}

	# We need to handle the different urls that are needed for different result types
	my $url;

	if ($type eq 'track') {

		$url = "songinfo.html?item=$id";

	} elsif ($type eq 'album') {

		$url = "browsedb.html?hierarchy=album,track\&amp;level=1\&amp;album.id=$id";

	} elsif ($type eq 'artist') {

		$url = "browsedb.html?hierarchy=artist,album,track\&amp;level=1\&amp;contributor.id=$id";
	}

	push @xml,"<div class=\"$rowType\">\n<div class=\"browsedbListItem\">
			<a href=\"$url\&amp;player=$player\">$name</a>$artist $album";

	push @xml,"<div class=\"browsedbControls\">

		<a href=\"status_header.html?command=playlist&amp;subcommand=loadtracks\&amp;$type.id=$id\&amp;player=$player\" target=\"status\">\n
		<img src=\"html/images/b_play.gif\" width=\"13\" height=\"13\" alt=\"Play\" title=\"Play\"/></a>\n\n

		<a href=\"status_header.html?command=playlist&amp;subcommand=addtracks\&amp;$type.id=$id\&amp;player=$player\" target=\"status\">\n
		<img src=\"html/images/b_add.gif\" width=\"13\" height=\"13\" alt=\"Add to playlist\" title=\"Add to playlist\"/></a> \n
		</div>\n</div>\n</div>\n";

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

		my $type   = $result->[0];
		my $total  = $result->[1];
		my $data   = $result->[2];
		my $count  = 0;
		my @output = ();

		for my $item (@{$data}) {

			my $rowType = $count % 2 ? 'even' : 'odd';
			if ($count <= MAXRESULTS) {

				push @output, sprintf('<livesearchitem id="%s">%s</livesearchitem>',
					$item->id, $item->name,
				);
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
	my $string = join('', @xml);

	return \$string;
}

1;

__END__
