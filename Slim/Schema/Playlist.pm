package Slim::Schema::Playlist;

# $Id$

use strict;
use base 'Slim::Schema::Track';

use Scalar::Util qw(blessed);
use Slim::Utils::Misc;

{
	my $class = __PACKAGE__;

	# Magic to create a ResultSource for this inherited class.
	$class->table($class->table);

	$class->resultset_class('Slim::Schema::ResultSet::Playlist');

	$class->has_many('playlist_tracks'   => 'Slim::Schema::PlaylistTrack' => 'playlist', undef, {
		order_by => 'playlist_tracks.position'
	});
}

sub tracks {
	my $self = shift;

	return $self->playlist_tracks->search_related('track' => @_);
}

sub setTracks {
	my $self   = shift;
	my $tracks = shift;

	# One fell swoop to delete.
	eval {
		Slim::Schema::PlaylistTrack->sql_deletePlaylist->execute($self->id);
	};

	if (!$tracks || ref($tracks) ne 'ARRAY') {
		return;
	}

	my $i = 0;

	for my $track (@$tracks) {

		# If tracks are being added via Browse Music Folder -
		# which still deals with URLs - get the objects to add.
		if (!blessed($track) || !$track->can('url')) {

			$track = Slim::Schema->objectForUrl({
				'url'      => $track,
				'create'   => 1,
				'readTags' => 1,
			});
		}

		if (blessed($track) && $track->can('id')) {

			Slim::Schema->rs('PlaylistTrack')->create({
				playlist => $self,
				track    => $track,
				position => $i++
			});
		}
	}

	# With playlists in the database - we want to make sure the playlist
	# is consistent to the user.
	Slim::Schema->forceCommit;
}

1;

__END__
