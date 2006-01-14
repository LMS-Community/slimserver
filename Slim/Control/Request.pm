package Slim::Control::Request;

# SlimServer Copyright (c) 2001-2006 Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

# This class implements a generic request mechanism for SlimServer.
# More documentation is provided below the table of commands & queries

######################################################################################################################################################################
# COMMANDS & QUERIES LIST
######################################################################################################################################################################
#
# This table lists all supported commands with their parameters. 
#
# C     P0             P1                          P2                          P3               P4       P5
######################################################################################################################################################################

# GENERAL
# N    debug           <debugflag>                 <0|1|?|>
# N    pref            <prefname>                  <prefvalue|?>
# N    version         ?

# DATABASE
# N    rescan          <|playlists|?>
# N    wipecache
# N    playlists       <startindex>                <numitems>                  <tagged parameters>


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
# N    players         <startindex>                <numitems>                  <tagged parameters>
# N    player          count                       ?
# N    player          ip                          <index or ID>               ?
# N    player          id|address                  <index or ID>               ?
# N    player          name                        <index or ID>               ?
# N    player          model                       <index or ID>               ?
# N    player          displaytype                 <index or ID>               ?

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
# Y    playlist        move                        <fromindex>                 <toindex>
# Y    playlist        clear
# Y    playlist        shuffle                     <0|1|2|?|>
# Y    playlist        repeat                      <0|1|2|?|>
# Y    playlist        deleteitem                  <item> (item can be a song, playlist or directory)
# Y    playlist        loadalbum|playalbum         <genre>                     <artist>         <album>  <songtitle>
# Y    playlist        addalbum                    <genre>                     <artist>         <album>  <songtitle>
# Y    playlist        insertalbum                 <genre>                     <artist>         <album>  <songtitle>
# Y    playlist        deletealbum                 <genre>                     <artist>         <album>  <songtitle>
# Y    playlist        playtracks                  <searchterms>    
# Y    playlist        loadtracks                  <searchterms>    
# Y    playlist        addtracks                   <searchterms>    
# Y    playlist        inserttracks                <searchterms>    
# Y    playlist        deletetracks                <searchterms>   
# Y    playlist        play|load                   <item> (item can be a song, playlist or directory)
# Y    playlist        add|append                  <item> (item can be a song, playlist or directory)
# Y    playlist        insert|insertlist           <item> (item can be a song, playlist or directory)
# Y    playlist        resume                      <playlist>    
# Y    playlist        save                        <playlist>    
# Y    playlistcontrol <tagged parameters>
# Y    status          <startindex>                <numitems>                  <tagged parameters>
# Y    artists         <startindex>                <numitems>                  <tagged parameters>
# Y    albums          <startindex>                <numitems>                  <tagged parameters>
# Y    genres          <startindex>                <numitems>                  <tagged parameters>
# Y    titles          <startindex>                <numitems>                  <tagged parameters>
# Y    songinfo        <startindex>                <numitems>                  <tagged parameters>
# Y    playlists       <startindex>                <numitems>                  <tagged parameters>
# Y    playlisttracks  <startindex>                <numitems>                  <tagged parameters>

# NOTIFICATION
# The following 'terms' are used for notifications 

# Y    newclient
# Y    playlist        newsong
# Y    playlist        open                        <url>
# Y    playlist        sync

######################################################################################################################################################################


# ABOUT THIS CLASS
#
# This class implements a generic request mechanism for SlimServer.
# This new mechanism supplants (and hopefully) improves over the "legacy"
# mechanisms that used to be provided by Slim::Control::Command. Where 
# appropriate, the Request class provides hooks supporting this legacy.
# This is why, for example, the debug flag for this code is $::d_command.
#
#
# The general mechansim is to create a Request object and execute it. There
# is an option of specifying a callback function, to be called once the 
# request is executed. In addition, it is possible to be notified of command
# execution (see NOTIFICATIONS below).


# NOTIFICATIONS
#
# The Request mechanism can notify "subscriber" functions of successful
# command request execution (not of queries). Callback functions have a single
# parameter corresponding to the request object.
# Optionally, the subscribe routine accepts a filter, which limits calls to the
# subscriber callback to those requests matching the filter. The filter is
# in the form of an array ref containing arrays refs (one per dispatch level) 
# containing lists of desirable commands (easier to code than explain, see
# examples below)
#
# Example
#
# Slim::Control::Request::subscribe( \&myCallbackFunction, 
#                                     [['playlist']]);
# -> myCallbackFunction will be called for any command starting with 'playlist'
# in the table below ('playlist save', playlist loadtracks', etc).
#
# Slim::Control::Request::subscribe( \&myCallbackFunction, 
#				                      [['mode'], ['play', 'pause']]);
# -> myCallbackFunction will be called for commands "mode play" and
# "mode pause", but not for "mode stop".
#
# In both cases, myCallbackFunction must be defined as:
# sub myCallbackFunction {
#      my $request = shift;
#
#      # do something useful here
# }



use strict;

use Tie::LLHash;

use Slim::Control::Commands;
use Slim::Control::Queries;
use Slim::Utils::Misc;


our %dispatchDB;				# contains a multi-level hash pointing to
								# each command or query subroutine

our %subscribers = ();   		# contains the clients to the notification
								# mechanism

my $d_notify = 1;               # local debug flag for notifications. Note that
                                # $::d_command must be enabled as well.

################################################################################
# Package methods
################################################################################
# These function are really package functions, i.e. to be called like
#  Slim::Control::Request::subscribe() ...

