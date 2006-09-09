package Slim::Player::Client;

# $Id$

# SlimServer Copyright (c) 2001-2006 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

use strict;
use Scalar::Util qw(blessed);
use Storable qw(nfreeze);

use Slim::Control::Request;
use Slim::Player::Sync;
use Slim::Utils::Misc;
use Slim::Utils::Network;
use Slim::Utils::PerfMon;
use Slim::Utils::Prefs;
use Slim::Utils::Strings;
use Slim::Utils::Timers;
use Slim::Web::HTTP;

# depricated, use $client->maxVolume
our $maxVolume = 100;

# This is a hash of clientState structs, indexed by the IP:PORT of the client
# Use the access functions.
our %clientHash = ();

use constant KNOB_NOWRAP => 0x01;
use constant KNOB_NOACCELERATION => 0x02;

=head1 NAME

Slim::Player::Client

=head1 DESCRIPTION

The following object contains all the state that we keep about each player.

=head1 METHODS

=cut

our $defaultPrefs = {
	'maxBitrate'       => undef, # will be set by the client device OR default to server pref when accessed.
	'alarmvolume'      => [50,50,50,50,50,50,50,50],
	'alarmfadeseconds' => 0, # fade in alarm, 0 means disabled
	'alarm'            => [0,0,0,0,0,0,0,0],
	'alarmtime'        => [0,0,0,0,0,0,0,0],
	'alarmplaylist'	   => ['','','','','','','',''],
	'lameQuality'      => 9,
	'playername'       => undef,
	'repeat'           => 2,
	'shuffle'          => 0,
	'titleFormat'      => [5, 1, 3, 6],
	'titleFormatCurr'  => 1,
};

