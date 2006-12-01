package Plugins::MoodLogic::Settings;

# SlimServer Copyright (C) 2001-2006 Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.moodlogic',
	'defaultLevel' => 'WARN',
});

sub name {
	return 'MOODLOGIC';
}

sub page {
	return 'plugins/MoodLogic/settings/moodlogic.html';
}

sub handler {
	my ($class, $client, $params) = @_;

	# These are lame preference names.
	my @prefs = qw(
		moodlogic
		instantMixMax
		varietyCombo
		moodlogicscaninterval
		MoodLogicplaylistprefix
		MoodLogicplaylistsuffix
	);

	# Cleanup the checkbox
	$params->{'moodlogic'} = defined $params->{'moodlogic'} ? 1 : 0;

	if ($params->{'submit'}) {

		if ($params->{'moodlogic'} != Slim::Utils::Prefs::get('moodlogic')) {

			for my $c (Slim::Player::Client::clients()) {

				Slim::Buttons::Home::updateMenu($c);
			}

			Slim::Music::Import->useImporter('Plugin::MoodLogic::Plugin', $params->{'moodlogic'});
		}

		for my $pref (@prefs) {

			# XXX - need validation!
			#'itunesscaninterval' => { 'validate' => \&Slim::Utils::Validate::number, },
			#'itunes_library_xml_path' => { 'validate' => \&Slim::Utils::Validate::isFile, },
			#'itunes_library_music_path' => { 'validate' => \&Slim::Utils::Validate::isDir, },

			Slim::Utils::Prefs::set($pref, $params->{$pref});
		}
	}

	for my $pref (@prefs) {

		$params->{'prefs'}->{$pref} = Slim::Utils::Prefs::get($pref);
        }

        return $class->SUPER::handler($client, $params);
}

1;

__END__
