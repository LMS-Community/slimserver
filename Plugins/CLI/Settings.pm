package Plugins::CLI::Settings;

# SlimServer Copyright (c) 2001-2006 Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use base qw(Slim::Web::Settings);

sub name {
        return 'PLUGIN_CLI';
}

sub page {
        return 'plugins/CLI/settings/basic.html';
}

sub handler {
        my ($class, $client, $params) = @_;

	my @prefs = qw(
		cliport
	);

	for my $pref (@prefs) {

		if ($params->{'saveSettings'}) {

			# XXX - validate port
			Slim::Utils::Prefs::set($pref, $params->{$pref});

			if ($params->{$pref} != Slim::Utils::Prefs::get($pref)) {

				Plugins::CLI::::Plugin::cli_socket_change();
			}
		}

		$params->{'prefs'}->{$pref} = Slim::Utils::Prefs::get($pref);
        }

        return $class->SUPER::handler($client, $params);
}

1;

__END__