# adds standard commands and queries to the dispatch DB...
sub init {

######################################################################################################################################################################
#                                                                                                     |requires Client
#                                                                                                     |  |is a Query
#                                                                                                     |  |  |has Tags
#                                                                                                     |  |  |  |Function to call
#                 P0               P1              P2            P3             P4         P5         C  Q  T  F
######################################################################################################################################################################

    addDispatch(['album',          '?'],                                                             [1, 1, 0, \&Slim::Control::Queries::cursonginfoQuery]);
    addDispatch(['albums',         '_index',      '_quantity'],                                      [0, 1, 1, \&Slim::Control::Queries::browseXQuery]);
    addDispatch(['artist',         '?'],                                                             [1, 1, 0, \&Slim::Control::Queries::cursonginfoQuery]);
    addDispatch(['artists',        '_index',      '_quantity'],                                      [0, 1, 1, \&Slim::Control::Queries::browseXQuery]);
    addDispatch(['button',         '_buttoncode',  '_time',      '_orFunction'],                     [1, 0, 0, \&Slim::Control::Commands::buttonCommand]);
    addDispatch(['connected',      '?'],                                                             [1, 1, 0, \&Slim::Control::Queries::connectedQuery]);
    addDispatch(['debug',          '_debugflag',   '?'],                                             [0, 1, 0, \&Slim::Control::Queries::debugQuery]);
    addDispatch(['debug',          '_debugflag',   '_newvalue'],                                     [0, 0, 0, \&Slim::Control::Commands::debugCommand]);
    addDispatch(['display',        '?',            '?'],                                             [1, 1, 0, \&Slim::Control::Queries::displayQuery]);
    addDispatch(['display',        '_line1',       '_line2',     '_duration'],                       [1, 0, 0, \&Slim::Control::Commands::displayCommand]);
    addDispatch(['displaynow',     '?',            '?'],                                             [1, 1, 0, \&Slim::Control::Queries::displaynowQuery]);
    addDispatch(['duration',       '?'],                                                             [1, 1, 0, \&Slim::Control::Queries::cursonginfoQuery]);
    addDispatch(['genre',          '?'],                                                             [1, 1, 0, \&Slim::Control::Queries::cursonginfoQuery]);
    addDispatch(['genres',         '_index',      '_quantity'],                                      [0, 1, 1, \&Slim::Control::Queries::browseXQuery]);
    addDispatch(['gototime',       '?'],                                                             [1, 1, 0, \&Slim::Control::Queries::timeQuery]);
    addDispatch(['gototime',       '_newvalue'],                                                     [1, 0, 0, \&Slim::Control::Commands::timeCommand]);
    addDispatch(['info',           'total',        'albums',     '?'],                               [0, 1, 0, \&Slim::Control::Queries::infoTotalQuery]);
    addDispatch(['info',           'total',        'artists',    '?'],                               [0, 1, 0, \&Slim::Control::Queries::infoTotalQuery]);
    addDispatch(['info',           'total',        'genres',     '?'],                               [0, 1, 0, \&Slim::Control::Queries::infoTotalQuery]);
    addDispatch(['info',           'total',        'songs',      '?'],                               [0, 1, 0, \&Slim::Control::Queries::infoTotalQuery]);
    addDispatch(['ir',             '_ircode',      '_time'],                                         [1, 0, 0, \&Slim::Control::Commands::irCommand]);
    addDispatch(['linesperscreen', '?'],                                                             [1, 1, 0, \&Slim::Control::Queries::linesperscreenQuery]);
    addDispatch(['mixer',          'bass',         '?'],                                             [1, 1, 0, \&Slim::Control::Queries::mixerQuery]);
    addDispatch(['mixer',          'bass',         '_newvalue'],                                     [1, 0, 0, \&Slim::Control::Commands::mixerCommand]);
    addDispatch(['mixer',          'muting',       '?'],                                             [1, 1, 0, \&Slim::Control::Queries::mixerQuery]);
    addDispatch(['mixer',          'muting',       '_newvalue'],                                     [1, 0, 0, \&Slim::Control::Commands::mixerCommand]);
    addDispatch(['mixer',          'pitch',        '?'],                                             [1, 1, 0, \&Slim::Control::Queries::mixerQuery]);
    addDispatch(['mixer',          'pitch',        '_newvalue'],                                     [1, 0, 0, \&Slim::Control::Commands::mixerCommand]);
    addDispatch(['mixer',          'treble',       '?'],                                             [1, 1, 0, \&Slim::Control::Queries::mixerQuery]);
    addDispatch(['mixer',          'treble',       '_newvalue'],                                     [1, 0, 0, \&Slim::Control::Commands::mixerCommand]);
    addDispatch(['mixer',          'volume',       '?'],                                             [1, 1, 0, \&Slim::Control::Queries::mixerQuery]);
    addDispatch(['mixer',          'volume',       '_newvalue'],                                     [1, 0, 0, \&Slim::Control::Commands::mixerCommand]);
    addDispatch(['mode',           'pause'],                                                         [1, 0, 0, \&Slim::Control::Commands::playcontrolCommand]);
    addDispatch(['mode',           'play'],                                                          [1, 0, 0, \&Slim::Control::Commands::playcontrolCommand]);
    addDispatch(['mode',           'stop'],                                                          [1, 0, 0, \&Slim::Control::Commands::playcontrolCommand]);
    addDispatch(['mode',           '?'],                                                             [1, 1, 0, \&Slim::Control::Queries::modeQuery]);
    addDispatch(['path',           '?'],                                                             [1, 1, 0, \&Slim::Control::Queries::cursonginfoQuery]);
    addDispatch(['pause',          '_newvalue'],                                                     [1, 0, 0, \&Slim::Control::Commands::playcontrolCommand]);
    addDispatch(['play'],                                                                            [1, 0, 0, \&Slim::Control::Commands::playcontrolCommand]);
    addDispatch(['player',         'address',      '_IDorIndex', '?'],                               [0, 1, 0, \&Slim::Control::Queries::playerXQuery]);
    addDispatch(['player',         'count',        '?'],                                             [0, 1, 0, \&Slim::Control::Queries::playerXQuery]);
    addDispatch(['player',         'displaytype',  '_IDorIndex', '?'],                               [0, 1, 0, \&Slim::Control::Queries::playerXQuery]);
    addDispatch(['player',         'id',           '_IDorIndex', '?'],                               [0, 1, 0, \&Slim::Control::Queries::playerXQuery]);
    addDispatch(['player',         'ip',           '_IDorIndex', '?'],                               [0, 1, 0, \&Slim::Control::Queries::playerXQuery]);
    addDispatch(['player',         'model',        '_IDorIndex', '?'],                               [0, 1, 0, \&Slim::Control::Queries::playerXQuery]);
    addDispatch(['player',         'name',         '_IDorIndex', '?'],                               [0, 1, 0, \&Slim::Control::Queries::playerXQuery]);
    addDispatch(['playerpref',     '_prefname',    '?'],                                             [1, 1, 0, \&Slim::Control::Queries::playerprefQuery]);
    addDispatch(['playerpref',     '_prefname',    '_newvalue'],                                     [1, 0, 0, \&Slim::Control::Commands::playerprefCommand]);
    addDispatch(['players',        '_index',       '_quantity'],                                     [0, 1, 1, \&Slim::Control::Queries::playersQuery]);
    addDispatch(['playlist',       'add',          '_item'],                                         [1, 0, 0, \&Slim::Control::Commands::playlistXitemCommand]);
    addDispatch(['playlist',       'addalbum',     '_genre',     '_artist',     '_album', '_title'], [1, 0, 0, \&Slim::Control::Commands::playlistXalbumCommand]);
    addDispatch(['playlist',       'addtracks',    '_what',      '_listref'],                        [1, 0, 0, \&Slim::Control::Commands::playlistXtracksCommand]);
    addDispatch(['playlist',       'album',        '_index',     '?'],                               [1, 1, 0, \&Slim::Control::Queries::playlistXQuery]);
    addDispatch(['playlist',       'append',       '_item'],                                         [1, 0, 0, \&Slim::Control::Commands::playlistXitemCommand]);
    addDispatch(['playlist',       'artist',       '_index',     '?'],                               [1, 1, 0, \&Slim::Control::Queries::playlistXQuery]);
    addDispatch(['playlist',       'clear'],                                                         [1, 0, 0, \&Slim::Control::Commands::playlistClearCommand]);
    addDispatch(['playlist',       'delete',       '_index'],                                        [1, 0, 0, \&Slim::Control::Commands::playlistDeleteCommand]);
    addDispatch(['playlist',       'deletealbum',  '_genre',     '_artist',     '_album', '_title'], [1, 0, 0, \&Slim::Control::Commands::playlistXalbumCommand]);
    addDispatch(['playlist',       'deleteitem',   '_item'],                                         [1, 0, 0, \&Slim::Control::Commands::playlistDeleteitemCommand]);
    addDispatch(['playlist',       'deletetracks', '_what',      '_listref'],                        [1, 0, 0, \&Slim::Control::Commands::playlistXtracksCommand]);
    addDispatch(['playlist',       'duration',     '_index',     '?'],                               [1, 1, 0, \&Slim::Control::Queries::playlistXQuery]);
    addDispatch(['playlist',       'genre',        '_index',     '?'],                               [1, 1, 0, \&Slim::Control::Queries::playlistXQuery]);
    addDispatch(['playlist',       'index',        '?'],                                             [1, 1, 0, \&Slim::Control::Queries::playlistXQuery]);
    addDispatch(['playlist',       'index',        '_index',     '_noplay'],                         [1, 0, 0, \&Slim::Control::Commands::playlistJumpCommand]);
    addDispatch(['playlist',       'insert',       '_item'],                                         [1, 0, 0, \&Slim::Control::Commands::playlistXitemCommand]);
    addDispatch(['playlist',       'insertlist',   '_item'],                                         [1, 0, 0, \&Slim::Control::Commands::playlistXitemCommand]);
    addDispatch(['playlist',       'insertalbum',  '_genre',     '_artist',     '_album', '_title'], [1, 0, 0, \&Slim::Control::Commands::playlistXalbumCommand]);
    addDispatch(['playlist',       'inserttracks', '_what',      '_listref'],                        [1, 0, 0, \&Slim::Control::Commands::playlistXtracksCommand]);
    addDispatch(['playlist',       'jump',         '?'],                                             [1, 1, 0, \&Slim::Control::Queries::playlistXQuery]);
    addDispatch(['playlist',       'jump',         '_index',     '_noplay'],                         [1, 0, 0, \&Slim::Control::Commands::playlistJumpCommand]);
    addDispatch(['playlist',       'load',         '_item'],                                         [1, 0, 0, \&Slim::Control::Commands::playlistXitemCommand]);
    addDispatch(['playlist',       'loadalbum',    '_genre',     '_artist',     '_album', '_title'], [1, 0, 0, \&Slim::Control::Commands::playlistXalbumCommand]);
    addDispatch(['playlist',       'loadtracks',   '_what',      '_listref'],                        [1, 0, 0, \&Slim::Control::Commands::playlistXtracksCommand]);
    addDispatch(['playlist',       'modified',     '?'],                                             [1, 1, 0, \&Slim::Control::Queries::playlistXQuery]);
    addDispatch(['playlist',       'move',         '_fromindex', '_toindex'],                        [1, 0, 0, \&Slim::Control::Commands::playlistMoveCommand]);
    addDispatch(['playlist',       'name',         '?'],                                             [1, 1, 0, \&Slim::Control::Queries::playlistXQuery]);
    addDispatch(['playlist',       'path',         '_index',     '?'],                               [1, 1, 0, \&Slim::Control::Queries::playlistXQuery]);
    addDispatch(['playlist',       'play',         '_item'],                                         [1, 0, 0, \&Slim::Control::Commands::playlistXitemCommand]);
    addDispatch(['playlist',       'playalbum',    '_genre',     '_artist',     '_album', '_title'], [1, 0, 0, \&Slim::Control::Commands::playlistXalbumCommand]);
    addDispatch(['playlist',       'playtracks',   '_what',      '_listref'],                        [1, 0, 0, \&Slim::Control::Commands::playlistXtracksCommand]);
    addDispatch(['playlist',       'repeat',       '?'],                                             [1, 1, 0, \&Slim::Control::Queries::playlistXQuery]);
    addDispatch(['playlist',       'repeat',       '_newvalue'],                                     [1, 0, 0, \&Slim::Control::Commands::playlistRepeatCommand]);
    addDispatch(['playlist',       'resume',       '_item'],                                         [1, 0, 0, \&Slim::Control::Commands::playlistXitemCommand]);
    addDispatch(['playlist',       'save',         '_title'],                                        [1, 0, 0, \&Slim::Control::Commands::playlistSaveCommand]);
    addDispatch(['playlist',       'shuffle',      '?'],                                             [1, 1, 0, \&Slim::Control::Queries::playlistXQuery]);
    addDispatch(['playlist',       'shuffle',      '_newvalue'],                                     [1, 0, 0, \&Slim::Control::Commands::playlistShuffleCommand]);
    addDispatch(['playlist',       'title',        '_index',     '?'],                               [1, 1, 0, \&Slim::Control::Queries::playlistXQuery]);
    addDispatch(['playlist',       'tracks',       '?'],                                             [1, 1, 0, \&Slim::Control::Queries::playlistXQuery]);
    addDispatch(['playlist',       'url',          '?'],                                             [1, 1, 0, \&Slim::Control::Queries::playlistXQuery]);
    addDispatch(['playlist',       'zap',          '_index'],                                        [1, 0, 0, \&Slim::Control::Commands::playlistZapCommand]);
    addDispatch(['playlisttracks', '_index',      '_quantity'],                                      [0, 1, 1, \&Slim::Control::Queries::playlisttracksQuery]);
    addDispatch(['playlists',      '_index',       '_quantity'],                                     [0, 1, 1, \&Slim::Control::Queries::playlistsQuery]);
    addDispatch(['playlistcontrol'],                                                                 [1, 0, 1, \&Slim::Control::Commands::playlistcontrolCommand]);
    addDispatch(['power',          '?'],                                                             [1, 1, 0, \&Slim::Control::Queries::powerQuery]);
    addDispatch(['power',          '_newvalue'],                                                     [1, 0, 0, \&Slim::Control::Commands::powerCommand]);
    addDispatch(['pref',           '_prefname',   '?'],                                              [0, 1, 0, \&Slim::Control::Queries::prefQuery]);
    addDispatch(['pref',           '_prefname',   '_newvalue'],                                      [0, 0, 0, \&Slim::Control::Commands::prefCommand]);
    addDispatch(['rate',           '?'],                                                             [1, 1, 0, \&Slim::Control::Queries::rateQuery]);
    addDispatch(['rate',           '_newvalue'],                                                     [1, 0, 0, \&Slim::Control::Commands::rateCommand]);
    addDispatch(['rescan',         '?'],                                                             [0, 1, 0, \&Slim::Control::Queries::rescanQuery]);
    addDispatch(['rescan',         '_playlists'],                                                    [0, 0, 0, \&Slim::Control::Commands::rescanCommand]);
    addDispatch(['signalstrength', '?'],                                                             [1, 1, 0, \&Slim::Control::Queries::signalstrengthQuery]);
    addDispatch(['sleep',          '?'],                                                             [1, 1, 0, \&Slim::Control::Queries::sleepQuery]);
    addDispatch(['sleep',          '_newvalue'],                                                     [1, 0, 0, \&Slim::Control::Commands::sleepCommand]);
    addDispatch(['songinfo',       '_index',      '_quantity'],                                      [0, 1, 1, \&Slim::Control::Queries::songinfoQuery]);
    addDispatch(['status',         '_index',      '_quantity'],                                      [1, 1, 1, \&Slim::Control::Queries::statusQuery]);
    addDispatch(['stop'],                                                                            [1, 0, 0, \&Slim::Control::Commands::playcontrolCommand]);
    addDispatch(['sync',           '?'],                                                             [1, 1, 0, \&Slim::Control::Queries::syncQuery]);
    addDispatch(['sync',           '_indexid-'],                                                     [1, 0, 0, \&Slim::Control::Commands::syncCommand]);
    addDispatch(['time',           '?'],                                                             [1, 1, 0, \&Slim::Control::Queries::timeQuery]);
    addDispatch(['time',           '_newvalue'],                                                     [1, 0, 0, \&Slim::Control::Commands::timeCommand]);
    addDispatch(['title',          '?'],                                                             [1, 1, 0, \&Slim::Control::Queries::cursonginfoQuery]);
    addDispatch(['titles',         '_index',      '_quantity'],                                      [0, 1, 1, \&Slim::Control::Queries::titlesQuery]);
    addDispatch(['version',        '?'],                                                             [0, 1, 0, \&Slim::Control::Queries::versionQuery]);
    addDispatch(['wipecache'],                                                                       [0, 0, 0, \&Slim::Control::Commands::wipecacheCommand]);

    addDispatch(['newclient'],                                                                       [1, 0, 0, undef]);
    addDispatch(['playlist',       'open',        '_path'],                                          [1, 0, 0, undef]);
    addDispatch(['playlist',       'newsong'],                                                       [1, 0, 0, undef]);
    addDispatch(['playlist',       'sync'],                                                          [1, 0, 0, undef]);

######################################################################################################################################################################

}

