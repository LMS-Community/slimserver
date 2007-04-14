package Slim::Plugin::MusicMagic::Settings;

# SlimServer Copyright (C) 2001-2006 Logitech.
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
	'category'     => 'plugin.musicmagic',
	'defaultLevel' => 'WARN',
});

my $prefs = preferences('plugin.musicmagic');

$prefs->migrate(1, sub {
	$prefs->set('enabled',         Slim::Utils::Prefs::OldPrefs->get('musicmagic'));
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

	$prefs->set('enabled', 0) unless defined $prefs->get('enabled'); # default to on if not previously set
	
	# use new naming of the old default wasn't changed
	if ($prefs->get('playlist_prefix') eq 'MusicMagic: ') {
		$prefs->set('playlist_prefix', 'MusicIP: ');
	}
	1;
});

$prefs->setValidate('num', qw(scan_interval port mix_variety mix_style reject_size));

$prefs->setChange(
	sub {
		Slim::Music::Import->useImporter('Plugin::iTunes::Plugin', $_[1]);

		for my $c (Slim::Player::Client::clients()) {
			Slim::Buttons::Home::updateMenu($c);
		}
	},
	'enabled',
);

sub name {
	return 'MUSICMAGIC';
}

sub page {
	return 'plugins/MusicMagic/settings/musicmagic.html';
}

sub prefs {
	return ($prefs, qw(enabled scan_interval player_settings port mix_filter reject_size reject_type 
			   mix_genre mix_variety mix_style mix_type mix_size playlist_prefix playlist_suffix));
}

sub handler {
	my ($class, $client, $params) = @_;

	# Cleanup the checkbox
	$params->{'enabled'} = defined $params->{'enabled'} ? 1 : 0;

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
