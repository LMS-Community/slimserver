package Slim::Plugin::SlimTris::Plugin;

# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use base qw(Slim::Plugin::Base);

our $VERSION = substr(q$Revision: 1.7 $,10);

# constants
my $height = 4;
my $customchar = 1;

# flag to avoid loading custom chars multiple times
my $loadedcustomchar = 0;

#
# array of blocks
# star represents rotational pivot
#
my @blocks = (

	['x  ',
	 'x*x'],
	
	['x*xx'],

	['xx',
	 '*x'],

	[' x ',
	 'x*x'],

	['  x',
	 'x*x'],

	 );

#
# state variables
# intentionally not per-client for multi-player goodness
#
my @blockspix = ();
my @grid = ();
my $xpos = 0;
my $ypos = 0;
my $currblock = 0;
my $gamemode = 'attract';
my $score = 0;

# button functions for top-level home directory
sub defaultHandler {
		my $client = shift;
		if ($gamemode eq 'attract') {
			$gamemode = 'play';
			resetGame($client);
			$client->pushLeft();
			return 1;
		} elsif ($gamemode eq 'gameover') {
			$gamemode = 'attract';
			$client->pushLeft();
			return 1;
		}
		return 0;
}

sub defaultMap {
	my $class = shift;

	return {'play' => 'rotate_1'
		,'play.repeat' => 'rotate_1'
		,'add' => 'rotate_-1'
		,'add.repeat' => 'rotate_-1'
		,'play.single' => 'dead'
		,'play.hold'   => 'dead'
		,'add.single'  => 'dead'
		,'add.hold'    => 'dead'
	}
}

