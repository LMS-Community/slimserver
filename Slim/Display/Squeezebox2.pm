package Slim::Display::Squeezebox2;

# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.


=head1 NAME

Slim::Display::Squeezebox2

=head1 DESCRIPTION

L<Slim::Display::Squeezebox2>
 Display class for Squeezebox 2/3 class display
  - 320 x 32 pixel display
  - client side animations

=cut

use strict;

use base qw(Slim::Display::Graphics);

use Slim::Utils::Prefs;

# ANIC flags
use constant ANIM_TRANSITION  => 0x01; # A transition animation has finished
use constant ANIM_SCROLL_ONCE => 0x02; # A scrollonce has finished
use constant ANIM_SCREEN_1    => 0x04; # For scrollonce only, screen 1 was scrolling
use constant ANIM_SCREEN_2    => 0x08; # For scrollonce only, screen 2 was scrolling

my $prefs = preferences('server');

# constants
my $display_maxLine = 2; # render up to 3 lines [0..$display_maxLine]

# Mode definitions - including visualizer

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

my $VISUALIZER_NONE = 0;
my $VISUALIZER_VUMETER = 1;
my $VISUALIZER_SPECTRUM_ANALYZER = 2;
my $VISUALIZER_WAVEFORM = 3;

my @modes = (
	# mode 0
	{ desc => ['BLANK'],
	  bar => 0, secs => 0,  width => 320, 
	  params => [$VISUALIZER_NONE] },
	# mode 1
	{ desc => ['ELAPSED'],
	  bar => 1, secs => 1,  width => 320,
	  params => [$VISUALIZER_NONE] },
	# mode 2
	{ desc => ['REMAINING'],
	  bar => 1, secs => -1, width => 320,
	  params => [$VISUALIZER_NONE] },
	# mode 3
	{ desc => ['VISUALIZER_VUMETER_SMALL'],
	  bar => 0, secs => 0,  width => 278,
	  params => [$VISUALIZER_VUMETER, 0, 0, 280, 18, 302, 18] },
	# mode 4
	{ desc => ['VISUALIZER_VUMETER_SMALL', 'AND', 'ELAPSED'],
	  bar => 1, secs => 1,  width => 278,
	  params => [$VISUALIZER_VUMETER, 0, 0, 280, 18, 302, 18] },
	# mode 5
	{ desc => ['VISUALIZER_VUMETER_SMALL', 'AND', 'REMAINING'],
	  bar => 1, secs => -1, width => 278, 
	  params => [$VISUALIZER_VUMETER, 0, 0, 280, 18, 302, 18] } , 
	# mode 6 
	{ desc => ['VISUALIZER_SPECTRUM_ANALYZER_SMALL'],
	  bar => 0, secs => 0,  width => 278, 
	  params => [$VISUALIZER_SPECTRUM_ANALYZER, 1, 1, 0x10000, 280, 40, 0, 4, 1, 0, 1, 3] },
	# mode 7
	{ desc => ['VISUALIZER_SPECTRUM_ANALYZER_SMALL', 'AND', 'ELAPSED'],
	  bar => 1, secs => 1,  width => 278,
	  params => [$VISUALIZER_SPECTRUM_ANALYZER, 1, 1, 0x10000, 280, 40, 0, 4, 1, 0, 1, 3] },
	# mode 8
	{ desc => ['VISUALIZER_SPECTRUM_ANALYZER_SMALL', 'AND', 'REMAINING'],
	  bar => 1, secs => -1, width => 278,
	  params => [$VISUALIZER_SPECTRUM_ANALYZER, 1, 1, 0x10000, 280, 40, 0, 4, 1, 0, 1, 3] },
	# mode 9  
	{ desc => ['VISUALIZER_SPECTRUM_ANALYZER'],
	  bar => 0, secs => 0,  width => 320, 
	  params => [$VISUALIZER_SPECTRUM_ANALYZER, 0, 0, 0x10000, 0, 160, 0, 4, 1, 1, 1, 1, 160, 160, 1, 4, 1, 1, 1, 1] },
	# mode 10
	{ desc => ['VISUALIZER_SPECTRUM_ANALYZER', 'AND', 'ELAPSED'],
	  bar => 1, secs => 1,  width => 320,
	  params => [$VISUALIZER_SPECTRUM_ANALYZER, 0, 0, 0x10000, 0, 160, 0, 4, 1, 1, 1, 1, 160, 160, 1, 4, 1, 1, 1, 1] },
	# mode 11
	{ desc => ['VISUALIZER_SPECTRUM_ANALYZER', 'AND', 'REMAINING'],
	  bar => 1, secs => -1, width => 320,
	  params => [$VISUALIZER_SPECTRUM_ANALYZER, 0, 0, 0x10000, 0, 160, 0, 4, 1, 1, 1, 1, 160, 160, 1, 4, 1, 1, 1, 1] } , 
	# mode 12	  
	{ desc => ['SETUP_SHOWBUFFERFULLNESS'],
	  bar => 1, secs => 0,  width => 320, fullness => 1,
	  params => [$VISUALIZER_NONE], },
	# mode 13
	{ desc => ['CLOCK'],
	  bar => 0, secs => 0, width => 320, clock => 1,
	  params => [$VISUALIZER_NONE] },
);

