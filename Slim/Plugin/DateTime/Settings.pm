package Slim::Plugin::DateTime::Settings;

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;

my $prefs = preferences('plugin.datetime');

my $timeFormats = Slim::Utils::DateTime::timeFormats();

my $dateFormats = {
	%{Slim::Utils::DateTime::shortDateFormats()},
	%{Slim::Utils::DateTime::longDateFormats()}
};

sub name {
	return Slim::Web::HTTP::CSRF->protectName('PLUGIN_SCREENSAVER_DATETIME');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('plugins/DateTime/settings/basic.html');
}

sub prefs {
	my ($class, $client) = @_;
	return ($prefs->client($client), qw(timeFormat dateFormat) );
}

sub needsClient {
	return 1;
}

sub validFor {
	my $class = shift;
	my $client = shift;
	
	return !$client->display->isa('Slim::Display::NoDisplay');
}

sub handler {
	my ($class, $client, $params) = @_;

	$params->{'timeFormats'} = $timeFormats;
	$params->{'dateFormats'} = $dateFormats;

	return $class->SUPER::handler($client, $params);
}

1;

__END__
