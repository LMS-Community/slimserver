package Slim::Player::StreamingController;

# $Id$

# SqueezeCenter Copyright 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use bytes;
use strict;
use warnings;

use Scalar::Util qw(blessed weaken);
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;
use Slim::Player::Song;
use Slim::Player::ReplayGain;

my $log = logger('player.source');

my $prefs = preferences('server');

# Streaming state
use constant IDLE      => 0;
use constant STREAMING => 1;
use constant STREAMOUT => 2;
use constant TRACKWAIT => 3;	# Waiting for next track info to be ready and all players ready-to-stream
my $i = 0;
my @StreamingStateName = ('IDLE', 'STREAMING', 'STREAMOUT', 'TRACKWAIT');
my %StreamingStateNameMap = map { $_ => $i++ } @StreamingStateName;

# Playing state (audio)
use constant STOPPED         => 0;
use constant BUFFERING       => 1;
use constant WAITING_TO_SYNC => 2;
use constant PLAYING         => 3;
use constant PAUSED          => 4;
$i = 0;
my @PlayingStateName = ('STOPPED', 'BUFFERING', 'WAITING_TO_SYNC', 'PLAYING', 'PAUSED');
my %PlayingStateNameMap = map { $_ => $i++ } @PlayingStateName;

use constant FADEVOLUME       => 0.3125;

sub new {
	my ($class, $client) = @_;

	my $self = {
		masterId             => $client->id(),
		players              => [],
		allPlayers           => [$client],

		# State
		streamingState       => IDLE,
		playingState         => STOPPED,
		rebuffering          => 0,
		lastStateChange      => 0,
		
		# Streaming control
		songqueue            => [],
		songStreamController => undef,
		nextCheckSyncTime    => 0,
		
		# Sync management
		frameData            => undef,              # array of (stream-byte-offset, stream-time-offset) tuples
		initialStreamBuffer  => undef,              # cache of initially-streamed data to calculate rate
		
		# Track management
		nextTrack            => undef,			    # a Song
		nextTrackCallbackId  => 0,
		consecutiveErrors    => 0,
	};
	
	if ($client->power) {
		push @{$self->{'players'}}, $client;
		weaken( $self->{players}->[0] );
	}
	
	weaken( $self->{allPlayers}->[0] );
	
	bless $self, $class;
	
	return $self;
}

# What we have here is a state table with a number of handlers, one named handler
# to cover each precondition/action/end-state combination. The handler functions
# are after the table.
#
# I am not convinced that the table is either the most efficient
# implementation of this state machine, nor the the most comprehensible.
# An alternate approach would be to evaluate the constriants and execute the
# actions & state-changes directly from the inbound-event functions. Whether it
# makes sense to change to this remains to be seen. But for the moment, use of
# the jump table gives more opportunities to find and fix unanticipated event-state
# combinations.

my @ValidStates = (
#	IDLE		STREAMING	STREAMOUT	TRACKWAIT
[	1,			0,			0,			1],		# STOPPED	
[	0,			1,			1,			0],		# BUFFERING
[	0,			1,			1,			0],		# WAITING_TO_SYNC
[	1,			1,			1,			1],		# PLAYING
[	1,			1,			1,			1],		# PAUSED
);

my %stateTable = (	# stateTable[event][playState][streamingState]
#		IDLE			STREAMING		STREAMOUT		TRACKWAIT
Stop =>
[	[	\&_NoOp,		\&_BadState,	\&_BadState,	\&_Stop],			# STOPPED	
	[	\&_BadState,	\&_Stop,		\&_Stop,		\&_BadState],		# BUFFERING
	[	\&_BadState,	\&_Stop,		\&_Stop,		\&_BadState],		# WAITING_TO_SYNC
	[	\&_Stop,		\&_Stop,		\&_Stop,		\&_Stop],			# PLAYING
	[	\&_Stop,		\&_Stop,		\&_Stop,		\&_Stop],			# PAUSED
],
Play =>
[	[	\&_StopGetNext,	\&_BadState,	\&_BadState,	\&_StopGetNext],	# STOPPED	
	[	\&_BadState,	\&_StopGetNext,	\&_StopGetNext,	\&_BadState],		# BUFFERING
	[	\&_BadState,	\&_StopGetNext,	\&_StopGetNext,	\&_BadState],		# WAITING_TO_SYNC
	[	\&_StopGetNext,	\&_StopGetNext,	\&_StopGetNext,	\&_StopGetNext],	# PLAYING
	[	\&_StopGetNext,	\&_StopGetNext,	\&_StopGetNext,	\&_StopGetNext],	# PAUSED
],
ContinuePlay =>
[	[	\&_Stop,		\&_BadState,	\&_BadState,	\&_StopGetNext],	# STOPPED	
	[	\&_BadState,	\&_StopGetNext,	\&_StopGetNext,	\&_BadState],		# BUFFERING
	[	\&_BadState,	\&_StopGetNext,	\&_StopGetNext,	\&_BadState],		# WAITING_TO_SYNC
	[	\&_Continue,	\&_Continue,	\&_Continue,	\&_Continue],		# PLAYING
	[	\&_Stop,		\&_Stop,		\&_Stop,		\&_Stop],			# PAUSED
],
Pause =>
[	[	\&_Invalid,		\&_BadState,	\&_BadState,	\&_NoOp],			# STOPPED	
	[	\&_BadState,	\&_NoOp,		\&_NoOp,		\&_BadState],		# BUFFERING
	[	\&_BadState,	\&_NoOp,		\&_NoOp,		\&_BadState],		# WAITING_TO_SYNC
	[	\&_Pause,		\&_Pause,		\&_Pause,		\&_Pause],			# PLAYING
	[	\&_Resume,		\&_Resume,		\&_Resume,		\&_Resume],			# PAUSED
],
Resume =>
[	[	\&_Invalid,		\&_BadState,	\&_BadState,	\&_Invalid],		# STOPPED	
	[	\&_BadState,	\&_Invalid,		\&_Invalid,		\&_BadState],		# BUFFERING
	[	\&_BadState,	\&_Invalid,		\&_Invalid,		\&_BadState],		# WAITING_TO_SYNC
	[	\&_Invalid,		\&_Invalid,		\&_Invalid,		\&_Invalid],		# PLAYING
	[	\&_Resume,		\&_Resume,		\&_Resume,		\&_Resume],			# PAUSED
],
Flush =>
[	[	\&_Invalid,		\&_BadState,	\&_BadState,	\&_Invalid],		# STOPPED	
	[	\&_BadState,	\&_Invalid,		\&_Invalid,		\&_BadState],		# BUFFERING
	[	\&_BadState,	\&_Invalid,		\&_Invalid,		\&_BadState],		# WAITING_TO_SYNC
	[	\&_Invalid,		\&_FlushGetNext,\&_FlushGetNext,\&_Invalid],		# PLAYING
	[	\&_Invalid,		\&_FlushGetNext,\&_FlushGetNext,\&_Invalid],		# PAUSED
],
Skip  => 
[	[	\&_StopGetNext,	\&_BadState,	\&_BadState,	\&_NoOp],			# STOPPED	
	[	\&_BadState,	\&_Skip,		\&_Skip,		\&_BadState],		# BUFFERING
	[	\&_BadState,	\&_Skip,		\&_Skip,		\&_BadState],		# WAITING_TO_SYNC
	[	\&_StopGetNext,	\&_Skip,		\&_Skip,		\&_Skip],			# PLAYING
	[	\&_StopGetNext,	\&_Skip,		\&_Skip,		\&_Skip],			# PAUSED
],
JumpToTime =>
[	[	\&_Invalid,		\&_BadState,	\&_BadState,	\&_Invalid],		# STOPPED	
	[	\&_BadState,	\&_JumpToTime,	\&_JumpToTime,	\&_BadState],		# BUFFERING
	[	\&_BadState,	\&_JumpToTime,	\&_JumpToTime,	\&_BadState],		# WAITING_TO_SYNC
	[	\&_JumpToTime,	\&_JumpToTime,	\&_JumpToTime,	\&_JumpToTime],		# PLAYING
	[	\&_JumpToTime,	\&_JumpToTime,	\&_JumpToTime,	\&_JumpToTime],		# PAUSED
],

NextTrackReady =>
[	[	\&_NoOp,		\&_BadState,	\&_BadState,	\&_Stream],			# STOPPED	
	[	\&_BadState,	\&_Invalid,		\&_Invalid,		\&_BadState],		# BUFFERING
	[	\&_BadState,	\&_Invalid,		\&_Invalid,		\&_BadState],		# WAITING_TO_SYNC
	[	\&_Invalid,		\&_Invalid,		\&_Invalid,		\&_StreamIfReady],	# PLAYING
	[	\&_Invalid,		\&_Invalid,		\&_Invalid,		\&_StreamIfReady],	# PAUSED
],
NextTrackError =>
[	[	\&_Invalid,		\&_BadState,	\&_BadState,	\&_NextIfMore],		# STOPPED	
	[	\&_BadState,	\&_Invalid,		\&_Invalid,		\&_BadState],		# BUFFERING
	[	\&_BadState,	\&_Invalid,		\&_Invalid,		\&_BadState],		# WAITING_TO_SYNC
	[	\&_Invalid,		\&_Invalid,		\&_Invalid,		\&_NextIfMore],		# PLAYING
	[	\&_Invalid,		\&_Invalid,		\&_Invalid,		\&_NextIfMore],		# PAUSED
],
LocalEndOfStream =>
[	[	\&_Invalid,		\&_BadState,	\&_BadState,	\&_Invalid],		# STOPPED	
	[	\&_BadState,	\&_Streamout,	\&_Invalid,		\&_BadState],		# BUFFERING
	[	\&_BadState,	\&_Streamout,	\&_Invalid,		\&_BadState],		# WAITING_TO_SYNC
	[	\&_Invalid,		\&_Streamout,	\&_Invalid,		\&_Invalid],		# PLAYING
	[	\&_Invalid,		\&_Streamout,	\&_Invalid,		\&_Invalid],		# PAUSED
],

BufferReady =>
[	[	\&_Invalid,		\&_BadState,	\&_BadState,	\&_Invalid],		# STOPPED	
	[	\&_BadState,	\&_WaitToSync,	\&_WaitToSync,	\&_BadState],		# BUFFERING
	[	\&_BadState,	\&_StartIfReady,\&_StartIfReady,\&_BadState],		# WAITING_TO_SYNC
	[	\&_Invalid,		\&_Invalid,		\&_Invalid,		\&_Invalid],		# PLAYING
	[	\&_Invalid,		\&_Invalid,		\&_Invalid,		\&_Invalid],		# PAUSED
],
Started =>
[	[	\&_Invalid,		\&_BadState,	\&_BadState,	\&_Invalid],		# STOPPED	
	[	\&_BadState,	\&_Playing,		\&_Playing,		\&_BadState],		# BUFFERING
	[	\&_BadState,	\&_Invalid,		\&_Invalid,		\&_BadState],		# WAITING_TO_SYNC
	[	\&_Playing,		\&_Playing,		\&_Playing,		\&_PlayAndStream],	# PLAYING
	[	\&_Invalid,		\&_Playing,		\&_Playing,		\&_PlayAndStream],	# PAUSED
],
StreamingFailed =>
[	[	\&_Invalid,		\&_BadState,	\&_BadState,	\&_Invalid],		# STOPPED	
	[	\&_BadState,	\&_StopNextIfMore, \&_StopNextIfMore, \&_BadState],	# BUFFERING
	[	\&_BadState,	\&_StopNextIfMore, \&_StopNextIfMore, \&_BadState],	# WAITING_TO_SYNC
	[	\&_Invalid,		\&_SyncStopNext, \&_SyncStopNext, \&_Invalid],		# PLAYING
	[	\&_Invalid,		\&_Stop,		\&_Stop,		\&_Invalid],		# PAUSED
],
EndOfStream =>
[	[	\&_NoOp,		\&_BadState,	\&_BadState,	\&_NoOp],			# STOPPED	
	[	\&_BadState,	\&_StartStreamout,\&_Start,		\&_BadState],		# BUFFERING; _Start in Streamout to counter Bug 9125
	[	\&_BadState,	\&_StartStreamout,\&_Start,		\&_BadState],		# WAITING_TO_SYNC
	[	\&_Invalid,		\&_AutoStart,	\&_AutoStart,	\&_Invalid],		# PLAYING
	[	\&_Invalid,		\&_Streamout,	\&_NoOp,		\&_Invalid],		# PAUSED
],
ReadyToStream =>
[	[	\&_Invalid,		\&_BadState,	\&_BadState,	\&_Invalid],		# STOPPED	
	[	\&_BadState,	\&_NoOp,		\&_Invalid,		\&_BadState],		# BUFFERING
	[	\&_BadState,	\&_Invalid,		\&_Invalid,		\&_BadState],		# WAITING_TO_SYNC
	[	\&_NoOp,		\&_NextIfMore,	\&_NextIfMore,	\&_StreamIfReady],	# PLAYING
	[	\&_NoOp,		\&_NextIfMore,	\&_NextIfMore,	\&_StreamIfReady],	# PAUSED
],
Stopped =>
[	[	\&_Invalid,		\&_BadState,	\&_BadState,	\&_Invalid],		# STOPPED	
	[	\&_BadState,	\&_NoOp,		\&_NoOp,		\&_BadState],		# BUFFERING
	[	\&_BadState,	\&_Invalid,		\&_Invalid,		\&_BadState],		# WAITING_TO_SYNC
	[	\&_Stopped,		\&_Buffering,	\&_Buffering,	\&_PlayIfReady],	# PLAYING
	[	\&_Stopped,		\&_Buffering,	\&_Buffering,	\&_Stopped],		# PAUSED
],
OutputUnderrun =>
[	[	\&_NoOp,		\&_BadState,	\&_BadState,	\&_NoOp],			# STOPPED	
	[	\&_BadState,	\&_NoOp,		\&_NoOp,		\&_BadState],		# BUFFERING
	[	\&_BadState,	\&_Invalid,		\&_Invalid,		\&_BadState],		# WAITING_TO_SYNC
	[	\&_Invalid,		\&_Rebuffer,	\&_Rebuffer,	\&_Invalid],		# PLAYING
	[	\&_NoOp,		\&_NoOp,		\&_NoOp,		\&_NoOp],			# PAUSED
],
StatusHeartbeat =>
[	[	\&_NoOp,		\&_BadState,	\&_BadState,	\&_NoOp],			# STOPPED	
	[	\&_BadState,	\&_NoOp,		\&_NoOp,		\&_BadState],		# BUFFERING
	[	\&_BadState,	\&_StartIfReady,\&_StartIfReady,\&_BadState],		# WAITING_TO_SYNC
	[	\&_CheckSync,	\&_CheckSync,	\&_CheckSync,	\&_CheckSync],		# PLAYING
	[	\&_NoOp,		\&_NoOp,		\&_NoOp,		\&_NoOp],			# PAUSED
],
);

####################################################################
# Actions
sub _eventAction {
	my ($self, $event, $params) = @_;
	
	my $action = $stateTable{$event}[$self->{'playingState'}][$self->{'streamingState'}];

	if (!defined $action) {
		$log->error(sprintf("%s: %s in state %s-%s -> undefined",
			$self->{'masterId'},
			$event,
			$PlayingStateName[$self->{'playingState'}], $StreamingStateName[$self->{'streamingState'}]));
		return;
	}	
	
	my $curPlayingState;
	my $curStreamingState;
	
	if ($log->is_debug) {
		$curPlayingState   = $PlayingStateName[$self->{'playingState'}];
		$curStreamingState = $StreamingStateName[$self->{'streamingState'}];
		
		$log->debug(
			sprintf("%s: %s in %s-%s -> %s",
			$self->{'masterId'},
			$event,
			$curPlayingState, $curStreamingState,
			Slim::Utils::PerlRunTime::realNameForCodeRef($action))
		);
			
		if ($params) {
			my $s = "params:";
			foreach my $p (keys %$params) {
				$s .= " $p => " . (defined $params->{$p} ? $params->{$p} : 'undef');
			}
			$log->debug($s);
		}	
	}

	my $result = $action->(@_);
	
	if (!$ValidStates[$self->{'playingState'}][$self->{'streamingState'}]) {
		$log->error(sprintf("%s:  %s with action %s resulted in invalid state %s-%s",
			$self->{'masterId'},
			$event,
			Slim::Utils::PerlRunTime::realNameForCodeRef($action),
			$PlayingStateName[$self->{'playingState'}], $StreamingStateName[$self->{'streamingState'}])
		);
	}
	
	elsif ($log->is_debug) {
		my $newPlayingState   = $PlayingStateName[$self->{'playingState'}];
		my $newStreamingState =  $StreamingStateName[$self->{'streamingState'}];
		
		if ( $newPlayingState ne $curPlayingState || $newStreamingState ne $curStreamingState ) {
			$log->debug( sprintf("%s: %s - new state %s-%s",
				$self->{'masterId'},
				$event,
				$newPlayingState, $newStreamingState,
			) );
		}	
	}

	return $result;
}

sub _NoOp {}

sub _BadState {
	my ($self, $event) = @_;
	$log->error(sprintf("%s: event %s received while in invalid state %s-%s", $self->{'masterId'}, $event,
		$PlayingStateName[$self->{'playingState'}], $StreamingStateName[$self->{'streamingState'}]));
	bt() if $log->is_warn;
}

sub _Invalid {
	my ($self, $event) = @_;
	$log->warn(sprintf("%s: event %s received while in invalid state %s-%s", $self->{'masterId'}, $event,
		$PlayingStateName[$self->{'playingState'}], $StreamingStateName[$self->{'streamingState'}]));
	bt() if $log->is_warn;
}

sub _Buffering {_setPlayingState($_[0], BUFFERING);}

sub _Playing {
	my ($self) = @_;
	
	# bug 10681 - don't actually change the state if we are rebuffering
	# as there can be a race condition between output buffer underrun and
	# track-start events especially, but not exclusively when synced.
	# We still advance the track information.
	if (!$self->{'rebuffering'}) {
		_setPlayingState($self, PLAYING);
	}
	
	$self->{'consecutiveErrors'} = 0;
	
	my $queue = $self->{'songqueue'};
	my $last_song = $self->playingSong();

	while (defined($last_song) 
		&& ($last_song->{status} == Slim::Player::Song::STATUS_PLAYING 
			|| $last_song->{status} == Slim::Player::Song::STATUS_FAILED
			|| $last_song->{status} == Slim::Player::Song::STATUS_FINISHED)
		&& scalar(@$queue) > 1)
	{
		$log->info("Song " . $last_song->{'index'} . " is not longer in the queue");
		pop @{$queue};
		$last_song = $queue->[-1];
	}
	
	if (defined($last_song)) {
		$log->info("Song " . $last_song->{'index'} . " has now started playing");
		$last_song->setStatus(Slim::Player::Song::STATUS_PLAYING);
	}
	
	# Update a few timestamps
	# trackStartTime is used to signal the buffering status message to stop
	# currentPlaylistChangeTime signals the web to refresh the playlist
	my $time = Time::HiRes::time();
	$self->master()->trackStartTime( $time );
	$self->master()->currentPlaylistChangeTime( $time );

	Slim::Player::Playlist::refreshPlaylist($self->master());
	
	if ( $last_song ) {
		foreach my $player (@{$self->{'players'}})	{
			Slim::Control::Request::notifyFromArray($player,
				[
					'playlist', 
					'newsong', 
					Slim::Music::Info::standardTitle(
						$self->master(), 
						$last_song->currentTrack()
					),
					$last_song->{'index'}
				]
			);
		}
	}
	
	if ( $log->is_info ) {
		$log->info("Song queue is now " . join(',', map { $_->{'index'} } @$queue));
	}
	
}

sub _Stopped {
	_setPlayingState( $_[0], STOPPED );
	_notifyStopped( $_[0] );
}

sub _notifyStopped {
	my ($self, $suppressNotifications) = @_;
	my $master = master($self);

	foreach my $player ( @{ $self->{'players'} } ) {
		# This was previously commented out, for bug 7781, 
		# because some plugins (Alarm) don't like extra stop events.
		# This broke important notifications for Jive.
		# Other changes mean that that this can be reinstated.
		Slim::Control::Request::notifyFromArray( $player, ['playlist', 'stop'] ) unless $suppressNotifications;
		
		if ($player->can('onStop')) {
			$player->onStop();
		}
	}
}

sub _Streamout {_setStreamingState($_[0], STREAMOUT);}

use constant CHECK_SYNC_INTERVAL        => 0.950;
use constant MIN_DEVIATION_ADJUST       => 0.010;
use constant MAX_DEVIATION_ADJUST       => 10.000;
use constant PLAYPOINT_RECENT_THRESHOLD => 3.0;

sub _CheckSync {
	my ($self, $event, $params) = @_;
	
	my $log = logger('player.sync');
	
	# check to see if resynchronization is necessary

	return unless scalar @{ $self->{'players'} } > 1;
	
	my $now = Time::HiRes::time();
	return if $now < $self->{'nextCheckSyncTime'};
	$self->{'nextCheckSyncTime'} = $now + CHECK_SYNC_INTERVAL;

	# need a recent play-point from all players in the group, otherwise give up
	my $recentThreshold = $now - PLAYPOINT_RECENT_THRESHOLD;
	my @playerPlayPoints;
	foreach my $player (@{ $self->{'players'} }) {
		next unless ( $player->isPlayer()
			&& $prefs->client($player)->get('maintainSync') );
		my $playPoint = $player->playPoint();
		if ( !defined $playPoint ) {
			if ( $log->is_debug ) {$log->debug( $player->id() . " bailing as no playPoint" );}
			return;
		}
		if ( $playPoint->[0] > $recentThreshold ) {
			push(@playerPlayPoints,
				[
					$player,
					$playPoint->[1] + $prefs->client($player)->get('playDelay') / 1000
				]
			);
		}
		else {
			if ( $log->is_debug ) {
				$log->debug( $player->id() . " bailing as playPoint too old: "
					  . ( $now - $playPoint->[0] ) . "s" );
			}
			return;
		}
	}
	return unless scalar(@playerPlayPoints);

	if ( $log->is_debug ) {
		my $first = $playerPlayPoints[0][1];
		my $str = sprintf( "%s: %.3f", $playerPlayPoints[0][0]->id(), $first );
		foreach ( @playerPlayPoints[ 1 .. $#playerPlayPoints ] ) {
			$str .= sprintf( ", %s: %+5d",
				$_->[0]->id(), ( $_->[1] - $first ) * 1000 );
		}
		$log->debug("playPoints: $str");
	}

	# sort the play-points by decreasing apparent-start-time
	@playerPlayPoints = sort { $b->[1] <=> $a->[1] } @playerPlayPoints;

 	# clean up the list of stored frame data
 	# (do this now, so that it does not delay critial timers when using pauseFor())
	Slim::Player::Source::purgeOldFrames( $self->master(),
		$recentThreshold - $playerPlayPoints[0][1] );

	# find the reference player - the most-behind that does not support skipAhead
	my $reference;
	for ( $reference = 0 ; $reference < $#playerPlayPoints ; $reference++ ) {
		last unless $playerPlayPoints[$reference][0]->can('skipAhead');
	}
	my $referenceTime = $playerPlayPoints[$reference][1];

	# my $referenceMinAdjust = $prefs->client($playerPlayPoints[$reference][0])->get('minSyncAdjust')/1000;

	# tell each player that is out-of-sync with the reference to adjust
	for ( my $i = 0 ; $i < @playerPlayPoints ; $i++ ) {
		next if ( $i == $reference );
		my $player = $playerPlayPoints[$i][0];
		my $delta  = abs( $playerPlayPoints[$i][1] - $referenceTime );
		next if (
			   $delta > MAX_DEVIATION_ADJUST
			|| $delta < MIN_DEVIATION_ADJUST
			|| $delta < $prefs->client($player)->get('minSyncAdjust') / 1000

			# || $delta < $referenceMinAdjust
		  );
		if ( $i < $reference ) {
			if ( $log->is_info ) {
				$log->info(sprintf("%s resync: skipAhead %dms",	$player->id(), $delta * 1000));
			}
			$player->skipAhead($delta);
			$self->{'nextCheckSyncTime'} += 1;
		}
		else {

 			# bug 6864: SB1s cannot reliably pause without skipping frames, so we don't try
			if ( $player->can('pauseForInterval') ) {
				if ( $log->is_info ) {
					$log->info(sprintf("%s resync: pauseFor %dms", $player->id(), $delta * 1000));
				}
				$player->pauseForInterval($delta);
				$self->{'nextCheckSyncTime'} += $delta;
			}
		}
	}	
}

sub _Stop {					# stop -> Stopped, Idle
	my ($self, $event, $params, $suppressNotifications) = @_;
	
	# bug 10458 - try to avoding unnecessary notifications
	$suppressNotifications = 1 unless ( $self->isPlaying() || $self->isPaused() );
	
	if ( !$suppressNotifications && $self->playingSong() && ( $self->isPlaying(1) || $self->isPaused() ) ) {
		my $song = $self->playingSong();
		my $handler = $song->currentTrackHandler();
		if ($handler->can('onStop')) {
			$handler->onStop($song);
		}
	}
	
	foreach my $player (@{$self->{'players'}})	{
		_stopClient($player);
	}
	
	my $queue = $self->{'songqueue'};
	while (scalar @$queue > 1) {shift @$queue;}
	
	$queue->[0]->setStatus(Slim::Player::Song::STATUS_FINISHED) if scalar @$queue;
	
	if ($log->is_info && scalar @$queue) {
		$log->info("Song queue is now " . join(',', map { $_->{'index'} } @$queue));
	}
	
	if ($self->{'songStreamController'}) {
		$self->{'songStreamController'}->close();
		$self->{'songStreamController'} = undef;
	}
	
	_setPlayingState($self, STOPPED);
	_setStreamingState($self, IDLE);
	_notifyStopped($self, $suppressNotifications);
}

sub _stopClient {
	my ($client) = @_;
	$client->stop;
	@{$client->chunks} = ();
	$client->closeStream();
}

sub _getNextTrack {			# getNextTrack -> TrackWait
	my ($self, $params, $ifMoreTracks) = @_;
	
	if ($self->{'consecutiveErrors'} > Slim::Player::Playlist::count(master($self)))  {
		$log->warn("Giving up because of too many consecutive errors: " . $self->{'consecutiveErrors'});
		return;
	}
		
	my $index = $params->{'index'};
	my $song  = $params->{'song'};

	my $id = ++$self->{'nextTrackCallbackId'};
	$self->{'nextTrack'} = undef;
	
	if (!$song) {
		# If we have an existing playlist song then we ask it for the next song.
		if (!defined($index) && ($song = $self->streamingSong()) && $song->isPlaylist()) {
			$song = $song->clonePlaylistSong();	# returns undef at end of playlist		
		} else {
			$song = undef;
		}
	}
	
	if (!$song) {
		# Otherwise, we use the repeat mode to decide which playlist entry to ask for.
		
		unless (defined($index)) {
			my $oldIndex = $params->{'errorSong'}
				? $params->{'errorSong'}->{'index'}
				: $params->{'errorIndex'};
			$index = nextsong($self, $oldIndex);
		}
			
		if (!defined($index)) {
			if ($ifMoreTracks) {
				return; # got to end of playlist & no repeat & no force play
			} else {
				$index = 0;			
			}
		}
			
		my $seekdata = $params->{'seekdata'};
		
		$song = Slim::Player::Song->new($self, $index, $seekdata);
		
		if (!$song) {
			_setStreamingState($self, TRACKWAIT);
			_nextTrackError($self, $id, $index);
			return;
		}
	}
	
	_setStreamingState($self, TRACKWAIT);
	
	# Bug 10841: Put the song on the queue now even if it might get removed again later
	# so that player displays can be correct while scanning a remote track
	my $queue = $self->{'songqueue'};
	unshift @$queue, $song unless scalar @$queue && $queue->[0] == $song;
	while (scalar @$queue && 
		   ($queue->[-1]->{'status'} == Slim::Player::Song::STATUS_FAILED || 
			$queue->[-1]->{'status'} == Slim::Player::Song::STATUS_FINISHED)
		  )
	{
		pop @$queue;
	}
	
	$song->getNextSong (
		sub {	# success
			_nextTrackReady($self, $id, $song);
		},
		sub {	# fail
			_nextTrackError($self, $id, $song, @_);
		}
	);
	
	# Show getting-track-info message if still in TRACKWAIT & STOPPED
	if ($self->{'playingState'} == STOPPED && $self->{'streamingState'} == TRACKWAIT) {

		my $handler = $song->currentTrackHandler();
		my $remoteMeta = $handler->can('getMetadataFor')
			? $handler->getMetadataFor($self->master(), $song->currentTrack()->url)
			: {};
		my $icon = $remoteMeta->{cover} || $remoteMeta->{icon} || '/music/' . $song->currentTrack()->id . '/cover.jpg';
		
		_playersMessage($self, $song->currentTrack->url,
			$remoteMeta, $song->isPlaylist() ? 'GETTING_TRACK_DETAILS' : 'GETTING_STREAM_INFO', $icon, 0, 30);
	}
	
}
sub _nextTrackReady {
	my ($self, $id, $song) = @_;
	
	if ($self->{'nextTrackCallbackId'} != $id) {
		$log->info($self->{'masterId'} . ": discarding unexpected nextTrackCallbackId $id, expected " . 
			$self->{'nextTrackCallbackId'});
		return;
	}

	$self->{'nextTrack'} = $song;
	$log->info($self->{'masterId'} . ": nextTrack will be index ". $song->{'index'});
	
	_eventAction($self, 'NextTrackReady');
}

sub _nextTrackError {
	my ($self, $id, $songOrIndex, @error) = @_;

	if ($self->{'nextTrackCallbackId'} != $id) {return;}

	my ($song, $index);
	if (blessed $songOrIndex) {
		$song = $songOrIndex;
	} else {
		$index = $songOrIndex;
	}
	
	_errorOpening($self, $song ? $song->currentTrack()->url : undef, @error);
		
	_eventAction($self, 'NextTrackError', {error => \@error, errorSong => $song, errorIndex => $index});
}

sub _errorOpening {
	my ($self, $songUrl, $error, $url) = @_;
	
	$self->{'consecutiveErrors'}++;
	
	$error ||= 'PROBLEM_OPENING';
	$url   ||= $songUrl;

	_playersMessage($self, $url, {}, $error, undef, 1, 5);
}

sub _playersMessage {
	my ($self, $url, $remoteMeta, $message, $icon, $block, $duration) = @_;
	
	$block    = 0  unless defined $block;
	$duration = 10 unless defined $duration;

	my $master = $self->master();

	my $line1 = (uc($message) eq $message) ? $master->string($message) : $message;
	
	$log->info("$line1: $url");

	foreach my $client (@{$self->{'players'}}) {

		my $line2 = Slim::Music::Info::getCurrentTitle($client, $url, 0, $remoteMeta) || $url;
	
		# Show an error message
		$client->showBriefly( {
			line => [ $line1, $line2 ],
			jive => { type => 'song', text => [ $line1, $line2 ], 'icon-id' => 0, duration => $duration * 1000},
		}, {
			scroll    => 1,
			firstline => 1,
			block     => $block,
			duration  => $duration,
		} );
	}
}

# nextsong is for figuring out what the next song will be.
sub nextsong {
	my ($self, $currsong) = @_;

	my $streamingSong = streamingSong($self);
	
	$currsong = $streamingSong ? $streamingSong->{'index'} : 0 unless defined $currsong;
	
	my $client = master($self);
	my $playlistCount = Slim::Player::Playlist::count($client);

	if (!$playlistCount) {return undef;}
	
	my $repeat = Slim::Player::Playlist::repeat($client);
	
	if ($self->{'consecutiveErrors'} >= 2) {
		if (scalar @{$self->songqueue()} == 1) {
			$log->warn("Giving up because of too many consecutive errors: " . $self->{'consecutiveErrors'});
			return undef;
		} elsif ($repeat == 1) {
			$repeat = 2;	# skip this track anyway after two errors
		}
	}

	if ( $repeat == 1 ) {
		return $currsong;
	}

	if ($self->{'consecutiveErrors'} >= $playlistCount) {
		$log->warn("Giving up because of too many consecutive errors: " . $self->{'consecutiveErrors'});
		return undef;
	}
	
	my $nextsong = $currsong + 1;

	if ($nextsong >= $playlistCount) {
		# play the next song and start over if necessary
		if (Slim::Player::Playlist::shuffle($client) && 
			$repeat == 2 &&
			$prefs->get('reshuffleOnRepeat')) {
			
			Slim::Player::Playlist::reshuffle($client, 1);
		}
		$nextsong = 0;
	}
		
	$log->info("The next song is number $nextsong, was $currsong");
	
	if (!$repeat && $nextsong == 0) {$nextsong = undef;}

	return $nextsong;
}

sub _Continue {
	my ($self, $event, $params) = @_;
	my $song          = $params->{'song'};
	my $bytesReceived = $params->{'bytesReceived'};
	
	my $seekdata;
	
	if ($bytesReceived) {
		$seekdata = $song->getSeekDataByPosition($bytesReceived);
	}	
	
	if (!$bytesReceived || $seekdata) {
		$log->is_info && $log->info("Restarting stream at offset $bytesReceived");
		_Stream($self, $event, {song => $song, seekdata => $seekdata, reconnect => 1});
		if ($song == playingSong($self)) {
			$song->setStatus(Slim::Player::Song::STATUS_PLAYING);
		}
	} else {
		$log->is_info && $log->info("Restarting playback at time offset: ". $self->playingSongElapsed());
		_JumpToTime($self, $event, {newtime => $self->playingSongElapsed(), restartIfNoSeek => 1});
	}
}

sub _StopGetNext {			# stop, getNextTrack -> Stopped, TrackWait
	my ($self, $event, $params) = @_;
	_Stop(@_);
	_getNextTrack($self, $params);	
}

sub _Skip {
	my ($self, $event, $params) = @_;
	
	my $currentSong = $self->streamingSong();
	my $handler     = $currentSong->currentTrackHandler();
	my $url         = $currentSong->currentTrack()->url;
	
	if ($handler->can('canDoAction') && !$handler->canDoAction($self->master(), $url, 'stop')) {
		$log->info("Skip for $url disallowed by protocol handler");
		return;
	}
	
	_StopGetNext(@_);
}

sub _FlushGetNext {			# flush -> Idle; IF [moreTracks] THEN getNextTrack -> TrackWait ENDIF
	my ($self, $event, $params) = @_;
	
	foreach my $player (@{$self->{'players'}})	{
		$player->flush();
	}
	_setStreamingState($self, IDLE);
	_getNextTrack($self, $params, 1);
}

sub _NextIfMore {			# -> Idle; IF [moreTracks] THEN getNextTrack -> TrackWait ENDIF
	my ($self, $event, $params) = @_;
	_setStreamingState($self, IDLE);
	_getNextTrack($self, $params, 1);
}

sub _StopNextIfMore {		# -> Stopped, Idle; IF [moreTracks] THEN getNextTrack -> TrackWait ENDIF
	my ($self, $event, $params) = @_;
	
	# bug 10165: need to force stop in case the failure that got use here did not stop all active players
	_Stop(@_);
	
	_getNextTrack($self, $params, 1);
}

sub _SyncStopNext {		# -> [synced]Stopped, Idle; IF [moreTracks] THEN getNextTrack -> TrackWait ENDIF
	my ($self, $event, $params) = @_;
	
	# bug 10165: need to force stop in case the failure that got use here did not stop all active players
	if ($self->activePlayers() > 1) {
		_Stop(@_);
	} else {
		_setStreamingState($self, IDLE);
	}
	_getNextTrack($self, $params, 1);
}

sub _JumpToTime {			# IF [canSeek] THEN stop, stream -> Buffering, Streaming ENDIF
	my ($self, $event, $params) = @_;
	my $newtime = $params->{'newtime'};
	my $restartIfNoSeek = $params->{'restartIfNoSeek'};

	my $song = playingSong($self) || return;
	my $handler = $song->currentTrackHandler();

	if ($newtime !~ /^[\+\-]/ && $newtime == 0) {
		# User is trying to restart the current track
		my $url         = $song->currentTrack()->url;
		
		if ($handler->can("canDoAction") && !$handler->canDoAction($self->master(), $url, 'rew')) {
			$log->debug("Restart for $url disallowed by protocol handler");
			return;
		}
		
		_Stop($self, $event, $params, 'suppressNotification');
		$song->resetSeekdata();
		_Stream($self, $event, {song => $song});
		return;
	}

	if ($newtime =~ /^[\+\-]/) {
		my $oldtime = playingSongElapsed($self);
		$log->info("Relative jump $newtime from current time $oldtime");
		$newtime += $oldtime;
		
		if ($newtime < 0) {
			$newtime = 0;
		} elsif ($newtime > $self->playingSongDuration()) {
			_Skip($self, $event);
			return;
		}
	}
	
	my $seekdata;
	
	# get seek data from protocol handler.
	if ($handler->can('getSeekData')) {
		$seekdata = $handler->getSeekData($song->master(), $song, $newtime);
	}	
	
	return unless $seekdata || $restartIfNoSeek;

	_Stop($self, $event, $params, 'suppressNotification');
	
	_Stream($self, $event, {song => $song, seekdata => $seekdata});
}

sub _Stream {				# play -> Buffering, Streaming
	my ($self, $event, $params) = @_;

	# Get song and seekdata from params if present
	
	my $song;
	my $seekdata;
	my $reconnect;
	if ($params) {
		$seekdata  = $params->{'seekdata'};
		$song      = $params->{'song'};
		$reconnect = $params->{'reconnect'};
	}
	
	if ($song) {
		$log->info($self->{'masterId'} . ": got song from params, song index ", $song->{'index'});
	}
	
	unless ($song) {$song = $self->{'nextTrack'}};
	
	assert($song);
	if (!$song) {
		$log->error("No song to stream: try next");
		# TODO - show error
		_NextIfMore($self, $event);
		return;
	}
	
	$log->info($self->{masterId} . ": preparing to stream song index " .  $song->{'index'});
	
	my $queue = $self->{'songqueue'};

	# bug 10510 - remove old songs from queue before adding new one
	# (Note: did not just test for STATUS_PLAYING so as not to hardwire max-queue-length == 2 too often)
	while (scalar @$queue && 
		   ($queue->[-1]->{'status'} == Slim::Player::Song::STATUS_FAILED || 
			$queue->[-1]->{'status'} == Slim::Player::Song::STATUS_FINISHED || 
			$queue->[-1]->{'status'} == Slim::Player::Song::STATUS_READY)
		  ) {

		pop @$queue;
	}
	
	unshift @$queue, $song unless scalar @$queue && $queue->[0] == $song;
	if ($log->is_info) {	
		$log->info("Song queue is now " . join(',', map { $_->{'index'} } @$queue));
	}
	
	# Allow protocol handler to override playback and do something else,
	# used by Random Play, MusicIP, to provide URLs
	if ( $song->currentTrackHandler()->can('overridePlayback') ) {
		$log->debug("Protocol Handler for " . $song->currentTrack()->url . " overriding playback");
		return $song->currentTrackHandler()->overridePlayback( $self->master(), $song->currentTrack()->url );
	}
	
	my ($songStreamController, @error) = $song->open($seekdata);
		
	if (!$songStreamController) {
		_errorOpening($self, $song->currentTrack()->url, @error);
		_NextIfMore($self, $event, {errorSong => $song});
		return;	
	}	

	Slim::Control::Request::notifyFromArray( $self->master(),
		[ 'playlist', 'open', $songStreamController->streamUrl() ] );

	$self->{'songStreamController'} = $songStreamController;

	my $paused = (scalar @{$self->{'players'}} > 1) && 
		($self->{'playingState'} == STOPPED || $self->{'playingState'} == BUFFERING);

	my $fadeIn = $self->{'fadeIn'} || 0;
	$paused ||= ($fadeIn > 0);
	
	my $setVolume = $self->{'playingState'} == STOPPED;
	my $masterVol = abs($prefs->client($self->master())->get("volume") || 0);
	
	my $startedPlayers = 0;
	my $reportsTrackStart = 0;
	
	# bug 10438
	Slim::Player::Source::resetFrameData($self->master());
	
	foreach my $player (@{$self->{'players'}}) {
		if ($setVolume) {
			# Bug 10310: Make sure volume is synced if necessary
			my $vol = ($prefs->client($player)->get('syncVolume'))
				? $masterVol
				: abs($prefs->client($player)->get("volume") || 0);
			$player->volume($vol);
		}
		
		my $myFadeIn = $fadeIn;
		if ($fadeIn > $player->maxTransitionInterval()) {
			$myFadeIn = 0;
		}
		
		$log->info($player->id . ": stream");
		
		if ($song->currentTrackHandler()->can('onStream')) {
			$song->currentTrackHandler()->onStream($player, $song);
		}
		
		$startedPlayers += $player->play( { 
			'paused'      => $paused, 
			'format'      => $song->streamformat(), 
			'controller'  => $songStreamController,
			'url'         => $songStreamController->streamUrl(), 
			'reconnect'   => $reconnect,
			'replay_gain' => Slim::Player::ReplayGain->fetchGainMode($self->master(), $song),
			'seekdata'    => $seekdata,
			'fadeIn'      => $myFadeIn,
			# we never set the 'loop' parameter
		} );
		
		$reportsTrackStart ||= $player->reportsTrackStart();
	}	
	
	if ($startedPlayers != scalar @{$self->{'players'}}) {
		$log->warn(sprintf('%s: only %d of %d players started streaming',
			$self->{'masterId'}, $startedPlayers, scalar @{$self->{'players'}}));
		_Stop($self); 	# what else can we do?
		$self->{'consecutiveErrors'}++;
		_NextIfMore($self);
		return;
	}

	if ( $log->is_info ) {
		$log->info("Song queue is now " . join(',', map { $_->{'index'} } @$queue));
	}

	Slim::Player::Playlist::refreshPlaylist($self->master());
	
	$self->{'nextTrack'} = undef;
	if ($self->{'playingState'} == STOPPED) {_setPlayingState( $self, BUFFERING );}
	_setStreamingState($self, STREAMING);
	
	if (!$reportsTrackStart) {
		_Playing($self);
	}
}

sub _PlayIfReady {		# -> Stopped; IF [trackReady] THEN play -> Buffering, Streaming ENDIF
	my ($self, $event, $params) = @_;
	
	_setPlayingState($self, STOPPED);

	if ( $self->{'nextTrack'} ) {
		_Stream(@_);
	}
	else {
		_notifyStopped($self);
	}
}


sub _PlayAndStream {		# -> PLAYING; IF [allReadyToStream] THEN play -> Streaming ENDIF
	_Playing(@_);
	_StreamIfReady(@_);		# Bug 5103
}

sub _StreamIfReady {		# IF [allReadyToStream] THEN play -> Streaming ENDIF
	my ($self, $event, $params) = @_;
	
	my $song = $self->{'nextTrack'};
	if (!$song) {return;}
	
	# Bug 5103, the firmware can handle only 2 tracks at a time: one playing and one streaming,
	# and on very short tracks we may get multiple decoder underrun events during playback of a single
	# track.  We need to ignore decoder underrun events if there's already a streaming track in the queue
	
	# Bug 10841: Bug check that the first song is not the one we want to play
	
	my $queue = $self->{'songqueue'};
	if (scalar @{$queue} > 1 && $queue->[0]->{'status'} != Slim::Player::Song::STATUS_READY) {
		return;
	}
	
	my $ready = 1;
	foreach my $player (@{$self->{'players'}})	{
		if (!$player->isReadyToStream($song)) {
			$ready = 0;
			last;
		}
	}
	
	_Stream(@_) unless (!$ready);
}

sub _Start {		# start -> Playing
	my ($self, $event, $params) = @_;
	
	if (!$self->{'rebuffering'}) {
		
		if ($self->{'fadeIn'}) {
			for (@{ $self->{'players'} }) {
				if ($self->{'fadeIn'} > $_->maxTransitionDuration()) {
					$_->fade_volume($self->{'fadeIn'});
				}
			}
		}
		$self->{'fadeIn'} = undef;

		if ( scalar @{ $self->{'players'} } > 1 ) {
			_syncStart($self);
		} else {
			$self->master()->resume();
		}

		_Playing(@_);
	} else {
		# TODO maybe try synchronized resume
		_Resume(@_);
	}
}

sub _syncStart {
	my ($self) = @_;

	my $playerStartDelay = 0;    # ms

	my $player;
	
	foreach $player ( @{ $self->{'players'} } ) {
		my $delay;               # ms
		if ((
				$delay = $prefs->client($player)->get('startDelay') +
				$prefs->client($player)->get('playDelay')
			) > $playerStartDelay
		  )
		{
			$playerStartDelay = $delay;
		}
	}

	my $startAt =
	  Time::HiRes::time() +
	  ( $playerStartDelay + ( $prefs->get('syncStartDelay') || 100 ) ) / 1000;

	foreach $player ( @{ $self->{'players'} } ) {
		$player->startAt(
			$startAt - (
				$prefs->client($player)->get('startDelay') +
				  $prefs->client($player)->get('playDelay') ) / 1000
		);
	}
}

sub _StartIfReady {			# IF [allReadyToStart] THEN 
							#	IF [rebuffering] THEN resume ELSE start ENDIF 
							#	-> Playing
							# ENDIF
	my ($self, $event, $params) = @_;
		
	my $ready = 1;
	foreach my $player (@{$self->{'players'}})	{
		if (!$player->isBufferReady()) {
			$ready = 0;
			last;
		}
	}
	
	_Start(@_) unless (!$ready);
}

sub _StartStreamout {		# start -> Playing, Streamout
	my ($self, $event, $params) = @_;
	_setStreamingState($self, STREAMOUT);
	_Start(@_);
}

sub _WaitToSync {			# IF [allReadyToStart] THEN start -> Playing ELSE -> WaitToSync ENDIF
	my ($self, $event, $params) = @_;
	_setPlayingState($self, WAITING_TO_SYNC);
	
	# Could have become the only player in the sync-group since we started (unlikely, but ...)
	# Let's just see if we can move on straight away
	return _StartIfReady(@_);
}


sub _Pause {				# pause -> Paused
	my ($self, $event, $params) = @_;

	_setPlayingState($self, PAUSED);
	
	# since we can't count on the accuracy of the fade
	# timers, we fade-out them all, but the master calls
	# back to pause everybody
	foreach my $player (@{$self->{'players'}})	{
		if (_isMaster($self, $player)) {
			$player->fade_volume(
				-(FADEVOLUME),
				sub {
					# Actually pause the players when the fade-out is complete.
					
					# Reevaluate player-set here in case sync-group membership
					# changed during fade-out, although this will fail if we
					# have a new master.
					foreach my $player (@{$self->{'players'}})	{
						$player->pause();
					}
				}
			);
		} else {
			$player->fade_volume(-(FADEVOLUME));
		}
		
		Slim::Control::Request::notifyFromArray( $player, ['playlist', 'pause', 1] );
	}
	
}

# Bug 8861
# Force a start in case a track was too short to trigger autostart
# This code should not be necessary if bug 9125 is fixed in firmware
sub _AutoStart {			# [streaming-track-not-playing] start -> Streamout
	my ($self, $event, $params) = @_;
	
	_setStreamingState($self, STREAMOUT);
	
	if ($self->streamingSong && $self->streamingSong->{status} != Slim::Player::Song::STATUS_PLAYING) {
		$log->info('autostart possibly short track');
		foreach my $player (@{$self->{'players'}})	{
			$player->resume();
		}
		# we still rely on a track-start-event from the player
	}
}

sub _Resume {				# resume -> Playing
	my ($self, $event, $params) = @_;

	_setPlayingState($self, PLAYING);
	foreach my $player (@{$self->{'players'}})	{
		# set volume to 0 to make sure fade works properly
		$player->volume(0,1);
		$player->resume();
		$player->fade_volume($self->{'fadeIn'} ? $self->{'fadeIn'} : FADEVOLUME);
		Slim::Control::Request::notifyFromArray( $player, ['playlist', 'pause', 0] );
	}
	$self->{'fadeIn'} = undef;
}


sub _Rebuffer {				# pause(noFadeOut) -> Buffering(rebuffering)
	my ($self, $event, $params) = @_;
	
	_setPlayingState($self, BUFFERING);
	$self->{'rebuffering'} = 1;
	foreach my $player (@{$self->{'players'}})	{
		$player->pause();
		$player->rebuffer();
	}
}

####################################################################
# Incoming queries - <<interface>> PlayStatus

sub isPlaying {
	my ($self, $really) = @_;
	return $really ? $self->{'playingState'} == PLAYING : (!isStopped($self) && !isPaused($self)); 
}

sub isStopped {
	return $_[0]->{'playingState'} == STOPPED && $_[0]->{'streamingState'} == IDLE;
}

sub isStreaming {
	return $_[0]->{'streamingState'} == STREAMING;
}

sub isStreamout {
	return $_[0]->{'streamingState'} == STREAMOUT;
}

sub isPaused {
	return $_[0]->{'playingState'} == PAUSED;
}

# returns 1 for normal buffering, 2 for rebuffering
sub buffering {
	return ($_[0]->{'playingState'} == BUFFERING || $_[0]->{'playingState'} == WAITING_TO_SYNC)
		? ($_[0]->{'rebuffering'} ? 2 : 1)
		: 0;
}

sub isWaitingToSync {
	return $_[0]->{'playingState'} == WAITING_TO_SYNC;
}

sub playingSongDuration {
	my $song = playingSong($_[0]) || return;
	return $song->duration();
}

sub playingSongElapsed {
	return Slim::Player::Source::songTime(master($_[0]));
}

sub master {
	return Slim::Player::Client::getClient($_[0]->{'masterId'});
}

sub songStreamController {
	return $_[0]->{'songStreamController'};
}

sub setSongStreamController {
	$_[0]->{'songStreamController'} = $_[1];
}

sub playingSong {
	return $_[0]->{'songqueue'}->[-1] if scalar $_[0]->{'songqueue'};
}

sub streamingSong {
	return $_[0]->{'songqueue'}->[0] if scalar $_[0]->{'songqueue'};
}

sub songqueue {
	return $_[0]->{'songqueue'};
}

sub currentSongForUrl {
	my ($self, $url) = @_;
	
	my $song;
	for $song (reverse @{$self->songqueue()}) {
		if ($song->currentTrack()->url eq $url || $song->{'track'}->url eq $url) {
			return $song;
		}
	}
}

sub onlyActivePlayer {
	my ($self, $client) = @_;
	
	my @activePlayers = $self->activePlayers();
	
	return (scalar @activePlayers == 1 && $client == $activePlayers[0]);	
}

sub frameData {
	my $self = shift;
	if (@_) {
		$self->{'frameData'} = shift;
	}
	return $self->{'frameData'};
}

sub initialStreamBuffer {
	my $self = shift;
	if (@_) {
		$self->{'initialStreamBuffer'} = shift;
	}
	return $self->{'initialStreamBuffer'};
}

####################################################################
# Incoming events - miscellaneous

sub localEndOfStream {
	
	closeStream($_[0]);

	_eventAction($_[0], 'LocalEndOfStream');
}

sub sync {
	my ($self, $player) = @_;

	my $log = logger('player.sync');
		
	if ($player->controller() == $self) {
		$log->info($self->{'masterId'} . " sync-group already contains: " . $player->id());
		if ($player->power && $player->connected) {
			$self->playerActive($player);
		}
		return;
	}
	
	my $other = $player->controller();
	if (@{$other->{'allPlayers'}} > 1) {
		$other->unsync($player);	# will also stop it, if necessary		
	} elsif (!$other->isStopped()) {
		_stopClient($player);
	}

	$log->info($self->{'masterId'} . " adding to syncGroup: " . $player->id()); # bt();
	
	assert (@{$player->controller()->{'allPlayers'}} == 1); # can only add un-synced player
	
	foreach (@{$self->{'allPlayers'}}) {
		if ($_ == $player) {
			$log->error($player->id . " already in this syncgroup but has different controller");
			return;
		}
	}
	
	# setup and save syncgroup
	my $id = $self->{'syncgroupid'};
	if (!$id) {
		$id = $prefs->client(master($self))->get('syncgroupid') || int(rand 999999999);
		$self->{'syncgroupid'} = $id;
		$prefs->client(master($self))->set('syncgroupid', $id);
	}
	$prefs->client($player)->set('syncgroupid', $id);

	# make it one of ours
	$player->controller($self);	# discards old controller -> safe, as not synced
	push @{$self->{'allPlayers'}}, $player;
	
	if (@{$self->{'allPlayers'}} == 1) {
		_newMaster($self);
	}
	
	# TODO - reevaluate master

	if ($player->power && $player->connected) {
		push @{$self->{'players'}}, $player;
		
		if (!isStopped($self)) {
			_JumpToTime($self, undef, {newtime => playingSongElapsed($self), restartIfNoSeek => 1});		# TODO - stay paused if paused
		}
	} else {
		if ($log->is_info) {
			$log->info(sprintf("New player inactive: power=%d, connected=%d", $player->power, $player->connected));
		}
	}
	
	foreach (@{$self->{'allPlayers'}}) {
		Slim::Control::Request::notifyFromArray($_, ['playlist', 'sync']);
	}
	
	if ($log->is_info) {
		$log->info($self->{'masterId'} . " sync group now has: " . join(',', map { $_->id } @{$self->{'allPlayers'}}));
		$log->info($self->{'masterId'} . " active players are: " . join(',', map { $_->id } @{$self->{'players'}}));
	}
}

sub unsync {
	my ($self, $player, $keepSyncGroupId) = @_;
	
	assert ($player->controller() == $self);
	
	if (@{$self->{'allPlayers'}} < 2) {return;}
	
	my $log = logger('player.sync');
	
	$log->info($self->{'masterId'} . " unsync " . $player->id()); # bt();
		
	# remove player from the lists
	my $i = 0;
	foreach my $c (@{$self->{'players'}}) {
		if ($c == $player) {
		
			if (!isStopped($self)) {
				if (@{$self->{'players'}} == 1) {
					# If player is our last active player, then stop
					_Stop($self);
				} else {
					# Otherwise just stop the one we are unsyncing
					_stopClient($player);
					Slim::Control::Request::notifyFromArray($player, ['playlist', 'stop']);	
				}
			} else {
				# Force stop anyway in case it was paused, off
				_stopClient($player);
			}
				
			splice @{$self->{'players'}}, $i, 1;
			last;
		}
		$i++;
	}

	$i = 0;
	foreach my $c (@{$self->{'allPlayers'}}) {
		if ($c == $player) {
			splice @{$self->{'allPlayers'}}, $i, 1;
			last;
		}
		$i++;
	}
	
	# Choose new master
	if (@{$self->{'allPlayers'}}) {
		_newMaster($self);
	}
	
	# Every player must have a controller
	$player->controller(Slim::Player::StreamingController->new($player));
	Slim::Player::Playlist::copyPlaylist($player, $self->master());
	
	$prefs->client($player)->remove('syncgroupid') unless $keepSyncGroupId;
	
	foreach ($player, @{$self->{'allPlayers'}}) {
		Slim::Control::Request::notifyFromArray($_, ['playlist', 'sync']);
	}
	
	if ($log->is_info) {
		$log->info($self->{'masterId'} . " sync group now has: " . join(',', map { $_->id } @{$self->{'allPlayers'}}));
		$log->info($self->{'masterId'} . " active players are: " . join(',', map { $_->id } @{$self->{'players'}}));
	}
}

sub playerActive {
	my ($self, $player) = @_;
	
	foreach my $c (@{$self->{'players'}}) {
		if ($c == $player) {
			$log->info($self->{'masterId'} . " player already active: " . $player->id());
			return;
		}
	}
	
	# It is possible for us to be paused with all the "active" players actually (logically) powered off.
	# bug 10406: In fact, the last active player in a group to be powered off may anyway be left active and off.
	# In this case it could be that another player in the sync group, which is not part of the off-active
	# set, is made active. So we first need to test for this situation
	if (!master($self)->power()) {
		# This means that the existing 'active' players were paused-on-powerOff, or the last player left active.
		# We need to stop them and make them inactive - otherwise they will auto-magically power-on.
		_Stop($self) if !$self->isStopped();
		$self->{'players'} = [];       
	}
	
	# bug 10828: don't unpause
	_Stop($self) if (isPaused($self));
	
	push @{$self->{'players'}}, $player;
	
	# Choose new master
	_newMaster($self);
	
	if ($log->is_info) {
		$log->info($self->{'masterId'} . " sync group now has: " . join(',', map { $_->id } @{$self->{'allPlayers'}}));
		$log->info($self->{'masterId'} . " active players are: " . join(',', map { $_->id } @{$self->{'players'}}));
	}
	
	if (!isStopped($self)) {
		$log->info($self->{'masterId'} . " restart play");
		_JumpToTime($self, undef, {newtime => playingSongElapsed($self), restartIfNoSeek => 1});		# TODO - stay paused if paused
	}
}

sub playerInactive {
	my ($self, $player) = @_;
	
	# remove player from the list
	my $i = 0;
	foreach my $c (@{$self->{'players'}}) {
		if ($c == $player) {

			if (!isStopped($self)) {
				if (@{$self->{'players'}} == 1) {
					# If player is our last active player, then stop
					_Stop($self);
				} else {
					# Otherwise just stop the one we are unsyncing
					_stopClient($player);
					Slim::Control::Request::notifyFromArray($player, ['playlist', 'stop']);	
				}
			}
	
			splice @{$self->{'players'}}, $i, 1;
			last;
		}
		$i++;
	}
	
	# Choose new master
	# TODO - in all cases
	if ($player->id() eq $self->{'masterId'} && @{$self->{'players'}}) {
		_newMaster($self);
	}

	if ($log->is_info) {
		$log->info($self->{'masterId'} . " sync group now has: " . join(',', map { $_->id } @{$self->{'allPlayers'}}));
		$log->info($self->{'masterId'} . " active players are: " . join(',', map { $_->id } @{$self->{'players'}}));	
	}
}

sub playerReconnect {
	my ($self, $bytesReceived) = @_;
	$log->info($self->{'masterId'});
	
	my $song = $self->streamingSong();
	
	if ($song) {
		_eventAction($self, 'ContinuePlay', {bytesReceived => $bytesReceived, song => $song});
	}
	
}

sub activePlayers {
	return @{$_[0]->{'players'}};
}

sub allPlayers {
	return @{$_[0]->{'allPlayers'}};
}

sub closeStream {
	$_[0]->{'songStreamController'}->close() if $_[0]->{'songStreamController'};
}

####################################################################
# Incoming events - <<interface>> PlayControl

sub stop       {$log->info($_[0]->{'masterId'}); _eventAction($_[0], 'Stop');}

sub play       {
	$log->info($_[0]->{'masterId'});
	$_[0]->{'consecutiveErrors'} = 0;
	$_[0]->{'fadeIn'} = $_[3] if ($_[3] && $_[3] > 0);
	_eventAction($_[0], 'Play', {index => $_[1], seekdata => $_[2]});
}

sub skip       {
	$log->info($_[0]->{'masterId'});
	$_[0]->{'consecutiveErrors'} = 0;
	_eventAction($_[0], 'Skip');
}


sub pause      {
	my ($self) = @_;
	
	$log->info($self->{'masterId'});
	
	# Some protocol handlers don't allow pausing of active streams.
	# We check if that's the case before continuing.
	my $song = playingSong($self) || {};
	my $handler = $song->{'handler'};

	if ($handler && $handler->can("canDoAction") &&
		!$handler->canDoAction(master($self), $song->currentTrack()->url, 'pause'))
	{
		$log->warn("Protocol handler doesn't allow pausing. Let's try stopping.");
		stop(@_);
	}
		
	_eventAction($_[0], 'Pause');
}


sub resume     {
	$_[0]->{'fadeIn'} = $_[1] if ($_[1] && $_[1] > 0);
	$log->info($_[0]->{'masterId'}, 'fadein=', ($_[1] ? $_[1] : 'undef'));
	_eventAction($_[0], 'Resume');
}

sub flush      {$log->info($_[0]->{'masterId'}); _eventAction($_[0], 'Flush');}
sub jumpToTime {$log->info($_[0]->{'masterId'}); _eventAction($_[0], 'JumpToTime', {newtime => $_[1], restartIfNoSeek => $_[2]});}


####################################################################
# Incoming events - <<interface>> PlayerNotificationHandler

sub playerStopped {
	my ($self, $client) = @_;
		
	$log->info($client->id);

	# TODO - handler hook
	
	unless (_isMaster($self, $client)) {return;}
	
	my $queue = $self->{'songqueue'};
	
	if (@{$queue} > 1) {
		pop @{$queue};
	} else {
		my $song = playingSong($self);
		if ($song && $song->{'status'} == Slim::Player::Song::STATUS_PLAYING) {
			$song->setStatus(Slim::Player::Song::STATUS_FINISHED);
		}
	}
	
	_eventAction($self, 'Stopped');
}

sub playerTrackStarted {
	my ($self, $client) = @_;

	$log->info($client->id);

	unless (_isMaster($self, $client)) {return;}
	
	# Hack - we can still get track-started events after abandoning the previous track
	# Mostly these duplicates do no harm, but when synced they can really mess things up.
	# So if we are synced then the first track will be 'started' via unpause
	if (scalar @{$self->songqueue()} == 1 && scalar $self->activePlayers() > 1) {return;}

	_eventAction($self, 'Started');

	# sync the button mode periodic update to the track time
	Slim::Buttons::Common::syncPeriodicUpdates($client, Time::HiRes::time() + 0.1);
}

sub playerReadyToStream {
	my ($self, $client) = @_;

	$log->info($client->id);

	if ($self->_isMaster($client)) {
		if ( my $song = $self->streamingSong() ) {
			my $handler = $song->currentTrackHandler();
			if ($handler->can('onPlayout')) {
				$handler->onPlayout($song);
			}
		}
	}

	_eventAction($self, 'ReadyToStream');
}

sub playerOutputUnderrun {
	my ($self, $client) = @_;
	
	if ( $log->is_info ) {
		my $decoder = $client->bufferFullness();
		my $output  = $client->outputBufferFullness() || 0;
		$log->info($client->id, ": decoder: $decoder / output: $output" );
	}

	# SN may want to log rebuffer events
	if ( main::SLIM_SERVICE ) {
		$client->logStreamEvent( 'rebuffer' );
		
		# Also may want to perform an alternate action on output underrun, such as just
		# restarting the stream to get an instant full buffer
		if ( $client->handleOutputUnderrun ) {
			return;
		}
	}

	_eventAction($self, 'OutputUnderrun');
}

sub playerStreamingFailed {
	my ($self, $client, @error) = @_;

	$log->info($client->id);
	
	my $song = streamingSong($self);
	
	if ( $song ) {
		$song->setStatus(Slim::Player::Song::STATUS_FAILED);
	}
	
	# bug 10407: remove failed Song from song-queue unless only Song in queue.
	my $queue = $self->{'songqueue'};
	if (scalar(@$queue) > 1) {
		shift @$queue;
	}

	if ( $song ) {
		_errorOpening($self, $song->currentTrack()->url, @error);
	}

	_eventAction($self, 'StreamingFailed');
}

sub playerBufferReady {
	my ($self, $client) = @_;

	$log->info($client->id);

	_eventAction($self, 'BufferReady');
}

sub playerEndOfStream {
	my ($self, $client) = @_;

	$log->info($client->id);

	# TODO - handler hook

	unless (_isMaster($self, $client)) {return;}

	_eventAction($self, 'EndOfStream');
}

sub playerDirectMetadata {
	my ($self, $client, $metadata, $timestamp) = @_;

	$log->info($client->id);

	unless (_isMaster($self, $client)) {return;}

	my $song = _streamingSong($self);
	my $handler = $song->currentTrackHandler();
	if ($handler->can('directMetadata')) {
		$handler->directMetadata($song, $metadata);
		# TODO - schedule title update? 
	}
}

sub playerStatusHeartbeat {
	my ($self, $client) = @_;

	unless (_isMaster($self, $client)) {return;}

	_eventAction($self, 'StatusHeartbeat');
}

sub setState {
	my ($self, $state) = @_;
	
	my ($playing, $streaming) = split /-/, $state;
	
	_setPlayingState( $self, $PlayingStateNameMap{ $playing } );
	_setStreamingState( $self, $StreamingStateNameMap{ $streaming } );
}

####################################################################
# Support Functions

sub _newMaster {
	my ($self) = @_;
	
	my $oldMaster = master($self);
	
	# TODO - better algorithm
	my $newMaster = $self->{'players'}->[0] || $self->{'allPlayers'}->[0];

	return if $oldMaster == $newMaster;
	
	$self->{'masterId'} = $newMaster->id();
	
	$log->info("new master: " . $self->{'masterId'});
	
	# copy the playlist to the new master
	Slim::Player::Playlist::copyPlaylist($newMaster, $oldMaster);
			
	$newMaster->streamformat($oldMaster->streamformat);
	$oldMaster->streamformat(undef);	
	
	# do we still need to save frame data?
	if (@{$self->{'players'}} < 2) {
		initialStreamBuffer($self, undef);
		frameData($self, undef);
	} else {
		my $needFrameData = 0;
	    foreach ( @{$self->{'players'}} ) {
		    my $model = $_->model();
		    last if $needFrameData = ($model eq 'slimp3' || $model eq 'squeezebox');
	    }
		initialStreamBuffer($self, undef);
		frameData($self, undef);
	}	
}

sub _isMaster {
	my ($self, $client) = @_;
	return ($self->{'masterId'} eq $client->id());
}

sub _getPlayingState {return $_[0]->{'playingState'};}
sub _getStreamingState {return $_[0]->{'streamingState'};}

sub _setPlayingState {
	my ($self, $newState) = @_;
	$self->{'playingState'} = $newState;

	$log->info("new playing state $PlayingStateName[$newState]");
	
	if ( main::SLIM_SERVICE ) {
		$self->_persistState();
	}

	if ($newState != BUFFERING && $newState != WAITING_TO_SYNC) {$self->{'rebuffering'} = 0;}
}

sub _setStreamingState {
	my ($self, $newState) = @_;
	$self->{'streamingState'} = $newState;
	
	$log->info("new streaming state $StreamingStateName[$newState]");
	
	# If we switch to IDLE then any oustanding getNextTrack callback should be discarded
	if ($newState == IDLE) {
		$self->{'nextTrackCallbackId'}++;
		$self->{'nextTrack'} = undef;
	}
	
	if ( main::SLIM_SERVICE ) {
		$self->_persistState();
	}
}

sub _persistState {
	my $self = shift;
	
	# Persist playing/streaming state to the SN database
	# This assists in seamless resume of a player if it gets moved
	# to another instance.
	my $state = $PlayingStateName[ $self->{playingState} ] 
		. '-' . $StreamingStateName[ $self->{streamingState} ];
	
	for my $client ( $self->activePlayers ) {
		# Only update if serviceip matches
		$client->playerData->updatePlaymode( $state, Slim::Utils::IPDetect::IP_port() );
	}
}

1;
