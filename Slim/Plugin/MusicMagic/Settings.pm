package Slim::Plugin::MusicMagic::Settings;

# Logitech Media Server Copyright 2001-2024 Logitech.
# Lyrion Music Server Copyright 2024-2026 Lyrion Community.
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
	return ($prefs, qw(musicip scan_interval player_settings host port mix_filter reject_size reject_type
			   mix_genre mix_genre_filter mix_variety mix_style mix_type mix_size playlist_prefix playlist_suffix
			   path_conversion_enabled path_conversion_source path_conversion_dest));
}

sub handler {
	my ($class, $client, $params, $callback, @args) = @_;

	if ( !$params->{'saveSettings'} && !$params->{'filters'} ) {

		Slim::Plugin::MusicMagic::Common::grabFilters($class, $client, $params, $callback, @args);

		return undef;
	}

	if ( $params->{'saveSettings'} ) {
		my $selected = $params->{'pref_mix_genre_filter'};

		# An empty multi-select submits no value at all (undef), which
		# means "no genres excluded", not "leave unchanged" - store an
		# empty arrayref for that case. A single selection submits as a
		# plain scalar rather than a one-item array; wrap it.
		$params->{'pref_mix_genre_filter'} = !defined $selected ? []
			: ( ref $selected eq 'ARRAY' ? $selected : [ $selected ] );
	}

	$params->{'filters'}    = Slim::Plugin::MusicMagic::Common->getFilterList();
	$params->{'genre_list'} = Slim::Plugin::MusicMagic::Common::getGenreList();

	my ($classPrefs) = $class->prefs($client);

	# Use a differently-named key for the checkbox-state lookup hash: it
	# used to be called 'mix_genre_filter', identical to the actual pref
	# name, which Slim::Web::Settings::handler flags and rejects on save
	# when the filter is empty (it treats any non-'pref_'-prefixed param
	# matching a real pref name as a template error).
	my $genreFilter = Slim::Plugin::MusicMagic::Common::genreFilterList($classPrefs->get('mix_genre_filter'));
	$params->{'mix_genre_filter_lookup'} = { map { $_ => 1 } @$genreFilter };

	return $class->SUPER::handler($client, $params);
}

1;

__END__
