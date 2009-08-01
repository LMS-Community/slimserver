package Slim::Schema::Genre;

# $Id$

use strict;
use base 'Slim::Schema::DBI';
use Scalar::Util qw(blessed);

use Slim::Schema::ResultSet::Genre;

use Slim::Utils::Misc;
use Slim::Utils::Log;

{
	my $class = __PACKAGE__;

	$class->table('genres');

	$class->add_columns(qw(
		id
		name
		namesort
		namesearch
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

	return sprintf('db:genre.namesearch=%s', URI::Escape::uri_escape($self->namesearch));
}

sub tracks {
	my $self = shift;

	return $self->genreTracks->search_related('track' => @_);
}

sub displayAsHTML {
	my ($self, $form, $descend, $sort) = @_;

	$form->{'text'}       = $self->name;

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
	
	# Using native DBI here to improve performance during scanning
	# and because DBIC objects are not needed here
	# This is around 20x faster than using DBIC
	my $dbh = Slim::Schema->storage->dbh;

	for my $genreSub (Slim::Music::Info::splitTag($genre)) {

		my $namesort = Slim::Utils::Text::ignoreCaseArticles($genreSub);

		# So that ucfirst() works properly.
		use locale;
		
		my $sth = $dbh->prepare_cached( 'SELECT id FROM genres WHERE namesearch = ?' );
		$sth->execute($namesort);
		my ($id) = $sth->fetchrow_array;
		$sth->finish;
		
		if ( !$id ) {
			$sth = $dbh->prepare_cached( qq{
				INSERT INTO genres
				(namesort, name, namesearch)
				VALUES
				(?, ?, ?)
			} );
			$sth->execute( $namesort, ucfirst($genreSub), $namesort );
			$id = $dbh->last_insert_id(undef, undef, undef, undef);
		}
		
		$sth = $dbh->prepare_cached( qq{
			REPLACE INTO genre_track
			(genre, track)
			VALUES
			(?, ?)
		} );
		$sth->execute( $id, $track->id );
	}
	
	return;
}

# XXX native DBI
sub rescan {
	my ( $class, @ids ) = @_;
	
	my $log = logger('scan.scanner');
	
	for my $id ( @ids ) {
		my $count = Slim::Schema->rs('GenreTrack')->search( genre => $id )->count;
		
		if ( !$count ) {
			main::DEBUGLOG && $log->is_debug && $log->debug("Removing unused genre: $id");
			Slim::Schema->rs('Genre')->find($id)->delete;
		}
	}
}

1;

__END__
