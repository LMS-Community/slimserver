package Slim::Display::Graphics;

# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.


=head1 NAME

Slim::Display::Graphics

=head1 DESCRIPTION

L<Slim::Display::Graphics>
 Graphics display base class - Contains common display code for all graphics displays
 New display objects should be created as subclasses of this class

=cut

use strict;

use Slim::Display::Display;
use Slim::Display::Lib::Fonts;

use base qw(Slim::Display::Display);

use Slim::Utils::Prefs;
use Slim::Utils::Log;

my $prefs = preferences('server');

# constants
my $scroll_pad_scroll = 40; # lines of padding between scrolling text
my $scroll_pad_ticker = 60; # lines of padding in ticker mode

our $defaultPrefs = {
	'scrollPixels'		   => 2,
	'scrollPixelsDouble'   => 3,
	'idleBrightness'       => 2,
	'powerOffBrightness'   => 1,
	'powerOnBrightness'    => 4,
};

$prefs->setValidate({ 'validator' => 'intlimit', 'low' => 1, 'high' => 20 }, qw(scrollPixels scrollPixelsDouble));

BEGIN {
	Slim::Display::Lib::Fonts::init();
}

sub initPrefs {
	my $display = shift;

	$prefs->client($display->client)->init($defaultPrefs);

	$display->SUPER::initPrefs();
}

sub validateFonts {
	# validate that all fonts defined by the prefs for this player are of the correct height for player
	# otherwise reset to the default fonts [prevents display corruption for softsqueeze when switching emulations]
	my $display = shift;
	my $defaultFontPrefs = shift;

	my $client = $display->client;
	my $height = $display->displayHeight;

	my $fontsOK = 1;
	
	Slim::Display::Lib::Fonts::init();

	foreach my $font (@{$prefs->client($client)->get('activeFont')}, @{$prefs->client($client)->get('idleFont')}) {
		my $fontheight = Slim::Display::Lib::Fonts::fontheight($font.".2");
		if (!$fontheight || $fontheight != $height) {
			$fontsOK = 0;
		}
	}

	unless ($fontsOK) {
		foreach my $pref (keys %{$defaultFontPrefs}) {
			$prefs->client($client)->set($pref, $defaultFontPrefs->{$pref});
		}
	}
}

sub linesPerScreen {
	my $display = shift;
	my $fonts = $display->fonts();
	if (defined($fonts)) {
		return 3 if ($fonts->{line}[2] || $fonts->{center}[2]);
		return 2 if ($fonts->{line}[0] || $fonts->{center}[0]);
		return 1;
	} else {
		return 2;
	}
}

sub screenBytes {
	my $display = shift;
	my $screen  = shift;
	return $display->bytesPerColumn() * $display->displayWidth($screen);
}

