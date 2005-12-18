package Slim::Control::Dispatch;

# $Id: Command.pm 5121 2005-11-09 17:07:36Z dsully $
#
# SlimServer Copyright (C) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

#use File::Basename;
#use File::Spec::Functions qw(:ALL);
#use FileHandle;
#use IO::Socket qw(:DEFAULT :crlf);
#use Scalar::Util qw(blessed);
#use Time::HiRes;

#use Slim::DataStores::Base;
#use Slim::Display::Display;
#use Slim::Music::Info;
use Slim::Utils::Misc;
#use Slim::Utils::Scan;
#use Slim::Utils::Strings qw(string);

use Slim::Control::Commands;
use Slim::Control::Queries;
use Slim::Control::Request;

our %notifications = ();
our %dispatchCommands = ();
our %dispatchQueries = ();

# COMMAND LIST #
  
# C     P0             P1                          P2                            P3            P4         P5        P6
        
# GENERAL
# N    debug           <debugflag>                 <0|1|?|>
# N    pref            <prefname>                  <prefvalue|?>
# N    version         ?

# DATABASE    
# N    rescan          <|playlists|?>    	
# N    wipecache

# PLAYERS
# Y    button          <buttoncode>
# Y    ir              <ircode>                    <time>
# Y    sleep           <0..n|?>
# Y    signalstrength  ?
# Y    connected       ?
# Y    playerpref      <prefname>                  <prefvalue|?>
# Y    sync            <playerindex|playerid|-|?>
# Y    power           <0|1|?|>
# Y    display         <line1>                     <line2>                       <duration>
# Y    display         ?                           ?
# Y    displaynow      ?                           ?
# Y    mixer           volume                      <0..100|-100..+100|?>
# Y    mixer           bass                        <0..100|-100..+100|?>
# Y    mixer           treble                      <0..100|-100..+100|?>
# Y    mixer           pitch                       <80..120|-100..+100|?>
# Y    mixer           muting					   <|?>

# PLAYLISTS
# Y    mode            <play|pause|stop|?>    
# Y    play        
# Y    pause           <0|1|>    
# Y    stop
# Y    rate            <rate|?>
# Y    time|gototime   <0..n|-n|+n|?>
# Y    genre           ?
# Y    artist          ?
# Y    album           ?
# Y    title           ?
# Y    duration        ?
# Y    path	           ?


