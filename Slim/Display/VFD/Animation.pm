#!/usr/bin/perl -w
package Slim::Display::VFD::Animation;

# $Id: Animation.pm,v 1.6 2004/09/10 15:16:46 kdf Exp $

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use Slim::Hardware::VFD;
use Slim::Display::VFD::Animation;
use Slim::Utils::Timers;
use Slim::Utils::Misc;

#
# Rates are given in seconds/frame which is more useful in the code.
#

my $scrollSingleLine1FrameRate = 0.9;	# How often to refresh line1 in 1x
                                        # scroll mode.  You might not think we
                                        # had to do this at all, but we want
                                        # to update the track timer if it is
                                        # being shown.  Perhaps this could be
                                        # slower?  But at this rate the time
                                        # looks smooth.

my $scrollSeparator = "      ";
################### WARNING WARNING WARNING WARNING ###################
# The code in this file has been carefully tuned for performance.
# The scrolling code especially has to be very fast becaues it runs many times
# a second and can caues player starvation and other bad things if it isn't fast.
# PLEASE, don't make changes unless your head is screwed on very tight.
# PLEASE, measure the performance of your changes vs the checked in versions.
#######################################################################

# Animations are performed by calling a function which calculates the next
# frame of the animation.  If the animation has more frames to show, the function
# schedules animate() for the next time the display should be updated.  The animate
# function takes as arguments; the client object, the animation function to call
# and the arguments to pass to that function.

# The public functions check the animation level, and if it is equal to or
# greater than the level required for the function, animate() is called.  If less
# the display is updated and the function exits.

# The following public functions provide information about whether the animation
# is running, and allow the animation to be stopped.

# All animations will have a pending timer for animate() if they are currently animating

sub animating {
	my $client = shift;

	if ((Slim::Utils::Timers::pendingTimers($client, \&animate) + Slim::Utils::Timers::pendingTimers($client, \&update)) > 0) {
		return 1;
	} else {
		return 0;
	}
}

# find all the queued up animation frames and toss them
sub killAnimation {
	my $client = shift;
	if (!$client->isPlayer()) { return; };
	Slim::Buttons::Common::param($client,'noUpdate',0);
	Slim::Utils::Timers::killTimers($client, \&animate);
	Slim::Utils::Timers::killTimers($client, \&endAnimation);
	Slim::Utils::Timers::killTimers($client, \&update);
}

sub endAnimation {
	my $client = shift;
	Slim::Buttons::Common::param($client,'noUpdate',0); 
	$client->update();
}

# These are the public animation routines

