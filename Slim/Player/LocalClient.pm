package Slim::Player::Client;

# $Id$

# Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# XXX
# This is incomplete
# It needs to be separated into methods that are called at the package level
# (Slim::Player::Client) and those that are called via a Client object.
# It should be made a subclass of Slim::Player::Client and should handle all
# accessor state variables, their validation, etc. As part of this,
# Slim::Player::Player and Slim::Player::HTTP should then be subclasses
# of this class (Slim::Player::LocalClient).

use strict;

use base qw(Slim::Utils::Accessor);

use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Network;
use Slim::Utils::Prefs;
use Slim::Utils::Strings;
use Slim::Player::LocalPlaylist;
use Slim::Player::Sync;

my $prefs = preferences('server');

$prefs->setValidate({
	validator => sub {
		my ($pref, $new, $params, $old, $client) = @_;
		
		return $new <= $client->mixerConstant($pref, 'max') 
		    && $new >= $client->mixerConstant($pref, 'min');
	} 
}, qw(bass treble));

$prefs->setChange( sub {
	my $value  = $_[1];
	my $client = $_[2] || return;
	Slim::Control::LocalPlayers::Jive::repeatSettings($client);
}, 'repeat' );

$prefs->setChange( sub {
	my $value  = $_[1];
	my $client = $_[2] || return;
	Slim::Control::LocalPlayers::Jive::shuffleSettings($client);
}, 'shuffle' );

$prefs->setChange( sub {
	my $value  = $_[1];
	my $client = $_[2] || return;
	Slim::Utils::Alarm->alarmsEnabledChanged($client);
}, 'alarmsEnabled' );

$prefs->setChange( sub {
	my $value  = $_[1];
	my $client = $_[2] || return;
	Slim::Utils::Alarm->defaultVolumeChanged($client);
}, 'alarmDefaultVolume' );


###############################################################
#
# Methods only relevant for locally-attached players from here on

sub getPlaylist {
	my $client = shift->master();
	
	if (my $p = $client->_playlist) {return $p;}
	
	# XXX - May want to move this to StreamingController
	return $client->_playlist(Slim::Player::LocalPlaylist->new($client));
}


sub startup {
	my $client = shift;
	my $syncgroupid = shift;
	
	Slim::Player::Sync::restoreSync($client, $syncgroupid);
	
	# restore the old playlist
	Slim::Player::Playlist::loadClientPlaylist($client, \&initial_add_done)
}

sub initial_add_done {
	my ($client, $currsong) = @_;

	$client->debug("initial_add_done()");

	return unless defined($currsong);

	my $shuffleType = Slim::Player::Playlist::shuffleType($client);

	$client->debug("shuffleType is: $shuffleType");

	if ($shuffleType eq 'track') {

		my $i = 0;

		foreach my $song (@{Slim::Player::Playlist::shuffleList($client)}) {

			if ($song == $currsong) {
				$client->execute(['playlist', 'move', $i, 0]);
				last;
			}

			$i++;
		}
		
		$currsong = 0;
		
		$client->controller()->resetSongqueue($currsong);
		
	} elsif ($shuffleType eq 'album') {

		# reshuffle set this properly, for album shuffle
		# no need to move the streamingSongIndex

	} else {

		if (Slim::Player::Playlist::count($client) == 0) {

			$currsong = 0;

		} elsif ($currsong >= Slim::Player::Playlist::count($client)) {

			$currsong = Slim::Player::Playlist::count($client) - 1;
		}

		$client->controller()->resetSongqueue($currsong);
	}

	$prefs->client($client)->set('currentSong', $currsong);

	if ($prefs->client($client)->get('autoPlay') || $prefs->get('autoPlay')) {

		$client->execute(['play']);
	}
}

sub needsUpgrade {
	return 0;
}

sub signalStrength {
	return undef;
}

sub voltage {
	return undef;
}

