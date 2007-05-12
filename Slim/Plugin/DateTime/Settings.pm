package Slim::Plugin::DateTime::Settings;

# SlimServer Copyright (c) 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;

my $prefs = preferences('plugin.datetime');

$prefs->migrate(1, sub {
	$prefs->set('timeformat', Slim::Utils::Prefs::OldPrefs->get('screensaverTimeFormat') || '');
	$prefs->set('dateformat', Slim::Utils::Prefs::OldPrefs->get('screensaverDateFormat') || '');
	1;
});

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

sub prefs {
	return ($prefs, qw(timeformat dateformat) );
}

sub handler {
	my ($class, $client, $params) = @_;

	$params->{'timeFormats'} = $timeFormats;
	$params->{'dateFormats'} = $dateFormats;

	return $class->SUPER::handler($client, $params);
}

1;

__END__