# --------- showBriefly
# The simplest animation routine.  Shows the first lines for one second, then
# shows the second lines.
sub showBriefly {
	my $client = shift;
	my $line1 = shift;
	my $line2 = shift;
	my $duration = shift;
	my $firstLineIfDoubled = shift;

	my $parsed;
	
	if (ref($line1) eq 'HASH') {
		$parsed = $line1;
	} else {
		$parsed = $client->parseLines([$line1,$line2]);
	}
	
	if ($firstLineIfDoubled && ($client->linesPerScreen() == 1)) {
		$parsed->{line2} = $parsed->{line1};
	}
	
	my $pause = Slim::Buttons::Common::paramOrPref($client,'scrollPause');
	
	if (!$client->isPlayer()) { return; };

	if (!$duration) {
		$duration = 1;
	}
	
	my ($measure1, $measure2);
	
	my $double = ($client->linesPerScreen() == 1);
	
	if ($double) {
		($measure1, $measure2) = Slim::Hardware::VFD::doubleSize($client,$parsed);
	} else {
		($measure1, $measure2) = ($parsed->{line1}, $parsed->{line2});
	}
	
	if (($duration >  $pause) && (Slim::Display::Display::lineLength($measure2) > 40) || (Slim::Display::Display::lineLength($measure1) > 40)) {

		my @newqueue = ();
		my ($t1, $t2);
		
		my $rate;
	
		# double them
		if ($double) {
			$rate = Slim::Buttons::Common::paramOrPref($client,'scrollRateDouble');
			($parsed->{line1}, $parsed->{line2}) = Slim::Hardware::VFD::doubleSize($client,$parsed);
		} else {
			$rate = Slim::Buttons::Common::paramOrPref($client,'scrollRate');
		}
		if ($rate == 0) {
			$client->update();
			return;
		}
	
		# add some blank space to the end of each line
		if (Slim::Display::Display::lineLength($parsed->{line1}) > 40) {
			$measure1 .= $scrollSeparator;		
		}
		if (Slim::Display::Display::lineLength($parsed->{line2}) > 40) {
			$measure2 .= $scrollSeparator;		
		}

		# even them out
		# put another copy of the text at the end of the line to make it appear to wrap around
		if (Slim::Display::Display::lineLength($parsed->{line2}) > 40) {
			while (Slim::Display::Display::lineLength($measure1) > Slim::Display::Display::lineLength($measure2)) { $measure2 .= ' '; }
			$parsed->{line2} = $measure2 . $parsed->{line2};
		}
		
		if (Slim::Display::Display::lineLength($parsed->{line1}) > 40) {
			while (Slim::Display::Display::lineLength($measure2) > Slim::Display::Display::lineLength($measure1)) { $measure1 .= ' '; }
			$parsed->{line1} = $measure1 . $parsed->{line1};
		}
		
		my $len2 = Slim::Display::Display::lineLength($measure2);
		my $len1 = Slim::Display::Display::lineLength($measure1);

		startAnimate ($client,\&animateScrollBottom
				,$pause
				,[$parsed->{line1},$parsed->{line2}] #lines
				,['',''] #overlays
				,[$len1,$len2] #end 40 chars from the right
				,[0,0] #start at the begining
				,[$double || (Slim::Display::Display::lineLength($parsed->{line1}) > 40),Slim::Display::Display::lineLength($parsed->{line2}) > 40] #scroll the top if doublesize
				,$rate,$double);
		
		Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + $duration, \&endAnimation);
	} else {
		$client->update($parsed);
	
		Slim::Utils::Timers::setTimer($client,Time::HiRes::time() + $duration,\&update)
	}
}

sub update {
	shift->update();
}

# push the old lines (start1,2) off the left side
sub pushLeft {
	my $client = shift;
	my $startref = shift;
	my $endref = shift;
	
	my ($start1, $start2) = Slim::Hardware::VFD::render($client, $startref);
	my ($end1, $end2) = Slim::Hardware::VFD::render($client, $endref);
	
	$start1 = Slim::Display::Display::subString($start1 . ' ' x (40 - Slim::Display::Display::lineLength($start1)),0,40);
	$start2 = Slim::Display::Display::subString($start2 . ' ' x (40 - Slim::Display::Display::lineLength($start2)),0,40);

	startAnimate($client,\&animateSlideWindows
			,[$start1 . $end1,$start2 . $end2] #lines
			,[40,40],[1,1],[3,3] #end, pos, step
			,0.0125,($client->linesPerScreen() == 1));
}

# push the old lines (start1,2) off the right side
sub pushRight {
	my $client = shift;
	my $startref = shift;
	my $endref = shift;
	
	my ($start1, $start2) = Slim::Hardware::VFD::render($client, $startref);
	my ($end1, $end2) = Slim::Hardware::VFD::render($client, $endref);
	
	$start1 = Slim::Display::Display::subString($start1 . ' ' x (40 - Slim::Display::Display::lineLength($start1)),0,40);
	$start2 = Slim::Display::Display::subString($start2 . ' ' x (40 - Slim::Display::Display::lineLength($start2)),0,40);

	startAnimate($client,\&animateSlideWindows
			,[$end1 . $start1,$end2 . $start2] #lines
			,[40,40],[39,39],[-3,-3] #end, pos, step
			,0.0125,($client->linesPerScreen() == 1));
}

