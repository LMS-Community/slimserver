package Slim::Plugin::MusicMagic::ClientSettings;

# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Plugin::MusicMagic::Common;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Prefs;

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.musicip',
	'defaultLevel' => 'ERROR',
});

my $prefs = preferences('plugin.musicip');

sub name {
	return 'MUSICMAGIC';
}

sub page {
	return 'plugins/MusicMagic/settings/mipclient.html';
}

sub prefs {
	my ($class,$client) = @_;
	
	return ($prefs->client($client), qw(mix_filter reject_size reject_type mix_genre mix_variety mix_style mix_type mix_size));
}

sub needsClient {
	return 1;
}

sub handler {
	my ($class, $client, $params, $callback, @args) = @_;

	if ( !$params->{'saveSettings'} && !$params->{'filters'} ) {

		Slim::Plugin::MusicMagic::Common::grabFilters($class, $client, $params, $callback, @args);
		
		return undef;
	}


	$params->{'filters'} = Slim::Plugin::MusicMagic::Common->getFilterList();

	return $class->SUPER::handler($client, $params);
}

1;

__END__