sub hasDigitalOut() { return 0; }
sub hasHeadSubOut() { return 0; }
sub hasVolumeControl() { return 0; }
sub hasEffectsLoop() { return 0; }
sub hasPreAmp() { return 0; }
sub hasExternalClock() { return 0; }
sub hasAesbeu() { return 0; }
sub hasPowerControl() { return 0; }
sub hasDisableDac() { return 0; }
sub hasPolarityInversion() { return 0; }
sub hasFrontPanel() { return 0; }
sub hasServ { return 0; }
sub hasRTCAlarm { return 0; }
sub hasLineIn { return 0; }
sub hasIR { return 0; }
sub hasOutputChannels { 0 }
sub hasRolloff { 0 }

sub maxBrightness() { return undef; }

sub maxVolume { return 100; }
sub minVolume {	return 100; }

sub maxPitch {	return 100; }
sub minPitch {	return 100; }

sub maxTreble {	return 50; }
sub minTreble {	return 50; }

sub maxBass {	return 50; }
sub minBass {	return 50; }

sub maxXL {	return 0; }
sub minXL {	return 0; }

sub canDirectStream { return 0; }
sub canLoop { return 0; }
sub canDoReplayGain { return 0; }

sub canPowerOff { return 1; }

=head2 mixerConstant( $client, $feature, $aspect )

Returns the requested aspect of a given mixer feature.

Supported features: volume, pitch, bass & treble.

Supported aspects:

=over 4

=item * min

The minimum setting of the feature.

=back

=over 4

=item * max

The maximum setting of the feature.

=item * mid

The midpoint of the feature, if important.

=item * scale

The multiplier for display of the feature value.

=item * increment

The inverse of scale.

=item * balanced.

Whether to bias the displayed value by the mid value.

=back

TODO allow different player types to have their own scale and increment, when
SB2 has better resolution uncomment the increments below

=cut

sub mixerConstant {
	my ($client, $feature, $aspect) = @_;
	my ($scale, $increment);

#	if ($client->displayWidth() > 100) {
#		$scale = 1;
#		$increment = 1;
#	} else {
		$increment = 2.5;
		$scale = 0.4;
# 	}

	if ($feature eq 'volume') {

		return $client->maxVolume() if $aspect eq 'max';
		return $client->minVolume() if $aspect eq 'min';
		return $client->minVolume() if $aspect eq 'mid';
		return $scale if $aspect eq 'scale';
		return $increment if $aspect eq 'increment';
		return 0 if $aspect eq 'balanced';

	} elsif ($feature eq 'pitch') {

		return $client->maxPitch() if $aspect eq 'max';
		return $client->minPitch() if $aspect eq 'min';
		return ( ( $client->maxPitch() + $client->minPitch() ) / 2 ) if $aspect eq 'mid';
		return 1 if $aspect eq 'scale';
		return 1 if $aspect eq 'increment';
		return 0 if $aspect eq 'balanced';

	} elsif ($feature eq 'bass') {

		return $client->maxBass() if $aspect eq 'max';
		return $client->minBass() if $aspect eq 'min';
		return ( ( $client->maxBass() + $client->minBass() ) / 2 ) if $aspect eq 'mid';
		return $scale if $aspect eq 'scale';
		return $increment if $aspect eq 'increment';
		return 1 if $aspect eq 'balanced';

	} elsif ($feature eq 'treble') {

		return $client->maxTreble() if $aspect eq 'max';
		return $client->minTreble() if $aspect eq 'min';
		return ( ( $client->maxTreble() + $client->minTreble() ) / 2 ) if $aspect eq 'mid';
		return $scale if $aspect eq 'scale';
		return $increment if $aspect eq 'increment';
		return 1 if $aspect eq 'balanced';
	}

	return undef;
}

=head2 volumeString( $client, $volume )

Returns a pretty string for the current volume value.

On Transporter units, this is in dB, with 100 steps.

Other clients, are in 40 steps.

=cut

sub volumeString {
	my ($client, $volume) = @_;

	my $value = int((($volume / 100) * 40) + 0.5);

	if ($volume <= 0) {

		$value = $client->string('MUTED');
	}

	return " ($value)";
}

