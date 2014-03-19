package Slim::Plugin::xPL::Plugin;

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
#
# xPL Protocol Support Plugin for Logitech Media Server
# http://www.xplproject.org.uk/

# $Id: Plugin.pm 10841 2006-12-03 16:57:58Z adrian $

use strict;
use IO::Socket;
use Scalar::Util qw(blessed);

if ( main::WEBUI ) {
	require Slim::Plugin::xPL::Settings;
}

use Slim::Music::Info;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Network;
use Slim::Utils::Prefs;

my $xpl_source = "slimdev-slimserv";
my $localip;
my $xpl_interval;
my $xpl_ir;
my $xpl_socket;
my $xpl_port;

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.xpl',
	'defaultLevel' => 'ERROR',
	'description'  => getDisplayName(),
});

my $prefs = preferences('plugin.xpl');

$prefs->migrate(1, sub {
	require Slim::Utils::Prefs::OldPrefs;
	$prefs->set('interval', Slim::Utils::Prefs::OldPrefs->get('xplinterval') || 5);
	$prefs->set('ir', Slim::Utils::Prefs::OldPrefs->get('xplir') || 'none');
	1;
});

################################################################################
# PLUGIN CODE
################################################################################

# plugin: initialize xPL support
sub initPlugin {

	if ( main::WEBUI ) {
		Slim::Plugin::xPL::Settings->new;
	}

	$localip = Slim::Utils::Network::hostAddr();

	$xpl_interval =	$prefs->get('interval');
	$xpl_ir       = $prefs->get('ir');

	$xpl_port = 50000;

	# Try and bind to a free port
	while (!$xpl_socket && $xpl_port < 50200) {

		$xpl_socket = IO::Socket::INET->new(
			Proto     => 'udp',
			LocalPort => $xpl_port,
			LocalAddr => $main::localClientNetAddr
		);	

		if (!$xpl_socket) {
			$xpl_port = $xpl_port + 1;
		}
	}

	defined(Slim::Utils::Network::blocking($xpl_socket,0)) || die "Cannot set port nonblocking";
	die "Could not create socket: $!\n" unless $xpl_socket;
	Slim::Networking::Select::addRead($xpl_socket, \&readxpl);
	sendxplhbeat();
	
	Slim::Control::Request::subscribe(\&xplExecuteCallback);
}

sub shutdownPlugin {
	Slim::Control::Request::unsubscribe(\&xplExecuteCallback);
}

# plugin: name of our plugin
sub getDisplayName {
	return 'PLUGIN_XPL';
}

sub enabled {
	return ($::VERSION ge '6.5');
}

# This routine ensures an xPL instance is valid
# by removing any invalid characters and trimming to
# a maximum of 16 characters.
sub validInstance {

	my $instance = $_[0];
	$instance =~ s/(-|\.|!|;| )//g;
	if (length($instance) > 16) {
		$instance = substr($instance,0,16);
	}
	return $instance;
}

# This routine accepts an xPL instance and determines if it matches one of our player names
# If it does, it returns the ID of the player.
sub checkInstances {
	my $clientName;
	my $instance;

	foreach my $client (Slim::Player::Client->clients) {
		$instance = lc validInstance($client->name);
		if ($_[0] eq "$xpl_source\.$instance") {
			return $client->id;
		}
	}
	return undef;
}

# Processes an incoming xPL message
sub readxpl {
	my $sock = shift;

	my $schema;
	my $msgtarget;
	my $msg = '';
	my $clientid;

	recv($sock,$msg,1500,0);

	# If message is not for us, ignore it
	$msgtarget = lc(gethdrparam($msg,"target"));

	if ($msgtarget ne "*") {
		$clientid = checkInstances($msgtarget);
		return unless defined $clientid;
	}

	# We're only interested in command messages
	if (getmsgtype($msg) eq "xpl-cmnd") {
		$schema = getmsgschema($msg);
		if ($schema eq "audio.basic" || $schema eq "audio.slimserv") {
			handleAudioMessage($msg,$clientid);
		}
		elsif ($schema eq "audio.request") {
			sendXplHBeatMsg(Slim::Player::Client::getClient($clientid), 1);
		}
		elsif ($schema eq "osd.basic") {
			handleOsdMessage($msg,$clientid);
		}
		elsif ($schema eq "remote.basic" && $msgtarget ne '*') {
			handleRemoteMessage($msg,$clientid);
		}
		elsif ($schema eq 'config.list' && $msgtarget ne '*') {
			handleConfigList($msg,$clientid);
		}
		elsif ($schema eq 'config.response' && $msgtarget ne '*') {
			handleConfigResponse($msg,$clientid);
		}
		elsif ($schema eq 'config.current' && $msgtarget ne '*') {
			handleConfigCurrent($msg,$clientid);
		}
	}
}

sub xplExecuteCmd {
	my @clients = Slim::Player::Client::clients();
	my $clientid;

	# If client ID is undefined, send to all players
	if (!defined($_[1])) {

		foreach my $client (@clients) {
			$clientid = $client->id();
			Slim::Control::Stdio::executeCmd("$clientid $_[0]");
		}

	} else {
		Slim::Control::Stdio::executeCmd("$_[1] $_[0]");
	}
}

# This routine handles audio.basic and audio.slimserv messages
sub handleAudioMessage {
	my $msg = shift;
	my $clientid = shift;


	# If client is undefined, send to all clients
	if (!defined($clientid)) {

		foreach my $client (Slim::Player::Client->clients) {

			$clientid = $client->id;

			if (defined($clientid)) {
				handleAudioMessage($msg,$clientid);
			}
		}

	} else {
		# Handle standard audio.basic commands
		my $xplcmd = lc getparam($msg,"command");
		my @params = split " ", $xplcmd;
		# BACK
		if ($xplcmd eq "back") {
			xplExecuteCmd("playlist index -1",$clientid);
		}
		# Clear
		elsif ($xplcmd eq "clear") {
			xplExecuteCmd("playlist clear",$clientid);
		}
		# Play
		elsif ($xplcmd eq "play") {
			xplExecuteCmd("play",$clientid);
		}
		# SKIP
		elsif ($xplcmd eq "skip") {
			xplExecuteCmd("playlist index +1",$clientid);
		}
		# Stop
		elsif ($xplcmd eq "stop") {
			xplExecuteCmd("stop",$clientid);
		}
		# RANDOM
		elsif ($xplcmd eq "random") {
			xplExecuteCmd("playlist shuffle",$clientid);
		}
		# Volume
		elsif ($xplcmd =~ /^volume (\+|-|<|>)?1?[0-9]{1,2}/) {
			xplExecuteCmd("mixer volume $params[1]",$clientid);
		}
	
		# Handle SlimServ-specific commands
		my $params;
		$xplcmd = getparam($msg, "extended");

		if (!defined($xplcmd)) {
			return;
		}
		if (length($xplcmd)==0) {
			return;
		}	
		if (index($xplcmd,' ') > 0) {
			$params = substr($xplcmd,index($xplcmd,' ')+1,length($xplcmd)-index($xplcmd,' ')-1);
			$xplcmd = substr($xplcmd,0,index($xplcmd,' '));
		}
		else {
			$params = '';
		}
		$xplcmd = lc $xplcmd;

		# AddFile
		if ($xplcmd eq "addfile") {
			$params = Slim::Utils::Misc::escape($params);
			xplExecuteCmd("playlist add $params",$clientid);
		}
		# PLAYFILE
		elsif ($xplcmd eq "playfile") {
			$params = Slim::Utils::Misc::escape($params);
			xplExecuteCmd("playlist play $params",$clientid);
		}
		# CLI commands
		else {
			# we need to lower case all of the protocol
			# words but leave the user content in its
			# original case
			if ($xplcmd eq "playlist") {
				if (index($params, ' ') > 0) {
					my $params_user = substr($params,index($params, ' ')+1, length($params)-index($params, ' ')-1);
					my $params_protocol = lc substr($params, 0, index($params, ' '));
					$params = $params_protocol . " " . $params_user;
	 			}
	 		}
			xplExecuteCmd("$xplcmd $params", $clientid);		
		}
	}
}

