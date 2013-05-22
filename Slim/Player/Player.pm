package Slim::Player::Player;

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# $Id$
#

use strict;

use Scalar::Util qw(blessed);

use base qw(Slim::Player::Client);

use Slim::Buttons::SqueezeNetwork;
use Slim::Hardware::IR;
use Slim::Player::Client;
use Slim::Player::Source;
use Slim::Player::Playlist;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;

my $log     = logger('player.ui');
my $nplog   = logger('network.protocol');
my $synclog = logger('player.sync');

my $prefs = preferences('server');

our $defaultPrefs = {
	'bass'                 => 50,
	'digitalVolumeControl' => 1,
	'preampVolumeControl'  => 0,
	'disabledirsets'       => [],
	'irmap'                => sub { Slim::Hardware::IR::defaultMapFile() },
	'menuItem'             => [qw(
		NOW_PLAYING
		BROWSE_MUSIC
		RADIO
		PLUGIN_MY_APPS_MODULE_NAME
		PLUGIN_APP_GALLERY_MODULE_NAME
		FAVORITES
		GLOBAL_SEARCH
		PLUGINS
		SETTINGS
		SQUEEZENETWORK_CONNECT
	)],
	'mp3SilencePrelude'    => 0,
	'pitch'                => 100,
	'power'                => 1,
	'screensaver'          => 'screensaver',
	'idlesaver'            => 'nosaver',
	'offsaver'             => 'SCREENSAVER.datetime',
	'alarmsaver'           => 'SCREENSAVER.datetime',
	'screensavertimeout'   => 30,
	'syncPower'            => 0,
	'syncVolume'           => 0,
	'treble'               => 50,
	'volume'               => 50,
	'bufferThreshold'      => 255,	# KB
	'powerOnResume'        => 'PauseOff-PlayOn',
	'maintainSync'         => 1,
	'minSyncAdjust'        => 30,	# ms
	'packetLatency'        => 2,	# ms
	'startDelay'           => 0,	# ms
	'playDelay'            => 0,	# ms
};

$prefs->migrateClient(9, sub {
	my $cprefs = shift;
	$cprefs->set('irmap' => Slim::Hardware::IR::defaultMapFile()) if $cprefs->get('irmap') =~ /SqueezeCenter/i;
	1;
});

$prefs->setChange( sub { $_[2]->volume($_[1]); }, 'volume');

$prefs->setChange( sub { $_[2]->volume( $_[2]->volume ); }, 'digitalVolumeControl');

$prefs->setChange( sub { my $client = $_[2]; $client->bass($_[1]); }, 'bass');
$prefs->setChange( sub { my $client = $_[2]; $client->treble($_[1]); }, 'treble');

$prefs->setChange( sub { $_[2]->pitch($_[1]); }, 'pitch');

sub new {
	my ($class, $id, $paddr, $rev, $s, $deviceid, $uuid) = @_;

	my $client = $class->SUPER::new($id, $paddr, $rev, $s, $deviceid, $uuid);

	# initialize model-specific features:
	$client->revision($rev);

	return $client;
}

sub init {
	my $client = shift;
	my (undef, undef, $syncgroupid) = @_;

	$client->SUPER::init(@_);

	Slim::Hardware::IR::initClient($client);
	Slim::Buttons::Home::updateMenu($client);

	# fire it up!
	$client->power($prefs->client($client)->get('power'));
	$client->startup($syncgroupid);

	return if $client->display->isa('Slim::Display::NoDisplay');
		
	# start the screen saver
	Slim::Buttons::ScreenSaver::screenSaver($client);
	$client->brightness($prefs->client($client)->get($client->power() ? 'powerOnBrightness' : 'powerOffBrightness'));

	$client->periodicScreenRefresh(); 
}

# noop for most players
sub periodicScreenRefresh {}    

sub reportsTrackStart { 1 }

sub initPrefs {
	my $client = shift;

	# make sure any preferences this client may not have set are set to the default
	# This should be a method on client!
	$prefs->client($client)->init($defaultPrefs);

	$client->SUPER::initPrefs();
}

# usage	- float	buffer fullness as a fraction
sub usage {
	my $client = shift;
	return $client->bufferSize() ? $client->bufferFullness() / $client->bufferSize() : 0;
}

# following now handled by display object
sub update      { shift->display->update(@_); }
sub showBriefly { shift->display->showBriefly(@_); }
sub pushLeft    { shift->display->pushLeft(@_); }
sub pushRight   { shift->display->pushRight(@_); }
sub pushUp      { shift->display->pushUp(@_); }
sub pushDown    { shift->display->pushDown(@_); }
sub bumpLeft    { shift->display->bumpLeft(@_); }
sub bumpRight   { shift->display->bumpRight(@_); }
sub bumpUp      { shift->display->bumpUp(@_); }
sub bumpDown    { shift->display->bumpDown(@_); }
sub brightness  { shift->display->brightness(@_); }
sub maxBrightness { shift->display->maxBrightness(@_); }
sub scrollTickerTimeLeft { shift->display->scrollTickerTimeLeft(@_); }
sub killAnimation { shift->display->killAnimation(@_); }
sub textSize    { shift->display->textSize(@_); }
sub maxTextSize { shift->display->maxTextSize(@_); }
sub linesPerScreen { shift->display->linesPerScreen(@_); }
sub symbols     { shift->display->symbols(@_); }
sub prevline1   { if (my $display = shift->display) { return $display->prevline1(@_); }}
sub prevline2   { if (my $display = shift->display) { return $display->prevline2(@_); }}
sub curDisplay  { shift->display->curDisplay(@_); }
sub curLines    { shift->display->curLines(@_); }
sub parseLines  { shift->display->parseLines(@_); }
sub renderOverlay { shift->display->renderOverlay(@_); }
sub measureText { shift->display->measureText(@_); }
sub displayWidth{ shift->display->displayWidth(@_); }
sub sliderBar   { shift->display->sliderBar(@_); }
sub progressBar { shift->display->progressBar(@_); }
sub balanceBar  { shift->display->balanceBar(@_); }
sub fonts         { shift->display->fonts(@_); }
sub displayHeight { shift->display->displayHeight(@_); }
sub currBrightness { shift->display->currBrightness(@_); }
sub vfdmodel    { shift->display->vfdmodel(@_); }

