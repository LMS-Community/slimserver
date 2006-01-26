package Slim::DataStores::DBI::Genre;

# $Id$

use strict;
use base 'Slim::DataStores::DBI::DataModel';
use Scalar::Util qw(blessed);

{
	my $class = __PACKAGE__;

	$class->table('genres');

	$class->columns(Primary => qw/id/);

	$class->columns(Essential => qw/name namesort moodlogic_id moodlogic_mixable musicmagic_mixable/);

	$class->columns(Others => qw/namesearch customsearch/);

	$class->columns(Stringify => qw/name/);

	$class->columns(UTF8 => qw/name namesort/);

	$class->has_many('genreTracks' => ['Slim::DataStores::DBI::GenreTrack' => 'genre']);
}

sub add {
	my $class = shift;
	my $genre = shift;
	my $track = shift;

	my @genres = ();

	for my $genreSub (Slim::Music::Info::splitTag($genre)) {

		my $namesort = Slim::Utils::Text::ignoreCaseArticles($genreSub);

		my ($genreObj) = Slim::DataStores::DBI::Genre->search({ 
			'namesort' => $namesort,
		});

		if (!defined $genreObj) {

			# So that ucfirst() works properly.
			use locale;

			$genreObj = Slim::DataStores::DBI::Genre->create({ 
				'namesort'   => $namesort,
				'name'       => ucfirst($genreSub),
				'namesearch' => $namesort,
			});
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