# main render routine for all types of graphic display
sub render {
	use bytes;
	my $display = shift;
	my $parts = shift;
	my $scroll = shift || 0; # 0 = no scroll, 1 = wrapped scroll if line too long, 2 = non wrapped scroll
	my $s2periodic = shift;  # this render is for a periodic screen 2 update - suppress some state changes
	my $client = $display->client;

	if (ref $parts ne 'HASH') {
		logError("bad lines function - non hash based display formats are deprecated");
	} elsif (!exists($parts->{screen1}) &&
		(exists($parts->{line1}) || exists($parts->{line2}) || exists($parts->{center1}) || exists($parts->{center2})) ) {
		# Backwards compatibility with 6.2 display hash
		$parts->{screen1}->{line}    = [ $parts->{line1}, $parts->{line2} ];
		$parts->{screen1}->{overlay} = [ $parts->{overlay1}, $parts->{overlay2} ];
		$parts->{screen1}->{center}  = [ $parts->{center1}, $parts->{center2} ];
		$parts->{screen1}->{bits}    = $parts->{bits};
	}

	my $cache = $display->renderCache();
	my $screens = $cache->{screens};
	my $maxLine = $cache->{maxLine};

	my $newDefaultFont; # flag indicating default font has changed - will force rerender

	my $dfonts = $cache->{defaultfont};
	unless ($dfonts) {
		$dfonts = $cache->{defaultfont} = $display->fonts();
		$newDefaultFont = 1;
	}

	my $rerender = ($parts == $cache); # rerendering renderCache - optimise some functions

	foreach my $screenNo (1..$screens) {

		# Per screen components of render cache
		#  line            - array of cached lines
		#  overlay         - array of cached overlays
		#  center          - array of cached centers
		#  bits            - bitmap for screen (if included in last render) else undef
		#  linebits        - array of bitmaps for cached lines
		#  overlaybits     - array of bitmaps for cached overlays
		#  centerbits      - array of bitmaps for cached centers
		#  linefinish      - array of lengths of cached line bitmaps (where the line finishes)
		#  overlaystart    - array of screensize - lengths of cached overlay bitmaps (where the overlay start)
		#  linereverse     - array of reverse indicators for lines (used to reverse scrolling if BiDiR)
		#  bitsref         - ref of bitmap for static result of render

		# Per screen scrolling data
		#  scroll          - scrolling state of render: 
		#                    0 = no scroll, 1 = normal scroll, 2 = ticker scroll - update, 3 = ticker - no update
		#  scrollline      - line which is scrolling [undef if no scrolling]
		#  scrollbitsref   - ref of bitmap for scrolling component of render result
		#  scrollstart     - start offset of scroll
		#  scrollend       - end offset of scroll
		#  scrolldir       - direction to scroll: +1 = left to right, -1 = right to left
		#  scrolltype      - for normal scroll, value of $scroll, 1 = wrapped scroll, 2 = non wrapped scroll
		#  [nb only scroll and scrollline are cleared when scrolling stops, others can contain stale data]

		# Per screen flags
		#  present         - this screen is present in the last display hash send to render
		#  changed         - this screen changed in the last render
		#  newscroll       - new scrollable text produced by this render - scrolling should restart

		my $screen;                     # screen definition to render
		my $sfonts;                     # non default fonts for screen 
		my $screen1 = ($screenNo == 1); # flag for main screen
		my $s = 'screen'.$screenNo;     # name of screen [screen1, screen2 etc]
		my $sc = $cache->{$s};          # screen cache for this screen
		my $changed = 0;                # current screen has changed
		my $screensize = $display->screenBytes($screenNo); # size of screen

		if ($screen1 && !exists($parts->{screen1}) && 
			(exists($parts->{line}) || exists($parts->{center}) || exists($parts->{overlay}) || 
			 exists($parts->{ticker}) || exists($parts->{bits}) || !scalar keys(%$parts))){ 
			$screen = $parts;           # screen 1 components allowed at top level of display hash
		} else {
			$screen = $parts->{$s};     # other screens must be within {screenX} component of hash
		}

		# reset flags per render
		$sc->{newscroll} = 0;
		$sc->{changed} = 0;
		$sc->{present} = 0 unless ($rerender || $s2periodic);

		# reset cache for screen if screensize or default font has changed
		if ($screensize != $sc->{ssize} || $newDefaultFont) {

			$sc->{ssize} = $screensize;

			if ($rerender) {

				# rerender of render cache - store fonts and create new $screen as copy
				$sfonts = $screen->{fonts};
				$screen = {};

				foreach my $c (qw(line overlay center)) {

					foreach my $l (0..$maxLine) {
						$screen->{$c}[$l] = $sc->{$c}[$l];
					}
				}

			} else {

				$screen->{fonts} ||= undef;
			}

			$sc->{fonts} = {}; # force component caches to be cleared below
			$sc->{extent} = Slim::Display::Lib::Fonts::extent($dfonts->{line}[1]);
			$changed = 1;
		}

		# update render components if screen is defined in display hash
		if ($screen) {

			if ($screen->{fonts}) {

				if ($rerender) {
					$sfonts = $screen->{fonts};

				} elsif (ref($screen->{fonts}) eq 'HASH') {
					# lines returns a font hash
					my $model = $display->vfdmodel();
					my $screenfonts = $screen->{fonts}->{"$model"} || {};

					if (ref($screenfonts) eq 'HASH') {
						$sfonts = $screenfonts;

					} else {
						my $fontref = Slim::Display::Lib::Fonts::gfonthash();
						if (exists($fontref->{$screenfonts})) {
							$sfonts = $fontref->{$screenfonts};
						}
					}
				}
			}

			my $cfonts = $sc->{fonts};
			if (($sfonts || 0) != ($cfonts || 0)) {

				# screen contains non default font definition which differs from cache - clear caches
				foreach my $c (qw(line overlay center)) {

					foreach my $l (0..$maxLine) {

						if (!$sfonts || !$cfonts || 
							( ($sfonts->{$c}[$l] || '')  ne ($cfonts->{$c}[$l] || '') ) || $changed) {
							$sc->{"$c"}[$l] = undef;
							$sc->{"$c"."bits"}[$l] = '';
							$sc->{"$c"."finish"}[$l] = 0 if ($c eq 'line');
							$sc->{"$c"."start"}[$l] = $screensize if ($c eq 'overlay');
							$changed = 1;
						}
					}
				}

				$sc->{fonts} = $sfonts;
				$sc->{extent} = Slim::Display::Lib::Fonts::extent($sfonts->{line}[1]||$dfonts->{line}[1]);
			}

			if (!$scroll || $changed) { 
				# kill any current scrolling if scrolling is disabled or fonts have changed
				$sc->{scroll} = 0;
				$sc->{scrollline} = undef;
			}

			# if in single line mode and nothing on line[1], copy line[0] - don't do in ticker mode
			if (!($sfonts->{line}[0] || $dfonts->{line}[0]) && (!$screen->{line}[1] || $screen->{line}[1] eq '') && 
				!exists($screen->{ticker})) {
				$screen->{line}[1] = $screen->{line}[0];
			}

			# lines - render if changed 
			foreach my $l (0..$maxLine) {
				if (defined($screen->{line}[$l]) && 
					(!defined($sc->{line}[$l]) || ($screen->{line}[$l] ne $sc->{line}[$l]))) {
					$sc->{line}[$l] = $screen->{line}[$l];
					($sc->{linereverse}[$l], $sc->{linebits}[$l]) = 
						Slim::Display::Lib::Fonts::string($sfonts->{line}[$l]||$dfonts->{line}[$l], $screen->{line}[$l]);
					$sc->{linefinish}[$l] = length($sc->{linebits}[$l]);
					if ($sc->{scroll} && ($sc->{scrollline} == $l)) {
						$sc->{scroll} = 0; $sc->{scrollline} = undef;
					}
					$changed = 1;
				} elsif (!defined($screen->{line}[$l]) && defined($sc->{line}[$l])) {
					$sc->{line}[$l] = undef;
					$sc->{linebits}[$l] = '';
					$sc->{linefinish}[$l] = 0;
					if ($sc->{scroll} && ($sc->{scrollline} == $l)) {
						$sc->{scroll} = 0; $sc->{scrollline} = undef;
					}
					$changed = 1;
				}
			}

			# overlays - render if changed
			foreach my $l (0..$maxLine) {
				if (defined($screen->{overlay}[$l]) && 
					(!defined($sc->{overlay}[$l]) || ($screen->{overlay}[$l] ne $sc->{overlay}[$l]))) {
					$sc->{overlay}[$l] = $screen->{overlay}[$l];
					my $overlay;
					{ no bytes; $overlay = "\x00" . $sc->{overlay}[$l]; }
					$sc->{overlaybits}[$l] = Slim::Display::Lib::Fonts::string($sfonts->{overlay}[$l]||$dfonts->{overlay}[$l], $overlay);
					if (length($sc->{overlaybits}[$l]) > $screensize ) {
						$sc->{overlaybits}[$l] = substr($sc->{overlaybits}[$l], 0, $screensize);
					}
					$sc->{overlaystart}[$l] = $screensize - length($sc->{overlaybits}[$l]);
					$changed = 1;
				} elsif (!defined($screen->{overlay}[$l]) && defined($sc->{overlay}[$l])) {
					$sc->{overlay}[$l] = undef;
					$sc->{overlaybits}[$l] = '';
					$sc->{overlaystart}[$l] = $screensize;
					$changed = 1;
				}
			}

			# centered lines - render if changed
			foreach my $l (0..$maxLine) {
				if (defined($screen->{center}[$l]) &&
					(!defined($sc->{center}[$l]) || ($screen->{center}[$l] ne $sc->{center}[$l]))) {
					$sc->{center}[$l] = $screen->{center}[$l];
					my $center = Slim::Display::Lib::Fonts::string($sfonts->{center}[$l]||$dfonts->{center}[$l], $screen->{center}[$l]);
					$center = chr(0) x ( int( ($screensize-length($center)) / ($display->bytesPerColumn()*2) )
										 * $display->bytesPerColumn() ) . $center;
					$sc->{centerbits}[$l] = substr($center, 0, $screensize);
					$changed = 1;
				} elsif (!defined($screen->{center}[$l]) && defined($sc->{center}[$l])) {
					$sc->{center}[$l] = undef;
					$sc->{centerbits}[$l] = '';
					$changed = 1;
				}
			}

			# ticker component - convert directly to new scrolling state
			if (exists($screen->{ticker})) {
				my $tickerbits = '';
				my $reverse;
				$sc->{scrollline} = -1; # dummy line if no ticker text
				$sc->{newscroll} = 1 if ($sc->{scroll} < 2); # switching scroll mode
				for (my $l = $maxLine; $l >= 0; $l--) { # prefer lower lines
					if (exists($screen->{ticker}[$l]) && defined($screen->{ticker}[$l])) {
						($reverse, $tickerbits) = 
							Slim::Display::Lib::Fonts::string($sfonts->{line}[$l]||$dfonts->{line}[$l], $screen->{ticker}[$l]);
						$sc->{scrollline} = $l;
						last;
					}
				}
				my $len = length($tickerbits);
				if ($len > 0 || $sc->{scroll} < 2) {
					my $pad = chr(0) x ($scroll_pad_ticker * $display->bytesPerColumn());
					if (!$reverse) {
						$tickerbits .= $pad;
						$sc->{scrollstart} = 0;
						$sc->{scrollend}   = $len;
						$sc->{scrolldir}   = 1;
					} else {
						$tickerbits = $pad . $tickerbits;
						$sc->{scrollstart} = $len + $scroll_pad_ticker * $display->bytesPerColumn();
						$sc->{scrollend}   = 0;
						$sc->{scrolldir}   = -1;
					}
					$sc->{scroll} = 2;
				} else {
					$sc->{scrollstart} = 0;
					$sc->{scrollend}   = 0;
					$sc->{scroll}      = 3;
				}
				$sc->{scrollbitsref} = \$tickerbits;
				$changed = 1;

			} elsif ($sc->{scroll} >= 2) {
				$sc->{scroll}     = 0;
				$sc->{scrollline} = undef;
			}
			
			$sc->{changed} = $changed;
			$sc->{present} = 1 unless $rerender;

		} # if ($screen)


		# Assemble components

		my $bits = '';

		# Potentially scrollable lines + overlays
		for (my $l = $maxLine; $l >= 0; $l--) { # do in reverse order as prefer to scroll lower lines

			if (!defined($sc->{line}[$l]) && !defined($sc->{overlay}[$l]) && !$l) {
				# do nothing for blank lines (except 1st to give blank screen)

			} elsif ($sc->{linefinish}[$l] <= $sc->{overlaystart}[$l] ) {
				# no need to scroll - assemble line + pad + overlay
				$bits |= $sc->{linebits}[$l] . chr(0) x ($sc->{overlaystart}[$l] - $sc->{linefinish}[$l]) . $sc->{overlaybits}[$l];
				if ($sc->{scroll} == 1 && $sc->{scrollline} == $l) {
					# previously scrolling same text on this line but no longer needed - probably due to overlay change
					$sc->{scroll} = 0;
					$sc->{scrolline} = undef;
				}

			} elsif (!$scroll || $l == 0 || ($sc->{scroll} && $sc->{scrollline} != $l) || ($s2periodic && $screen1) ) {
				# scrolling not enabled, line 0 or already scrolling for another line - truncate line
				if (!$sc->{linereverse}[$l]) {
					$bits |= substr($sc->{linebits}[$l], 0, $sc->{overlaystart}[$l]). $sc->{overlaybits}[$l];
				} else {
					$bits |= substr($sc->{linebits}[$l], $sc->{linefinish}[$l] - $sc->{overlaystart}[$l]) . 
						$sc->{overlaybits}[$l];
				}

			} elsif ($sc->{scroll} && $sc->{scrollline} == $l && $sc->{scrolltype} == $scroll) {
				# scrolling already on this line - add overlay only
				$bits |= chr(0) x $sc->{overlaystart}[$l] . $sc->{overlaybits}[$l];

			} else {
				# scrolling allowed and not currently scrolling - create scrolling state

				$sc->{scrolldir} = ($sc->{linereverse}[$l]) ? -1 : 1; # right to left scroll if reverse set

				my $bytesPerColumn = $display->bytesPerColumn;
				my $scrollbits;

				if ($scroll == 1) {
					# normal wrapped text scrolling
					my $padBytes = $scroll_pad_scroll * $bytesPerColumn;
					my $pixels = $prefs->client($client)->get($display->linesPerScreen() == 1 ? 'scrollPixelsDouble': 'scrollPixels');
					my $bytesPerScroll = $pixels * $bytesPerColumn;
					my $len = $padBytes + $sc->{linefinish}[$l];
					if ($pixels > 1) {
						$padBytes += $bytesPerScroll - ($len % $bytesPerScroll);
					}
					if ($sc->{scrolldir} == 1) {
						$scrollbits = $sc->{linebits}[$l] . 
							chr(0) x $padBytes . substr($sc->{linebits}[$l], 0, $screensize);
						$sc->{scrollstart} = 0;
						$sc->{scrollend} = $sc->{linefinish}[$l] + $padBytes;
					} else {
						my $offset = $sc->{linefinish}[$l] - $sc->{overlaystart}[$l];
						$scrollbits = substr($sc->{linebits}[$l], $offset) . chr(0) x $padBytes . $sc->{linebits}[$l];
						$sc->{scrollstart} = $sc->{overlaystart}[$l] + $padBytes + $offset;
						$sc->{scrollend} = 0;
					}
					$sc->{scrolltype} = 1;

				} else {
					# don't wrap text - scroll to end only
					$scrollbits = $sc->{linebits}[$l];
					if ($sc->{scrolldir} == 1) {
						$sc->{scrollstart} = 0;
						$sc->{scrollend} = $sc->{linefinish}[$l] - $sc->{overlaystart}[$l];
					} else {
						$sc->{scrollstart} = $sc->{linefinish}[$l] - $sc->{overlaystart}[$l];
						$sc->{scrollend} = 0;
					}
					$sc->{scrolltype} = 2;
				}

				$sc->{scroll} = 1;
				$sc->{scrollline} = $l;
				$sc->{newscroll} = 1;
				$sc->{scrollbitsref} = \$scrollbits;
				
				# add overlay only to static bitmap
				$bits |= chr(0) x $sc->{overlaystart}[$l] . $sc->{overlaybits}[$l];
			}
		}

		# Centered text
		foreach my $l (0..$maxLine) {
			if (defined($sc->{center}[$l])) { 
				$bits |= $sc->{centerbits}[$l];
			}
		}

		# Bitmaps
		if (defined($screen->{bits}) && length($screen->{bits})) {
			$bits |= substr($screen->{bits}, 0, $screensize);
			$sc->{bits} = $screen->{bits} unless $rerender;
			$sc->{changed} = 1;
		} else {
			$sc->{bits} = undef;
		}

		$sc->{bitsref} = \$bits;

	} # foreach my $screenNo (@screens)

	return $cache;
}

