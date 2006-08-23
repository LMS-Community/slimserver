package Slim::Display::Transporter;

# SlimServer Copyright (c) 2001-2006 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

# $Id$

# Display class for Transporter display
#  - 2 screens
#  - 320 x 32 pixel displays 
#  - client side animations

use strict;

use base qw(Slim::Display::Squeezebox2);

# constants
my $display_maxLine = 2; # render up to 3 lines [0..$display_maxLine]

our $defaultPrefs = {
	'activeFont'          => [qw(light standard full)],
	'activeFont_curr'     => 1,
	'idleFont'            => [qw(light standard full)],
	'idleFont_curr'       => 1,
	'idleBrightness'      => 2,
	'playingDisplayMode'  => 0,
	'playingDisplayModes' => [0..5],
	'visualMode'          => 0,
	'visualModes'         => [0..5],
};

# Display modes for Transporter:
#    0 - just text
#    1 - text and progress bar
#    2 - text and progress bar and time
#    3 - text and progress bar and time remaining
#    4 - text and time
#    5 - text and time remaining

my @modes = (
	# mode 0
	{ desc => ['BLANK'],
	  bar => 0, secs => 0, 	width => 320 }, 
	# mode 1
	{ desc => ['PROGRESS_BAR'],
	  bar => 1, secs => 0,  width => 320 },
	# mode 2
	{ desc => ['PROGRESS_BAR', 'AND', 'ELAPSED'],
	  bar => 1, secs => 1,  width => 320 },
	# mode 3
	{ desc => ['PROGRESS_BAR', 'AND', 'REMAINING'],
	  bar => 1, secs => -1, width => 320 },
	# mode 4
	{ desc => ['ELAPSED'], 
	  bar => 0, secs => 1,  width => 320 },
	# mode 5
	{ desc => ['REMAINING'],
	  bar => 0, secs => -1, width => 320 },
	# mode 6
	{ desc => ['SETUP_SHOWBUFFERFULLNESS'],
	  bar => 1, secs => 0,  width => 320, fullness => 1 },
);

my $nmodes = $#modes;

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

use constant VISUALIZER_NONE => 0;
use constant VISUALIZER_VUMETER => 1;
use constant VISUALIZER_SPECTRUM_ANALYZER => 2;
use constant VISUALIZER_WAVEFORM => 3;

my @visualizers = (
	{ desc => ['BLANK'],
	  params => [VISUALIZER_NONE],
    },
	{ desc => ['VISUALIZER_EXTENDED_TEXT'],
	  text => 1,
	  params => [VISUALIZER_NONE],
    },
	{ desc => ['VISUALIZER_ANALOG_VUMETER'],
	  params => [VISUALIZER_VUMETER, 0, 1, 0 + 320, 160, 160 + 320, 160],
    },
	{ desc => ['VISUALIZER_DIGITAL_VUMETER'],
	  params => [VISUALIZER_VUMETER, 0, 0, 20 + 320, 130, 170 + 320, 130],
    },
	{ desc => ['VISUALIZER_SPECTRUM_ANALYZER'],
	  params => [VISUALIZER_SPECTRUM_ANALYZER, 0, 0, 0x10000, 0 + 320, 160, 0, 4, 1, 1, 1, 3, 160 + 320, 160, 1, 4, 1, 1, 1, 3],
    },
	{ desc => ['VISUALIZER_SPECTRUM_ANALYZER', 'AND', 'VISUALIZER_EXTENDED_TEXT'],
	  text => 1,
	  params => [VISUALIZER_SPECTRUM_ANALYZER, 0, 0, 0x10000, 0 + 320, 160, 0, 4, 1, 1, 1, 1, 160 + 320, 160, 1, 4, 1, 1, 1, 1],
    },
);

my $nvisualizers = $#visualizers;

sub modes {
	return \@modes;
}

sub nmodes {
	return $nmodes;
}

sub visualizerModes {
	return \@visualizers;
}

sub visualizerNModes {
	return $nvisualizers;
}

sub hasScreen2 { 1 }

