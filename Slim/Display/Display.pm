package Slim::Display::Display;

# $Id$

# SlimServer Copyright (c) 2001-2006 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

=head1 NAME

Slim::Display::Display

=head1 DESCRIPTION

L<Slim::Display::Display>
 Base for display class - contains display functions common to all display types

=cut

use strict;

use Slim::Utils::Misc;
use Slim::Utils::Timers;

# Display routines use the following state variables: 
#   $display->updateMode(), $display->screen2updateOK(), $display->animateState(), $display->scrollState()
#
# updateMode: (single value for all screens)
#   0 = normal
#   1 = periodic updates are blocked
#   2 = all updates are blocked
#
# screen2updateOK: single value for second screen to allow periodic update to screen 2 while updateMode set
#   0 = use status of updateMode
#   1 = allow periodic updates of screen2 to bypass updateMode check [animation or showBriefly on screen 1 only]
#
# animateState: (single value for all screens)         Slimp3/SB1      SB1G      SB2/3/Transporter   
#   0 = no animation                                        x             x        x
#   1 = client side push/bump animations                                           x
#   2 = update scheduled (timer set to callback update)                            x   
#   3 = server side push & bumpLeft/Right                   x             x
#   4 = server side bumpUp/Down                             x             x 
#   5 = server side showBriefly                             x             x        x
#   6 = clear scrolling (scrollonce and end scrolling mode) x             x        x
#
# scrollState: (per screen)
#   0 = no scrolling
#   1 = server side normal scrolling
#   2 = server side ticker mode
#  3+ = <reserved for client side scrolling>

our $defaultPrefs = {
	'autobrightness'       => 1,
	'idleBrightness'       => 1,
	'scrollMode'           => 0,
	'scrollPause'          => 3.6,
	'scrollPauseDouble'    => 3.6,
	'scrollRate'           => 0.15,
	'scrollRateDouble'     => 0.1,
};


# create base class - always called via a class which inherits from this one
sub new {
	my $class = shift;
	my $client = shift;
	
	my $display =[];	
	bless $display, $class;

	$display->[0] = \$client; # ref to client
	$display->[1] = 0;        # updateMode [0 = normal, 1 = periodic update blocked, 2 = all updates blocked]
	$display->[2] = 0;        # animateState
	$display->[3] = [0, 0, 0];# scrollState - element 1 = screen1
	$display->[4] = {};       # renderCache
	$display->[5] = [];       # scrollData - element 1 = screen1
	$display->[6] = 1;        # currBrightness
	$display->[7] = undef;    # lastVisMode
	$display->[8] = undef;    # sbCallbackData
	$display->[9] = undef;    # sbOldDisplay
	$display->[10]= undef;    # sbName
	$display->[11]= 0;        # screen2updateOK

	$display->resetDisplay(); # init render cache

	return $display;
}

sub init {
	my $display = shift;
	Slim::Utils::Prefs::initClientPrefs($display->client, $defaultPrefs);
}

# Methods to access display state
sub client {
	return ${shift->[0]};
}
sub updateMode {
	my $r = shift;
	@_ ? ($r->[1] = shift) : $r->[1];
}
sub animateState {
	my $r = shift;
	@_ ? ($r->[2] = shift) : $r->[2];
}    
sub scrollState {
	my $r = shift;
	my $s = shift || 1;
	@_ ? ($r->[3][$s] = shift) : $r->[3][$s];
}    
sub renderCache {
	my $r = shift;
	@_ ? ($r->[4] = shift) : $r->[4];
}    
sub scrollData {
	my $r = shift;
	my $s = shift || 1;
	@_ ? ($r->[5][$s] = shift) : $r->[5][$s];
}    
sub currBrightness {
	my $r = shift;
	@_ ? ($r->[6] = shift) : $r->[6];
}    
sub lastVisMode {
	my $r = shift;
	@_ ? ($r->[7] = shift) : $r->[7];
}    
sub sbCallbackData {
	my $r = shift;
	@_ ? ($r->[8] = shift) : $r->[8];
}
sub sbOldDisplay {
	my $r = shift;
	@_ ? ($r->[9] = shift) : $r->[9];
}
sub sbName {
	my $r = shift;
	@_ ? ($r->[10] = shift) : $r->[10];
}
sub screen2updateOK {
	my $r = shift;
	@_ ? ($r->[11] = shift) : $r->[11];
}