# XXX - this is gross. Move to Class::Accessor or Object::InsideOut
sub new {
	my ($class, $id, $paddr) = @_;
	
	# If we haven't seen this client, initialialize a new one
	my $client = [];
	my $clientAlreadyKnown = 0;
	bless $client, $class;

	$::d_protocol && msg("New client connected: $id\n");

	assert(!defined(getClient($id)));

	# The following indexes are unused:
	# 2, 3, 8, 11, 12, 13, 16, 23, 24, 25, 26, 27, 33, 34, 53
	# 64, 65, 66, 67, 68, 72, 82,

	$client->[0] = $id;
	$client->[1] = Slim::Utils::Prefs::getClientPrefs($id); # _prefs

	# client variables id and version info
	$client->[4] = undef; # revision
	$client->[5] = undef; # macaddress
	$client->[6] = $paddr; # paddr
	
	$client->[7] = undef; # startupPlaylistLoading

	# client hardware information
	$client->[9] = undef; # udpsock
	$client->[10] = undef; # tcpsock
	$client->[14] = 0; # readytosync
	$client->[15] = undef; # streamformat
	$client->[17] = undef; # streamingsocket
	$client->[18] = undef; # audioFilehandle
	$client->[19] = 0; # audioFilehandleIsSocket
	$client->[20] = []; # chunks
	$client->[21] = 0; # songStartStreamTime
	$client->[22] = 0; # remoteStreamStartTime
	$client->[28] = []; # playlist
	$client->[29] = []; # shufflelist
	$client->[30] = []; # currentsongqueue
	$client->[31] = 'stop'; # playmode
	$client->[32] = 1; # rate
	$client->[35] = 0; # outputBufferFullness
	$client->[36] = undef; # irRefTime
	$client->[37] = 0; # bytesReceived
	$client->[38] = ''; # currentplayingsong
	$client->[39] = 0; # currentSleepTime
	$client->[40] = 0; # sleepTime
	$client->[41] = undef; # master
	$client->[42] = []; # slaves
	$client->[43] = undef; # syncgroupid
	$client->[44] = undef; # password
	$client->[45] = undef; # lastirbutton
	$client->[46] = 0; # lastirtime
	$client->[47] = 0; # lastircode
	$client->[48] = 0; # lastircodebytes
	$client->[50] = 0; # startirhold
	$client->[51] = 0; # irtimediff
	$client->[52] = 0; # irrepeattime
	$client->[54] = Time::HiRes::time(); # epochirtime
	$client->[55] = []; # modeStack
	$client->[56] = []; # modeParameterStack
	$client->[57] = undef; # lines
	$client->[58] = []; # trackInfoLines
	$client->[59] = []; # trackInfoContent
	$client->[60] = {}; # lastID3Selection
	$client->[61] = undef; # blocklines
	$client->[62] = {}; # curSelection
	$client->[63] = undef; # pluginsSelection
	$client->[69] = undef; # curDepth
	$client->[70] = undef; # searchFor
	$client->[71] = []; # searchTerm
	$client->[73] = 0;  # lastLetterIndex
	$client->[74] = ''; # lastLetterDigit
	$client->[75] = 0;  # lastLetterTime
	$client->[76] = Slim::Utils::PerfMon->new("Signal Strength ($id)", [10,20,30,40,50,60,70,80,90,100]);
	$client->[77] = Slim::Utils::PerfMon->new("Buffer Fullness ($id)", [10,20,30,40,50,60,70,80,90,100]);
	$client->[78] = Slim::Utils::PerfMon->new("Slimproto QLen ($id)", [1, 2, 5, 10, 20]);
	$client->[79] = undef; # irRefTimeStored
	$client->[80] = undef; # syncSelection
	$client->[81] = []; # syncSelections
	$client->[83] = undef; # suppressStatus
	$client->[84] = 0; # songBytes
	$client->[85] = 0; # pauseTime
	$client->[87] = 0; # bytesReceivedOffset
	$client->[88] = 0; # buffersize
	$client->[89] = 0; # streamBytes
	$client->[90] = undef; # trickSegmentRemaining
	$client->[91] = undef; # currentPlaylist
	$client->[92] = undef; # currentPlaylistModified
	$client->[93] = undef; # songElapsedSeconds
	$client->[94] = undef; # customPlaylistLines
	# 95 is currentPlaylistRender
	# 96 is currentPlaylistChangeTime
	$client->[97] = undef; # tempVolume temporary volume setting
	$client->[98] = undef; # directurl
	$client->[99] = undef; # directbody
	$client->[100] = undef; # display object
	$client->[101] = undef; # lines2periodic
	$client->[102] = 0; # periodicUpdateTime
	$client->[103] = undef; # musicInfoTextCache
	$client->[104] = undef; # customVolumeLines
	# 105 is scroll state
	$client->[106] = undef; # knobPos
	$client->[107] = undef; # knobTime
	$client->[108] = 0; # lastDigitIndex
	$client->[109] = 0; # lastDigitTime
	$client->[110] = undef; # lastSong (last URL played in this play session - a play session ends when the player is stopped or a track is skipped)
	$client->[111] = {}; # pipe sockets used for parent/child communication
	$client->[112] = 0; # knobSync

	$clientHash{$id} = $client;

	Slim::Control::Request::notifyFromArray($client, ['client', 'new']);

	return $client;
}

sub init {
	my $client = shift;

	# make sure any preferences unique to this client may not have set are set to the default
	Slim::Utils::Prefs::initClientPrefs($client,$defaultPrefs);

	# init display including setting any display specific preferences to default
	if ($client->display) {
		$client->display->init();
	}
}

=head1 FUNCTIONS

Accessors for the list of known clients. These are functions, and do not need
clients passed. They should be moved to be class methods.

=head2 clients()

Returns an array of all client objects.

=cut

sub clients {
	return values %clientHash;
}

=head2 clientCount()

Returns the number of known clients.

=cut

sub clientCount {
	return scalar(keys %clientHash);
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
	return (values %clientHash)[0];
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

		$client->prefSet("playername", $name);

	} else {

		$name = $client->prefGet("playername");
	}

	if (!defined $name) {
		$name = defaultName($client);
	}
	
	return $name;
}

=head2 defaultName( $client )

Returns the default name for the client (IP address)

=cut

sub defaultName {
	return shift->ip;
}

=head2 debug( $client, @msg )

Log a debug message for this client.

=cut

sub debug {
	my $self = shift;

	if ($::d_client) {
		msg(sprintf("%s : %s\n", $self->name(), @_));
	}
}

