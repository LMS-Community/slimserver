package Slim::Web::Settings::Player::Alarm;

# $Id: Basic.pm 10633 2006-11-09 04:26:27Z kdf $

# SlimServer Copyright (c) 2001-2006 Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

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

						my $time    = $paramRef->{'alarmtime'.$i};
						my $newtime = 0;

						$time =~ s{
							^(0?[0-9]|1[0-9]|2[0-4]):([0-5][0-9])\s*(P|PM|A|AM)?$
						}{
							if (defined $3) {
								$newtime = ($1 == 12?0:$1 * 60 * 60) + ($2 * 60) + ($3 =~ /P/?12 * 60 * 60:0);
							} else {
								$newtime = ($1 * 60 * 60) + ($2 * 60);
							}
						}iegsx;

						if ($newtime != $client->prefGet('alarmtime', $i)) {

							push @changed, 'alarmtime'.$i;
						}

						$client->prefSet('alarmtime', $newtime, $i);

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
	my $playlistRef = Slim::Web::Setup::playlists();
	$playlistRef->{''} = undef;

	my $specialPlaylists = \%Slim::Buttons::AlarmClock::specialPlaylists;

	for my $key (keys %{$specialPlaylists}) {

		$playlistRef->{$key} = $key;
	}

	$paramRef->{'playlistOptions'} = { %{$playlistRef} };

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

				my $time = $client->prefGet('alarmtime',$i);
				
				my ($h0, $h1, $m0, $m1, $p) = Slim::Buttons::Input::Time::timeDigits($client,$time);

				my $timestring = ' ';

				if (!defined $p || $h0 != 0) {

					$timestring = $h0;
				}

				$timestring .= "$h1:$m0$m1 ";

				if (defined $p) {
					$timestring .= $p;
				}
				
				${$paramRef->{'prefs'}->{'alarmtime'}}[$i] = $timestring;
			}
		}
	}

	return $class->SUPER::handler($client, $paramRef);
}

1;

__END__
