# Slim Server Copyright (c) 2001, 2002, 2003 Sean Adams, Slim Devices Inc.
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
use Class::Struct;
use Slim::Utils::Misc;
use File::Spec::Functions qw(:ALL);

# This is a hash of clientState structs, indexed by the IP:PORT of the client
# Use the access functions.
my %clientHash = ();

# The following struct contains all the state that we keep about each player.
# Each time we receive a packet for a particular client, we set the global $c
# to point to the struct object for this client.
#

struct( clientState => [

    id                 		=>'$', # string     client's ip & port as string
    
# client variables id and version info
    type             		=>'$', # type 		"player", "http"
   	model					=>'$', # string		"slimp3", "squeezebox"
    deviceid				=>'$', # id			hardware device id (0x01 for slimp3, 0x02 for squeezebox)
    revision                =>'$', # int        firmware rev   0=unknown, 1.2 = old (1.0, 1.1, 1.2), 1.3 = new streaming protocol, 2.0 = client sends MAC address, NEC IR codes supported
    macaddress              =>'$', # string     client's MAC (V2.0 firmware)
    paddr                   =>'$', # sockaddr_in client's ip and port

# client hardware information
	vfdmodel				=>'$', # string		hardware revision number for VFD display module
	decoder                 =>'$', # string     client decoder type: mas3507, shoutcast

# client variables for slim protocol networking
    udpsock                 =>'$', # filehandle the socket we should use to talk to this client
    tcpsock                 =>'$', # filehandle the socket we should use to talk to this client
    RTT                     =>'$', # float      rtt estimate (seconds)
    prevwptr                =>'$', # int        wptr at previous request - see protocol docs
 
    waitforstart            =>'$', # bool       1 = we've sent the client the start command, and we're waiting
                                   #            for him to start a new stream
    readytosync             =>'$', # bool       when starting a new synced stream, indicates whether this 
                                   #            client is ready to be unpaused. 
    usage					=>'$', # float		buffer fullness as a percentage
	resync					=>'$', # bool		1 if we are in the process of resyncing clients
	    
# client variables for HTTP protocol clients
	streamingsocket			=>'$', # filehandle streaming socket for http clients
	
# client variables for song data
    mp3filehandle           =>'$', # filehandle the currently open MP3 file OR TCP stream
    mp3filehandleIsSocket   =>'$', # bool       becase Windows gets confused if you select on a regular file.
    chunks                  =>'@', # array      array of references to chunks of data to be sent to client.
    lastchunk               =>'$', # ref        ref to the last chunk sent to this client, for retransmissions
    remoteStreamStartTime   =>'$', # int        time we began playing the remote stream

# client variables for shoutcast meta information 
    shoutMetaPointer        =>'$', # int        shoutcast metadata stream pointer
    shoutMetaInterval       =>'$', # int        shoutcast metadata interval

# client variables for display
    vfdbrightness           =>'$', # int        current brightness setting of the client's VFD display, range 0..4
    prevline1               =>'$', # string     what's currently on the the client's display, line 1
    prevline2               =>'$', # string     and line 2
	
# client variables for current playlist and mode
    playlist                => '@', # array     playlist of songs  (when synced, use the master's)
    shufflelist             => '@', # array     array of indices into playlist which may be shuffled (when synced, use the master's)
    currentsong             => '$', # int       index into the playlist of the currently playing song (updated when reshuffled)

    playmode                => '$', # string    'stop', 'play', or 'pause'
    rate		            => '$', # float		playback rate: 1 is normal, 0 is paused, 2 is ffwd, -1 is rew
	lastskip				=> '$', # time		last time we skipped forward or back while playing at a non-1 rate
    songtotalbytes          => '$', # float     length of this song in bytes
    songduration			=> '$', # float     song length in seconds
	songoffset				=> '$', # int		offset in bytes to beginning of song in file
    songpos                 => '$', # int       position in current song (not incl. buffer)
    currentplayingsong      => '$', # string    current song that's playing out from player.  May not be the same as in the playlist as the client's buffer plays out.

# client variables for sleep
    currentSleepTime        => '$', # int       what the sleep time is currently set to (in minutes)
	sleepTime				=> '$', # int		time() value for when we'll sleep
	
# client variables for synchronzation
    master                  => '$', # client    if we're synchronized, 'master' points to master client
    slaves                  => '@', # clients   if we're a master, this is an array of slaves which are synced to us
    syncgroupid				=> '$', # uniqueid	unique identifier for this sync group

# client variables for HTTP status caching
    htmlstatus              => '$', # string    html formatted status page
    htmlstatusvalid         => '$', # bool      current status is valid?

# client variables are for IR processing
    lastirtime              =>'$', # int        time at which we last received an IR code (in client's 625KHz ticks)
    lastircode              =>'$', # string     the last IR command we received, so we can tell if a button's being held down
    lastircodebytes         =>'$', # string     the last IR code we received, so we can tell if a button's being held down
	ticspersec				=>'$', # int		number of IR tics per second
    startirhold             =>'$', # string     the first time the button was pressed, so we can tell how long the button is held
    irtimediff              =>'$', # float      calculated diff ir time
    irrepeattime            =>'$', # float      calculated time for repeat codes
    easteregg               =>'$', # string     IR history for the easter egg, see IR.pm
    epochirtime             =>'$', # int        epoch time that we last received an IR signal

# state for button navigation
    modeStack               =>'@', # array      stack of current browse modes: 'playlist', 'browse', 'off', etc...
	modeParameterStack		=>'@', # array		stack of hashes of mode parameters for previous modes
    lines                   =>'$', # \function  reference to function to display lines for current mode
	

#
# the remainder are temporary and global client variables are for the various button display modes
#

# trackinfo mode
    trackInfoLines          =>'@', # strings    current trackinfo lines
    trackInfoContent		=>'@', # strings	content type for trackinfo lines.

# browseid3 mode
    lastID3Selection  		=>'%', # hash       the item that was last selected for a given browse position

# blocked mode
    blocklines              =>'@', # strings    what to display when we're blocked.

# home mode
    homeSelection           =>'$', # int        index into home selection: 'music', 'playlist', 'settings', ...

# plugins mode
    pluginsSelection        =>'$', # int        index into plugins list

# browse music folder mode
    pwd                     =>'$', # string     present directory, relative to $mp3dir
    currentDirItem          =>'$', # int        the index of the currently selected item (in @dirItems)
    numberOfDirItems        =>'$', # int        size of @dirItems    FIXME this is redundant, right?
    dirItems                =>'@', # strings    list of file names in the current directory
    lastSelection           =>'%', # hash       the curdiritem (integer) that was selected last time we
                                   #            were in each directory (string)
# search mode
    searchSelection         => '$', # int       index into search selection
    searchFor               => '$', # string    what we are searching for from the remote: "ALBUMS", "ARTISTS", "SONGS"
    searchTerm              => '@', # array     of characters we are searching for
    searchCursor            => '$', # int       position of cursor (zero based)

    lastLetterIndex         => '$', # int       index into letters for each digit when using digits to type letters
    lastLetterDigit         => '$', # int       last digit hit while entering text
    lastLetterTime          => '$', # int       epoch time of previous letter

# games
    otype                   => '@', # array     game obstacles
    opos                    => '@', # array     game obstacles
    cpos                    => '$', # int       game player position
    gplay                   => '$', # int       is the game playing?

# synchronization mode
	syncSelection			=> '$', # int		scroll selection while in the syncronization screen, 0 is to unsync
	syncSelections			=> '@', # clients	addresses of possible syncable selections

# browse menu mode
	browseMenuSelection		=> '$', # int		scroll selection when in browse menu
	
# settings menu mode
	settingsSelection	=> '$', # int		scroll selection when in browse menu
	
]);


