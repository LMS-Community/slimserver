package Slim::Plugin::iTunes::Settings;

# SqueezeCenter Copyright (c) 2001-2007 Logitech.
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
	'category'     => 'plugin.itunes',
	'defaultLevel' => 'WARN',
});

my $prefs = preferences('plugin.itunes');

$prefs->migrate(1, sub {
	$prefs->set('itunes',          Slim::Utils::Prefs::OldPrefs->get('itunes'));
	$prefs->set('scan_interval',   Slim::Utils::Prefs::OldPrefs->get('itunesscaninterval')   || 3600      );
	$prefs->set('ignore_disabled', Slim::Utils::Prefs::OldPrefs->get('ignoredisableditunestracks') || 0   );
	$prefs->set('xml_file',        Slim::Utils::Prefs::OldPrefs->get('itunes_library_xml_path')           );
	$prefs->set('music_path',      Slim::Utils::Prefs::OldPrefs->get('itunes_library_music_path')         );
	$prefs->set('playlist_prefix', Slim::Utils::Prefs::OldPrefs->get('iTunesplaylistprefix') || 'iTunes: ');
	$prefs->set('playlist_suffix', Slim::Utils::Prefs::OldPrefs->get('iTunesplaylistsuffix') || ''        );

	$prefs->set('itunes', 1) unless defined $prefs->get('itunes'); # default to on if not previously set
	1;
});

$prefs->setValidate('num', 'scan_interval');
$prefs->setValidate('file', 'xml_file');
$prefs->setValidate('dir', 'music_path');

$prefs->setChange(
	sub {
		Slim::Music::Import->useImporter('Plugin::iTunes::Plugin', $_[1]);

		for my $c (Slim::Player::Client::clients()) {
			Slim::Buttons::Home::updateMenu($c);
		}
	},
'itunes');

sub name {
	return Slim::Web::HTTP::protectName('ITUNES');
}

sub page {
	return Slim::Web::HTTP::protectURI('plugins/iTunes/settings/itunes.html');
}

sub prefs {
	return ($prefs, qw(itunes scan_interval ignore_disabled xml_file music_path playlist_prefix playlist_suffix));
}

sub handler {
	my ($class, $client, $params) = @_;

	# Cleanup the checkbox
	$params->{'itunes'} = defined $params->{'itunes'} ? 1 : 0;

	return $class->SUPER::handler($client, $params);
}

1;

__END__
