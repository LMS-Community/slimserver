package Slim::DataStores::DBI::GenreTrack;

# $Id$
#
# Genre to track mapping class

use strict;
use base 'Slim::DataStores::DBI::DataModel';

{
	my $class = __PACKAGE__;

	$class->table('genre_track');
	$class->columns(Essential => qw/id genre track/);

	$class->has_a(genre => 'Slim::DataStores::DBI::Genre');
	$class->has_a(track => 'Slim::DataStores::DBI::Track');

	$class->add_constructor('genresFor' => 'track = ?');
}

tie our %_cache, 'Tie::Cache::LRU::Expires', EXPIRES => 1200, ENTRIES => 25;

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

		# Try and fetch the genre from the cache. Otherwise, search
		# for it based on the normalized namesort. If that doesn't
		# work, create it, and upper case the first letter.
		unless ($_cache{$genreSub}) {

			my $namesort = Slim::Utils::Text::ignoreCaseArticles($genreSub);
			my $genreObj;

			($genreObj) = Slim::DataStores::DBI::Genre->search({ 
				namesort => $namesort
			});

			unless ($_cache{$genreSub}) {

				$genreObj = Slim::DataStores::DBI::Genre->create({ 
					name     => ucfirst($genreSub),
					namesort => $namesort,
				});
			}

			if ($Class::DBI::Weaken_Is_Available) {

				Scalar::Util::weaken($_cache{$genreSub} = $genreObj);

			} else {

				$_cache{$genreSub} = $genreObj;
			}
		}

		push @genres, $_cache{$genreSub};
		
		Slim::DataStores::DBI::GenreTrack->find_or_create({
			track => $track,
			genre => $_cache{$genreSub},
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