# Sends either a hbeat.app or audio.basic status message from a particular client
sub sendXplHBeatMsg {
	my $msg;
	my $client = $_[0];
	my $clientName = validInstance($client->name);
	my $playmode;
	my $song = $client->currentplayingsong();
	my $prevline1 = $client->prevline1();
	my $prevline2 = $client->prevline2();

	my $album = " ";
	my $artist = " ";
	my $trackname = " ";
	my $power = "1";

	if (defined($client->revision())) {
		$power = $client->power();
	}

	if ($client->isPlaying()) {
		$playmode = "playing";

		my $track = Slim::Schema->objectForUrl({
			'url'      => Slim::Player::Playlist::song($client),
			'create'   => 1,
			'readTags' => 1,
		});

		if (blessed($track)) {

			my $albumObj = $track->album;

			if (blessed($albumObj) && $albumObj->can('title')) {

				$album = $albumObj->title;
			}

			my $artistObj = $track->artist;

			if (blessed($artistObj) && $artistObj->can('name')) {

				$artist = $artistObj->name;
			}
		}

		$trackname = Slim::Music::Info::getCurrentTitle($client, Slim::Player::Playlist::url($client));

		# if the song name has the track number at the beginning, remove it
		$trackname =~ s/^[0-9]*\.//g;
		$trackname =~ s/^ //g;

	} elsif ($client->isStopped()) {
		$playmode = "stopped";
	} elsif ($client->isPaused()) {
		$playmode = "paused";
	}

	if (defined($_[1])) {
		$msg = "status=$playmode";
		$msg = "$msg\nARTIST=$artist\nALBUM=$album\nTRACK=$trackname\nPOWER=$power";

		sendxplmsg("xpl-stat", "*","audio.basic", $msg, $clientName);

	} else {
		$msg = "interval=$xpl_interval\nport=$xpl_port\nremote-ip=$localip\nschema=audio.slimserv\nstatus=$playmode";
		$msg = "$msg"; #\nsong=$song\nline1=$prevline1\nline2=$prevline2";

		sendxplmsg("xpl-stat", "*","hbeat.app", $msg, $clientName);
	}
}

# Sends an xPL heartbeat from all clients that are currently connected
sub sendxplhbeat {

	foreach my $client (Slim::Player::Client->clients) {
		sendXplHBeatMsg($client);
	}

	Slim::Utils::Timers::setTimer("", Time::HiRes::time() + ($xpl_interval*60), \&sendxplhbeat);
}
sub sendXplStatusMsg {
	my $msg;
	my $client = $_[0];
	my $status = $_[1];
	my $clientName = validInstance($client->name);
	my $playmode = Slim::Player::Source::playmode($client);
        $msg = "status=$playmode";
        $msg = "$msg\nupdate=$status";

        sendxplmsg("xpl-stat", "*","audio.slimserv", $msg, $clientName);
}

# Generic routine for sending an xPL message.
sub sendxplmsg {
	my $msg = "$_[0]\n{\nhop=1\nsource=$xpl_source.$_[4]\ntarget=$_[1]\n}\n$_[2]\n{\n$_[3]\n}\n";

	my $ipaddr   = inet_aton('255.255.255.255');
	my $portaddr = sockaddr_in(3865, $ipaddr);

	my $sockUDP = IO::Socket::INET->new(
		'PeerPort' => 3865,
		'Proto'    => 'udp',
	);

	$sockUDP->autoflush(1);
	$sockUDP->sockopt(SO_BROADCAST,1);

	eval { $sockUDP->send( Slim::Utils::Unicode::utf8encode($msg), 0, $portaddr ) };

	if ($@) {
		logError("Caught exception when trying to ->send: [$@]");
	}

	main::DEBUGLOG && $log->debug("Sending [$msg]");

	close $sockUDP;
}

