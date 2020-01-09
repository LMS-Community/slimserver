package Slim::Display::SqueezeboxG;

# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.


=head1 NAME

Slim::Display::SqueezeboxG

=head1 DESCRIPTION

L<Slim::Display::SqueezeboxG>
 Display class for Squeezebox 1 Graphics class display
  - 280 x 16 display
  - no client side animations

=cut

use strict;

use base qw(Slim::Display::Graphics);

use Slim::Utils::Prefs;

my $prefs = preferences('server');

# constants
my $display_maxLine = 1; # render up to 2 lines [0..$display_maxLine]

my $GRAPHICS_FRAMEBUF_LIVE = (1 * 280 * 2);

our $defaultPrefs = {
	'playingDisplayMode'  => 0,
	'playingDisplayModes' => [0..5],
	'scrollRate'          => 0.15,
	'scrollRateDouble'    => 0.1,
	'scrollPixels'		  => 7,
	'scrollPixelsDouble'  => 7,
};

our $defaultFontPrefs = {
	'activeFont'          => [qw(small medium large huge)],
	'activeFont_curr'     => 1,
	'idleFont'            => [qw(small medium large huge)],
	'idleFont_curr'       => 1,
};

$prefs->setChange( sub { $_[2]->textSize($_[1]) if $_[2]->power(); }, 'activeFont_curr');
$prefs->setChange( sub { $_[2]->textSize($_[1]) unless $_[2]->power(); }, 'idleFont_curr');


# Display Modes

my @modes = (
	# mode 0
	{ desc => ['BLANK'],
	  bar => 0, secs => 0,  width => 280, },
	# mode 1
	{ desc => ['ELAPSED'],
	  bar => 0, secs => 1,  width => 280, },
	# mode 2
	{ desc => ['REMAINING'],
	  bar => 0, secs => -1, width => 280, },
	# mode 3
	{ desc => ['PROGRESS_BAR'],
	  bar => 1, secs => 0,  width => 280, },
	# mode 4
	{ desc => ['ELAPSED', 'AND', 'PROGRESS_BAR'],
	  bar => 1, secs => 1,  width => 280, },
	# mode 5
	{ desc => ['REMAINING', 'AND', 'PROGRESS_BAR'],
	  bar => 1, secs => -1, width => 280, },
	# mode 6
	{ desc => ['SETUP_SHOWBUFFERFULLNESS'],
	  bar => 1, secs => 0,  width => 280, fullness => 1, }
);

my $nmodes = $#modes;

sub init {
	my $display = shift;
	
	# load fonts for this display if not already loaded and remember to load at startup in future
	if (!$prefs->get('loadFontsSqueezeboxG')) {
		$prefs->set('loadFontsSqueezeboxG', 1);
		Slim::Display::Lib::Fonts::loadFonts(1);
	}

	$display->SUPER::init();

	$display->validateFonts($defaultFontPrefs);
}

sub initPrefs {
	my $display = shift;
	
	$prefs->client($display->client)->init($defaultPrefs);
	$prefs->client($display->client)->init($defaultFontPrefs);

	$display->SUPER::initPrefs();
}

sub resetDisplay {
	my $display = shift;

	my $cache = $display->renderCache();
	$cache->{'defaultfont'} = undef;
	$cache->{'screens'} = 1;
	$cache->{'maxLine'} = $display_maxLine;
	$cache->{'screen1'} = { 'ssize' => 0, 'fonts' => {} };

	$display->killAnimation();
}	

sub bytesPerColumn {
	return 2;
}

sub displayHeight {
	return 16;
}

sub displayWidth {
	return 280;
}

sub vfdmodel {
	return 'graphic-280x16';
}

sub brightnessMap {
	return (0, 1, 4, 16, 30);
}

sub graphicCommand {
	return 'grfd';
}

sub updateScreen {
	my $display = shift;
	my $screen = shift;
	$display->drawFrameBuf($screen->{bitsref});
}

sub drawFrameBuf {
	my $display = shift;
	my $framebufref = shift;
	my $parts = shift;

	my $client = $display->client;

	if ($client->opened()) {

		my $framebuf = pack('n', $GRAPHICS_FRAMEBUF_LIVE) . $$framebufref;
		my $len = length($framebuf);

		if ($len != $display->screenBytes() + 2) {
			$framebuf = substr($framebuf .  chr(0) x $display->screenBytes(), 0, $display->screenBytes() + 2);
		}

		$client->sendFrame('grfd', \$framebuf);
	}
}	

