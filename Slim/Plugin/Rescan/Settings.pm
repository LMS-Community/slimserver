package Slim::Plugin::Rescan::Settings;

# SlimServer Copyright (C) 2001-2006 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::DateTime;

sub name {
        return 'PLUGIN_RESCAN_MUSIC_LIBRARY';
}

sub page {
        return 'plugins/Rescan/settings/basic.html';
}

sub handler {
        my ($class, $client, $params) = @_;

	my @prefs = qw(
		rescan-scheduled
		rescan-time
		rescan-type
	);

	for my $pref (@prefs) {

		if ($params->{'saveSettings'}) {

			if ($pref eq 'rescan-time') {

				$params->{$pref} = Slim::Utils::DateTime::prettyTimeToSecs($params->{$pref});
			}

			Slim::Utils::Prefs::set($pref, $params->{$pref});
		}

		$params->{'prefs'}->{$pref} = Slim::Utils::Prefs::get($pref);

		if ($pref eq 'rescan-time') {

			$params->{'prefs'}->{$pref} = Slim::Utils::DateTime::secsToPrettyTime(
				$params->{'prefs'}->{$pref}
			);
		}

		# Hack prefs - Template Toolkit doesn't like the dashes.
		my $value = delete $params->{'prefs'}->{$pref};

		$pref =~ s/-(\w)/\u$1/;

		$params->{'prefs'}->{$pref} = $value;
        }

        return $class->SUPER::handler($client, $params);
}

1;

__END__
