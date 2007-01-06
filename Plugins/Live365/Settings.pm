package Plugins::Live365::Settings;

# SlimServer Copyright (C) 2001-2006 Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

sub name {
        return 'PLUGIN_LIVE365_MODULE_NAME';
}

sub page {
        return 'plugins/Live365/settings/basic.html';
}

sub handler {
        my ($class, $client, $params) = @_;

	my @prefs = qw(
		plugin_live365_username
		plugin_live365_password
		plugin_live365_sort_order
		plugin_live365_web_show_details
	);

	for my $pref (@prefs) {

		if ($params->{'saveSettings'}) {

			if ($pref eq 'plugin_live365_password') {

				$params->{$pref} = pack('u', $params->{$pref});

				chomp($params->{$pref});
			}

			Slim::Utils::Prefs::set($pref, $params->{$pref});
		}

		# Do we want to display the password?
		if ($pref eq 'plugin_live365_password') {
			next;
		}

		$params->{'prefs'}->{$pref} = Slim::Utils::Prefs::get($pref);
        }

        return $class->SUPER::handler($client, $params);
}

1;

__END__