our $defaultPrefs = {
	'playingDisplayMode'  => 5,
	'playingDisplayModes' => [0..11]
};

our $defaultFontPrefs = {
	'activeFont'          => [qw(light standard full)],
	'activeFont_curr'     => 1,
	'idleFont'            => [qw(light standard full)],
	'idleFont_curr'       => 1,
};

sub init {
	my $display = shift;

	# load fonts for this display if not already loaded and remember to load at startup in future
	if (!$prefs->get('loadFontsSqueezebox2')) {
		$prefs->set('loadFontsSqueezebox2', 1);
		Slim::Display::Lib::Fonts::loadFonts(1);
	}

	$display->SUPER::init();

	$display->validateFonts($defaultFontPrefs);
}

sub initPrefs {
	my $display = shift;

	$prefs->client($display->client)->init($defaultPrefs);
	$prefs->client($display->client)->init($defaultFontPrefs);

	$display->SUPER::initPrefs();
}

sub resetDisplay {
	my $display = shift;

	my $cache = $display->renderCache();
	$cache->{'defaultfont'} = undef;
	$cache->{'screens'} = 1;
	$cache->{'maxLine'} = $display_maxLine;
	$cache->{'screen1'} = { 'ssize' => 0, 'fonts' => {} };

	$display->killAnimation();
}	

sub periodicScreenRefresh {} # noop for this player

sub bytesPerColumn {
	return 4;
}

sub displayHeight {
	return 32;
}

sub displayWidth {
	my $display = shift;
	my $client = $display->client;

	# if we're showing the always-on visualizer & the current buttonmode 
	# hasn't overridden, then use the playing display mode to index
	# into the display width, otherwise, it's fullscreen.
	my $mode = 0;
	
	if ( $display->showVisualizer() && !defined($client->modeParam('visu')) ) {
		my $cprefs = $prefs->client($client);
		$mode = $cprefs->get('playingDisplayModes')->[ $cprefs->get('playingDisplayMode') ];
	}

	return $display->widthOverride || $display->modes->[$mode || 0]{width};
}

sub vfdmodel {
	return 'graphic-320x32';
}

sub brightnessMap {
	return (65535, 0, 1, 3, 4);
}

sub graphicCommand {
	return 'grfe';
}

# update screen - supressing unchanged screens
sub updateScreen {
	my $display = shift;
	my $screen = shift;
	if ($screen->{changed}) {
	    $display->drawFrameBuf($screen->{bitsref});
	} else {
	    # check to see if visualiser has changed even if screen display has not
		$display->visualizer();
	}
}

