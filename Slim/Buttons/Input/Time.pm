package Slim::Buttons::Input::Time;

# $Id$

# SlimServer Copyright (c) 2001-2006 Sean Adams, Slim Devices Inc.
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

L<Slim::Buttons::Input::Time> is a reusable SlimServer module to create a standard UI
for entering Time formatted strings.  This is a slimmed down variation of Input::Text 
with custom handling for limting characters based on the timeFormat server preference
and typicall formatting of time strings. Callers include Sli::Buttons::AlarmCLock

=cut

use strict;

use Slim::Buttons::Common;
use Slim::Utils::Misc;
use Slim::Display::Display;

Slim::Buttons::Common::addMode('INPUT.Time',getFunctions(),\&setMode);

###########################
#Button mode specific junk#
###########################
our %functions = (
	#change character at cursorPos (both up and down)
	'up' => sub {
			my ($client,$funct,$functarg) = @_;

			scroll($client,1);
		}

	,'down' => sub {
			my ($client,$funct,$functarg) = @_;

			scroll($client,-1);
		}

	,'knob' => sub {
			my ($client,$funct,$functarg) = @_;

			my @timedigits = timeDigits($client, $client->param('valueRef'));

			scroll($client, $client->knobPos() - $timedigits[$client->param('cursorPos')]);
		}

	#moving one position to the left, exiting on leftmost position
	,'left' => sub {
			my ($client,$funct,$functarg) = @_;
			Slim::Utils::Timers::killTimers($client, \&nextChar);

			my $cursorPos = $client->param('cursorPos');
			$cursorPos--;

			if ($cursorPos < 0) {
				exitInput($client,'left');
				return;
			}

			$client->param('cursorPos',$cursorPos);
			$client->update();
		}

	#advance to next character, exiting if last char is right arrow
	,'right' => sub {
			my ($client,$funct,$functarg) = @_;

			Slim::Utils::Timers::killTimers($client, \&nextChar);
			moveCursor($client,1,1);
		}
	#move cursor left/right, exiting at edges
	,'cursor' => sub {
			my ($client,$funct,$functarg) = @_;
			Slim::Utils::Timers::killTimers($client, \&nextChar);

			my $increment = $functarg =~ m/_(\d+)$/;
			$increment = $increment || 1;

			if ($functarg =~ m/^left/i) {
				$increment = -$increment;
			}

			moveCursor($client,$increment,0);
		}

	#use numbers to enter characters
	,'numberLetter' => sub {
			my ($client,$button,$digit) = @_;
			
			Slim::Utils::Timers::killTimers($client, \&nextChar);
	
			# if it's a different number, then skip ahead
			if (Slim::Buttons::Common::testSkipNextNumberLetter($client, $digit)) {
				nextChar($client);
			}
			
			my $valueRef = $client->param('valueRef');
			my ($h0, $h1, $m0, $m1, $p) = timeDigits($client,$valueRef);

			$p = (defined $p && $p eq 'PM') ? 1 : 0;
			
			my $c = $client->param('cursorPos');

			my $ampm = (Slim::Utils::Prefs::get('timeFormat') =~ /%p/);

			my $max = 9;
			if ($c == 0) {

				$max = ($ampm ? 1 : 2);
				$h0 = $digit unless ($digit > $max);

				if ($ampm) {

					if ($h0 == 1 && $h1 > 2) {
						$h1 = 2;
					}

				} else {

					if ($h0 == 2 && $h1 > 3) {
						$h1 = 3;
					}
				}

			} elsif ($c == 1) {

				if ($ampm) {

					if ($h0 == 1) {
						$max = 2;
					}

				} else {

					if ($h0 == 2) {
						$max = 3;
					}
				}

				$h1 = $digit unless ($digit > $max);

			} elsif ($c == 2) {
				$m0 = $digit unless ($digit > 5);

			} elsif ($c == 3) {
				$m1 = $digit unless ($digit > 9);

			} elsif ($c == 4) {
				$p = $digit unless ($digit > 1);
			}
			
			if ($h0 == 0 && $h1 == 0 && $ampm) {
				$h1 = 1;
			}
			
			if ($ampm && $h0 && $h1 == 2) {

				if ($p) {
					$p = 0;

				} else {
					$h0 = 0; 
					$h1 = 0;
				}
			}
			
			$$valueRef = timeDigitsToTime($h0, $h1, $m0, $m1, $p);
	
			Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + Slim::Utils::Prefs::get("displaytexttimeout"), \&nextChar);
			
			#update the display
			my $onChange = $client->param('onChange');

			if (ref($onChange) eq 'CODE') {
				my $onChangeArgs = $client->param('onChangeArgs');
				my @args;

				push @args, $client if $onChangeArgs =~ /c/i;
				push @args, $$valueRef if $onChangeArgs =~ /v/i;
				$onChange->(@args);
			}
			
			$client->update();
		}

	#call callback procedure
	,'exit' => sub {
			my ($client,$funct,$functarg) = @_;

			Slim::Utils::Timers::killTimers($client, \&nextChar);

			if (!defined($functarg) || $functarg eq '') {
				$functarg = 'exit'
			}

			exitInput($client,$functarg);
		}

	,'passback' => sub {
			my ($client,$funct,$functarg) = @_;
			my $parentMode = $client->param('parentMode');

			if (defined($parentMode)) {
				Slim::Hardware::IR::executeButton($client,$client->lastirbutton,$client->lastirtime,$parentMode);
			}
		}
);

