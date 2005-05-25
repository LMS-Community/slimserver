package Slim::Control::Stdio;

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
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
#    <playerid> <p0> <p1> <p2> <p3> <p4><CR>
#
# where:  
#       <playerid> is the unique identifier to specify the player to control.  
#                  The <playerid> may be omitted if there is only one player in the system.
#                  <playerid> may be obtained by using the "player id" command.
#
#       <p0> through <p4> are command parameters. 
#                         Pass a "?" to obtain a value for that parameter in the response.
#
# The following commands are supported:
#
#   player	count			?
#   player	name			<playerindex>				?
#   player	id				<playerindex>				?
#   debug	d_debugflag		<?|0|1>
#   <playerid> play
#   <playerid> pause 		(0|1|)
#   <playerid> stop
#   <playerid> mode			<play|pause|stop|?>
#   <playerid> sleep 		<0..n|?>
#   <playerid> power 		(0|1|?)
#   <playerid> time			(0..n sec)|(-n..+n sec)|?
#   <playerid> genre		?
#   <playerid> artist		?
#   <playerid> album		?
#   <playerid> title		?
#   <playerid> duration  	?
#   <playerid> playlist 	play 	    <song>
#   <playerid> playlist 	append 	    <song>
#   <playerid> playlist 	load 	    <playlist>
#   <playerid> playlist 	resume 		<playlist>
#   <playerid> playlist 	save 		<playlist>
#   <playerid> playlist 	add 	    <playlist>
#   <playerid> playlist   	loadalbum   <genre>						<artist>	<album>
#   <playerid> playlist   	addalbum	<genre> 					<artist>	<album>
#   <playerid> playlist		clear
#   <playerid> playlist 	move 		<fromoffset> 				<tooffset>
#   <playerid> playlist 	delete 		<songoffset>
#   <playerid> playlist 	jump 		<index>
#   <playerid> playlist 	index		<index>						?
#   <playerid> playlist		genre		<index>						?
#   <playerid> playlist		artist		<index>						?
#   <playerid> playlist		album		<index>						?
#   <playerid> playlist		title		<index>						?
#   <playerid> playlist		duration	<index>						?
#   <playerid> playlist		tracks		?
#   <playerid> mixer		volume		(0 .. 100)|(-100 .. +100)
#   <playerid> mixer		volume		?
#   <playerid> mixer		balance		(-100 .. 100)|(-200 .. +200)		(not implemented!)
#   <playerid> mixer		base		(0 .. 100)|(-100 .. +100)		(not implemented!)
#   <playerid> mixer		treble		(0 .. 100)|(-100 .. +100)		(not implemented!)
#   <playerid> display   	<line1> 	<line2>                     (duration)
#   <playerid> display   	? 			?
#   <playerid> button   	buttoncode

# To obtain information about the players in the system, use the "player count", "player name" and "player id" commands.
#
#		Request:  "player count ?<cr>"
# 		Response: "player count 2<cr>"
#
#		Request:  "player name 0 ?<cr>"
#		Request:  "player name 0 Living Room<cr>"
#
#		Request:  "player id 0 ?<cr>"
#		Request:  "player id 0 01:02:03:04:05:06<cr>"

# Basic commands to control playback include "stop", "pause", "play", "jump"
# Examples:
#		Request:  "01:02:03:04:05:06 pause 1<cr>"
# 		Response: "01:02:03:04:05:06 pause 1<cr>"
#
#		Request:  "01:02:03:04:05:06 stop<cr>"
# 		Response: "01:02:03:04:05:06 stop<cr>"
#
#		Request:  "01:02:03:04:05:06 jump +1<cr>"
# 		Response: "01:02:03:04:05:06 jump +1<cr>"
#

#
# Additionaly, the status for various variables can be obtained:
#
# index   - will return the numerical index within the playlist of the current song (1 is the first item, etc.)
# Example: 
#		Request:  "01:02:03:04:05:06 playlist index ?<cr>"
#		Response: "01:02:03:04:05:06 playlist index 2<cr>"
#
# genre, artist, album, title, duration - will return the requested information for a the current song 
# or a given song in the current playlist
#
# Examples: 
#		Request:  "01:02:03:04:05:06 genre ?<cr>"
#		Response: "01:02:03:04:05:06 genre Rock<cr>"

#		Request:  "01:02:03:04:05:06 artist ?<cr>"
#		Response: "01:02:03:04:05:06 artist Abba<cr>"