################################################################################################

# main display function - all screen updates [other than push/bumps] are driven by this function
sub update {
	my $display = shift;
	my $lines   = shift;
	my $scrollMode = shift;	# 0 = normal scroll, 1 = scroll once only, 2 = no scroll, 3 = scroll once and end
	my $s2periodic = shift; # flag to indicate called by peridic update for screen 2 [to bypass some state checks]
	my $client  = $display->client;

	my $parts;
	if (defined($lines)) {
		$parts = $display->parseLines($lines);
	} else {
		my $linefunc = $client->lines();
		$parts = $display->parseLines(&$linefunc($client));
	}

	unless ($s2periodic && $display->screen2updateOK) {

		# return if updates are blocked
		return if ($display->updateMode() == 2);

		# clear any server side animations or pending updates, don't kill scrolling
		$display->killAnimation(1) if ($display->animateState() > 0);

	} elsif ($display->sbOldDisplay()) {

		# replace any stored screen 2 for show briefly
		$display->sbOldDisplay()->{'screen2'} = $parts->{'screen2'};

	}

	if (!defined $scrollMode) {
		$scrollMode = $client->paramOrPref('scrollMode') || 0;
	}

	my ($scroll, $scrollonce);
	if    ($scrollMode == 0) { $scroll = 1; $scrollonce = 0; }
	elsif ($scrollMode == 1) { $scroll = 1; $scrollonce = 1; }
	elsif ($scrollMode == 2) { $scroll = 0; $scrollonce = 0; }
	elsif ($scrollMode == 3) { $scroll = 2; $scrollonce = 2; }

	my $render = $display->render($parts, $scroll, $s2periodic);

	foreach my $screenNo (1..$render->{screens}) {
		
		my $state = $display->scrollState($screenNo);
		my $screen = $render->{'screen'.$screenNo};

		if (!$screen->{scroll}) {
			# no scrolling required
			if ($state > 0) {
				$display->scrollStop($screenNo);
			}
			$display->updateScreen($screen, $screenNo);

		} else {
			if ($state == 0) {
				# not scrolling - start scrolling
				$display->scrollInit($screen, $screenNo, $scrollonce);

			} elsif ($screen->{newscroll}) {
				# currently scrolling - stop and restart
				$display->scrollStop($screenNo);
				$display->scrollInit($screen, $screenNo, $scrollonce);

			} elsif ($state == 2 && $screen->{scroll} == 2) {
				# staying in ticker mode - add to ticker queue & update background
				$display->scrollUpdateTicker($screen, $screenNo);
				$display->scrollUpdateBackground($screen, $screenNo);

			} else {
				# same scrolling text, possibly new background
				$display->scrollUpdateBackground($screen, $screenNo);
			}			  
		}
	}

	# return any old display if stored
	$display->returnOldDisplay($render) if (!$s2periodic && $display->sbOldDisplay());
}

