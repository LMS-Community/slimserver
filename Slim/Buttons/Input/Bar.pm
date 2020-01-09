package Slim::Buttons::Input::Bar;


# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

=head1 NAME

Slim::Buttons::Input::Bar

=head1 SYNOPSIS

$params->{'valueRef'} = \$value;

Slim::Buttons::Common::pushMode($client, 'INPUT.Bar', $params);

=head1 DESCRIPTION

L<Slim::Buttons::Home> is a Logitech Media Server module for creating and
navigating a configurable multilevel menu structure.

Avilable Parameters and their defaults:

 'header'          = ''    # message displayed on top line, can be a scalar, a code ref,
                           # or an array ref to a list of scalars or code refs
 'headerArgs'      = CV    # accepts C, and V, determines if the $client(C) and or the $valueRef(V) 
                          # are sent to the above codeRef
 'stringHeader'    = undef # if true, put the value of header through the string function
                           # before displaying it.
 'headerValue'     = undef
	set to 'scaled' to show the current value modified by the increment in parentheses
	set to 'unscaled' to show the current value in parentheses
	set to a codeRef which returns a string to be shown after the standard header
 'headerValueArgs' = CV    # accepts C, and V
 'headerValueUnit' = ''    # Set to a units symbol to be displayed before the closing paren
 'valueRef'        =       # reference to value to be selected
 'trackValueChanges'= undef# allow the value referenced by valueRef to be updated externally
 'callback'        = undef # function to call to exit mode
 'handleLeaveMode' = undef # call the exit callback function whenever leaving this mode
 'overlayRef'      = undef # reference to subroutine to set any overlay display conditions.
 'overlayRefArgs'  = CV    # accepts C, and V
 'onChange'        = undef # code reference to execute when the valueRef is changed
 'onChangeArgs'    = CV    # accepts C, and V
 'min'             = 0     # minimum value for slider scale
 'max'             = 100   # maximum value for slider scale
 'mid'             = 0     # midpoint value for marking the division point for a balance bar.
 'midIsZero'       = 1     # set to 0 if you don't want the mid value to be interpreted as zero
 'cursor'	       = undef # plave a visible cursor at the specified position.
 'increment'       = 2.5   # step value for each bar character or button press.
 'barOnDouble'     = 0     # set to 1 if the bar is preferred when using large text.
 'smoothing'       = 0     # set to 1 if you want the character display to use custom chars to 
                           # smooth the movement of the bar.

 'knobaccelup'     = 0.05  # Constant that determines how fast the Bar accelerates when 
 'knobacceldown'   = 0.05  # using a knob.   up and down accelerations are different.

=cut

use strict;

use Slim::Buttons::Common;
use Slim::Utils::Log;
use Slim::Utils::Misc;

use constant UPDATE_DELAY => 0.05; # time to delay screen updates by

my %functions = ();

# XXXX - This should this be in init() - but we don't init Input methods
# before trying to use them.
Slim::Buttons::Common::addMode('INPUT.Bar', getFunctions(), \&setMode, \&_leaveModeHandler);
Slim::Buttons::Common::addMode('INPUT.Volume', getFunctions(), \&setMode, \&_leaveModeHandler);

