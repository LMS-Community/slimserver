package Slim::Display::Display;

# $Id$

# SlimServer Copyright (c) 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

=head1 NAME

Slim::Display::Display

=head1 DESCRIPTION

L<Slim::Display::Display>
 Base for display class - contains display functions common to all display types

=cut

use strict;

use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Timers;
use Slim::Utils::Prefs;

my $prefs = preferences('server');

# Display routines use the following state variables: 
#   $display->updateMode(), $display->screen2updateOK(), $display->animateState(), $display->scrollState()
#
# updateMode: (single value for all screens)
#   0 = normal
#   1 = periodic updates are blocked
#   2 = all updates are blocked
#
# screen2updateOK: single value for second screen to allow periodic update to screen 2 while updateMode set
#   0 = use status of updateMode
#   1 = allow periodic updates of screen2 to bypass updateMode check [animation or showBriefly on screen 1 only]
#
# animateState: (single value for all screens)         Slimp3/SB1      SB1G      SB2/3/Transporter   
#   0 = no animation                                        x             x        x
#   1 = client side push/bump animations                                           x
#   2 = update scheduled (timer set to callback update)                            x   
#   3 = server side push & bumpLeft/Right                   x             x
#   4 = server side bumpUp/Down                             x             x 
#   5 = server side showBriefly                             x             x        x
#   6 = clear scrolling (scrollonce and end scrolling mode) x             x        x
#
# scrollState: (per screen)
#   0 = no scrolling
#   1 = server side normal scrolling
#   2 = server side ticker mode
#  3+ = <reserved for client side scrolling>

my $log = logger('player.display');

our $defaultPrefs = {
	'autobrightness'       => 1,
	'idleBrightness'       => 1,
	'scrollMode'           => 0,
	'scrollPause'          => 3.6,
	'scrollPauseDouble'    => 3.6,
	'scrollRate'           => 0.15,
	'scrollRateDouble'     => 0.1,
};


# create base class - always called via a class which inherits from this one
sub new {
	my $class = shift;
	my $client = shift;
	
	my $display =[];	
	bless $display, $class;

	$display->[0] = \$client; # ref to client
	$display->[1] = 0;        # updateMode [0 = normal, 1 = periodic update blocked, 2 = all updates blocked]
	$display->[2] = 0;        # animateState
	$display->[3] = [0, 0, 0];# scrollState - element 1 = screen1
	$display->[4] = {};       # renderCache
	$display->[5] = [];       # scrollData - element 1 = screen1
	$display->[6] = 1;        # currBrightness
	$display->[7] = undef;    # lastVisMode
	$display->[8] = undef;    # sbCallbackData
	$display->[9] = undef;    # sbOldDisplay
	$display->[10]= undef;    # sbName
	$display->[11]= 0;        # screen2updateOK
	$display->[12]= {};       # displayStrings - strings for this display
	$display->[13]= [];       # widthOverride - element 1 = screen1 (undef if default for display)

	$display->resetDisplay(); # init render cache

	return $display;
}

sub init {
	my $display = shift;

	$prefs->client($display->client)->init($defaultPrefs);

	$display->displayStrings(Slim::Utils::Strings::clientStrings($display->client));
}

