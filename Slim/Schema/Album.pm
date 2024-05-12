package Slim::Schema::Album;


use strict;
use base 'Slim::Schema::DBI';

use JSON::XS::VersionOneAndTwo;

use Slim::Schema::ResultSet::Album;

use Slim::Utils::Log;
use Slim::Utils::Prefs;

my $prefs = preferences('server');

my $log = logger('database.info');

{
	my $class = __PACKAGE__;

	$class->table('albums');

	$class->add_columns(qw(
		id
		titlesort
		contributor
		compilation
		year
		artwork
		disc
		discc
		musicmagic_mixable
		titlesearch
		replay_gain
		replay_peak
		musicbrainz_id
		release_type
		extid
	), title => { accessor => undef() });

	$class->set_primary_key('id');
	$class->add_unique_constraint('titlesearch' => [qw/id titlesearch/]);

	$class->belongs_to('contributor' => 'Slim::Schema::Contributor');

	$class->has_many('tracks'            => 'Slim::Schema::Track'            => 'album');
	# need to duplicate this relation because it should have been 'track' not 'tracks', but changing this now would lead to breakages elsewhere.
	# See https://github.com/LMS-Community/slimserver/pull/1060 for details.
	$class->has_many('track'             => 'Slim::Schema::Track'            => 'album');
	$class->has_many('contributorAlbums' => 'Slim::Schema::ContributorAlbum' => 'album');

	if ($] > 5.007) {
		$class->utf8_columns(qw/title titlesort/);
	}

	$class->resultset_class('Slim::Schema::ResultSet::Album');

	# Simple caching as artistsWithAttributes is expensive.
	$class->mk_group_accessors('simple' => 'cachedArtistsWithAttributes');
}

use constant CUSTOM_RELEASE_TYPE_PREFIX => 'RELEASE_TYPE_CUSTOM_';

# see https://musicbrainz.org/doc/Release_Group/Type
my @PRIMARY_RELEASE_TYPES = qw(
	Album
	EP
	Single
	Broadcast
	Other
);

my %releaseTypeMap = map {
	uc($_) => 1
} @PRIMARY_RELEASE_TYPES;

sub url {
	my $self = shift;

	return $self->extid
		|| sprintf('db:album.title=%s&contributor.name=%s', URI::Escape::uri_escape_utf8($self->title), URI::Escape::uri_escape_utf8($self->contributor->name))
}

sub name {
	return shift->title;
}

sub namesort {
	return shift->titlesort;
}

sub namesearch {
	return shift->titlesearch;
}

# Do a proper join
sub contributors {
	my $self = shift;

	return $self->contributorAlbums->search_related(
		'contributor', undef, { distinct => 1 }
	)->search(@_);
}

sub releaseTypes {
	my $self = shift;

	my $dbh = Slim::Schema->dbh;
	my $release_types_sth = $dbh->prepare_cached('SELECT DISTINCT(release_type) FROM albums ORDER BY release_type');
	my $releaseTypes = [
		grep { $_ !~ /compilation/i }
		map { $_->[0] } @{ $dbh->selectall_arrayref($release_types_sth) || [] }
	];

	return $releaseTypes;
}

sub primaryReleaseTypes { \@PRIMARY_RELEASE_TYPES }

sub addReleaseTypeMap {
	my ($self, $releaseType, $normalizedReleaseType) = @_;

	return unless $releaseType;
	return if $releaseTypeMap{$normalizedReleaseType};

	$releaseTypeMap{$normalizedReleaseType} = $releaseType;

	my $last = Slim::Schema->rs('MetaInformation')->find_or_create( {
		'name' => 'releaseTypeMap'
	} );

	$last->value(to_json(\%releaseTypeMap));
	$last->update;
}

sub addReleaseTypeStrings {
	my $stringsObj = Slim::Schema->rs('MetaInformation')->find( {
		'name' => 'releaseTypeMap'
	} );

	if ($stringsObj) {
		my $strings = eval { from_json($stringsObj->value) };
		if ($strings && ref $strings) {
			while (my ($token, $string) = each %$strings) {
				next if $string == 1;

				$token =~ s/[^a-z_0-9]/_/ig;
				$token = CUSTOM_RELEASE_TYPE_PREFIX . $token;

				if ( !Slim::Utils::Strings::stringExists($token) ) {
					Slim::Utils::Strings::storeExtraStrings([{
						strings => { EN => $string},
						token   => $token,
					}]) if !Slim::Utils::Strings::stringExists($token);
				}
			}
		}

		$stringsObj->delete;
	}
}