# easter egg animation
my $easter = 0;
sub doEasterEgg {
	my $client = shift;
	my @newqueue = ();
	my $frame_rate = 0.15;

	if ($easter == 0) {
		my $text1 = sprintf(Slim::Utils::Strings::string('ABOUT'), $main::VERSION );
		$text1 = (' ' x (int((40-Slim::Display::Display::lineLength($text1))/2))) . $text1 . (' ' x (int((40-Slim::Display::Display::lineLength($text1))/2)));
		my $text2 =  join(', ', @main::AUTHORS) . ', ';
		$text2 = $text2 . $text2 . $text2 . $text2;
		startAnimate($client,\&animateSlideWindows
			,[$text1,$text2] #lines
			,[40,Slim::Display::Display::lineLength($text2) - 40],[0,0],[0,1] #end, pos, step
			,$frame_rate,1);
		$easter++;
	} elsif ($easter == 1) {
		my $lines = $client->parseLines(Slim::Display::Display::curLines($client));
		my $text1 = $lines->{line1};
		my $text2 = $lines->{line2};
		$text1 = Slim::Display::Display::subString(($text1 . (' ' x (40 - Slim::Display::Display::lineLength($text1)))),0,40);
		$text2 = Slim::Display::Display::subString(($text2 . (' ' x (40 - Slim::Display::Display::lineLength($text2)))),0,40);
		my $line1 = $text1 . join('',reverse(@{Slim::Display::Display::splitString($text2)})) . $text1;
		my $line2 = $text2 . join('',reverse(@{Slim::Display::Display::splitString($text1)})) . $text2;
		startAnimate($client,\&animateSlideWindows
			,[$line1,$line2] #lines
			,[80,80],[80,0],[-1,1] #end, pos, step
			,$frame_rate,1);
		$easter++;
	} elsif ($easter ==2) {
		my $text1 = sprintf(Slim::Utils::Strings::string('ABOUT'), $main::VERSION );
		$text1 = (' ' x (40-Slim::Display::Display::lineLength($text1))) . $text1 . (' ' x (40-Slim::Display::Display::lineLength($text1)));
		my $text2 =  join(', ', @main::AUTHORS) . ', ';
		while (Slim::Display::Display::lineLength($text2) < 40) { $text2 .= $text2; }
		$text2 .= Slim::Display::Display::subString($text2,0,40);
		startAnimate($client,\&animateFunky
			,[$text1,$text2] #lines
			,[Slim::Display::Display::lineLength($text1) - 40,Slim::Display::Display::lineLength($text2) - 40],[0,0],[1,1] #end, pos, step
			,$frame_rate,1);
		$easter++;
	}
	$easter %= 3;
}


sub bumpLeft {
	my $client = shift;
	my $lines = $client->parseLines(Slim::Display::Display::curLines($client));

	$lines->{line1} = Slim::Display::Display::symbol('hardspace') . $lines->{line1} if ($lines->{line1});
	$lines->{line2} = Slim::Display::Display::symbol('hardspace') . $lines->{line2} if ($lines->{line2});
	$lines->{overlay1} = Slim::Display::Display::subString($lines->{overlay1}, 0, -1) if ($lines->{overlay1});
	$lines->{overlay2} = Slim::Display::Display::subString($lines->{overlay2}, 0, -1) if ($lines->{overlay2});

	showBriefly($client, $lines, undef, 0.125);
}

sub bumpUp {
	my $client = shift;
	my $lines = $client->parseLines(Slim::Display::Display::curLines($client));

	$lines->{line1} = $lines->{line2};
	$lines->{line2} = '';
	$lines->{overlay1} = $lines->{overlay2};
	$lines->{overlay2} = '';

	showBriefly($client, $lines, undef, 0.125);
}

sub bumpDown {
	my $client = shift;
	my $lines = $client->parseLines(Slim::Display::Display::curLines($client));

	$lines->{line2} = $lines->{line1};
	$lines->{line1} = '';
	$lines->{overlay2} = $lines->{overlay1};
	$lines->{overlay1} = '';

	showBriefly($client, $lines, undef, 0.125);
}

sub bumpRight {
	my $client = shift;
	my $lines = $client->parseLines(Slim::Display::Display::curLines($client));

	$lines->{line1} = Slim::Display::Display::subString($lines->{line1}, 1, 39) . ' ' if ($lines->{line1});
	$lines->{line2} = Slim::Display::Display::subString($lines->{line2}, 1, 39) . ' ' if ($lines->{line1});
	$lines->{overlay1} = $lines->{overlay1} . Slim::Display::Display::symbol('hardspace') if ($lines->{overlay1});
	$lines->{overlay2} = $lines->{overlay2} . Slim::Display::Display::symbol('hardspace') if ($lines->{overlay2});

	showBriefly($client, $lines, undef, 0.125);
}


