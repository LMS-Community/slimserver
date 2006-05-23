package Slim::Control::Command;

# SlimServer Copyright (C) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use Slim::Control::Request;
use Slim::Utils::Misc qw(msg errorMsg);

use Slim::DataStores::Base;
use Slim::Display::Display;
use Slim::Music::Info;
use Slim::Utils::Misc;
use Slim::Utils::Scanner;
use Slim::Utils::Strings qw(string);

use Slim::Control::Dispatch;

our %executeCallbacks = ();

# execute - did all the hard work, thanks. 
# PLEASE USE THE REQUEST.PM CLASS
# takes:
#   a client reference
#   a reference to an array of parameters
#   a reference to a callback function
#   a list of callback function args
#
# returns an array containing the given parameters

sub execute {

	my $p0 = $parrayref->[0];
	my $p1 = $parrayref->[1];
	my $p2 = $parrayref->[2];
	my $p3 = $parrayref->[3];
	my $p4 = $parrayref->[4];
	my $p5 = $parrayref->[5];
	my $p6 = $parrayref->[6];
	my $p7 = $parrayref->[7];

	my $callcallback = 1;
	my @returnArray = ();
	my $pushParams = 1;


	# Try and go through dispatch

	# Determine if this is a query
	my $query = 0;
	for my $p (@$parrayref) {
		# if a param is ? then it is a query...
		if ($p eq '?') {
			$query = 1;
			last;
		}
	}
	
	my $cmdText = $p0;
	
	# create a request
	my $cmd = new Slim::Control::Request($cmdText, $query, $client);
	
	# add all parameters by position
	my $first = 1;
	for my $p (@$parrayref) {
		# need to skip $p0 without changing the array
		# there is probably a more elegant Perl solution but this works...
		if (!$first && $p ne '?') {
			$cmd->addParamPos($p);
		}
		$first = 0;
	}
	
	$::d_command && $cmd->dump();
	
	$cmd->execute();
	
	if ($cmd->wasStatusDispatched()){
	
		$::d_command && $cmd->dump();
		
		# make sure we don't execute again if ever dispatch knows
		# about a command still below
		$p0 .= "(was dispatched)";
		
		# prevent pushing $p0 again..
		$pushParams = 0;
	
		# patch the return array so that callbacks function as before
		@returnArray = $cmd->getArray();
	}
		
# END

	$::d_command && msg("Executing command " . ($client ? $client->id() : "no client") . ": $p0 (" .
			(defined $p1 ? $p1 : "") . ") (" .
			(defined $p2 ? $p2 : "") . ") (" .
			(defined $p3 ? $p3 : "") . ") (" .
			(defined $p4 ? $p4 : "") . ") (" .
			(defined $p5 ? $p5 : "") . ") (" .
			(defined $p6 ? $p6 : "") . ") (" .
			(defined $p7 ? $p7 : "") . ")\n");
	
	

# The first parameter is the client identifier to execute the command. Column C in the
# table below indicates if a client is required (Y) or not (N) for the command.
#
# If a parameter is "?" it is replaced by the current value in the array
# returned by the function
#
# COMMAND LIST #
  
# C     P0             P1                          P2                            P3            P4         P5        P6
    
# GENERAL
# N    debug           <debugflag>                 <0|1|?|>
# N    pref            <prefname>                  <prefvalue|?>

# PLAYERS
# Y    sleep           <0..n|?>
# Y    sync            <playerindex|playerid|-|?>
# Y    power           <0|1|?|>
# Y    signalstrength  ?
# Y    connected       ?
# Y    mixer           volume                      <0..100|-100..+100|?>
# Y    mixer           balance                     (not implemented)
# Y    mixer           bass                        <0..100|-100..+100|?>
# Y    mixer           treble                      <0..100|-100..+100|?>
# Y    mixer           pitch                       <80..120|-100..+100|?>
# Y    mixer           muting
# Y    display         <line1>                     <line2>                       <duration>
# Y    display         ?                           ?
# Y    displaynow      ?                           ?
# Y    playerpref      <prefname>                  <prefvalue|?>
# Y    button          <buttoncode>
# Y    ir              <ircode>                    <time>
# Y    rate            <rate|?>

#DATABASE    
# N    rescan          <?>    	
# N    rescan          playlists
# N    wipecache

#PLAYLISTS
# Y    mode            <play|pause|stop|?>    
# Y    play        
# Y    pause           <0|1|>    
# Y    stop
# Y    time|gototime   <0..n|-n|+n|?>
# Y    genre           ?
# Y    artist          ?
# Y    album           ?
# Y    title           ?
# Y    duration        ?
# Y    path|url        ?
 
# Y    playlist        playtracks                  <searchterms>    
# Y    playlist        loadtracks                  <searchterms>    
# Y    playlist        addtracks                   <searchterms>    
# Y    playlist        inserttracks                <searchterms>    
# Y    playlist        deletetracks                <searchterms>   
# Y    playlistcontrol <params>

# Y    playlist        play|load                   <item>                       [<title>] (item can be a song, playlist or directory)
# Y    playlist        add|append                  <item>                       [<title>] (item can be a song, playlist or directory)
# Y    playlist        insert|insertlist           <item> (item can be a song, playlist or directory)
# Y    playlist        deleteitem                  <item> (item can be a song, playlist or directory)
# Y    playlist        move                        <fromindex>                 <toindex>    
# Y    playlist        delete                      <index>
# Y    playlist        resume                      <playlist>    
# Y    playlist        save                        <playlist>    
# Y    playlist        loadalbum|playalbum         <genre>                     <artist>         <album>        <songtitle>
# Y    playlist        addalbum                    <genre>                     <artist>         <album>        <songtitle>
# Y    playlist        insertalbum                 <genre>                     <artist>         <album>        <songtitle>
# Y    playlist        deletealbum                 <genre>                     <artist>         <album>        <songtitle>
# Y    playlist        clear    
# Y    playlist        zap                         <index>
# Y    playlist        name                        ?
# Y    playlist        url                         ?
# Y    playlist        modified                    ?
# Y    playlist        index|jump                  <index|?>    
# Y    playlist        genre                       <index>                     ?
# Y    playlist        artist                      <index>                     ?
# Y    playlist        album                       <index>                     ?
# Y    playlist        title                       <index>                     ?
# Y    playlist        duration                    <index>                     ?
# Y    playlist        tracks                      ?
# Y    playlist        shuffle                     <0|1|2|?|>
# Y    playlist        repeat                      <0|1|2|?|>

#NOTIFICATION
# The following 'terms' go through execute for its notification ability, but 
# do not actually do anything
# Y    favorite	       add         // Favorite plugin
# Y    newclient                   // there is a new client
# Y    newsong                     // song starts to play
# Y    open                        // file is opened (for playing)
# Y    playlist        sync


	my $ds   = Slim::Music::Info::getCurrentDataStore();
	my $find = {};

	if (!defined($p0)) {

		# ignore empty commands

# handled by dispatch
#	} elsif ($p0 eq "pref") {
#		
#		if (defined($p2) && $p2 ne '?' && !$::nosetup) {
#			Slim::Utils::Prefs::set($p1, $p2);
#		}
#
#		$p2 = Slim::Utils::Prefs::get($p1);
#
#		$client = undef;

# handled by dispatch
#	} elsif ($p0 eq "rescan") {
#	
#		if (defined $p1 && $p1 eq '?') {
#
#			$p1 = Slim::Utils::Misc::stillScanning() ? 1 : 0;
#
#		} elsif (!Slim::Utils::Misc::stillScanning()) {
#
#			if (defined $p1 && $p1 eq 'playlists') {
#
#				Slim::Music::Import::scanPlaylistsOnly(1);
#
#			} else {
#
#				Slim::Music::Import::cleanupDatabase(1);
#			}
#
#			Slim::Music::Info::clearPlaylists();
#			Slim::Music::Import::resetImporters();
#			Slim::Music::Import::startScan();
#		}
#
#		$client = undef;

# handled by dispatch
#	} elsif ($p0 eq "wipecache") {
#
#		if (!Slim::Utils::Misc::stillScanning()) {
#
#			# Clear all the active clients's playlists
#			for my $client (Slim::Player::Client::clients()) {
#
#				$client->execute([qw(playlist clear)]);
#			}
#
#			Slim::Music::Info::clearPlaylists();
#			Slim::Music::Info::wipeDBCache();
#			Slim::Music::Import::resetImporters();
#			Slim::Music::Import::startScan();
#		}
#		
#		$client = undef;
		
# handled by dispatch
#	} elsif ($p0 eq "version") {
#		$p1 = $::VERSION;

# handled by dispatch
#	} elsif ($p0 eq "debug") {
#
#		if ($p1 =~ /^d_/) {
#
#			my $debugsymbol = "::" . $p1;
#			no strict 'refs';
#
#			if (!defined($p2)) {
#
#				$$debugsymbol = ($$debugsymbol ? 0 : 1);
#
#			} elsif ($p2 eq "?")  {
#
#				$p2 = $$debugsymbol;
#				$p2 ||= 0;
#
#			} else {
#
#				$$debugsymbol = $p2;
#			}
#		}
#
#		$client = undef;
 		
 		
################################################################################
# The following commands require a valid client to be specified
################################################################################

	} elsif ($client) {

		if ($p0 eq "playerpref") {

			if (defined($p2) && $p2 ne '?' && !$::nosetup) {
				$client->prefSet($p1, $p2);
			}

			$p2 = $client->prefGet($p1);

		} elsif ($p0 eq "play") {

			Slim::Player::Source::playmode($client, "play");
			Slim::Player::Source::rate($client,1);
			$client->update();

		} elsif ($p0 eq "pause") {

			if (defined($p1)) {
				if ($p1 && Slim::Player::Source::playmode($client) eq "play") {
					$client->rate(1);
					Slim::Player::Source::playmode($client, "pause");
				} elsif (!$p1 && Slim::Player::Source::playmode($client) eq "pause") {
					Slim::Player::Source::playmode($client, "resume");
				} elsif (!$p1 && Slim::Player::Source::playmode($client) eq "stop") {
					Slim::Player::Source::playmode($client, "play");
				}
			} else {
				if (Slim::Player::Source::playmode($client) eq "pause") {
					Slim::Player::Source::playmode($client, "resume");
				} elsif (Slim::Player::Source::playmode($client) eq "play") {
					$client->rate(1);
					Slim::Player::Source::playmode($client, "pause");
				} elsif (Slim::Player::Source::playmode($client) eq "stop") {
					Slim::Player::Source::playmode($client, "play");
				}
			}
			$client->update();

		} elsif ($p0 eq "rate") {

			if ($client->directURL() || $client->audioFilehandleIsSocket) {
				Slim::Player::Source::rate($client, 1);
			} elsif (!defined($p1) || $p1 eq "?") {
				$p1 = Slim::Player::Source::rate($client);
			} else {
				Slim::Player::Source::rate($client,$p1);
			}

		} elsif ($p0 eq "stop") {

			Slim::Player::Source::playmode($client, "stop");
			# Next time we start, start at normal playback rate
			$client->rate(1);
			$client->update();

		} elsif ($p0 eq "mode") {

			if (!defined($p1) || $p1 eq "?") {
				$p1 = Slim::Player::Source::playmode($client);
			} else {
				if (Slim::Player::Source::playmode($client) eq "pause" && $p1 eq "play") {
					Slim::Player::Source::playmode($client, "resume");
				} else {
					Slim::Player::Source::playmode($client, $p1);
				}
				$client->update();
			}

		} elsif ($p0 eq "sleep") {
			if ($p1 eq "?") {
				$p1 = $client->sleepTime() - Time::HiRes::time();
				if ($p1 < 0) {
					$p1 = 0;
				}
			} else {
				Slim::Utils::Timers::killTimers($client, \&sleepStartFade);
				Slim::Utils::Timers::killTimers($client, \&sleepPowerOff);
				
				if ($p1 != 0) {
					my $fadeTime = 0;
					$fadeTime = $p1 - 40 if ($p1>40);
					my $offTime = $p1;
				
					Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + $offTime, \&sleepPowerOff);
					Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + $fadeTime, \&sleepStartFade);


					$client->sleepTime(Time::HiRes::time() + $offTime);
					$client->currentSleepTime($offTime / 60);
				} else {
					$client->sleepTime(0);
					$client->currentSleepTime(0);
				}
			}

		} elsif ($p0 eq "gototime" || $p0 eq "time") {
			if ($p1 eq "?") {
				$p1 = Slim::Player::Source::songTime($client);
			} else {
				Slim::Player::Source::gototime($client, $p1);
			}

		} elsif ($p0 =~ /^(duration|artist|album|title|genre)$/) {

			my $method = $1;
			my $url    = Slim::Player::Playlist::song($client);
			my $track  = $ds->objectForUrl(Slim::Player::Playlist::song($client));

			if (blessed($track) && $track->can('secs')) {

				if ($p0 eq 'duration') {
				
					$p1 = $track->secs() || 0;
					
				} else {

					$p1 = $track->$method() || 0;
				}

			} else {

				msg("Couldn't fetch object for URL: [$url] - skipping track\n");
				bt();
			}

		} elsif ($p0 eq "path") {

			$p1 = Slim::Player::Playlist::song($client) || 0;

		} elsif ($p0 eq "connected") {

			$p1 = $client->connected() || 0;

		} elsif ($p0 eq "signalstrength") {

			$p1 = $client->signalStrength() || 0;

		} elsif ($p0 eq "power") {

			if (!defined $p1) {
				
				my $newPower = $client->power() ? 0 : 1;

				if (Slim::Player::Sync::isSynced($client)) {

					syncFunction($client, $newPower, "power", undef);
				}

				$client->power($newPower);

			} elsif ($p1 eq "?") {

				$p1 = $client->power();

			} else {

				if (Slim::Player::Sync::isSynced($client)) {

					syncFunction($client, $p1, "power", undef);
				}

				$client->power($p1);
				
				if ($p1 eq "0") {
					# Powering off cancels sleep...
					Slim::Utils::Timers::killTimers($client, \&sleepStartFade);
					Slim::Utils::Timers::killTimers($client, \&sleepPowerOff);
					$client->sleepTime(0);
					$client->currentSleepTime(0);
				}
			}

		} elsif ($p0 eq "sync") {

			if (!defined $p1) {

			} elsif ($p1 eq "?") {

				$p1 = Slim::Player::Sync::syncIDs($client)

			} elsif ($p1 eq "-") {

				Slim::Player::Sync::unsync($client);

			} else {

				my $buddy;

				if (Slim::Player::Client::getClient($p1)) {

					$buddy = Slim::Player::Client::getClient($p1);

				} else {

					my @clients = Slim::Player::Client::clients();
					if (defined $clients[$p1]) {
						$buddy = $clients[$p1];
					}
				}
				Slim::Player::Sync::sync($buddy, $client) if defined $buddy;
			}

		} elsif ($p0 eq "playlistcontrol") {
		
 			$pushParams = 0;
 	
 			my $ds     = Slim::Music::Info::getCurrentDataStore();
 			my %params = parseParams($parrayref, \@returnArray);
 			my @songs;
 			my $size = 0;
 			
 			if (Slim::Utils::Misc::stillScanning()) {
 				push @returnArray, "rescan:1";
 			}

			if (defined $params{'cmd'}) {

				my $load = ($params{'cmd'} eq 'load');
				my $insert = ($params{'cmd'} eq 'insert');
				my $add = ($params{'cmd'} eq 'add');
				my $delete = ($params{'cmd'} eq 'delete');
	
				Slim::Player::Source::playmode($client, "stop") if $load;
				Slim::Player::Playlist::clear($client) if $load;
				
				if (defined $params{'playlist_id'}){
					# Special case...

					my $obj = $ds->objectForId('track', $params{'playlist_id'});

					if (blessed($obj) && $obj->can('tracks')) {

						# We want to add the playlist name to the client object.
						$client->currentPlaylist($obj) if $load;

						@songs = $obj->tracks;
					}
				}
				else {
					if (defined $params{'genre_id'}){
						$find->{'genre'} = $params{'genre_id'};
					}
					if (defined $params{'artist_id'}){
						$find->{'artist'} = $params{'artist_id'};
					}
					if (defined $params{'album_id'}){
						$find->{'album'} = $params{'album_id'};
					}
					if (defined $params{'track_id'}){
						$find->{'id'} = $params{'track_id'};
					}
					if (defined $params{'year_id'}){
						$find->{'year'} = $params{'year_id'};
					}
						
					my $sort = exists $find->{'album'} ? 'tracknum' : 'track';

					if ($load || $add || $insert || $delete){

						@songs = @{ $ds->find({
							'field'   => 'lightweighttrack',
							'find'    => $find,
							'sortyBy' => $sort,
						}) };
					}
				}
				
				$size  = scalar(@songs);
				my $playListSize = Slim::Player::Playlist::count($client);
				
				push(@{Slim::Player::Playlist::playList($client)}, @songs) if ($load || $add || $insert);
				Slim::Player::Playlist::removeMultipleTracks($client, \@songs) if $delete;
				
				insert_done($client, $playListSize, $size) if $insert;
				
				Slim::Player::Playlist::reshuffle($client,$load?1:0) if ($load || $add);
				Slim::Player::Source::jumpto($client, 0) if $load;
	
				$client->currentPlaylistModified(1) if ($add || $insert || $delete);
				$client->currentPlaylistChangeTime(time()) if ($load || $add || $insert || $delete);
				#$client->currentPlaylist(undef) if $load;
			}			

	 		push @returnArray, "count:$size";

		} elsif ($p0 eq "playlist") {

			my $results;

			# This should be undef - see bug 2085
			my $jumpToIndex;

			# Query for the passed params
			if ($p1 =~ /^(play|load|add|insert|delete)album$/) {

				my $sort = 'track';
				# XXX - FIXME - searching for genre.name with
				# anything else kills the database. As a
				# stop-gap, don't add the search for
				# genre.name if we have a more specific query.
				if (specified($p2) && !specified($p3)) {
					$find->{'genre.name'} = singletonRef($p2);
				}

				if (specified($p3)) {
					$find->{'contributor.name'} = singletonRef($p3);
				}

				if (specified($p4)) {
					$find->{'album.title'} = singletonRef($p4);
					$sort = 'tracknum';
				}

				if (specified($p5)) {
					$find->{'track.title'} = singletonRef($p5);
				}

				$results = $ds->find({
					'field'  => 'lightweighttrack',
					'find'   => $find,
					'sortBy' => $sort,
				});
			}

			# here are all the commands that add/insert/replace songs/directories/playlists on the current playlist
			if ($p1 =~ /^(play|load|append|add|resume|insert|insertlist)$/) {
			
				my $path = $p2;

				if ($path) {

					if (!-e $path && !(Slim::Music::Info::isPlaylistURL($path))) {

						my $easypath = catfile(Slim::Utils::Prefs::get('playlistdir'), basename ($p2) . ".m3u");

						if (-e $easypath) {

							$path = $easypath;

						} else {

							$easypath = catfile(Slim::Utils::Prefs::get('playlistdir'), basename ($p2) . ".pls");

							if (-e $easypath) {
								$path = $easypath;
							}
						}
					}

					# Un-escape URI that have been escaped again.
					if (Slim::Music::Info::isRemoteURL($path)) {

						$path = Slim::Utils::Misc::unescape($path);
					}
					
					if ($p1 =~ /^(play|load|resume)$/) {

						Slim::Player::Source::playmode($client, "stop");
						Slim::Player::Playlist::clear($client);

						my $fixpath = Slim::Utils::Misc::fixPath($path);

						$client->currentPlaylist($fixpath);

						Slim::Music::Info::setTitle($fixpath, $p3) if defined $p3;

						$client->currentPlaylistModified(0);

					} elsif ($p1 =~ /^(add|append)$/) {

						my $fixpath = Slim::Utils::Misc::fixPath($path);

						Slim::Music::Info::setTitle($fixpath, $p3) if defined $p3;

						$client->currentPlaylistModified(1);

					} else {

						$client->currentPlaylistModified(1);
					}

					#$path = Slim::Utils::Misc::virtualToAbsolute($path);

					if ($p1 =~ /^(play|load)$/) { 

						$jumpToIndex = 0;

					} elsif ($p1 eq "resume" && Slim::Music::Info::isM3U($path)) {

						$jumpToIndex = Slim::Formats::Parse::readCurTrackForM3U($path);
					}
					
					if ($p1 =~ /^(insert|insertlist)$/) {

						my $playListSize = Slim::Player::Playlist::count($client);
						my @dirItems     = ();

						Slim::Utils::Scan::addToList({
							'listRef'      => \@dirItems,
							'url'          => $path,
						});

						Slim::Utils::Scan::addToList({
							'listRef'      => Slim::Player::Playlist::playList($client),
							'url'          => $path,
							'recursive'    => 1,
							'callback'     => \&insert_done,
							'callbackArgs' => [
								$client,
								$playListSize,
								scalar(@dirItems),
								$callbackf,
								$callbackargs,
							],
						});

					} else {

						Slim::Utils::Scan::addToList({
							'listRef'      => Slim::Player::Playlist::playList($client),
							'url'          => $path,
							'recursive'    => 1,
							'callback'     => \&load_done,
							'callbackArgs' => [
								$client,
								$jumpToIndex,
								$callbackf,
								$callbackargs,
							],
						});
					}
					
					$callcallback = 0;
					$p2 = $path;
				}

				$client->currentPlaylistChangeTime(time());
			
			} elsif ($p1 eq "loadalbum" || $p1 eq "playalbum") {

				Slim::Player::Source::playmode($client, "stop");
				Slim::Player::Playlist::clear($client);

				push(@{Slim::Player::Playlist::playList($client)}, @$results);

				Slim::Player::Playlist::reshuffle($client, 1);
				Slim::Player::Source::jumpto($client, 0);
				$client->currentPlaylist(undef);
				$client->currentPlaylistChangeTime(time());
			
			} elsif ($p1 eq "addalbum") {

				push(@{Slim::Player::Playlist::playList($client)}, @$results);

				Slim::Player::Playlist::reshuffle($client);
				$client->currentPlaylistModified(1);
				$client->currentPlaylistChangeTime(time());
			
			} elsif ($p1 eq "insertalbum") {

				my $playListSize = Slim::Player::Playlist::count($client);
				my $size = scalar(@$results);

				push(@{Slim::Player::Playlist::playList($client)}, @$results);
					
				insert_done($client, $playListSize, $size);
				#Slim::Player::Playlist::reshuffle($client);
				$client->currentPlaylistModified(1);
				$client->currentPlaylistChangeTime(time());
			
			} elsif ($p1 eq "loadtracks" || $p1 eq "playtracks") {
				Slim::Player::Source::playmode($client, "stop");
				Slim::Player::Playlist::clear($client);

				if ($p2 =~ /listref/i) {
					push(@{Slim::Player::Playlist::playList($client)}, parseListRef($client,$p2,$p3));
				} else {
					push(@{Slim::Player::Playlist::playList($client)}, parseSearchTerms($client, $p2));
				}

				Slim::Player::Playlist::reshuffle($client, 1);

				# The user may have stopped in the middle of a
				# saved playlist - resume if we can. Bug 1582
				my $playlistObj = $client->currentPlaylist;

				if ($playlistObj && ref($playlistObj) && $playlistObj->content_type =~ /^(?:ssp|m3u)$/) {

					$jumpToIndex = Slim::Formats::Parse::readCurTrackForM3U( $client->currentPlaylist->path );

					# And set a callback so that we can
					# update CURTRACK when the song changes.
					setExecuteCallback(\&Slim::Player::Playlist::newSongPlaylistCallback);
				}

				Slim::Player::Source::jumpto($client, $jumpToIndex);

				$client->currentPlaylistModified(0);
				$client->currentPlaylistChangeTime(time());
			
			} elsif ($p1 eq "addtracks") {

				if ($p2 =~ /listref/i) {
					push(@{Slim::Player::Playlist::playList($client)}, parseListRef($client,$p2,$p3));
				} else {
					push(@{Slim::Player::Playlist::playList($client)}, parseSearchTerms($client, $p2));
				}

				Slim::Player::Playlist::reshuffle($client);
				$client->currentPlaylistModified(1);
				$client->currentPlaylistChangeTime(time());
			
			} elsif ($p1 eq "inserttracks") {
					
				my @songs = $p2 =~ /listref/i ? parseListRef($client,$p2,$p3) : parseSearchTerms($client, $p2);
				my $size  = scalar(@songs);

				my $playListSize = Slim::Player::Playlist::count($client);
					
				push(@{Slim::Player::Playlist::playList($client)}, @songs);

				insert_done($client, $playListSize, $size);
				#Slim::Player::Playlist::reshuffle($client);
				$client->currentPlaylistModified(1);
				$client->currentPlaylistChangeTime(time());
			
			} elsif ($p1 eq "deletetracks") {

				my @listToRemove = $p2 =~ /listref/i ? parseListRef($client,$p2,$p3) : parseSearchTerms($client, $p2);
 
				Slim::Player::Playlist::removeMultipleTracks($client, \@listToRemove);
				$client->currentPlaylistModified(1);
				$client->currentPlaylistChangeTime(time());

			} elsif ($p1 eq "save") {

				my $title = $p2;

				my $playlistObj = $ds->updateOrCreate({
					'url'        => Slim::Utils::Misc::fileURLFromPath(
						catfile(Slim::Utils::Prefs::get('playlistdir'), $title . '.m3u')
					),
					'attributes' => {
						'TITLE' => $title,
						'CT'    => 'ssp',
					},
				});

				my $annotatedList;

				if (Slim::Utils::Prefs::get('saveShuffled')) {
				
					for my $shuffleitem (@{Slim::Player::Playlist::shuffleList($client)}) {
						push (@$annotatedList, @{Slim::Player::Playlist::playList($client)}[$shuffleitem]);
					}
				
				} else {

					$annotatedList = Slim::Player::Playlist::playList($client);
				}

				$playlistObj->setTracks($annotatedList);
				$playlistObj->update();

				Slim::Player::Playlist::scheduleWriteOfPlaylist($client, $playlistObj);

				# Pass this back to the caller.
				$p0 = $playlistObj;

			} elsif ($p1 eq "deletealbum") {

				Slim::Player::Playlist::removeMultipleTracks($client, $results);
				$client->currentPlaylistModified(1);
				$client->currentPlaylistChangeTime(time());
			
			} elsif ($p1 eq "deleteitem") {
 
				if (defined($p2) && $p2 ne '') {

					my $contents = [];

					if (!Slim::Music::Info::isList($p2)) {

						Slim::Player::Playlist::removeMultipleTracks($client,[$p2]);

					} elsif (Slim::Music::Info::isDir($p2)) {

						$contents = Slim::Utils::Scanner->scanDirectory({
							'url'       => $p2,
							'recursive' => 1,
						});

						Slim::Player::Playlist::removeMultipleTracks($client, $contents);

					} else {

						$contents = Slim::Music::Info::cachedPlaylist($p2);

						if (!scalar @$contents) {

							my $playlist_filehandle;

							if (!open($playlist_filehandle, Slim::Utils::Misc::pathFromFileURL($p2))) {

								errorMsg("Couldn't open playlist file $p2 : $!\n");

								$playlist_filehandle = undef;

							} else {

								$contents = [Slim::Formats::Parse::parseList($p2,$playlist_filehandle,dirname($p2))];
							}

						} else {
			 
							Slim::Player::Playlist::removeMultipleTracks($client,$contents);
						}
					}

					$client->currentPlaylistModified(1);
					$client->currentPlaylistChangeTime(time());
				}
			
			} elsif ($p1 eq "repeat") {

				# change between repeat values 0 (don't repeat), 1 (repeat the current song), 2 (repeat all)
				if (!defined($p2)) {

					Slim::Player::Playlist::repeat($client, (Slim::Player::Playlist::repeat($client) + 1) % 3);

				} elsif ($p2 eq "?") {

					$p2 = Slim::Player::Playlist::repeat($client);

				} else {

					Slim::Player::Playlist::repeat($client, $p2);
				}
			
			} elsif ($p1 eq "shuffle") {

				if (!defined($p2)) {

					my $nextmode = (1,2,0)[Slim::Player::Playlist::shuffle($client)];
					Slim::Player::Playlist::shuffle($client, $nextmode);
					Slim::Player::Playlist::reshuffle($client);

				} elsif ($p2 eq "?") {

					$p2 = Slim::Player::Playlist::shuffle($client);

				} else {

					Slim::Player::Playlist::shuffle($client, $p2);
					Slim::Player::Playlist::reshuffle($client);
				}

				$client->currentPlaylistChangeTime(time());
			
			} elsif ($p1 eq "clear") {

				Slim::Player::Playlist::clear($client);
				Slim::Player::Source::playmode($client, "stop");
				$client->currentPlaylist(undef);
				$client->currentPlaylistChangeTime(time());
			
			} elsif ($p1 eq "move") {

				Slim::Player::Playlist::moveSong($client, $p2, $p3);
				$client->currentPlaylistModified(1);
				$client->currentPlaylistChangeTime(time());
			
			} elsif ($p1 eq "delete") {

				if (defined($p2)) {
					Slim::Player::Playlist::removeTrack($client,$p2);
				}

				$client->currentPlaylistModified(1);
				$client->currentPlaylistChangeTime(time());
			
			} elsif (($p1 eq "jump") || ($p1 eq "index")) {

				if ($p2 eq "?") {
					$p2 = Slim::Player::Source::playingSongIndex($client);
				} else {
					Slim::Player::Source::jumpto($client, $p2, $p3);
				}

			} elsif ($p1 eq "name") {

				$p2 = Slim::Music::Info::standardTitle($client,$client->currentPlaylist());

			} elsif ($p1 eq "url") {

				$p2 = $client->currentPlaylist();

			} elsif ($p1 eq "tracks") {

				$p2 = Slim::Player::Playlist::count($client);

			} elsif ($p1 =~ /(?:duration|artist|album|title|genre)/) {

				my $url = Slim::Player::Playlist::song($client, $p2);
				my $obj = $ds->objectForUrl($url, 1, 1);

				if (blessed($obj) && $obj->can('secs')) {

					# Just call the method on Track
					if ($p1 eq 'duration') {
						$p3 = $obj->secs();
					}
					else {
						$p3 = $obj->$p1();
					}
				}

			} elsif ($p1 eq "path") {

				$p3 = Slim::Player::Playlist::song($client,$p2) || 0;
			
			} elsif ($p1 eq "zap") {

				my $zapped   = string('ZAPPED_SONGS');
				my $zapsong  = Slim::Player::Playlist::song($client,$p2);
				my $zapindex = defined $p2 ? $p2 : Slim::Player::Source::playingSongIndex($client);
 
				#  Remove from current playlist
				if (Slim::Player::Playlist::count($client) > 0) {

					# Callo ourselves.
					execute($client, ["playlist", "delete", $zapindex]);
				}

				my $playlistObj = $ds->updateOrCreate({
					'url'        => "playlist://$zapped",
					'attributes' => {
						'TITLE' => $zapped,
						'CT'    => 'ssp',
					},
				});

				my @list = $playlistObj->tracks;
				push @list,$zapsong;

				$playlistObj->setTracks(\@list);
				$playlistObj->update();

				$client->currentPlaylistModified(1);
				$client->currentPlaylistChangeTime(time());
			}

			Slim::Player::Playlist::refreshPlaylist($client) if $client->currentPlaylistModified();

		} elsif ($p0 eq "mixer") {

			if ($p1 eq "volume") {
				my $newvol;
				my $oldvol = $client->prefGet("volume"); 

				if ($p2 eq "?") {

					$p2 = $oldvol;

				} else {

					if ($oldvol < 0) {
						# volume was previously muted
						$oldvol *= -1;      # un-mute volume
					} 
					
					if ($p2 =~ /^[\+\-]/) {
						$newvol = $oldvol + $p2;
					} else {
						$newvol = $p2;
					}
					
					$newvol = $client->volume($newvol);
					
					if (Slim::Player::Sync::isSynced($client)) {
						syncFunction($client, $newvol, "volume",\&setVolume);
					}
				}

			} elsif ($p1 eq "muting") {
				my $vol = $client->volume();
				my $fade;
				
				if ($vol < 0) {
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
 
				$client->fade_volume($fade, \&mute, [$client]);
 
				if (Slim::Player::Sync::isSynced($client)) {
					syncFunction($client, $fade, "mute", undef);
				}

			} elsif ($p1 eq "balance") {

				# unsupported yet

			} elsif ($p1 eq "treble") {

				my $newtreb;
				my $oldtreb = $client->treble();
				if ($p2 eq "?") {
					$p2 = $oldtreb;
				} else {
				
					if ($p2 =~ /^[\+\-]/) {
						$newtreb = $oldtreb + $p2;
					} else {
						$newtreb = $p2;
					}

					$newtreb = $client->treble($newtreb);

					if (Slim::Player::Sync::isSynced($client)) {
						syncFunction($client, $newtreb, "treble",\&setTreble);
					}
				}

			} elsif ($p1 eq "bass") {

				my $newbass;
				my $oldbass = $client->bass();

				if ($p2 eq "?") {
					$p2 = $oldbass;
				} else {
				
					if ($p2 =~ /^[\+\-]/) {
						$newbass = $oldbass + $p2;
					} else {
						$newbass = $p2;
					}

					$newbass = $client->bass($newbass);

					if (Slim::Player::Sync::isSynced($client)) {
						syncFunction($client, $newbass, "bass",\&setBass);
					}
				}

			} elsif ($p1 eq "pitch") {

				my $newpitch;
				my $oldpitch = $client->pitch();

				if ($p2 eq "?") {

					$p2 = $oldpitch;

				} else {

					if ($p2 =~ /^[\+\-]/) {
						$newpitch = $oldpitch + $p2;
					} else {
						$newpitch = $p2;
					}

					$newpitch = $client->pitch($newpitch);

					if (Slim::Player::Sync::isSynced($client)) {
						syncFunction($client, $newpitch, "pitch",\&setPitch);
					}
				}
			}

		} elsif ($p0 eq "displaynow") {

			if ($p1 eq "?" && $p2 eq "?") {
				$p1 = $client->prevline1();
				$p2 = $client->prevline2();
			} 

		} elsif ($p0 eq "linesperscreen") {

			$p1 = $client->linesPerScreen();

		} elsif ($p0 eq "display") {

			if ($p1 eq "?" && $p2 eq "?") {
				my $parsed = $client->parseLines(Slim::Display::Display::curLines($client));
				$p1 = $parsed->{line1} || '';
				$p2 = $parsed->{line2} || '';
			} else {
				Slim::Buttons::ScreenSaver::wakeup($client);
				$client->showBriefly($p1, $p2, $p3, $p4);
			}

		} elsif ($p0 eq "button") {

			# all buttons now go through execute()
			Slim::Hardware::IR::executeButton($client, $p1, $p2, undef, defined($p3) ? $p3 : 1);

		} elsif ($p0 eq "ir") {

			# all ir signals go through execute()
			Slim::Hardware::IR::processIR($client, $p1, $p2);
	
 		# Extended CLI API STATUS		
 		} elsif ($p0 eq "status") {

 			$pushParams = 0;
 
 			my $tags = "gald";
 			
 			my %params = parseParams($parrayref, \@returnArray);
 			
 			$tags = $params{'tags'} if defined($params{'tags'});
 			
 			my $connected = $client->connected() || 0;
 			my $power     = $client->power();
 			my $repeat    = Slim::Player::Playlist::repeat($client);
 			my $shuffle   = Slim::Player::Playlist::shuffle($client);
			my $songCount = Slim::Player::Playlist::count($client);
			my $idx = 0;
 		    	
 			if (Slim::Utils::Misc::stillScanning()) {
 				push @returnArray, "rescan:1";
 			}
 			
 			push @returnArray, "player_name:" . $client->name();
 			push @returnArray, "player_connected:" . $connected;
 			push @returnArray, "power:".$power;
 			
 			if ($client->model() eq "squeezebox" || $client->model() eq "squeezebox2") {
 				push @returnArray, "signalstrength:".($client->signalStrength() || 0);
 			}
 			
 			if ($power) {
 			
 				#push @returnArray, "player_mode:".Slim::Buttons::Common::mode($client);
 		    	push @returnArray, "mode:". Slim::Player::Source::playmode($client);

 				if (Slim::Player::Playlist::song($client)) { 
					my $track = $ds->objectForUrl(Slim::Player::Playlist::song($client));

 					my $dur   = 0;

 					if (blessed($track) && $track->can('secs')) {

						$dur = $track->secs;
					}

 					if ($dur) {
						push @returnArray, "rate:".Slim::Player::Source::rate($client); #(>1 ffwd, <0 rew else norm)
						push @returnArray, "time:".Slim::Player::Source::songTime($client);
						push @returnArray, "duration:".$dur;
 					}
 				}
 				
 				if ($client->currentSleepTime()) {

 					my $sleep = $client->sleepTime() - Time::HiRes::time();
					push @returnArray, "sleep:" . $client->currentSleepTime() * 60;
					push @returnArray, "will_sleep_in:" . ($sleep < 0 ? 0 : $sleep);
 				}
 				
 				if (Slim::Player::Sync::isSynced($client)) {

 					my $master = Slim::Player::Sync::masterOrSelf($client);

 					push @returnArray, "sync_master:" . $master->id();

 					my @slaves = Slim::Player::Sync::slaves($master);
 					my @sync_slaves = map { $_->id } @slaves;

 					push @returnArray, "sync_slaves:" . join(" ", @sync_slaves);
 				}
 			
				push @returnArray, "mixer volume:".$client->volume();
				push @returnArray, "mixer treble:".$client->treble();
				push @returnArray, "mixer bass:".$client->bass();

				if ($client->model() ne "slimp3") {
					push @returnArray, "mixer pitch:".$client->pitch();
				}

				#push @returnArray, "mixer balance:";
				push @returnArray, "playlist repeat:".$repeat; #(0 no, 1 title, 2 all)
				push @returnArray, "playlist shuffle:".$shuffle; #(0 no, 1 title, 2 albums)
 		    
 				if ($songCount > 0) {
 					$idx = Slim::Player::Source::playingSongIndex($client);
 					push @returnArray, "playlist_cur_index:".($idx);
 				}

 		    		push @returnArray, "playlist_tracks:".$songCount;
 			}
 			
 			if ($songCount > 0 && $power) {
 			
 				# we can return playlist data.
 				# which mode are we in?
 				my $modecurrent = 0;

 				if (defined($p1) && ($p1 eq "-")) {
 					$modecurrent = 1;
 				}
 				
 				# if repeat is 1 (song) and modecurrent, then show the current song
 				if ($modecurrent && ($repeat == 1) && $p2) {

 					push @returnArray, "playlist index:".($idx);
 					push @returnArray, pushSong(Slim::Player::Playlist::song($client, $idx), $tags);	

 				} else {

 					my ($valid, $start, $end);
 					
 					if ($modecurrent) {
 						($valid, $start, $end) = normalize(($idx), scalar($p2), $songCount);
 					} else {
 						($valid, $start, $end) = normalize(scalar($p1), scalar($p2), $songCount);
 					}
 		
 					if ($valid) {
 						my $count = 0;
 	
 						for ($idx = $start; $idx <= $end; $idx++){
 							$count++;
 							push @returnArray, "playlist index:".($idx);
 							push @returnArray, pushSong(Slim::Player::Playlist::song($client, $idx), $tags);
 							::idleStreams() ;
 						}
 						
 						my $repShuffle = Slim::Utils::Prefs::get('reshuffleOnRepeat');
 						my $canPredictFuture = ($repeat == 2)  			# we're repeating all
 												&& 						# and
 												(	($shuffle == 0)		# either we're not shuffling
 													||					# or
 													(!$repShuffle));	# we don't reshuffle
 						
 						if ($modecurrent && $canPredictFuture && ($count < scalar($p2))) {

 							# wrap around the playlist...
 							($valid, $start, $end) = normalize(0, (scalar($p2) - $count), $songCount);		

 							if ($valid) {

 								for ($idx = $start; $idx <= $end; $idx++){
 									push @returnArray, "playlist index:".($idx);
 									push @returnArray, pushSong(Slim::Player::Playlist::song($client, $idx), $tags);
 									::idleStreams() ;
 								}
 							}						
 						}
 					}
 				}
 			}

 		}
 	}				
 		
 	# extended CLI API calls do push their return values directly
 	if ($pushParams) {
 		if (defined($p0)) { push @returnArray, $p0 };
 		if (defined($p1)) { push @returnArray, $p1 };
 		if (defined($p2)) { push @returnArray, $p2 };
 		if (defined($p3)) { push @returnArray, $p3 };
 		if (defined($p4)) { push @returnArray, $p4 };
 		if (defined($p5)) { push @returnArray, $p5 };
 		if (defined($p6)) { push @returnArray, $p6 };
 		if (defined($p7)) { push @returnArray, $p7 };
  	}

	$callcallback && $callbackf && (&$callbackf(@$callbackargs, \@returnArray));

	executeCallback($client, \@returnArray);
	
	$::d_command && msg(" Returning array: " . $returnArray[0] . " (" .
			(defined $returnArray[1] ? $returnArray[1] : "") . ") (" .
			(defined $returnArray[2] ? $returnArray[2] : "") . ") (" .
			(defined $returnArray[3] ? $returnArray[3] : "") . ") (" .
			(defined $returnArray[4] ? $returnArray[4] : "") . ") (" .
			(defined $returnArray[5] ? $returnArray[5] : "") . ") (" .
			(defined $returnArray[6] ? $returnArray[6] : "") . ") (" .
			(defined $returnArray[7] ? $returnArray[7] : "") . ")\n");
	
	return @returnArray;
}

