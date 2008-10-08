package Slim::Control::Commands;

# $Id: Commands.pm 5121 2005-11-09 17:07:36Z dsully $
#
# SqueezeCenter Copyright 2001-2007 Logitech.
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

Implements most SqueezeCenter commands and is designed to be exclusively called
through Request.pm and the mechanisms it defines.

The code for the "alarm" command is heavily commented and corresponds to a
"model" synchronous command.  Check CLI handling code in the Shoutcast plugin
for an asynchronous command.

=cut

use strict;

use Scalar::Util qw(blessed);
use File::Spec::Functions qw(catfile);
use File::Basename qw(basename);
use Net::IP;
use JSON::XS::VersionOneAndTwo;

use Slim::Utils::Alarm;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Scanner;
use Slim::Utils::Prefs;

my $log = logger('control.command');

my $prefs = preferences('server');


sub abortScanCommand {
	my $request = shift;

	Slim::Music::Import->abortScan();
	
	$request->setStatusDone();
}


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
		my ( $tag, $val ) = split /:/, $cmd;
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
		$client->showBriefly({
			'jive' => { 
				'type'    => 'popupplay',
				'text'    => [ $client->string('ALARM_SAVING') ],
			}
		});
	}
	elsif ($params->{cmd} eq 'enableall') {
		$prefs->client($client)->alarmsEnabled(1);
		$client->showBriefly({
			'jive' => { 
				'type'    => 'popupplay',
				# FIXME: this string will get translated post-7.2 release
				# 'text'    => [ $client->string('ALARM_ALL_ALARMS_ENABLED') ],
				'text'    => [ $client->string('ENABLED') ],
			}
		});

	}
	elsif ($params->{cmd} eq 'disableall') {
		$prefs->client($client)->alarmsEnabled(0);
		$client->showBriefly({
			'jive' => { 
				'type'    => 'popupplay',
				# FIXME: this string will get translated post-7.2 release
				# 'text'    => [ $client->string('ALARM_ALL_ALARMS_DISABLED') ],
				'text'    => [ $client->string('DISABLED') ],
			}
		});
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
			$client->showBriefly({
				'jive' => { 
					'type'    => 'popupplay',
					'text'    => [ $client->string('ALARM_DELETING') ],
				}
			});
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
		
		if ( $host =~ /^www.squeezenetwork.com$/i ) {
			$host = 1;
		}
		elsif ( $host =~ /^www.test.squeezenetwork.com$/i ) {
			$host = 2;
		}
		elsif ( $host eq '0' ) {
			# SqueezeCenter (used on SN)
		}
		else {
			my $ip = Net::IP->new($host);
			if ( !defined $ip ) {
				$request->setStatusBadParams();
				return;
			}
			
			$host = $ip->intip;
		}
		
		$packed = pack 'N', $host;
		
		$client->execute([ 'stop' ]);
		
		$client->sendFrame( serv => \$packed );
		
		if ( main::SLIM_SERVICE ) {
			# Bug 7973, forget client immediately
			$client->forgetClient;
		}
		else {
			$client->execute([ 'client', 'forget' ]);
		}
	}
	
	$request->setStatusDone();
}

sub clientForgetCommand {
	my $request = shift;

	# check this is the correct command. Syntax approved by Dean himself!
	if ($request->isNotCommand([['client'], ['forget']])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# get the parameters
	my $client = $request->client();
	
	# Bug 6508
	# Can have a timing race with client reconnecting before this command get executed
	if ($client->connected()) {
		$log->info($client->id . ': not forgetting as connected again');
		return;
	}
	
	$client->controller()->playerInactive($client);

	$client->forgetClient();
	
	$request->setStatusDone();
}


sub debugCommand {
	my $request = shift;

	# check this is the correct command. Syntax approved by Dean himself!
	if ($request->isNotCommand([['debug']])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# get the parameters
	my $category = $request->getParam('_debugflag');
	my $newValue = $request->getParam('_newvalue');

	if ( !defined $category || !Slim::Utils::Log->isValidCategory($category) ) {

		$request->setStatusBadParams();
		return;
	}
	
	my $ret = Slim::Utils::Log->setLogLevelForCategory($category, $newValue);

	if ($ret == 0) {

		$request->setStatusBadParams();
		return;
	}

	# If the above setLogLevelForCategory has returned true, we need to reinitialize.
	if ($ret == 1) {

		Slim::Utils::Log->reInit;
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
	if ( $server =~ /^www.squeezenetwork.com$/i || $server =~ /^www.test.squeezenetwork.com$/i ) {

		$log->debug("Sending disconnect request for $remoteClient to $server");
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

		$log->debug("Sending connect request to $server: $postdata");

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

	my @buddies;

	# if we're sync'd, get our buddies
	if ($client->isSynced()) {
		@buddies = $client->syncedWith();
	}
	
	if ($entity eq 'muting') {
	
		my $curmute = $prefs->client($client)->get('mute');
	
		if (!defined $newvalue) { # toggle
			$newvalue = !$curmute;
		}
		
		if ($newvalue != $curmute) {
			my $vol = $client->volume();
			my $fade;
			
			if ($newvalue == 0) {

				# need to un-mute volume
				$log->info("Unmuting, volume is [$vol]");

				$prefs->client($client)->set('mute', 0);
				$fade = 0.3125;

			} else {

				# need to mute volume
				$log->info("Muting, volume is [$vol]");

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
		$log->debug("PLAYERNAMECHANGE: " . $newValue);
		$prefs->client($client)->set('playername', $newValue);
		# refresh Jive menu
		Slim::Control::Jive::playerSettingsMenu($client);
		Slim::Control::Jive::playerPower($client);
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
			$client->execute([ 'playlist', 'jump', $index ]);
		}
		else {
			# set new playmode
			Slim::Player::Source::playmode($client, $wantmode);
			
			# give user feedback of new mode and current song
			if ($client->isPlayer()) {
				my $parts = $client->currentSongLines({ suppressDisplay => Slim::Buttons::Common::suppressStatus($client) });
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

	Slim::Player::Playlist::clear($client);
	Slim::Player::Source::playmode($client, "stop");

	my $playlistObj = Slim::Music::Info::playlistForClient($client);

	if (blessed($playlistObj)) {

		$playlistObj->playlist_tracks->delete;
		$playlistObj->update;
	}

	# called by Slim::Player::Playlist::clear above
	# $client->currentPlaylist(undef);
	
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

	my $song = Slim::Player::Playlist::song($client, $index);

	# show feedback if this action came from jive cometd session
	if ($request->source && $request->source =~ /\/slim\/request/) {
		$client->showBriefly({
			'jive' => { 
				'type'    => 'song',
				'text'    => [ $client->string('JIVE_POPUP_REMOVING_FROM_PLAYLIST', $song->title) ],
				'icon-id' => $song->remote ? 0 : ($song->album->artwork || 0) + 0,
			}
		});
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

		my $playlist = Slim::Schema->rs('Playlist')->objectForUrl({ 'url' => $item });

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
	my $noplay = $request->getParam('_noplay');
	my $seekdata = $request->getParam('_seekdata');
	
	my $songcount = Slim::Player::Playlist::count($client) || return;
	
	my $newIndex = 0;
	my $isStopped = $client->isStopped();
	
	if (!$client->power()) {
		$client->execute([ 'power', 1, 1 ]);
	}

	# Is this a relative jump, etc.
	if ( defined $index && $index =~ /[+-]/ ) {
		
		if (!$isStopped) {
			my $handler = $client->playingSong()->currentTrackHandler();
			my $url     = $client->playingSong()->currentTrack()->url();

			if ( ($songcount == 1 && $index eq '-1') || $index eq '+0' ) {
				# User is trying to restart the current track
				$client->controller()->jumpToTime(0, 1);
				$request->setStatusDone();
				return;	
			} elsif ($index eq '+1') {
				# User is trying to skip to the next track
				$client->controller()->skip();		
				$request->setStatusDone();
				return;	
			}
			
		}
		
		$newIndex = Slim::Player::Source::playingSongIndex($client) + $index;
		$log->info("Jumping by $index");
		
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
		$log->info("Jumping to $index");
	}
	
	# Check for wrap-around
	if ($newIndex >= $songcount) {
		$newIndex %=  $songcount;
	} elsif ($newIndex < 0) {
		$newIndex =  ($newIndex + $songcount) % $songcount;
	}
	
	if ($noplay && $isStopped) {
		Slim::Player::Source::streamingSongIndex($client, $newIndex, 1);
	} else {
		$log->info("playing $index");
		$client->controller()->play($newIndex, $seekdata);
	}	

	# Does the above change the playlist?
	Slim::Player::Playlist::refreshPlaylist($client) if $client->currentPlaylistModified();

	Slim::Buttons::Common::syncPeriodicUpdates($client, Time::HiRes::time() + 0.1);

# should be done by StreamingController
#	# update the display unless suppressed
#	if ($client->isPlayer()) {
#		my $parts = $client->currentSongLines(undef, Slim::Buttons::Common::suppressStatus($client), 1);
#		$client->showBriefly($parts) if $parts;
#	}
		
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
	if (!$prefs->get('playlistdir')) {
		$request->setStatusBadConfig();
		return;
	}

	# get the parameters
	my $client = $request->client();
	my $title  = $request->getParam('_title');
	my $titlesort = Slim::Utils::Text::ignoreCaseArticles($title);

	$title = Slim::Utils::Misc::cleanupFilename($title);

	my $playlistObj = Slim::Schema->rs('Playlist')->updateOrCreate({

		'url' => Slim::Utils::Misc::fileURLFromPath(
			catfile( $prefs->get('playlistdir'), Slim::Utils::Unicode::utf8encode_locale($title) . '.m3u')
		),

		'attributes' => {
			'TITLE' => $title,
			'CT'    => 'ssp',
		},
	});

	my $annotatedList = [];

	if ($prefs->get('saveShuffled')) {

		for my $shuffleitem (@{Slim::Player::Playlist::shuffleList($client)}) {
			push @$annotatedList, @{Slim::Player::Playlist::playList($client)}[$shuffleitem];
		}
				
	} else {

		$annotatedList = Slim::Player::Playlist::playList($client);
	}

	$playlistObj->set_column('titlesort', $titlesort);
	$playlistObj->set_column('titlesearch', $titlesort);
	$playlistObj->setTracks($annotatedList);
	$playlistObj->update;

	Slim::Schema->forceCommit;

	Slim::Player::Playlist::scheduleWriteOfPlaylist($client, $playlistObj);

  	$client->showBriefly({
		'jive' => {
			'type'    => 'popupplay',
			'text'    => [ $client->string('SAVED_THIS_PLAYLIST_AS', $title) ],
                                }
                        });

	$request->addResult('__playlist_id', $playlistObj->id);
	$request->addResult('__playlist_obj', $playlistObj);

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


sub playlistXalbumCommand {
	my $request = shift;

	# check this is the correct command.
	if ($request->isNotCommand([['playlist'], ['playalbum', 'loadalbum', 'addalbum', 'insertalbum', 'deletealbum']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get the parameters
	my $client   = $request->client();
	my $cmd      = $request->getRequest(1);
	my $genre    = $request->getParam('_genre'); #p2
	my $artist   = $request->getParam('_artist');#p3
	my $album    = $request->getParam('_album'); #p4
	my $title    = $request->getParam('_title'); #p5

	# Pass to parseSearchTerms
	my $find     = {};

	if (specified($genre)) {

		$find->{'genre.name'} = _playlistXalbum_singletonRef($genre);
	}

	if (specified($artist)) {

		$find->{'contributor.name'} = _playlistXalbum_singletonRef($artist);
	}

	if (specified($album)) {

		$find->{'album.title'} = _playlistXalbum_singletonRef($album);
	}

	if (specified($title)) {

		$find->{'me.title'} = _playlistXalbum_singletonRef($title);
	}

	my @results = _playlistXtracksCommand_parseSearchTerms($client, $find);

	$cmd =~ s/album/tracks/;

	Slim::Control::Request::executeRequest($client, ['playlist', $cmd, 'listRef', \@results]);

	$request->setStatusDone();
}


sub playlistXitemCommand {
	my $request = shift;

	# check this is the correct command.
	if ($request->isNotCommand([['playlist'], ['add', 'append', 'insert', 'insertlist', 'load', 'play', 'resume']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get the parameters
	my $client   = $request->client();
	my $cmd      = $request->getRequest(1); #p1
	my $item     = $request->getParam('_item'); #p2
	my $title    = $request->getParam('_title') || ''; #p3

	if (!defined $item) {
		$request->setStatusBadParams();
		return;
	}

	$log->info("cmd: $cmd, item: $item, title: $title");

	my $jumpToIndex; # This should be undef - see bug 2085
	my $results;
	
	if ( main::SLIM_SERVICE ) {
		# If the item is a base64+storable string, decode it.
		# This is used for sending multiple URLs from the web
		# XXX: JSON::XS is faster than Storable
		use MIME::Base64 qw(decode_base64);
		use Storable qw(thaw);
		
		if ( !ref $item && $item =~ /^base64:/ ) {
			$item =~ s/^base64://;
			$item = thaw( decode_base64( $item ) );
		}
	}
	
	# If we're playing a list of URLs (from XMLBrowser), only work on the first item
	my $list;
	if ( ref $item eq 'ARRAY' ) {
		
		# If in shuffle mode, we need to shuffle the list of items as
		# soon as we get it
		if ( Slim::Player::Playlist::shuffle($client) == 1 ) {
			Slim::Player::Playlist::fischer_yates_shuffle($item);
		}
		
		$list = $item;
		$item = shift @{$item};
	}

	my $url  = blessed($item) ? $item->url : $item;

	# Strip off leading and trailing whitespace. PEBKAC
	$url =~ s/^\s*//;
	$url =~ s/\s*$//;

	$log->info("url: $url");

	my $path = $url;
	
	# Set title if supplied
	if ( $title ) {
		Slim::Music::Info::setTitle( $url, $title );
		Slim::Music::Info::setCurrentTitle( $url, $title );
	}

	# check whether url is potentially for a local file or db entry, if so pass to playlistXtracksCommand
	# this avoids rescanning items already in the database and allows playlist and other favorites to be played
	
	# XXX: hardcoding these protocols isn't the best way to do this. We should have a flag in ProtocolHandler to get this list
	if ($path =~ /^file:\/\/|^db:|^itunesplaylist:|^musicipplaylist:/) {

		if (my @tracks = _playlistXtracksCommand_parseDbItem($client, $path)) {

			$client->execute([ 'playlist', $cmd . 'tracks' , 'listRef', \@tracks ]);
			$request->setStatusDone();
			return;
		}
	}

	# correct the path
	# this only seems to be useful for playlists?
	if (!Slim::Music::Info::isRemoteURL($path) && !-e $path && !(Slim::Music::Info::isPlaylistURL($path))) {

		my $easypath = catfile($prefs->get('playlistdir'), basename($url) . ".m3u");

		if (-e $easypath) {

			$path = $easypath;

		} else {

			$easypath = catfile($prefs->get('playlistdir'), basename($url) . ".pls");

			if (-e $easypath) {
				$path = $easypath;
			}
		}
	}

	# Un-escape URI that have been escaped again.
	if (Slim::Music::Info::isRemoteURL($path) && $path =~ /%3A%2F%2F/) {

		$path = Slim::Utils::Misc::unescape($path);
	}

	$log->info("path: $path");

	if ($cmd =~ /^(play|load|resume)$/) {

		Slim::Player::Source::playmode($client, 'stop');
		Slim::Player::Playlist::clear($client);

		$client->currentPlaylist( Slim::Utils::Misc::fixPath($path) );

		if ( $log->is_info ) {
			$log->info("currentPlaylist:" .  Slim::Utils::Misc::fixPath($path));
		}

		$client->currentPlaylistModified(0);

	} elsif ($cmd =~ /^(add|append)$/) {

		$client->currentPlaylist( Slim::Utils::Misc::fixPath($path) );
		$client->currentPlaylistModified(1);

		if ( $log->is_info ) {
			$log->info("currentPlaylist:" .  Slim::Utils::Misc::fixPath($path));
		}

	} else {

		$client->currentPlaylistModified(1);
	}

	if (!Slim::Music::Info::isRemoteURL($path) && Slim::Music::Info::isFileURL($path)) {

		$path = Slim::Utils::Misc::pathFromFileURL($path);

		$log->info("path: $path");
	}

	if ($cmd =~ /^(play|load)$/) { 

		$jumpToIndex = 0;

	} elsif ($cmd eq "resume" && Slim::Music::Info::isM3U($path)) {

		$jumpToIndex = Slim::Formats::Playlists::M3U->readCurTrackForM3U($path);
	}

	if ( $log->is_info ) {
		$log->info(sprintf("jumpToIndex: %s", (defined $jumpToIndex ? $jumpToIndex : 'undef')));
	}

	if ($cmd =~ /^(insert|insertlist)$/) {

		my $playListSize = Slim::Player::Playlist::count($client);
		my @dirItems     = ();

		$log->info("inserting, playListSize: $playListSize");

		Slim::Utils::Scanner->scanPathOrURL({
			'url'      => $path,
			'listRef'  => \@dirItems,
			'client'   => $client,
			'callback' => sub {
				my $foundItems = shift;

				push @{ Slim::Player::Playlist::playList($client) }, @{$foundItems};

				_insert_done(
					$client,
					$playListSize,
					scalar @{$foundItems},
					$request->callbackFunction,
					$request->callbackArguments,
				);

				playlistXitemCommand_done( $client, $request, $path );
			},
		});
		if ( $cmd eq 'insert' && Slim::Music::Info::isRemoteURL($path) && !Slim::Music::Info::isDigitalInput($path) && !Slim::Music::Info::isLineIn($path) ) {

			my $insert = Slim::Music::Info::title($path) || $path;
			my $msg = $client->string('JIVE_POPUP_ADDING_TO_PLAY_NEXT', $insert);
			my @line = split("\n", $msg);
			$client->showBriefly({
					'line' => [ @line ],
					'jive' => { 'type' => 'popupplay', text => [ $msg ] },
				});
		}
	} else {
		
		# Display some feedback for the player on remote URLs
		# XXX - why only remote URLs?
		if ( $cmd eq 'add' && Slim::Music::Info::isRemoteURL($path) && !Slim::Music::Info::isDigitalInput($path) && !Slim::Music::Info::isLineIn($path) ) {

			my $insert = Slim::Music::Info::title($path) || $path;
			$client->showBriefly( {
				line => [
					$client->string('ADDING_TO_PLAYLIST'),
					$insert,
				],
				jive => {
					type => 'popupplay',
					text => [ 
						$client->string('JIVE_POPUP_ADDING_TO_PLAYLIST', $insert)
					],
				},
			} );
		}

		Slim::Utils::Scanner->scanPathOrURL({
			'url'      => $path,
			'listRef'  => Slim::Player::Playlist::playList($client),
			'client'   => $client,
			'cmd'      => $cmd,
			'callback' => sub {
				my ( $foundItems, $error ) = @_;
				
				# If we are playing a list of URLs, add the other items now
				my $noShuffle = 0;
				if ( ref $list eq 'ARRAY' ) {
					push @{$foundItems}, @{$list};
					
					# If we had a list of tracks, we already shuffled above
					$noShuffle = 1;
				}

				push @{ Slim::Player::Playlist::playList($client) }, @{$foundItems};

				_playlistXitem_load_done(
					$client,
					$jumpToIndex,
					$request,
					scalar @{Slim::Player::Playlist::playList($client)},
					$path,
					$error,
					$noShuffle,
				);

				playlistXitemCommand_done( $client, $request, $path );
			},
		});

	}

	if (!$request->isStatusDone()) {
		$request->setStatusProcessing();
	}

	$log->debug("done.");
}

# Called after insert/load async callbacks are finished
sub playlistXitemCommand_done {
	my ( $client, $request, $path ) = @_;

	# The callback, if any, will be called by _load/_insert_done, so
	# don't call it now
	# Hmm, in fact the request is not done until load/insert is called.
	# addToList is asynchronous. load/insert should call request done...
	$request->callbackEnabled(0);

	# Update the parameter item with the correct path
	# Not sure anyone depends on this behaviour...
	$request->addParam('_item', $path);

	$client->currentPlaylistUpdateTime(Time::HiRes::time());

	Slim::Player::Playlist::refreshPlaylist($client) if $client->currentPlaylistModified();

	$request->setStatusDone();
}

sub playlistXtracksCommand {
	my $request = shift;

	# check this is the correct command.
	if ($request->isNotCommand([['playlist'], ['playtracks', 'loadtracks', 'addtracks', 'inserttracks', 'deletetracks']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get the parameters
	my $client   = $request->client();
	my $cmd      = $request->getRequest(1); #p1
	my $what     = $request->getParam('_what'); #p2
	my $listref  = $request->getParam('_listref');#p3

	if (!defined $what) {
		$request->setStatusBadParams();
		return;
	}

	# This should be undef - see bug 2085
	my $jumpToIndex = undef;

	my $load   = ($cmd eq 'loadtracks' || $cmd eq 'playtracks');
	my $insert = ($cmd eq 'inserttracks');
	my $add    = ($cmd eq 'addtracks');
	my $delete = ($cmd eq 'deletetracks');

	# if loading, start by stopping it all...
	if ($load) {
		Slim::Player::Source::playmode($client, 'stop');
		Slim::Player::Playlist::clear($client);
	}

	# parse the param
	my @tracks = ();

	if ($what =~ /urllist/i) {
		@tracks = _playlistXtracksCommand_constructTrackList($client, $what, $listref);
	} elsif ($what =~ /listRef/i) {
		@tracks = _playlistXtracksCommand_parseListRef($client, $what, $listref);

	} elsif ($what =~ /searchRef/i) {

		@tracks = _playlistXtracksCommand_parseSearchRef($client, $what, $listref);

	} else {

		@tracks = _playlistXtracksCommand_parseSearchTerms($client, $what);
	}

	my $size  = scalar(@tracks);
	my $playListSize = Slim::Player::Playlist::count($client);

	# add or remove the found songs
	if ($load || $add || $insert) {
		push(@{Slim::Player::Playlist::playList($client)}, @tracks);
	}

	if ($insert) {
		_insert_done($client, $playListSize, $size);
	}

	if ($delete) {
		Slim::Player::Playlist::removeMultipleTracks($client, \@tracks);
	}

	if ($load || $add) {
		Slim::Player::Playlist::reshuffle($client, $load ? 1 : undef);
	}

	if ($load) {
		# The user may have stopped in the middle of a
		# saved playlist - resume if we can. Bug 1582
		my $playlistObj = $client->currentPlaylist();

		if ($playlistObj && ref($playlistObj) && $playlistObj->content_type =~ /^(?:ssp|m3u)$/) {

			if (!Slim::Player::Playlist::shuffle($client)) {
				$jumpToIndex = Slim::Formats::Playlists::M3U->readCurTrackForM3U( $client->currentPlaylist->path );
			}

			# And set a callback so that we can
			# update CURTRACK when the song changes.
			Slim::Control::Request::subscribe(\&Slim::Player::Playlist::newSongPlaylistCallback, [['playlist'], ['newsong']]);
		}
		
		$client->execute( [ 'playlist', 'jump', $jumpToIndex ] );
		
		$client->currentPlaylistModified(0);
	}

	if ($add || $insert || $delete) {
		$client->currentPlaylistModified(1);
	}

	if ($load || $add || $insert || $delete) {
		$client->currentPlaylistUpdateTime(Time::HiRes::time());
	}

	$request->setStatusDone();
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

	my $playlistObj = Slim::Schema->rs('Playlist')->updateOrCreate({
		'url'        => Slim::Utils::Misc::fileURLFromPath(
			catfile( $prefs->get('playlistdir'), $zapped . '.m3u')
		),

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


sub playlistcontrolCommand {
	my $request = shift;
	
	$log->error("Begin Function");

	# check this is the correct command.
	if ($request->isNotCommand([['playlistcontrol']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get the parameters
	my $client = $request->client();
	my $cmd    = $request->getParam('cmd');;
	
	if (Slim::Music::Import->stillScanning()) {
		$request->addResult('rescan', "1");
	}

	if ($request->paramUndefinedOrNotOneOf($cmd, ['load', 'insert', 'add', 'delete'])) {
		$request->setStatusBadParams();
		return;
	}

	my $load   = ($cmd eq 'load');
	my $insert = ($cmd eq 'insert');
	my $add    = ($cmd eq 'add');
	my $delete = ($cmd eq 'delete');
	
	# shortcut to playlist $cmd url if given a folder_id...
	# the acrobatics it does are too risky to replicate
	if (defined(my $folderId = $request->getParam('folder_id'))) {
		
		# unfortunately playlist delete is not supported
		if ($delete) {
			$request->setStatusBadParams();
			return;
		}
		
		my $folder = Slim::Schema->find('Track', $folderId);
		
		# make sure it's a folder
		if (!blessed($folder) || !$folder->can('url') || !$folder->can('content_type') || $folder->content_type() ne 'dir') {
			$request->setStatusBadParams();
			return;
		}

		if ( $add || $load || $insert ) {
			my $token;
			if ($add) {
				$token = 'JIVE_POPUP_ADDING_TO_PLAYLIST';
			} elsif ($insert) {
				$token = 'JIVE_POPUP_ADDING_TO_PLAY_NEXT';
			} else {
				$token = 'JIVE_POPUP_NOW_PLAYING';
			}
			my $string = $client->string($token, $folder->title);
			$client->showBriefly({ 
				'jive' => { 
					'type'    => 'popupplay',
					'text'    => [ $string ],
				}
			});
		} 

		Slim::Control::Request::executeRequest(
			$client, ['playlist', $cmd, $folder->url()]
		);
		$request->addResult('count', 1);
		$request->setStatusDone();
		return;
	}

	# if loading, first stop everything
	if ($load) {
		Slim::Player::Source::playmode($client, "stop");
		Slim::Player::Playlist::clear($client);
	}

	# find the songs
	my @tracks = ();

	# info line and artwork to display if sucessful
	my @info;
	my $artwork;

	# Bug: 2373 - allow the user to specify a playlist name
	my $playlist_id = 0;

	if (defined(my $playlist_name = $request->getParam('playlist_name'))) {

		my $playlistObj = Slim::Schema->single('Playlist', { 'title' => $playlist_name });

		if (blessed($playlistObj)) {

			$playlist_id = $playlistObj->id;
		}
	}

	if (!$playlist_id && $request->getParam('playlist_id')) {

		$playlist_id = $request->getParam('playlist_id');
	}

	if ($playlist_id) {

		# Special case...
		my $playlist = Slim::Schema->find('Playlist', $playlist_id);

		if (blessed($playlist) && $playlist->can('tracks')) {

			if ( $add || $load || $insert ) {
				my $token;
				if ($add) {
					$token = 'JIVE_POPUP_ADDING_TO_PLAYLIST';
				} elsif ($insert) {
					$token = 'JIVE_POPUP_ADDING_TO_PLAY_NEXT';
				} else {
					$token = 'JIVE_POPUP_NOW_PLAYING';
				}
				my $string = $client->string($token, $playlist->title);
				$client->showBriefly({ 
					'jive' => { 
						'type'    => 'popupplay',
						'text'    => [ $string ],
					}
				});			
			}

			$cmd .= "tracks";

			Slim::Control::Request::executeRequest(
				$client, ['playlist', $cmd, 'playlist.id=' . $playlist_id]
			);

			$request->addResult('count', scalar($playlist->tracks()));

			$request->setStatusDone();
			
			return;
		}

	} elsif (defined(my $track_id_list = $request->getParam('track_id'))) {

		# split on commas
		my @track_ids = split(/,/, $track_id_list);
		
		# keep the order
		my %track_ids_order;
		my $i = 0;
		for my $id (@track_ids) {
			$track_ids_order{$id} = $i++;
		}

		# find the tracks
		my @rawtracks = Slim::Schema->search('Track', { 'id' => { 'in' => \@track_ids } })->all;
		
		# sort them back!
		@tracks = sort { $track_ids_order{$a->id()} <=> $track_ids_order{$b->id()} } @rawtracks;


	} else {

		# rather than re-invent the wheel, use _playlistXtracksCommand_parseSearchTerms
		
		my $what = {};
		
		if (defined(my $genre_id = $request->getParam('genre_id'))) {
			$what->{'genre.id'} = $genre_id;
			$info[0] = Slim::Schema->find('Genre', $genre_id)->name;
		}

		if (defined(my $artist_id = $request->getParam('artist_id'))) {
			$what->{'contributor.id'} = $artist_id;
			$info[0] = Slim::Schema->find('Contributor', $artist_id)->name;
		}

		if (defined(my $album_id = $request->getParam('album_id'))) {
			$what->{'album.id'} = $album_id;
			my $album = Slim::Schema->find('Album', $album_id);
			@info    = ( $album->title, $album->contributors->first->name );
			$artwork = $album->artwork +0;
		}

		if (defined(my $year = $request->getParam('year'))) {
			$what->{'year.id'} = $year;
			$info[0] = $year;
		}

		# Fred: form year_id DEPRECATED in 7.0
		if (defined(my $year_id = $request->getParam('year_id'))) {

			$what->{'year.id'} = $year_id;
		}
		
		@tracks = _playlistXtracksCommand_parseSearchTerms($client, $what);
	}

	# don't call Xtracks if we got no songs
	if (@tracks) {

		if ($load || $add || $insert) {

			$info[0] ||= $tracks[0]->title;
			my $token;
			if ($add) {
				$token = 'JIVE_POPUP_ADDING_TO_PLAYLIST';
			} elsif ($insert) {
				$token = 'JIVE_POPUP_ADDING_TO_PLAY_NEXT';
			} else {
				$token = 'JIVE_POPUP_NOW_PLAYING';
			}
			my $string = $client->string($token, $info[0]);
			$client->showBriefly({ 
				'jive' => { 
					'type'    => defined $artwork ? 'song' : 'popupplay',
					'text'    => [ $string ],
					'icon-id' => $artwork,
				}
			});

		}

		$cmd .= "tracks";

		Slim::Control::Request::executeRequest(
			$client, ['playlist', $cmd, 'listRef', \@tracks]
		);
	}

	$request->addResult('count', scalar(@tracks));

	$request->setStatusDone();
}


sub playlistsEditCommand {
	my $request = shift;

	# check this is the correct command.
	if ($request->isNotCommand([['playlists'], ['edit']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get the parameters
	my $playlist_id = $request->getParam('playlist_id');
	my $cmd = $request->getParam('cmd');
	my $itemPos = $request->getParam('index');
	my $newPos = $request->getParam('toindex');

	if ($request->paramUndefinedOrNotOneOf($cmd, ['up', 'down', 'delete', 'add', 'move'])) {
		$request->setStatusBadParams();
		return;
	}

	if (!$playlist_id) {
		$request->setStatusBadParams();
		return;
	}

	if (!defined($itemPos) && $cmd ne 'add') {
		$request->setStatusBadParams();
		return;
	}

	if (!defined($newPos) && $cmd eq 'move') {
		$request->setStatusBadParams();
		return;
	}

	# transform the playlist id in a playlist obj
	my $playlist = Slim::Schema->find('Playlist', $playlist_id);

	if (!blessed($playlist)) {
		$request->setStatusBadParams();
		return;
	}
	
	# now perform the operation
	my @items   = $playlist->tracks;
	my $changed = 0;

	# Once we move to using DBIx::Class::Ordered, most of this code can go away.
	if ($cmd eq 'delete') {

		splice(@items, $itemPos, 1);

		$changed = 1;

	} elsif ($cmd eq 'up') {

		# Up function - Move entry up in list
		if ($itemPos != 0) {

			my $item = $items[$itemPos];
			$items[$itemPos] = $items[$itemPos - 1];
			$items[$itemPos - 1] = $item;

			$changed = 1;
		}

	} elsif ($cmd eq 'down') {

		# Down function - Move entry down in list
		if ($itemPos != scalar(@items) - 1) {

			my $item = $items[$itemPos];
			$items[$itemPos] = $items[$itemPos + 1];
			$items[$itemPos + 1] = $item;

			$changed = 1;
		}

	} elsif ($cmd eq 'move') {

		if ($itemPos != $newPos && $itemPos < scalar(@items) && $itemPos >= 0 
			&& $newPos < scalar(@items)	&& $newPos >= 0) {

			# extract the item to be moved
			my $item = splice @items, $itemPos, 1;
			my @tail = splice @items, ($newPos);
			push @items, $item, @tail;

			$changed = 1;
		}
	
	} elsif ($cmd eq 'add') {

		# Add function - Add entry it not already in list
		my $found = 0;
		my $title = $request->getParam('title');
		my $url   = $request->getParam('url');

		if ($url) {

			my $playlistTrack = Slim::Schema->rs('Track')->updateOrCreate({
				'url'      => $url,
				'readTags' => 1,
				'commit'   => 1,
			});

			for my $item (@items) {

				if ($item->id eq $playlistTrack->id) {

					$found = 1;
					last;
				}
			}

			# XXXX - call ->appendTracks() once this is reworked.
			if ($found == 0) {
				push @items, $playlistTrack;
			}

			if ($title) {
				$playlistTrack->title($title);
				$playlistTrack->titlesort(Slim::Utils::Text::ignoreCaseArticles($title));
				$playlistTrack->titlesearch(Slim::Utils::Text::ignoreCaseArticles($title));
			}

			$playlistTrack->update;

			$changed = 1;
		}
	}

	if ($changed) {

		my $log = logger('player.playlist');

		$log->info("Playlist has changed via editing - saving new list of tracks.");

		$playlist->setTracks(\@items);
		$playlist->update;

		if ($playlist->content_type eq 'ssp') {

			$log->info("Writing out playlist to disk..");

			Slim::Formats::Playlists->writeList(\@items, undef, $playlist->url);
		}
		
		$playlist = undef;

		Slim::Schema->forceCommit;
		Slim::Schema->wipeCaches;
	}

	$request->setStatusDone();
}


sub playlistsDeleteCommand {
	my $request = shift;

	# check this is the correct command.
	if ($request->isNotCommand([['playlists'], ['delete']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get the parameters
	my $playlist_id = $request->getParam('playlist_id');

	if (!$playlist_id) {
		$request->setStatusBadParams();
		return;
	}

	# transform the playlist id in a playlist obj
	my $playlistObj = Slim::Schema->find('Playlist', $playlist_id);

	if (!blessed($playlistObj) || !$playlistObj->isPlaylist()) {
		$request->setStatusBadParams();
		return;
	}

	# show feedback if this action came from jive cometd session
	if ($request->source && $request->source =~ /\/slim\/request/) {
		$request->client->showBriefly({
			'jive' => {
				'text'    => [	
					$request->string('JIVE_DELETE_PLAYLIST', $playlistObj->name)
				],
			},
		});
	}

	Slim::Player::Playlist::removePlaylistFromDisk($playlistObj);
	
	# Do a fast delete, and then commit it.
	$playlistObj->setTracks([]);
	$playlistObj->delete;

	$playlistObj = undef;

	Slim::Schema->forceCommit;



	$request->setStatusDone();
}


sub playlistsNewCommand {
	my $request = shift;

	# check this is the correct command.
	if ($request->isNotCommand([['playlists'], ['new']])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# can't do much without playlistdir!
	if (!$prefs->get('playlistdir')) {
		$request->setStatusBadConfig();
		return;
	}

	# get the parameters
	my $title  = $request->getParam('name');
	$title = Slim::Utils::Misc::cleanupFilename($title);

	my $titlesort = Slim::Utils::Text::ignoreCaseArticles($title);

	# create the playlist URL
	my $newUrl   = Slim::Utils::Misc::fileURLFromPath(
		catfile($prefs->get('playlistdir'), $title . '.m3u')
	);

	my $existingPlaylist = Slim::Schema->rs('Playlist')->objectForUrl({
		'url' => $newUrl,
	});

	if (blessed($existingPlaylist)) {

		# the name already exists!
		$request->addResult("overwritten_playlist_id", $existingPlaylist->id());
	}
	else {

		my $playlistObj = Slim::Schema->rs('Playlist')->updateOrCreate({

			'url' => $newUrl,

			'attributes' => {
				'TITLE' => $title,
				'CT'    => 'ssp',
			},
		});

		$playlistObj->set_column('titlesort', $titlesort);
		$playlistObj->update;

		Slim::Schema->forceCommit;

		Slim::Player::Playlist::scheduleWriteOfPlaylist(undef, $playlistObj);

		$request->addResult('playlist_id', $playlistObj->id);
	}
	
	$request->setStatusDone();
}


sub playlistsRenameCommand {
	my $request = shift;

	# check this is the correct command.
	if ($request->isNotCommand([['playlists'], ['rename']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get the parameters
	my $playlist_id = $request->getParam('playlist_id');
	my $newName = $request->getParam('newname');
	my $dry_run = $request->getParam('dry_run');

	if (!$playlist_id || !$newName) {
		$request->setStatusBadParams();
		return;
	}

	# transform the playlist id in a playlist obj
	my $playlistObj = Slim::Schema->find('Playlist', $playlist_id);

	if (!blessed($playlistObj)) {
		$request->setStatusBadParams();
		return;
	}

	$newName = Slim::Utils::Misc::cleanupFilename($newName);

	# now perform the operation
	
	my $newUrl   = Slim::Utils::Misc::fileURLFromPath(
		catfile($prefs->get('playlistdir'), $newName . '.m3u')
	);

	my $existingPlaylist = Slim::Schema->rs('Playlist')->objectForUrl({
		'url' => $newUrl,
	});

	if (blessed($existingPlaylist)) {

		$request->addResult("overwritten_playlist_id", $existingPlaylist->id());
	}
	
	if (!$dry_run) {

		if (blessed($existingPlaylist) && $existingPlaylist->id ne $playlistObj->id) {

			Slim::Control::Request::executeRequest(undef, ['playlists', 'delete', 'playlist_id:' . $existingPlaylist->id]);

			$existingPlaylist = undef;
		}
		
		my $index = Slim::Formats::Playlists::M3U->readCurTrackForM3U( $playlistObj->path );

		Slim::Player::Playlist::removePlaylistFromDisk($playlistObj);

		$playlistObj->set_column('url', $newUrl);
		$playlistObj->set_column('title', $newName);
		$playlistObj->set_column('titlesort', Slim::Utils::Text::ignoreCaseArticles($newName));
		$playlistObj->set_column('titlesearch', Slim::Utils::Text::ignoreCaseArticles($newName));
		$playlistObj->update;

#			Slim::Player::Playlist::scheduleWriteOfPlaylist($client, $playlistObj);
		Slim::Formats::Playlists::M3U->write( 
			[ $playlistObj->tracks ],
			undef,
			$playlistObj->path,
			1,
			$index,
			);
	}

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
			Slim::Control::Jive::playerPower($client);
			
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
	Slim::Control::Jive::playerPower($client);

	$request->setStatusDone();
}


sub prefCommand {
	my $request = shift;

	if ($request->isNotCommand([['pref']]) && $request->isNotCommand([['playerpref']])) {
		$request->setStatusBadDispatch();
		return;
	}

	my $client;

	if ($request->isCommand([['playerpref']])) {
		
		$client = $request->client();
		
		unless ($client) {			
			$request->setStatusBadDispatch();
			return;
		}
	}

	# get our parameters
	my $prefName = $request->getParam('_prefname');
	my $newValue = $request->getParam('value') || $request->getParam('_newvalue');

	# split pref name from namespace: name.space.pref:
	my $namespace = 'server';
	if ($prefName =~ /^(.*):(\w+)$/) {
		$namespace = $1;
		$prefName = $2;
	}
	
	if ($newValue =~ /^value:/) {
		$newValue =~ s/^value://;
	}

	if (!defined $prefName || !defined $newValue || !defined $namespace) {
		$request->setStatusBadParams();
		return;
	}	

	if ($client) {
		preferences($namespace)->client($client)->set($prefName, $newValue);
	}
	else {
		preferences($namespace)->set($prefName, $newValue);
	}
	
	$request->setStatusDone();
}

sub rescanCommand {
	my $request = shift;

	if ($request->isNotCommand([['rescan']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get our parameters
	my $playlistsOnly = $request->getParam('_playlists') || 0;
	
	# if we're scanning allready, don't do it twice
	if (!Slim::Music::Import->stillScanning()) {

		my %args = (
			'rescan'  => 1,
			'cleanup' => 1,
		);

		if ($playlistsOnly) {

			$args{'playlists'} = 1;
		}

		Slim::Music::Import->launchScan(\%args);
	}

	$request->setStatusDone();
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
		$client->showBriefly({
			'jive' => { 
				'type'    => 'popupplay',
				'text'    => [ $client->string('SLEEPING_IN_X_MINUTES', $will_sleep_in_minutes ) ],
			}
		});
		
	} else {

		# finish canceling any sleep in progress
		$client->sleepTime(0);
		$client->currentSleepTime(0);

		$client->showBriefly({
			'jive' => { 
				'type'    => 'popupplay',
				'text'    => [ $client->string('CANCEL_SLEEP' ) ],
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
		
		$client->controller()->sync($buddy) if defined $buddy;
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


sub wipecacheCommand {
	my $request = shift;

	if ($request->isNotCommand([['wipecache']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# no parameters
	
	# if we're scanning allready, don't do it twice
	if (!Slim::Music::Import->stillScanning()) {

		# Clear all the active clients's playlists
		for my $client (Slim::Player::Client::clients()) {

			$client->execute([qw(playlist clear)]);
		}

		Slim::Music::Import->launchScan({
			'wipe' => 1,
		});
	}

	$request->setStatusDone();
}

sub ratingCommand {
	my $request = shift;

	# check this is the correct command.
	if ( $request->isNotCommand( [['rating']] ) ) {
		$request->setStatusBadDispatch();
		return;
	}

	# get the parameters
	my $item   = $request->getParam('_item');      #p1
	my $rating = $request->getParam('_rating');    #p2, optional

	if ( !defined $item ) {
		$request->setStatusBadParams();
		return;
	}

	if ( defined $rating ) {
		$log->info("Setting rating for $item to $rating");
	}

	my $track = blessed($item);

	if ( !$track ) {
		# Look for track based on ID or URL
		if ( $item =~ /^\d+$/ ) {
			$track = Slim::Schema->resultset('Track')->find($item);
		}
		else {
			my $url = Slim::Utils::Misc::fileURLFromPath($item);
			if ( $url ) {
				$track = Slim::Schema->rs('Track')->objectForUrl( { url => $url } );
			}
		}
	}

	if ( !blessed($track) || $track->audio != 1 ) {
		$log->warn("Can't find track: $item");
		$request->setStatusBadParams();
		return;
	}

	if ( defined $rating ) {
		if ( $rating < 0 || $rating > 100 ) {
			$request->setStatusBadParams();
			return;
		}

		Slim::Schema->rating( $track, $rating );
	}
	else {
		$rating = Slim::Schema->rating($track);
		
		$request->addResult( '_rating', defined $rating ? $rating : 0 );
	}

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

sub _playlistXitem_load_done {
	my ($client, $index, $request, $count, $url, $error, $noShuffle) = @_;
	
	# dont' keep current song on loading a playlist
	if ( !$noShuffle ) {
		Slim::Player::Playlist::reshuffle($client,
			(Slim::Player::Source::playmode($client) eq "play" || ($client->power && Slim::Player::Source::playmode($client) eq "pause")) ? 0 : 1
		);
	}

	if (defined($index)) {
		$client->execute( [ 'playlist', 'jump', $index ] );
	}

	# XXX: this should not be calling a request callback directly!
	# It should be handled by $request->setStatusDone
	if ( my $callbackf = $request->callbackFunction ) {
		if ( my $callbackargs = $request->callbackArguments ) {
			$callbackf->( @{$callbackargs} );
		}
		else {
			$callbackf->( $request );
		}
	}

	Slim::Control::Request::notifyFromArray($client, ['playlist', 'load_done']);
}


sub _insert_done {
	my ($client, $listsize, $size, $callbackf, $callbackargs) = @_;

	my $playlistIndex = Slim::Player::Source::streamingSongIndex($client)+1;
	my @reshuffled;

	if (Slim::Player::Playlist::shuffle($client)) {

		for (my $i = 0; $i < $size; $i++) {
			push @reshuffled, ($listsize + $i);
		};
			
		$client = $client->master();
		
		if (Slim::Player::Playlist::count($client) != $size) {	
			splice @{$client->shufflelist}, $playlistIndex, 0, @reshuffled;
		}
		else {
			push @{$client->shufflelist}, @reshuffled;
		}
	} else {

		if (Slim::Player::Playlist::count($client) != $size) {
			Slim::Player::Playlist::moveSong($client, $listsize, $playlistIndex, $size);
		}

		Slim::Player::Playlist::reshuffle($client);
	}

	Slim::Player::Playlist::refreshPlaylist($client);

	$callbackf && (&$callbackf(@$callbackargs));

	Slim::Control::Request::notifyFromArray($client, ['playlist', 'load_done']);

}


sub _playlistXalbum_singletonRef {
	my $arg = shift;

	if (!defined($arg)) {
		return [];
	} elsif ($arg eq '*') {
		return [];
	} elsif ($arg) {
		# force stringification of a possible object.
		return ["" . $arg];
	} else {
		return [];
	}
}


sub _playlistXtracksCommand_parseSearchTerms {
	my $client = shift;
	my $what   = shift;

	# if there isn't an = sign, then change the first : to a =
	if ($what !~ /=/) {
		$what =~ s/(.*)?:(.*)/$1=$2/;
	}

	my %find   = ();
	my $terms  = {};
	my %attrs  = ();
	my @fields = map { lc($_) } Slim::Schema->sources;
	my ($sort, $limit, $offset);

	# Bug: 3629 - sort by album, then disc, tracknum, titlesort
	my $albumSort = "concat(album.titlesort, '0'), me.disc, me.tracknum, concat(me.titlesort, '0')";
	my $trackSort = "me.disc, me.tracknum, concat(me.titlesort, '0')";
	
	if ( main::SLIM_SERVICE ) {
		# XXX: this should never be called on SN, but have seen it happen
		return ();
	}

	# Setup joins as needed - we want to end up with Tracks in the end.
	my %joinMap = ();

	# Accept both the old key=value "termlist", and internal use by passing a hash ref.
	if (ref($what) eq 'HASH') {

		$terms = $what;

	} else {

		for my $term (split '&', $what) {

			# If $terms has a leading &, split will generate an initial empty string
			next if !$term;

			if ($term =~ /^(.*)=(.*)$/ && grep { $1 =~ /$_\.?/ } @fields) {

				my $key   = URI::Escape::uri_unescape($1);
				my $value = URI::Escape::uri_unescape($2);

				$terms->{$key} = $value;

			} elsif ($term =~ /^(fieldInfo)=(\w+)$/) {

				$terms->{$1} = $2;
			}
		}
	}

	while (my ($key, $value) = each %{$terms}) {

		# ignore anti-CSRF token
		if ($key eq 'pageAntiCSRFToken') {
			next;
		}

		# Bug: 4063 - don't enforce contributor.role when coming from
		# the web UI's search.
		if ($key eq 'contributor.role') {
			next;
		}

		# Bug: 3582 - reconstitute from 0 for album.compilation.
		if ($key eq 'album.compilation' && $value == 0) {

			$find{$key} = [ { 'is' => undef }, { '=' => 0 } ];
		}

		# Do some mapping from the player browse mode. This is
		# already done in the web ui.
		if ($key =~ /^(playlist|age|album|contributor|genre|year)$/) {
			$key = "$1.id";
		}

		# New Music browsing is working on the
		# tracks.timestamp column, but shows years
		if ($key =~ /^age\.id$/) {

			$key = 'album.id';
		}

		# Setup the join mapping
		if ($key =~ /^genre\./) {

			$sort = $albumSort;
			$joinMap{'genre'} = { 'genreTracks' => 'genre' };

		} elsif ($key =~ /^album\./) {

			$sort = $albumSort;
			$joinMap{'album'} = 'album';

		} elsif ($key =~ /^year\./) {

			$sort = $albumSort;
			$joinMap{'year'} = 'year';

		} elsif ($key =~ /^contributor\./) {

			$sort = $albumSort;
			$joinMap{'contributor'} = { 'contributorTracks' => 'contributor' };
		}

		# Turn 'track.*' into 'me.*'
		if ($key =~ /^(playlist)?track(\.?.*)$/) {
			$key = "me$2";
		}

		# Meta tags that are passed.
		if ($key =~ /^(?:limit|offset)$/) {

			$attrs{$key} = $value;

		} elsif ($key eq 'sort') {

			$sort = $value;

		} else {

			if ($key =~ /\.(?:name|title)search$/) {
				
				# BUG 4536: if existing value is a hash, don't create another one
				if (ref $value eq 'HASH') {
					$find{$key} = $value;
				} else {
					$find{$key} = { 'like' => Slim::Utils::Text::searchStringSplit($value) };
				}

			} else {

				$find{$key} = Slim::Utils::Text::ignoreCaseArticles($value);
			}
		}
	}

	# 
	if (my $fieldKey = $find{'fieldInfo'}) {

		return Slim::Schema->rs($fieldKey)->browse({ 'audio' => 1 });

	} elsif ($find{'playlist.id'} && !$find{'me.id'}) {

		# Treat playlists specially - they are containers.
		my $playlist = Slim::Schema->find('Playlist', $find{'playlist.id'});

		if (blessed($playlist) && $playlist->can('tracks')) {

			$client->currentPlaylist($playlist);

			return $playlist->tracks;
		}

		return ();

	} else {

		# on search, only grab audio items.
		$find{'audio'} = 1;
		$find{'remote'} = 0;

		# Bug 2271 - allow VA albums.
		if (defined $find{'album.compilation'} && $find{'album.compilation'} == 1) {

			delete $find{'contributor.id'};
		}

		if ($find{'album.id'} && $find{'contributor.id'} && 
			$find{'contributor.id'} == Slim::Schema->variousArtistsObject->id) {

			delete $find{'contributor.id'};
		}

		if ($find{'playlist.id'}) {
		
			delete $find{'playlist.id'};
		}

		# If we have an album and a year - remove the year, since
		# there is no explict relationship between Track and Year.
		if ($find{'album.id'} && $find{'year.id'}) {

			delete $find{'year.id'};
			delete $joinMap{'year'};

		} elsif ($find{'year.id'}) {

			$find{'album.year'} = delete $find{'year.id'};
			delete $joinMap{'year'};
		}

		# Bug: 3629 - if we're sorting by album - be sure to include it in the join table.
		if ($sort && $sort eq $albumSort) {
			$joinMap{'album'} = 'album';
		}

		# limit & offset may have been populated above.
		$attrs{'order_by'} = $sort || $trackSort;
		$attrs{'join'}     = [ map { $_ } values %joinMap ];

		return Slim::Schema->rs('Track')->search(\%find, \%attrs)->distinct->all;
	}
}

sub _playlistXtracksCommand_constructTrackList {
	my $client  = shift;
	my $term    = shift;
	my $list    = shift;
	
	my @list = split /,/, $list;
	my @tracks = ();
	for my $url ( @list ) {
		my $track = Slim::Schema->rs('Track')->objectForUrl($url);
		push @tracks, $track if blessed($track) && $track->id;
	}

	return @tracks;

}

sub _playlistXtracksCommand_parseListRef {
	my $client  = shift;
	my $term    = shift;
	my $listRef = shift;

	if ($term =~ /listref=(\w+)&?/i) {
		$listRef = $client->modeParam($1);
	}

	if (defined $listRef && ref $listRef eq "ARRAY") {

		return @$listRef;
	}
}

sub _playlistXtracksCommand_parseSearchRef {
	my $client    = shift;
	my $term      = shift;
	my $searchRef = shift;

	if ($term =~ /searchRef=(\w+)&?/i) {
		$searchRef = $client->modeParam($1);
	}

	my $cond = $searchRef->{'cond'} || {};
	my $attr = $searchRef->{'attr'} || {};

	# XXX - For some reason, the join key isn't passed along with the ref.
	# Perl bug because 'join' is a keyword?
	if (!$attr->{'join'} && $attr->{'joins'}) {
		$attr->{'join'} = delete $attr->{'joins'};
	}

	return Slim::Schema->rs('Track')->search($cond, $attr)->distinct->all;
}

# Allow any URL to be a favorite - this includes things like iTunes playlists.
sub _playlistXtracksCommand_parseDbItem {
	my $client  = shift;
	my $url     = shift;

	my %classes;
	my $class   = 'Track';
	my $obj     = undef;

	# Bug: 2569
	# We need to ask for the right type of object.
	# 
	# Contributors, Genres & Albums have a url of:
	# db:contributor.namesearch=BEATLES
	#
	# Remote playlists are Track objects, not Playlist objects.
	if ($url =~ /^db:(\w+\.\w+=.+)$/) {
	  
		for my $term ( split '&', $1 ) {

			# If $terms has a leading &, split will generate an initial empty string
			next if !$term;

			if ($term =~ /^(\w+)\.(\w+)=(.*)$/) {

				my $key   = URI::Escape::uri_unescape($2);
				my $value = URI::Escape::uri_unescape($3);

				$class = ucfirst($1);
				$obj   = Slim::Schema->single( $class, { $key => $value } );
				
				$classes{$class} = $obj;
			}
		}

	}
	elsif ( Slim::Music::Info::isPlaylist($url) && !Slim::Music::Info::isRemoteURL($url) ) {

		%classes = (
			Playlist => Slim::Schema->rs($class)->objectForUrl( {
				url => $url,
			} )
		);
	}
	else {

		# else we assume it's a track
		%classes = (
			Track => Slim::Schema->rs($class)->objectForUrl( {
				url => $url,
			} )
		);
	}

	# Bug 4790: we get a track object of content type 'dir' if a fileurl for a directory is passed
	# this needs scanning so pass empty list back to playlistXitemCommand in this case
	my $terms = "";
	while ( ($class, $obj) = each %classes ) {
		if ( blessed($obj) && (
			$class eq 'Album' || 
			$class eq 'Contributor' || 
			$class eq 'Genre' ||
			$class eq 'Year' ||
			( $obj->can('content_type') && $obj->content_type ne 'dir') 
		) ) {
			$terms .= "&" if ( $terms ne "" );
			$terms .= sprintf( '%s.id=%d', lc($class), $obj->id );
		}
	}
	
	if ( $terms ne "" ) {
			return _playlistXtracksCommand_parseSearchTerms($client, $terms);
	}
	else {
		return ();
	}
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