sub brightness {
	my $display = shift;
	my $delta = shift;
	
	my $brightness = $display->SUPER::brightness($delta);

	if (defined($delta)) {
		my @brightnessMap = $display->brightnessMap;
		my $brightnesscode = pack('n', $brightnessMap[$brightness]);
		$display->client->sendFrame('grfb', \$brightnesscode); 
	}

	return $brightness;
}

sub maxBrightness {
	my $display = shift;

	my @brightnessMap = $display->brightnessMap;
	return $#brightnessMap;
}

# update display for graphics scrolling
sub scrollUpdateDisplay {
	my $display = shift;
	my $scroll = shift;
	my $client = $display->client || return;
	
	# don't send update if the slimproto socket is congested
	if ( Slim::Networking::Select::writeNoBlockQLen($client->tcpsock) != 0 ) {
		return;
	}

	my $data;

	if ($scroll->{dir} == 1 || $scroll->{offset} >= 0) {
		$data = $scroll->{scrollHeader} . 
			(${$scroll->{bitsref}} | substr(${$scroll->{scrollbitsref}}, $scroll->{offset}, $scroll->{overlaystart}));
	} else {
		$data = $scroll->{scrollHeader} . 
			(${$scroll->{bitsref}} |
			 (substr(${$scroll->{bitsref}}, 0, abs($scroll->{offset})) . 
			  substr(${$scroll->{scrollbitsref}}, 0, $scroll->{overlaystart} + $scroll->{offset})
			 ));
	}		
	
	$client->sendFrame( $display->graphicCommand, \$data );
}

