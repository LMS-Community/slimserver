package Slim::Plugin::MusicMagic::Prefs::ClientV2;

use strict;

sub init {
	my ($class, $prefs) = @_;

	$prefs->migrateClient(2, sub {
		my ($clientprefs, $client) = @_;
		
		my $oldPrefs = Slim::Utils::Prefs::preferences('plugin.musicmagic');
		$clientprefs->set('mix_filter',  $oldPrefs->client($client)->get($client, 'mix_filter')  );
		$clientprefs->set('reject_size', $oldPrefs->client($client)->get($client, 'reject_size') );
		$clientprefs->set('reject_type', $oldPrefs->client($client)->get($client, 'reject_type') );
		$clientprefs->set('mix_genre',   $oldPrefs->client($client)->get($client, 'mix_genre')   );
		$clientprefs->set('mix_variety', $oldPrefs->client($client)->get($client, 'mix_variety') );
		$clientprefs->set('mix_style',   $oldPrefs->client($client)->get($client, 'mix_style')   );
		$clientprefs->set('mix_type',    $oldPrefs->client($client)->get($client, 'mix_type')    );
		$clientprefs->set('mix_size',    $oldPrefs->client($client)->get($client, 'mix_size')    );
		1;
	});
}

1;