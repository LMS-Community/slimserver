package Slim::Utils::Prefs::Migration::ClientV6;

use strict;

use Slim::Utils::Alarm;

sub init {
	my ($class, $prefs) = @_;

	# migrate old alarm clock prefs into new alarms
	$prefs->migrateClient( 6, sub {
		my ( $cprefs, $client ) = @_;
		
		# Don't migrate if new 'alarms' pref is already here
		if ( $cprefs->get('alarms') ) {
			$cprefs->remove('alarm');
			$cprefs->remove('alarmtime');
			$cprefs->remove('alarmplaylist');
			$cprefs->remove('alarmvolume');
			
			return 1;
		}

		my $alarm    = $cprefs->get('alarm');
		my $time     = $cprefs->get('alarmtime');
		my $playlist = $cprefs->get('alarmplaylist');
		my $volume   = $cprefs->get('alarmvolume');
		
		my @newAlarms;

		my %playlistMap = (
			CURRENT_PLAYLIST => undef,
			'' => undef,
			PLUGIN_RANDOM_TRACK => 'randomplay://track',
			PLUGIN_RANDOM_ALBUM => 'randomplay://album',
			PLUGIN_RANDOM_CONTRIBUTOR => 'randomplay://contributor',
		);

		# Old alarms: day 0 is every day, days 1..7 are mon..sun
		# New alarms: days 0..6 are sun..sat

		# Migrate any alarm that is enabled or has a time that isn't 0
		for (my $day = 0; $day < 8; $day++) {
			if ($alarm->[$day] || $time->[$day]) {
				my $duplicate = 0;
				foreach my $newAlarm (@newAlarms) {
					# Won't get here for day 0
					if ($newAlarm->time == $time->[$day]) {
						if ($newAlarm->day($day % 7)) {
							# Alarm has same time as an everyday alarm.  Ignore.
							$duplicate = 1;
							last;
						} else {
							if (
								(defined $newAlarm->playlist
								&& (defined $playlistMap{$playlist->[$day]} && $newAlarm->playlist eq $playlistMap{$playlist->[$day]})
								|| $newAlarm->playlist eq $playlist->[$day]
								)

								||

								(! defined $newAlarm->playlist
								&& ($playlist->[$day] eq 'CURRENT_PLAYLIST' || $playlist->[$day] eq ''))
							)  {
								# Same as an existing alarm - just add the day to it
								if ($alarm->[$day]) {
									$newAlarm->day($day % 7, 1);
								}
								$duplicate = 1;
								last;
							}
						}
					}
				}

				if (! $duplicate) {
					my $newAlarm = Slim::Utils::Alarm->new($client, $time->[$day]);
					$newAlarm->enabled($alarm->[$day]);
					$newAlarm->everyDay(0);
					if ($day == 0) {
						$newAlarm->everyDay(1);
					} else {
						$newAlarm->day($day % 7, 1);
					}
					if (exists $playlistMap{$playlist->[$day]}) {
						$newAlarm->playlist($playlistMap{$playlist->[$day]});
					} else {
						$newAlarm->playlist($playlist->[$day]);
					}
					push @newAlarms, $newAlarm;
				}
			}
		}

		# Save the new alarms in one batch to avoid calling $alarm->save, which would create an infinite
		# loop when it tried to read prefs (thus causing them to migrate)
		my $prefAlarms = {};
		foreach my $newAlarm (@newAlarms) {
			$prefAlarms->{$newAlarm->id} = $newAlarm->_createSaveable;
		}

		$cprefs->set('alarms', $prefAlarms);
		
		# Remove old alarm prefs
		$cprefs->remove('alarm');
		$cprefs->remove('alarmtime');
		$cprefs->remove('alarmplaylist');
		$cprefs->remove('alarmvolume');

		return 1;
	} );
	
}

1;