# show text briefly and then return to original display
sub showBriefly {
	my $display = shift;

	my $client = $display->client;

	# return if update blocked
	return if ($display->updateMode() == 2);

	my ($parsed, $duration, $firstLine, $blockUpdate, $scrollToEnd, $brightness, $callback, $callbackargs, $name);

	my $parts = shift;
	if (ref($parts) eq 'HASH') {
		$parsed = $parts;
	} else {
		$parsed = $display->parseLines([$parts,shift]);
	}

	my $args = shift;
	if (ref($args) eq 'HASH') {
		$duration    = $args->{'duration'} || 1; # duration - default to 1 second
		$firstLine   = $args->{'firstline'};     # use 1st line in doubled mode
		$blockUpdate = $args->{'block'};         # block other updates from cancelling
		$scrollToEnd = $args->{'scroll'};        # scroll text once before cancelling if scrolling is necessary
		$brightness   = $args->{'brightness'};   # brightness to display at
		$callback     = $args->{'callback'};     # callback when showBriefly completes
		$callbackargs = $args->{'callbackargs'}; # callback arguments
		$name         = $args->{'name'};         # name - so caller can name who owns current showBriefly
	} else {
		$duration = $args || 1;
		$firstLine   = shift;
		$blockUpdate = shift;
		$scrollToEnd = shift;
		$brightness   = shift;
		$callback     = shift;
		$callbackargs = shift;
		$name         = shift;
	}

	if ($firstLine && ($display->linesPerScreen() == 1)) {
		$parsed->{line}[1] = $parsed->{line}[0];
	}

	my $oldDisplay = $display->sbOldDisplay() || $display->curDisplay();
	$display->sbOldDisplay(undef);

	$display->update($parsed, $scrollToEnd ? 3 : undef);
	
	$display->screen2updateOK( ($oldDisplay->{'screen2'} && !$parsed->{'screen2'} && !$display->updateMode) ? 1 : 0 );
	$display->updateMode( $blockUpdate ? 2 : 1 );
	$display->animateState(5);

	my $callbackData;
	
	if (defined($brightness)) {
		if ($brightness =~ /powerOn|powerOff|idle/) {
			$brightness = $display->client->prefGet($brightness.'Brightness');
		}
		$callbackData->{'brightness'} = $display->brightness();
		$display->brightness($brightness);
	}

	if (defined($callback)) {
		$callbackData->{'callback'} = $callback;
		$callbackData->{'callbackargs'} = $callbackargs;
	}

	$display->sbOldDisplay($oldDisplay);
	$display->sbCallbackData($callbackData);
	$display->sbName($name);

	if (!$scrollToEnd || !$display->scrollData()) {
		Slim::Utils::Timers::setTimer($display,Time::HiRes::time() + $duration, \&endAnimation);
	}
}

sub endShowBriefly {
	my $display = shift;

	$display->sbName(undef);

	my $callbackData = $display->sbCallbackData() || return;

	if (defined(my $brightness = $callbackData->{'brightness'})) {
		$display->brightness($brightness);
	}

	if (defined(my $cb = $callbackData->{'callback'})) {
		my $cbargs = $callbackData->{'callbackargs'};
		&$cb($cbargs);
	}

	$display->sbCallbackData(undef);
}

# return old display which was stored during showBriefly, suppressing screens which are covered by last render
sub returnOldDisplay {
	my $display = shift;
	my $render = shift;

	my $oldDisplay = $display->sbOldDisplay();
	my $screens = $render->{screens};

	foreach my $screenNo (1..$render->{screens}) {
		if ($render->{"screen$screenNo"}->{present}) {
			delete $oldDisplay->{"screen$screenNo"};
			$screens--;
		}
	}

	$display->sbOldDisplay(undef);

	$display->update($oldDisplay) if $screens;
}

# push and bumps are display specific
sub pushLeft {}
sub pushRight {}
sub pushUp {}
sub pushDown {}
sub bumpLeft {}
sub bumpRight {}
sub bumpUp {}
sub bumpDown {}

sub brightness {
	my $display = shift;
	my $delta = shift;

	if (defined($delta) ) {

		if ($delta =~ /[\+\-]\d+/) {
			$display->currBrightness( ($display->currBrightness() + $delta) );
		} else {
			$display->currBrightness( $delta );
		}

		$display->currBrightness(0) if ($display->currBrightness() < 0);
		$display->currBrightness($display->maxBrightness()) if ($display->currBrightness() > $display->maxBrightness());
	}
	
	my $brightness = $display->currBrightness();

	if (!defined($brightness)) { $brightness = $display->maxBrightness(); }	

	return $brightness;
}

sub prevline1 {
	my $display = shift;
	my $cache = $display->renderCache() || return;
	return $cache->{screen1}->{line}[0];
}

sub prevline2 {
	my $display = shift;
	my $cache = $display->renderCache() || return;
	return $cache->{screen1}->{line}[1];
}

sub curDisplay {
	my $display = shift;

	my $parts;
	my $render = $display->renderCache();

	foreach my $s (1..$render->{screens}) {
		my $sc = $render->{'screen'.$s};
		foreach my $c ('line', 'overlay', 'center') {
			$parts->{"screen$s"}->{"$c"} = Storable::dclone($sc->{"$c"}) if $sc->{"$c"};
		}
		if ($sc->{'fonts'}) {
			my $model = $display->vfdmodel();
			$parts->{"screen$s"}->{'fonts'}->{"$model"} = Storable::dclone($sc->{'fonts'});
		}
	}

	return $parts;
}

