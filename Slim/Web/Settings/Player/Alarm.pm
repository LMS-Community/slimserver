package Slim::Web::Settings::Player::Alarm;

# $Id: Basic.pm 10633 2006-11-09 04:26:27Z kdf $

# SlimServer Copyright (c) 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::DateTime;
use Slim::Utils::Log;
use Slim::Utils::Prefs;

sub name {
	return 'ALARM_SETTINGS';
}

sub page {
	return 'settings/player/alarm.html';
}

sub needsClient {
	return 1;
}

sub handler {
	my ($class, $client, $paramRef) = @_;

	my $prefs = preferences('server');

	my @prefs = qw(alarmfadeseconds alarm alarmtime alarmvolume alarmplaylist);

	# If this is a settings update
	if ($paramRef->{'saveSettings'}) {

		for my $pref (@prefs) {

			if ($pref eq 'alarmfadeseconds') {

				$prefs->client($client)->set( $paramRef->{$pref} ? 1 : 0 );

			} else {

				my $array = $prefs->client($client)->get($pref);

				for my $i (0..7) {

					if ($pref eq 'alarmtime') {

						$array->[$i] = Slim::Utils::DateTime::prettyTimeToSecs($paramRef->{$pref.$i});

					} else {

						$array->[$i] = $paramRef->{$pref.$i};
					}
				}

				$prefs->client($client)->set($pref, $array);
			}
		}
	}

	# Load any option lists for dynamic options.
	my $playlists = {
		'' => undef,
	};

	for my $playlist (Slim::Schema->rs('Playlist')->getPlaylists) {

		$playlists->{$playlist->url} = Slim::Music::Info::standardTitle(undef, $playlist);
	}

	my $specialPlaylists = \%Slim::Buttons::AlarmClock::specialPlaylists;

	for my $key (keys %{$specialPlaylists}) {

		$playlists->{$key} = Slim::Utils::Strings::string($key);
	}

	$paramRef->{'playlistOptions'} = $playlists;

	# Set current values for prefs
	# load into prefs hash so that web template can detect exists/!exists
	for my $pref (@prefs) {

		if ($pref eq 'alarmtime') {

			my $time = $prefs->client($client)->get('alarmtime');

			for my $i (0..7) {

				${$paramRef->{'prefs'}->{'alarmtime'}}[$i] = Slim::Utils::DateTime::secsToPrettyTime($time->[$i]);
			}

		} else {

			$paramRef->{'prefs'}->{$pref} = $prefs->client($client)->get($pref);
		}
	}

	return $class->SUPER::handler($client, $paramRef);
}

1;

__END__
