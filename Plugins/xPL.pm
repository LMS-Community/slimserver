package Plugins::xPL;
# SlimServer Copyright (C) 2001 Sean Adams, Slim Devices Inc.
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
# xPL Protocol Support Plugin for SlimServer
# http://www.xplproject.org.uk/
#
use strict;
use IO::Socket;
use Scalar::Util qw(blessed);

use Slim::Music::Info;
use Slim::Utils::Misc;
use Slim::Utils::Network;
use Slim::Utils::Prefs;

my $xpl_source = "slimdev-slimserv";
my $localip;
my $xpl_interval;
my $xpl_ir;
my $xpl_socket;
my $xpl_port;

my $d_xpl = 0;


################################################################################
# PLUGIN CODE
################################################################################

# plugin: initialize xPL support
sub initPlugin {

	my $computername = Slim::Utils::Network::hostName();

	$localip = inet_ntoa((gethostbyname($computername))[4]);

	$xpl_interval =	Slim::Utils::Prefs::get("xplinterval");

	if (!defined($xpl_interval)) {
		$xpl_interval = 5;
		Slim::Utils::Prefs::set("xplinterval",$xpl_interval);
	}

	$xpl_ir = Slim::Utils::Prefs::get("xplir");

	if (!defined($xpl_ir)) {
		$xpl_ir = 'none'; 
		Slim::Utils::Prefs::set("xplir",$xpl_ir);
	}

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
	
	Slim::Control::Request::subscribe(\&Plugins::xPL::xplExecuteCallback);
}

sub shutdownPlugin {
	Slim::Control::Request::unsubscribe(\&Plugins::xPL::xplExecuteCallback);
}

# plugin: name of our plugin
sub getDisplayName {
	return 'PLUGIN_XPL';
}

sub enabled {
	return ($::VERSION ge '6.5');
}

# plugin: manage the CLI preference
sub setupGroup {
	my $client = shift;
	
	my %setupGroup = (
		'PrefOrder' => ['xplinterval', 'xplir']
		,'PrefsInTable' => 1
		,'Suppress_PrefHead' => 1
		,'Suppress_PrefDesc' => 1
		,'Suppress_PrefLine' => 1
		,'Suppress_PrefSub' => 1
		,'GroupHead' => Slim::Utils::Strings::string('SETUP_GROUP_XPL')
		,'GroupDesc' => Slim::Utils::Strings::string('SETUP_GROUP_XPL_DESC')
		,'GroupLine' => 1
		,'GroupSub' => 1
	);
	
	my %setupPrefs = (
		'xplinterval' => {
					'validate' => \&Slim::Utils::Validate::isInt
						,'validateArgs' => [5,30,1,1]
				}
		,'xplir' => {
					'options' => {
							'none' => Slim::Utils::Strings::string('SETUP_XPLIR_NONE')
							,'buttons' => Slim::Utils::Strings::string('SETUP_XPLIR_BUTTONS')
							,'raw' => Slim::Utils::Strings::string('SETUP_XPLIR_RAW')
							,'both' => Slim::Utils::Strings::string('SETUP_XPLIR_BOTH')
							}
			}
	);
	
	return (\%setupGroup, \%setupPrefs);

	
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
	my $playmode = $client->playmode;
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

	if ($playmode eq 'play') {
		$playmode = "playing";

		my $track = Slim::Schema->rs('Track')->objectForUrl({
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

	} elsif ($playmode eq 'stop') {
		$playmode = "stopped";
	} elsif ($playmode eq 'pause') {
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
	my $playmode = $client->playmode;
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
		errorMsg("xPL - caught exception when trying to ->send: [$@]\n");
	}
	
	$d_xpl && msg("xPL: sending [$msg]\n\n");

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

	Slim::Utils::Prefs::set("xplinterval",$xpl_interval);
	Slim::Utils::Prefs::set("xplir",$xpl_ir);
	sendXplHBeatMsg($client);
}

# This routine is called when a button is pressed on the remote control.
# It sends out a remote.basic xPL message.
# If xPL support is not enabled, the routine returns immediately.
#sub processircode {
#	$d_xpl && msg("xPL: processircode()\n");
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


# This routine is called by Slim::Command::execute() for each command 
# it processes.

sub xplExecuteCallback {
#	my $client = shift;
#	my $paramsRef = shift;
	my $request = shift;
	
	my $client = $request->client();
	
#	my $command    = $request->getRequest(0);
#	my $subCommand = $request->getRequest(1);

	# callback is all client based below, so avoid a crash and shortcut all of it when no client supplied
	unless (defined $client) {
#		$d_xpl && msg("xPL: xplExecuteCallback without a client: $command - $subCommand\n");
		$d_xpl && msg("xPL: xplExecuteCallback without a client: " . $request->getRequestString() . "\n");
		return;
	}

	
	my $clientname = validInstance($client->name);
	my $power = 'off';
	
	if ($client->can('power')){
		$power = ($client->power()==0 ? 'off' : 'on');
	}
	
#	if ($command eq 'newclient') {
	if ($request->isCommand([['client'], ['new']])) {
		$d_xpl && msg("xPL: xplExecuteCallback for new client\n");
		
		sendXplHBeatMsg($client);
	}
	
#	elsif ($command eq 'power') {
	elsif ($request->isCommand([['power']])) {
		$d_xpl && msg("xPL: xplExecuteCallback for power\n");
		
		sendXplHBeatMsg($client, 1);
	}
	
#	elsif ($command eq 'button' && ($xpl_ir eq 'buttons' || $xpl_ir eq 'both')) {
	elsif ($request->isCommand([['button']]) && ($xpl_ir eq 'buttons' || $xpl_ir eq 'both')) {
		$d_xpl && msg("xPL: xplExecuteCallback for button\n");
		
		my $param = $request->getParam('_buttoncode');
#		sendxplmsg("xpl-trig", "*", "remote.basic", "zone=slimserver\ndevice=$clientname\nkeys=$subCommand\npower=$power", $clientname);
		sendxplmsg("xpl-trig", "*", "remote.basic", "zone=slimserver\ndevice=$clientname\nkeys=$param\npower=$power", $clientname);
	}
	
#	elsif ($command eq 'ir' && ($xpl_ir eq 'raw' || $xpl_ir eq 'both')) {
	elsif ($request->isCommand([['ir']]) && ($xpl_ir eq 'raw' || $xpl_ir eq 'both')) {
		$d_xpl && msg("xPL: xplExecuteCallback for IR\n");
		
		my $param = $request->getParam('_ircode');
#		sendxplmsg("xpl-trig", "*", "remote.basic", "zone=slimserver\ndevice=$clientname\nkeys=$subCommand\npower=$power", $clientname);
		sendxplmsg("xpl-trig", "*", "remote.basic", "zone=slimserver\ndevice=$clientname\nkeys=$param\npower=$power", $clientname);
	}

#	elsif ($command eq 'newsong') {
	elsif ($request->isCommand([['playlist'], ['newsong']])) {
		$d_xpl && msg("xPL: xplExecuteCallback for newsong\n");
		
		sendXplHBeatMsg($client, 1);
	}
	
#	elsif ($command eq 'stop') {
	elsif ($request->isCommand([['stop']]) || $request->isCommand([['mode'], ['stop']])) {
		$d_xpl && msg("xPL: xplExecuteCallback for stop\n");

		sendXplHBeatMsg($client, 1);
	}

}

# plugin: return strings
sub strings {
	return "
PLUGIN_XPL
	EN	xPL Interface
	FR	Interface xPL
	NL	xPL interface
	
SETUP_GROUP_XPL
	DE	xPL Einstellungen
	EN	xPL Settings
	ES	Configuración de xPL
	FR	Paramètres xPL
	JA	xPL セッティング
	NL	xPL instellingen
	NO	xPL-innstillinger
	SV	xPL-inställningar
	ZH_CN	xPL设置

SETUP_GROUP_XPL_DESC
	DE	Diese Einstellungen steuern das Verhalten des xPL Protokolls
	EN	These settings control the behavior of the xPL protocol
	ES	Estos valores controlan el comportamiento del protocolo xPL
	FR	Ces réglages permettent de paramétrer le protocole xPL.
	HE	הגדרות הפרוטוקול
	IT	Queste impostazioni controllano il comportamento del protocollo xPL.
	JA	これらのセッティングはxPLプロトコルを調節します
	NL	Deze instellingen wijzigen het gedrag van het xPL protocol.
	NO	Dette er innstillinger for xPL-protokollen
	SV	Detta är inställningar för xPL-protokollet
	ZH_CN	控制xPL协议的设置

SETUP_XPLSUPPORT
	DE	xPL Support
	EN	xPL support
	ES	soporte xPL
	FR	Support du xPL
	JA	xPL サポート
	NL	xPL ondersteuning
	NO	xPL støtte
	SV	xPL-stöd
	ZH_CN	xPL支持

SETUP_XPLSUPPORT_CHOOSE
	DE	xPL Support:
	EN	xPL support:
	ES	soporte xPL:
	FR	Support du xPL :
	NL	xPL ondersteuning:
	NO	xPL støtte:
	SV	xPL-stöd:
	ZH_CN	xPL支持：

SETUP_XPLINTERVAL
	CS	Interval kontrolního taktu
	DE	Heartbeat Intervall
	EN	Heartbeat Interval
	ES	Intervalo de latidos
	FI	Sykeväli
	FR	Intervale
	JA	インターバル
	NL	Heartbeat interval
	NO	Intervall
	SV	Hjärtrytm, intervall
	ZH_CN	心跳间隔时间

SETUP_XPLINTERVAL_CHOOSE
	CS	Interval kontrolního taktu:
	DE	Heartbeat Intervall:
	EN	Heartbeat Interval:
	ES	Intervalo de latidos:
	FR	Intervalle :
	JA	インターバル:
	NL	Heartbeat interval:
	NO	Intervall:
	SV	Hjärtrytm, intervall:
	ZH_CN	心跳间隔时间：

SETUP_XPLIR
	DE	Infrarot Verarbeitung
	EN	Infra-red Processing
	ES	Procesando Infra-rojo
	FR	Traitement infrarouge
	JA	赤外線プロセシング
	NL	Infrarood verwerking
	NO	Infrarød håndtering
	SV	Infraröd, hantering
	ZH_CN	红外线处理

SETUP_XPLIR_CHOOSE
	DE	Infrarot Verarbeitung:
	EN	Infra-red Processing:
	ES	Procesamiento Infra-rojo
	FR	Traitement infrarouge :
	JA	赤外線プロセシング:
	NL	Infrarood verwerking:
	NO	Infrarød håndtering:
	SV	Infraröd, hantering:
	ZH_CN	红外线处理：

SETUP_XPLIR_NONE
	CS	Není
	DE	Keine
	EN	None
	ES	Ninguno
	FR	Aucun
	HE	אף אחד
	IT	Nessuno
	JA	なし
	NL	Geen
	NO	Ingen
	SV	Ingen
	ZH_CN	无

SETUP_XPLIR_BUTTONS
	CS	Tlačítka
	DE	Tasten
	EN	Buttons
	ES	Botones
	FR	Touches
	HE	כפתורים
	JA	ボタン
	NL	Knoppen
	NO	Knapper
	SV	Knappar
	ZH_CN	按钮

SETUP_XPLIR_RAW
	DE	Roh
	EN	Raw
	ES	Crudo
	FR	Brut
	HE	גולמי
	JA	列
	NL	Ruw (Raw)
	NO	Rå
	SV	Rå
	ZH_CN	生

SETUP_XPLIR_BOTH
	CS	Oba
	DE	Beide
	EN	Both
	ES	Ambos
	FI	Molemmat
	FR	Les deux
	HE	שניהם
	IT	Entrambi
	JA	両方
	NL	Beide
	NO	Begge
	SV	Båda
	ZH_CN	两者皆是
";
}


1;