# If the ID is undef, that means we have a new client.
sub getClient {
	my $id  = shift || return undef;
	my $ret = $clientHash{$id};

	# Try a brute for match for the client.
	if (!defined($ret)) {
#		while (my ($key, $value) = each(%clientHash)) {

   		 for my $value ( values %clientHash ) {
			return $value if (ipport($value) eq $id);
			return $value if (ip($value) eq $id);
			return $value if (name($value) eq $id);
		}
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
		$client->display->forgetDisplay();
		Slim::Web::HTTP::forgetClient($client);
		Slim::Utils::Timers::forgetTimer($client);
		delete $clientHash{$client->id()};
		
		# stop watching this player
		delete $Slim::Networking::Slimproto::heartbeat{ $client->id };
	}	
}

sub startup {
	my $client = shift;

	Slim::Player::Sync::restoreSync($client);
	
	# restore the old playlist if we aren't already synced with somebody (that has a playlist)
	if (!Slim::Player::Sync::isSynced($client) && Slim::Utils::Prefs::get('persistPlaylists')) {

		my $playlist = Slim::Music::Info::playlistForClient($client);
		my $currsong = $client->prefGet('currentSong');

		if (blessed($playlist)) {

			my $tracks = [ $playlist->tracks ];

			# Only add on to the playlist if there are tracks.
			if (scalar @$tracks && defined $tracks->[0] && blessed($tracks->[0]) && $tracks->[0]->id) {

				$client->debug("found nowPlayingPlaylist - will loadtracks");

				# We don't want to re-setTracks on load - so mark a flag.
				$client->startupPlaylistLoading(1);

				$client->execute(
					['playlist', 'addtracks', 'listref', $tracks ],
					\&initial_add_done, [$client, $currsong],
				);
			}
		}
	}
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
		
		Slim::Player::Source::streamingSongIndex($client,$currsong, 1);
		
	} elsif ($shuffleType eq 'album') {

		# reshuffle set this properly, for album shuffle
		# no need to move the streamingSongIndex

	} else {

		if (Slim::Player::Playlist::count($client) == 0) {

			$currsong = 0;

		} elsif ($currsong >= Slim::Player::Playlist::count($client)) {

			$currsong = Slim::Player::Playlist::count($client) - 1;
		}

		Slim::Player::Source::streamingSongIndex($client, $currsong, 1);
	}

	$client->prefSet('currentSong', $currsong);

	if ($client->prefGet('autoPlay') || Slim::Utils::Prefs::get('autoPlay')) {

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
sub hasPreAmp() { return 0; }
sub hasExternalClock() { return 0; }
sub hasDigitalIn() { return 0; }
sub hasAesbeu() { return 0; }
sub hasPowerControl() { return 0; }
sub hasPolarityInversion() { return 0; }

sub maxBrightness() { return undef; }

sub maxVolume { return 100; }
sub minVolume {	return 100; }

sub maxPitch {	return 100; }
sub minPitch {	return 100; }

sub maxTreble {	return 50; }
sub minTreble {	return 50; }

sub maxBass {	return 50; }
sub minBass {	return 50; }

sub canDirectStream { return 0; }
sub canLoop { return 0; }
sub canDoReplayGain { return 0; }

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

		if ($volume < $client->minVolume) {
			$volume = $client->minVolume;
		}

		if ($temp) {

			$client->[97] = $volume;

		} else {

			# persist only if $temp not set
			Slim::Utils::Prefs::clientSet($client, "volume", $volume);

			# forget any previous temporary volume
			$client->[97] = undef;
		}
	}

	# return the current volume, whether temporary or persisted
	if (defined $client->tempVolume) {

		return $client->tempVolume;

	} else {

		return Slim::Utils::Prefs::clientGet($client, "volume");
	}
}

# getter only.
# use volume() to set, passing in temp flag
sub tempVolume {
	my $r = shift;
	return $r->[97];
}

sub treble {
	my ($client, $treble) = @_;
	if (defined($treble)) {
		if ($treble > $client->maxTreble()) { $treble = $client->maxTreble(); }
		if ($treble < $client->minTreble()) { $treble = $client->minTreble(); }
		Slim::Utils::Prefs::clientSet($client, "treble", $treble);
	}
	return Slim::Utils::Prefs::clientGet($client, "treble");
}

