package Slim::Control::Command;

# $Id: Command.pm,v 1.33 2004/04/15 18:49:39 dean Exp $
#
# SlimServer Copyright (C) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use File::Basename;
use File::Spec::Functions qw(:ALL);
use FileHandle;
use IO::Socket qw(:DEFAULT :crlf);
use Time::HiRes;
use Slim::Display::Display;
use Slim::Utils::Misc;
use Slim::Utils::Scan;
use Slim::Utils::Strings qw(string);

my %executeCallbacks;

#############################################################################
# execute - does all the hard work.  Use it.
# takes:
#   a client reference
#   a reference to an array of parameters
#   a reference to a callback function
#   a list of callback function args
#
# returns an array containing the given parameters

sub execute {
	my($client, $parrayref, $callbackf, $callbackargs) = @_;
	my $callcallback = 1;
	my $p0 = $$parrayref[0];
	my $p1 = $$parrayref[1];
	my $p2 = $$parrayref[2];
	my $p3 = $$parrayref[3];
	my $p4 = $$parrayref[4];
	my $p5 = $$parrayref[5];
	my $p6 = $$parrayref[6];

	$::d_command && msg(" Executing command " . ($client ? $client->id() : "no client") . ": $p0 (" .
			(defined $p1 ? $p1 : "") . ") (" .
			(defined $p2 ? $p2 : "") . ") (" .
			(defined $p3 ? $p3 : "") . ") (" .
			(defined $p4 ? $p4 : "") . ") (" .
			(defined $p5 ? $p5 : "") . ") (" .
			(defined $p6 ? $p6 : "") . ")\n");

	# The first parameter is the client identifier to execute the command.
	# If a parameter is "?" it is replaced by the current value in the array
	# returned by the function
	# Below are a list of the commands:
	#
	# P0				P1				P2				P3			P4			P5			P6
	# play		
	# pause			(0|1|)	
	# stop
	# mode			<play|pause|stop>	
	# mode			?
	# sleep 			(0..n)
	# sleep 			?
	# gototime		(0..n sec)|(-n..+n sec)?
	# power 			(0|1|?)
	# genre			?
	# artist			?
	# album			?
	# title			?
	# duration		?
			
	# playlist		play 			<item>		(item can be a song, playlist or directory. synonym: load)
	# playlist		insert		<item>		(item can be a song, playlist or directory. synonym: insertlist)
	# playlist		add 			<item>		(item can be a song, playlist or directory. synonym: append)

	# playlist		playalbum	<genre>		<artist>	<album>	<songtitle>	(synonym: loadalbum)
	# playlist		insertalbum	<genre>		<artist>	<album>	<songtitle>
	# playlist		addalbum		<genre>		<artist>	<album>	<songtitle>
	
	# playlist		deletealbum	<genre>		<artist>	<album>	<songtitle>
	# playlist		deleteitem	<filename/playlist>	
		
	# playlist 		resume 		<playlist>	
	# playlist 		save 			<playlist>	
		
	# playlist 		clear	
	# playlist 		move 			<fromoffset> <tooffset>	
	# playlist 		delete 		<songoffset>
			
	# playlist 		jump 			<index>	
	# playlist 		index			<index>		?
	# playlist		genre			<index>		?
	# playlist		artist		<index>		?
	# playlist		album			<index>		?
	# playlist		title			<index>		?
	# playlist		duration		<index>		?
	# playlist		tracks		?
	# playlist		zap			<index>
	# mixer			volume		(0 .. 100)|(-100 .. +100)
	# mixer			volume		?
	# mixer			balance		(-100 .. 100)|(-200 .. +200)			(not implemented!)
	# mixer			bass			(0 .. 100)|(-100 .. +100)
	# mixer			treble		(0 .. 100)|(-100 .. +100)
	# mixer			pitch		(0 .. 100 .. 1000)|(-100 .. +100)
	# display		<line1>		<line2>	<duration>
	# display		?				?
	# displaynow	?				?
	# button			<buttoncode>
	# player			count			?
	# player			id				<playerindex|playerid>				?
	# player			name			<playerindex|playerid>				?
	# player			ip				<playerindex|playerid>				?
	# player			address		<playerindex|playerid>				?	(deprecated)
	# player			model			<playerindex|playerid>				?
	# pref			<prefname>	<prefvalue>
	# pref			<prefname>	?
	# playerpref	<prefname>	<prefvalue>
	# playerpref	<prefname>	?
	
	# rescan	
	# wipecache
	
	if (!defined($p0)) {
		# ignore empty commands
	# these commands don't require a valid client

	} elsif ($p0 eq "player") {
		if (!defined($p1)) {
		
		} elsif ($p1 eq "count") {
			$p2 = Slim::Player::Client::clientCount();
		} elsif ($p1 eq "name" || $p1 eq "address" || $p1 eq "ip" || $p1 eq "id" || $p1 eq "model") {
		
			my $p2client;
			
			# were we passed an ID?
			if (defined $p2 && Slim::Player::Client::getClient($p2)) {
				$p2client = Slim::Player::Client::getClient($p2);
			} else {
			
			# otherwise, try for an index
				my @clients = Slim::Player::Client::clients();
				if (defined $p2 && defined $clients[$p2]) {
					$p2client = $clients[$p2];
				}
			}
			
			if (defined $p2client) {
				if ($p1 eq "name") {
					$p3 = $p2client->name();
				} elsif ($p1 eq "address" || $p1 eq "id") {
					$p3 = $p2client->id();
				} elsif ($p1 eq "ip") {
					$p3 = $p2client->ipport();
				} elsif ($p1 eq "model") {
					$p3 = $p2client->model();
				}
			}
		} 

	} elsif ($p0 eq "pref") {
		if (defined($p2) && $p2 ne '?' && !$::nosetup) {
			Slim::Utils::Prefs::set($p1, $p2);
		}
		$p2 = Slim::Utils::Prefs::get($p1);
	} elsif ($p0 eq "rescan") {
		Slim::Music::MusicFolderScan::startScan();
	} elsif ($p0 eq "wipecache") {
		Slim::Music::Info::wipeDBCache();
		Slim::Music::MusicFolderScan::startScan();
	} elsif ($p0 eq "info") {
		if (!defined($p1)) {
		} elsif ($p1 eq "total") {
			if ($p2 eq "genres") {
			   $p3 = Slim::Music::Info::genreCount([],[],[],[]);
			} elsif ($p2 eq "artists") {
			   $p3 = Slim::Music::Info::artistCount([],[],[],[]);
			} elsif ($p2 eq "albums") {
			   $p3 = Slim::Music::Info::albumCount([],[],[],[]);
			} elsif ($p2 eq "songs") {
			   $p3 = Slim::Music::Info::songCount([],[],[],[]);
			}
		}

	} elsif ($p0 eq "debug") {
		if ($p1 =~ /^d_/) {
			my $debugsymbol = "::" . $p1;
			no strict 'refs';
			if (!defined($p2)) {
				$$debugsymbol = ! $$debugsymbol;
				$p2 = $$debugsymbol;

			} elsif ($p2 eq "?")  {
				$p2 = $$debugsymbol;
			} else {
				$$debugsymbol = $p2;
			}	
			use strict 'refs';
			if (!$p2) { $p2 = 0; }
		}
	#the following commands require a valid client to be specified
	} elsif ($client) {

		if ($p0 eq "playerpref") {
			if (defined($p2) && $p2 ne '?' && !$::nosetup) {
				Slim::Utils::Prefs::clientSet($client, $p1, $p2);
			}
			$p2 = Slim::Utils::Prefs::clientGet($client, $p1);

		} elsif ($p0 eq "play") {
			Slim::Player::Source::playmode($client, "play");
			Slim::Player::Source::rate($client,1);

		} elsif ($p0 eq "pause") {
			if (defined($p1)) {
				if ($p1 && $client->playmode eq "play") {
					Slim::Player::Source::playmode($client, "pause");
				} elsif (!$p1 && $client->playmode eq "pause") {
					Slim::Player::Source::playmode($client, "resume");
				}
			} else {
				if ($client->playmode eq "pause") {
					Slim::Player::Source::playmode($client, "resume");
				} elsif ($client->playmode eq "play") {
					Slim::Player::Source::playmode($client, "pause");
				}
			}

		} elsif ($p0 eq "rate") {
			if ($client->audioFilehandleIsSocket) {
				Slim::Player::Source::rate($client, 1);
			} elsif (!defined($p1) || $p1 eq "?") {
				$p1 = Slim::Player::Source::rate($client);
			} else {
				Slim::Player::Source::rate($client,$p1);
			}

		} elsif ($p0 eq "stop") {
			Slim::Player::Source::playmode($client, "stop");

		} elsif ($p0 eq "mode") {
			if (!defined($p1) || $p1 eq "?") {
				$p1 = $client->playmode;
			} else {
				if ($client->playmode eq "pause" && $p1 eq "play") {
					Slim::Player::Source::playmode($client, "resume");
				} else {
					Slim::Player::Source::playmode($client, $p1);
				}
			}

		} elsif ($p0 eq "sleep") {
			if ($p1 eq "?") {
				$p1 = $client->sleepTime() - Time::HiRes::time();
				if ($p1 < 0) {
					$p1 = 0;
				}
			} else {
				Slim::Utils::Timers::killTimers($client, \&gotosleep);
				
				if ($p1 != 0) {
					Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + $p1, \&gotosleep);
					$client->sleepTime(Time::HiRes::time() + $p1);
					$client->currentSleepTime($p1 / 60);
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

		} elsif ($p0 eq "duration") {
			$p1 = Slim::Music::Info::durationSeconds(Slim::Player::Playlist::song($client)) || 0;

		} elsif ($p0 eq "artist") {
			$p1 = Slim::Music::Info::artist(Slim::Player::Playlist::song($client)) || 0;

		} elsif ($p0 eq "album") {
			$p1 = Slim::Music::Info::album(Slim::Player::Playlist::song($client)) || 0;

		} elsif ($p0 eq "title") {
			$p1 = Slim::Music::Info::title(Slim::Player::Playlist::song($client)) || 0;

		} elsif ($p0 eq "genre") {
			$p1 = Slim::Music::Info::genre(Slim::Player::Playlist::song($client)) || 0;

		} elsif ($p0 eq "path") {
			$p1 = Slim::Player::Playlist::song($client) || 0;

		} elsif ($p0 eq "power") {
			if (!defined $p1) {
				if (Slim::Player::Sync::isSynced($client)) {
					syncFunction($client,!$client->power(), "power",undef);
				}
				$client->power(!$client->power());
			} elsif ($p1 eq "?") {
				$p1 = $client->power();
			} else {
				if (Slim::Player::Sync::isSynced($client)) {
					syncFunction($client,$p1, "power",undef);
				}
				$client->power($p1);
			}

		} elsif ($p0 eq "playlist") {
			# here are all the commands that add/insert/replace songs/directories/playlists on the current playlist
			if ($p1 =~ /^(play|load|append|add|resume|insert|insertlist)$/) {
			
				my $jumptoindex = undef;
				my $path = $p2;
				if ($path) {
					if (!-e $path) {
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
					
					if ($p1 =~ /^(play|load|resume)$/) {
						Slim::Player::Source::playmode($client, "stop");
						Slim::Player::Playlist::clear($client);
					}
					
					$path = Slim::Utils::Misc::virtualToAbsolute($path);
					
					if ($p1 =~ /^(play|load)$/) { 
						$jumptoindex = 0;
					} elsif ($p1 eq "resume" && Slim::Music::Info::isM3U($path)) {
						# do nothing to the index if we can't open the list
						my $playlist = new FileHandle($path, "r");
						if ($playlist) {
							# retrieve comment with track number in it
							$jumptoindex = $playlist->getline;
							if ($jumptoindex =~ /^#CURTRACK (\d+)$/) {
								$jumptoindex = $1;
							} else {
								$jumptoindex = 0;
							}
							close $playlist;
						}
					}
					
					if ($p1 =~ /^(insert|insertlist)$/) {
						my $playListSize = Slim::Player::Playlist::count($client);
						my @dirItems;
						Slim::Utils::Scan::addToList(\@dirItems, $path, 1, undef);
						Slim::Utils::Scan::addToList(
							Slim::Player::Playlist::playList($client)
							, $path
							, 1
							, undef
							, \&insert_done
							, $client
							, $playListSize
							, scalar(@dirItems)
							,$callbackf
							, $callbackargs
						);
					} else {
						Slim::Utils::Scan::addToList(
							Slim::Player::Playlist::playList($client)
							, $path
							, 1
							, undef
							, \&load_done
							, $client
							, $jumptoindex
							, $callbackf
							, $callbackargs
							);
					}
					
					$callcallback = 0;
					$p2 = $path;
				}
			
			} elsif ($p1 eq "loadalbum" | $p1 eq "playalbum") {
				Slim::Player::Source::playmode($client, "stop");
				Slim::Player::Playlist::clear($client);
				push(@{Slim::Player::Playlist::playList($client)}, Slim::Music::Info::songs(singletonRef($p2), singletonRef($p3), singletonRef($p4), singletonRef($p5), $p6));
				Slim::Player::Playlist::reshuffle($client);
				Slim::Player::Source::jumpto($client, 0);
			
			} elsif ($p1 eq "addalbum") {
				push(@{Slim::Player::Playlist::playList($client)}, Slim::Music::Info::songs(singletonRef($p2), singletonRef($p3), singletonRef($p4), singletonRef($p5), $p6));
				Slim::Player::Playlist::reshuffle($client);
			
			} elsif ($p1 eq "insertalbum") {
				my @songs = Slim::Music::Info::songs(singletonRef($p2), singletonRef($p3), singletonRef($p4), singletonRef($p5), $p6);
				my $playListSize = Slim::Player::Playlist::count($client);
				my $size = scalar(@songs);
				push(@{Slim::Player::Playlist::playList($client)}, @songs);
				insert_done($client, $playListSize, $size);
				#Slim::Player::Playlist::reshuffle($client);
			
			} elsif ($p1 eq "save") {
				if ( Slim::Utils::Prefs::get('playlistdir')) {
					# just use the filename to avoid nasties
					my $savename = basename ($p2);
					# save the current playlist position as a comment at the head of the list
					my $annotatedlistRef;
					if (Slim::Utils::Prefs::get('saveShuffled')) {
						foreach my $shuffleitem (@{Slim::Player::Playlist::shuffleList($client)}) {
							push (@$annotatedlistRef,@{Slim::Player::Playlist::playList($client)}[$shuffleitem]);
						}
					} else {
						$annotatedlistRef = Slim::Player::Playlist::playList($client);
					}
					Slim::Formats::Parse::writeM3U( 
						$annotatedlistRef 
						,catfile(Slim::Utils::Prefs::get('playlistdir') 
						,$savename . ".m3u") 
						,1 
						,Slim::Player::Source::currentSongIndex($client)
					);
				}
			
			} elsif ($p1 eq "deletealbum") {
				my @listToRemove=Slim::Music::Info::songs(singletonRef($p2),singletonRef($p3),singletonRef($p4),singletonRef($p5),$p6);
				Slim::Player::Playlist::removeMultipleTracks($client,\@listToRemove);
			
			} elsif ($p1 eq "deleteitem") {
				if (defined($p2) && $p2 ne '') {
					$p2 = Slim::Utils::Misc::virtualToAbsolute($p2);
					my $contents;
					if (!Slim::Music::Info::isList($p2)) {
						Slim::Player::Playlist::removeMultipleTracks($client,[$p2]);
					} elsif (Slim::Music::Info::isDir($p2)) {
						Slim::Utils::Scan::addToList(\@{$contents}, $p2, 1);
						Slim::Player::Playlist::removeMultipleTracks($client,\@{$contents});
					} else {
						$contents = Slim::Music::Info::cachedPlaylist($p2);
						if (defined($contents)) {
							$contents = [Slim::Music::Info::cachedPlaylist($p2)];
						} else {
							my $playlist_filehandle;
							if (!open($playlist_filehandle, $p2)) {
								$::d_files && msg("Couldn't open playlist file $p2 : $!");
								$playlist_filehandle = undef;
							} else {
								$contents = [Slim::Formats::Parse::parseList($p2,$playlist_filehandle,dirname($p2))];
							}
						}
						if (defined($contents)) {
							Slim::Player::Playlist::removeMultipleTracks($client,$contents);
						}
					}
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
					my $nextmode=(1,2,0)[Slim::Player::Playlist::shuffle($client)];
					Slim::Player::Playlist::shuffle($client, $nextmode);
					Slim::Player::Playlist::reshuffle($client);
				} elsif ($p2 eq "?") {
					$p2 = Slim::Player::Playlist::shuffle($client);
				} else {
					Slim::Player::Playlist::shuffle($client, $p2);
					Slim::Player::Playlist::reshuffle($client);
				}
			
			} elsif ($p1 eq "clear") {
				Slim::Player::Playlist::clear($client);
				Slim::Player::Source::playmode($client, "stop");
			
			} elsif ($p1 eq "move") {
				Slim::Player::Playlist::moveSong($client, $p2, $p3);
			
			} elsif ($p1 eq "delete") {
				if (defined($p2)) {
					Slim::Player::Playlist::removeTrack($client,$p2);
				}
			
			} elsif (($p1 eq "jump") || ($p1 eq "index")) {
				if ($p2 eq "?") {
					$p2 = Slim::Player::Source::currentSongIndex($client);
				} else {
						Slim::Player::Source::jumpto($client, $p2);
				}
			
			} elsif ($p1 eq "tracks") {
				$p2 = Slim::Player::Playlist::count($client);
			} elsif ($p1 eq "duration") {
				$p3 = Slim::Music::Info::durationSeconds(Slim::Player::Playlist::song($client,$p2)) || 0;
			} elsif ($p1 eq "artist") {
				$p3 = Slim::Music::Info::artist(Slim::Player::Playlist::song($client,$p2)) || 0;
			} elsif ($p1 eq "album") {
				$p3 = Slim::Music::Info::album(Slim::Player::Playlist::song($client,$p2)) || 0;
			} elsif ($p1 eq "title") {
				$p3 = Slim::Music::Info::title(Slim::Player::Playlist::song($client,$p2)) || 0;
			} elsif ($p1 eq "genre") {
				$p3 = Slim::Music::Info::genre(Slim::Player::Playlist::song($client,$p2)) || 0;
			} elsif ($p1 eq "path") {
				$p3 = Slim::Player::Playlist::song($client,$p2) || 0;
			
			} elsif ($p1 eq "zap") {
				my $zapped=catfile(Slim::Utils::Prefs::get('playlistdir'), string('ZAPPED_SONGS') . '.m3u');
				my $zapsong = Slim::Player::Playlist::song($client,$p2);
				my $zapindex = $p2 || Slim::Player::Source::currentSongIndex($client);;
				#Remove from current playlist
				if (Slim::Player::Playlist::count($client) > 0) {
					Slim::Control::Command::execute($client, ["playlist", "delete", $zapindex]);
				}
				# Append the zapped song to the zapped playlist
				# This isn't as nice as it should be, but less work than loading and rewriting the whole list
				my $zapref = new FileHandle $zapped, "a";
				if ($zapref) {
					my @zaplist = ($zapsong);
					my $zapitem = Slim::Formats::Parse::writeM3U(\@zaplist);
					print $zapref $zapitem;
					close $zapref;
				} else {
					msg("Could not open $zapped for writing.\n");
				}
			}

		} elsif ($p0 eq "mixer") {
			if ($p1 eq "volume") {
				my $newvol;
				my $oldvol = Slim::Utils::Prefs::clientGet($client, "volume");
				if ($p2 eq "?") {
					$p2 = $oldvol;
				} else {
					if($oldvol < 0) {
						# volume was previously muted
						$oldvol *= -1;      # un-mute volume
					} 
					
					if ($p2 =~ /^[\+\-]/) {
						$newvol = $oldvol + $p2;
					} else {
						$newvol = $p2;
					}
					
					if ($newvol> 100) { $newvol = $Slim::Player::Client::maxVolume; }
					if ($newvol < 0) { $newvol = 0; }
					Slim::Utils::Prefs::clientSet($client, "volume", $newvol);
					$client->volume($newvol);
					if (Slim::Player::Sync::isSynced($client)) {syncFunction($client, $newvol, "volume",\&setVolume);};
				}
			} elsif ($p1 eq "muting") {
				my $vol = Slim::Utils::Prefs::clientGet($client, "volume");
				my $fade;
				
				if($vol < 0) {
					# need to un-mute volume
					Slim::Utils::Prefs::clientSet($client, "mute",0);
					$fade = 0.3125;
				} else {
					# need to mute volume
					Slim::Utils::Prefs::clientSet($client, "mute",1);
					$fade = -0.3125;
				}
				$client->fade_volume($fade, "mute", [$client]);
				if (Slim::Player::Sync::isSynced($client)) {syncFunction($client, $fade, "mute",undef);};
			} elsif ($p1 eq "balance") {
				# unsupported yet
			} elsif ($p1 eq "treble") {
				my $newtreb;
				my $oldtreb = Slim::Utils::Prefs::clientGet($client, "treble");
				if ($p2 eq "?") {
					$p2 = $oldtreb;
				} else {
				
					if ($p2 =~ /^[\+\-]/) {
						$newtreb = $oldtreb + $p2;
					} else {
						$newtreb = $p2;
					}
					if ($newtreb > $Slim::Player::Client::maxTreble) { $newtreb = $Slim::Player::Client::maxTreble; }
					if ($newtreb < $Slim::Player::Client::minTreble) { $newtreb = $Slim::Player::Client::minTreble; }
					Slim::Utils::Prefs::clientSet($client, "treble", $newtreb);
					$client->treble($newtreb);
					if (Slim::Player::Sync::isSynced($client)) {syncFunction($client, $newtreb, "treble",\&setTreble);};
				}
			} elsif ($p1 eq "bass") {
				my $newbass;
				my $oldbass = Slim::Utils::Prefs::clientGet($client, "bass");
				if ($p2 eq "?") {
					$p2 = $oldbass;
				} else {
				
					if ($p2 =~ /^[\+\-]/) {
						$newbass = $oldbass + $p2;
					} else {
						$newbass = $p2;
					}
					if ($newbass > $Slim::Player::Client::maxBass) { $newbass = $Slim::Player::Client::maxBass; }
					if ($newbass < $Slim::Player::Client::minBass) { $newbass = $Slim::Player::Client::minBass; }
					Slim::Utils::Prefs::clientSet($client, "bass", $newbass);
					$client->bass($newbass);
					if (Slim::Player::Sync::isSynced($client)) {syncFunction($client, $newbass, "bass",\&setBass);};
				}
			} elsif ($p1 eq "pitch") {
				my $newpitch;
				my $oldpitch = Slim::Utils::Prefs::clientGet($client, "pitch");
				if ($p2 eq "?") {
					$p2 = $oldpitch;
				} else {
				
					if ($p2 =~ /^[\+\-]/) {
						$newpitch = $oldpitch + $p2;
					} else {
						$newpitch = $p2;
					}
					if ($newpitch > $Slim::Player::Client::maxPitch) { $newpitch = $Slim::Player::Client::maxPitch; }
					if ($newpitch < $Slim::Player::Client::minPitch) { $newpitch = $Slim::Player::Client::minPitch; }
					Slim::Utils::Prefs::clientSet($client, "pitch", $newpitch);
					$client->pitch($newpitch);
					if (Slim::Player::Sync::isSynced($client)) {syncFunction($client, $newpitch, "pitch",\&setPitch);};
				}
			}
		} elsif ($p0 eq "displaynow") {
			if ($p1 eq "?" && $p2 eq "?") {
				$p1 = $client->prevline1();
				$p2 = $client->prevline2();
			} 		
		} elsif ($p0 eq "display") {
			if ($p1 eq "?" && $p2 eq "?") {
				my ($line1, $line2) = Slim::Display::Display::curLines($client);
				$p1 = $line1;
				$p2 = $line2;
			} else {
				Slim::Buttons::ScreenSaver::wakeup($client);
				Slim::Display::Animation::showBriefly($client, $p1, $p2, $p3, $p4);
			}
		} elsif ($p0 eq "button") {
			# all buttons now go through execute()
			Slim::Hardware::IR::executeButton($client, $p1, $p2);
		} elsif ($p0 eq "ir") {
			# all ir signals go through execute()
			Slim::Hardware::IR::processIR($client, $p1, $p2);
		}
	}
	
	my @returnArray = ();
	
	if (defined($p0)) { push @returnArray, $p0 };
	if (defined($p1)) { push @returnArray, $p1 };
	if (defined($p2)) { push @returnArray, $p2 };
	if (defined($p3)) { push @returnArray, $p3 };
	if (defined($p4)) { push @returnArray, $p4 };
	if (defined($p5)) { push @returnArray, $p5 };
	if (defined($p6)) { push @returnArray, $p6 };
	
	$callcallback && $callbackf && (&$callbackf(@$callbackargs, \@returnArray));

	executeCallback($client, \@returnArray);
	
	$::d_command && msg(" Returning array: $p0 (" .
			(defined $p1 ? $p1 : "") . ") (" .
			(defined $p2 ? $p2 : "") . ") (" .
			(defined $p3 ? $p3 : "") . ") (" .
			(defined $p4 ? $p4 : "") . ") (" .
			(defined $p5 ? $p5 : "") . ") (" .
			(defined $p6 ? $p6 : "") . ")\n");
	
	return @returnArray;
}

sub syncFunction {
	my $client = shift;
	my $newval = shift;
	my $setting = shift;
	my $controlRef = shift;
	
	my @buddies = Slim::Player::Sync::syncedWith($client);
	if (scalar(@buddies) > 0) {
		foreach my $eachclient (@buddies) {
			if (Slim::Utils::Prefs::clientGet($eachclient,'syncVolume')) {
				if ($setting eq "mute") {
					$eachclient->fade_volume($newval, "mute", [$eachclient]);
				} else {
					Slim::Utils::Prefs::clientSet($eachclient, $setting, $newval);
					&$controlRef($eachclient, $newval);
				}
				if ($setting eq "volume") {
					Slim::Display::Display::volumeDisplay($eachclient);
				}
			}
			if (Slim::Utils::Prefs::clientGet($client,'syncPower')) {
				if ($setting eq "power") {
					$eachclient->power($newval);
				}
			}
		}
	}
}

sub setVolume {
	my $client = shift;
	my $volume = shift;
	$client->volume($volume);
}

sub setBass {
	my $client = shift;
	my $bass = shift;
	$client->bass($bass);
}

sub setPitch {
	my $client = shift;
	my $pitch = shift;
	$client->pitch($pitch);
}

sub setTreble {
	my $client = shift;
	my $treble = shift;
	$client->treble($treble);
}

sub setExecuteCallback {
	my $callbackRef = shift;
	$executeCallbacks{$callbackRef} = $callbackRef;
}

sub clearExecuteCallback {
	my $callbackRef = shift;
	delete $executeCallbacks{$callbackRef};
}

sub executeCallback {
	my $client = shift;
	my $paramsRef = shift;

	no strict 'refs';
		
	foreach my $executecallback (keys %executeCallbacks) {
		$executecallback = $executeCallbacks{$executecallback};
		&$executecallback($client, $paramsRef);
	}
}

sub load_done {
	my ($client, $index, $callbackf, $callbackargs)=@_;
	Slim::Player::Playlist::reshuffle($client);
	if (defined($index)) {
		Slim::Player::Source::jumpto($client, $index);
	}
	$callbackf && (&$callbackf(@$callbackargs));
	Slim::Control::Command::executeCallback($client, ['playlist','load_done']);
}

sub insert_done {
	my ($client, $listsize, $size,$callbackf, $callbackargs)=@_;
	my $i;
	my $playlistIndex = Slim::Player::Source::currentSongIndex($client)+1;
	my @reshuffled;

	if (Slim::Player::Playlist::shuffle($client)) {
		for ($i = 0; $i < $size; $i++) {
			push @reshuffled,$listsize+$i;
		};
		$client = Slim::Player::Sync::masterOrSelf($client);
		
		splice @{$client->shufflelist},$playlistIndex, 0, @reshuffled;
	} else {
		Slim::Player::Playlist::moveSong($client, $listsize, $playlistIndex,$size);
		Slim::Player::Playlist::reshuffle($client);
	};
	Slim::Player::Playlist::refreshPlaylist($client);
	$callbackf && (&$callbackf(@$callbackargs));
	Slim::Control::Command::executeCallback($client, ['playlist','load_done']);
}

sub singletonRef {
	my $arg = shift;

	if (!defined($arg)) {
		return [];
	} elsif ($arg eq '*') {
		return [];
	} elsif ($arg) {
		return [$arg];
	} else {
		return [];
	}
}

sub gotosleep {
	my $client = shift;
	if ($client->isPlayer()) {
		$client->fade_volume(-60,\&turnitoff,[$client]);
	}
	$client->sleepTime(0);
	$client->currentSleepTime(0);
}

sub turnitoff {
	my $client = shift;
	
	# Turn off quietly
	execute($client, ['stop', 0]);
	execute($client, ['power', 0]);
}

1;
__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:

