package Slim::Schema::Album;

# $Id$

use strict;
use base 'Slim::Schema::DBI';

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

	# Add alias for ->name, so that everyone can use the same accessors.
	$class->register_column('title', { accessor => 'name' });
	$class->register_column('titlesort', { accessor => 'namesort' });
	$class->register_column('titlesearch', { accessor => 'namesearch' });

	$class->set_primary_key('id');

	$class->belongs_to('contributor' => 'Slim::Schema::Contributor');

	$class->has_many(
		'tracks' => 'Slim::Schema::Track', undef,
		{ 'order_by' => [qw(disc tracknum titlesort)] }
	);

	$class->has_many('contributorAlbums' => 'Slim::Schema::ContributorAlbum');

	if ($] > 5.007) {
		$class->utf8_columns(qw/title titlesort/);
	}

	$class->resultset_class('Slim::Schema::ResultSet::Album');
}

# Do a proper join
sub contributors {
	my $self = shift;

	return $self->contributorAlbums->search_related(
		'contributor', undef, { distinct => 1 }
	)->search(@_);
}

sub hasArtwork {
	my $class = shift;

	return $class->search_literal('artwork IS NOT NULL ORDER BY titlesort, disc');
}

# Update the title dynamically if we're part of a set.
sub title {
	my $self = shift;

	return $self->set_column('title', shift) if @_;

	if (Slim::Utils::Prefs::get('groupdiscs')) {

		return $self->get_column('title');
	}

	return Slim::Music::Info::addDiscNumberToAlbumTitle(
		map { $self->get_column($_) } qw(title disc discc)
	);
}

sub displayAsHTML {
	my ($self, $form, $descend, $sort) = @_;

	$form->{'text'}       = $self->title;
	$form->{'coverThumb'} = $self->artwork || 0;
	$form->{'size'}       = Slim::Utils::Prefs::get('thumbSize');

	$form->{'item'}       = $self->title;

	# XXXX - need to pass sort along?
	if (my $showYear = Slim::Utils::Prefs::get('showYear') || $sort && $sort =~ /^year/) {

		# Don't show years when browsing years..
		#if (!$findCriteria->{'year'}) {
		#	$form->{'showYear'} = $showYear;
		#	$form->{'year'} = $self->year;
		#}
	}

	# Show the artist in the album view
	if (Slim::Utils::Prefs::get('showArtist') || $sort && $sort =~ /^artist/) {

		if (my $contributor = $self->contributor) {

			$form->{'artist'}        = $contributor;
			#$form->{'includeArtist'} = defined $findCriteria->{'artist'} ? 0 : 1;
			$form->{'noArtist'}      = Slim::Utils::Strings::string('NO_ARTIST');

		}
	}

	my $Imports = Slim::Music::Import->importers;

	for my $mixer (keys %{$Imports}) {
	
		if (defined $Imports->{$mixer}->{'mixerlink'}) {
			&{$Imports->{$mixer}->{'mixerlink'}}($self, $form, $descend);
		}
	}
}

sub artistsForRole {
	my ($self, $role) = @_;

	my %artists = ();

	my $it = Slim::Schema::ContributorAlbum->contributorsForAlbumAndRole(
		$self->id,
		Slim::Schema::Contributor->typeToRole($role),
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

		@artists = Slim::Schema->variousArtistsObject;

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

		my @attributes = join('=', 'contributor.id', $artist->id);

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