# send display frame to player
sub drawFrameBuf {
	my $display = shift;
	my $framebufref = shift;
	my $offset = shift || 0;
	my $transition = shift || 'c';
	my $param = shift || 0;

	my $client = $display->client;

	if ($client->opened()) {

		$display->visualizer();

		my $framebuf = pack('n', $offset) .    # offset [transporter screen 2 = offset of 640]
						   $transition .       # transition
						   pack('c', $param) . # param byte
						   $$framebufref;
	
		$client->sendFrame('grfe', \$framebuf);
	}
}	

sub showVisualizer {
	my $client = shift->client;
	
	# show the always-on visualizer while browsing or when playing.
	return (Slim::Player::Source::playmode($client) eq 'play') || (Slim::Buttons::Playlist::showingNowPlaying($client));
}

sub visualizer {
	my $display   = shift;
	my $forceSend = shift || 0;
	my $client    = $display->client;

	my $paramsref = $client->modeParam('visu');

	if ($display->hideVisu && ( ($display->hideVisu == 1 && $client->modeParam('hidevisu')) || $display->hideVisu == 2) ) {
		$paramsref = [0]; # hide all visualisers
	}

	if (!$paramsref) {
		$paramsref = $display->visualizerParams()
	}

	if (!$forceSend && defined($paramsref) && defined($display->lastVisMode) && $paramsref == $display->lastVisMode) {
		return;
	}

	my @params = @{$paramsref};

	my $which = shift @params;
	my $count = scalar(@params);

	my $parambytes = pack "CC", $which, $count;

	for my $param (@params) {
		$parambytes .= pack "N", $param;
	}

	$client->sendFrame('visu', \$parambytes);
	$display->lastVisMode($paramsref);
}

sub visualizerParams {
	my $display = shift;
	my $client = $display->client;

	my $cprefs = $prefs->client($client);

	my $visu = $cprefs->get('playingDisplayModes')->[ $cprefs->get('playingDisplayMode') ];
	
	$visu = 0 if (!$display->showVisualizer());
	
	if (!defined $visu || $visu < 0) { 
		$visu = 0; 
	}
	
	if ($visu > $display->nmodes) {
		$visu = $display->nmodes;
	}

	return $display->modes()->[$visu]{params};
}

sub modes {
	return \@modes;
}

sub nmodes {
	return $#modes;
}

# update visualizer and init scrolling
sub scrollInit {
    my $display = shift;
	$display->visualizer();
    $display->SUPER::scrollInit(@_);
}

# update visualiser and scroll background - suppressing unchanged backgrounds
sub scrollUpdateBackground {
    my $display = shift;
    my $screen = shift;
	my $screenNo = shift;
	$display->visualizer();
    $display->SUPER::scrollUpdateBackground($screen, $screenNo) if $screen->{changed};
}

# preformed frame header for fast scolling - contains header added by drawFrameBuf
sub scrollHeader {
	return pack('n', 0) . 'c' . pack ('c', 0);
}

sub pushLeft {
	my $display = shift;
	my $start = shift;
	my $end = shift || $display->curLines({ trans => 'pushLeft' });

	my $render = $display->render($end);
	$display->pushBumpAnimate($render, 'r');
}

sub pushRight {
	my $display = shift;
	my $start = shift;
	my $end = shift || $display->curLines({ trans => 'pushRight' });

	my $render = $display->render($end);
	$display->pushBumpAnimate($render, 'l');
}

sub pushUp {
	my $display = shift;
	my $start = shift;
	my $end = shift || $display->curLines({ trans => 'pushUp' });

	my $render = $display->render($end);
	$display->pushBumpAnimate($render, 'u', $render->{screen1}->{extent});
}

sub pushDown {
	my $display = shift;
	my $start = shift;
	my $end = shift || $display->curLines({ trans => 'pushDown' });

	my $render = $display->render($end);
	$display->pushBumpAnimate($render, 'd', $render->{screen1}->{extent});
}

sub bumpLeft {
	my $display = shift;
	$display->pushBumpAnimate($display->render($display->renderCache()), 'L');
}

