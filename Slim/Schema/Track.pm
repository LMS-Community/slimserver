package Slim::Schema::Track;

# $Id$

use strict;
use base 'Slim::Schema::DBI';

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

	$class->register_column('title', { accessor => 'name' });
	$class->register_column('titlesort', { accessor => 'namesort' });
	$class->register_column('titlesearch', { accessor => 'namesearch' });

	# setup our relationships
	$class->belongs_to('album' => 'Slim::Schema::Album');

	$class->has_many('genreTracks'       => 'Slim::Schema::GenreTrack' => 'track');
	$class->has_many('comment_objects'   => 'Slim::Schema::Comment'    => 'track');

	$class->has_many('contributorTracks' => 'Slim::Schema::ContributorTrack');

	if ($] > 5.007) {
		$class->utf8_columns(qw/title titlesort/);
	}

	$class->resultset_class('Slim::Schema::ResultSet::Track');
}

sub contributors {
	my $self = shift;

	return $self->contributorTracks->search_related(
		'contributor', undef, { distinct => 1 }
	)->search(@_);
}

sub comments {
	my $self = shift;

	return map { $_->value } $self->comment_objects(@_);
}

sub genres {
	my $self = shift;

	return $self->genreTracks->search_related('genre', @_);
}

sub attributes {
	my $class = shift;

	# Return a hash ref of column names
	return { map { $_ => 1 } @allColumns };
}

sub albumid {
	my $self = shift;

	return $self->get_column('album');
}

sub artist {
	my $self = shift;

	return $self->contributorsOfType('ARTIST')->single;
}

sub artists {
	my $self = shift;

	return $self->contributorsOfType('ARTIST')->all;
}

sub artistsWithAttributes {
	my $self = shift;

	my @artists = ();

	for my $artist ($self->artists) {

		push @artists, {
			'artist'     => $artist,
			'attributes' => join('=', 'contributor.id', $artist->id),
		};
	}

	return \@artists;
}

sub composer {
	my $self = shift;

	return $self->contributorsOfType('COMPOSER')->all;
}

sub conductor {
	my $self = shift;

	return $self->contributorsOfType('CONDUCTOR')->all;
}

sub band {
	my $self = shift;

	return $self->contributorsOfType('BAND')->all;
}

sub genre {
	my $self = shift;

	return $self->genres->single;
}

sub comment {
	my $self = shift;

	my $comment;

	# extract multiple comments and concatenate them
	for my $c ($self->comments) {

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

	my $secs = $self->secs;

	return sprintf('%s:%02s', int($secs / 60), $secs % 60) if defined $secs;
}

sub durationSeconds {
	my $self = shift;

	return $self->secs;
}

sub modificationTime {
	my $self = shift;

	my $time = $self->timestamp;

	return join(', ', Slim::Utils::Misc::longDateF($time), Slim::Utils::Misc::timeF($time));
}

sub prettyBitRate {
	my $self = shift;
	my $only = shift;

	my $bitrate  = $self->bitrate;
	my $vbrScale = $self->vbr_scale;

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

	return Slim::Music::Info::isRemoteURL($self->url);
}

sub isPlaylist {
	my $self = shift;

	return Slim::Music::Info::isPlaylist($self->url);
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
	if (!$self->audio) {
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

	if ($artwork && $artwork ne 1) {

		($body, $contentType) = Slim::Music::Artwork->getImageContentAndType($artwork);

		if ($body && $contentType) {

			$::d_artwork && msg("coverArt: Found cached $artType file: $artwork\n");

			$path = $artwork;
		}
	}

	# If we didn't already store an artwork value - look harder.
	if (!$artwork || $artwork eq 1 || !$body) {

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

sub contributorsOfType {
	my $self = shift;
	my $type = shift;

	# Check for valid roles.
	my $role = Slim::Schema::Contributor->typeToRole($type) || return ();

	return $self
		->search_related('contributorTracks', { 'role' => $role })
		->search_related('contributor');
}

sub contributorRoles {
	my $self = shift;

	return Slim::Schema::Contributor->contributorRoles;
}

sub displayAsHTML {
	my ($self, $form, $descend, $sort) = @_;

	my $format = Slim::Utils::Prefs::getInd("titleFormat", Slim::Utils::Prefs::get("titleFormatWeb"));

	# Go directly to infoFormat, as standardTitle is more client oriented.
	$form->{'text'}     = Slim::Music::TitleFormatter::infoFormat($self, $format, 'TITLE');
	$form->{'item'}     = $self->id;
	$form->{'itempath'} = $self->url;
	$form->{'itemobj'}  = $self;

	# Only include Artist & Album if the user doesn't have them defined in a custom title format.
	if ($format !~ /ARTIST/) {
		$form->{'artist'}        = $self->artist;
		$form->{'includeArtist'} = 1;
	}

	if ($format !~ /ALBUM/) {
		$form->{'includeAlbum'}  = 1;
	}

	$form->{'noArtist'} = Slim::Utils::Strings::string('NO_ARTIST');
	$form->{'noAlbum'}  = Slim::Utils::Strings::string('NO_ALBUM');

	my $Imports = Slim::Music::Import->importers;

	for my $mixer (keys %{$Imports}) {

		if (defined $Imports->{$mixer}->{'mixerlink'}) {
			&{$Imports->{$mixer}->{'mixerlink'}}($self,$form,0);
		}
	}
}

1;

__END__
