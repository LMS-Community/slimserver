package Slim::Control::Stdio;

# SlimServer Copyright (c) 2001, 2002, 2003 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use FindBin qw($Bin);
use File::Spec::Functions qw(:ALL);

use Slim::Networking::Select;
use Slim::Utils::Strings qw(string);
use Slim::Utils::OSDetect;
use Slim::Utils::Misc;

use vars qw($stdin);




#$::d_stdio = 1;

# This module provides a command-line interface to the server via standard in and out.

# Each command is terminated by a carriage return.  The server will reply echoing the request.
# The format of the commands is as follows:
#
#    <playerip> <p0> <p1> <p2> <p3> <p4><CR>
#
# where:  
#       <playerip> is the IP address & port of the player to control (e.g. 10.0.1.201:69).  
#                  The <playerip> may be omitted if there is only one player in the system.
#                  <playerip> may be obtained by using the "player address" command.
#
#       <p0> through <p4> are command parameters. 
#                         Pass a "?" to obtain a value for that parameter in the response.
#
# The following commands are supported:
#
#   player	count			?
#   player	name			<playerindex>				?
#   player	address			<playerindex>				?
#   debug	d_debugflag		<?|0|1>
#   <playerip> play
#   <playerip> pause 		(0|1|)
#   <playerip> stop
#   <playerip> mode			<play|pause|stop|?>
#   <playerip> sleep 		<0..n|?>															
#	<playerip> power 	    (0|1|?)
#   <playerip> time			(0..n sec)|(-n..+n sec)|?
#   <playerip> genre		?
#   <playerip> artist		?
#   <playerip> album		?
#   <playerip> title		?
#   <playerip> duration  	?
#   <playerip> playlist 	play 	    <song>
#   <playerip> playlist 	append 	    <song>
#   <playerip> playlist 	load 	    <playlist>
#   <playerip> playlist 	resume 		<playlist>
#   <playerip> playlist 	save 		<playlist>
#   <playerip> playlist 	add 	    <playlist>
#   <playerip> playlist   	loadalbum   <genre>						<artist>	<album>
#   <playerip> playlist   	addalbum	<genre> 					<artist>	<album>
#   <playerip> playlist		clear
#   <playerip> playlist 	move 		<fromoffset> 				<tooffset>
#   <playerip> playlist 	delete 		<songoffset>
#   <playerip> playlist 	jump 		<index>
#   <playerip> playlist 	index		<index>						?
#   <playerip> playlist		genre		<index>						?
#   <playerip> playlist		artist		<index>						?
#   <playerip> playlist		album		<index>						?
#   <playerip> playlist		title		<index>						?
#   <playerip> playlist		duration	<index>						?
#   <playerip> playlist		tracks		?
#   <playerip> mixer		volume		(0 .. 100)|(-100 .. +100)
#   <playerip> mixer		volume		?
#   <playerip> mixer		balance		(-100 .. 100)|(-200 .. +200)							(not implemented!)
#   <playerip> mixer		base		(0 .. 100)|(-100 .. +100)								(not implemented!)
#   <playerip> mixer		treble		(0 .. 100)|(-100 .. +100)								(not implemented!)
#   <playerip> display   	<line1> 	<line2>                     (duration)
#   <playerip> display   	? 			?
#   <playerip> button   	buttoncode

# To obtain information about the players in the system, use the "player count", "player name" and "player address" commands.
#
#		Request:  "player count ?<cr>"
# 		Response: "player count 2<cr>"
#
#		Request:  "player name 0 ?<cr>"
#		Request:  "player name 0 Living Room<cr>"
#
#		Request:  "player address 0 ?<cr>"
#		Request:  "player address 0 10.0.1.203:69<cr>"

# Basic commands to control playback include "stop", "pause", "play", "jump"
# Examples:
#		Request:  "10.0.1.203:69 pause 1<cr>"
# 		Response: "10.0.1.203:69 pause 1<cr>"
#
#		Request:  "10.0.1.203:69 stop<cr>"
# 		Response: "10.0.1.203:69 stop<cr>"
#
#		Request:  "10.0.1.203:69 jump +1<cr>"
# 		Response: "10.0.1.203:69 jump +1<cr>"
#

#
# Additionaly, the status for various variables can be obtained:
#
# index   - will return the numerical index within the playlist of the current song (1 is the first item, etc.)
# Example: 
#		Request:  "10.0.1.203:69 playlist index ?<cr>"
#		Response: "10.0.1.203:69 playlist index 2<cr>"
#
# genre, artist, album, title, duration - will return the requested information for a the current song  or a given song in the current playlist
# Examples: 
#		Request:  "10.0.1.203:69 genre ?<cr>"
#		Response: "10.0.1.203:69 genre Rock<cr>"

#		Request:  "10.0.1.203:69 artist ?<cr>"
#		Response: "10.0.1.203:69 artist Abba<cr>"