# add standard commands and queries to the dispatch hashes...
sub init {


	addCommand(	'button', 			\&Slim::Control::Commands::buttonCommand);
	addCommand(	'debug', 			\&Slim::Control::Commands::debugCommand);
	addCommand(	'display', 			\&Slim::Control::Commands::displayCommand);
	addCommand(	'gototime',			\&Slim::Control::Commands::timeCommand);
	addCommand(	'ir', 				\&Slim::Control::Commands::irCommand);
	addCommand(	'mixer', 			\&Slim::Control::Commands::mixerCommand);
	addCommand(	'mode', 			\&Slim::Control::Commands::playcontrolCommand);
	addCommand(	'pause', 			\&Slim::Control::Commands::playcontrolCommand);
	addCommand(	'play', 			\&Slim::Control::Commands::playcontrolCommand);
	addCommand(	'playerpref', 		\&Slim::Control::Commands::playerprefCommand);
	addCommand(	'power', 			\&Slim::Control::Commands::powerCommand);
	addCommand(	'pref', 			\&Slim::Control::Commands::prefCommand);
	addCommand(	'rate',	 			\&Slim::Control::Commands::rateCommand);
	addCommand(	'rescan', 			\&Slim::Control::Commands::rescanCommand);
	addCommand(	'sleep', 			\&Slim::Control::Commands::sleepCommand);
	addCommand(	'stop', 			\&Slim::Control::Commands::playcontrolCommand);
	addCommand(	'sync', 			\&Slim::Control::Commands::syncCommand);
	addCommand(	'time',	 			\&Slim::Control::Commands::timeCommand);
	addCommand(	'wipecache', 		\&Slim::Control::Commands::wipecacheCommand);


	addQuery(	'album',			\&Slim::Control::Queries::cursonginfoQuery);
	addQuery(	'artist',			\&Slim::Control::Queries::cursonginfoQuery);
	addQuery(	'connected', 		\&Slim::Control::Queries::connectedQuery);
	addQuery(	'debug',			\&Slim::Control::Queries::debugQuery);
	addQuery(	'displaynow',		\&Slim::Control::Queries::displaynowQuery);
	addQuery(	'duration',			\&Slim::Control::Queries::cursonginfoQuery);
	addQuery(	'genre',			\&Slim::Control::Queries::cursonginfoQuery);
	addQuery(	'gototime',			\&Slim::Control::Queries::timeQuery);
	addQuery(	'info', 			\&Slim::Control::Queries::infototalQuery);
	addQuery(	'linesperscreen',	\&Slim::Control::Queries::linesperscreenQuery);
	addQuery(	'mixer', 			\&Slim::Control::Queries::mixerQuery);
	addQuery(	'mode', 			\&Slim::Control::Queries::modeQuery);
	addQuery(	'path',				\&Slim::Control::Queries::cursonginfoQuery);
	addQuery(	'playerpref', 		\&Slim::Control::Queries::playerprefQuery);
	addQuery(	'power', 			\&Slim::Control::Queries::powerQuery);
	addQuery(	'pref', 			\&Slim::Control::Queries::prefQuery);
	addQuery(	'rate', 			\&Slim::Control::Queries::rateQuery);
	addQuery(	'rescan', 			\&Slim::Control::Queries::rescanQuery);
	addQuery(	'signalstrength', 	\&Slim::Control::Queries::signalstrengthQuery);
	addQuery(	'sleep', 			\&Slim::Control::Queries::sleepQuery);
	addQuery(	'sync', 			\&Slim::Control::Queries::syncQuery);
	addQuery(	'time', 			\&Slim::Control::Queries::timeQuery);
	addQuery(	'title',			\&Slim::Control::Queries::cursonginfoQuery);
	addQuery(	'version', 			\&Slim::Control::Queries::versionQuery);

}



# add a command to the dispatcher
sub addCommand {
	my $commandName = shift;
	my $commandFuncRef = shift;
	$dispatchCommands{$commandName} = $commandFuncRef;	
}

# add queries to the dispatcher
sub addQuery {
	my $queryName = shift;
	my $queryFuncRef = shift;
	$dispatchQueries{$queryName} = $queryFuncRef;	
}

# for the moment, no identified need to REMOVE commands/queries

# add a watcher to be notified of commands
sub setNotify {
	my $notifyFuncRef = shift;
	$notifications{$notifyFuncRef} = $notifyFuncRef;
}

# remove a watcher
sub clearNotify {
	my $notifyFuncRef = shift;
	delete $notifications{$notifyFuncRef};
}

# notify watchers...
sub notify {
	my $request = shift;

#	no strict 'refs';
		
	for my $notification (keys %notifications) {
		my $notifyFuncRef = $notifications{$notification};
		&$notifyFuncRef($request);
	}
}


# do the job, i.e. dispatch a request
sub dispatch {
	my $request = shift;

	# we can do some preflighting here...

	# get the request name for debug and easy reference
	my $requestText = $request->getRequest();

	$::d_command && msg("dispatch(): Dispatching request [$requestText]\n" );

	# get the function pointer
	my $funcPtr;

	if ($request->query()) {
		$funcPtr = $dispatchQueries{$requestText};
	}
	else {
		$funcPtr = $dispatchCommands{$requestText};
	}

	# can't find no function for that request, returning...
	if (!$funcPtr) {

		$::d_command && errorMsg("dispatch(): Found no function for request [$requestText]\n" );
		return ();
	}

	$request->setStatusDispatched();

	# got it, now do it
	&{$funcPtr}($request);

	# check status
	if ($request->isStatusDone()) {
		$::d_command && msg("dispatch(): Done request [$requestText]\n");

		# notify watchers of commands
		notify($request) if !$request->query();
	}	
}

1;
