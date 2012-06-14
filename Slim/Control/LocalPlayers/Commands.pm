package Slim::Control::Commands;

# $Id: Commands.pm 5121 2005-11-09 17:07:36Z dsully $
#
# Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

################################################################################

=head1 NAME

Slim::Control::Commands

=head1 DESCRIPTION

Implements most server commands and is designed to be exclusively called
through Request.pm and the mechanisms it defines.

=cut

use strict;

use Scalar::Util qw(blessed);
use File::Spec::Functions qw(catfile);
use Digest::SHA1 qw(sha1_base64);
use JSON::XS::VersionOneAndTwo;

use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Scanner;
use Slim::Utils::Prefs;
use Slim::Utils::Alarm;

my $log = logger('control.command');

my $prefs = preferences('server');


###############################################################
#
# Methods only relevant for locally-attached players from here on

sub alarmCommand {
	# functions designed to execute requests have a single parameter, the
	# Request object
	my $request = shift;

	# check this is the correct command. In theory this should never happen
	# but we check anyway since it is easy to err in the big dispatch table.
	# Please check other commands for examples of more advanced usage of
	# isNotCommand for multi-term commands
	if ($request->isNotCommand([['alarm']])) {
	
		# set an appropriate error state. This will stop execute and callback
		# and notification, etc.
		$request->setStatusBadDispatch();
		return;
	}
	
	# get the parameters. In this case the parameters are defined here only
	# but for some commands, the parameters name start with _ and are defined
	# in the big dispatch table (see Request.pm).
	my $client      = $request->client();
	my $cmd         = $request->getParam('_cmd');

	my @tags = qw( id dow dowAdd dowDel enabled repeat time volume playlisturl url cmd );

	# legacy support for "bare" alarm cli command (i.e., sending all tagged params)
	my $params;
	my $skip;
	if ($cmd =~ /:/) {
		my ( $tag, $val ) = split (/:/, $cmd);
		$params->{$tag} = $val;
		$skip = $tag;
	} else {
		$params->{cmd} = $cmd;
		$skip = 'cmd';
	}

	for my $tag (@tags) {
		# skip this if we already got it from the _cmd param in the first slot of the command
		next if $tag eq $skip;
		$params->{$tag} = $request->getParam($tag);
	}

	# validate the parameters using request's convenient functions
	# take this command by command to avoid logical insanity

	# command needs to be one of 6 different things
	if ( $request->paramUndefinedOrNotOneOf($params->{cmd}, ['add', 'delete', 'update', 'enableall', 'disableall', 'defaultvolume' ]) ) {
		$request->setStatusBadParams();
		return;
	}
 
	# required param for 'defaultvolume' is volume
	if ( $params->{cmd} eq 'defaultvolume' && ! defined $params->{volume} ) {
		$request->setStatusBadParams();
		return;
	}

	# required param for 'add' is time, given as numbers only
	# client needs to be given
	# dow needs to be properly formatted
	if ( $params->{cmd} eq 'add' && 
		(
			! defined $params->{time} ||
			$params->{time} =~ /\D/ ||
			! defined $client ||
			( defined $params->{dow} && $params->{dow} !~ /^[0-6](?:,[0-6])*$/ )
		) 
	) {
		$request->setStatusBadParams();
		return;
	}

	# required param for 'delete' is id, and needs a client
	if ( $params->{cmd} eq 'delete' && ( ! $params->{id} || ! $client ) ) {
		$request->setStatusBadParams();
		return;
	}

	# required param for 'update' is id, and needs a client
	if ( $params->{cmd} eq 'update' && ( ! $params->{id} || ! $client ) ) {
		$request->setStatusBadParams();
		return;
	}

	my $alarm;
	
	if ($params->{cmd} eq 'add') {
		$alarm = Slim::Utils::Alarm->new($client);
	}
	elsif ($params->{cmd} eq 'enableall') {
		$prefs->client($client)->alarmsEnabled(1);
	}
	elsif ($params->{cmd} eq 'disableall') {
		$prefs->client($client)->alarmsEnabled(0);
	}
	elsif ($params->{cmd} eq 'defaultvolume') {
		# set the volume
		Slim::Utils::Alarm->defaultVolume($client, $params->{volume});
	}
	else {
		$alarm = Slim::Utils::Alarm->getAlarm($client, $params->{id});
	}

	if (defined $alarm) {

		if ($params->{cmd} eq 'delete') {
			$alarm->delete;
		}

		else {
		
			$alarm->time($params->{time}) if defined $params->{time};
			# the playlisturl param is supported for backwards compatability
			# but url is preferred
			my $url = undef;
			if (defined $params->{url}) {
			  $url = $params->{url};
			} elsif (defined $params->{playlisturl}) {
			  $url = $params->{playlisturl};
			}

			if (defined $url) {
			  if ($url eq '0') {
				# special case for sending 0 for url/playlisturl
				# (needed for proper jive support for selecting "Current Playlist")
				$alarm->playlist(undef);
			  } else {
				$alarm->playlist($url);
			  }
			}

			$alarm->volume($params->{volume}) if defined $params->{volume};
			$alarm->enabled($params->{enabled}) if defined $params->{enabled};
			$alarm->repeat($params->{repeat}) if defined $params->{repeat};

			# handle dow tag, if defined
			if ( defined $params->{dow} ) {
				foreach (0..6) {
					my $set = $params->{dow} =~ /$_/; 
					$alarm->day($_, $set);
				}
			}
	
			# allow for a dowAdd and dowDel param for adding/deleting individual days
			# these directives take precendence over anything that's in dow
			if ( defined $params->{dowAdd} ) {
				$alarm->day($params->{dowAdd}, 1);
			}
			if ( defined $params->{dowDel} ) {
				$alarm->day($params->{dowDel}, 0);
			}
			
			$alarm->save();

		}

		# we add a result for the benefit of the caller (in this case, most
		# likely the CLI).
		$request->addResult('id', $alarm->id);
	}
	
	# indicate the request is done. This enables execute to continue with
	# calling the callback and notifying, etc...
	$request->setStatusDone();
}

