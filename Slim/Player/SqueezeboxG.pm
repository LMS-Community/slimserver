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

my $scroll_pad_scroll = 40; # lines of padding between scrolling text
my $scroll_pad_ticker = 60; # lines of padding in ticker mode

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
	my $scroll = shift || 0; # 0 = no scroll, 1 = normal horiz scroll mode if line 2 too long, 2 = ticker scroll

	my $parts;
	
	if ((ref($lines) eq 'HASH')) {
		$parts = $lines;
	} else {
		$parts = $client->parseLines($lines);
	}

	my $cache = $client->renderCache();
	$cache->{changed} = 0;
	$cache->{newscroll} = 0;
	$cache->{restartticker} = 0;

	my $screensize = $client->screenBytes();
	if ($screensize != $cache->{screensize}) {
		$cache->{screensize} = $screensize;
		$cache->{changed} = 1;
		$cache->{restartticker} = 1;
	}

	my $fonts = defined($parts->{fonts}) ? $parts->{fonts} : $client->fonts();
	if ($fonts != $cache->{fonts}) {
		$cache->{fonts} = $fonts;
		$cache->{line2height} = Slim::Display::Graphics::extent($fonts->[1]);
		$cache->{changed} = 1;
		$cache->{restartticker} = 1;
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
		$cache->{ticker} = 0;
	}

	# if we're only displaying the second line (i.e. single line mode) and the second line is blank,
	# copy the first to the second.  Don't do for ticker mode.
	if (!defined($fonts->[0]) && (!$parts->{line2} || $parts->{line2} eq '') && $scroll != 2) {
		$parts->{line2} = $parts->{line1};
	}
	
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
		(!defined($cache->{line2}) || ($parts->{line2} ne $cache->{line2}) || (!$scroll && $cache->{scrolling}) ||
		 ($scroll == 2) || ($scroll == 1 && $cache->{ticker}) )) {
		$cache->{line2} = $parts->{line2};
		$cache->{line2bits} = Slim::Display::Graphics::string($fonts->[1], $parts->{line2});
		$cache->{scrollbitsref} = undef;
		$cache->{scrolling} = 0;
		$cache->{ticker} = 0 if ($scroll != 2);
		$cache->{line2finish} = length($cache->{line2bits});
		$cache->{changed} = 1;
	} elsif (!defined($parts->{line2}) && defined($cache->{line2})) {
		$cache->{line2} = undef;
		$cache->{line2bits} = '';
		$cache->{line2finish} = 0;
		$cache->{changed} = 1;
		$cache->{scrolling} = 0;
		$cache->{ticker} = 0 if ($scroll != 2);
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
	if ($cache->{line1finish} <= $cache->{overlay1start}) {
		$bits = $cache->{line1bits}. chr(0) x ($cache->{overlay1start} - $cache->{line1finish}) 
			. $cache->{overlay1bits};
	} else {
		$bits = substr($cache->{line1bits}, 0, $cache->{overlay1start}). $cache->{overlay1bits};
	}
	# Add 2nd line
	if ( ($cache->{line2finish} <= $cache->{overlay2start}) && ($scroll != 2) ) {
		$bits |= $cache->{line2bits}. chr(0) x ($cache->{overlay2start} - $cache->{line2finish}) 
			. $cache->{overlay2bits};
	} else {
		if ($scroll) {
			my $bytesPerColumn = $client->bytesPerColumn;
			my $scrollbits = $cache->{line2bits};
			if ($scroll == 1) {
				# enable line 2 normal scrolling, remove line2bits from base display to scrollbits
				# add padding to ensure end back at start of text for all scrollPixel settings
				my $padBytes = $scroll_pad_scroll * $bytesPerColumn;
				my $pixels = $client->paramOrPref($client->linesPerScreen() == 1 ? 'scrollPixelsDouble': 'scrollPixels');
				my $bytesPerScroll = $pixels * $bytesPerColumn;

				my $len = $padBytes + $cache->{line2finish};
				if ($pixels > 1) {
					$padBytes += $bytesPerScroll - int($bytesPerScroll * ($len/$bytesPerScroll - int($len/$bytesPerScroll)) + 0.1);
				}
				$scrollbits .= chr(0) x $padBytes . substr($cache->{line2bits}, 0, $screensize);
				$cache->{endscroll} = $cache->{line2finish} + $padBytes;
				$cache->{newscroll} = 1;
			} else {
				# ticker mode
				my $padBytes = $scroll_pad_ticker * $bytesPerColumn;			
				if ($cache->{line2finish} > 0 || !$cache->{ticker}) {
					$scrollbits .= chr(0) x $padBytes;
					$cache->{endscroll} = $cache->{line2finish};
					$cache->{newscroll} = 1;
				} else {
					$cache->{endscroll} = 0;
				}
				$cache->{ticker} = 1;
			}
			$cache->{scrollbitsref} = \$scrollbits;
			$cache->{line2bits} = '';
			$cache->{line2finish} = 0;
			$cache->{scrolling} = 1;
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

# update screen for graphics display
sub updateScreen {
	my $client = shift;
	my $render = shift;
	$client->drawFrameBuf($render->{bitsref});
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

# update display for graphics scrolling
sub scrollUpdateDisplay {
	my $client = shift;
	my $scroll = shift;

	my $frame = $scroll->{scrollHeader} . 
		(${$scroll->{bitsref}} | substr(${$scroll->{scrollbitsref}}, $scroll->{offset}, $scroll->{overlay2start}));

	# check for congestion on slimproto socket and send update if not congested
	if ((Slim::Networking::Select::writeNoBlockQLen($client->tcpsock) == 0) && (length($frame) == $scroll->{scrollFrameSize})) {
		Slim::Networking::Select::writeNoBlock($client->tcpsock, \$frame);
	}
}

sub scrollUpdateTicker {
	my $client = shift;
	my $render = shift;

	my $scroll = $client->scrollData();

	my $scrollbits = substr(${$scroll->{scrollbitsref}}, $scroll->{offset});
	my $len = $scroll->{endscroll} - $scroll->{offset};
	my $padBytes = $scroll_pad_ticker * $client->bytesPerColumn;

	my $pad = 0;
	if ($render->{overlay2start} > ($len + $padBytes)) {
		$pad = $render->{overlay2start} - $len - $padBytes;
		$scrollbits .= chr(0) x $pad;
	}
	
	$scrollbits .= ${$render->{scrollbitsref}};

	$scroll->{scrollbitsref} = \$scrollbits;
	$scroll->{endscroll} = $len + $padBytes + $pad + $render->{endscroll};
	$scroll->{offset} = 0;
}

# find all the queued up animation frames and toss them
sub killAnimation {
	my $client = shift;
	my $exceptScroll = shift; # all but scrolling to be killed

	my $animate = $client->animateState();
	Slim::Utils::Timers::killTimers($client, \&Slim::Player::Player::update) if ($animate == 2);
	Slim::Utils::Timers::killTimers($client, \&pushUpdate) if ($animate == 3);	
	Slim::Utils::Timers::killTimers($client, \&endAnimation) if ($animate == 4);	
	Slim::Utils::Timers::killTimers($client, \&Slim::Player::Player::endAnimation) if ($animate == 5);	
	$client->scrollStop() if (($client->scrollState() > 0) && !$exceptScroll) ;
	$client->animateState(0);
	$client->updateMode(0);
}

sub endAnimation {
	my $client = shift;
	$client->SUPER::endAnimation(@_);
}

# temporary for SBG to ensure periodic screen update
sub periodicScreenRefresh {
	my $client = shift;

	$client->update() unless ($client->updateMode() || $client->scrollState() == 2 || $client->param('modeUpdateInterval'));

	Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + 1, \&periodicScreenRefresh);
}


1;

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:

