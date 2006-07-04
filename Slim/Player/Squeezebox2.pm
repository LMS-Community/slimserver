package Slim::Player::Squeezebox2;

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
use base qw(Slim::Player::SqueezeboxG);

use File::Spec::Functions qw(:ALL);
use IO::Socket;
use MIME::Base64;

use Slim::Formats::Playlists;
use Slim::Player::Player;
use Slim::Player::ProtocolHandlers;
use Slim::Player::Protocols::HTTP;
use Slim::Player::Protocols::MMS;
use Slim::Utils::Misc;
use Slim::Utils::Unicode;

our $defaultPrefs = {
	'activeFont'			=> [qw(light standard full)],
	'activeFont_curr'		=> 1,
	'idleFont'				=> [qw(light standard full)],
	'idleFont_curr'			=> 1,
	'idleBrightness'		=> 2,
	'transitionType'		=> 0,
	'transitionDuration'	=> 0,
	'replayGainMode'		=> '3',
	'playingDisplayMode'	=> 5,
	'playingDisplayModes'	=> [0..11]
};

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


# sb2 display modes:
#    0 - just text
#    1 - text and progress bar and time
#    2 - text + vu on side
#    3 - text + progress bar + vu
#    4 - text + spectrum analyzer
#    5 - text + full screen spectrum analyser
#    6 - text + indicator

my $VISUALIZER_NONE = 0;
my $VISUALIZER_VUMETER = 1;
my $VISUALIZER_SPECTRUM_ANALYZER = 2;
my $VISUALIZER_WAVEFORM = 3;

my @modes = ( 	
	{ bar => 0, 
	  secs => 0, 
	  width => 320, 
	  params => [$VISUALIZER_NONE] } , 
	{ bar => 1, 
	  secs => 1,
	  width => 320, 
	  params => [$VISUALIZER_NONE] } , 
	{ bar => 1, 
	  secs => -1, 
	  width => 320, 
	  params => [$VISUALIZER_NONE] } , 
	  
	{ bar => 0, 
	  secs => 0, 
	  width => 278, 
	  params => [$VISUALIZER_VUMETER, 0, 0, 280, 18, 302, 18] } , 
	{ bar => 1, 
	  secs => 1,
	  width => 278, 
	  params => [$VISUALIZER_VUMETER, 0, 0, 280, 18, 302, 18] } , 
	{ bar => 1, 
	  secs => -1, 
	  width => 278, 
	  params => [$VISUALIZER_VUMETER, 0, 0, 280, 18, 302, 18] } , 
	  
	{ bar => 0, 
	  secs => 0, 
	  width => 278, 
	  params => [$VISUALIZER_SPECTRUM_ANALYZER, 1, 1, 0x10000, 280, 40, 0, 4, 1, 0, 1, 3] } , 
	{ bar => 1, 
	  secs => 1,
	  width => 278, 
	  params => [$VISUALIZER_SPECTRUM_ANALYZER, 1, 1, 0x10000, 280, 40, 0, 4, 1, 0, 1, 3] } , 
	{ bar => 1, 
	  secs => -1, 
	  width => 278, 
	  params => [$VISUALIZER_SPECTRUM_ANALYZER, 1, 1, 0x10000, 280, 40, 0, 4, 1, 0, 1, 3] } , 
	  
	{ bar => 0, 
	  secs => 0, 
	  width => 320, 
	  params => [$VISUALIZER_SPECTRUM_ANALYZER, 0, 0, 0x10000, 0, 160, 0, 4, 1, 1, 1, 1, 160, 160, 1, 4, 1, 1, 1, 1] } , 
	{ bar => 1, 
	  secs => 1,
	  width => 320, 
	  params => [$VISUALIZER_SPECTRUM_ANALYZER, 0, 0, 0x10000, 0, 160, 0, 4, 1, 1, 1, 1, 160, 160, 1, 4, 1, 1, 1, 1] } , 
	{ bar => 1, 
	  secs => -1, 
	  width => 320, 
	  params => [$VISUALIZER_SPECTRUM_ANALYZER, 0, 0, 0x10000, 0, 160, 0, 4, 1, 1, 1, 1, 160, 160, 1, 4, 1, 1, 1, 1] } , 
	  
	{ bar => 1, 
	  secs => 0, 
	  width => 320, 
	  params => [$VISUALIZER_NONE], fullness => 1 }
);