# Methods to access display state
sub client {
	return ${shift->[0]};
}
sub updateMode {
	my $r = shift;
	@_ ? ($r->[1] = shift) : $r->[1];
}
sub animateState {
	my $r = shift;
	@_ ? ($r->[2] = shift) : $r->[2];
}    
sub scrollState {
	my $r = shift;
	my $s = shift || 1;
	@_ ? ($r->[3][$s] = shift) : $r->[3][$s];
}    
sub renderCache {
	my $r = shift;
	@_ ? ($r->[4] = shift) : $r->[4];
}    
sub scrollData {
	my $r = shift;
	my $s = shift || 1;
	@_ ? ($r->[5][$s] = shift) : $r->[5][$s];
}    
sub currBrightness {
	my $r = shift;
	@_ ? ($r->[6] = shift) : $r->[6];
}    
sub lastVisMode {
	my $r = shift;
	@_ ? ($r->[7] = shift) : $r->[7];
}    
sub sbCallbackData {
	my $r = shift;
	@_ ? ($r->[8] = shift) : $r->[8];
}
sub sbOldDisplay {
	my $r = shift;
	@_ ? ($r->[9] = shift) : $r->[9];
}
sub sbName {
	my $r = shift;
	@_ ? ($r->[10] = shift) : $r->[10];
}
sub screen2updateOK {
	my $r = shift;
	@_ ? ($r->[11] = shift) : $r->[11];
}
sub displayStrings {
	my $r = shift;
	@_ ? ($r->[12] = shift) : $r->[12];
}
sub widthOverride {
	my $r = shift;
	my $s = shift || 1;
	@_ ? ($r->[13][$s] = shift) : $r->[13][$s];
}

################################################################################################

# main display function - all screen updates [other than push/bumps] are driven by this function
sub update {
	my $display = shift;
	my $parts   = shift;
	my $scrollMode = shift;	# 0 = normal scroll, 1 = scroll once only, 2 = no scroll, 3 = scroll once and end
	my $s2periodic = shift; # flag to indicate called by peridic update for screen 2 [to bypass some state checks]
	my $client  = $display->client;

	$parts ||= $display->curLines;

	unless ($s2periodic && $display->screen2updateOK) {

		# return if updates are blocked
		return if ($display->updateMode() == 2);

		# clear any server side animations or pending updates, don't kill scrolling
		$display->killAnimation(1) if ($display->animateState() > 0);

	} elsif ($display->sbOldDisplay()) {

		# replace any stored screen 2 for show briefly
		$display->sbOldDisplay()->{'screen2'} = $parts->{'screen2'};

	}

	if (!defined $scrollMode) {
		$scrollMode = $prefs->client($client)->get('scrollMode') || 0;
	}

	my ($scroll, $scrollonce);
	if    ($scrollMode == 0) { $scroll = 1; $scrollonce = 0; }
	elsif ($scrollMode == 1) { $scroll = 1; $scrollonce = 1; }
	elsif ($scrollMode == 2) { $scroll = 0; $scrollonce = 0; }
	elsif ($scrollMode == 3) { $scroll = 2; $scrollonce = 2; }

	my $render = $display->render($parts, $scroll, $s2periodic);

	foreach my $screenNo (1..$render->{screens}) {
		
		my $state = $display->scrollState($screenNo);
		my $screen = $render->{'screen'.$screenNo};

		if (!$screen->{scroll}) {
			# no scrolling required
			if ($state > 0) {
				$display->scrollStop($screenNo);
			}
			$display->updateScreen($screen, $screenNo);

		} else {
			if ($state == 0) {
				# not scrolling - start scrolling
				$display->scrollInit($screen, $screenNo, $scrollonce);

			} elsif ($screen->{newscroll}) {
				# currently scrolling - stop and restart
				$display->scrollStop($screenNo);
				$display->scrollInit($screen, $screenNo, $scrollonce);

			} elsif ($state == 2 && $screen->{scroll} == 2 && $screen->{changed}) {
				# staying in ticker mode - add to ticker queue & update background
				$display->scrollUpdateTicker($screen, $screenNo);
				$display->scrollUpdateBackground($screen, $screenNo);

			} else {
				# same scrolling text, possibly new background
				$display->scrollUpdateBackground($screen, $screenNo);
			}			  
		}
	}

	# return any old display if stored
	$display->returnOldDisplay($render) if (!$s2periodic && $display->sbOldDisplay());

	# notify cli/jive of update - if there is a subscriber this will grab the curDisplay
	$display->notify('update');
}

# show text briefly and then return to original display
sub showBriefly {
	my $display = shift;
	my $parts   = shift;
	my $args    = shift;

	my $client = $display->client;

	if ($log->is_info) {
		my ($line, $subr) = (caller(1))[2,3];
		($line, $subr) = (caller(2))[2,3] if $subr eq 'Slim::Player::Player::showBriefly';
		$log->info(sprintf "caller %s (%d) %s ", $subr, $line, $display->updateMode() == 2 ? '[Blocked]' : '');
	}

	# return if update blocked
	return if ($display->updateMode() == 2);

	my ($duration, $firstLine, $blockUpdate, $scrollToEnd, $brightness, $callback, $callbackargs, $name);

	if (ref($parts) ne 'HASH') {
		logBacktrace("showBriefly should be passed a display hash");
		return;
	}

	if ( $log->is_debug ) {
		$log->debug( Data::Dump::dump($parts) );
	}

	if (ref($args) eq 'HASH') {
		$duration    = $args->{'duration'} || 1; # duration - default to 1 second
		$firstLine   = $args->{'firstline'};     # use 1st line in doubled mode
		$blockUpdate = $args->{'block'};         # block other updates from cancelling
		$scrollToEnd = $args->{'scroll'};        # scroll text once before cancelling if scrolling is necessary
		$brightness   = $args->{'brightness'};   # brightness to display at
		$callback     = $args->{'callback'};     # callback when showBriefly completes
		$callbackargs = $args->{'callbackargs'}; # callback arguments
		$name         = $args->{'name'};         # name - so caller can name who owns current showBriefly
	} else {
		$duration = $args || 1;
		$firstLine   = shift;
		$blockUpdate = shift;
		$scrollToEnd = shift;
		$brightness   = shift;
		$callback     = shift;
		$callbackargs = shift;
		$name         = shift;
	}

	# notify cli/jive of the show briefly message
	$display->notify('showbriefly', $parts);

	if ($firstLine && ($display->linesPerScreen() == 1)) {
		$parts->{line}[1] = $parts->{line}[0];
	}

	my $oldDisplay = $display->sbOldDisplay() || $display->curDisplay();
	$display->sbOldDisplay(undef);

	$display->update($parts, $scrollToEnd ? 3 : undef);
	
	$display->screen2updateOK( ($oldDisplay->{'screen2'} && !$parts->{'screen2'} && !$display->updateMode) ? 1 : 0 );
	$display->updateMode( $blockUpdate ? 2 : 1 );
	$display->animateState(5);

	my $callbackData;
	
	if (defined($brightness)) {
		if ($brightness =~ /powerOn|powerOff|idle/) {
			$brightness = $prefs->client($display->client)->get($brightness.'Brightness');
		}
		$callbackData->{'brightness'} = $display->brightness();
		$display->brightness($brightness);
	}

	if (defined($callback)) {
		$callbackData->{'callback'} = $callback;
		$callbackData->{'callbackargs'} = $callbackargs;
	}

	$display->sbOldDisplay($oldDisplay);
	$display->sbCallbackData($callbackData);
	$display->sbName($name);

	if (!$scrollToEnd || !$display->scrollData()) {
		Slim::Utils::Timers::setTimer($display,Time::HiRes::time() + $duration, \&endAnimation);
	}
}

sub endShowBriefly {
	my $display = shift;

	$display->sbName(undef);

	my $callbackData = $display->sbCallbackData() || return;

	if (defined(my $brightness = $callbackData->{'brightness'})) {
		$display->brightness($brightness);
	}

	if (defined(my $cb = $callbackData->{'callback'})) {
		my $cbargs = $callbackData->{'callbackargs'};
		&$cb($cbargs);
	}

	$display->sbCallbackData(undef);
}

