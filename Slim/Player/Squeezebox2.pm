package Slim::Player::Squeezebox2;

# $Id: Squeezebox2.pm,v 1.10 2005/01/19 01:02:23 vidur Exp $

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
use File::Spec::Functions qw(:ALL);
use FindBin qw($Bin);
use IO::Socket;
use Slim::Player::Player;
use Slim::Utils::Misc;
use MIME::Base64;
use Data::Dumper;

our @ISA = ("Slim::Player::SqueezeboxG");

our $defaultPrefs = {
	'activeFont'		=> [qw(light standard full)],
	'activeFont_curr'	=> 1,
	'idleFont'		=> [qw(light standard full)],
	'idleFont_curr'		=> 1,
	'idleBrightness'	=> 2,
	'transitionType'		=> 0,
	'transitionDuration'		=> 0,
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
	  
	{ bar => 0, 
	  secs => 0, 
	  width => 320, 
	  params => [$VISUALIZER_NONE], fullness => 1 }
);

sub playingModeOptions { 
	my $client = shift;
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
	);

	if (Slim::Utils::Prefs::clientGet($client,'showbufferfullness')) {	
		$options{'12'} = $client->string('SETUP_SHOWBUFFERFULLNESS');
	}
	
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

sub nowPlayingModes {
	my $client = shift;
	my $count = scalar(@modes);
	
	if (!Slim::Utils::Prefs::clientGet($client,'showbufferfullness')) {
		$count--;
	}
	
	return $count;
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
	my $mode = ($client->showVisualizer() && !defined($client->modeParam('visu'))) ? Slim::Utils::Prefs::clientGet($client, "playingDisplayMode") : 0;
	return $modes[$mode || 0]{width};
}

sub bytesPerColumn {
	return 4;
}

sub displayHeight {
	return 32;
}

sub maxBass { 0 };
sub minBass { 0 };
sub maxTreble { 0 };
sub minTreble { 0 };
sub maxPitch { 0 };
sub minPitch { 0 };

sub model {
	return 'squeezebox2';
};

sub upgradeFont {
	return 'light';
};

# in order of preference based on whether we're connected via wired or wireless...
sub formats {
	my $client = shift;
	
	return ('flc','aif','wav','mp3');
}

# we only have 129 levels to work with now, and within 100 range, that's pretty tight.
# this table is optimized for 40 steps (like we have in the current player UI.
# TODO: Increase dynamic range of multiplier in client.
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


