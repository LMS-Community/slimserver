package Plugins::CLI;

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use IO::Socket;
use Socket qw(:crlf);
use Scalar::Util qw(blessed);
use URI::Escape;

use Slim::Control::Request;
use Slim::Music::Import;
use Slim::Music::Info;
use Slim::Networking::mDNS;
use Slim::Networking::Select;
use Slim::Utils::Misc;
use Slim::Utils::Network;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Unicode;
use Slim::Web::Pages::Search;

# This plugin provides a command-line interface to the server via a TCP/IP port.
# See cli-api.html for documentation.

# Queries and commands handled by this module:
#  albums
#  artists
#  exit
#  genres
#  info
#  login
#  listen
#  player
#  players
#  playlists
#  playlisttracks
#  songinfo
#  titles, tracks, songs
#  version
# Other CLI queries/commands are handled in Command.pm


my $d_cli_v = 0;			# verbose debug, for developpement
my $d_cli_vv = 0;			# very verbose debug, function calls...


my $cli_socket;				# server socket
my $cli_socket_port = 0;	# CLI port on which socket is opened

my $cli_busy = 0;			# 1 if CLI is processing command

our %connections;			# hash indexed by client_sock value
							# each element is a hash with following keys
							# .. id: 		"IP:PORT" for debug
							# .. socket: 	the socket (a hash key is *not* an object, but the value is...)
							# .. inbuff: 	input buffer
							# .. outbuff: 	output buffer (array)
							# .. listen:	listen command value for this connection
							# .. auth:		1 if connection authenticated (login)
							

################################################################################
# PLUGIN CODE
################################################################################

# plugin: initialize the command line interface server
sub initPlugin {

	$d_cli_vv && msg("CLI: initPlugin()\n");

	# enable general debug if verbose debug is on
	$::d_cli = $d_cli_v;
	
	# make sure we have a default value for our preference
	if (!defined Slim::Utils::Prefs::get('cliport')) {
		Slim::Utils::Prefs::set('cliport', 9090);
	}
	
	# open our socket
	cli_socket_change();
}

# plugin: name of our plugin
sub getDisplayName {
	return 'PLUGIN_CLI';
}

# plugin: manage the CLI preference
sub setupGroup {
	my $client = shift;
	
	my %setupGroup = (
		PrefOrder => ['cliport'],
	);
	
	my %setupPrefs = (
		'cliport'	=> {
			'validate' => \&Slim::Web::Setup::validatePort,
			'onChange' => \&cli_socket_change,
		}
	);
	
	return (\%setupGroup, \%setupPrefs);
}


# plugin: shutdown the CLI
sub shutdownPlugin {

	$d_cli_vv && msg("CLI: shutdownPlugin()\n");

	# close all connections
	foreach my $client_socket (keys %connections) {

		# retrieve the socket object
		$client_socket = $connections{$client_socket}{'socket'};
		
		# close the connection
		client_socket_close($client_socket);
	}
	
	# close the socket
	cli_socket_close();
}


################################################################################
# SOCKETS
################################################################################

# start our listener
sub cli_socket_open {
	my $listenerport = shift;

	$d_cli_vv && msg("CLI: cli_socket_open($listenerport)\n");

	if ($listenerport) {

		$cli_socket = IO::Socket::INET->new(  
			Proto     => 'tcp',
			LocalPort => $listenerport,
			LocalAddr => $::cliaddr,
			Listen    => SOMAXCONN,
			ReuseAddr => 1,
			Reuse     => 1,
			Timeout   => 0.001
		) or die "CLI: Can't setup the listening port $listenerport: $!";
	
		$cli_socket_port = $listenerport;
	
		Slim::Networking::Select::addRead($cli_socket, \&cli_socket_accept);
	
		Slim::Networking::mDNS->addService('_slimcli._tcp', $cli_socket_port);
	
		Slim::Control::Command::setExecuteCallback(\&Plugins::CLI::cli_executeCallback);
		
		$::d_cli && msg("CLI: Now accepting connections on port $listenerport\n");
	}
}


# open or change our socket
sub cli_socket_change {

	$d_cli_vv && msg("CLI: cli_socket_change()\n");

	# get the port we must use
	my $newport = Slim::Utils::Prefs::get('cliport');

	# if the port changed...
	if ($cli_socket_port != $newport) {

		# if we've already opened a socket, let's close it
		# (this is false the first time through)
		if ($cli_socket_port) {
			cli_socket_close();
		}

		# if we've got an command line interface port specified, open it up!
		if ($newport) {
			cli_socket_open($newport);
		}
	}
}


# stop our listener on cli_socket_port
sub cli_socket_close {

	$d_cli_vv && msg("CLI: cli_socket_close()\n");

	if ($cli_socket_port) {

		$::d_cli && msg("CLI: Closing socket $cli_socket_port\n");
	
		Slim::Networking::mDNS->removeService('_slimcli._tcp');
		
		Slim::Networking::Select::addRead($cli_socket, undef);
		$cli_socket->close();
		$cli_socket_port = 0;
		Slim::Control::Command::clearExecuteCallback(\&Plugins::CLI::cli_executeCallback);
	}
}