#		Request:  "01:02:03:04:05:06 album ?<cr>"
#		Response: "01:02:03:04:05:06 album Greatest Hits<cr>"

#		Request:  "01:02:03:04:05:06 title ?<cr>"
#		Response: "01:02:03:04:05:06 title Voulez vous<cr>"

#		Request:  "01:02:03:04:05:06 duration ?<cr>"
#		Response: "01:02:03:04:05:06 duration 103.2<cr>"

#		Request:  "01:02:03:04:05:06 playlist genre 3 ?<cr>"
#		Request:  "01:02:03:04:05:06 playlist genre 3 Rock<cr>"

#		Request:  "01:02:03:04:05:06 playlist artist 3 ?<cr>"
#		Response: "01:02:03:04:05:06 playlist artist 3 Abba<cr>"

#		Request:  "01:02:03:04:05:06 playlist album 3 ?<cr>"
#		Response: "01:02:03:04:05:06 playlist album 3 Greatest Hits<cr>"

#		Request:  "01:02:03:04:05:06 playlist title 3 ?<cr>"
#		Response: "01:02:03:04:05:06 playlist title 3 Voulez Vous<cr>"

#		Request:  "01:02:03:04:05:06 playlist duration 3 ?<cr>"
#		Response: "01:02:03:04:05:06 playlist duration 3 103.2<cr>"


#
# mixer volume  - will return the current volume setting for the player (0-99)
# Example: 
#		Request:  "01:02:03:04:05:06 mixer volume ?<cr>"
#		Response: "01:02:03:04:05:06 mixer volume 98<cr>"
#
# tracks  - will return the total number of tracks in the current playlist
# Example: 
#		Request:  "01:02:03:04:05:06 playlist tracks ?<cr>"
#		Response: "01:02:03:04:05:06 playlist tracks 7<cr>"
#
# shuffle - will return the playlist shuffle state -  0=no, 1=yes
# Example: 
#		Request:  "01:02:03:04:05:06 playlist shuffle ?<cr>"
#		Response: "01:02:03:04:05:06 playlist shuffle 1<cr>"
#
# repeat  - will return the playlist repeat state -  0=stop at end, 1=repeat current song, 2=repeat all songs
# Example: 
#		Request:  "01:02:03:04:05:06 playlist repeat ?<cr>"
#		Response: "01:02:03:04:05:06 playlist repeat 2<cr>"
#
# mode    - will return the current player mode - <play|pause|stop|off>
# Example: 
#		Request:  "01:02:03:04:05:06 mode ?<cr>"
#		Response: "01:02:03:04:05:06 mode play<cr>"
#
# time    - will return the number of seconds of the song that have been played. Floating point value.
# Example: 
#		Request:  "01:02:03:04:05:06 time ?<cr>"
#		Response: "01:02:03:04:05:06 time 32.3<cr>"
#
# pref    - will set or query a prefs value
# Example: 
#		Request:  "01:02:03:04:05:06 pref audiodir ?<cr>"
#		Response: "01:02:03:04:05:06 pref audiodir %2fUsers%2fdean%2fDesktop%2ftest%20music<cr>"

my $stdout;
my $curline = "";

# initialize the stdio interface
sub init {
	$stdin = shift;
	$stdout = shift;

	return if Slim::Utils::OSDetect::OS() eq 'win';

	Slim::Networking::Select::addRead($stdin, \&processRequest);

	$stdin->autoflush(1);
	$stdout->autoflush(1);
}

#
#  Handle an Stdio request
#
sub processRequest {
	my $clientsock = shift || return;

	my $firstline = <$clientsock>;

	if (defined($firstline)) {

		#process the commands
		$::d_stdio && msg("Got line: $firstline\n");
		chomp $firstline; 
		my $message = executeCmd($firstline);

		$::d_stdio && msg("response is: $message\n");
		$stdout->print($message . "\n") if $message;
	}
}

# executeCmd - handles the execution of the stdio request
#
#
sub executeCmd {
	my $command = shift;

	my $output  = undef;
	# People wanting spaces need to use %20
	my @params  = split(" ", $command);

	foreach my $param (@params) {
		$param = Slim::Web::HTTP::unescape($param);
	}

	if (defined $params[0]) {

		my $client = Slim::Player::Client::getClient($params[0]);
		my $prefix = "";
		
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