sub init {
	my $client = shift;

	if (!defined($client->modeParam('parentMode'))) {

		my $i = -2;

		while ($client->modeStack->[$i] =~ /^INPUT\./) {
			$i--;
		}

		$client->modeParam('parentMode', $client->modeStack->[$i]);
	}

	my %initValues = (
		'header'          => '',
		'min'             => 0,
		'mid'             => 0,
		'midIsZero'       => 1,
		'max'             => 100,
		'increment'       => 2.5,
		'barOnDouble'     => 0,
		'onChangeArgs'    => 'CV',
		'headerArgs'      => 'CV',
		'overlayRefArgs'  => 'CV',
		'headerValueArgs' => 'CV',
		'headerValueUnit' => '',

		# Bug: 2093 - Don't let the knob wrap or have acceleration when in INPUT.Bar mode.
		'knobFlags'       => Slim::Player::Client::KNOB_NOWRAP() | Slim::Player::Client::KNOB_NOACCELERATION(),
		'knobWidth'	  => 100,
		'knobHeight'	  => 1,
		'knobBackgroundForce' => 15,
	);

	# Set our defaults for this mode.
	for my $name (keys %initValues) {

		if (!defined $client->modeParam($name)) {

			$client->modeParam($name, $initValues{$name});
		}
	}
	
	my $min  = getExtVal($client, 'min');
	my $mid  = getExtVal($client, 'mid');
	my $max  = getExtVal($client, 'max');
	
	my $step = $client->modeParam('increment');
	
	my $listRef = [];
	my $j = 0;

	for (my $i = $min; $i <= $max; $i = $i + $step) {

		$listRef->[$j++] = $i;
	}

	$client->modeParam('listRef', $listRef);

	my $listIndex = $client->modeParam('listIndex');
	my $valueRef  = $client->modeParam('valueRef');

	if (!defined($listIndex)) {

		$listIndex = 0;

	} elsif ($listIndex > $#$listRef) {

		$listIndex = $#$listRef;
	}

	while ($listIndex < 0) {
		$listIndex += scalar(@$listRef);
	}

	if (!defined($valueRef)) {

		$$valueRef = $listRef->[$listIndex];
		$client->modeParam('valueRef', $valueRef);

	} elsif (!ref($valueRef)) {

		my $value = $valueRef;
		$valueRef = \$value;

		$client->modeParam('valueRef', $valueRef);
	}

	if ($$valueRef != $listRef->[$listIndex]) {

		my $newIndex;

		for ($newIndex = 0; $newIndex < scalar(@$listRef); $newIndex++) {

			last if $$valueRef <= $listRef->[$newIndex];
		}

		if ($newIndex < scalar(@$listRef)) {
			$listIndex = $newIndex;
		} else {
			$$valueRef = $listRef->[$listIndex];
		}
	}

	$client->modeParam('listIndex', $listIndex);

	my $headerValue = lc($client->modeParam('headerValue') || '');

	if ($headerValue eq 'scaled') {

		$client->modeParam('headerValue',\&scaledValue);

	} elsif ($headerValue eq 'unscaled') {

		$client->modeParam('headerValue',\&unscaledValue);
	}

	# change character at cursorPos (both up and down)
	%functions = (

		'up' => sub {
			my ($client, $funct, $functarg) = @_;

			changePos($client, 1, $funct);
		},

		'down' => sub {
			my ($client, $funct, $functarg) = @_;

			changePos($client, -1, $funct);
		},

		'knob' => sub {
			my ($client, $funct, $functarg) = @_;
			
			my $knobPos   = $client->knobPos();
			my $listIndex = $client->modeParam('listIndex');
			my $log       = logger('player.ui');

			main::DEBUGLOG && $log->debug("Got a knob event for the bar: knobpos: $knobPos listindex: $listIndex");

			changePos($client, $knobPos - $listIndex, $funct);

			if ( main::DEBUGLOG && $log->is_debug ) {
				$log->debug("New listindex: ", $client->modeParam('listIndex'));
			}
		},

		# call callback procedure
		'exit' => sub {
			my ($client, $funct, $functarg) = @_;

			if (!$functarg) {
				$functarg = 'exit'
			}

			exitInput($client, $functarg);
		},

		'passback' => sub {
			my ($client, $funct, $functarg) = @_;

			my $parentMode = $client->modeParam('parentMode');

			if (defined $parentMode) {
				Slim::Hardware::IR::executeButton($client, $client->lastirbutton, $client->lastirtime, $parentMode);
			}
		},
	);

	return 1;
}

sub scaledValue {
	my $client = shift;
	my $value  = shift;

	if ($client->modeParam('midIsZero')) {
		$value -= getExtVal($client, 'mid');
	}

	my $increment = $client->modeParam('increment');

	$value /= $increment if $increment;
	if ($value > 0) {
		$value = int($value + 0.5);
	} else {
		$value = int($value);
	}

	my $unit = $client->modeParam('headerValueUnit');

	if (!defined $unit) {
		$unit = '';
	}

	return " ($value$unit)"	
}

sub unscaledValue {
	my $client = shift;
	my $value  = shift;

	if ($client->modeParam('midIsZero')) {
		$value -= getExtVal($client, 'mid');
	}

	if ($value > 0) {
		$value = int($value + 0.5);
	} else {
		$value = int($value);
	}

	my $unit = $client->modeParam('headerValueUnit');

	if (!defined $unit) {
		$unit = '';
	}
	
	return " ($value$unit)"	
}

sub changePos {
	my ($client, $dir, $funct) = @_;

	my $listRef   = $client->modeParam('listRef');
	my $listIndex = $client->modeParam('listIndex');
	my $valueRef  = $client->modeParam('valueRef');
	
	# Track intermediate change to value
	if ($client->modeParam('trackValueChanges') && $$valueRef != $listRef->[$listIndex]) {
		my $newIndex;
		for ($newIndex = 0; $newIndex < scalar(@$listRef); $newIndex++) {
			 if ($$valueRef <= $listRef->[$newIndex]) {
			 	$listIndex = $newIndex;
			 	last;
			 }
		}
	}

	if (($listIndex == 0 && $dir < 0) || ($listIndex == (scalar(@$listRef) - 1) && $dir > 0)) {

		# not wrapping and at end of list
		return;
	}
	
	my $accel = 8; # Hz/sec
	my $rate  = 50; # Hz
	my $mid   = getExtVal($client, 'mid') || 0;
	my $min   = getExtVal($client, 'min') || 0;
	my $max   = getExtVal($client, 'max') || 100;

	my $midpoint = ($mid-$min)/($max-$min)*(scalar(@$listRef) - 1);

	if (Slim::Hardware::IR::holdTime($client) > 0) {

		$dir *= Slim::Hardware::IR::repeatCount($client, $rate, $accel);
	}

	my $currVal     = $listIndex;
	my $newposition = undef;
	
	my $knobData = $client->knobData;
	
	if ($knobData->{'_knobEvent'}) {
		# Knob event
		my $knobAccelerationConstant = undef;
		#
		# TODO make down and up parameterized so that 
		# we can have different speeds for different controls.  
		# I.e. volume should go down faster than up, but bass and treble should 
		# be the same in both cases.
		# 
		if ($dir > 0) {
			$knobAccelerationConstant = $client->modeParam('knobaccelup') || .05; # Accel going up.
		} else {
			$knobAccelerationConstant = $client->modeParam('knobacceldown') ||.05; # Accel going down. 
		}
		my $velocity      = $knobData->{'_velocity'};
		my $acceleration  = $knobData->{'_acceleration'};
		my $deltatime     = $knobData->{'_deltatime'};
		my $deltaX = $velocity * $knobAccelerationConstant;
		if ($deltaX > 0) {
			if ($deltaX < 1) {
				$deltaX = 1;
			}
		} elsif ($deltaX < 0) {
			if ($deltaX > -1) {
				$deltaX = -1;
			}
		} else {
			# deltaX == 0, follow the dir.
			$deltaX = $dir;
		}
		$deltaX = int($deltaX);
		$newposition = $listIndex + $deltaX;
		
	} else {
		# Not _knobEvent (i.e. regular button event.);
		$newposition = $listIndex + $dir;
	}
	
	
	if ($dir > 0) {

		if ($currVal < ($midpoint - .5) && ($currVal + $dir) >= ($midpoint - .5)) {

			# make the midpoint sticky by resetting the start of the hold
			$newposition = $midpoint;
			Slim::Hardware::IR::resetHoldStart($client);
		}

	} else {

		if ($currVal > ($midpoint + .5) && ($currVal + $dir) <= ($midpoint + .5)) {

			# make the midpoint sticky by resetting the start of the hold
			$newposition = $midpoint;
			Slim::Hardware::IR::resetHoldStart($client);
		}
	}

	$newposition = scalar(@$listRef) -1 if $newposition > scalar(@$listRef) -1;
	$newposition = 0 if $newposition < 0;

	$$valueRef   = $listRef->[$newposition];
	
	my $val;
	if ($dir > 0) {
		$val = '+'.abs($listRef->[$newposition] - $listRef->[$listIndex]);
	} else {
		$val = '-'.abs($listRef->[$newposition] - $listRef->[$listIndex]);
	}

	$client->modeParam('listIndex', int($newposition));

	$client->updateKnob();

	my $onChange = $client->modeParam('onChange');

	if (ref($onChange) eq 'CODE') {

		my $onChangeArgs = $client->modeParam('onChangeArgs');
		my @args = ();

		push @args, $client if $onChangeArgs =~ /c/i;
		push @args, $val if $onChangeArgs =~ /v/i;

		$onChange->(@args);
	}

	# update the screen on a callback so we can rate limit the number of screen updates
	if (!$client->updatePending) {

		$client->updatePending(1);

		Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + UPDATE_DELAY, \&_updateScreen);
	}
}

sub _updateScreen {
	my $client = shift;

	$client->update;

	$client->updatePending(0);
}

