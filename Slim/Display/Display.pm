package Slim::Display::Display;

# $Id: Display.pm,v 1.6 2003/08/09 06:43:26 dean Exp $

# Slim Server Copyright (c) 2001, 2002, 2003 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use File::Spec::Functions qw(:ALL);
use Slim::Utils::Misc;
use Slim::Hardware::VFD;
use Slim::Utils::Timers;
use Slim::Utils::Strings qw(string);
use POSIX qw(strftime);

#depricated, use $client->update
sub update {
	my $client = shift;
	$client->update();
}

sub renderOverlay {
	my $line1 = shift;
	my $line2 = shift;
	my $overlay1 = shift;
	my $overlay2 = shift;
	
	if (defined($overlay1)) {
		my $overlayLength =  Slim::Hardware::VFD::lineLength($overlay1);
		$line1 .= ' ' x 40;
		$line1 = Slim::Hardware::VFD::subString($line1, 0, 40 - $overlayLength) . $overlay1;
	}
	
	if (defined($overlay2)) {
		my $overlayLength =  Slim::Hardware::VFD::lineLength($overlay2);
		$line2 .= ' ' x 40;
		$line2 = Slim::Hardware::VFD::subString($line2, 0, 40 - $overlayLength) . $overlay2;
	}
	return ($line1, $line2);
}

# the lines functions return a pair of lines and a pair of overlay strings
# which may need to be overlayed on top of the first pair, right justified.

sub curLines {
	my $client = shift;
	
	if (!defined($client)) { return; }
	
	my $linefunc = $client->lines();
	
	if (defined $linefunc) {
		return renderOverlay(&$linefunc($client));
	} else {
		$::d_ui && msg("Linefunction for client is undefined!\n");
		$::d_ui && bt();
	}
}

#	FUNCTION:	volumeDisplay
#
#	DESCRIPTION:	Used to display a bar graph of the current volume below a label
#	
#	EXAMPLE OUTPUT:	Volume
#					###############-----------------
#	
#	USAGE:		volumeDisplay($client)
sub volumeDisplay {
	my $client = shift;
	Slim::Display::Animation::showBriefly($client,Slim::Buttons::Settings::volumeLines($client));
}

sub center {
	my $line = shift;
	return (Slim::Hardware::VFD::symbol('center'). $line);
}

# the following are the custom character definitions for the new progress/level bar...

Slim::Hardware::VFD::setCustomChar('notesymbol',
				 ( 0b00000100, 
				   0b00000110, 
				   0b00000101, 
				   0b00000101, 
				   0b00001101, 
				   0b00011100, 
				   0b00011000, 
				   0b00000000 ));

Slim::Hardware::VFD::setCustomChar('leftprogress0',
				 ( 0b00000111, 
				   0b00001000, 
				   0b00010000, 
				   0b00010000, 
				   0b00010000, 
				   0b00001000, 
				   0b00000111, 
				   0b00000000 ));

Slim::Hardware::VFD::setCustomChar('leftprogress1',
				 ( 0b00000111, 
				   0b00001000, 
				   0b00011000, 
				   0b00011000, 
				   0b00011000, 
				   0b00001000, 
				   0b00000111, 
				   0b00000000 ));

Slim::Hardware::VFD::setCustomChar('leftprogress2',
				 ( 0b00000111, 
				   0b00001100, 
				   0b00011100, 
				   0b00011100, 
				   0b00011100, 
				   0b00001100, 
				   0b00000111, 
				   0b00000000 ));

Slim::Hardware::VFD::setCustomChar('leftprogress3',
				 ( 0b00000111, 
				   0b00001110, 
				   0b00011110, 
				   0b00011110, 
				   0b00011110, 
				   0b00001110, 
				   0b00000111, 
				   0b00000000 ));

Slim::Hardware::VFD::setCustomChar('leftprogress4',
				 ( 0b00000111, 
				   0b00001111, 
				   0b00011111, 
				   0b00011111, 
				   0b00011111, 
				   0b00001111, 
				   0b00000111, 
				   0b00000000 ));

Slim::Hardware::VFD::setCustomChar('middleprogress0',
				 ( 0b00011111, 
				   0b00000000, 
				   0b00000000, 
				   0b00000000, 
				   0b00000000, 
				   0b00000000, 
				   0b00011111, 
				   0b00000000 ));

