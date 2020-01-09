package Slim::Buttons::Input::Time;


# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

=head1 NAME

Slim::Buttons::Input::Time

=head1 SYNOPSIS

my %params = (
  'header'       => 'ALARM_SET',
  'stringHeader' => 1,
  'initialValue' => sub { return $_[0]->prefGet("alarmtime", weekDay($_[0])) },
  'cursorPos'    => 0,
  'callback'     => \&exitSetHandler,
  'onChange'     => sub { $_[0]->prefSet('alarmtime', $_[1], weekDay($_[0])) },
  'onChangeArgs' => 'CV',
);

my $value = $nextParams{'initialValue'}->($client);

$params{'valueRef'} = \$value;

Slim::Buttons::Common::pushMode($client, 'INPUT.Time', \%params);

=head1 DESCRIPTION

L<Slim::Buttons::Input::Time> is a reusable Logitech Media Server module to create a standard UI
for entering Time formatted strings.  This is a slimmed down variation of Input::Text 
with custom handling for limiting characters based on the timeFormat server preference
and typical formatting of time strings. Callers include Slim::Buttons::AlarmCLock

=cut

use strict;

use Slim::Buttons::Common;
use Slim::Utils::DateTime;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;

my $prefs = preferences('server');

Slim::Buttons::Common::addMode('INPUT.Time',getFunctions(),\&setMode);

our %functions = (
	# change character at cursorPos (both up and down)
	'up' => sub {
			my ($client,$funct,$functarg) = @_;

			scroll($client,1);
		}

	,'down' => sub {
			my ($client,$funct,$functarg) = @_;

			scroll($client,-1);
		}

	,'knob' => sub {
			#warn 'knob';
			my ($client,$funct,$functarg) = @_;

			my @timedigits = Slim::Utils::DateTime::splitTime($client->modeParam('valueRef'), 0, $client);
			# Manually set the am/pm bit
			$timedigits[2] = $timedigits[0] > 11 ? 1 : 0;

			# Don't scroll if on right arrow
			if (defined $timedigits[$client->modeParam('cursorPos')]) {
				scroll($client, $client->knobPos() - $timedigits[$client->modeParam('cursorPos')]);
			}
		}

	# move one position to the left, exiting on leftmost position
	,'left' => sub {
			my ($client,$funct,$functarg) = @_;

			moveCursor($client,-1);
		}

	# advance to next character, exiting if last char is right arrow
	,'right' => sub {
			my ($client,$funct,$functarg) = @_;

			moveCursor($client,1);
		}
	# move cursor left/right, exiting at edges
	,'cursor' => sub {
			my ($client,$funct,$functarg) = @_;

			my $increment = $functarg =~ m/_(\d+)$/;
			$increment = $increment || 1;

			if ($functarg =~ m/^left/i) {
				$increment = -$increment;
			}

			moveCursor($client,$increment);
		}

	# use numbers to enter ... er... numbers ;-)
	,'numberLetter' => \&numberButton

	# call callback procedure
	,'exit' => sub {
			my ($client,$funct,$functarg) = @_;

			if (!defined($functarg) || $functarg eq '') {
				$functarg = 'exit'
			}

			exitInput($client,$functarg);
		}

	,'passback' => sub {
			my ($client,$funct,$functarg) = @_;
			my $parentMode = $client->modeParam('parentMode');

			if (defined($parentMode)) {
				Slim::Hardware::IR::executeButton($client,$client->lastirbutton,$client->lastirtime,$parentMode);
			}
		}
);

sub lines {
	my $client = shift;
	
	my ($line1, $line2);
	
	$line1 = $client->modeParam('header');

	if ($client->modeParam('stringHeader') && Slim::Utils::Strings::stringExists($line1)) {
		$line1 = $client->string($line1);
	}
	
	my $timestring = timeString($client, 
		Slim::Utils::DateTime::timeDigits($client->modeParam('valueRef'), $client)
	);
	
	if (!defined($timestring)) {

		return {};
	}

	$line2 = $timestring;
	
	return {
		'line' => [ $line1, $line2 ]
	};
}

sub getFunctions {
	return \%functions;
}

sub setMode {
	my $client = shift;
	
	#my $setMethod = shift;
	#possibly skip the init if we are popping back to this mode
	if (!init($client)) {
		Slim::Buttons::Common::popModeRight($client);
	}

	$client->lines(\&lines);

	prepKnob($client, 1);
}

