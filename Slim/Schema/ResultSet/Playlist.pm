package Slim::Schema::ResultSet::Playlist;

# $Id$

use strict;
use base qw(Slim::Schema::ResultSet::Base);

use Scalar::Util qw(blessed);
use Slim::Utils::Prefs;

sub clearExternalPlaylists {
	my $self = shift;
	my $url  = shift;

	# We can specify a url prefix to only delete certain types of external
	# playlists - ie: only iTunes, or only MusicIP.
	for my $track ($self->getPlaylists('external')) {

		# XXX - exception should go here. Comming soon.
		if (!blessed($track) || !$track->can('url')) {
			next;
		}

		$track->delete if (defined $url ? $track->url =~ /^$url/ : 1);
	}

	Slim::Schema->forceCommit;
}

# Get the playlists
# param $type is 'all' for all playlists, 'internal' for internal playlists
# 'external' for external playlists. Default is 'all'.
# param $search is a search term on the playlist title.
sub getPlaylists {
	my $self   = shift;
	my $type   = shift || 'all';
	my $search = shift;
	my $library_id = shift;

	my @playlists = ();

	if ($type eq 'all' || $type eq 'internal') {
		push @playlists, $Slim::Music::Info::suffixes{'playlist:'};
	}

	# Don't search for playlists if the plugin isn't enabled.
	if ($type eq 'all' || $type eq 'external') {

		for my $importer (qw(itunes musicip)) {
	
			my $prefs = preferences("plugin.$importer");
	
			if ($prefs->get($importer)) {
	
				push @playlists, $Slim::Music::Info::suffixes{sprintf('%splaylist:', $importer)};
			}
		}
	}

	return () unless (scalar @playlists);

	my $sql      = 'SELECT tracks.id FROM tracks ';
	my $w        = [];
	my $p        = [];

	if ( $search && ref $search && ref $search->[0] eq 'ARRAY' ) {
		unshift @{$w}, '(' . join( ' OR ', map { 'tracks.titlesearch LIKE ?' } @{ $search->[0] } ) . ')';
		unshift @{$p}, @{ $search->[0] };
	}
	elsif ( $search && ref $search ) {
		unshift @{$w}, 'tracks.titlesearch LIKE ?';
		unshift @{$p}, @{$search};
	}
	elsif ( $search && Slim::Schema->canFulltextSearch ) {
		Slim::Plugin::FullTextSearch::Plugin->createHelperTable({
			name   => 'playlistSearch',
			search => $search,
			type   => 'playlist',
		});
		
		$sql = 'SELECT tracks.id FROM playlistSearch, tracks ';
		unshift @$w, "tracks.id = playlistSearch.id";
	}
	elsif (defined $search) {
		push @$w, 'tracks.titlesearch LIKE ? ';
		push @$p, $search;
	}
	
	if ($library_id) {
		# create temporary table with playlist IDs available in this library
		# we could do this at scan time, but playlists can change often
		my $dbh = Slim::Schema->dbh;

		my $name = 'library_playlists_' . $library_id;
		
		$dbh->do('DROP TABLE IF EXISTS ' . $name);
		
		# include non-local playlist items like remote http:// streams etc.
		$dbh->do(qq(
			CREATE TEMPORARY TABLE $name AS 
				SELECT DISTINCT playlist_track.playlist AS playlist_id

				FROM playlist_track
				LEFT OUTER JOIN tracks ON tracks.url = playlist_track.track
				LEFT OUTER JOIN library_track ON library_track.track = tracks.id
				
				WHERE playlist_track.track NOT LIKE 'file:/%' OR (library_track.track = tracks.id AND library_track.library = '$library_id')
		));
		
		$sql .= ", $name ";
		push @$w, "tracks.id IN (SELECT playlist_id FROM $name)";
	}

	push @$w, 'tracks.content_type IN (' . join(',', map { "'$_'" } @playlists) . ') ';

	if ( @{$w} ) {
		$sql .= 'WHERE ';
		my $s .= join( ' AND ', @{$w} );
		$s =~ s/\%/\%\%/g;
		$sql .= $s . ' ';
	}

	# Add search criteria for playlists
	my $collate = Slim::Utils::OSDetect->getOS()->sqlHelperClass()->collate();
	my $rs = $self->search_literal(
		"id IN ($sql)", 
		@$p, 
		{ 'order_by' => "titlesort $collate" }
	);

	return wantarray ? $rs->all : $rs;
}

sub objectForUrl {
	my $self = shift;
	my $args = shift;

	$args->{'playlist'} = 1;

	return Slim::Schema->objectForUrl($args);
}

sub updateOrCreate {
	my $self = shift;
	my $args = shift;

	$args->{'playlist'} = 1;

	return Slim::Schema->updateOrCreate($args);
}

1;
