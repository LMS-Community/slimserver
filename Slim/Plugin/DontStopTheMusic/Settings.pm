package Slim::Plugin::DontStopTheMusic::Settings;

# Logitech Media Server Copyright 2001-2016 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;

my $prefs = preferences('plugin.dontstopthemusic');

sub name {
	return Slim::Web::HTTP::CSRF->protectName('PLUGIN_DSTM');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('plugins/DontStopTheMusic/settings.html');
}

sub needsClient { 1 }

sub prefs {
	my ($class, $client) = @_;

	return if (!defined $client);

	return ($prefs->client($client), 'provider');
}

sub handler {
	my ($class, $client, $paramRef) = @_;

	$paramRef->{handlers} = [ sort {
		lc(Slim::Plugin::DontStopTheMusic::Plugin::getString($a, $client)) cmp lc(Slim::Plugin::DontStopTheMusic::Plugin::getString($b, $client));
	} keys %{Slim::Plugin::DontStopTheMusic::Plugin->getHandlers()} ];
	
	return $class->SUPER::handler($client, $paramRef);
}

1;