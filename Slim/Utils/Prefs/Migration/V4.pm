package Slim::Utils::Prefs::Migration::V4;

use strict;

sub init {
	my ($class, $prefs) = @_;
		
	$prefs->migrate( 4, sub {
		$prefs->set('librarycachedir', $prefs->get('cachedir'));
		1;
	} );
}

1;