# Retrieves a parameter from the body of an xPL message
sub getparam {
	my $buff = $_[0];  
        $buff =~ s/$_[1]/$_[1]/gi;
	$buff = substr($buff,index($buff,"}"),length($buff)-index($buff,"}"));
	$buff = substr($buff,index($buff,"{")+2,length($buff)-index($buff,"{")-2);
	$buff = substr($buff,0,index($buff,"}")-1);
	my %params = map { split /=/, $_, 2 } split /\n/, $buff ;
	return $params{$_[1]};
}

# Retrieves a parameter from the header of an xPL message
sub gethdrparam {
	my $buff = $_[0];  
        $buff =~ s/$_[1]/$_[1]/gi;
	$buff = substr($buff,index($buff,"{")+2,length($buff)-index($buff,"{")-2);
	$buff = substr($buff,0,index($buff,"}")-1);
	my %params = map { split /=/, $_, 2 } split /\n/, $buff ;
	return $params{$_[1]};
}

# Returns the type of an xPL message, e.g. xpl-stat, xpl-trig or xpl-cmnd
sub getmsgtype {
	return lc substr($_[0],0,8);
}

# This routine accepts an xPL message and returns the message schema, in lowercase characters
sub getmsgschema {
	my $buff = $_[0];
	$buff = substr($buff,index($buff,"}")+2,length($buff)-index($buff,"}")-2);
	$buff = substr($buff,0,index($buff,"\n"));
	return lc $buff;
}

# Routine to handle display of text using osd.basic messages
sub handleOsdMessage {

	# If client is undefined, send to all clients
	my $clientid = $_[1];
	if (!defined($clientid)) {

		foreach my $client (Slim::Player::Client->clients) {

			$clientid = $client->id;
			if (defined($clientid)) {
				handleOsdMessage($_[0],$clientid);
			}
		}

	} else {
		my $osdcmd = lc getparam($_[0],"command");
		my $osdmsg = getparam($_[0],"text");
		my $osddelay = getparam($_[0],"delay");
	
		# Extract text
		my ($text1, $text2) = split /\\n/, $osdmsg;

		if ($text1 eq '') {
			$text1 = ' ';
		}

		if (!defined($text2)) {
			$text2 = ' ';
		}	

		# Escape text
		my $esctext1 = Slim::Utils::Misc::escape($text1);
		my $esctext2 = Slim::Utils::Misc::escape($text2);
	
		# If delay is unspecified, set to default of 5 seconds
		if (!defined($osddelay)) {
			$osddelay = 5;
		} elsif ($osddelay eq '') {
			$osddelay = 5;
		}

		# Display the text
		xplExecuteCmd("display $esctext1 $esctext2 $osddelay",$_[1]);

		# Send a confirmation message
		my $clientname = validInstance(Slim::Player::Client::getClient($_[1])->name);	

		sendxplmsg("xpl-trig","*","osd.confirm","command=clear\ntext=$text1\\n$text2\ndelay=$osddelay",$clientname);
	}
}

# Routine to process incoming remote.basic messages
sub handleRemoteMessage {
	my @keys = split ",", getparam($_[0],"keys");

	foreach my $remotekey (@keys) {
		xplExecuteCmd("button $remotekey",$_[1]);
	}
}

# Returns the current xPL configuration of a client
sub handleConfigCurrent {
	my $clientname = validInstance(Slim::Player::Client::getClient($_[1])->name);	

	sendxplmsg("xpl-stat","*","config.current","newconf=$clientname\ninterval=$xpl_interval\ninfrared=$xpl_ir",$clientname);
}

# This sub-routine sends an xPL message in response to a config.list request.
# The config.list message contains information about how this device may be
# configured.
sub handleConfigList {
	my $clientname = validInstance(Slim::Player::Client::getClient($_[1])->name);	

	sendxplmsg("xpl-stat","*","config.list","reconf=newconf\noption=interval\noption=infrared",$clientname);
}

