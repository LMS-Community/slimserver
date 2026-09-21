package Slim::Utils::Prefs::Migration::V10;

use strict;

use base qw(Slim::Utils::Prefs::Migration);

sub migrate {
	my ($class, $prefs) = @_;

	# fix possile corruption of cleanupReleaseTypes
	$prefs->migrate( 10, sub {
		$prefs->set('cleanupReleaseTypes', $prefs->get('cleanupReleaseTypes')->[0]) if ( ref $prefs->get('cleanupReleaseTypes') eq 'ARRAY' );
		1;
	} );
}

1;