sub lines {
	my $client = shift;
	my $args   = shift;

	# These parameters are used when calling this function from Slim::Player::Player::mixerDisplay
	my $value  = $args->{'value'};
	my $header = $args->{'header'};
	my $min    = $args->{'min'};
	my $mid    = $args->{'mid'};
	my $max    = $args->{'max'};
	my $noOverlay = $args->{'noOverlay'} || 0;

	my $line1;

	my $valueRef = $client->modeParam('valueRef');

	if (defined $value) {
		$valueRef = \$value;
	}

	my $listIndex = $client->modeParam('listIndex');

	if (defined $header) {

		$line1 = $header;

	} else {

		$line1 = Slim::Buttons::Input::List::getExtVal($client, $$valueRef, $listIndex, 'header');

		if ($client->modeParam('stringHeader') && Slim::Utils::Strings::stringExists($line1)) {

			$line1 = $client->string($line1);
		}

		if (ref $client->modeParam('headerValue') eq "CODE") {

			$line1 .= Slim::Buttons::Input::List::getExtVal($client, $$valueRef, $listIndex, 'headerValue');
		}
	}
	
	$min = getExtVal($client, 'min') || 0 unless defined $min;
	$mid = getExtVal($client, 'mid') || 0 unless defined $mid;
	$max = getExtVal($client, 'max') || 100 unless defined $max;
	
	my $cursor = $client->modeParam('cursor');
	if (defined($cursor)) {
		$cursor = $max == $min ? 0 : int(($cursor - $min)*100/($max-$min));
	}

	my $val = $max == $min ? 0 : int(($$valueRef - $min)*100/($max-$min));
	my $fullstep = 1 unless $client->modeParam('smoothing');

	my $parts = {};

	my $singleLine = ($client->linesPerScreen() == 1);

	unless ($noOverlay) {

		my ($overlay1, $overlay2) = Slim::Buttons::Input::List::getExtVal($client, $valueRef, $listIndex, 'overlayRef');

		$parts->{overlay} = $singleLine ? [ undef, $overlay1 ] : [ $overlay1, $overlay2 ];
	}

	if ($client->display->can('simpleSliderBar') && !$singleLine && $mid == 0 && !defined $cursor) {

		# optimised case - use fast simpleSliderBar which produces a bitmap
		$parts->{bits} = $client->display->simpleSliderBar($client->displayWidth, $val, 1);
		$parts->{line} = [ $line1, undef ];

	} elsif ($singleLine && !$client->modeParam('barOnDouble')) {

		$parts->{line} = [ undef, $line1 ];

	} else {

		$parts->{line} = [
			$line1,
			$client->sliderBar($client->displayWidth(), $val,$max == $min ? 0 :($mid-$min)/($max-$min)*100,$fullstep,0,$cursor),
		];
	}

	return $parts;
}

sub getFunctions {
	return \%functions;
}

sub setMode {
	my $client = shift;

	#my $setMethod = shift;

	#possibly skip the init if we are popping back to this mode
	#if ($setMethod ne 'pop') {

		if (!init($client)) {
			Slim::Buttons::Common::popModeRight($client);
		}
	#}

	$client->updatePending(0);

	$client->lines( $client->modeParam('lines') || \&lines );
}

sub _leaveModeHandler {
	my ($client, $exittype) = @_;

	Slim::Utils::Timers::killTimers($client, \&_updateScreen);
	$client->updatePending(0);
	
	if ($exittype eq 'pop') {
		return;	# to avoid recursion
	}
	
	if (defined $client->modeParam('handleLeaveMode')) {
		exitInput($client, $exittype);
	}
}

sub exitInput {
	my ($client, $exitType) = @_;

	my $callbackFunct = $client->modeParam('callback');

	if (!defined($callbackFunct) || !(ref($callbackFunct) eq 'CODE')) {

		if ($exitType eq 'right') {

			$client->bumpRight();

		} elsif ($exitType eq 'left') {

			Slim::Buttons::Common::popModeRight($client);

		} elsif ($exitType eq 'passback') {

			Slim::Buttons::Common::popMode($client);
			Slim::Hardware::IR::executeButton($client, $client->lastirbutton, $client->lastirtime, Slim::Buttons::Common::mode($client));

		} else {

			Slim::Buttons::Common::popMode($client);
		}

		return;
	}

	$callbackFunct->(@_);

	if ($exitType eq 'passback') {
		Slim::Hardware::IR::executeButton($client, $client->lastirbutton, $client->lastirtime, Slim::Buttons::Common::mode($client));
	}
}

sub getExtVal {
	my $client = shift;
	my $value  = shift;

	if (ref $client->modeParam($value) eq 'CODE') {

		my $ret = eval { $client->modeParam($value)->($client) };

		if ($@) {

			logError("Couldn't run coderef. [$@]");
			return '';
		}

		return $ret;

	} else {

		return $client->modeParam($value);
	}
}

=head1 SEE ALSO

L<Slim::Buttons::Common>

L<Slim::Buttons::Settings>

=cut

1;