# return old display which was stored during showBriefly, suppressing screens which are covered by last render
sub returnOldDisplay {
	my $display = shift;
	my $render = shift;

	my $oldDisplay = $display->sbOldDisplay();
	my $screens = $render->{screens};

	foreach my $screenNo (1..$render->{screens}) {
		if ($render->{"screen$screenNo"}->{present}) {
			delete $oldDisplay->{"screen$screenNo"};
			$screens--;
		}
	}

	$display->sbOldDisplay(undef);

	$display->update($oldDisplay) if $screens;
}

# push and bumps are display specific
sub pushLeft {}
sub pushRight {}
sub pushUp {}
sub pushDown {}
sub bumpLeft {}
sub bumpRight {}
sub bumpUp {}
sub bumpDown {}

sub brightness {
	my $display = shift;
	my $delta = shift;

	if (defined($delta) ) {

		if ($delta =~ /[\+\-]\d+/) {
			$display->currBrightness( ($display->currBrightness() + $delta) );
		} else {
			$display->currBrightness( $delta );
		}

		$display->currBrightness(0) if ($display->currBrightness() < 0);
		$display->currBrightness($display->maxBrightness()) if ($display->currBrightness() > $display->maxBrightness());
	}
	
	my $brightness = $display->currBrightness();

	if (!defined($brightness)) { $brightness = $display->maxBrightness(); }	

	return $brightness;
}

sub prevline1 {
	my $display = shift;
	my $cache = $display->renderCache() || return;
	return $cache->{screen1}->{line}[0];
}

sub prevline2 {
	my $display = shift;
	my $cache = $display->renderCache() || return;
	return $cache->{screen1}->{line}[1];
}

sub curDisplay {
	my $display = shift;

	my $parts;
	my $render = $display->renderCache();

	foreach my $s (1..$render->{screens}) {
		my $sc = $render->{'screen'.$s};
		foreach my $c ('line', 'overlay', 'center') {
			$parts->{"screen$s"}->{"$c"} = Storable::dclone($sc->{"$c"}) if $sc->{"$c"};
		}
		if ($sc->{'fonts'}) {
			my $model = $display->vfdmodel();
			$parts->{"screen$s"}->{'fonts'}->{"$model"} = Storable::dclone($sc->{'fonts'});
		}
	}

	return $parts;
}

sub curLines {
	my $display = shift;

	unless ($display->isa('Slim::Display::Display')) {
		# not called as a display method
		logBacktrace("This function is depreciated, please call \$client->curLines() or \$display->curLines()");
		return;
	}

	my $client = $display->client;
	my $linefunc = $client->lines;
	my $parts;

	if (defined $linefunc) {
		$parts = eval {  $display->parseLines(&$linefunc($client)) };

		if ($@) {
			logError("bad lines function: $@");
		}
	}

	if ($log->is_info) {

		my $source = Slim::Utils::PerlRunTime::realNameForCodeRef($linefunc);
		my ($line, $sub, @subs);
		my $frame = 1;

		do {
			($line, $sub) = (caller($frame++))[2,3];
			push @subs, $sub;
		} while ($sub && $sub =~ /Slim::Display|Slim::Player::Player::update|Slim::Player::Player::push/);

		$log->info(sprintf "lines $source [%s($line)]", join(", ", @subs));
		$log->debug( Data::Dump::dump($parts) );
	}

	return $parts;
}