=head1 METHODS

=head2 init( $client)

This function sets up the params for INPUT.Time.  The optional params and their defaults are:

 'header'       = 'Enter Time:'   # message displayed on top line
 'valueRef'     = \""             # string to be edited
 'cursorPos'    = 0		 # position within string actively being edited
 'callback'     = undef           # function to call to exit mode
 'parentMode'   = $client->modeStack->[-2]
				 mode to which to pass button presses mapped to the passback function
				 defaults to the first non-INPUT mode in or before second to last position on call stack (which should be the mode that called INPUT.Time), 
 'onChange'     = undef           # subroutine reference called when the value changes
 'onChangeArgs' = CV              # arguments provided to onChange subroutine, C= client object, V= current value

=cut

sub init {
	my $client = shift;
	
	if (!defined($client->modeParam('parentMode'))) {
		my $i = -2;

		while ($client->modeStack->[$i] =~ /^INPUT./) { $i--; }
		$client->modeParam('parentMode',$client->modeStack->[$i]);
	}

	if (!defined($client->modeParam('header'))) {
		$client->modeParam('header','Enter Time:');
	}

	if (!defined($client->modeParam('cursorPos'))) {
		$client->modeParam('cursorPos',0)
	}

	if (!defined($client->modeParam('onChangeArgs'))) {
		$client->modeParam('onChangeArgs','CV');
	}
	
	my $valueRef = $client->modeParam('valueRef');

	if (!defined($valueRef)) {
		$$valueRef = '';
		$client->modeParam('valueRef',$valueRef);

	} elsif (!ref($valueRef)) {
		my $value = $valueRef;

		$valueRef = \$value;
		$client->modeParam('valueRef',$valueRef);
	}

	return 1;
}

=head2 timeString( $client, $h0, $h1, $m0, $m1, $p, $c)

This function converts the discrete time digits into a time string for use with a player display hash.

Takes as arguments, the hour ($h0, $h1), minute ($m0, $m1) and whether time is am or pm if applicable ($p)

$c is the current cursor position for rendering in the display - set to -1 to not display a cursor

=cut

