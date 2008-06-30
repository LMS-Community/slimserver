package Slim::Web::Settings::Player::Alarm;

# $Id: Basic.pm 10633 2006-11-09 04:26:27Z kdf $

# SqueezeCenter Copyright 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::DateTime;
use Slim::Utils::Log;
use Slim::Utils::Prefs;

my $prefs = preferences('server');

sub name {
	return Slim::Web::HTTP::protectName('ALARM_SETTINGS');
}

sub page {
	return Slim::Web::HTTP::protectURI('settings/player/alarm.html');
}

sub needsClient {
	return 1;
}

sub prefs {
	my ($class, $client) = @_;

	return ($prefs->client($client), qw(alarmSnoozeSeconds alarmfadeseconds));
}

sub handler {
	my ($class, $client, $paramRef) = @_;

	my $prefs = preferences('server');

	my ($prefsClass, @prefs) = $class->prefs($client);

	if ($paramRef->{'saveSettings'}) {
		for my $alarm (Slim::Utils::Alarm->getAlarms($client)) {
			if ($paramRef->{'Remove'.$alarm->id}) {
				$alarm->delete;
			} else {
				$alarm->volume($paramRef->{'alarmvolume'.$alarm->id});
				$alarm->playlist($paramRef->{'alarmplaylist'.$alarm->id});

				my $t = Slim::Utils::DateTime::prettyTimeToSecs($paramRef->{'alarmtime'.$alarm->id});
				my ($h, $m) = Slim::Utils::DateTime::splitTime($t);
				# don't accept hours > midnight
				$t = Slim::Utils::DateTime::prettyTimeToSecs($h % 24 . ":$m") if ($h > 23);
				$alarm->time($t);

				$alarm->enabled($paramRef->{'alarm_enable'.$alarm->id});
				$alarm->repeat($paramRef->{'alarm_repeat'.$alarm->id});
				for my $day (1 .. 7) {
					$alarm->day($day,$paramRef->{'alarmday'.$alarm->id.$day} ? 1 : 0);
				}
				$alarm->save;
			}
		}
		if ($paramRef->{'AddAlarm'}) {
				my $newAlarm = Slim::Utils::Alarm->new($client,0);
				$newAlarm->enabled(1);
				$newAlarm->save;
		}
	}

	my %playlistTypes = Slim::Utils::Alarm->getPlaylists($client);
	
	$paramRef->{'playlistOptions'} = \%playlistTypes;
	$paramRef->{'defaultVolume'}   = Slim::Utils::Alarm->defaultVolume($client);

	# Get the non-calendar alarms for this client
	$paramRef->{'prefs'}->{'alarms'} = [Slim::Utils::Alarm->getAlarms($client, 1)];
	
	return $class->SUPER::handler($client, $paramRef);
}

1;

__END__
