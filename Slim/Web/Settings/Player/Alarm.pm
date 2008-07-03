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

use constant NEWALARMID => '_new';

my $prefs = preferences('server');

sub new {
	my $class = shift;

	Slim::Web::Pages->addPageLinks('plugins', { $class->name => $class->page });
	
	$class->SUPER::new();
}

sub name {
	return Slim::Web::HTTP::protectName('ALARM');
}

sub page {
	return Slim::Web::HTTP::protectURI('settings/player/alarm.html');
}

sub needsClient {
	return 1;
}

sub prefs {
	my ($class, $client) = @_;

	return ($prefs->client($client), qw(alarmSnoozeSeconds alarmfadeseconds alarmsEnabled alarmDefaultVolume));
}

sub handler {
	my ($class, $client, $paramRef) = @_;

	my $prefs = preferences('server');

	my ($prefsClass, @prefs) = $class->prefs($client);

	my $editedAlarms = {
		id     => [],
		remove => [],
	};
	
	foreach (keys %{ $paramRef }) {
		
		if (/alarm_(id|remove)_(.+)/) {
			
			push @{ $editedAlarms->{$1} }, $2; 
		}
	}

	if ($paramRef->{'saveSettings'}) {

		for my $alarmID ( @{ $editedAlarms->{id} } ) {

			if ($alarmID eq NEWALARMID) {

				if ($paramRef->{'alarmtime' . NEWALARMID} && (my $alarm = Slim::Utils::Alarm->new($client, 0))) {
					
					saveAlarm($alarm, NEWALARMID, $paramRef);
				}		
			}

			elsif (my $alarm = Slim::Utils::Alarm->getAlarm($client, $alarmID)) {
				
				saveAlarm($alarm, $alarmID, $paramRef);
			}
		}
	}

	for my $alarmID ( @{ $editedAlarms->{remove} } ) {

		if (my $alarm = Slim::Utils::Alarm->getAlarm($client, $alarmID)) {

			$alarm->delete;

		}
	}

	my %playlistTypes = Slim::Utils::Alarm->getPlaylists($client);
	
	$paramRef->{'playlistOptions'} = \%playlistTypes;
	$paramRef->{'newAlarmID'}      = NEWALARMID;

	# Get the non-calendar alarms for this client
	$paramRef->{'prefs'}->{'alarms'} = [Slim::Utils::Alarm->getAlarms($client, 1)];
	
	return $class->SUPER::handler($client, $paramRef);
}

sub saveAlarm {
	my $alarm    = shift;
	my $id       = shift;
	my $paramRef = shift;
	
	$alarm->volume( $paramRef->{'alarmvolume' . $id} );
	$alarm->usesDefaultVolume( $paramRef->{'usesDefaultVolume' . $id} );
	$alarm->playlist( $paramRef->{'alarmplaylist' . $id} );

	# don't accept hours > midnight
	my $t       = Slim::Utils::DateTime::prettyTimeToSecs( $paramRef->{'alarmtime' . $id} );
	my ($h, $m) = Slim::Utils::DateTime::splitTime($t);

	if ($h > 23) {
		
		$t = Slim::Utils::DateTime::prettyTimeToSecs($h % 24 . ":$m");
	}

	$alarm->time($t);
	$alarm->enabled( $paramRef->{'alarm_enable' . $id} );
	$alarm->repeat( $paramRef->{'alarm_repeat' . $id} );

	for my $day (0 .. 6) {

		$alarm->day($day, $paramRef->{'alarmday' . $id . $day} ? 1 : 0);
	}

	$alarm->save;
}

1;

__END__