sub volume {
	my $client = shift;
	my $newvolume = shift;

	my $volume = $client->Slim::Player::Client::volume($newvolume, @_);
	if (defined($newvolume)) {
		my $level = $volume_map[int($volume)];
		my $data = pack('NNC', $level, $level, Slim::Utils::Prefs::clientGet($client, "digitalVolumeControl"));
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



# following required to send periodic visu frames whilst scrolling
sub scrollInit {
    my $client = shift;
    my $render = shift;
    my $scrollonce = shift;
    $client->visualizer();    
    $client->SUPER::scrollInit($render, $scrollonce);
}

sub scrollUpdateBackground {
    my $client = shift;
    my $render = shift;
    $client->visualizer();
    $client->SUPER::scrollUpdateBackground($render);
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
	
	my $paramsref = $client->modeParam('visu');
	
	if (!$paramsref) {
		my $visu = Slim::Utils::Prefs::clientGet($client, "playingDisplayMode");

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
	
	return if (defined($paramsref) && ($paramsref == $client->lastVisMode())); 

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
	my $end = shift;

	$client->pushUpDown($end, 'u');
}

sub pushDown {
	my $client = shift;
	my $end = shift;

	$client->pushUpDown($end, 'd');
}

sub pushUpDown {
	my $client = shift;
	my $end = shift;
	my $dir = shift;
	
	if (!defined($end)) {
		my @end = Slim::Display::Display::curLines($client);
		$end = \@end;
	}
	
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
	my $end = shift;

	$client->killAnimation();
	$client->animateState(1);
	$client->updateMode(1);
	$client->drawFrameBuf($client->render($end)->{bitsref}, undef, 'r', 0);
}

# push the old screen off the right side
sub pushRight {
	my $client = shift;
	my $start = shift;
	my $end = shift;

	$client->killAnimation();	
	$client->animateState(1);
	$client->updateMode(1);
	$client->drawFrameBuf($client->render($end)->{bitsref}, undef, 'l', 0);
}

# bump left against the edge
sub bumpLeft {
	my $client = shift;
	my $startbits = $client->render(Slim::Display::Display::curLines($client))->{bitsref};
	
	$client->killAnimation();	
	$client->animateState(1);
	$client->updateMode(1);
	$client->drawFrameBuf($startbits, undef, 'L', 0);
}

# bump right against the edge
sub bumpRight {
	my $client = shift;
	my $startbits = $client->render(Slim::Display::Display::curLines($client))->{bitsref};
	
	$client->killAnimation();	
	$client->animateState(1);
	$client->updateMode(1);
	$client->drawFrameBuf($startbits, undef, 'R', 0);
}

# bump left against the edge
sub bumpUp {
	my $client = shift;
	my $startbits = $client->render(Slim::Display::Display::curLines($client))->{bitsref};
	
	$client->killAnimation();
	$client->animateState(1);
	$client->updateMode(1);
	$client->drawFrameBuf($startbits, undef, 'U', 0);
}

# bump right against the edge
sub bumpDown {
	my $client = shift;
	my $startbits = $client->render(Slim::Display::Display::curLines($client))->{bitsref};

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

	my $filename = catdir($Bin, "Firmware", $client->model . "_$to_version.bin");

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
	
	my $mode = Slim::Utils::Prefs::clientGet($client, "playingDisplayMode");
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

sub canDirectStreamDisabled {
	my $client = shift;
	my $url = shift;

	my $handler = Slim::Player::Source::protocolHandlerForURL($url);
	if ($handler && $handler->can('convertToHTTP')) {
	    $url = $handler->convertToHTTP($url);
	}
	
	my $type = Slim::Music::Info::contentType($url);
	my $cando = (Slim::Music::Info::isHTTPURL($url) && ($client->contentTypeSupported($type) || $type eq 'unk' || Slim::Music::Info::isList($url)) );
	
	$::d_directstream && msg("Direct stream type: $type can: $cando: for $url\n");
	return $cando ? $url : undef;
}
	
sub directHeaders {
	my $client = shift;
	my $headers = shift;
	$::d_directstream && msg("processing headers for direct streaming\n");
	$::d_directstream && msg(Dumper($headers));
	$::d_directstream && bt();
	my $url = $client->directURL();
	
	return unless $url;
	
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
		
		if ($response < 200) {
			$::d_directstream && msg("Invalid response code ($response) from remote stream $url\n");
			$client->failedDirectStream();
		} elsif ($response > 399) {
			$::d_directstream && msg("Invalid response code ($response) from remote stream $url\n");
			$client->failedDirectStream();
		} else {
			my $redir = '';
			my $metaint = 0;
			my $length;
			my $title;
			my $contentType = "audio/mpeg";  # assume it's audio.  Some servers don't send a content type.
			my $bitrate;
			$::d_directstream && msg("processing " . scalar(@headers) . " headers\n");
			foreach my $header (@headers) {
				
				$::d_directstream && msg("header: " . $header . "\n");
		
				if ($header =~ /^ic[ey]-name:\s*(.+)/i) {
		
					$title = $1;
		
					if ($title && $] > 5.007) {
						$title = Encode::decode('iso-8859-1', $title, Encode::FB_QUIET());
					}	
				}
	
				if ($header =~ /^icy-br:\s*(.+)\015\012$/i) {
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
		
			# update bitrate, content-type title for this URL...
			Slim::Music::Info::setContentType($url, $contentType) if $contentType;
			Slim::Music::Info::setBitrate($url, $bitrate) if $bitrate;
			Slim::Music::Info::setCurrentTitle($url, $title) if $title;
			$::d_directstream && msg("got a stream type:: $contentType  bitrate: $bitrate  title: $title\n");

			if ($redir) {
				$::d_directstream && msg("Redirecting to: $redir\n");
				$client->stop();
				$client->play(Slim::Player::Sync::isSynced($client), ($client->masterOrSelf())->streamformat(), $redir); 

			} elsif ($client->contentTypeSupported(Slim::Music::Info::mimeToType($contentType))) {
				$::d_directstream && msg("Beginning direct stream!\n");
				my $loop = 0;
				if ($length) {
				    my $currentDB = Slim::Music::Info::getCurrentDataStore();
				    $currentDB->updateOrCreate({
					'url'        => $url,
					'attributes' => { 'SIZE' => $length },
				    });
				    
				    $loop = Slim::Player::Source::shouldLoop($client);
				}
				$client->streamformat(Slim::Music::Info::mimeToType($contentType));
				$client->sendFrame('cont', \(pack('NC',$metaint, $loop)));		
			} elsif (Slim::Music::Info::isList($url)) {
				$::d_directstream && msg("Direct stream is list, get body to explode\n");
				$client->directBody('');
				# we've got a playlist in all likelyhood, have the player send it to us
				$client->sendFrame('body', \(pack('N', $length)));
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
	$::d_directstream && msg("got some body from the player, length " . length($body) . ": $body\n");
	if (length($body)) {
		$::d_directstream && msg("saving away that body message until we get an empty body\n");
		$client->directBody($client->directBody() . $body);
	} else {
		if (length($client->directBody())) {
			$::d_directstream && msg("empty body means we should parse what we have for " . $client->directURL() . "\n");

			my $url = $client->directURL();
			my $handler = Slim::Player::Source::protocolHandlerForURL($url);

			my @items;
			# done getting body of playlist, let's parse it!
			if ($handler && $handler->can('parseList')) {
				@items = $handler->parseList($client->directURL(), $client->directBody());
			}
			else {
				my $io = IO::String->new($client->directBody());
				@items = Slim::Formats::Parse::parseList($client->directURL(), $io);
			}
	
			if (@items && scalar(@items)) { 
				Slim::Player::Source::explodeSong($client, \@items);
				Slim::Player::Source::playmode($client, 'play');
			} else {
				$::d_directstream && msg("body had no parsable items in it.\n");

				$client->failedDirectStream()
			}
		} else {
			$::d_directstream && msg("actually, the body was empty.  Got nobody...\n");
		}
	}
} 

sub directMetadata {
	my $client = shift;
	my $metadata = shift;

	Slim::Player::Protocols::HTTP::parseMetadata($client, Slim::Player::Playlist::song($client), $metadata);
	
	# new song, so reset counters
	$client->songBytes(0);
}

sub failedDirectStream {
	my $client = shift;
	my $url = $client->directURL();
	$::d_directstream && msg("Oh, well failed to do a direct stream for: $url\n");
	$client->directURL(undef);
	$client->directBody(undef);
	
	$client->stop();
	# todo notify upper layers that this is a bad station.
}

sub canLoop {
	my $client = shift;
	my $length = shift;

	if ($length < 3*1024*1024) {
	    return 1;
	}

	return 0;
}

1;