sub scrollBottom {
	my $client = shift;

	my $linefunc  = $client->lines();
	my $lines = $client->parseLines(&$linefunc($client));

	return if Slim::Buttons::Common::param($client,'noScroll');
	
	my $line1 = $lines->{line1} || '';
	my $line2 = $lines->{line2} || '';
	my $overlay1 = $lines->{overlay1} || '';
	my $overlay2 = $lines->{overlay2} || '';

	my $rate;
	my $double = $client->linesPerScreen() == 1;
	
	if ($double) {
		$rate = Slim::Buttons::Common::paramOrPref($client,'scrollRateDouble');
	} else {
		$rate = Slim::Buttons::Common::paramOrPref($client,'scrollRate');
	}

	my $len;

	if ($rate == 0) {
		$client->update();
		return;
	}

	# special case scrolling for nowplaying
	# now uses a client param, undef or zero for static top line, non-zero for a dynamic top line.
	if (defined(Slim::Buttons::Common::param($client,'animateTop')) 
				&& Slim::Buttons::Common::param($client,'animateTop')) {
		if ($double) {
			scrollDouble($client,$line2,$overlay2,$rate);
		}
		else {
			scrollSingle($client,$line2,$overlay2);
		}
		return;
	}
	
	# calculate the displayed length
	if ($double) {
		my $rate = Slim::Buttons::Common::paramOrPref($client,'scrollRate');#*2/3;
		$overlay2 = "";
		$overlay1 = "";
		my ($double1, $double2) = Slim::Hardware::VFD::doubleSize($client,{ line1=> $line1, line2 =>$line2} );
		$len = Slim::Display::Display::lineLength($double1);
	} else {
		$len = Slim::Display::Display::lineLength($line2);
	}

	#only scroll if our line is long enough
	if ($len > (40 - Slim::Display::Display::lineLength($overlay2))){
		
		my $now = Slim::Buttons::Common::paramOrPref($client,'scrollPause');
		my @newqueue = ();
		my ($measure1, $measure2);
		my ($t1, $t2);
		
		# measure the length of the text to scroll
		$measure2 = $line2 . $scrollSeparator;		
		$line2 = $line2 . $scrollSeparator . $line2;

		# double them
		if ($double) {
			scrollDouble($client,$line2,$overlay2,$rate);
			return;
		}
	
		$len = Slim::Display::Display::lineLength($measure2);

		startAnimate ($client,\&animateScrollBottom
				,$now
				,[$line1,$line2] #lines
				,[$overlay1,$overlay2] #overlays
				,[$len-1,$len] #end 40 chars from the right
				,[0,0] #start at the begining
				,[$double,1] #scroll the top if doublesize
				,$rate,$double);
	} else {
		$client->update();
	}
}


# scrollSingle - private.  Starts scrolling text2 across the bottom line of
# client.
sub scrollSingle {
	my $client = shift;
	my $text2 = shift;
	my $overlay2 = shift;
	my $rate = shift;
	
	if (!defined($overlay2)) { $overlay2 = '' };
	if (Slim::Display::Display::lineLength($text2) <= 40 - Slim::Display::Display::lineLength($overlay2)) {
		# No need to actually scroll
		$client->update();
	}
	else {
		$text2 = $text2 . $scrollSeparator;
		my $text22 = $text2 . $text2;

		startAnimate($client,\&animateScrollSingle1, \$text22, Slim::Display::Display::lineLength($text2), 0);
	}
}

# scrollDouble - private. 2x mode scrolling.  Scroll line2 across the screen
# in 2x mode.
sub scrollDouble {
	my $client = shift;
	my $line2 = shift;
	my $overlay2 = shift;
	my $rate = shift;
	
	if (!defined($rate) || $rate < 0) {
		my $rate = Slim::Buttons::Common::paramOrPref($client,'scrollRateDouble');
	}

	my ($text1,$text2) = Slim::Hardware::VFD::doubleSize($client,{line2 => $line2});
	if (Slim::Display::Display::lineLength($text2) < 41) {
		$client->update();
	}
	else {
		my $graphic = "        ";
		$text1 = $text1. $graphic;
		$text2 = $text2. $graphic;
		my $text11 = $text1 . $text1;
		my $text22 = $text2 . $text2;

		startAnimate($client,\&animateScrollDouble,\$text11,\$text22,Slim::Display::Display::lineLength($text1),
					 Slim::Display::Display::lineLength($text1),$rate);
	}
}