###################
# Accessors for the list of known clients

sub clientIPs {
	my @players;
	foreach my $client (values %clientHash) {
		push @players, ipaddress($client);
	}
	return @players;
}

sub clientCount {
	return scalar keys %clientHash;
}

sub clients {
	return values %clientHash;
}

sub id {
	my $client = shift; 
	if (!defined($client)) { 
		warn "null client for id\n";
		bt(); 
	} else {
		return $client->id;
	}
}

sub ipaddress {
	my $client = shift;
	assert(defined($client->paddr));
	assert($client->paddr);
	return Slim::Networking::Protocol::paddr2ipaddress($client->paddr);
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
	my ($name) = split(':', ipaddress(shift));
	return $name;
}

sub getClient {
	my $id = shift;
	return $clientHash{$id};
}

sub newClient {
	my (
		$id,
		$paddr,
		$newplayeraddr,
		$deviceid,
		$revision,
		$udpsock,		# defined only for Slimp3
		$tcpsock,		# defined only for squeezebox
	) = @_;
	
	# if we haven't seen this client, initialialize a new one
	my $client;	
	my $clientAlreadyKnown = 0;

	if (defined(getClient($id))) {
		$::d_protocol && msg("We know this client. Skipping client prefs and state initialization.\n");
		$client=getClient($id);
		$clientAlreadyKnown = 1;
	} else {
		$::d_protocol && msg("New client connected: $id\n");
		$client = clientState->new();
		$client->revision(0);
		$client->lastirtime(0);
		$client->lastircode(0);
		$client->lastircodebytes(0);
		$client->startirhold(0);
		$client->epochirtime(0);
		$client->irrepeattime(0);
		$client->irtimediff(0);
	
		$client->vfdmodel('');
		$client->decoder('');

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
		$client->lastskip(0);
	
		$client->currentsong(0);
		$client->songpos(0);
		$client->songtotalbytes(0);
		$client->currentplayingsong("");
	
		$client->lastchunk(undef);

		$client->readytosync(0);

		$client->currentSleepTime(0);
		$client->sleepTime(0);
		
		$client->htmlstatus("");
		$client->htmlstatusvalid(0);

		$client->RTT(.5);

		$client->searchCursor(0);
	
		$client->vfdbrightness(1);

		$clientHash{$id} = $client;
		# make sure any preferences this client may not have set are set to the default
		Slim::Utils::Prefs::checkClientPrefs($client);

		# skip player initialization for http clients
		return unless (defined($newplayeraddr) && $newplayeraddr);
	}

	# the rest of this stuff is set each time the client connects, even if we know him already.

	$client->paddr($paddr);

	# initialize model-specific features:

	$client->deviceid($deviceid);
	$client->revision($revision);
	$client->udpsock($udpsock);
	$client->tcpsock($tcpsock);

	if ($deviceid==0) {
		$client->type('http');
		
		$client->streamingsocket($tcpsock);
		
	} elsif ($deviceid==1) {

		$client->type('player');
		$client->model('slimp3');
		$client->ticspersec(625000);

		$client->decoder('mas3507d');

		if ($revision >= 2.2) {
			my $mac = $id;
			$client->macaddress($mac);
			if ($mac eq '00:04:20:03:04:e0') {
				$client->vfdmodel('futaba-latin1');
			} elsif ($mac eq '00:04:20:02:07:6e' ||
					$mac =~ /^00:04:20:04:1/ ||
					$mac =~ /^00:04:20:00:/	) {
				$client->vfdmodel('noritake-european');
			} else {
				$client->vfdmodel('noritake-katakana');
			}
		} else {
			$client->vfdmodel('noritake-katakana');
		}		

	} elsif ($deviceid==2) {	# squeezebox
		$client->type('player');
		$client->model('squeezebox');
		$client->ticspersec(1000);

		$client->vfdmodel('noritake-european');
		$client->decoder('mas35x9');
	}

	# skip the rest of this if the client was already known
	$clientAlreadyKnown && 
		return($client);

	# add the new client all the currently known clients so we can say hello to them later
	my $clientlist = Slim::Utils::Prefs::get("clients");

	if (defined($clientlist)) {
		$clientlist .= ",$newplayeraddr";
	} else {
		$clientlist = $newplayeraddr;
	}

	my %seen = ();
	my @uniq = ();  

	foreach my $item (split( /,/, $clientlist)) {
		push(@uniq, $item) unless $seen{$item}++ || $item eq '';
	}
	Slim::Utils::Prefs::set("clients", join(',', @uniq));

	# fire it up!
	($client->type eq 'player') && Slim::Player::Client::power($client,Slim::Utils::Prefs::clientGet($client, 'power'));
	Slim::Player::Client::startup($client);
                
	# start the screen saver
	($client->type eq 'player') && Slim::Buttons::ScreenSaver::screenSaver($client);

	return $client;
}

