package Slim::Player::Client;

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

use strict;
use Scalar::Util qw(blessed);

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

=head1 Object Definition

The following object contains all the state that we keep about each player.

=head1 Client variables id and version info

=over

=item

_prefs() - type: hashref

	A reference to the preferences for this client.

=item 

revision() - type: int

	firmware rev

		  0 = unknown,
		1.2 = old (1.0, 1.1, 1.2),
		1.3 = new streaming protocol,
		2.0 = client sends MAC address, NEC IR codes supported

=item

macaddress() - type: string

	client's MAC (V2.0 firmware)

=item

paddr() - type: sockaddr_in

	Client's IP and port

=back

=head1 Client variables for slim protocol networking

=over

=item

udpsock() - type: filehandle

	the socket we should use to talk to this client

=item

tcpsock() - type: filehandle

	the socket we should use to talk to this client

=item

RTT() - type: float

	rtt estimate (seconds)

=item

prevwptr() - type: int

	wptr at previous request - see protocol docs

=item

waitforstart() - type: bool

	1 = we've sent the client the start command, and we're waiting for him to start a new stream

=item

readytosync() - type: bool

	when starting a new synced stream, indicates whether this client is ready to be unpaused. 

=item

resync() - type: bool

	1 if we are in the process of resyncing clients

=back

=head1 client variables for HTTP protocol clients

=over

=item

streamingsocket() - type: filehandle

	streaming socket for http clients

=back

=head1 client variables for song data

=over

=item

audioFilehandle() - type: filehandle

	The currently open MP3 file OR TCP stream

=item

audioFilehandleIsSocket() - type: bool

	Becase Windows gets confused if you select on a regular file.

=item

chunks() - type: array

	array of references to chunks of data to be sent to client.

=item

songStartStreamTime() - type: float

	time offset at which we started streaming this song

=item

remoteStreamStartTime() - type: float

	time we began playing the remote stream

=item

pauseTime() - type: float

	time that we started pausing

=back

=head1 client variables for shoutcast meta information 

=over

=item

shoutMetaPointer() - type: int

	shoutcast metadata stream pointer

=item

shoutMetaInterval() - type: int

	shoutcast metadata interval

=back

=head1 client variables for display

=over

=item

currBrightness() - type: int

	current brightness setting of the client's VFD display, range 0..4

=item

prevline1() - type: string

	what's currently on the the client's display, line 1

=item

prevline2() - type: string

	and line 2

=back

=head1 client variables for current playlist and mode

=over

=item

playlist() - type: array

	playlist of songs  (when synced, use the master's)

=item

shufflelist() - type: array

	array of indices into playlist which may be shuffled (when synced, use the master's)

=item

currentsong() - type: int

	index into the playlist of the currently playing song (updated when reshuffled)

=item

playmode() - type: string

	'stop', 'play', or 'pause'

=item

rate() - type: float

	playback rate: 1 is normal, 0 is paused, 2 is ffwd, -1 is rew

=item

songBytes	() - type: int

	number of bytes read from the current song

=item

currentplayingsong() - type: string

	current song that's playing out from player.  May not be the same as in the playlist as the client's buffer plays out.

=back

=head1 client variables for sleep

=over

=item

currentSleepTime() - type: int

	what the sleep time is currently set to (in minutes)

=item

sleepTime() - type: int

	time() value for when we'll sleep

=back

=head1 client variables for synchronzation

=over

=item

master() - type: client

	if we're synchronized, 'master' points to master client

=item

slaves() - type: clients

	if we're a master, this is an array of slaves which are synced to us

=item

syncgroupid() - type: uniqueid

	unique identifier for this sync group

=back

=head1 client variables are for IR processing

=over

=item

lastirtime() - type: int

	time at which we last received an IR code (in client's 625KHz ticks)

=item

lastircode() - type: string

	the last IR command we received, so we can tell if a button's being held down

=item

lastircodebytes() - type: string

	the last IR code we received, so we can tell if a button's being held down

=item

ticspersec() - type: int

	number of IR tics per second

=item

startirhold() - type: string

	the first time the button was pressed, so we can tell how long the button is held

=item

irtimediff() - type: float

	calculated diff ir time

=item

irrepeattime() - type: float

	calculated time for repeat codes

=item

epochirtime	() - type: int

		epoch time that we last received an IR signal

=back

=head1 state for button navigation

=over

=item

modeStack() - type: array

	stack of current browse modes: 'playlist', 'browse', 'off', etc...

=item

modeParameterStack() - type: array

	stack of hashes of mode parameters for previous modes

=item

lines() - type: function

	reference to function to display lines for current mode

=back

=head1 Other

The remainder are temporary and global client variables are for the various button display modes

TODO - These don't belong in the client object

=head1 trackinfo mode

=over

=item

trackInfoLines() - type: strings

	current trackinfo lines

=item

trackInfoContent() - type: strings

	content type for trackinfo lines.

=back

=head1 browseid3 mode

=over

=item

lastID3Selection() - type: hash

	the item that was last selected for a given browse position

=back

=head1 blocked mode

=over

=item

blocklines() - type: strings

	what to display when we're blocked.

=back

=head1 home mode

=over

=item

curSelection() - type: hash

	currently selected item in player menu

=back

=head1 plugins mode

=over

=item

pluginsSelection() - type: int

	index into plugins list

=back

=head1 browse music folder mode

=over

=item

pwd() - type: string

	present directory, relative to $audiodir

=item

currentDirItem() - type: int

	the index of the currently selected item (in @dirItems)

=item

numberOfDirItems() - type: int

	size of @dirItems -  FIXME this is redundant, right?

=item

dirItems() - type: strings

	list of file names in the current directory

=item

lastSelection() - type: hash

	the curdiritem (integer) that was selected last time we were in each directory (string)

=back

=head1 search mode

=over

=item

curDepth() - type: strings

	string identifier for the current depth of home menu navigation tree (separator: -)

=item

searchFor() - type: string

	what we are searching for from the remote: "ALBUMS", "ARTISTS", "SONGS"

=item

searchTerm() - type: array

	of characters we are searching for

=item

searchCursor() - type: int

	position of cursor (zero based)

=item

lastLetterIndex() - type: int

	index into letters for each digit when using digits to type letters

=item

lastLetterDigit() - type: int

	last digit hit while entering text

=item

lastLetterTime() - type: int

	epoch time of previous letter

=item

lastDigitIndex() - type: int

	the index number entered so far when directly entering an index number in a list

=item

lastDigitTime() - type: int

	epoch time of previous digit

=back

=head1 synchronization mode

=over

=item

syncSelection() - type: int

	scroll selection while in the syncronization screen, 0 is to unsync

=item

syncSelections() - type: clients

	addresses of possible syncable selections

=back

=head1 browse menu mode

=over

=item

browseMenuSelection() - type: int

	scroll selection when in browse menu

=back

=head1 settings menu mode

=over

=item

settingsSelection() - type: int

	scroll selection when in settings menu

=back

=cut

our $defaultPrefs = {
		'maxBitrate'			=> undef # will be set by the client device OR default to server pref when accessed.
		,'alarmvolume'			=> [50,50,50,50,50,50,50,50]
		,'alarmfadeseconds'		=> 0 # fade in alarm, 0 means disabled
		,'alarm'				=> [0,0,0,0,0,0,0,0]
		,'alarmtime'			=> [0,0,0,0,0,0,0,0]
		,'alarmplaylist'		=> ['','','','','','','','']
		,'lameQuality'			=> 9
		,'playername'			=> undef
		,'repeat'				=> 2
		,'shuffle'				=> 0
		,'titleFormat'			=> [5, 1, 3, 6]
		,'titleFormatCurr'		=> 1
	};

# Do this once for speed.
our $failsafeLanguage     = Slim::Utils::Strings::failsafeLanguage();
our %validClientLanguages = Slim::Utils::Strings::validClientLanguages();

sub new {
	my ($class, $id, $paddr) = @_;
	
	# if we haven't seen this client, initialialize a new one
	my $client =[];	
	my $clientAlreadyKnown = 0;
	bless $client, $class;

	$::d_protocol && msg("new client id: ($id)\n");

	assert(!defined(getClient($id)));

	$client->[0] = undef; # id 	

	$client->[1] = undef; # _prefs
	# $client->[2] = undef; # unused
	# $client->[3] = undef; # unused

	# client variables id and version info
	$client->[4] = undef; # revision		int        firmware rev   0=unknown, 1.2 = old (1.0, 1.1, 1.2), 1.3 = new streaming protocol, 2.0 = client sends MAC address, NEC IR codes supported
	$client->[5] = undef; # macaddress		string     client's MAC (V2.0 firmware)
	$client->[6] = undef; # paddr			sockaddr_in client's ip and port
	
	$client->[7] = undef; # startupPlaylistLoading
	# $client->[8] = undef; # unused

	# client hardware information
	$client->[9] = undef; # udpsock
	$client->[10] = undef; # tcpsock
	$client->[11] = undef; # RTT
	$client->[12] = undef; # prevwptr
	$client->[13] = undef; # waitforstart
	$client->[14] = undef; # readytosync
	$client->[15] = undef; # streamformat
	$client->[16] = undef; # resync
	$client->[17] = undef; # streamingsocket
	$client->[18] = undef; # audioFilehandle
	$client->[19] = 0; # audioFilehandleIsSocket
	$client->[20] = []; # chunks
	$client->[21] = 0;  # songStartStreamTime
	$client->[22] = 0; # remoteStreamStartTime
	$client->[23] = undef; # shoutMetaPointer
	$client->[24] = undef; # shoutMetaInterval
	$client->[25] = undef; # currBrightness
	$client->[26] = undef; # prevline1
	$client->[27] = undef; # prevline2
	$client->[28] = []; # playlist
	$client->[29] = []; # shufflelist
	$client->[30] = []; # currentsongqueue
	$client->[31] = undef; # playmode
	$client->[32] = undef; # rate
	$client->[33] = 0; # bufferThreshold
	$client->[34] = 0; # visualizer
	$client->[35] = 0; # outputBufferFullness
	$client->[36] = undef; # irRefTime
	$client->[37] = 0; # bytesReceived
	$client->[38] = undef; # currentplayingsong
	$client->[39] = undef; # currentSleepTime
	$client->[40] = undef; # sleepTime
	$client->[41] = undef; # master
	$client->[42] = []; # slaves
	$client->[43] = undef; # syncgroupid
	$client->[44] = undef; # password
	$client->[45] = undef; # lastirbutton
	$client->[46] = undef; # lastirtime
	$client->[47] = undef; # lastircode
	$client->[48] = undef; # lastircodebytes
	$client->[50] = undef; # startirhold
	$client->[51] = undef; # irtimediff
	$client->[52] = undef; # irrepeattime
	$client->[53] = undef; # showBrieflyData
	$client->[54] = undef; # epochirtime
	$client->[55] = []; # modeStack
	$client->[56] = []; # modeParameterStack
	$client->[57] = undef; # lines
	$client->[58] = []; # trackInfoLines
	$client->[59] = []; # trackInfoContent
	$client->[60] = {}; # lastID3Selection
	$client->[61] = undef; # blocklines
	$client->[62] = {}; # curSelection
	$client->[63] = undef; # pluginsSelection
	$client->[64] = undef; # pwd
	$client->[65] = undef; # currentDirItem
	$client->[66] = undef; # numberOfDirItems
	$client->[67] = []; # dirItems
	$client->[68] =  {}; # lastSelection
	$client->[69] = undef; # curDepth
	$client->[70] = undef; # searchFor
	$client->[71] = []; # searchTerm
	$client->[72] = undef; # searchCursor
	$client->[73] = undef; # lastLetterIndex
	$client->[74] = undef; # lastLetterDigit
	$client->[75] = undef; # lastLetterTime
	$client->[76] = Slim::Utils::PerfMon->new("Signal Strength ($id)", [10,20,30,40,50,60,70,80,90,100]);
	$client->[77] = Slim::Utils::PerfMon->new("Buffer Fullness ($id)", [10,20,30,40,50,60,70,80,90,100]);
	$client->[78] = Slim::Utils::PerfMon->new("Slimproto QLen ($id)", [1, 2, 5, 10, 20]);
	$client->[79] = undef; # irRefTimeStored
	$client->[80] = undef; # syncSelection
	$client->[81] = []; # syncSelections
	$client->[82] = undef; # browseMenuSelection
	$client->[83] = undef; # settingsSelection
	$client->[84] = undef; # songBytes
	$client->[85] = 0; # pauseTime
	$client->[87] = 0; # bytesReceivedOffset
	$client->[88] = 0; # buffersize
	$client->[89] = 0; # streamBytes
	$client->[90] = undef; # trickSegmentRemaining
	$client->[91] = undef; # currentPlaylist
	$client->[92] = undef; # currentPlaylistModified
	$client->[93] = undef; # songElapsedSeconds
	$client->[94] = 0; # updateMode [0 = normal, 1 = periodic update blocked, 2 = all updates blocked]
	# 95 is currentPlaylistRender
	# 96 is currentPlaylistChangeTime
	$client->[97] = undef; # tempVolume temporary volume setting
	$client->[98] = undef; # directurl
	$client->[99] = undef; # directbody
	$client->[100] = undef; # renderCache
	$client->[101] = undef; # scrollData
	$client->[102] = 0; # periodicUpdateTime
	$client->[103] = 0; # lastVisMode
	$client->[104] = 0; # animateState
	$client->[105] = 0; # scrollState
	$client->[106] = undef; # lastDigitIndex
	$client->[107] = undef; # lastDigitTime
	$client->[108] = undef; # lastSong (last URL played in this play session - a play session ends when the player is stopped or a track is skipped)

	$::d_protocol && msg("New client connected: $id\n");
	$client->lastirtime(0);
	$client->lastircode(0);
	$client->lastircodebytes(0);
	$client->startirhold(0);
	# initialize the irtime to the current time so that
	# (re)connecting counts as activity (and we don't
	# immediately switch into a screensaver).
	my $now = Time::HiRes::time();
	$client->epochirtime($now);
	$client->irrepeattime(0);
	$client->irtimediff(0);

	$client->id($id);
	$client->_prefs(Slim::Utils::Prefs::getClientPrefs($client->id()));
	$client->prevwptr(-1);
	$client->pwd('');  # start browsing at the root MP3 directory

	$client->prevline1('');
	$client->prevline2('');

	$client->lastircode('');

	$client->lastLetterIndex(0);
	$client->lastLetterDigit('');
	$client->lastLetterTime(0);

	$client->lastDigitIndex(0);
	$client->lastDigitTime(0);

	$client->playmode("stop");
	$client->rate(1);

	$client->songBytes(0);
	$client->currentplayingsong("");

	$client->readytosync(0);

	$client->currentSleepTime(0);
	$client->sleepTime(0);

	$client->RTT(.5);

	$client->searchCursor(0);

	$client->currBrightness(1);

	$clientHash{$id} = $client;

	$client->paddr($paddr);

	Slim::Control::Request::notifyFromArray($client, ['client', 'new']);

	return $client;
}

sub init {
	my $client = shift;

	# make sure any preferences unique to this client may not have set are set to the default
	Slim::Utils::Prefs::initClientPrefs($client,$defaultPrefs);
}


###################
# Accessors for the list of known clients

# returns all clients
sub clients {
	return values %clientHash;
}

# returns the number of known clients
sub clientCount {
	return scalar(keys %clientHash);
}

# return IP info of all clients
sub clientIPs {
	my @players;
	foreach my $client (values %clientHash) {
		push @players, $client->ipport();
	}
	return @players;
}

# returns a random client
sub clientRandom {

	# the "randomness" of this is limited to the hashing mysteries
	
	return (values %clientHash)[0];
}

###################
# Client methods

# returns ip:port
sub ipport {
	my $client = shift;

	assert($client->paddr);

	return Slim::Utils::Network::paddr2ipaddress($client->paddr);
}

# returns IP address
sub ip {
	return (split(':',shift->ipport))[0];
}

# returns port
sub port {
	return (split(':',shift->ipport))[1];
}

sub name {
	my $client = shift;
	my $name = shift;

	return unless $client;
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

sub defaultName {
	my ($name) = split(':', ipport(shift));
	return $name;
}

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
		while (my ($key, $value) = each(%clientHash)) {
			return $value if (ipport($value) eq $id);
			return $value if (ip($value) eq $id);
			return $value if (name($value) eq $id);
		}
	}

	return($ret);
}

sub forgetClient {
	my $client = shift;
	
	if ($client) {
		Slim::Web::HTTP::forgetClient($client);
		Slim::Utils::Timers::forgetTimer($client);
		delete $clientHash{$client->id()};
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

sub hasDigitalOut() { return 0; }
sub hasPreAmp() { return 0; }

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

# mixerConstant returns the requested aspect of a given mixer feature
# Supported features: volume, pitch, bass, treble
# Supported aspects: min       - the minimum setting of the feature
#                    max       - the maximum setting of the feature
#                    mid       - the midpoint of the feature, if important
#                    scale     - the multiplier for display of the feature value
#                    increment - The inverse of scale  
#                    balanced  - whether to bias the displayed value by the mid value
# TODO allow different player types to have their own scale and increment, when SB2 has better resolution
# uncomment the increments below
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
	} else {
		return undef;
	}
}

sub volume {
	my ($client, $volume, $temp) = @_;

	if (defined($volume)) {
		if ($volume > $client->maxVolume()) { $volume = $client->maxVolume(); }
		if ($volume < $client->minVolume()) { $volume = $client->minVolume(); }
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
	if (defined($client->tempVolume())) {
		return $client->tempVolume();
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

sub flush {}

sub power {}

sub isValidClientLanguage {
	my $class = shift;
	my $lang  = shift;

	if ($validClientLanguages{$lang}) {
		return 1;
	}

	return 0;
}

#
sub string {
	my $client = shift;
	my $string = shift;

	my $language = Slim::Utils::Strings::getLanguage();

	# We're in the list - ok.
	if ($validClientLanguages{$language}) {

		return Slim::Utils::Unicode::utf8toLatin1(Slim::Utils::Strings::string($string, $language));
	}

	# Otherwise return using the failsafe.
	return Slim::Utils::Strings::string($string, $failsafeLanguage);
}

sub doubleString {
	my $client = shift;
	my $string = shift;

	my $language = Slim::Utils::Strings::getLanguage();

	# We're in the list - ok.
	if ($validClientLanguages{$language}) {

		return Slim::Utils::Unicode::utf8toLatin1(Slim::Utils::Strings::doubleString($string, $language));
	}

	# Otherwise return using the failsafe.
	return Slim::Utils::Strings::doubleString($string, $failsafeLanguage);
}

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

sub prefSet {
	my $client = shift;
	my $pref = shift;
	my $value = shift;
	my $ind = shift;
	
	return Slim::Utils::Prefs::set($pref,$value,$ind,$client,$client->_prefs());
}

sub prefPush {
	my $client = shift;
	my $pref = shift;
	my $value = shift;
	
	Slim::Utils::Prefs::push($pref,$value,$client->_prefs());
}

sub prefDelete {
	my $client = shift;
	my $pref = shift;
	my $ind = shift;
	
	Slim::Utils::Prefs::delete($pref,$ind,$client->_prefs());
}

sub masterOrSelf {
	Slim::Player::Sync::masterOrSelf(@_)
}

sub requestStatus {
}

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

sub shouldLoop {
	my $client = shift;

	return 0;
}

# data accessors

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
sub RTT {
	my $r = shift;
	@_ ? ($r->[11] = shift) : $r->[11];
}
sub prevwptr {
	my $r = shift;
	@_ ? ($r->[12] = shift) : $r->[12];
}
sub waitforstart {
	my $r = shift;
	@_ ? ($r->[13] = shift) : $r->[13];
}
sub readytosync {
	my $r = shift;
	@_ ? ($r->[14] = shift) : $r->[14];
}

sub streamformat {
	my $r = shift;
	@_ ? ($r->[15] = shift) : $r->[15];
}

sub resync {
	my $r = shift;
	@_ ? ($r->[16] = shift) : $r->[16];
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
sub shoutMetaPointer {
	my $r = shift;
	@_ ? ($r->[23] = shift) : $r->[23];
}
sub shoutMetaInterval {
	my $r = shift;
	@_ ? ($r->[24] = shift) : $r->[24];
}
sub currBrightness {
	my $r = shift;
	@_ ? ($r->[25] = shift) : $r->[25];
}
sub prevline1 {
	my $r = shift;
	@_ ? ($r->[26] = shift) : $r->[26];
}
sub prevline2 {
	my $r = shift;
	@_ ? ($r->[27] = shift) : $r->[27];
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

sub bufferThreshold {
	my $r = shift;
	@_ ? ($r->[33] = shift) : $r->[33];
}

sub visualizer {
	my $r = shift;
	@_ ? ($r->[34] = shift) : $r->[34];
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
sub showBrieflyData {
	my $r = shift;
	@_ ? ($r->[53] = shift) : $r->[53];
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
sub pwd {
	my $r = shift;
	@_ ? ($r->[64] = shift) : $r->[64];
}
sub currentDirItem {
	my $r = shift;
	@_ ? ($r->[65] = shift) : $r->[65];
}
sub numberOfDirItems {
	my $r = shift;
	@_ ? ($r->[66] = shift) : $r->[66];
}
sub dirItems {
	my $r = shift;
	my $i;
	@_ ? ($i = shift) : return $r->[67];
	@_ ? ($r->[67]->[$i] = shift) : $r->[67]->[$i];
}
sub lastSelection {
	my $r = shift;
	my $i;
	@_ ? ($i = shift) : return $r->[68];
	@_ ? ($r->[68]->{$i} = shift) : $r->[68]->{$i};
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
sub searchCursor {
	my $r = shift;
	@_ ? ($r->[72] = shift) : $r->[72];
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
sub browseMenuSelection {
	my $r = shift;
	@_ ? ($r->[82] = shift) : $r->[82];
}
sub settingsSelection {
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

sub updateMode {
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

sub renderCache {
	my $r = shift;
	@_ ? ($r->[100] = shift) : $r->[100];
}    

sub scrollData {
	my $r = shift;
	@_ ? ($r->[101] = shift) : $r->[101];
}    

sub periodicUpdateTime {
	my $r = shift;
	@_ ? ($r->[102] = shift) : $r->[102];
}    

sub lastVisMode {
	my $r = shift;
	@_ ? ($r->[103] = shift) : $r->[103];
}    

sub animateState {
	my $r = shift;
	@_ ? ($r->[104] = shift) : $r->[104];
}    

sub scrollState {
	my $r = shift;
	@_ ? ($r->[105] = shift) : $r->[105];
}    

sub lastDigitIndex {
	my $r = shift;
	@_ ? ($r->[106] = shift) : $r->[106];
}

sub lastDigitTime {
	my $r = shift;
	@_ ? ($r->[107] = shift) : $r->[107];
}

sub lastSong {
	my $r = shift;
	@_ ? ($r->[108] = shift) : $r->[108];
}

1;