sub curLines {
	my $display = shift;

	my $client;

	if ($display->isa('Slim::Display::Display')) {
		$client = $display->client;

	} elsif ($display->isa('Slim::Player::Player')) {
		# this code is reached if curLines is called with the old API rather than a method of display
		msg("Slim::Display::curLines() depreciated, please call \$client->curLines()\n");
		Slim::Utils::Misc::bt();
		$client = $display;
		  
	} else {
		return undef;
	}

	my $linefunc = $client->lines();

	if (defined $linefunc) {
		return $display->parseLines(&$linefunc($client));
	} else {
		return undef;
	}
}

# Parse lines into the latest hash format.  Provides backward compatibility for array and escaped lines definitions
# NB will not convert 6.2 hash into a 6.5 hash - this is done in render
sub parseLines {
	my $display = shift;
	my $lines = shift;
	my ($line1, $line2, $line3, $line4, $overlay1, $overlay2, $center1, $center2, $bits);
	
	if (ref($lines) eq 'HASH') { 
		return $lines;
	} elsif (ref($lines) eq 'SCALAR') {
		$line1 = $$lines;
	} else {
		if (ref($lines) eq 'ARRAY') {
			$line1= $lines->[0];
			$line2= $lines->[1];
			$line3= $lines->[2];
			$line4= $lines->[3];
		} else {
			$line1 = $lines;
			$line2 = shift;
			$line3 = shift;
			$line4 = shift;
		}
		
		return $line1 if (ref($line1) eq 'HASH');
		
		if (!defined($line1)) { $line1 = ''; }
		if (!defined($line2)) { $line2 = ''; }

		$line1 .= "\x1eright\x1e" . $line3 if (defined($line3));

		$line2 .= "\x1eright\x1e" . $line4 if (defined($line4));

		if (length($line2)) { 
			$line1 .= "\x1elinebreak\x1e" . $line2;
		}
	}

	while ($line1 =~ s/\x1eframebuf\x1e(.*)\x1e\/framebuf\x1e//s) {
		$bits |= $1;
	}

	$line1 = $display->symbols($line1) || '';
	($line1, $line2) = split("\x1elinebreak\x1e", $line1);

	if (!defined($line2)) { $line2 = '';}
	
	($line1, $overlay1) = split("\x1eright\x1e", $line1) if $line1;
	($line2, $overlay2) = split("\x1eright\x1e", $line2) if $line2;

	($line1, $center1) = split("\x1ecenter\x1e", $line1) if $line1;
	($line2, $center2) = split("\x1ecenter\x1e", $line2) if $line2;

	$line1 = '' if (!defined($line1));

	return {
		'bits'    => $bits,
		'line'    => [ $line1, $line2 ],
		'overlay' => [ $overlay1, $overlay2 ],
		'center'  => [ $center1, $center2 ],
	};
}

sub renderOverlay {
	msg("renderOverlay depreciated - please use parseLines\n");
	bt();
	return shift->parseLines(@_);
}

sub sliderBar {}

sub progressBar {
	my $display = shift;
	return $display->sliderBar(shift,(shift)*100,0,undef,shift);
}

sub balanceBar {
	my $display = shift;
	return $display->sliderBar(shift,shift,50);
}

