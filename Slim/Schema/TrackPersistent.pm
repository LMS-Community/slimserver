package Slim::Schema::TrackPersistent;


use strict;
use base 'Slim::Schema::DBI';

use File::Slurp qw(read_file);
use JSON::XS::VersionOneAndTwo;
use Scalar::Util qw(blessed);

use Slim::Utils::DateTime;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;

my $prefs = preferences('server');

our @allColumns = ( qw(
	id urlmd5 url musicbrainz_id added playcount lastplayed rating
) );

{
	my $class = __PACKAGE__;

	$class->table('tracks_persistent');

	$class->add_columns( @allColumns );

	$class->set_primary_key('id');
}

sub attributes {
	my $class = shift;

	# Return a hash ref of column names
	return { map { $_ => 1 } @allColumns };
}

sub addedTime {
	my $self = shift;

	return Slim::Schema::Track->buildModificationTime($self->added);
}

sub import_json {
	if ( main::SCANNER ) {
		my ( $class, $json ) = @_;

		my $tracks = eval { from_json( read_file($json) ) };
		if ( $@ ) {
			logError($@);
			return;
		}

		for my $track ( @{$tracks} ) {
			my $tp;
			if ( $track->{mb} ) {
				$tp = Slim::Schema->first('TrackPersistent', { musicbrainz_id => $track->{mb} } );
			}
			else {
				$tp = Slim::Schema->first('TrackPersistent', { url => $track->{url} } );
			}

			next unless $tp;

			for my $key ( qw(lastplayed playcount rating) ) {
				$tp->$key( $track->{$key} );
			}

			$tp->update;
		}

		return 1;
	}
}

# Faster return of data as a hash
sub findhash {
	my ( $class, $mbid, $urlmd5 ) = @_;

	my $sth;

	if ($mbid) {
		$sth = Slim::Schema->dbh->prepare_cached( qq{
			SELECT *
			FROM tracks_persistent
			WHERE (	urlmd5 = ? OR musicbrainz_id = ? )
		} );

		$sth->execute( $urlmd5, $mbid );
	}
	else {
		$sth = Slim::Schema->dbh->prepare_cached( qq{
			SELECT *
			FROM tracks_persistent
			WHERE urlmd5 = ?
		} );

		$sth->execute( $urlmd5 );
	}

	my $hash = $sth->fetchrow_hashref;

	$sth->finish;

	return $hash;
}

1;

__END__