# accept new connection!
sub cli_socket_accept {

	$d_cli_vv && msg("CLI: cli_socket_accept()\n");

	# Check max connections
	if (scalar keys %connections > Slim::Utils::Prefs::get("tcpConnectMaximum")) {
		$::d_cli && msg("CLI: Did not accept connection: too many connections open\n");
		return;
	}

	my $client_socket = $cli_socket->accept();

	if ($client_socket && $client_socket->connected && $client_socket->peeraddr) {

		my $tmpaddr = inet_ntoa($client_socket->peeraddr);

		# Check allowed hosts
		
		if (!(Slim::Utils::Prefs::get('filterHosts')) || (Slim::Utils::Network::isAllowedHost($tmpaddr))) {

			Slim::Networking::Select::addRead($client_socket, \&client_socket_read);
			Slim::Networking::Select::addError($client_socket, \&client_socket_close);
			
			$connections{$client_socket}{'socket'} = $client_socket;
			$connections{$client_socket}{'id'} = $tmpaddr.':'.$client_socket->peerport;
			$connections{$client_socket}{'inbuff'} = '';
			$connections{$client_socket}{'outbuff'} = ();
			$connections{$client_socket}{'listen'} = 0;
			$connections{$client_socket}{'auth'} = !Slim::Utils::Prefs::get('authorize');
			$connections{$client_socket}{'terminator'} = $LF;

			$::d_cli && msg("CLI: Accepted connection from ". $connections{$client_socket}{'id'} . " (" . (scalar keys %connections) . " active connections)\n");
		} 
		else {
			
			$::d_cli && msg("CLI: Did not accept connection from ". $tmpaddr . ": unauthorized source\n");
			$client_socket->close();
		}

	} else {
		$::d_cli && msg("CLI: Could not accept connection\n");
	}
}


# close connection
sub client_socket_close {
	my $client_socket = shift;
	
	$d_cli_vv && msg("CLI: client_socket_close()\n");


	my $client_id = $connections{$client_socket}{'id'};
		
	Slim::Networking::Select::addWrite($client_socket, undef);
	Slim::Networking::Select::addRead($client_socket, undef);
	Slim::Networking::Select::addError($client_socket, undef);
	
	close $client_socket;
	delete($connections{$client_socket});
	
	$::d_cli && msg("CLI: Closed connection with $client_id (" . (scalar keys %connections) . " active connections)\n");
}


# data from connection
sub client_socket_read {
	my $client_socket = shift;
	use bytes;
	
	$d_cli_vv && msg("CLI: client_socket_read()\n");


	if (!defined($client_socket)) {
		$::d_cli && msg("CLI: client_socket undefined in client_socket_read()!\n");
		return;		
	}

	if (!($client_socket->connected)) {
		$::d_cli && msg("CLI: connection with " . $connections{$client_socket}{'id'} . " closed by peer\n");
		client_socket_close($client_socket);		
		return;
	}			

	my $bytes_to_read = 100;
	my $indata = '';
	my $bytes_read = $client_socket->sysread($indata, $bytes_to_read);

	if (!defined($bytes_read) || ($bytes_read == 0)) {
		$::d_cli && msg("CLI: connection with " . $connections{$client_socket}{'id'} . " half-closed by peer\n");
		client_socket_close($client_socket);		
		return;
	}

	$connections{$client_socket}{'inbuff'} .= $indata;
	
	# only parse when we're not busy
	client_socket_buf_parse($client_socket) unless $cli_busy;
}

# parse buffer data
sub client_socket_buf_parse {
	my $client_socket = shift;

	$d_cli_vv && msg("CLI: client_socket_buf_parse()\n");

	# parse our buffer to find LF, CR, CRLF or even LFCR (for nutty clients)	
	while ($connections{$client_socket}{'inbuff'}) {

		if ($connections{$client_socket}{'inbuff'} =~ m/([^\r\n]*)([$CR|$LF|$CR$LF|\x0]+)(.*)/s) {
			
			# $1 : command
			# $2 : terminator used
			# $3 : rest of buffer

			# Keep the leftovers for the next run...
			$connections{$client_socket}{'inbuff'} = $3;

			# Remember the terminator used
			$connections{$client_socket}{'terminator'} = $2;
			if ($::d_cli) {
				my $str;
				for (my $i = 0; $i < length($2); $i++) {
					$str .= ord(substr($2, $i, 1)) . " ";
				}
				msg("CLI: using terminator $str\n");
			}

			# Process the command
			# Indicate busy so that any incoming data is buffered and not parsed
			# during command processing
			$cli_busy = 1;
			my $exit = cli_process($client_socket, $1);
			$cli_busy = 0;
			
			if ($exit) {
				client_socket_write($client_socket);
				client_socket_close($client_socket);
				return;
			}
		}
		else {
			# there's data in our buffer but it doesn't match 
			# so wait for more data...
			last;
		}
	}
}


# data to connection
sub client_socket_write {
	my $client_socket = shift;

	$d_cli_vv && msg("CLI: client_socket_write()\n");

	my $message = shift(@{$connections{$client_socket}{'outbuff'}});
	my $sentbytes;

	return unless $message;

	$::d_cli && msg("CLI: Sending response...\n");
	
	$sentbytes = send($client_socket, $message, 0);

	unless (defined($sentbytes)) {

		# Treat $clientsock with suspicion
		$::d_cli && msg("CLI: Send to " . $connections{$client_socket}{'id'}  . " had error\n");
		client_socket_close($client_socket);

		return;
	}

	if ($sentbytes < length($message)) {

		# sent incomplete message
		unshift @{$connections{$client_socket}{'outbuff'}}, substr($message, $sentbytes);

	} else {

		# sent full message
		if (@{$connections{$client_socket}{'outbuff'}} == 0) {

			# no more messages to send
			$::d_cli && msg("CLI: No more messages to send to " . $connections{$client_socket}{'id'}  . "\n");
			Slim::Networking::Select::addWrite($client_socket, undef);
			
		} else {
			$::d_cli && msg("CLI: More to send to " . $connections{$client_socket}{'id'}  . "\n");
		}
	}
}


