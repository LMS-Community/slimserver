package Slim::Plugin::MusicMagic::ClientSettings;

# Logitech Media Server Copyright 2001-2024 Logitech.
# Lyrion Music Server Copyright 2024-2026 Lyrion Community.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Plugin::MusicMagic::Settings);

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

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('plugins/MusicMagic/settings/mipclient.html');
}

sub prefs {
	my ($class, $client) = @_;

	return ($prefs->client($client), qw(mix_filter mix_genre_filter reject_size reject_type mix_genre mix_variety mix_style mix_type mix_size));
}

sub needsClient {
	return 1;
}

1;

__END__