sub timeString {
	my ($client, $h0, $h1, $m0, $m1, $p, $c) = @_;
		
	my $cs = $client->symbols('cursorpos');

	$c = $c || $client->modeParam('cursorPos') || 0;

	my $timestring =
		($h0 == 0 && defined($p) ? '' : $h0) .
		($c == 0 ? $cs : '') .  $h1 .  ':' .
		$m0 .
		($c == 1 ? $cs : '') . $m1;

	# Add am/pm
	if (defined($p)) {
		if ($c == 2) {
			# Put the cursor before 2nd char of $p
			my @ampm = split(//, $p);
			$timestring .= ' ' . shift(@ampm) . $cs . shift(@ampm);
			
		} else {
			$timestring .= ' ' . $p;
		}
	}
		
	# Add right arrow if cursor is in last position
	if ($c == 2 && ! defined($p) || $c == 3) {
		$timestring .= $client->symbols('rightarrow');
	}

	return ($timestring);
}

sub exitInput {
	my ($client,$exitType) = @_;
	
	my $callbackFunct = $client->modeParam('callback');
	
	if (!defined($callbackFunct) || !(ref($callbackFunct) eq 'CODE')) {
		Slim::Buttons::Common::popMode($client);
		$client->update();
		return;
	}

	$callbackFunct->(@_);

	return;
}

# Call the requested onChange function
sub callOnChange {
	#warn 'onChange';
	my $client = shift;

	my $onChange = $client->modeParam('onChange');
	
	if (ref($onChange) eq 'CODE') {
		my $onChangeArgs = $client->modeParam('onChangeArgs');
		my @args;

		push @args, $client if $onChangeArgs =~ /c/i;
		if ($onChangeArgs =~ /v/i) {
			my $valueRef = $client->modeParam('valueRef');
			push @args, $$valueRef;
		}
		$onChange->(@args);
	}
}

sub nextChar {
	my $client = shift;
	my $increment = shift || +1;

	$client->lastLetterTime(0);
	$client->lastLetterDigit('');
	moveCursor($client, $increment);
	callOnChange($client);
}

sub moveCursor {
	my $client = shift;
	my $increment = shift || 1;
	
	my $cursorPos = $client->modeParam('cursorPos');

	$cursorPos += $increment;

	if ($cursorPos < 0) {
		$cursorPos = 0;

		if ($client->modeParam('cursorPos') == 0) {
			exitInput($client,'left');
			return;
		}
	}

	my $charIndex;

	if ($cursorPos > (Slim::Utils::DateTime::hasAmPm($client) ? 3 : 2)) {
		exitInput($client,'right');
		return;
	}

	$client->modeParam('cursorPos',$cursorPos);
	$client->update();
	
	prepKnob($client, 1);
}

sub scroll {
	my ($client, $dir) = @_;
	
	my $ampm = Slim::Utils::DateTime::hasAmPm($client);
	my $c = $client->modeParam('cursorPos');
	# Don't scroll on the right arrow
	return if ($ampm && $c == 3 || ! $ampm && $c == 2);

	my $valueRef = $client->modeParam('valueRef');
	my $oldTime = $$valueRef;
	my $time = scrollTime($client,$dir);

	return if $time == $oldTime;

	callOnChange($client);

	prepKnob($client, 0);

	$client->update();
}

=head2 prepKnob( $client, $digits )

This function is required for updating the Transporter knob.  The knob extents are based on the listLen param, 
which changes in this mode depending on which column of the time display is being adjusted.

Takes as arguments, the $client structure and whether the knob is now scrolling through a diferent list. 

=cut

sub prepKnob {
	my ($client, $newList) = @_;

	my ($h, $m) = Slim::Utils::DateTime::splitTime($client->modeParam('valueRef'), 0, $client);
	
	my $c = $client->modeParam('cursorPos');

	my $ampm = Slim::Utils::DateTime::hasAmPm($client);
	
	if ($c == 0) {
		$client->modeParam('listLen', 24);
		$client->modeParam('listIndex', $h);

	} elsif ($c == 1) {
		$client->modeParam('listLen', 60);
		$client->modeParam('listIndex', $m);

	} elsif ($c == 2 && $ampm) { 
		my $p = $h > 11 ? 1 : 0;
		$client->modeParam('listLen', 2);
		$client->modeParam('listIndex', $p);
	} else {
		# Right arrow
		$client->modeParam('listLen', 1);
		$client->modeParam('listIndex', 0);
	}

	$client->updateKnob($newList);
}

=head2 scrollTime( $client,$dir,$valueRef,$c)

Specialized scroll routine similar to Slim::Buttons::Common::scroll, but made specifically to handle the nature of 
a formatted time string. Handles invalid values in time ranges gracefully when digits wrap.

Takes the $client object as the first argument.

$dir specifies the direction to scroll. 
$valueRef is a reference to the scalar time value.
$c specifies the current cursor position at which the digit should be scrolled.

=cut

sub scrollTime {
	my ($client,$dir,$valueRef,$c) = @_;
	
	$c = $client->modeParam('cursorPos') unless defined $c;
	
	if (defined $valueRef) {

		if (!ref $valueRef) {
			my $value = $valueRef;
			$valueRef = \$value;
		}

	} else {

		$valueRef = $client->modeParam('valueRef');
	}
	
	my ($h, $m) = Slim::Utils::DateTime::splitTime($valueRef, 0, $client);

	my $ampm = Slim::Utils::DateTime::hasAmPm($client);

	if ($c == 0) {
		# Scrolling is done in 24h mode regardless of 12h preference as in 12h mode it goes from 12am through to 11pm
		$h = Slim::Buttons::Common::scroll($client, $dir, 24, $h);
	} elsif ($c == 1) { 
		$m = Slim::Buttons::Common::scroll($client, $dir, 60, $m);
	# 2 is the right arrow unless we're using 12 hour clock
	} elsif ($ampm && $c == 2) { 
		# Scrolling on am/pm simply alters the hour value by +-12
		my $p = $h > 11 ? 1 : 0;
		
		my $newp = Slim::Buttons::Common::scroll($client, $dir, 2, $p);
		
		# Bug 12756: recalculate the hours if $p has changed.
		if ($p != $newp) {
			$h = ($h + ($p ? 12 : -12)) % 24;
		}
	}

	$$valueRef = Slim::Utils::DateTime::hourMinToTime($h, $m);
	
	return $$valueRef;
}

=head2 numberButton ( )

Handle times being entered using the number buttons.

=cut
sub numberButton {
	my ($client,$button,$digit) = @_;

	#warn "$button $digit";
	
	my $now = Time::HiRes::time();

	my $valueRef = $client->modeParam('valueRef');
	my ($h0, $h1, $m0, $m1, $p) = Slim::Utils::DateTime::timeDigits($valueRef, $client);

	my $ampm = defined $p;
	if ($ampm) {
		$p = $p eq 'PM' ? 1 : 0;
	}
	
	my $c = $client->modeParam('cursorPos');

	# Don't do anything if on the right arrow
	return if $c == 2 && ! $ampm || $c > 3;

	my $changed = 0;
	my $passOn = undef;

	if ($c == 0) {
		if ($client->lastLetterTime()) {
			#warn "2nd letter $digit";
			# Entering the 2nd digit of an already started number
			$h0 = $client->lastLetterDigit();
			my $maxDigit = 0;
			if ($h0 == 0) {
				$maxDigit = 10;
			} elsif ($h0 == 1) {
				$maxDigit = $ampm ? 3 : 10;
			} elsif ($h0 == 2) {
				$maxDigit = 4;
			}
			if ($digit < $maxDigit) {
				$h1 = $digit;
				$changed = 1;
			} else {
				# Ignore the digit for this position and pass it on to the next position
				$h1 = $h0;
				$h0 = 0;
				$passOn = $digit;
			}
			Slim::Utils::Timers::killOneTimer($client, \&nextChar);
			$client->lastLetterTime(0);
			$client->lastLetterDigit('');
			moveCursor($client, +1);
		} else {
			# First digit of new number
			#warn "1st letter $digit";
			if (! $ampm || $digit != 0) {
				$h0 = 0;
				$h1 = $digit;
				# Move on immediately if digit couldn't go in h0 slot
				if (($ampm && $digit > 1) || $digit > 2) {
					$changed = 1;
					moveCursor($client, +1);
				} else {
					$client->lastLetterTime($now);
					$client->lastLetterDigit($digit);
					Slim::Utils::Timers::setTimer($client,
						Time::HiRes::time() + preferences('server')->get('displaytexttimeout'),
						\&nextChar
					);
				}
			} else {
				# Ignore 0 key in 12h mode, but allow it to be used as a quick way of entering a single digit hour (e.g. 08) without having to press Right or waiting for the timeout.  If the timeout occurs before any other key is pressed, just pretend nothing happened.
				$client->lastLetterTime($now);
				$client->lastLetterDigit($digit);
				Slim::Utils::Timers::setTimer($client,
					Time::HiRes::time() + preferences('server')->get('displaytexttimeout'),
					sub {
						$client->lastLetterTime(0);
						$client->lastLetterDigit('');
					}
				);
			}
		}
	} elsif ($c == 1) {
		if ($client->lastLetterTime()) {
			#warn '2nd letter';
			# Entering the 2nd digit of an already started number
			$m0 = $client->lastLetterDigit();
			$m1 = $digit;
			$changed = 1;
			Slim::Utils::Timers::killOneTimer($client, \&nextChar);
			$client->lastLetterTime(0);
			$client->lastLetterDigit('');
			moveCursor($client, +1);
		} else {
			# First digit of new number
			#warn '1st letter';
			$m0 = 0;
			$m1 = $digit;
			# Move on immediately if digit couldn't go in m0 slot
			if ($digit > 5) {
				$changed = 1;
				moveCursor($client, +1);
			} else {
				$client->lastLetterTime($now);
				$client->lastLetterDigit($digit);
				Slim::Utils::Timers::setTimer($client,
					Time::HiRes::time() + preferences('server')->get('displaytexttimeout'),
					\&nextChar
				);
			}
		}
	} elsif ($c == 2 && $ampm) {
		# 2 for AM, 7 for PM (corresponding letter keys for A and P)
		if ($digit == 2 || $digit == 7) {
			$p = ($digit == 2 ? 0 : 1);
			$changed = 1;
			moveCursor($client, +1);
		}
	}

	$$valueRef = Slim::Utils::DateTime::timeDigitsToTime($h0, $h1, $m0, $m1, $p);

	if ($changed) {
		callOnChange($client);
	}

	$client->update();
	if (defined $passOn) {
		numberButton($client, undef, $passOn);
	}
}

=head1 SEE ALSO

L<Slim::Buttons::Common>

L<Slim::Buttons::Alarm>

=cut

1;

__END__