sub scrollUpdateTicker {
	my $display = shift;
	my $screen = shift;
	my $screenNo = shift;

	my $scroll   = $display->scrollData($screenNo);
	my $padBytes = $scroll_pad_ticker * $display->bytesPerColumn;
	my $pad      = 0;	
	my $scrollbits;
	my $len;

	if ($scroll->{dir} != $screen->{scrolldir}) {

		# restart ticker going in the opposite direction
		$display->scrollStop($screenNo);
		$display->scrollInit($screen, $screenNo, 0);
		return;
	}

	if ($scroll->{dir} == 1) {

		$scrollbits = substr(${$scroll->{scrollbitsref}}, $scroll->{offset});

		$len = $scroll->{scrollend} - $scroll->{offset};

		if ($screen->{overlaystart}[$screen->{scrollline}] > ($len + $padBytes)) {
			$pad = $screen->{overlaystart}[$screen->{scrollline}] - $len - $padBytes;
		}
	
		$scrollbits .= (chr(0) x $pad) . ${$screen->{scrollbitsref}};
		
		$scroll->{scrollend} = $len + $padBytes + $pad + $screen->{scrollend};
		$scroll->{offset} = 0;
		
	} else {

		$scrollbits = substr(${$scroll->{scrollbitsref}}, 0, $scroll->{offset} + $screen->{overlaystart}[$screen->{scrollline}]);

		if ($screen->{overlaystart}[$screen->{scrollline}] > length($scrollbits)) {
			$pad = $screen->{overlaystart}[$screen->{scrollline}] - length($scrollbits);
		}

		$scrollbits = ${$screen->{scrollbitsref}} . (chr(0) x $pad) . $scrollbits;
		
		$scroll->{offset} = $scroll->{offset} + length(${$screen->{scrollbitsref}}) + $pad;
	}

	$scroll->{scrollbitsref} = \$scrollbits;
}