sub volume {
	my ($client, $volume, $temp) = @_;

	if (defined($volume)) {

		if ($volume > $client->maxVolume) {
			$volume = $client->maxVolume;
		}

		if ($volume < $client->minVolume && !$prefs->client($client)->get('mute')) {
			$volume = $client->minVolume;
		}

		if ($temp) {

			$client->_tempVolume($volume);

		} else {

			# persist only if $temp not set
			$prefs->client($client)->set('volume', $volume);

			# forget any previous temporary volume
			$client->_tempVolume(undef);
		}
	}

	# return the current volume, whether temporary or persisted
	if (defined $client->tempVolume) {

		return $client->tempVolume;

	} else {

		return $prefs->client($client)->get('volume');
	}
}

# getter only.
# use volume() to set, passing in temp flag
sub tempVolume {
	my $client = shift;
	return $client->_tempVolume;
}

sub treble {
	my ($client, $value) = @_;

	return $client->_mixerPrefs('treble', 'maxTreble', 'minTreble', $value);
}

sub bass {
	my ($client, $value) = @_;

	return $client->_mixerPrefs('bass', 'maxBass', 'minBass', $value);
}

sub pitch {
	my ($client, $value) = @_;

	return $client->_mixerPrefs('pitch', 'maxPitch', 'minPitch', $value);
}

sub stereoXL {
	my ($client, $value) = @_;

	return $client->_mixerPrefs('stereoxl', 'maxXL', 'minXL', $value);
};

sub _mixerPrefs {
	my ($client, $pref, $max, $min, $value) = @_;

	if (defined($value)) {

		if ($value > $client->$max()) {
			$value = $client->$max();
		}

		if ($value < $client->$min()) {
			$value = $client->$min();
		}

		$prefs->client($client)->set($pref, $value);
	}

	return $prefs->client($client)->get($pref);
}

sub pause {
	my $client = shift;
	$client->pauseTime(Time::HiRes::time());
}

sub resume {
	my $client = shift;
	if ($client->pauseTime()) {
		$client->remoteStreamStartTime($client->remoteStreamStartTime() + (Time::HiRes::time() - $client->pauseTime()));
		$client->pauseTime(0);
	}
	$client->pauseTime(undef);
}

=head2 prettySleepTime( $client )

Returns a pretty string for the current sleep time.

Normally we simply return the time in minutes.

For the case of stopping after the current song, 
a friendly string is returned.

=cut

sub prettySleepTime {
	my $client = shift;
	
	
	my $sleeptime = $client->sleepTime() - Time::HiRes::time();
	my $sleepstring = "";
	
	my $dur = $client->controller()->playingSongDuration() || 0;
	my $remaining = 0;
	
	if ($dur) {
		$remaining = $dur - Slim::Player::Source::songTime($client);
	}

	if ($client->sleepTime) {
		
		# check against remaining time to see if sleep time matches within a minute.
		if (int($sleeptime/60 + 0.5) == int($remaining/60 + 0.5)) {
			$sleepstring = $client->string('SLEEPING_AT_END_OF_SONG');
		} else {
			$sleepstring = join(" " ,$client->string('SLEEPING_IN'),int($sleeptime/60 + 0.5),$client->string('MINUTES'));
		}
	}
	
	return $sleepstring;
}

sub flush {}

sub power {}

sub doubleString {}

sub maxTransitionDuration {
	return 0;
}

sub reportsTrackStart {
	return 0;
}

# deprecated in favor of modeParam
sub param {
	my $client = shift;
	my $name   = shift;
	my $value  = shift;

	logBacktrace("Use of \$client->param is deprecated, use \$client->modeParam instead");

	my $mode   = $client->modeParameterStack->[-1] || return undef;

	if (defined $value) {

		$mode->{$name} = $value;

	} else {

		return $mode->{$name};
	}
}

# this is a replacement for param that allows you to pass undef to clear a parameter
# Looks a bit ugly but this is to improve performance and avoid an accessor call
sub modeParam {
	my $mode = $_[0]->[ $Slim::Player::Client::modeParameterStackIndex ]->[-1] || return undef;

	@_ > 2 ? ( $mode->{ $_[1] } = $_[2] ) : $mode->{ $_[1] };
}