Slim::Hardware::VFD::setCustomChar('middleprogress1',
				 ( 0b00011111, 
				   0b00010000, 
				   0b00010000, 
				   0b00010000, 
				   0b00010000, 
				   0b00010000, 
				   0b00011111, 
				   0b00000000 ));

Slim::Hardware::VFD::setCustomChar('middleprogress2',
				 ( 0b00011111, 
				   0b00011000, 
				   0b00011000, 
				   0b00011000, 
				   0b00011000, 
				   0b00011000, 
				   0b00011111, 
				   0b00000000 ));

Slim::Hardware::VFD::setCustomChar('middleprogress3',
				 ( 0b00011111, 
				   0b00011100, 
				   0b00011100, 
				   0b00011100, 
				   0b00011100, 
				   0b00011100, 
				   0b00011111, 
				   0b00000000 ));

Slim::Hardware::VFD::setCustomChar('middleprogress4',
				 ( 0b00011111, 
				   0b00011110, 
				   0b00011110, 
				   0b00011110, 
				   0b00011110, 
				   0b00011110, 
				   0b00011111, 
				   0b00000000 ));

Slim::Hardware::VFD::setCustomChar('middleprogress5',
				 ( 0b00011111, 
				   0b00011111, 
				   0b00011111, 
				   0b00011111, 
				   0b00011111, 
				   0b00011111, 
				   0b00011111, 
				   0b00000000 ));

Slim::Hardware::VFD::setCustomChar('rightprogress0',
				 ( 0b00011100, 
				   0b00000010, 
				   0b00000001, 
				   0b00000001, 
				   0b00000001, 
				   0b00000010, 
				   0b00011100, 
				   0b00000000 ));

Slim::Hardware::VFD::setCustomChar('rightprogress1',
				 ( 0b00011100, 
				   0b00010010, 
				   0b00010001, 
				   0b00010001, 
				   0b00010001, 
				   0b00010010, 
				   0b00011100, 
				   0b00000000 ));

Slim::Hardware::VFD::setCustomChar('rightprogress2',
				 ( 0b00011100, 
				   0b00011010, 
				   0b00011001, 
				   0b00011001, 
				   0b00011001, 
				   0b00011010, 
				   0b00011100, 
				   0b00000000 ));

Slim::Hardware::VFD::setCustomChar('rightprogress3',
				 ( 0b00011100, 
				   0b00011110, 
				   0b00011101, 
				   0b00011101, 
				   0b00011101, 
				   0b00011110, 
				   0b00011100, 
				   0b00000000 ));

Slim::Hardware::VFD::setCustomChar('rightprogress4',
				 ( 0b00011100, 
				   0b00011110, 
				   0b00011111, 
				   0b00011111, 
				   0b00011111, 
				   0b00011110, 
				   0b00011100, 
				   0b00000000 ));

# returns progress bar text AND sets up custom characters if necessary
sub progressBar {
	my $client = shift;
	my $width = shift;
	my $fractioncomplete = shift;
	my $charwidth = 5;
	if ($fractioncomplete < 0) {
		$fractioncomplete = 0;
	}
	
	if ($fractioncomplete > 1.0) {
		$fractioncomplete = 1.0;
	}
	
	if ($width == 0) {
		return "";
	}
	
	my $chart = "";
	
	my $totaldots = $charwidth + ($width - 2) * $charwidth + $charwidth;

	# felix mueller discovered some rounding errors that were causing the
	# calculations to be off.  Doing it 1000 times up seems to be better.  
	# go figure.
	my $dots = int( ( ( $fractioncomplete * 1000) * $totaldots) / 1000);
	
	if ($dots < 0) { $dots = 0 };
	
	if ($dots < $charwidth) {
		$chart = Slim::Hardware::VFD::symbol('leftprogress'.$dots);
	} else {
		$chart = Slim::Hardware::VFD::symbol('leftprogress4');
	}
	
	$dots -= $charwidth;
			
	for (my $i = 1; $i < ($width - 1); $i++) {
		if ($dots <= 0) {
			$chart .= Slim::Hardware::VFD::symbol('middleprogress0');					
		} elsif ($dots < $charwidth) {
			$chart .= Slim::Hardware::VFD::symbol('middleprogress'.$dots);						
		} else {
			$chart .= Slim::Hardware::VFD::symbol('middleprogress5');								
		}
		$dots -= $charwidth;
	}
	
	if ($dots <= 0) {
		$chart .= Slim::Hardware::VFD::symbol('rightprogress0');
	} elsif ($dots < $charwidth) {
		$chart .= Slim::Hardware::VFD::symbol('rightprogress'.$dots);
	} else {
		$chart .= Slim::Hardware::VFD::symbol('rightprogress4');
	}
	
	return $chart;
}

