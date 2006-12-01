package Slim::Web::Settings::Player::Alarm;

# $Id: Basic.pm 10633 2006-11-09 04:26:27Z kdf $

# SlimServer Copyright (c) 2001-2006 Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::DateTime;
use Slim::Utils::Log;

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

	my @prefs = qw(alarmfadeseconds alarm alarmtime alarmvolume alarmplaylist);
	
	# If this is a settings update
	if ($paramRef->{'submit'}) {

		my @changed = ();

		for my $pref (@prefs) {

			if ($pref eq 'alarmfadeseconds') {
			
				# parse indexed array prefs.
				if ($paramRef->{$pref} ne $client->prefGet($pref)) {

					push @changed, $pref;
				}
				
				if (defined $paramRef->{$pref}) {

					$client->prefSet($pref, $paramRef->{$pref});
				}

			} else {
			
				for my $i (0..7) {

					# parse indexed array prefs.
					if ($pref ne 'alarmtime' && $paramRef->{$pref.$i} ne $client->prefGet($pref, $i)) {

						push @changed, $pref.$i;
					}

					if ($pref eq 'alarmtime') {

						my $newTime = Slim::Utils::DateTime::prettyTimeToSecs($paramRef->{"alarmtime$i"});

						if ($newTime != $client->prefGet('alarmtime', $i)) {

							push @changed, 'alarmtime'.$i;
						}

						$client->prefSet('alarmtime', $newTime, $i);

					} else {
					
						if (defined $paramRef->{$pref.$i}) {

							$client->prefSet($pref.$i, $paramRef->{$pref.$i});
						}
					}
				}
			}
		}
		
		$class->_handleChanges($client, \@changed, $paramRef);
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

		$playlists->{$key} = $key;
	}

	$paramRef->{'playlistOptions'} = $playlists;

	# Set current values for prefs
	# load into prefs hash so that web template can detect exists/!exists
	for my $pref (@prefs) {
		
		if ($pref eq 'alarmfadeseconds') {
		
			$paramRef->{'prefs'}->{$pref} = $client->prefGet($pref);

		} else {

			@{$paramRef->{'prefs'}->{$pref}} = $client->prefGetArray($pref);
		}
		
		if ($pref eq 'alarmtime') {

			for my $i (0..7) {

				my $time = Slim::Utils::DateTime::secsToPrettyTime(
					$client->prefGet('alarmtime', $i)
				);
				
				${$paramRef->{'prefs'}->{'alarmtime'}}[$i] = $time;
			}
		}
	}

	return $class->SUPER::handler($client, $paramRef);
}

1;

__END__
