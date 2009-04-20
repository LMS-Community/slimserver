package Slim::Schema::TrackPersistent;

# $Id:$

use strict;
use base 'Slim::Schema::DBI';

use File::Slurp qw(write_file);
use JSON::XS::VersionOneAndTwo;
use Scalar::Util qw(blessed);

use Slim::Utils::DateTime;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;

my $prefs = preferences('server');

our @allColumns = ( qw(
	id url musicbrainz_id track added playcount lastplayed rating
) );

{
	my $class = __PACKAGE__;

	$class->table('tracks_persistent');

	$class->add_columns( @allColumns );

	$class->set_primary_key('id');

	# setup our relationships
	$class->belongs_to( track => 'Slim::Schema::Track' );
}

sub attributes {
	my $class = shift;

	# Return a hash ref of column names
	return { map { $_ => 1 } @allColumns };
}

sub addedTime {
	my $self = shift;

	my $time = $self->added;

	return join( ', ', Slim::Utils::DateTime::longDateF($time), Slim::Utils::DateTime::timeF($time) );
}

sub export {
	my ( $class, $file ) = @_;
	
	my $export = [];
	
	# Only export items that have data
	my $find = [
		rating     => { '!=' => undef },
		playcount  => { '!=' => undef },
		lastplayed => { '!=' => undef },
	];
	
	my $rs = Slim::Schema->search( TrackPersistent => $find );
	
	while ( my $track = $rs->next ) {
		push @{$export}, {
			url        => $track->url,
			mb         => $track->musicbrainz_id,
			rating     => $track->rating,
			playcount  => $track->playcount,
			lastplayed => $track->lastplayed,
		};
	}
	
	write_file( $file, to_json($export) );
}

1;

__END__
