package Slim::DataStores::DBI::ContributorTrack;

# $Id$
#
# Contributor to track mapping class

use strict;
use base 'Slim::DataStores::DBI::DataModel';

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

	$class->table('contributor_track');

	$class->columns(Primary => qw/id/);

	$class->columns(Essential => qw/role contributor track namesort/);

	$class->has_a(contributor => 'Slim::DataStores::DBI::Contributor');
	$class->has_a(track => 'Slim::DataStores::DBI::Track');

	# xxx - removed album => $track->album(), creates database coherency problem
	#$class->has_a(album => 'Slim::DataStores::DBI::Album');

	$class->add_constructor('contributorsFor' => 'track = ?');
	$class->add_constructor('artistsFor'      => "track = ? AND role = $contributorToRoleMap{'ARTIST'}");
	$class->add_constructor('composersFor'    => "track = ? AND role = $contributorToRoleMap{'COMPOSER'}");
	$class->add_constructor('conductorsFor'   => "track = ? AND role = $contributorToRoleMap{'CONDUCTOR'}");
	$class->add_constructor('bandsFor'        => "track = ? AND role = $contributorToRoleMap{'BAND'}");
	$class->add_constructor('albumArtistsFor' => "track = ? AND role = $contributorToRoleMap{'ALBUMARTIST'}");
	$class->add_constructor('trackArtistsFor' => "track = ? AND role = $contributorToRoleMap{'TRACKARTIST'}");
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
	if (ref $artist && $artist->isa('Slim::DataStores::DBI::Contributor')) {

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
		my $sort   = Slim::Utils::Text::ignoreCaseArticles($sortedList[$i]);

		my $artistObj = Slim::DataStores::DBI::Contributor->find_or_create({ 
			namesearch => $search,
		});

		$artistObj->name($name);
		$artistObj->namesort($sort);
		$artistObj->update;

		push @contributors, $artistObj;

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
