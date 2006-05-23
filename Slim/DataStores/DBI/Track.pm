package Slim::DataStores::DBI::Track;

# $Id$

use strict;
use base 'Slim::DataStores::DBI::DataModel';

use Scalar::Util qw(blessed);

use Slim::Music::Artwork;
use Slim::Music::Info;
use Slim::Utils::Misc;

our @allColumns = (qw(
	id url content_type title titlesort titlesearch album tracknum timestamp
	filesize tag disc thumb remote audio audio_size audio_offset
	year secs cover vbr_scale bitrate samplerate samplesize channels block_alignment
	endian bpm tagversion drm moodlogic_id moodlogic_mixable musicmagic_mixable
	musicbrainz_id playcount lastplayed lossless lyrics rating replay_gain replay_peak
));

{
	my $class = __PACKAGE__;

	$class->table('tracks');

	$class->add_columns(@allColumns);

	$class->set_primary_key('id');

	# Columns that need to be upgraded to UTF8
	# XXXX - how to do this for DBIx::Class ?
	# $class->columns(UTF8 => qw/title titlesort/);

	# setup our relationships
	$class->belongs_to('album' => 'Slim::DataStores::DBI::Album');

	$class->has_many('genre_tracks'       => 'Slim::DataStores::DBI::GenreTrack' => 'track');
	$class->has_many('comment_objects'     => 'Slim::DataStores::DBI::Comment' => 'track');

	$class->has_many('contributorTracks' => 'Slim::DataStores::DBI::ContributorTrack');

	$class->has_many('playlist_tracks' => 'Slim::DataStores::DBI::PlaylistTrack' => 'playlist' => { order_by => 'playlist_tracks.position' });

}

sub tracks {
  return shift->playlist_tracks->search_related('track' => @_);
}

sub contributors {

  return shift->contributorTracks->search_related(
           'contributor', undef, { distinct => 1, order_by => 'tracknum' }
             )->search(@_);
}

sub comments { return map { $_->value } shift->comment_objects(@_); }

sub genres { shift->genre_tracks->search_related('track', @_); }

sub attributes {
	my $class = shift;

	# Return a hash ref of column names
	return { map { $_ => 1 } @allColumns };
}

sub stringify {
	my $self = shift;

	return $self->get_column('url');
}

sub albumid {
	my $self = shift;

	return $self->get_column('album');
}

sub artist {
	my $self = shift;

	return ($self->artists)[0];
}

sub artists {
	my $self = shift;

	return $self->contributorsOfType('ARTIST');
}

sub artistsWithAttributes {
	my $self = shift;

	my @artists = ();

	for my $artist ($self->artists) {

		push @artists, {
			'artist'     => $artist,
			'attributes' => join('=', 'artist', $artist->id),
		};
	}

	return \@artists;
}

sub composer {
	my $self = shift;

	return $self->contributorsOfType('COMPOSER');
}

sub conductor {
	my $self = shift;

	return $self->contributorsOfType('CONDUCTOR');
}

sub band {
	my $self = shift;

	return $self->contributorsOfType('BAND');
}

sub genre {
	my $self = shift;

	return ($self->genres)[0];
}

sub comment {
	my $self = shift;

	my $comment;

	# extract multiple comments and concatenate them
	for my $c ($self->comments()) {

		next unless $c;

		# ignore SoundJam and iTunes CDDB comments
		if ($c =~ /SoundJam_CDDB_/ ||
		    $c =~ /iTunes_CDDB_/ ||
		    $c =~ /^\s*[0-9A-Fa-f]{8}(\+|\s)/ ||
		    $c =~ /^\s*[0-9A-Fa-f]{2}\+[0-9A-Fa-f]{32}/) {
			next;
		} 

		# put a slash between multiple comments.
		$comment .= ' / ' if $comment;
		$c =~ s/^eng(.*)/$1/;
		$comment .= $c;
	}

	return $comment;
}

sub duration {
	my $self = shift;

	my $secs = $self->secs();

	return sprintf('%s:%02s', int($secs / 60), $secs % 60) if defined $secs;
}

sub durationSeconds {
	my $self = shift;

	return $self->secs();
}

sub modificationTime {
	my $self = shift;

	my $time = $self->timestamp();

	return join(', ', Slim::Utils::Misc::longDateF($time), Slim::Utils::Misc::timeF($time));
}

