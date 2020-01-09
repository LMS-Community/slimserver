package Slim::Plugin::MusicMagic::Settings;

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
	return Slim::Web::HTTP::CSRF->protectName('MUSICMAGIC');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('plugins/MusicMagic/settings/musicmagic.html');
}

sub prefs {
	return ($prefs, qw(musicip scan_interval player_settings port mix_filter reject_size reject_type 
			   mix_genre mix_variety mix_style mix_type mix_size playlist_prefix playlist_suffix));
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
