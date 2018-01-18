package Slim::Player::Client;

# $Id$

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

use strict;

use base qw(Slim::Utils::Accessor);

use Scalar::Util qw(blessed);
use Storable qw(nfreeze);

use Slim::Player::Sync;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Network;
use Slim::Utils::Prefs;
use Slim::Utils::Strings;
use Slim::Utils::Timers;
use Slim::Player::StreamingController;

if ( !main::SCANNER ) {
	require Slim::Control::Request;
	require Slim::Web::HTTP;
}

my $prefs = preferences('server');

our $defaultPrefs = {
	'maxBitrate'           => undef, # will be set by the client device OR default to server pref when accessed.
	# Alarm prefs
	'alarms'               => {},	
	'alarmsEnabled'        => 1,
	'alarmDefaultVolume'   => 50, # if this is changed, also change the hardcoded value in the prefs migration code in Prefs.pm
	'alarmSnoozeSeconds'   => 540, # 9 minutes
	'alarmfadeseconds'     => 1, # whether to fade in the volume for alarms.  Boolean only, despite the name! 
	'alarmTimeoutSeconds'  => 3600, # time after which to automatically end an alarm.  false to never end

	'lameQuality'          => 9,
	'playername'           => \&_makeDefaultName,
	'repeat'               => 0,
	'shuffle'              => 0,
	'titleFormat'          => [5, 1, 3, 6, 0],
	'titleFormatCurr'      => 4,
	'presets'              => [],
};

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
	Slim::Control::Jive::repeatSettings($client);
}, 'repeat' );

