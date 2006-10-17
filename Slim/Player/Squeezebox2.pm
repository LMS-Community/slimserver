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
use base qw(Slim::Player::Squeezebox);

use File::Spec::Functions qw(:ALL);
use File::Temp;
use IO::Socket;
use MIME::Base64;
use Scalar::Util qw(blessed);

use Slim::Formats::Playlists;
use Slim::Player::Player;
use Slim::Player::ProtocolHandlers;
use Slim::Player::Protocols::HTTP;
use Slim::Player::Protocols::MMS;
use Slim::Utils::Misc;
use Slim::Utils::Unicode;

our $defaultPrefs = {
	'transitionType'		=> 0,
	'transitionDuration'	=> 0,
	'replayGainMode'		=> 0,
	'disableDac'			=> 0,
};

# Keep track of direct stream redirects
our $redirects = {};

# WMA GUIDs we want to have the player send back to us
my @WMA_FILE_PROPERTIES_OBJECT_GUID              = (0x8c, 0xab, 0xdc, 0xa1, 0xa9, 0x47, 0x11, 0xcf, 0x8e, 0xe4, 0x00, 0xc0, 0x0c, 0x20, 0x53, 0x65);
my @WMA_CONTENT_DESCRIPTION_OBJECT_GUID          = (0x75, 0xB2, 0x26, 0x33, 0x66, 0x8E, 0x11, 0xCF, 0xA6, 0xD9, 0x00, 0xAA, 0x00, 0x62, 0xCE, 0x6C);
my @WMA_EXTENDED_CONTENT_DESCRIPTION_OBJECT_GUID = (0xd2, 0xd0, 0xa4, 0x40, 0xe3, 0x07, 0x11, 0xd2, 0x97, 0xf0, 0x00, 0xa0, 0xc9, 0x5e, 0xa8, 0x50);
my @WMA_STREAM_BITRATE_PROPERTIES_OBJECT_GUID    = (0x7b, 0xf8, 0x75, 0xce, 0x46, 0x8d, 0x11, 0xd1, 0x8d, 0x82, 0x00, 0x60, 0x97, 0xc9, 0xa2, 0xb2);

sub new {
	my $class = shift;

	my $client = $class->SUPER::new(@_);

	bless $client, $class;

	return $client;
}

sub init {
	my $client = shift;
	# make sure any preferences unique to this client may not have set are set to the default
	Slim::Utils::Prefs::initClientPrefs($client,$defaultPrefs);
	$client->SUPER::init();
}