Slim::Hardware::VFD::setCustomChar('leftmark',
 					(   0b00011111,
						0b00000001,
						0b00000001,
						0b00000001,
						0b00000001,
						0b00000001,
						0b00011111,
						0b00000000   ));
                  
Slim::Hardware::VFD::setCustomChar('rightmark',
					( 	0b00011111,
						0b00010000,
						0b00010000,
						0b00010000,
						0b00010000,
						0b00010000,
						0b00011111,
						0b00000000   ));
                  
# returns a +/- balance/bass/treble bar text AND sets up custom characters if necessary
# range 0 to 100, 50 is middle.
sub balanceBar {
	my $client = shift;
	my $width = shift;
	my $balance = shift;
	
	if ($balance < 0) {
		$balance = 0;
	}
	
	if ($balance > 100) {
		$balance = 100;
	}
	
	if ($width == 0) {
		return "";
	}
	
	my $chart = "";
		
	my $edgepos = $balance / 100.0 * $width;
	# do the leftmost char
	if ($balance <= 0) {
		$chart = Slim::Hardware::VFD::symbol('leftprogress4');
	} else {
		$chart = Slim::Hardware::VFD::symbol('leftprogress0');
	}
	
	my $i;
	
	# left half
	for ($i = 1; $i < $width/2; $i++) {
		if ($balance >= 50) {
			if ($i == $width/2-1) {
				$chart .= Slim::Hardware::VFD::symbol('leftmark');
			} else {
				$chart .= Slim::Hardware::VFD::symbol('middleprogress0');
			}
		} else {
			if ($i < $edgepos) {
				$chart .= Slim::Hardware::VFD::symbol('middleprogress0');
			} else {
				$chart .= Slim::Hardware::VFD::symbol('middleprogress5');
			}			
		}
	}
	
	# right half
	for ($i = $width/2; $i < $width-1; $i++) {
		if ($balance <= 50) {
			if ($i == $width/2) {
				$chart .= Slim::Hardware::VFD::symbol('rightmark');
			} else {	
				$chart .= Slim::Hardware::VFD::symbol('middleprogress0');
			}
		} else {
			if ($i < $edgepos) {
				$chart .= Slim::Hardware::VFD::symbol('middleprogress5');
			} else {
				$chart .= Slim::Hardware::VFD::symbol('middleprogress0');
			}			
		}
	}
	
	# do the rightmost char
	if ($balance >= 100) {
		$chart .= Slim::Hardware::VFD::symbol('rightprogress4');
	} else {
		$chart .= Slim::Hardware::VFD::symbol('rightprogress0');
	}
	
	return $chart;
}

# replaces ~ in format string
# setup the special characters
Slim::Hardware::VFD::setCustomChar( 'toplinechar',	
					(	0b00011111, 
						0b00000000, 
						0b00000000, 
						0b00000000, 
						0b00000000, 
						0b00000000, 
						0b00000000, 
						0b00000000	 ));

# replaces = in format string
Slim::Hardware::VFD::setCustomChar( 'doublelinechar', 
					(	0b00011111, 
						0b00000000, 
						0b00000000, 
						0b00000000, 
						0b00000000, 
						0b00000000, 
						0b00011111, 
						0b00000000	 ));

# replaces ? in format string.  Used in Z, ?, 7
Slim::Hardware::VFD::setCustomChar( 'Ztop', 		
			(      		0b00011111,
						0b00000001,
						0b00000001,
						0b00000010,
						0b00000100,
						0b00001000,
						0b00010000,
						0b00000000   ));
                  
# replaces < in format string.  Used in Z, 2, 6
Slim::Hardware::VFD::setCustomChar( 'Zbottom', 		
			(   		0b00000001,
						0b00000010,
						0b00000100,
						0b00001000,
						0b00010000,
						0b00010000,
						0b00011111,
						0b00000000   ));
                  