# Parse lines into the latest hash format.  Provides backward compatibility for array and escaped lines definitions
# NB will not convert 6.2 hash into a 6.5 hash - this is done in render
sub parseLines {
	my $display = shift;
	my $lines = shift;
	my ($line1, $line2, $line3, $line4, $overlay1, $overlay2, $center1, $center2, $bits);

	return $lines if (ref($lines) eq 'HASH');

	logBacktrace("lines function not using display hash, please update to display hash as this will be depreciated");

	if (ref($lines) eq 'SCALAR') {
		$line1 = $$lines;
	} else {
		if (ref($lines) eq 'ARRAY') {
			$line1= $lines->[0];
			$line2= $lines->[1];
			$line3= $lines->[2];
			$line4= $lines->[3];
		} else {
			$line1 = $lines;
			$line2 = shift;
			$line3 = shift;
			$line4 = shift;
		}
		
		return $line1 if (ref($line1) eq 'HASH');
		
		if (!defined($line1)) { $line1 = ''; }
		if (!defined($line2)) { $line2 = ''; }

		$line1 .= "\x1eright\x1e" . $line3 if (defined($line3));

		$line2 .= "\x1eright\x1e" . $line4 if (defined($line4));

		if (length($line2)) { 
			$line1 .= "\x1elinebreak\x1e" . $line2;
		}
	}

	while ($line1 =~ s/\x1eframebuf\x1e(.*)\x1e\/framebuf\x1e//s) {
		$bits |= $1;
	}

	$line1 = $display->symbols($line1) || '';
	($line1, $line2) = split("\x1elinebreak\x1e", $line1);

	if (!defined($line2)) { $line2 = '';}
	
	($line1, $overlay1) = split("\x1eright\x1e", $line1) if $line1;
	($line2, $overlay2) = split("\x1eright\x1e", $line2) if $line2;

	($line1, $center1) = split("\x1ecenter\x1e", $line1) if $line1;
	($line2, $center2) = split("\x1ecenter\x1e", $line2) if $line2;

	$line1 = '' if (!defined($line1));

	return {
		'bits'    => $bits,
		'line'    => [ $line1, $line2 ],
		'overlay' => [ $overlay1, $overlay2 ],
		'center'  => [ $center1, $center2 ],
	};
}

sub renderOverlay {
	logBacktrace("renderOverlay depreciated - please use parseLines()");

	return shift->parseLines(@_);
}

sub sliderBar {}

sub progressBar {
	my $display = shift;
	return $display->sliderBar(shift,(shift)*100,0,undef,shift);
}

sub balanceBar {
	my $display = shift;
	return $display->sliderBar(shift,shift,50);
}

# initiate server side scrolling for display
sub scrollInit {
	my $display = shift;
	my $screen = shift;
	my $screenNo = shift;
	my $scrollonce = shift; # 0 = continue scrolling after pause, 1 = scroll to scrollend and then stop, 
	                        # 2 = scroll to scrollend and then end animation (causing new update)

	my $client = $display->client;

	my $ticker = ($screen->{scroll} == 2);

	my $refresh = $prefs->client($client)->get($display->linesPerScreen() == 1 ? 'scrollRateDouble': 'scrollRate'  );
	my $pause   = $prefs->client($client)->get($display->linesPerScreen() == 1 ? 'scrollPauseDouble': 'scrollPause');

	my $now = Time::HiRes::time();
	my $start = $now + ($ticker ? 0 : (($pause > 0.5) ? $pause : 0.5));

	my $scroll = {
		'scrollstart'   => $screen->{scrollstart},
		'scrollend'     => $screen->{scrollend},
		'offset'        => $screen->{scrollstart},
		'dir'           => $screen->{scrolldir},
		'scrollonce'    => ($scrollonce || $ticker) ? 1 : 0,
		'scrollonceend' => ($scrollonce == 2) ? 1 : 0,
		'refreshInt'    => $refresh,
		'pauseInt'      => $pause,
		'pauseUntil'    => $start,
		'refreshTime'   => $start,
		'paused'        => 0,
		'overlaystart'  => $screen->{overlaystart}[$screen->{scrollline}],
		'ticker'        => $ticker,
	};

	if (defined($screen->{bitsref})) {
		# graphics display
		my $pixels = $prefs->client($client)->get($display->linesPerScreen() == 1 ? 'scrollPixelsDouble': 'scrollPixels');
		$scroll->{shift} = $pixels * $display->bytesPerColumn() * $screen->{scrolldir};
		$scroll->{scrollHeader} = $display->scrollHeader($screenNo);
		$scroll->{scrollFrameSize} = length($display->scrollHeader) + $display->screenBytes($screenNo);
		$scroll->{bitsref} = $screen->{bitsref};
		if (!$ticker) {
			$scroll->{scrollbitsref} = $screen->{scrollbitsref};
		} else {
			my $tickerbits = (chr(0) x $screen->{overlaystart}[$screen->{scrollline}]) . ${$screen->{scrollbitsref}};
			$scroll->{scrollbitsref} = \$tickerbits;
			$scroll->{scrollend} += $screen->{overlaystart}[$screen->{scrollline}];
		}

	} elsif (defined($screen->{lineref})) {
		# text display
		my $double = $screen->{double};
		$scroll->{shift} = 1;
		$scroll->{double} = $double;
		$scroll->{scrollline} = $screen->{scrollline};
		$scroll->{line1ref} = $screen->{lineref}[0];
		$scroll->{line2ref} = $screen->{lineref}[1];
		$scroll->{overlay1text} = $screen->{overlaytext}[0];
		$scroll->{overlay2text} = $screen->{overlaytext}[1];
		if (!$ticker) {
			$scroll->{scrollline1ref} = $screen->{scrollref}[0];
			$scroll->{scrollline2ref} = $screen->{scrollref}[1];
		} else {
			my $line1 = (' ' x $screen->{overlaystart}[$screen->{scrollline}]) . ${$screen->{scrollref}[0]};
			my $line2 = (' ' x $screen->{overlaystart}[$screen->{scrollline}]) . ${$screen->{scrollref}[1]};
			$scroll->{scrollline1ref} = \$line1;
			$scroll->{scrollline2ref} = \$line2;
			$scroll->{scrollend} += $screen->{overlaystart}[$screen->{scrollline}];
		}
	}

	$display->scrollData($screenNo, $scroll);
	$display->scrollState($screenNo, $ticker ? 2 : 1);
	$display->scrollUpdate($scroll);
}

