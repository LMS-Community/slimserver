package Slim::Utils::Prefs::Migration::V11;

use strict;

use base qw(Slim::Utils::Prefs::Migration);

sub migrate {
	my ($class, $prefs) = @_;

	# Norwegian is now NB (bokmål) and NN (nynorsk). The old NO was bokmål.
	$prefs->migrate( 11, sub {
		$prefs->set('language', 'NB') if uc($prefs->get('language') || '') eq 'NO';
		1;
	} );
}

1;