sub updateMode  { shift->display->updateMode(@_); }
sub animateState{ shift->display->animateState(@_); }
sub scrollState { shift->display->scrollState(@_); }

sub block       { Slim::Buttons::Block::block(@_); }
sub unblock     { Slim::Buttons::Block::unblock(@_); }

sub string      { shift->display->string(@_); }
sub doubleString{ shift->display->doubleString(@_); }

sub isPlayer {
	return 1;
}

sub power {
	my $client = shift;
	my $on     = shift;
	my $noplay = shift;
	
	my $currOn = $prefs->client($client)->get('power') || 0;

	return $currOn unless defined $on;
	return unless (!defined(Slim::Buttons::Common::mode($client)) || ($currOn != $on));

	my $resume = $prefs->client($client)->get('powerOnResume');
	$resume =~ /(.*)Off-(.*)On/;
	my ($resumeOff, $resumeOn) = ($1,$2);
	
	my $controller = $client->controller();

	if (!$on) {
		# turning player off - unsync/pause/stop player and move to off mode
		
		my $justUnsync = 0;
		
		for my $other ($client->syncedWith()) {
			if ($other->power() && !$prefs->client($other)->get('syncPower')) {
				$justUnsync = 1;
				last;				
			}
		}

		if ($justUnsync) {
			# Just stop this player if more than one in sync group & not all syncing-off
			$controller->playerInactive($client);
			$prefs->client($client)->set('playingAtPowerOff', 0);
 		} else {	
			my $playing = $controller->isPlaying(1);
			$prefs->client($client)->set('playingAtPowerOff', $playing);
			
			# bug 8776, only pause if really playing a local file, otherwise always stop
			# bug 10645, this is no longer necessary as the controller will stop the remote stream if necessary
			
			if ($playing && ($resumeOff eq 'Pause')) {
				# Pause client mid track
				$client->execute(["pause", 1, undef, 1]);
			} elsif ($controller->isPaused() && ($resumeOff eq 'Pause')) {
				# already paused, do nothing
			} else {
				# bug 8776, force stop here in case in some intermediate state (TRACKWAIT, BUFFERING, ...)
				$client->execute(["stop"]);
			}
	 	}

		$client->display->renderCache()->{defaultfont} = undef;
	 	
	 	# Do now, not earlier so that playmode changes still work
	 	$prefs->client($client)->set('power', $on); # Do now, not earlier so that 
	 	
		# turn off audio outputs
		$client->audio_outputs_enable(0);

		# move display to off mode
		$client->killAnimation();
		$client->brightness($prefs->client($client)->get('powerOffBrightness'));

		Slim::Buttons::Common::setMode($client, 'off');

	} else {

		$client->display->renderCache()->{defaultfont} = undef;

		$prefs->client($client)->set('power', $on);
		
		# turning player on - reset mode & brightness, display welcome and sync/start playing
		$client->audio_outputs_enable(1);

		$client->update( { 'screen1' => {}, 'screen2' => {} } );

		$client->updateMode(2); # block updates to hide mode change

		Slim::Buttons::Common::setMode($client, 'home');

		$client->updateMode(0); # unblock updates
			
		# no need to initialize brightness if no display is available
		if ( !$client->display->isa('Slim::Display::NoDisplay') ) {
			# restore the saved brightness, unless its completely dark...
			my $powerOnBrightness = $prefs->client($client)->get('powerOnBrightness');
	
			if ($powerOnBrightness < 1) {
				$powerOnBrightness = 1;
				$prefs->client($client)->set('powerOnBrightness', $powerOnBrightness);
			}
			$client->brightness($powerOnBrightness);
	
			my $oneline = ($client->linesPerScreen() == 1);
	
			$client->welcomeScreen();
		}

		$controller->playerActive($client);

		if (!$controller->isPlaying() && !$noplay) {
			
			if ($resumeOn =~ /Reset/) {
				# reset playlist to start, but don't start the playback yet
				$client->execute(["playlist","jump", 0, 1, 1]);
			}
			
			if ($resumeOn =~ /Play/ && Slim::Player::Playlist::song($client)
				&& $prefs->client($client)->get('playingAtPowerOff')) {
				# play even if current playlist item is a remote url (bug 7426)
				# but only if we were playing at power-off (bug 7061)
				$client->execute(["play"]); # will resume if paused
			}
		}		
	}
}

