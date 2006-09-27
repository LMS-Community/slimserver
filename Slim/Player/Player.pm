package Slim::Player::Player;

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
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

use Slim::Player::Client;
use Slim::Utils::Misc;
use Slim::Hardware::IR;
use Slim::Buttons::SqueezeNetwork;

use base qw(Slim::Player::Client);

our $defaultPrefs = {
	'bass'                 => 50,
	'digitalVolumeControl' => 1,
	'preampVolumeControl'  => 0,
	'disabledirsets'       => [],
	'doublesize'           => 0,
	'irmap'                => Slim::Hardware::IR::defaultMapFile(),
	'menuItem'             => [qw(
		NOW_PLAYING
		BROWSE_MUSIC
		SEARCH
		RandomPlay::Plugin
		FAVORITES
		SAVED_PLAYLISTS
		RADIO
		SETTINGS
		PLUGINS
	)],
	'mp3SilencePrelude'    => 0,
	'offDisplaySize'       => 0,
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
	'upgrade-5.4b1-script' => 1,
	'upgrade-5.4b2-script' => 1,
	'upgrade-6.1b1-script' => 1,
	'upgrade-6.2-script'   => 1,
	'upgrade-R4627-script' => 1,
	'upgrade-R8775-script' => 1,
	'upgrade-R9279-script' => 1,
	'volume'               => 50,
	'syncBufferThreshold'  => 128,
	'bufferThreshold'      => 255,
	'powerOnResume'        => 'PauseOff-NoneOn',
};

