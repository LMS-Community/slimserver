package Slim::Control::Commands;

# $Id: Command.pm 5121 2005-11-09 17:07:36Z dsully $
#
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

use Slim::Utils::Misc;

use Slim::Control::Request;


sub prefCommand {
	my $request = shift;
	
	if ($request->isNotCommand(['pref'])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# uses positional things as backups
	my $prefName = $request->getParam('prefName') || $request->getParam('_p1');
	my $newValue = $request->getParam('newValue') || $request->getParam('_p2');

	if (!defined $prefName || !defined $newValue) {
		$request->setStatusBadParams();
		return;
	}	

	Slim::Utils::Prefs::set($prefName, $newValue);
	
	$request->setStatusDone();
}


sub rescanCommand {
	my $request = shift;
	
	if ($request->isNotCommand(['rescan'])) {
		$request->setStatusBadDispatch();
		return;
	}

	my $playlistsOnly = $request->getParam('playlistsOnly') || $request->getParam('_p1') || 0;
	
	# if we're scanning allready, don't do it twice
	if (!Slim::Utils::Misc::stillScanning()) {

		if ($playlistsOnly) {

			Slim::Music::Import::scanPlaylistsOnly(1);

		} else {

			Slim::Music::Import::cleanupDatabase(1);
		}

		Slim::Music::Info::clearPlaylists();
		Slim::Music::Import::resetImporters();
		Slim::Music::Import::startScan();
	}

	$request->setStatusDone();
}

sub wipecacheCommand {
	my $request = shift;
	
	if ($request->isNotCommand(['wipecache'])) {
		$request->setStatusBadDispatch();
		return;
	}

	# no parameters
	
	# if we're scanning allready, don't do it twice
	if (!Slim::Utils::Misc::stillScanning()) {

		# Clear all the active clients's playlists
		for my $client (Slim::Player::Client::clients()) {

			$client->execute([qw(playlist clear)]);
		}

		Slim::Music::Info::clearPlaylists();
		Slim::Music::Info::wipeDBCache();
		Slim::Music::Import::resetImporters();
		Slim::Music::Import::startScan();
	}

	$request->setStatusDone();
}

sub debugCommand {
	my $request = shift;
	
	# check this is the correct command. Syntax approved by Dean himself!
	if ($request->isNotCommand(['debug'])) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# use positional parameters as backups
	my $debugFlag = $request->getParam('debugFlag') || $request->getParam('_p1');
	my $newValue = $request->getParam('newValue') || $request->getParam('_p2');
	
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



1;