sub welcomeScreen {
	my $client = shift;

	return if $client->display->isa('Slim::Display::NoDisplay');

	# SLIM_SERVICE
	my $line1 = ( main::SLIM_SERVICE ) 
		? $client->string('WELCOME_TO_APPLICATION')
		: $client->string('WELCOME_TO_' . $client->model);
	my $line2 = ( main::SLIM_SERVICE )
		? $client->string('WELCOME_MESSAGE')
		: $client->string('FREE_YOUR_MUSIC');

	$client->showBriefly( {
		'center' => [ 
				$line1,
				$line2
			],
		'fonts' => { 
				'graphic-320x32' => 'standard',
				'graphic-160x32' => 'standard_n',
				'graphic-280x16' => 'medium',
				'text'           => 2,
			},
		'screen2' => {},
		'jive' => undef,
	}, undef, undef, 1);
}

sub audio_outputs_enable { }

sub maxVolume { return 100; }
sub minVolume {	return 0; }

sub maxTreble {	return 100; }
sub minTreble {	return 0; }

sub maxBass {	return 100; }
sub minBass {	return 0; }

# fade the volume up or down
# $fade = number of seconds to fade 100% (positive to fade up, negative to fade down) 
# $callback is function reference to be called when the fade is complete

sub fade_volume {
	my ($client, $fade, $callback, $callbackargs) = @_;

	my $int = 0.05; # interval between volume updates

	my $vol = abs($prefs->client($client)->get("volume"));
	my $now = Time::HiRes::time();
	
	Slim::Utils::Timers::killHighTimers($client, \&_fadeVolumeUpdate);

	$client->_fadeVolumeUpdate( {
		'startVol' => ($fade > 0) ? 0 : $vol,
		'endVol'   => ($fade > 0) ? $vol : 0,
		'startTime'=> $now,
		'endTime'  => $callback ? $now + $fade : undef,
		'int'      => $int,
		'rate'     => ($vol && $fade) ? $vol / $fade : 0,
		'cb'       => $callback,
		'cbargs'   => $callbackargs,
	} );
}

sub _fadeVolumeUpdate {
	my $client = shift;
	my $f = shift;
	
	# If the user manually changed the volume, stop fading
	if ( $f->{'vol'} && $f->{'vol'} != $client->volume ) {
		
		# Bug 9752: always call callback
		if ($f->{'cb'}) {
			&{$f->{'cb'}}(@{$f->{'cbargs'}});
		}
		
		return;
	}
	
	my $now = Time::HiRes::time();

	# new vol based on time since fade started to minise impact of timers firing late
	$f->{'vol'} = $f->{'startVol'} + ($now - $f->{'startTime'}) * $f->{'rate'};

	my $rate = $f->{'rate'};

	if (
		   !$rate 
		|| ( $rate < 0 && $f->{'vol'} < $f->{'endVol'} )
		|| ( $rate > 0 && $f->{'vol'} > $f->{'endVol'} )
	) {

		# reached end of fade - set final volume
		$client->volume($f->{'endVol'}, 1);

		if ($f->{'cb'}) {
			
			if ( $f->{'endTime'} && $f->{'endTime'} > $now ) {

				# delay the callback until endTime so it occurs at approx same time as other synced players
				my $endTime = delete $f->{'endTime'};
				Slim::Utils::Timers::setHighTimer($client, $endTime, \&_fadeVolumeUpdate, $f);

			} else {

				&{$f->{'cb'}}(@{$f->{'cbargs'}});
			}
		}

	} else {

		$client->volume($f->{'vol'}, 1);
		Slim::Utils::Timers::setHighTimer($client, $now + $f->{'int'}, \&_fadeVolumeUpdate, $f);
	}
}

# mute or un-mute volume as necessary
# A negative volume indicates that the player is muted and should be restored 
# to the absolute value when un-muted.
sub mute {
	my $client = shift;
	
	if (!$client->isPlayer()) {
		return 1;
	}

	my $vol = $prefs->client($client)->get('volume');
	my $mute = $prefs->client($client)->get('mute');
	
	if (($vol < 0) && ($mute)) {
		# mute volume
		# todo: there is actually a hardware mute feature
		# in both decoders. Need to add Decoder::mute
		$client->volume(0);
	} else {
		# un-mute volume
		$vol *= -1;
		$client->volume($vol);
	}

	$prefs->client($client)->set('volume', $vol);
	$client->mixerDisplay('volume');
}

sub hasDigitalOut {
	return 0;
}

sub hasVolumeControl {
	return 1;
}
	
sub sendFrame {};

