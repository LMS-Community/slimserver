package Slim::Display::Boom;

# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.


=head1 NAME

Slim::Display::Squeezebox2

=head1 DESCRIPTION

L<Slim::Display::Boom>
 Display class for Boom class display
  - 160 x 32 pixel display
  - client side animations

=cut

use strict;

use base qw(Slim::Display::Squeezebox2);

use Slim::Utils::Prefs;

my $prefs = preferences('server');

# Mode definitions - including visualizer

# Parameters for the vumeter:
#   0 - Channels: stereo == 0, mono == 1
#   1 - Style: digital == 0, analog == 1
# Left channel parameters:
#   2 - Position in pixels
#   3 - Width in pixels
# Right channel parameters (not required for mono):
#   4-5 - same as left channel parameters

# Parameters for the spectrum analyzer:
#   0 - Channels: stereo == 0, mono == 1
#   1 - Bandwidth: 0..22050Hz == 0, 0..11025Hz == 1
#   2 - Preemphasis in dB per KHz
# Left channel parameters:
#   3 - Position in pixels
#   4 - Width in pixels
#   5 - orientation: left to right == 0, right to left == 1
#   6 - Bar width in pixels
#   7 - Bar spacing in pixels
#   8 - Clipping: show all subbands == 0, clip higher subbands == 1
#   9 - Bar intensity (greyscale): 1-3
#   10 - Bar cap intensity (greyscale): 1-3
# Right channel parameters (not required for mono):
#   11-18 - same as left channel parameters

my $VISUALIZER_NONE = 0;
my $VISUALIZER_VUMETER = 1;
my $VISUALIZER_SPECTRUM_ANALYZER = 2;
my $VISUALIZER_WAVEFORM = 3;

my @modes = (
	# mode 0
	{ desc => ['BLANK'],
	  bar => 0, secs => 0,  width => 160, 
	  params => [$VISUALIZER_NONE] },
	# mode 1
	{ desc => ['PROGRESS_BAR'],
	  bar => 1, secs => 0,  width => 160,
	  params => [$VISUALIZER_NONE] },
	# mode 2
	{ desc => ['ELAPSED'],
	  bar => 0, secs => 1,  width => 160,
	  params => [$VISUALIZER_NONE] },
	# mode 3
	{ desc => ['REMAINING'],
	  bar => 0, secs => -1, width => 160,
	  params => [$VISUALIZER_NONE] },
	# mode 4
	{ desc => ['VISUALIZER_VUMETER_SMALL'],
	  bar => 0, secs => 0,  width => 145,
	  params => [$VISUALIZER_VUMETER, 0, 0, 146, 6, 154, 6] },
	# mode 5
	{ desc => ['VISUALIZER_SPECTRUM_ANALYZER_SMALL'],
	  bar => 0, secs => 0,  width => 145,
	  params => [$VISUALIZER_SPECTRUM_ANALYZER, 1, 1, 0x10000, 146, 16, 0, 2, 0, 0, 1, 3] },
	# mode 6
	{ desc => ['VISUALIZER_SPECTRUM_ANALYZER'],
	  bar => 0, secs => 0,  width => 160,
	  params => [$VISUALIZER_SPECTRUM_ANALYZER, 0, 0, 0x10000, 0, 80, 0, 3, 1, 1, 1, 1, 81, 80, 1, 3, 1, 1, 1, 1] },
	# mode 7
	{ desc => ['VISUALIZER_SPECTRUM_ANALYZER', 'AND', 'PROGRESS_BAR'],
	  bar => 1, secs => 0,  width => 160,
	  params => [$VISUALIZER_SPECTRUM_ANALYZER, 0, 0, 0x10000, 0, 80, 0, 3, 1, 1, 1, 1, 81, 80, 1, 3, 1, 1, 1, 1] },
	# mode 8
	{ desc => ['VISUALIZER_SPECTRUM_ANALYZER', 'AND', 'ELAPSED'],
	  bar => 0, secs => 1,  width => 160,
	  params => [$VISUALIZER_SPECTRUM_ANALYZER, 0, 0, 0x10000, 0, 80, 0, 3, 1, 1, 1, 1, 81, 80, 1, 3, 1, 1, 1, 1] },
	# mode 9
	{ desc => ['VISUALIZER_SPECTRUM_ANALYZER', 'AND', 'REMAINING'],
	  bar => 0, secs => -1, width => 160,
	  params => [$VISUALIZER_SPECTRUM_ANALYZER, 0, 0, 0x10000, 0, 80, 0, 3, 1, 1, 1, 1, 81, 80, 1, 3, 1, 1, 1, 1] }, 
	# mode 10
	{ desc => ['CLOCK'],
	  bar => 0, secs => 0, width => 160, clock => 1,
	  params => [$VISUALIZER_NONE] },
	# mode 11	  
	{ desc => ['SETUP_SHOWBUFFERFULLNESS'],
	  bar => 0, secs => 0,  width => 160, fullness => 1,
	  params => [$VISUALIZER_NONE],
	},
);

our $defaultPrefs = {
	'playingDisplayMode'  => 1,
	'playingDisplayModes' => [0..10],
	'idleBrightness'       => 6,
	'powerOnBrightness'    => 6,
	'powerOffBrightness'   => 6,
	'scrollPause'          => 1.5,
	'scrollPauseDouble'    => 1.5,
	'alwaysShowCount'      => 0,
};

our $defaultFontPrefs = {
	'activeFont'          => [qw(light_n standard_n full_n)],
	'activeFont_curr'     => 1,
	'idleFont'            => [qw(light_n standard_n full_n)],
	'idleFont_curr'       => 2,
};

sub init {
	my $display = shift;

	# load fonts for this display if not already loaded and remember to load at startup in future
	if (!$prefs->get('loadFontsSqueezebox2')) {
		$prefs->set('loadFontsSqueezebox2', 1);
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

sub modes {
	return \@modes;
}

sub nmodes {
	return $#modes;
}

sub vfdmodel {
	return 'graphic-160x32';
}

sub string {
	my $display = shift;
	
	my $name = uc(shift);
	
	if (Slim::Utils::Strings::stringExists($name."_ABBR")) {
		return $display->SUPER::string($name."_ABBR",@_);
	} else {
		return $display->SUPER::string($name,@_);
	}
}

sub brightnessMap {
	my $display = shift;

	my $sens = $prefs->client($display->client)->get( "sensAutoBrightness");	# 1 - 20
	if( $sens < 1) { $sens = 1; }
	if( $sens > 20) { $sens = 20; }
	my $divisor = 21 - $sens;

	my $offset = $prefs->client($display->client)->get( "minAutoBrightness");	# 1 - 7
	if( $offset < 1) { $offset = 1; }
	if( $offset > 7) { $offset = 7; }

	return (0, 1, 2, 3, 4, 5, ( $divisor * 256) + $offset);	# Formula: vfd brightness = lightsensor value / upper byte + lower byte
}

=head1 SEE ALSO

L<Slim::Display::Graphics>

=cut

1;

