# $Id: Client.pm,v 1.58 2004/09/24 01:45:20 kdf Exp $

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
package Slim::Player::Client;

use strict;
use Slim::Utils::Misc;
use File::Spec::Functions qw(:ALL);

# depricated, use $client->maxVolume
$Slim::Player::Client::maxVolume = 100;

# This is a hash of clientState structs, indexed by the IP:PORT of the client
# Use the access functions.
my %clientHash = ();

=head1 Object Definition

The following object contains all the state that we keep about each player.

=head1 Client variables id and version info

=over

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

songtotalbytes() - type: float

	length of this song in bytes

=item

songduration() - type: float

	song length in seconds

=item

songoffset() - type: int

	offset in bytes to beginning of song in file

=item

songblockalign() - type: int

	block alignment of samples in file

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

easteregg() - type: string

	IR history for the easter egg, see IR.pm

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

homeSelection() - type: int

	index into home selection: 'music', 'playlist', 'settings', ...

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

searchSelection() - type: int

	index into search selection

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

=back

=head1 games

=over

=item

otype() - type: array

	game obstacles

=item

opos() - type: array

	game obstacles

=item

cpos() - type: int

	game player position

=item

gplay() - type: int

	is the game playing?

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

	scroll selection when in browse menu

=back

=cut

my $defaultPrefs = {
		'maxBitrate'			=> undef # will be set by the client device OR default to server pref when accessed.
		,'alarmvolume'			=> 50
		,'alarm'				=> 0
		,'playername'			=> undef
		,'repeat'				=> 2
		,'shuffle'				=> 0
		,'titleFormat'			=> [5, 1, 3, 6]
		,'titleFormatCurr'		=> 1
	};

sub new {
	my ($class, $id, $paddr) = @_;
	
	# if we haven't seen this client, initialialize a new one
	my $client =[];	
	my $clientAlreadyKnown = 0;
	bless $client, $class;

	$::d_protocol && msg "new client id: ($id)\n";

	assert(!defined(getClient($id)));

	$client->[0] = undef; # id 	

	# client variables id and version info
	$client->[4] = undef; # revision		int        firmware rev   0=unknown, 1.2 = old (1.0, 1.1, 1.2), 1.3 = new streaming protocol, 2.0 = client sends MAC address, NEC IR codes supported
	$client->[5] = undef; # macaddress		string     client's MAC (V2.0 firmware)
	$client->[6] = undef; # paddr			sockaddr_in client's ip and port
	
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
	$client->[21] = undef; # songStartStreamTime
	$client->[22] = 0; # remoteStreamStartTime
	$client->[23] = undef; # shoutMetaPointer
	$client->[24] = undef; # shoutMetaInterval
	$client->[25] = undef; # currBrightness
	$client->[26] = undef; # prevline1
	$client->[27] = undef; # prevline2
	$client->[28] = []; # playlist
	$client->[29] = []; # shufflelist
	$client->[30] = undef; # currentsong
	$client->[31] = undef; # playmode
	$client->[32] = undef; # rate

	$client->[34] = undef; # songtotalbytes
	$client->[35] = undef; # songduration
	$client->[36] = undef; # songoffset
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
	$client->[53] = undef; # easteregg
	$client->[54] = undef; # epochirtime
	$client->[55] = []; # modeStack
	$client->[56] = []; # modeParameterStack
	$client->[57] = undef; # lines
	$client->[58] = []; # trackInfoLines
	$client->[59] = []; # trackInfoContent
	$client->[60] = {}; # lastID3Selection
	$client->[61] = []; # blocklines
	$client->[62] = undef; # homeSelection
	$client->[63] = undef; # pluginsSelection
	$client->[64] = undef; # pwd
	$client->[65] = undef; # currentDirItem
	$client->[66] = undef; # numberOfDirItems
	$client->[67] = []; # dirItems
	$client->[68] =  {}; # lastSelection
	$client->[69] = undef; # searchSelection
	$client->[70] = undef; # searchFor
	$client->[71] = []; # searchTerm
	$client->[72] = undef; # searchCursor
	$client->[73] = undef; # lastLetterIndex
	$client->[74] = undef; # lastLetterDigit
	$client->[75] = undef; # lastLetterTime
	$client->[76] = []; # otype
	$client->[77] = []; # opos
	$client->[78] = undef; # cpos
	$client->[79] = undef; # gplay
	$client->[80] = undef; # syncSelection
	$client->[81] = []; # syncSelections
	$client->[82] = undef; # browseMenuSelection
	$client->[83] = undef; # settingsSelection
	$client->[84] = undef; # songBytes
	$client->[85] = 0; # pauseTime
	$client->[86] = 1; # songblockalign
	$client->[87] = 0; # bytesReceivedOffset
	$client->[88] = 0; # buffersize
	$client->[89] = 0; # streamBytes
	$client->[90] = undef; # trickSegmentRemaining
	$client->[91] = undef; # currentPlaylist
	$client->[92] = undef; # currentPlaylistModified

	$::d_protocol && msg("New client connected: $id\n");
	$client->lastirtime(0);
	$client->lastircode(0);
	$client->lastircodebytes(0);
	$client->startirhold(0);
	$client->epochirtime(0);
	$client->irrepeattime(0);
	$client->irtimediff(0);

	$client->id($id);
	$client->prevwptr(-1);
	$client->pwd('');  # start browsing at the root MP3 directory

	$client->prevline1('');
	$client->prevline2('');

	$client->lastircode('');

	$client->lastLetterIndex(0);
	$client->lastLetterDigit('');
	$client->lastLetterTime(0);

	$client->playmode("stop");
	$client->rate(1);

	$client->currentsong(0);
	$client->songBytes(0);
	$client->songtotalbytes(0);
	$client->currentplayingsong("");

	$client->readytosync(0);

	$client->currentSleepTime(0);
	$client->sleepTime(0);

	$client->RTT(.5);

	$client->searchCursor(0);

	$client->currBrightness(1);

	$clientHash{$id} = $client;

	# make sure any preferences this client may not have set are set to the default
	Slim::Utils::Prefs::initClientPrefs($client,$defaultPrefs);

	$client->paddr($paddr);

	# Tell the xPL module that a new client has connected
	Slim::Control::xPL::newClient($client);

	return $client;
}