sub textSize {
	my $display = shift;
	my $newsize = shift;

	my $client = $display->client;

	# grab base for prefname depending on mode
	my $prefname = ($client->power()) ? "activeFont" : "idleFont";
	
	if (defined($newsize)) {

		my $size = $prefs->client($client)->set($prefname."_curr", $newsize);

		if ($display->animateState() == 5) {
			# currently in showBriefly - end it
			Slim::Utils::Timers::killTimers($display, \&Slim::Display::Display::endAnimation);
			$display->endAnimation();
		}

		# prefchanged callback will reset render cache defaultfont, so just redisplay here
		$display->update($display->renderCache());
		
		return $size;

	} else {
		return $prefs->client($client)->get($prefname."_curr");
	}
}

sub maxTextSize {
	my $display = shift;

	my $prefname = ($display->client->power()) ? "activeFont" : "idleFont";

	return scalar @{ $prefs->client($display->client)->get($prefname)} - 1;
}

sub measureText {
	my $display = shift;
	my $text = shift || '';
	my $line = shift;
	my $spaces = shift; # number or additional inter-character spaces to add [overlay needs at least 1]
	
	my $fonts = $display->fonts();

	if ($spaces) {
		$text .= chr(0) x $spaces;
	}

	my $len = Slim::Display::Lib::Fonts::measureText($fonts->{"line"}[$line-1], $display->symbols($text));
	return $len;
}

