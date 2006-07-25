package Slim::Buttons::Input::Text;

# $Id$

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use Slim::Buttons::Common;
use Slim::Utils::Misc;

our $DOUBLEWIDTH = 10;
my $rightarrow = Slim::Display::Display::symbol('rightarrow');

our @numberLettersMixed = (
	[' ','0'], # 0
	['.',',',"'",'?','!','@','-','1'], # 1
	['a','b','c','A','B','C','2'], 	   # 2
	['d','e','f','D','E','F','3'], 	   # 3
	['g','h','i','G','H','I','4'], 	   # 4
	['j','k','l','J','K','L','5'], 	   # 5
	['m','n','o','M','N','O','6'], 	   # 6
	['p','q','r','s','P','Q','R','S','7'], 	# 7
	['t','u','v','T','U','V','8'], 		# 8
	['w','x','y','z','W','X','Y','Z','9']   # 9
);

our @numberLettersUpper = (
	[' ','0'],				# 0
	['.',',',"'",'?','!','@','-','1'],	# 1
	['A','B','C','2'], 			# 2
	['D','E','F','3'], 			# 3
	['G','H','I','4'], 			# 4
	['J','K','L','5'], 			# 5
	['M','N','O','6'], 			# 6
	['P','Q','R','S','7'], 			# 7
	['T','U','V','8'], 			# 8
	['W','X','Y','Z','9'],			# 9
);

our @UpperChars = (
	Slim::Display::Display::symbol('rightarrow'),
	'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
	'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
	' ',
	'.', ',', "'", '?', '!', '@', '-', '_', '#', '$', '%', '^', '&',
	'(', ')', '{', '}', '[', ']', '\\','|', ';', ':', '"', '<', '>',
	'*', '=', '+', '`', '/', 'ß', 
	'0', '1', '2', '3', '4', '5', '6', '7', '8', '9'
);

our @BothChars = (
	Slim::Display::Display::symbol('rightarrow'),
	'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm',
	'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z',
	'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
	'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
 	' ',
	'.', ',', "'", '?', '!', '@', '-', '_', '#', '$', '%', '^', '&',
	'(', ')', '{', '}', '[', ']', '\\','|', ';', ':', '"', '<', '>',
	'*', '=', '+', '`', '/', 'ß', 
	'0', '1', '2', '3', '4', '5', '6', '7', '8', '9'
);

Slim::Buttons::Common::addMode('INPUT.Text',getFunctions(),\&setMode);

###########################
#Button mode specific junk#
###########################
our %functions = (
	#change character at cursorPos (both up and down)
	'up' => sub {
			my ($client,$funct,$functarg) = @_;
			changeChar($client,-1);
		}
	,'down' => sub {
			my ($client,$funct,$functarg) = @_;
			changeChar($client,1);
		}
	,'knob' => sub {
			my ($client,$funct,$functarg) = @_;
			changeChar($client, $client->knobPos() - $client->param('listIndex'));
		}
	#delete current, moving one position to the left, exiting on leftmost position
	,'backspace' => sub {
			my ($client,$funct,$functarg) = @_;
			Slim::Utils::Timers::killTimers($client, \&nextChar);
			$client->lastLetterTime(0);
			my $valueRef = $client->param('valueRef');
			my $cursorPos = $client->param('cursorPos');
			Slim::Display::Display::subString($$valueRef,$cursorPos,1,'');
			$cursorPos--;
			if ($cursorPos < 0) {
				exitInput($client,'backspace');
				return;
			}
			checkCursorDisplay($client,$cursorPos);
			$client->param('cursorPos',$cursorPos);
			$client->param('listIndex',charIndex($client->param('charsRef'),Slim::Display::Display::subString($$valueRef,$cursorPos,1)));
			$client->update();
		}
	#delete current, staying in place, moving left if in the rightmost position
	#,exiting if string empty
	,'delete' => sub {
			my ($client,$funct,$functarg) = @_;
			Slim::Utils::Timers::killTimers($client, \&nextChar);
			my $valueRef = $client->param('valueRef');
			my $cursorPos = $client->param('cursorPos');
			Slim::Display::Display::subString($$valueRef,$cursorPos,1,'');
			if ($$valueRef eq '') {
				exitInput($client,'delete');
				return;
			}
			if ($cursorPos == Slim::Display::Display::lineLength($$valueRef)) { 
				$cursorPos--; 
				$client->param('cursorPos',$cursorPos);
			}
			checkCursorDisplay($client,$cursorPos);
			$client->param('listIndex',charIndex($client->param('charsRef'),Slim::Display::Display::subString($$valueRef,$cursorPos,1)));
			$client->update();
		}
	#advance to next character, exiting if last char is right arrow
	,'nextChar' => sub {
			my ($client,$funct,$functarg) = @_;
			Slim::Utils::Timers::killTimers($client, \&nextChar);
			#reset last letter time to reset the character cycling.
			$client->lastLetterTime(0);
			my $valueRef = $client->param('valueRef');
			my $cursorPos = $client->param('cursorPos');
			if (Slim::Display::Display::subString($$valueRef,$cursorPos,1) eq $rightarrow) {
				exitInput($client,'nextChar');
				return;
			}
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
	#scroll display window left/right
	,'scroll' => sub {
			my ($client,$funct,$functarg) = @_;
			Slim::Utils::Timers::killTimers($client, \&nextChar);
			if ($functarg eq 'full') {
				#do full scroll here
				return;
			}
			my $increment = $functarg =~ m/_(\d+)$/;
			$increment = $increment || 1;
			if ($functarg =~ m/^left/i) {
				$increment = -$increment;
			}
			my $displayPos = $client->param('displayPos');
			my $displayPos2X = $client->param('displayPos2X');
			if ($displayPos != $displayPos2X && ($client->linesPerScreen() == 1)) {
				$displayPos = $displayPos2X;
			}
			my $valueEnd = Slim::Display::Display::lineLength(${$client->param('valueRef')}) - 1;
			if ($displayPos == $valueEnd && $increment > 0) {
				exitInput($client,'scroll_right');
				return;
			} elsif ($displayPos == 0 && $increment < 0) {
				exitInput($client,'scroll_left');
				return;
			}
			$displayPos = scroll_noacc_nowrap($client,$increment,$valueEnd,$displayPos);
			if ($displayPos > $valueEnd) {
				$displayPos = $valueEnd;
			} elsif ($displayPos < 0) {
				$displayPos = 0;
			}
			$client->param('displayPos',$displayPos);
			$client->param('displayPos2X',$displayPos);
			$client->update();
		}
	#Insert char at current cursor position
	,'insert' => sub {
			my ($client,$funct,$functarg) = @_;
			Slim::Utils::Timers::killTimers($client, \&nextChar);
			my $char = validateChar($client,$functarg);
			if (!defined($char)) {
				my $charsRef = $client->param('charsRef');
				$char = $charsRef->[($client->param('rightIndex') == 0) ? 1 : 0];
			}
			my $valueRef = $client->param('valueRef');
			my $cursorPos = $client->param('cursorPos');
			checkCursorDisplay($client,$cursorPos);
			Slim::Display::Display::subString($$valueRef,$cursorPos,0,$char);
			$client->update();
		}
	#clear current text
	,'clear' => sub {
			my ($client,$funct,$functarg) = @_;
			Slim::Utils::Timers::killTimers($client, \&nextChar);
			my $charIndex = $client->param('rightIndex');
			$charIndex = ($charIndex == -1) ? 0 : $charIndex;
			my $valueRef = $client->param('valueRef');
			my $charsRef = $client->param('charsRef');
			$$valueRef = $charsRef->[$charIndex];
			$client->param('listIndex',$charIndex);
			$client->param('cursorPos',0);
			$client->param('displayPos',0);
			$client->param('displayPos2X',0);
			$client->update();
		}
	#use numbers to enter characters
	,'numberLetter' => sub {
			my ($client,$funct,$functarg) = @_;
			Slim::Utils::Timers::killTimers($client, \&nextChar);
			# if it's a different number, then skip ahead
			if (Slim::Buttons::Common::testSkipNextNumberLetter($client, $functarg)) {
				nextChar($client);
			}
			my $char = validateChar($client,Slim::Buttons::Common::numberLetter($client, $functarg, $client->param('numberLetterRef')));
			my $valueRef = $client->param('valueRef');
			my $cursorPos = $client->param('cursorPos');
			Slim::Display::Display::subString($$valueRef,$cursorPos,1,$char);
			my $charIndex = charIndex($client->param('charsRef'),Slim::Display::Display::subString($$valueRef,$cursorPos));
			$client->param('listIndex',$charIndex);
			# set up a timer to automatically skip ahead
			Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + Slim::Utils::Prefs::get("displaytexttimeout"), \&nextChar);
			#update the display
			$client->update();
		}
	#use characters to enter characters
	,'letter' => sub {
			my ($client,$funct,$functarg) = @_;
			Slim::Utils::Timers::killTimers($client, \&nextChar);
			my $char = validateChar($client,$functarg);
			return unless defined($char);
			my $valueRef = $client->param('valueRef');
			my $cursorPos = $client->param('cursorPos');
			Slim::Display::Display::subString($$valueRef,$cursorPos,1,$char);
			nextChar($client);
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

	my $line1 = Slim::Buttons::Input::List::getExtVal($client,undef,undef,'header');
	my $line2;

	if ($client->param('stringHeader') && Slim::Utils::Strings::stringExists($line1)) {
		$line1 = $client->string($line1);
	}

	my $valueRef  = $client->param('valueRef') || return ('','');
	my $cursorPos = $client->param('cursorPos');

	my $displayPos;

	if (!($client->linesPerScreen() == 1)) {
		$displayPos = $client->param('displayPos');
	} else {

		$displayPos = $client->param('displayPos2X');

		if (my $doublereplaceref = $client->param('doublesizeReplace')) {

			while (my ($find, $replace) = each %$doublereplaceref) {

				$line2 =~ s/$find/$replace/g;
			}
		}
	}
	
	$line2 = Slim::Display::Display::subString($$valueRef,$displayPos,$client->displayWidth);
	
	my $end = $client->measureText(Slim::Display::Display::subString($line2,0,$cursorPos-$displayPos),2);

	if ($displayPos <= $cursorPos && ($end < $client->displayWidth)) {
		Slim::Display::Display::subString($line2,$cursorPos - $displayPos,0,Slim::Display::Display::symbol('cursorpos'));
	}

	return ($line1, $line2);
}

sub getFunctions {
	return \%functions;
}

sub setMode {
	my $client = shift;
	#my $setMethod = shift;
	#possibly skip the init if we are popping back to this mode
	init($client);
	$client->lines(\&lines);
}

# set unsupplied parameters to the defaults
# header = 'Enter Text:' # message displayed on top line
# charsRef = \@UpperChars # reference to array of allowed characters
# valueRef = \"" # string to be edited
# cursorPos = len($$valueRef) # position within string actively being edited
# charIndex = charIndex($charsRef,substring($$valueRef,$cursorPos)) 
	# index of character at cursorPos within charsRef array
# callback = undef # function to call to exit mode
# displayPos = cursorPos - 40 
	# position within string to display at first position of VFD (single height)
# displayPosX2 = cursorPos - DOUBLEWIDTH
	# same as displayPos, but for double height mode
# doublesizeReplace = undef
	# hashref of characters where the keys are the characters to replace
	# and the values are the replacement characters
# parentMode = $client->modeStack->[-2]
	# mode to which to pass button presses mapped to the passback function
	# defaults to mode in second to last position on call stack (which is
	# the mode that called INPUT.Text)
# other parameters used
# rightIndex = charIndex($charsRef,symbol('rightarrow'))
	# index of right arrow within charsRef array
sub init {
	my $client = shift;
	if (!defined($client->param('parentMode'))) {
		my $i = -2;
		while ($client->modeStack->[$i] =~ /^INPUT./) { $i--; }
		$client->param('parentMode',$client->modeStack->[$i]);
	}
	if (!defined($client->param('header'))) {
		$client->param('header','Enter Text:');
	}
	if (!defined($client->param('noScroll'))) {
		$client->param('noScroll',1)
	}
	#check for charsref options and set defaults if needed.
	my $charsRef = $client->param('charsRef');
	if (!defined($charsRef)) {
		$client->param('charsRef',\@UpperChars);
	} elsif (ref($charsRef) ne 'ARRAY') {
		if (uc($charsRef) eq 'UPPER') {
			$client->param('charsRef',\@UpperChars);
		} elsif (uc($charsRef) eq 'BOTH') {
			$client->param('charsRef',\@BothChars);
		} else {
			$client->param('charsRef',\@UpperChars);
		}
	}

	$charsRef = $client->param('charsRef');
	$client->param('listLen', $#$charsRef + 1);
	
	cleanArray($charsRef);
	# check for numberLetterRef and set defaults if needed
	my $numberLetterRef = $client->param('numberLetterRef');
	if (!defined($numberLetterRef)) {
		$client->param('numberLetterRef',\@numberLettersMixed);
	} elsif (ref($numberLetterRef) ne 'ARRAY') {
		if (uc($numberLetterRef) eq 'UPPER') {
			$client->param('numberLetterRef',\@numberLettersUpper);
		} else {
			$client->param('numberLetterRef',\@numberLettersMixed);
		}
	}
	# cannot directly clean multidimensional array, this may need to be done in future
	#cleanArray($numberLetterRef);
	my $rightIndex = charIndex($charsRef,$rightarrow);
	$client->param('rightIndex',$rightIndex);
	my $valueRef = $client->param('valueRef');
	if (!defined($valueRef)) {
		$$valueRef = '';
		$client->param('valueRef',$valueRef);
	} elsif (!ref($valueRef)) {
		my $value = $valueRef;
		$valueRef = \$value;
		$client->param('valueRef',$valueRef);
	}
	$$valueRef = cleanString($$valueRef,$charsRef);
	my $cursorPos = $client->param('cursorPos');
	my $valueRefLen = Slim::Display::Display::lineLength($$valueRef);
	if (!defined($cursorPos) || $cursorPos > $valueRefLen || $cursorPos < 0) {
		$cursorPos = $valueRefLen;
		$client->param('cursorPos',$cursorPos);
	}
	$client->param('displayPos',(($cursorPos < ($client->displayWidth/2)) ? 0 : $cursorPos - (($client->displayWidth/2)-1)));
	$client->param('displayPos2X',(($cursorPos < $DOUBLEWIDTH) ? 0 : $cursorPos - $DOUBLEWIDTH));
	my $charIndex = $client->param('listIndex');
	if ($cursorPos == $valueRefLen) {
		if (!defined($charIndex) || $charIndex < 0 || $charIndex > $#$charsRef) {
			$charIndex = ($rightIndex >= 0) ? $rightIndex : 0;
			$client->param('listIndex',$charIndex);
		}
		$$valueRef .= ($client->param('charsRef'))->[$charIndex];
	} else {
		$charIndex = charIndex($charsRef,Slim::Display::Display::subString($$valueRef,$cursorPos,1));
		if ($charIndex == -1) {
			$charIndex = ($rightIndex == 0) ? 1 : 0;
			#some debug message here
		}
		$client->param('listIndex',$charIndex);
	}
}

sub changeChar {
	my ($client,$dir) = @_;
	Slim::Utils::Timers::killTimers($client, \&nextChar);
	my $charsRef = $client->param('charsRef');
	my $charIndex = Slim::Buttons::Common::scroll($client, $dir, scalar(@{$charsRef}), $client->param('listIndex'));
	my $valueRef = $client->param('valueRef');
	my $cursorPos = $client->param('cursorPos');
	if ($charIndex == $client->param('rightIndex') && $cursorPos != (Slim::Display::Display::lineLength($$valueRef) - 1)) {
		#only allow right arrow in last position
		if ($dir < 0) {
			$charIndex--;
		} else {
			$charIndex++;
		}
		if ($charIndex < 0) {
			$charIndex = $#$charsRef;
		}
		if ($charIndex > $#$charsRef) {
			$charIndex = 0;
		}
	}
	Slim::Display::Display::subString($$valueRef,$cursorPos,1,$charsRef->[$charIndex]);
	checkCursorDisplay($client,$cursorPos);
	
	$client->param('listIndex',$charIndex);
	$client->update();
}

#find the position of the character in the character array
sub charIndex {
	my ($charsRef,$char) = @_;
	for (my $i = 0; $i < @$charsRef; $i++) {
		return $i if $char eq $charsRef->[$i];
	}
	return -1;
}

#make sure each entry in the supplied array is a single character
sub cleanArray {
	my $charsRef = shift;
	foreach (@$charsRef) {
		$_ = Slim::Display::Display::subString($_,0,1);
	}
}

# make sure all characters are in the array of characters specified
sub cleanString {
	my $inString = shift;
	my $charsRef = shift;
	return undef unless (defined($inString) && defined($charsRef));
	my %charsHash = map {$_ => 1} @{$charsRef};
	my $replaceChar = exists($charsHash{' '}) ? '' : ' ';
	my $outString = '';
	foreach (@{Slim::Display::Display::splitString($inString)}) {
		if (exists($charsHash{$_})) {
			$outString .= $_ unless $_ eq $rightarrow;
		} elsif (exists($charsHash{Slim::Utils::Text::matchCase($_)})) {
			$outString .= Slim::Utils::Text::matchCase($_);
		} else {
			$outString .= $replaceChar;
		}
	}
	return $outString;
}

sub validateChar {
	my $client = shift;
	my $char = shift;
	return undef unless defined($char);
	my $charsRef = $client->param('charsRef');
	if ($char =~ /^sp/i) {
		$char = ' ';
	}
	if ($char eq 'sharp' || $char eq 'hash' || $char eq 'pound' || $char =~ /^num/i) {
		$char = '#';
	}
	if ($char =~ /^eq/i) {
		$char = '=';
	}
	return cleanString(Slim::Display::Display::subString($char,0,1),$charsRef);
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
	moveCursor($client,$increment,1,1);
}

sub moveCursor {
	my $client = shift;
	my $increment = shift || 1;
	my $addChar = shift;
	my $forceMove = shift;
	
	my $valueRef = $client->param('valueRef');
	my $cursorPos = $client->param('cursorPos');
	my $valueLen = Slim::Display::Display::lineLength($$valueRef);
	if ($forceMove) {
		$cursorPos += $increment;
	} else {
		$cursorPos = scroll_noacc_nowrap($client,$increment,$valueLen,$cursorPos);
	}
	if ($cursorPos < 0) {
		$cursorPos = 0;
		if ($client->param('cursorPos') == 0) {
			exitInput($client,'cursor_left');
			return;
		}
	}
	my $rightIndex = $client->param('rightIndex');
	my $charsRef = $client->param('charsRef');
	if (!defined $charsRef) {
		# server will crash if no charsRef from here.  
		#This can happen if there is an unpredicted exit from this mode
		return;
	}
	my $charIndex;
	if ($cursorPos == $valueLen) {
		#add right arrow char to end of string (if defined and $addChar set)
		if ($addChar) {
			$charIndex = ($rightIndex >= 0) ? $rightIndex : 0;
			$$valueRef .= $charsRef->[$charIndex];
		} else {
			exitInput($client,'cursor_right');
			return;
		}
	} else {
		$charIndex = charIndex($charsRef,Slim::Display::Display::subString($$valueRef,$cursorPos,1));
	}
	checkCursorDisplay($client,$cursorPos);
	$client->param('listIndex',$charIndex);
	$client->param('cursorPos',$cursorPos);
	$client->update();
	return;
}

sub checkCursorDisplay {
	my $client = shift;
	my $cursorPos = shift;

	my $displayPos = $client->linesPerScreen() == 1 ? $client->param('displayPos2X') : $client->param('displayPos');

	my $valueRef = $client->param('valueRef');
	my $line = Slim::Display::Display::subString($$valueRef,$displayPos,$client->displayWidth);
	my $cursor = $client->measureText(Slim::Display::Display::subString($line,0,$cursorPos),2);

	if ($cursor >= $client->displayWidth) {
		$displayPos += 1;
		$client->linesPerScreen() == 1 ? 
			$client->param('displayPos2X',$displayPos)
		 : 
			$client->param('displayPos',$displayPos);
	} elsif ($cursorPos < $displayPos) {
		$displayPos = $cursorPos;
		$client->linesPerScreen() == 1 ? 
			$client->param('displayPos2X',$displayPos)
		 : 
			$client->param('displayPos',$displayPos);
	}
}

sub scroll_noacc_nowrap {
	my $client = shift;
	my $direction = shift;
	my $listlength = shift;
	my $listposition = shift;
	my $holdtime = Slim::Hardware::IR::holdTime($client);

	if (!$listlength) {
		return 0;
	}
	
	my $i = 1;
	my $rate = 3; # Hz
	$i *= $direction;

	if ($holdtime > 0) {
		$i *= Slim::Hardware::IR::repeatCount($client,$rate);
	}
	$listposition += $i;

	if ($listposition >= $listlength) {
		if ($holdtime > 0) {
			$listposition = $listlength - 1;
		} else {
			$listposition = $listlength;
		}
	} elsif ($listposition < 0) {
		if ($holdtime > 0) {
			$listposition = 0;
		} else {
			$listposition = -1;
		}
	}

	return $listposition;
}

1;