###################
# Accessors for the list of known clients

sub clientIPs {
	my @players;
	foreach my $client (values %clientHash) {
		push @players, $client->ipport();
	}
	return @players;
}

sub clientCount {
	return scalar keys %clientHash;
}

sub clients {
	return values %clientHash;
}

# returns ip:port
sub ipport {
	my $client = shift;
	assert(defined($client->paddr));
	assert($client->paddr);
	return Slim::Networking::Protocol::paddr2ipaddress($client->paddr);
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
	if (defined $name) {
		Slim::Utils::Prefs::clientSet($client,"playername", $name);
	}
	$name = Slim::Utils::Prefs::clientGet($client,"playername");
	
	if (!defined $name) {
		$name = defaultName($client);
	}
	
	return $name;
}

sub defaultName {
	my ($name) = split(':', ipport(shift));
	return $name;
}

sub getClient {
	my $id = shift;
	my $ret = $clientHash{$id};
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
	my $id = shift;
	my $client = getClient($id);
	
	if ($client) {
		Slim::Web::HTTP::forgetClient($client);
		Slim::Player::Playlist::forgetClient($client);
		Slim::Utils::Timers::forgetClient($client);
		delete $clientHash{$id};
	}	
}

sub startup {
	my $client = shift;

	my $restoredPlaylist;
	my $currsong = 0;
	my $id = $client->id;
	
	Slim::Player::Sync::restoreSync($client);
	
	# restore the old playlist if we aren't already synced with somebody (that has a playlist)
	if (!Slim::Player::Sync::isSynced($client)) {	
		if (Slim::Utils::Prefs::get('defaultPlaylist')) {
			$restoredPlaylist = Slim::Utils::Prefs::get('defaultPlaylist');
		} elsif (Slim::Utils::Prefs::get('persistPlaylists') && Slim::Utils::Prefs::get('playlistdir')) {
			my $playlistname = "__$id.m3u";
			$playlistname =~ s/\:/_/g;
			$playlistname = catfile(Slim::Utils::Prefs::get('playlistdir'),$playlistname);
			$currsong = Slim::Utils::Prefs::clientGet($client,'currentSong');
			if (-e $playlistname) {
				$restoredPlaylist = $playlistname;
			}
		}
	
		if (defined $restoredPlaylist) {
			Slim::Control::Command::execute($client,['playlist','add',$restoredPlaylist],\&initial_add_done,[$client,$currsong]);
		}
	}
}