# initiate server side scrolling for display
sub scrollInit {
	my $display = shift;
	my $screen = shift;
	my $screenNo = shift;
	my $scrollonce = shift; # 0 = continue scrolling after pause, 1 = scroll to scrollend and then stop, 
	                        # 2 = scroll to scrollend and then end animation (causing new update)

	my $client = $display->client;

	my $ticker = ($screen->{scroll} == 2);

	my $refresh = $client->paramOrPref($display->linesPerScreen() == 1 ? 'scrollRateDouble': 'scrollRate');
	my $pause = $client->paramOrPref($display->linesPerScreen() == 1 ? 'scrollPauseDouble': 'scrollPause');	

	my $now = Time::HiRes::time();
	my $start = $now + ($ticker ? 0 : (($pause > 0.5) ? $pause : 0.5));

	my $scroll = {
		'scrollstart'   => $screen->{scrollstart},
		'scrollend'     => $screen->{scrollend},
		'offset'        => $screen->{scrollstart},
		'dir'           => $screen->{scrolldir},
		'scrollonce'    => ($scrollonce || $ticker) ? 1 : 0,
		'scrollonceend' => ($scrollonce == 2) ? 1 : 0,
		'refreshInt'    => $refresh,
		'pauseInt'      => $pause,
		'pauseUntil'    => $start,
		'refreshTime'   => $start,
		'paused'        => 0,
		'overlaystart'  => $screen->{overlaystart}[$screen->{scrollline}],
		'ticker'        => $ticker,
	};

	if (defined($screen->{bitsref})) {
		# graphics display
		my $pixels = $client->paramOrPref($display->linesPerScreen() == 1 ? 'scrollPixelsDouble': 'scrollPixels');	
		$scroll->{shift} = $pixels * $display->bytesPerColumn() * $screen->{scrolldir};
		$scroll->{scrollHeader} = $display->scrollHeader($screenNo);
		$scroll->{scrollFrameSize} = length($display->scrollHeader) + $display->screenBytes($screenNo);
		$scroll->{bitsref} = $screen->{bitsref};
		if (!$ticker) {
			$scroll->{scrollbitsref} = $screen->{scrollbitsref};
		} else {
			my $tickerbits = (chr(0) x $screen->{overlaystart}[$screen->{scrollline}]) . ${$screen->{scrollbitsref}};
			$scroll->{scrollbitsref} = \$tickerbits;
			$scroll->{scrollend} += $screen->{overlaystart}[$screen->{scrollline}];
		}

	} elsif (defined($screen->{lineref})) {
		# text display
		my $double = $screen->{double};
		$scroll->{shift} = 1;
		$scroll->{double} = $double;
		$scroll->{scrollline} = $screen->{scrollline};
		$scroll->{line1ref} = $screen->{lineref}[0];
		$scroll->{line2ref} = $screen->{lineref}[1];
		$scroll->{overlay1text} = $screen->{overlaytext}[0];
		$scroll->{overlay2text} = $screen->{overlaytext}[1];
		if (!$ticker) {
			$scroll->{scrollline1ref} = $screen->{scrollref}[0];
			$scroll->{scrollline2ref} = $screen->{scrollref}[1];
		} else {
			my $line1 = (' ' x $screen->{overlaystart}[$screen->{scrollline}]) . ${$screen->{scrollref}[0]};
			my $line2 = (' ' x $screen->{overlaystart}[$screen->{scrollline}]) . ${$screen->{scrollref}[1]};
			$scroll->{scrollline1ref} = \$line1;
			$scroll->{scrollline2ref} = \$line2;
			$scroll->{scrollend} += $screen->{overlaystart}[$screen->{scrollline}];
		}
	}

	$display->scrollData($screenNo, $scroll);
	$display->scrollState($screenNo, $ticker ? 2 : 1);
	$display->scrollUpdate($scroll);
}

# stop server side scrolling
sub scrollStop {
	my $display = shift;
	my $screenNo = shift;
	my $scroll = $display->scrollData($screenNo) || return;

	Slim::Utils::Timers::killSpecific($scroll->{timer});

	$display->scrollState($screenNo, 0);
	$display->scrollData($screenNo, undef);
}

# update the background of a scrolling display
sub scrollUpdateBackground {
	my $display = shift;
	my $screen = shift;
	my $screenNo = shift;

	my $scroll = $display->scrollData($screenNo);

	if (defined($screen->{bitsref})) {
		# graphics display
		$scroll->{bitsref} = $screen->{bitsref};

	} elsif (defined($screen->{lineref})) {
		# text display
		$scroll->{line1ref} = $screen->{lineref}[0];
		$scroll->{line2ref} = $screen->{lineref}[1];
		$scroll->{overlay1text} = $screen->{overlaytext}[0];
		$scroll->{overlay2text} = $screen->{overlaytext}[1];
	}

	$scroll->{overlaystart} = $screen->{overlaystart}[$screen->{scrollline}];

	# force update of screen for if paused, otherwise rely on scrolling to update
	if ($scroll->{paused}) {
		$display->scrollUpdateDisplay($scroll);
	}
}

