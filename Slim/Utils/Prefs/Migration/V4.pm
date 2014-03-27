package Slim::Utils::Prefs::Migration::V4;

use strict;

use base qw(Slim::Utils::Prefs::Migration);

sub migrate {
	my ($class, $prefs) = @_;
		
	$prefs->migrate( 4, sub {
		$prefs->set('librarycachedir', $prefs->get('cachedir'));
		1;
	} );
	
	# for whatever reasons we don't have versions 5-7, but we need to bump the version anyway
	$prefs->migrate( 7, sub { 1 } );
}

1;