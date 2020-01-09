package Slim::Buttons::Input::Text;


# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

=head1 NAME

Slim::Buttons::Input::Text

=head1 SYNOPSIS

my %params = (
	'header'          => 'SEARCH_STREAMS',
	'stringHeader'    => 1
	'charsRef'        => 'UPPER',
	'numberLetterRef' => 'UPPER',
	'callback'        => \&handleSearch,
);

Slim::Buttons::Common::pushModeLeft($client, 'INPUT.Text', \%params);

=head1 DESCRIPTION

L<Slim::Buttons::Input::Text> is a reusable Logitech Media Server module for creating a standard UI
for inputting Text. Client parameters may determine the character sets available, and set
any actions done on the resulting text.

The following params may be set when pushing into INPUT.Text, together with their defaults:

header            = 'Edit String:'  message displayed on top line
stringHeader      = undef           header is a string token
charsRef          = \@UpperChars    reference to array of allowed characters
                                    or 'UPPER' (upper case) or 'BOTH' (upper and lower case)
numberLetterRef   = \@numberLettersMixed
                                    reference to array of arrays for number input
                                    or 'UPPER' (upper case + numbers) or 'MIXED' (upper, lower and numbers)
valueRef          = \""             reference to string to be edited
callback          = undef           function to callback when exiting mode
parentMode        = $client->modeStack->[-2]
                                    mode to which to pass button presses mapped to the passback function
                                    defaults to mode in second to last position on call stack (which is
                                    the mode that called INPUT.Text)

The text input is returned as $$valueRef.

Rightarrow is represented by undef in the charRef array.

=cut

# The text string being edited is decomposed into an array of indexes to the charsRef array and stored in arrayRef
# The string is edited by adding/deleting/modifying from the end of arrayRef
# When the exit function is called, the arrayRef array of indexes is assembled into the string in $$valueRef and the mode is popped
#
# The string is:
#
# for my $index ( @{ $arrayRef } ) {
#    $string .= $charRef->[$index];
# }

use strict;

use Slim::Buttons::Common;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;

# default arrays for numberLetterRef

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

# Chars allowed in email addresses:
# Uppercase and lowercase English letters (a-z, A-Z)
# Digits 0 through 9
# Characters ! # $ % & ' * + - / = ? ^ _ ` { | } ~
our @numberLettersEmail = (
	['0','@','.'], # 0
	['1','-','_','+'], # 1
	['a','b','c','2'], 	   # 2
	['d','e','f','3'], 	   # 3
	['g','h','i','4'], 	   # 4
	['j','k','l','5'], 	   # 5
	['m','n','o','6'], 	   # 6
	['p','q','r','s','7'], 	# 7
	['t','u','v','8'], 		# 8
	['w','x','y','z','9']   # 9
);

# default arrays for charRef

our @UpperChars = (
	undef, # represents rightarrow
	'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
	'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
	' ',
	'.', ',', "'", '?', '!', '@', '-', '_', '#', '$', '%', '^', '&',
	'(', ')', '{', '}', '[', ']', '\\','|', ';', ':', '"', '<', '>',
	'*', '=', '+', '`', '/',
	'0', '1', '2', '3', '4', '5', '6', '7', '8', '9'
);

our @BothChars = (
	undef, # represents rightarrow
	'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm',
	'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z',
	'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
	'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
 	' ',
	'.', ',', "'", '?', '!', '@', '-', '_', '#', '$', '%', '^', '&',
	'(', ')', '{', '}', '[', ']', '\\','|', ';', ':', '"', '<', '>',
	'*', '=', '+', '`', '/',
	'0', '1', '2', '3', '4', '5', '6', '7', '8', '9'
);

our @EmailChars = (
	undef, # represents rightarrow
	'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm',
	'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z',
 	'@',
	'.', '-', '_', '+',
	'0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
	'!', '&', "'", '/', '`', '|', '~', '#', '$', '%', '*', '=', '?', '^', '{', '}',
);

Slim::Buttons::Common::addMode('INPUT.Text',getFunctions(),\&setMode);