sub releaseTypeName {
	my ($self, $releaseType, $client) = @_;

	my $nameToken = uc($releaseType);
	$nameToken =~ s/[^a-z_0-9]/_/ig;

	my $name;
	foreach ('RELEASE_TYPE_' . $nameToken . 'S', CUSTOM_RELEASE_TYPE_PREFIX . $nameToken, $nameToken . 'S', 'RELEASE_TYPE_' . $nameToken, $nameToken) {
		$name = Slim::Utils::Strings::cstring($client, $_) if Slim::Utils::Strings::stringExists($_);
		last if $name;
	}

	return $name || $releaseType;
}

# Update the title dynamically if we're part of a set.
sub title {
	my $self = shift;

	return $self->set_column('title', shift) if @_;

	if ($prefs->get('groupdiscs')) {

		return $self->get_column('title');
	}

	return Slim::Music::Info::addDiscNumberToAlbumTitle(
		map { $self->get_column($_) } qw(title disc discc)
	);
}

# return the raw title untainted by Lyrion Music Server logic
sub rawtitle {
	my $self = shift;

	return $self->get_column('title');
}

sub displayAsHTML {
	my ($self, $form, $descend, $sort, $anchortextRef) = @_;

	$form->{'text'}       = $self->title;
	$form->{'coverThumb'} = $self->artwork || 0;
	$form->{'size'}       = $prefs->get('thumbSize');
	$form->{'albumId'}    = $self->id;
	$form->{'item'}       = $form->{'text'};
	$form->{'albumTitle'} = $form->{'text'};
	$form->{'attributes'} = "&album.id=" . $form->{'albumId'};

	# Show the year if pref set or storted by year first
	if (my $showYear = $prefs->get('showYear') || ($sort && $sort =~ /^album\.year/)) {
		$form->{'showYear'} = $showYear;
		$form->{'year'}     = $self->year;
	}

	# Show the artist in the album view
	my $showArtists = ($sort && $sort =~ /^contributor\.namesort/);

	if ($prefs->get('showArtist') || $showArtists) {
		my $contributor_sth = Slim::Schema->dbh->prepare_cached(sprintf(qq(
			SELECT DISTINCT(contributor_album.contributor), contributors.name
			FROM contributor_album, contributors
			WHERE contributor_album.album = ? AND contributor_album.role IN (%s,%s) AND contributors.id = contributor_album.contributor
		), map { Slim::Schema::Contributor->typeToRole($_) } qw(ARTIST TRACKARTIST)) );

		my ($contributorId, $contributorName);
		$contributor_sth->execute($form->{'albumId'});
		$contributor_sth->bind_col( 1, \$contributorId );
		$contributor_sth->bind_col( 2, \$contributorName );

		my @info;

		while ($contributor_sth->fetch) {
			utf8::decode($contributorName);

			push @info, {
				'artistId'   => $contributorId,
				'name'       => $contributorName,
				'attributes' => 'contributor.id=' . $contributorId,
			};
		}

		if (scalar @info) {
			$form->{'includeArtist'} = 1;
			$form->{'artistsWithAttributes'} = \@info;
		}
	}
}

sub artistsForRoles {
	my ($self, @types) = @_;

	my @roles = map { Slim::Schema::Contributor->typeToRole($_) } @types;

	return $self
		->search_related('contributorAlbums', { 'role' => { 'in' => \@roles } }, { 'order_by' => 'role desc' })
		->search_related('contributor')->distinct->all;
}