sub initial_add_done {
	my ($client,$currsong) = @_;
	
	return unless defined($currsong);
	
	if (Slim::Player::Playlist::shuffle($client) == 1) {
		my $i = 0;
		foreach my $song (@{Slim::Player::Playlist::shuffleList($client)}) {
			if ($song == $currsong) {
				Slim::Control::Command::execute($client,['playlist','move',$i,0]);
				last;
			}
			$i++;
		}
		
		$currsong = 0;
		
		Slim::Player::Source::currentSongIndex($client,$currsong);
		
	} elsif (Slim::Player::Playlist::shuffle($client) == 2) {
		# reshuffle set this properly, for album shuffle
		# no need to move the currentSongIndex
	} else {
		Slim::Player::Source::currentSongIndex($client,$currsong);
	}
	
	Slim::Utils::Prefs::clientSet($client,'currentSong',$currsong);
	if (Slim::Utils::Prefs::get('autoPlay') || Slim::Utils::Prefs::clientGet($client,'autoPlay')) {
		Slim::Control::Command::execute($client,['play']);
	}
}	

sub needsUpgrade {
	return 0;
}

sub signalStrength {
	return undef;
}

sub hasDigitalOut() { return 0; }

sub maxBrightness() { return undef; }

sub maxVolume { return 100; }
sub minVolume {	return 100; }

sub maxPitch {	return 100; }
sub minPitch {	return 100; }

sub maxTreble {	return 50; }
sub minTreble {	return 50; }

sub maxBass {	return 50; }
sub minBass {	return 50; }

sub volume {
	my ($client, $volume, $temp) = @_;

	if (defined($volume)) {
		if ($volume > $client->maxVolume()) { $volume = $client->maxVolume(); }
		if ($volume < $client->minVolume()) { $volume = $client->minVolume(); }
		Slim::Utils::Prefs::clientSet($client, "volume", $volume) if (!$temp);
	}
	return Slim::Utils::Prefs::clientGet($client, "volume");
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
sub animating {}
sub killAnimation {}
sub endAnimation {}
sub showBriefly {}
sub pushLeft {}
sub pushRight {}
sub doEasterEgg {}
sub bumpLeft {}
sub bumpRight {}
sub bumpUp {}
sub bumpDown {}
sub scrollBottom {}
	

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

# data accessors

sub id {
	my $r = shift;
	@_ ? ($r->[0] = shift) : $r->[0];
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
sub currentsong {
	my $r = shift;
	@_ ? ($r->[30] = shift) : $r->[30];
}
sub playmode {
	my $r = shift;
	@_ ? ($r->[31] = shift) : $r->[31];
}
sub rate {
	my $r = shift;
	@_ ? ($r->[32] = shift) : $r->[32];
}




sub songtotalbytes {
	my $r = Slim::Player::Sync::masterOrSelf(shift);
	@_ ? ($r->[34] = shift) : $r->[34];
}
sub songduration {
	my $r = Slim::Player::Sync::masterOrSelf(shift);
	@_ ? ($r->[35] = shift) : $r->[35];
}
sub songoffset {
	my $r = Slim::Player::Sync::masterOrSelf(shift);
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
sub easteregg {
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
	my $i;
	@_ ? ($i = shift) : return $r->[61];
	@_ ? ($r->[61]->[$i] = shift) : $r->[61]->[$i];
}
sub homeSelection {
	my $r = shift;
	@_ ? ($r->[62] = shift) : $r->[62];
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
sub searchSelection {
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
sub otype {
	my $r = shift;
	my $i;
	@_ ? ($i = shift) : return $r->[76];
	@_ ? ($r->[76]->[$i] = shift) : $r->[76]->[$i];
}
sub opos {
	my $r = shift;
	my $i;
	@_ ? ($i = shift) : return $r->[77];
	@_ ? ($r->[77]->[$i] = shift) : $r->[77]->[$i];
}
sub cpos {
	my $r = shift;
	@_ ? ($r->[78] = shift) : $r->[78];
}
sub gplay {
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

sub songblockalign {
	my $r = shift;
	@_ ? ($r->[86] = shift) : $r->[86];
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
	my $r = shift;
	@_ ? ($r->[91] = shift) : $r->[91];
}
sub currentPlaylistModified {
	my $r = shift;
	@_ ? ($r->[92] = shift) : $r->[92];
}

1;