sub bitrate {
	my $self = shift;
	my $only = shift;

	my ($bitrate, $vbrScale) = $self->get_columns(qw(bitrate vbr_scale));

	# Source only wants the raw bitrate
	if ($only) {
		return $bitrate || 0;
	}

	my $mode = defined $vbrScale ? 'VBR' : 'CBR';

	if ($bitrate) {
		return int ($bitrate/1000) . Slim::Utils::Strings::string('KBPS') . ' ' . $mode;
	}

	return 0;
}

sub prettySampleRate {
	my $self = shift;

	my $sampleRate = $self->samplerate;

	if ($sampleRate) {
		return sprintf('%.1f kHz', $sampleRate / 1000);
	}
}

# Wrappers around common functions
sub isRemoteURL {
	my $self = shift;

	return Slim::Music::Info::isRemoteURL($self);
}

sub isPlaylist {
	my $self = shift;

	return Slim::Music::Info::isPlaylist($self);
}

sub isCUE {
	my $self = shift;

	return Slim::Music::Info::isCUE($self);
}

sub isContainer {
	my $self = shift;

	return Slim::Music::Info::isContainer($self);
}

# we cache whether we had success reading the cover art.
sub coverArt {
	my $self    = shift;
	my $artType = shift || 'cover';
	my $list    = shift || 0;

	# return with nothing if this isn't a file. 
	# We don't need to search on streams, for example.
	if (!Slim::Utils::Prefs::get('lookForArtwork') || !$self->audio) {

		return undef;
	}

	# Don't pass along anchors - they mess up the content-type.
	# See Bug: 2219
	my $url = Slim::Utils::Misc::stripAnchorFromURL($self->url);

	$::d_artwork && msg("Retrieving artwork ($artType) for: $url\n");

	my ($body, $contentType, $mtime, $path);

	# artType will be either 'cover' or 'thumb'
	#
	# A value of 1 indicate the cover art is embedded in the file's
	# metdata tags.
	# 
	# Otherwise we'll have a path to a file on disk.
	my $artwork = $self->get_column($artType);

	if ($artwork && $artwork != 1) {

		($body, $contentType) = Slim::Music::Artwork->getImageContentAndType($artwork);

		if ($body && $contentType) {

			$::d_artwork && msg("coverArt: Found cached $artType file: $artwork\n");

			$path = $artwork;
		}
	}

	# If we didn't already store an artwork value - look harder.
	if (!$artwork || $artwork == 1 || !$body) {

		($body, $contentType, $path) = Slim::Music::Artwork->readCoverArt($self, $artType);
	}

	# kick this back up to the webserver so we can set last-modified
	if (defined $path) {

		$self->set($artType, $path);
		$self->update;

		$mtime = (stat($path))[9];
	}

	# This is a hack, as Template::Stash::XS calls us in list context,
	# even though it should be in scalar context.
	if (!$list && wantarray) {
		return ($body, $contentType, $mtime);
	} else {
		return $body;
	}
}

sub path {
	my $self = shift;

	my $url  = $self->url;

	# Turn playlist special files back into file urls
	$url =~ s/^playlist:/file:/;

	if (Slim::Music::Info::isFileURL($url)) {

		return Slim::Utils::Misc::pathFromFileURL($url);
	}

	return $url;
}

sub setTracks {
	my $self   = shift;
	my $tracks = shift;

	# One fell swoop to delete.
	eval {
		Slim::DataStores::DBI::PlaylistTrack->sql_deletePlaylist->execute($self->id);
	};

	my $ds = Slim::Music::Info::getCurrentDataStore();

	if ($tracks && ref($tracks) eq 'ARRAY') {

		my $i = 0;

		for my $track (@$tracks) {

			# If tracks are being added via Browse Music Folder -
			# which still deals with URLs - get the objects to add.
			if (!blessed($track) || !$track->can('url')) {

				$track = $ds->objectForUrl($track, 1, 1, 1);
			}

			if (blessed($track) && $track->can('id')) {

				Slim::DataStores::DBI::PlaylistTrack->create({
					playlist => $self,
					track    => $track,
					position => $i++
				});
			}
		}
	}

	# With playlists in the database - we want to make sure the playlist
	# is consistent to the user.
	$ds->forceCommit;
}

sub contributorsOfType {
	my $self = shift;
	my $type = shift;

	# Not a valid role!
	unless (Slim::DataStores::DBI::Contributor->typeToRole($type)) {

		return ();
	}

	return map { $_->contributor } Slim::DataStores::DBI::ContributorTrack->contributorsForTrackAndRole(
		$self->id, Slim::DataStores::DBI::Contributor->typeToRole($type),
	);
}

sub contributorRoles {
	my $self = shift;

	return Slim::DataStores::DBI::Contributor->contributorRoles;
}

1;

__END__


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