sub currentSongLines {
	my $client = shift;
	my $args   = shift;

	my $onScreen2        = $args->{'screen2'};         # return as screen2
	my $suppressDisplay  = $args->{'suppressDisplay'}; # suppress both displays [leaving just jive hash]
	my $retrieveMetadata = $args->{'retrieveMetadata'} || 0;
	my $jiveIconStyle    = $args->{'jiveIconStyle'} || undef;   # an icon style to send to squeezeplay (used for fwd and rew icons)

	my $parts;
	my $status;
	my @lines = ();
	my @overlay = ();
	my $screen2;
	my $jive;
	
	my $playmode    = Slim::Player::Source::playmode($client);
	my $playlistlen = Slim::Player::Playlist::count($client);

	$jiveIconStyle = $jiveIconStyle ? $jiveIconStyle : $playmode;

	if ($playlistlen < 1) {

		$status = $client->string('NOTHING');

		@lines = ( $client->string('NOW_PLAYING'), $client->string('NOTHING') );

		if ($client->display->showExtendedText() && !$suppressDisplay && !$onScreen2) {
			$screen2 = {};
		}

	} else {

		if ($playmode eq "pause") {

			$status = $client->string('PAUSED');

			if ( $playlistlen == 1 ) {

				$lines[0] = $status;

			} else {

				$lines[0] = sprintf(
					$status." (%d %s %d) ",
					Slim::Player::Source::playingSongIndex($client) + 1, $client->string('OUT_OF'), $playlistlen
				);
			}

		# for taking photos of the display, comment out the line above, and use this one instead.
		# this will cause the display to show the "Now playing" screen to show when paused.
		# line1 = "Now playing" . sprintf " (%d %s %d) ", Slim::Player::Source::playingSongIndex($client) + 1, string('OUT_OF'), $playlistlen;

		} elsif ($playmode eq "stop") {

			$status = $client->string('STOPPED');

			if ( $playlistlen == 1 ) {
				$lines[0] = $status;
			}
			else {
				$lines[0] = sprintf(
					$status." (%d %s %d) ",
					Slim::Player::Source::playingSongIndex($client) + 1, $client->string('OUT_OF'), $playlistlen
				);
			}

		} elsif ($client->isRetrying()) {
			
			$status = $lines[0] = $client->string('RETRYING');

			if ( $playlistlen == 1 ) {

				$lines[0] = $status;

			} else {

				$lines[0] = sprintf(
					$status." (%d %s %d) ",
					Slim::Player::Source::playingSongIndex($client) + 1, $client->string('OUT_OF'), $playlistlen
				);
			}
			
		} else {

			$status = $lines[0] = $client->string('PLAYING');
			
			if ($client->volume() < 0) {
				$lines[0] .= " ". $client->string('LCMUTED');
			}

			if ( $playlistlen > 1 ) {
				$lines[0] .= sprintf(
					" (%d %s %d) ",
					Slim::Player::Source::playingSongIndex($client) + 1, $client->string('OUT_OF'), $playlistlen
				);
			}
		}
		
		my $song = Slim::Player::Playlist::song($client);
		
		my $currentTitle;
		my $imgKey;
		my $artwork;
		my $remoteMeta;

		if ( $song->isRemoteURL ) {
			my $handler = Slim::Player::ProtocolHandlers->handlerForURL($song->url);

			if ( $handler && $handler->can('getMetadataFor') ) {

				$remoteMeta = $handler->getMetadataFor( $client, $song->url );

				if ( $remoteMeta->{cover} ) {
					$imgKey = 'icon';
					$artwork = $remoteMeta->{cover};
				}
				elsif ( $remoteMeta->{icon} ) {
					$imgKey = 'icon-id';
					$artwork = $remoteMeta->{icon};
				}
				
				# Format remote metadata according to title format
				$currentTitle = Slim::Music::Info::getCurrentTitle( $client, $song->url, 0, $remoteMeta );
			}
			
			# If that didn't return anything, use default title
			if ( !$currentTitle ) {
				$currentTitle = Slim::Music::Info::getCurrentTitle( $client, $song->url );
			}

			if ( !$artwork ) {
				$imgKey  = 'icon-id';
				$artwork = '/html/images/radio.png';
				
				if ( main::SLIM_SERVICE ) {
					$artwork = Slim::Networking::SqueezeNetwork->url('/static/images/icons/radio.png', 'external');
				}
			}
		}
		else {
			$currentTitle = Slim::Music::Info::getCurrentTitle( $client, $song->url );
			
			if ( my $album = $song->album ) {
				$imgKey = 'icon-id';
				$artwork = $album->artwork || 0;
			}
		}
		
		$lines[1] = $currentTitle;

		$overlay[1] = $client->symbols('notesymbol');

		# add screen2 information if required
		if ($client->display->showExtendedText() && !$suppressDisplay && !$onScreen2) {
			
			my ($s2line1, $s2line2);

			if ($song && $song->isRemoteURL) {

				my $title = Slim::Music::Info::displayText($client, $song, 'TITLE');

				if ( ($currentTitle || '') ne ($title || '') && !Slim::Music::Info::isURL($title) ) {

					$s2line2 = $title;

				} elsif ($remoteMeta) {

					$s2line1 = Slim::Music::Info::displayText($client, $song, 'ALBUM', $remoteMeta);
					$s2line2 = Slim::Music::Info::displayText($client, $song, 'ARTIST', $remoteMeta);
				}

			} else {

				$s2line1 = Slim::Music::Info::displayText($client, $song, 'ALBUM');
				$s2line2 = Slim::Music::Info::displayText($client, $song, 'ARTIST');
			}

			$screen2 = {
				'line' => [ $s2line1, $s2line2 ],
			};
		}
		
		$jive = {
			'type' => 'icon',
			'text' => [ $status, $song ? $song->title : undef ],
			'style' => $jiveIconStyle,
			'play-mode' => $playmode,
			'is-remote' => $song->isRemoteURL,
		};
		
		if ( $imgKey ) {
			$jive->{$imgKey} = Slim::Web::ImageProxy::proxiedImage($artwork);
		}
	}

	if (!$suppressDisplay) {

		if (!$onScreen2) {

			# build display for screen1 and possibly screen2
			$parts->{'line'}    = \@lines;
			$parts->{'overlay'} = \@overlay;
			$parts->{'screen2'} = $screen2 if defined $screen2;
			$client->nowPlayingModeLines($parts, undef) unless ($playlistlen < 1);

		} else {

			# build display on screen2
			$parts->{'screen2'}->{'line'}    = \@lines;
			$parts->{'screen2'}->{'overlay'} = \@overlay;
			$client->nowPlayingModeLines($parts->{'screen2'}, 1) unless ($playlistlen < 1);
		}

		$parts->{'jive'} = $jive if defined $jive;

	} elsif ($suppressDisplay ne 'all') {

		$parts->{'jive'} = $jive || \@lines;
	}

	return $parts;
}

