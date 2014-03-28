package Slim::Plugin::MusicMagic::Prefs::V1;

use strict;

use base qw(Slim::Utils::Prefs::Migration);

use Slim::Utils::Prefs::OldPrefs;

sub migrate {
	my ($class, $prefs, $defaults) = @_;
	
	$prefs->migrate(1, sub {
		$prefs->set('musicmagic',      Slim::Utils::Prefs::OldPrefs->get('musicmagic'));
		$prefs->set('scan_interval',   Slim::Utils::Prefs::OldPrefs->get('musicmagicscaninterval') || 3600            );
		$prefs->set('player_settings', Slim::Utils::Prefs::OldPrefs->get('MMMPlayerSettings') || 0                    );
		$prefs->set('port',            Slim::Utils::Prefs::OldPrefs->get('MMSport') || 10002                          );
		$prefs->set('mix_filter',      Slim::Utils::Prefs::OldPrefs->get('MMMFilter')                                 );
		$prefs->set('reject_size',     Slim::Utils::Prefs::OldPrefs->get('MMMRejectSize') || 0                        );
		$prefs->set('reject_type',     Slim::Utils::Prefs::OldPrefs->get('MMMRejectType')                             );
		$prefs->set('mix_genre',       Slim::Utils::Prefs::OldPrefs->get('MMMMixGenre')                               );
		$prefs->set('mix_variety',     Slim::Utils::Prefs::OldPrefs->get('MMMVariety') || 0                           );
		$prefs->set('mix_style',       Slim::Utils::Prefs::OldPrefs->get('MMMStyle') || 0                             );
		$prefs->set('mix_type',        Slim::Utils::Prefs::OldPrefs->get('MMMMixType')                                );
		$prefs->set('mix_size',        Slim::Utils::Prefs::OldPrefs->get('MMMSize') || 12                             );
		$prefs->set('playlist_prefix', Slim::Utils::Prefs::OldPrefs->get('MusicMagicplaylistprefix') || ''   );
		$prefs->set('playlist_suffix', Slim::Utils::Prefs::OldPrefs->get('MusicMagicplaylistsuffix') || ''            );
	
		$prefs->set('musicmagic', 0) unless defined $prefs->get('musicmagic'); # default to on if not previously set
		
		# use new naming of the old default wasn't changed
		if ($prefs->get('playlist_prefix') eq 'MusicMagic: ') {
			$prefs->set('playlist_prefix', 'MusicIP: ');
		}
		1;
	});
}

1;