sub bass {
	my ($client, $bass) = @_;
	if (defined($bass)) {	
		if ($bass > $client->maxBass()) { $bass = $client->maxBass(); }
		if ($bass < $client->minBass()) { $bass = $client->minBass(); }
		Slim::Utils::Prefs::clientSet($client, "bass", $bass);
	}
	return Slim::Utils::Prefs::clientGet($client, "bass");
}

sub pitch {
	my ($client, $pitch) = @_;
	if (defined($pitch)) {	
		if ($pitch > $client->maxPitch()) { $pitch = $client->maxPitch(); }
		if ($pitch < $client->minPitch()) { $pitch = $client->minPitch(); }
		Slim::Utils::Prefs::clientSet($client, "pitch", $pitch);
	}
	return Slim::Utils::Prefs::clientGet($client, "pitch");
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
	
	if ($client->sleepTime) {
		
		# assumes that remaining time was under 15 minutes.  might need to check against every default value just to cover all cases.
		if ($client->currentSleepTime < 15) {
			$sleepstring = join(' ',$client->string('SLEEPING_AT'),$client->string('END_OF_SONG'));
		} else {
			$sleepstring = join(" " ,$client->string('SLEEPING_IN'),int($sleeptime/60)+1,$client->string('MINUTES'));
		}
	}
	
	return $sleepstring;
}

sub flush {}

sub power {}

# string processing is display object specific
sub string       { shift->display->string(@_); }
sub doubleString { shift->display->doubleString(@_); }

sub maxTransitionDuration {
	return 0;
}

sub reportsTrackStart {
	return 0;
}

sub param {
	my $client = shift;
	my $name   = shift;
	my $value  = shift;

	my $mode   = $client->modeParameterStack(-1) || return undef;

	if (defined $value) {

		$mode->{$name} = $value;

	} else {

		return $mode->{$name};
	}
}

# this is a replacement for param that allows you to pass undef to clear a parameter
sub modeParam {
	my $client = shift;
	my $name   = shift;
	my $mode   = $client->modeParameterStack(-1) || return undef;

	@_ ? ($mode->{$name} = shift) : $mode->{$name};
}

sub paramOrPref {
	my $client = shift;
	my $name   = shift;

	my $mode   = $client->modeParameterStack(-1) || return undef;

	if (defined $mode && defined $mode->{$name}) {
		return $mode->{$name};
	}

	return $client->prefGet($name);
}
	
sub getPref {
	prefGet(@_);
}

sub setPref {
	prefSet(@_);
}

# method for getting/setting prefs
# for non-indexed prefs the first parameter should be the pref name
# for indexed prefs the first parameter should be a two element array reference
# with the pref name first and the index second
sub pref {
	my $client = shift;
	my $pref = shift;
	my $value = shift;

	my $ind = undef;

	return undef unless defined $pref;

	if (ref($pref) eq "ARRAY") {
		($pref,$ind) = @$pref;
	}

	if (defined $value) {
		return $client->prefSet($pref,$value,$ind);
	} else {
		return $client->prefGet($pref,$ind);
	}
}

sub prefGet {
	my $client = shift;
	my $pref = shift;
	my $ind = shift;

	if (defined $ind) {
		$client->prefGetInd($pref,$ind);
	} else {
		return $client->_prefs()->{$pref};
	}
}

sub prefGetInd {
	my $client = shift;
	my $pref = shift;
	my $index = shift;

	my $prefs = $client->_prefs();

	if (defined $prefs->{$pref}) {
		if (ref $prefs->{$pref} eq 'ARRAY') {
			return $prefs->{$pref}[$index];
		} elsif (ref $prefs->{$pref} eq 'HASH') {
			return $prefs->{$pref}{$index};
		}
	}
	return undef;
}

sub prefGetArray {
	my $client = shift;
	my $arrayPref = shift;
	
	my $prefs = $client->_prefs();

	if (defined($prefs->{$arrayPref}) && ref($prefs->{$arrayPref}) eq 'ARRAY') {
		return @{$prefs->{$arrayPref}};
	} else {
		return ();
	}
}