# This method is misnamed - it adds in the progress overlay only
# Call currentSongLines to get the full display
sub nowPlayingModeLines {
	my ($client, $parts, $screen2) = @_;

	my $display = $client->display;

	return if $display->isa('Slim::Display::NoDisplay');

	my $overlay;
	my $fractioncomplete = 0;
	my $songtime = '';
	
	my $modes;
	
	if ( main::SLIM_SERVICE ) {
		# Allow buffer fullness display to work on SN where we don't have a playingDisplayModes pref
		if ( $client->isa('Slim::Player::Transporter') ) {
			if ( $prefs->client($client)->get('playingDisplayMode') >= 6 ) {
				$modes = [0..7];
			}
		}
		elsif ( $client->isa('Slim::Player::Boom') ) {
			if ( $prefs->client($client)->get('playingDisplayMode') >= 10 ) {
				$modes = [0..11];
			}
		}
		else {
			if ( $prefs->client($client)->get('playingDisplayMode') >= 12 ) {
				$modes = [0..13];
			}
		}
	}
	
	if ( !defined $modes ) {
		$modes = $prefs->client($client)->get('playingDisplayModes');
	}
	
	my $mode = $modes->[ $prefs->client($client)->get('playingDisplayMode') ];

	unless (defined $mode) { $mode = 1; };

	my $modeOpts = $display->modes->[$mode];

	my $showBar      = $modeOpts->{bar};
	my $showTime     = $modeOpts->{secs};
	my $showFullness = $modeOpts->{fullness};
	my $showClock    = $modeOpts->{clock};
	my $displayWidth = $display->displayWidth($screen2 ? 2 : 1);
	
	# check if we don't know how long the track is...
	if (!$client->controller()->playingSongDuration()) {
		$showBar = 0;
	}
	
	if ($showFullness) {
		$fractioncomplete = $client->usage();
	} elsif ($showBar) {
		$fractioncomplete = Slim::Player::Source::progress($client);
	}
	
	if ($showFullness) {
		$songtime = ' ' . int($fractioncomplete * 100 + 0.5)."%";
		
		# for remote streams where we know the bitrate, 
		# show the number of seconds of audio in the buffer instead of a percentage
		my $url = Slim::Player::Playlist::url($client);
		if ( Slim::Music::Info::isRemoteURL($url) ) {
			my $decodeBuffer = 0;
			
			# Display decode buffer as seconds if we know the bitrate, otherwise show KB
			if ( $client->streamingSong() ) {
				my $bitrate = $client->streamingSong()->streambitrate();
				if ( $bitrate && $bitrate > 0 ) {
					$decodeBuffer = sprintf( "%.1f", $client->bufferFullness() / ( int($bitrate / 8) ) );
				}
				else {
					$decodeBuffer = sprintf( "%d KB", $client->bufferFullness() / 1024 );
				}
			}
			
			if ( $client->isa('Slim::Player::Squeezebox2') ) {
				# Only show output buffer status on SB2 and higher
				my $outputBuffer = $client->outputBufferFullness() / (44100 * 8);
				$songtime  = ' ' . sprintf "%s / %.1f", $decodeBuffer, $outputBuffer;
				$songtime .= ' ' . $client->string('SECONDS') unless $client->isa('Slim::Player::Boom');
			}
			else {
				$songtime  = ' ' . sprintf "%s", $decodeBuffer;
				$songtime .= ' ' . $client->string('SECONDS');
			}
		}

	} elsif ($showTime) { 
		$songtime = ' ' . $client->textSongTime($showTime < 0);
	} elsif ($showClock) {
		# show the current time in the format defined for datetime screensaver
		$songtime = ' ' . $client->timeF();
	}

	if ($showTime || $showFullness || $showClock) {
		$overlay = $songtime;
	}
	
	if ($showBar) {
		# show both the bar and the time
		my $leftLength = $display->measureText($parts->{line}[0], 1);
		my $barlen = $displayWidth - $leftLength - $display->measureText($overlay, 1, 2);
		my $bar    = $display->symbols($client->progressBar($barlen, $fractioncomplete, ($showBar < 0)));

		$overlay = $bar . $songtime;
	}
	
	$parts->{overlay}[0] = $overlay if defined($overlay);
}

sub textSongTime {
	my $client = shift;
	my $remaining = shift;

	my $delta = 0;
	my $sign  = '';

	my $duration = $client->controller()->playingSongDuration() || 0;

	if (Slim::Player::Source::playmode($client) eq "stop") {
		$delta = 0;
	} else {	
		$delta = Slim::Player::Source::songTime($client);
		if ($duration && $delta > $duration) {
			$delta = $duration;
		}
	}

	# 2 and 5 display remaining time, not elapsed
	if ($remaining) {
		if ($duration) {
			$delta = $duration - $delta;	
			$sign = '-';
		}
	}
	
	my $hrs = int($delta / (60 * 60));
	my $min = int(($delta - $hrs * 60 * 60) / 60);
	my $sec = $delta - ($hrs * 60 * 60 + $min * 60);
	
	if ($hrs) {

		return sprintf("%s%d:%02d:%02d", $sign, $hrs, $min, $sec);

	} else {

		return sprintf("%s%02d:%02d", $sign, $min, $sec);
	}
}

