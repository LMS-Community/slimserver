package Slim::Web::Settings::Player::Alarm;

# Logitech Media Server Copyright 2001-2020 Logitech.
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
	Slim::Web::Pages->addPageLinks('icons', { 'ALARM' => 'html/images/alarm.png' });
	
	$class->SUPER::new();
}

sub name {
	return Slim::Web::HTTP::CSRF->protectName('ALARM');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('settings/player/alarm.html');
}

sub needsClient {
	return 1;
}

sub prefs {
	my ($class, $client) = @_;

	my @prefs = qw(alarmfadeseconds alarmsEnabled);

	unless (defined $prefs->client($client)->get('digitalVolumeControl')
		&& !$prefs->client($client)->get('digitalVolumeControl')) {
			
		push @prefs, 'alarmDefaultVolume';
	}

	return ($prefs->client($client), @prefs);
}

sub handler {
	my ($class, $client, $paramRef) = @_;

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

		# pref is in seconds, we only want to expose minutes in the web UI
		$prefsClass->set('alarmSnoozeSeconds', $paramRef->{'pref_alarmSnoozeMinutes'} * 60);
		$prefsClass->set('alarmTimeoutSeconds', $paramRef->{'pref_alarmTimeoutMinutes'} * 60);

		for my $alarmID ( @{ $editedAlarms->{id} } ) {

			if ($alarmID eq NEWALARMID) {

				if ($paramRef->{'alarmtime' . NEWALARMID} && (my $alarm = Slim::Utils::Alarm->new($client, 0))) {
					
					saveAlarm($alarm, NEWALARMID, $paramRef);
	
					# saveAlarm() might have enabled alarms again, if this was the very first alarm
					if (@{ $editedAlarms->{id} } == 1) {
						$paramRef->{'pref_alarmsEnabled'} = $prefsClass->get('alarmsEnabled');
					}
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

	$paramRef->{'prefs'}->{'pref_alarmSnoozeMinutes'} = $prefsClass->get('alarmSnoozeSeconds') / 60;
	$paramRef->{'prefs'}->{'pref_alarmTimeoutMinutes'} = $prefsClass->get('alarmTimeoutSeconds') / 60;

	$paramRef->{'playlistOptions'} = Slim::Utils::Alarm->getPlaylists($client);
	$paramRef->{'newAlarmID'}      = NEWALARMID;
	
	$paramRef->{'timeFormat'} = $prefs->get('timeFormat');
	# need to remove seconds
	$paramRef->{'timeFormat'} =~ s/[\.,:]{1}\%S//g;
	# need to convert our timeformat into JS/PHP compatible format
	$paramRef->{'timeFormat'} =~ s/h/\\\\h/g;
	$paramRef->{'timeFormat'} =~ s/\|\%I/g/g;
	$paramRef->{'timeFormat'} =~ s/\%I/h/g;
	$paramRef->{'timeFormat'} =~ s/\|\%H/G/g;
	$paramRef->{'timeFormat'} =~ s/\%H/H/g;
	$paramRef->{'timeFormat'} =~ s/\%M/i/g;
	$paramRef->{'timeFormat'} =~ s/\W*\%S//g;
	$paramRef->{'timeFormat'} =~ s/\%p/A/g;

	# if we're using a "am/pm" format, make it case independant
	$paramRef->{'altFormats'} = $paramRef->{'timeFormat'};
	$paramRef->{'altFormats'} =~ s/A/a/g;

	# Get the non-calendar alarms for this client
	$paramRef->{'prefs'}->{'alarms'} = [Slim::Utils::Alarm->getAlarms($client, 1)];
	
	return $class->SUPER::handler($client, $paramRef);
}

sub saveAlarm {
	my $alarm    = shift;
	my $id       = shift;
	my $paramRef = shift;
	
	my $playlist = $paramRef->{'alarmplaylist' . $id};
	if ($playlist eq '') {
		$playlist = undef;
	}
	$alarm->playlist($playlist);

	# prettyTimeToSecs() can only handle : as a separator
	$paramRef->{'alarmtime' . $id} =~ s/[\.,]/:/g;

	# don't accept hours > midnight
	my $t       = Slim::Utils::DateTime::prettyTimeToSecs( $paramRef->{'alarmtime' . $id} );
	my ($h, $m) = Slim::Utils::DateTime::splitTime($t);

	if ($h > 23) {
		
		$t = Slim::Utils::DateTime::prettyTimeToSecs($h % 24 . ":$m");
	}

	$alarm->time($t);
	$alarm->enabled( $paramRef->{'alarm_enable' . $id} );
	$alarm->repeat( $paramRef->{'alarm_repeat' . $id} );
	$alarm->shufflemode( $paramRef->{'alarm_shufflemode' . $id} );

	for my $day (0 .. 6) {

		$alarm->day($day, $paramRef->{'alarmday' . $id . $day} ? 1 : 0);
	}

	$alarm->save;
}

1;

__END__