sub modeParams {
	my $client = shift;
	
	@_ ? $client->modeParameterStack()->[-1] = shift : $client->modeParameterStack()->[-1];
}

sub getMode {
	my $client = shift;
	return $client->modeStack->[-1];
}

sub requestStatus {
}

=head2 contentTypeSupported( $client, $type )

Returns true if the player natively supports the content type.

Returns false otherwise.

=cut

sub contentTypeSupported {
	my $client = shift;
	my $type = shift;
	foreach my $format ($client->formats()) {
		if ($type && $type eq $format) {
			return 1;
		}
	}
	return 0;
}

=head2 shouldLoop( $client )

Tells the client to loop on the track in the player itself. Only valid for
Alarms and other short audio segments. Squeezebox v2, v3 & Transporter.

=cut

sub shouldLoop {
	my $client = shift;

	return 0;
}

=head2 streamingProgressBar( $client, \%args )

Given bitrate and content-length of a stream, display a progress bar

Valid arguments are:

=over 4

=item * url

Required.

=item * duration

Specified directly - IE: from a plugin.

=back

=over 4

=item * bitrate

=item * length

Duration can be calculatd from bitrate + length.

=back

=cut

sub streamingProgressBar {
	my ( $client, $args ) = @_;

	my $log = logger('player.streaming');

	my $url = $args->{'url'};
	
	# Duration specified directly (i.e. from a plugin)
	my $duration = $args->{'duration'};
	
	# Duration can be calculated from bitrate + length
	my $bitrate = $args->{'bitrate'};
	my $length  = $args->{'length'};
	
	if (main::INFOLOG && $log->is_info) {
		$log->info(sprintf("url=%s, duration=%s, bitrate=%s, contentLength=%s",
			$url,
			(defined($duration) ? $duration : 'undef'),
			(defined($bitrate) ? $bitrate : 'undef'),
			(defined($length) ? $length : 'undef'))
		);
	}
	
	my $secs;
	
	if ( $duration ) {
		$secs = $duration;
	}
	elsif ( $bitrate > 0 && $length > 0 ) {
		$secs = ( $length * 8 ) / $bitrate;
	}
	else {
		return;
	}
	
	my %cacheEntry = (
		'SECS' => $secs,
	);
	
	Slim::Music::Info::updateCacheEntry( $url, \%cacheEntry );
	
	Slim::Music::Info::setDuration( $url, $secs );
	
	# Set the duration so the progress bar appears
	if ( my $song = $client->streamingSong()) {

		$song->duration($secs);

		if ( main::INFOLOG && $log->is_info ) {
			if ( $duration ) {

				$log->info("Duration of stream set to $duration seconds");

			} else {

				$log->info("Duration of stream set to $secs seconds based on length of $length and bitrate of $bitrate");
			}
		}
	} else {
		main::INFOLOG && $log->info("not setting duration as no current song!");
	}
}

sub currentsongqueue {return $_[0]->controller()->songqueue();}

sub epochirtime {
	my $client = shift;

	if ( @_ ) {
		# Also update lastActivityTime on IR events
		my $val = shift;

		$client->lastActivityTime($val);
		$client->_epochirtime($val);
	}
	
	return $client->_epochirtime;
}

sub currentplayingsong {
	my $client = shift->master();

	return $client->_currentplayingsong(@_);
}

sub currentPlaylistUpdateTime {
	# This needs to be the same for all synced clients
	my $client = shift->master();

	if (@_) {
		my $time = shift;
		$client->_currentPlaylistUpdateTime($time);
		# update playlistChangeTime
		$client->currentPlaylistChangeTime($time);
		return;
	}

	return $client->_currentPlaylistUpdateTime;
}

sub currentPlaylist {
	my $client = shift->master();

	if (@_) {
		$client->_currentPlaylist(shift);
		return;
	}

	my $playlist = $client->_currentPlaylist;

	# Force the caller to do the right thing.
	if (ref($playlist)) {
		return $playlist;
	}

	return;
}

sub currentPlaylistChangeTime {
	# This needs to be the same for all synced clients
	my $client = shift->master();

	$client->_currentPlaylistChangeTime(@_);
}