sub lines {
	my $client = shift;
	
	my ($line1, $line2);
	
	$line1 = $client->param('header');

	if ($client->param('stringHeader') && Slim::Utils::Strings::stringExists($line1)) {
		$line1 = $client->string($line1);
	}
	
	my $timestring = timeString($client,timeDigits($client,$client->param('valueRef')));
	
	if (!defined($timestring)) { return ( {} ); }
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

	# The knob on Transporter needs to be prepopulated with list lengths
	# for proper scrolling.
	my @timedigits = timeDigits($client, $client->param('valueRef'));

	prepKnob($client, \@timedigits);
}

=head1 METHODS

=head2 init( $client)

This function sets up the params for INPUT.Time.  The optional params and their defaults are:

 'header'       = 'Enter Time:'   # message displayed on top line
 'valueRef'     = \""             # string to be edited
 'cursorPos'    = len($$valueRef) # position within string actively being edited
 'callback'     = undef           # function to call to exit mode
 'parentMode'   = $client->modeStack->[-2]
				 mode to which to pass button presses mapped to the passback function
				 defaults to mode in second to last position on call stack (which is
				 the mode that called INPUT.Text)
 'onChange'     = undef           # subroutine reference called when the value changes
 'onChangeArgs' = CV              # arguments provided to onChange subroutine, C= client object, V= current value

=cut

sub init {
	my $client = shift;
	
	if (!defined($client->param('parentMode'))) {
		my $i = -2;

		while ($client->modeStack->[$i] =~ /^INPUT./) { $i--; }
		$client->param('parentMode',$client->modeStack->[$i]);
	}

	if (!defined($client->param('header'))) {
		$client->param('header','Enter Time:');
	}

	if (!defined($client->param('cursorPos'))) {
		$client->param('cursorPos',0)
	}

	if (!defined($client->param('onChangeArgs'))) {
		$client->param('onChangeArgs','CV');
	}
	
	my $valueRef = $client->param('valueRef');

	if (!defined($valueRef)) {
		$$valueRef = '';
		$client->param('valueRef',$valueRef);

	} elsif (!ref($valueRef)) {
		my $value = $valueRef;

		$valueRef = \$value;
		$client->param('valueRef',$valueRef);
	}

	return 1;
}

=head2 timeDigits( $client, $timeRef)

This function converts a unix time value to the individual values for hours, minutes and am/pm

Takes as arguments, the $client object/structure and a reference to the scalar time value.

=cut

