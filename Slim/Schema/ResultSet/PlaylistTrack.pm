package Slim::Schema::ResultSet::PlaylistTrack;

# $Id$

use strict;
use base qw(Slim::Schema::ResultSet::Track);

sub getTracks {
	my $self        = shift;
	my $playlist_id = shift;
	my $library_id  = shift;

	my $librarySQL = '';
	my @p = ($playlist_id);
	
	if ($library_id) {
		$librarySQL = qq( AND me.track IN (
			SELECT playlist_track.track
			
			FROM playlist_track
			LEFT OUTER JOIN tracks ON tracks.url = playlist_track.track
			LEFT OUTER JOIN library_track ON library_track.track = tracks.id
			
			WHERE playlist_track.playlist = ? 
				AND (
					playlist_track.track NOT LIKE 'file:/%'
					OR (library_track.track = tracks.id AND library_track.library = ?)
				)
		) );
		
		push @p, $playlist_id, $library_id;
	}

	# Add search criteria for tracks
	my $rs = $self->search_literal(
		'me.playlist = ? ' . $librarySQL,
		@p,
		{ 'order_by' => 'me.position' }
	);

	return wantarray ? $rs->all : $rs;
}

1;
