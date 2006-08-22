package Slim::Buttons::Input::Bar;

# $Id$

# SlimServer Copyright (c) 2001-2006 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use Slim::Buttons::Common;
use Slim::Display::Display;
use Slim::Utils::Misc;

my %functions = ();

# XXXX - This should this be in init() - but we don't init Input methods
# before trying to use them.
Slim::Buttons::Common::addMode('INPUT.Bar', getFunctions(), \&setMode);

# set unsupplied parameters to the defaults
# header = '' # message displayed on top line, can be a scalar, a code ref,
# or an array ref to a list of scalars or code refs
#
# headerArgs = CV
# stringHeader = undef # if true, put the value of header through the string function
# before displaying it.
#
# headerValue = undef
# 	set to 'scaled' to show the current value modified by the increment in parentheses
#	set to 'unscaled' to show the current value in parentheses
# 	set to a codeRef which returns a string to be shown after the standard header
#
# headerValueArgs = CV
# headerValueUnit = '' # Set to a units symbol to be displayed before the closing paren
# valueRef =  # reference to value to be selected
# callback = undef # function to call to exit mode
# overlayRef = undef
# overlayRefArgs = CV
# onChange = undef
# onChangeArgs = CV
# min = 0 # minimum value for slider scale
# max = 100 #maximum value for slider scale
# mid = 0 # midpoint value for marking the division point for a balance bar.
# midIsZero = 1 # set to 0 if you don't want the mid value to be interpreted as zero
# increment = 2.5 # step value for each bar character or button press.
# barOnDouble = 0 # set to 1 if the bar is preferred when using large text.
# smoothing = 0 # set to 1 if you want the character display to use custom chars to smooth the movement of the bar.

