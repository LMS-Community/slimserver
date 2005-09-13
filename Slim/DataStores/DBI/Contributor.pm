package Slim::DataStores::DBI::Contributor;

# $Id$

use strict;
use base 'Slim::DataStores::DBI::DataModel';

our %contributorToRoleMap = (
	'ARTIST'      => 1,
	'COMPOSER'    => 2,
	'CONDUCTOR'   => 3,
	'BAND'        => 4,
	'ALBUMARTIST' => 5,
);

{
	my $class = __PACKAGE__;

	$class->table('contributors');

	$class->columns(Primary => qw/id/);

	$class->columns(Essential => qw/name namesort moodlogic_id moodlogic_mixable musicmagic_mixable/);

	$class->columns(Others => qw/namesearch/);

	$class->columns(Stringify => qw/name/);

	$class->has_many('contributorTracks' => ['Slim::DataStores::DBI::ContributorTrack' => 'contributor']);
}

sub contributorRoles {
	my $class = shift;

	return keys %contributorToRoleMap;
}

sub totalContributorRoles {
	my $class = shift;

	return scalar keys %contributorToRoleMap;
}

sub typeToRole {
	my $class = shift;
	my $type  = shift;

	return $contributorToRoleMap{$type};
}

sub add {
	my $class      = shift;
	my $artist     = shift;
	my $role       = shift;
	my $track      = shift;
	my $artistSort = shift || $artist;
	my $create     = shift || 0;

	my @contributors = ();

	# Dynamically determine the constructor if the caller wants to force
	# object creation.
	my $createMethod = $create ? 'create' : 'find_or_create';

	# Handle the case where $artist is already an object:
	if (ref $artist && ref($artist) ne 'ARRAY' && $artist->isa('Slim::DataStores::DBI::Contributor')) {

		my $contributorTrack = Slim::DataStores::DBI::ContributorTrack->$createMethod({
			track => $track,
			contributor => $artist,
			namesort => Slim::Utils::Text::ignoreCaseArticles($artist),
		});

		$contributorTrack->role($role);
		$contributorTrack->update;

		return wantarray ? ($artist) : $artist;
	}

	# Split both the regular and the normalized tags
	my @artistList   = Slim::Music::Info::splitTag($artist);
	my @sortedList   = Slim::Music::Info::splitTag($artistSort);

	for (my $i = 0; $i < scalar @artistList; $i++) {

		# The search columnn is the canonical text that we match against in a search.
		my $name   = $artistList[$i];
		my $search = Slim::Utils::Text::ignoreCaseArticles($name);
		my $sort   = Slim::Utils::Text::ignoreCaseArticles(($sortedList[$i] || $name));

		my $artistObj = Slim::DataStores::DBI::Contributor->find_or_create({ 
			namesearch => $search,
		});

		$artistObj->name($name);
		$artistObj->namesort($sort);
		$artistObj->update;

		push @contributors, $artistObj;

		# Create a contributor <-> track mapping table.
		my $contributorTrack = Slim::DataStores::DBI::ContributorTrack->$createMethod({
			track => $track,
			contributor => $artistObj,
			namesort => $sort,
		});

		$contributorTrack->role($role);
		$contributorTrack->update;
	}

	return wantarray ? @contributors : $contributors[0];
}

1;

__END__


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