sub mixerDisplay {
	my $client = shift;
	my $feature = shift;
	
	if ($feature !~ /(?:volume|pitch|bass|treble)/) {
		return;
	}

	my $featureValue = $prefs->client($client)->get($feature);

	# Check for undefined - 0 is a valid value.
	if (!defined $featureValue) {
		return;
	}

	my $mid   = $client->mixerConstant($feature, 'mid');
	my $scale = $client->mixerConstant($feature, 'scale');

	my $headerValue = '';
	my ($parts, $oldvisu, $savedvisu);

	if ($client->mixerConstant($feature, 'balanced')) {

		$headerValue = sprintf(' (%d)', int((($featureValue - $mid) * $scale) + 0.5));

	} elsif ($feature eq 'volume') {

		# Negative value = muting
		if ($featureValue < 0) {
			$featureValue = 0;
		}

		if (my $linefunc = $client->customVolumeLines()) {

			$parts = &$linefunc($client, { value => $featureValue });

		} else {
			
			$headerValue = $client->volumeString($featureValue);

		}

	} else {

		$headerValue = sprintf(' (%d)', int(($featureValue * $scale) + 0.5));
	}

	if ($feature eq 'pitch') {

		$headerValue .= '%';
	}

	my $featureHeader = join('', $client->string(uc($feature)), $headerValue);

	if (blessed($client->display) =~ /Squeezebox2|Boom/) {
		# XXXX hack attack: turn off visualizer when showing volume, etc.		
		$oldvisu = $client->modeParam('visu');
		$savedvisu = 1;
		$client->modeParam('visu', [0]);
	}

	$parts ||= Slim::Buttons::Input::Bar::lines($client, {
		'value'     => $featureValue,
		'header'    => $featureHeader,
		'min'       => $client->mixerConstant($feature, 'min'),
		'mid'       => $mid,
		'max'       => $client->mixerConstant($feature, 'max'),
		'noOverlay' => 1,
	});

	# suppress display forwarding
	$parts->{'jive'} = $parts->{'cli'} = undef;

	$client->display->showBriefly($parts, { 'name' => 'mixer' } );

	# Turn the visualizer back to it's old value.
	if ($savedvisu) {
		$client->modeParam('visu', $oldvisu);
	}
}

# Intended to be overridden by sub-classes who know better
sub packetLatency {
	return $prefs->client(shift)->get('packetLatency') / 1000;
}

use constant JIFFIES_OFFSET_TRACKING_LIST_SIZE => 50;	# Must be this big for large forward jumps
use constant JIFFIES_OFFSET_TRACKING_LIST_MIN  => 10;	# Must be this big to use at all
use constant JIFFIES_EPOCH_MIN_ADJUST          => 0.001;
use constant JIFFIES_EPOCH_MAX_ADJUST          => 0.005;

sub trackJiffiesEpoch {
	my ($client, $jiffies, $timestamp) = @_;

	# Note: we do not take the packet latency into account here;
	# see jiffiesToTimestamp

	my $jiffiesTime = $jiffies / $client->ticspersec;
	my $offset      = $timestamp - $jiffiesTime;
	my $epoch       = $client->jiffiesEpoch || 0;

	if ( main::DEBUGLOG && $nplog->is_debug ) {
		$nplog->debug($client->id() . " trackJiffiesEpoch: epoch=$epoch, offset=$offset");
	}

	if (   $offset < $epoch			# simply a better estimate, or
		|| $offset - $epoch > 50	# we have had wrap-around (or first time)
	) {
		if ( main::DEBUGLOG && $synclog->is_debug ) {
			if ( abs($offset - $epoch) > 0.001 ) {
				$synclog->debug( sprintf("%s adjust jiffies epoch %+.3fs", $client->id(), $offset - $epoch) );
			}
		}
		
		$client->jiffiesEpoch($epoch = $offset);	
	}

	my $diff = $offset - $epoch;
	my $jiffiesOffsetList = $client->jiffiesOffsetList();

	unshift @{$jiffiesOffsetList}, $diff;
	pop @{$jiffiesOffsetList}
		if (@{$jiffiesOffsetList} > JIFFIES_OFFSET_TRACKING_LIST_SIZE);

	if (   $diff > 0.001
		&& (@{$jiffiesOffsetList} >= JIFFIES_OFFSET_TRACKING_LIST_MIN)
	) {
		my $min_diff = Slim::Utils::Misc::min($jiffiesOffsetList);
		if ( $min_diff > JIFFIES_EPOCH_MIN_ADJUST ) {
			
			# We only make jumps larger than JIFFIES_EPOCH_MAX_ADJUST if we have a full sequence of offsets.
			if ( $min_diff > JIFFIES_EPOCH_MAX_ADJUST  && @{$jiffiesOffsetList} < JIFFIES_OFFSET_TRACKING_LIST_SIZE ) {
				# wait until we have a full list
				return $diff;
			}
			if ( main::DEBUGLOG && $synclog->is_debug ) {
				$synclog->debug( sprintf("%s adjust jiffies epoch +%.3fs", $client->id(), $min_diff) );
			}
			$client->jiffiesEpoch($epoch += $min_diff);
			$diff -= $min_diff;
			@{$jiffiesOffsetList} = ();	# start tracking again
		}
	}
	return $diff;
}

sub jiffiesToTimestamp {
	my ($client, $jiffies) = @_;

	# Note: we only take the packet latency into account here,
	# rather than in trackJiffiesEpoch(), so that a bad calculated latency
	# (which presumably would be transient) does not permanently effect
	# our idea of the jiffies-epoch.
	
	return $client->jiffiesEpoch + $jiffies / $client->ticspersec - $client->packetLatency();
}
	