sub prefGetArrayMax{
	my $client = shift;
	my $arrayPref = shift;
	
	my $prefs = $client->_prefs();
	
	if (defined($prefs->{$arrayPref}) && ref($prefs->{$arrayPref}) eq 'ARRAY') {
		my @prefArray = @{$prefs->{$arrayPref}};
		my $max = $#prefArray;
		return $max;
	} else {
		return undef;
	}
}

sub prefGetHash {
	my $client = shift;
	my $hashPref = shift;
	
	my $prefs = $client->_prefs();

	if (defined($prefs->{$hashPref}) && ref($prefs->{$hashPref}) eq 'HASH') {
		return %{$prefs->{$hashPref}};
	} else {
		return ();
	}
}

sub prefGetKeys {
	my $client = shift;
	my $hashPref = shift;
	
	my $prefs = $client->_prefs();

	if (defined($prefs->{$hashPref}) && ref($prefs->{$hashPref}) eq 'HASH') {
		return keys %{$prefs->{$hashPref}};
	} else {
		return ();
	}
}

sub prefIsDefined {
	my $client = shift;
	my $key = shift;
	my $ind = shift;
	
	my $prefs = $client->_prefs();
	
	if (defined($ind)) {
		if (defined $prefs->{$key}) {
			if (ref $prefs->{$key} eq 'ARRAY') {
				return defined $prefs->{$key}[$ind];
			} elsif (ref $prefs->{$key} eq 'HASH') {
				return defined $prefs->{$key}{$ind};
			}
		}
	}
	return defined $prefs->{$key};
}

# using wrappers for methods which involve changing the preference
# so that we don't have to worry about writing out the preferences

=head2 prefSet( $client, $prefName, $value, $index )

Sets the client preference to the specified value.

See L<Slim::Utils::Prefs::set>

=cut

sub prefSet {
	my $client = shift;
	my $pref = shift;
	my $value = shift;
	my $ind = shift;
	
	return Slim::Utils::Prefs::set($pref,$value,$ind,$client,$client->_prefs());
}

=head2 prefPush( $client, $prefName, $value )

Appends the value to the specified client array preference.

=cut

sub prefPush {
	my $client = shift;
	my $pref = shift;
	my $value = shift;
	
	Slim::Utils::Prefs::push($pref,$value,$client->_prefs());
}

=head2 prefDelete( $client, $prefName, $index )

Removes a client pref specified by the name and index.

=cut

sub prefDelete {
	my $client = shift;
	my $pref = shift;
	my $ind = shift;
	
	Slim::Utils::Prefs::delete($pref,$ind,$client->_prefs());
}

=head2 masterOrSelf( $client )

See L<Slim::Player::Sync> for more information.

Returns the the master L<Slim::Player::Client> object if one exists, otherwise
returns ourself.

=cut