sub reconnect {
	my $client = shift;
	$client->SUPER::reconnect(@_);

	$client->getPlayerSetting('playername');
	$client->getPlayerSetting('disableDac');
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
	
	return qw(wma ogg flc aif wav mp3);
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

sub periodicScreenRefresh {
    my $client = shift;
    # noop for this player - not required
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
		
		# display an error message
		$client->showBriefly( {
			'line1' => $client->string( 'FIRMWARE_MISSING' ),
			'line2' => $client->string( 'FIRMWARE_MISSING_DESC' ),
		},
		{ 
			'block'     => 1,
			'scroll'    => 1,
			'firstline' => 1,
			'callback'  => sub {
				# send upgrade done when the error message is done being displayed.  updn causes the
				# player to disconnect and reconnect, so if we do this too early the message gets lost
				$client->sendFrame('updn',\(' '));
			},
		} );

		return(0);
	}
	
	$client->stop();

	$::d_firmware && msg("using new update mechanism: $filename\n");

	my $err = $client->upgradeFirmware_SDK5($filename);

	if (defined($err)) {
		msg("upgrade failed: $err");
	} else {
		$client->forgetClient();
	}
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

	# update pending pref changes in the firmware
	foreach my $pref (keys %{$client->pendingPrefChanges()}) {

	    $client->setPlayerSetting($pref, $client->prefGet($pref));

	}
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
		$client->failedDirectStream($response);
	} else {
	
		my $status_line = $response;
		$response = $1;
		
		if (($response < 200) || $response > 399) {
			$::d_directstream && msg("Invalid response code ($response) from remote stream $url\n");
			if ($handler && $handler->can("handleDirectError")) {
				$handler->handleDirectError($client, $url, $response, $status_line);
			}
			else {
				$client->failedDirectStream($status_line);
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
		
					if ($header =~ /^(?:ic[ey]-name|x-audiocast-name):\s*(.+)/i) {
						
						$title = Slim::Utils::Unicode::utf8decode_guess($1, 'iso-8859-1');
					}
					
					if ($header =~ /^(?:icy-br|x-audiocast-bitrate):\s*(.+)/i) {
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
			
			if ($title && !Slim::Music::Info::title( $url )) {
				Slim::Music::Info::setTitle($url, $title);
			}
			
			# Bitrate may have been set in Scanner by reading the mp3 stream
			if ( !$bitrate ) {
				$bitrate = Slim::Music::Info::getBitrate( $url );
			}
			
			# WMA handles duration based on metadata
			if ( $contentType ne 'wma' ) {
				
				# See if we have an existing track object with duration info for this stream.
				if ( my $secs = Slim::Music::Info::getDuration($url) ) {
				
					# Display progress bar
					$client->streamingProgressBar( {
						'url'      => $url,
						'duration' => $secs,
					} );
				}
				else {
			
					if ( $bitrate && $length && $bitrate > 0 && $length > 0 && !$client->shouldLoop($length) ) {
						# if we know the bitrate and length of a stream, display a progress bar
						if ( $bitrate < 1000 ) {
							$bitrate *= 1000;
						}
						$client->streamingProgressBar( {
							'url'     => $url,
							'bitrate' => $bitrate,
							'length'  => $length,
						} );
					}
				}
			}

			$::d_directstream && msg("got a stream type:: $contentType  bitrate: $bitrate  title: $title\n");

			if ($contentType eq 'wma') {
				push @guids, @WMA_FILE_PROPERTIES_OBJECT_GUID;
				push @guids, @WMA_CONTENT_DESCRIPTION_OBJECT_GUID;
				push @guids, @WMA_EXTENDED_CONTENT_DESCRIPTION_OBJECT_GUID;
				push @guids, @WMA_STREAM_BITRATE_PROPERTIES_OBJECT_GUID;

			    $guids_length = scalar @guids;

			    # sending a length of -1 will return all wma header objects
			    # for debugging
			    ##@guids = ();
			    ##$guids_length = -1;
			}

			if ($redir) {
				$::d_directstream && msg("Redirecting to: $redir\n");
				
				# Store the old URL so we can update its bitrate/content-type/etc
				$redirects->{ $redir } = $url;			
				
				$client->stop();

				$client->play({
					'paused' => Slim::Player::Sync::isSynced($client), 
					'format' => ($client->masterOrSelf())->streamformat(), 
					'url'    => $redir,
				});

			} elsif ($body || Slim::Music::Info::isList($url)) {

				$::d_directstream && msg("Direct stream is list, get body to explode\n");
				$client->directBody(undef);

				# we've got a playlist in all likelyhood, have the player send it to us
				$client->sendFrame('body', \(pack('N', $length)));
				
			} elsif ( $contentType =~ /^(?:mp3|ogg|flc)$/ && !defined $bitrate ) {
				
				# if we're streaming mp3, ogg or flac audio and don't know the bitrate, request some body data
				$::d_directstream && msg("MP3/Ogg/FLAC stream with unknown bitrate, requesting body from player to parse\n");
				
				$client->sendFrame( 'body', \(pack( 'N', 16 * 1024 )) );

			} elsif ($client->contentTypeSupported($contentType)) {
				
				# If we redirected (Live365), update the original URL with the metadata from the real URL
				if ( my $oldURL = delete $redirects->{ $url } ) {
					Slim::Music::Info::setContentType( $oldURL, $contentType ) if $contentType;
					Slim::Music::Info::setBitrate( $oldURL, $bitrate ) if $bitrate;
					
					# carry the original title forward to the new URL
					my $title = Slim::Music::Info::title( $oldURL );
					Slim::Music::Info::setTitle( $url, $title ) if $title;
				}

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

	$::d_directstream && msg("got some body from the player, length " . length($body) . "\n");
	
	if (length($body)) {
		$::d_directstream && msg("saving away that body message until we get an empty body\n");

		if ($handler && $handler->can('handleBodyFrame')) {
			$done = $handler->handleBodyFrame($client, $body);
			if ($done) {
				$client->stop();
			}
		}
		else {
			# save direct body to a temporary file
			if ( !blessed $client->directBody ) {
				my $fh = File::Temp->new();
				$client->directBody( $fh );
				$::d_directstream && msg("directBodyFrame: Saving to temp file: " . $fh->filename . "\n");
			}
			
			$client->directBody->write( $body, length($body) );
		}
	} else {
		$::d_directstream && msg("empty body means we should parse what we have for " . $client->directURL() . "\n");
		$done = 1;
	}

	if ($done) {
		if ( defined $client->directBody ) {
			
			# seek back to the front of the file
			seek $client->directBody, 0, 0;

			my @items;
			# done getting body of playlist, let's parse it!
			# If the protocol handler knows how to parse it, give
			# it a chance, else we parse based on the type we know
			# already.
			if ( $handler && $handler->can('parseDirectBody') ) {
				@items = $handler->parseDirectBody( $client, $url, $client->directBody );
			}
			else {
				@items = Slim::Formats::Playlists->parseList( $url, $client->directBody );
			}
	
			if ( scalar @items ) { 
				Slim::Player::Source::explodeSong($client, \@items);
				Slim::Player::Source::playmode($client, 'play');
			} else {
				$::d_directstream && msg("body had no parsable items in it.\n");

				$client->failedDirectStream( $client->string('PLAYLIST_NO_ITEMS_FOUND') );
			}

			$client->directBody(undef); # Will also remove the temporary file
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
	my $error  = shift;
	my $url = $client->directURL();
	$::d_directstream && msg("Oh, well failed to do a direct stream for: $url [$error]\n");
	$client->directURL(undef);
	$client->directBody(undef);	

	Slim::Player::Source::errorOpening( $client, $error || $client->string("PROBLEM_CONNECTING") );

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
	
	# Check with the protocol handler
	my $handler = Slim::Player::ProtocolHandlers->handlerForURL($url);
	if ( $handler && $handler->can('shouldLoop') ) {
		return $handler->shouldLoop($audio_size, $url);
	}
	
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

sub hasDisableDac() {
	return 1;
}

sub audio_outputs_enable { 
	my $client = shift;
	my $enabled = shift;

	# spdif enable / dac enable
	my $data = pack('CC', $enabled, $enabled);
	$client->sendFrame('aude', \$data);
}


# The following settings are sync'd between the player firmware and slimserver
our $pref_settings = {
	'playername' => {
		firmwareid => 0,
		pack => 'Z*',
	},
    	'digitalOutputEncoding' => {
		firmwareid => 1,
		pack => 'C',
	},
    	'wordClockOutput' => {
		firmwareid => 2,
		pack => 'C',
	},
    	'powerOffDac' => { # (Transporter only)
		firmwareid => 3,
		pack => 'C',
	},
    	'disableDac' => { # (Squezebox2/3 only)
		firmwareid => 4,
		pack => 'C',
	},
};

# Request a pref from the player firmware
sub getPlayerSetting {
	my $client = shift;
	my $pref = shift;

	$::d_prefs && msg("getPlayerSetting $pref\n");

	my $currpref = $pref_settings->{$pref};

	my $data = pack('C', $currpref->{firmwareid});
	$client->sendFrame('setd', \$data);
}

# Update a pref in the player firmware
sub setPlayerSetting {
	my $client = shift;
	my $pref = shift;
	my $value = shift;

	return if !defined $value;

	$::d_prefs && msg("setPlayerSetting $pref = $value\n");

	my $currpref = $pref_settings->{$pref};

	if ($client->playmode() eq 'stop') {

		my $data = pack('C'.$currpref->{pack}, $currpref->{firmwareid}, $value);
		$client->sendFrame('setd', \$data);

	}
	else {

		# we can't update the pref's while playing, cache this change for later
		$::d_prefs && msg("setPlayerSeting pending change for $pref\n");
		$client->pendingPrefChanges()->{$pref}++;

	}
}

# Allow the firmware to update a pref in slimserver
sub playerSettingsFrame {
	my $client = shift;
	my $data_ref = shift;

	my $id = unpack('C', $$data_ref);

	while (my ($pref, $currpref) = each %$pref_settings) {
		next unless ($currpref->{firmwareid} == $id);

		my $value = (unpack('C'.$currpref->{pack}, $$data_ref))[1];
		$value = undef if (length($value) == 0);

		$::d_prefs && msg("playerSettingsFrame $pref = $value\n");

		if (!defined $value) {
			$client->setPlayerSetting($pref, $client->prefGet($pref));
		} else {
			$client->SUPER::prefSet($pref, $value);
		}
	}
}

sub prefSet {
	my $client = shift;
	my $pref = shift;
	my $value = shift;
	my $ind = shift;

	if (exists $pref_settings->{$pref}) {
		$client->setPlayerSetting($pref, $value);
	}

	$client->SUPER::prefSet($pref, $value, $ind);
}

sub pcm_sample_rates {
	my $client = shift;
	my $track = shift;

    	my %pcm_sample_rates = ( 8000 => '5',
				 11000 => '0',
				 12000 => '6',
				 22000 => '1',
				 24000 => '8',
				 32000 => '2',
				 44100 => '3',
				 48000 => '4',
				 70000 => '7',
				 96000 => '9',			 
				 );

	return $pcm_sample_rates{$track->samplerate()} || '3';
}

1;
