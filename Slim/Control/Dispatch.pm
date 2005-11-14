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


# add standard commands and queries to the dispatch hashes...
sub init {
	addCommand('pref', \&Slim::Control::Commands::prefCommand);
	addQuery('pref', \&Slim::Control::Queries::prefQuery);
	addCommand('rescan', \&Slim::Control::Commands::rescanCommand);
	addQuery('rescan', \&Slim::Control::Queries::rescanQuery);
	addCommand('wipecache', \&Slim::Control::Commands::wipecacheCommand);
	addQuery('version', \&Slim::Control::Queries::versionQuery);
	addCommand('debug', \&Slim::Control::Commands::debugCommand);
	addQuery('debug', \&Slim::Control::Queries::debugQuery);
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
	unless ($funcPtr) {
		errorMsg("dispatch(): Found no function for request [$requestText]\n" );
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

