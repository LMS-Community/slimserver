package Slim::Hardware::VFD;

# $Id: VFD.pm,v 1.1 2003/07/18 19:42:14 dean Exp $

# SliMP3 Server Copyright (C) 2001 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use Slim::Utils::Misc;

my %vfdCommand = ();

# the display packet header
my $header = 'l                 ';

# these codes identify the operation to 
# perform on each byte of data sent.
my $vfdCodeCmd  = pack 'B8', '00000010';       
my $vfdCodeChar = pack 'B8', '00000011'; 

# vfd.pl initiliazion:  Builds %vfdCommand, an associative array containing the 
# packed codes for all the noritake VFD commands
$vfdCommand{"CFF"}		= pack 'B8', "00001100";
$vfdCommand{"CUR"}		= pack 'B8', "00001110";

$vfdCommand{"HOME"} 	= pack 'B8', "00000010";
$vfdCommand{"HOME2"} 	= pack 'B8', "11000000";

$vfdCommand{"INCSC"} 	= pack 'B8', "00000110";

my @vfdBright = ( (pack 'B8', "00000011"), # 0%
				  (pack 'B8', "00000011"), # 25%
				  (pack 'B8', "00000010"), # 50%
				  (pack 'B8', "00000001"), # 75%
				  (pack 'B8', "00000000")); # 100%

my @vfdBrightFutaba = ( (pack 'B8', "00111011"), # 0%
				   (pack 'B8', "00111011"), # 25%
				   (pack 'B8', "00111010"), # 50%
				   (pack 'B8', "00111001"), # 75%
				   (pack 'B8', "00111000")); # 100%

my $noritakeBrightPrelude = 
			   $vfdCodeCmd .  (pack 'B8', "00110011") . 
			   $vfdCodeCmd .  (pack 'B8', "00000000") .
			   $vfdCodeCmd .  (pack 'B8', "00110000") .
			   $vfdCodeChar;

my $vfdReset = $vfdCodeCmd . $vfdCommand{"INCSC"} . $vfdCodeCmd . $vfdCommand{"HOME"};
$Slim::Hardware::VFD::MAXBRIGHTNESS = 4;

my %vfdcustomchars;

my %symbolmap = (
	'katakana' => {
		'notesymbol' => chr(0x0e),
		'rightarrow' => chr(0x0f),
		'leftvbar' => chr(0x10),
		'rightvbar' => chr(0x18),
		'hardspace' => chr(0x20),
	},
	'latin1' => {
		'rightarrow' => chr(0x1a),
		'hardspace' => chr(0x20),
	},
	'european' => {
		'rightarrow' => chr(0x7e),
		'hardspace' => chr(0x20),
	}
);

# these get remapped in the iso -> vfd conversion
#
sub symbol {
	my $symname = shift;
	if ($symname eq 'cursorpos' || $symname eq 'center') { 
		return ('__'.$symname.'__');
	} else {
		return ('vfD_'. $symname . '_Vfd');
	}
}

#
# Given the address of the character to edit, followed by an array of eight numbers specifying
# the bitmask of the character, caches the codes needed to create the specified character.
#
sub setCustomChar {
	my($charname, @rows)=@_;
	
	die unless ((@rows) == 8); 

	$vfdcustomchars{$charname} = \@rows;
}

sub lineLength {
	my $line = shift;
	return 0 unless length($line);

	$line =~ s/vfD_[^_]+_Vfd/x/g;
	$line =~ s/(__cursorpos__|__center__|\n)//g;
	return length($line);
}

sub splitString {
	my $string = shift;
	my @result = ();
	$string =~ s/(vfD_[^_]+_Vfd|__cursorpos__|__center__|.)/push @result, $1;/eg;
	return \@result;
}

sub subString {
	my ($string,$start,$length,$replace) = @_;
	my $newstring = '';
	my $oldstring = '';
	
	if ($string =~ s/^((?:vfD_[^_]+_Vfd|(?:__(?:cursorpos|center)__)?(?:__(?:cursorpos|center)__)(?:vfD_[^_]+_Vfd|.)|.){0,$start})//) {
		$oldstring = $1;
	}
	
	if (defined($length)) {
		if ($string =~ s/^((?:vfD_[^_]+_Vfd|(?:__(?:cursorpos|center)__)?(?:__(?:cursorpos|center)__)(?:vfD_[^_]+_Vfd|.)|.){0,$length})//) {
			$newstring = $1;
		}
		if (defined($replace)) {
			$_[0] = $oldstring . $replace . $string;
		}
	} else {
		$newstring = $string;
	}
	return $newstring;
}
	
