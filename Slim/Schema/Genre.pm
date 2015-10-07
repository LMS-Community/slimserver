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

	return sprintf('db:genre.name=%s', URI::Escape::uri_escape_utf8($self->name));
}

sub tracks {
	my $self = shift;

	return $self->genreTracks->search_related('track' => @_);
}

sub displayAsHTML {
	my ($self, $form, $descend, $sort) = @_;

	$form->{'text'} = $self->name;
}

sub add {
	my $class = shift;
	my $genre = shift;
	my $trackId = shift;
	
	# Using native DBI here to improve performance during scanning
	# and because DBIC objects are not needed here
	# This is around 20x faster than using DBIC
	my $dbh = Slim::Schema->dbh;

	for my $genreSub (Slim::Music::Info::splitTag($genre)) {

		my $namesort = Slim::Utils::Text::ignoreCaseArticles($genreSub);
		my $namesearch = Slim::Utils::Text::ignoreCase($genreSub, 1);

		# So that ucfirst() works properly.
		use locale;
		
		my $sth = $dbh->prepare_cached( 'SELECT id FROM genres WHERE name = ?' );
		$sth->execute( ucfirst($genreSub) );
		my ($id) = $sth->fetchrow_array;
		$sth->finish;
		
		if ( !$id ) {
			$sth = $dbh->prepare_cached( qq{
				INSERT INTO genres
				(namesort, name, namesearch)
				VALUES
				(?, ?, ?)
			} );
			$sth->execute( $namesort, ucfirst($genreSub), $namesearch );
			$id = $dbh->last_insert_id(undef, undef, undef, undef);
		}
		
		$sth = $dbh->prepare_cached( qq{
			REPLACE INTO genre_track
			(genre, track)
			VALUES
			(?, ?)
		} );
		$sth->execute( $id, $trackId );
	}
	
	return;
}

sub rescan {
	my ( $class, @ids ) = @_;
	
	my $dbh = Slim::Schema->dbh;
	
	my $log = logger('scan.scanner');
	
	for my $id ( @ids ) {
		my $sth = $dbh->prepare_cached( qq{
			SELECT COUNT(*) FROM genre_track WHERE genre = ?
		} );
		$sth->execute($id);
		my ($count) = $sth->fetchrow_array;
		$sth->finish;
				
		if ( !$count ) {
			main::DEBUGLOG && $log->is_debug && $log->debug("Removing unused genre: $id");
			
			$dbh->do( "DELETE FROM genres WHERE id = ?", undef, $id );
		}
	}
}

1;

__END__