# buffer a response
sub client_socket_buffer {
	my $client_socket = shift;
	my $message = shift;

	$d_cli_vv && msg("CLI: client_socket_buffer()\n");

	push @{$connections{$client_socket}{'outbuff'}}, $message;
	Slim::Networking::Select::addWrite($client_socket, \&client_socket_write);
}

################################################################################
# COMMAND PROECESSING
################################################################################


# process command 
sub cli_process {
	my($client_socket, $command) = @_;

	$d_cli_vv && msg("CLI: cli_process($command)\n");
	
	my $exit = 0;
	my $writeoutput = 1;

	# Parse the command
	my $cmdRef = cli_command_parse($client_socket, $command);
	
	return if !defined $cmdRef;
	
	my $cmd = $cmdRef->{'_command'};
	my $encoding = $cmdRef->{'charset'} || "utf8";
	
	$::d_cli && msg("CLI: Processing command [$cmd]\n");
	
	# Try pureblood
	if ($cmd eq 'login') {
		$exit = cli_cmd_login($client_socket, $cmdRef);
	}
	
	elsif ($connections{$client_socket}{'auth'} == 0) {
			$::d_cli && msg("CLI: Connection requires authentication, bye!\n");
			$exit = 1;
	}
	
	else {
		
		if ($cmd eq 'exit'){
			$exit = 1;
		}

		elsif ($cmd eq 'albums') {
			cli_cmd_artists_albums_genres($client_socket, $cmdRef);
		}
		
		elsif ($cmd eq 'artists') {
			cli_cmd_artists_albums_genres($client_socket, $cmdRef);
		}
				
		elsif ($cmd eq 'genres') {
			cli_cmd_artists_albums_genres($client_socket, $cmdRef);
		}

#		elsif ($cmd eq 'info') {
#			cli_cmd_info($client_socket, $cmdRef);
#		}
		
		elsif ($cmd eq 'listen') {
			cli_cmd_listen($client_socket, $cmdRef);
		} 
		
		elsif ($cmd eq "player") {
	 		cli_cmd_player($client_socket, $cmdRef);
		}

		elsif ($cmd eq "players") {
	 		cli_cmd_players($client_socket, $cmdRef);
		}
		
		elsif ($cmd eq 'playlists') {
			cli_cmd_playlists($client_socket, $cmdRef);
		}

		elsif ($cmd eq 'playlisttracks') {
			cli_cmd_playlisttracks($client_socket, $cmdRef);
		}
		
		elsif ($cmd eq 'songinfo') {
			cli_cmd_songinfo($client_socket, $cmdRef);
		}

		elsif ($cmd eq 'titles' || $cmd eq 'tracks' || $cmd eq 'songs') {
			cli_cmd_titles($client_socket, $cmdRef);
		}

		else {
		
			$::d_cli && msg("CLI: Forwarding [$cmd] to Command.pm\n");
		
			# Need to call the mothership command.pm
			cli_command_command($client_socket, $cmdRef);
			
			# Don't write output if listen is 1, the callback willl
			$writeoutput = !$connections{$client_socket}{'listen'};
		}
	}
	
	cli_response_write($client_socket, $encoding) if $writeoutput;
	
	return $exit;
}


# parse the command
sub cli_command_parse {
	my $client_socket = shift;
	my $command = shift;
	
	$d_cli_vv && msg("CLI: cli_command_parse($command)\n");

	# Remember command line
	$connections{$client_socket}{'command'} = $command;
	# Delete response array
	@{$connections{$client_socket}{'response'}} = ();


	$d_cli_v && msg("CLI: Handling command: $command\n");


	# Split the command string
	# Space in parameters are to be encoded as %20
	my @elements  = split(" ", $command);
	
	# Unescape
	foreach my $elem (@elements) {
		$elem = URI::Escape::uri_unescape($elem);
#		$::d_cli && msg("CLI: cli_parse_command: Found [$elem]\n");
	}

	return if !scalar @elements;
		
	# Now this gets messy...
	# Legacy CLI queries have one or more param eq '?'
	# Extended CLI queries have 2 positional parameters, then tags
	# Legacy CLI commands have no '?'
	# Extended CLI commands have no positional parameters
	# Nevertheless we want to return params in a given order -> array
	# But we want control over the VALUE charset -> hash
	# We'd need an ordered hash that accepts multiple time the same value...

	# Store the parsed command data in a hash for easy access...
	# Pseudo-params (positional) have keys starting with _
	my %cmdHash;	
	
	# Check if first param is a client...
	my $client = Slim::Player::Client::getClient($elements[0]);

	if (defined $client) {
		# Remove the client from the param array
		shift @elements;
		# Remember the client in the hash...
		$cmdHash{'_client'} = $client;
		$::d_cli && msg("CLI: Parsing command: Found client [" . $client->id() ."]\n");
		# Push the client in the answer
		cli_response_push($client_socket, $client->id());
	}
	
	# Remember command array if ever we need to call Command.pm
	@{$connections{$client_socket}{'command_array'}} = @elements;

	
	# Populate the hash, positional parameters have keys _pX

	for(my $i=0; $i < scalar @elements; $i++) {
	
		# Special case mac address as param...
		if ($elements[$i] =~ /[0-9a-fA-F][0-9a-fA-F]:[0-9a-fA-F][0-9a-fA-F]:[0-9a-fA-F][0-9a-fA-F]:[0-9a-fA-F][0-9a-fA-F]:[0-9a-fA-F][0-9a-fA-F]:[0-9a-fA-F][0-9a-fA-F]/) {
			$cmdHash{($i==0?'_command':"_p$i")} = $elements[$i];
			$::d_cli && msg("CLI: Parsing command: Found param [$i], value mac address [" . $cmdHash{"_p$i"} . "]\n");			
		}
		elsif ($elements[$i] =~ /([^:]+):(.*)/) {
			$cmdHash{$1} = $2;
			$::d_cli && msg("CLI: Parsing command: Found param [$1], value [$2]\n");
		}
		else {
			$cmdHash{($i==0?'_command':"_p$i")} = $elements[$i];
			$::d_cli && msg("CLI: Parsing command: Found " . ($i==0?"command":"param [$i]") . ", value [" . $cmdHash{($i==0?'_command':"_p$i")} . "]\n");
		}
		
		# Unless it is '?', push it back...
		unless ($elements[$i] eq '?') {
			cli_response_push($client_socket, $elements[$i]);
		}
	}

	# We'd really need to know the arguments types for each command
	#  positional or tagged (to allow ":" in a positional parameter)
	#  string or number or flag or whatever (for utf8 handling)
	#  client is $p0 or not
	
	# check $p0, is it command?
	# .. if yes and require client assign random client
	# .. if yes and does not require client use params
	# .. if no, is $p1 a command?
	# ... if yes, is $p0 a client?
	# .... if no, error
	# .... if yes, does it require a client?
	
	return \%cmdHash;
}


# Execute command through Command.pm
sub cli_command_command {
	my $client_socket = shift;
	my $cmdRef = shift;

	$d_cli_vv && msg("CLI: cli_command_command()\n");

	# Clear response array, command.pm operates differently than us
	@{$connections{$client_socket}{'response'}} = ();

	# Add client to response if we have one
	if (defined $cmdRef->{'_client'}) {
		push @{$connections{$client_socket}{'response'}}, 
			$cmdRef->{'_client'}->id();
	}
	else {
		# Mimic stdio, find a client if we have none
		$cmdRef->{'_client'} = cli_random_client();
	}
	
	push @{$connections{$client_socket}{'response'}},
		Slim::Control::Command::execute(
			$cmdRef->{'_client'}, 
			\@{$connections{$client_socket}{'command_array'}});	

}
	
	
# add some data to the current response
sub cli_response_push {
	my $client_socket = shift;
	my $value = shift;
	my $key = shift;

	$d_cli_vv && msg("CLI: cli_response_push($value)\n");
	
	my $data;
	
	if (defined $key) {
		$data = $key . ':' . $value;
	}
	else {
		$data = $value;
	}

	push @{$connections{$client_socket}{'response'}}, $data;
}


# generate a string output from the current response array
sub cli_response_write {
	my $client_socket = shift;
	my $encoding = shift;
	
	$d_cli_vv && msg("CLI: cli_response_write()\n");
		
	foreach my $elem (@{$connections{$client_socket}{'response'}}) {
		$elem = Slim::Utils::Unicode::utf8encode($elem, $encoding);
		$elem = URI::Escape::uri_escape_utf8($elem);
	}
	
	my $output = join " ",  @{$connections{$client_socket}{'response'}};
	$::d_cli && msg("CLI: Response: " . $output . "\n");
	
	client_socket_buffer($client_socket, $output . $connections{$client_socket}{'terminator'});
}



# handles callbacks from Slim::Command::execute
sub cli_executeCallback {
	my $client = shift;
	my $paramsRef = shift;

	$d_cli_vv && msg("CLI: cli_executeCallback()\n");

	# XXX - this should really be passed and not global.
	foreach my $client_socket (keys %connections) {

		next unless ($connections{$client_socket}{'listen'} == 1);

		# retrieve the socket object
		$client_socket = $connections{$client_socket}{'socket'};

		# Format reply
		my $output = '';
		
		$output = URI::Escape::uri_escape($client->id()) . ' ' if $client;

		foreach my $param (@$paramsRef) {
			$output .= URI::Escape::uri_escape($param) . ' ';
		}
		
		chop($output);
		
		# send to client
		client_socket_buffer($client_socket, $output . $connections{$client_socket}{'terminator'});

		# not sure why client_socket_write would be needed here
#		client_socket_write($client_socket);
	}
}

################################################################################
# Utilities
################################################################################
# determine a random client
sub cli_random_client {

	$d_cli_vv && msg("CLI: cli_random_client()\n");

	if (Slim::Player::Client::clientCount > 0) {
		my @allclients = Slim::Player::Client::clients();
		return $allclients[0];
	}
	return undef;
}

# normalizes params for extended queries
sub cli_normalize {
	my $cmdRef = shift;
	my $count = shift;
	
	$d_cli_vv && msg("CLI: cli_normalize()\n");

	my $from = $cmdRef->{'_p1'};
	my $numofitems = $cmdRef->{'_p2'};

	my $start = 0;
	my $end   = 0;
	my $valid = 0;
	
	if ($numofitems && $count) {

		my $lastidx = $count - 1;

		if ($from > $lastidx) {
			return ($valid, $start, $end);
		}

		if ($from < 0) {
			$from = 0;
		}
	
		$start = $from;
		$end = $start + $numofitems - 1;
	
		if ($end > $lastidx) {
			$end = $lastidx;
		}

		$valid = 1;
	}

	return ($valid, $start, $end);
}