sub nowPlayingModes {
	return 13;
	
	# Optimization: This used to be:
	# return scalar(keys %{$client->playingModeOptions()});
	# which made tons of useless string calls!
}

my @WMA_FILE_PROPERTIES_OBJECT_GUID = (0x8c, 0xab, 0xdc, 0xa1, 0xa9, 0x47, 0x11, 0xcf, 0x8e, 0xe4, 0x00, 0xc0, 0x0c, 0x20, 0x53, 0x65);
my @WMA_CONTENT_DESCRIPTION_OBJECT_GUID = (0x75, 0xB2, 0x26, 0x33, 0x66, 0x8E, 0x11, 0xCF, 0xA6, 0xD9, 0x00, 0xAA, 0x00, 0x62, 0xCE, 0x6C);
my @WMA_EXTENDED_CONTENT_DESCRIPTION_OBJECT_GUID = (0xd2, 0xd0, 0xa4, 0x40, 0xe3, 0x07, 0x11, 0xd2, 0x97, 0xf0, 0x00, 0xa0, 0xc9, 0x5e, 0xa8, 0x50);

sub playingModeOptions { 
	my $client = shift;
	
	# NOTE: if you add an option here, update the count in nowPlayingModes above
	
	my %options = (
		'0' => $client->string('BLANK'),
		'1' => $client->string('ELAPSED'),
		'2' => $client->string('REMAINING') ,
		'3' => $client->string('VISUALIZER_VUMETER_SMALL'),
		'4' => $client->string('VISUALIZER_VUMETER_SMALL'). ' ' . $client->string('AND') . ' ' . $client->string('ELAPSED'),
		'5' => $client->string('VISUALIZER_VUMETER_SMALL'). ' ' . $client->string('AND') . ' ' . $client->string('REMAINING'),
		'6' => $client->string('VISUALIZER_SPECTRUM_ANALYZER_SMALL'),
		'7' => $client->string('VISUALIZER_SPECTRUM_ANALYZER_SMALL'). ' ' . $client->string('AND') . ' ' . $client->string('ELAPSED'),
		'8' => $client->string('VISUALIZER_SPECTRUM_ANALYZER_SMALL'). ' ' . $client->string('AND') . ' ' . $client->string('REMAINING'),
		'9' => $client->string('VISUALIZER_SPECTRUM_ANALYZER'),
		'10' => $client->string('VISUALIZER_SPECTRUM_ANALYZER'). ' ' . $client->string('AND') . ' ' . $client->string('ELAPSED'),
		'11' => $client->string('VISUALIZER_SPECTRUM_ANALYZER'). ' ' . $client->string('AND') . ' ' . $client->string('REMAINING'),
		'12' => $client->string('SETUP_SHOWBUFFERFULLNESS'),
	);
	
	return \%options;
}

sub new {
	my $class = shift;

	my $client = $class->SUPER::new(@_);

	bless $client, $class;

	return $client;
}

sub vfdmodel {
	return 'graphic-320x32';
}

sub init {
	my $client = shift;
	# make sure any preferences unique to this client may not have set are set to the default
	Slim::Utils::Prefs::initClientPrefs($client,$defaultPrefs);
	$client->SUPER::init();
}

sub showVisualizer {
	my $client = shift;
	
	# show the always-on visualizer while browsing or when playing.
	return (Slim::Player::Source::playmode($client) eq 'play') || (Slim::Buttons::Playlist::showingNowPlaying($client));
}