#
# Adjust display brightness by delta (-3 to +3)
#
sub vfdBrightness {
	my ($client,$delta) = @_;

	if (defined($delta) ) {
		if ($delta =~ /[\+\-]\d+/) {
			$client->vfdbrightness( $client->vfdbrightness() + $delta );
		} else {
			$client->vfdbrightness( $delta );
		}
		
		$client->vfdbrightness(0) if ($client->vfdbrightness() < 0);
		$client->vfdbrightness(4) if ($client->vfdbrightness() > 4);
	
		my $temp1 = $client->prevline1();
		my $temp2 = $client->prevline2();
	
		vfdUpdate($client, $temp1, $temp2, 1);
	}
	
	return $client->vfdbrightness();
}

sub vfdUpdate {
	my $client = shift;
	my $line1  = shift; 
	my $line2  = shift;
	my $noDoubleSize = shift; #to suppress the doublesize call (in case the input lines have already been doubled)
	my @custom;
	my $cur = -1;
	my $pos;
	my %customChars;
	my $customCharCount = 0;
	my @customCharBitmaps;
	my $double;
	
	# convert to the VFD char set
	my $lang = $client->vfdmodel;
	if (!$lang) { 
		$lang = 'katakana';
	} else {
		$lang =~ s/[^-]*-(.*)/$1/;
	}

	$::d_ui && msg("vfdUpdate $lang\nline1: $line1\nline2: $line2\n\n");
	
	
	my $vfdbrightness = Slim::Hardware::VFD::vfdBrightness($client);

	if (!defined($line1)) { $line1 = '' };
	if (!defined($line2)) { $line2 = '' };

	# don't display carriage returns
	$line1 =~ s/\n//g;
	$line2 =~ s/\n//g;
		
	if (Slim::Utils::Prefs::clientGet($client,'doublesize') && !$noDoubleSize) {
		($line1, $line2) = Slim::Display::Display::doubleSize($client,$line1, $line2);
		$double = 1;
	}

	$client->prevline1($line1);
	$client->prevline2($line2);
	
	if (defined($vfdbrightness) && ($vfdbrightness == 0)) {
		$line1 = '';
		$line2 = '';
	} 
	
	my $line;

	my $centerspaces=0;
	foreach my $curline ($line1, $line2) {
		my $i = 0;
		my $linepos = 0;

		# make line exactly 40 chars
		$curline = subString($curline . (' ' x 40), 0, 40);
			
		while (1) {
			# if we're done with the line, break;
			if ($linepos > length($curline)) {
				last;
			}

			# get the next character
			my $scan = substr($curline, $linepos);
			
			# if this is a cursor position token, remember the location and go on
			if ($scan =~ /^__cursorpos__/) {
				$cur = length($line);
				$linepos += length('__cursorpos__');
				redo;
			# is this a center character?
			} elsif (index($scan, symbol('center') ) == 0)  {
				# remove the center symbol#
				$curline = substr($curline, length(symbol('center')));
				# have we centered before?  if so, use the 
				if (!$double || !$centerspaces) {
					# do the work to $curline and re-start loop
					# trim line to ensure proper centering
					$curline =~ s/\s*$//;
					#now center the line, but take into
					# account odd and even lengths for kerning
					$centerspaces = int((40-lineLength($curline))/2);
				}
				$curline = (" " x $centerspaces).$curline;
				# reset to exactly 40 chars long
				$curline = subString($curline . (' ' x 40), 0, 40);
				redo;
			# if this is a custom character, process it
			} elsif ($scan =~ /^vfD_([^_]+)_Vfd/) {
				$linepos += length('vfD_' . $1 . '_Vfd');
				# is it one of our existing symbols?
				if ($symbolmap{$lang} && $symbolmap{$lang}{$1}) {
					$line .= $symbolmap{$lang}{$1};
				} else {
					# must be a custom character, check if we have it already mapped
					if (exists($customChars{$1})) {
						$line .= $customChars{$1};
					# if we've already used up all 8, then just put in a space
					} elsif ($customCharCount == 8) {
						$line .= ' ';
					# remember the character bits and use the identifier.
					} else {
						$customCharBitmaps[$customCharCount] = $vfdcustomchars{$1};
						$customChars{$1} = chr($customCharCount);
						$line .= $customChars{$1};
						$customCharCount++;
					}
				}
				$i++;
			# it must just be a regular character, whew...
			} else {
				$line .= substr($scan, 0, 1);
				$linepos++;
				$i++
			}	
		}
	}
	
	if ($lang eq 'latin1') {
		# golly, the latin1 character map _is_ latin1;
		#		$line =~ tr{}
		#				   {};
	} elsif ($lang eq 'european') {
		# why can't we all just get along?
		$line =~ tr{\xa1\xa2\xa3\xa4\xa5\xa6\xa8\xa9\xab\xad\xaf \xbb\xbf \xc0\xc1\xc2\xc3\xc4\xc5\xc6\xc7\xc8\xc9\xca\xcb\xcc\xcd\xce\xcf \xd0\xd1\xd2\xd3\xd4\xd5\xd6\xd7\xd8\xd9\xda\xdb\xdc\xdd\xde\xdf \xe0\xe1\xe2\xe3\xe4\xe5\xe6\xe7\xe8\xe9\xea\xeb\xec\xed\xee\xef \xf0\xf1\xf2\xf3\xf4\xf5\xf6\xf7\xf8\xf9\xfa\xfb\xfc\xfd\xfe\xff}
				   {\x21\x63\x4c\x6f\x59\x7c\x22\x63\x22\x2d\x2d \x22\xeb \xb4\xb3\xd3\xb2\xf1\xf3\xce\xc9\xb8\xb7\xd6\xf7\xf0\xb0\xd0\xb1 \xcb\xde\xaf\xbf\xdf\xcf\xef\x78\x30\xb6\xb5\xf4\xd4\x59\xfb\xe2 \xa4\xa3\xc3\xa2\xe1\xc3\xbe\xc9\xa8\xa7\xc6\xe7\xe0\xa0\xc0\xa1 \xab\xee\xaf\xbf\xdf\xcf\xef\x2f\xbd\xa6\xa5\xe4\xf5\xac\xfb\xcc};
	} else {
		# translate iso8859-1 to vfd charset
		$line =~ tr{\x0e\x0f\x5c\x70\x7e\x7f\xa0\xa1\xa2\xa3\xa4\xa5\xa6\xa7\xa8\xa9\xaa\xab\xac\xad\xae\xaf\xb0\xb1\xb2\xb3\xb4\xb5\xb6\xb7\xb8\xb9\xba\xbb\xbc\xbd\xbe\xbf\xc0\xc1\xc2\xc3\xc4\xc5\xc6\xc7\xc8\xc9\xca\xcb\xcc\xcd\xce\xcf\xd0\xd1\xd2\xd3\xd4\xd5\xd6\xd7\xd8\xd9\xda\xdb\xdc\xdd\xde\xdf\xe0\xe1\xe2\xe3\xe4\xe5\xe6\xe7\xe8\xe9\xea\xeb\xec\xed\xee\xef\xf0\xf1\xf2\xf3\xf4\xf5\xf6\xf7\xf8\xf9\xfa\xfb\xfc\xfd\xfe\xff}
				   {\x19\x7e\x8c\xf0\x8e\x8f\x20\x98\xec\x92\xeb\x5c\x98\x8f\xde\x63\x61\x3c\xa3\x2d\x72\xb0\xdf\xb7\x32\x33\x60\xe4\xf1\x94\x2c\x31\xdf\x3e\x25\x25\x25\x3f\x81\x81\x82\x82\x80\x81\x90\x99\x45\x45\x45\x45\x49\x49\x49\x49\x44\xee\x4f\x4f\x4f\x4f\x86\x78\x30\x55\x55\x55\x8a\x59\x70\xe2\x84\x83\x84\x84\xe1\x84\x91\x99\x65\x65\x65\x65\x69\x69\x69\x69\x95\xee\x6f\x6f\x6f\x6f\xef\xfd\x88\x75\x75\x75\xf5\x79\xf0\x79};	
	}	
	
	# start calculating the control strings
	
	my $vfddata = $header;
	my $vfdmodel = $client->vfdmodel();

	# force the display out of 4 bit mode if it got there somehow, then set the brightness
	if ( $vfdmodel =~ 'futaba') {
		$vfddata .= $vfdCodeCmd .  $vfdBrightFutaba[$vfdbrightness];
	} else {
		$vfddata .= $noritakeBrightPrelude . $vfdBright[$vfdbrightness];
	}

	# include the custom character maps, if any
	if ($customCharCount) {
		my $i = 0;
		foreach my $bitmapref (@customCharBitmaps) {
			my $bitmap = pack ('C8', @$bitmapref);
			$bitmap =~ s/(.)/$vfdCodeChar$1/gos;
			$vfddata .= $vfdCodeCmd . pack('C',0b01000000 + ($i * 8)) . $bitmap;
			$i++;			
		}
	}	
	
	# put us in incrementing mode and move the cursor home
	$vfddata .= $vfdReset;
	$vfddata .= $vfdCodeCmd . $vfdCommand{"CFF"};
	# include our actual character data
	$line =~ s/(.)/$vfdCodeChar$1/gos;
	
	# split the line in two and move the cursor to the second line
	$line = substr($line, 0, 80) . $vfdCodeCmd . $vfdCommand{"HOME2"} . substr($line, 80);

	$vfddata .= $line;
	
	# set the cursor
	if ($cur >= 0) {
		if ($cur < 40) {
			$vfddata .= $vfdCodeCmd.(pack 'C', (0b10000000 + $cur));
		} else {
			$vfddata .= $vfdCodeCmd.(pack 'C', (0b11000000 + $cur - 40));
		}
		# turn on  the cursor			
		$vfddata .= $vfdCodeCmd. $vfdCommand{'CUR'};
	}

	Slim::Networking::Protocol::sendClient($client, $vfddata);
	
	my $len = length($vfddata);
	die "Odd vfddata: $vfddata" if ($len % 2);
	die "VFDData too long: $len bytes: $vfddata" if ($len > 500);
}

1;