# add an entry to the dispatch DB
sub addDispatch {
	my $arrayCmdRef  = shift; # the array containing the command or query
	my $arrayDataRef = shift; # the array containing the function to call

# parse the first array in parameter to create a multi level hash providing
# fast access to 2nd array data, i.e. (the example is incomplete!)
# { 
#  'rescan' => {
#               '?'          => 2nd array associated with ['rescan', '?']
#               '_playlists' => 2nd array associated with ['rescan', '_playlists']
#              },
#  'info'   => {
#               'total'      => {
#                                'albums'  => 2nd array associated with ['info', 'total', albums']
# ...
#
# this is used by init() above to add the standard commands and queries to the 
# table and by the plugin glue code to add plugin-specific and plugin-defined
# commands and queries to the system.
# Note that for the moment, there is no identified need to ever REMOVE commands
# from the dispatch table (and consequently no defined function for that).

	my $DBp     = \%dispatchDB;	    # pointer to the current table level
	my $CRindex = 0;                # current index into $arrayCmdRef
	my $done    = 0;                # are we done
	my $oldDR;						# if we replace, what did we?
	
	while (!$done) {
	
		# check if we have a subsequent verb in the command
		my $haveNextLevel = defined $arrayCmdRef->[$CRindex + 1];
		
		# get the verb at the current level of the command
		my $curVerb       = $arrayCmdRef->[$CRindex];
	
		# if the verb is undefined at the current level
		if (!defined $DBp->{$curVerb}) {
		
			# if we have a next verb, prepare a hash for it
			if ($haveNextLevel) {
			
				$DBp->{$curVerb} = {};
			
			# else store the 2nd array and we're done
			} else {
			
				$DBp->{$curVerb} = $arrayDataRef;
				$done = 1;
			}
		}
		
		# if the verb defined at the current level points to an array
		elsif (ref $DBp->{$curVerb} eq 'ARRAY') {
		
			# if we have more terms, move the array to the next level using
			# an empty verb
			# (note: at the time of writing these lines, this never occurs with
			# the commands as defined now)
			if ($haveNextLevel) {
			
				$DBp->{$curVerb} = {'', $DBp->{$curVerb}};
			
			# if we're out of terms, something is maybe wrong as we're adding 
			# twice the same command. In Perl hash fashion, replace silently with
			# the new value and we're done
			} else {
			
				$oldDR = $DBp->{$curVerb};
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
	
	# return what we replaced, if any
	return $oldDR;
}

# add a subscriber to be notified of requests
sub subscribe {
	my $subscriberFuncRef = shift || return;
	my $requestsRef = shift;
	
	$subscribers{$subscriberFuncRef} = [$subscriberFuncRef, $requestsRef];
	
	$::d_command && $d_notify && msg("Request: subscribe($subscriberFuncRef)"
		. " - (" . scalar(keys %subscribers) . " suscribers)\n");
}

# remove a subscriber
sub unsubscribe {
	my $subscriberFuncRef = shift;
	
	delete $subscribers{$subscriberFuncRef};
	
	$::d_command && $d_notify && msg("Request: unsubscribe($subscriberFuncRef)" 
		. " - (" . scalar(keys %subscribers) . " suscribers)\n");
}

# notify subscribers from an array, useful for notifying w/o execution
# (requests must, however, be defined in the dispatch table)
sub notifyFromArray {
	my $client         = shift;     # client, if any, to which the query applies
	my $requestLineRef = shift;     # reference to an array containing the 
									# query verbs

	$::d_command && $d_notify && msg("Request: notifyFromArray(" .
						(join " ", @{$requestLineRef}) . ")\n");

	my $request = Slim::Control::Request->new($client, $requestLineRef);
	
	$request->notify() if defined $request;
}

# convenient function to execute a request from an array, with optional
# callback parameters. Returns the Request object.
sub executeRequest {
	my($client, $parrayref, $callbackf, $callbackargs) = @_;

	# create a request from the array
	my $request = Slim::Control::Request->new($client, $parrayref);
	
	if (defined $request && $request->isStatusDispatchable()) {
		
		# add callback params
		$request->callbackParameters($callbackf, $callbackargs);
		
		$request->execute();
	}

	return $request;
}

# perform the same feat that the old execute: array in, array out
sub executeLegacy {

	my $request = executeRequest(@_);
	
	return $request->renderAsArray() if defined $request;
}

################################################################################
# Constructors
################################################################################

sub new {
	my $class = shift;             # class to construct
	my $client = shift;            # client, if any, to which the request applies
	my $requestLineRef = shift;    # reference to an array containing the 
                                   # request verbs
	
	tie (my %paramHash, "Tie::LLHash", {lazy => 1});
	tie (my %resultHash, "Tie::LLHash", {lazy => 1});
	
	my $self = {
		'_request'    => [],
		'_isQuery'    => undef,
		'_client'     => $client,
		'_needClient' => 0,
		'_params'     => \%paramHash,
		'_curparam'   => 0,
		'_status'     => 0,
		'_results'    => \%resultHash,
		'_func'       => undef,
		'_cb_enable'  => 1,
		'_cb_func'    => undef,
		'_cb_args'    => undef,
		'_source'     => undef,
	};

	bless $self, $class;
	
	# parse $requestLineRef to finish create the Request
	$self->__parse($requestLineRef);
	
	return $self;
}


################################################################################
# Read/Write basic query attributes
################################################################################

# sets/returns the client
sub client {
	my $self = shift;
	my $client = shift;
	
	if (defined $client) {
		$self->{'_client'} = $client;
		$self->validate();
	}
	
	return $self->{'_client'};
}

# sets/returns the need client state
sub needClient {
	my $self = shift;
	my $needClient = shift;
	
	if (defined $needClient) {
		$self->{'_needClient'} = $needClient;
		$self->validate();
	}

	return $self->{'_needClient'};
}

# sets/returns the query state
sub query {
	my $self = shift;
	my $isQuery = shift;
	
	$self->{'_isQuery'} = $isQuery if defined $isQuery;
	
	return $self->{'_isQuery'};
}

# sets/returns the function that executes the request
sub executeFunction {
	my $self = shift;
	my $newvalue = shift;
	
	if (defined $newvalue) {
		$self->{'_func'} = $newvalue;
		$self->validate();
	}
	
	return $self->{'_func'};
}

# sets/returns the callback enabled state
sub callbackEnabled {
	my $self = shift;
	my $newvalue = shift;
	
	$self->{'_cb_enable'} = $newvalue if defined $newvalue;
	
	return $self->{'_cb_enable'};
}

# sets/returns the callback function
sub callbackFunction {
	my $self = shift;
	my $newvalue = shift;
	
	$self->{'_cb_func'} = $newvalue if defined $newvalue;
	
	return $self->{'_cb_func'};
}

# sets/returns the callback arguments
sub callbackArguments {
	my $self = shift;
	my $newvalue = shift;
	
	$self->{'_cb_args'} = $newvalue if defined $newvalue;
	
	return $self->{'_cb_args'};
}

# sets/returns the request source
sub source {
	my $self = shift;
	my $newvalue = shift;
	
	$self->{'_source'} = $newvalue if defined $newvalue;
	
	return $self->{'_source'};
}


################################################################################
# Read/Write status
################################################################################
# useful hash for debugging and as a reminder when writing new status methods
my %statusMap = (
	  0 => 'New',
	  1 => 'Dispatchable',
	  2 => 'Dispatched',
	 10 => 'Done',
	 11 => 'Callback done',
	101 => 'Bad dispatch!',
	102 => 'Bad params!',
	103 => 'Missing client!',
	104 => 'Unkown in dispatch table',
);

# validate the Request, make sure we are dispatchable
sub validate {
	my $self = shift;

	if (ref($self->executeFunction) ne 'CODE') {

		$self->setStatusNotDispatchable();

	} elsif ($self->needClient() && !$self->client()) {

		$self->setStatusNeedsClient();

	} else {

		$self->setStatusDispatchable();
	}
}

sub isStatusNew {
	my $self = shift;
	return ($self->__status() == 0);
}

sub setStatusDispatchable {
	my $self = shift;
	$self->__status(1);
}

sub isStatusDispatchable {
	my $self = shift;
	return ($self->__status() == 1);
}

sub setStatusDispatched {
	my $self = shift;
	$self->__status(2);
}

sub isStatusDispatched {
	my $self = shift;
	return ($self->__status() == 2);
}

sub wasStatusDispatched {
	my $self = shift;
	return ($self->__status() > 1);
}

sub setStatusDone {
	my $self = shift;
	$self->__status(10);
}

sub isStatusDone {
	my $self = shift;
	return ($self->__status() == 10);
}

sub setStatusCallbackDone {
	my $self = shift;
	$self->__status(11);
}

sub isStatusCallbackDone {
	my $self = shift;
	return ($self->__status() == 11);
}

sub isStatusError {
	my $self = shift;
	return ($self->__status() > 100);
}

sub setStatusBadDispatch {
	my $self = shift;	
	$self->__status(101);
}

sub isStatusBadDispatch {
	my $self = shift;
	return ($self->__status() == 101);
}

sub setStatusBadParams {
	my $self = shift;	
	$self->__status(102);
}

sub isStatusBadParams {
	my $self = shift;
	return ($self->__status() == 102);
}

sub setStatusNeedsClient {
	my $self = shift;	
	$self->__status(103);
}

sub isStatusNeedsClient {
	my $self = shift;
	return ($self->__status() == 103);
}

sub setStatusNotDispatchable {
	my $self = shift;	
	$self->__status(104);
}

sub isStatusNotDispatchable {
	my $self = shift;
	return ($self->__status() == 104);
}

################################################################################
# Request mgmt
################################################################################

# returns the request name. Read-only
sub getRequestString {
	my $self = shift;
	
	return join " ", @{$self->{_request}};
}

# add a request value to the request array
sub addRequest {
	my $self = shift;
	my $text = shift;

	push @{$self->{'_request'}}, $text;
	++$self->{'_curparam'};
}

sub getRequest {
	my $self = shift;
	my $idx = shift;
	
	return $self->{'_request'}->[$idx];
}

sub getRequestCount {
	my $self = shift;
	my $idx = shift;
	
	return scalar @{$self->{'_request'}};
}

################################################################################
# Param mgmt
################################################################################

sub addParam {
	my $self = shift;
	my $key = shift;
	my $val = shift;

	${$self->{'_params'}}{$key} = $val;
	++$self->{'_curparam'};
}


sub addParamHash {
	my $self = shift;
	my $hashRef = shift || return;
	
	while (my ($key,$value) = each %{$hashRef}) {
        $self->addParam($key, $value);
    }
}

sub addParamPos {
	my $self = shift;
	my $val = shift;
	
	${$self->{'_params'}}{ "_p" . $self->{'_curparam'}++ } = $val;
}

sub getParam {
	my $self = shift;
	my $key = shift || return;
	
	return ${$self->{'_params'}}{$key};
}

################################################################################
# Result mgmt
################################################################################

sub addResult {
	my $self = shift;
	my $key = shift;
	my $val = shift;

	${$self->{'_results'}}{$key} = $val;
}

sub addResultLoop {
	my $self = shift;
	my $loop = shift;
	my $loopidx = shift;
	my $key = shift;
	my $val = shift;

	if ($loop !~ /^@.*/) {
		$loop = '@' . $loop;
	}
	
	if (!defined ${$self->{'_results'}}{$loop}) {
		${$self->{'_results'}}{$loop} = [];
	}
	
	if (!defined ${$self->{'_results'}}{$loop}->[$loopidx]) {
		tie (my %paramHash, "Tie::LLHash", {lazy => 1});
		${$self->{'_results'}}{$loop}->[$loopidx] = \%paramHash;
	}
	
	${${$self->{'_results'}}{$loop}->[$loopidx]}{$key} = $val;
}

sub setResultLoopHash {
	my $self = shift;
	my $loop = shift;
	my $loopidx = shift;
	my $hashRef = shift;
	
	if ($loop !~ /^@.*/) {
		$loop = '@' . $loop;
	}
	
	if (!defined ${$self->{'_results'}}{$loop}) {
		${$self->{'_results'}}{$loop} = [];
	}
	
	${$self->{'_results'}}{$loop}->[$loopidx] = $hashRef;
}

sub getResult {
	my $self = shift;
	my $key = shift || return;
	
	return ${$self->{'_results'}}{$key};
}

sub getResultLoopCount {
	my $self = shift;
	my $loop = shift;
	
	if ($loop !~ /^@.*/) {
		$loop = '@' . $loop;
	}
	
	if (defined ${$self->{'_results'}}{$loop}) {
		return scalar(@{${$self->{'_results'}}{$loop}});
	}
}

sub getResultLoop {
	my $self = shift;
	my $loop = shift;
	my $loopidx = shift;
	my $key = shift || return undef;

	if ($loop !~ /^@.*/) {
		$loop = '@' . $loop;
	}
	
	if (defined ${$self->{'_results'}}{$loop} && 
		defined ${$self->{'_results'}}{$loop}->[$loopidx]) {
		
			return ${${$self->{'_results'}}{$loop}->[$loopidx]}{$key};
	}
	return undef;
}



################################################################################
# Compound calls
################################################################################

# accepts a reference to an array containing references to arrays containing
# synonyms for the query names, 
# and returns 1 if no name match the request. Used by functions implementing
# queries to check the dispatcher did not send them a wrong request.
# See Queries.pm for usage examples, for example infoTotalQuery.
sub isNotQuery {
	my $self = shift;
	my $possibleNames = shift;
	
	return !$self->__isCmdQuery(1, $possibleNames);
}

# same for commands
sub isNotCommand {
	my $self = shift;
	my $possibleNames = shift;
	
	return !$self->__isCmdQuery(0, $possibleNames);
}

sub isCommand{
	my $self = shift;
	my $possibleNames = shift;
	
	return $self->__isCmdQuery(0, $possibleNames);
}

# returns true if $param is undefined or not one of the possible values
# not really a method on request data members but defined as such since it is
# useful for command and queries implementation.
sub paramUndefinedOrNotOneOf {
	my $self = shift;
	my $param = shift;
	my $possibleValues = shift;

	return 1 if !defined $param;
	return 1 if !defined $possibleValues;
	return !grep(/$param/, @{$possibleValues});
}

# sets callback parameters (function and arguments) in a single call...
sub callbackParameters {
	my $self = shift;
	my $callbackf = shift;
	my $callbackargs = shift;

	$self->{'_cb_func'} = $callbackf;
	$self->{'_cb_args'} = $callbackargs;	
}

################################################################################
# Other
################################################################################

# execute the request
sub execute {
	my $self = shift;
	
	$::d_command && msg("\n");
#	$::d_command && $self->dump("Request");

	# do nothing if something's wrong
	if ($self->isStatusError()) {
		$::d_command && msg('Request: Request in error, exiting');
		return;
	}
	
	# call the execute function
	if (my $funcPtr = $self->executeFunction()) {

		if (defined $funcPtr && ref($funcPtr) eq 'CODE') {

			eval { &{$funcPtr}($self) };

			if ($@) {
				errorMsg("execute: Error when trying to run coderef: [$@]\n");
				$self->dump('Request');
			}

		} else {

			errorMsg("execute: Didn't get a valid coderef from ->executeFunction\n");
			$self->dump('Request');
		}
	}
	
	# if the status is done
	if ($self->isStatusDone()) {

		$::d_command && $self->dump('Request');
		
		# perform the callback
		$self->callback();
		
		# notify for commands
		if (!$self->query()) {
		
			$self->notify();
		}

	} else {

		$::d_command && $self->dump('Request');
	}
}

sub callback {
	my $self = shift;

	# do nothing unless callback is enabled
	if ($self->callbackEnabled()) {
		
		if (defined(my $funcPtr = $self->callbackFunction())) {

			$::d_command && msg("Request: Calling callback function\n");

			my $args = $self->callbackArguments();
		
			# if we have no arg, use the request
			if (!defined $args) {

				eval { &$funcPtr($self) };

				if ($@) { 
					errorMsg("callback: Error when trying to run coderef: [$@]\n");
					$self->dump('Request');
				}
			
			# else use the provided arguments
			} else {

				eval { &$funcPtr(@$args) };

				if ($@) { 
					errorMsg("callback: Error when trying to run coderef: [$@]\n");
					$self->dump('Request');
				}
			}

			$self->setStatusCallbackDone();
		}

	} else {
	
		$::d_command && msg("Request: Callback disabled\n");
	}
}

# notify subscribers...
sub notify {
	my $self = shift || return;
	my $dontcallExecuteCallback = shift;

	for my $subscriber (keys %subscribers) {

		# filter based on desired requests
		# undef means no filter
		my $requestsRef = $subscribers{$subscriber}->[1];
		
		if (defined($requestsRef)) {

			if ($self->isNotCommand($requestsRef)) {

				$::d_command && $d_notify && msg("Request: Don't notify "
					. $subscriber . " of " . $self->getRequestString() . " !~ "
					. __filterString($requestsRef) . "\n");

				next;
			}
		}

		$::d_command && $d_notify && msg("Request: Notifying $subscriber of " 
			. $self->getRequestString() . " =~ "
			. __filterString($requestsRef) . "\n");
		
		my $notifyFuncRef = $subscribers{$subscriber}->[0];
		&$notifyFuncRef($self);
	}
	
	if (!defined $dontcallExecuteCallback) {
		my @params = $self->renderAsArray();
		Slim::Control::Command::executeCallback(
			$self->client(),
			\@params,
			"not again"
			);
	}
}

################################################################################
# Legacy
################################################################################
# support for legacy applications
# returns the request as an array
sub renderAsArray {
	my $self = shift;
	my $encoding = shift;
	
	my @returnArray;
	
	# conventions: 
	# -- parameter or result with key starting with "_": value outputted
	# -- parameter or result with key starting with "__": no output TODO
	# -- result starting with "@": is a loop
	# -- anything else: output "key:value"
	
	# push the request terms
	push @returnArray, @{$self->{'_request'}};
	
	# push the parameters
	while (my ($key, $val) = each %{$self->{'_params'}}) {

		$val = Encode::encode($encoding, $val) if $encoding && $] > 5.007;

		if ($key =~ /^__/) {
			# no output
		} elsif ($key =~ /^_/) {
			push @returnArray, $val;
		} else {
			push @returnArray, ($key . ":" . $val);
		}
 	}
 	
 	# push the results
	while (my ($key, $val) = each %{$self->{'_results'}}) {

		$val = Encode::encode($encoding, $val) if $encoding && $] > 5.007;

		if ($key =~ /^@/) {

			# loop over each elements
			foreach my $hash (@{${$self->{'_results'}}{$key}}) {

				while (my ($key2, $val2) = each %{$hash}) {

					$val2 = Encode::encode($encoding, $val2) 
						if $encoding && $] > 5.007;

					if ($key2 =~ /^__/) {
						# no output
					} elsif ($key2 =~ /^_/) {
						push @returnArray, $val2;
					} else {
						push @returnArray, ($key2 . ':' . $val2);
					}
				}	
			}

		} elsif ($key =~ /^__/) {
			# no output
		} elsif ($key =~ /^_/) {
			push @returnArray, $val;
		} else {
			push @returnArray, ($key . ':' . $val);
		}
 	}
	
	return @returnArray;
}

