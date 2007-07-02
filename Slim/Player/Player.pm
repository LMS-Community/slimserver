package Slim::Player::Player;

# SlimServer Copyright (c) 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# $Id$
#

use strict;

use Scalar::Util qw(blessed);

use base qw(Slim::Player::Client);

use Slim::Buttons::SqueezeNetwork;
use Slim::Hardware::IR;
use Slim::Player::Client;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;

my $log = logger('player.ui');

my $prefs = preferences('server');

our $defaultPrefs = {
	'bass'                 => 50,
	'digitalVolumeControl' => 1,
	'preampVolumeControl'  => 0,
	'disabledirsets'       => [],
	'irmap'                => \&Slim::Hardware::IR::defaultMapFile(),
	'menuItem'             => [qw(
		NOW_PLAYING
		BROWSE_MUSIC
		SEARCH
		PLUGIN_RANDOMPLAY
		FAVORITES
		SAVED_PLAYLISTS
		RADIO
		SETTINGS
		PLUGINS
	)],
	'mp3SilencePrelude'    => 0,
	'pitch'                => 100,
	'power'                => 1,
	'powerOffBrightness'   => 1,
	'powerOnBrightness'    => 4,
	'screensaver'          => 'playlist',
	'idlesaver'            => 'nosaver',
	'offsaver'             => 'SCREENSAVER.datetime',
	'screensavertimeout'   => 30,
	'silent'               => 0,
	'syncPower'            => 0,
	'syncVolume'           => 0,
	'treble'               => 50,
	'volume'               => 50,
	'syncBufferThreshold'  => 128,
	'bufferThreshold'      => 255,
	'powerOnResume'        => 'PauseOff-NoneOn',
};

sub new {
	my $class    = shift;
	my $id       = shift;
	my $paddr    = shift;
	my $revision = shift;

	my $client = $class->SUPER::new($id, $paddr);

	# initialize model-specific features:
	$client->revision($revision);

	return $client;
}

sub init {
	my $client = shift;

	# make sure any preferences this client may not have set are set to the default
	# This should be a method on client!
	$prefs->client($client)->init($defaultPrefs);

	$client->SUPER::init();

	Slim::Buttons::Home::updateMenu($client);

	# fire it up!
	$client->power($prefs->client($client)->get('power'));
	$client->startup();

	# start the screen saver
	Slim::Buttons::ScreenSaver::screenSaver($client);
	$client->brightness($prefs->client($client)->get($client->power() ? 'powerOnBrightness' : 'powerOffBrightness'));
}

# usage	- float	buffer fullness as a percentage
sub usage {
	my $client = shift;
	return $client->bufferSize() ? $client->bufferFullness() / $client->bufferSize() : 0;
}

# following now handled by display object
sub update      { shift->display->update(@_); }
sub showBriefly { shift->display->showBriefly(@_); }
sub pushLeft    { shift->display->pushLeft(@_); }
sub pushRight   { shift->display->pushRight(@_); }
sub pushUp      { shift->display->pushUp(@_); }
sub pushDown    { shift->display->pushDown(@_); }
sub bumpLeft    { shift->display->bumpLeft(@_); }
sub bumpRight   { shift->display->bumpRight(@_); }
sub bumpUp      { shift->display->bumpUp(@_); }
sub bumpDown    { shift->display->bumpDown(@_); }
sub brightness  { shift->display->brightness(@_); }
sub maxBrightness { shift->display->maxBrightness(@_); }
sub scrollTickerTimeLeft { shift->display->scrollTickerTimeLeft(@_); }
sub killAnimation { shift->display->killAnimation(@_); }
sub textSize    { shift->display->textSize(@_); }
sub maxTextSize { shift->display->maxTextSize(@_); }
sub linesPerScreen { shift->display->linesPerScreen(@_); }
sub symbols     { shift->display->symbols(@_); }
sub prevline1   { if (my $display = shift->display) { return $display->prevline1(@_); }}
sub prevline2   { if (my $display = shift->display) { return $display->prevline2(@_); }}
sub curDisplay  { shift->display->curDisplay(@_); }
sub curLines    { shift->display->curLines(@_); }
sub parseLines  { shift->display->parseLines(@_); }
sub renderOverlay { shift->display->renderOverlay(@_); }
sub measureText { shift->display->measureText(@_); }
sub displayWidth{ shift->display->displayWidth(@_); }
sub sliderBar   { shift->display->sliderBar(@_); }
sub progressBar { shift->display->progressBar(@_); }
sub balanceBar  { shift->display->balanceBar(@_); }
sub fonts         { shift->display->fonts(@_); }
sub displayHeight { shift->display->displayHeight(@_); }
sub currBrightness { shift->display->currBrightness(@_); }
sub vfdmodel    { shift->display->vfdmodel(@_); }