sub bumpRight {
	my $display = shift;
	$display->pushBumpAnimate($display->render($display->renderCache()), 'R');
}

sub bumpDown {
	my $display = shift;
	my $render = $display->render($display->renderCache());
	$display->pushBumpAnimate($render, 'U', $render->{screen1}->{extent});
}

sub bumpUp {
	my $display = shift;
	my $render = $display->render($display->renderCache());
	$display->pushBumpAnimate($render, 'D', $render->{screen1}->{extent});
}

sub pushBumpAnimate {
	my $display = shift;
	my $render = shift;
	my $trans = shift;
	my $param = shift || 0;

	$display->killAnimation();
	$display->animateState(1);
	$display->updateMode(1);

	$display->drawFrameBuf($render->{screen1}->{bitsref}, 0, $trans, $param);

	# notify cli/jive of animation - if there is a subscriber this will grab the curDisplay
	if ($display->notifyLevel == 2) {
		$display->notify("animate-$trans");
	}
}

sub clientAnimationComplete {
	# Called when client sends ANIC frame
	my $display = shift;
	my $data_ref = shift;
	my $flags = unpack 'c', $$data_ref;
	# for players with client side scrolling, flags are:
	# ANIM_TRANSITION (0x01) - transition animation has finished (previous use of ANIC)
	# ANIM_SCREEN_1 (0x04)                           - end of first scroll on screen 1
	# ANIM_SCREEN_2 (0x08)                           - end of first scroll on screen 2
	# ANIM_SCROLL_ONCE (0x02) | ANIM_SCREEN_1 (0x04) - end of scroll once on screen 1
	# ANIM_SCROLL_ONCE (0x02) | ANIM_SCREEN_2 (0x08) - end of scroll once on screen 2
	
	if (!$display->client->hasScrolling || $flags & ANIM_TRANSITION) {
		# end of transition ANIC
		$display->updateMode(0);

		# process any defered showBriefly
		if ($display->animateState == 7) {
			$display->showBriefly($display->sbDeferred->{parts}, $display->sbDeferred->{args});
			return;
		}

		# Ensure scrolling is started by setting a timer to call update in 1.0 seconds
		$display->animateState(2);
		Slim::Utils::Timers::setTimer($display, Time::HiRes::time() + 1.0, \&Slim::Display::Display::update);
	}

	# process end of scroll once ANIC (from clients with native scrolling)
	elsif ($flags & (ANIM_SCREEN_1 | ANIM_SCREEN_2)) {
		my $scroll = $display->scrollData(($flags & ANIM_SCREEN_1) ? 1 : 2);
		if ($scroll) {
			$scroll->{inhibitsaver} = 0;
			if (($flags & ANIM_SCROLL_ONCE) && $scroll->{scrollonceend}) {
				# schedule endAnimaton to kill off scrolling and display new screen
				$display->animateState(6) unless ($display->animateState() == 5);
				my $end = ($scroll->{pauseInt} > 0.5) ? $scroll->{pauseInt} : 0.5;
				Slim::Utils::Timers::setTimer($display, Time::HiRes::time() + $end, \&Slim::Display::Display::endAnimation);
			}
		}
	}
}

sub killAnimation {
	# kill all server side animation in progress and clear state
	my $display = shift;
	my $exceptScroll = shift; # all but scrolling to be killed
	my $screenNo = shift || 1;  

	my $animate = $display->animateState();
	Slim::Utils::Timers::killTimers($display, \&Slim::Display::Display::update) if ($animate == 2);
	Slim::Utils::Timers::killTimers($display, \&Slim::Display::Display::endAnimation) if ($animate >= 4);	
	$display->scrollStop($screenNo) if (($display->scrollState($screenNo) > 0) && !$exceptScroll);
	$display->animateState(0);
	$display->updateMode(0);
	$display->screen2updateOK(0);
	$display->endShowBriefly() if ($animate == 5);
}

=head1 SEE ALSO

L<Slim::Display::Graphics>

=cut

1;