################################################################################
# Utility function to dump state of the request object to stdout
################################################################################
sub dump {
	my $self = shift;
	my $introText = shift || '?';
	
	my $str = $introText . ": ";
	
	if ($self->query()) {
		$str .= 'Query ';
	} else {
		$str .= 'Command ';
	}
	
	if (my $client = $self->client()) {
		my $clientid = $client->id();
		$str .= "[$clientid->" . $self->getRequestString() . "]";
	} else {
		$str .= "[" . $self->getRequestString() . "]";
	}

	if ($self->callbackFunction()) {

		if ($self->callbackEnabled()) {
			$str .= " cb+ ";
		} else {
			$str .= " cb- ";
		}
	}

	$str .= ' (' . $statusMap{$self->__status()} . ")\n";
		
	msg($str);

	while (my ($key, $val) = each %{$self->{'_params'}}) {

    		msg("   Param: [$key] = [$val]\n");
 	}
 	
	while (my ($key, $val) = each %{$self->{'_results'}}) {
    	
		if ($key =~ /^@/) {

			my $count = scalar @{${$self->{'_results'}}{$key}};

			msg("   Result: [$key] is loop with $count elements:\n");
			
			# loop over each elements
			for (my $i = 0; $i < $count; $i++) {

				my $hash = ${$self->{'_results'}}{$key}->[$i];

				while (my ($key2, $val2) = each %{$hash}) {
					msg("   Result:   $i. [$key2] = [$val2]\n");
				}	
			}

		} else {
			msg("   Result: [$key] = [$val]\n");
		}
 	}
}