# defined, but does not contain a *
sub specified {
	my $i = shift;

	return 0 if ref($i) eq 'ARRAY';
	return 0 unless defined $i;
	return $i !~ /\*/;
}


# This maps the extended CLI commands to methods on Track.
# Allocation map: capital letters are still free:
#  a b c d e f g h i j k l m n o p q r s t u v X y z

our %cliTrackMap = (
	'g' => 'genre',
	'a' => 'artist',
	'l' => 'album',
	't' => 'tracknum',
	'y' => 'year',
	'm' => 'bpm',
	'k' => 'comment',
	'v' => 'tagversion',
	'r' => 'bitrate',
	'z' => 'drm',
	'n' => 'modificationTime',
	'u' => 'url',
	'f' => 'filesize',
);

# Special cased:
#	'c' => 'composer',
#	'b' => 'band',
#	'h' => 'conductor',
# d duration
# i disc
# j Cover art
# o type
# q disc count
# e album_id
# p genre_id
# s artist_id

sub cli_songdata {
	my $pathOrObj = shift;
	my $tags      = shift;

	$d_cli_vv && msg("CLI: cli_songdata()\n");

	my $ds        = Slim::Music::Info::getCurrentDataStore();
	my $track     = blessed($pathOrObj) && $pathOrObj->can('id') ? $pathOrObj : $ds->objectForUrl($pathOrObj);
	
	if (!blessed($track) || !$track->can('id')) {

		errorMsg("Slim::Control::CLI::cli_songdata called with invalid object or path: $pathOrObj!\n");
		
		# For some reason, $pathOrObj may be an id... try that before giving up...
		$track = $ds->objectForId('track', $pathOrObj);

		if (!blessed($track) || !$track->can('id')) {

			errorMsg("Slim::Control::CLI::cli_songdata cannot make track from: $pathOrObj!\n");
			return;
		}
	}

	my @returnArray = (
		sprintf('id:%s', $track->id()),
		sprintf('title:%s', $track->title()),
	);

	#use Data::Dumper;
	#print Dumper($track);

	for my $tag (split //, $tags) {

		if (my $method = $cliTrackMap{$tag}) {

			my $value = $track->$method();

			if (defined $value && $value !~ /^\s*$/ && !(($tag eq 'c' || $tag eq 'b' || $tag eq 'h') && $value == 0)) {

				push @returnArray, sprintf('%s:%s', $method, $value);
			}

			next;
		}

		if ($tag eq 'd' && defined(my $duration = $track->secs())) {
			push @returnArray, "duration:$duration";
			next;
		}

		if ($tag eq 'c' && (my @composers = $track->composer())) {
			push @returnArray, "composer:" . $composers[0];
			next;
		}

		if ($tag eq 'b' && (my @bands = $track->band())) {
			push @returnArray, "band:" . $bands[0];
			next;
		}

		if ($tag eq 'h' && (my @conductors = $track->conductor())) {
			push @returnArray, "conductor:" . $conductors[0];
			next;
		}

		if ($tag eq 'p' && defined(my $genre = $track->genre())) {
			if (defined(my $id = $genre->id())) {
				push @returnArray, "genre_id:$id";
				next;
			}
		}

		if ($tag eq 's' && defined(my $artist = $track->artist())) {
			if ($tag eq 's' && defined(my $id = $artist->id())) {
				push @returnArray, "artist_id:$id";
				next;
			}
		}
		
		# Cover art!
		if ($tag eq 'j' && $track->coverArt()) {
			push @returnArray, "coverart:1";
			next;
		}
	
		if ($tag eq 'o' && defined(my $ct = $track->content_type())) {
			push @returnArray, sprintf('type:%s', string(uc($ct)));
			next;
		}

		if ($tag eq 'i' && defined(my $disc = $track->disc())) {
			push @returnArray, "disc:$disc";
			next;
		}

		# Handle album specifics
		if (defined(my $album = $track->album())) {
		
#			use Data::Dumper;
#			print Dumper($album);

			if ($tag eq 'e' && defined(my $id = $album->id())) {
				push @returnArray, "album_id:$id";
				next;
			}
	
			if ($tag eq 'q' && defined(my $discc = $album->discc())) {
				push @returnArray, "disccount:$discc" unless $discc eq '';
				next;
			}
		}
	}

	return @returnArray;
}

sub cli_pushSong {
	my $client_socket 	= shift;
	my $pathOrObj 		= shift;
	my $tags      		= shift;

	my @items = cli_songdata($pathOrObj, $tags);
	
	foreach my $item (@items) {
		cli_response_push($client_socket, $item);
	}
}

our %searchMap = (

	'artist' => 'contributor.namesearch',
	'genre'  => 'genre.namesearch',
	'album'  => 'album.titlesearch',
	'track'  => 'track.titlesearch',
);

################################################################################
# CLI commands & queries
################################################################################

