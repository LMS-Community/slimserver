package Slim::Player::SqueezeboxG;

# $Id$

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#

use strict;
use warnings;
use File::Spec::Functions qw(:ALL);
use FindBin qw($Bin);
use IO::Socket;
use Slim::Player::Player;
use Slim::Utils::Misc;

use base qw(Slim::Player::Squeezebox);

my $GRAPHICS_FRAMEBUF_LIVE    = (1 * 280 * 2);

our $defaultPrefs = {
	'activeFont'		=> [qw(small medium large huge)],
	'activeFont_curr'	=> 1,
	'idleFont'		=> [qw(small medium large huge)],
	'idleFont_curr'		=> 1,
	'idleBrightness'	=> 2,
};

sub new {
	my $class = shift;

	my $client = $class->SUPER::new(@_);

	return $client;
}

sub init {
	my $client = shift;
	# make sure any preferences unique to this client may not have set are set to the default
	Slim::Utils::Prefs::initClientPrefs($client,$defaultPrefs);
	$client->SUPER::init();
}

sub vfdmodel {
	return 'graphic-280x16';
}

sub displayWidth {
	return 280;
}

sub bytesPerColumn {
	return 2;
}

sub screenBytes {
	my $client = shift;
	return $client->bytesPerColumn() * $client->displayWidth();
}

my @brightnessMap = (0, 1, 4, 16, 30);

sub brightness {
	my $client = shift;
	my $delta = shift;
	
	my $brightness = $client->SUPER::brightness($delta, 1);

	if (defined($delta)) {
		my $brightnesscode = pack('n', $brightnessMap[$brightness]);
		$client->sendFrame('grfb', \$brightnesscode); 
	}

	return $brightness;
}

sub maxBrightness {
	return $#brightnessMap;
}

sub maxTextSize {
	my $client = shift;

	my $prefname = ($client->power()) ? "activeFont" : "idleFont";
	Slim::Utils::Prefs::clientGetArrayMax($client,$prefname);
}

sub textSize {
	my $client = shift;
	my $newsize = shift;
	
	# grab base for prefname depending on mode
	my $prefname = ($client->power()) ? "activeFont" : "idleFont";
	
	if (defined($newsize)) {
		return	Slim::Utils::Prefs::clientSet($client, $prefname."_curr", $newsize);
	} else {
		return	Slim::Utils::Prefs::clientGet($client, $prefname."_curr");
	}
}

sub linesPerScreen {
	my $client = shift;
	return (defined($client->fonts()->[0]) ? 2 : 1);
}

my %fontSymbols = (
	'notesymbol' => "\x01",
	'rightarrow' => "\x02",
	
	'progressEnd' => "\x03",
	'progress1e' => "\x04",
	'progress2e' => "\x05",
	'progress3e' => "\x06",
	'progress1' => "\x07",
	'progress2' => "\x08",
	'progress3' => "\x09",
	'cursor'	=> "\x0a",
	'mixable' => "\x0b",
	
	'hardspace' => "\x20"
);

sub update {
	my $client = shift;
	my $lines = shift;
	my $nodoublesize = shift;

	if ($client->param('noUpdate')) {
		#mode has blocked client updates temporarily
	} else { 
		$client->killAnimation();
		if (!defined($lines)) {
			my @lines = Slim::Display::Display::curLines($client);
			$lines = \@lines;
		}
	
		$client->drawFrameBuf($client->render($lines),$lines);
	}
}	

sub render {
	use bytes;
	my $client = shift;
	my $lines = shift;
	my $frameHeader = shift || '';

	my $parts;
	
	if ((ref($lines) eq 'HASH')) {
		$parts = $lines;
	} else {
		$parts = $client->parseLines($lines);
	}

	my $bits = '';
	my $otherbits = undef;
	my $fonts = $client->fonts();
	my $screensize = $client->screenBytes();
	my $line1same = 1;
	
	# check and see if the line 1 bits have already been rendered and use those.
	if (!defined($parts->{line1bits})) {
	    $client->prevline1($parts->{line1});	    
		$parts->{line1bits} = Slim::Display::Graphics::string($fonts->[0], $parts->{line1});
		$parts->{line1finish} = length($parts->{line1bits});
		$line1same = 0;
	}
		
	# check and see if the line 2 bits have already been rendered and use those.
	if (!defined($parts->{line2bits})) {
		$client->prevline2($parts->{line2});
		# if we're only displaying the second line (i.e. single line mode) and the second line is blank,
		# copy the first to the second.
		if (!defined($fonts->[0]) && $parts->{line2} eq '') { $parts->{line2} = $parts->{line1}; };
		$parts->{line2bits} = Slim::Display::Graphics::string($fonts->[1], $parts->{line2});
		$parts->{line2finish} = length($parts->{line2bits});
	}

	# get the first line overlay and use the rendered cached bits if possible
	if (!defined($parts->{overlay1bits})) {
		if (defined($parts->{overlay1})) {
			$parts->{overlay1bits} = Slim::Display::Graphics::string($fonts->[0], "\x00" . $parts->{overlay1});
			$parts->{overlay1start} = $screensize - length($parts->{overlay1bits});
			$line1same = 0;
		} else {
			$parts->{overlay1bits} = '';
			$parts->{overlay1start} = $screensize;
			$line1same = 0;
		}
	}
		
	# get the second line overlay and use the rendered cached bits if possible
	if (!defined($parts->{overlay2bits})) {
		if (defined($parts->{overlay2})) {
			$parts->{overlay2bits} = Slim::Display::Graphics::string($fonts->[1], "\x00" . $parts->{overlay2});
			$parts->{overlay2start} = $screensize - length($parts->{overlay2bits});
		} else {
			$parts->{overlay2bits} = '';
			$parts->{overlay2start} = $screensize;
		}
	}

	# fast bitmap assemble for scrolling and no changes - assume no other text
	if (defined($parts->{scrolling}) && $line1same) {
		$bits = $parts->{cache} | $frameHeader . substr($parts->{line2bits}, $parts->{offset2}, $parts->{overlay2start})
			. $parts->{overlay2bits};
		return \$bits;
	}
	
	# render other text - no caching
	if (defined($parts->{center1}) || defined($parts->{center2}) || $parts->{bits}) {
		my $center1 = '';
		my $center2 = '';
		if (defined($parts->{center1})) {
			$center1 = Slim::Display::Graphics::string($fonts->[0], $parts->{center1});
			$center1 = chr(0) x ( int( ($screensize-length($center1)) / ($client->bytesPerColumn()*2) )
					      * $client->bytesPerColumn() ) . $center1;
		}
	
		if (defined($parts->{center2})) {
			$center2 = Slim::Display::Graphics::string($fonts->[1], $parts->{center2});				
			$center2 = chr(0) x ( int( ($screensize-length($center2)) / ($client->bytesPerColumn()*2) )
					      * $client->bytesPerColumn() ) . $center2;
		}
		$line1same = 0;
		$otherbits = $frameHeader . substr($parts->{bits} | $center1 | $center2 , 0, $screensize);
	}

	# standard bitmap assemble
	# 1st line
	if ($parts->{line1finish} < $parts->{overlay1start}) {
		$parts->{cache} = $frameHeader . $parts->{line1bits}. chr(0) x ($parts->{overlay1start} - $parts->{line1finish}) 
			. $parts->{overlay1bits};
	} else {
		$parts->{cache} = $frameHeader . substr($parts->{line1bits}, 0, $parts->{overlay1start}). $parts->{overlay1bits};
	}
	# 2nd line
	$parts->{offset2} = 0 unless defined $parts->{offset2};
	if ($parts->{line2finish} < $parts->{overlay2start}) {
		$bits = $parts->{cache} | $frameHeader . $parts->{line2bits} 
		    . chr(0) x ($parts->{overlay2start} - $parts->{line2finish}) . $parts->{overlay2bits};
	} else {
		$bits = $parts->{cache} | $frameHeader . substr($parts->{line2bits}, $parts->{offset2}, $parts->{overlay2start}) 
			. $parts->{overlay2bits};
	}
	$bits |= $otherbits if defined $otherbits;

	return \$bits;
}

sub fonts {
	my $client = shift;
	my $size = shift;
	my $current;
	
	my $font;
	
	if (defined $client->param('font')) {
		$font = $client->param('font');
	} else {
		unless (defined $size) {$size = $client->textSize();}
		
		# grab base for prefname depending on mode
		my $prefname = ($client->power()) ? "activeFont" : "idleFont";
		$font	= Slim::Utils::Prefs::clientGet($client, $prefname, $size);
	}
	
	my $fontref = Slim::Display::Graphics::gfonthash();
	
	if (!$font) { return undef; };
	
	return $fontref->{$font};
}
	
# returns progress bar text
sub progressBar {
	return sliderBar(shift,shift,(shift)*100,0);
}

sub balanceBar {
	return sliderBar(shift,shift,shift,50);
}

# Draws a slider bar, bidirectional or single direction is possible.
# $value should be pre-processed to be from 0-100
# $midpoint specifies the position of the divider from 0-100 (use 0 for progressBar)
sub sliderBar {
	my $client = shift;
	my $width = shift;
	my $value = shift;
	my $midpoint = shift;
	my $sym;
	$midpoint = 0 unless defined $midpoint;
	if ($value < 0) {
		$value = 0;
	}
	
	if ($value > 100) {
		$value = 100;
	}
	
	if ($width == 0) {
		return "";
	}

	my $spaces = int($width) - 4;
	my $dots = int($value/100 * $spaces);
	my $divider = ($midpoint/100) * ($spaces);	
	if ($dots < 0) { $dots = 0 };
		
	my $chart = Slim::Display::Display::symbol('tight') . 
				Slim::Display::Display::symbol('progressEnd');
	
	my $i;

	if ($midpoint) {
		#left half
		for (my $i = 0; $i < $divider; $i++) {
			if ($value >= $midpoint) {
				if ($i == 0 || $i == $spaces/2 - 1) {
					$sym = 'progress1e';
				} elsif ($i == 1 || $i == $spaces/2 - 2) {
					$sym = 'progress2e';
				} else {
					$sym = 'progress3e';
				}
			} else {
				if ($i == 0 || $i == $divider - 1) {
					$sym = 'progress1';
				} elsif ($i == 1 || $i == $divider - 2) {
					$sym = 'progress2';
				} else {
					$sym = 'progress3';
				}
				if ($i < $dots) { $sym .= 'e' };
			}
			
			$chart .= Slim::Display::Display::symbol($sym);
		}
	
		$chart .= Slim::Display::Display::symbol('progressEnd');
	}
	
	# right half
	for ($i = $divider +1; $i < $spaces; $i++) {
		if ($value <= $midpoint) {
			if ($i == $divider +1 || $i == $spaces - 1) {
				$sym = 'progress1e';
			} elsif ($i == $divider + 2 || $i == $spaces - 2) {
				$sym = 'progress2e';
			} else {
				$sym = 'progress3e';
			}
		} else {
			if ($i == $divider +1 || $i == $spaces - 1) {
				$sym = 'progress1';
			} elsif ($i == $divider + 2 || $i == $spaces - 2) {
				$sym = 'progress2';
			} else {
				$sym = 'progress3';
			}
			if ($i > $dots) { $sym .= 'e' };
		}
		$chart .= Slim::Display::Display::symbol($sym);
	}

	$chart .= Slim::Display::Display::symbol('progressEnd') . 
			  Slim::Display::Display::symbol('/tight');
	return $chart;
}

sub measureText {
	my $client = shift;
	my $text = shift;
	my $line = shift;
	
	my $fonts = $client->fonts();

	my $len = Slim::Display::Graphics::measureText($fonts->[$line-1], $client->symbols($text));
	return $len;
}

sub symbols {
	my $client = shift;
	my $line = shift;
	
	if (defined($line)) {
		$line =~ s/\x1f([^\x1f]+)\x1f/$fontSymbols{$1} || "\x1F" . $1 . "\x1F"/eg;
		$line =~ s/\x1etight\x1e/\x1d/g;
		$line =~ s/\x1e\/tight\x1e/\x1c/g;
		$line =~ s/\x1ecursorpos\x1e/\x0a/g;
	}
	
	return $line;
}
	
sub drawFrameBuf {
	my $client = shift;
	my $framebufref = shift;
	my $parts = shift;
	if ($client->opened()) {
		my $framebuf = pack('n', $GRAPHICS_FRAMEBUF_LIVE) . $$framebufref;
		my $len = length($framebuf);
		if ($len != $client->screenBytes() + 2) {
			$framebuf = substr($framebuf .  chr(0) x $client->screenBytes(), 0, $client->screenBytes() + 2);
		}

		$client->sendFrame('grfd', \$framebuf);
	}
}	

# preformed frame header for fast scolling - contains header added by sendFrame and drawFrameBuf
sub scrollHeader {
	my $client = shift;
	my $header = 'grfd' . pack('n', $GRAPHICS_FRAMEBUF_LIVE);

	return pack('n', length($header) + $client->screenBytes ) . $header;
}

sub showBriefly {
	my $client = shift;
	my $line1 = shift;
	my $line2 = shift;
	my $duration = shift;
	my $firstLineIfDoubled = shift;
	my @lines = [$line1,$line2];

	$client->update(@lines);

	if (!$duration) {
		$duration = 1;
	}

	Slim::Utils::Timers::setTimer($client,Time::HiRes::time() + $duration,\&update);
	$client->animating(1);
}

# push the old screen off the left side
sub pushLeft {
	my $client = shift;
	my $start = shift;
	my $end = shift;

	my $startbits = $client->render($start);
	my $endbits = $client->render($end);
	
	my $allbits = $$startbits . $$endbits;

	$client->killAnimation();
	$client->pushUpdate([\$allbits, 0, $client->screenBytes() / 8, $client->screenBytes(),  0.025]);
}

# push the old lines (start1,2) off the right side
sub pushRight {
	my $client = shift;
	my $start = shift;
	my $end = shift;

	my $startbits = $client->render($start);
	my $endbits = $client->render($end);
	
	my $allbits = $$endbits . $$startbits;
	
	$client->killAnimation();
	$client->pushUpdate([\$allbits, $client->screenBytes(), 0 - $client->screenBytes() / 8, 0, 0.025]);
}

sub bumpRight {
	my $client = shift;
	my $startbits = $client->render(Slim::Display::Display::curLines($client));
	$startbits = $$startbits .  (chr(0) x 16);
	$client->killAnimation();
	$client->pushUpdate([\$startbits, 16, -8, 0, 0.125]);	
}

sub bumpLeft {
	my $client = shift;
	my $startbits = $client->render(Slim::Display::Display::curLines($client));
	$startbits =  (chr(0) x 16) . $$startbits;
	$client->killAnimation();
	$client->pushUpdate([\$startbits, 0, 8, 16, 0.125]);	
}

sub pushUpdate {
	my $client = shift;
	my $params = shift;
	my ($allbits, $offset, $delta, $end, $deltatime) = @$params;
	
	$offset += $delta;
	
	my $len = length($$allbits);
	my $screen;

	$screen = substr($$allbits, $offset, $client->screenBytes());
	
	$client->drawFrameBuf(\$screen);
	if ($offset != $end) {
		Slim::Utils::Timers::setTimer($client,Time::HiRes::time() + $deltatime,\&pushUpdate,[$allbits,$offset,$delta,$end,$deltatime]);
		$client->animating(1);
	} else {
		$client->animating(0);
	}
}

sub bumpDown {
	my $client = shift;

	my $startbits = $client->render(Slim::Display::Display::curLines($client));
	$startbits = substr((chr(0) . $$startbits) & ((chr(0) . chr(255)) x ($client->screenBytes() / 2)), 0, $client->screenBytes());

	$client->killAnimation();
	
	$client->drawFrameBuf(\$startbits);

	Slim::Utils::Timers::setTimer($client,Time::HiRes::time() + 0.125,\&update);
	$client->animating(1);
}

sub bumpUp {
	my $client = shift;
	my $startbits = $client->render(Slim::Display::Display::curLines($client));
	$startbits = substr(($$startbits . chr(0)) & ((chr(0) . chr(255)) x ($client->screenBytes() / 2)), 1, $client->screenBytes());
	
	$client->killAnimation();

	$client->drawFrameBuf(\$startbits);

	Slim::Utils::Timers::setTimer($client,Time::HiRes::time() + 0.125,\&update);
	$client->animating(1);
}


sub doEasterEgg {
	my $client = shift;
	$client->update();
}