# stop server side scrolling
sub scrollStop {
	my $display = shift;
	my $screenNo = shift;
	my $scroll = $display->scrollData($screenNo) || return;

	Slim::Utils::Timers::killSpecific($scroll->{timer});

	$display->scrollState($screenNo, 0);
	$display->scrollData($screenNo, undef);
}

# update the background of a scrolling display
sub scrollUpdateBackground {
	my $display = shift;
	my $screen = shift;
	my $screenNo = shift;

	my $scroll = $display->scrollData($screenNo);

	if (defined($screen->{bitsref})) {
		# graphics display
		$scroll->{bitsref} = $screen->{bitsref};

	} elsif (defined($screen->{lineref})) {
		# text display
		$scroll->{line1ref} = $screen->{lineref}[0];
		$scroll->{line2ref} = $screen->{lineref}[1];
		$scroll->{overlay1text} = $screen->{overlaytext}[0];
		$scroll->{overlay2text} = $screen->{overlaytext}[1];
	}

	$scroll->{overlaystart} = $screen->{overlaystart}[$screen->{scrollline}];

	# force update of screen for if paused, otherwise rely on scrolling to update
	if ($scroll->{paused}) {
		$display->scrollUpdateDisplay($scroll);
	}
}

# returns: time to complete ticker, time to expose queued up text
sub scrollTickerTimeLeft {
	my $display = shift;
	my $screenNo = shift || 1;

	my $scroll = $display->scrollData($screenNo);

	if (!$scroll) {
		return (0, 0);
	} 

	my $todisplay = $scroll->{scrollend} - $scroll->{offset};
	my $completeTime = $todisplay / ($scroll->{shift} / $scroll->{refreshInt});

	my $notdisplayed = $todisplay - $scroll->{overlaystart};
	my $queueTime = ($notdisplayed > 0) ? $notdisplayed / ($scroll->{shift} / $scroll->{refreshInt}) : 0;

	return ($completeTime, $queueTime);
}

# update scrolling screen during server side scrolling
sub scrollUpdate {
	my $display = shift;
	my $scroll = shift;

	# update display
	$display->scrollUpdateDisplay($scroll);

	my $timenow = Time::HiRes::time();

	if ($timenow < $scroll->{pauseUntil}) {
		# called during pause phase - don't scroll
		$scroll->{paused} = 1;
		$scroll->{refreshTime} = $scroll->{pauseUntil};
		$scroll->{timer} = Slim::Utils::Timers::setHighTimer($display, $scroll->{pauseUntil}, \&scrollUpdate, $scroll);

	} else {
		# update refresh time and skip frame if running behind actual timenow
		do {
			$scroll->{offset} += $scroll->{shift};
			$scroll->{refreshTime} += $scroll->{refreshInt};
		} while ($scroll->{refreshTime} < $timenow);

		$scroll->{paused} = 0;
		if (($scroll->{dir} == 1 && $scroll->{offset} >= $scroll->{scrollend}) ||
			($scroll->{dir} == -1 && $scroll->{offset} <= $scroll->{scrollend}) ) {
			if ($scroll->{scrollonce}) {
				$scroll->{offset} = $scroll->{scrollend};
				if ($scroll->{ticker}) {
					# keep going to wait for ticker to fill
				} elsif ($scroll->{scrollonce} == 1) {
					# finished scrolling at next scrollUpdate
					$scroll->{scrollonce} = 2;
				} elsif ($scroll->{scrollonce} == 2) {
					# transition to permanent scroll pause state
					$scroll->{offset} = $scroll->{scrollstart};
					$scroll->{paused} = 1;
					if ($scroll->{scrollonceend}) {
						# schedule endAnimaton to kill off scrolling and display new screen
						$display->animateState(6) unless ($display->animateState() == 5);
						my $end = ($scroll->{pauseInt} > 0.5) ? $scroll->{pauseInt} : 0.5;
						Slim::Utils::Timers::setTimer($display, $timenow + $end, \&endAnimation);
					}
					return;
				}
			} elsif ($scroll->{pauseInt} > 0) {
				$scroll->{offset} = $scroll->{scrollstart};
				$scroll->{pauseUntil} = $scroll->{refreshTime} + $scroll->{pauseInt};
			} else {
				$scroll->{offset} = $scroll->{scrollstart};
			}
		}
		# fast timer during scroll
		$scroll->{timer} = Slim::Utils::Timers::setHighTimer($display, $scroll->{refreshTime}, \&scrollUpdate, $scroll);
	}
}

sub endAnimation {
	# called after after an animation to redisplay current screen and initiate scrolling
	my $display = shift;
	my $animate = $display->animateState();
	my $screen = ($animate <= 3) ? $display->renderCache() : undef;
	$display->animateState(0);
	$display->updateMode(0);
	$display->screen2updateOK(0);
	$display->endShowBriefly() if ($animate == 5);
	$display->update($screen);
}	

sub resetDisplay {}
sub killAnimation {}
sub fonts {}
sub displayHeight {}
sub showExtendedText {}
sub modes { [] }
sub nmodes { 0 }
sub hasScreen2 { 0 }
sub vfdmodel {}

sub forgetDisplay {
	my $display = shift;
	Slim::Utils::Timers::forgetTimer($display);
}

sub string {
	my $strings = shift->displayStrings;
	my $name = uc(shift);
	return $strings->{$name} || logBacktrace("missing string $name") && '';
}

sub doubleString {
	my $strings = shift->displayStrings;
	my $name = uc(shift);
	return $strings->{$name.'_DBL'} || $strings->{$name} || logBacktrace("missing string $name") && '';
}

sub notify {
	my $display = shift;
	my $type    = shift;
	my $info    = shift;

	# send a notification for this display update to 'displaystatus' queries
	Slim::Control::Request->new($display->client->id, ['displaynotify', $type, $info])->notify('displaystatus');
}

=head1 SEE ALSO

=cut

1;
