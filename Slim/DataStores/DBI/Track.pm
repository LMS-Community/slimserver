package Slim::DataStores::DBI::Track;

# $Id$

use strict;
use base 'Slim::DataStores::DBI::DataModel';
use Class::DBI::Iterator;

use Slim::Utils::Misc;

# Map the database column to the accessor name. Not quite sure why we did it this way..
our %primaryColumns = (
	'id' => 'id',
);

our %essentialColumns = (
	'url' => 'url',
	'ct' => 'content_type',
	'title' => 'title',
	'titlesort' => 'titlesort',
	'album' => 'album',
	'tracknum' => 'tracknum',
	'age' => 'timestamp',
	'fs' => 'filesize',
	'tag' => 'tag',
	'disc' => 'disc',
	'thumb' => 'thumb',
	'multialbumsortkey' => 'multialbumsortkey',
);

our %otherColumns = (
	'size' => 'audio_size',
	'offset' => 'audio_offset',
	'year' => 'year',
	'secs' => 'secs',
	'cover' => 'cover',
	'covertype' => 'covertype',
	'thumbtype' => 'thumbtype',
	'vbr_scale' => 'vbr_scale',
	'bitrate' => 'bitrate',
	'rate' => 'samplerate',
	'samplesize' => 'samplesize',
	'channels' => 'channels',
	'blockalign' => 'block_alignment',
	'endian' => 'endian',
	'bpm' => 'bpm',
	'tagversion' => 'tagversion',
	'tagsize' => 'tagsize',
	'drm' => 'drm',
	'moodlogic_id' => 'moodlogic_id',
	'moodlogic_mixable' => 'moodlogic_mixable',
	'musicmagic_mixable' => 'musicmagic_mixable',
	'playCount' => 'playCount',
	'lastPlayed' => 'lastPlayed',
);

our %allColumns = ( %primaryColumns, %essentialColumns, %otherColumns );

{
	my $class = __PACKAGE__;

	$class->table('tracks');

	$class->columns(Primary => keys %primaryColumns);
	$class->columns(Essential => keys %essentialColumns);
	#$class->columns(Essential => keys %allColumns);

	# Combine essential and other for now for performance, at the price of
	# larger in-memory object size
	$class->columns(Others => keys %otherColumns);
	$class->columns(Stringify => qw/url/);

	# setup our relationships
	$class->has_a(album => 'Slim::DataStores::DBI::Album');

	$class->has_many(genres => ['Slim::DataStores::DBI::GenreTrack' => 'genre'] => 'track');
	$class->has_many(comments => ['Slim::DataStores::DBI::Comment' => 'value'] => 'track');
	$class->has_many(contributors => ['Slim::DataStores::DBI::ContributorTrack' => 'contributor'] => 'track');
	$class->has_many(tracks => [ 'Slim::DataStores::DBI::PlaylistTrack' => 'track' ] => 'playlist');
	$class->has_many(diritems => [ 'Slim::DataStores::DBI::DirlistTrack' => 'item' ] => 'dirlist');

	# And some custom sql
	$class->add_constructor(externalPlaylists => qq{
		url LIKE 'itunesplaylist:%' OR
		url LIKE 'moodlogicplaylist:%' OR
		url LIKE 'musicmagicplaylist:%'
	});
}

our $loader;

sub setLoader {
	my $class = shift;

	$loader = shift;
}

sub attributes {
	my $class = shift;

	return \%allColumns;
}

sub accessor_name {
	my ($class, $column) = @_;
	
	return $allColumns{$column};
}

# For now, only allow one attribute to be fetched at a time
sub get {
	my $self = shift;
	my $attr = shift;

	my $item = $self->SUPER::get($attr);

	if (!defined $item) {

		if ($attr =~ /^(COVER|COVERTYPE)$/) {

			$loader->updateCoverArt($self->SUPER::get('url'), 'cover');

		} elsif ($attr =~ /^(THUMB|THUMBTYPE)$/) {

			# defer thumb information until needed
			$loader->updateCoverArt($self->SUPER::get('url'), 'thumb');
		}

		$item = $self->SUPER::get($attr);
	}

	return $item;
}

sub artist {
	my $self = shift;

	return ($self->contributorsOfType('artist'))[0];
}

sub artistsort {
	my $self = shift;

	my $obj  = ($self->contributorsOfType('artist'))[0];

	return $obj->namesort() if $obj && ref($obj);
	return undef;
}