sub artistPerformsOnWork {
	my ($self, $work, $grouping, $artist) = @_;

	my $sth = Slim::Schema->dbh->prepare_cached(
		qq{
			SELECT count(*)
			from albums
			JOIN tracks ON albums.id = tracks.album
			JOIN contributor_track ON tracks.id = contributor_track.track
			WHERE tracks.work = :work
			AND albums.id = :album
			AND contributor_track.contributor = :artist
			AND ( (:grouping IS NULL AND tracks.grouping IS NULL) OR tracks.grouping = :grouping )
		}
	);

	$sth->bind_param(":work", $work);
	$sth->bind_param(":album", $self->id);
	$sth->bind_param(":artist", $artist);
	$sth->bind_param(":grouping", $grouping);
	$sth->execute();

	my ($count) = $sth->fetchrow_array;
	$sth->finish;
	return $count
}

# Return an array of artists associated with this album.
sub artists {
	my $self = shift;

	# First try to fetch an explict album artist
	my @artists = $self->artistsForRoles('ALBUMARTIST');

	# If the user wants to use BAND as album artist, pull that.
	if (scalar @artists == 0 && $prefs->get('bandInArtists')) {

		@artists = $self->artistsForRoles('BAND');
	}

	# Nothing there, and we're not a compilation? Get a list of artists.
	if (scalar @artists == 0 && (!$prefs->get('variousArtistAutoIdentification') || !$self->compilation)) {

		@artists = $self->artistsForRoles('ARTIST');
	}

	# Still nothing? Use the singular contributor - which might be the $vaObj
	if (scalar @artists == 0 && $self->compilation) {

		@artists = Slim::Schema->variousArtistsObject;

	} elsif (scalar @artists == 0) {

		if ( main::DEBUGLOG && $log->is_debug ) {
			$log->debug(sprintf("\%artists == 0 && \$self->contributor - returning: [%s]", $self->contributors));
		}

		@artists = $self->contributors;
	}

	return @artists;
}

sub artistsWithAttributes {
	my $self = shift;

	if ($self->cachedArtistsWithAttributes) {
		return $self->cachedArtistsWithAttributes;
	}

	my @artists  = ();
	my $vaString = Slim::Music::Info::variousArtistString();

	for my $artist ($self->artists) {

		my @attributes = join('=', 'contributor.id', $artist->id);

		if ($artist->name eq $vaString) {

			push @attributes, join('=', 'album.compilation', 1);
		}

		push @artists, {
			'artist'     => $artist,
			'name'       => $artist->name,
			'attributes' => join('&', @attributes),
		};
	}

	$self->cachedArtistsWithAttributes(\@artists);

	return \@artists;
}

# access the id, not the relation
sub contributorid {
	my $self = shift;

	return $self->get_column('contributor');
}

sub findhash {
	my ( $class, $id ) = @_;

	my $sth = Slim::Schema->dbh->prepare_cached( qq{
		SELECT * FROM albums WHERE id = ?
	} );

	$sth->execute($id);
	my $hash = $sth->fetchrow_hashref;
	$sth->finish;

	return $hash || {};
}

# Rescan list of albums, this simply means to make sure at least 1 track
# from this album still exists in the database.  If not, delete the album.
sub rescan {
	my ( $class, @ids ) = @_;

	my $slog = logger('scan.scanner');

	my $dbh = Slim::Schema->dbh;

	for my $id ( @ids ) {
		my $sth = $dbh->prepare_cached( qq{
			SELECT COUNT(*) FROM tracks WHERE album = ?
		} );
		$sth->execute($id);
		my ($count) = $sth->fetchrow_array;
		$sth->finish;

		if ( !$count ) {
			main::DEBUGLOG && $slog->is_debug && $slog->debug("Removing unused album: $id");
			$dbh->do( "DELETE FROM albums WHERE id = ?", undef, $id );

			# Bug 17283, this removed album may be cached as lastAlbum in Schema
			Slim::Schema->wipeLastAlbumCache($id);
		}
	}
}

sub duration {
	my $self = shift;
	my $workId = shift;
	my $grouping = shift;

	my $secs = 0;
	foreach ($self->tracks) {
		return if !defined $_->secs;
		$secs += $_->secs if !$workId || $_->get_column('work') == $workId && $_->get_column('grouping') eq $grouping;
	}
	return sprintf('%s:%02s', int($secs / 60), $secs % 60);
}

1;

__END__