# replaces / in format string.
Slim::Hardware::VFD::setCustomChar( 'slash', 	
			 (     		0b00000001,
						0b00000001,
						0b00000010,
						0b00000100,
						0b00001000,
						0b00010000,
						0b00010000,
						0b00000000   ));
                  
Slim::Hardware::VFD::setCustomChar( 'backslash', 	
				( 		0b00010000,
						0b00010000,
						0b00001000,
						0b00000100,
						0b00000010,
						0b00000001,
						0b00000001,
						0b00000000   ));
                  
Slim::Hardware::VFD::setCustomChar( 'filledcircle',		
					 ( 	0b00000001,
						0b00001111,
						0b00011111,
						0b00011111,
						0b00011111,
						0b00001110,
						0b00000000,
						0b00000000   ));	

Slim::Hardware::VFD::setCustomChar( 'leftvbar',		
					 ( 	0b00010000,
						0b00010000,
						0b00010000,
						0b00010000,
						0b00010000,
						0b00010000,
						0b00010000,
						0b00000000   ));	

Slim::Hardware::VFD::setCustomChar( 'rightvbar',		
					 ( 	0b00000001,
						0b00000001,
						0b00000001,
						0b00000001,
						0b00000001,
						0b00000001,
						0b00000001,
						0b00000000   ));	

my $leftvbar = Slim::Hardware::VFD::symbol('leftvbar');
my $rightvbar = Slim::Hardware::VFD::symbol('rightvbar');
my $slash = Slim::Hardware::VFD::symbol('slash');
my $backslash = Slim::Hardware::VFD::symbol('backslash');
my $toplinechar = Slim::Hardware::VFD::symbol('toplinechar');
my $doublelinechar = Slim::Hardware::VFD::symbol('doublelinechar');
my $Zbottom = Slim::Hardware::VFD::symbol('Zbottom');
my $Ztop = Slim::Hardware::VFD::symbol('Ztop');
my $notesymbol = Slim::Hardware::VFD::symbol('notesymbol');
my $filledcircle = Slim::Hardware::VFD::symbol('filledcircle');
my $rightarrow = Slim::Hardware::VFD::symbol('rightarrow');
my $cursorpos = Slim::Hardware::VFD::symbol('cursorpos');
my $hardspace = Slim::Hardware::VFD::symbol('hardspace');
my $centerchar = Slim::Hardware::VFD::symbol('center');