sub playPoint {
	my $client = shift;
	if (@_) {
		my $new = $client->_playPoint(shift);
		$client->playPoints(undef) if (!defined($new));
		return $new;
	} else {
		return $client->_playPoint;
	}
}

sub nextChunk {
	return Slim::Player::Source::nextChunk(@_);
}

sub closeStream { }

sub isBufferReady {
	my $client = shift;
	return $client->bufferReady();
}

=head2 setPreset( $client, \%args )

Set a preset for this player.  Arguments:

=over 4

=item slot 

Which preset to set.  Valid values are from 1-10.

=item URL

URL (remote or local)

=item text

The preset title.

=item type

The type (audio, link, playlist, etc)

=item parser

Optional.  XMLBrowser parser.

=back

=cut

sub setPreset {
	my ( $client, $args ) = @_;
	
	return unless $args->{slot} && $args->{URL} && $args->{text};
	
	my $preset = {
		URL  => $args->{URL},
		text => $args->{text},
		type => $args->{type} || 'audio',
	};
	
	$preset->{parser} = $args->{parser} if $args->{parser};		
	
	my $cprefs = $prefs->client($client);
	my $presets = $cprefs->get('presets');
	$presets->[ $args->{slot} - 1 ] = $preset;
	$cprefs->set( presets => $presets );
}

##############################################################
# Methods to delegate to our StreamingController.
# TODO - review to see which are still necessary.

sub master {return $_[0]->controller()->master();}

sub streamingSong {return $_[0]->controller()->streamingSong();}
sub playingSong {return $_[0]->controller()->playingSong();}
	
sub isPlaying {return $_[0]->controller()->isPlaying($_[1]);}
sub isPaused {return $_[0]->controller()->isPaused();}
sub isStopped {return $_[0]->controller()->isStopped();}
sub isRetrying {return $_[0]->controller()->isRetrying();}

sub currentTrackForUrl {
	my ($client, $url) = @_;
	
	my $song = $client->controller()->currentSongForUrl($url);
	if ( $song ) {
		return $song->currentTrack();
	}
}

sub currentSongForUrl {
	my ($client, $url) = @_;
	
	return $client->controller()->currentSongForUrl($url);
}

# These probably belong in Player.pm - (most) should not be called for non-players

sub syncGroupActiveMembers {return $_[0]->controller()->activePlayers();}

sub isSynced {
	my ($client, $active) = @_;
	return ($active 
				? $client->controller()->activePlayers() 
				: $client->controller()->allPlayers()
			) > 1;
}

sub isSyncedWith {return $_[0]->controller() == $_[1]->controller();}

sub syncedWith {
	my $client  = shift || return undef;
	my $exclude = shift;

	my @slaves;
	foreach my $player ($client->controller()->allPlayers()) {
			next if ($exclude && $exclude == $player);
			push (@slaves, $player) unless $client == $player;
	}

	return @slaves;
}

sub syncedWithNames {
	my $client        = shift || return undef;
	my $includeClient = shift || 0;

	return undef unless isSynced($client);

	my @syncList = syncedWith($client);
	# syncedWith will not return $client in the list, so add it if $includeClient
	push @syncList, $client if $includeClient;

	return join(' & ', map { $_->name || $_->id } @syncList);

}
	
sub maxSupportedSamplerate {
	return 48000;
}

sub canDecodeRhapsody { 0 };

sub canImmediateCrossfade { 0 };

sub proxyAddress { undef };

sub hidden { 0 }

sub hasScrolling { 0 }

sub apps {
	my $client = shift;
	
	my %clientApps = %{$prefs->client($client)->get('apps') || {}};

	if (my $nonSNApps = Slim::Plugin::Base->nonSNApps) {
		for my $plugin (@$nonSNApps) {
			if ($plugin->can('tag')) {
				$clientApps{ $plugin->tag } = { plugin => $plugin };
			}
		}
	}

	return \%clientApps;
}

sub isAppEnabled {
	my ( $client, $app ) = @_;
	
	if ( grep { $_ eq lc($app) } keys %{ $client->apps } ) {
		return 1;
	}
	
	return;
}



1;