# Handles the "login" command
sub cli_cmd_login {
	my $client_socket = shift;
	my $cmdRef = shift;

	$d_cli_vv && msg("CLI: cli_cmd_login()\n");

	my $login = $cmdRef->{'_p1'};
	my $pwd = $cmdRef->{'_p2'};
	
	# Replace pushed p2 with *****
	pop @{$connections{$client_socket}{'response'}};
	cli_response_push($client_socket, '******');
	
	# if we're not authorized yet, try to be...
	if ($connections{$client_socket}{'auth'} == 0) {
		if (Slim::Web::HTTP::checkAuthorization($login, $pwd)) {
			$::d_cli && msg("CLI: Connection requires authentication, authorized!\n");
			$connections{$client_socket}{'auth'} = 1;
			return 0;
		}
		return 1;
	}
	return 0;
}

# Handles the "listen" command
sub cli_cmd_listen {
	my $client_socket = shift;
	my $cmdRef = shift;

	$d_cli_vv && msg("CLI: cli_cmd_listen()\n");

	my $param = $cmdRef->{'_p1'};

	if (defined $param) {
		if ($param eq "?") {
			cli_response_push($client_socket, $connections{$client_socket}{'listen'}||0);
		}
		elsif ($param == 0) {
			$connections{$client_socket}{'listen'} = 0;
		} 
		elsif ($param == 1) {
			$connections{$client_socket}{'listen'} = 1;
		}			
	} 
	else {
		$connections{$client_socket}{'listen'} = !$connections{$client_socket}{'listen'};
	}
}


# handled by dispatch
# Handles the "info" query
#sub cli_cmd_info {
#	my $client_socket = shift;
#	my $cmdRef = shift;
#
#	$d_cli_vv && msg("CLI: cli_cmd_info()\n");
#
#	my $p1 = $cmdRef->{'_p1'};
#	return unless (defined $p1 && $p1 eq "total");
#	
#	my $p2 = $cmdRef->{'_p2'};
#	my $ds = Slim::Music::Info::getCurrentDataStore();
#
#	if ($p2 =~ /^(genre|artist|album|song)s$/) {
#
#		my $field = $1;
#
#		$field = 'track'       if $field eq 'song';
#		$field = 'contributor' if $field eq 'artist';
#
#		cli_response_push($client_socket, $ds->count($field));
#	}
#}

# Handles the "player" query
sub cli_cmd_player {
	my $client_socket = shift;
	my $cmdRef = shift;

	$d_cli_vv && msg("CLI: cli_cmd_player()\n");

	my $p1 = $cmdRef->{'_p1'};
	
	return unless defined $p1;
	
	if ($p1 eq "count") {

		cli_response_push($client_socket, Slim::Player::Client::clientCount());

	} elsif ($p1 =~ /^(?:name|address|ip|id|model|displaytype)$/) {
	
		my $p2client;
		my $p2 = $cmdRef->{'_p2'};
		
		# were we passed an ID?
		if (defined $p2 && Slim::Player::Client::getClient($p2)) {

			$p2client = Slim::Player::Client::getClient($p2);

		} else {
		
			# otherwise, try for an index
			my @clients = Slim::Player::Client::clients();

			if (defined $p2 && defined $clients[$p2]) {
				$p2client = $clients[$p2];
			}
		}
		
		if (defined $p2client) {

			if ($p1 eq "name") {
				cli_response_push($client_socket, $p2client->name());
			} elsif ($p1 eq "address" || $p1 eq "id") {
				cli_response_push($client_socket, $p2client->id());
			} elsif ($p1 eq "ip") {
				cli_response_push($client_socket, $p2client->ipport());
			} elsif ($p1 eq "model") {
				cli_response_push($client_socket, $p2client->model());
			} elsif ($p1 eq "displaytype") {
				cli_response_push($client_socket, $p2client->vfdmodel());
			}
		}
	}
}

# Handles the "players" command
sub cli_cmd_players {
	my $client_socket = shift;
	my $cmdRef = shift;

	$d_cli_vv && msg("CLI: cli_cmd_players()\n");

	my $count = Slim::Player::Client::clientCount();
	cli_response_push($client_socket, "count:" . $count);
	
	my ($valid, $start, $end) = cli_normalize($cmdRef, $count);

	if ($valid) {
		my $idx = $start;
		my @players = Slim::Player::Client::clients();

		if (scalar(@players) > 0) {

			for my $eachclient (@players[$start..$end]) {
				cli_response_push($client_socket, "playerindex:" . $idx);
				cli_response_push($client_socket, "playerid:" . $eachclient->id());
				cli_response_push($client_socket, "ip:" . $eachclient->ipport());
				cli_response_push($client_socket, "name:" . $eachclient->name());
				cli_response_push($client_socket, "model:" . $eachclient->model()); #squeezebox, softsqueeze, slimp3
				cli_response_push($client_socket, "displaytype:" . $eachclient->vfdmodel()); 
				cli_response_push($client_socket, "connected:" . ($eachclient->connected() || 0));
				$idx++;
			}	
		}
	}
}