# double sized characters
my %doublechars = (
	
	"(" => [ $slash,
			 $backslash ],
	
	")" => [ ' ' . $backslash,
			 ' ' . $slash ],
	
	"[" => [ $rightvbar . $toplinechar,
			 $rightvbar . '_' ],
	
	"]" => [ $toplinechar . $leftvbar,
			 '_' . $leftvbar],
	
	"<" => [ '/',
			 $backslash ],
	
	">" => [ $backslash,
			 '/' ],
	
	"{" => [ '(',
			 '(' ],
	
	"}" => [ ')',
			 ')' ],
	
	'"' => [ '\'\'',
			 '  '],
	"%" => [ 'o/', '/o'],
	"&" => [ '_' . 'L', $backslash . $leftvbar],
	"^" => [ $slash . $backslash, '  '],
	" " => [ '  ', '  ' ],
	"'" => [ '|', ' ' ],
	"!" => [ '|', '.' ],
	":" => [ '.', '.' ],
	"." => [ ' ', '.' ],
	";" => [ '.', ',' ],
	"," => [ ' ', '/' ],
	"`" => [ $backslash, ' ' ],
	
	"_" => [ '  ', '_' . '_' ],
	
	"+" => [ '_' . 'L', ' ' . $leftvbar],
	
	"*" => [ '**', '**'],
	
	'~' => [ $slash . $toplinechar, '  ' ],
	
	"@" => [ $slash . 'd',
			 $backslash . '_' ],
	
	"#" => [ '##', '##' ],
	
	'$' => [ '$$', '$$' ],
	
	"|" => [ '|',
			 '|' ],
	
	"-" => [ '_' . '_',
			 '  ' ],
	
	"/" => [ ' ' . $slash,
			 $slash . ' ' ],
	
	"\\" => [ $backslash . ' ',
			  ' ' . $backslash ],
	
	"=" => ['--'
		   ,'--'],
	
	'?' => [$toplinechar . $Ztop,
		,' .'],

	$cursorpos => ['',''],
		
	$notesymbol => [ $leftvbar . $backslash , $filledcircle . " "],

	$rightarrow => [ ' _' . $backslash , ' ' . $toplinechar . '/'],

	$hardspace => [ ' ', ' '],
	
	$centerchar => [$centerchar,$centerchar]
	,'0' => [$slash . $toplinechar . $backslash, $backslash . '_' . $slash]
	,'1' => [' ' . $slash . $leftvbar , '  ' . $leftvbar]
	,'2' => [' ' . $toplinechar . ')' , ' ' . $Zbottom . '_']
	,'3' => [' ' . $doublelinechar . ')' , ' _)']
	,'4' => [$rightvbar . '_' . $leftvbar , '  ' . $leftvbar]
	,'5' => [$rightvbar . $doublelinechar . $toplinechar , ' _)']
	,'6' => [' ' . $Zbottom . ' ' , '(_)']
	,'7' => [' ' . $toplinechar . $Ztop , ' ' . $slash . ' ']
	,'8' => ['(' . $doublelinechar . ')' , '(_)']
	,'9' => ['(' . $doublelinechar . ')' , ' ' . $slash . ' ']
	,'A' => [' ' . $slash . $backslash . ' ' , $rightvbar . $toplinechar . $toplinechar . $leftvbar]
	,'B' => [$rightvbar . $doublelinechar . ')' , $rightvbar . '_)']
	,'C' => [$slash . $toplinechar , $backslash . '_']
	,'D' => [$rightvbar . $toplinechar . $backslash , $rightvbar . '_' . $slash]
	,'E' => [$rightvbar . $doublelinechar , $rightvbar . '_']
	,'F' => [$rightvbar . $doublelinechar , $rightvbar . ' ']
	,'G' => [$slash . $toplinechar . ' ' , $backslash . $doublelinechar . $leftvbar]
	,'H' => [$rightvbar . '_' . $leftvbar , $rightvbar . ' ' . $leftvbar]
	,'I' => [' ' . $leftvbar , ' ' . $leftvbar]
	,'J' => ['  ' . $leftvbar , $rightvbar . '_' . $leftvbar]
	,'K' => [$rightvbar . $slash , $rightvbar . $backslash]
	,'L' => [$rightvbar . ' ' , $rightvbar . '_']
	,'M' => [$rightvbar . $backslash . $slash . $leftvbar , $rightvbar . '  ' . $leftvbar]
	,'N' => [$rightvbar . $backslash . $leftvbar , $rightvbar . ' ' . $leftvbar]
	,'O' => [$slash . $toplinechar . $backslash , $backslash . '_' . $slash]
	,'P' => [$rightvbar . $doublelinechar .')' , $rightvbar . '  ']
	,'Q' => [$slash . $toplinechar . $backslash , $backslash . '_X']
	,'R' => [$rightvbar . $doublelinechar . ')' , $rightvbar . ' ' . $backslash]
	,'S' => ['(' . $toplinechar , '_)']
	,'T' => [$toplinechar . '|' . $toplinechar , ' | ']
	,'U' => [$rightvbar . ' ' . $leftvbar , $rightvbar . '_' . $leftvbar]
	,'V' => [$leftvbar . $rightvbar , $backslash . $slash]
	,'W' => [$leftvbar . '  ' . $rightvbar , $backslash . $slash . $backslash . $slash]
	,'X' => [$backslash . $slash , $slash . $backslash]
	,'Y' => [$backslash . $slash , ' ' . $leftvbar]
	,'Z' => [$toplinechar . $Ztop , $Zbottom . '_']
);

sub addDoubleChar {
	my ($char,$doublechar) = @_;
	if (!exists $doublechars{$char} && ref($doublechar) eq 'ARRAY' 
			&& Slim::Hardware::VFD::lineLength($doublechar->[0]) == Slim::Hardware::VFD::lineLength($doublechar->[1])) {
		$doublechars{$char} = $doublechar;
	} else {
		if ($::d_display) {
			msg("Could not add character $char, it already exists.\n") if exists $doublechars{$char};
			msg("Could not add character $char, doublechar is not array reference.\n") if ref($doublechar) ne 'ARRAY';
			msg("Could not add character $char, lines of doublechar have unequal lengths.\n")
				if Slim::Hardware::VFD::lineLength($doublechar->[0]) != Slim::Hardware::VFD::lineLength($doublechar->[1]);
		}
	}
}