# Draws a slider bar, bidirectional or single direction is possible.
# $value should be pre-processed to be from 0-100
# $midpoint specifies the position of the divider from 0-100 (use 0 for progressBar)
# $reverse reverses fill for progressBar only (0 midpoint)

sub sliderBar {
	my $display = shift;
	my $width = shift;
	my $value = shift;
	my $midpoint = shift;
	my $fullstep = shift; # unused - only for text sliderBar
	my $reverse = shift;
	my $cursor = shift;

	$midpoint = 0 unless defined $midpoint;

	if ($value < 0)   { $value = 0; }
	if ($value > 100) { $value = 100; }
	if ($width == 0)  { return ""; }

	my $spaces = $midpoint ? $width - 2 : $width - 1; # allocate space for progressEnd and mid point
	my $dots   = int($value/100 * $spaces);
	my $divider= int($midpoint/100 * $spaces);
	if (defined $cursor) {
		$cursor = int($cursor/100 * $spaces);
	}	

	if ($dots < 0) { $dots = 0 };
		
	my $prog1 = $display->symbols('progress1');
	my $prog2 = $display->symbols('progress2');
	my $prog3 = $display->symbols('progress2');
	my $prog1e = $display->symbols('progress1e');
	my $prog2e = $display->symbols('progress2e');
	my $prog3e = $display->symbols('progress2e');
	my $progEnd = $display->symbols('progressEnd');
	my $cursorSymbol = $display->symbols('cursor');

	my $chart = $display->symbols('tight') . $progEnd;

	if ($midpoint) {
		#left half
		for (my $i = 0; $i < $divider; $i++) {
			if ($value >= $midpoint) {
				if ((($i == $divider - 1) && !(defined $cursor && $cursor == $divider)) || $i == 0) {
					$chart .= $prog1e;
				} elsif ((($i == $divider - 2) && !(defined $cursor && $cursor == $divider)) || $i == 1) {
					$chart .= $prog2e;
				} else {
					$chart .= $prog3e;
				}
			} else {
				if ((($i == $divider - 1) && !(defined $cursor && $midpoint && $cursor == $divider)) || $i == 0) {
					$chart .= ($i < $dots) ? $prog1e : $prog1;
				} elsif ((($i == $divider - 2) && !(defined $cursor && $midpoint && $cursor == $divider)) || $i == 1) {
					$chart .= ($i < $dots) ? $prog2e : $prog2;
				} else {
					$chart .= ($i < $dots) ? $prog3e : $prog3;
				}
			}
		}
		
		if (defined $cursor && $cursor == $divider) {
			$chart .= $cursorSymbol;
			$chart .= $prog3;
		} else {
			$chart .= $progEnd;
		}
	}
	
	# right half
	for (my $i = $divider + 1; $i < $spaces; $i++) {
		if ($value <= $midpoint) {

			# create end lobes
			# check for midpoint and cursor position to skip the lobe when a left half exists.
			if ((($i == $divider +1) && !(defined $cursor && $cursor == $divider && $midpoint)) || $i == $spaces - 1) {
				$chart .= $reverse ? $prog1 : $prog1e;
			} elsif ((($i == $divider +2) && !(defined $cursor && $cursor == $divider && $midpoint)) || $i == $spaces - 2) {
				$chart .= $reverse ? $prog2 : $prog2e;
			} else {
				$chart .= $reverse ? $prog3 : $prog3e;
			}
		} else {
			my $pos = $reverse ? ($i <= $dots) : ($i > $dots);
			if (defined $cursor && $i == $cursor) {
				$chart .= $cursorSymbol;
				$chart .= $pos ? $prog3 : $prog3e;
			} elsif ((($i == $divider +1) && !(defined $cursor && $cursor == $divider && $midpoint)) || $i == $spaces - 1) {
				$chart .= $pos ? $prog1e : $prog1;
			} elsif ((($i == $divider +2) && !(defined $cursor && $cursor == $divider && $midpoint)) || $i == $spaces - 2) {
				$chart .= $pos ? $prog2e : $prog2;
			} else {
				$chart .= $pos ? $prog3e : $prog3;
			}
		}
	}
	$chart .= $progEnd . $display->symbols('/tight');

	return $chart;
}

