package Slim::Buttons::Input::Text;

# Slim Server Copyright (c) 2001, 2002, 2003 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use Slim::Buttons::Common;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw (string);
use Slim::Hardware::VFD;

our $DOUBLEWIDTH = 10;
my $rightarrow = Slim::Hardware::VFD::symbol('rightarrow');
###########################
#Button mode specific junk#
###########################
my %functions = (
	#change character at cursorPos (both up and down)
	'up' => sub {
			my ($client,$funct,$functarg) = @_;
			changeChar($client,-1);
		}
	,'down' => sub {
			my ($client,$funct,$functarg) = @_;
			changeChar($client,1);
		}
	#delete current, moving one position to the left, exiting on leftmost position
	,'backspace' => sub {
			my ($client,$funct,$functarg) = @_;
			Slim::Utils::Timers::killTimers($client, \&nextChar);
			my $valueRef = Slim::Buttons::Common::param($client,'valueRef');
			my $cursorPos = Slim::Buttons::Common::param($client,'cursorPos');
			Slim::Hardware::VFD::subString($$valueRef,$cursorPos,1,'');
			$cursorPos--;
			if ($cursorPos < 0) {
				exitInput($client,'backspace');
				return;
			}
			checkCursorDisplay($client,$cursorPos);
			Slim::Buttons::Common::param($client,'cursorPos',$cursorPos);
			Slim::Buttons::Common::param($client,'charIndex',charIndex(Slim::Buttons::Common::param($client,'charsRef'),Slim::Hardware::VFD::subString($$valueRef,$cursorPos,1)));
			$client->update();
		}
	#delete current, staying in place, moving left if in the rightmost position
	#,exiting if string empty
	,'delete' => sub {
			my ($client,$funct,$functarg) = @_;
			Slim::Utils::Timers::killTimers($client, \&nextChar);
			my $valueRef = Slim::Buttons::Common::param($client,'valueRef');
			my $cursorPos = Slim::Buttons::Common::param($client,'cursorPos');
			Slim::Hardware::VFD::subString($$valueRef,$cursorPos,1,'');
			if ($$valueRef eq '') {
				exitInput($client,'delete');
				return;
			}
			if ($cursorPos == Slim::Hardware::VFD::lineLength($$valueRef)) { 
				$cursorPos--; 
				Slim::Buttons::Common::param($client,'cursorPos',$cursorPos);
			}
			checkCursorDisplay($client,$cursorPos);
			Slim::Buttons::Common::param($client,'charIndex',charIndex(Slim::Buttons::Common::param($client,'charsRef'),Slim::Hardware::VFD::subString($$valueRef,$cursorPos,1)));
			$client->update();
		}
	#advance to next character, exiting if last char is right arrow
	,'nextChar' => sub {
			my ($client,$funct,$functarg) = @_;
			Slim::Utils::Timers::killTimers($client, \&nextChar);
			my $valueRef = Slim::Buttons::Common::param($client,'valueRef');
			my $cursorPos = Slim::Buttons::Common::param($client,'cursorPos');
			if (Slim::Hardware::VFD::subString($$valueRef,$cursorPos,1) eq $rightarrow) {
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
			my $displayPos = Slim::Buttons::Common::param($client,'displayPos');
			my $displayPos2X = Slim::Buttons::Common::param($client,'displayPos2X');
			if ($displayPos != $displayPos2X && Slim::Utils::Prefs::clientGet($client,'doublesize')) {
				$displayPos = $displayPos2X;
			}
			my $valueEnd = Slim::Hardware::VFD::lineLength(${Slim::Buttons::Common::param($client,'valueRef')}) - 1;
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
			Slim::Buttons::Common::param($client,'displayPos',$displayPos);
			Slim::Buttons::Common::param($client,'displayPos2X',$displayPos);
			$client->update();
		}
	#Insert char at current cursor position
	,'insert' => sub {
			my ($client,$funct,$functarg) = @_;
			Slim::Utils::Timers::killTimers($client, \&nextChar);
			my $char = validateChar($client,$functarg);
			if (!defined($char)) {
				my $charsRef = Slim::Buttons::Common::param($client,'charsRef');
				$char = $charsRef->[(Slim::Buttons::Common::param($client,'rightIndex') == 0) ? 1 : 0];
			}
			my $valueRef = Slim::Buttons::Common::param($client,'valueRef');
			my $cursorPos = Slim::Buttons::Common::param($client,'cursorPos');
			checkCursorDisplay($client,$cursorPos);
			Slim::Hardware::VFD::subString($$valueRef,$cursorPos,0,$char);
			$client->update();
		}
	#clear current text
	,'clear' => sub {
			my ($client,$funct,$functarg) = @_;
			Slim::Utils::Timers::killTimers($client, \&nextChar);
			my $charIndex = Slim::Buttons::Common::param($client,'rightIndex');
			$charIndex = ($charIndex == -1) ? 0 : $charIndex;
			my $valueRef = Slim::Buttons::Common::param($client,'valueRef');
			my $charsRef = Slim::Buttons::Common::param($client,'charsRef');
			$$valueRef = $charsRef->[$charIndex];
			Slim::Buttons::Common::param($client,'charIndex',$charIndex);
			Slim::Buttons::Common::param($client,'cursorPos',0);
			Slim::Buttons::Common::param($client,'displayPos',0);
			Slim::Buttons::Common::param($client,'displayPos2X',0);
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
			my $char = validateChar($client,Slim::Buttons::Common::numberLetter($client, $functarg));
			if (!defined($char)) { $char = ''; }
			my $valueRef = Slim::Buttons::Common::param($client,'valueRef');
			my $cursorPos = Slim::Buttons::Common::param($client,'cursorPos');
			Slim::Hardware::VFD::subString($$valueRef,$cursorPos,1,$char);
			my $charIndex = charIndex(Slim::Buttons::Common::param($client,'charsRef'),Slim::Hardware::VFD::subString($$valueRef,$cursorPos));
			Slim::Buttons::Common::param($client,'charIndex',$charIndex);
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
			my $valueRef = Slim::Buttons::Common::param($client,'valueRef');
			my $cursorPos = Slim::Buttons::Common::param($client,'cursorPos');
			Slim::Hardware::VFD::subString($$valueRef,$cursorPos,1,$char);
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
);

sub lines {
	my $client = shift;
	my ($line1, $line2);
	$line1 = Slim::Buttons::Common::param($client,'header');
	my $valueRef = Slim::Buttons::Common::param($client,'valueRef');
	if (!defined($valueRef)) { return ('',''); }
	my $cursorPos = Slim::Buttons::Common::param($client,'cursorPos');
	my $displayPos;
	if (!Slim::Utils::Prefs::clientGet($client,'doublesize')) {
		$displayPos = Slim::Buttons::Common::param($client,'displayPos');
	} else {
		$displayPos = Slim::Buttons::Common::param($client,'displayPos2X');
		if (my $doublereplaceref = Slim::Buttons::Common::param($client,'doublesizeReplace')) {
			while (my ($find,$replace) = each(%$doublereplaceref)) {
				$line2 =~ s/$find/$replace/g;
			}
		}
	}
	$line2 = Slim::Hardware::VFD::subString($$valueRef,$displayPos,40);
	if ($displayPos <= $cursorPos && ($cursorPos - $displayPos < 40)) {
		Slim::Hardware::VFD::subString($line2,$cursorPos - $displayPos,0,Slim::Hardware::VFD::symbol('cursorpos'));
	}
	return ($line1,$line2);
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

my @UpperChars = (
	Slim::Hardware::VFD::symbol('rightarrow'),
	'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
	'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
	' ',
	'.', ',', "'", '?', '!', '@', '-', '_', '#', '$', '%', '^', '&',
	'(', ')', '{', '}', '[', ']', '\\','|', ';', ':', '"', '<', '>',
	'*', '=', '+', '`', '/', 'ß', 
	'0', '1', '2', '3', '4', '5', '6', '7', '8', '9'
);
my @BothChars = (
	Slim::Hardware::VFD::symbol('rightarrow'),
	'A', 'a', 'B', 'b', 'C', 'c', 'D', 'd', 'E', 'e', 'F', 'f',
	'G', 'g', 'H', 'h', 'I', 'i', 'J', 'j', 'K', 'k', 'L', 'l', 'M', 'm',
	'N', 'n', 'O', 'o', 'P', 'p', 'Q', 'q', 'R', 'r', 'S', 's', 'T', 't',
	'U', 'u', 'V', 'v', 'W', 'w', 'X', 'x', 'Y', 'y', 'Z', 'z',
	' ',
	'.', ',', "'", '?', '!', '@', '-', '_', '#', '$', '%', '^', '&',
	'(', ')', '{', '}', '[', ']', '\\','|', ';', ':', '"', '<', '>',
	'*', '=', '+', '`', '/', 'ß', 
	'0', '1', '2', '3', '4', '5', '6', '7', '8', '9'
);

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
# other parameters used
# rightIndex = charIndex($charsRef,symbol('rightarrow'))
	# index of right arrow within charsRef array
sub init {
	my $client = shift;
	if (!defined(Slim::Buttons::Common::param($client,'header'))) {
		Slim::Buttons::Common::param($client,'header','Enter Text:');
	}
	if (!defined(Slim::Buttons::Common::param($client,'noScroll'))) {
		Slim::Buttons::Common::param($client,'noScroll',1)
	}
	my $charsRef = Slim::Buttons::Common::param($client,'charsRef');
	if (!defined($charsRef)) {
		Slim::Buttons::Common::param($client,'charsRef',\@UpperChars);
	} elsif (ref($charsRef) ne 'ARRAY') {
		if (uc($charsRef) eq 'UPPER') {
			Slim::Buttons::Common::param($client,'charsRef',\@UpperChars);
		} elsif (uc($charsRef) eq 'BOTH') {
			Slim::Buttons::Common::param($client,'charsRef',\@BothChars);
		} else {
			Slim::Buttons::Common::param($client,'charsRef',\@UpperChars);
		}
	} else {
		Slim::Buttons::Common::param($client,'charsRef',\@UpperChars);
	}
	$charsRef = Slim::Buttons::Common::param($client,'charsRef');
	cleanArray($charsRef);
	my $rightIndex = charIndex($charsRef,$rightarrow);
	Slim::Buttons::Common::param($client,'rightIndex',$rightIndex);
	my $valueRef = Slim::Buttons::Common::param($client,'valueRef');
	if (!defined($valueRef)) {
		$$valueRef = '';
		Slim::Buttons::Common::param($client,'valueRef',$valueRef);
	} elsif (!ref($valueRef)) {
		$$valueRef = $valueRef;
		Slim::Buttons::Common::param($client,'valueRef',$valueRef);
	}
	$$valueRef = cleanString($$valueRef,$charsRef);
	my $cursorPos = Slim::Buttons::Common::param($client,'cursorPos');
	my $valueRefLen = Slim::Hardware::VFD::lineLength($$valueRef);
	if (!defined($cursorPos) || $cursorPos > $valueRefLen || $cursorPos < 0) {
		$cursorPos = $valueRefLen;
		Slim::Buttons::Common::param($client,'cursorPos',$cursorPos);
	}
	Slim::Buttons::Common::param($client,'displayPos',(($cursorPos < 40) ? 0 : $cursorPos - 39));
	Slim::Buttons::Common::param($client,'displayPos2X',(($cursorPos < $DOUBLEWIDTH) ? 0 : $cursorPos - $DOUBLEWIDTH));
	my $charIndex = Slim::Buttons::Common::param($client,'charIndex');
	if ($cursorPos == $valueRefLen) {
		if (!defined($charIndex) || $charIndex < 0 || $charIndex > $#$charsRef) {
			$charIndex = ($rightIndex >= 0) ? $rightIndex : 0;
			Slim::Buttons::Common::param($client,'charIndex',$charIndex);
		}
		$$valueRef .= (Slim::Buttons::Common::param($client,'charsRef'))->[$charIndex];
	} else {
		$charIndex = charIndex($charsRef,Slim::Hardware::VFD::subString($$valueRef,$cursorPos,1));
		if ($charIndex == -1) {
			$charIndex = ($rightIndex == 0) ? 1 : 0;
			#some debug message here
		}
		Slim::Buttons::Common::param($client,'charIndex',$charIndex);
	}
}

sub changeChar {
	my ($client,$dir) = @_;
	Slim::Utils::Timers::killTimers($client, \&nextChar);
	my $charsRef = Slim::Buttons::Common::param($client,'charsRef');
	my $charIndex = Slim::Buttons::Common::scroll($client, $dir, scalar(@{$charsRef}), Slim::Buttons::Common::param($client,'charIndex'));
	my $valueRef = Slim::Buttons::Common::param($client,'valueRef');
	my $cursorPos = Slim::Buttons::Common::param($client,'cursorPos');
	if ($charIndex == Slim::Buttons::Common::param($client,'rightIndex') && $cursorPos != (Slim::Hardware::VFD::lineLength($$valueRef) - 1)) {
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
	Slim::Hardware::VFD::subString($$valueRef,$cursorPos,1,$charsRef->[$charIndex]);
	checkCursorDisplay($client,$cursorPos);
	Slim::Buttons::Common::param($client,'charIndex',$charIndex);
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
		s/^(vfD_[^_]+_Vfd|.).*$/$1/;
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
	foreach (@{Slim::Hardware::VFD::splitString($inString)}) {
		if (exists($charsHash{$_})) {
			$outString .= $_ unless $_ eq $rightarrow;
		} elsif (exists($charsHash{Slim::Music::Info::matchCase($_)})) {
			$outString .= Slim::Music::Info::matchCase($_);
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
	my $charsRef = Slim::Buttons::Common::param($client,'charsRef');
	if ($char =~ /^sp/i) {
		$char = ' ';
	}
	if ($char eq 'sharp' || $char eq 'hash' || $char eq 'pound' || $char =~ /^num/i) {
		$char = '#';
	}
	if ($char =~ /^eq/i) {
		$char = '=';
	}
	return cleanString(Slim::Hardware::VFD::subString($char,0,1),$charsRef);
}



sub exitInput {
	my ($client,$exitType) = @_;
	my $callbackFunct = Slim::Buttons::Common::param($client,'callback');
	if (!defined($callbackFunct) || !(ref($callbackFunct) eq 'CODE')) {
		Slim::Buttons::Common::popMode($client);
		return;
	}
	&$callbackFunct(@_);
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
	
	my $valueRef = Slim::Buttons::Common::param($client,'valueRef');
	my $cursorPos = Slim::Buttons::Common::param($client,'cursorPos');
	my $valueLen = Slim::Hardware::VFD::lineLength($$valueRef);
	if ($forceMove) {
		$cursorPos += $increment;
	} else {
		$cursorPos = scroll_noacc_nowrap($client,$increment,$valueLen,$cursorPos);
	}
	if ($cursorPos < 0) {
		$cursorPos = 0;
		if (Slim::Buttons::Common::param($client,'cursorPos') == 0) {
			exitInput($client,'cursor_left');
			return;
		}
	}
	my $rightIndex = Slim::Buttons::Common::param($client,'rightIndex');
	my $charsRef = Slim::Buttons::Common::param($client,'charsRef');
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
		$charIndex = charIndex($charsRef,Slim::Hardware::VFD::subString($$valueRef,$cursorPos,1));
	}
	checkCursorDisplay($client,$cursorPos);
	Slim::Buttons::Common::param($client,'charIndex',$charIndex);
	Slim::Buttons::Common::param($client,'cursorPos',$cursorPos);
	$client->update();
	return;
}

sub checkCursorDisplay {
	my $client = shift;
	my $cursorPos = shift;
	my $displayPos = Slim::Buttons::Common::param($client,'displayPos');
	my $displayPos2X = Slim::Buttons::Common::param($client,'displayPos2X');
	if ($cursorPos > $displayPos + 39) {
		$displayPos = $cursorPos - 39;
		Slim::Buttons::Common::param($client,'displayPos',$displayPos);
	} elsif ($cursorPos < $displayPos) {
		$displayPos = $cursorPos;
		Slim::Buttons::Common::param($client,'displayPos',$displayPos);
	}
	if ($cursorPos >= $displayPos2X + $DOUBLEWIDTH) {
		$displayPos2X = $cursorPos - $DOUBLEWIDTH;
		Slim::Buttons::Common::param($client,'displayPos2X',$displayPos2X);
	} elsif ($cursorPos < $displayPos2X) {
		$displayPos2X = $cursorPos;
		Slim::Buttons::Common::param($client,'displayPos2X',$displayPos2X);
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

