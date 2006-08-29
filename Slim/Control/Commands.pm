package Slim::Control::Commands;

# $Id: Commands.pm 5121 2005-11-09 17:07:36Z dsully $
#
# SlimServer Copyright (c) 2001-2006  Sean Adams, Slim Devices Inc.
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

Implements most SlimServer commands and is designed to be exclusively called
through Request.pm and the mechanisms it defines.

The code for the "alarm" command is heavily commented and corresponds to a
"model" synchronous command.  Check CLI handling code in the Shoutcast plugin
for an asynchronous command.

=cut

use strict;

use Scalar::Util qw(blessed);
use File::Spec::Functions qw(catfile);
use File::Basename qw(basename);

use Slim::Utils::Alarms;
use Slim::Utils::Misc;
use Slim::Utils::Scanner;

my $d_commands = 0; # local debug flag


sub alarmCommand {
	# functions designed to execute requests have a single parameter, the
	# Request object
	my $request = shift;
	
	# this is convenient to check the mapping in debug mode.
	$d_commands && msg("Commands::alarmCommand()\n");

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
	my $cmd         = $request->getParam('cmd');
	my $fade        = $request->getParam('fade');
	my $dow         = $request->getParam('dow');
	my $enable      = $request->getParam('enabled');
	my $time        = $request->getParam('time');
	my $volume      = $request->getParam('volume');
	my $playlisturl = $request->getParam('url');
	my $playlistid  = $request->getParam('playlist_id');
	
	# validate the parameters using request's convenient functions
	if ($request->paramUndefinedOrNotOneOf($cmd, ['set', 'clear', 'update']) ||
		$request->paramNotOneOfIfDefined($fade, ['0', '1']) ||
		$request->paramNotOneOfIfDefined($dow, ['0', '1', '2', '3', '4', '5', '6', '7']) ) {
		
		# set an appropriate error state if something is wrong
		$request->setStatusBadParams();
		return;
	}
	
	# more parameter checking and reporting
	if (!defined $fade && !defined $dow) {
		$request->setStatusBadParams();
		return;
	}
	
	my $alarm;
	
	if ($cmd eq 'update') {
		$alarm = Slim::Utils::Alarms->newLoaded($client, $dow);
	} else {
		$alarm = Slim::Utils::Alarms->new($client, $dow);
	}
	
	if (defined $alarm) {
		if ($cmd eq 'set' || $cmd eq 'update') {
		
			$client->prefSet('alarmfadeseconds', $fade) if defined $fade;
			$alarm->time($time) if defined $time;
			$alarm->playlistid($playlistid) if defined $playlistid;
			$alarm->playlist($playlisturl) if defined $playlisturl;
			$alarm->volume($volume) if defined $volume;
			$alarm->enabled($enable) if defined $enable;
		}

		$alarm->save();
		
		# we add a result for the benefit of the caller (in this case, most
		# likely the CLI).
		$request->addResult('count', 1);
	}
	
	# indicate the request is done. This enables execute to continue with
	# calling the callback and notifying, etc...
	$request->setStatusDone();
}


sub buttonCommand {
	my $request = shift;
	
	$d_commands && msg("Commands::buttonCommand()\n");

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
	
	Slim::Hardware::IR::executeButton($client, $button, $time, undef, defined($orFunction) ? $orFunction : 1);
	
	$request->setStatusDone();
}