sub init {
	my $client = shift;

	if (!defined($client->param('parentMode'))) {

		my $i = -2;

		while ($client->modeStack->[$i] =~ /^INPUT\./) {
			$i--;
		}

		$client->param('parentMode', $client->modeStack->[$i]);
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
	);

	# Set our defaults for this mode.
	for my $name (keys %initValues) {

		if (!defined $client->param($name)) {

			$client->param($name, $initValues{$name});
		}
	}
	
	my $min = $client->param('min');
	my $mid = $client->param('mid');
	my $max = $client->param('max');
	my $step = $client->param('increment');

	my $listRef = [];
	my $j = 0;

	for (my $i = $min; $i <= $max; $i = $i + $step) {

		$listRef->[$j] = $i;
		$j++;
	}

	$client->param('listRef', $listRef);

	my $listIndex = $client->param('listIndex');
	my $valueRef  = $client->param('valueRef');

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
		$client->param('valueRef', $valueRef);

	} elsif (!ref($valueRef)) {

		my $value = $valueRef;
		$valueRef = \$value;

		$client->param('valueRef', $valueRef);
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

	$client->param('listIndex', $listIndex);

	my $headerValue = lc($client->param('headerValue') || '');

	if ($headerValue eq 'scaled') {

		$client->param('headerValue',\&scaledValue);

	} elsif ($headerValue eq 'unscaled') {

		$client->param('headerValue',\&unscaledValue);
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
			my $listIndex = $client->param('listIndex');
			
			$::d_ui && msg("got a knob event for the bar: knobpos: $knobPos listindex: $listIndex\n");

			changePos($client, $knobPos - $listIndex, $funct);

			$::d_ui && msgf("new listindex: %d\n", $client->param('listIndex'));
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

			my $parentMode = $client->param('parentMode');

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

	if ($client->param('midIsZero')) {
		$value -= $client->param('mid');
	}

	my $increment = $client->param('increment');

	$value /= $increment if $increment;
	$value = int($value + 0.5);

	my $unit = $client->param('headerValueUnit');

	if (!defined $unit) {
		$unit = '';
	}

	return " ($value$unit)"	
}

sub unscaledValue {
	my $client = shift;
	my $value  = shift;

	if ($client->param('midIsZero')) {
		$value -= $client->param('mid');
	}

	$value = int($value + 0.5);

	my $unit = $client->param('headerValueUnit');

	if (!defined $unit) {
		$unit = '';
	}
	
	return " ($value$unit)"	
}

sub changePos {
	my ($client, $dir, $funct) = @_;

	my $listRef   = $client->param('listRef');
	my $listIndex = $client->param('listIndex');

	if (($listIndex == 0 && $dir < 0) || ($listIndex == (scalar(@$listRef) - 1) && $dir > 0)) {

		# not wrapping and at end of list
		return;
	}
	
	my $accel = 8; # Hz/sec
	my $rate  = 50; # Hz
	my $mid   = $client->param('mid')||0;
	my $min   = $client->param('min')||0;
	my $max   = $client->param('max')||100;

	my $midpoint = ($mid-$min)/($max-$min)*(scalar(@$listRef) - 1);

	if (Slim::Hardware::IR::holdTime($client) > 0) {

		$dir *= Slim::Hardware::IR::repeatCount($client, $rate, $accel);
	}

	my $currVal     = $listIndex;
	my $newposition = $listIndex + $dir;

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

	my $valueRef = $client->param('valueRef');
	$$valueRef   = $listRef->[$newposition];

	$client->param('listIndex', int($newposition));

	my $onChange = $client->param('onChange');

	if (ref($onChange) eq 'CODE') {

		my $onChangeArgs = $client->param('onChangeArgs');
		my @args = ();

		push @args, $client if $onChangeArgs =~ /c/i;
		push @args, $$valueRef if $onChangeArgs =~ /v/i;

		$onChange->(@args);
	}

	$client->update;
}

sub lines {
	my $client = shift;

	# These parameters are used when calling this function from Slim::Display::Display
	my $value  = shift;
	my $header = shift;
	my $args   = shift;

	my $min = $args->{'min'};
	my $mid = $args->{'mid'};
	my $max = $args->{'max'};
	my $noOverlay = $args->{'noOverlay'} || 0;

	my ($line1, $line2);

	my $valueRef = $client->param('valueRef');

	if (defined $value) {
		$valueRef = \$value;
	}

	my $listIndex = $client->param('listIndex');

	if (defined $header) {

		$line1 = $header;

	} else {

		$line1 = Slim::Buttons::Input::List::getExtVal($client, $$valueRef, $listIndex, 'header');

		if ($client->param('stringHeader') && Slim::Utils::Strings::stringExists($line1)) {

			$line1 = $client->string($line1);
		}

		if (ref $client->param('headerValue') eq "CODE") {

			$line1 .= Slim::Buttons::Input::List::getExtVal($client, $$valueRef, $listIndex, 'headerValue');
		}
	}
	
	$min = $client->param('min') || 0 unless defined $min;
	$mid = $client->param('mid') || 0 unless defined $mid;
	$max = $client->param('max') || 100 unless defined $max;

	my $val = $max == $min ? 0 : int(($$valueRef - $min)*100/($max-$min));
	my $fullstep = 1 unless $client->param('smoothing');

	$line2 = $client->sliderBar($client->displayWidth(), $val,$max == $min ? 0 :($mid-$min)/($max-$min)*100,$fullstep);

	if ($client->linesPerScreen() == 1) {

		if ($client->param('barOnDouble')) {

			$line1 = $line2;
			$line2 = '';

		} else {

			$line2 = $line1;
		}
	}

	my @overlay = $noOverlay ? undef : Slim::Buttons::Input::List::getExtVal($client, $valueRef, $listIndex, 'overlayRef');

	return ($line1, $line2, @overlay);
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

	$client->lines(\&lines);
}

sub exitInput {
	my ($client, $exitType) = @_;

	my $callbackFunct = $client->param('callback');

	if (!defined($callbackFunct) || !(ref($callbackFunct) eq 'CODE')) {

		if ($exitType eq 'right') {

			$client->bumpRight();

		} elsif ($exitType eq 'left') {

			Slim::Buttons::Common::popModeRight($client);

		} else {

			Slim::Buttons::Common::popMode($client);
		}

		return;
	}

	$callbackFunct->(@_);
}

1;