sub masterOrSelf {
	Slim::Player::Sync::masterOrSelf(@_)
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
	
	my $url = $args->{'url'};
	
	# Duration specified directly (i.e. from a plugin)
	my $duration = $args->{'duration'};
	
	# Duration can be calculated from bitrate + length
	my $bitrate = $args->{'bitrate'};
	my $length  = $args->{'length'};
	
	my $secs;
	
	if ( $duration ) {
		$secs = $duration;
	}
	elsif ( $bitrate > 0 && $length > 0 ) {
		$secs = int( ( $length * 8 ) / $bitrate );
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
	if ( ref $client->currentsongqueue->[0] eq 'HASH' ) {
		$client->currentsongqueue()->[0]->{'duration'} = $secs;
		
		if ( $::d_remotestream || $::d_directstream ) {
			if ( $duration ) {
				msgf("Duration of stream set to %d seconds\n", $duration );
			}
			else {
				msgf(
					"Duration of stream set to %d seconds based on length of %d and bitrate of %d\n",
					$secs,
					$length,
					$bitrate
				);
			}
		}
	}
}

=head2 sendParent( $client, $msg )

Send an IPC message to our parent process. Used for forked streaming.

=cut

sub sendParent {
	my ( $client, $msg ) = @_;
	
	return unless $Slim::Web::HTTP::inChild;
	
	if ( $client->pipes->{pw} ) {
		$msg->{clientid} = $client->id;
		$client->pipes->{pw}->syswrite( nfreeze( $msg ) );
	}
}

=head2 sendChild( $client, $msg )

Send an IPC message to our child process. Used for forked streaming.

=cut

sub sendChild {
	my ( $client, $msg ) = @_;
	
	return if $Slim::Web::HTTP::inChild;
	
	if ( $client->pipes->{cw} ) {
		$msg->{clientid} = $client->id;
		$client->pipes->{cw}->syswrite( nfreeze( $msg ) );
	}
}

=head2 id()

Returns the client ID - in the form of a MAC Address.

=cut

sub id {
	my $r = shift;
	@_ ? ($r->[0] = shift) : $r->[0];
}

# the _prefs method should not be used to access individual prefs
# use the pref* methods for working with client prefs
sub _prefs {
	my $r = shift;
	@_ ? ($r->[1] = shift) : $r->[1];
}

=head2 revision()

Returns the firmware revision of the client.

=over 4

=item * 0

Unknown

item * 1.2

Old (1.0, 1.1, 1.2),

item * 1.3

New streaming protocol (Squeezebox v1?)

=item * 2.0

Client sends MAC address, NEC IR codes supported

=back

=cut

sub revision {
	my $r = shift;
	@_ ? ($r->[4] = shift) : $r->[4];
}

sub macaddress {
	my $r = shift;
	@_ ? ($r->[5] = shift) : $r->[5];
}
sub paddr {
	my $r = shift;
	@_ ? ($r->[6] = shift) : $r->[6];
}

sub startupPlaylistLoading {
	my $r = shift;
	@_ ? ($r->[7] = shift) : $r->[7];
}

sub udpsock {
	my $r = shift;
	@_ ? ($r->[9] = shift) : $r->[9];
}

sub tcpsock {
	my $r = shift;
	@_ ? ($r->[10] = shift) : $r->[10];
}

sub readytosync {
	my $r = shift;
	@_ ? ($r->[14] = shift) : $r->[14];
}

sub streamformat {
	my $r = shift;
	@_ ? ($r->[15] = shift) : $r->[15];
}

sub streamingsocket {
	my $r = shift;
	@_ ? ($r->[17] = shift) : $r->[17];
}

sub audioFilehandle {
	my $r = shift;
	@_ ? ($r->[18] = shift) : $r->[18];
}

sub audioFilehandleIsSocket {
	my $r = shift;
	@_ ? ($r->[19] = shift) : $r->[19];
}

sub chunks {
	my $r = shift;
	my $i;
	@_ ? ($i = shift) : return $r->[20];
	@_ ? ($r->[20]->[$i] = shift) : $r->[20]->[$i];
}

sub songStartStreamTime {
	my $r = shift;
	@_ ? ($r->[21] = shift) : $r->[21];
}

sub remoteStreamStartTime {
	my $r = shift;
	@_ ? ($r->[22] = shift) : $r->[22];
}


sub playlist {
	my $r = shift;
	my $i;
	@_ ? ($i = shift) : return $r->[28];
	@_ ? ($r->[28]->[$i] = shift) : $r->[28]->[$i];
}

sub shufflelist {
	my $r = shift;
	my $i;
	@_ ? ($i = shift) : return $r->[29];
	@_ ? ($r->[29]->[$i] = shift) : $r->[29]->[$i];
}

sub currentsongqueue {
	my $r = shift;
	my $i;
	@_ ? ($i = shift) : return $r->[30];
	@_ ? ($r->[30]->[$i] = shift) : $r->[30]->[$i];
}

sub playmode {
	my $r = shift;
	@_ ? ($r->[31] = shift) : $r->[31];
}

sub rate {
	my $r = shift;
	@_ ? ($r->[32] = shift) : $r->[32];
}

sub outputBufferFullness {
	my $r = shift;
	@_ ? ($r->[35] = shift) : $r->[35];
}

sub irRefTime {
	my $r = shift;
	@_ ? ($r->[36] = shift) : $r->[36];
}

sub bytesReceived {
	my $r = shift;
	@_ ? ($r->[37] = shift) : $r->[37];
}

sub currentplayingsong {
	my $r = Slim::Player::Sync::masterOrSelf(shift);
	@_ ? ($r->[38] = shift) : $r->[38];
}

sub currentSleepTime {
	my $r = shift;
	@_ ? ($r->[39] = shift) : $r->[39];
}

sub sleepTime {
	my $r = shift;
	@_ ? ($r->[40] = shift) : $r->[40];
}

sub master {
	my $r = shift;
	@_ ? ($r->[41] = shift) : $r->[41];
}

sub slaves {
	my $r = shift;
	my $i;
	@_ ? ($i = shift) : return $r->[42];
	@_ ? ($r->[42]->[$i] = shift) : $r->[42]->[$i];
}

sub syncgroupid {
	my $r = shift;
	@_ ? ($r->[43] = shift) : $r->[43];
}

sub password {
	my $r = shift;
	@_ ? ($r->[44] = shift) : $r->[44];
}

sub lastirbutton {
	my $r = shift;
	@_ ? ($r->[45] = shift) : $r->[45];
}

sub lastirtime {
	my $r = shift;
	@_ ? ($r->[46] = shift) : $r->[46];
}

sub lastircode {
	my $r = shift;
	@_ ? ($r->[47] = shift) : $r->[47];
}

sub lastircodebytes {
	my $r = shift;
	@_ ? ($r->[48] = shift) : $r->[48];
}

sub startirhold {
	my $r = shift;
	@_ ? ($r->[50] = shift) : $r->[50];
}

sub irtimediff {
	my $r = shift;
	@_ ? ($r->[51] = shift) : $r->[51];
}

sub irrepeattime {
	my $r = shift;
	@_ ? ($r->[52] = shift) : $r->[52];
}

sub epochirtime {
	my $r = shift;
	@_ ? ($r->[54] = shift) : $r->[54];
}

sub modeStack {
	my $r = shift;
	my $i;
	@_ ? ($i = shift) : return $r->[55];
	@_ ? ($r->[55]->[$i] = shift) : $r->[55]->[$i];
}

sub modeParameterStack {
	my $r = shift;
	my $i;
	@_ ? ($i = shift) : return $r->[56];
	@_ ? ($r->[56]->[$i] = shift) : $r->[56]->[$i];
}

sub lines {
	my $r = shift;
	@_ ? ($r->[57] = shift) : $r->[57];
}

sub trackInfoLines {
	my $r = shift;
	my $i;
	@_ ? ($i = shift) : return $r->[58];
	@_ ? ($r->[58]->[$i] = shift) : $r->[58]->[$i];
}

sub trackInfoContent {
	my $r = shift;
	my $i;
	@_ ? ($i = shift) : return $r->[59];
	@_ ? ($r->[59]->[$i] = shift) : $r->[59]->[$i];
}

sub lastID3Selection {
	my $r = shift;
	my $i;
	@_ ? ($i = shift) : return $r->[60];
	@_ ? ($r->[60]->{$i} = shift) : $r->[60]->{$i};
}

sub blocklines {
	my $r = shift;
	@_ ? ($r->[61] = shift) : $r->[61];
}

sub curSelection {
	my $r = shift;
	my $i;
	@_ ? ($i = shift) : return $r->[62];
	@_ ? ($r->[62]->{$i} = shift) : $r->[62]->{$i};
}

sub pluginsSelection {
	my $r = shift;
	@_ ? ($r->[63] = shift) : $r->[63];
}

sub curDepth {
	my $r = shift;
	@_ ? ($r->[69] = shift) : $r->[69];
}

sub searchFor {
	my $r = shift;
	@_ ? ($r->[70] = shift) : $r->[70];
}

sub searchTerm {
	my $r = shift;
	my $i;
	@_ ? ($i = shift) : return $r->[71];
	@_ ? ($r->[71]->[$i] = shift) : $r->[71]->[$i];
}

sub lastLetterIndex {
	my $r = shift;
	@_ ? ($r->[73] = shift) : $r->[73];
}

sub lastLetterDigit {
	my $r = shift;
	@_ ? ($r->[74] = shift) : $r->[74];
}

sub lastLetterTime {
	my $r = shift;
	@_ ? ($r->[75] = shift) : $r->[75];
}

sub signalStrengthLog {
	my $r = shift;
	@_ ? ($r->[76]->log(shift)) : $r->[76];
}

sub bufferFullnessLog {
	my $r = shift;
	@_ ? ($r->[77]->log(shift)) : $r->[77];
}

sub slimprotoQLenLog {
	my $r = shift;
	@_ ? ($r->[78]->log(shift)) : $r->[78];
}

sub irRefTimeStored {
	my $r = shift;
	@_ ? ($r->[79] = shift) : $r->[79];
}

sub syncSelection {
	my $r = shift;
	@_ ? ($r->[80] = shift) : $r->[80];
}

sub syncSelections {
	my $r = shift;
	my $i;
	@_ ? ($i = shift) : return $r->[81];
	@_ ? ($r->[81]->[$i] = shift) : $r->[81]->[$i];
}

sub suppressStatus {
	my $r = shift;
	@_ ? ($r->[83] = shift) : $r->[83];
}

sub songBytes {
	my $r = shift;
	@_ ? ($r->[84] = shift) : $r->[84];
}

sub pauseTime {
	my $r = shift;
	@_ ? ($r->[85] = shift) : $r->[85];
}

sub bytesReceivedOffset {
	my $r = shift;
	@_ ? ($r->[87] = shift) : $r->[87];
}

sub bufferSize {
	my $r = shift;
	@_ ? ($r->[88] = shift) : $r->[88];
}

sub streamBytes {
	my $r = shift;
	@_ ? ($r->[89] = shift) : $r->[89];
}

sub trickSegmentRemaining {
	my $r = shift;
	@_ ? ($r->[90] = shift) : $r->[90];
}

sub currentPlaylist {
	my $r    = Slim::Player::Sync::masterOrSelf(shift);

	if (@_) {
		$r->[91] = shift;
		return;
	}

	my $playlist = $r->[91];

	# Force the caller to do the right thing.
	if (ref($playlist)) {
		return $playlist;
	}

	return;
}

sub currentPlaylistModified {
	my $r = shift;
	@_ ? ($r->[92] = shift) : $r->[92];
}

sub songElapsedSeconds {
	my $r = shift;
	@_ ? ($r->[93] = shift) : $r->[93];
}

sub customPlaylistLines {
	my $r = shift;
	@_ ? ($r->[94] = shift) : $r->[94];
}

sub currentPlaylistRender {
	my $r = shift;
	@_ ? ($r->[95] = shift) : $r->[95];
}

sub currentPlaylistChangeTime {
	# This needs to be the same for all synced clients
	my $r = Slim::Player::Sync::masterOrSelf(shift);
	@_ ? ($r->[96] = shift) : $r->[96];
}

sub directURL {
	my $r = shift;
	@_ ? ($r->[98] = shift) : $r->[98];
}

sub directBody {
	my $r = shift;
	@_ ? ($r->[99] = shift) : $r->[99];
}

sub display {
	my $r = shift;
	@_ ? ($r->[100] = shift) : $r->[100];
}

sub lines2periodic {
	my $r = shift;
	@_ ? ($r->[101] = shift) : $r->[101];
}

sub periodicUpdateTime {
	my $r = shift;
	@_ ? ($r->[102] = shift) : $r->[102];
}

sub musicInfoTextCache {
	my $r = shift;
	@_ ? ($r->[103] = shift) : $r->[103];
}

sub customVolumeLines {
	my $r = shift;
	@_ ? ($r->[104] = shift) : $r->[104];
}

sub knobPos {
	my $r = shift;
	@_ ? ($r->[106] = shift) : $r->[106];
}

sub knobTime {
	my $r = shift;
	@_ ? ($r->[107] = shift) : $r->[107];
}

sub lastDigitIndex {
	my $r = shift;
	@_ ? ($r->[108] = shift) : $r->[108];
}

sub lastDigitTime {
	my $r = shift;
	@_ ? ($r->[109] = shift) : $r->[109];
}

sub lastSong {
	my $r = shift;
	@_ ? ($r->[110] = shift) : $r->[110];
}

sub pipes {
	my $r = shift;
	@_ ? ($r->[111] = shift) : $r->[111];
}

sub knobSync {
	my $r = shift;
	@_ ? ($r->[112] = shift) : $r->[112];
}

1;