sub updateMode  { shift->display->updateMode(@_); }
sub animateState{ shift->display->animateState(@_); }
sub scrollState { shift->display->scrollState(@_); }

sub block       { Slim::Buttons::Block::block(@_); }
sub unblock     { Slim::Buttons::Block::unblock(@_); }

sub string      { shift->display->string(@_); }
sub doubleString{ shift->display->doubleString(@_); }

sub isPlayer {
	return 1;
}

sub power {
	my $client = shift;
	my $on = shift;
	
	my $currOn = $prefs->client($client)->get('power') || 0;

	return $currOn unless defined $on;
	return unless (!defined(Slim::Buttons::Common::mode($client)) || ($currOn != $on));

	$client->display->renderCache()->{defaultfont} = undef;

	$prefs->client($client)->set('power', $on);

	my $resume = Slim::Player::Sync::syncGroupPref($client, 'powerOnResume') || $prefs->client($client)->get('powerOnResume');
	$resume =~ /(.*)Off-(.*)On/;
	my ($resumeOff, $resumeOn) = ($1,$2);

	if (!$on) {

		# turning player off - move to off mode and unsync/pause/stop player
		$client->killAnimation();
		$client->brightness($prefs->client($client)->get('powerOffBrightness'));

		Slim::Buttons::Common::setMode($client, 'off');

		my $sync = $prefs->client($client)->get('syncPower');

		if (defined $sync && $sync == 0) {

			logger('player.sync')->info("Temporary Unsync " . $client->id);

			Slim::Player::Sync::unsync($client, 1);
  		}
  
		if (Slim::Player::Source::playmode($client) eq 'play') {

			if (Slim::Player::Playlist::song($client) && 
				Slim::Music::Info::isRemoteURL(Slim::Player::Playlist::url($client))) {
				# always stop if currently playing remote stream
				$client->execute(["stop"]);
			
			} elsif ($resumeOff eq 'Pause') {
				# Pause client mid track
				$client->execute(["pause", 1]);
  		
			} else {
				# Stop client
				$client->execute(["stop"]);
			}
		}

		# turn off audio outputs
		$client->audio_outputs_enable(0);

	} else {

		# turning player on - reset mode & brightness, display welcome and sync/start playing
		$client->audio_outputs_enable(1);

		$client->update( { 'screen1' => {}, 'screen2' => {} } );

		$client->updateMode(2); # block updates to hide mode change

		Slim::Buttons::Common::setMode($client, 'home');

		$client->updateMode(0); # unblock updates
		
		# restore the saved brightness, unless its completely dark...
		my $powerOnBrightness = $prefs->client($client)->get('powerOnBrightness');

		if ($powerOnBrightness < 1) {
			$powerOnBrightness = 1;
			$prefs->client($client)->set('powerOnBrightness', $powerOnBrightness);
		}
		$client->brightness($powerOnBrightness);

		my $oneline = ($client->linesPerScreen() == 1);
		
		$client->showBriefly( {
			'center' => [ $client->string('WELCOME_TO_' . $client->model), $client->string('FREE_YOUR_MUSIC') ],
			'fonts' => { 
					'graphic-320x32' => 'standard',
					'graphic-280x16' => 'medium',
					'text'           => 2,
				},
			'screen2' => {},
		}, undef, undef, 1);

		# check if there is a sync group to restore
		Slim::Player::Sync::restoreSync($client);

		if (Slim::Player::Source::playmode($client) ne 'play') {
			
			if ($resumeOn =~ /Reset/) {
				# reset playlist to start
				$client->execute(["playlist","jump", 0, 1]);
			}

			if ($resumeOn =~ /Play/ && Slim::Player::Playlist::song($client) &&
				!Slim::Music::Info::isRemoteURL(Slim::Player::Playlist::url($client))) {
				# play if current playlist item is not a remote url
				$client->execute(["play"]);
			}
		}		
	}
}

