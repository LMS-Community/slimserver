package Slim::DataStores::DBI::GenreTrack;

# $Id: GenreTrack.pm,v 1.1 2004/12/17 20:33:03 dsully Exp $
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

tie my %_cache, 'Tie::Cache::LRU', 5000;

sub add {
	my $class = shift;
	my $genre = shift;
	my $track = shift;

	my @genres = ();

	for my $genreSub (Slim::Music::Info::splitTag($genre)) {

		$genreSub =~ s/^\s*//o;
		$genreSub =~ s/\s*$//o;

		my $genreObj = $_cache{$genreSub} ||= Slim::DataStores::DBI::Genre->find_or_create({ 
			name => $genreSub,
		});

		push @genres, $genreObj;
		
		Slim::DataStores::DBI::GenreTrack->create({
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