sub buttonCommand {
	my $request = shift;

	# check this is the correct command.
	if ($request->isNotCommand([['button']])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# get the parameters
	my $client     = $request->client();
	my $button     = $request->getParam('_buttoncode');
	my $time       = $request->getParam('_time');
	my $orFunction = $request->getParam('_orFunction');
	
	if (!defined $button ) {
		$request->setStatusBadParams();
		return;
	}
	
	# if called from cli, json or comet then store this as the last button as we have bypassed the ir code
	if ($request->source) {
		$client->lastirbutton($button);
	}

	Slim::Hardware::IR::executeButton($client, $button, $time, undef, defined($orFunction) ? $orFunction : 1);
	
	$request->setStatusDone();
}


sub clientConnectCommand {
	my $request = shift;
	my $client  = $request->client();

	if ( $client->hasServ() ) {
		my ($host, $packed);
		$host = $request->getParam('_where');
		
		# Bug 14224, if we get jive/baby/fab4.squeezenetwork.com, use the configured prod SN hostname
		if ( $host =~ /^(?:jive|baby|fab4)/i ) {
			$host = Slim::Networking::SqueezeNetwork->get_server('sn');
		}
		
		if ( $host =~ /^www\.(?:squeezenetwork|mysqueezebox)\.com$/i ) {
			$host = 1;
		}
		elsif ( $host =~ /^www\.test\.(?:squeezenetwork|mysqueezebox)\.com$/i ) {
			$host = 2;
		}
		elsif ( $host eq '0' ) {
			# UE Music Library (used on SN)
		}
		else {
			$host = Slim::Utils::Network::intip($host);
			
			if ( !$host ) {
				$request->setStatusBadParams();
				return;
			}
		}
		
		if ($client->controller()->allPlayers() > 1) {
			my $syncgroupid = $prefs->client($client)->get('syncgroupid') || 0;		
			$packed = pack 'NA10', $host, sprintf('%010d', $syncgroupid);
		} else {
			$packed = pack 'N', $host;
		}
		
		$client->execute([ 'stop' ]);
		
		foreach ($client->controller()->allPlayers()) {
			
			if ($_->hasServ()) {

				$_->sendFrame( serv => \$packed );
				
				# Bug 14400: make sure we do not later accidentally reattach a returning client
				# to a sync-group that is no longer current.
				$prefs->client($_)->remove('syncgroupid');
				
				# Give player time to disconnect
				Slim::Utils::Timers::setTimer($_, time() + 3,
					sub { shift->execute([ 'client', 'forget' ]); }
				);
			} else {
				$log->warn('Cannot switch player to new server as player not capable: ', $_->id());
			}
		}
	}
	
	$request->setStatusDone();
}

# disconnect a player from a remote server and connect to us
# this is done by doing a "connect" call to the remote server
sub disconnectCommand {
	my $request = shift;

	# check this is the correct command.
	if ($request->isNotCommand([['disconnect']])) {
		$request->setStatusBadDispatch();
		return;
	}

	my $remoteClient = $request->getParam('_playerid');
	my $server       = $request->getParam('_from');

	if (! ($remoteClient && $server)) {
		$request->setStatusBadParams();
		return;
	}

	# leave the SN case to its own command
	if ( $server =~ /^www.(?:squeezenetwork|mysqueezebox).com$/i || $server =~ /^www.test.(?:squeezenetwork|mysqueezebox).com$/i ) {

		main::DEBUGLOG && $log->debug("Sending disconnect request for $remoteClient to $server");
		Slim::Control::Request::executeRequest(undef, [ 'squeezenetwork', 'disconnect', $remoteClient ]);
	}

	else {

		$server = Slim::Networking::Discovery::Server::getWebHostAddress($server);

		my $http = Slim::Networking::SimpleAsyncHTTP->new(
			sub {},
			sub { $log->error("Problem disconnecting client $remoteClient from $server: " . shift->error); },
			{ timeout => 10 }
		);

		my $postdata = to_json({
			id     => 1,
			method => 'slim.request',
			params => [ $remoteClient, ['connect', Slim::Utils::Network::hostAddr()] ]
		});

		main::DEBUGLOG && $log->debug("Sending connect request to $server: $postdata");

		$http->get( $server . 'jsonrpc.js', $postdata);

	}
	
	$request->setStatusDone();
}


sub displayCommand {
	my $request = shift;

	# check this is the correct command.
	if ($request->isNotCommand([['display']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get the parameters
	my $client   = $request->client();
	my $line1    = $request->getParam('_line1');
	my $line2    = $request->getParam('_line2');
	my $duration = $request->getParam('_duration');
	my $p4       = $request->getParam('_p4');
	
	if (!defined $line1) {
		$request->setStatusBadParams();
		return;
	}
	
	Slim::Buttons::ScreenSaver::wakeup($client);

	$client->showBriefly({
		'line' => [ $line1, $line2 ],
	}, $duration, $p4);
	
	$request->setStatusDone();
}

sub irCommand {
	my $request = shift;

	# check this is the correct command.
	if ($request->isNotCommand([['ir']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get the parameters
	my $client      = $request->client();
	my $irCodeBytes = $request->getParam('_ircode');
	my $irTime      = $request->getParam('_time');	
	
	if (!defined $irCodeBytes || !defined $irTime ) {
		$request->setStatusBadParams();
		return;
	}
	
	Slim::Hardware::IR::processIR($client, $irCodeBytes, $irTime);
	
	$request->setStatusDone();
}


sub irenableCommand {
	my $request = shift;

	# check this is the correct command.
	if ($request->isNotCommand([['irenable']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get our parameters
	my $client    = $request->client();
	my $newenable = $request->getParam('_newvalue');
	
	# handle toggle
	if (!defined $newenable) {

		$newenable = $client->irenable() ? 0 : 1;
	}

	$client->irenable($newenable);

	$request->setStatusDone();
}

sub mixerCommand {
	my $request = shift;

	# check this is the correct command.
	if ($request->isNotCommand([['mixer'], ['volume', 'muting', 'treble', 'bass', 'pitch', 'stereoxl']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get the parameters
	my $client   = $request->client();
	my $entity   = $request->getRequest(1);
	my $newvalue = $request->getParam('_newvalue');

	my $sequenceNumber = $request->getParam('seq_no');
	if (defined $sequenceNumber) {
		$client->sequenceNumber($sequenceNumber);
	}
	
	my $controllerSequenceId = $request->getParam('controllerSequenceId');
	if (defined $controllerSequenceId) {
		$client->controllerSequenceId($controllerSequenceId);
		$client->controllerSequenceNumber($request->getParam('controllerSequenceNumber'));
	}

	my @buddies;

	# if we're sync'd, get our buddies
	if ($client->isSynced()) {
		@buddies = $client->syncedWith();
	}
	
	if ($entity eq 'muting') {
	
		my $curmute = $prefs->client($client)->get('mute');

		if ( !defined $newvalue || $newvalue eq 'toggle' ) { # toggle
			$newvalue = !$curmute;
		}
		
		if ($newvalue != $curmute) {
			my $vol = $client->volume();
			my $fade;
			
			if ($newvalue == 0) {

				# need to un-mute volume
				main::INFOLOG && $log->info("Unmuting, volume is [$vol]");

				$prefs->client($client)->set('mute', 0);
				$fade = 0.3125;

			} else {

				# need to mute volume
				main::INFOLOG && $log->info("Muting, volume is [$vol]");

				$prefs->client($client)->set('mute', 1);
				$fade = -0.3125;
			}
	
			$client->fade_volume($fade, \&_mixer_mute, [$client]);
	
			for my $eachclient (@buddies) {

				if ($prefs->client($eachclient)->get('syncVolume')) {

					$eachclient->fade_volume($fade, \&_mixer_mute, [$eachclient]);
				}
			}
		}

	} else {

		my $newval;
		my $oldval = $prefs->client($client)->get($entity);

		# if the player is muted and the volume changed, unmute first
		# we're resetting the volume to 0 to mimick the IR behaviour in case of relative changes
		if ($entity eq 'volume' && $prefs->client($client)->get('mute')) {
			$prefs->client($client)->set('mute', 0);
			$oldval = 0;
		}

		if ($newvalue =~ /^[\+\-]/) {
			$newval = $oldval + $newvalue;
		} else {
			$newval = $newvalue;
		}

		if ($entity eq 'volume' && defined $client->tempVolume && $client->tempVolume == 0 && $oldval > 0) {
			# only set pref as volume is temporarily set to 0
			$prefs->client($client)->set('volume', $newval) if ($newval <= $client->maxVolume);
		} else {
			# change current setting - this will also set the pref
			$newval = $client->$entity($newval);
		}

		for my $eachclient (@buddies) {
			if ($prefs->client($eachclient)->get('syncVolume')) {
				$prefs->client($eachclient)->set($entity, $newval);
				$eachclient->$entity($newval);
				$eachclient->mixerDisplay('volume') if $entity eq 'volume';
			}
		}
	}
		
	if (defined $controllerSequenceId) {
		$client->controllerSequenceId(undef);
		$client->controllerSequenceNumber(undef);
	}

	$request->setStatusDone();
}


sub nameCommand {
	my $request = shift;

	if ($request->isNotCommand([['name']])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# get our parameters
	my $client = $request->client();
	my $newValue = $request->getParam('_newvalue');

	if (!defined $newValue || !defined $client) {
		$request->setStatusBadParams();
		return;
	}	

	if ($newValue ne "0") {
		main::DEBUGLOG && $log->debug("PLAYERNAMECHANGE: " . $newValue);
		$prefs->client($client)->set('playername', $newValue);
		# refresh Jive menu
		Slim::Control::LocalPlayers::Jive::playerSettingsMenu($client);
		Slim::Control::LocalPlayers::Jive::playerPower($client);
	}

	$request->setStatusDone();
}


sub playcontrolCommand {
	my $request = shift;

	# check this is the correct command.
	# "mode" is deprecated
	if ($request->isNotCommand([['play', 'stop', 'pause']]) &&
		$request->isNotCommand([['mode'], ['play', 'pause', 'stop']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get the parameters
	my $client = $request->client();
	my $cmd    = $request->getRequest(0);
	my $param  = $request->getRequest(1);
	my $newvalue = $request->getParam('_newvalue');
	my $fadeIn = $request->getParam('_fadein');
	my $suppressShowBriefly = $request->getParam('_suppressShowBriefly');
	
	# which state are we in?
	my $curmode = Slim::Player::Source::playmode($client);
	
	# which state do we want to go to?
	my $wantmode = $cmd;
	
	# the "mode" command is deprecated, please do not use or fix
	if ($cmd eq 'mode') {
		
		# we want to go to $param if the command is mode
		$wantmode = $param;
		# and for pause we want 1
		$newvalue = 1;
	}
	
	if ($cmd eq 'pause') {
		
		# pause 1, pause 0 and pause (toggle) are all supported, figure out which
		# one we want...
		if (defined $newvalue) {
			$wantmode = $newvalue ? 'pause' : 'play';
		} else {
			# Toggle, or start upon a pause command if player is currently in stop mode
			$wantmode = ($curmode eq 'pause' || $curmode eq 'stop') ? 'play' : 'pause';
		}
	}
	# Adjust for resume: if we're paused and asked to play, we resume
	$wantmode = 'resume' if ($curmode eq 'pause' && $wantmode eq 'play');

	# Adjust for pause: can only do it from play
	if ($wantmode eq 'pause') {

		# default to doing nothing...
		$wantmode = $curmode;
		
		# pause only from play
		$wantmode = 'pause' if $curmode eq 'play';
	}			
	
	# do we need to do anything?
	if ($curmode ne $wantmode) {
		
		if ( $wantmode eq 'play' ) {
			# Bug 6813, 'play' from CLI needs to work the same as IR play button, by going
			# through playlist jump - this will include a showBriefly to give feedback
			my $index = Slim::Player::Source::playingSongIndex($client);
			
			$client->execute(['playlist', 'jump', $index, $fadeIn]);
		}
		else {
			# set new playmode
			Slim::Player::Source::playmode($client, $wantmode, undef, undef, $fadeIn);
			
			# give user feedback of new mode and current song
			if ($client->isPlayer()) {
				my $parts = $client->currentSongLines({ suppressDisplay => (main::IP3K ? Slim::Buttons::Common::suppressStatus($client) : 0) });
				if ($suppressShowBriefly) {
					$parts->{jive} = undef;
				}
				$client->showBriefly($parts) if $parts;
			}
		}
	}
		
	$request->setStatusDone();
}


sub playlistClearCommand {
	my $request = shift;

	# check this is the correct command.
	if ($request->isNotCommand([['playlist'], ['clear']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get the parameters
	my $client = $request->client();

	Slim::Player::Playlist::stopAndClear($client);

	# called by currentPlaylistUpdateTime below
	# $client->currentPlaylistChangeTime(Time::HiRes::time());
	
	$client->currentPlaylistUpdateTime(Time::HiRes::time());
	
	# The above changes the playlist but I am not sure this is ever
	# executed, or even if it should be
	Slim::Player::Playlist::refreshPlaylist($client) if $client->currentPlaylistModified();
	
	$request->setStatusDone();
}


sub playlistDeleteCommand {
	my $request = shift;

	# check this is the correct command.
	if ($request->isNotCommand([['playlist'], ['delete']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get the parameters
	my $client = $request->client();
	my $index  = $request->getParam('_index');;
	
	if (!defined $index) {
		$request->setStatusBadParams();
		return;
	}

	Slim::Player::Playlist::removeTrack($client, $index);

	$client->currentPlaylistModified(1);
	#$client->currentPlaylistChangeTime(Time::HiRes::time());
	$client->currentPlaylistUpdateTime(Time::HiRes::time());
	Slim::Player::Playlist::refreshPlaylist($client);
	
	$request->setStatusDone();
}


sub playlistDeleteitemCommand {
	my $request = shift;

	# check this is the correct command.
	if ($request->isNotCommand([['playlist'], ['deleteitem']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get the parameters
	my $client = $request->client();
	my $item   = $request->getParam('_item');;
	
	if (!$item) {
		$request->setStatusBadParams();
		return;
	}

	# This used to update $p2; anybody depending on this behaviour needs
	# to be changed to used the returned result (commented below)
	my $contents = [];
	my $absitem  = blessed($item) ? $item->url : $item;

	if (!Slim::Music::Info::isList($absitem)) {

		Slim::Player::Playlist::removeMultipleTracks($client, [$absitem]);

	} elsif (Slim::Music::Info::isDir($absitem)) {
		
		Slim::Utils::Scanner->scanPathOrURL({
			'url'      => Slim::Utils::Misc::pathFromFileURL($absitem),
			'listRef'  => \@{$contents},
			'client'   => $client,
			'callback' => sub {
				my $foundItems = shift;
				
				Slim::Player::Playlist::removeMultipleTracks($client, $foundItems);
			},
		});
	
	} else {

		my $playlist = Slim::Schema->objectForUrl({ 'url' => $item, playlist => 1 });

		if ($playlist) {
			$contents = [ map { $_->url } $playlist->tracks ];
		}

		if (!scalar @$contents) {

			my $fh = undef;

			if (!open($fh, Slim::Utils::Misc::pathFromFileURL($absitem))) {

				logError("Couldn't open playlist file $absitem : $!");

				$fh = undef;

			} else {

				$contents = [Slim::Formats::Playlists->parseList($absitem, $fh, dirname($absitem))];
			}
		}

		if (scalar @$contents) {
			Slim::Player::Playlist::removeMultipleTracks($client, $contents);
		}
	}

	$contents = [];

	$client->currentPlaylistModified(1);
	#$client->currentPlaylistChangeTime(Time::HiRes::time());
	$client->currentPlaylistUpdateTime(Time::HiRes::time());
	Slim::Player::Playlist::refreshPlaylist($client);
	
	$request->setStatusDone();
}


sub playlistJumpCommand {
	my $request = shift;

	# check this is the correct command.
	if ($request->isNotCommand([['playlist'], ['jump', 'index']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get the parameters
	my $client = $request->client();
	my $index  = $request->getParam('_index');
	my $fadeIn = $request->getParam('_fadein');
	my $noplay = $request->getParam('_noplay');
	my $seekdata = $request->getParam('_seekdata');
	
	my $songcount = Slim::Player::Playlist::count($client) || return;
	
	my $newIndex = 0;
	my $isStopped = $client->isStopped();
	
	if (!$client->power()) {
		$client->execute([ 'power', 1, 1 ]);
	}

	my $showStatus = sub {
		my $jiveIconStyle = shift || undef;
		if ($client->isPlayer()) {
			my $parts = $client->currentSongLines({
					suppressDisplay => (main::IP3K ? Slim::Buttons::Common::suppressStatus($client) : 0),
					jiveIconStyle => $jiveIconStyle,
				});
				
			# awy: We used to set $parts->{'jive'}->{'duration'} = 10000 here in order to
			# ensure that the new track title is pushed to the first line of the display
			# and stays there until a new playerStatus arrives. This can take quite a
			# long time under some circumstances, such as with slow servers. However,
			# setting the delay here affected both the duration of the new title on the
			# display and that of the the Play pop-up icon if the command was invoked via IR.
			# Having the popup hang around for 10s can be irritating (bug 17758). Given that
			# the player has control of title change itself, it can set a long duration
			# on just that element and use the default show-briefly duration for the popup.
			
			$client->showBriefly($parts, { duration => 2 }) if $parts;
			Slim::Buttons::Common::syncPeriodicUpdates($client, Time::HiRes::time() + 0.1) if main::IP3K;
		}
	};

	# Is this a relative jump, etc.
	if ( defined $index && $index =~ /[+-]/ ) {
		
		if (!$isStopped) {
			my $handler = $client->playingSong()->currentTrackHandler();
			
			if ( ($songcount == 1 && $index eq '-1') || $index eq '+0' ) {
				# User is trying to restart the current track
				$client->controller()->jumpToTime(0, 1);
				$showStatus->('rew');
				$request->setStatusDone();
				return;	
			} elsif ($index eq '+1') {
				# User is trying to skip to the next track
				$client->controller()->skip();
				$showStatus->('fwd');
				$request->setStatusDone();
				return;	
			}
			
		}
		
		$newIndex = Slim::Player::Source::playingSongIndex($client) + $index;
		main::INFOLOG && $log->info("Jumping by $index");
		
		# Handle skip in repeat mode
		if ( $newIndex >= $songcount ) {
			# play the next song and start over if necessary
			if (Slim::Player::Playlist::shuffle($client) && 
				Slim::Player::Playlist::repeat($client) == 2 &&
				$prefs->get('reshuffleOnRepeat')) {

				Slim::Player::Playlist::reshuffle($client, 1);
			}
		}
		
	} else {
		$newIndex = $index if defined $index;
		main::INFOLOG && $log->info("Jumping to $newIndex");
	}
	
	# Check for wrap-around
	if ($newIndex >= $songcount) {
		$newIndex %=  $songcount;
	} elsif ($newIndex < 0) {
		$newIndex =  ($newIndex + $songcount) % $songcount;
	}
	
	if ($noplay && $isStopped) {
		$client->controller()->resetSongqueue($newIndex);
	} else {
		main::INFOLOG && $log->info("playing $newIndex");
		$client->controller()->play($newIndex, $seekdata, undef, $fadeIn);
	}	

	# Does the above change the playlist?
	Slim::Player::Playlist::refreshPlaylist($client) if $client->currentPlaylistModified();

	# if we're jumping +1/-1 in the index let squeezeplay know this showBriefly is to be styled accordingly
	my $jiveIconStyle = undef;
	if ($index eq '-1') {
		$jiveIconStyle = 'rew';
	} elsif ($index eq '+1')  {
		$jiveIconStyle = 'fwd';
	}
	$showStatus->($jiveIconStyle);
		
	$request->setStatusDone();
}

sub playlistMoveCommand {
	my $request = shift;

	# check this is the correct command.
	if ($request->isNotCommand([['playlist'], ['move']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get the parameters
	my $client     = $request->client();
	my $fromindex  = $request->getParam('_fromindex');;
	my $toindex    = $request->getParam('_toindex');;
	
	if (!defined $fromindex || !defined $toindex) {
		$request->setStatusBadParams();
		return;
	}

	Slim::Player::Playlist::moveSong($client, $fromindex, $toindex);
	$client->currentPlaylistModified(1);
	#$client->currentPlaylistChangeTime(Time::HiRes::time());
	$client->currentPlaylistUpdateTime(Time::HiRes::time());
	
	Slim::Player::Playlist::refreshPlaylist($client);
	
	$request->setStatusDone();
}


sub playlistRepeatCommand {
	my $request = shift;

	# check this is the correct command.
	if ($request->isNotCommand([['playlist'], ['repeat']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get the parameters
	my $client   = $request->client();
	my $newvalue = $request->getParam('_newvalue');
	
	if (!defined $newvalue) {
		# original code: (Slim::Player::Playlist::repeat($client) + 1) % 3
		$newvalue = (1,2,0)[Slim::Player::Playlist::repeat($client)];
	}
	
	Slim::Player::Playlist::repeat($client, $newvalue);
	
	$request->setStatusDone();
}


sub playlistSaveCommand {
	my $request = shift;

	# check this is the correct command.
	if ($request->isNotCommand([['playlist'], ['save']])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# can't do much without playlistdir!
	if (!Slim::Utils::Misc::getPlaylistDir()) {
		$request->setStatusBadConfig();
		return;
	}

	# get the parameters
	my $client = $request->client();
	my $title  = $request->getParam('_title');
	my $silent = $request->getParam('silent') || 0;
	my $titlesort = Slim::Utils::Text::ignoreCaseArticles($title);

	$title = Slim::Utils::Misc::cleanupFilename($title);


	my $playlistObj = Slim::Schema->updateOrCreate({

		'url' => Slim::Utils::Misc::fileURLFromPath(
			catfile( Slim::Utils::Misc::getPlaylistDir(), Slim::Utils::Unicode::encode_locale($title) . '.m3u')
		),
		'playlist' => 1,
		'attributes' => {
			'TITLE' => $title,
			'CT'    => 'ssp',
		},
	});

	my $annotatedList = [];

	if ($prefs->get('saveShuffled')) {

		for my $shuffleitem (@{Slim::Player::Playlist::shuffleList($client)}) {
			push @$annotatedList, Slim::Player::Playlist::song($client, $shuffleitem, 0, 0);
		}
				
	} else {

		$annotatedList = Slim::Player::Playlist::playList($client);
	}

	$playlistObj->set_column('titlesort', $titlesort);
	$playlistObj->set_column('titlesearch', $titlesort);
	$playlistObj->setTracks($annotatedList);
	$playlistObj->update;

	Slim::Schema->forceCommit;

	if (!defined Slim::Player::Playlist::scheduleWriteOfPlaylist($client, $playlistObj)) {
		$request->addResult('writeError', 1);
	}
	
	$request->addResult('__playlist_id', $playlistObj->id);

	if ( ! $silent ) {
		$client->showBriefly({
			'jive' => {
				'type'    => 'popupplay',
				'text'    => [ $client->string('SAVED_THIS_PLAYLIST_AS', $title) ],
			}
		});
	}

	$request->setStatusDone();
}

sub playlistShuffleCommand {
	my $request = shift;

	# check this is the correct command.
	if ($request->isNotCommand([['playlist'], ['shuffle']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get the parameters
	my $client   = $request->client();
	my $newvalue = $request->getParam('_newvalue');
	
	if (!defined $newvalue) {
		$newvalue = (1,2,0)[Slim::Player::Playlist::shuffle($client)];
	}
	
	Slim::Player::Playlist::shuffle($client, $newvalue);
	Slim::Player::Playlist::reshuffle($client);
	#$client->currentPlaylistChangeTime(Time::HiRes::time());
	$client->currentPlaylistUpdateTime(Time::HiRes::time());
	
	# Does the above change the playlist?
	Slim::Player::Playlist::refreshPlaylist($client) if $client->currentPlaylistModified();
	
	$request->setStatusDone();
}


sub playlistPreviewCommand {
	my $request = shift;
	# check this is the correct command.
	if ( $request->isNotCommand( [ ['playlist'], ['preview' ] ]) ) {
		$request->setStatusBadDispatch();
		return;
	}

	my $client   = $request->client();
	my $cmd      = $request->getParam('cmd'); 
	my $url      = $request->getParam('url'); 
	my $title    = $request->getParam('title') || '';
	my $fadeIn   = $request->getParam('fadein') ? $request->getParam('fadein') : undef;
	
	# if we have a cmd of 'stop', load the most recent playlist (which will clear the preview)
	if ($cmd eq 'stop') {
		# stop and clear the current tone
		Slim::Player::Playlist::stopAndClear($client);

		my $filename = _getPreviewPlaylistName($client);
		main::INFOLOG && $log->info("loading ", $filename, " to resume previous playlist");

		# load mostrecent.m3u and jump to the previously playing track, but don't play
		$client->execute( [ 'playlist', 'resume', $filename, '', 'noplay:1', 'wipePlaylist:1' ]);

	} else {

		# if we're not stopping, we're previewing. first check for correct params
		if ( ! defined($url) ) {
			$request->setStatusBadDispatch();
			return;
		}

		my $filename = _getPreviewPlaylistName($client);
		main::INFOLOG && $log->info("saving current playlist as ", $filename);
                $client->execute( ['playlist', 'save', $filename, 'silent:1' ] );

		main::INFOLOG && $log->info("queuing up ", $title, " for preview");
		$client->execute( ['playlist', 'play', $url, $title, $fadeIn ] );
        
	}

	$request->setStatusDone();
	
}

sub _getPreviewPlaylistName {
	my $client = shift;
	my $filename = "tempplaylist_" . $client->id();
	$filename =~ s/://g;
	return $filename;
}


sub playlistZapCommand {
	my $request = shift;

	# check this is the correct command.
	if ($request->isNotCommand([['playlist'], ['zap']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get the parameters
	my $client   = $request->client();
	my $index    = $request->getParam('_index');;
	
	my $zapped   = $client->string('ZAPPED_SONGS');
	my $zapindex = defined $index ? $index : Slim::Player::Source::playingSongIndex($client);
	my $zapsong  = Slim::Player::Playlist::song($client, $zapindex);

	#  Remove from current playlist
	if (Slim::Player::Playlist::count($client) > 0) {

		# Call ourselves.
		Slim::Control::Request::executeRequest($client, ["playlist", "delete", $zapindex]);
	}

	my $playlistObj = Slim::Schema->updateOrCreate({
		'url'        => Slim::Utils::Misc::fileURLFromPath(
			catfile( Slim::Utils::Misc::getPlaylistDir(), $zapped . '.m3u')
		),
		'playlist'   => 1,

		'attributes' => {
			'TITLE' => $zapped,
			'CT'    => 'ssp',
		},
	});

	$playlistObj->appendTracks([ $zapsong ]);
	$playlistObj->update;

	Slim::Player::Playlist::scheduleWriteOfPlaylist($client, $playlistObj);

	$client->currentPlaylistModified(1);
	$client->currentPlaylistUpdateTime(Time::HiRes::time());
	Slim::Player::Playlist::refreshPlaylist($client);
	
	$request->setStatusDone();
}


sub powerCommand {
	my $request = shift;

	# check this is the correct command.
	if ($request->isNotCommand([['power']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get our parameters
	my $client   = $request->client();
	my $newpower = $request->getParam('_newvalue');
	my $noplay   = $request->getParam('_noplay');
	my $sequenceNumber = $request->getParam('seq_no');
	if (defined $sequenceNumber) {
		$client->sequenceNumber($sequenceNumber)
	}

	# handle toggle
	if (!defined $newpower) {
		$newpower = $client->power() ? 0 : 1;
	}

	if ($newpower == $client->power()) {return;}
	
	# handle sync'd players
	if ($client->isSynced()) {

		my @buddies = $client->syncedWith();
		
		for my $eachclient (@buddies) {
			$eachclient->power($newpower, 1) if $prefs->client($eachclient)->get('syncPower');
			
			# send an update for Jive player power menu
			Slim::Control::LocalPlayers::Jive::playerPower($eachclient);
			
		}
	}

	$client->power($newpower, $noplay);

	# Powering off cancels sleep...
	if ($newpower eq "0") {
		Slim::Utils::Timers::killTimers($client, \&_sleepStartFade);
		Slim::Utils::Timers::killTimers($client, \&_sleepPowerOff);
		$client->sleepTime(0);
		$client->currentSleepTime(0);
	}
		
	# send an update for Jive player power menu
	Slim::Control::LocalPlayers::Jive::playerPower($client);

	$request->setStatusDone();
}


sub setSNCredentialsCommand {
	my $request = shift;

	if ($request->isNotCommand([['setsncredentials']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get our parameters
	my $username = $request->getParam('_username');
	my $password = $request->getParam('_password');
	my $sync     = $request->getParam('sync');
	my $client   = $request->client;
	
	# Sync can be toggled without username/password
	if (defined $sync ) {
		$prefs->set('sn_sync', $sync);
	
		Slim::Networking::SqueezeNetwork::PrefSync->shutdown();
		if ( $sync ) {
			Slim::Networking::SqueezeNetwork::PrefSync->init();
		}
	}

	$password = sha1_base64($password);
	
	# Verify username/password
	if ($username) {
	
		$request->setStatusProcessing();

		Slim::Networking::SqueezeNetwork->login(
			username => $username,
			password => $password,
			client   => $client,
			cb       => sub {
				$request->addResult('validated', 1);
				$request->addResult('warning', $request->cstring('SETUP_SN_VALID_LOGIN'));
	
				# Shut down all SN activity
				Slim::Networking::SqueezeNetwork->shutdown();
			
				$prefs->set('sn_email', $username);
				$prefs->set('sn_password_sha', $password);
				
				# Start it up again if the user enabled it
				Slim::Networking::SqueezeNetwork->init();
	
				$request->setStatusDone();
			},
			ecb      => sub {
				$request->addResult('validated', 0);
				$request->addResult('warning', $request->cstring('SETUP_SN_INVALID_LOGIN'));
	
				$request->setStatusDone();
			},
		);
	}
	
	# stop SN integration if either mail or password is undefined
	else {
		$request->addResult('validated', 1);
		$prefs->set('sn_email', '');
		$prefs->set('sn_password_sha', '');
		Slim::Networking::SqueezeNetwork->shutdown();
	}
}


sub showCommand {
	my $request = shift;

	# check this is the correct command.
	if ($request->isNotCommand([['show']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get the parameters
	my $client     = $request->client();
	my $line1      = $request->getParam('line1');
	my $line2      = $request->getParam('line2');
	my $duration   = $request->getParam('duration');
	my $brightness = $request->getParam('brightness');
	my $font       = $request->getParam('font');
	my $centered   = $request->getParam('centered');
	my $screen     = $request->getParam('screen');
	
	if (!defined $line1 && !defined $line2) {
		$request->setStatusBadParams();
		return;
	}

	$brightness = $client->maxBrightness() unless defined($brightness);
	$duration = 3 unless defined($duration);

	my $hash = {};
	
	if ($centered) {
		$hash->{'center'} = [$line1, $line2];
	}
	else {
		$hash->{'line'} = [$line1, $line2];
	}
	
	if ($font eq 'huge') {
		$hash->{'fonts'} = {
			'graphic-320x32' => 'full',
			'graphic-160x32' => 'full_n',
			'graphic-280x16' => 'huge',
			'text'           => 1,
		};		
	}
	else {
		$hash->{'fonts'} = {
			'graphic-320x32' => 'standard',
			'graphic-160x32' => 'standard_n',
			'graphic-280x16' => 'medium',
			'text'           => 2,
		};
	}

	if (defined $screen && $screen == 2) {
		$hash = { 'screen2' => $hash };
	}

	# get out of the screensaver if one is active
	# we'll get back to it as soon as done (automatically)
	if (Slim::Buttons::Common::mode($client) =~ /screensaver/i) {
		Slim::Buttons::Common::popMode($client);
	}

	# call showBriefly for the magic!
	$client->showBriefly($hash, 
		$duration, 
		0,  # line2 is single line
		1,  # block updates
		1,  # scroll to end
		$brightness,
		\&Slim::Control::Commands::_showCommand_done,
		{ 'request' => $request }
	);

	# we're not done yet
	$request->setStatusProcessing();
}

sub sleepCommand {
	my $request = shift;

	# check this is the correct command.
	if ($request->isNotCommand([['sleep']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get our parameters
	my $client        = $request->client();
	my $will_sleep_in = $request->getParam('_newvalue');
	
	if (!defined $will_sleep_in) {
		$request->setStatusBadParams();
		return;
	}


	# Cancel the timers, we'll set them back if needed
	Slim::Utils::Timers::killTimers($client, \&_sleepStartFade);
	Slim::Utils::Timers::killTimers($client, \&_sleepPowerOff);
		
	# if we have a sleep duration
	if ($will_sleep_in > 0) {
	
		my $now = Time::HiRes::time();
		
		# this is when we want to power off
		my $offTime = $now + $will_sleep_in;
	
		# this is the time we have to fade
		my $fadeDuration = $offTime - $now - 1;
		# fade for the last 60 seconds max
		$fadeDuration = 60 if ($fadeDuration > 60); 

		# time at which we start fading
		my $fadeTime = $offTime - $fadeDuration;
			
		# set our timers
		Slim::Utils::Timers::setTimer($client, $offTime, \&_sleepPowerOff);
		Slim::Utils::Timers::setTimer($client, $fadeTime, 
			\&_sleepStartFade, $fadeDuration);

		$client->sleepTime($offTime);
		# for some reason this is minutes...
		$client->currentSleepTime($will_sleep_in / 60); 

		my $will_sleep_in_minutes = int( $will_sleep_in / 60 );
		# only show a showBriefly if $will_sleep_in_minutes has a style on SP side
		my $validSleepStyles = {
			'15' => 1,
			'30' => 1,
			'45' => 1,
			'60' => 1,
			'90' => 1,
		};
		if ($validSleepStyles->{$will_sleep_in_minutes}) {
			$client->showBriefly({
				'jive' => { 
					'type'    => 'icon',
					'style'   => 'sleep_' . $will_sleep_in_minutes,
					'text'    => [ $will_sleep_in_minutes ],
				}
			});
		} else {
			my $sleepTime = $client->prettySleepTime;
                	$client->showBriefly( {
				'jive' =>
					{
						'type'    => 'popupplay',
						'text'    => [ $sleepTime ],
					},
			});
		}
		
	} else {

		# finish canceling any sleep in progress
		$client->sleepTime(0);
		$client->currentSleepTime(0);

		$client->showBriefly({
			'jive' => { 
				'type'    => 'icon',
				'style'	  => 'sleep_cancel',
				'text'    => [ '' ],
			}
		});
	
	}


	$request->setStatusDone();
}


sub syncCommand {
	my $request = shift;

	# check this is the correct command.
	if ($request->isNotCommand([['sync']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get our parameters
	my $client   = $request->client();
	my $newbuddy = $request->getParam('_indexid-');
	my $noRestart= $request->getParam('noRestart');
	
	if (!defined $newbuddy) {
		$request->setStatusBadParams();
		return;
	}
	
	if ($newbuddy eq '-') {
	
		$client->controller()->unsync($client);
		
	} else {

		# try an ID
		my $buddy = Slim::Player::Client::getClient($newbuddy);

		# try a player index
		if (!defined $buddy) {
			my @clients = Slim::Player::Client::clients();
			if (defined $clients[$newbuddy]) {
				$buddy = $clients[$newbuddy];
			}
		}
		
		$client->controller()->sync($buddy, $noRestart) if defined $buddy;
	}
	
	$request->setStatusDone();
}


sub timeCommand {
	my $request = shift;

	# check this is the correct command.
	# "gototime" is deprecated
	if ($request->isNotCommand([['time', 'gototime']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get our parameters
	my $client  = $request->client();
	my $newtime = $request->getParam('_newvalue');
	
	if (!defined $newtime) {
		$request->setStatusBadParams();
		return;
	}
	
	Slim::Player::Source::gototime($client, $newtime);
	
	$request->setStatusDone();
}


################################################################################
# Helper functions
################################################################################

sub _sleepStartFade {
	my $client = shift;
	my $fadeDuration = shift;
	
	if ($client->isPlayer()) {
		$client->fade_volume(-$fadeDuration);
	}
}

sub _sleepPowerOff {
	my $client = shift;

	$client->sleepTime(0);
	$client->currentSleepTime(0);
	
	Slim::Control::Request::executeRequest($client, ['stop']);
	Slim::Control::Request::executeRequest($client, ['power', 0]);
}


sub _mixer_mute {
	my $client = shift;

	$client->mute();
}

sub _showCommand_done {
	my $args = shift;

	my $request = $args->{'request'};
	my $client = $request->client();
	
	# now we're done!
	$request->setStatusDone();
}



=head1 SEE ALSO

L<Slim::Control::Request.pm>

=cut

1;

__END__
