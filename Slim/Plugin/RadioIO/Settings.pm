package Slim::Plugin::RadioIO::Settings;

# SlimServer Copyright (c) 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;

my $prefs = preferences('plugin.radioio');

$prefs->migrate(1, sub {
	$prefs->set('username', Slim::Utils::Prefs::OldPrefs->get('plugin_radioio_username'));
	$prefs->set('password', Slim::Utils::Prefs::OldPrefs->get('plugin_radioio_password'));
	1;
});

sub name {
	return 'PLUGIN_RADIOIO_MODULE_NAME';
}

sub page {
	return 'plugins/RadioIO/settings/basic.html';
}

sub prefs {
	return ($prefs, qw(username password));
}

sub handler {
	my ($class, $client, $params) = @_;

	if ($params->{'saveSettings'}) {

		if ($params->{'password'}) {

			$params->{'password'} = MIME::Base64::encode_base64($params->{'password'});

			chomp($params->{'password'});
		}
	}

	return $class->SUPER::handler($client, $params);
}

1;

__END__
