package Slim::DataStores::DBI::Contributor;

# $Id$

use strict;
use base 'Slim::DataStores::DBI::DataModel';
use Scalar::Util qw(blessed);

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

	$class->columns(Others => qw/namesearch customsearch musicbrainz_id/);

	$class->columns(Stringify => qw/name/);

	$class->columns(UTF8 => qw/name namesort/);

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

		my ($contributorObj) = Slim::DataStores::DBI::Contributor->search({
			'namesearch' => $search,
		});

		if (!$contributorObj) {

			$contributorObj = Slim::DataStores::DBI::Contributor->create({ 
				'namesearch'     => $search,
				'name'           => $name,
				'namesort'       => $sort,
				'musicbrainz_id' => $brainzID,
			});
		}

		push @contributors, $contributorObj;

		# Create a contributor <-> track mapping table.
		Slim::DataStores::DBI::ContributorTrack->find_or_create({
			'track'       => $track,
			'contributor' => $contributorObj,
			'role'        => $role,
		});
	}

	return wantarray ? @contributors : $contributors[0];
}

1;

__END__


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
