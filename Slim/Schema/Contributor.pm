package Slim::Schema::Contributor;

# $Id$

use strict;
use base 'Slim::Schema::DBI';
use Scalar::Util qw(blessed);

use Slim::Utils::Misc;

our %contributorToRoleMap = (
	'ARTIST'      => 1,
	'COMPOSER'    => 2,
	'CONDUCTOR'   => 3,
	'BAND'        => 4,
	'ALBUMARTIST' => 5,
	'TRACKARTIST' => 6,
);

{
	my $class = __PACKAGE__;

	$class->table('contributors');

	$class->add_columns(qw(
		id
		name
		namesort
		musicmagic_mixable
		namesearch
		musicbrainz_id
	));

	$class->set_primary_key('id');
	$class->add_unique_constraint('namesearch' => [qw/namesearch/]);

	$class->has_many('contributorTracks' => 'Slim::Schema::ContributorTrack');
	$class->has_many('contributorAlbums' => 'Slim::Schema::ContributorAlbum');

	$class->many_to_many('tracks', 'contributorTracks' => 'contributor', undef, {
		'distinct' => 1,
		'order_by' => [qw(disc tracknum titlesort)],
	});

	$class->many_to_many('albums', 'contributorAlbums' => 'album', undef, { 'distinct' => 1 });

	if ($] > 5.007) {
		$class->utf8_columns(qw/name namesort/);
	}

	$class->resultset_class('Slim::Schema::ResultSet::Contributor');
}

sub contributorRoles {
	my $class = shift;

	return sort keys %contributorToRoleMap;
}

sub totalContributorRoles {
	my $class = shift;

	return scalar keys %contributorToRoleMap;
}

sub typeToRole {
	my $class = shift;
	my $type  = shift;

	return $contributorToRoleMap{$type} || $type;
}

sub displayAsHTML {
	my ($self, $form, $descend, $sort) = @_;

	my $vaString = Slim::Music::Info::variousArtistString();

	$form->{'text'} = $self->name;
	
	if ($self->name eq $vaString) {
		$form->{'attributes'} .= "&album.compilation=1";
	}

	my $Imports = Slim::Music::Import->importers;

	for my $mixer (keys %{$Imports}) {

		if (defined $Imports->{$mixer}->{'mixerlink'}) {
			&{$Imports->{$mixer}->{'mixerlink'}}($self, $form, $descend);
		}
	}
}

# For saving favorites.
sub url {
	my $self = shift;

	return sprintf('db:contributor.namesearch=%s', Slim::Utils::Misc::escape($self->namesearch));
}

sub add {
	my $class = shift;
	my $args  = shift;

	# Pass args by name
	my $artist     = $args->{'artist'} || return;
	my $brainzID   = $args->{'brainzID'};
	my $role       = $args->{'role'}   || return;
	my $track      = $args->{'track'}  || return;
	my $artistSort = $args->{'sortBy'} || $artist;

	my @contributors = ();

	# Bug 1955 - Previously 'last one in' would win for a
	# contributorTrack - ie: contributor & role combo, if a track
	# had an ARTIST & COMPOSER that were the same value.
	#
	# If we come across that case, force the creation of a second
	# contributorTrack entry.
	#
	# Split both the regular and the normalized tags
	my @artistList   = Slim::Music::Info::splitTag($artist);
	my @sortedList   = Slim::Music::Info::splitTag($artistSort);

	for (my $i = 0; $i < scalar @artistList; $i++) {

		# The search columnn is the canonical text that we match against in a search.
		my $name   = $artistList[$i];
		my $search = Slim::Utils::Text::ignoreCaseArticles($name);
		my $sort   = Slim::Utils::Text::ignoreCaseArticles(($sortedList[$i] || $name));

		my $contributorObj = Slim::Schema->resultset('Contributor')->find_or_create({ 
			'namesearch'     => $search,
			'name'           => $name,
			'namesort'       => $sort,
			'musicbrainz_id' => $brainzID,
		}, { 'key' => 'namesearch' });

		if ($contributorObj && $search ne $sort) {

			# Bug 3069: update the namesort only if it's different than namesearch
			$contributorObj->namesort($sort);
			$contributorObj->update;
		}

		# Create a contributor <-> track mapping table.
		Slim::Schema->resultset('ContributorTrack')->find_or_create({
			'track'       => (ref $track ? $track->id : $track),
			'contributor' => $contributorObj->id,
			'role'        => $role,
		});

		push @contributors, $contributorObj;
	}

	return wantarray ? @contributors : $contributors[0];
}

1;

__END__
