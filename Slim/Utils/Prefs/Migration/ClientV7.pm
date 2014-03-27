package Slim::Utils::Prefs::Migration::ClientV7;

use strict;

sub init {
	my ($class, $prefs) = @_;

	# Bug 8555, add Clock as an option to the Boom display options if it currently the previous default
	$prefs->migrateClient( 7, sub {
		my ( $cprefs, $client ) = @_;
		if ( $client->isa('Slim::Player::Boom') ) {
			if ( my $existing = $cprefs->get('playingDisplayModes') ) {
				if (scalar @$existing == 10 && $existing->[0] == 0 && $existing->[-1] == 9) {
					$cprefs->set('playingDisplayModes', [0..10]);
				}
			}
		}
		1;
	} );
}

1;