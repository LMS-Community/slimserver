package Slim::DataStores::DBI::Album;

# $Id$

use strict;
use base 'Slim::DataStores::DBI::DataModel';

use Slim::Utils::Misc;

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

	# XXXX - DBIx::Class
	#$class->columns(UTF8 => qw/title titlesort/);

	$class->belongs_to('contributor' => 'Slim::DataStores::DBI::Contributor');

	$class->has_many(
		'tracks' => 'Slim::DataStores::DBI::Track',
		undef,
		{ 'order_by' => 'disc,tracknum,titlesort' }
	);

	$class->has_many('contributorAlbums' => 'Slim::DataStores::DBI::ContributorAlbum');
}

# Do a proper join
sub contributors {

  return shift->contributorAlbums->search_related(
	'contributor', undef, { distinct => 1 })->search(@_);

	my $self = shift;

	# XXX - we need to do our own 'DISTINCT' until mst adds support.
        # MST - I did

	my @contributors = Slim::DataStores::DBI::Contributor->search(
		{ 'album.id' => $self->id },
		{ 'join'     => { 'contributorAlbums' => 'album' } }
	);

	my %unique = map { $_->id => $_ } @contributors;

	return values %unique;
}

sub hasArtwork {
	my $class = shift;

	# This has the same sort order as %DataModel::sortFieldMap{'album'}
	return $class->search_literal('artwork IS NOT NULL ORDER BY titlesort, disc');
}

sub stringify {
	my $self = shift;

	return $self->get_column('title');
}

# Update the title dynamically if we're part of a set.
sub title {
	my $self = shift;

	return $self->set_column(shift) if @_;

	if (Slim::Utils::Prefs::get('groupdiscs')) {

		return $self->get_column('title');
	}

	return Slim::Music::Info::addDiscNumberToAlbumTitle( $self->get(qw(title disc discc)) );
}

sub artistsForRole {
	my ($self, $role) = @_;

	my %artists = ();

	my $it = Slim::DataStores::DBI::ContributorAlbum->contributorsForAlbumAndRole(
		$self->id,
		Slim::DataStores::DBI::Contributor->typeToRole($role),
	);

	while (my $contributorAlbum = $it->next) {

		my $artist = $contributorAlbum->contributor;

		$artists{ $artist->id } = $artist;
	}

	if ($::d_info) {

		msgf("\tFetching contributors for role: [%s]\n", $role);

		while (my ($id, $artist) = each %artists) {
			msgf("\tArtist: [%s]\n", $artist->name);
		}
	}

	return values %artists;
}

# Return an array of artists associated with this album.
sub artists {
	my $self = shift;

	$::d_info && msgf("Album: [%s]\n", $self->title);

	# First try to fetch an explict album artist
	my @artists = $self->artistsForRole('ALBUMARTIST');

	# If the user wants to use TPE2 as album artist, pull that.
	if (@artists == 0 && Slim::Utils::Prefs::get('useBandAsAlbumArtist')) {

		@artists = $self->artistsForRole('BAND');
	}

	# Nothing there, and we're not a compilation? Get a list of artists.
	if (@artists == 0 && (!Slim::Utils::Prefs::get('variousArtistAutoIdentification') || !$self->compilation)) {

		@artists = $self->artistsForRole('ARTIST');
	}

	# Still nothing? Use the singular contributor - which might be the $vaObj
	if (@artists == 0 && $self->compilation) {

		@artists = Slim::DataStores::DBI::DBIStore->variousArtistsObject;

	} elsif (@artists == 0 && $self->contributor) {

		$::d_info && msgf("\t\%artists == 0 && \$self->contributor - returning: [%s]\n", $self->contributor);

		@artists = $self->contributor;
	}

	return @artists;
}

sub artistsWithAttributes {
	my $self = shift;

	my @artists = ();

	for my $artist ($self->artists) {

		my @attributes = join('=', 'artist', $artist->id);

		if ($artist->name eq Slim::Music::Info::variousArtistString()) {

			push @attributes, join('=', 'album.compilation', 1);
		}

		push @artists, {
			'artist'     => $artist,
			'attributes' => join('&', @attributes),
		};
	}

	return \@artists;
}

1;

__END__


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