sub updateDoubleChar {
	my ($char,$doublechar) = @_;
	if (ref($doublechar) eq 'ARRAY' 
			&& Slim::Hardware::VFD::lineLength($doublechar->[0]) == Slim::Hardware::VFD::lineLength($doublechar->[1])) {
		$doublechars{$char} = $doublechar;
	} else {
		if ($::d_display) {
			msg("Could not update character $char, doublechar is not array reference.\n") if ref($doublechar) ne 'ARRAY';
			msg("Could not update character $char, lines of doublechar have unequal lengths.\n")
				if Slim::Hardware::VFD::lineLength($doublechar->[0]) != Slim::Hardware::VFD::lineLength($doublechar->[1]);
		}
	}
}

# the font format string
#my $double = 
	# all digits are 3 chars wide
#	'0/~\01 /[12 ~)23 =)34]_[45]=~56 < 67 ~?78(=)89(=)9' .
#	'0\_/01  [12 <_23 _)34  [45 _)56(_)67 / 78(_)89 / 9' .
#	# kerning is custom so exclude blanks here except for 'I'
#	'A /\ AB]=)BC/~CD]~\DE]=EF]=FG/~ GH]_[HI [IJ  [J' .
#	'A]~~[AB]_)BC\_CD]_/DE]_EF] FG\=[GH] [HI [IJ]_[J' .
#	'K]/KL] LM]\/[MN]\[NO/~\OP]=)PQ/~\QR]=)RS(~S' .
#	'K]\KL]_LM]  [MN] [NO\_/OP]  PQ\_xQR] \RS_)S' .
#	'T~|~TU] [UV[]VW[  ]WX\/XY\/YZ~?Z' .
#	'T | TU]_[UV\/VW\/\/WX/\XY [YZ<_Z';
	
#my $kernL = '\~\]\?\_\<\=';
#my $kernR = '\~\[\<\_\\\\/';

my $kernL = qr/(?:$toplinechar|$rightvbar|$Ztop|_|$Zbottom|$doublelinechar)$/o;
my $kernR = qr/^(?:$toplinechar|$leftvbar|$Zbottom|_|$backslash|$slash)/o;

#
# double the height and width of line 2 of the display
#
sub doubleSize {
	my $client = shift;
	my ($line1, $line2) = (shift,shift);
	my ($newline1, $newline2) = ("", "");
	
	if (!defined($line2) || $line2 eq "") { $line2 = $line1; };
	$line2 =~ s/$cursorpos//g;
	$line2 =~ s/^(\s*)(.*)/$2/;
	
	$::d_ui && msg("undoubled line1: $line1\n");
	$::d_ui && msg("undoubled line2: $line2\n");
	$line2 =~ s/(?:Æ|æ)/AE/g;
	$line2 =~ s/(?:Œ|œ)/OE/g;
	my $lastch1 = "";
	my $lastch2 = "";
   
	my $lastchar = "";
	my $split = Slim::Hardware::VFD::splitString($line2);
	
	foreach my $char (@$split) {
		if (exists($doublechars{$char}) || exists($doublechars{Slim::Music::Info::matchCase($char)})) {
			my ($char1,$char2);
			if (!exists($doublechars{$char})) {
				$char = Slim::Music::Info::matchCase($char);
			}
			($char1,$char2)=  @{$doublechars{$char}};
			if ($char =~ /[A-Z]/ && $lastchar ne ' ' && $lastchar !~ /\d/) {
					if (($lastch1 =~ $kernL && $char1 =~ $kernR) ||
						 ($lastch2 =~ $kernL && $char2 =~ $kernR)) {
					
						if ($lastchar =~ /[CGLSTZ]/ && $char =~ /[COQ]/) {
							# Special cases to exclude kerning between
						} else {
						   $newline1 .= ' ';
						   $newline2 .= ' ';
						}
					}
			}
			$lastch1 = $char1;
			$lastch2 = $char2;
			$newline1 .= $char1;
			$newline2 .= $char2;
		} else {
			$::d_display && msg("Character $char has no double\n");
			next;
		}
		$lastchar = $char;
	}

	$newline1 = $newline1 . (' ' x (40 - Slim::Hardware::VFD::lineLength($newline1)));
	$newline2 = $newline2 . (' ' x (40 - Slim::Hardware::VFD::lineLength($newline1)));

	return ($newline1, $newline2);

}

1;
__END__