#		Request:  "10.0.1.203:69 album ?<cr>"
#		Response: "10.0.1.203:69 album Greatest Hits<cr>"

#		Request:  "10.0.1.203:69 title ?<cr>"
#		Response: "10.0.1.203:69 title Voulez vous<cr>"

#		Request:  "10.0.1.203:69 duration ?<cr>"
#		Response: "10.0.1.203:69 duration 103.2<cr>"

#		Request:  "10.0.1.203:69 playlist genre 3 ?<cr>"
#		Request:  "10.0.1.203:69 playlist genre 3 Rock<cr>"

#		Request:  "10.0.1.203:69 playlist artist 3 ?<cr>"
#		Response: "10.0.1.203:69 playlist artist 3 Abba<cr>"

#		Request:  "10.0.1.203:69 playlist album 3 ?<cr>"
#		Response: "10.0.1.203:69 playlist album 3 Greatest Hits<cr>"

#		Request:  "10.0.1.203:69 playlist title 3 ?<cr>"
#		Response: "10.0.1.203:69 playlist title 3 Voulez Vous<cr>"

#		Request:  "10.0.1.203:69 playlist duration 3 ?<cr>"
#		Response: "10.0.1.203:69 playlist duration 3 103.2<cr>"


#
# mixer volume  - will return the current volume setting for the player (0-99)
# Example: 
#		Request:  "10.0.1.203:69 mixer volume ?<cr>"
#		Response: "10.0.1.203:69 mixer volume 98<cr>"
#
# tracks  - will return the total number of tracks in the current playlist
# Example: 
#		Request:  "10.0.1.203:69 playlist tracks ?<cr>"
#		Response: "10.0.1.203:69 playlist tracks 7<cr>"
#
# shuffle - will return the playlist shuffle state -  0=no, 1=yes
# Example: 
#		Request:  "10.0.1.203:69 playlist shuffle ?<cr>"
#		Response: "10.0.1.203:69 playlist shuffle 1<cr>"
#
# repeat  - will return the playlist repeat state -  0=stop at end, 1=repeat current song, 2=repeat all songs
# Example: 
#		Request:  "10.0.1.203:69 playlist repeat ?<cr>"
#		Response: "10.0.1.203:69 playlist repeat 2<cr>"
#
# mode    - will return the current player mode - <play|pause|stop|off>
# Example: 
#		Request:  "10.0.1.203:69 mode ?<cr>"
#		Response: "10.0.1.203:69 mode play<cr>"
#
# time    - will return the number of seconds of the song that have been played. Floating point value.
# Example: 
#		Request:  "10.0.1.203:69 time ?<cr>"
#		Response: "10.0.1.203:69 time 32.3<cr>"
#
# pref    - will set or query a prefs value
# Example: 
#		Request:  "10.0.1.203:69 pref mp3dir ?<cr>"
#		Response: "10.0.1.203:69 pref mp3dir %2fUsers%2fdean%2fDesktop%2ftest%20music<cr>"


my $stdout;
my $curline = "";

# initialize the stdio interface
sub init {
	if (Slim::Utils::OSDetect::OS() eq 'win') { return; }
	$stdin = shift;
	$stdout = shift;

	Slim::Networking::Select::addRead($stdin, \&processRequest);

	$stdin->autoflush(1);
	$stdout->autoflush(1);
}

#
#  Handle an Stdio request
#
sub processRequest {
	my $clientsock = shift;
	my $firstline;

	if ($clientsock) {
		$firstline = <$clientsock>;
		if (defined($firstline)) {
			#process the commands
			$::d_stdio && msg("Got line: $firstline\n");
			chomp $firstline; 
			my $message = executeCmd($firstline);
	
			$::d_stdio && msg("response is: $message\n");
			if ($message) {
				$stdout->print($message . "\n");
			}
		}
	}
}

# executeCmd - handles the execution of the stdio request
#
#
sub executeCmd {
	my($command) = @_;
	my $output = undef;
	my @params;
	my($client) = undef;
	my $prefix = "";

	# todo - allow for escaping and/or quoting
	@params = split(" ",$command);

	foreach my $param (@params) {
		$param = Slim::Web::HTTP::unescape($param);
	}

	if (defined $params[0]) {
		$client = Slim::Player::Client::getClient($params[0]);
		
		if (defined($client)) {
			$prefix = Slim::Web::HTTP::escape($params[0]) . " ";
			shift @params;
		}
		
		#if we don't have a player specified, just pick one if there is one...
		if (!defined($client) && Slim::Player::Client::clientCount > 0) {
			my @allclients = Slim::Player::Client::clients();
			$client = $allclients[0];
		}
	
		my @outputParams = Slim::Control::Command::execute($client, \@params);
		
		foreach my $param (@outputParams) {
			$param = Slim::Web::HTTP::escape($param);
		}

		$output = $prefix . join(" ", @outputParams);
	} else {
		$::d_stdio && msg("No params parsed from stdio!\n");
	}
	return $output;
}

1;
__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