sub init {
	my $display = shift;
	my $client = $display->client;
	Slim::Utils::Prefs::initClientPrefs($client, $defaultPrefs);
	$display->SUPER::init();

	# register default handler for periodic screen2 updates on visual screen
	$client->lines2periodic(\&Slim::Player::Player::currentSongLines);
}

sub resetDisplay {
	my $display = shift;

	my $cache = $display->renderCache();
	$cache->{'screens'} = 2;
	$cache->{'maxLine'} = $display_maxLine;
	$cache->{'screen1'} = { 'ssize' => 0, 'fonts' => {} };
	$cache->{'screen2'} = { 'ssize' => 0, 'fonts' => {} };

	$display->killAnimation(undef, 1);
	$display->killAnimation(undef, 2);
}	

sub bytesPerColumn {
	return 4;
}

sub displayHeight {
	return 32;
}

sub displayWidth {
	return 320;
}

sub vfdmodel {
	return 'graphic-320x32';
}

sub updateScreen {
	my $display = shift;
	my $screen = shift;
	my $screenNo = shift;

	if ($screenNo == 1 && $screen->{changed}) {
		$display->drawFrameBuf($screen->{bitsref}, 0);

	} elsif ($screenNo == 2 && $screen->{changed}) {
		$display->drawFrameBuf($screen->{bitsref}, 640);

	} else {
	    # check to see if visualiser has changed even if screen display has not
	    $display->visualizer();
	}
}

sub scrollHeader {
	my $display = shift;
	my $screenNo = shift;

	my $offset = ($screenNo && $screenNo == 2) ? 640 : 0;
	my $header = 'grfe' . pack('n', $offset) . 'c' . pack ('c', 0);

	return pack('n', length($header) + $display->screenBytes ) . $header;
}

sub pushUp {
	my $display = shift;
	my $start = shift;
	my $end = shift || $display->curLines();

	my $render = $display->render($end);
	$display->pushBumpAnimate($render, 'u', $render->{screen1}->{extent}, $render->{screen2}->{extent});
}

sub pushDown {
	my $display = shift;
	my $start = shift;
	my $end = shift || $display->curLines();

	my $render = $display->render($end);
	$display->pushBumpAnimate($render, 'd', $render->{screen1}->{extent}, $render->{screen2}->{extent});
}

sub pushBumpAnimate {
	my $display = shift;
	my $render = shift;
	my $trans = shift;
	my $param1 = shift || 0;
	my $param2 = shift || 0;

	if ($render->{screen1}->{changed} && $render->{screen2}->{changed}) {
		# animate both screens
		my $twoScreen = ${$render->{screen1}->{bitsref}} . ${$render->{screen2}->{bitsref}};
		$display->killAnimation(undef, 1);
		$display->killAnimation(undef, 2);
		$display->drawFrameBuf(\$twoScreen, 0, $trans, $param1);

	} elsif ($render->{screen2}->{changed}) {
		# animate screen 2 only
		$display->killAnimation(undef, 2);
		$display->drawFrameBuf($render->{screen2}->{bitsref}, 640, $trans, $param2);

	} else {
		# animate screen 1 only
		$display->killAnimation(undef, 1);
		$display->drawFrameBuf($render->{screen1}->{bitsref}, 0, $trans, $param1);
	}

	$display->animateState(1);
	$display->updateMode(1);
}

sub visualizerParams {
	my $display = shift;
	my $client = $display->client;

	my $visu = $client->prefGet('visualModes', $client->prefGet('visualMode')) || 0;
	
	$visu = 0 if (!$display->showVisualizer());
	
	return $visualizers[$visu]{params};
}

sub visualizer {
	my $display = shift;
	my $forceSend = shift;

	$display->SUPER::visualizer($forceSend);	
}

sub showVisualizer {
	my $display = shift;

	return $display->client->power();
}

sub showExtendedText {
	my $display = shift;
	my $client = $display->client;

	return 1 if ($client->param('visu'));
	return 0 if (!$client->power());

	my $visu = $client->prefGet('visualModes', $client->prefGet('visualMode')) || 0;
	
	return $visualizers[$visu]{text};
}

1;

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:


