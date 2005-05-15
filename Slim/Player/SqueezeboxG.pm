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

	# init renderCache for client
	my $cache = {
		'changed'      => 0,        # last render resulted in no change to screen
		'scrolling'    => 0,        # last render enabled line2 scroll mode
		'newscrollbits'=> 0,        # change to scroll bits on last render
		'bitsref'      => undef,    # ref to bitmap result of last render
		'fonts'        => 0,        # font used for last render
		'screensize'   => 0,        # screensize for last render [0 forces reset on first render]
		'line1'        => undef,    # line1 text at last render
		'line1bits'    => '',       # result of rendering above line1
		'line1finish'  => 0,        # length of line1 bits
		'line2'        => undef,    # line2 text at last render
		'line2bits'    => '',       # result of rendering line2 if not scrolling
		'line2finish'  => 0,        # length of line2 bits
		'scrollbitsref'=> undef,    # ref to result of rendering line2 if scrolling required
		'endscroll'    => 0,        # offset for ending scroll at
		'overlay1'     => undef,    # overlay1 at last render
		'overlay1bits' => '',       # result of rendering overlay1
		'overlay1start'=> 0,        # start position for overlay1 
		'overlay2'     => undef,    # overlay2 at last render
		'overlay2bits' => '',       # result of rendering overlay2
		'overlay2start'=> 0,        # start position for overlay2 
		'center1'      => undef,    # center1 at last render 
		'center1bits'  => '',       # result of rendering center1
		'center2'      => undef,    # center2 at last render
		'center2bits'  => '',       # result of rendering center2
		'line2height'  => 0,        # height of line2 fonts - scrollable portion
	};
	$client->renderCache($cache);

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