# optimised simple slide bar for volume display which returns a bitmap rather than string of symbols
sub simpleSliderBar {
	my $display = shift;
	my $width   = shift;
	my $val     = shift;
	my $line    = shift; # which line it appears on

	my $cache   = $display->renderCache();
	my $fonts   = $display->fonts();

	my $sbinfo  = $cache->{sbinfo} ||= {
		width => -1,
	};

	if ($width != $sbinfo->{width} || $fonts != $sbinfo->{fonts} || $line != $sbinfo->{line}) {
		$sbinfo->{width} = $width;
		$sbinfo->{fonts} = $fonts;
		$sbinfo->{line}  = $line;
		$sbinfo->{full}  = (Slim::Display::Lib::Fonts::string($fonts->{line}[$line], $display->sliderBar($width, 100)))[1];
		$sbinfo->{empty} = (Slim::Display::Lib::Fonts::string($fonts->{line}[$line], $display->sliderBar($width, 0)))[1];
	}

	my $splicePoint = int($width * $val / 100) * $display->bytesPerColumn;
				
	return substr($sbinfo->{full}, 0, $splicePoint) . substr($sbinfo->{empty}, $splicePoint);
}

sub fonts {
	my $display = shift;
	my $size = shift;

	my $client = $display->client;

	unless (defined $size) {

		# return default font if cached by render
		my $cache = $display->renderCache()->{defaultfont};
		return $cache if defined ($cache);

		$size = $display->textSize();
	}
		
	# grab base for prefname depending on mode
	my $prefname = ($client->power()) ? "activeFont" : "idleFont";
	my $font = $prefs->client($client)->get($prefname)->[ $size ];
	
	my $fontref = Slim::Display::Lib::Fonts::gfonthash();

	if (!$font) { return undef; };

	return $fontref->{$font};
}

