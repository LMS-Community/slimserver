package Slim::DataStores::DBI::Genre;

# $Id$

use strict;
use base 'Slim::DataStores::DBI::DataModel';
use Scalar::Util qw(blessed);

{
	my $class = __PACKAGE__;

	$class->table('genres');

	$class->add_columns(qw(
		id
		name
		namesort
		namesearch
		moodlogic_id
		moodlogic_mixable
		musicmagic_mixable
	));

	$class->set_primary_key('id');

	$class->has_many('genreTracks' => 'Slim::DataStores::DBI::GenreTrack' => 'genre');

	if ($] > 5.007) {
		$class->utf8_columns(qw/name namesort/);
	}

	$class->resultset_class('Slim::DataStores::DBI::ResultSet::Genre');
}

sub tracks {
	my $self = shift;

	return $self->genreTracks->search_related('track' => @_);
}

sub displayAsHTML {
	my ($self, $form, $descend, $sort) = @_;

	my $Imports = Slim::Music::Import->importers;

	for my $mixer (keys %{$Imports}) {

		if (defined $Imports->{$mixer}->{'mixerlink'}) {
			&{$Imports->{$mixer}->{'mixerlink'}}($self, $form, $descend);
		}
	}
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
			track => $track->id,
			genre => $genreObj->id,
		});
	}

	return wantarray ? @genres : $genres[0];
}

sub stringify {
	my $self = shift;

	return $self->get_column('name');
}

1;

__END__


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