sub setExecuteCallback {
	my $callbackRef = shift;
	
	$executeCallbacks{$callbackRef} = $callbackRef;
	
	# Let Request know if it needs to call us
	Slim::Control::Request::needToCallExecuteCallback(scalar(keys %executeCallbacks));
	
	# warn about deprecated call
	errorMsg("Slim::Control::Command::setExecuteCallback() has been deprecated!");
	errorMsg("Please use Slim::Control::Request::subscribe() instead!");
	errorMsg("Documentation is available in Slim::Control::Request.pm\n");
}

sub clearExecuteCallback {
	my $callbackRef = shift;
	
	delete $executeCallbacks{$callbackRef};
	
	# Let Request know if it needs to call us
	Slim::Control::Request::needToCallExecuteCallback(scalar(keys %executeCallbacks));
	
	# warn about deprecated call
	errorMsg("Slim::Control::Command::clearExecuteCallback() has been deprecated!");
	errorMsg("Please use Slim::Control::Request::unsubscribe() instead!");
	errorMsg("Documentation is available in Slim::Control::Request.pm\n");
}

sub executeCallback {
	my $client = shift;
	my $paramsRef = shift;
	my $dontcallDispatch = shift;

#	$::d_command && msg("Command: executeCallback()\n");

	no strict 'refs';
		
	for my $executecallback (keys %executeCallbacks) {
		$executecallback = $executeCallbacks{$executecallback};
		&$executecallback($client, $paramsRef);
	}
	
	# make sure we inform Request not to call us again by defining the third
	# parameter. Request does the same for us, so we avoid an infinite loop.
	Slim::Control::Request::notifyFromArray($client, $paramsRef, "no no no") 
		if !defined $dontcallDispatch;
}

1;