sub displayHeight {
	return bytesPerColumn() * 8;
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

sub upgradeFont {
	return 'small';
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
	return (defined($client) &&
			defined($client->fonts()) &&
			defined($client->fonts()->[0])    ? 2 : 1);
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

sub render {
	use bytes;
	my $client = shift;
	my $lines = shift;
	my $scroll = shift || 0; # horiz line 2 scroll mode enabled if set and line2 too long

	my $parts;
	
	if ((ref($lines) eq 'HASH')) {
		$parts = $lines;
	} else {
		$parts = $client->parseLines($lines);
	}

	my $cache = $client->renderCache();
	$cache->{changed} = 0;
	$cache->{newscrollbits} = 0;

	my $screensize = $client->screenBytes();
	if ($screensize != $cache->{screensize}) {
		$cache->{screensize} = $screensize;
		$cache->{changed} = 1;
	}

	my $fonts = defined($parts->{fonts}) ? $parts->{fonts} : $client->fonts();
	if ($fonts != $cache->{fonts}) {
		$cache->{fonts} = $fonts;
		$cache->{line2height} = Slim::Display::Graphics::extent($fonts->[1]);
		$cache->{changed} = 1;
	}

	if ($cache->{changed}) {
		# force full rerender with new font or new screensize
		$cache->{scrolling} = 0;
		$cache->{line1} = undef;
		$cache->{line1bits} = '';
		$cache->{line1finish} = 0;
		$cache->{line2} = undef;
		$cache->{line2bits} = '';
		$cache->{line2finish} = 0;
		$cache->{scrollbitsref} = undef;
		$cache->{overlay1} = undef;
		$cache->{overlay1bits} = '';
		$cache->{overlay1start} = $screensize;
		$cache->{overlay2} = undef;
		$cache->{overlay2bits} = '';
		$cache->{overlay2start} = $screensize;
		$cache->{center1} = undef;
		$cache->{center1bits} = '';
   		$cache->{center2} = undef;
		$cache->{center2bits} = '';
	}

	# if we're only displaying the second line (i.e. single line mode) and the second line is blank,
	# copy the first to the second.
	if (!defined($fonts->[0]) && $parts->{line2} eq '') { $parts->{line2} = $parts->{line1}; }
	
	# line 1 - render if changed
	if (defined($parts->{line1}) && (!defined($cache->{line1}) || ($parts->{line1} ne $cache->{line1}))) {
		$cache->{line1} = $parts->{line1};
		$cache->{line1bits} = Slim::Display::Graphics::string($fonts->[0], $parts->{line1});
		$cache->{line1finish} = length($cache->{line1bits});
		$cache->{changed} = 1;
	} elsif (!defined($parts->{line1}) && defined($cache->{line1})) {
		$cache->{line1} = undef;
		$cache->{line1bits} = '';
		$cache->{line1finish} = 0;
		$cache->{changed} = 1;
	}

	# line 2 - render if changed
	if (defined($parts->{line2}) && 
		(!defined($cache->{line2}) || ($parts->{line2} ne $cache->{line2}) || (!$scroll && $cache->{scrolling}) )) {
		$cache->{line2} = $parts->{line2};
		$cache->{line2bits} = Slim::Display::Graphics::string($fonts->[1], $parts->{line2});
		$cache->{scrollbitsref} = undef;
		$cache->{scrolling} = 0;
		$cache->{line2finish} = length($cache->{line2bits});
		$cache->{changed} = 1;
	} elsif (!defined($parts->{line2}) && defined($cache->{line2})) {
		$cache->{line2} = undef;
		$cache->{line2bits} = '';
		$cache->{line2finish} = 0;
		$cache->{changed} = 1;
		$cache->{scrolling} = 0;
		$cache->{scrollbitsref} = undef;
	}

	# overlay 1 - render if changed
	if (defined($parts->{overlay1}) && (!defined($cache->{overlay1}) || ($parts->{overlay1} ne $cache->{overlay1}))) {
		$cache->{overlay1} = $parts->{overlay1};
		$cache->{overlay1bits} = Slim::Display::Graphics::string($fonts->[0], "\x00" . $parts->{overlay1});
		if (length($cache->{overlay1bits}) > $screensize ) {
			$cache->{overlay1bits} = substr($cache->{overlay1bits}, 0, $screensize);
		}
		$cache->{overlay1start} = $screensize - length($cache->{overlay1bits});
		$cache->{changed} = 1;
	} elsif (!defined($parts->{overlay1}) && defined($cache->{overlay1})) {
		$cache->{overlay1} = undef;
		$cache->{overlay1bits} = '';
		$cache->{overlay1start} = $screensize;
		$cache->{changed} = 1;
	}

	# overlay 2 - render if changed
	if (defined($parts->{overlay2}) && (!defined($cache->{overlay2}) || ($parts->{overlay2} ne $cache->{overlay2}))) {
		$cache->{overlay2} = $parts->{overlay2};
		$cache->{overlay2bits} = Slim::Display::Graphics::string($fonts->[1], "\x00" . $parts->{overlay2});
		if (length($cache->{overlay2bits}) > $screensize ) {
			$cache->{overlay2bits} = substr($cache->{overlay2bits}, 0, $screensize);
		}
		$cache->{overlay2start} = $screensize - length($cache->{overlay2bits});
		$cache->{changed} = 1;
	} elsif (!defined($parts->{overlay2}) && defined($cache->{overlay2})) {
		$cache->{overlay2} = undef;
		$cache->{overlay2bits} = '';
		$cache->{overlay2start} = $screensize;
		$cache->{changed} = 1;
	}

	# center 1 - render if changed
	if (defined($parts->{center1}) && (!defined($cache->{center1}) || ($parts->{center1} ne $cache->{center1}))) {
		$cache->{center1} = $parts->{center1};
		my $center1 = Slim::Display::Graphics::string($fonts->[0], $parts->{center1});
		$center1 = chr(0) x ( int( ($screensize-length($center1)) / ($client->bytesPerColumn()*2) )
					      * $client->bytesPerColumn() ) . $center1;
		$cache->{center1bits} = substr($center1, 0, $screensize);
		$cache->{changed} = 1;
	} elsif (!defined($parts->{center1}) && defined($cache->{center1})) {
		$cache->{center1} = undef;
		$cache->{center1bits} = '';
		$cache->{changed} = 1;
	}

	# center 2 - render if changed
	if (defined($parts->{center2}) && (!defined($cache->{center2}) || ($parts->{center2} ne $cache->{center2}))) {
		$cache->{center2} = $parts->{center2};
		my $center2 = Slim::Display::Graphics::string($fonts->[1], $parts->{center2});
		$center2 = chr(0) x ( int( ($screensize-length($center2)) / ($client->bytesPerColumn()*2) )
					      * $client->bytesPerColumn() ) . $center2;
		$cache->{center2bits} = substr($center2, 0, $screensize);
		$cache->{changed} = 1;
	} elsif (!defined($parts->{center2}) && defined($cache->{center2})) {
		$cache->{center2} = undef;
		$cache->{center2bits} = '';
		$cache->{changed} = 1;
	}
			
	# Assemble components

	my $bits;

	# 1st line
	if ($cache->{line1finish} < $cache->{overlay1start}) {
		$bits = $cache->{line1bits}. chr(0) x ($cache->{overlay1start} - $cache->{line1finish}) 
			. $cache->{overlay1bits};
	} else {
		$bits = substr($cache->{line1bits}, 0, $cache->{overlay1start}). $cache->{overlay1bits};
	}
	# Add 2nd line
	if ($cache->{line2finish} < $cache->{overlay2start}) {
		$bits |= $cache->{line2bits}. chr(0) x ($cache->{overlay2start} - $cache->{line2finish}) 
			. $cache->{overlay2bits};
	} else {
		if ($scroll) {
			# enable line 2 scrolling, remove line2bits from base display and move to scrollbits
			if ($cache->{line2finish} != 0) {
				my $scrollbits = $cache->{line2bits} .  chr(0) x (40 * $client->bytesPerColumn()) . $cache->{line2bits};
				$cache->{scrollbitsref} = \$scrollbits;
				$cache->{line2bits} = '';
				$cache->{endscroll} = $cache->{line2finish} + (40 * $client->bytesPerColumn());
				$cache->{line2finish} = 0;
				$cache->{scrolling} = 1;
				$cache->{newscrollbits} = 1;

			}
			$bits |= chr(0) x $cache->{overlay2start} . $cache->{overlay2bits};

		} else {
			# scrolling not enabled - truncate line2
			$bits |= substr($cache->{line2bits}, 0, $cache->{overlay2start}). $cache->{overlay2bits};
		}
	}

	# Add other bits
	if (defined($cache->{center1})) { 
		$bits |= $cache->{center1bits};
	}
	if (defined($cache->{center2})) { 
		$bits |= $cache->{center2bits};
	}
	if (defined($parts->{bits}) && length($parts->{bits})) { 
		$bits |= substr($parts->{bits}, 0, $screensize);
		$cache->{changed} = 1;
	}

	$cache->{bitsref} = \$bits;

	return $cache;
}

# Update and animation routines use $client->updateMode() and $client->animateState(), $client->scrollState()
#
# updateMode: 
#   0 = normal
#   1 = periodic updates are blocked
#   2 = all updates are blocked
#
# animateState: 
#   0 = no animation
#   1 = client side push/bump animations
#   2 = update scheduled (timer set to callback update)
#   3 = server side push & bumpLeft/Right
#   4 = server side bumpUp/Down
#   5 = server side showBriefly
#
# scrollState:
#   0 = no scrolling
#   1 = server side scrolling
#  2+ = <reserved for client side scrolling>

sub update {
	my $client = shift;
	my $lines = shift;
	my $nodoublesize = shift;    # backwards compatibility - not used
	my $scrollMode = shift || 0; # 0 = normal scroll, 1 = scroll once only, 2 = no scroll

	# return if updates are blocked
	return if ($client->updateMode() == 2);

	# clear any server side animations or pending updates, don't kill scrolling
	$client->killAnimation(1) if ($client->animateState() >= 2);

	my $scroll = ($scrollMode == 0 || $scrollMode == 1) ? 1: 0;
	my $scrollonce = ($scrollMode == 1) ? 1 : 0;

	my $render;

	if (defined($lines)) {
		$render = $client->render($lines, $scroll);
	} else {
		my $linefunc  = $client->lines();
		my $parts = $client->parseLines(&$linefunc($client));
		$render = $client->render($parts, $scroll);
	}

	if (!$render->{scrolling}) {
		# lines don't require scrolling
		if ($client->scrollState() == 1) {
			$client->scrollStop();
		}
		
		# only refresh screen if changed - once SB1 supports this and SB2 does not need the visu frames
		#$client->drawFrameBuf($render->{bitsref}) if $render->{changed};
		# for now always refresh screen:
		$client->drawFrameBuf($render->{bitsref});
	} else {
		if ($client->scrollState() != 1) {
			# start scrolling - new scolling text
			$client->scrollInit($render, $scrollonce);
		} elsif ($render->{newscrollbits}) {
			# new scrolling text and background - restart 
			$client->scrollStop();
			$client->scrollInit($render, $scrollonce);
		} else {
			# same scrolling text, possibly new background
			# for the moment always update it
			# later only do so if $render->{changed}
			# [currently need for SB1 in pause mode and SB2 to trigger visu frames]
			$client->scrollUpdateBackground($render);
		}			  
	}
}

sub prevline1 {
	my $client = shift;
	my $cache = $client->renderCache();
	return $cache->{line1};
}

sub prevline2 {
	my $client = shift;
	my $cache = $client->renderCache();
	return $cache->{line2};
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
	my $blockUpdate = shift;

	# return if update blocked
	return if ($client->updateMode() == 2);

	my @lines = [$line1,$line2];
	$client->update(@lines);
	
	if (!$duration) {
		$duration = 1;
	}
	
	$client->updateMode( $blockUpdate ? 2 : 1 );
	$client->animateState(5);
	Slim::Utils::Timers::setTimer($client,Time::HiRes::time() + $duration, \&endAnimation);
}

# push the old screen off the left side
sub pushLeft {
	my $client = shift;
	my $start = shift;
	my $end = shift;

	my $startbits = $client->render($start)->{bitsref};
	my $endbits = $client->render($end)->{bitsref};
	
	my $allbits = $$startbits . $$endbits;

	$client->killAnimation();
	$client->pushUpdate([\$allbits, 0, $client->screenBytes() / 8, $client->screenBytes(),  0.025]);
}

# push the old lines (start1,2) off the right side
sub pushRight {
	my $client = shift;
	my $start = shift;
	my $end = shift;

	my $startbits = $client->render($start)->{bitsref};
	my $endbits = $client->render($end)->{bitsref};
	
	my $allbits = $$endbits . $$startbits;
	
	$client->killAnimation();
	$client->pushUpdate([\$allbits, $client->screenBytes(), 0 - $client->screenBytes() / 8, 0, 0.025]);
}

sub bumpRight {
	my $client = shift;
	my $startbits = $client->render(Slim::Display::Display::curLines($client))->{bitsref};
	$startbits = $$startbits .  (chr(0) x 16);
	$client->killAnimation();
	$client->pushUpdate([\$startbits, 16, -8, 0, 0.125]);	
}

sub bumpLeft {
	my $client = shift;
	my $startbits = $client->render(Slim::Display::Display::curLines($client))->{bitsref};
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
		$client->updateMode(1);
		$client->animateState(3);
		Slim::Utils::Timers::setHighTimer($client,Time::HiRes::time() + $deltatime,\&pushUpdate,[$allbits,$offset,$delta,$end,$deltatime]);
	} else {
		$client->endAnimation();
	}
}

sub bumpDown {
	my $client = shift;

	my $startbits = $client->render(Slim::Display::Display::curLines($client))->{bitsref};
	$startbits = substr((chr(0) . $$startbits) & ((chr(0) . chr(255)) x ($client->screenBytes() / 2)), 0, $client->screenBytes());

	$client->killAnimation();
	
	$client->drawFrameBuf(\$startbits);

	$client->updateMode(1);
	$client->animateState(4);
	Slim::Utils::Timers::setHighTimer($client,Time::HiRes::time() + 0.125, \&endAnimation);
}

sub bumpUp {
	my $client = shift;
	my $startbits = $client->render(Slim::Display::Display::curLines($client))->{bitsref};
	$startbits = substr(($$startbits . chr(0)) & ((chr(0) . chr(255)) x ($client->screenBytes() / 2)), 1, $client->screenBytes());
	
	$client->killAnimation();

	$client->drawFrameBuf(\$startbits);

	$client->updateMode(1);
	$client->animateState(4);
	Slim::Utils::Timers::setHighTimer($client,Time::HiRes::time() + 0.125, \&endAnimation);
}


sub doEasterEgg {
	my $client = shift;
	$client->update();
}

sub scrollInit {
	my $client = shift;
	my $render = shift;
	my $scrollonce = shift || 0; # 0 = scroll to endscroll and then stop, 1 = pause and then scroll again

	my $refresh = $client->paramOrPref($client->linesPerScreen() == 1 ? 'scrollRateDouble': 'scrollRate');
	my $pause = $client->paramOrPref($client->linesPerScreen() == 1 ? 'scrollPauseDouble': 'scrollPause');	
	my $pixels = $client->paramOrPref($client->linesPerScreen() == 1 ? 'scrollPixelsDouble': 'scrollPixels');	
	my $now = Time::HiRes::time();

	my $start = $now + (($pause > 0.5) ? $pause : 0.5);

	my $scroll = {
		'endscroll'       => $render->{endscroll},
		'offset'          => 0,
		'scrollonce'      => $scrollonce,
		'refreshInt'      => $refresh,
		'pauseInt'        => $pause,
		'shift'           => $pixels * $client->bytesPerColumn(),
		'pauseUntil'      => $start,
		'refreshTime'     => $start,
		'paused'          => 0,
		'scrollHeader'    => $client->scrollHeader,
		'scrollFrameSize' => length($client->scrollHeader) + $client->screenBytes,
		'bitsref'         => $render->{bitsref},
		'scrollbitsref'   => $render->{scrollbitsref},
		'overlay2start'   => $render->{overlay2start},
		};

	$client->scrollData($scroll);
	
	$client->scrollState(1);
	$client->scrollUpdate();
}

sub scrollStop {
	my $client = shift;

	Slim::Utils::Timers::killTimers($client, \&scrollUpdate);
	$client->scrollState(0);
	$client->scrollData(undef);
}

sub scrollUpdateBackground {
	my $client = shift;
	my $render = shift;

	my $scroll = $client->scrollData();
	$scroll->{bitsref} = $render->{bitsref};
	$scroll->{overlay2start} = $render->{overlay2start};

	# force update of screen for server side scrolling if paused, otherwise rely on scrolling to update
	if ($scroll->{paused}) {
		Slim::Utils::Timers::firePendingTimer($client, \&scrollUpdate);
	}
}

sub scrollUpdate {
	my $client = shift;

	my $scroll = $client->scrollData();
	my $bitsref = $scroll->{bitsref};
	my $scrollref = $scroll->{scrollbitsref};

	my $frame = $scroll->{scrollHeader} . 
		($$bitsref | substr($$scrollref, $scroll->{offset}, $scroll->{overlay2start}));

	# check for congestion on slimproto socket and send update if not congested
	if (defined($client->tcpsock) && !Slim::Networking::Select::writeNoBlockQLen($client->tcpsock) && (length($frame) == $scroll->{scrollFrameSize})) {
		Slim::Networking::Select::writeNoBlock($client->tcpsock, \$frame);
	}

	my $timenow = Time::HiRes::time();

	if ($timenow < $scroll->{pauseUntil}) {
		# called early for background update - reset timer for end of pause
		Slim::Utils::Timers::setHighTimer($client, $scroll->{pauseUntil}, \&scrollUpdate);

	} else {
		# update refresh time and skip frame if running behind actual timenow
		do {
			$scroll->{offset} += $scroll->{shift};
			$scroll->{refreshTime} += $scroll->{refreshInt};
		} while ($scroll->{refreshTime} < $timenow );

		$scroll->{paused} = 0;
		if ($scroll->{offset} > $scroll->{endscroll}) {
			$scroll->{offset} = 0;
			if ($scroll->{scrollonce}) {
				# finished one scroll - stop scrolling and clean up
				$scroll = undef;
				$client->scrollStop();
				return;
			}
			if ($scroll->{pauseInt} > 0) {
				$scroll->{pauseUntil} = $scroll->{refreshTime} + $scroll->{pauseInt};
				$scroll->{refreshTime} = $scroll->{pauseUntil};
				$scroll->{paused} = 1;
				# sleep for pauseInt
				Slim::Utils::Timers::setHighTimer($client, $scroll->{pauseUntil}, \&scrollUpdate);
				return;
			}
		}
		# fast timer during scroll
		Slim::Utils::Timers::setHighTimer($client, $scroll->{refreshTime}, \&scrollUpdate);
	}
}

# find all the queued up animation frames and toss them
sub killAnimation {
	my $client = shift;
	my $exceptScroll = shift; # all but scrolling to be killed (used by showBriefly)

	my $animate = $client->animateState();
	Slim::Utils::Timers::killTimers($client, \&update) if ($animate == 2);
	Slim::Utils::Timers::killTimers($client, \&pushUpdate) if ($animate == 3);	
	Slim::Utils::Timers::killTimers($client, \&endAnimation) if ($animate == 4 || $animate == 5);	
	Slim::Utils::Timers::killTimers($client, \&scrollUpdate) if ($client->scrollState() == 1 && !$exceptScroll) ;
	$client->animateState(0);
	$client->scrollState(0) unless $exceptScroll;
	$client->updateMode(0);
}

sub endAnimation {
	# called after after an animation to display the screen and initiate scrolling
	my $client = shift;
	my $delay = shift;

	if ($delay) {
		$client->animateState(2);
		$client->updateMode(1);
		Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + $delay, \&update);
	} else {
		$client->animateState(0);
		$client->updateMode(0);
		$client->update();
	}
}	

# temporary for SBG to ensure periodic screen update
sub periodicScreenRefresh {
	my $client = shift;

	$client->update() unless ($client->updateMode());

	Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + 1, \&periodicScreenRefresh);
}


1;

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:

