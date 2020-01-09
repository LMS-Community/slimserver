package Slim::Display::Text;

# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.


=head1 NAME

Slim::Display::Text

=head1 DESCRIPTION

L<Slim::Display::Text>
 Display code for text (character) based displays: Slimp3, SB1, squeezeslave
  - 40 (or client controlled) character x 2 lines
  - server side animation

=cut

use strict;

use base qw(Slim::Display::Display);

use Slim::Display::Lib::TextVFD;
use Slim::Utils::Prefs;
use Slim::Utils::Log;

my $prefs = preferences('server');

my $scroll_pad_scroll = 6; # chars of padding between scrolling text
my $scroll_pad_ticker = 8; # chars of padding in ticker mode

my $defaultWidth = 40;     # default character width of display (unless client tells us otherwise)

our $defaultPrefs = {
	'doublesize'          => 0,
	'offDisplaySize'      => 0,
	'powerOffBrightness'  => 1,
	'idleBrightness'      => 2,
	'powerOnBrightness'   => 4,
	'largeTextFont'       => 1,
	'playingDisplayMode'  => 0,
	'playingDisplayModes' => [0..5],
	'scrollRate'          => 0.15,
	'scrollRateDouble'    => 0.1,
};


sub initPrefs {
	my $display = shift;

	if (!$prefs->get('loadFontsText')) {
		$prefs->set('loadFontsText', 1);
	}

	$prefs->client($display->client)->init($defaultPrefs);

	$display->SUPER::initPrefs();
}

sub resetDisplay {
	my $display = shift;

	my $cache = $display->renderCache();
	$cache->{'screens'} = 1;
	$cache->{'maxLine'} = 1;
	$cache->{'screen1'} = { 'ssize' => 0 };

	$display->killAnimation();
}	

sub linesPerScreen {
	my $display = shift;
	return $display->textSize() ? 1 : 2;	
}

sub displayWidth {
	my $display = shift;
	return $display->widthOverride || $defaultWidth;
}

sub vfdmodel {
	my $display = shift;
	my $client = $display->client;

	if ($client->isa('Slim::Player::SLIMP3')) {
		if ($client->revision >= 2.2) {
			my $mac = $client->macaddress();
			if ($mac eq '00:04:20:03:04:e0') {
				return 'futaba-latin1';
			} elsif ($mac eq '00:04:20:02:07:6e' ||
					 $mac =~ /^00:04:20:04:1/ ||
					 $mac =~ /^00:04:20:00:/	) {
				return 'noritake-european';
			} else {
				return 'noritake-katakana';
			}
		} else {
			return 'noritake-katakana';
		}
	} elsif ($client->isa('Slim::Player::SqueezeSlave')) {  
		return 'squeezeslave';
	} else {
		# Squeezebox 1
		return 'noritake-european';
	}
}

# Render function for character displays
sub render {
	my $display = shift;
	my $parts = shift;
	my $scroll = shift || 0; # 0 = no scroll, 1 = wrapped scroll if line too long, 2 = non wrapped scroll
	my $client = $display->client;

	my $double;
	my $displayoverlays;

	if ((ref($parts) ne 'HASH')) {

		logError("bad lines function - non hash based display formats are depreciated");
		$parts = {};

	} elsif (!exists($parts->{screen1}) &&
		(exists($parts->{line1}) || exists($parts->{line2}) || exists($parts->{center1}) || exists($parts->{center2})) ) {
		# Backwards compatibility with 6.2 display hash
		$parts->{screen1}->{line}    = [ $parts->{line1}, $parts->{line2} ];
		$parts->{screen1}->{overlay} = [ $parts->{overlay1}, $parts->{overlay2} ];
		$parts->{screen1}->{center}  = [ $parts->{center1}, $parts->{center2} ];
	}

	my $cache = $display->renderCache();

	# Per screen components of render cache
	#  line            - array of cached lines
	#  overlay         - array of cached overlays
	#  center          - array of cached centers
	#  linetext        - array of text for cached lines
	#  overlaytext     - array of text for cached overlays
	#  centertext      - array of text for cached centers
	#  linefinish      - array of lengths of cached line bitmaps (where the line finishes)
	#  overlaystart    - array of screensize - lengths of cached overlay bitmaps (where the overlay start)
	#  textref         - array of refs for static result of render

	# Per screen scrolling data
	#  scroll          - scrolling state of render: 
	#                    0 = no scroll, 1 = normal scroll, 2 = ticker scroll - update, 3 = ticker - no update
	#  scrollline      - line which is scrolling [undef if no scrolling]
	#  scrollref       - array of refs for scrolling component of render result
	#  scrollstart     - start offset of scroll
	#  scrollend       - end offset of scroll
	#  scrolldir       - direction to scroll: always 1 as character displays don't scroll r->l
	#  scrolltype      - for normal scroll, value of $scroll, 1 = wrapped scroll, 2 = non wrapped scroll
	#  [nb only scroll and scrollline are cleared when scrolling stops, others can contain stale data]

	# Per screen flags
	#  present         - this screen is present in the last display hash send to render
	#  changed         - this screen changed in the last render
	#  newscroll       - new scrollable text produced by this render - scrolling should restart

	my $screen;                     # screen definition to render
	my $sc = $cache->{screen1};     # screen cache for this screen

	if (!exists($parts->{screen1}) && 
		(exists($parts->{line}) || exists($parts->{center}) || exists($parts->{overlay}) || 
		 exists($parts->{ticker}) || exists($parts->{bits}))){ 
		$screen = $parts;           # components allowed at top level of display hash
	} else {
		$screen = $parts->{screen1};
	}

	# reset flags per render
	$sc->{changed} = 0;
	$sc->{newscroll} = 0;
	$sc->{present} = 1;

	# force (re)initialisation of cache if size changed
	if ($sc->{ssize} != $display->displayWidth) {
		$sc->{double} = 0;
		$sc->{changed} = 1;
		$sc->{ssize} = $display->displayWidth;
	}

	# check display hash for text size definitions
	if (defined($screen->{fonts}) && defined($parts->{fonts}->{text})) {
		my $text = $screen->{fonts}->{text};
		if (ref($text) eq 'HASH') {
			if (defined($text->{lines})) {
				if     ($text->{lines} == 1) { $double = 1; }
				elsif ($text->{lines} == 2) { $double = 0; }
			}
			$displayoverlays = $text->{displayoverlays} if exists $text->{displayoverlays};
		} else {
			if    ($text == 1) { $double = 1; } 
			elsif ($text == 2) { $double = 0; }
		}
	} 
	if (defined($screen->{double})) {
		$double = $screen->{double};
	}
	if (!defined($double)) { $double = $display->textSize() ? 1 : 0; }

	if ($double != $sc->{double}) {
		$sc->{double} = $double;
		$sc->{changed} = 1;
	}

	if ($sc->{changed}) {
		foreach my $l (0..1) {
			$sc->{line}[$l] = undef; $sc->{linetext}[$l] = ''; $sc->{linefinish}[$l] = 0;
			$sc->{overlay}[$l] = undef; $sc->{overlaytext}[$l] = ''; $sc->{overlaystart}[$l] = $display->displayWidth;
			$sc->{center}[$l] = undef; $sc->{centertext}[$l] = '';
		}
		$sc->{scroll} = 0;
		$sc->{scrollline} = undef;
	}

	if (!$scroll) { 
		$sc->{scroll} = 0;
		$sc->{scrollline} = undef;
	}

	# if doubled and nothing on line[1], copy line[0]
	if ($double && (!$screen->{line}[1] || $screen->{line}[1] eq '')) {
		$screen->{line}[1] = $screen->{line}[0];
	}

	# lines - render if changed 
	foreach my $l (0..1) {
		if (defined($screen->{line}[$l]) && 
			(!defined($sc->{line}[$l]) || ($screen->{line}[$l] ne $sc->{line}[$l]))) {
			$sc->{line}[$l] = $screen->{line}[$l];
			next if ($double && $l == 0);
			if (!$double) {
				if (Slim::Utils::Unicode::encodingFromString($screen->{line}[$l], 'ignore-utf8-flag') eq 'raw') {
					# SliMP3 / Pre-G can't handle wide characters outside the latin1 range - turn off the utf8 flag.
					$sc->{linetext}[$l] = Slim::Utils::Unicode::utf8off($screen->{line}[$l]);
				} else {
					$sc->{linetext}[$l] = $screen->{line}[$l];
				}
				$sc->{linefinish}[$l] = lineLength($sc->{linetext}[$l]);
			} else {
				($sc->{linetext}[0], $sc->{linetext}[1]) =
					Slim::Display::Lib::TextVFD::doubleSize($client,$screen->{line}[1]);
				$sc->{linefinish}[0] = lineLength($sc->{linetext}[0]);
				$sc->{linefinish}[1] = lineLength($sc->{linetext}[1]);
			}
			if ($sc->{scroll} && ($sc->{scrollline} == $l || $double)) {
				$sc->{scroll} = 0; $sc->{scrollline} = undef;
			}
			$sc->{changed} = 1;
		} elsif (!defined($screen->{line}[$l]) && defined($sc->{line}[$l])) {
			$sc->{line}[$l] = undef;
			next if ($double && $l == 0);
			$sc->{linetext}[$l] = '';
			$sc->{linefinish}[$l] = 0;
			if ($double) {
				$sc->{linetext}[0] = '';
				$sc->{linefinish}[0] = 0;
			}
			if ($sc->{scroll} && ($sc->{scrollline} == $l) || $double) {
				$sc->{scroll} = 0; $sc->{scrollline} = undef;
			}
			$sc->{changed} = 1;
		}
	}

	# overlays - render if changed
	foreach my $l (0..1) {
		if (defined($screen->{overlay}[$l]) && 
			(!defined($sc->{overlay}[$l]) || ($screen->{overlay}[$l] ne $sc->{overlay}[$l]))) {
			$sc->{overlay}[$l] = $screen->{overlay}[$l];
			if (!$double || $displayoverlays) {
				$sc->{overlaytext}[$l] = $screen->{overlay}[$l];
			} else {
				$sc->{overlaytext}[$l] = '';
			}
			if (lineLength($sc->{overlaytext}[$l]) > $display->displayWidth ) {
				$sc->{overlaytext}[$l] = subString($sc->{overlaytext}[$l], 0, $display->displayWidth);
				$sc->{overlaystart}[$l] = $display->displayWidth;
			} else {
				$sc->{overlaystart}[$l] = $display->displayWidth - lineLength($sc->{overlaytext}[$l]);
			}
			$sc->{changed} = 1;
		} elsif (!defined($screen->{overlay}[$l]) && defined($sc->{overlay}[$l])) {
			$sc->{overlay}[$l] = undef;
			$sc->{overlaytext}[$l] = '';
			$sc->{overlaystart}[$l] = $display->displayWidth;
			$sc->{changed} = 1;
		}
	}

	# centered lines - render if changed
	foreach my $l (0..1) {
		if (defined($screen->{center}[$l]) &&
			(!defined($sc->{center}[$l]) || ($screen->{center}[$l] ne $sc->{center}[$l]))) {
			$sc->{center}[$l] = $screen->{center}[$l];
			next if ($double && $l == 0);
			if (!$double) {
				my $len = lineLength($screen->{center}[$l]); 
				if ($len < $display->displayWidth - 1) {
					$sc->{centertext}[$l] = ' ' x (($display->displayWidth - $len)/2) . $screen->{center}[$l] . 
						' ' x ($display->displayWidth - $len - int(($display->displayWidth - $len)/2));
				} else {
					$sc->{centertext}[$l] = subString($screen->{center}[$l] . ' ', 0, $display->displayWidth);
				}
			} else {
				my ($center1, $center2) = Slim::Display::Lib::TextVFD::doubleSize($client,$screen->{center}[1]);
				my $len = lineLength($center1);
				if ($len < $display->displayWidth - 1) {
					$sc->{centertext}[0] = ' ' x (($display->displayWidth - $len)/2) . $center1 . ' ' x ($display->displayWidth - $len - int(($display->displayWidth - $len)/2));
					$sc->{centertext}[1] = ' ' x (($display->displayWidth - $len)/2) . $center2 . ' ' x ($display->displayWidth - $len - int(($display->displayWidth - $len)/2));
				} else {
					$sc->{centertext}[0] = subString($center1 . ' ', 0 ,$display->displayWidth);
					$sc->{centertext}[1] = subString($center2 . ' ', 0 ,$display->displayWidth);
				}
			}
			$sc->{changed} = 1;
		} elsif (!defined($screen->{center}[$l]) && defined($sc->{center}[$l])) {
			$sc->{center}[$l] = undef;
			next if ($double && $l == 0);
			$sc->{centertext}[$l] = '';
			$sc->{centertext}[0] = '' if ($double);
			$sc->{changed} = 1;
		}
	}

	# ticker component - convert directly to new scrolling state
	if (exists($screen->{ticker})) {
		my @ticker = ('', '');
		$sc->{scrollline} = -1;                               # dummy line if no ticker text
		$sc->{newscroll} = 1 if ($sc->{scroll} < 2);          # switching scroll mode
		my $len = 0;

		foreach my $l (0..1) {
			next if ($double && $l == 0);
			if (exists($screen->{ticker}[$l]) && defined($screen->{ticker}[$l])) {
				$sc->{scrollline} = $l;
				if (!$double) {
					$ticker[$l] = $screen->{ticker}[$l];
					$len = lineLength($ticker[$l]);
				} else {
					($ticker[0], $ticker[1]) = Slim::Display::Lib::TextVFD::doubleSize($client,$screen->{ticker}[$l]);
					$len = lineLength($ticker[$l]);
				}
				last;
			}
		}
		if ($len > 0 || $sc->{scroll} < 2) {
			$ticker[$sc->{scrollline}] .= ' ' x $scroll_pad_ticker;
			$ticker[0] .= ' ' x $scroll_pad_ticker if ($double);
			$sc->{scrollend} = $len;
			$sc->{scroll} = 2;
		} else {
			$sc->{scrollend} = 0;
			$sc->{scroll} = 3;
		}
		$sc->{scrollref}[0] = \$ticker[0];
		$sc->{scrollref}[1] = \$ticker[1];

		$sc->{scrolldir} = 1;
		$sc->{scrollstart} = 0;
		$sc->{changed} = 1;

	} elsif ($sc->{scroll} >= 2) {
		$sc->{scroll} = 0;
		$sc->{scrollline} = undef;
	}

	# Assemble components

	# Potentially scrollable lines + overlays + centered text
	for (my $l = 1; $l >= 0; $l--) { # do in reverse order as prefer to scroll lower lines

		my $line;

		if ($sc->{centertext}[$l]) {
			# centered text takes precedence
			$line = subString($sc->{centertext}[$l], 0, $sc->{overlaystart}[$l]). 
				$sc->{overlaytext}[$l];

		} elsif ($sc->{linefinish}[$l] <= $sc->{overlaystart}[$l] ) {
			# no need to scroll - assemble line + pad + overlay
			$line = $sc->{linetext}[$l] . ' ' x ($sc->{overlaystart}[$l] - $sc->{linefinish}[$l]) . 
				$sc->{overlaytext}[$l];

		} elsif (!$scroll || ($sc->{scroll} && $sc->{scrollline} != $l) ) {
			# scrolling not enabled or already scrolling for another line - truncate line
			$line = subString($sc->{linetext}[$l], 0, $sc->{overlaystart}[$l]) .
				$sc->{overlaytext}[$l];

		} elsif ($sc->{scroll} && $sc->{scrollline} == $l && $sc->{scrolltype} == $scroll) {
			# scrolling already on this line - add overlay only
			$line = ' ' x $sc->{overlaystart}[$l] . $sc->{overlaytext}[$l];

		} else {
			# scrolling allowed and not currently scrolling - create scrolling state

			$sc->{scrolldir} = 1; # Character players only support left -> right scrolling

			my $scrolltext = $sc->{linetext}[$l];

			$sc->{scrollstart} = 0;
			if ($scroll == 1) {
				# normal wrapped text scrolling
				$scrolltext .= ' ' x $scroll_pad_scroll . subString($scrolltext, 0, $display->displayWidth);
				$sc->{scrollend} = $sc->{linefinish}[$l] + $scroll_pad_scroll;
				$sc->{scrolltype} = 1;
			} else {
				# don't wrap text - scroll to end only
				$sc->{scrollend} = $sc->{linefinish}[$l] - $display->displayWidth;
				$sc->{scrolltype} = 2;
			}

			if (!$double || $l == 0) {
				# if doubled only set scroll state on second pass - $l = 0
				$sc->{scroll} = 1;
				$sc->{scrollline} = $l; 
				$sc->{newscroll} = 1;
			}

			$sc->{scrollref}[$l] = \$scrolltext;
			
			# add overlay only to static bitmap
			$line = ' ' x $sc->{overlaystart}[$l] . $sc->{overlaytext}[$l];
		}

		$sc->{lineref}[$l] = \$line;
	}

	return $cache;
}

sub updateScreen {
	my $display = shift;
	my $screen = shift;
	Slim::Display::Lib::TextVFD::vfdUpdate($display->client, ${$screen->{lineref}[0]}, ${$screen->{lineref}[1]});
}

sub pushLeft {
	my $display = shift;
	my $start = shift || $display->renderCache();
	my $end = shift || $display->client->curLines({ trans => 'pushLeft' });

	my $renderstart = $display->render($start);
	my ($line1start, $line2start) = ($renderstart->{screen1}->{lineref}[0], $renderstart->{screen1}->{lineref}[1]);
	my $renderend = $display->render($end);
	my ($line1end, $line2end) = ($renderend->{screen1}->{lineref}[0], $renderend->{screen1}->{lineref}[1]);

	my $line1 = $$line1start . $$line1end;
	my $line2 = $$line2start . $$line2end;

	$display->killAnimation();
	$display->pushUpdate([\$line1, \$line2, 0, 4, $display->displayWidth,  0.02]);

	if ($display->notifyLevel == 2) {
		$display->notify('update');
	}
}

sub pushRight {
	my $display = shift;
	my $start = shift || $display->renderCache();
	my $end = shift || $display->client->curLines({ trans => 'pushRight' });

	my $renderstart = $display->render($start);
	my ($line1start, $line2start) = ($renderstart->{screen1}->{lineref}[0], $renderstart->{screen1}->{lineref}[1]);
	my $renderend = $display->render($end);
	my ($line1end, $line2end) = ($renderend->{screen1}->{lineref}[0], $renderend->{screen1}->{lineref}[1]);

	my $line1 = $$line1end . $$line1start;
	my $line2 = $$line2end . $$line2start;

	$display->killAnimation();
	$display->pushUpdate([\$line1, \$line2, $display->displayWidth, -4, 0,  0.02]);

	if ($display->notifyLevel == 2) {
		$display->notify('update');
	}
}

sub pushUp {
	my $display = shift;

	$display->killAnimation();
	$display->update($display->curLines({ trans => 'pushUp' }));
	$display->simulateANIC;
}

sub pushDown {
	my $display = shift;

	$display->killAnimation();
	$display->update($display->curLines({ trans => 'pushDown' }));
	$display->simulateANIC;
}

sub bumpRight {
	my $display = shift;

	my $render = $display->render($display->renderCache());
	my $line1 = ${$render->{screen1}->{lineref}[0]} . $display->symbols('hardspace');
	my $line2 = ${$render->{screen1}->{lineref}[1]} . $display->symbols('hardspace');

	$display->killAnimation();
	$display->pushUpdate([\$line1, \$line2, 2, -1, 0, 0.125]);	
}

sub bumpLeft {
	my $display = shift;

	my $render = $display->render($display->renderCache());
	my $line1 = $display->symbols('hardspace') . ${$render->{screen1}->{lineref}[0]};
	my $line2 = $display->symbols('hardspace') . ${$render->{screen1}->{lineref}[1]};

	$display->killAnimation();
	$display->pushUpdate([\$line1, \$line2, -1, 1, 1, 0.125]);	
}

sub pushUpdate {
	my $display = shift;
	my $params = shift;
	my ($line1, $line2, $offset, $delta, $end, $deltatime) = @$params;
	
	$offset += $delta;
	# With custom widths, offset may not be a factor of the width, so fix up to avoid problems!
	$offset=$end if ($delta > 0 && $offset > $end); 
	$offset=$end if ($delta < 0 && $offset < $end);

	my $screenline1 = subString($$line1, $offset, $display->displayWidth);
	my $screenline2 = subString($$line2, $offset, $display->displayWidth);

	Slim::Display::Lib::TextVFD::vfdUpdate($display->client, $screenline1, $screenline2);		

	if ($offset != $end) {
		$display->updateMode(1);
		$display->animateState(3);
		Slim::Utils::Timers::setHighTimer($display,Time::HiRes::time() + $deltatime,\&pushUpdate,[$line1,$line2,$offset,$delta,$end,$deltatime]);
	} else {
		$display->simulateANIC;
	}
}

sub bumpDown {
	my $display = shift;

	my $render = $display->render($display->renderCache());
	my $line1 = ${$render->{screen1}->{lineref}[1]};
	my $line2 = ' ' x $display->displayWidth;

	Slim::Display::Lib::TextVFD::vfdUpdate($display->client, $line1, $line2);		

	$display->updateMode(1);
	$display->animateState(4);
	Slim::Utils::Timers::setHighTimer($display,Time::HiRes::time() + 0.125, \&endAnimation);
}

sub bumpUp {
	my $display = shift;

	my $render = $display->render($display->renderCache());
	my $line1 = ' ' x $display->displayWidth;
	my $line2 = ${$render->{screen1}->{lineref}[0]};

	Slim::Display::Lib::TextVFD::vfdUpdate($display->client, $line1, $line2);		

	$display->updateMode(1);
	$display->animateState(4);
	Slim::Utils::Timers::setHighTimer($display,Time::HiRes::time() + 0.125, \&endAnimation);
}

sub brightness {
	my $display = shift;
	my $delta = shift;

	my $brightness = $display->SUPER::brightness($delta);
	$display->update($display->renderCache()) if ($delta);

	return $brightness;
}

sub maxBrightness {
	return $Slim::Display::Lib::TextVFD::MAXBRIGHTNESS;
}

sub brightnessMap {
	return (0 .. maxBrightness());
}

sub modes {
	my $display = shift;
	# Display Modes
	
	my @modes = (
		# mode 0
		{ desc => ['BLANK'],
		  bar => 0, secs => 0,  width => $display->displayWidth, },
		# mode 1
		{ desc => ['ELAPSED'],
		  bar => 0, secs => 1,  width => $display->displayWidth, },
		# mode 2
		{ desc => ['REMAINING'],
		  bar => 0, secs => -1, width => $display->displayWidth, },
		# mode 3
		{ desc => ['PROGRESS_BAR'],
		  bar => 1, secs => 0,  width => $display->displayWidth, },
		# mode 4
		{ desc => ['ELAPSED', 'AND', 'PROGRESS_BAR'],
		  bar => 1, secs => 1,  width => $display->displayWidth, },
		# mode 5
		{ desc => ['REMAINING', 'AND', 'PROGRESS_BAR'],
		  bar => 1, secs => -1, width => $display->displayWidth, },
		# mode 6
		{ desc => ['SETUP_SHOWBUFFERFULLNESS'],
		  bar => 1, secs => 0,  width => $display->displayWidth, fullness => 1, },
	   );
	
	return \@modes;
}

sub nmodes { 6 }

sub scrollUpdateDisplay {
	# update scrolling for character display
	my $display = shift;
	my $scroll = shift;

	my ($line1, $line2);
	
	my $padlen = $scroll->{overlaystart} - ($scroll->{scrollend} - $scroll->{offset});
	$padlen = 0 if ($padlen < 0);
	my $pad = ' ' x $padlen;

	if (!$scroll->{double}) {
		if ($scroll->{scrollline} == 0) {
			# top line scrolling
			$line2 = ${$scroll->{line2ref}};
			if ($padlen) {
				$line1 = subString(${$scroll->{scrollline1ref}} . $pad, $scroll->{offset}, $scroll->{overlaystart}) . $scroll->{overlay1text};
			} else {
				$line1 = subString(${$scroll->{scrollline1ref}}, $scroll->{offset}, $scroll->{overlaystart}) . $scroll->{overlay1text};
			}
		} else {
			# bottom line scrolling
			$line1 = ${$scroll->{line1ref}};
			if ($padlen) {
				$line2 = subString(${$scroll->{scrollline2ref}} . $pad, $scroll->{offset}, $scroll->{overlaystart}) . $scroll->{overlay2text};
			} else {
				$line2 = subString(${$scroll->{scrollline2ref}}, $scroll->{offset}, $scroll->{overlaystart}) . $scroll->{overlay2text};
			}
		}
	} else {
		# both lines scrolling
		if ($padlen) {
			$line1 = subString(${$scroll->{scrollline1ref}} . $pad, $scroll->{offset}, $display->displayWidth);
			$line2 = subString(${$scroll->{scrollline2ref}} . $pad, $scroll->{offset}, $display->displayWidth);
		} else {
			$line1 = subString(${$scroll->{scrollline1ref}}, $scroll->{offset}, $display->displayWidth);
			$line2 = subString(${$scroll->{scrollline2ref}}, $scroll->{offset}, $display->displayWidth);
		}
	}

	Slim::Display::Lib::TextVFD::vfdUpdate($display->client, $line1, $line2);
}