# returns: time to complete ticker, time to expose queued up text
sub scrollTickerTimeLeft {
	my $display = shift;
	my $screenNo = shift || 1;

	my $scroll = $display->scrollData($screenNo);

	if (!$scroll) {
		return (0, 0);
	} 

	my $todisplay = $scroll->{scrollend} - $scroll->{offset};
	my $completeTime = $todisplay / ($scroll->{shift} / $scroll->{refreshInt});

	my $notdisplayed = $todisplay - $scroll->{overlaystart};
	my $queueTime = ($notdisplayed > 0) ? $notdisplayed / ($scroll->{shift} / $scroll->{refreshInt}) : 0;

	return ($completeTime, $queueTime);
}

# update scrolling screen during server side scrolling
sub scrollUpdate {
	my $display = shift;
	my $scroll = shift;

	# update display
	$display->scrollUpdateDisplay($scroll);

	my $timenow = Time::HiRes::time();

	if ($timenow < $scroll->{pauseUntil}) {
		# called during pause phase - don't scroll
		$scroll->{paused} = 1;
		$scroll->{refreshTime} = $scroll->{pauseUntil};
		$scroll->{timer} = Slim::Utils::Timers::setHighTimer($display, $scroll->{pauseUntil}, \&scrollUpdate, $scroll);

	} else {
		# update refresh time and skip frame if running behind actual timenow
		do {
			$scroll->{offset} += $scroll->{shift};
			$scroll->{refreshTime} += $scroll->{refreshInt};
		} while ($scroll->{refreshTime} < $timenow);

		$scroll->{paused} = 0;
		if (($scroll->{dir} == 1 && $scroll->{offset} >= $scroll->{scrollend}) ||
			($scroll->{dir} == -1 && $scroll->{offset} <= $scroll->{scrollend}) ) {
			if ($scroll->{scrollonce}) {
				$scroll->{offset} = $scroll->{scrollend};
				if ($scroll->{ticker}) {
					# keep going to wait for ticker to fill
				} elsif ($scroll->{scrollonce} == 1) {
					# finished scrolling at next scrollUpdate
					$scroll->{scrollonce} = 2;
				} elsif ($scroll->{scrollonce} == 2) {
					# transition to permanent scroll pause state
					$scroll->{offset} = $scroll->{scrollstart};
					$scroll->{paused} = 1;
					if ($scroll->{scrollonceend}) {
						# schedule endAnimaton to kill off scrolling and display new screen
						$display->animateState(6) unless ($display->animateState() == 5);
						my $end = ($scroll->{pauseInt} > 0.5) ? $scroll->{pauseInt} : 0.5;
						Slim::Utils::Timers::setTimer($display, $timenow + $end, \&endAnimation);
					}
					return;
				}
			} elsif ($scroll->{pauseInt} > 0) {
				$scroll->{offset} = $scroll->{scrollstart};
				$scroll->{pauseUntil} = $scroll->{refreshTime} + $scroll->{pauseInt};
			} else {
				$scroll->{offset} = $scroll->{scrollstart};
			}
		}
		# fast timer during scroll
		$scroll->{timer} = Slim::Utils::Timers::setHighTimer($display, $scroll->{refreshTime}, \&scrollUpdate, $scroll);
	}
}

sub endAnimation {
	# called after after an animation to redisplay current screen and initiate scrolling
	my $display = shift;
	my $animate = $display->animateState();
	my $screen = ($animate <= 3) ? $display->renderCache() : undef;
	$display->animateState(0);
	$display->updateMode(0);
	$display->screen2updateOK(0);
	$display->endShowBriefly() if ($animate == 5);
	$display->update($screen);
}	

sub resetDisplay {}
sub killAnimation {}
sub fonts {}
sub displayHeight {}
sub showExtendedText {}
sub modes() { [] }
sub nmodes() { 0 }
sub hasScreen2 { 0 }
sub vfdmodel {}

sub forgetDisplay {
	my $display = shift;
	Slim::Utils::Timers::forgetTimer($display);
}

our $failsafeLanguage     = Slim::Utils::Strings::failsafeLanguage();
our %validClientLanguages = Slim::Utils::Strings::validClientLanguages();

sub string {
	my $display = shift;
	my $string = shift;

	my $language = Slim::Utils::Strings::getLanguage();

	# We're in the list - ok.
	if ($validClientLanguages{$language}) {

		return Slim::Utils::Unicode::utf8toLatin1(Slim::Utils::Strings::string($string, $language));
	}

	# Otherwise return using the failsafe.
	return Slim::Utils::Strings::string($string, $failsafeLanguage);
}