sub displayWidth {
	my $client = shift;
	
	# if we're showing the always-on visualizer & the current buttonmode 
	# hasn't overridden, then use the playing display mode to index
	# into the display width, otherwise, it's fullscreen.
	my $mode = ($client->showVisualizer() && !defined($client->modeParam('visu'))) ? ${[$client->prefGetArray('playingDisplayModes')]}[$client->prefGet("playingDisplayMode")] : 0;
	return $modes[$mode || 0]{width};
}

sub bytesPerColumn {
	return 4;
}

sub displayHeight {
	return 32;
}

sub maxBass { 50 };
sub minBass { 50 };
sub maxTreble { 50 };
sub minTreble { 50 };
sub maxPitch { 100 };
sub minPitch { 100 };

sub model {
	return 'squeezebox2';
};

# in order of preference based on whether we're connected via wired or wireless...
sub formats {
	my $client = shift;
	
	return qw(wma flc aif wav mp3);
}

# The original Squeezebox2 firmware supported a fairly narrow volume range
# below unity gain - 129 levels on a linear scale represented by a 1.7
# fixed point number (no sign, 1 integer, 7 fractional bits).
# From FW 22 onwards, volume is sent as a 16.16 value (no sign, 16 integer,
# 16 fractional bits), significantly increasing our fractional range.
# Rather than test for the firmware level, we send both values in the 
# volume message.

# We thought about sending a dB scale volume to the client, but decided 
# against it. Sending a fixed point multiplier allows us to change 
# the mapping of UI volume settings to gain as we want, without being
# constrained by any scale other than that of the fixed point range allowed
# by the client.

# Old style volume:
# we only have 129 levels to work with now, and within 100 range,
# that's pretty tight.
# this table is optimized for 40 steps (like we have in the current player UI.
my @volume_map = ( 
0, 1, 1, 1, 2, 2, 2, 3,  3,  4, 
5, 5, 6, 6, 7, 8, 9, 9, 10, 11, 
12, 13, 14, 15, 16, 16, 17, 18, 19, 20, 
22, 23, 24, 25, 26, 27, 28, 29, 30, 32, 
33, 34, 35, 37, 38, 39, 40, 42, 43, 44, 
46, 47, 48, 50, 51, 53, 54, 56, 57, 59, 
60, 61, 63, 65, 66, 68, 69, 71, 72, 74, 
75, 77, 79, 80, 82, 84, 85, 87, 89, 90, 
92, 94, 96, 97, 99, 101, 103, 104, 106, 108, 110, 
112, 113, 115, 117, 119, 121, 123, 125, 127, 128
 );

sub dBToFixed {
	my $db = shift;

	# Map a floating point dB value to a 16.16 fixed point value to
	# send as a new style volume to SB2 (FW 22+).
	my $floatmult = 10 ** ($db/20);
	
	# use 8 bits of accuracy for dB values greater than -30dB to avoid rounding errors
	if ($db >= -30 && $db <= 0) {
		return int($floatmult * (1 << 8) + 0.5) * (1 << 8);
	}
	else {
		return int(($floatmult * (1 << 16)) + 0.5);
	}
}

sub volume {
	my $client = shift;
	my $newvolume = shift;

	my $volume = $client->Slim::Player::Client::volume($newvolume, @_);
	my $preamp = 255 - int(2 * $client->prefGet("preampVolumeControl"));

	if (defined($newvolume)) {
		# Old style volume:
		my $oldGain = $volume_map[int($volume)];
		
		my $newGain;
		if ($volume == 0) {
			$newGain = 0;
		}
		else {
			# With new style volume, let's try -49.5dB as the lowest
			# value.
			my $db = ($volume - 100)/2;	
			$newGain = dBToFixed($db);
		}

		my $data = pack('NNCCNN', $oldGain, $oldGain, $client->prefGet("digitalVolumeControl"), $preamp, $newGain, $newGain);
		$client->sendFrame('audg', \$data);
	}
	return $volume;
}

sub drawFrameBuf {
	my $client = shift;
	my $framebufref = shift;
	my $parts = shift;
	my $transition = shift || 'c';
	my $param = shift || 0;

	if ($client->opened()) {
		# for now, we'll send a visu packet with each screen update.	
		$client->visualizer();

		my $framebuf = pack('n', 0) .   # offset of zero
						   $transition . # transition
						   pack('c', $param) . # param byte
						   substr($$framebufref, 0, $client->displayWidth() * $client->bytesPerColumn()); # truncate if necessary
	
		$client->sendFrame('grfe', \$framebuf);
	}
}	


sub periodicScreenRefresh {
    my $client = shift;
    # noop for this player - not required
}    

# update screen - supressing unchanged screens
sub updateScreen {
	my $client = shift;
	my $render = shift;
	if ($render->{changed}) {
	    $client->drawFrameBuf($render->{bitsref});
	} else {
	    # check to see if visualiser has changed even if screen display has not
	    $client->visualizer();
	}
}

# update visualizer and init scrolling
sub scrollInit {
    my $client = shift;
    $client->visualizer();    
    $client->SUPER::scrollInit(@_);
}

# update visualiser and scroll background - suppressing unchanged backgrounds
sub scrollUpdateBackground {
    my $client = shift;
    my $render = shift;
    $client->visualizer();
    $client->SUPER::scrollUpdateBackground($render) if $render->{changed};
}

# preformed frame header for fast scolling - contains header added by sendFrame and drawFrameBuf
sub scrollHeader {
	my $client = shift;
	my $header = 'grfe' . pack('n', 0) . 'c' . pack ('c', 0);

	return pack('n', length($header) + $client->screenBytes ) . $header;
}

# set the visualizer and update the player.  If blank, just update the player with the current mode setting.
sub visualizer {
	my $client = shift;
	my $forceSend = shift || 0;
	
	my $paramsref = $client->modeParam('visu');
	
	if (!$paramsref) {
		my $visu = $client->prefGet('playingDisplayModes',$client->prefGet("playingDisplayMode"));

		$visu = 0 if (!$client->showVisualizer());
		
		if (!defined $visu || $visu < 0) { 
			$visu = 0; 
		}
		my $nmodes = $client->nowPlayingModes();
		if ($visu >= $nmodes) { 
			$visu = $nmodes - 1;
		}
		
		$paramsref = $modes[$visu]{params};
	}
	
	return if (!$forceSend && defined($paramsref) && ($paramsref == $client->lastVisMode())); 

	my @params = @{$paramsref};
	
	my $which = shift @params;
	my $count = scalar(@params);

	my $parambytes = pack "CC", $which, $count;
	for my $param (@params) {
		$parambytes .= pack "N", $param;
	}

	$client->sendFrame('visu', \$parambytes);
	$client->lastVisMode($paramsref);
}

sub pushUp {
	my $client = shift;
	my $end = shift || $client->curLines();

	$client->pushUpDown($end, 'u');
}

sub pushDown {
	my $client = shift;
	my $end = shift || $client->curLines();

	$client->pushUpDown($end, 'd');
}

sub pushUpDown {
	my $client = shift;
	my $end = shift;
	my $dir = shift;
	
	$client->killAnimation();
	$client->animateState(1);
	$client->updateMode(1);
	
	my $render = $client->render($end);

	# start the push animation, passing in the extent of the second line
	$client->drawFrameBuf($render->{bitsref}, undef, $dir, $render->{line2height});
}

# push the old screen off the left side
sub pushLeft {
	my $client = shift;
	my $start = shift;
	my $end = shift || $client->curLines();

	$client->killAnimation();
	$client->animateState(1);
	$client->updateMode(1);
	$client->drawFrameBuf($client->render($end)->{bitsref}, undef, 'r', 0);
}

# push the old screen off the right side
sub pushRight {
	my $client = shift;
	my $start = shift;
	my $end = shift || $client->curLines();

	$client->killAnimation();	
	$client->animateState(1);
	$client->updateMode(1);
	$client->drawFrameBuf($client->render($end)->{bitsref}, undef, 'l', 0);
}

