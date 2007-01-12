package Slim::Plugin::DateTime::Settings;

# SlimServer Copyright (C) 2001-2006 Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

my $timeFormats = Slim::Utils::DateTime::timeFormats();

my $dateFormats = {
	%{Slim::Utils::DateTime::shortDateFormats()},
	%{Slim::Utils::DateTime::longDateFormats()}
};

sub name {
        return 'PLUGIN_SCREENSAVER_DATETIME';
}

sub page {
        return 'plugins/DateTime/settings/basic.html';
}

sub handler {
        my ($class, $client, $params) = @_;

	my @prefs = qw(
		screensaverTimeFormat
		screensaverDateFormat
	);

	for my $pref (@prefs) {

		if ($params->{'saveSettings'}) {

			Slim::Utils::Prefs::set($pref, $params->{$pref});
		}

		$params->{'prefs'}->{$pref} = Slim::Utils::Prefs::get($pref);
        }

	$params->{'timeFormats'} = $timeFormats;
	$params->{'dateFormats'} = $dateFormats;

        return $class->SUPER::handler($client, $params);
}

1;

__END__
