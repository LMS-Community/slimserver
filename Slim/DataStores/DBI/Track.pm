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
	'remote' => 'remote',
	'audio' => 'audio',
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
	'lossless' => 'lossless',
	'titlesearch' => 'titlesearch',
	'lyrics' => 'lyrics',
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

	$class->has_many(tracks => [ 'Slim::DataStores::DBI::PlaylistTrack' => 'track' ] => {
		'foreign_key' => 'playlist',
		'order_by'    => 'position',
	});

	$class->has_many(diritems => [ 'Slim::DataStores::DBI::DirlistTrack' => 'item' ] => 'dirlist');
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

sub get {
	my ($self, @attrs) = @_;

	my @items = $self->SUPER::get(@attrs);

	for (my $i = 0; $i <= $#attrs; $i++) {

		if (!defined $items[$i]) {

			if ($attrs[$i] =~ /^(COVER|COVERTYPE)$/) {

				$loader->updateCoverArt($self->SUPER::get('url'), 'cover');

			} elsif ($attrs[$i] =~ /^(THUMB|THUMBTYPE)$/) {

				# defer thumb information until needed
				$loader->updateCoverArt($self->SUPER::get('url'), 'thumb');
			}

			$items[$i] = $self->SUPER::get($attrs[$i]);
		}
	}

	return wantarray ? @items : $items[0];
}

sub albumid {
	my $self = shift;

	my ($albumid) = $self->_attrs('album');
	return $albumid;
}

sub artist {
	my $self = shift;

	return ($self->contributorsOfType('artist'))[0] || ($self->contributorsOfType('trackArtist'))[0];
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

	my ($bitrate, $vbrScale) = $self->get(qw(bitrate vbr_scale));

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
	
	$::d_artwork && msgf("Retrieving artwork ($art) for: %s\n", $self->url());
	
	my ($body, $contenttype, $mtime, $path);

	my $artwork = $art eq 'cover' ? $self->cover() : $self->thumb();
	
	if ($artwork && ($artwork ne '1')) {

		$body = Slim::Music::Info::getImageContent($artwork);

		if ($body) {

			$::d_artwork && msg("Found cached $art file: $artwork\n");

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
			unless (ref($track)) {
				$track = $ds->objectForUrl($track, 1, 0, 1) || next;
			}

			Slim::DataStores::DBI::PlaylistTrack->create({
				playlist => $self,
				track    => $track->id,
				position => $i++
			});
		}
	}

	# With playlists in the database - we want to make sure the playlist
	# is consistent to the user.
	$ds->forceCommit;
}

sub setDirItems {
	my $self  = shift;
	my $items = shift;
	
	# One fell swoop to delete.
	eval {
		Slim::DataStores::DBI::DirlistTrack->sql_deleteDirItems->execute($self->id);
	};

	my $ds = Slim::Music::Info::getCurrentDataStore();

	if ($items && ref($items) eq 'ARRAY') {

		my $i = 0;

		for my $item (@$items) {

			# If tracks are being added via Browse Music Folder -
			# which still deals with URLs - get the objects to add.
			unless (ref($item)) {
				$item = $ds->objectForUrl($item, 1, 0, 1) || next;
			}

			Slim::DataStores::DBI::DirlistTrack->create({
				dirlist  => $self,
				item     => $item->id,
				position => $i++
			});
		}
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
