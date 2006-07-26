package Slim::Schema::Genre;

# $Id$

use strict;
use base 'Slim::Schema::DBI';
use Scalar::Util qw(blessed);

use Slim::Utils::Misc;

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
	$class->add_unique_constraint('namesearch' => [qw/namesearch/]);

	$class->has_many('genreTracks' => 'Slim::Schema::GenreTrack' => 'genre');

	if ($] > 5.007) {
		$class->utf8_columns(qw/name namesort/);
	}

	$class->resultset_class('Slim::Schema::ResultSet::Genre');
}

sub url {
	my $self = shift;

	return Slim::Utils::Misc::escape(sprintf('db:genre.namesearch=%s', $self->namesearch));
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

		# So that ucfirst() works properly.
		use locale;

		my $genreObj = Slim::Schema->resultset('Genre')->search_or_create({ 
			'namesort'   => $namesort,
			'name'       => ucfirst($genreSub),
			'namesearch' => $namesort,
		}, { 'key' => 'namesearch' });

		Slim::Schema->resultset('GenreTrack')->find_or_create({
			track => $track->id,
			genre => $genreObj->id,
		});

		push @genres, $genreObj;
	}

	return wantarray ? @genres : $genres[0];
}

1;

__END__
