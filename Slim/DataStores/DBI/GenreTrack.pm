package Slim::DataStores::DBI::GenreTrack;

# $Id$
#
# Genre to track mapping class

use strict;
use base 'Slim::DataStores::DBI::DataModel';

{
	my $class = __PACKAGE__;

	$class->table('genre_track');

	$class->columns(Primary => qw/id/);

	$class->columns(Essential => qw/genre track/);

	$class->has_a(genre => 'Slim::DataStores::DBI::Genre');
	$class->has_a(track => 'Slim::DataStores::DBI::Track');

	$class->add_constructor('genresFor' => 'track = ?');
}

sub add {
	my $class = shift;
	my $genre = shift;
	my $track = shift;

	my @genres = ();

	# Handle the case where $genre is already an object:
	if (ref $genre && $genre->isa('Slim::DataStores::DBI::Genre')) {

		Slim::DataStores::DBI::GenreTrack->find_or_create({
			track => $track,
			genre => $genre,
		});

		return wantarray ? ($genre) : $genre;
	}

	for my $genreSub (Slim::Music::Info::splitTag($genre)) {

		my $namesort = Slim::Utils::Text::ignoreCaseArticles($genreSub);

		my ($genreObj) = Slim::DataStores::DBI::Genre->search({ 
			namesort => $namesort,
		});

		if (!defined $genreObj) {

			$genreObj = Slim::DataStores::DBI::Genre->create({ 
				namesort => $namesort,
			});

			$genreObj->name(ucfirst($genreSub)),
			$genreObj->namesearch($namesort);
			$genreObj->update;
		}

		push @genres, $genreObj;
		
		Slim::DataStores::DBI::GenreTrack->find_or_create({
			track => $track,
			genre => $genreObj,
		});
	}

	return wantarray ? @genres : $genres[0];
}

1;

__END__


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
