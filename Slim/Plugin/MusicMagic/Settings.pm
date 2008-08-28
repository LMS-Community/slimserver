package Slim::Plugin::MusicMagic::Settings;

# SqueezeCenter Copyright 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Prefs;

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.musicip',
	'defaultLevel' => 'ERROR',
});

my $prefs = preferences('plugin.musicip');

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
	$prefs->set('playlist_prefix', Slim::Utils::Prefs::OldPrefs->get('MusicMagicplaylistprefix') || 'MusicIP: '   );
	$prefs->set('playlist_suffix', Slim::Utils::Prefs::OldPrefs->get('MusicMagicplaylistsuffix') || ''            );

	$prefs->set('musicmagic', 0) unless defined $prefs->get('musicmagic'); # default to on if not previously set
	
	# use new naming of the old default wasn't changed
	if ($prefs->get('playlist_prefix') eq 'MusicMagic: ') {
		$prefs->set('playlist_prefix', 'MusicIP: ');
	}
	1;
});

$prefs->migrate(2, sub {
	my $oldPrefs = preferences('plugin.musicmagic'); 

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
	$prefs->set('playlist_prefix', $oldPrefs->get('playlist_prefix') || 'MusicIP: ' );
	$prefs->set('playlist_suffix', $oldPrefs->get('playlist_suffix') || ''          );

	$prefs->remove('musicmagic');
	1;
});

$prefs->setValidate('num', qw(scan_interval port mix_variety mix_style reject_size));

$prefs->setChange(
	sub {
		my $newval = $_[1];
		
		if ($newval) {
			Slim::Plugin::MusicMagic::Plugin->initPlugin();
		}
		
		Slim::Music::Import->useImporter('Slim::Plugin::MusicMagic::Plugin', $_[1]);

		for my $c (Slim::Player::Client::clients()) {
			Slim::Buttons::Home::updateMenu($c);
		}
	},
	'musicip',
);

$prefs->setChange(
	sub {
			Slim::Utils::Timers::killTimers(undef, \&Slim::Plugin::MusicMagic::Plugin::checker);
			
			my $interval = $prefs->get('scan_interval') || 3600;
			
			$log->info("re-setting checker for $interval seconds from now.");
			
			Slim::Utils::Timers::setTimer(undef, Time::HiRes::time() + $interval, \&Slim::Plugin::MusicMagic::Plugin::checker);
	},
'scan_interval');

sub name {
	return Slim::Web::HTTP::protectName('MUSICMAGIC');
}

sub page {
	return Slim::Web::HTTP::protectURI('plugins/MusicMagic/settings/musicmagic.html');
}

sub prefs {
	return ($prefs, qw(musicip scan_interval player_settings port mix_filter reject_size reject_type 
			   mix_genre mix_variety mix_style mix_type mix_size playlist_prefix playlist_suffix));
}

sub handler {
	my ($class, $client, $params) = @_;

	# Cleanup the checkbox
	$params->{'pref_musicip'} = defined $params->{'pref_musicip'} ? 1 : 0;

	$params->{'filters'}  = grabFilters();

	return $class->SUPER::handler($client, $params);
}

sub grabFilters {
	my @filters    = ();
	my %filterHash = ();
	
	my $MMSport = $prefs->get('port');
	my $MMSHost = $prefs->get('host');

	$log->debug("Get filters list");

	my $http = Slim::Player::Protocols::HTTP->new({
		'url'    => "http://$MMSHost:$MMSport/api/filters",
		'create' => 0,
	});

	if ($http) {

		@filters = split(/\n/, $http->content);
		$http->close;

		if ($log->is_debug && scalar @filters) {

			$log->debug("Found filters:");

			for my $filter (@filters) {

				$log->debug("\t$filter");
			}
		}
	}

	my $none = sprintf('(%s)', Slim::Utils::Strings::string('NONE'));

	push @filters, $none;

	foreach my $filter ( @filters ) {

		if ($filter eq $none) {

			$filterHash{0} = $filter;
			next
		}

		$filterHash{$filter} = $filter;
	}

	return \%filterHash;
}

1;

__END__
