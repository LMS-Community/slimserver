package Slim::DataStores::DBI::Track;

# $Id: Track.pm,v 1.1 2004/12/17 20:33:04 dsully Exp $

use strict;
use base 'Slim::DataStores::DBI::DataModel';

use Slim::Utils::Misc;

my %primaryColumns = (
	'id' => 'id',
);

my %essentialColumns = (
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

my %otherColumns = (
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

my %allColumns = ( %primaryColumns, %essentialColumns, %otherColumns );

__PACKAGE__->table('tracks');
__PACKAGE__->columns(Primary => keys %primaryColumns);
__PACKAGE__->columns(Essential => keys %allColumns);
# Combine essential and other for now for performance, at the price of
# larger in-memory object size
#__PACKAGE__->columns(Others => keys %otherColumns);
__PACKAGE__->columns(Stringify => qw/url/);

__PACKAGE__->has_a(album => 'Slim::DataStores::DBI::Album');
__PACKAGE__->has_many(genres => ['Slim::DataStores::DBI::GenreTrack' => 'genre'] => 'track');
__PACKAGE__->has_many(comments => ['Slim::DataStores::DBI::Comment' => 'value'] => 'track');
__PACKAGE__->has_many(contributors => ['Slim::DataStores::DBI::ContributorTrack' => 'contributor'] => 'track');
__PACKAGE__->has_many(tracks => [ 'Slim::DataStores::DBI::PlaylistTrack' => 'track' ] => 'playlist');
__PACKAGE__->has_many(diritems => [ 'Slim::DataStores::DBI::DirlistTrack' => 'item' ] => 'dirlist');

__PACKAGE__->add_constructor(externalPlaylists => qq{
	url LIKE 'itunesplaylist:%' OR
	url LIKE 'moodlogicplaylist:%' OR
	url LIKE 'musicmagicplaylist:%'
});

tie my %_cache, 'Tie::Cache::LRU', 5000;

my $loader;

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

# String version of contributors list
sub artist {
	my $self = shift;

	# FIXME Possible premature optimization - cache the artist string.
	# XXX - we may be able to replace this with the LRU cache
	return $self->{'cachedArtist'} if $self->{'cachedArtist'};

	$self->{'cachedArtist'} = join(", ", map { $_->name } $self->contributors());

	return $self->{'cachedArtist'};
}

sub artistsort {
	my $self = shift;

	# FIXME Possible premature optimization - cache the artistsort string.
	# XXX - we may be able to replace this with the LRU cache
	return $self->{'cachedArtistSort'} if $self->{'cachedArtistSort'};

	$self->{'cachedArtistSort'} = join(", ", map { $_->namesort } $self->contributors());

	return $self->{'cachedArtistSort'};
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
	return $self->{'cachedGenre'} if $self->{'cachedGenre'};

	$self->{'cachedGenre'} = join(", ", map { $_->name } $self->genres());

	return $self->{'cachedGenre'};
}

sub setTracks {
	my $self = shift;

	for my $track (Slim::DataStores::DBI::PlaylistTrack->tracksOf($self)) {
		$track->delete();
	}

	my $i = 0;

	for my $track (@_) {

		Slim::DataStores::DBI::PlaylistTrack->create({
			playlist => $self,
			track    => $track,
			position => $i++
		});
	}
}

sub setDirItems {
	my $self = shift;
	
	for my $item (Slim::DataStores::DBI::DirlistTrack->tracksOf($self)) {
		$item->delete();
	}

	my $i = 0;

	for my $item (@_) {

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

	my $contributorKeys = Slim::DataStores::DBI::Contributors->contributorFields();

	return () unless grep { $type eq $_ } @$contributorKeys;

	$type .= 'sFor';

	return map { $_->contributor } Slim::DataStores::DBI::ContributorTrack->$type($self);
}

sub searchTitle {
	my $class   = shift;
	my $pattern = shift;

	return $class->searchColumn($pattern, 'title');
}

sub searchColumn {
	my $class   = shift;
	my $pattern = shift;
	my $column  = shift;

	s/\*/%/g for @$pattern;

	my %where  = ( $column => $pattern, );

	$_cache{$pattern} = [ $class->searchPattern('tracks', \%where, ['titlesort']) ];

	return wantarray ? @{$_cache{$pattern}} : $_cache{$pattern}->[0];
}

1;

__END__


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
