package Slim::Player::Squeezebox2;

# $Id: Squeezebox2.pm,v 1.10 2005/01/19 01:02:23 vidur Exp $

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

use strict;
use File::Spec::Functions qw(:ALL);
use FindBin qw($Bin);
use IO::Socket;
use Slim::Player::Player;
use Slim::Utils::Misc;
use MIME::Base64;

our @ISA = ("Slim::Player::SqueezeboxG");

our $defaultPrefs = {
	'activeFont'		=> [qw(standard light full)],
	'activeFont_curr'	=> 0,
	'idleFont'		=> [qw(standard light full)],
	'idleFont_curr'		=> 0,
	'idleBrightness'	=> 2,
	'transitionType'		=> 0,
	'transitionDuration'		=> 0,
};

my $VISUALIZER_NONE = 0;
my $VISUALIZER_VUMETER = 1;
my $VISUALIZER_SPECTRUM_ANALYZER = 2;
my $VISUALIZER_WAVEFORM = 3;

# Parameters for the vumeter:
#   0 - Channels: stereo == 0, mono == 1
#   1 - Style: digital == 0, analog == 1
# Left channel parameters:
#   2 - Position in pixels
#   3 - Width in pixels
# Right channel parameters (not required for mono):
#   4-5 - same as left channel parameters

# Parameters for the spectrum analyzer:
#   0 - Channels: stereo == 0, mono == 1
#   1 - Bandwidth: 0..22050Hz == 0, 0..11025Hz == 1
#   2 - Preemphasis in dB per KHz
# Left channel parameters:
#   3 - Position in pixels
#   4 - Width in pixels
#   5 - orientation: left to right == 0, right to left == 1
#   6 - Bar width in pixels
#   7 - Bar spacing in pixels
#   8 - Clipping: show all subbands == 0, clip higher subbands == 1
#   9 - Bar intensity (greyscale): 1-3
#   10 - Bar cap intensity (greyscale): 1-3
# Right channel parameters (not required for mono):
#   11-18 - same as left channel parameters


# sb2 display modes:
#    0 - just text
#    1 - text and progress bar and time
#    2 - text + vu on side
#    3 - text + progress bar + vu
#    4 - text + spectrum analyzer
#    5 - text + full screen spectrum analyser
#    6 - text + indicator

my @showBar =         (  0,   1,   0,   0,   0,   1,  1 );
my @showTime =        (  0,   1,   0,   1,   1,   1,  0 );
my @showFullness =    (  0,   0,   0,   0,   0,   0,  1 );
my @displayWidth = 	  (  320, 320, 278, 278, 278, 320, 320  );

my @visualizer =   	  (  	$VISUALIZER_NONE,
				$VISUALIZER_NONE,
				$VISUALIZER_VUMETER,   
				$VISUALIZER_VUMETER,   
				$VISUALIZER_SPECTRUM_ANALYZER,   
				$VISUALIZER_SPECTRUM_ANALYZER,   
				$VISUALIZER_NONE);

my @visualizerParameters = ( 	[],
				[], 
				[0, 0, 280, 18, 302, 18], 
				[0, 0, 280, 18, 302, 18], 
				[1, 1, 0x10000, 280, 40, 0, 4, 1, 0, 1, 3], 
				[0, 0, 0x10000, 0, 160, 0, 4, 1, 1, 1, 1, 160, 160, 1, 4, 1, 1, 1, 1],
				[],
);

sub new {
	my $class = shift;

	my $client = $class->SUPER::new(@_);

	bless $client, $class;

	return $client;
}

sub vfdmodel {
	return 'graphic-320x32';
}

sub init {
	my $client = shift;
	# make sure any preferences unique to this client may not have set are set to the default
	Slim::Utils::Prefs::initClientPrefs($client,$defaultPrefs);
	$client->SUPER::init();
}

sub nowPlayingModes {
	my $client = shift;
	my $count = scalar(@showBar);
	$count += Slim::Utils::Prefs::clientGet($client,'showbufferfullness') ? 1 : 0;
	return $count;
}

sub displayWidth {
	my $client = shift;
	my $mode = Slim::Utils::Prefs::clientGet($client, "playingDisplayMode") || 0;
	return $displayWidth[$mode];
}

sub bytesPerColumn {
	return 4;
}

sub displayHeight {
	return 32;
}

sub model {
	return 'squeezebox2';
};

# only refresh if we're in a screen that needs it  (this knowledge needs to be moved to the mode...)
sub refresh {
	my $client = shift;
	if (Slim::Buttons::Playlist::showingNowPlaying($client) || !$client->power()) {
		$client->update();
	}
}


# in order of preference based on whether we're connected via wired or wireless...
sub formats {
	my $client = shift;
	
	return ('flc','aif','wav','mp3');
}

sub volume {
	my $client = shift;
	my $newvolume = shift;

	my $volume = $client->Slim::Player::Client::volume($newvolume, @_);
	if (defined($newvolume)) {
		my ($right_level, $left_level);
	    	$right_level = $left_level = int(0x80 * (($volume / $client->maxVolume) ** 2));
		my $data = pack('NN', $left_level, $right_level);
		$client->sendFrame('audg', \$data);
	}
	return $volume;
}

sub drawFrameBuf {
	my $client = shift;
	my $framebufref = shift;
	my $parts = shift;
	my $transition = shift || 'c';
	my $param = shift || pack('c', 0);
	
	if ($client->opened()) {
	
	my $framebuf = pack('n', 0) .   # offset of zero
		               $transition . # transition
		               $param . # transition parameter
		               substr($$framebufref, 0, $client->displayWidth() * $client->bytesPerColumn()); # truncate if necessary

	$client->sendFrame('grfe', \$framebuf);
	}
}	

