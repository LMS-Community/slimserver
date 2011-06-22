package Slim::Plugin::iTunes::Settings;

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Prefs;
use Slim::Plugin::iTunes::Plugin;

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.itunes',
	'defaultLevel' => 'ERROR',
});

my $prefs = preferences('plugin.itunes');

sub name {
	return Slim::Web::HTTP::CSRF->protectName('ITUNES');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('plugins/iTunes/settings/itunes.html');
}

sub prefs {
	return ($prefs, qw(itunes scan_interval ignore_disabled xml_file music_path playlist_prefix playlist_suffix ignore_playlists extract_artwork));
}

sub handler {
	my ($class, $client, $params) = @_;

	# Cleanup the checkboxes
	$params->{'pref_itunes'}          = defined $params->{'pref_itunes'} ? 1 : 0;
	$params->{'pref_extract_artwork'} = defined $params->{'pref_extract_artwork'} ? 1 : 0;

	my $ret = $class->SUPER::handler($client, $params);
	
	# We need to immediately write the prefs file to disk, or the scanner may launch and
	# use the previous prefs
	$prefs->savenow();
	
	return $ret;
}

1;

__END__
