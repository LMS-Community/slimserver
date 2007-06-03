package Slim::Plugin::Live365::Settings;

# SlimServer Copyright (c) 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;

my $prefs = preferences('plugin.live365');

sub name {
        return 'PLUGIN_LIVE365_MODULE_NAME';
}

sub page {
        return 'plugins/Live365/settings/basic.html';
}

sub handler {
        my ($class, $client, $params) = @_;

	my @prefs = qw(username password sort_order web_show_details);

	for my $pref (@prefs) {

		if ($params->{'saveSettings'}) {

			if ($pref eq 'password') {

				$params->{$pref} = pack('u', $params->{$pref});

				chomp($params->{$pref});
			}

			$prefs->set($pref, $params->{$pref});
		}

		# Do we want to display the password?
		if ($pref eq 'password') {
			next;
		}

		$params->{'prefs'}->{$pref} = $prefs->get($pref);
        }

        return $class->SUPER::handler($client, $params);
}

1;

__END__
