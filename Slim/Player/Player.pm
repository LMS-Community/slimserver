# SlimServer Copyright (c) 2001, 2002, 2003 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
package Slim::Player::Player;

use Slim::Player::Client;
use Slim::Hardware::Decoder;
use Slim::Utils::Misc;

@ISA = ("Slim::Player::Client");

sub new {
	my $class = shift;
	my $id = shift;
	my $paddr = shift;
	my $revision = shift;
	my $client = Slim::Player::Client->new($id, $paddr);
	bless $client, $class;

	# initialize model-specific features:
	$client->revision($revision);

	return $client;
}

sub init {
	my $client = shift;
	# fire it up!
	$client->power(Slim::Utils::Prefs::clientGet($client,'power'));
	$client->startup();
                
	# start the screen saver
	Slim::Buttons::ScreenSaver::screenSaver($client);
}

# usage							float		buffer fullness as a percentage
sub usage {
	my $client = shift;
	return $client->bufferFullness() / $client->buffersize();
}

sub update {
	my $client = shift;
	Slim::Display::Animation::killAnimation($client);
	Slim::Hardware::VFD::vfdUpdate($client, Slim::Display::Display::curLines($client));
}	

sub isPlayer {
	return 1;
}

sub power {
	my $client = shift;
	my $on = shift;
	
	my $mode = Slim::Buttons::Common::mode($client);
	my $currOn;
	if (defined($mode)) {
		$currOn = $mode ne "off" ? 1 : 0;
	}
	
	if (!defined $on) {
		return ($currOn);
	} else {
		if (!defined($currOn) || ($currOn != $on)) {
			if ($on) {
				Slim::Buttons::Common::setMode($client, 'home');
				
				my $welcome = Slim::Utils::Prefs::clientGet($client, "doublesize") ? '' : Slim::Display::Display::center(Slim::Utils::Strings::string('WELCOME_TO_' . $client->model));
				my $welcome2 = Slim::Utils::Prefs::clientGet($client, "doublesize") ? '' : Slim::Display::Display::center(Slim::Utils::Strings::string('FREE_YOUR_MUSIC'));
				Slim::Display::Animation::showBriefly($client, $welcome, $welcome2);
				
				# restore the saved brightness, unless its completely dark...
				my $powerOnBrightness = Slim::Utils::Prefs::clientGet($client, "powerOnBrightness");
				if ($powerOnBrightness < 1) { 
					$powerOnBrightness = 1;
				}
				Slim::Utils::Prefs::clientSet($client, "powerOnBrightness", $powerOnBrightness);
				#check if there is a sync group to restore
				Slim::Player::Sync::restoreSync($client);
				# restore volume (un-mute if necessary)
				my $vol = Slim::Utils::Prefs::clientGet($client,"volume");
				if($vol < 0) { 
					# un-mute volume
					$vol *= -1;
					Slim::Utils::Prefs::clientSet($client, "volume", $vol);
				}
				Slim::Control::Command::execute($client, ["mixer", "volume", $vol]);
			
			} else {
				Slim::Buttons::Common::setMode($client, 'off');
			}
			# remember that we were on if we restart the server
			Slim::Utils::Prefs::clientSet($client, 'power', $on ? 1 : 0);
		}
	}
}			

sub volume {
	my ($client, $volume) = @_;

	if (!$client->isPlayer()) {
		return 1;
	}

	if ($volume > $Slim::Player::Client::maxVolume) { $volume = $Slim::Player::Client::maxVolume; }
	if ($volume < 0) { $volume = 0; }
	
	# normalize
	$volume = $volume / $Slim::Player::Client::maxVolume;

	$::d_control && msg("volume: $volume\n");
 	
	Slim::Hardware::Decoder::volume($client, $volume);
}

sub treble {
	my ($client, $treble) = @_;
	if ($treble > $Slim::Player::Client::maxTreble) { $treble = $Slim::Player::Client::maxTreble; }
	if ($treble < $Slim::Player::Client::minTreble) { $treble = $Slim::Player::Client::minTreble; }

	Slim::Hardware::Decoder::treble($client, $treble);
}


sub bass {
	my ($client, $bass) = @_;
	if ($bass > $Slim::Player::Client::maxBass) { $bass = $Slim::Player::Client::maxBass; }
	if ($bass < $Slim::Player::Client::minBass) { $bass = $Slim::Player::Client::minBass; }

	Slim::Hardware::Decoder::bass($client, $bass);
}




# fade the volume up or down
# $fade = number of seconds to fade 100% (positive to fade up, negative to fade down) 
# $callback is function reference to be called when the fade is complete
# FYI 8 to 10 seems to be a good fade value
my %fvolume;  # keep temporary fade volume for each client
sub fade_volume {
	my($client, $fade, $callback, $callbackargs) = @_;

	my $faderate = 20;  # how often do we send updated fade volume commands per second
	
	Slim::Utils::Timers::killTimers($client, \&fade_volume);
	
	my $vol = Slim::Utils::Prefs::clientGet($client, "volume");
	my $mute = Slim::Utils::Prefs::clientGet($client, "mute");
	if ($vol < 0) {
		# the volume is muted, don't fade.
		$callback && (&$callback(@$callbackargs));
		return;
	}
	
	if ($mute) {
		# Set Target (Negative indicates mute, but still saves old value)
		Slim::Utils::Prefs::clientSet($client, "volume", $vol * -1);
	}

	# on the first pass, set temporary fade volume
	if(!$fvolume{$client} && $fade > 0) {
		# fading up, start volume at 0
		$fvolume{$client} = 0;
	} elsif(!$fvolume{$client}) {
		# fading down, start volume at current volume
		$fvolume{$client} = $vol;
	}

	$fvolume{$client} += $Slim::Player::Client::maxVolume * (1/$faderate) / $fade; # fade volume

	if ($fvolume{$client} < 0) { $fvolume{$client} = 0; };
	if ($fvolume{$client} > $vol) { $fvolume{$client} = $vol; };

	&volume($client, $fvolume{$client}); # set volume

	if ($fvolume{$client} == 0 || $fvolume{$client} == $vol) {	
		# done fading
		$::d_ui && msg("fade_volume done.\n");
		$fvolume{$client} = 0; # reset temporary fade volume 
		$callback && (&$callback(@$callbackargs));
	} else {
		$::d_ui && msg("fade_volume - setting volume to $fvolume{$client} (originally $vol)\n");
		Slim::Utils::Timers::setTimer($client, Time::HiRes::time()+ (1/$faderate), \&fade_volume, ($fade, $callback, $callbackargs));
	}
}

# mute or un-mute volume as necessary
# A negative volume indicates that the player is muted and should be restored 
# to the absolute value when un-muted.
sub mute {
	my $client = shift;
	
	if (!$client->isPlayer()) {
		return 1;
	}
	my $vol = Slim::Utils::Prefs::clientGet($client, "volume");
	my $mute = Slim::Utils::Prefs::clientGet($client, "mute");
	
			
	if (($vol < 0) && ($mute)) {
		# mute volume
		# todo: there is actually a hardware mute feature
		# in both decoders. Need to add Decoder::mute
		&volume($client, 0);
	} else {
		# un-mute volume
		$vol *= -1;
		&volume($client, $vol);
	}
	Slim::Utils::Prefs::clientSet($client, "volume", $vol);
	Slim::Display::Display::volumeDisplay($client);
}

sub hasDigitalOut {
	return 0;
}
	

1;