# private animation functions

# ------------ startAnimate
# Kick off an animation on client.  Same arguments as animate, but is meant to be called for
# the inital call in the sequence only so it can clean up after running any currently running
# animations.
sub startAnimate {
	my ($client,$animationFunction,@args) = @_;
	killAnimation($client);
	animate($client,$animationFunction,Time::HiRes::time(),@args);
}

# main private animation function
sub animate {
	my ($client
		,$animationFunction
		,$expectedTime
		,@animateArgs) = @_;
	my $now = Time::HiRes::time();
	my $framedelay;
	my $overdue = $now - $expectedTime;
	if (defined $animationFunction) {
		($framedelay,$animationFunction,@animateArgs) = $animationFunction->($client,$overdue,@animateArgs);
	}
	if (defined($animationFunction) && $framedelay) {
		my $when = $now + $framedelay;
		Slim::Utils::Timers::setTimer($client,$when,\&animate,$animationFunction,$when,@animateArgs);
	}
}


# ------------ animateFrames
# Takes an array ref of frame arrays, shows the first item in the array, then reschedules
# for the time to show the next frame.
# The frame array consists of three items:
# [0] is the delay until the next frame should be shown (in seconds)
# [1] is the first line of the display
# [2] is the second line of the display
sub animateFrames {
	my $client = shift;
	my $overdue = shift;
	my $framesref = shift;
	my $repeat = shift;
	my $noDoubleSize = shift;
	my $frameref = shift @$framesref;

	while ($overdue > $frameref->[0] && @$framesref) {
		#catch up
		if ($repeat) { push @$framesref,$frameref; }
		$overdue -= $frameref->[0];
		$frameref = shift @$framesref;
	}

	$client->update([$frameref->[1],$frameref->[2]],$noDoubleSize);
	if ($repeat) { push @$framesref,$frameref; }
	if (@$framesref) {
		return ($frameref->[0],\&animateFrames,$framesref,$repeat,$noDoubleSize);
	}
	return $frameref->[0];
}

# -----------  animatePush
# Takes an array ref of line arrays, containing the before and after lines to be shown
# Pushes left if $step is positive, right if negative
# the lines array looks like this:
# [0][0] - the top left line, [0][1] - the top right line
# [1][0] - the bottom left line, [1][1] the bottom right line
sub animatePush {
	my $client = shift;
	my $overdue = shift;
	my $linesref = shift;
	my $pos = shift;
	my $step = shift;
	my $noDoubleSize = shift;

	if ($overdue > 0.0125) {
		$pos += $step * (int($overdue/0.0125));
		if ($pos >40) { $pos = 40; }
	}
	$client->update(
		[(Slim::Display::Display::subString($linesref->[0][0],$pos,40-$pos) . $linesref->[0][1])
		,(Slim::Display::Display::subString($linesref->[1][0],$pos,40-$pos) . $linesref->[1][1])]
		,$noDoubleSize);
	$pos += $step;
	if ($pos > -1 && $pos < 41) {
		return (0.0125,\&animatePush,$linesref,$pos,$step,$noDoubleSize);
	}
	return 0;
}

# -----------  animateSlideWindows
# Takes an array ref of two strings, then slides 40 character windows over each string
# The windows can move independently of each other, and both strings need not be the same
# length.  The animation stops when either window goes over the edge on either end.  The
# left edge is always 0, the right edge is passed in as a parameter and is usually 40
# characters from the right end of the string (it denotes the position of the leftmost
# char of the window.
# $client - the client whose display is animating
# for the following array refs the value in position [0] is for the top, and [1] is for the bottom
# $linesref - reference to an array of strings
# $endref - reference to an array of right edges
# $posref - reference to an array of the current position of both lines
# $stepref - reference to an array of the step values to use (negative shifts right, positive shifts left)
# $framedelay - time until next frame should be shown
# $noDoubleSize - flag to $client->update() not to apply the doubleSize function