sub audio_outputs_enable { }

sub maxVolume { return 100; }
sub minVolume {	return 0; }

sub maxTreble {	return 100; }
sub minTreble {	return 0; }

sub maxBass {	return 100; }
sub minBass {	return 0; }

# fade the volume up or down
# $fade = number of seconds to fade 100% (positive to fade up, negative to fade down) 
# $callback is function reference to be called when the fade is complete

sub fade_volume {
	my ($client, $fade, $callback, $callbackargs) = @_;

	my $int = 0.05; # interval between volume updates

	my $vol = abs($prefs->client($client)->get("volume"));
	
	Slim::Utils::Timers::killHighTimers($client, \&_fadeVolumeUpdate);

	$client->_fadeVolumeUpdate( {
		'startVol' => ($fade > 0) ? 0 : $vol,
		'endVol'   => ($fade > 0) ? $vol : 0,
		'startTime'=> Time::HiRes::time(),
		'int'      => $int,
		'rate'     => ($vol && $fade) ? $vol / $fade : 0,
		'cb'       => $callback,
		'cbargs'   => $callbackargs,
	} );
}

sub _fadeVolumeUpdate {
	my $client = shift;
	my $f = shift;
	
	# If the user manually changed the volume, stop fading
	if ( $f->{'vol'} && $f->{'vol'} != $client->volume ) {
		return;
	}
	
	my $now = Time::HiRes::time();

	# new vol based on time since fade started to minise impact of timers firing late
	$f->{'vol'} = $f->{'startVol'} + ($now - $f->{'startTime'}) * $f->{'rate'};

	my $rate = $f->{'rate'};

	if (
		   !$rate 
		|| ( $rate < 0 && $f->{'vol'} < $f->{'endVol'} )
		|| ( $rate > 0 && $f->{'vol'} > $f->{'endVol'} )
		|| !$client->power
	) {

		# reached end of fade
		$client->volume($f->{'endVol'}, 1);

		if ($f->{'cb'}) {
			&{$f->{'cb'}}(@{$f->{'cbargs'}});
		}

	} else {

		$client->volume($f->{'vol'}, 1);
		Slim::Utils::Timers::setHighTimer($client, $now + $f->{'int'}, \&_fadeVolumeUpdate, $f);
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

	my $vol = $prefs->client($client)->get('volume');
	my $mute = $prefs->client($client)->get('mute');
	
	if (($vol < 0) && ($mute)) {
		# mute volume
		# todo: there is actually a hardware mute feature
		# in both decoders. Need to add Decoder::mute
		$client->volume(0);
	} else {
		# un-mute volume
		$vol *= -1;
		$client->volume($vol);
	}

	$prefs->client($client)->set('volume', $vol);
	$client->mixerDisplay('volume');
}

sub hasDigitalOut {
	return 0;
}

sub hasVolumeControl {
	return 1;
}
	
sub sendFrame {};

sub currentSongLines {
	my $client = shift;
	my $suppressScreen2 = shift;

	my $parts;
	
	my $playlistlen = Slim::Player::Playlist::count($client);

	if ($playlistlen < 1) {

		$parts = { 'line' => [ $client->string('NOW_PLAYING'), $client->string('NOTHING') ] };

		if ($client->display->showExtendedText() && !$suppressScreen2) {
			$parts->{'screen2'} = {};
		}

	} else {

		if (Slim::Player::Source::playmode($client) eq "pause") {

			if ( $playlistlen == 1 ) {

				$parts->{line}[0] = $client->string('PAUSED');

			} else {

				$parts->{line}[0] = sprintf(
					$client->string('PAUSED')." (%d %s %d) ",
					Slim::Player::Source::playingSongIndex($client) + 1, $client->string('OUT_OF'), $playlistlen
				);
			}

		# for taking photos of the display, comment out the line above, and use this one instead.
		# this will cause the display to show the "Now playing" screen to show when paused.
		# line1 = "Now playing" . sprintf " (%d %s %d) ", Slim::Player::Source::playingSongIndex($client) + 1, string('OUT_OF'), $playlistlen;

		} elsif (Slim::Player::Source::playmode($client) eq "stop") {

			if ( $playlistlen == 1 ) {
				$parts->{line}[0] = $client->string('STOPPED');
			}
			else {
				$parts->{line}[0] = sprintf(
					$client->string('STOPPED')." (%d %s %d) ",
					Slim::Player::Source::playingSongIndex($client) + 1, $client->string('OUT_OF'), $playlistlen
				);
			}

		} else {

			if (Slim::Player::Source::rate($client) != 1) {
				$parts->{line}[0] = $client->string('NOW_SCANNING') . ' ' . Slim::Player::Source::rate($client) . 'x';
			} elsif (Slim::Player::Playlist::shuffle($client)) {
				$parts->{line}[0] = $client->string('PLAYING_RANDOMLY');
			} else {
				$parts->{line}[0] = $client->string('PLAYING');
			}
			
			if ($client->volume() < 0) {
				$parts->{line}[0] .= " ". $client->string('LCMUTED');
			}

			if ( $playlistlen > 1 ) {
				$parts->{line}[0] = $parts->{line}[0] . sprintf(
					" (%d %s %d) ",
					Slim::Player::Source::playingSongIndex($client) + 1, $client->string('OUT_OF'), $playlistlen
				);
			}
		} 

		my $currentTitle = Slim::Music::Info::getCurrentTitle($client, Slim::Player::Playlist::url($client));

		$parts->{line}[1] = $currentTitle;

		$parts->{overlay}[1] = $client->symbols('notesymbol');

		# add in the progress bar and time...
		$client->nowPlayingModeLines($parts);

		# add screen2 information if required
		if ($client->display->showExtendedText() && !$suppressScreen2) {
			
			my ($s2line1, $s2line2);

			my $song = Slim::Player::Playlist::song($client);

			if ($song && $song->isRemoteURL) {

				my $title = Slim::Music::Info::displayText($client, $song, 'TITLE');

				if ( ($currentTitle || '') ne ($title || '') && !Slim::Music::Info::isURL($title) ) {
					$s2line2 = $title;
				}

			} else {

				$s2line1 = Slim::Music::Info::displayText($client, $song, 'ALBUM');
				$s2line2 = Slim::Music::Info::displayText($client, $song, 'ARTIST');

			}

			$parts->{'screen2'} = {
				'line' => [ $s2line1, $s2line2 ],
			};
		}
	}

	return $parts;
}

sub nowPlayingModeLines {
	my ($client, $parts) = @_;

	my $display = $client->display;

	my $overlay;
	my $fractioncomplete = 0;
	my $songtime = '';

	my $mode = $prefs->client($client)->get('playingDisplayModes')->[ $prefs->client($client)->get('playingDisplayMode') ];

	unless (defined $mode) { $mode = 1; };

	my $modeOpts = $display->modes->[$mode];

	my $showBar      = $modeOpts->{bar};
	my $showTime     = $modeOpts->{secs};
	my $displayWidth = $modeOpts->{width};
	my $showFullness = $modeOpts->{fullness};
	
	# check if we don't know how long the track is...
	if (!Slim::Player::Source::playingSongDuration($client)) {
		$showBar = 0;
	}
	
	if ($showFullness) {
		$fractioncomplete = $client->usage();
	} elsif ($showBar) {
		$fractioncomplete = Slim::Player::Source::progress($client);
	}
	
	if ($showFullness) {
		$songtime = ' ' . int($fractioncomplete * 100 + 0.5)."%";
		
		# for remote streams where we know the bitrate, 
		# show the number of seconds of audio in the buffer instead of a percentage
		my $url = Slim::Player::Playlist::url($client);
		if ( Slim::Music::Info::isRemoteURL($url) ) {
			my $decodeBuffer;
			
			# Display decode buffer as seconds if we know the bitrate, otherwise show KB
			my $bitrate = Slim::Music::Info::getBitrate($url);
			if ( $bitrate > 0 ) {
				$decodeBuffer = sprintf( "%.1f", $client->bufferFullness() / ( int($bitrate / 8) ) );
			}
			else {
				$decodeBuffer = sprintf( "%d KB", $client->bufferFullness() / 1024 );
			}
			
			if ( $client->isa('Slim::Player::Squeezebox2') ) {
				# Only show output buffer status on SB2 and higher
				my $outputBuffer = $client->outputBufferFullness() / (44100 * 8);
				$songtime  = ' ' . sprintf "%s / %.1f", $decodeBuffer, $outputBuffer;
				$songtime .= ' ' . $client->string('SECONDS');
			}
			else {
				$songtime  = ' ' . sprintf "%s", $decodeBuffer;
				$songtime .= ' ' . $client->string('SECONDS');
			}
		}
	} elsif ($showTime) { 
		$songtime = ' ' . $client->textSongTime($showTime < 0);
	}

	if ($showTime || $showFullness) {
		$overlay = $songtime;
	}
	
	if ($showBar) {
		# show both the bar and the time
		my $leftLength = $display->measureText($parts->{line}[0], 1);
		my $barlen = $displayWidth - $leftLength - $display->measureText($overlay, 1);
		my $bar    = $display->symbols($client->progressBar($barlen, $fractioncomplete, ($showBar < 0)));

		$overlay = $bar . $songtime;
	}
	
	$parts->{overlay}[0] = $overlay if defined($overlay);
}

sub textSongTime {
	my $client = shift;
	my $remaining = shift;

	my $delta = 0;
	my $sign  = '';

	my $duration = Slim::Player::Source::playingSongDuration($client) || 0;

	if (Slim::Player::Source::playmode($client) eq "stop") {
		$delta = 0;
	} else {	
		$delta = Slim::Player::Source::songTime($client);
		if ($duration && $delta > $duration) {
			$delta = $duration;
		}
	}

	# 2 and 5 display remaining time, not elapsed
	if ($remaining) {
		if ($duration) {
			$delta = $duration - $delta;	
			$sign = '-';
		}
	}
	
	my $hrs = int($delta / (60 * 60));
	my $min = int(($delta - $hrs * 60 * 60) / 60);
	my $sec = $delta - ($hrs * 60 * 60 + $min * 60);
	
	if ($hrs) {

		return sprintf("%s%d:%02d:%02d", $sign, $hrs, $min, $sec);

	} else {

		return sprintf("%s%02d:%02d", $sign, $min, $sec);
	}
}

sub mixerDisplay {
	my $client = shift;
	my $feature = shift;
	
	if ($feature !~ /(?:volume|pitch|bass|treble)/) {
		return;
	}

	my $featureValue = $prefs->client($client)->get($feature);

	# Check for undefined - 0 is a valid value.
	if (!defined $featureValue) {
		return;
	}

	my $mid   = $client->mixerConstant($feature, 'mid');
	my $scale = $client->mixerConstant($feature, 'scale');

	my $headerValue = '';
	my ($parts, $oldvisu, $savedvisu);

	if ($client->mixerConstant($feature, 'balanced')) {

		$headerValue = sprintf(' (%d)', int((($featureValue - $mid) * $scale) + 0.5));

	} elsif ($feature eq 'volume') {

		if (my $linefunc = $client->customVolumeLines()) {

			$parts = &$linefunc($client, $featureValue);

		} else {
			
			$headerValue = $client->volumeString($featureValue);

		}

	} else {

		$headerValue = sprintf(' (%d)', int(($featureValue * $scale) + 0.5));
	}

	if ($feature eq 'pitch') {

		$headerValue .= '%';
	}

	my $featureHeader = join('', $client->string(uc($feature)), $headerValue);

	if (blessed($client->display) eq 'Slim::Display::Squeezebox2') {
		# XXXX hack attack: turn off visualizer when showing volume, etc.		
		$oldvisu = $client->modeParam('visu');
		$savedvisu = 1;
		$client->modeParam('visu', [0]);
	}

	$parts ||= Slim::Buttons::Input::Bar::lines($client, $featureValue, $featureHeader, {
		'min'       => $client->mixerConstant($feature, 'min'),
		'mid'       => $mid,
		'max'       => $client->mixerConstant($feature, 'max'),
		'noOverlay' => 1,
	});

	$client->display->showBriefly($parts, { 'name' => 'mixer' } );

	# Turn the visualizer back to it's old value.
	if ($savedvisu) {
		$client->modeParam('visu', $oldvisu);
	}
}

1;

__END__
