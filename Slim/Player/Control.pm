package Slim::Player::Control;

# SliMP3 Server Copyright (C) 2001 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

# These are the high-level functions for playback and vol/bass/treble

use strict;

use Slim::Hardware::Decoder;
use Slim::Utils::Misc;
use Slim::Utils::Timers;
use Slim::Networking::Stream;

$Slim::Player::Control::maxVolume = 100;
$Slim::Player::Control::maxTreble = 100;
$Slim::Player::Control::minTreble = 0;
$Slim::Player::Control::maxBass = 100;
$Slim::Player::Control::minBass = 0;

#
# initialize the MAS3507D and tell the client to start a new stream
#
sub play {
	my $client = shift;
	my $paused = shift;
	my $pcm = shift;

	if (!Slim::Player::Client::isSliMP3($client)) {
		return 1;
	}

	&volume($client, Slim::Utils::Prefs::clientGet($client, "volume"));
	Slim::Hardware::Decoder::reset($client, $pcm);
	

	Slim::Networking::Stream::newStream($client, $paused);
	#
	# We can't start playing until the i2c has all been acked. Ideally
	# something like:
	#	Slim::Hardware::i2c::callback_when_done(Slim::Networking::Stream::newStream,($client,$paused));
	# For now just kludge it:
	#Slim::Utils::Timers::setTimer($client, Time::HiRes::time()+2, 
	#	\&Slim::Networking::Stream::newStream, ($paused));

	return 1;
}

#
# set the MAS3507D volume
#
sub volume {
	my ($client, $volume) = @_;

	if (!Slim::Player::Client::isSliMP3($client)) {
		return 1;
	}

	if ($volume > $Slim::Player::Control::maxVolume) { $volume = $Slim::Player::Control::maxVolume; }
	if ($volume < 0) { $volume = 0; }
	
	# normalize
	$volume = $volume / $Slim::Player::Control::maxVolume;

	$::d_control && msg "volume: $volume\n";
 	
	Slim::Hardware::Decoder::volume($client, $volume);
}

#
# set the MAS3507D treble in the range of -1 to 1
#

sub treble {
	my ($client, $treble) = @_;
	if ($treble > $Slim::Player::Control::maxTreble) { $treble = $Slim::Player::Control::maxTreble; }
	if ($treble < $Slim::Player::Control::minTreble) { $treble = $Slim::Player::Control::minTreble; }

	Slim::Hardware::Decoder::treble($client, $treble);
}

#
# set the MAS3507D bass in the range of -1 to 1
#

sub bass {
	my ($client, $bass) = @_;
	if ($bass > $Slim::Player::Control::maxBass) { $bass = $Slim::Player::Control::maxBass; }
	if ($bass < $Slim::Player::Control::minBass) { $bass = $Slim::Player::Control::minBass; }

	Slim::Hardware::Decoder::bass($client, $bass);
}



# fade the volume up or down
# $fade = amount to fade (positive to fade up, negative to fade down)
# $callback is function reference to be called when the fade is complete
# FYI 8 to 10 seems to be a good fade value
my %fvolume;  # keep temporary fade volume for each client
sub fade_volume {
	my($client, $fade, $callback, $callbackargs) = @_;

	if (!Slim::Player::Client::isSliMP3($client)) {
		return 1;
	}
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

	$fvolume{$client} += $fade; # fade volume

	if($fvolume{$client} <= 0 || $fvolume{$client} >= $vol) {
		# done fading
		$::d_ui && msg("fade_volume done.\n");
		$fvolume{$client} = 0; # reset temporary fade volume 
		$callback && (&$callback(@$callbackargs));
	} else {
		$::d_ui && msg("fade_volume - setting volume to $fvolume{$client}\n");
		&volume($client, $fvolume{$client}); # set volume
		Slim::Utils::Timers::setTimer($client, Time::HiRes::time()+0.025, \&fade_volume, ($fade, $callback, $callbackargs));
	}
}

# mute or un-mute volume as necessary
# A negative volume indicates that the player is muted and should be restored 
# to the absolute value when un-muted.
sub mute {
	my $client = shift;
	
	if (!Slim::Player::Client::isSliMP3($client)) {
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

#
# tell the client to unpause the decoder
#
sub resume {
	my $client = shift;

	if (!Slim::Player::Client::isSliMP3($client)) {
		return 1;
	}

	&volume($client, Slim::Utils::Prefs::clientGet($client, "volume"));

	Slim::Networking::Stream::unpause($client);

	return 1;
}

#
# pause
#
sub pause {
	my $client = shift;
	if (!Slim::Player::Client::isSliMP3($client)) {
		return 1;
	}
	Slim::Networking::Stream::pause($client);
	return 1;
}

#
# does the same thing as pause
#
sub stop {
	my $client = shift;

	if (!Slim::Player::Client::isSliMP3($client)) {
		return 1;
	}

	Slim::Networking::Stream::stop($client);
}

#
# playout - play out what's in the buffer
#
sub playout {
	my $client = shift;
	if (!Slim::Player::Client::isSliMP3($client)) {
		return 1;
	}
	Slim::Networking::Stream::playout($client);
	return 1;
}

1;

__END__
