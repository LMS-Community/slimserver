package Slim::Utils::Prefs::Migration::ClientV11;

use strict;
use Storable;

use Slim::Player::Player;

sub init {
	my ($class, $prefs) = @_;
	
	# Bug 13229, migrate menuItem pref so everyone gets the correct menu structure for 7.4
	$prefs->migrateClient( 11, sub {
		my ( $cprefs, $client ) = @_;
		my $defaults = $Slim::Player::Player::defaultPrefs;

		if ( $client->hasDigitalIn ) {
			require Slim::Player::Transporter;
			$defaults = $Slim::Player::Transporter::defaultPrefs;
		}

		if ( $client->isa('Slim::Player::Boom') ) {
			require Slim::Player::Boom;
			$defaults = $Slim::Player::Boom::defaultPrefs;
		}

		if ($defaults && defined $defaults->{menuItem}) {
			# clone for each client
			$cprefs->set( menuItem => Storable::dclone($defaults->{menuItem}) );
		}
		1;
	} );
}

1;