#} elsif ($p0 =~ /^(artist|album|genre)s$/) {
sub cli_cmd_artists_albums_genres {
	my $client_socket = shift;
	my $cmdRef = shift;

	$d_cli_vv && msg("CLI: cli_cmd_artists_albums_genres()\n");

	my $ds = Slim::Music::Info::getCurrentDataStore();
	my $find = {};
	my $label = $cmdRef->{'_command'};
	chop($label);

	if (defined $searchMap{$label} && specified($cmdRef->{'search'})) {
		$find->{ $searchMap{$label} } = Slim::Web::Pages::Search::searchStringSplit($cmdRef->{'search'});
	}
	if (defined $cmdRef->{'genre_id'}){
		$find->{'genre'} = $cmdRef->{'genre_id'};
	}
	if (defined $cmdRef->{'artist_id'}){
		$find->{'artist'} = $cmdRef->{'artist_id'};
	}
	if (defined $cmdRef->{'album_id'}){
		$find->{'album'} = $cmdRef->{'album_id'};
	}

	if ($cmdRef->{'_command'} eq 'artists') {

		# The user may not want to include all the composers/conductors
		if (my $roles = $ds->artistOnlyRoles) {

			$find->{'contributor.role'} = $roles;
		}
	}
	
	if (Slim::Music::Import::stillScanning()) {
		cli_response_push($client_socket, "rescan:1");
	}

	my $results = $ds->find({
		'field'  => $label,
		'find'   => $find,
		'sortBy' => $label,
#		'limit'  => $cmdRef->{'_p2'},
#		'offset' => $cmdRef->{'_p1'},
	});

	my $count   = scalar @$results;

	cli_response_push($client_socket, "count:$count");

	my ($valid, $start, $end) = cli_normalize($cmdRef, $count);

	if ($valid) {

		for my $eachitem (@$results[$start..$end]) {
			cli_response_push($client_socket, 'id:'. $eachitem->id);
			cli_response_push($client_socket, $label . ':' . $eachitem);
		}
	}
}
	
# handles the "titles" query
sub cli_cmd_titles {
	my $client_socket = shift;
	my $cmdRef = shift;

	$d_cli_vv && msg("CLI: cli_cmd_titles()\n");

	my $ds = Slim::Music::Info::getCurrentDataStore();
	my $find = {};
	my $label = 'track';
	my $sort  = 'title';
	my $tags  = 'gald';
	
	if (defined $searchMap{$label} && specified($cmdRef->{'search'})) {
		$find->{ $searchMap{$label} } = Slim::Web::Pages::Search::searchStringSplit($cmdRef->{'search'});
	}
	if (defined $cmdRef->{'genre_id'}){
		$find->{'genre'} = $cmdRef->{'genre_id'};
	}
	if (defined $cmdRef->{'artist_id'}){
		$find->{'artist'} = $cmdRef->{'artist_id'};
	}
	if (defined $cmdRef->{'album_id'}){
		$find->{'album'} = $cmdRef->{'album_id'};
	}

	# did we have override on the defaults?
	# note that this is not equivalent to 
	# $val = $param || $default;
	# since when $default eq '' -> $val eq $param
	$sort =  $cmdRef->{'sort'} if defined $cmdRef->{'sort'};
	$tags =  $cmdRef->{'tags'} if defined $cmdRef->{'tags'};
	
	
	if ($sort eq "tracknum" && !($tags =~ /t/)) {
		$tags = $tags . "t";
	}
	
	if (Slim::Music::Import::stillScanning()) {
		cli_response_push($client_socket, "rescan:1");
	}

	my $results = $ds->find({
		'field'  => $label,
		'find'   => $find,
		'sortBy' => $sort,
#		'limit'  => $cmdRef->{'_p2'},
#		'offset' => $cmdRef->{'_p1'},
	});
	
	my $count   = scalar @$results;

	cli_response_push($client_socket, "count:$count");

	my ($valid, $start, $end) = cli_normalize($cmdRef, $count);

	my $cur = $start;

	if ($valid) {
	
		for my $item (@$results[$start..$end]) {

			cli_pushSong($client_socket, $item, $tags);

			::idleStreams();
		}
	}
}
	
# handles the "playlists" query
sub cli_cmd_playlists {
	my $client_socket = shift;
	my $cmdRef = shift;

	$d_cli_vv && msg("CLI: cli_cmd_playlists()\n");

	my $ds 		= Slim::Music::Info::getCurrentDataStore();
	my $search	= $cmdRef->{'search'};
	my $tags    = $cmdRef->{'tags'} || '';

	# Normalize any search parameters
	if (defined $search) {
		$search = Slim::Web::Pages::Search::searchStringSplit($search);
	}

	if (Slim::Music::Import::stillScanning()) {
		cli_response_push($client_socket, "rescan:1");
	}

	my $iterator = $ds->getPlaylists('all', $search);

	if (defined $iterator) {

		my $numitems = scalar @$iterator;
		
		cli_response_push($client_socket, "count:$numitems");
		
		my ($valid, $start, $end) = cli_normalize($cmdRef, $numitems);

		if ($valid) {
			for my $eachitem (@$iterator[$start..$end]) {
				cli_response_push($client_socket, "id:"  . $eachitem->id);
				cli_response_push($client_socket, "playlist:" . Slim::Music::Info::standardTitle(undef, $eachitem));
				cli_response_push($client_socket, "url:" . $eachitem->url) if ($tags =~ /u/);
			}
		}
	} 
}


# handles the "playlisttracks" query
sub cli_cmd_playlisttracks {
	my $client_socket 	= shift;
	my $cmdRef 			= shift;

	$d_cli_vv && msg("CLI: cli_cmd_playlisttracks()\n");

	my $ds 				= Slim::Music::Info::getCurrentDataStore();
	my $find 			= {};
	my $tags 			= 'gald';
	$tags   	 		= $cmdRef->{'tags'} if defined $cmdRef->{'tags'};
	my $playlist 		= $cmdRef->{'playlist_id'};
	my $iterator;
	my @tracks;

	if (Slim::Music::Import::stillScanning()) {
		cli_response_push($client_socket, "rescan:1");
	}

	if ($playlist) {

		my $obj = $ds->objectForId('track', $playlist);
				
		if (blessed($obj) && $obj->can('tracks')) {
			$iterator = $obj->tracks;
		}
	}

	if (defined $iterator) {
#		use Data::Dumper;
#		print Dumper($iterator);

		my $numitems = $iterator->count;

		cli_response_push($client_socket, "count:$numitems");
		
		my ($valid, $start, $end) = cli_normalize($cmdRef, $numitems);
		my $cur = $start;

		if ($valid) {

			for my $eachitem ($iterator->slice($start, $end)) {
				cli_response_push($client_socket, "playlist index:$cur");

				cli_pushSong($client_socket, $eachitem, $tags);

				$cur++;
			}
		}
	} else {
		cli_response_push($client_socket, "count:0");
	}
}