sub animateSlideWindows {
	my ($client,$overdue,$linesref,$endref,$posref,$stepref,$framedelay,$noDoubleSize) = @_;

	if ($overdue > $framedelay) {
		for (my $i = 0;$i <= 1; $i++) {
			$$posref[$i] += $$stepref[$i] * (int($overdue/$framedelay));
			$$posref[$i] = 0 if $$posref[$i] < 0;
			$$posref[$i] = $$endref[$i] if $$posref[$i] > $$endref[$i];
		}
	}
	
	$client->update([Slim::Display::Display::subString($linesref->[0],$posref->[0],40)
		,Slim::Display::Display::subString($linesref->[1],$posref->[1],40)]
		,$noDoubleSize);
	$posref->[0] += $stepref->[0];
	$posref->[1] += $stepref->[1];
	if ($$posref[0] >= 0 && $$posref[1] >= 0 && $$posref[0] <= $$endref[0] && $$posref[1] <= $$endref[1]) {
		return ($framedelay,\&animateSlideWindows
			,$linesref,$endref,$posref,$stepref
			,$framedelay,$noDoubleSize);
	}
	return 0;
}

# -----------  animateSlideWindowsOverlay
# Takes an array ref of two strings, then slides 40 character windows over each string, with
# an overlay being applied to the string under the window.
# The windows can move independently of each other, and both strings need not be the same
# length.  The animation stops when either window goes over the edge on either end.  The
# left edge is always 0, the right edge is passed in as a parameter and is usually 40
# characters from the right end of the string (it denotes the position of the leftmost
# char of the window.
# $client - the client whose display is animating
# for the following array refs the value in position [0] is for the top, and [1] is for the bottom
# $linesref - reference to an array of strings
# $overref - reference to an array of overlays
# $endref - reference to an array of right edges
# $posref - reference to an array of the current position of both lines
# $stepref - reference to an array of the step values to use (negative shifts right, positive shifts left)
# $framedelay - time until next frame should be shown
# $noDoubleSize - flag to $client->update() not to apply the doubleSize function

sub animateSlideWindowsOverlay {
	my ($client,$overdue,$linesref,$overref,$endref,$posref,$stepref,$framedelay,$noDoubleSize) = @_;

	if ($overdue > $framedelay) {
		for (my $i = 0;$i <= 1; $i++) {
			$$posref[$i] += $$stepref[$i] * (int($overdue/$framedelay));
			$$posref[$i] = 0 if $$posref[$i] < 0;
			$$posref[$i] = $$endref[$i] if $$posref[$i] > $$endref[$i];
		}
	}
	$client->update([$client->renderOverlay(Slim::Display::Display::subString($linesref->[0],$posref->[0],40)
							,Slim::Display::Display::subString($linesref->[1],$posref->[1],40)
							,@$overref)]
		,$noDoubleSize);
	$posref->[0] += $stepref->[0];
	$posref->[1] += $stepref->[1];
	if ($$posref[0] >= 0 && $$posref[1] >= 0 && $$posref[0] <= $$endref[0] && $$posref[1] <= $$endref[1]) {
		return ($framedelay,\&animateSlideWindowsOverlay
			,$linesref,$overref,$endref,$posref,$stepref
			,$framedelay,$noDoubleSize);
	}
	return 0;
}
# ----------- animateScrollBottom
# Perform an initial pause then transition to a slide windows with overlay

sub animateScrollBottom {
	my ($client,$overdue,$initialPause
		,$linesref,$overref,$endref,$posref,$stepref,$framedelay,$noDoubleSize) = @_;

	if ($initialPause) {
		animateFrames($client,$overdue,[[$initialPause,$client->renderOverlay(@$linesref,@$overref)]],0,$noDoubleSize);
		return ($initialPause,\&animateSlideWindowsOverlay,$linesref,$overref,$endref,$posref,$stepref,$framedelay,$noDoubleSize);
	}
	return animateSlideWindowsOverlay($client,$overdue,$linesref,$overref,$endref,$posref,$stepref,$framedelay,$noDoubleSize);
}