################################################################################
# Private methods
################################################################################
sub __isCmdQuery {
	my $self = shift;
	my $isQuery = shift;
	my $possibleNames = shift;
	
	# the query state must match
	if ($isQuery == $self->{'_isQuery'}) {
	
		my $possibleNamesCount = scalar (@{$possibleNames});

		# we must have the same number (or more) of request terms
		# than of passed names
		if ((scalar(@{$self->{'_request'}})) >= $possibleNamesCount) {

			# check each request term matches one of the passed params
			for (my $i = 0; $i < $possibleNamesCount; $i++) {
				
				my $name = $self->{'_request'}->[$i];;

				# return as soon we fail
				return 0 if !grep(/$name/, @{$possibleNames->[$i]});
			}
			
			# everything matched
			return 1;
		}
	}
	return 0;
}

# sets/returns the status state of the request
sub __status {
	my $self = shift;
	my $status = shift;
	
	$self->{'_status'} = $status if defined $status;
	
	return $self->{'_status'};
}

# returns a string corresponding to the notification filter, used for 
# debugging
sub __filterString {
	my $requestsRef = shift;
	
	return "(no filter)" if !defined $requestsRef;
	
	my $str = "[";

	foreach my $req (@$requestsRef) {
		$str .= "[";
		my @list = map { "\'$_\'" } @$req;
		$str .= join(",", @list);
		$str .= "]";
	}
		
	$str .= "]";
}

# given a command or query in an array, walk down the dispatch DB to find
# the function to call for it. Used by the Request constructor
sub __parse {
	my $self           = shift;
	my $requestLineRef = shift;     # reference to an array containing the 
									# query verbs
		
#	$::d_command && msg("Request: parse(" 
#						. (join " ", @{$requestLineRef}) . ")\n");

	my $debug = 0;					# debug flag internal to the function


	my $found;						# have we found the right command
	my $outofverbs;					# signals we're out of verbs to try and match
	my $LRindex    = 0;				# index into $requestLineRef
	my $done       = 0;				# are we done yet?
	my $DBp        = \%dispatchDB;	# pointer in the dispatch table
	my $match      = $requestLineRef->[$LRindex];
									# verb of the command we're trying to match

	while (!$done) {
	
		# we're out of verbs to check for a match -> try with ''
		if (!defined $match) {

			$match = '';
			$outofverbs = 1;
		}

		$debug && msg("..Trying to match [$match]\n");
		$debug && print Data::Dumper::Dumper($DBp);

		# our verb does not match in the hash 
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
							$self->addParam($key, $match);
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
				$self->addRequest($match);
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
				$self->addRequest($match);
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

				$self->addParam($1, $2);

			} else {
			
				# default to positional param...
				$self->addParamPos($requestLineRef->[$i]);
			}
		}

		$self->{'_needClient'} = $found->[0];
		$self->{'_isQuery'} = $found->[1];
		$self->{'_func'} = $found->[3];
				
	} else {

		$::d_command && msg("Request [" . (join " ", @{$requestLineRef}) . "]: no match in dispatchDB!\n");

		# handle the remaining params, if any...
		# only for the benefit of CLI echoing...
		for (my $i=$LRindex; $i < scalar @{$requestLineRef}; $i++) {
			$self->addParamPos($requestLineRef->[$i]);
		}
	}
	
	$self->validate();
}



1;

__END__
