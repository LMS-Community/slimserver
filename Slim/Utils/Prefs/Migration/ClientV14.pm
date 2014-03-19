package Slim::Utils::Prefs::Migration::ClientV14;

use strict;

sub init {
	my ($class, $prefs) = @_;
	
	# Update scrolling prefs for client-side scrolling
	$prefs->migrateClient( 14, sub {
		my ( $cprefs, $client ) = @_;
		
		if ( $client->isa('Slim::Player::Squeezebox2') ) {
			$cprefs->set( scrollRate         => 0.033 );
			$cprefs->set( scrollRateDouble   => 0.033 );
			$cprefs->set( scrollPixels       => 2 );
			$cprefs->set( scrollPixelsDouble => 3 );
		}
		
		1;
	} );	
	
}

1;