sub modes {
	return \@modes;
}

sub nmodes {
	return $nmodes;
}

sub scrollHeader {
	return pack('n', $GRAPHICS_FRAMEBUF_LIVE);
}

# Server based push/bump animations

sub pushLeft {
	my $display = shift;
	my $start = shift || $display->renderCache();
	my $end = shift || $display->curLines({ trans => 'pushLeft' });

	my $startbits = $display->render($start)->{screen1}->{bitsref};
	my $endbits = $display->render($end)->{screen1}->{bitsref};
	
	my $allbits = $$startbits . $$endbits;

	$display->killAnimation();
	$display->pushUpdate([\$allbits, 0, $display->screenBytes() / 8, $display->screenBytes(),  0.025]);

	if ($display->notifyLevel == 2) {
		$display->notify('update');
	}
}

sub pushRight {
	my $display = shift;
	my $start = shift || $display->renderCache();
	my $end = shift || $display->curLines({ trans => 'pushRight' });

	my $startbits = $display->render($start)->{screen1}->{bitsref};
	my $endbits = $display->render($end)->{screen1}->{bitsref};
	
	my $allbits = $$endbits . $$startbits;
	
	$display->killAnimation();
	$display->pushUpdate([\$allbits, $display->screenBytes(), 0 - $display->screenBytes() / 8, 0, 0.025]);

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

sub bumpLeft {
	my $display = shift;

	my $startbits = $display->render($display->renderCache())->{screen1}->{bitsref};
	$startbits =  (chr(0) x 16) . $$startbits;
	$display->killAnimation();
	$display->pushUpdate([\$startbits, 0, 8, 16, 0.125]);	
}

sub bumpRight {
	my $display = shift;

	my $startbits = $display->render($display->renderCache())->{screen1}->{bitsref};
	$startbits = $$startbits .  (chr(0) x 16);
	$display->killAnimation();
	$display->pushUpdate([\$startbits, 16, -8, 0, 0.125]);	
}

sub pushUpdate {
	my $display = shift;
	my $params = shift;
	my ($allbits, $offset, $delta, $end, $deltatime) = @$params;
	
	$offset += $delta;
	
	my $len = length($$allbits);
	my $screen;

	$screen = substr($$allbits, $offset, $display->screenBytes());
	
	$display->drawFrameBuf(\$screen);
	if ($offset != $end) {
		$display->updateMode(1);
		$display->animateState(3);
		Slim::Utils::Timers::setHighTimer($display,Time::HiRes::time() + $deltatime,\&pushUpdate,[$allbits,$offset,$delta,$end,$deltatime]);
	} else {
		$display->simulateANIC;
	}
}

sub bumpUp {
	my $display = shift;

	my $startbits = $display->render($display->renderCache())->{screen1}->{bitsref};
	$startbits = substr((chr(0) . $$startbits) & ((chr(0) . chr(255)) x ($display->screenBytes() / 2)), 0, $display->screenBytes());

	$display->killAnimation();
	
	$display->drawFrameBuf(\$startbits);

	$display->updateMode(1);
	$display->animateState(4);
	Slim::Utils::Timers::setHighTimer($display,Time::HiRes::time() + 0.125, \&endAnimation);
}

sub bumpDown {
	my $display = shift;

	my $startbits = $display->render($display->renderCache())->{screen1}->{bitsref};
	$startbits = substr(($$startbits . chr(0)) & ((chr(0) . chr(255)) x ($display->screenBytes() / 2)), 1, $display->screenBytes());
	
	$display->killAnimation();

	$display->drawFrameBuf(\$startbits);

	$display->updateMode(1);
	$display->animateState(4);
	Slim::Utils::Timers::setHighTimer($display,Time::HiRes::time() + 0.125, \&endAnimation);
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
	
	$display->scrollStop() if (($display->scrollState() > 0) && !$exceptScroll);
	$display->animateState(0);
	$display->updateMode(0);
	$display->endShowBriefly if ($animate == 5);
}

sub string {
	my $display = shift;
	return Slim::Utils::Unicode::utf8toLatin1($display->SUPER::string(@_));
}

sub doubleString {
	my $display = shift;
	return Slim::Utils::Unicode::utf8toLatin1($display->SUPER::doubleString(@_));
}


=head1 SEE ALSO

L<Slim::Display::Graphics>

=cut

1;


