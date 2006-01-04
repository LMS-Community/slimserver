package Slim::Control::Dispatch;

# $Id$
#
# SlimServer Copyright (C) 2001-2006 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use Slim::Control::Commands;
use Slim::Control::Queries;
use Slim::Control::Request;
use Slim::Utils::Misc;

our %notifications = ();
our %dispatchDB;

################
# COMMAND LIST #
################

# This table lists all supported commands with their parameters. 

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
# Y    mixer           muting                      <|?>


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
# Y    path            ?
# Y    playlist        name                        ?
# Y    playlist        url                         ?
# Y    playlist        modified                    ?
# Y    playlist        index|jump                  <index|?>
# Y    playlist        delete                      <index>
# Y    playlist        zap                         <index>
# Y    playlistcontrol <params>
# Y    playlist        move                        <fromindex>                 <toindex>
# Y    playlist        clear
# Y    playlist        shuffle                     <0|1|2|?|>
# Y    playlist        repeat                      <0|1|2|?|>
# Y    playlist        deleteitem                  <item> (item can be a song, playlist or directory)
# Y    status          <startindex>                <numitems>                  <tagged parameters>


# add standard commands and queries to the dispatch hashes...
sub init {

#############################################################################################################################################
#                                                                                        |requires Client
#                                                                                        |  |is a Query
#                                                                                        |  |  |has Tags
#                                                                                        |  |  |  |Function to call
#                 P0                P1                   P2              P3              C  Q  T  F
#############################################################################################################################################

    addDispatch(['album',           '?'],                                               [1, 1, 0, \&Slim::Control::Queries::cursonginfoQuery]);
    addDispatch(['artist',          '?'],                                               [1, 1, 0, \&Slim::Control::Queries::cursonginfoQuery]);
    addDispatch(['button',          '_buttoncode',      '_time',        '_orFunction'], [1, 0, 0, \&Slim::Control::Commands::buttonCommand]);
    addDispatch(['connected',       '?'],                                               [1, 1, 0, \&Slim::Control::Queries::connectedQuery]);
    addDispatch(['debug',           '_debugflag',       '?'],                           [0, 1, 0, \&Slim::Control::Queries::debugQuery]);
    addDispatch(['debug',           '_debugflag',       ,'_newvalue'],                  [0, 0, 0, \&Slim::Control::Commands::debugCommand]);
    addDispatch(['display',         '?',                '?'],                           [1, 1, 0, \&Slim::Control::Queries::displayQuery]);
    addDispatch(['display',         '_line1',           '_line2',       '_duration'],   [1, 0, 0, \&Slim::Control::Commands::displayCommand]);
    addDispatch(['displaynow',      '?',                '?'],                           [1, 1, 0, \&Slim::Control::Queries::displaynowQuery]);
    addDispatch(['duration',        '?'],                                               [1, 1, 0, \&Slim::Control::Queries::cursonginfoQuery]);
    addDispatch(['genre',           '?'],                                               [1, 1, 0, \&Slim::Control::Queries::cursonginfoQuery]);
    addDispatch(['gototime',        '?'],                                               [1, 1, 0, \&Slim::Control::Queries::timeQuery]);
    addDispatch(['gototime',        '_newvalue'],                                       [1, 0, 0, \&Slim::Control::Commands::timeCommand]);
    addDispatch(['info',            'total',            'albums',       '?'],           [0, 1, 0, \&Slim::Control::Queries::infoTotalQuery]);
    addDispatch(['info',            'total',            'artists',      '?'],           [0, 1, 0, \&Slim::Control::Queries::infoTotalQuery]);
    addDispatch(['info',            'total',            'genres',       '?'],           [0, 1, 0, \&Slim::Control::Queries::infoTotalQuery]);
    addDispatch(['info',            'total',            'songs',        '?'],           [0, 1, 0, \&Slim::Control::Queries::infoTotalQuery]);
    addDispatch(['ir',              '_ircode',          '_time'],                       [1, 0, 0, \&Slim::Control::Commands::irCommand]);
    addDispatch(['linesperscreen',  '?'],                                               [1, 1, 0, \&Slim::Control::Queries::linesperscreenQuery]);
    addDispatch(['mixer',           'bass',             '?'],                           [1, 1, 0, \&Slim::Control::Queries::mixerQuery]);
    addDispatch(['mixer',           'bass',             '_newvalue'],                   [1, 0, 0, \&Slim::Control::Commands::mixerCommand]);
    addDispatch(['mixer',           'muting',           '?'],                           [1, 1, 0, \&Slim::Control::Queries::mixerQuery]);
    addDispatch(['mixer',           'muting',           '_newvalue'],                   [1, 0, 0, \&Slim::Control::Commands::mixerCommand]);
    addDispatch(['mixer',           'pitch',            '?'],                           [1, 1, 0, \&Slim::Control::Queries::mixerQuery]);
    addDispatch(['mixer',           'pitch',            '_newvalue'],                   [1, 0, 0, \&Slim::Control::Commands::mixerCommand]);
    addDispatch(['mixer',           'treble',           '?'],                           [1, 1, 0, \&Slim::Control::Queries::mixerQuery]);
    addDispatch(['mixer',           'treble',           '_newvalue'],                   [1, 0, 0, \&Slim::Control::Commands::mixerCommand]);
    addDispatch(['mixer',           'volume',           '?'],                           [1, 1, 0, \&Slim::Control::Queries::mixerQuery]);
    addDispatch(['mixer',           'volume',           '_newvalue'],                   [1, 0, 0, \&Slim::Control::Commands::mixerCommand]);
    addDispatch(['mode',            'pause'],                                           [1, 0, 0, \&Slim::Control::Commands::playcontrolCommand]);
    addDispatch(['mode',            'play'],                                            [1, 0, 0, \&Slim::Control::Commands::playcontrolCommand]);
    addDispatch(['mode',            'stop'],                                            [1, 0, 0, \&Slim::Control::Commands::playcontrolCommand]);
    addDispatch(['mode',            '?'],                                               [1, 1, 0, \&Slim::Control::Queries::modeQuery]);
    addDispatch(['path',            '?'],                                               [1, 1, 0, \&Slim::Control::Queries::cursonginfoQuery]);
    addDispatch(['pause',           '_newvalue'],                                       [1, 0, 0, \&Slim::Control::Commands::playcontrolCommand]);
    addDispatch(['play'],                                                               [1, 0, 0, \&Slim::Control::Commands::playcontrolCommand]);
    addDispatch(['playlist',        'album',            '_index',       '?'],           [1, 1, 0, \&Slim::Control::Queries::playlistinfoQuery]);
    addDispatch(['playlist',        'artist',           '_index',       '?'],           [1, 1, 0, \&Slim::Control::Queries::playlistinfoQuery]);
    addDispatch(['playlist',        'clear'],                                           [1, 0, 0, \&Slim::Control::Commands::playlistClearCommand]);
    addDispatch(['playlist',        'duration',         '_index',       '?'],           [1, 1, 0, \&Slim::Control::Queries::playlistinfoQuery]);
    addDispatch(['playlist',        'delete',           '_index'],                      [1, 0, 0, \&Slim::Control::Commands::playlistDeleteCommand]);
    addDispatch(['playlist',        'deleteitem',       '_item'],                       [1, 0, 0, \&Slim::Control::Commands::playlistDeleteitemCommand]);
    addDispatch(['playlist',        'genre',            '_index',       '?'],           [1, 1, 0, \&Slim::Control::Queries::playlistinfoQuery]);
    addDispatch(['playlist',        'index',            '?'],                           [1, 1, 0, \&Slim::Control::Queries::playlistinfoQuery]);
    addDispatch(['playlist',        'index',            '_index',       '_noplay'],     [1, 0, 0, \&Slim::Control::Commands::playlistJumpCommand]);
    addDispatch(['playlist',        'jump',             '?'],                           [1, 1, 0, \&Slim::Control::Queries::playlistinfoQuery]);
    addDispatch(['playlist',        'jump',             '_index',       '_noplay'],     [1, 0, 0, \&Slim::Control::Commands::playlistJumpCommand]);
    addDispatch(['playlist',        'modified',         '?'],                           [1, 1, 0, \&Slim::Control::Queries::playlistinfoQuery]);
    addDispatch(['playlist',        'move',             '_fromindex',   '_toindex'],    [1, 0, 0, \&Slim::Control::Commands::playlistMoveCommand]);
    addDispatch(['playlist',        'name',             '?'],                           [1, 1, 0, \&Slim::Control::Queries::playlistinfoQuery]);
    addDispatch(['playlist',        'path',             '_index',       '?'],           [1, 1, 0, \&Slim::Control::Queries::playlistinfoQuery]);
    addDispatch(['playlist',        'repeat',           '?'],                           [1, 1, 0, \&Slim::Control::Queries::playlistinfoQuery]);
    addDispatch(['playlist',        'repeat',           '_newvalue'],                   [1, 0, 0, \&Slim::Control::Commands::playlistRepeatCommand]);
    addDispatch(['playlist',        'shuffle',          '?'],                           [1, 1, 0, \&Slim::Control::Queries::playlistinfoQuery]);
    addDispatch(['playlist',        'shuffle',          '_newvalue'],                   [1, 0, 0, \&Slim::Control::Commands::playlistShuffleCommand]);
    addDispatch(['playlist',        'title',            '_index',       '?'],           [1, 1, 0, \&Slim::Control::Queries::playlistinfoQuery]);
    addDispatch(['playlist',        'tracks',           '?'],                           [1, 1, 0, \&Slim::Control::Queries::playlistinfoQuery]);
    addDispatch(['playlist',        'url',              '?'],                           [1, 1, 0, \&Slim::Control::Queries::playlistinfoQuery]);
    addDispatch(['playlist',        'zap',              '_index'],                      [1, 0, 0, \&Slim::Control::Commands::playlistZapCommand]);
    addDispatch(['playlistcontrol'],                                                    [1, 0, 1, \&Slim::Control::Commands::playlistcontrolCommand]);
    addDispatch(['playerpref',      '_prefname',        '?'],                           [1, 1, 0, \&Slim::Control::Queries::playerprefQuery]);
    addDispatch(['playerpref',      '_prefname',        '_newvalue'],                   [1, 0, 0, \&Slim::Control::Commands::playerprefCommand]);
    addDispatch(['power',           '?'],                                               [1, 1, 0, \&Slim::Control::Queries::powerQuery]);
    addDispatch(['power',           '_newvalue'],                                       [1, 0, 0, \&Slim::Control::Commands::powerCommand]);
    addDispatch(['pref',            '_prefname',        '?'],                           [0, 1, 0, \&Slim::Control::Queries::prefQuery]);
    addDispatch(['pref',            '_prefname',        '_newvalue'],                   [0, 0, 0, \&Slim::Control::Commands::prefCommand]);
    addDispatch(['rate',            '?'],                                               [1, 1, 0, \&Slim::Control::Queries::rateQuery]);
    addDispatch(['rate',            '_newvalue'],                                       [1, 0, 0, \&Slim::Control::Commands::rateCommand]);
    addDispatch(['rescan',          '?'],                                               [0, 1, 0, \&Slim::Control::Queries::rescanQuery]);
    addDispatch(['rescan',          '_playlists'],                                      [0, 0, 0, \&Slim::Control::Commands::rescanCommand]);
    addDispatch(['signalstrength',  '?'],                                               [1, 1, 0, \&Slim::Control::Queries::signalstrengthQuery]);
    addDispatch(['sleep',           '?'],                                               [1, 1, 0, \&Slim::Control::Queries::sleepQuery]);
    addDispatch(['sleep',           '_newvalue'],                                       [1, 0, 0, \&Slim::Control::Commands::sleepCommand]);
    addDispatch(['status',          '_index',            '_quantity'],                  [1, 1, 1, \&Slim::Control::Queries::statusQuery]);
    addDispatch(['stop'],                                                               [1, 0, 0, \&Slim::Control::Commands::playcontrolCommand]);
    addDispatch(['sync',            '?'],                                               [1, 1, 0, \&Slim::Control::Queries::syncQuery]);
    addDispatch(['sync',            '_indexid-'],                                       [1, 0, 0, \&Slim::Control::Commands::syncCommand]);
    addDispatch(['time',            '?'],                                               [1, 1, 0, \&Slim::Control::Queries::timeQuery]);
    addDispatch(['time',            '_newvalue'],                                       [1, 0, 0, \&Slim::Control::Commands::timeCommand]);
    addDispatch(['title',           '?'],                                               [1, 1, 0, \&Slim::Control::Queries::cursonginfoQuery]);
    addDispatch(['version',         '?'],                                               [0, 1, 0, \&Slim::Control::Queries::versionQuery]);
    addDispatch(['wipecache'],                                                          [0, 0, 0, \&Slim::Control::Commands::wipecacheCommand]);

}

