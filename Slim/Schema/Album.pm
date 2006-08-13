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

	return sprintf('db:album.titlesearch=%s', Slim::Utils::Misc::escape($self->titlesearch));
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

	if (Slim::Utils::Prefs::get('groupdiscs')) {

		return $self->get_column('title');
	}

	return Slim::Music::Info::addDiscNumberToAlbumTitle(
		map { $self->get_column($_) } qw(title disc discc)
	);
}

# return the raw title untainted by slimserver logic
sub rawtitle {
	my $self = shift;
	
	return $self->get_column('title');
}

sub displayAsHTML {
	my ($self, $form, $descend, $sort, $anchortextRef) = @_;

	$form->{'text'}       = $self->title;
	$form->{'coverThumb'} = $self->artwork || 0;
	$form->{'size'}       = Slim::Utils::Prefs::get('thumbSize');

	$form->{'item'}       = $self->title;

	# Show the year if pref set or storted by year first
	if (my $showYear = Slim::Utils::Prefs::get('showYear') || ($sort && $sort =~ /^album\.year/)) {

		$form->{'showYear'} = $showYear;
		$form->{'year'}     = $self->year;
	}

	# Show the artist in the album view
	my $showContributor = ($sort && $sort =~ /^contributor\.namesort/);

	if (Slim::Utils::Prefs::get('showArtist') || $showContributor) {

		# XXX - only show the contributor when there are multiple
		# contributors in the album view.
		# if ($form->{'hierarchy'} ne 'contributor,album,track') {

			if (my $contributor = $self->contributors->first) {

				$form->{'artist'}        = $contributor;
				#$form->{'includeArtist'} = defined $findCriteria->{'artist'} ? 0 : 1;
				$form->{'noArtist'}      = Slim::Utils::Strings::string('NO_ARTIST');
				
				if ($showContributor) {
					# override default field for anchors with contributor.namesort
					$$anchortextRef = $contributor->namesort;
				}
			}
		# }
	}

	my $Imports = Slim::Music::Import->importers;

	for my $mixer (keys %{$Imports}) {
	
		if (defined $Imports->{$mixer}->{'mixerlink'}) {
			&{$Imports->{$mixer}->{'mixerlink'}}($self, $form, $descend);
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

	# If the user wants to use TPE2 as album artist, pull that.
	if (scalar @artists == 0 && Slim::Utils::Prefs::get('useBandAsAlbumArtist')) {

		@artists = $self->artistsForRoles('BAND');
	}

	# Nothing there, and we're not a compilation? Get a list of artists.
	if (scalar @artists == 0 && (!Slim::Utils::Prefs::get('variousArtistAutoIdentification') || !$self->compilation)) {

		@artists = $self->artistsForRoles('ARTIST');
	}

	# Still nothing? Use the singular contributor - which might be the $vaObj
	if (scalar @artists == 0 && $self->compilation) {

		@artists = Slim::Schema->variousArtistsObject;

	} elsif (scalar @artists == 0) {

		$::d_info && msgf("\t\%artists == 0 && \$self->contributor - returning: [%s]\n", $self->contributors);

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


1;

__END__