# handles the "songinfo" query
sub cli_cmd_songinfo {
	my $client_socket = shift;
	my $cmdRef = shift;

	$d_cli_vv && msg("CLI: cli_cmd_songinfo()\n");

	my $ds     = Slim::Music::Info::getCurrentDataStore();
	my $track;
	
	my $path = $cmdRef->{'url'};
	my $id = $cmdRef->{'track_id'};
	my $tags = "abcdefghijklmnopqrstvwyz"; # all letter EXCEPT u AND x
	$tags = $cmdRef->{'tags'} if defined  $cmdRef->{'tags'};
	
	if (defined $id){

		if ($tags !~ /u/) {
			$tags .= 'u';
		}

		$track = $ds->objectForId('track', $id);

	} else {

		if (defined $path && Slim::Music::Info::isSong($path)){

			if ($tags !~ /x/) {
				$tags .= 'x';
			}

			$track = $ds->objectForUrl($path)
		}
	}

	if (Slim::Music::Import::stillScanning()) {
		cli_response_push($client_socket, "rescan:1");
	}

	if (blessed($track) && $track->can('id')) {

		my @items = cli_songdata($track, $tags);
		
		cli_response_push($client_socket, "count:" . scalar(@items));

		my ($valid, $start, $end) = cli_normalize($cmdRef, scalar(@items));

		if ($valid) {
			for my $eachitem (@items[$start..$end]) {
				cli_response_push($client_socket, $eachitem);
			}
		}

	} else {

		cli_response_push($client_socket, "count:0");
	}
}

# plugin: return strings
sub strings {
	return "
PLUGIN_CLI
	EN	Command Line Interface (CLI)
	ES	Interface de Línea de Comando (CLI)

SETUP_CLIPORT
	CZ	Číslo portu příkazové řádky
	DE	Kommandozeilen-Schnittstellen Port-Nummer
	DK	Port-nummer for Command Line Interface
	EN	Command Line Interface Port Number
	ES	Número de puerto para la interfaz de linea de comandos
	FR	Numéro de port de l'interface en ligne de commande
	JP	コマンドライン インターフェース ポートナンバー
	NL	Poortnummer van de Opdrachtprompt interface
	NO	Portnummer for terminalgrensesnitt
	PT	Porta TCP da Interface de Linha de Comando
	SE	Portnummer för terminalgränssnitt
	ZH_CN	命令行界面端口号

SETUP_CLIPORT_DESC
	CZ	Můžete změnit číslo portu, který bude použit k ovládání přehrávače z příkazové řádky.
	DE	Sie können den Port wechseln, der für die Kommandozeilen-Schnittstellen verwendet werden soll.
	DK	Du kan ændre hvilket port-nummer der anvendes til at styre player-afspilleren via Command Line Interfacet.
	EN	You can change the port number that is used to by a command line interface to control the player.
	ES	Puede cambiar el número de puerto que se usa para controlar el reproductor con la linea de comandos.
	FR	Vous pouvez changer le port utilisé par l'interface en ligne de commande pour contrôler la platine.
	JP	プレーヤーをコントロールする、コマンドライン インターフェースに使われるポートナンバーを変更することができます。
	NL	Je kunt het poortnummer aanpassen dat gebruikt wordt om de player via een Opdrachtprompt interface te bedienen. Zet dit poortnummer op 0 (nul) als je de Opdrachtprompt interface wilt uitschakelen.
	NO	Du kan endre portnummeret som brukes for å kontrollere din spiller via et terminalgrensesnitt.
	PT	Pode mudar o número da porta para ligação da interface de linha de comando do player.
	SE	Du kan ändra portnumret som används för att kontrollera din spelare via ett terminalgränssnitt.
	ZH_CN	您可以改变控制播放机的命令行界面所使用的端口号。

SETUP_CLIPORT_OK
	CZ	Nyní bude používán následující port pro ovládaní příkazovým řádkem
	DE	Der folgende Port wird für die Kommandozeilen-Schnittstelle verwendet:
	DK	Anvender nu følgende port til Command Line Interfacet:
	EN	Now using the following port for the command line interface:
	ES	Utilizando puerto:
	FR	L'interface en ligne de commande utilise maintenant le port :
	JP	現在コマンドライン インターフェースには、以下のポートが使われています:
	NL	De volgende poort wordt gebruikt voor de Opdrachtprompt interface:
	NO	Bruker nå følgende portnummer for terminalgrensesnitt:
	PT	A porta para acesso via linha de comando é
	SE	Använder nu följande portnummer för terminalgränssnittet:
	ZH_CN	当前正使用如下的命令行界面端口：

";
}


#		my $str;
#		for (my $i = 0; $i < length($1); $i++) {
#			$str .= ord(substr($1, $i, 1)) . " ";
#		}
#		print("     1: $str\n");



1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
