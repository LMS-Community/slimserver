package Slim::Utils::Prefs::Migration::V2;

use strict;

use base qw(Slim::Utils::Prefs::Migration);

sub migrate {
	my ($class, $prefs) = @_;
	
	# rank of Staff Picks has changed
	$prefs->migrate( 2, sub {
		$prefs->set( 'rank-PLUGIN_PICKS_MODULE_NAME' => 25 );
	} );
}

1;