# bump left against the edge
sub bumpLeft {
	my $client = shift;
	my $startbits = $client->render($client->renderCache())->{bitsref};
	
	$client->killAnimation();	
	$client->animateState(1);
	$client->updateMode(1);
	$client->drawFrameBuf($startbits, undef, 'L', 0);
}

# bump right against the edge
sub bumpRight {
	my $client = shift;
	my $startbits = $client->render($client->renderCache())->{bitsref};
	
	$client->killAnimation();	
	$client->animateState(1);
	$client->updateMode(1);
	$client->drawFrameBuf($startbits, undef, 'R', 0);
}

sub bumpDown {
	my $client = shift;
	my $startbits = $client->render($client->renderCache())->{bitsref};
	
	$client->killAnimation();
	$client->animateState(1);
	$client->updateMode(1);
	$client->drawFrameBuf($startbits, undef, 'U', 0);
}

sub bumpUp {
	my $client = shift;
	my $startbits = $client->render($client->renderCache())->{bitsref};

	$client->killAnimation();	
	$client->animateState(1);
	$client->updateMode(1);
	$client->drawFrameBuf($startbits, undef, 'D', 0);
}

my @brightmap = (
	65535,
	0,
	1,
	3,
	4,
);

sub brightness {
	my $client = shift;
	my $delta = shift;
	
	my $brightness = $client->Slim::Player::Player::brightness($delta, 1);
		
	if (defined($delta)) {
		
		my $brightnesscode = pack('n', $brightmap[$brightness]);
		$client->sendFrame('grfb', \$brightnesscode); 
	}
	
	return $brightness;
}

sub maxBrightness {
	return 4;
}

sub upgradeFirmware {
	my $client = shift;

	my $to_version = $client->needsUpgrade();

	if (!$to_version) {
		$to_version = $client->revision;
		$::d_firmware && msg ("upgrading to same rev: $to_version\n");
	}

	my $filename = catdir( Slim::Utils::OSDetect::dirsFor('Firmware'), $client->model . "_$to_version.bin" );

	if (!-f $filename) {
		warn("file does not exist: $filename\n");
		return(0);
	}
	
	$client->execute(["stop"]);

	$::d_firmware && msg("using new update mechanism: $filename\n");

	my $err = $client->upgradeFirmware_SDK5($filename);

	if (defined($err)) {
		msg("upgrade failed: $err");
	} else {
		$client->forgetClient();
	}
}

sub nowPlayingModeLines {
	my ($client, $parts) = @_;
	my $overlay;
	my $fractioncomplete   = 0;
	
	my $mode = $client->prefGet('playingDisplayModes',$client->prefGet("playingDisplayMode"));

	my $songtime = '';
	
	Slim::Buttons::Common::param(
		$client,
		'animateTop',
		(Slim::Player::Source::playmode($client) ne "stop") ? $mode : 0
	);

	unless (defined $mode) {
		$mode = 1;
	};

	my $showBar =  $modes[$mode]{bar};
	my $showTime = $modes[$mode]{secs};
	my $showFullness = $modes[$mode]{fullness};
	
	# check if we don't know how long the track is...
	if (!Slim::Player::Source::playingSongDuration($client)) {
		$showBar = 0;
	}
	
	if ($showFullness) {
		$fractioncomplete = $client->usage();
	} elsif ($showBar) {
		$fractioncomplete = Slim::Player::Source::progress($client);
	}
	
	if ($showFullness) {
		$songtime = ' ' . int($fractioncomplete * 100 + 0.5)."%";
	} elsif ($showTime) { 
		$songtime = ' ' . $client->textSongTime($showTime < 0);
	}

	if ($showTime || $showFullness) {
		$overlay = $songtime;
	}
	
	if ($showBar) {
		# show both the bar and the time
		my $leftLength = $client->measureText($parts->{line1}, 1);
		my $barlen = $client->displayWidth() - $leftLength - $client->measureText($overlay, 1);
		my $bar    = $client->symbols($client->progressBar($barlen, $fractioncomplete));

		$overlay = $bar . $songtime;
	}
	
	$parts->{overlay1} = $overlay if defined($overlay);
	
}