use constant PLAY_POINT_LIST_SIZE		=> 8;		# how many to keep
use constant MAX_STARTTIME_VARIATION	=> 0.015;	# latest apparent-stream-start-time estimate
													# must be this close to the average
sub publishPlayPoint {
	my ( $client, $statusTime, $apparentStreamStartTime, $cutoffTime ) = @_;
	
	my $playPoints = $client->playPoints();
	$client->playPoints($playPoints = []) if (!defined($playPoints));
	
	unshift(@{$playPoints}, [$statusTime, $apparentStreamStartTime]);

	# remove all old and excessive play-points
	pop @{$playPoints} if ( @{$playPoints} > PLAY_POINT_LIST_SIZE );
	while( $cutoffTime && @{$playPoints} && $playPoints->[-1][0] < $cutoffTime ) {
		pop @{$playPoints};
	}

	# Do we have a consistent set of playPoints so that we can publish one?
	if ( @{$playPoints} == PLAY_POINT_LIST_SIZE ) {
		my $meanStartTime = 0;
		foreach my $point ( @{$playPoints} ) {
			$meanStartTime += $point->[1];
		}
		$meanStartTime /= @{$playPoints};

		if ( abs($apparentStreamStartTime - $meanStartTime) < MAX_STARTTIME_VARIATION ) {
			# Ok, good enough, publish it!
			$client->playPoint( [$statusTime, $meanStartTime] );
			
			if ( 0 && $synclog->is_debug ) {
				main::DEBUGLOG && $synclog->debug(
					$client->id()
					. " publishPlayPoint: $meanStartTime @ $statusTime"
				);
			}
		}
	}
}

sub isReadyToStream {
	my $client = shift; # ignore $song, $playingSong
	return $client->readyToStream();
}

sub rebuffer {
	my ($client) = @_;
	my $threshold = 80 * 1024; # 5 seconds of 128k
	my $outputThreshold = 5 * 44100 * 2 * 4; # 5 seconds, 2 channels, 32bits/sample

	my $song = $client->playingSong() || return;
	my $url = $song->currentTrack()->url;

	my $handler = $song->currentTrackHandler();
	my $remoteMeta = $handler->can('getMetadataFor') ? $handler->getMetadataFor($client, $url) : {};
	my $title = Slim::Music::Info::getCurrentTitle($client, $url, 0, $remoteMeta) || Slim::Music::Info::title($url);
	my $cover = $remoteMeta->{cover} || $remoteMeta->{icon} || '/music/' . $song->currentTrack()->coverid . '/cover.jpg';
	
	if ( my $bitrate = $song->streambitrate() ) {
		$threshold = 5 * ( int($bitrate / 8) );
	}
	
	# We could calculate a more-accurate outputThreshold, but it really is not worth it
	
	if ($threshold > $client->bufferSize() - 4000) {
		$threshold = $client->bufferSize() - 4000;	# cheating , really for SliMP3s
	}
	
	# We restart playback based on the decode buffer, 
	# as the output buffer is not updated in pause mode.
	my $fullness = $client->bufferFullness();
	
	main::INFOLOG && $log->info( "Rebuffering: $fullness / $threshold" );
	
	$client->bufferReady(0);
	
	$client->bufferStarted( Time::HiRes::time() ); # track when we started rebuffering
	Slim::Utils::Timers::killTimers( $client, \&_buffering );
	Slim::Utils::Timers::setTimer(
		$client,
		Time::HiRes::time() + 0.125,
		\&_buffering,
		{song => $song, threshold => $threshold, outputThreshold => $outputThreshold, title => $title, cover => $cover}
	);
}

sub buffering {
	my ($client, $bufferThreshold, $outputThreshold) = @_;
	
	my $song = $client->streamingSong();
	my $url = $song->currentTrack()->url;

	my $handler = $song->currentTrackHandler();
	my $remoteMeta = $handler->can('getMetadataFor') ? $handler->getMetadataFor($client, $url) : {};
	my $title = Slim::Music::Info::getCurrentTitle($client, $url, 0, $remoteMeta) || Slim::Music::Info::title($url);
	my $cover = $remoteMeta->{cover} || $remoteMeta->{icon} || '/music/' . $song->currentTrack()->coverid . '/cover.jpg';
	
	# Set a timer for feedback during buffering
	$client->bufferStarted( Time::HiRes::time() ); # track when we started buffering
	Slim::Utils::Timers::killTimers( $client, \&_buffering );
	Slim::Utils::Timers::setTimer(
		$client,
		Time::HiRes::time() + 0.125,
		\&_buffering,
		{song => $song, threshold => $bufferThreshold, outputThreshold => $outputThreshold, title => $title, cover => $cover}
	);
}

