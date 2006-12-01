package Plugins::RadioIO::Settings;

# SlimServer Copyright (C) 2001-2006 Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

sub name {
        return 'PLUGIN_RADIOIO_MODULE_NAME';
}

sub page {
        return 'plugins/RadioIO/settings/basic.html';
}

sub handler {
        my ($class, $client, $params) = @_;

	my @prefs = qw(
		plugin_radioio_username
		plugin_radioio_password
	);

	for my $pref (@prefs) {

		if ($params->{'submit'}) {

			if ($pref eq 'plugin_radioio_password') {

				$params->{$pref} = MIME::Base64::encode_base64($params->{$pref});
				chomp($params->{$pref});
			}

			Slim::Utils::Prefs::set($pref, $params->{$pref});
		}

		# Do we want to display the password?
		if ($pref eq 'plugin_radioio_password') {
			next;
		}

		$params->{'prefs'}->{$pref} = Slim::Utils::Prefs::get($pref);
        }

        return $class->SUPER::handler($client, $params);
}

1;

__END__
