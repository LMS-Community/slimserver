package Slim::Display::Display;

# $Id$

# Logitech Media Server Copyright 2001-2011 Logitech.
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

use base qw(Slim::Utils::Accessor);

use Scalar::Util qw(weaken);

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
#   2 = update scheduled (timer set to callback update)     x             x        x   
#   3 = server side push & bumpLeft/Right                   x             x
#   4 = server side bumpUp/Down                             x             x 
#   5 = server side showBriefly                             x             x        x
#   6 = clear scrolling (scrollonce and end scrolling mode) x             x        x
#   7 = defered showBriefly (mid client side push/bump)                            x
#
# scrollState: (per screen)
#   0 = no scrolling
#   1 = server side normal scrolling
#   2 = server side ticker mode
#   3 = client-side scrolling

my $log = logger('player.display');

my $initialized;

our $defaultPrefs = {
	'idleBrightness'       => 1,
	'scrollMode'           => 0,
	'scrollPause'          => 3.6,
	'scrollPauseDouble'    => 3.6,
	'scrollRate'           => 0.033,
	'scrollRateDouble'     => 0.033,
	'alwaysShowCount'      => 1,
};

$prefs->setValidate('num', qw(scrollRate scrollRateDouble scrollPause scrollPauseDouble));


{
	__PACKAGE__->mk_accessor('rw', 'client'); # Note: Always keep client as the first accessor
	__PACKAGE__->mk_accessor('rw',   qw(updateMode screen2updateOK animateState renderCache currBrightness
										lastVisMode sbCallbackData sbOldDisplay sbName sbDeferred displayStrings notifyLevel hideVisu));
	__PACKAGE__->mk_accessor('arraydefault', 1, qw(scrollState scrollData widthOverride));
}

# create base class - always called via a class which inherits from this one
sub new {
	my $class = shift;
	my $client = shift;

	my $display = $class->SUPER::new;

	# set default state
	$display->client($client);
	weaken( $display->[0] );

	$display->init_accessor(
		updateMode     => 0,      # 0 = normal, 1 = periodic update blocked, 2 = all updates blocked
		screen2updateOK=> undef,
		animateState   => 0,
		renderCache    => {},
		currBrightness => 1,
		lastVisMode    => undef,
		sbCallbackData => undef,
		sbOldDisplay   => undef,
		sbName         => undef,
		displayStrings => {},
		notifyLevel    => 0,      # 0 = notify off, 1 = showbriefly only, 2 = all
		hideVisu       => 0,      # 0 = don't hide, 1 = hide if mode requests, 2 = hide all
		scrollState    => [0,0,0],
		scrollData     => [],
		widthOverride  => [],
	);

	$display->resetDisplay();     # init render cache
	
	return $display;
}

sub init {
	my $display = shift;

	$display->initPrefs();

	$display->displayStrings(Slim::Utils::Strings::clientStrings($display->client));
	
	$initialized = 1;
}

sub initPrefs {
	my $display = shift;

	$prefs->client($display->client)->init($defaultPrefs);
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
	if ($display->notifyLevel == 2) {
		$display->notify('update');
	}
}

# show text briefly and then return to original display
sub showBriefly {
	my $display = shift;
	my $parts   = shift;
	my $args    = shift;
	
	return unless $initialized;

	my $client = $display->client;

	# if called during client animation, then stash params for later when animation completes and return immediately
	if ($display->animateState == 1 || $display->animateState == 7) {
		$display->sbDeferred({ parts => $parts, args => $args});
		$display->animateState(7);
		return;
	}

	if (main::INFOLOG && $log->is_info) {
		my ($line, $subr) = (caller(1))[2,3];
		($line, $subr) = (caller(2))[2,3] if $subr eq 'Slim::Player::Player::showBriefly';
		$log->info(sprintf "caller %s (%d) %s ", $subr, $line, $display->updateMode() == 2 ? '[Blocked]' : '');
	}

	# return if update blocked
	return if ($display->updateMode() == 2);

	my ($duration, $firstLine, $blockUpdate, $scrollToEnd, $brightness, $callback, $callbackargs, $name, $hideVisu);

	if (ref($parts) ne 'HASH') {
		logBacktrace("showBriefly should be passed a display hash");
		return;
	}

	if ( main::DEBUGLOG && $log->is_debug ) {
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
		$hideVisu     = $args->{'hidevisu'} ? 2 : 1 # caller requests all visualisers to be hidden
	} else {
		$duration = $args || 1;
		$firstLine   = shift;
		$blockUpdate = shift;
		$scrollToEnd = shift;
		$brightness   = shift;
		$callback     = shift;
		$callbackargs = shift;
		$name         = shift;
		$hideVisu     = @_ ? 2 : 1;
	}

	# cache info for async showBriefly (web UI)
	$display->renderCache->{showBriefly} = {
		ttl  => time() + 15,
		line => $parts->{line}
	};

	# notify cli/jive of the show briefly message
	if ($display->notifyLevel >= 1) {
		$display->notify('showbriefly', $parts, $duration);
	}

	if ($firstLine && ($display->linesPerScreen() == 1)) {
		$parts->{line}[1] = $parts->{line}[0];
	}

	my $oldDisplay = $display->sbOldDisplay() || $display->curDisplay();
	$display->sbOldDisplay(undef);
	$display->hideVisu($hideVisu);

	$display->update($parts, $scrollToEnd ? 3 : undef);
	
	$display->hideVisu(0);
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

sub getBrightnessOptions {
	my $display = shift;

	my %brightnesses = (
		0 => '0 ('.$display->client->string('BRIGHTNESS_DARK').')',
		1 => '1 ('.$display->client->string('BRIGHTNESS_DIMMEST').')',
		2 => '2',
		3 => '3',
		4 => '4 ('.$display->client->string('BRIGHTNESS_BRIGHTEST').')',
	);

	if (!defined $display) {

		return \%brightnesses;
	}

	if (defined $display->maxBrightness) {
	
		my $maxBrightness = $display->maxBrightness;

		$brightnesses{4} = 4;

		my @brightnessMap = $display->brightnessMap();
		
		# for large values at the end of the brightnessMap, we assume these are ambient index values
		if ($brightnessMap[$maxBrightness] > 255 ) {

			for my $brightness (4 .. $maxBrightness) {
				if ($brightnessMap[$brightness] > 255 ) {
		
#					$brightnesses{$brightness} = $display->client->string('BRIGHTNESS_AMBIENT').' ('.sprintf("%4X",$brightnessMap[$brightness]).')';
					$brightnesses{$brightness} = $display->client->string('BRIGHTNESS_AMBIENT');
					$maxBrightness--;
				}
			}
		}
		
		
		$brightnesses{$maxBrightness} = sprintf('%s (%s)',
			$maxBrightness, $display->client->string('BRIGHTNESS_BRIGHTEST')
		);

	}

	return \%brightnesses;
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
	my $client = $display->client || return;
	my $linefunc = $client->lines;
	my $parts;

	if (defined $linefunc) {
		$parts = eval { &$linefunc($client, @_) };

		if ($@) {
			logError("bad lines function: $@");
		}
	}

	if (main::INFOLOG && $log->is_info) {

		my $source = main::DEBUGLOG ? Slim::Utils::PerlRunTime::realNameForCodeRef($linefunc) : 'unk';
		my ($line, $sub, @subs);
		my $frame = 1;

		do {
			($line, $sub) = (caller($frame++))[2,3];
			push @subs, $sub;
		} while ($sub && $sub =~ /Slim::Display|Slim::Player::Player::update|Slim::Player::Player::push/);

		main::INFOLOG && $log->info(sprintf "lines $source [%s($line)]", join(", ", @subs));
		main::DEBUGLOG && $log->is_debug && $log->debug( Data::Dump::dump($parts) );
	}

	return $parts;
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
	my $cprefs = $prefs->client($client);

	my $ticker = ($screen->{scroll} == 2);

	my $refresh = $cprefs->get($display->linesPerScreen() == 1 ? 'scrollRateDouble': 'scrollRate'    );
	my $pause   = $cprefs->get($display->linesPerScreen() == 1 ? 'scrollPauseDouble': 'scrollPause'  );
	my $pixels  = $cprefs->get($display->linesPerScreen() == 1 ? 'scrollPixelsDouble': 'scrollPixels');

	my $now = Time::HiRes::time();
	my $start = $now + ($ticker ? 0 : (($pause > 0.5) ? $pause : 0.5));
	
	# Adjust scrolling params for ticker mode, we don't want the server scrolling at 30fps
	if ($ticker) {
		$refresh = 0.15;
		$pixels = 7;
	}

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
		'inhibitsaver'  => $ticker ? 0 : 1,
	};

	if (defined($screen->{bitsref})) {
		# graphics display
		$scroll->{shift} = $pixels * $display->bytesPerColumn() * $screen->{scrolldir};
		$scroll->{scrollHeader} = $display->scrollHeader($screenNo);
		$scroll->{scrollFrameSize} = length($display->scrollHeader) + $display->screenBytes($screenNo);
		$scroll->{bitsref} = $screen->{bitsref};
		if (!$ticker) {
			$scroll->{scrollbitsref} = $screen->{scrollbitsref};
		} else {
			my $padbits = chr(0) x $screen->{overlaystart}[$screen->{scrollline}];
			my $tickerbits;
			if ($scroll->{dir} == 1) {
				$tickerbits = $padbits . ${$screen->{scrollbitsref}};
				$scroll->{scrollend} += $screen->{overlaystart}[$screen->{scrollline}];
			} else {
				$tickerbits = ${$screen->{scrollbitsref}} . $padbits;
				$scroll->{scrollend} -= $screen->{overlaystart}[$screen->{scrollline}];
			}
			$scroll->{scrollbitsref} = \$tickerbits;
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
	
	if (!$ticker && $client->hasScrolling) {
		# Start client-side scrolling
		$display->scrollState($screenNo, 3);
		
		my $scrollbits = ${$scroll->{scrollbitsref}};
		my $length = length $scrollbits;
		my $offset = 0;
		
		# Don't exceed max width the firmware can handle (10 screen widths)
		my $maxWidth = $display->screenBytes($screenNo) * 10;
		if ( $length > $maxWidth ) {
			substr $scrollbits, $maxWidth, $length - $maxWidth, '';
			$scroll->{scrollend} = $maxWidth - $display->screenBytes($screenNo);
			$length = length $scrollbits;
		}
		
		# First send the scrollable data frame
		# Note: length of $data header must be even!
		my $header = pack 'ccNNnnn',
			$screenNo,
			($scroll->{dir} == 1 ? 1 : 2),
			$pause * 1000,
			$refresh * 1000,
			$pixels,
			$scroll->{scrollonce},    # repeat flag
			$scroll->{scrollend} / 4; # width of scroll area in pixels
		
		while ($length > 0) {
			if ( $length > 1280 ) { # split up into normal max grf size
				$length = 1280;
			}
			
			my $data = $header . pack('n', $offset) . substr( $scrollbits, 0, $length, '' );
			
			$client->sendFrame( grfs => \$data );
			$offset += $length;			
			$length = length $scrollbits;
		}
		
		# Next send the background frame, display will be updated after it is received
		# and scrolling will begin.
		# Note: also must have an even length
		my $data2 = pack 'nn',
			$screenNo,
			$screen->{overlaystart}[$screen->{scrollline}] / 4; # width of scrollable area
		
		$data2 .= ${$scroll->{bitsref}};
		$client->sendFrame( grfg => \$data2 );
	}
	else {
		# server-side scrolling
		$display->scrollUpdate($scroll);
	}
}

# stop server side scrolling
sub scrollStop {
	my $display = shift;
	my $screenNo = shift;
	my $scroll = $display->scrollData($screenNo) || return;

	delete $scroll->{timer};

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

	# If we're doing client-side scrolling, send a new background frame
	if ($display->scrollState($screenNo) == 3) {
		my $data = pack 'nn',
			$screenNo,
			$scroll->{overlaystart} / 4; # width of scrollable area

		$data .= ${$scroll->{bitsref}};
		$display->client->sendFrame( grfg => \$data );
	}
	else {
		# force update of screen for if paused, otherwise rely on scrolling to update
		if ($scroll->{paused}) {
			$display->scrollUpdateDisplay($scroll);
		}
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

	my $todisplay = $scroll->{dir} == 1 ? $scroll->{scrollend} - $scroll->{offset} : $scroll->{offset} + $scroll->{overlaystart};
	my $completeTime = $todisplay / (abs($scroll->{shift}) / $scroll->{refreshInt});

	my $notdisplayed = $scroll->{dir} == 1 ? $todisplay - $scroll->{overlaystart} : $scroll->{offset};
	my $queueTime = ($notdisplayed > 0) ? $notdisplayed / (abs($scroll->{shift}) / $scroll->{refreshInt}) : 0;

	return ($completeTime, $queueTime);
}

# update scrolling screen during server side scrolling
sub scrollUpdate {
	my $display = shift;
	my $scroll = shift;

	# update display
	$display->scrollUpdateDisplay($scroll);
	
	# We use a direct EV timer here because this is a high-frequency repeating
	# timer, and we can take advantage of EV's built-in repeating timer mode
	# which isn't supported via the Slim::Utils::Timers API
	my $timer = $scroll->{timer};
	if ( !$timer ) {
		$timer = $scroll->{timer} = EV::timer_ns(
			0,
			0,
			sub { scrollUpdate($display, $scroll) },
		);
		# Make it a high priority timer
		$timer->priority(2);
	}

	my $timenow = Time::HiRes::time();

	if ($timenow < $scroll->{pauseUntil}) {
		# called during pause phase - don't scroll
		$scroll->{paused} = 1;
		$scroll->{refreshTime} = $scroll->{pauseUntil};
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
					$scroll->{inhibitsaver} = 0;
					$timer->stop;
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
				$scroll->{inhibitsaver} = 0;
			} else {
				$scroll->{offset} = $scroll->{scrollstart};
				$scroll->{inhibitsaver} = 0;
			}
		}
	}
	
	$timer->set( 0, $scroll->{refreshTime} - $timenow );
	$timer->again;
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

# called by Screensaver to check whether we should change state into screensaver mode
sub inhibitSaver {
	my $display = shift;

	# don't switch to screensaver if blocked, performing animation or on first scroll
	return
		$display->updateMode() == 2 ||
		$display->animateState()    ||
		($display->scrollState(1) == 1 && $display->scrollData(1)->{inhibitsaver});
}

# periodic screen refresh for players requiring it (SB1 and Slimp3)
sub periodicScreenRefresh {
	my $display = shift;

	unless ($display->updateMode > 0  || 
			$display->scrollState == 2 ||
			$display->animateState > 0 && $display->animateState <= 4 ||
			$display->client->modeParam('modeUpdateInterval') ) {

		$display->update($display->renderCache);
	}

	Slim::Utils::Timers::setTimer($display, Time::HiRes::time() + 1, \&periodicScreenRefresh);
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

# depreciated
sub parseLines {}
sub renderOverlay {}


sub forgetDisplay {
	my $display = shift;
	Slim::Utils::Timers::forgetTimer($display);
}

sub string {
	my $display = shift;
	
	my $strings = $display->displayStrings;
	my $name = uc(shift);
	
	# Check language override
	if ( $display->client ) {
		if ( my $lang = $display->client->languageOverride ) {
			$strings = Slim::Utils::Strings::loadAdditional( $lang );
		}
	}		
	
	if ( @_ ) {
		return sprintf( $strings->{$name} || ( logBacktrace("missing string $name") && $name ), @_ );
	}
	
	return $strings->{$name} || ( logBacktrace("missing string $name") && $name );
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
	my $duration= shift;

	# send a notification for this display update to 'displaystatus' queries
	Slim::Control::Request->new($display->client->id, ['displaynotify', $type, $info, $duration])->notify('displaystatus');
}

=head1 SEE ALSO

=cut

1;
