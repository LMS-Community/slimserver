package Slim::DataStores::DBI::ContributorTrack;

# $Id$
#
# Contributor to track mapping class

use strict;
use base 'Slim::DataStores::DBI::DataModel';

our %contributorToRoleMap = (
	'ARTIST'    => 1,
	'COMPOSER'  => 2,
	'CONDUCTOR' => 3,
	'BAND'      => 4,
);

{
	my $class = __PACKAGE__;

	$class->table('contributor_track');
	$class->columns(Essential => qw/id role contributor track namesort/);

	$class->has_a(contributor => 'Slim::DataStores::DBI::Contributor');
	$class->has_a(track => 'Slim::DataStores::DBI::Track');

	# xxx - removed album => $track->album(), creates database coherency problem
	#$class->has_a(album => 'Slim::DataStores::DBI::Album');

	$class->add_constructor('contributorsFor' => 'track = ?');
	$class->add_constructor('artistsFor'      => "track = ? AND role = $contributorToRoleMap{'ARTIST'}");
	$class->add_constructor('composersFor'    => "track = ? AND role = $contributorToRoleMap{'COMPOSER'}");
	$class->add_constructor('conductorsFor'   => "track = ? AND role = $contributorToRoleMap{'CONDUCTOR'}");
	$class->add_constructor('bandsFor'        => "track = ? AND role = $contributorToRoleMap{'BAND'}");
}

tie our %_cache, 'Tie::Cache::LRU::Expires', EXPIRES => 1200, ENTRIES => 25;

sub clearCache {
	my $class = shift;

	%_cache = ();
}

sub add {
	my $class      = shift;
	my $artist     = shift;
	my $role       = shift;
	my $track      = shift;
	my $artistSort = shift || $artist;

	my @contributors = ();

	# Handle the case where $genre is already an object:
	if (ref $artist && $artist->isa('Slim::DataStores::DBI::Contributor')) {

		Slim::DataStores::DBI::ContributorTrack->find_or_create({
			track => $track,
			contributor => $artist,
			role => $role,
			namesort => Slim::Utils::Text::ignoreCaseArticles($artist),
		});

		return wantarray ? ($artist) : $artist;
	}

	# Split both the regular and the normalized tags
	my @artistList   = Slim::Music::Info::splitTag($artist);
	my @sortedList   = Slim::Music::Info::splitTag($artistSort);
	
	for (my $i = 0; $i < scalar @artistList; $i++) {

		my $name = $artistList[$i];
		my $sort = Slim::Utils::Text::ignoreCaseArticles($sortedList[$i]);

		my $artistObj;

		if (defined $_cache{$name}) {

			$artistObj = $_cache{$name};

			# If we had an explicitly specified sort tag, modify
			# the existing object.
			if ($artist ne $artistSort) {
				$artistObj->namesort($sort);
			}

		} else {

			$artistObj = Slim::DataStores::DBI::Contributor->find_or_create({ 
				name => $name,
			});

			$artistObj->namesort($sort);
			$artistObj->update();

			# Try to prevent leaks and circular references.
			if ($Class::DBI::Weaken_Is_Available) {

				Scalar::Util::weaken($_cache{$name} = $artistObj);

			} else {

				$_cache{$name} = $artistObj;
			}
		}

		push @contributors, $artistObj;

		Slim::DataStores::DBI::ContributorTrack->find_or_create({
			track => $track,
			contributor => $artistObj,
			role => $role,
			namesort => $sort,
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