sub maxTransitionDuration {
	return 10;
}

sub reportsTrackStart {
	return 1;
}

sub requestStatus {
	shift->sendFrame('stat');
}

sub stop {
	my $client = shift;
	$client->SUPER::stop(@_);
	# Preemptively set the following state variables
	# to 0, since we rely on them for time display and may
	# have to wait to get a status message with the correct
	# values.
	$client->songElapsedSeconds(0);
	$client->outputBufferFullness(0);
}

sub songElapsedSeconds {
	my $client = shift;

	# Ignore values sent by the client if we're in the stopped
	# state, since they may be out of sync.
	if (defined($_[0]) && 
	    Slim::Player::Source::playmode($client) eq 'stop') {
		$client->SUPER::songElapsedSeconds(0);
	}

	return $client->SUPER::songElapsedSeconds(@_);
}

sub canDirectStream {
	my $client = shift;
	my $url = shift;

	my $handler = Slim::Player::ProtocolHandlers->handlerForURL($url);

	if ($handler && $handler->can("canDirectStream")) {
		return $handler->canDirectStream($client, $url);
	}

	return undef;
}
	
sub directHeaders {
	my $client = shift;
	my $headers = shift;

	$::d_directstream && msg("processing headers for direct streaming:\n$headers");

	my $url = $client->directURL || return;
	
	# We involve the protocol handler in the header parsing process.
	# The current iteration of the firmware only knows about HTTP 
	# headers. Specifically, it returns headers after finding a 
	# CRLF pair in the stream. In the future, we could tell the firmware
	# to return a specific number of bytes or look for a specific 
	# byte sequence and make this less HTTP specific. For now, we only
	# support this type of direct streaming for HTTP-esque protocols.
	my $handler = Slim::Player::ProtocolHandlers->handlerForURL($url);	

	# Trim embedded nulls 
	$headers =~ s/[\0]*$//;

	$headers =~ s/\r/\n/g;
	$headers =~ s/\n\n/\n/g;

	my @headers = split "\n", $headers;

	chomp(@headers);
	
	my $response = shift @headers;
	
	if (!$response || $response !~ / (\d\d\d)/) {
		$::d_directstream && msg("Invalid response code ($response) from remote stream $url\n");
		$client->failedDirectStream();
	} else {
	
		$response = $1;
		
		if (($response < 200) || $response > 399) {
			$::d_directstream && msg("Invalid response code ($response) from remote stream $url\n");
			if ($handler && $handler->can("handleDirectError")) {
				$handler->handleDirectError($client, $url, $response);
			}
			else {
				$client->failedDirectStream();
			}
		} else {
			my $redir = '';
			my $metaint = 0;
			my @guids = ();
			my $guids_length = 0;
			my $length;
			my $title;
			my $contentType = "audio/mpeg";  # assume it's audio.  Some servers don't send a content type.
			my $bitrate;
			my $body;
			$::d_directstream && msg("processing " . scalar(@headers) . " headers\n");

			if ($handler && $handler->can("parseDirectHeaders")) {
				# Could use a hash ref for header parameters
				($title, $bitrate, $metaint, $redir, $contentType, $length, $body) = $handler->parseDirectHeaders($client, $url, @headers);
			}
			else {
				# This code could move to the HTTP protocol handler
				foreach my $header (@headers) {
				
					$::d_directstream && msg("header-ds: " . $header . "\n");
		
					if ($header =~ /^ic[ey]-name:\s*(.+)/i) {
						
						$title = Slim::Utils::Unicode::utf8decode_guess($1, 'iso-8859-1');
					}
					
					if ($header =~ /^icy-br:\s*(.+)/i) {
						$bitrate = $1 * 1000;
					}
				
					if ($header =~ /^icy-metaint:\s*(.+)/) {
						$metaint = $1;
					}
				
					if ($header =~ /^Location:\s*(.*)/i) {
						$redir = $1;
					}
					
					if ($header =~ /^Content-Type:\s*(.*)/i) {
						$contentType = $1;
					}
					
					if ($header =~ /^Content-Length:\s*(.*)/i) {
						$length = $1;
					}
				}
	
				$contentType = Slim::Music::Info::mimeToType($contentType);
			}

			# update bitrate, content-type title for this URL...
			Slim::Music::Info::setContentType($url, $contentType) if $contentType;
			Slim::Music::Info::setBitrate($url, $bitrate) if $bitrate;
			Slim::Music::Info::setCurrentTitle($url, $title) if $title;

			$::d_directstream && msg("got a stream type:: $contentType  bitrate: $bitrate  title: $title\n");

			if ($contentType eq 'wma') {
			    push @guids, @WMA_FILE_PROPERTIES_OBJECT_GUID;
			    push @guids, @WMA_CONTENT_DESCRIPTION_OBJECT_GUID;
			    push @guids, @WMA_EXTENDED_CONTENT_DESCRIPTION_OBJECT_GUID;

			    $guids_length = $#guids;

			    # sending a length of -1 will return all wma header objects
			    # for debugging
			    ##@guids = ();
			    ##$guids_length = -1;
			}

			if ($redir) {
				$::d_directstream && msg("Redirecting to: $redir\n");
				$client->stop();
				$client->play(Slim::Player::Sync::isSynced($client), ($client->masterOrSelf())->streamformat(), $redir); 

			} elsif ($body || Slim::Music::Info::isList($url)) {

				$::d_directstream && msg("Direct stream is list, get body to explode\n");
				$client->directBody('');

				# we've got a playlist in all likelyhood, have the player send it to us
				$client->sendFrame('body', \(pack('N', $length)));

			} elsif ($client->contentTypeSupported($contentType)) {

				$::d_directstream && msg("Beginning direct stream!\n");

				my $loop = $client->shouldLoop($length);

				$client->streamformat($contentType);
				$client->sendFrame('cont', \(pack('NCnC*',$metaint, $loop, $guids_length, @guids)));		

			} else {

				$::d_directstream && msg("Direct stream failed\n");
				$client->failedDirectStream();
			}
		}
	}
}

