package Slim::Control::Request;

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.


use strict;

use Tie::LLHash;

use Slim::Utils::Misc;

# This class implements a generic request, that will be dispatched to the
# correct function by Slim::Control::Dispatch code.

our %subscribers = ();          # contains the clients to the notification
                                # mechanism

our @notificationQueue;         # contains the Requests waiting to be notified

my $callExecuteCallback = 0;    # flag to know if we must call the legacy
                                # Slim::Control::Command::executeCallback

my $d_notify = 1;               # local debug flag for notifications. Note that
                                # $::d_command must be enabled as well.

our $requestTask = Slim::Utils::PerfMon->new('Request Task', [0.002, 0.005, 0.010, 0.015, 0.025, 0.050, 0.1, 0.5, 1, 5]);

################################################################################
# Package methods
################################################################################
# These function are really package functions, i.e. to be called like
#  Slim::Control::Request::subscribe() ...

# adds standard commands and queries to the dispatch DB...
sub init {

	# Allow deparsing of code ref function names.
	if ($::d_command && $d_notify) {
		require Slim::Utils::PerlRunTime;
	}

######################################################################################################################################################################
#                                                                                                     |requires Client
#                                                                                                     |  |is a Query
#                                                                                                     |  |  |has Tags
#                                                                                                     |  |  |  |Function to call
#                 P0               P1              P2            P3             P4         P5         C  Q  T  F
######################################################################################################################################################################

    addDispatch(['alarm'],                                                                           [1, 0, 1, \&Slim::Control::Commands::alarmCommand]);
    addDispatch(['alarms',         '_index',      '_quantity'],                                      [1, 1, 1, \&Slim::Control::Queries::alarmsQuery]);
    addDispatch(['album',          '?'],                                                             [1, 1, 0, \&Slim::Control::Queries::cursonginfoQuery]);
    addDispatch(['albums',         '_index',      '_quantity'],                                      [0, 1, 1, \&Slim::Control::Queries::browseXQuery]);
    addDispatch(['artist',         '?'],                                                             [1, 1, 0, \&Slim::Control::Queries::cursonginfoQuery]);
    addDispatch(['artists',        '_index',      '_quantity'],                                      [0, 1, 1, \&Slim::Control::Queries::browseXQuery]);
    addDispatch(['button',         '_buttoncode',  '_time',      '_orFunction'],                     [1, 0, 0, \&Slim::Control::Commands::buttonCommand]);
    addDispatch(['client',         'forget'],                                                        [1, 0, 0, \&Slim::Control::Commands::clientForgetCommand]);
    addDispatch(['connected',      '?'],                                                             [1, 1, 0, \&Slim::Control::Queries::connectedQuery]);
    addDispatch(['current_title',  '?'],                                                             [1, 1, 0, \&Slim::Control::Queries::cursonginfoQuery]);
    addDispatch(['debug',          '_debugflag',   '?'],                                             [0, 1, 0, \&Slim::Control::Queries::debugQuery]);
    addDispatch(['debug',          '_debugflag',   '_newvalue'],                                     [0, 0, 0, \&Slim::Control::Commands::debugCommand]);
    addDispatch(['display',        '?',            '?'],                                             [1, 1, 0, \&Slim::Control::Queries::displayQuery]);
    addDispatch(['display',        '_line1',       '_line2',     '_duration'],                       [1, 0, 0, \&Slim::Control::Commands::displayCommand]);
    addDispatch(['displaynow',     '?',            '?'],                                             [1, 1, 0, \&Slim::Control::Queries::displaynowQuery]);
    addDispatch(['duration',       '?'],                                                             [1, 1, 0, \&Slim::Control::Queries::cursonginfoQuery]);
    addDispatch(['genre',          '?'],                                                             [1, 1, 0, \&Slim::Control::Queries::cursonginfoQuery]);
    addDispatch(['genres',         '_index',      '_quantity'],                                      [0, 1, 1, \&Slim::Control::Queries::browseXQuery]);
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
    addDispatch(['playlist',       'remote',       '_index',     '?'],                               [1, 1, 0, \&Slim::Control::Queries::playlistXQuery]);
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
    addDispatch(['playlisttracks', '_index',       '_quantity'],                                     [0, 1, 1, \&Slim::Control::Queries::playlisttracksQuery]);
    addDispatch(['playlists',      '_index',       '_quantity'],                                     [0, 1, 1, \&Slim::Control::Queries::playlistsQuery]);
    addDispatch(['playlistcontrol'],                                                                 [1, 0, 1, \&Slim::Control::Commands::playlistcontrolCommand]);
    addDispatch(['power',          '?'],                                                             [1, 1, 0, \&Slim::Control::Queries::powerQuery]);
    addDispatch(['power',          '_newvalue'],                                                     [1, 0, 0, \&Slim::Control::Commands::powerCommand]);
    addDispatch(['pref',           '_prefname',    '?'],                                             [0, 1, 0, \&Slim::Control::Queries::prefQuery]);
    addDispatch(['pref',           '_prefname',    '_newvalue'],                                     [0, 0, 0, \&Slim::Control::Commands::prefCommand]);
    addDispatch(['rate',           '?'],                                                             [1, 1, 0, \&Slim::Control::Queries::rateQuery]);
    addDispatch(['rate',           '_newvalue'],                                                     [1, 0, 0, \&Slim::Control::Commands::rateCommand]);
    addDispatch(['remote',         '?'],                                                             [1, 1, 0, \&Slim::Control::Queries::cursonginfoQuery]);
    addDispatch(['rescan',         '?'],                                                             [0, 1, 0, \&Slim::Control::Queries::rescanQuery]);
    addDispatch(['rescan',         '_playlists'],                                                    [0, 0, 0, \&Slim::Control::Commands::rescanCommand]);
    addDispatch(['search',         '_index',       '_quantity'],                                     [0, 1, 1, \&Slim::Control::Queries::searchQuery]);
    addDispatch(['show'],                                                                            [1, 0, 1, \&Slim::Control::Commands::showCommand]);
    addDispatch(['signalstrength', '?'],                                                             [1, 1, 0, \&Slim::Control::Queries::signalstrengthQuery]);
    addDispatch(['sleep',          '?'],                                                             [1, 1, 0, \&Slim::Control::Queries::sleepQuery]);
    addDispatch(['sleep',          '_newvalue'],                                                     [1, 0, 0, \&Slim::Control::Commands::sleepCommand]);
    addDispatch(['songinfo',       '_index',       '_quantity'],                                     [0, 1, 1, \&Slim::Control::Queries::songinfoQuery]);
    addDispatch(['songs',          '_index',       '_quantity'],                                     [0, 1, 1, \&Slim::Control::Queries::titlesQuery]);
    addDispatch(['status',         '_index',       '_quantity'],                                     [1, 1, 1, \&Slim::Control::Queries::statusQuery]);
    addDispatch(['stop'],                                                                            [1, 0, 0, \&Slim::Control::Commands::playcontrolCommand]);
    addDispatch(['stopserver'],                                                                      [0, 0, 0, \&main::stopServer]);
    addDispatch(['sync',           '?'],                                                             [1, 1, 0, \&Slim::Control::Queries::syncQuery]);
    addDispatch(['sync',           '_indexid-'],                                                     [1, 0, 0, \&Slim::Control::Commands::syncCommand]);
    addDispatch(['time',           '?'],                                                             [1, 1, 0, \&Slim::Control::Queries::timeQuery]);
    addDispatch(['time',           '_newvalue'],                                                     [1, 0, 0, \&Slim::Control::Commands::timeCommand]);
    addDispatch(['title',          '?'],                                                             [1, 1, 0, \&Slim::Control::Queries::cursonginfoQuery]);
    addDispatch(['titles',         '_index',       '_quantity'],                                     [0, 1, 1, \&Slim::Control::Queries::titlesQuery]);
    addDispatch(['tracks',         '_index',       '_quantity'],                                     [0, 1, 1, \&Slim::Control::Queries::titlesQuery]);
    addDispatch(['version',        '?'],                                                             [0, 1, 0, \&Slim::Control::Queries::versionQuery]);
    addDispatch(['wipecache'],                                                                       [0, 0, 0, \&Slim::Control::Commands::wipecacheCommand]);

# NOTIFICATIONS
    addDispatch(['client',         'disconnect'],                                                    [1, 0, 0, undef]);
    addDispatch(['client',         'new'],                                                           [1, 0, 0, undef]);
    addDispatch(['client',         'reconnect'],                                                     [1, 0, 0, undef]);
    addDispatch(['playlist',       'load_done'],                                                     [1, 0, 0, undef]);
    addDispatch(['playlist',       'newsong'],                                                       [1, 0, 0, undef]);
    addDispatch(['playlist',       'open',         '_path'],                                         [1, 0, 0, undef]);
    addDispatch(['playlist',       'sync'],                                                          [1, 0, 0, undef]);
    addDispatch(['playlist',       'cant_open',    '_url'],                                          [1, 0, 0, undef]);
    addDispatch(['rescan',         'done'],                                                          [0, 0, 0, undef]);
    addDispatch(['unknownir',      '_ircode',      '_time'],                                         [1, 0, 0, undef]);

# DEPRECATED
	addDispatch(['mode',           'pause'],                                                         [1, 0, 0, \&Slim::Control::Commands::playcontrolCommand]);
    addDispatch(['mode',           'play'],                                                          [1, 0, 0, \&Slim::Control::Commands::playcontrolCommand]);
    addDispatch(['mode',           'stop'],                                                          [1, 0, 0, \&Slim::Control::Commands::playcontrolCommand]);
	# use commands "pause", "play" and "stop"
    
    addDispatch(['gototime',       '?'],                                                             [1, 1, 0, \&Slim::Control::Queries::timeQuery]);
    addDispatch(['gototime',       '_newvalue'],                                                     [1, 0, 0, \&Slim::Control::Commands::timeCommand]);
	# use command "time"

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
	
	$::d_command && $d_notify && msgf(
		"Request: subscribe(%s) - (%d subscribers)\n",
		Slim::Utils::PerlRunTime::realNameForCodeRef($subscriberFuncRef),
		scalar(keys %subscribers)
	);
}

# remove a subscriber
sub unsubscribe {
	my $subscriberFuncRef = shift;
	
	delete $subscribers{$subscriberFuncRef};

	$::d_command && $d_notify && msgf(
		"Request: unsubscribe(%s) - (%d subscribers)\n",
		Slim::Utils::PerlRunTime::realNameForCodeRef($subscriberFuncRef),
		scalar(keys %subscribers)
	);
}

# notify subscribers from an array, useful for notifying w/o execution
# (requests must, however, be defined in the dispatch table)
sub notifyFromArray {
	my $client         = shift;     # client, if any, to which the query applies
	my $requestLineRef = shift;     # reference to an array containing the 
									# query verbs

	$::d_command && $d_notify && msg("Request: notifyFromArray(" .
						(join " ", @{$requestLineRef}) . ")\n");

	my $request = Slim::Control::Request->new(
									(blessed($client) ? $client->id() : undef), 
									$requestLineRef
								);
	
	push @notificationQueue, $request;
}

# sends notifications for first entry in queue - called once per idle loop
sub checkNotifications {
	
	return 0 if (!scalar @notificationQueue);

	# notify first entry on queue
	my $request = shift @notificationQueue;
	$request->notify() if blessed($request);

	return 1;
}

# convenient function to execute a request from an array, with optional
# callback parameters. Returns the Request object.
sub executeRequest {
	my($client, $parrayref, $callbackf, $callbackargs) = @_;

	# create a request from the array
	my $request = Slim::Control::Request->new( 
		(blessed($client) ? $client->id() : undef), 
		$parrayref
	);
	
	if (defined $request && $request->isStatusDispatchable()) {
		
		# add callback params
		$request->callbackParameters($callbackf, $callbackargs);
		
		$request->execute();
	}

	return $request;
}

################################################################################
# Constructors
################################################################################

sub new {
	my $class = shift;
	my $request = shift || return;
	my $isQuery = shift;
	my $client = shift;
	
	tie (my %paramHash, "Tie::LLHash", {lazy => 1});
	tie (my %resultHash, "Tie::LLHash", {lazy => 1});
	
	my $self = {
		'_request' => $request,
		'_isQuery' => $isQuery,
		'_client' => $client,
		'_params' => \%paramHash,
		'_curparam' => 1,
		'_status' => 0,
		'_results' => \%resultHash,
	};
	# MISSING SOURCE, CALLBACK
	
	bless $self, $class;
	
	return $self;
}

sub dump {
	my $self = shift;
	
	my $str = "Request: Dumping ";
	
	if ($self->query()) {
		$str .= 'query ';
	} else {
		$str .= 'command ';
	}
	
	if (my $client = $self->client()){
		my $clientid = $client->id();
		$str .= "[$clientid->" . $self->getRequest() . "]";
	} else {
		$str .= "[" . $self->getRequest() . "]";
	}
	
	if ($self->isStatusNew()) {
		$str .= " (New)\n";
	} elsif ($self->isStatusDispatched()) {
		$str .= " (Dispatched)\n";
	} elsif ($self->isStatusDone()) {
		$str .= " (Done)\n";
	} elsif ($self->isStatusBadDispatch()) {
		$str .= " (Bad Dispatch)\n";
	} elsif ($self->isStatusBadParams()) {
		$str .= " (Bad Params)\n";
	}
	
	msg($str);

	while (my ($key, $val) = each %{$self->{'_params'}}) {
    	msg("   Param: [$key] = [$val]\n");
 	}
 	
	while (my ($key, $val) = each %{$self->{'_results'}}) {
    	msg("   Result: [$key] = [$val]\n");
 	}
}

################################################################################
# Read/Write basic query attributes
################################################################################

# returns the request name. Read-only
sub getRequest {
	my $self = shift;
	
	return $self->{_request};
}

# sets/returns the query state of the request
sub query {
	my $self = shift;
	my $isQuery = shift;
	
	$self->{'_isQuery'} = $isQuery if defined $isQuery;
	
	return $self->{'_isQuery'};
}

# sets/returns the client, if any, that applies to the request
sub client {
	my $self = shift;
	my $client = shift;
	
	$self->{'_client'} = $client if defined $client;
	
	return $self->{'_client'};
}

################################################################################
# Read/Write status
################################################################################
# 0 new
# 1 dispatched
# 10 done
# 101 bad dispatch
# 102 bad params

sub isStatusNew {
	my $self = shift;
	return ($self->__status() == 0);
}

sub setStatusDispatched {
	my $self = shift;
	$self->__status(1);
}
sub isStatusDispatched {
	my $self = shift;
	return ($self->__status() == 1);
}
sub wasStatusDispatched {
	my $self = shift;
	return ($self->__status() > 0);
}

sub setStatusDone {
	my $self = shift;
	$self->__status(10);
}
sub isStatusDone {
	my $self = shift;
	return ($self->__status() == 10);
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




################################################################################
# Compound requests
################################################################################

# accepts a reference to an array containing synonyms for the query name
# and returns 1 if no name match the request. Used by functions implementing
# queries to check the dispatcher did not send them a wrong request.
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


################################################################################
# Other
################################################################################
sub execute {
	my $self = shift;
	
	Slim::Control::Dispatch::dispatch($self);
}

sub callback {
}

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

sub addResult {
	my $self = shift;
	my $key = shift;
	my $val = shift;

	${$self->{'_results'}}{$key} = $val;
}

sub getResult {
	my $self = shift;
	my $key = shift || return;
	
	return ${$self->{'_results'}}{$key};
}

sub getArray {
	my $self = shift;
	my @returnArray;
	
	push @returnArray, $self->getRequest();
	
	while (my ($key, $val) = each %{$self->{'_params'}}) {
    	if ($key =~ /_p*/) {
    		push @returnArray, $val;
    	}
 	}
 	
 	# any client expecting something more sophisticated should not go
 	# through execute but through dispatch directly...
	while (my ($key, $val) = each %{$self->{'_results'}}) {
    	push @returnArray, $val;
 	}
	
	return @returnArray;
}

################################################################################
# Private methods
################################################################################
sub __isCmdQuery {
	my $self = shift;
	my $isQuery = shift;
	my $possibleNames = shift;
	
	if ($isQuery == $self->query()){
		my $name = $self->getRequest();
		my $result = grep(/$name/, @{$possibleNames});
		return $result;
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




1;