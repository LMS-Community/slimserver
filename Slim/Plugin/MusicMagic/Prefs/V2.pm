package Slim::Plugin::MusicMagic::Prefs::V2;

use strict;

use base qw(Slim::Utils::Prefs::Migration);

sub migrate {
	my ($class, $prefs, $defaults) = @_;
	
	$prefs->migrate(2, sub {
		my $oldPrefs = Slim::Utils::Prefs::preferences('plugin.musicmagic'); 
	
		$prefs->set('musicip',         $oldPrefs->get('musicmagic'));
		$prefs->set('scan_interval',   $oldPrefs->get('scan_interval') || 3600          );
		$prefs->set('player_settings', $oldPrefs->get('player_settings') || 0           );
		$prefs->set('port',            $oldPrefs->get('port') || 10002                  );
		$prefs->set('mix_filter',      $oldPrefs->get('mix_filter')                     );
		$prefs->set('reject_size',     $oldPrefs->get('reject_size') || 0               );
		$prefs->set('reject_type',     $oldPrefs->get('reject_type')                    );
		$prefs->set('mix_genre',       $oldPrefs->get('mix_genre')                      );
		$prefs->set('mix_variety',     $oldPrefs->get('mix_variety') || 0               );
		$prefs->set('mix_style',       $oldPrefs->get('mix_style') || 0                 );
		$prefs->set('mix_type',        $oldPrefs->get('mix_type')                       );
		$prefs->set('mix_size',        $oldPrefs->get('mix_size') || 12                 );
		$prefs->set('playlist_prefix', $oldPrefs->get('playlist_prefix') || '' );
		$prefs->set('playlist_suffix', $oldPrefs->get('playlist_suffix') || ''          );
	
		my $prefix = $prefs->get('playlist_prefix');
		if ($prefix =~ /MusicMagic/) {
			$prefix =~ s/MusicMagic/MusicIP/g;
			$prefs->set('playlist_prefix', $prefix);
		}
	
		$prefs->remove('musicmagic');
		1;
	});
}

1;