sub addDispatch {
	my $arrayCmdRef = shift;
	my $arrayDataRef = shift;

	my $DBp = \%dispatchDB;
	my $CRindex = 0;
	my $done = 0;
	
	while (!$done) {
	
		my $haveNextLevel = defined $arrayCmdRef->[$CRindex + 1];
		my $curVerb = $arrayCmdRef->[$CRindex];
	
		if (!defined $DBp->{$curVerb}) {
		
			if ($haveNextLevel) {
			
				$DBp->{$curVerb} = {};
				
			} else {
			
				$DBp->{$curVerb} = $arrayDataRef;
				$done = 1;
			}
		}
		
		elsif (ref $DBp->{$curVerb} eq 'ARRAY') {
		
			if ($haveNextLevel) {
			
				$DBp->{$curVerb} = {'', $DBp->{$curVerb}};
				
			} else {
			
				# replace...
				$DBp->{$curVerb} = $arrayDataRef;
				$done = 1;
			}
		}
		
		# go to next level if not done...
		if (!$done) {
		
			$DBp = \%{$DBp->{$curVerb}};
			$CRindex++;
		}
	}
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
#		$funcPtr = $dispatchQueries{$requestText};
	}
	else {
#		$funcPtr = $dispatchCommands{$requestText};
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

sub requestFromArray {
	my $client = shift;
	my $requestLineRef = shift;
	
	my $debug = 0;
	
	$::d_command && msg("Dispatch::requestFromArray(" . (join " ", @{$requestLineRef}) . ")\n");

	my $DBp = \%dispatchDB;
	my $LRindex = 0;
	my $found;
	my $done = 0;
	my $match = $requestLineRef->[$LRindex];
	my $outofverbs = !defined $match;
	
	my $request = new Slim::Control::Request($client);
	
	while (!$done) {
	
		# We're out of verbs to check for a match -> check if we can
		if (!defined $match) {
			# we don't, try to match ''
			$match = '';
			$outofverbs = 1;
		}

		$debug && msg("..Trying to match [$match]\n");
		$debug && print Data::Dumper::Dumper($DBp);

		# Our verb does not match in the hash 
		if (!defined $DBp->{$match}) {
		
			$debug && msg("..no match for [$match]\n");
			
			# if $match is '?', abandon ship
			if ($match eq '?') {
			
				$debug && msg("...[$match] is ?, done\n");
				$done = 1;
				
			} else {
			
				my $foundparam = 0;
				my $key;

				# Can we find a key that starts with '_' ?
				$debug && msg("...looking for a key starting with _\n");
				foreach $key (keys %{$DBp}) {
				
					$debug && msg("....considering [$key]\n");
					
					if ($key =~ /^_.*/) {
					
						$debug && msg("....[$key] starts with _\n");
						
						# found it, add $key=$match to the params
						if (!$outofverbs) {
							$debug && msg("....not out of verbs, adding param [$key, $match]\n");
							$request->addParam($key, $match);
						}
						
						# and continue with $key...
						$foundparam = 1;
						$match = $key;
						last;
					}
				}
				
				if (!$foundparam) {
					$done = 1;
				}
			}
		}
		
		# Our verb matches, and it is an array -> done
		if (!$done && ref $DBp->{$match} eq 'ARRAY') {
		
			$debug && msg("..[$match] is ARRAY -> done\n");
			
			if ($match ne '' && !($match =~ /^_.*/) && $match ne '?') {
			
				# add $match to the request list if it is something sensible
				$request->addRequest($match);
			}

			# we're pointing to an array -> done
			$done = 1;
			$found = $DBp->{$match};
		}
		
		# Our verb matches, and it is a hash -> go to next level
		# (no backtracking...)
		if (!$done && ref $DBp->{$match} eq 'HASH') {
		
			$debug && msg("..[$match] is HASH\n");

			if ($match ne '' && !($match =~ /^_.*/) && $match ne '?') {
			
				# add $match to the request list if it is something sensible
				$request->addRequest($match);
			}

			$DBp = \%{$DBp->{$match}};
			$match = $requestLineRef->[++$LRindex];
		}
	}

	if (defined $found) {
		# 0: needs client
		# 1: is a query
		# 2: has Tags
		# 3: Function
		
		# handle the remaining params
		for (my $i=++$LRindex; $i < scalar @{$requestLineRef}; $i++) {
			
			# try tags if we know we have some
			if ($found->[2] && ($requestLineRef->[$i] =~ /([^:]+):(.*)/)) {

				$request->addParam($1, $2);

			} else {
			
				# default to positional param...
				$request->addParamPos($requestLineRef->[$i]);
			}
		}

		$request->query($found->[1]);
		$request->setFunc($found->[3]);
		
		if (!defined $client && $found->[0]) {
			$request->setStatusNeedsClient();
		}

		return $request;
	}

	# handle the remaining params, if any...
	# only for the benefit of CLI echoing...
	for (my $i=++$LRindex; $i < scalar @{$requestLineRef}; $i++) {
		$request->addParamPos($requestLineRef->[$i]);
	}
	
	$::d_command && msg("Dispatch::requestFromArray: Request [" . (join " ", @{$requestLineRef}) . "]: no match in dispatchDB!\n");
	return undef;
}

1;