sub startup {
	my $client = shift;

	my $restoredPlaylist;
	my $currsong = 0;
	my $id = $client->id;
	
	Slim::Player::Playlist::restoreSync($client);
	
	# restore the old playlist if we aren't already synced with somebody (that has a playlist)
	if (!Slim::Player::Playlist::isSynced($client)) {	
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
			Slim::Control::Command::execute($client,['playlist','add',$restoredPlaylist],\&initial_add_done,[$client,0]);
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
		Slim::Player::Playlist::currentSongIndex($client,0);
	} elsif (Slim::Player::Playlist::shuffle($client) == 2) {
		# reshuffle set this properly, for album shuffle
		# no need to move the currentSongIndex
	} else {
		Slim::Player::Playlist::currentSongIndex($client,$currsong);
	}
	Slim::Utils::Prefs::clientSet($client,'currentSong',$currsong);
	if (Slim::Utils::Prefs::get('autoPlay') || Slim::Utils::Prefs::clientGet($client,'autoPlay')) {
		Slim::Control::Command::execute($client,['play']);
	}
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

sub power {
	my $client = shift;
	my $on = shift;
	
	if (!isPlayer($client)) {
		return 1;
	}
	my $mode = Slim::Buttons::Common::mode($client);
	my $currOn;
	if (defined($mode)) {
		$currOn = $mode ne "off" ? 1 : 0;
	}
	
	if (!defined $on) {
		return ($currOn);
	} else {
		if (!defined($currOn) || ($currOn != $on)) {
			if ($on) {
				Slim::Buttons::Common::setMode($client, 'home');
				
				
				my $welcome =  Slim::Display::Display::center(Slim::Utils::Strings::string(Slim::Utils::Prefs::clientGet($client, "doublesize") ? 'SQUEEZEBOX' : 'WELCOME_TO_SQUEEZEBOX'));
				my $welcome2 = Slim::Utils::Prefs::clientGet($client, "doublesize") ? '' : Slim::Display::Display::center(Slim::Utils::Strings::string('FREE_YOUR_MUSIC'));
				Slim::Display::Animation::showBriefly($client, $welcome, $welcome2);
				
				# restore the saved brightness, unless its completely dark...
				my $powerOnBrightness = Slim::Utils::Prefs::clientGet($client, "powerOnBrightness");
				if ($powerOnBrightness < 1) { 
					$powerOnBrightness = 1;
				}
				Slim::Utils::Prefs::clientSet($client, "powerOnBrightness", $powerOnBrightness);
				#check if there is a sync group to restore
				Slim::Player::Playlist::restoreSync($client);
				# restore volume (un-mute if necessary)
				my $vol = Slim::Utils::Prefs::clientGet($client,"volume");
				if($vol < 0) { 
					# un-mute volume
					$vol *= -1;
					Slim::Utils::Prefs::clientSet($client, "volume", $vol);
				}
				Slim::Control::Command::execute($client, ["mixer", "volume", $vol]);
			
			} else {
				Slim::Buttons::Common::setMode($client, 'off');
			}
			# remember that we were on if we restart the server
			Slim::Utils::Prefs::clientSet($client, 'power', $on ? 1 : 0);
		}
	}
}			

sub isPlayer {
	my $client = shift;
	assert($client);
	assert($client->type);
	return ($client->type eq 'player');
}

1;