sub artists {
	my $self = shift;

	# Create an iterator for artists - as that's what contributors from
	# has_many returns as well. So it can be used in the templates.
	return Class::DBI::Iterator->new('Slim::DataStores::DBI::Contributor', [ $self->contributorsOfType('artist') ]);
}

sub composer {
	my $self = shift;

	return $self->contributorsOfType('composer');
}

sub conductor {
	my $self = shift;

	return $self->contributorsOfType('conductor');
}

sub band {
	my $self = shift;

	return $self->contributorsOfType('band');
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

	my $bitrate = $self->get('bitrate');

	# Source only wants the raw bitrate
	if ($only) {
		return $bitrate || 0;
	}

	my $mode = (defined $self->vbr_scale()) ? 'VBR' : 'CBR';

	if ($bitrate) {
		return int ($bitrate/1000) . Slim::Utils::Strings::string('KBPS') . ' ' . $mode;
	}

	return 0;
}

# we cache whether we had success reading the cover art.
sub coverArt {
	my $self = shift;
	my $art  = shift || 'cover';
	my $list = shift || 0;

	my $image;

	# return with nothing if this isn't a file. 
	# We don't need to search on streams, for example.
	if (!Slim::Utils::Prefs::get('lookForArtwork') || 
	    !Slim::Music::Info::isSong($self) ||
	     Slim::Music::Info::isRemoteURL($self)) {

		return undef;
	}
	
	$::d_artwork && Slim::Utils::Misc::msgf("Retrieving artwork ($art) for: %s\n", $self->url());
	
	my ($body, $contenttype, $mtime, $path);

	my $artwork = $art eq 'cover' ? $self->cover() : $self->thumb();
	
	if ($artwork && ($artwork ne '1')) {

		$body = Slim::Music::Info::getImageContent($artwork);

		if ($body) {

			$::d_artwork && Slim::Utils::Misc::msg("Found cached $art file: $artwork\n");

			$contenttype = Slim::Music::Info::mimeType(Slim::Utils::Misc::fileURLFromPath($artwork));

			$path = $artwork;

		} else {

			($body, $contenttype, $path) = Slim::Music::Info::readCoverArt($self->url, $art);

			if (defined $path) {

				$art eq 'cover' ? $self->cover($path) : $self->thumb($path);
				$self->update();
			}
		}

	} else {

		($body, $contenttype, $path) = Slim::Music::Info::readCoverArt($self->url, $art);

		if (defined $path) {

			$art eq 'cover' ? $self->cover($path) : $self->thumb($path);
			$self->update();
		}
	}

	# kick this back up to the webserver so we can set last-modified
	if ($path && -r $path) {
		$mtime = (stat(_))[9];
	}

	# This is a hack, as Template::Stash::XS calls us in list context,
	# even though it should be in scalar context.
	if (!$list && wantarray()) {
		return ($body, $contenttype, $mtime);
	} else {
		return $body;
	}
}

sub setTracks {
	my $self   = shift;
	my @tracks = @_;

	for my $track (Slim::DataStores::DBI::PlaylistTrack->tracksOf($self->id)) {
		$track->delete();
	}

	my $i = 0;

	for my $track (@tracks) {

		Slim::DataStores::DBI::PlaylistTrack->create({
			playlist => $self,
			track    => $track,
			position => $i++
		});
	}
}

sub setDirItems {
	my $self  = shift;
	my @items = @_;
	
	for my $item (Slim::DataStores::DBI::DirlistTrack->tracksOf($self->id)) {
		$item->delete();
	}

	my $i = 0;

	for my $item (@items) {

		# Store paths properly encoded as utf8 in the db.
		if ($Slim::Utils::Misc::locale ne 'utf8') {
			$item = Slim::Utils::Misc::utf8encode($item);
		}

		Slim::DataStores::DBI::DirlistTrack->create({
			dirlist  => $self,
			item     => $item,
			position => $i++
		});
	}
}

sub contributorsOfType {
	my $self = shift;
	my $type = shift;

	my $contributorKeys = Slim::DataStores::DBI::Contributor->contributorFields();

	return () unless grep { $type eq $_ } @$contributorKeys;

	$type .= 'sFor';

	return map { $_->contributor } Slim::DataStores::DBI::ContributorTrack->$type($self->id);
}

sub contributorRoles {
	my $self = shift;

	return grep { ! /contributor/ } @{ Slim::DataStores::DBI::Contributor->contributorFields() };
}

1;

__END__


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