sub directBodyFrame {
	my $client = shift;
	my $body = shift;

	my $url = $client->directURL();
	my $handler = Slim::Player::ProtocolHandlers->handlerForURL($url);
	my $done = 0;

	$::d_directstream && msg("got some body from the player, length " . length($body) . ": $body\n");
	if (length($body)) {
		$::d_directstream && msg("saving away that body message until we get an empty body\n");

		if ($handler && $handler->can('handleBodyFrame')) {
			$done = $handler->handleBodyFrame($client, $body);
			if ($done) {
				$client->stop();
			}
		}
		else {
			$client->directBody($client->directBody() . $body);
		}
	} else {
		$::d_directstream && msg("empty body means we should parse what we have for " . $client->directURL() . "\n");
		$done = 1;
	}

	if ($done) {
		if (length($client->directBody())) {

			my @items;
			# done getting body of playlist, let's parse it!
			# If the protocol handler knows how to parse it, give
			# it a chance, else we parse based on the type we know
			# already.
			if ($handler && $handler->can('parseDirectBody')) {
				@items = $handler->parseDirectBody($client, $url, $client->directBody());
			}
			else {
				my $io = IO::String->new($client->directBody());
				@items = Slim::Formats::Playlists->parseList($url, $io);
			}
	
			if (@items && scalar(@items)) { 
				Slim::Player::Source::explodeSong($client, \@items);
				Slim::Player::Source::playmode($client, 'play');
			} else {
				$::d_directstream && msg("body had no parsable items in it.\n");

				$client->failedDirectStream()
			}

			$client->directBody('');
		} else {
			$::d_directstream && msg("actually, the body was empty.  Got nobody...\n");
		}
	}
} 

