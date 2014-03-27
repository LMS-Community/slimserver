package Slim::Utils::Prefs::Migration::ClientV13;

use strict;
use Storable;

use Slim::Player::Player;

sub init {
	my ($class, $prefs) = @_;
	
	# add global search to menu if client is still using default menu items
	$prefs->migrateClient( 13, sub {
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
			
			my @oldDefaults  = grep { $_ !~ /GLOBAL_SEARCH/ } @{ $defaults->{menuItem} };
			my @currentPrefs = @{ $cprefs->get('menuItem') };

			# only replace menu if user didn't customize it
			if ("@oldDefaults" eq "@currentPrefs") {
				$cprefs->set( menuItem => Storable::dclone($defaults->{menuItem}) );
			}
		}
		1;
	} );
}

1;