sub scrollUpdateTicker {
	my $display = shift;
	my $screen = shift;

	my $scroll = $display->scrollData();
	my $double = $scroll->{double};
	my $scrollline = $screen->{scrollline};

	my $len = $scroll->{scrollend} - $scroll->{offset};
	my $padChar = $scroll_pad_ticker;

	my $pad = 0;
	if ($screen->{overlaystart}[$scrollline] > ($len + $padChar)) {
		$pad = $screen->{overlaystart}[$scrollline] - $len - $padChar;
	}

	if ($double || $scrollline == 0) {
		my $line1 = subString(${$scroll->{scrollline1ref}}, $scroll->{offset});
		$line1 .= ' ' x $pad;
		$line1 .= ${$screen->{scrollref}[0]};
		$scroll->{scrollline1ref} = \$line1;
	}
	if ($double || $scrollline == 1) {
		my $line2 = subString(${$scroll->{scrollline2ref}}, $scroll->{offset});
		$line2 .= ' ' x $pad;
		$line2 .= ${$screen->{scrollref}[1]};
		$scroll->{scrollline2ref} = \$line2;
	}

	$scroll->{scrollend} = $len + $padChar + $pad + $screen->{scrollend};
	$scroll->{offset} = 0;
	$scroll->{scrollline} = $scrollline;
}

sub simulateANIC {
	my $display = shift;

	$display->animateState(2);
	Slim::Utils::Timers::setHighTimer($display, Time::HiRes::time() + 1.5, \&Slim::Display::Display::update);
}

sub endAnimation {
	shift->SUPER::endAnimation(@_);
}

sub killAnimation {
	# kill all server side animation in progress and clear state
	my $display = shift;
	my $exceptScroll = shift; # all but scrolling to be killed

	my $animate = $display->animateState();

	Slim::Utils::Timers::killHighTimers($display, \&Slim::Display::Display::update) if ($animate == 2);
	Slim::Utils::Timers::killHighTimers($display, \&pushUpdate) if ($animate == 3);	
	Slim::Utils::Timers::killHighTimers($display, \&endAnimation) if ($animate == 4);
	Slim::Utils::Timers::killTimers($display, \&Slim::Display::Display::endAnimation) if ($animate >= 5);

	$display->scrollStop() if (($display->scrollState() > 0) && !$exceptScroll) ;
	$display->animateState(0);
	$display->updateMode(0);
	$display->endShowBriefly() if ($animate == 5);
}

sub textSize {
	# textSize = 1 for LARGE text, 0 for small.
	my $display = shift;
	my $newsize = shift;
	my $client = $display->client;

	my $prefname = ($client->power()) ? "doublesize" : "offDisplaySize";
	
	if (defined($newsize)) {
		return	$prefs->client($client)->set($prefname, $newsize);
	} else {
		return	$prefs->client($client)->get($prefname);
	}
}

sub maxTextSize {
	return 1;
}

sub measureText {
	my $display = shift;
	my $text = shift;
	return lineLength($text);
}

# Draws a slider bar, bidirectional or single direction is possible.
# $value should be pre-processed to be from 0-100
# $midpoint specifies the position of the divider from 0-100 (use 0 for progressBar)
sub sliderBar {
	my ($display, $width, $value, $midpoint, $fullstep) = @_;

	$midpoint = 0 unless defined $midpoint;
	if ($width == 0) {
		return "";
	}
	
	my $charwidth = 5;

	if ($value < 0) {
		$value = 0;
	}
	
	if ($value > 100) {
		$value = 100;
	}
	
	my $chart = "";
	
	my $totaldots = $charwidth + ($width - 2) * $charwidth + $charwidth;

	# felix mueller discovered some rounding errors that were causing the
	# calculations to be off.  Doing it 1000 times up seems to be better.  
	# go figure.
	my $dots = int( ( ( $value * 10 ) * $totaldots) / 1000);
	my $divider = ($midpoint/100) * ($width-2);

	my $val = $value/100 * $width;
	$width = $width - 1 if $midpoint;
	
	if ($dots < 0) { $dots = 0 };
	
	if ($dots < $charwidth) {
		$chart = $midpoint ? $display->symbols('leftprogress4') : $display->symbols('leftprogress'.$dots);
	} else {
		$chart = $midpoint ? $display->symbols('leftprogress0') : $display->symbols('leftprogress4');
	}
	
	$dots -= $charwidth;
			
	if ($midpoint) {
		for (my $i = 1; $i < $divider; $i++) {
			if ($dots <= 0) {
				$chart .= $display->symbols('solidblock');
			} else {
				$chart .= $display->symbols('middleprogress0');
			}
			$dots -= $charwidth;
		}
		if ($value < $midpoint) {
			$chart .= $display->symbols('solidblock');
			$dots -= $charwidth;
		} else {
			$chart .= $display->symbols('leftmark');
			$dots -= $charwidth;
		}
	}
	for (my $i = $divider + 1; $i < ($width - 1); $i++) {
		if ($midpoint && $i == $divider + 1) {
			if ($value > $midpoint) {
				$chart .= $display->symbols('solidblock');
			} else {
				$chart .= $display->symbols('rightmark');
			}
			$dots -= $charwidth;
		}
		if ($dots <= 0) {
			$chart .= $display->symbols('middleprogress0');
		} elsif ($dots < $charwidth && !$fullstep) {
			$chart .= $display->symbols('middleprogress'.$dots);
		} else {
			$chart .= $display->symbols('solidblock');
		}
		$dots -= $charwidth;
	}
		
	if ($dots <= 0) {
		$chart .= $display->symbols('rightprogress0');
	} elsif ($dots < $charwidth && !$fullstep) {
		$chart .= $display->symbols('rightprogress'.$dots);
	} else {
		$chart .= $display->symbols('rightprogress4');
	}
	
	return $chart;
}