sub _buffering {
	my ( $client, $args ) = @_;
	
	my $log = logger('player.source');
	
	my $song = $args->{song};
	my $threshold = $args->{'threshold'};
	my $outputThreshold = $args->{'outputThreshold'};
	
	my $controller = $client->controller();
	my $buffering = $controller->buffering();
	my $syncWait = $controller->isWaitingToSync();
	
	# If the track has started, stop displaying buffering status
	if ( (!$buffering && !$syncWait)
		|| !$client->power) # Bug 6549, if the user powers off, stop rebuffering
	{
		$client->display->updateMode(0);
		$client->update();
		$client->bufferStarted(0); # marker that we are no longer rebuffering
		return;
	}
	
	my $handler = $song->currentTrackHandler();
	my $suppressPlayersMessage = $handler->can('suppressPlayersMessage') || sub {};

	my ($line1, $line2, $status);
	
	# Bug 6712, give up after 30s
	if ( $buffering == 2 && (time() > $client->bufferStarted() + 30) ) {
		# Only show rebuffering failed status if no user activity on player or we're on the Now Playing screen
		my $nowPlaying = Slim::Buttons::Playlist::showingNowPlaying($client);
		my $lastIR     = Slim::Hardware::IR::lastIRTime($client) || 0;

		if ( $nowPlaying || $lastIR < $client->bufferStarted() ) {
		
			my $failedString = $client->string('REBUFFERING_FAILED');
			$line1 = $client->string('NOW_PLAYING') . ': ' . $failedString; 
			if ( $client->linesPerScreen() == 1 ) { 	 
				$line2 = $failedString; 	 
			} else {
				$line2 = $args->{'title'};
			}

			$client->showBriefly( {
				line => [ $line1, $line2 ],
				jive => { 
					type => 'popupplay', 
					text => [ $failedString ], 
					'icon-id' => Slim::Web::ImageProxy::proxiedImage($args->{'cover'})
				},
				cli  => undef,
			}, { duration => 2 } );
		}
		
		$client->bufferStarted(0);
		$controller->jumpToTime($controller->playingSongElapsed(), 1); # restart
		return;
	}
	
	my $fullness = $client->bufferFullness();
	my $outputFullness = $client->outputBufferFullness();
	
	main::INFOLOG &&                                        $log->info("Buffering... $fullness / $threshold");
	main::INFOLOG && $outputThreshold && $outputFullness && $log->info("  +output... $outputFullness / $outputThreshold");
	
	# Bug 1827, display better buffering feedback while we wait for data
	my $fraction = $fullness / $threshold;
	
	if ($outputThreshold && $outputFullness) {
		$fraction += $outputFullness / $outputThreshold;
	}
	
	my $string;
	my $percent = sprintf "%d", $fraction * 100;
	
	my $stillBuffering = ( $percent < 100 ) ? 1 : 0;
	
	# TODO - add output-buffer calculations
	
	if (!$stillBuffering && $buffering == 2 && $client->bufferStarted()) {
		$client->bufferReady(1);
		$controller->playerBufferReady($client);
		$client->bufferStarted(0); # marker that we are no longer rebuffering
	}

	if ( $percent == 0 && $buffering == 1) {
		$string = 'CONNECTING_FOR';
		$status = $client->string($string);
  		if ( $client->linesPerScreen() == 1 ) {
			$line2 = $status;
		} else {
			$line1 = $client->string('NOW_PLAYING') . " ($status)";
			$line2 = $args->{'title'};
		}
	}
	else {

		# When synced, a player may have to wait longer than the buffering time
		if ( $syncWait && $percent >= 100 ) {
			$string = 'WAITING_TO_SYNC';
			$status = $client->string($string);
			$stillBuffering = 1;
		}
		else {
			if ( $percent > 100 ) {
				$percent = 99;
			}
			
			$string = $buffering < 2 ? 'BUFFERING' : 'REBUFFERING';
			$status = $client->string($string) . ' ' . $percent . '%';
		}

  		if ( $client->linesPerScreen() == 1 ) {
			$line2 = $status;
		} else {
			$line1 = $client->string('NOW_PLAYING') . ' (' . $status . ')';
			$line2 = $args->{'title'};
		}
	}
	
	# Only show buffering status if no user activity on player or we're on the Now Playing screen
	my $nowPlaying = Slim::Buttons::Playlist::showingNowPlaying($client);
	my $lastIR     = Slim::Hardware::IR::lastIRTime($client) || 0;
	my $screen     = Slim::Buttons::Common::msgOnScreen2($client) ? 'screen2' : 'screen1';
	
	if ( ($nowPlaying || $lastIR < $client->bufferStarted()) ) {

		if ( !$suppressPlayersMessage->($handler, $client, $song, $string) ) {
			$client->display->updateMode(0);
			$client->showBriefly({
				$screen => { line => [ $line1, $line2 ] },
				# Bug 17937: leave the title alone (empty string is noticed in SP) for these sorts of message
				jive => { type => 'song', text => [ $status, ''], duration => 500 },
				cli  => undef,
			}, { duration => 1, block => 1 });
		}
	}
	
	# Call again unless we've reached the threshold
	if ( $stillBuffering ) {
		Slim::Utils::Timers::setTimer(
			$client,
			Time::HiRes::time() + 0.300, # was .125 but too fast sometimes in wireless settings
			\&_buffering,
			$args,
		);
		
		$client->requestStatus(); # so we get another up date soon
	}
	else {
		# All done buffering, refresh the screen
		$client->display->updateMode(0);
		$client->update;
		$client->bufferStarted(0);
	}
}

sub resume {
	my $client = shift;
	Slim::Utils::Timers::killTimers($client, \&_buffering);
	$client->SUPER::resume();
	return 1;
}

sub pause {
	my $client = shift;
	Slim::Utils::Timers::killTimers($client, \&_buffering);
	$client->SUPER::pause();
	return 1;
}

sub stop {
	my $client = shift;
	Slim::Utils::Timers::killTimers($client, \&_buffering);
}

sub flush {
	my $client = shift;
	Slim::Utils::Timers::killTimers($client, \&_buffering);
	$client->SUPER::flush();
}


1;

__END__
