package Slim::DataStores::DBI::Track;

# $Id$

use strict;
use base 'Slim::DataStores::DBI::DataModel';

use Slim::Utils::Misc;

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
	'thumb' => 'thumb',
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
	'moodlogic_song_id' => 'moodlogic_song_id',
	'moodlogic_artist_id' => 'moodlogic_artist_id',
	'moodlogic_genre_id' => 'moodlogic_genre_id',
	'moodlogic_song_mixable' => 'moodlogic_song_mixable',
	'moodlogic_artist_mixable' => 'moodlogic_artist_mixable',
	'moodlogic_genre_mixable' => 'moodlogic_genre_mixable',
	'musicmagic_genre_mixable' => 'musicmagic_genre_mixable',
	'musicmagic_artist_mixable' => 'musicmagic_artist_mixable',
	'musicmagic_album_mixable' => 'musicmagic_album_mixable',
	'musicmagic_song_mixable' => 'musicmagic_song_mixable',
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

tie our %_cache, 'Tie::Cache::LRU', 5000;

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

		} elsif (!$self->SUPER::get('tag')) {

			$loader->readTags($self);
		}

		$item = $self->SUPER::get($attr);
	}

	return $item;
}

sub set {
	my $self = shift;
	
	$self->{'cachedArtist'} = undef;
	$self->{'cachedArtistSort'} = undef;
	$self->{'cachedGenre'} = undef;

	return $self->SUPER::set(@_);
}

sub getCached {
	my $self = shift;
	my $attr = shift;

	return $self->SUPER::get($attr);
}

# For easy access in Web::Pages
sub track {
	my $self = shift;

	return $self->SUPER::get('tracknum');
}

# String version of contributors list
sub artist {
	my $self = shift;

	# FIXME Possible premature optimization - cache the artist string.
	# XXX - we may be able to replace this with the LRU cache
	return $self->{'cachedArtist'} ||= join(", ", map { $_->name } $self->contributors());
}

sub artistsort {
	my $self = shift;

	# FIXME Possible premature optimization - cache the artistsort string.
	# XXX - we may be able to replace this with the LRU cache
	return $self->{'cachedArtistSort'} ||= join(", ", map { $_->namesort } $self->contributors());
}

sub albumsort {
	my $self = shift;
	my $album = $self->album();

	return $album->titlesort();
}

# String version of genre list
sub genre {
	my $self = shift;

	# FIXME Possible premature optimization - cache the genre string.
	# XXX - we may be able to replace this with the LRU cache
	return $self->{'cachedGenre'} ||= join(", ", map { $_->name } $self->genres());
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

	return map { $_->contributor } Slim::DataStores::DBI::ContributorTrack->$type($self);
}

sub searchTitle {
	my $class   = shift;
	my $pattern = shift;

	return $class->searchColumn($pattern, 'titlesort');
}

sub searchColumn {
	my $class   = shift;
	my $pattern = shift;
	my $column  = shift;

	s/\*/%/g for @$pattern;

	my %where   = ( $column => $pattern, );
	my $findKey = join(':', $column, @$pattern);

	$_cache{$findKey} = [ $class->searchPattern('tracks', \%where, ['titlesort']) ];

	return wantarray ? @{$_cache{$findKey}} : $_cache{$findKey}->[0];
}

1;

__END__


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