sub string {
	my $display = shift;
	return Slim::Utils::Unicode::utf8toLatin1($display->SUPER::string(@_));
}

sub doubleString {
	my $display = shift;
	return Slim::Utils::Unicode::utf8toLatin1($display->SUPER::doubleString(@_));
}

our %Symbols = (
	'notesymbol' => "\x1Fnotesymbol\x1F",
	'rightarrow' => "\x1Frightarrow\x1F",
	'solidblock' => "\x1Fsolidblock\x1F",
	'mixable'    => "\x1Fmixable\x1F",
	'bell'	     => "\x1Fbell\x1F",
	'hardspace'  => "\x1Fhardspace\x1F"
);

our %commandmap = (
	'center'     => "\x1ecenter\x1e",
	'cursorpos'  => "\x1ecursorpos\x1e",
	'framebuf'   => "\x1eframebuf\x1e",
	'/framebuf'  => "\x1e/framebuf\x1e",
	'linebreak'  => "\x1elinebreak\x1e",
	'repeat'     => "\x1erepeat\x1e", 
	'right'      => "\x1eright\x1e",
	'scroll'     => "\x1escroll\x1e",
	'/scroll'    => "\x1e/scroll\x1e", 
);

sub symbols {
	my $display = shift;
	my $line = shift || return undef;

	return $Symbols{$line} if exists $Symbols{$line};
	return $commandmap{$line} if exists $commandmap{$line};
	return "\x1F$line\x1F" if Slim::Display::Lib::TextVFD::isCustomChar($line);

	return $line;
}


# register text custom characters - not called as a method of display
sub setCustomChar {
	Slim::Display::Lib::TextVFD::setCustomChar(@_);
}

# utility functions to manipulate strings including text display control characters

sub lineLength {
	my $line = shift;
	return 0 if (!defined($line) || !length($line));

	$line =~ s/\x1f[^\x1f]+\x1f/x/g;
	$line =~ s/(\x1eframebuf\x1e.*\x1e\/framebuf\x1e|\n|\xe1[^\x1e]\x1e)//gs;
	return length($line);
}

sub splitString {
	my $string = shift;
	my @result = ();
	$string =~ s/(\x1f[^\x1f]+\x1f|\x1eframebuf\x1e.*\x1e\/framebuf\x1e|\x1e[^\x1e]+\x1e|.)/push @result, $1;/esg;
	return \@result;
}

sub subString {
	my ($string,$start,$length,$replace) = @_;
	$string =~ s/\x1eframebuf\x1e.*\x1e\/framebuf\x1e//s if ($string);

	my $newstring = '';
	my $oldstring = '';

	if ($start && $length && ($start > 32765 || ($length || 0) > 32765)) {

		logBacktrace("substr on string with start or length greater than 32k, returning empty string.");

		return '';
	}

	if ($string && $string =~ s/^(((?:(\x1e[^\x1e]+\x1e)|)(?:[^\x1e\x1f]|\x1f[^\x1f]+\x1f)){0,$start})//) {
		$oldstring = $1;
	}

	if (defined($length)) {
		if ($string =~ s/^(((?:(\x1e[^\x1e]+\x1e)|)([^\x1e\x1f]|\x1f[^\x1f]+\x1f)){0,$length})//) {
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

=head1 SEE ALSO

L<Slim::Display::Display>

L<Slim::Display::Lib::TextVFD>

=cut

1;