our %functions = (
	# change character at cursorPos (both up and down)
	'up' => sub {
		my ($client,$funct,$functarg) = @_;
		changeChar($client, -1);
	},

	'down' => sub {
		my ($client,$funct,$functarg) = @_;
		changeChar($client, 1);
	},

	'knob' => sub {
		my ($client,$funct,$functarg) = @_;
		changeChar($client, $client->knobPos() - $client->modeParam('listIndex'));
	},

	# delete current, moving one position to the left, exiting on leftmost position
	'backspace' => sub {
		my ($client,$funct,$functarg) = @_;

		Slim::Utils::Timers::killTimers($client, \&nextChar);

		$client->lastLetterTime(0);

		my $arrayRef = $client->modeParam('arrayRef');

		if (scalar @{$arrayRef} <= 1) {
			exitInput($client, 'backspace');
			return;
		}

		pop @{$arrayRef};

		$client->modeParam('listIndex', $arrayRef->[$#{$arrayRef}]);

		$client->update();
		$client->updateKnob(1);
	},

	# advance to next character, exiting if last char is right arrow
	'nextChar' => sub {
		my ($client,$funct,$functarg) = @_;

		Slim::Utils::Timers::killTimers($client, \&nextChar);

		# reset last letter time to reset the character cycling.
		$client->lastLetterTime(0);

		my $arrayRef = $client->modeParam('arrayRef');
		my $charsRef = $client->modeParam('charsRef');

		# if last character is undef (rightarrow) then exit
		if (!defined $charsRef->[ $arrayRef->[$#{$arrayRef}] ]) {
			exitInput($client, 'nextChar');
			return;
		}
	
		nextChar($client);
	},

	# use numbers to enter characters
	'numberLetter' => sub {
		my ($client,$funct,$functarg) = @_;

		Slim::Utils::Timers::killTimers($client, \&nextChar);

		# if it's a different number, then skip ahead
		if (Slim::Buttons::Common::testSkipNextNumberLetter($client, $functarg)) {
			nextChar($client);
		}

		my $char     = Slim::Buttons::Common::numberLetter($client, $functarg, $client->modeParam('numberLetterRef'));
		my $arrayRef = $client->modeParam('arrayRef');
		my $charsRef = $client->modeParam('charsRef');
		my $charsInd = $client->modeParam('charsInd');

		my $index = $charsInd->{ $char };

		return unless defined($index);

		$arrayRef->[$#{$arrayRef}] = $index;

		$client->modeParam('listIndex', $index);

		# set up a timer to automatically skip ahead
		Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + preferences('server')->get('displaytexttimeout'), \&nextChar);

		#update the display
		$client->update();
	},

	# use characters to enter characters
	'letter' => sub {
		my ($client,$funct,$functarg) = @_;

		Slim::Utils::Timers::killTimers($client, \&nextChar);

		$functarg = ' ' if $functarg eq 'space';

		my $index = $client->modeParam('charsInd')->{ $functarg };

		return unless defined($index);

		my $arrayRef = $client->modeParam('arrayRef');
		my $charsRef = $client->modeParam('charsRef');

		$arrayRef->[$#{$arrayRef}] = $index;

		nextChar($client);
	},

	'exit' => sub {
		my ($client,$funct,$functarg) = @_;

		Slim::Utils::Timers::killTimers($client, \&nextChar);

		if (!defined($functarg) || $functarg eq '') {
			$functarg = 'exit'
		}

		exitInput($client, $functarg);
	},

	'passback' => sub {
		my ($client,$funct,$functarg) = @_;

		my $parentMode = $client->modeParam('parentMode');

		if (defined($parentMode)) {
			Slim::Hardware::IR::executeButton($client,$client->lastirbutton,$client->lastirtime,$parentMode);
		}

	},
);

sub getFunctions {
	return \%functions;
}

sub changeChar {
	my ($client, $dir) = @_;

	Slim::Utils::Timers::killTimers($client, \&nextChar);

	my $charsRef  = $client->modeParam('charsRef');
	my $charIndex = Slim::Buttons::Common::scroll($client, $dir, scalar(@{$charsRef}), $client->modeParam('listIndex'));
	my $arrayRef  = $client->modeParam('arrayRef');

	$arrayRef->[$#{$arrayRef}] = $charIndex;

	$client->modeParam('listIndex', $charIndex);

	$client->update();
	$client->updateKnob();
}

sub nextChar {
	my $client = shift;

	my $newIndex = 0;

	my $arrayRef = $client->modeParam('arrayRef');
	my $charsRef = $client->modeParam('charsRef');

	$arrayRef->[$#{$arrayRef} + 1] = $newIndex;

	$client->modeParam('listIndex', $newIndex);

	$client->update();
	$client->updateKnob(1);
}

sub exitInput {
	my ($client, $exitType) = @_;

	my $valueRef = $client->modeParam('valueRef');
	my $arrayRef = $client->modeParam('arrayRef');
	my $charsRef = $client->modeParam('charsRef');

	$$valueRef = '';

	for my $charIndex (@$arrayRef) {
		$$valueRef .= $charsRef->[$charIndex];
	}

	my $callbackFunct = $client->modeParam('callback');

	if (!defined($callbackFunct) || !(ref($callbackFunct) eq 'CODE')) {

		Slim::Buttons::Common::popMode($client);
		return;
	}

	$callbackFunct->(@_);

	return;
}

sub lines {
	my $client = shift;

	my $arrayRef = $client->modeParam('arrayRef') || return {};
	my $charsRef = $client->modeParam('charsRef');

	my $line1    = $client->modeParam('header');
	my $line2;

	# assemble string, for all but last character as this needs the cursor first
	for my $i (0 .. (scalar @{$arrayRef} - 2) ) {
		$line2 .= $charsRef->[ $arrayRef->[$i] ];
	}

	# add cursor and last character/rightarrow
	$line2 .= $client->symbols('cursorpos');

	my $last = $arrayRef->[ $#{$arrayRef} ];

	$line2 .= defined $last && defined $charsRef->[$last] ? $charsRef->[$last] : $client->symbols('rightarrow');

	# trim left of string if too long for display
	while ($client->measureText($line2, 2) > $client->displayWidth) {
		$line2 = substr($line2, 1);
	}

	return { 'line' => [ $line1, $line2 ] };
}

sub setMode {
	my $client = shift;
	my $method = shift;

	if ($method eq 'push') {
		init($client);
	}

	$client->lines(\&lines);
}

sub init {
	my $client = shift;

	if (!defined($client->modeParam('parentMode'))) {
		my $i = -2;
		while ($client->modeStack->[$i] =~ /^INPUT./) { $i--; }
		$client->modeParam('parentMode',$client->modeStack->[$i]);
	}

	if ($client->modeParam('stringHeader') && Slim::Utils::Strings::stringExists( $client->modeParam('header'))) {
		$client->modeParam('header', $client->string($client->modeParam('header')));
	}

	# check for charsRef options and set defaults if needed.
	my $charsRef = $client->modeParam('charsRef');

	if (!defined($charsRef)) {
		$client->modeParam('charsRef',\@UpperChars);

	} elsif (ref($charsRef) ne 'ARRAY') {

		if (uc($charsRef) eq 'UPPER') {
			$client->modeParam('charsRef',\@UpperChars);

		} elsif (uc($charsRef) eq 'BOTH') {
			$client->modeParam('charsRef',\@BothChars);
		
		} elsif (uc($charsRef) eq 'EMAIL') {
			$client->modeParam('charsRef',\@EmailChars);
			
		} else {
			$client->modeParam('charsRef',\@UpperChars);
		}
	}

	$charsRef = $client->modeParam('charsRef');
	$client->modeParam('listLen', $#$charsRef + 1);

	# check for numberLetterRef and set defaults if needed
	my $numberLetterRef = $client->modeParam('numberLetterRef');

	if (!defined($numberLetterRef)) {
		$client->modeParam('numberLetterRef',\@numberLettersMixed);

	} elsif (ref($numberLetterRef) ne 'ARRAY') {

		if (uc($numberLetterRef) eq 'UPPER') {
			$client->modeParam('numberLetterRef',\@numberLettersUpper);
		
		} elsif (uc($numberLetterRef) eq 'EMAIL') {
			$client->modeParam('numberLetterRef',\@numberLettersEmail);
			
		} else {
			$client->modeParam('numberLetterRef',\@numberLettersMixed);
		}
	}

	# get the string to be edited
	my $valueRef = $client->modeParam('valueRef');

	if (!defined($valueRef)) {
		$$valueRef = '';
		$client->modeParam('valueRef',$valueRef);

	} elsif (!ref($valueRef)) {
		my $value = $valueRef;

		$valueRef = \$value;
		$client->modeParam('valueRef',$valueRef);
	}

	# create a hash for char to index mapping from the charsRef array
	my $charsInd = {};
	my $index = 0;

	for my $char (@{$client->modeParam('charsRef')}) {
		no warnings;
		$charsInd->{ $char } = $index++;
	}

	$client->modeParam('charsInd', $charsInd);

	# create an array of indexes to the charsRef array representing the given string
	my @indexArray;

	for ( my $i = 0; $i < length($$valueRef); ++$i ) {
		my $char = substr($$valueRef, $i, 1);
		push @indexArray, $charsInd->{ $char };
	}

	unless (@indexArray) {
		push @indexArray, $charsInd->{ undef };
	}

	$client->modeParam('arrayRef', \@indexArray);
	$client->modeParam('listIndex', $indexArray[$#indexArray] || 0);
}

=head1 SEE ALSO

L<Slim::Buttons::Common>

=cut

1;