sub timeDigits {
	my $client = shift;
	my $timeRef = shift;
	my $time;

	if (ref($timeRef))  {
		$time = $$timeRef || 0;

	} else {
		$time = $timeRef || 0;
	}

	my $h = int($time / (60*60));
	my $m = int(($time - $h * 60 * 60) / 60);
	my $p = undef;

	if (Slim::Utils::Prefs::get('timeFormat') =~ /%p/) {
		$p = 'AM';

		if ($h > 11) { $h -= 12; $p = 'PM'; }

		if ($h == 0) { $h = 12; }
	} #else { $p = " "; };

	if ($h < 10) { $h = '0' . $h; }

	if ($m < 10) { $m = '0' . $m; }

	my $h0 = substr($h, 0, 1);
	my $h1 = substr($h, 1, 1);
	my $m0 = substr($m, 0, 1);
	my $m1 = substr($m, 1, 1);

	return ($h0, $h1, $m0, $m1, $p);
}

=head2 timeDigitsToTime( $h0, $h1, $m0, $m1, $p)

This function converts discreet time digits into a scalar time value.  It is the reverse of timeDigits()

Takes as arguments, the hour ($h0, $h1), minute ($m0, $m1) and whether time is am or pm if applicable ($p)

=cut

sub timeDigitsToTime {
	my ($h0, $h1, $m0, $m1, $p) = @_;

	$p ||= 0;
	
	my $time = (((($p * 12)            # pm adds 12 hours
	         + ($h0 * 10) + $h1) * 60) # convert hours to minutes
	         + ($m0 * 10) + $m1) * 60; # then  minutes to seconds

	return $time;
}


=head2 timeString( $client, $h0, $h1, $m0, $m1, $p, $c)

This function converts the discrete time digits into a time string for use with a player display hash.

Takes as arguments, the hour ($h0, $h1), minute ($m0, $m1) and whether time is am or pm if applicable ($p)

$c is the current cursor position for redering in teh display

=cut

sub timeString {
	my ($client, $h0, $h1, $m0, $m1, $p, $c) = @_;
		
	my $cs = $client->symbols('cursorpos');

	$c = $c || $client->param('cursorPos') || 0;
	
	my $timestring = ($c == 0 ? $cs : '') . ((defined($p) && $h0 == 0) ? ' ' : $h0) . ($c == 1 ? $cs : '') . $h1 . ":" . ($c == 2 ? $cs : '') .  $m0 . ($c == 3 ? $cs : '') . $m1 . " " . ($c == 4 ? $cs : '') . (defined($p) ? $p : '');

	return ($timestring);
}

sub exitInput {
	my ($client,$exitType) = @_;
	
	my $callbackFunct = $client->param('callback');
	
	if (!defined($callbackFunct) || !(ref($callbackFunct) eq 'CODE')) {
		Slim::Buttons::Common::popMode($client);
		return;
	}

	$callbackFunct->(@_);

	return;
}

sub nextChar {
	my $client = shift;
	my $increment = shift || 1;
	
	moveCursor($client,$increment);
}

sub moveCursor {
	my $client = shift;
	my $increment = shift || 1;
	
	my $cursorPos = $client->param('cursorPos');

	$cursorPos += $increment;

	if ($cursorPos < 0) {
		$cursorPos = 0;

		if ($client->param('cursorPos') == 0) {
			exitInput($client,'left');
			return;
		}
	}

	my $charIndex;

	if ($cursorPos > ((Slim::Utils::Prefs::get('timeFormat') =~ /%p/) ? 4 : 3)) {
		exitInput($client,'right');
		return;
	}

	$client->param('cursorPos',$cursorPos);
	$client->update();
	
	prepKnob($client, [ timeDigits($client,$client->param('valueRef')) ]);
}

sub scroll {
	my ($client,$dir) = @_;
	
	my $time = scrollTime($client,$dir);
	my $onChange = $client->param('onChange');
	
	if (ref($onChange) eq 'CODE') {
		my $onChangeArgs = $client->param('onChangeArgs');
		my @args;

		push @args, $client if $onChangeArgs =~ /c/i;
		push @args, $time if $onChangeArgs =~ /v/i;
		$onChange->(@args);
	}

	$client->update();
}

