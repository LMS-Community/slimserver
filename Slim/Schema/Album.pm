package Slim::Schema::Album;

# $Id$

use strict;
use base 'Slim::Schema::DBI';

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
	), title => { accessor => undef() });

	$class->set_primary_key('id');
	$class->add_unique_constraint('titlesearch' => [qw/id titlesearch/]);

	$class->belongs_to('contributor' => 'Slim::Schema::Contributor');

	$class->has_many('tracks'            => 'Slim::Schema::Track'            => 'album');
	$class->has_many('contributorAlbums' => 'Slim::Schema::ContributorAlbum' => 'album');

	if ($] > 5.007) {
		$class->utf8_columns(qw/title titlesort/);
	}

	$class->resultset_class('Slim::Schema::ResultSet::Album');

	# Simple caching as artistsWithAttributes is expensive.
	$class->mk_group_accessors('simple' => 'cachedArtistsWithAttributes');
}

sub url {
	my $self = shift;

	return sprintf('db:album.title=%s', URI::Escape::uri_escape_utf8($self->title));
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

# return the raw title untainted by Logitech Media Server logic
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
	
	my $secs = 0;
	foreach ($self->tracks) {
		return if !defined $_->secs;
		$secs += $_->secs;
	}
	return sprintf('%s:%02s', int($secs / 60), $secs % 60);
}

1;

__END__
