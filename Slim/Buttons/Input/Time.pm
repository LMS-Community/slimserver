package Slim::Buttons::Input::Time;

# $Id$

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

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

			my $h = $h0 * 10 + $h1;
			if ($p && $h == 12) { $h = 0 };
	
			my $c = $client->param('cursorPos');
			if ($c == 0 && $digit < ($p ? 2:3)) { $h0 = $digit; nextChar($client); };
			if ($c == 1 && (($h0 * 10 + $digit) < 24)) { $h1 = $digit; nextChar($client); };
			if ($c == 2) { $m0 = $digit; nextChar($client); };
			if ($c == 3) { $m1 = $digit };
	
			$p = (defined $p && $p eq 'PM') ? 1 : 0;
			if ($c == 4 && (Slim::Utils::Prefs::get('timeFormat') =~ /%p/)) { $p = $digit % 2; }
	
			my $time = ($h0 * 10 + $h1) * 60 * 60 + $m0 * 10 * 60 + $m1 * 60 + $p * 12 * 60 * 60;
			$client->param('valueRef',$time);
			
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
	my $valueRef = \&timeString($client,timeDigits($client,$client->param('valueRef')));
	if (!defined($valueRef)) { return ('',''); }
	$line2 = $$valueRef;
	return ($line1,$line2);
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
}

# set unsupplied parameters to the defaults
# header = 'Enter Text:' # message displayed on top line
# valueRef = \"" # string to be edited
# cursorPos = len($$valueRef) # position within string actively being edited
# callback = undef # function to call to exit mode
# parentMode = $client->modeStack->[-2]
	# mode to which to pass button presses mapped to the passback function
	# defaults to mode in second to last position on call stack (which is
	# the mode that called INPUT.Text)
# onChange = undef
# onChangeArgs = CV
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
	if (!defined($client->param('noScroll'))) {
		$client->param('noScroll',1)
	}
	if (!defined($client->param('cursorPos'))) {
		$client->param('cursorPos',1)
	}
	if (!defined($client->param('onChangeArgs'))) {
		$client->param('onChangeArgs','CV');
	}
	return 1;
}

sub timeDigits {
	my $client = shift;
	my $time = shift || 0;

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

sub timeString {
	my ($client, $h0, $h1, $m0, $m1, $p) = @_;
		
	my $cs = Slim::Display::Display::symbol('cursorpos');
	my $c = $client->param('cursorPos') || 0;
	
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
	
	my $valueRef = \&timeString($client,timeDigits($client,$client->param('valueRef')));
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
	return;
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

sub scrollTime {
	my ($client,$dir,$valueRef,$c) = @_;
	
	$c = $client->param('cursorPos') unless defined $c;
	$valueRef = $client->param('valueRef') unless defined $valueRef;
	
	my ($h0, $h1, $m0, $m1, $p) = timeDigits($client,$valueRef);
	my $h = $h0 * 10 + $h1;
	
	if ($c == 0) {$c++;};
	if ($p && $h == 12) { $h = 0 };
	
	$p = ($p && $p eq 'PM') ? 1 : 0;

	if ($c == 4 && (Slim::Utils::Prefs::get('timeFormat') =~ /%p/)) { $p = Slim::Buttons::Common::scroll($client, +1, 2, $p); }
	if ($c == 3) { 
		$m1 = Slim::Buttons::Common::scroll($client, $dir, 10, $m1);
		$c = ($m1 == 0 && $dir == 1)||($m1 == 9 && $dir == -1) ? $c -1 : $c;
	}
	if ($c == 2) { 
		$m0 = Slim::Buttons::Common::scroll($client, $dir, 6, $m0);
		$c = ($m0 == 0 && $dir == 1)||($m0 == 5 && $dir == -1) ? $c -1 : $c;
	}
	if ($c == 1) {
		$h = Slim::Buttons::Common::scroll($client, $dir, ($p == 1) ? 12 : 24, $h);
		#change AM and PM if we scroll past midnight or noon boundary
		if (Slim::Utils::Prefs::get('timeFormat') =~ /%p/) {
		if (($h == 0 && $dir == 1)||($h == 11 && $dir == -1)) { $p = Slim::Buttons::Common::scroll($client, +1, 2, $p); };
		};
	};

	my $time = $h * 60 * 60 + $m0 * 10 * 60 + $m1 * 60 + $p * 12 * 60 * 60;
	$client->param('valueRef',$time);
	
	return $time;
}

1;

__END__