sub scrollBottom {
	my $client = shift;
	my $lines = shift;
	return if $client->param('noScroll');
	
	my $rate = $client->paramOrPref($client->linesPerScreen() == 1 ? 'scrollRateDouble': 'scrollRate');
	my $pause = $client->paramOrPref($client->linesPerScreen() == 1 ? 'scrollPauseDouble': 'scrollPause');	
	my $pixels = $client->paramOrPref($client->linesPerScreen() == 1 ? 'scrollPixelsDouble': 'scrollPixels');	

	my $linefunc  = $client->lines();
	my $parts = $client->parseLines(&$linefunc($client));

	my $fonts = $client->fonts();
	
	my $interspace = '     ';
	
	my $line2bits = Slim::Display::Graphics::string($fonts->[1], $parts->{line2}) || '';
	my $overlay2bits = Slim::Display::Graphics::string($fonts->[1], $parts->{overlay2}) || '';

	if ($rate && ((length($line2bits) + length($overlay2bits)) > $client->screenBytes() )) {

		my $interspaceBits = Slim::Display::Graphics::string($fonts->[1], $interspace) || '';

		$parts->{line2} .= $interspace . $parts->{line2};
		$parts->{endscroll2} = length($line2bits) + length($interspaceBits);
		$parts->{scroll2} = $client->bytesPerColumn() * $pixels;
		$parts->{offset2} = 0;

		$parts->{updateInt} = 0.5; # update at least twice a second
		$parts->{pauseInt} = $pause;
		$parts->{updateTime} = Time::HiRes::time();
		$parts->{pauseUntil} = $parts->{updateTime} + $pause;
		$parts->{refresh} = $rate;
		$parts->{refreshTime} = $parts->{updateTime};
		$parts->{scrollHeader} = $client->scrollHeader;
		$parts->{scrollFrameSize} = length($client->scrollHeader) + $client->screenBytes;
		
		$client->killAnimation();
		$client->scrollUpdate($parts);
		$client->animating(1);

	} else {
		$client->refresh($parts);
	}
}

sub scrollUpdate {
	my $client = shift;
	my $parts = shift;
	
	my $timenow = Time::HiRes::time();

	# implement drawFrameBuf in here to avoid string copies
	my $framebuf = $client->render($parts, $parts->{scrollHeader} );
	if ($client->tcpsock && $client->tcpsock->connected && length($$framebuf) == $parts->{scrollFrameSize}) {
		Slim::Networking::Select::writeNoBlock($client->tcpsock, $framebuf);
	}

	if ($timenow > $parts->{updateTime}) {
		# get the latest content from line every updateInt
		# can take some time so do after updating screen
		$parts->{updateTime} += $parts->{updateInt};

		my $linefunc  = $client->lines();
		my $parts1 = $client->parseLines(&$linefunc($client));

		my $oldline1 = $parts->{line1};
		my $newline1 = $parts1->{line1};
	
		if (defined($oldline1) && defined($newline1) && $oldline1 ne $newline1) {
			$parts->{line1} = $newline1;
			$parts->{line1bits} = undef;
		}
	
		my $oldoverlay = $parts->{overlay1};
		my $newoverlay = $parts1->{overlay1};	

		if (defined($oldoverlay) && defined($newoverlay) && $oldoverlay ne $newoverlay) {
			$parts->{overlay1} = $newoverlay;
			$parts->{overlay1bits} = undef;
		}

	}

	if ($timenow < $parts->{pauseUntil}) {
		# slow timer for updates during scrolling pause
		$parts->{refreshTime} = $parts->{updateTime};
		Slim::Utils::Timers::setTimer($client, $parts->{updateTime}, \&scrollUpdate, $parts);

	} else {

		# update refresh time and skip frame if running behind actual timenow
		do {
			$parts->{offset2} += $parts->{scroll2};
			$parts->{refreshTime} += $parts->{refresh};
		} while ($parts->{refreshTime} < Time::HiRes::time() );

		$parts->{scrolling} = 1;

		if ($parts->{offset2} > $parts->{endscroll2}) {
			$parts->{offset2} = 0;
			if ($parts->{pauseInt} > 0) {
				$parts->{pauseUntil} = $parts->{refreshTime} + $parts->{pauseInt};
				$parts->{scrolling} = undef;
			}
		}
		# fast timer during scroll
		Slim::Utils::Timers::setTimer($client, $parts->{refreshTime}, \&scrollUpdate, $parts);
	}
}

# find all the queued up animation frames and toss them
sub killAnimation {
	my $client = shift;
	$client->param('noUpdate',0);
	Slim::Utils::Timers::killTimers($client, \&pushUpdate);
	Slim::Utils::Timers::killTimers($client, \&update);
	Slim::Utils::Timers::killTimers($client, \&scrollUpdate);
	$client->animating(0);
}

sub endAnimation {
	my $client = shift;
	$client->param('noUpdate',0); 
	$client->update();
}

1;