# This sub-routine processes the configuration data in a config.response message
sub handleConfigResponse {
	my $new_instance = getparam($_[0],"newconf");
	my $new_interval = getparam($_[0],"interval");
	my $new_ir = lc getparam($_[0],"infrared");
	my $client = Slim::Player::Client::getClient($_[1]);

	if ($new_instance ne '') {
		$client->name($new_instance);
	}

	if ($new_interval ne '') {
		$xpl_interval = $new_interval;
	}

	if (defined($new_ir) && $new_ir =~ "^(none)|(buttons)|(raw)|(both)") {
		$xpl_ir = $new_ir;
	}

	$prefs->set('interval', $xpl_interval);
	$prefs->set('ir', $xpl_ir);
	sendXplHBeatMsg($client);
}

# This routine is called when a button is pressed on the remote control.
# It sends out a remote.basic xPL message.
# If xPL support is not enabled, the routine returns immediately.
#sub processircode {
#	$log->debug("Begin Function");
#	return unless defined $xpl_port;
#
#	my $clientname = validInstance($_[0]->name);
#	my $power = ($_[0]->power()==0 ? 'off' : 'on');
#
#	if ($xpl_ir eq 'raw' || $xpl_ir eq 'both') {
#		sendxplmsg("xpl-trig","*","remote.basic","zone=slimserver\ndevice=$clientname\nkeys=$_[2]\npower=$power",$clientname);
#	}
#
#	if (defined($_[1]) && ($xpl_ir eq 'buttons' || $xpl_ir eq 'both')) {
#		sendxplmsg("xpl-trig","*","remote.basic","zone=slimserver\ndevice=$clientname\nkeys=$_[1]\npower=$power",$clientname);
#	}
#}

# This routine sends out a heartbeat when a new client is connected.
# It returns immediately if xPL support is not enabled.
#sub newClient {
#	return unless defined $xpl_port;
#
#	sendXplHBeatMsg($_[0]);        
#}

# This routine is called by Slim::Command::execute() for each command it processes.
sub xplExecuteCallback {
	my $request = shift;
	
	my $client = $request->client();
	
	# callback is all client based below, so avoid a crash and shortcut all of it when no client supplied
	if (!defined $client) {

		logWarning("Called without a client: " . $request->getRequestString);
		return;
	}

	my $clientname = validInstance($client->name);
	my $power = 'off';
	
	if ($client->can('power')){
		$power = ($client->power()==0 ? 'off' : 'on');
	}

	if ($request->isCommand([['client'], ['new']])) {

		main::DEBUGLOG && $log->debug("Got new client.");
		
		sendXplHBeatMsg($client);
	}
	
	elsif ($request->isCommand([['power']])) {

		main::DEBUGLOG && $log->debug("Callback for power.");
		
		sendXplHBeatMsg($client, 1);
	}
	
	elsif ($request->isCommand([['button']]) && ($xpl_ir eq 'buttons' || $xpl_ir eq 'both')) {

		main::DEBUGLOG && $log->debug("Callback for button.");

		my $param = $request->getParam('_buttoncode');

		sendxplmsg("xpl-trig", "*", "remote.basic", "zone=slimserver\ndevice=$clientname\nkeys=$param\npower=$power", $clientname);
	}
	
	elsif ($request->isCommand([['ir']]) && ($xpl_ir eq 'raw' || $xpl_ir eq 'both')) {

		main::DEBUGLOG && $log->debug("Callback for IR.");
		
		my $param = $request->getParam('_ircode');

		sendxplmsg("xpl-trig", "*", "remote.basic", "zone=slimserver\ndevice=$clientname\nkeys=$param\npower=$power", $clientname);
	}

	elsif ($request->isCommand([['playlist'], ['newsong']])) {

		main::DEBUGLOG && $log->debug("Callback for newsong.");

		sendXplHBeatMsg($client, 1);
	}

	elsif ($request->isCommand([['stop']]) || $request->isCommand([['mode'], ['stop']])) {

		main::DEBUGLOG && $log->debug("Callback for stop.");

		sendXplHBeatMsg($client, 1);
	}
}

1;