sub clientForgetCommand {
	my $request = shift;
	
	$d_commands && msg("Commands::clientForgetCommand()\n");

	# check this is the correct command. Syntax approved by Dean himself!
	if ($request->isNotCommand([['client'], ['forget']])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# get the parameters
	my $client = $request->client();
	
	# Bug 3115, temporarily unsync player when disconnecting
	if ( Slim::Player::Sync::isSynced($client) ) {
		Slim::Player::Sync::unsync( $client, 'temp' );
	}

	$client->forgetClient();
	
	$request->setStatusDone();
}


sub debugCommand {
	my $request = shift;
	
	$d_commands && msg("Commands::debugCommand()\n");

	# check this is the correct command. Syntax approved by Dean himself!
	if ($request->isNotCommand([['debug']])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# get the parameters
	my $debugFlag = $request->getParam('_debugflag');
	my $newValue = $request->getParam('_newvalue');
	
	if ( !defined $debugFlag || !($debugFlag =~ /^d_/) ) {
		$request->setStatusBadParams();
		return;
	}
	
	$debugFlag = "::" . $debugFlag;
	no strict 'refs';
	
	if (defined($newValue)) {
		$$debugFlag = $newValue;
	} else {
		# toggle if we don't have a new value
		$$debugFlag = ($$debugFlag ? 0 : 1);
	}
	
	$request->setStatusDone();
}


sub displayCommand {
	my $request = shift;
	
	$d_commands && msg("Commands::displayCommand()\n");

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

	$client->showBriefly($line1, $line2, $duration, $p4);
	
	$request->setStatusDone();
}

sub irCommand {
	my $request = shift;
	
	$d_commands && msg("Commands::irCommand()\n");

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


sub mixerCommand {
	my $request = shift;
	
	$d_commands && msg("Commands::mixerCommand()\n");

	# check this is the correct command.
	if ($request->isNotCommand([['mixer'], ['volume', 'muting', 'treble', 'bass', 'pitch']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get the parameters
	my $client   = $request->client();
	my $entity   = $request->getRequest(1);
	my $newvalue = $request->getParam('_newvalue');

	my @buddies;

	# if we're sync'd, get our buddies
	if (Slim::Player::Sync::isSynced($client)) {
		@buddies = Slim::Player::Sync::syncedWith($client);
	}
	
	if ($entity eq 'muting') {
	
		my $curmute = $client->prefGet("mute");
	
		if (!defined $newvalue) { # toggle
			$newvalue = !$curmute;
		}
		
		if ($newvalue != $curmute) {
			my $vol = $client->volume();
			my $fade;
			
			if ($newvalue == 0) {
				# need to un-mute volume
				$::d_command && msg("Unmuting, volume is $vol.\n");
				$client->prefSet("mute", 0);
				$fade = 0.3125;
			} else {
				# need to mute volume
				$::d_command && msg("Muting, volume is $vol.\n");
				$client->prefSet("mute", 1);
				$fade = -0.3125;
			}
	
			$client->fade_volume($fade, \&_mixer_mute, [$client]);
	
			for my $eachclient (@buddies) {
				if ($eachclient->prefGet('syncVolume')) {
					$eachclient->fade_volume($fade, \&_mixer_mute, [$eachclient]);
				}
			}
		}
	} else {
		my $newval;
		my $oldval = $client->$entity();

		if ($newvalue =~ /^[\+\-]/) {
			$newval = $oldval + $newvalue;
		} else {
			$newval = $newvalue;
		}

		$newval = $client->$entity($newval);

		for my $eachclient (@buddies) {
			if ($eachclient->prefGet('syncVolume')) {
				$eachclient->prefSet($entity, $newval);
				$eachclient->$entity($newval);
				Slim::Display::Display::volumeDisplay($eachclient) if $entity eq 'volume';
			}
		}
	}
		
	$request->setStatusDone();
}


sub playcontrolCommand {
	my $request = shift;
	
	$d_commands && msg("playcontrolCommand()\n");

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
		if ($newvalue) {
			$wantmode = $newvalue ? 'pause' : 'play';
		} else {
			$wantmode = ($curmode eq 'pause') ? 'play' : 'pause';
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
		
		# set new playmode
		Slim::Player::Source::playmode($client, $wantmode);

		# reset rate in all cases
		Slim::Player::Source::rate($client, 1);
		
		# update the display
		$client->update();
	}
		
	$request->setStatusDone();
}


sub playlistClearCommand {
	my $request = shift;
	
	$d_commands && msg("Commands::playlistClearCommand()\n");

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

	$client->currentPlaylist(undef);
	$client->currentPlaylistChangeTime(time());
	
	# The above changes the playlist but I am not sure this is ever
	# executed, or even if it should be
	Slim::Player::Playlist::refreshPlaylist($client) if $client->currentPlaylistModified();
	
	$request->setStatusDone();
}


sub playlistDeleteCommand {
	my $request = shift;
	
	$d_commands && msg("Commands::playlistDeleteCommand()\n");

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
	$client->currentPlaylistChangeTime(time());
	Slim::Player::Playlist::refreshPlaylist($client);
	
	$request->setStatusDone();
}


sub playlistDeleteitemCommand {
	my $request = shift;
	
	$d_commands && msg("Commands::playlistDeleteitemCommand()\n");

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

				errorMsg("Couldn't open playlist file $absitem : $!\n");
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
	$client->currentPlaylistChangeTime(time());
	Slim::Player::Playlist::refreshPlaylist($client);
	
	$request->setStatusDone();
}


sub playlistJumpCommand {
	my $request = shift;
	
	$d_commands && msg("Commands::playlistJumpCommand()\n");

	# check this is the correct command.
	if ($request->isNotCommand([['playlist'], ['jump', 'index']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get the parameters
	my $client = $request->client();
	my $index  = $request->getParam('_index');;
	my $noplay = $request->getParam('_noplay');;
	
	Slim::Player::Source::jumpto($client, $index, $noplay);

	# Does the above change the playlist?
	Slim::Player::Playlist::refreshPlaylist($client) if $client->currentPlaylistModified();
	
	$request->setStatusDone();
}


sub playlistMoveCommand {
	my $request = shift;
	
	$d_commands && msg("Commands::playlistMoveCommand()\n");

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
	$client->currentPlaylistChangeTime(time());
	
	Slim::Player::Playlist::refreshPlaylist($client);
	
	$request->setStatusDone();
}


sub playlistRepeatCommand {
	my $request = shift;
	
	$d_commands && msg("Commands::playlistRepeatCommand()\n");

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
	
	$d_commands && msg("Commands::playlistSaveCommand()\n");

	# check this is the correct command.
	if ($request->isNotCommand([['playlist'], ['save']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get the parameters
	my $client = $request->client();
	my $title  = $request->getParam('_title');
	my $titlesort = Slim::Utils::Text::ignoreCaseArticles($title);

	my $playlistObj = Slim::Schema->rs('Playlist')->updateOrCreate({

		'url' => Slim::Utils::Misc::fileURLFromPath(
			catfile( Slim::Utils::Prefs::get('playlistdir'), $title . '.m3u')
		),

		'attributes' => {
			'TITLE' => $title,
			'CT'    => 'ssp',
		},
	});

	my $annotatedList = [];

	if (Slim::Utils::Prefs::get('saveShuffled')) {

		for my $shuffleitem (@{Slim::Player::Playlist::shuffleList($client)}) {
			push @$annotatedList, @{Slim::Player::Playlist::playList($client)}[$shuffleitem];
		}
				
	} else {

		$annotatedList = Slim::Player::Playlist::playList($client);
	}

	$playlistObj->set_column('titlesort', $titlesort);
	$playlistObj->setTracks($annotatedList);
	$playlistObj->update;

	Slim::Schema->forceCommit;

	Slim::Player::Playlist::scheduleWriteOfPlaylist($client, $playlistObj);

	$request->addResult('__playlist_id', $playlistObj->id);
	$request->addResult('__playlist_obj', $playlistObj);

	$request->setStatusDone();
}


sub playlistShuffleCommand {
	my $request = shift;
	
	$d_commands && msg("Commands::playlistShuffleCommand()\n");

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
	$client->currentPlaylistChangeTime(time());
	
	# Does the above change the playlist?
	Slim::Player::Playlist::refreshPlaylist($client) if $client->currentPlaylistModified();
	
	$request->setStatusDone();
}


sub playlistXalbumCommand {
	my $request = shift;

	$d_commands && msg("Commands::playlistXalbumCommand()\n");

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

	# Pass to Schema
	my $find     = {};
	my @joins    = ();
	my $attrs    = {
		'order_by' => 'me.disc, me.tracknum, me.titlesort'
	};

	# Find the songs for the passed params
	my $sort = 'track';

	if (specified($genre)) {

		$find->{'genre.name'} = _playlistXalbum_singletonRef($genre);

		push @joins, { 'genreTracks' => 'genre' };
	}

	if (specified($artist)) {

		$find->{'contributor.name'} = _playlistXalbum_singletonRef($artist);

		push @joins, { 'contributorTracks' => 'contributor' };
	}

	if (specified($album)) {

		$find->{'album.title'} = _playlistXalbum_singletonRef($album);

		push @joins, 'album';
	}

	if (specified($title)) {

		$find->{'me.title'} = _playlistXalbum_singletonRef($title);
	}

	if (scalar @joins) {
		$attrs->{'join'} = \@joins;
	}

	my @results = Slim::Schema->search('Track', $find, $attrs)->all;

	$cmd =~ s/album/tracks/;

	Slim::Control::Request::executeRequest($client, ['playlist', $cmd, 'listRef', \@results]);

	$request->setStatusDone();
}


sub playlistXitemCommand {
	my $request = shift;
	
	$d_commands && msg("Commands::playlistXitemCommand()\n");

	# check this is the correct command.
	if ($request->isNotCommand([['playlist'], ['add', 'append', 'insert', 'insertlist', 'load', 'play', 'resume']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get the parameters
	my $client   = $request->client();
	my $cmd      = $request->getRequest(1); #p1
	my $item     = $request->getParam('_item'); #p2

	if (!defined $item) {
		$request->setStatusBadParams();
		return;
	}

	my $jumpToIndex; # This should be undef - see bug 2085
	my $results;

	my $url  = blessed($item) ? $item->url : $item;

	# Strip off leading and trailing whitespace. PEBKAC
	$url =~ s/^\s*//;
	$url =~ s/\s*$//;

	my $path = $url;

	# correct the path
	# this only seems to be useful for playlists?
	if (!Slim::Music::Info::isRemoteURL($path) && !-e $path && !(Slim::Music::Info::isPlaylistURL($path))) {

		my $easypath = catfile(Slim::Utils::Prefs::get('playlistdir'), basename($url) . ".m3u");

		if (-e $easypath) {

			$path = $easypath;

		} else {

			$easypath = catfile(Slim::Utils::Prefs::get('playlistdir'), basename($url) . ".pls");

			if (-e $easypath) {
				$path = $easypath;
			}
		}
	}

	# Un-escape URI that have been escaped again.
	if (Slim::Music::Info::isRemoteURL($path) && $path =~ /%3A%2F%2F/) {

		$path = Slim::Utils::Misc::unescape($path);
	}

	if ($cmd =~ /^(play|load|resume)$/) {

		Slim::Player::Source::playmode($client, 'stop');
		Slim::Player::Playlist::clear($client);

		$client->currentPlaylist( Slim::Utils::Misc::fixPath($path) );

		$client->currentPlaylistModified(0);

	} elsif ($cmd =~ /^(add|append)$/) {

		$client->currentPlaylist( Slim::Utils::Misc::fixPath($path) );
		$client->currentPlaylistModified(1);

	} else {

		$client->currentPlaylistModified(1);
	}

	if (!Slim::Music::Info::isRemoteURL($path) && Slim::Music::Info::isFileURL($path)) {

		$path = Slim::Utils::Misc::pathFromFileURL($path);
	}

	if ($cmd =~ /^(play|load)$/) { 

		$jumpToIndex = 0;

	} elsif ($cmd eq "resume" && Slim::Music::Info::isM3U($path)) {

		$jumpToIndex = Slim::Formats::Playlists::M3U->readCurTrackForM3U($path);
	}
					
	if ($cmd =~ /^(insert|insertlist)$/) {

		my $playListSize = Slim::Player::Playlist::count($client);
		my @dirItems     = ();

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

	} else {
		
		# Display some feedback for the player on remote URLs
		if ( Slim::Music::Info::isRemoteURL($path) ) {
			my $line1 = $client->string('NOW_PLAYING') . ' (' . $client->string('CHECKING_STREAM') . ')';
			my $line2 = Slim::Music::Info::title($path) || $path;
			if ( $client->linesPerScreen() == 1 ) {
				$line2 = $client->string('CHECKING_STREAM');
			}
			my $timeout = Slim::Utils::Prefs::get('remotestreamtimeout') || 10;
			$client->showBriefly( $line1, $line2, $timeout + 5 );
		}			

		Slim::Utils::Scanner->scanPathOrURL({
			'url'      => $path,
			'listRef'  => Slim::Player::Playlist::playList($client),
			'client'   => $client,
			'callback' => sub {
				my ( $foundItems, $error ) = @_;

				push @{ Slim::Player::Playlist::playList($client) }, @{$foundItems};

				_playlistXitem_load_done(
					$client,
					$jumpToIndex,
					$request->callbackFunction,
					$request->callbackArguments,
					scalar @{Slim::Player::Playlist::playList($client)},
					$path,
					$error,
				);

				playlistXitemCommand_done( $client, $request, $path );
			},
		});

	}
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

	$client->currentPlaylistChangeTime(time());

	Slim::Player::Playlist::refreshPlaylist($client) if $client->currentPlaylistModified();

	$request->setStatusDone();
}

sub playlistXtracksCommand {
	my $request = shift;
	
	$d_commands && msg("Commands::playlistXtracksCommand()\n");

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

	if ($what =~ /listRef/i) {

		@tracks = _playlistXtracksCommand_parseListRef($client, $what, $listref);

	} elsif ($what =~ /favorite/i) {

		@tracks = _playlistXtracksCommand_parseFavorite($client, $what, $listref);

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

		Slim::Player::Source::jumpto($client, $jumpToIndex);
		$client->currentPlaylistModified(0);
	}

	if ($add || $insert || $delete) {
		$client->currentPlaylistModified(1);
	}

	if ($load || $add || $insert || $delete) {
		$client->currentPlaylistChangeTime(time);
	}

	Slim::Player::Playlist::refreshPlaylist($client) if $client->currentPlaylistModified();

	$request->setStatusDone();
}

sub playlistZapCommand {
	my $request = shift;
	
	$d_commands && msg("Commands::playlistZapCommand()\n");

	# check this is the correct command.
	if ($request->isNotCommand([['playlist'], ['zap']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get the parameters
	my $client   = $request->client();
	my $index    = $request->getParam('_index');;
	
	my $zapped   = Slim::Utils::Strings::string('ZAPPED_SONGS');
	my $zapindex = defined $index ? $index : Slim::Player::Source::playingSongIndex($client);
	my $zapsong  = Slim::Player::Playlist::song($client, $zapindex);

	#  Remove from current playlist
	if (Slim::Player::Playlist::count($client) > 0) {

		# Call ourselves.
		Slim::Control::Request::executeRequest($client, ["playlist", "delete", $zapindex]);
	}

	my $playlistObj = Slim::Schema->rs('Playlist')->updateOrCreate({
		'url'        => Slim::Utils::Misc::fileURLFromPath(
			catfile( Slim::Utils::Prefs::get('playlistdir'), $zapped . '.m3u')
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
	$client->currentPlaylistChangeTime(time());
	Slim::Player::Playlist::refreshPlaylist($client);
	
	$request->setStatusDone();
}


sub playlistcontrolCommand {
	my $request = shift;
	
	$d_commands && msg("Commands::playlistcontrolCommand()\n");

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

	# if loading, first stop everything
	if ($load) {
		Slim::Player::Source::playmode($client, "stop");
		Slim::Player::Playlist::clear($client);
	}

	# find the songs
	my @tracks = ();

	if (defined(my $playlist_id = $request->getParam('playlist_id'))) {

		# Special case...
		my $playlist = Slim::Schema->find('Playlist', $playlist_id);

		if (blessed($playlist) && $playlist->can('tracks')) {

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

		@tracks = Slim::Schema->search('Track', { 'id' => { 'in' => \@track_ids } })->all;

	} else {

		my $find  = {};
		my @joins = ();

		if (defined(my $genre_id = $request->getParam('genre_id'))) {

			$find->{'genreTracks.genre'} = $genre_id;

			push @joins, 'genreTracks';
		}

		if (defined(my $artist_id = $request->getParam('artist_id'))) {

			$find->{'contributorTracks.contributor'} = $artist_id;

			push @joins, 'contributorTracks';
		}

		if (defined(my $album_id = $request->getParam('album_id'))) {

			$find->{'me.album'} = $album_id;
		}

		if (defined(my $year_id = $request->getParam('year_id'))) {

			$find->{'me.year'} = $year_id;
		}

		@tracks = Slim::Schema->search('Track', $find, {
			'order_by' => 'me.disc, me.tracknum, me.titlesort',
			'join'     => \@joins,
		})->all;
	}

	# don't call Xtracks if we got no songs
	if (@tracks) {

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
	
	$d_commands && msg("Commands::playlistsEditCommand()\n");

	# check this is the correct command.
	if ($request->isNotCommand([['playlists'], ['edit']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get the parameters
	my $playlist_id = $request->getParam('playlist_id');
	my $cmd = $request->getParam('cmd');
	my $itemPos = $request->getParam('index');

	if ($request->paramUndefinedOrNotOneOf($cmd, ['up', 'down', 'delete', 'add'])) {
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
	
	} elsif ($cmd eq 'add') {

		# Add function - Add entry it not already in list
		my $found = 0;
		my $title = $request->getParam('title');
		my $url   = $request->getParam('url');

		if ($title && $url) {

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

			$playlistTrack->title($title);
			$playlistTrack->titlesort(Slim::Utils::Text::ignoreCaseArticles($title));
			$playlistTrack->titlesearch(Slim::Utils::Text::ignoreCaseArticles($title));
			$playlistTrack->update;

			$changed = 1;
		}
	}

	if ($changed) {
		$::d_playlist && msg("Playlist has changed via editing - saving new list of tracks.\n");

		$playlist->setTracks(\@items);
		$playlist->update;

		if ($playlist->content_type eq 'ssp') {

			$::d_playlist && msg("Writing out playlist to disk..\n");

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
	
	$d_commands && msg("Commands::playlistsDeleteCommand()\n");

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

	if (!blessed($playlistObj)) {
		$request->setStatusBadParams();
		return;
	}
	
	Slim::Player::Playlist::removePlaylistFromDisk($playlistObj);
	
	# Do a fast delete, and then commit it.
	$playlistObj->setTracks([]);
	$playlistObj->delete;

	$playlistObj = undef;

	Slim::Schema->forceCommit;

	$request->setStatusDone();
}


sub playlistsRenameCommand {
	my $request = shift;
	
	$d_commands && msg("Commands::playlistsRenameCommand()\n");

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
	
	# now perform the operation
		
	# don't allow periods, colons, control characters, slashes, backslashes, just to be safe.
	$newName     =~ tr|.:\x00-\x1f\/\\| |s;
	
	my $newUrl   = Slim::Utils::Misc::fileURLFromPath(
		catfile(Slim::Utils::Prefs::get('playlistdir'), $newName . '.m3u')
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

sub playerprefCommand {
	my $request = shift;
	
	$d_commands && msg("Commands::playerprefCommand()\n");

	if ($request->isNotCommand([['playerpref']])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# get our parameters
	my $client   = $request->client();
	my $prefName = $request->getParam('_prefname');
	my $newValue = $request->getParam('_newvalue');

	if (!defined $prefName || !defined $newValue) {
		$request->setStatusBadParams();
		return;
	}	

	$client->prefSet($prefName, $newValue);
	
	$request->setStatusDone();
}


sub powerCommand {
	my $request = shift;
	
	$d_commands && msg("Commands::powerCommand()\n");

	# check this is the correct command.
	if ($request->isNotCommand([['power']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get our parameters
	my $client   = $request->client();
	my $newpower = $request->getParam('_newvalue');
	
	# handle toggle
	if (!defined $newpower) {

		$newpower = $client->power() ? 0 : 1;
	}

	# handle sync'd players
	if (Slim::Player::Sync::isSynced($client)) {

		my @buddies = Slim::Player::Sync::syncedWith($client);
		
		for my $eachclient (@buddies) {
			$eachclient->power($newpower) if $eachclient->prefGet('syncPower');
		}
	}

	$client->power($newpower);

	# Powering off cancels sleep...
	if ($newpower eq "0") {
		Slim::Utils::Timers::killTimers($client, \&_sleepStartFade);
		Slim::Utils::Timers::killTimers($client, \&_sleepPowerOff);
		$client->sleepTime(0);
		$client->currentSleepTime(0);
	}
		
	$request->setStatusDone();
}


sub prefCommand {
	my $request = shift;
	
	$d_commands && msg("Commands::prefCommand()\n");

	if ($request->isNotCommand([['pref']])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# get our parameters
	my $prefName = $request->getParam('_prefname');
	my $newValue = $request->getParam('_newvalue');

	if (!defined $prefName || !defined $newValue) {
		$request->setStatusBadParams();
		return;
	}	

	Slim::Utils::Prefs::set($prefName, $newValue);
	
	$request->setStatusDone();
}


sub rateCommand {
	my $request = shift;
	
	$d_commands && msg("Commands::rateCommand()\n");

	# check this is the correct command.
	if ($request->isNotCommand([['rate']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get our parameters
	my $client  = $request->client();
	my $newrate = $request->getParam('_newvalue');
	
	if (!defined $newrate) {
		$request->setStatusBadParams();
		return;
	}
	
	if ($client->directURL() || $client->audioFilehandleIsSocket) {
		Slim::Player::Source::rate($client, 1);
		# shouldn't we return an error here ???
	} else {
		Slim::Player::Source::rate($client, $newrate);
	}
	
	$request->setStatusDone();
}


sub rescanCommand {
	my $request = shift;
	
	$d_commands && msg("Commands::rescanCommand()\n");

	if ($request->isNotCommand([['rescan']])) {
		$request->setStatusBadDispatch();
		return;
	}

	# get our parameters
	my $playlistsOnly = $request->getParam('_playlists') || 0;
	
	# if we're scanning allready, don't do it twice
	if (!Slim::Music::Import->stillScanning()) {

		my %args = (
			'rescan' => 1,
		);

		if ($playlistsOnly) {

			$args{'playlists'} = 1;

		} else {

			$args{'cleanup'} = 1;
		}

		Slim::Music::Import->launchScan(\%args);
	}

	$request->setStatusDone();
}

sub showCommand {
	my $request = shift;
	
	$d_commands && msg("Commands::showCommand()\n");

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
			'graphic-280x16' => 'huge',
			'text'           => 1,
		};		
	}
	else {
		$hash->{'fonts'} = {
			'graphic-320x32' => 'standard',
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
	
	$d_commands && msg("Commands::sleepCommand()\n");

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
		
	} else {

		# finish canceling any sleep in progress
		$client->sleepTime(0);
		$client->currentSleepTime(0);
	}
	
	$request->setStatusDone();
}


sub syncCommand {
	my $request = shift;
	
	$d_commands && msg("Commands::syncCommand()\n");

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
	
		Slim::Player::Sync::unsync($client);
		
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
		
		Slim::Player::Sync::sync($buddy, $client) if defined $buddy;
	}
	
	$request->setStatusDone();
}


sub timeCommand {
	my $request = shift;
	
	$d_commands && msg("Commands::timeCommand()\n");

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
	
	$d_commands && msg("Commands::wipecacheCommand()\n");

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

################################################################################
# Helper functions
################################################################################

sub _sleepStartFade {
	my $client = shift;
	my $fadeDuration = shift;

	$d_commands && msg("Commands::_sleepStartFade()\n");
	
	if ($client->isPlayer()) {
		$client->fade_volume(-$fadeDuration);
	}
}

sub _sleepPowerOff {
	my $client = shift;
	
	$d_commands && msg("Commands::_sleepPowerOff()\n");

	$client->sleepTime(0);
	$client->currentSleepTime(0);
	
	Slim::Control::Request::executeRequest($client, ['stop']);
	Slim::Control::Request::executeRequest($client, ['power', 0]);
}


sub _mixer_mute {
	my $client = shift;

	$d_commands && msg("Commands::_mixer_mute()\n");

	$client->mute();
}


sub _playlistXitem_load_done {
	my ($client, $index, $callbackf, $callbackargs, $count, $url, $error) = @_;

	$d_commands && msg("Commands::_playlistXitem_load_done()\n");

	# dont' keep current song on loading a playlist
	Slim::Player::Playlist::reshuffle($client,
		(Slim::Player::Source::playmode($client) eq "play" || ($client->power && Slim::Player::Source::playmode($client) eq "pause")) ? 0 : 1
	);

	if (defined($index)) {
		Slim::Player::Source::jumpto($client, $index);
	}
	
	if ( !$count && $url ) {
		# If the playlist was unable to load a remote URL, notify
		# This is used for logging broken stream links
		Slim::Control::Request::notifyFromArray($client, ['playlist', 'cant_open', $url, $error]);
		
		# Show an error message
		$client->showBriefly({
			'line1'    => $client->string( $error || 'PROBLEM_OPENING_REMOTE_URL' ),
			'line2'    => $url,
		}, { 'duration' => 2, 'block' => 1, 'scroll' => 1, 'firstline' => 1 });
	}

	$callbackf && (&$callbackf(@$callbackargs));

	Slim::Control::Request::notifyFromArray($client, ['playlist', 'load_done']);
}


sub _insert_done {
	my ($client, $listsize, $size, $callbackf, $callbackargs) = @_;

	$d_commands && msg("Commands::_insert_done()\n");

	my $playlistIndex = Slim::Player::Source::streamingSongIndex($client)+1;
	my @reshuffled;

	if (Slim::Player::Playlist::shuffle($client)) {

		for (my $i = 0; $i < $size; $i++) {
			push @reshuffled, ($listsize + $i);
		};
			
		$client = Slim::Player::Sync::masterOrSelf($client);
		
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

	$d_commands && msg("Commands::_playlistXtracksCommand_parseSearchTerms()\n");

	my %find   = ();
	my $terms  = {};
	my %attrs  = ();
	my @fields = map { lc($_) } Slim::Schema->sources;
	my ($sort, $limit, $offset);

	# Bug: 3629 - sort by album, then disc, tracknum, titlesort
	my $albumSort = "concat(album.titlesort, '0'), me.disc, me.tracknum, concat(me.titlesort, '0')";
	my $trackSort = "me.disc, me.tracknum, concat(me.titlesort, '0')";

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

				$find{$key} = { 'like' => Slim::Utils::Text::searchStringSplit($value) };

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

sub _playlistXtracksCommand_parseListRef {
	my $client  = shift;
	my $term    = shift;
	my $listRef = shift;

	$d_commands && msg("Commands::_playlistXtracksCommand_parseListRef()\n");

	if ($term =~ /listref=(\w+)&?/i) {
		$listRef = $client->param($1);
	}

	if (defined $listRef && ref $listRef eq "ARRAY") {

		return @$listRef;
	}
}

sub _playlistXtracksCommand_parseSearchRef {
	my $client    = shift;
	my $term      = shift;
	my $searchRef = shift;

	$d_commands && msg("Commands::_playlistXtracksCommand_parseSearchRef()\n");

	if ($term =~ /searchRef=(\w+)&?/i) {
		$searchRef = $client->param($1);
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
sub _playlistXtracksCommand_parseFavorite {
	my $client  = shift;
	my $what    = shift;
	my $url     = shift;

	my $class   = 'Track';
	my $obj     = undef;
	my $terms   = undef;

	$d_commands && msg("Commands::_playlistXtracksCommand_parseFavorite()\n");

	# If coming from the web UI.
	if ($what =~ /favorite=(.+?)\&/i) {
		$url = Slim::Utils::Misc::unescape($1);
	}

	# Bug: 2569
	# We need to ask for the right type of object.
	# 
	# Contributors, Genres & Albums have a url of:
	# db:contributor.namesearch=BEATLES
	#
	# Remote playlists are Track objects, not Playlist objects.
	if ($url =~ /^db:(\w+)\.(\w+)=(.+)/) {

		$class = ucfirst($1);
		$obj   = Slim::Schema->single($class, { $2 => Slim::Utils::Misc::unescape($3) });

	} elsif (Slim::Music::Info::isPlaylist($url) && !Slim::Music::Info::isRemoteURL($url)) {

		$class = 'Playlist';
	}

	# else we assume it's a track
	if ($class eq 'Track' || $class eq 'Playlist') {

		$obj = Slim::Schema->rs($class)->objectForUrl({
			'url'      => $url,
			'create'   => 1,
			'readTags' => 1
		});
	}

	if (blessed($obj)) {

		$terms = sprintf('%s.id=%d', lc($class), $obj->id);
	}

	return _playlistXtracksCommand_parseSearchTerms($client, $terms);
}

sub _showCommand_done {
	my $args = shift;
	
	$d_commands && msg("Commands::_showCommand_done()\n");

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