sub doubleString {
	my $display = shift;
	my $string = shift;

	my $language = Slim::Utils::Strings::getLanguage();

	# We're in the list - ok.
	if ($validClientLanguages{$language}) {

		return Slim::Utils::Unicode::utf8toLatin1(Slim::Utils::Strings::doubleString($string, $language));
	}

	# Otherwise return using the failsafe.
	return Slim::Utils::Strings::doubleString($string, $failsafeLanguage);
}


# Utility functions for Text players + backwards compatibility for plugins
# Aim to move this into Display::Text, but will mean plugin changes

our %Symbols = (
	'notesymbol' => "\x1Fnotesymbol\x1F",
	'rightarrow' => "\x1Frightarrow\x1F",
	'progressEnd'=> "\x1FprogressEnd\x1F",
	'progress1e' => "\x1Fprogress1e\x1F",
	'progress2e' => "\x1Fprogress2e\x1F",
	'progress3e' => "\x1Fprogress3e\x1F",
	'progress1'  => "\x1Fprogress1\x1F",
	'progress2'  => "\x1Fprogress2\x1F",
	'progress3'  => "\x1Fprogress3\x1F",
	'cursor'	 => "\x1Fcursor\x1F",
	'mixable'    => "\x1Fmixable\x1F",
	'bell'	     => "\x1Fbell\x1F",
	'hardspace'  => "\x1Fhardspace\x1F"
);

our %commandmap = (
	'center'     => "\x1ecenter\x1e",
	'cursorpos'  => "\x1ecursorpos\x1e",
	'framebuf'   => "\x1eframebuf\x1e",
	'/framebuf'  => "\x1e/framebuf\x1e",
	'linebreak'  => "\x1elinebreak\x1e",
	'repeat'     => "\x1erepeat\x1e", 
	'right'      => "\x1eright\x1e",
	'scroll'     => "\x1escroll\x1e",
	'/scroll'    => "\x1e/scroll\x1e", 
	'tight'      => "\x1etight\x1e",
	'/tight'     => "\x1e/tight\x1e",
	'font'       => "\x1efont\x1e",
	'/font'      => "\x1e/font\x1e",
	'defaultfont'=> "\x1edefaultfont\x1e",
);

sub symbol {
	my $symname = shift;
	if (exists($commandmap{$symname})) { return $commandmap{$symname}; }
	return ("\x1f". $symname . "\x1f");
}

sub command {
	my $symname = shift;
	if (exists($commandmap{$symname})) { return $commandmap{$symname}; }
}

sub lineLength {
	my $line = shift;
	return 0 if (!defined($line) || !length($line));

	$line =~ s/\x1f[^\x1f]+\x1f/x/g;
	$line =~ s/(\x1eframebuf\x1e.*\x1e\/framebuf\x1e|\n|\xe1[^\x1e]\x1e)//gs;
	return length($line);
}

sub splitString {
	my $string = shift;
	my @result = ();
	$string =~ s/(\x1f[^\x1f]+\x1f|\x1eframebuf\x1e.*\x1e\/framebuf\x1e|\x1e[^\x1e]+\x1e|.)/push @result, $1;/esg;
	return \@result;
}

sub subString {
	my ($string,$start,$length,$replace) = @_;
	$string =~ s/\x1eframebuf\x1e.*\x1e\/framebuf\x1e//s if ($string);

	my $newstring = '';
	my $oldstring = '';

	if ($start && $length && ($start > 32765 || ($length || 0) > 32765)) {
			msg("substr on string with start or length greater than 32k, returning empty string.\n");
			bt();
			return '';
	}

	if ($string && $string =~ s/^(((?:(\x1e[^\x1e]+\x1e)|)(?:[^\x1e\x1f]|\x1f[^\x1f]+\x1f)){0,$start})//) {
		$oldstring = $1;
	}
	
	if (defined($length)) {
		if ($string =~ s/^(((?:(\x1e[^\x1e]+\x1e)|)([^\x1e\x1f]|\x1f[^\x1f]+\x1f)){0,$length})//) {
			$newstring = $1;
		}
	
		if (defined($replace)) {
			$_[0] = $oldstring . $replace . $string;
		}
	} else {
		$newstring = $string;
	}
	return $newstring;
}

=head1 SEE ALSO



=cut

1;

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