# ------------- animateFunky
# the top line scrolls back and forth, the bottom line scrolls to the left indefinitely
sub animateFunky {
	my ($client,$overdue,$linesref,$endref,$posref,$stepref,$framedelay,$noDoubleSize) = @_;
	my ($nextTime,$functref);
	($nextTime,$functref) = animateSlideWindows($client,$overdue,$linesref,$endref,$posref,$stepref,$framedelay,$noDoubleSize);
	if (!$functref) { #hit the end, find out which end, and take the appropriate action
		if ($$posref[0] < 0) {
			$$posref[0] = 1;
			$$stepref[0] *= -1;
		} elsif ($$posref[0] > $$endref[0]) {
			$$posref[0] = $$endref[0] - 1;
			$$stepref[0] *= -1;
		}
		if ($$posref[1] > $$endref[1]) {
			$$posref[1] = 1;
		}
	}
	return ($framedelay,\&animateFunky,$linesref,$endref,$posref,$stepref,$framedelay,$noDoubleSize);
}


# Single mode scrolling has two states.  state1 is the paused state.  In this
# state we have to keep updating the display (because the track timer might be
# changing.)  State2 actually scrolls the bottom line once.

sub animateScrollSingle1 {
	# state1

	my $client = shift;
	my $overdue = shift;
	my $text22 = shift;
	my $text22_length = shift;
	my $pause_count = shift(@_) + $overdue;
	my $hold = Slim::Buttons::Common::paramOrPref($client,'scrollPause');
	my $rate = Slim::Buttons::Common::paramOrPref($client,'scrollRate');
	if ($rate == 0) {
		$client->update();
		return;
	}
		
	my $lines = $client->parseLines(Slim::Display::Display::curLines($client));
	if ($pause_count < $hold) {
		$client->update($lines,0);
		return ($rate,\&animateScrollSingle1, $text22, $text22_length,
				$pause_count + $scrollSingleLine1FrameRate);
	} else {
		return animateScrollSingle2($client, 0, $text22, 0, $text22_length, $lines, 0);
	}
}

sub animateScrollSingle2 {
	# state2
	my $client = shift;
	my $overdue = shift;
	my $text22 = shift;
	my $ind = shift;
	my $len = shift;
	my $lines = shift;
	my $line1_age = shift(@_) + $overdue;
	my $rate = Slim::Buttons::Common::paramOrPref($client,'scrollRate');
	if ($rate == 0) {
		$client->update();
		return;
	}
	if ($overdue > $rate) {
		$ind += int($overdue/$rate);
	}
	
	if ($ind < $len) {
		if ($line1_age > $rate) {
			# If there is a track time display on line 1, we'd like to refresh it
			# often enough to have it look smooth.  But calling curLines can be
			# kind of expensive, so we'll try to keep the old value for just a
			# little less than a second.
			$lines = $client->parseLines(Slim::Display::Display::curLines($client));
			$line1_age = 0;
		}
		$client->update([$lines->{line1}, Slim::Display::Display::subString($$text22, $ind, 40),$lines->{overlay1}], 0);

		return ($rate, \&animateScrollSingle2, $text22, $ind+1, $len,
				 $lines, $line1_age + $rate);
	} else {
		return animateScrollSingle1($client, 0, $text22, $len, 0);
	}
}

sub animateScrollDouble {
	my $client = shift;
	my $overdue = shift;
	my $text11 = shift;
	my $text22 = shift;
	my $ind = shift;
	my $len = shift;
	my $hold = Slim::Buttons::Common::paramOrPref($client,'scrollPauseDouble');
	my $rate = Slim::Buttons::Common::paramOrPref($client,'scrollRateDouble');
	if ($rate == 0) {
		$client->update();
		return;
	}
	if ($overdue > $rate) {
		$ind += int($overdue/$rate);
	}
	if ($ind > $len) {
		$client->update([Slim::Display::Display::subString($$text11, 0, 40), Slim::Display::Display::subString($$text22, 0, 40)], 1);
		return ($hold + $rate, \&animateScrollDouble, $text11, $text22, 0, $len);
	}
	else {
		$client->update([ Slim::Display::Display::subString($$text11, $ind, 40), Slim::Display::Display::subString($$text22, $ind, 40)], 1);
		return ($rate,\&animateScrollDouble, $text11, $text22, $ind+1, $len);
	}
}

1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End: