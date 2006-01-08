package Slim::Control::Dispatch;

# SlimServer Copyright (C) 2001-2006 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use Slim::Control::Commands;
use Slim::Control::Queries;
use Slim::Control::Request;
use Slim::Utils::Misc qw(msg bt);

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



our %subscribers = ();   		# contains the clients to the notification
								# mechanism
								
our %dispatchDB;				# contains a multi-level hash pointing to
								# each command or query subroutine


# adds standard commands and queries to the dispatch hashes...
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


# parse the first array in parameter to create a multi level hash providing
# fast access to 2nd array data, i.e. (the example is incomplete!)
# { 
#  'rescan' => {
#               '?'          => [2nd param array of 1st array ['rescan', '?']]
#               '_playlists' => [2nd param array of 1st array ['rescan', '_playlists']]
#              },
#  'info'   => {
#               'total'      => {
#                                'albums'  => [$arrayDataRef of ['info', 'total', albums']]
# ...
#
# this is used by init() above to add the standard commands and queries to the 
# table and by the plugin glue code to add plugin-specific and plugin-defined
# commands and queries to the system.
# Note that for the moment, there is no identified need to ever REMOVE commands
# from the dispatch table (and consequently no defined function for that).
sub addDispatch {
	my $arrayCmdRef  = shift; # the array containing the command or query
	my $arrayDataRef = shift; # the array containing the function to call

#	$::d_command && msg("Dispatch: addDispatch()\n");

	my $DBp     = \%dispatchDB;	    # pointer to the current table level
	my $CRindex = 0;                # current index into $arrayCmdRef
	my $done    = 0;                # are we done
	
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

# given a command or query in an array, walk down the dispatch table to find
# the function to call for it. Create a complete request object in the process
# and return it to the caller, ready for execution.
sub requestFromArray {
	my $client         = shift;     # client, if any, to which the query applies
	my $requestLineRef = shift;     # reference to an array containing the 
									# query verbs
		
	$::d_command && msg("Dispatch: requestFromArray(" 
						. (join " ", @{$requestLineRef}) . ")\n");

	my $debug = 0;					# debug flag internal to the function


	my $found;						# have we found the right command
	my $outofverbs;					# signals we're out of verbs to try and match
	my $LRindex    = 0;				# index into $requestLineRef
	my $done       = 0;				# are we done yet?
	my $DBp        = \%dispatchDB;	# pointer in the dispatch table
	my $match      = $requestLineRef->[$LRindex];
									# verb of the command we're trying to match

	
	# create the request with what we have so far (the client)
	my $request = new Slim::Control::Request($client);
	
	
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

		$request->needClient($found->[0]);
		$request->query($found->[1]);
		$request->executeFunction($found->[3]);
				
	} else {

		$::d_command && msg("Dispatch::requestFromArray: Request [" . (join " ", @{$requestLineRef}) . "]: no match in dispatchDB!\n");

		# handle the remaining params, if any...
		# only for the benefit of CLI echoing...
		for (my $i=$LRindex; $i < scalar @{$requestLineRef}; $i++) {
			$request->addParamPos($requestLineRef->[$i]);
		}
	}
	
	$request->validate();

	return $request;
}

################################################################################
# NOTIFICATIONS
################################################################################
# The dispatch mechanism can notify "subscriber" functions of successful
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
# Slim::Control::Dispatch::subscribe( \&myCallbackFunction, 
#                                     [['playlist']]);
# -> myCallbackFunction will be called for any command starting with 'playlist'
# in the table above ('playlist save', playlist loadtracks', etc).
#
# Slim::Control::Dispatch::subscribe( \&myCallbackFunction, 
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
################################################################################

# add a subscriber to be notified of requests
sub subscribe {
	my $subscriberFuncRef = shift || return;
	my $requestsRef = shift;
	
	$subscribers{$subscriberFuncRef} = [$subscriberFuncRef, $requestsRef];
	
	$::d_command && msg("Dispatch: subscribe($subscriberFuncRef) - ("
		. scalar(keys %subscribers) . " suscribers)\n");
}

# remove a subscriber
sub unsubscribe {
	my $subscriberFuncRef = shift;
	
	delete $subscribers{$subscriberFuncRef};
	
	$::d_command && msg("Dispatch: unsubscribe($subscriberFuncRef) - (" 
		. scalar(keys %subscribers) . " suscribers)\n");
}

# notify subscribers...
sub notify {
	my $request = shift || return;

	for my $subscriber (keys %subscribers) {

		# filter based on desired requests
		# undef means no filter
		my $requestsRef = $subscribers{$subscriber}->[1];
		
		if (defined($requestsRef)) {

			if ($request->isNotCommand($requestsRef)) {

				$::d_command && msg("Dispatch: Don't notify $subscriber of "
					. $request->getRequestString() . " !~ "
					. filterString($requestsRef) . "\n");

				next;
			}
		}

		$::d_command && msg("Dispatch: Notifying $subscriber of " 
			. $request->getRequestString() . " =~ "
			. filterString($requestsRef) . "\n");
		
		my $notifyFuncRef = $subscribers{$subscriber}->[0];
		&$notifyFuncRef($request);
	}
}

# notify subscribers from an array, useful for notifying w/o execution
# (requests must, however, be defined in the dispatch table)
sub notifyFromArray {
	my $client         = shift;     # client, if any, to which the query applies
	my $requestLineRef = shift;     # reference to an array containing the 
									# query verbs

	$::d_command && msg("Dispatch: notifyFromArray(" .
						(join " ", @{$requestLineRef}) . ")\n");

	my $request = requestFromArray($client, $requestLineRef);
	
	notify($request);
}

# returns a string corresponding to the filter, useful for debugging
sub filterString {
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

1;
