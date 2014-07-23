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

use strict;

use base qw(Slim::Utils::Accessor);

use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Network;
use Slim::Utils::Prefs;
use Slim::Utils::Strings;
use Slim::Utils::Timers;

if ( !main::SLIM_SERVICE && !main::SCANNER ) {
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

# deprecated, use $client->maxVolume
our $maxVolume = 100;

# This is a hash of clientState structs, indexed by the IP:PORT of the client
# Use the access functions.
our %clientHash = ();

our $modeParameterStackIndex;

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
								modeStack modeParameterStack playlist _playlist chunks
								shuffleInhibit syncSelections searchTerm
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
		_playlist               => undef,				# Will probably migrate to StreamingController
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
	
	# On SN, we need to fully load all the player's prefs from the database
	# before going further
	if ( main::SLIM_SERVICE ) {
		$client->loadPrefs();
	}

	if (main::LOCAL_PLAYERS) {
		require Slim::Player::StreamingController;
		
		$client->controller(Slim::Player::StreamingController->new($client));
	
		if (!main::SCANNER) {	
			Slim::Control::Request::notifyFromArray($client, ['client', 'new']);
		}
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

	Slim::Utils::Alarm->loadAlarms($client) if main::LOCAL_PLAYERS;
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
	return grep { $_->isLocalPlayer } values %clientHash;
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
	return scalar( main::LOCAL_PLAYERS ? clients() : 0 );
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
		
		if ( main::SLIM_SERVICE && $client->playerData ) {
			$name = $client->playerData->name;
		}
	}

	return $name;
}

# If this player does not have a name set, then find the first 
# unused name from the sequence ("Name", "Name 2", "Name 3", ...),
# where Name, is the result of the modelName() method. Consider
# all the players ever known to this SC in finding an unused name.
sub _makeDefaultName {
	my $client = shift;
	
	# This method is not useful on SN
	return if main::SLIM_SERVICE;

	my $modelName = $client->modelName() || $client->ip;

	my $name;
	my %existingName;

	foreach my $clientPref ( $prefs->allClients ) {
		$existingName{ $clientPref->get('playername') || 'UE Smart Radio' } = 1;
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
	
	if ( main::SLIM_SERVICE || !main::LOCAL_PLAYERS ) {
		# There is no point making the below lookups, which add massive
		# amounts of DB calls when name() is called and lots of other
		# clients are connected
		return ($ret);
	}

	# Try a brute for match for the client.
	if (!defined($ret)) {
   		 for my $value ( values %clientHash ) {
			return $value if (ipport($value) eq $id);
			return $value if (ip($value) eq $id);
			return $value if (name($value) eq $id);
			return $value if (id($value) eq $id);
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
		# Clean up global variables used in various modules
		if (main::IP3K) {
			Slim::Buttons::Common::forgetClient($client);
			Slim::Buttons::Home::forgetClient($client);
			Slim::Buttons::Input::Choice::forgetClient($client);
			Slim::Buttons::Playlist::forgetClient($client);
		}
		Slim::Utils::Timers::forgetTimer($client);
		
		if ( !main::SLIM_SERVICE && !main::SCANNER ) {
			Slim::Web::HTTP::forgetClient($client);
		}
		
		if (main::LOCAL_PLAYERS) {
			Slim::Utils::Alarm->forgetClient($client) if main::LOCAL_PLAYERS;
	
			$client->controller()->unsync($client, 'keepSyncGroupId');
			
			$client->display->forgetDisplay();
		
			# stop watching this player
			delete $Slim::Networking::Slimproto::heartbeat{ $client->id };
			
			# Bug 15860: Force the connection shut if it is not already
			Slim::Networking::Slimproto::slimproto_close($client->tcpsock()) if defined $client->tcpsock();
		}

		delete $clientHash{ $client->id };
	}
}

# Wrapper method so "execute" can be called as an object method on $client.
sub execute {
	my $self = shift;

	return Slim::Control::Request::executeRequest($self, @_);
}

sub string {
	$_[0]->display && return shift->display->string(@_);
}

sub hasDigitalIn() { return 0; }

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

sub pluginData {
	my ( $client, $key, $value ) = @_;
	
	my $namespace;
	
	# if called from a plugin, we automatically use the plugin's namespace for keys
	my $package;
	if ( main::SLIM_SERVICE ) {
		# pluginData is called from SNClient, need to increase caller stack
		$package = caller(1);
	}
	else {
		$package = caller(0);
	}
	
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

sub revisionNumber { $_[0]->revision }

{
	if (main::LOCAL_PLAYERS) {
		require Slim::Player::LocalClient;
	}
}


1;
