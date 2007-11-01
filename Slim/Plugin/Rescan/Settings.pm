package Slim::Plugin::Rescan::Settings;

# SqueezeCenter Copyright (c) 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;
use Slim::Utils::DateTime;

my $prefs = preferences('plugin.rescan');

$prefs->migrate(1, sub {
	$prefs->set('time',      Slim::Utils::Prefs::OldPrefs->get('rescan-time')      || 9 * 60 * 60 );
	$prefs->set('scheduled', Slim::Utils::Prefs::OldPrefs->get('rescan-scheduled') || 0           );
	$prefs->set('type',      Slim::Utils::Prefs::OldPrefs->get('rescan-type')      || '1rescan'   );
	1;
});

sub name {
	return Slim::Web::HTTP::protectName('PLUGIN_RESCAN_MUSIC_LIBRARY');
}

sub page {
	return Slim::Web::HTTP::protectURI('plugins/Rescan/settings/basic.html');
}

sub prefs {
	return ($prefs, qw(scheduled type) );
}

sub handler {
	my ($class, $client, $params) = @_;

	if ($params->{'saveSettings'} && $params->{'time'}) {
		$prefs->set('time', Slim::Utils::DateTime::prettyTimeToSecs($params->{'time'}));
	}

	$params->{'prefs'}->{'time'} = Slim::Utils::DateTime::secsToPrettyTime($prefs->get('time'));

	return $class->SUPER::handler($client, $params);
}

1;

__END__