$prefs->setChange( sub {
	my $value  = $_[1];
	my $client = $_[2] || return;
	Slim::Control::Jive::shuffleSettings($client);
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

# deprecated, use $client->maxVolume
our $maxVolume = 100;

# This is a hash of clientState structs, indexed by the IP:PORT of the client
# Use the access functions.
our %clientHash = ();

my $modeParameterStackIndex;

use constant KNOB_NOWRAP => 0x01;
use constant KNOB_NOACCELERATION => 0x02;

{
	__PACKAGE__->mk_accessor('ro', qw(
								id deviceid uuid
							));
	__PACKAGE__->mk_accessor('rw', qw(
								revision _needsUpgrade isUpgrading
								macaddress paddr udpsock tcpsock
								irRefTime irRefTimeStored ircodes irmaps lastirtime lastircode lastircodebytes lastirbutton
								startirhold irtimediff irrepeattime irenable _epochirtime lastActivityTime
								knobPos knobTime knobSync
								sequenceNumber
								controllerSequenceId controllerSequenceNumber
								controller
								bufferReady readyToStream connecting streamStartTimestamp
								streamformat streamingsocket remoteStreamStartTime
								trackStartTime outputBufferFullness bytesReceived songBytes pauseTime
								bytesReceivedOffset streamBytes songElapsedSeconds bufferSize bufferStarted
								streamReadableCallback
								_currentplayingsong
								directBody
								startupPlaylistLoading currentPlaylistModified currentPlaylistRender
								_currentPlaylist _currentPlaylistUpdateTime _currentPlaylistChangeTime
								display lines customVolumeLines customPlaylistLines lines2periodic periodicUpdateTime
								blocklines suppressStatus
								curDepth lastLetterIndex lastLetterDigit lastLetterTime lastDigitIndex lastDigitTime searchFor
								syncSelection _playPoint playPoints
								jiffiesEpoch jiffiesOffsetList
								_tempVolume musicInfoTextCache metaTitle languageOverride controlledBy controllerUA password currentSleepTime
								sleepTime pendingPrefChanges _pluginData
								alarmData knobData
								modeStack modeParameterStack playlist chunks
								shufflelist shuffleInhibit syncSelections searchTerm
								updatePending httpState
								disconnected
							));
	__PACKAGE__->mk_accessor('hash', qw(
								curSelection lastID3Selection
							));
							
	# modeParameterStack is called a lot, cache the index to avoid many accessor calls
	$modeParameterStackIndex = __PACKAGE__->_slot('modeParameterStack');
}

=head1 NAME

Slim::Player::Client

=head1 DESCRIPTION

The following object contains all the state that we keep about each player.

=head1 METHODS

=cut

sub new {
	my ($class, $id, $paddr, $rev, $s, $deviceid, $uuid) = @_;

	my $client = $class->SUPER::new;

	main::INFOLOG && logger('network.protocol')->info("New client connected: $id");

	assert(!defined(getClient($id)));

	# Ignore UUID if all zeros or many zeroes (bug 6899)
	if ( defined $uuid && $uuid =~ /0000000000/ ) {
		$uuid = undef;
	}
	
	$client->init_accessor(

		# device identify
		id                      => $id,
		deviceid                => $deviceid,
		uuid                    => $uuid,

		# upgrade management
		revision                => $rev,
		_needsUpgrade           => undef,
		isUpgrading             => 0,

		# network state
		macaddress              => undef,
		paddr                   => $paddr,
		udpsock                 => undef,
		tcpsock                 => undef,

		# ir / knob state
		ircodes                 => undef,
		irmaps                  => undef,
		irRefTime               => undef,
		irRefTimeStored         => undef,
		lastirtime              => 0,
		lastircode              => 0,
		lastircodebytes         => 0,
		lastirbutton            => undef,
		startirhold             => 0,
		irtimediff              => 0,
		irrepeattime            => 0,
		irenable                => 1,
		_epochirtime            => Time::HiRes::time(),
		lastActivityTime        => 0,                   #  last time this client performed some action (IR, CLI, web)
		knobPos                 => undef,
		knobTime                => undef,
		knobSync                => 0,

		#The sequenceNumber is sent by the player for certain locally maintained player parameters like volume and power.
		#It is used to allow the player to act as the master for the locally maintained parameter.
		sequenceNumber          => 0,

		# The (controllerSequenceId, controllerSequenceNumber) tuple is used to enable synchronization of commands 
		# sent to the player via the server and via an additional, out-of-band mechanism (currently UDAP).
		# It is used to enable the player to discard duplicate commands received via both channels.
		controllerSequenceId    => undef,
		controllerSequenceNumber=> undef,

		# streaming control
		controller              => undef,
		bufferReady             => 0,
		readyToStream           => 1, 
		streamStartTimestamp	=> undef,

		# streaming state
		streamformat            => undef,
		streamingsocket         => undef,
		remoteStreamStartTime   => 0,
		trackStartTime          => 0,
		outputBufferFullness    => undef,
		bytesReceived           => 0,
		songBytes               => 0,
		pauseTime               => 0,
		bytesReceivedOffset     => 0,
		streamBytes             => 0,
		songElapsedSeconds      => undef,
		bufferSize              => 0,
		directBody              => undef,
		chunks                  => [],
		bufferStarted           => 0,                  # when we started buffering/rebuffering
		streamReadableCallback  => undef,

		_currentplayingsong     => '',                 # FIXME - is this used ????

		# playlist state
		playlist                => [],
		shufflelist             => [],
		shuffleInhibit          => undef,
		startupPlaylistLoading  => undef,
		_currentPlaylist        => undef,
		currentPlaylistModified => undef,
		currentPlaylistRender   => undef,
		_currentPlaylistUpdateTime => Time::HiRes::time(), # only changes to the playlist
		_currentPlaylistChangeTime => undef,               # updated on song changes
		
		# display state
		display                 => undef,
		lines                   => undef,
		customVolumeLines       => undef,
	    customPlaylistLines     => undef,
		lines2periodic          => undef,
		periodicUpdateTime      => 0,
		blocklines              => undef,
		suppressStatus          => undef,

		# button mode state
		modeStack               => [],
		modeParameterStack      => [],
		curDepth                => undef,
		curSelection            => {},
		lastLetterIndex         => 0,
		lastLetterDigit         => '',
		lastLetterTime          => 0,
		lastDigitIndex          => 0,
		lastDigitTime           => 0,
		searchFor               => undef,
		searchTerm              => [],
		lastID3Selection        => {},

		# sync state
		syncSelection           => undef,
		syncSelections          => [],
		_playPoint              => undef,              # (timeStamp, apparentStartTime) tuple
		playPoints              => undef,              # set of (timeStamp, apparentStartTime) tuples to determine consistency
		jiffiesEpoch            => undef,
		jiffiesOffsetList       => [],                 # array tracking the relative deviations relative to our clock
		
		# alarm state
		alarmData		=> {},			# Stored alarm data for this client.  Private.
		
		# Knob data
		knobData		=> {},			# Stored knob data for this client

		# other
		_tempVolume             => undef,
		musicInfoTextCache      => undef,
		metaTitle               => undef,
		languageOverride        => undef,
		controlledBy            => undef,
		controllerUA            => undef,
		password                => undef,
		currentSleepTime        => 0,
		sleepTime               => 0,
		pendingPrefChanges      => {},
		_pluginData             => {},
		updatePending           => 0,
		disconnected            => 0,
	
	);
	
	$clientHash{$id} = $client;

	$client->controller(Slim::Player::StreamingController->new($client));

	if (!main::SCANNER) {	
		Slim::Control::Request::notifyFromArray($client, ['client', 'new']);
	}

	return $client;
}

sub init {
	my $client = shift;

	$client->initPrefs();

	# init display including setting any display specific preferences to default
	if ($client->display) {
		$client->display->init();
	}

	Slim::Utils::Alarm->loadAlarms($client);
}

sub initPrefs {
	my $client = shift;

	# make sure any preferences unique to this client may not have set are set to the default
	$prefs->client($client)->init($defaultPrefs);

	# init display including setting any display specific preferences to default
	if ($client->display) {
		$client->display->initPrefs();
	}
}


=head1 FUNCTIONS

Accessors for the list of known clients. These are functions, and do not need
clients passed. They should be moved to be class methods.

=cut

=head2 clients()

Returns an array of all client objects.

=cut

sub clients {
	return grep { !$_->hidden } values %clientHash;
}

=head2 resetPrefs()

Resets a client's preference object.

=cut

sub resetPrefs {
	my $client = shift;

	my $clientPrefs = $prefs->client($client);

	$clientPrefs->remove( keys %{$clientPrefs->all} );

	$client->initPrefs();
}

=head2 clientCount()

Returns the number of known clients.

=cut

sub clientCount {
	return scalar( clients() );
}

=head2 clientIPs()

Return IP info of all clients. This is an ip:port string.

=cut

sub clientIPs {
	return map { $_->ipport } clients();
}

=head2 clientRandom()

Returns a random client object.

=cut

sub clientRandom {

	# the "randomness" of this is limited to the hashing mysteries
	return ( clients() )[0];
}

=head1 CLIENT (INSTANCE) METHODS

=head2 ipport( $client )

Returns a string in the form of 'ip:port'.

=cut

sub ipport {
	my $client = shift;

	assert($client->paddr);

	return Slim::Utils::Network::paddr2ipaddress($client->paddr);
}

=head2 ip( $client )

Returns the client's IP address.

=cut

sub ip {
	return (split(':',shift->ipport))[0];
}

=head2 port( $client )

Returns the client's port.

=cut

sub port {
	return (split(':',shift->ipport))[1];
}

=head2 name( $client, [ $name ] )

Get the playername for the client. Optionally set the playername if $name was passed.

=cut

sub name {
	my $client = shift || return;
	my $name   = shift;

	if (defined $name) {

		$prefs->client($client)->set('playername', $name);

	} else {

		$name = $prefs->client($client)->get('playername');
	}

	return $name;
}

# If this player does not have a name set, then find the first 
# unused name from the sequence ("Name", "Name 2", "Name 3", ...),
# where Name, is the result of the modelName() method. Consider
# all the players ever known to this SC in finding an unused name.
sub _makeDefaultName {
	my $client = shift;

	my $modelName = $client->modelName() || $client->ip;

	my $name;
	my %existingName;

	foreach my $clientPref ( $prefs->allClients ) {
		$existingName{ $clientPref->get('playername') || 'Squeezebox' } = 1;
	}
	
	my $maxIndex = 0;

	do {
		$name = $modelName . ($maxIndex++ ? " $maxIndex" : '');
	} while ($existingName{$name});

	return $name;
}

=head2 debug( $client, @msg )

Log a debug message for this client.

=cut

sub debug {
	my $self = shift;

	main::DEBUGLOG && logger('player')->debug(sprintf("%s : ", $self->name), @_);
}

# If the ID is undef, that means we have a new client.
sub getClient {
	my $id  = shift || return undef;
	my $ret = $clientHash{$id};

	# Try a brute for match for the client.
	if (!defined($ret)) {
   		 for my $value ( values %clientHash ) {
			return $value if $value->ipport eq $id;
			return $value if $value->ip eq $id;
			return $value if $value->name eq $id;
			return $value if $value->id eq $id;
		}
		# none of these matched, so return undef
		return undef;
	}

	return($ret);
}

=head2 forgetClient( $client )

Removes the client from the server's watchlist. The client will not show up in
the WebUI, nor will any it's timers be serviced anymore until it reconnects.

=cut

sub forgetClient {
	my $client = shift;
	
	if ($client) {
		$client->controller()->unsync($client, 'keepSyncGroupId');
		
		$client->display->forgetDisplay();
		
		# Clean up global variables used in various modules
		Slim::Buttons::Common::forgetClient($client);
		Slim::Buttons::Home::forgetClient($client);
		Slim::Buttons::Input::Choice::forgetClient($client);
		Slim::Buttons::Playlist::forgetClient($client);
		Slim::Utils::Alarm->forgetClient($client);
		Slim::Utils::Timers::forgetTimer($client);
		
		if ( !main::SCANNER ) {
			Slim::Web::HTTP::forgetClient($client);
		}
		
		delete $clientHash{ $client->id };
		
		# stop watching this player
		delete $Slim::Networking::Slimproto::heartbeat{ $client->id };
		
		# Bug 15860: Force the connection shut if it is not already
		Slim::Networking::Slimproto::slimproto_close($client->tcpsock()) if defined $client->tcpsock();
	}
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

# Wrapper method so "execute" can be called as an object method on $client.
sub execute {
	my $self = shift;

	return Slim::Control::Request::executeRequest($self, @_);
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
sub hasDigitalIn() { return 0; }
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

sub canHTTPS { return 0; }

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

# stub out display functions, some players may not have them.
sub update {}
sub killAnimation {}
sub endAnimation {}
sub showBriefly {}
sub pushLeft {}
sub pushRight {}
sub doEasterEgg {}
sub displayHeight {}
sub bumpLeft {}
sub bumpRight {}
sub bumpUp {}
sub bumpDown {}
sub scrollBottom {}
sub parseLines {}
sub playingModeOptions {}
sub block{}
sub symbols{}
sub unblock{}
sub updateKnob{}
sub prevline1 {}
sub prevline2 {}
sub currBrightness {}
sub linesPerScreen {}
sub knobListPos {}
sub setPlayerSetting {}
sub modelName {}

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

sub string {
	$_[0]->display && return shift->display->string(@_);
}

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
	my $mode = $_[0]->[ $modeParameterStackIndex ]->[-1] || return undef;

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

sub pluginData {
	my ( $client, $key, $value ) = @_;
	
	my $namespace;
	
	# if called from a plugin, we automatically use the plugin's namespace for keys
	my $package = caller(0);
	
	if ( $package =~ /^(?:Slim::Plugin|Plugins)::(\w+)/ ) {
		$namespace = $1;
	}
	
	if ( $namespace && !defined $key ) {
		return $client->_pluginData->{$namespace};
	}
	
	if ( defined $value ) {
		if ( $namespace ) {
			$client->_pluginData->{$namespace}->{$key} = $value;
		}
		else {
			$client->_pluginData->{$key} = $value;
		}
	}
	
	if ( $namespace ) {
		my $val = $client->_pluginData->{$namespace}->{$key};
		return ( defined $val ) ? $val : undef;
	}
	else {
		return $client->_pluginData;
	}
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
	
# return formatted date/time strings - overwritten in SN to respect timezone
sub timeF {
	return Slim::Utils::DateTime::timeF(
		undef, 
		preferences('plugin.datetime')->client($_[0])->get('timeFormat')
	);
}

sub longDateF {
	return Slim::Utils::DateTime::longDateF(
		undef, 
		preferences('plugin.datetime')->client($_[0])->get('dateFormat')
	);
}

sub shortDateF {
	return Slim::Utils::DateTime::shortDateF();
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

sub revisionNumber { $_[0]->revision }

1;
