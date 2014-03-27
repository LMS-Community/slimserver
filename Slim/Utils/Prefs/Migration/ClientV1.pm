package Slim::Utils::Prefs::Migration::ClientV1;

use strict;

use Slim::Utils::Prefs::OldPrefs;

sub init {
	my ($class, $prefs) = @_;
	
	# migrate old preferences to new client preferences
	$prefs->migrateClient(1, sub {
		my ($clientprefs, $client) = @_;
		my @migrate = qw(
						 alarmfadeseconds alarm alarmtime alarmvolume alarmplaylist
						 powerOnresume lame maxBitrate lameQuality
						 synchronize syncVolume syncPower powerOffDac disableDac transitionType transitionDuration digitalVolumeControl
						 mp3SilencePrelude preampVolumeControl digitalOutputEncoding clockSource polarityInversion wordClockOutput
						 replayGainMode mp3StreamingMethod
						 playername titleFormat titleFormatCurr playingDisplayMode playingDisplayModes
						 screensaver alarmsaver idlesaver offsaver screensavertimeout visualMode visualModes
						 powerOnBrightness powerOffBrightness idleBrightness autobrightness
						 scrollMode scrollPause scrollPauseDouble scrollRate scrollRateDouble scrollPixels scrollPixelsDouble
						 activeFont idleFont activeFont_curr idleFont_curr doublesize offDisplaySize largeTextFont
						 irmap disabledirsets
						 power mute volume bass treble pitch repeat shuffle currentSong
						);

		my $toMigrate;

		for my $pref (@migrate) {
			my $old = Slim::Utils::Prefs::OldPrefs->clientGet($client, $pref);
			$toMigrate->{$pref} = $old if defined $old;
		}

		# create migrated version using init as will not call the onchange callbacks
		$clientprefs->init($toMigrate);

		1;
	});
}

1;