=head2 prepKnob( $client, $client, $digits )

This function is required for updating the Transporter knob.  The knob extents are based on the listLen param, 
which changes in this mode depending on which column of the time display is being adjusted.

Takes as arguments, the $client structure and a reference to the array of discret digits returned by timeDigits.

=cut

sub prepKnob {
	my ($client, $digits) = @_;
	
	my $ampm = (Slim::Utils::Prefs::get('timeFormat') =~ /%p/);
	my $c    = $client->param('cursorPos');
	
	if ($c == 0) {
		$client->param('listLen', $ampm ? 2 : 3);

	} elsif ($c == 1) {
		$client->param('listLen', $ampm ? ($digits->[0] ? 3 : 10) : ($digits->[0] == 2 ? 4 : 10));

	} elsif ($c == 2) { 
		$client->param('listLen', 6);

	} elsif ($c == 3) { 
		$client->param('listLen', 10);

	} elsif ($c == 4) { 
		$client->param('listLen', 2);
	}

	$client->param('listIndex', $digits->[$c]);

	$client->updateKnob(1);
}

=head2 scrollTime( $client,$dir,$valueRef,$c)

Specialized scroll routine similar to Slim::Buttons::Common::scroll, but made specifically to handle the nature of 
a formatted time string. Handles invalid values in time ranges gracefully when digits wrap.

Takes the $client object as the first argument.

$dir specifies the direction to scroll. 
$valueRef is a reference to the scalar time value.
$c specifies the current cursor position where the digit is intended to scrol.

=cut

sub scrollTime {
	my ($client,$dir,$valueRef,$c) = @_;
	
	$c = $client->param('cursorPos') unless defined $c;
	
	if (defined $valueRef) {

		if (!ref $valueRef) {
			my $value = $valueRef;
			$valueRef = \$value;
		}

	} else {
		$valueRef = $client->param('valueRef');
	}
	
	my ($h0, $h1, $m0, $m1, $p) = timeDigits($client,$valueRef);

	my $ampm = (Slim::Utils::Prefs::get('timeFormat') =~ /%p/);
	
	$p = ($p && $p eq 'PM') ? 1 : 0;

	if ($c == 0) {
		$h0 = Slim::Buttons::Common::scroll($client, $dir, $ampm ? 2 : 3, $h0);
		
		if ($ampm) {
			if ($h0 == 0 && $h1 == 0) {
				$h1 = 1;
			}	
			
			if ($h0 && $h1 > 2) {
				$h1 = 0;
			}
		} else {

			if ($h0 == 2 && $h1 > 3) {
				$h1 = 0;
			}
		}
	} elsif ($c == 1) {
		my $max = $ampm ? ($h0 ? 3 : 10) : ($h0 == 2 ? 4 : 10);

		$h1 = Slim::Buttons::Common::scroll($client, $dir, $max, $h1);

		if ($ampm && $h1 == 0 && $h0 == 0) {
			$h1 = $dir > 0 ? 1 : ($max - 1);
		}

	} elsif ($c == 2) { 
		$m0 = Slim::Buttons::Common::scroll($client, $dir, 6, $m0);

	} elsif ($c == 3) { 
		$m1 = Slim::Buttons::Common::scroll($client, $dir, 10, $m1);

	} elsif ($c == 4) { 
		$p = Slim::Buttons::Common::scroll($client, +1, 2, $p);
	}

	if ($ampm && $h0 && $h1 == 2) {

		if ($p) {
			$p = 0;

		} else {
			$h0 = 0; 
			$h1 = 0;
		}
	}
	
	$$valueRef = timeDigitsToTime($h0, $h1, $m0, $m1, $p);
	
	return $$valueRef;
}

=head1 SEE ALSO

L<Slim::Buttons::Common>

L<Slim::Buttons::AlarmClock>

=cut

1;

__END__