# code for handling name to symbol mappings
# 
my %fontSymbols = (
	'notesymbol'  => "\x01",
	'rightarrow'  => "\x02",
	'progressEnd' => "\x03",
	'progress1e'  => "\x04",
	'progress2e'  => "\x05",
	'progress3e'  => "\x06",
	'progress1'   => "\x07",
	'progress2'   => "\x08",
	'progress3'   => "\x09",
	'cursor'	  => "\x0a",
	'mixable'     => "\x0b",
	'circle'      => "\x0c",
	'filledcircle'=> "\x0d",
	'square'      => "\x0e",
	'filledsquare'=> "\x0f",
	'bell'	      => "\x10",
	'sleep'       => "\x11",
	'hardspace'   => "\x20",

	# following are commands rather than symbols
	'tight'       => "\x1d",     # escape command to avoid inter character gap
	'/tight'      => "\x1c",
	'cursorpos'   => "\x0a",     # set cursor position
	'font'        => "\x1b",     # change font - to allow change of font mid string
	'/font'       => "\x1b",
	'defaultfont' => "\x1b\x1b", # return to default font for string
);

sub symbols {
	my $display = shift;
	my $line = shift || return undef;

	return $fontSymbols{$line} if exists $fontSymbols{$line};

	if (defined($line)) {
		$line =~ s/\x1f([^\x1f]+)\x1f/$fontSymbols{$1} || "\x1F" . $1 . "\x1F"/eg;
		$line =~ s/\x1etight\x1e/\x1d/g;
		$line =~ s/\x1e\/tight\x1e/\x1c/g;
		$line =~ s/\x1ecursorpos\x1e/\x0a/g;
		$line =~ s/\x1efont\x1e/\x1b/g;
		$line =~ s/\x1e\/font\x1e/\x1b/g;
		$line =~ s/\x1edefaultfont\x1e/\x1b\x1b/g;
	}
	
	return $line;
}

# register custom characters for graphics displays - not called as a method of display
sub setCustomChar {
	my $symbol = shift;
	my $char = shift;
	my $font = shift;

	# $font is intended to be used if occasional custom chars are added to strings
	# it is not efficient for long strings of custom chars from the same font
	# when set custom characters can be included in strings simply by using $client->symbols('charname')

	if ($font) {
		# change font to $font add symbol and change back to default font
		$fontSymbols{$symbol} = "\x1b".$font."\x1b" . $char . "\x1b\x1b";

	} else {
		# just store the symbol to character mapping
		$fontSymbols{$symbol} = $char;
	}
}
=head1 SEE ALSO

L<Slim::Display::Display>

L<Slim::Display::Lib::Fonts>

=cut

1;