sub directMetadata {
	my $client = shift;
	my $metadata = shift;
	
	my $url = $client->directURL;
	my $type = Slim::Music::Info::contentType($url);
	
	if ( $type eq 'wma' ) {
		Slim::Player::Protocols::MMS::parseMetadata( $client, $url, $metadata );
	}
	else {
		Slim::Player::Protocols::HTTP::parseMetadata( $client, Slim::Player::Playlist::url($client), $metadata );
	}
	
	# new song, so reset counters
	$client->songBytes(0);
}

sub failedDirectStream {
	my $client = shift;
	my $url = $client->directURL();
	$::d_directstream && msg("Oh, well failed to do a direct stream for: $url\n");
	$client->directURL(undef);
	$client->directBody(undef);

	Slim::Player::Source::errorOpening($client, $client->string("PROBLEM_CONNECTING"));

	# Similar to an underrun, but only continue if we're not at the
	# end of a playlist (irrespective of the repeat mode).
	if ($client->playmode eq 'playout-play' &&
		Slim::Player::Source::streamingSongIndex($client) != (Slim::Player::Playlist::count($client) - 1)) {
		Slim::Player::Source::skipahead($client);
	} else {
		Slim::Player::Source::playmode($client, 'stop');
	}
	
	# 6.3 Rhapsody code added this, why?
	# 1 means underrun due to error
	# Slim::Player::Source::underrun($client, 1);
}

# Should we use the inifinite looping option that some players
# (Squeezebox2) have as an optimization?
sub shouldLoop {
	my $client     = shift;
	my $audio_size = shift;

	# XXX Not turned on yet for regular SlimServer, since we
	# need to deal with the user:
	# 1) Turning off the repeat flag
	# 2) Adding a new track in playlist repeat mode
	return 0;

	# No looping if we have synced players
	return 0 if Slim::Player::Sync::isSynced($client);

	# This only makes sense if the player is in song repeat mode or
	# in playlist repeat mode with just one song on the list.
	return 0 unless (Slim::Player::Playlist::repeat($client) == 1 ||
		(Slim::Player::Playlist::repeat($client) == 2 &&
		Slim::Player::Playlist::count($client) == 1));

	my $url = Slim::Player::Playlist::url(
		$client,
		Slim::Player::Source::streamingSongIndex($client)
	);

	if (!$url) {
		errorMsg("shouldLoop: Invalid URL for client song!: [$url]\n");
		return 0;
	}

	# If we don't know the size of the track, don't bother
	return 0 unless $audio_size;

	# Ask the client if the track is small enough for this
	return 0 unless ($client->canLoop($audio_size));
	
	return 1;
}

sub canLoop {
	my $client = shift;
	my $length = shift;

	if ($length < 3*1024*1024) {
	    return 1;
	}

	return 0;
}

sub canDoReplayGain {
	my $client = shift;
	my $replay_gain = shift;

	if (defined($replay_gain)) {
		return dBToFixed($replay_gain);
	}

	return 0;
}


sub hasPreAmp {
	return 1;
}

# SB2 can display Unicode fonts via a TTF
sub isValidClientLanguage {
	my $class = shift;
	my $lang  = shift;

	return 1;
}

sub string {
        my $client = shift;
        my $string = shift;

	return Slim::Utils::Strings::string($string, Slim::Utils::Strings::getLanguage());
}

sub doubleString {
        my $client = shift;
        my $string = shift;

	return Slim::Utils::Strings::doubleString($string, Slim::Utils::Strings::getLanguage());
}

sub audio_outputs_enable { 
	my $client = shift;
	my $enabled = shift;

	# spdif enable / dac enable
	my $data = pack('CC', $enabled, $enabled);
	$client->sendFrame('aude', \$data);
}

1;
