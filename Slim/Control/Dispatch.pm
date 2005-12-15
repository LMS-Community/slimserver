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

# PLAYLISTS
# Y    mode            <play|pause|stop|?>    
# Y    play        
# Y    pause           <0|1|>    
# Y    stop


# add standard commands and queries to the dispatch hashes...
sub init {

	addCommand(	'button', 			\&Slim::Control::Commands::buttonCommand);

	addQuery(	'connected', 		\&Slim::Control::Queries::connectedQuery);

	addCommand(	'debug', 			\&Slim::Control::Commands::debugCommand);
	addQuery(	'debug',			\&Slim::Control::Queries::debugQuery);

	addQuery(	'info', 			\&Slim::Control::Queries::infototalQuery);

	addCommand(	'ir', 				\&Slim::Control::Commands::irCommand);

	addCommand(	'pref', 			\&Slim::Control::Commands::prefCommand);
	addQuery(	'pref', 			\&Slim::Control::Queries::prefQuery);

	addCommand(	'play', 			\&Slim::Control::Commands::playcontrolCommand);
	addCommand(	'stop', 			\&Slim::Control::Commands::playcontrolCommand);
	addCommand(	'pause', 			\&Slim::Control::Commands::playcontrolCommand);
	addCommand(	'mode', 			\&Slim::Control::Commands::playcontrolCommand);
	addQuery(	'mode', 			\&Slim::Control::Queries::modeQuery);

	addCommand(	'playerpref', 		\&Slim::Control::Commands::playerprefCommand);
	addQuery(	'playerpref', 		\&Slim::Control::Queries::playerprefQuery);

#	addCommand(	'rate',	 			\&Slim::Control::Commands::rateCommand);
#	addQuery(	'rate', 			\&Slim::Control::Queries::rateQuery);

	addCommand(	'rescan', 			\&Slim::Control::Commands::rescanCommand);
	addQuery(	'rescan', 			\&Slim::Control::Queries::rescanQuery);

	addQuery(	'signalstrength', 	\&Slim::Control::Queries::signalstrengthQuery);

	addCommand(	'sleep', 			\&Slim::Control::Commands::sleepCommand);
	addQuery(	'sleep', 			\&Slim::Control::Queries::sleepQuery);

	addQuery(	'version', 			\&Slim::Control::Queries::versionQuery);

	addCommand(	'wipecache', 		\&Slim::Control::Commands::wipecacheCommand);
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