our %functions = (
	'rotate' => sub {
		my ($client,$funct,$functarg) = @_;
		if (defaultHandler($client)) {return};
		if ((!Slim::Hardware::IR::holdTime($client) || Slim::Hardware::IR::repeatCount($client,2,0)) && $functarg =~ /-?1/) {
			rotate($client, $functarg);
			$client->update();
		}
	},

	'knob' => sub {
			my ($client, $funct, $functarg) = @_;
			if (defaultHandler($client)) {return};
			my $knobPos   = $client->knobPos();
			if ($knobPos > $client->modeParam('listIndex')) {
				rotate($client, 1);
			} elsif ($knobPos < $client->modeParam('listIndex')) {
				rotate($client, -1);
			}
			$client->update();
			$client->modeParam('listIndex', $knobPos);			
	},

	'left' => sub  {
		my $client = shift;
		Slim::Buttons::Common::popModeRight($client);
		return;
	},
	'right' => sub  {
		my $client = shift;
		if (defaultHandler($client)) {return};
		while (move($client, 1,0)) {
			$client->update();
		}
		$client->update();
	},
	'up' => sub  {
		my $client = shift;
		if (defaultHandler($client)) {return};
		if (!Slim::Hardware::IR::holdTime($client) || Slim::Hardware::IR::repeatCount($client,2,0)) {
			move($client, 0,-1);
			$client->update();
		}
	},
	'down' => sub  {
		my $client = shift;
		if (defaultHandler($client)) {return};
		if (!Slim::Hardware::IR::holdTime($client) || Slim::Hardware::IR::repeatCount($client,2,0)) {
			move($client, 0,1);
			$client->update();
		}
	},
);
#
# start a random new block at the top
#
sub dropNewBlock {
	my $client = shift;
	$xpos = 3;
	$ypos = 2;
	$currblock = int(rand() * ($#blocks+1));
	# initial position of 4x1 block might overlap with border resulting in false Game Over
	if ($currblock == 1) {
		checkBorderConflict();
	}
	if (!move($client, 0,0)) {
		gameOver();
	}
}

#
# rotates a block if it can
#
sub rotate {
	my $client = shift;
	my $direction = shift;

	my $block = $blockspix[$currblock];
	foreach my $pixel (@$block)
	{
		my $temppix = @$pixel[0];
		@$pixel[0] = @$pixel[1] * -1 * $direction;
		@$pixel[1] = $temppix * $direction;
	}
	# check the position we rotated into and rotate back if it's bad
	if (!move($client, 0,0)) {
		rotate($client, -1 * $direction);
	}
}

#
# moves a block
# returns true if move was successful
# returns false if the move was blocked and doesn't move it
#
sub move {
	my $client = shift;
	my $xdelta = shift;
	my $ydelta = shift;

	if (checkBlock($xpos + $xdelta, $ypos + $ydelta)) {
		$xpos+=$xdelta;
		$ypos+=$ydelta;
		return (1);
	} else {
		#handle blocked move right specially
		if ($xdelta == 1)
		{
			my $block = $blockspix[$currblock];
			foreach my $pixel (@$block)
			{
				my $x = @$pixel[0] + $xpos;
				my $y = @$pixel[1] + $ypos;
				$grid[$x][$y] = 1;
			}
			cleanupGrid($client);
			dropNewBlock($client);
		}
		return (0);
	}
}

#
# remove full lines and shift the rest to compensate
#
# NOTE: stolen from Sean's perltris cause I suck
#
sub cleanupGrid {
	my $client = shift;
	my $scoremult = 0;

	my $width = $client->displayWidth() / 8 - 1;
	

COL:	for (my $x = $width; $x >= 1; $x--)
	{
		for (my $y = 1; $y < $height+1; $y++) {
			$grid[$x][$y] || next COL;
		}
		$scoremult *= 2;
		$scoremult = 100 if ($scoremult == 0);
	
		for (my $x2 = $x; $x2 >= 1; $x2--) {
			for (my $y = 1; $y < $height+1; $y++) {
				$grid[$x2][$y] = ($x2 > 2) ? $grid[$x2-1][$y] : 0;
			}
		}
		$x++;
	}
	$score += $scoremult;
}

#
# returns true if the block has no overlap with the grid
#
sub checkBlock {
	my $bx = shift;
	my $by = shift;

	my $block = $blockspix[$currblock];
	foreach my $pixel (@$block) {
		my $x = @$pixel[0] + $bx;
		my $y = @$pixel[1] + $by;
		return (0) if ($grid[$x][$y]);
	}
	return (1);
}


#
# adjust block position if overlap with grid border
#
sub checkBorderConflict {
	my $block = $blockspix[$currblock];
	my $upperConflict = 0;
	my $lowerConflict = 0;
	foreach my $pixel (@$block) {
		my $y = @$pixel[1] + $ypos;
		if ($y == 0) {
			$upperConflict = 1;
		} elsif ($y == ($height+1)) {
			$lowerConflict = 1;
		}
	}
	if ($upperConflict) {
		$ypos++;
	} elsif ($lowerConflict) {
		$ypos--;
	}
}

#
# convert from the asciii block picture to coordinate pairs
# all pairs are relative to the starred block for rotational goodness
#
sub loadBlocks {

	@blockspix = ();
	foreach my $block (@blocks)
	{
		my $y = 0;
		my @blockpix = ();
		my @center;
		foreach my $line (@$block) {
			my $x = 0;
			foreach my $char (split(//, $line)) { 
				if ($char eq '*') {
					@center = ($x, $y);
					push(@blockpix, [$x, $y]);
				} elsif ($char eq 'x') {
					push(@blockpix, [$x, $y]);
				}
				$x++;
			}
			$y++;
		}

		my @cenblockpix = ();

		foreach my $pix (@blockpix) {
			my $x = @$pix[0] - $center[0];
			my $y = @$pix[1] - $center[1];
			push(@cenblockpix, [$x, $y]);
		}

		push(@blockspix, \@cenblockpix);
	}
}

#
# initalize a grid with walls around the playing area
#
sub initGrid {
	my $client = shift;
	my $width = $client->displayWidth() / 8 - 1;
	for (my $x = 0; $x < $width+2; $x++) {
		for (my $y = 0; $y < $height+2; $y++) {
	
			if ($x == 0 || $y == 0 || $x == $width+1 || $y == $height+1) {
				$grid[$x][$y] = 1;	
			} else {
				$grid[$x][$y] = 0;
			}
		}
	}
}

sub resetGame {
	my $client = shift;
	loadBlocks();
	initGrid($client);
	dropNewBlock($client);
	$gamemode = 'play';
	$score = 0;
}

sub gameOver {
	$gamemode = 'gameover';
}

sub setMode {
	my $class  = shift;
	my $client = shift;

	$gamemode = 'attract';

	if ($customchar) {
		loadCustomChars($client);
	}

	$client->modeParam('modeUpdateInterval', 1);

	$client->modeParam('knobFlags', Slim::Player::Client::KNOB_NOACCELERATION());
	$client->modeParam('knobWidth', 4);
	$client->modeParam('knobHeight', 25);
	$client->modeParam('listIndex', 1000);
	$client->modeParam('listLen', 0);

	$client->lines(\&lines);
}

my $lastdrop = Time::HiRes::time();

my @bitmaps = (
	"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00",
	"\xe0\x00\xe0\x00\xe0\x00\xe0\x00\xe0\x00\x00\x00\x00",
	"\x0e\x00\x0e\x00\x0e\x00\x0e\x00\x0e\x00\x00\x00\x00",
	"\xee\x00\xee\x00\xee\x00\xee\x00\xee\x00\x00\x00\x00",
);

my @bitmaps2 = (
	"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00",
	"\x7f\x00\x00\x00\x55\x00\x00\x00\x6b\x00\x00\x00\x55\x00\x00\x00\x6b\x00\x00\x00\x7f\x00\x00\x00\x00\x00",
	"\x00\x7f\x00\x00\x00\x55\x00\x00\x00\x6b\x00\x00\x00\x55\x00\x00\x00\x6b\x00\x00\x00\x7f\x00\x00\x00\x00",
	"\x7f\x7f\x00\x00\x55\x55\x00\x00\x6b\x6b\x00\x00\x55\x55\x00\x00\x6b\x6b\x00\x00\x7f\x7f\x00\x00\x00\x00",
);

#
# figure out the lines to be put up to display the directory
#
sub lines {
	my $client = shift;
	my ($line1, $line2);

	my $parts;

	my $width = $client->displayWidth() / 8 - 1;
	
	if ($gamemode eq 'attract') {
		$parts = {
		    'center1' => "- S - L - I - M - T - R - I - S -",
		    'center2' => "1 coin 1 play",
		};
		return $parts;
	} elsif ($gamemode eq 'gameover') {
		$parts = {
		    'center1' => "Game over man, game over!",
		    'center2' => "Score: $score",
		};
		return $parts;
	}

	if (Time::HiRes::time() - $lastdrop > .5)
	{
		move($client, 1,0);
		cleanupGrid($client);
		$lastdrop = Time::HiRes::time();
	}

	# make a copy of the grid
	my @dispgrid = map [@$_], @grid;

	# overlay the current block on the grid
	my $block = $blockspix[$currblock];
	foreach my $pixel (@$block)
	{
		my $x = @$pixel[0] + $xpos;
		my $y = @$pixel[1] + $ypos;
		$dispgrid[$x][$y] = 1;
	}

	if ($client->display->isa( "Slim::Display::Squeezebox2")) {
		my $bits = '';
		for (my $x = 1; $x < $width+2; $x++)
			{	
				my $column = ($bitmaps2[$dispgrid[$x][1]] | $bitmaps2[$dispgrid[$x][2]*2]) . "\x00\x00";
				
				$column |= "\x00\x00" . ($bitmaps2[$dispgrid[$x][3]] | $bitmaps2[$dispgrid[$x][4]*2]);
				
				$bits .= $column;
			}
		$parts->{bits} = $bits;
	} elsif ($client->display->isa( "Slim::Display::SqueezeboxG")) {
		my $bits = '';
		for (my $x = 1; $x < $width+2; $x++)
			{	
				my $column = ($bitmaps[$dispgrid[$x][1]] | $bitmaps[$dispgrid[$x][2]*2]) . "\x00";
				
				$column |= "\x00" . ($bitmaps[$dispgrid[$x][3]] | $bitmaps[$dispgrid[$x][4]*2]);
				
				$bits .= $column;
			}
		$parts->{bits} = $bits;
	} else {
		my ($line1, $line2);
		for (my $x = 1; $x < $width+2; $x++)
			{
				$line1 .= grid2char($client, $dispgrid[$x][1] * 2 + $dispgrid[$x][2]);
				$line2 .= grid2char($client, $dispgrid[$x][3] * 2 + $dispgrid[$x][4]);
			}
		$parts = {
		    'line1' => $line1,
		    'line2' => $line2,
		};
	}
	return $parts;
}	

#
# convert numbers into characters.  should use custom characters.
#
sub grid2char {
	my $client = shift;
	my $val = shift;

	if ($customchar) {
		return " " if ($val == 0);
		return $client->symbols('slimtristop') if ($val == 1);
		return $client->symbols('slimtrisbottom') if ($val == 2);
		return $client->symbols('slimtrisboth') if ($val == 3);
	} else {
		return " " if ($val == 0);
		return "o" if ($val == 1);
		return "^" if ($val == 2);
		return "O" if ($val == 3);
	}
	warn "unrecognized grid value";
}

sub loadCustomChars {
	my $client = shift;

	return unless $client->display->isa('Slim::Display::Text');

	return if $loadedcustomchar;
	
	Slim::Display::Text::setCustomChar( 'slimtristop', ( 
		0b00000000, 
		0b00000000, 
		0b00000000, 
		0b00000000, 
		0b11111110, 
		0b11111111, 
		0b01111111,

		0b00000000
		));
	Slim::Display::Text::setCustomChar( 'slimtrisbottom', ( 
		0b11111110, 
		0b11111111, 
		0b01111111, 
		0b00000000, 
		0b00000000, 
		0b00000000, 
		0b00000000,
		
		0b00000000
		));
	Slim::Display::Text::setCustomChar( 'slimtrisboth', ( 
		0b11111110, 
		0b11111111, 
		0b01111111, 
		0b00000000, 
		0b11111110, 
		0b11111111, 
		0b01111111,
		
		0b00000000

#		0b00011111,
#                  0b00010101,
#                  0b00001010,
#                  0b00010101,
#                  0b00001010,
#                  0b00010101,
#                  0b00011111,
#                  0b00000000

		));
		
	$loadedcustomchar = 1;

}
	
sub getFunctions {
	my $class = shift;

    \%functions;
}

1;

__END__
