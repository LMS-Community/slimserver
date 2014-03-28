package Slim::Plugin::MusicMagic::Prefs::ClientV1;

use strict;

use Slim::Utils::Prefs::OldPrefs;

sub init {
	my ($class, $prefs) = @_;
	
	$prefs->migrateClient(1, sub {
		my ($clientprefs, $client) = @_;
		
		$clientprefs->set('mix_filter',  Slim::Utils::Prefs::OldPrefs->clientGet($client, 'MMMFilter')     );
		$clientprefs->set('reject_size', Slim::Utils::Prefs::OldPrefs->clientGet($client, 'MMMRejectSize') );
		$clientprefs->set('reject_type', Slim::Utils::Prefs::OldPrefs->clientGet($client, 'MMMRejectType') );
		$clientprefs->set('mix_genre',   Slim::Utils::Prefs::OldPrefs->clientGet($client, 'MMMMixGenre')   );
		$clientprefs->set('mix_variety', Slim::Utils::Prefs::OldPrefs->clientGet($client, 'MMMVariety')    );
		$clientprefs->set('mix_style',   Slim::Utils::Prefs::OldPrefs->clientGet($client, 'MMMStyle')      );
		$clientprefs->set('mix_type',    Slim::Utils::Prefs::OldPrefs->clientGet($client, 'MMMMixType')    );
		$clientprefs->set('mix_size',    Slim::Utils::Prefs::OldPrefs->clientGet($client, 'MMMSize')       );
		
		1;
	});
}

1;