# preformed frame header for fast scolling - contains header added by sendFrame and drawFrameBuf
sub scrollHeader {
	my $client = shift;
	my $header = 'grfe' . pack('n', 0) . 'c' . pack ('c', 0);

	return pack('n', length($header) + $client->screenBytes ) . $header;
}

# set the visualizer and update the player.  If blank, just update the player with the current mode setting.
sub visualizer {
	my $client = shift;
	my $visu = shift;
	if (!defined($visu)) {
		$visu = Slim::Utils::Prefs::clientGet($client, "playingDisplayMode");
		$visu = 0 if (!$client->power());
	}
	
	if ($visu < 0) { 
	    $visu = 0; 
	}
	my $nmodes = $client->nowPlayingModes();
	if ($visu >= $nmodes) { 
	    $visu = $nmodes - 1;
	}

	my $params = pack "CC", $visualizer[$visu], scalar(@{$visualizerParameters[$visu]});
	for my $param (@{$visualizerParameters[$visu]}) {
		$params .= pack "N", $param;
	}
	$client->sendFrame('visu', \$params);
}

# push the old screen off the left side
sub pushLeft {
	my $client = shift;
	my $start = shift;
	my $end = shift;
	$client->killAnimation();
	$client->animating(1);
	$client->drawFrameBuf($client->render($end), undef, 'r', 0);
}

# push the old screen off the right side
sub pushRight {
	my $client = shift;
	my $start = shift;
	my $end = shift;

	$client->killAnimation();	
	$client->animating(1);
	$client->drawFrameBuf($client->render($end), undef, 'l', 0);
}

# bump left against the edge
sub bumpLeft {
	my $client = shift;
	my $startbits = $client->render(Slim::Display::Display::curLines($client));
	
	$client->killAnimation();	
	$client->animating(1);
	$client->drawFrameBuf($startbits, undef, 'L', 0);
}

# bump right against the edge
sub bumpRight {
	my $client = shift;
	my $startbits = $client->render(Slim::Display::Display::curLines($client));
	
	$client->killAnimation();	
	$client->animating(1);
	$client->drawFrameBuf($startbits, undef, 'R', 0);
}

# bump left against the edge
sub bumpUp {
	my $client = shift;
	my $startbits = $client->render(Slim::Display::Display::curLines($client));
	
	$client->killAnimation();	
	$client->animating(1);
	$client->drawFrameBuf($startbits, undef, 'U', 0);
}

# bump right against the edge
sub bumpDown {
	my $client = shift;
	my $startbits = $client->render(Slim::Display::Display::curLines($client));

	$client->killAnimation();	
	$client->animating(1);
	$client->drawFrameBuf($startbits, undef, 'D', 0);
}

sub brightness {
	my $client = shift;
	my $delta = shift;
	
	my $brightness = $client->Slim::Player::Player::brightness($delta, 1);
		
	if (defined($delta)) {
		my $brightnesscode = pack('n', $brightness);
		$client->sendFrame('grfb', \$brightnesscode); 
	}
	
	return $brightness;
}

sub maxBrightness {
	return 4;
}

sub upgradeFirmware {
	my $client = shift;

	my $to_version;

	$to_version = $client->needsUpgrade();

	if (!$to_version) {
		$to_version = $client->revision;
		msg ("upgrading to same rev: $to_version\n");
	}

	my $filename = catdir($Bin, "Firmware", $client->model . "_$to_version.bin");

	if (!-f$filename) {
		warn("file does not exist: $filename\n");
		return(0);
	}
	
	Slim::Control::Command::execute($client, ["stop"]);

	my $err;
	$::d_firmware && msg("using new update mechanism: $filename\n");
	$err = $client->upgradeFirmware_SDK5($filename);

	if (defined($err)) {
		msg("upgrade failed: $err");
	} else {
		$client->forgetClient();
	}
}

sub nowPlayingModeLines {
	my ($client, $parts) = @_;
	my $overlay;
	my $fractioncomplete   = 0;
	my $playingDisplayMode = Slim::Utils::Prefs::clientGet($client, "playingDisplayMode");
	my $songtime = '';
	
	Slim::Buttons::Common::param(
		$client,
		'animateTop',
		(Slim::Player::Source::playmode($client) ne "stop") ? $playingDisplayMode : 0
	);

	unless (defined $playingDisplayMode) {
		$playingDisplayMode = 1;
	};

	my $showBar = $showBar[$playingDisplayMode];
	my $showTime = $showTime[$playingDisplayMode];
	my $showFullness = $showFullness[$playingDisplayMode];
	
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
		$songtime = ' ' . $client->textSongTime();
	}

	if ($showTime || $showFullness) {
		$overlay = $songtime;
	}
	
	if ($showBar) {
		# show both the bar and the time
		my $leftLength = $client->measureText($parts->{line1}, 1);
		my $barlen = $client->displayWidth() - $leftLength - $client->measureText($overlay, 1);
		my $bar    = $client->symbols($client->progressBar($barlen, $fractioncomplete));

		$overlay = $bar . $songtime;
	}
	
	$parts->{overlay1} = $overlay if defined($overlay);
	
}

sub maxTransitionDuration {
	return 8;
}

sub reportsTrackStart {
	return 1;
}

sub power {
	my $client = shift;
	my $on = shift;
	
	if (defined($on) && !$on) {
		$client->visualizer(0);
	} 
	my $pow = $client->SUPER::power($on);

	if ($on) {		
		$client->visualizer();
	}
	return $pow;
}

sub reconnect {
	my $client = shift;
	$client->SUPER::reconnect(@_);
	$client->visualizer();
}

sub requestStatus {
	shift->sendFrame('stat');
}

1;
