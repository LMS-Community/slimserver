package Slim::Utils::Prefs::Migration::V3;

use strict;

use base qw(Slim::Utils::Prefs::Migration);

use Slim::Utils::Prefs;

sub migrate {
	my ($class, $prefs) = @_;
	
	$prefs->migrate( 3, sub {

		if ($prefs->exists('cachedir') && $prefs->get('cachedir') =~ /SqueezeCenter/i) {
			$prefs->set('cachedir', Slim::Utils::Prefs::defaultCacheDir());
			Slim::Utils::Prefs::makeCacheDir();
		}

		1;
	} );
}

1;