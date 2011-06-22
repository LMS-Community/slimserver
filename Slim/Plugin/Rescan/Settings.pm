package Slim::Plugin::Rescan::Settings;

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;
use Slim::Utils::DateTime;

my $prefs = preferences('plugin.rescan');

sub name {
	return Slim::Web::HTTP::CSRF->protectName('PLUGIN_RESCAN_MUSIC_LIBRARY');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('plugins/Rescan/settings/basic.html');
}

sub prefs {
	return ($prefs, qw(scheduled type) );
}

sub handler {
	my ($class, $client, $params) = @_;

	if ($params->{'saveSettings'} && $params->{'pref_time'}) {
		$prefs->set('time', Slim::Utils::DateTime::prettyTimeToSecs($params->{'pref_time'}));
	}

	$params->{'prefs'}->{'pref_time'} = Slim::Utils::DateTime::secsToPrettyTime($prefs->get('time'));

	return $class->SUPER::handler($client, $params);
}

1;

__END__