our %upgradeScripts = (

	# Allow the "upgrading" of old menu items to new ones.
	'5.4b1' => sub {

		my $client = shift;
		my $index  = 0;

		foreach my $menuItem ($client->prefGetArray('menuItem')) {

			if ($menuItem eq 'ShoutcastBrowser') {
				$client->prefSet('menuItem', 'RADIO', $index);
				last;
			}

			$index++;
		}
	},

	'5.4b2' => sub {
		my $client = shift;

		my $addedBrowse = 0;
		my @newitems = ();

		foreach my $menuItem ($client->prefGetArray('menuItem')) {

			if ($menuItem =~ 'BROWSE_') {

				if (!$addedBrowse) {
					push @newitems, 'BROWSE_MUSIC';
					$addedBrowse = 1;
				}

			} else {

				push @newitems, $menuItem;
			}
		}

		$client->prefSet('menuItem', \@newitems);
	},

	'6.1b1' => sub {
		my $client = shift;

		if (Slim::Buttons::SqueezeNetwork::clientIsCapable($client)) {
			# append a menu item to connect to squeezenetwork to the home menu
			$client->prefPush('menuItem', 'SQUEEZENETWORK_CONNECT');
		}
	},

	'6.2' => sub {
		my $client = shift;
		#kill all alarm settings
		my $alarm = $client->prefGet('alarm') || 0;
		
		if (ref $alarm ne 'ARRAY') {
			my $alarmTime = $client->prefGet('alarmtime') || 0;
			my $alarmplaylist = $client->prefGet('alarmplaylist') || '';
			my $alarmvolume = $client->prefGet('alarmvolume') || 50;
			$client->prefDelete('alarm');
			$client->prefDelete('alarmtime');
			$client->prefDelete('alarmplaylist');
			$client->prefDelete('alarmvolume');
			$client->prefSet('alarm',[$alarm,0,0,0,0,0,0,0]);
			$client->prefSet('alarmtime',[$alarmTime,0,0,0,0,0,0,0]);
			$client->prefSet('alarmplaylist',[$alarmplaylist,'','','','','','','']);
			$client->prefSet('alarmvolume',[$alarmvolume,50,50,50,50,50,50,50]);
		}
	},

	'R4627' => sub {
		my $client = shift;
		my $menuItem = $client->prefGet('menuItem') || 0;
		
		# Add RandomMix to home and clear unused prefs
		if (ref $menuItem eq 'ARRAY') {

			my $insertPos = undef;
			my $randomMixFound = 0;

			for (my $i = 0; $i < @$menuItem; $i++) {

				if (@$menuItem[$i] eq 'RandomPlay::Plugin') {
					$randomMixFound = 1;
					last;
				} elsif (@$menuItem[$i] eq 'SEARCH') {
					$insertPos = $i + 1;
				}
			}

			if (!$randomMixFound) {

				if (defined $insertPos) {

					# Insert random mix after SEARCH
					splice(@$menuItem, $insertPos, 0, 'RandomPlay::Plugin');
				} else {
					push (@$menuItem, 'RandomPlay::Plugin');
				}

				$client->prefSet('menuItem', $menuItem);
			}

			# Clear old prefs
			$client->prefDelete('plugin_random_exclude_genres');
			Slim::Utils::Prefs::delete('plugin_random_remove_old_tracks');
		}
	},

	'R8775' => sub {
		my $client = shift;
		my $menuItem = $client->prefGet('menuItem') || 0;

		# Add Favorites to home
		if (ref($menuItem) ne 'ARRAY') {
			return;
		}

		my $insertPos = undef;

		# Insert Favorites before SAVED_PLAYLISTS
		for (my $i = 0; $i < @$menuItem; $i++) {

			if (@$menuItem[$i] eq 'FAVORITES') {

				return;

			} elsif (@$menuItem[$i] eq 'SAVED_PLAYLISTS') {

				$insertPos = $i;
			}
		}

		if (defined $insertPos) {

			splice(@$menuItem, $insertPos, 0, 'FAVORITES');

		} else {

			push (@$menuItem, 'FAVORITES');
		}

		$client->prefSet('menuItem', $menuItem);
	},
	
	'R9279' => sub {
		my $client = shift;
		my $menuItem = $client->prefGet('menuItem') || 0;

		# Add Favorites to home
		if (ref($menuItem) ne 'ARRAY') {
			return;
		}
		
		# DigitalInput menu item for Transporter only
		if (blessed($client) ne 'Slim::Player::Transporter') {
			return;
		}

		my $insertPos = undef;

		# Insert DigitalInput before SETTINGS
		for (my $i = 0; $i < @$menuItem; $i++) {

			if (@$menuItem[$i] eq 'DigitalInput::Plugin') {

				return;

			} elsif (@$menuItem[$i] eq 'SETTINGS') {

				$insertPos = $i;
			}
		}

		if (defined $insertPos) {

			splice(@$menuItem, $insertPos, 0, 'DigitalInput::Plugin');

		} else {

			push (@$menuItem, 'DigitalInput::Plugin');
		}

		$client->prefSet('menuItem', $menuItem);
	},
);

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
	Slim::Utils::Prefs::initClientPrefs($client, $defaultPrefs);

	$client->SUPER::init();

	for my $version (sort keys %upgradeScripts) {
		if ($client->prefGet("upgrade-$version-script")) {
			&{$upgradeScripts{$version}}($client);
			$client->prefSet( "upgrade-$version-script", 0);
		}
	}

	Slim::Buttons::Home::updateMenu($client);

	# fire it up!
	$client->power($client->prefGet('power'));
	$client->startup();

	# start the screen saver
	Slim::Buttons::ScreenSaver::screenSaver($client);
	$client->brightness($client->prefGet($client->power() ? 'powerOnBrightness' : 'powerOffBrightness'));
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
	
	my $currOn = $client->prefGet('power') || 0;

	return $currOn unless defined $on;
	return unless (!defined(Slim::Buttons::Common::mode($client)) || ($currOn != $on));

	$client->display->renderCache()->{defaultfont} = undef;

	$client->prefSet( 'power', $on);

	my $resume = Slim::Player::Sync::syncGroupPref($client, 'powerOnResume') || $client->prefGet('powerOnResume');
	$resume =~ /(.*)Off-(.*)On/;
	my ($resumeOff, $resumeOn) = ($1,$2);

	if (!$on) {

		# turning player off - move to off mode and unsync/pause/stop player
		$client->killAnimation();
		$client->brightness($client->prefGet("powerOffBrightness"));

		Slim::Buttons::Common::setMode($client, 'off');

		my $sync = $client->prefGet('syncPower');

		if (defined $sync && $sync == 0) {
			$::d_sync && msg("Temporary Unsync ".$client->id()."\n");
			Slim::Player::Sync::unsync($client,1);
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
		my $powerOnBrightness = $client->prefGet("powerOnBrightness");

		if ($powerOnBrightness < 1) { 
			$powerOnBrightness = 1;
			$client->prefSet("powerOnBrightness", $powerOnBrightness);
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
our %fvolume;  # keep temporary fade volume for each client

sub fade_volume {
	my($client, $fade, $callback, $callbackargs) = @_;

	$::d_ui && msg("entering fade_volume:  fade: $fade to $fvolume{$client}\n");
	
	my $faderate = 20;  # how often do we send updated fade volume commands per second
	
	Slim::Utils::Timers::killTimers($client, \&fade_volume);
	
	my $vol = $client->prefGet("volume");
	my $mute = $client->prefGet("mute");
	
	if ($vol < 0) {
		# correct volume if mute volume is stored
		$vol = -$vol;
	}
	
	if (($fade == 0) ||
		($vol < 0 && $fade < 0)) {
		# the volume is muted or fade is instantaneous, don't fade.
		$callback && (&$callback(@$callbackargs));
		return;
	}

	# on the first pass, set temporary fade volume
	if(!$fvolume{$client} && $fade > 0) {
		# fading up, start volume at 0
		$fvolume{$client} = 0;
	} elsif(!$fvolume{$client}) {
		# fading down, start volume at current volume
		$fvolume{$client} = $vol;
	}

	$fvolume{$client} += $client->maxVolume() * (1/$faderate) / $fade; # fade volume

	if ($fvolume{$client} < 0) { $fvolume{$client} = 0; };
	if ($fvolume{$client} > $vol) { $fvolume{$client} = $vol; };

	$client->volume($fvolume{$client},1); # set volume

	if (($fvolume{$client} == 0 && $fade < 0) || ($fvolume{$client} == $vol && $fade > 0)) {	
		# done fading
		$::d_ui && msg("fade_volume done.  fade: $fade to $fvolume{$client} (vol: $vol)\n");
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

	my $vol = $client->prefGet("volume");
	my $mute = $client->prefGet("mute");
	
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

	$client->prefSet( "volume", $vol);
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

		$parts->{line}[0] = $client->string('NOW_PLAYING');
		$parts->{line}[1] = $client->string('NOTHING');

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

	my $mode = $client->prefGet('playingDisplayModes',$client->prefGet("playingDisplayMode"));

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

	my $featureValue = $client->prefGet($feature);

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
