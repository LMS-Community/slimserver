package Slim::Utils::Prefs::Migration::ClientV5;

use strict;

sub init {
	my ($class, $prefs) = @_;
	
	# Bug 8690, reset fixed digital volume pref because it now affects analog outputs
	$prefs->migrateClient( 5, sub {
		my ( $cprefs, $client ) = @_;
		my $dvc = $cprefs->get('digitalVolumeControl');
		if ( defined $dvc && $dvc == 0 ) {
			$cprefs->set( digitalVolumeControl => 1 );
			if ( $cprefs->get('volume') > 50 ) {
				$cprefs->set( volume => 50 );
			}
		}
		
		return 1;
	} );
	
}

1;