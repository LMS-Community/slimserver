package Slim::Web::Pages;

# $Id: Pages.pm,v 1.40 2004/01/30 06:19:41 kdf Exp $
# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use File::Spec::Functions qw(:ALL);
use POSIX;
use Slim::Utils::Misc;

use Slim::Utils::Strings qw(string);

my($NEWLINE) = "\012";

sub home {
	my($client, $paramsref) = @_;
	my %listform;

	if (defined($$paramsref{'forget'})) {
		Slim::Player::Client::forgetClient($$paramsref{'forget'});
	}
	if ($::nosetup) {
		$$paramsref{'nosetup'} = 1;
	}
	if ($::newVersion) {
		$$paramsref{'newVersion'} = $::newVersion;
	}
	
	# fill out the client setup choices
	foreach my $player (sort { $a->name() cmp $b->name() } Slim::Player::Client::clients()) {
		# every player gets a page.
		# next if (!$player->isPlayer());
		$listform{'playername'} = $player->name();
		$listform{'playerid'} = $player->id();
		$listform{'player'} = $$paramsref{'player'};
		$listform{'skinOverride'} = $$paramsref{'skinOverride'};
		$$paramsref{'player_list'} .= ${Slim::Web::HTTP::filltemplatefile("homeplayer_list.html", \%listform)};
	}

	if (Slim::Music::iTunes::useiTunesLibrary()) {
		$$paramsref{'nofolder'} = 1;
	}
	if (!Slim::Utils::Prefs::get('lookForArtwork')) {
		$$paramsref{'noartwork'} = 1;
	}
	
	addStats($paramsref, [],[],[],[]);

	my $template = 'index.html';
	if ( $$paramsref{"path"}  =~ /home\.(htm|xml)/) { $template = 'home.html'; }
	
	return Slim::Web::HTTP::filltemplatefile($template, $paramsref);
}

sub addStats {
	my $paramsref = shift;
	my $genreref = shift;
	my $artistref = shift;
	my $albumref = shift;
	my $songref = shift;
	
	if (!Slim::Utils::Misc::stillScanning()) {
		my $count = Slim::Music::Info::songCount($genreref,$artistref,$albumref,$songref);
		$$paramsref{'song_count'} = $count . " " . lc(($count == 1 ? string('SONG') : string('SONGS')));
		$count = Slim::Music::Info::artistCount($genreref,$artistref,$albumref,$songref);
		$$paramsref{'artist_count'} = $count . " " . lc(($count == 1 ? string('ARTIST') : string('ARTISTS')));
		$count	= Slim::Music::Info::albumCount($genreref,$artistref,$albumref,$songref);
		$$paramsref{'album_count'} = $count . " " . lc(($count == 1 ? string('ALBUM') : string('ALBUMS')));
	}
}

sub browser {
	my($client, $paramsref, $callback, $httpclientsock, $result, $headersref, $paramheadersref) = @_;
	my $dir = defined($$paramsref{'dir'}) ? $$paramsref{'dir'} : "";

	my $item;
	my $itempath;
	my @items;
	my %list_form;
	my $current_player = "";
	my $playlist;
	my $fulldir = Slim::Utils::Misc::virtualToAbsolute($dir);

	$::d_http && msg("browse virtual path: " . $dir . "\n");
	$::d_http && msg("with absolute path: " . $fulldir . "\n");

	if (defined($client)) {
		$current_player = $client->id();
	}

	if ($dir =~ /^__playlists/) {
		$playlist = 1;
		$$paramsref{'playlist'} = 1;

		if (!defined(Slim::Utils::Prefs::get("playlistdir") && !Slim::Music::iTunes::useiTunesLibrary())) {
			$::d_http && msg("no valid playlists directory!!\n");
			return Slim::Web::HTTP::filltemplatefile("badpath.html", $paramsref);
		}

		if ($dir =~ /__current.m3u$/) {
			# write out the current playlist to a file with the special name __current
			if (defined($client)) {
				my $count = Slim::Player::Playlist::count($client);
				$::d_http && msg("Saving playlist of $count items to $fulldir\n");
				if ($count) {
					Slim::Control::Command::execute($client, ['playlist', 'save', '__current']);
				}
			} else {
				$::d_http && msg("no client, so we can't save a file!!\n");
				return Slim::Web::HTTP::filltemplatefile("badpath.html", $paramsref);
			}
		}

	} else {
		if (!defined(Slim::Utils::Prefs::get("audiodir"))) {
			$::d_http && msg("no audiodir, so we can't save a file!!\n");
			return Slim::Web::HTTP::filltemplatefile("badpath.html", $paramsref);
		}
	}

	if (!$fulldir || !Slim::Music::Info::isList($fulldir)) {
		# check if we're just showing itunes playlists
		if (Slim::Music::iTunes::useiTunesLibrary()) {
			browser_addtolist_done($current_player, $httpclientsock, $paramsref, [], $result, $headersref, $paramheadersref);
			return undef;
		} else {
			$::d_http && msg("the selected playlist $fulldir isn't good!!.\n");
			return Slim::Web::HTTP::filltemplatefile("badpath.html", $paramsref);
		}
	}

	# if they are renaming the playlist, let 'em.
	if ($playlist && $$paramsref{'newname'}) {
		my $newname = $$paramsref{'newname'};
		# don't allow periods, colons, control characters, slashes, backslashes, just to be safe.
		$newname =~ tr/.:\x00-\x1f\/\\/ /s;
		if (Slim::Music::Info::isM3U($fulldir)) { $newname .= ".m3u"; };
		if (Slim::Music::Info::isPLS($fulldir)) { $newname .= ".pls"; };
		
		if ($newname ne "") {
			my @newpath  = splitdir($fulldir);
			pop @newpath;
			my $container = catdir(@newpath);
			push @newpath, $newname;
			my $newfullname = catdir(@newpath);

			$::d_http && msg("renaming $fulldir to $newfullname\n");
			if ($newfullname ne $fulldir && !-e $newfullname && rename $fulldir, $newfullname) {
				Slim::Music::Info::clearCache($container);
				Slim::Music::Info::clearCache($fulldir);
				$fulldir = $newfullname;

				$dir = Slim::Utils::Misc::descendVirtual(Slim::Utils::Misc::ascendVirtual($dir), $newname);

				$$paramsref{'dir'} = $dir;
				$::d_http && msg("new dir value: $dir\n");
			} else {
				$::d_http && msg("Rename failed!\n");
				$$paramsref{'RENAME_WARNING'} = 1;
			}
		}
	} elsif ($playlist && $$paramsref{'delete'}) {
		if (-f $fulldir && unlink $fulldir) {
			my @newpath  = splitdir($fulldir);
			pop @newpath;
			my $container = catdir(@newpath);
			Slim::Music::Info::clearCache($container);
			Slim::Music::Info::clearCache($fulldir);
			$dir = Slim::Utils::Misc::ascendVirtual($dir);
			$$paramsref{'dir'} = $dir;
			$fulldir = Slim::Utils::Misc::virtualToAbsolute($dir);
		}
	}

	#
	# Make separate links for each component of the pwd
	#
	%list_form=();
	$list_form{'player'} = $current_player;
	$list_form{'myClientState'} = $client;
	$list_form{'skinOverride'} = $$paramsref{'skinOverride'};
	my $aggregate = "";
	if ($playlist) { $aggregate = "__playlists" };
	$$paramsref{'pwd_list'} = " ";
	my $lastpath;
	foreach my $c (splitdir($dir)) {
		if ($c ne "" && $c ne "__playlists" && $c ne "__current.m3u") {
			$aggregate = (defined($aggregate) && $aggregate ne '') ? catdir($aggregate, $c) : $c;        # incrementally build the path for each link
			$list_form{'dir'}=Slim::Web::HTTP::escape($aggregate);
				if ($c =~ /(.*)\.m3u$/) { $c = $1; }
			
			if (Slim::Music::Info::isURL($c)) {
				$list_form{'shortdir'}= Slim::Music::Info::standardTitle(undef, $c);
			} else {
				$list_form{'shortdir'}=$c; #possibly make this into the TITLE of the playlist if this is a number
			}
			$$paramsref{'pwd_list'} .= ${Slim::Web::HTTP::filltemplatefile("browse_pwdlist.html", \%list_form)};
		}
		if ($c) { $lastpath = $c; }
	}

	if (Slim::Music::Info::isM3U($fulldir)) {
		$::d_http && msg("lastpath equals $lastpath\n");
		if ($lastpath eq "__current.m3u") {
			$$paramsref{'playlistname'} = string("UNTITLED");
			$$paramsref{'savebuttonname'} = string("SAVE");
		} else {
			$lastpath =~ s/(.*)\.m3u$/$1/;
			$$paramsref{'playlistname'} = $lastpath;
			$$paramsref{'savebuttonname'} = string("RENAME");
			$$paramsref{'titled'} = 1;
		}
	} elsif (Slim::Music::Info::isPLS($fulldir)) {
			$lastpath =~ s/(.*)\.pls$/$1/;
			$$paramsref{'playlistname'} = $lastpath;
			$$paramsref{'savebuttonname'} = string("RENAME");
			$$paramsref{'titled'} = 1;
	}

	my $items = [];

	Slim::Utils::Scan::addToList($items, $fulldir, 0, undef,  
			\&browser_addtolist_done, $current_player, $callback, $httpclientsock, $paramsref, $items, $result, $headersref, $paramheadersref);  
	
	# when this finishes, it calls the next function, browser_addtolist_done:
	return undef; # return undef means we'll take care of sending the output to the client (special case because we're going into the background)
}

sub browser_addtolist_done {
	my (	$current_player,
		$callback,
		$httpclientsock,
		$paramsref,
		$itemsref,
		$result,
		$headersref,
		$paramheadersref
	) = @_;
	
	if (defined $paramsref->{'dir'} && $paramsref->{'dir'} eq '__playlists' && Slim::Music::iTunes::useiTunesLibrary()) {
		$::d_http && msg("just showing itunes playlists\n");
		push @$itemsref, @{Slim::Music::iTunes::playlists()};
		if (Slim::Music::iTunes::stillScanning()) {
			$paramsref->{'warn'} = 1;
		}
	} 
	
	my $numitems = scalar @{ $itemsref };
	
	$::d_http && msg("browser_addtolist_done with $numitems items (". scalar @{ $itemsref } . ")\n");

	my $shortitem;
	${$paramsref}{'browse_list'} = " ";
	if ($numitems) {
		my %list_form;
		my $item;
		my $otherparams = 	'player=' . Slim::Web::HTTP::escape($current_player) .
							'&dir=' . Slim::Web::HTTP::escape($paramsref->{'dir'}) . '&';
							
		my @namearray;
		foreach $item ( @{$itemsref} ) {
			$::d_http && msg("browser_addtolist_done getting name for $item\n");
			if ($item) {
				push @namearray, Slim::Music::Info::standardTitle(undef,$item);
			}
		}
		my ($start,$end);
		
		if (defined $paramsref->{'nopagebar'}){
			($start, $end) = simpleheader($numitems,
											\$$paramsref{'start'},
											\$$paramsref{'browselist_header'},
											$$paramsref{'skinOverride'},
											$$paramsref{'itemsPerPage'},
											0);
		}
		else{
			($start,$end) = pagebar($numitems,
								$$paramsref{'path'},
								0,
								$otherparams,
								\$$paramsref{'start'},
								\$$paramsref{'browselist_header'},
								\$$paramsref{'browselist_pagebar'},
								$$paramsref{'skinOverride'}
								,$$paramsref{'itemsPerPage'});
		}
		my $itemnumber = $start;
		my $offset = $start % 2 ? 0 : 1;
		my $lastAnchor = '';
		my $filesort = Slim::Utils::Prefs::get('filesort');
		my ($cover,$thumb, $body, $type);
		
		# don't look up cover art info if we're browsing a playlist.
		if ($paramsref->{'dir'} && $paramsref->{'dir'} =~ /^__playlists/) { $thumb = 1; $cover = 1;}
		
		foreach $item ( @{$itemsref}[$start..$end] ) {
			
			# make sure the players get some time...
			::idleStreams();
			
			# don't display and old unsaved playlist
			if ($item =~ /__current.m3u$/) { next; }
			%list_form=();
			#
			# There are different templates for directories and playlist items:
			#
			$shortitem = Slim::Utils::Misc::descendVirtual($paramsref->{'dir'},$item,$itemnumber);
			if (Slim::Music::Info::isList($item)) {
				$list_form{'descend'}     = $shortitem;
			} elsif (Slim::Music::Info::isSong($item)){
				$list_form{'descend'}     = 0;
				if (!defined $cover) {
					($body, $type) =  Slim::Music::Info::coverArt($item,'cover');
					if (defined($body)) { $$paramsref{'coverart'} = 1; $$paramsref{'coverartpath'} = $shortitem;}
					$cover = $item;
				}
				if (!defined $thumb) {
					($body, $type) =  Slim::Music::Info::coverArt($item,'thumb');
					if (defined($body)) { $$paramsref{'coverthumb'} = 1; $$paramsref{'thumbpath'} = $shortitem;}
					$thumb = $item;
				}
			}

			if ($filesort) {
				$list_form{'title'}		= Slim::Music::Info::fileName($item);
			} else {
				$list_form{'title'}		= Slim::Music::Info::standardTitle(undef,$item);
				$list_form{'artist'}    = Slim::Music::Info::artist($item);
				$list_form{'album'}     = Slim::Music::Info::album($item);
			}
			
			$list_form{'itempath'}  = Slim::Utils::Misc::virtualToAbsolute($item);
			$list_form{'odd'}	  	= ($itemnumber + $offset) % 2;
			$list_form{'player'}	= $current_player;
			$list_form{'mixable_not_descend'} = Slim::Music::Info::isSongMixable($item);
			addStats($paramsref, [],[],[],[]);
 						
			my $anchor = anchor($list_form{'title'},1);
			if ($lastAnchor ne $anchor) {
				$list_form{'anchor'}  = $anchor;
				$lastAnchor = $anchor;
			}
			$list_form{'skinOverride'} = $$paramsref{'skinOverride'};
			$$paramsref{'browse_list'} .= ${Slim::Web::HTTP::filltemplatefile(($$paramsref{'playlist'} ? "browse_playlist_list.html" : "browse_list.html"), \%list_form)};
			$itemnumber++;
		}
	} else {
		$$paramsref{'browse_list'} = ${Slim::Web::HTTP::filltemplatefile("browse_list_empty.html", {'skinOverride' => $$paramsref{'skinOverride'}})};
	}

	my $output =  Slim::Web::HTTP::filltemplatefile(($$paramsref{'playlist'} ? "browse_playlist.html" : "browse.html"), $paramsref);

	$callback->($current_player, $paramsref, $output, $httpclientsock, $result, $headersref, $paramheadersref);
}

#
# Send the status page (what we're currently playing, contents of the playlist)
#

sub status_header {
	my($client, $paramsref, $callback, $httpclientsock, $result, $headersref, $paramheadersref) = @_;
	$$paramsref{'omit_playlist'} = 1;
	return status(@_);
}

sub status {
	my($client, $main_form_ref, $callback, $httpclientsock, $resultref, $headersref, $paramheadersref) = @_;

	$$main_form_ref{'playercount'} = Slim::Player::Client::clientCount();
	
	my @players = Slim::Player::Client::clients();
	if (scalar(@players) > 1) {
		my %clientlist = ();
		foreach my $eachclient (@players) {
			$clientlist{$eachclient->id()} =  $eachclient->name();
			if (Slim::Player::Sync::isSynced($eachclient)) {
				$clientlist{$eachclient->id()} .= " (".string('SYNCHRONIZED_WITH')." ".Slim::Player::Sync::syncwith($eachclient).")";
			}	
		}
		$$main_form_ref{'player_chooser_list'} = options($client->id(),\%clientlist,$$main_form_ref{'skinOverride'});
	}

	$$main_form_ref{'refresh'} = Slim::Utils::Prefs::get("refreshRate");
	
	if (!defined($client)) {
		return Slim::Web::HTTP::filltemplatefile("status_noclients.html", $main_form_ref);
	} elsif ($client->needsUpgrade()) {
		$$main_form_ref{'player_needs_upgrade'} = '1';
		return Slim::Web::HTTP::filltemplatefile("status_needs_upgrade.html", $main_form_ref);
	}

	my $current_player;
	my $songcount = 0;
	 
	if (defined($client)) {
		$songcount = Slim::Player::Playlist::count($client);
		
		if ($client->defaultName() ne $client->name()) {
			$$main_form_ref{'player_name'} = $client->name();
		}
		if (Slim::Player::Playlist::shuffle($client) == 1) {
			$$main_form_ref{'shuffleon'} = "on";
		} elsif (Slim::Player::Playlist::shuffle($client) == 2) {
			$$main_form_ref{'shufflealbum'} = "album";
		} else {
			$$main_form_ref{'shuffleoff'} = "off";
		}
	
		$$main_form_ref{'songtime'} = int(Slim::Player::Source::songTime($client));
		if (Slim::Player::Playlist::song($client)) { 
			my $dur = Slim::Music::Info::durationSeconds(Slim::Player::Playlist::song($client));
			if ($dur) { $dur = int($dur); }
			$$main_form_ref{'songduration'} = $dur; 
		}
		
		if (!Slim::Player::Playlist::repeat($client)) {
			$$main_form_ref{'repeatoff'} = "off";
		} elsif (Slim::Player::Playlist::repeat($client) == 1) {
			$$main_form_ref{'repeatone'} = "one";
		} else {
			$$main_form_ref{'repeatall'} = "all";
		}
	
		if("play" eq Slim::Player::Source::playmode($client)) {
			$$main_form_ref{'modeplay'} = "Play";
			if (defined($$main_form_ref{'songduration'}) && defined($$main_form_ref{'songtime'})) {
				my $remaining = $$main_form_ref{'songduration'} - $$main_form_ref{'songtime'};
				if ($remaining < $$main_form_ref{'refresh'}) { $$main_form_ref{'refresh'} = ($remaining < 2) ? 2 : $remaining;}
			}
		} elsif ("pause" eq Slim::Player::Source::playmode($client)) {
			$$main_form_ref{'modepause'} = "Pause";
		
		} else {
			$$main_form_ref{'modestop'} = "Stop";
		}
		if (Slim::Player::Source::rate($client) > 1) {
			$$main_form_ref{'rate'} = 'ffwd';
		} elsif (Slim::Player::Source::rate($client) < 0) {
			$$main_form_ref{'rate'} = 'rew';
		} else {
			$$main_form_ref{'rate'} = 'norm';
		}
		
		$$main_form_ref{'sync'} = Slim::Player::Sync::syncwith($client);
		
		$$main_form_ref{'mode'} = Slim::Buttons::Common::mode($client);
		if ($client->isPlayer()) {
			$$main_form_ref{'sleeptime'} = $client->currentSleepTime();
			$$main_form_ref{'isplayer'} = 1;
			$$main_form_ref{'volume'} = int(Slim::Utils::Prefs::clientGet($client, "volume") + 0.5);
			$$main_form_ref{'bass'} = int(Slim::Utils::Prefs::clientGet($client, "bass") + 0.5);
			$$main_form_ref{'treble'} = int(Slim::Utils::Prefs::clientGet($client, "treble") + 0.5);
		}
		
		$$main_form_ref{'player'} = $client->id();
	}
	
	if ($songcount > 0) {
		my $song = Slim::Player::Playlist::song($client);
		$$main_form_ref{'currentsong'}    = Slim::Player::Source::currentSongIndex($client) + 1;
		$$main_form_ref{'thissongnum'}    = Slim::Player::Source::currentSongIndex($client);
		$$main_form_ref{'songcount'}      = $songcount;
		$$main_form_ref{'songtitle'}      = Slim::Music::Info::standardTitle(undef,$song);
		$$main_form_ref{'artist'} 	  = Slim::Music::Info::artist($song);
		$$main_form_ref{'album'} 	  = Slim::Music::Info::album($song);
		addsonginfo($client, $song, $main_form_ref);

		if (Slim::Utils::Prefs::get("playlistdir"))  { $$main_form_ref{'cansave'} = 1; };
	}
	
	my $output = "";
	
	if (!$$main_form_ref{'omit_playlist'}) {
		$$main_form_ref{'callback'} = $callback;
		$$main_form_ref{'playlist'} = playlist($client, $main_form_ref, \&status_done, $httpclientsock, $resultref, $headersref, $paramheadersref);
		if (!$$main_form_ref{'playlist'}) {
			#playlist went into background, stash $callback and exit
			return undef;
		} else {
			$$main_form_ref{'playlist'} = ${$$main_form_ref{'playlist'}};
		}
	}
	return Slim::Web::HTTP::filltemplatefile($$main_form_ref{'omit_playlist'} ? "status_header.html" : "status.html" , $main_form_ref);
}

sub status_done {
	my ($client, $main_form_ref, $bodyref, $httpclientsock, $resultref, $headersref, $paramheadersref) = @_;
	$$main_form_ref{'playlist'} = $$bodyref;
	my $output = Slim::Web::HTTP::filltemplatefile("status.html" , $main_form_ref);
	$$main_form_ref{'callback'}->($client, $main_form_ref, $output, $httpclientsock, $resultref, $headersref, $paramheadersref);
}

sub playlist {
	my($client, $main_form_ref, $callback, $httpclientsock, $resultref, $headersref, $paramheadersref) = @_;
	
	if (defined($client) && $client->needsUpgrade()) {
		$$main_form_ref{'player_needs_upgrade'} = '1';
		return Slim::Web::HTTP::filltemplatefile("playlist_needs_upgrade.html", $main_form_ref);
	}
	
	my $songcount = 0;
	if (defined($client)) {$songcount = Slim::Player::Playlist::count($client);}
	$$main_form_ref{'playlist_items'} = '';
	if ($songcount > 0) {
		my %listBuild = ();
		my $item;
		my %list_form;
		if (Slim::Utils::Prefs::get("playlistdir"))  { $$main_form_ref{'cansave'} = 1; };
		
		my ($start,$end);
		
		if (defined $main_form_ref->{'nopagebar'}){
			($listBuild{'start'}, $listBuild{'end'}) = simpleheader($songcount,
											\$$main_form_ref{'start'},
											\$$main_form_ref{'playlist_header'},
											$$main_form_ref{'skinOverride'},
											$$main_form_ref{'itemsPerPage'},
											0);
		}
		else{
			($listBuild{'start'}, $listBuild{'end'}) = pagebar($songcount,
								$$main_form_ref{'path'},
								Slim::Player::Source::currentSongIndex($client),
								"player=" . Slim::Web::HTTP::escape($client->id()) . "&", 
								\$$main_form_ref{'start'}, 
								\$$main_form_ref{'playlist_header'},
								\$$main_form_ref{'playlist_pagebar'},
								$$main_form_ref{'skinOverride'}
								,$$main_form_ref{'itemsPerPage'});
		}
		$listBuild{'offset'} = $listBuild{'start'} % 2 ? 0 : 1; 
		my $webFormat = Slim::Utils::Prefs::getInd("titleFormat",Slim::Utils::Prefs::get("titleFormatWeb"));
		$listBuild{'includeArtist'} =  ($webFormat !~ /ARTIST/);
		$listBuild{'includeAlbum'} = ($webFormat !~ /ALBUM/) ;
		$listBuild{'currsongind'} = Slim::Player::Source::currentSongIndex($client);
		$listBuild{'item'} = $listBuild{'start'};
		if (buildPlaylist ($client, $main_form_ref, $callback, $httpclientsock, $resultref
					, $headersref, $paramheadersref, \%listBuild)) {
			Slim::Utils::Scheduler::add_task(\&buildPlaylist
								,$client
								,$main_form_ref
								,$callback
								,$httpclientsock
								,$resultref
								,$headersref
								,$paramheadersref
								,\%listBuild);
		}
		return undef;
	}
	return  Slim::Web::HTTP::filltemplatefile("playlist.html", $main_form_ref);
}

sub buildPlaylist {
	my($client, $main_form_ref, $callback, $httpclientsock, $result, $headersref, $paramheadersref, $listBuild) = @_;
	my %list_form = ();
	my $itemCount = 0;
	my $buildItemsPerPass = Slim::Utils::Prefs::get('buildItemsPerPass');
	my $starttime = Time::HiRes::time();
	while ($$listBuild{'item'} < ($$listBuild{'end'} + 1) && $itemCount < $buildItemsPerPass) {
		%list_form = ();
		$list_form{'myClientState'} = $client;
		$list_form{'num'}=$$listBuild{'item'};
		$list_form{'odd'} = ($$listBuild{'item'} + $$listBuild{'offset'}) % 2;
		if ($$listBuild{'item'} == $$listBuild{'currsongind'}) {
			$list_form{'currentsong'} = "current";
		} else {
			$list_form{'currentsong'} = undef;
		}
		$list_form{'nextsongind'} = $$listBuild{'currsongind'} + (($$listBuild{'item'} > $$listBuild{'currsongind'}) ? 1 : 0);
		my $song = Slim::Player::Playlist::song($client, $$listBuild{'item'});
		$list_form{'player'}	= $$main_form_ref{'player'};
		$list_form{'title'} 	= Slim::Music::Info::standardTitle(undef,$song);
		if ($$listBuild{'includeArtist'}) { $list_form{'artist'} 	= Slim::Music::Info::artist($song);}
		if ($$listBuild{'includeAlbum'}) { $list_form{'album'} 	= Slim::Music::Info::album($song);} 
		$list_form{'start'}		= $$main_form_ref{'start'};
		$list_form{'skinOverride'}		= $$main_form_ref{'skinOverride'};
		push @{$listBuild->{'playlist_items'}}, ${Slim::Web::HTTP::filltemplatefile("status_list.html", \%list_form)};
		$$listBuild{'item'}++;
		$itemCount++;
		# don't neglect the streams for over 0.25 seconds
		::idleStreams() if (Time::HiRes::time() - $starttime) > 0.25;
	}
	if ($$listBuild{'item'} < $$listBuild{'end'} + 1) {
		return 1;
	} else {
		$$main_form_ref{'playlist_items'} = join('',@{$listBuild->{'playlist_items'}});
		undef(%$listBuild);
		playlist_done($client, $main_form_ref, $callback, $httpclientsock, $result, $headersref, $paramheadersref);
		return 0;
	}
}

sub playlist_done {
	my($client, $main_form_ref, $callback, $httpclientsock, $result, $headersref, $paramheadersref) = @_;
	my $body = Slim::Web::HTTP::filltemplatefile("playlist.html", $main_form_ref);
	if (ref($callback) eq 'CODE') {
		$callback->($client, $main_form_ref, $body, $httpclientsock, $result, $headersref, $paramheadersref);
	}
}

sub search {
	my($client, $paramsref) = @_;
	$$paramsref{'browse_list'} = " ";

	my $player = $$paramsref{'player'};
	my $query = $$paramsref{'query'};
	$$paramsref{'numresults'} = -1;

	my $descend;
	my $lastAnchor = '';
	if ($query) {
		my $otherparams = 'player=' . Slim::Web::HTTP::escape($player) . 
		                  '&type=' . ($$paramsref{'type'} ? $$paramsref{'type'} : ''). 
		                  '&query=' . Slim::Web::HTTP::escape($$paramsref{'query'}) . '&';
		if ($$paramsref{'type'} eq 'artist') {
			my @searchresults = Slim::Music::Info::artists([], searchStringSplit($query), [], []);
			$$paramsref{'numresults'} = scalar @searchresults;
			$descend = 'true';
			my $itemnumber = 0;
			if ($$paramsref{'numresults'}) {
			
				my ($start,$end);
				if (defined $paramsref->{'nopagebar'}){
					($start, $end) = simpleheader(scalar @searchresults,
											\$$paramsref{'start'},
											\$$paramsref{'browselist_header'},
											$$paramsref{'skinOverride'},
											$$paramsref{'itemsPerPage'},
											0);
				}
				else{
					($start,$end) = alphapagebar(\@searchresults
								,$$paramsref{'path'}
								,$otherparams
								,\$$paramsref{'start'}
								,\$$paramsref{'searchlist_pagebar'}
								,1
								,$$paramsref{'skinOverride'}
								,$$paramsref{'itemsPerPage'});
				}
				foreach my $item ( @searchresults[$start..$end] ) {
					my %list_form=();
					$list_form{'genre'}	  = '*';
					$list_form{'artist'}  = $item;
					$list_form{'album'}	  = '';
					$list_form{'song'}	  = '';
					$list_form{'title'}   = $item;
					$list_form{'descend'} = $descend;
					$list_form{'player'} = $player;
					$list_form{'odd'}	  = ($itemnumber + 1) % 2;
					$list_form{'skinOverride'} = $$paramsref{'skinOverride'};
					my $anchor = anchor($item, 1);
					if ($lastAnchor ne $anchor) {
						$list_form{'anchor'}  = $anchor;
						$lastAnchor = $anchor;
					}
					$itemnumber++;
					$$paramsref{'browse_list'} .= ${Slim::Web::HTTP::filltemplatefile("browseid3_list.html", \%list_form)};
				}
			}
		} elsif ($$paramsref{'type'} eq 'album') {
			my @searchresults = Slim::Music::Info::albums([], [], searchStringSplit($query), []);
			$$paramsref{'numresults'} = scalar @searchresults;
			$descend = 'true';
			my $itemnumber = 0;
			if ($$paramsref{'numresults'}) {
				my ($start,$end);
				if (defined $paramsref->{'nopagebar'}){
					($start, $end) = simpleheader(scalar @searchresults,
											\$$paramsref{'start'},
											\$$paramsref{'browselist_header'},
											$$paramsref{'skinOverride'},
											$$paramsref{'itemsPerPage'},
											0);
				}
				else{
					($start,$end) = alphapagebar(\@searchresults
								,$$paramsref{'path'}
								,$otherparams
								,\$$paramsref{'start'}
								,\$$paramsref{'searchlist_pagebar'}
								,1
								,$$paramsref{'skinOverride'}
								,$$paramsref{'itemsPerPage'});
				}
				foreach my $item ( @searchresults[$start..$end] ) {
					my %list_form=();
					$list_form{'genre'}	  = '*';
					$list_form{'artist'}  = '*';
					$list_form{'album'}	  = $item;
					$list_form{'song'}	  = '';
					$list_form{'title'}   = $item;
					$list_form{'descend'} = $descend;
					$list_form{'player'} = $player;
					$list_form{'odd'}	  = ($itemnumber + 1) % 2;
					$list_form{'skinOverride'} = $$paramsref{'skinOverride'};
					my $anchor = anchor($item,1);
					if ($lastAnchor ne $anchor) {
						$list_form{'anchor'}  = $anchor;
						$lastAnchor = $anchor;
					}
					$itemnumber++;
					$$paramsref{'browse_list'} .= ${Slim::Web::HTTP::filltemplatefile("browseid3_list.html", \%list_form)};
				}
			}
		} elsif ($$paramsref{'type'} eq 'song') {
			my @searchresults = Slim::Music::Info::songs([], [], [], searchStringSplit($query), 1);
			$$paramsref{'numresults'} = scalar @searchresults;
			my $itemnumber = 0;
			if ($$paramsref{'numresults'}) {
				my ($start,$end);
				if (defined $paramsref->{'nopagebar'}){
					($start, $end) = simpleheader(scalar @searchresults,
											\$$paramsref{'start'},
											\$$paramsref{'browselist_header'},
											$$paramsref{'skinOverride'},
											$$paramsref{'itemsPerPage'},
											0);
				}
				else{
					($start,$end) = pagebar(scalar(@searchresults)
								,$$paramsref{'path'}
								,0
								,$otherparams
								,\$$paramsref{'start'}
								,\$$paramsref{'searchlist_header'}
								,\$$paramsref{'searchlist_pagebar'}
								,$$paramsref{'skinOverride'}
								,$$paramsref{'itemsPerPage'});
				}
				foreach my $item ( @searchresults[$start..$end] ) {
					my %list_form=();
					$list_form{'genre'}	  = Slim::Music::Info::genre($item);
					$list_form{'artist'}  = Slim::Music::Info::artist($item);
					$list_form{'album'}	  = Slim::Music::Info::album($item);
					$list_form{'itempath'} = $item;
					$list_form{'title'}   = Slim::Music::Info::standardTitle(undef, $item);
					$list_form{'descend'} = undef;
					$list_form{'player'} = $player;
					$list_form{'odd'}	  = ($itemnumber + 1) % 2;
					$list_form{'skinOverride'} = $$paramsref{'skinOverride'};
					$itemnumber++;
					$$paramsref{'browse_list'} .= ${Slim::Web::HTTP::filltemplatefile("browseid3_list.html", \%list_form)};
				}
			}
		}
	}
	return Slim::Web::HTTP::filltemplatefile("search.html", $paramsref);
}

sub addsonginfo {
	my($client, $song, $paramsref) = @_;

	if (!$song) {
		my $song = Slim::Music::Info::songPath($$paramsref{'genre'}, $$paramsref{'artist'}, $$paramsref{'album'}, $$paramsref{'track'});
	}

	if ($song) {
		$$paramsref{'genre'} = Slim::Music::Info::genre($song);
		$$paramsref{'artist'} = Slim::Music::Info::artist($song);
		$$paramsref{'composer'} = Slim::Music::Info::composer($song);
		$$paramsref{'band'} = Slim::Music::Info::band($song);
		$$paramsref{'conductor'} = Slim::Music::Info::conductor($song);
		$$paramsref{'album'} = Slim::Music::Info::album($song);
		$$paramsref{'title'} = Slim::Music::Info::title($song);
		if (Slim::Music::Info::fileLength($song)) { $$paramsref{'filelength'} = Slim::Utils::Misc::delimitThousands(Slim::Music::Info::fileLength($song)); }
		$$paramsref{'duration'} = Slim::Music::Info::duration($song);
		$$paramsref{'disc'} = Slim::Music::Info::disc($song);
		$$paramsref{'track'} = Slim::Music::Info::trackNumber($song);
		$$paramsref{'year'} = Slim::Music::Info::year($song);
		$$paramsref{'type'} = string(uc(Slim::Music::Info::contentType($song)));
		$$paramsref{'tagversion'} = Slim::Music::Info::tagVersion($song);
		$$paramsref{'mixable'} = Slim::Music::Info::isSongMixable($song);
		
		my ($body, $type) =  Slim::Music::Info::coverArt($song,'cover');
		if (defined($body)) { $$paramsref{'coverart'} = 1; }
		($body, $type) =  Slim::Music::Info::coverArt($song,'thumb');
		if (defined($body)) { $$paramsref{'coverthumb'} = 1; }
		
		$$paramsref{'modtime'} = Slim::Utils::Misc::longDateF(Slim::Music::Info::age($song)) . ", " . Slim::Utils::Misc::timeF(Slim::Music::Info::age($song));

		# make urls in comments into links
		$$paramsref{'comment'} = Slim::Music::Info::comment($song);
		my $comment = Slim::Music::Info::comment($song);
		if ($comment) {
			if (!($comment =~ s!\b(http://[\-~A-Za-z0-9_/\.]+)!<a href=\"$1\" target=\"_blank\">$1</a>!igo)) {
				# handle emusic-type urls which don't have http://
				$comment =~ s!\b(www\.[\-~A-Za-z0-9_/\.]+)!<a href=\"http://$1\" target=\"_blank\">$1</a>!igo;
			}
		}
		$$paramsref{'comment'} = $comment;

		$$paramsref{'bitrate'} = Slim::Music::Info::bitrate($song);

		my $url;
		my $songpath;
		if (Slim::Music::Info::isHTTPURL($song)) {
			$url = $song;
			$songpath = $song;
		} else {
			my $loc = $song;
			my @path;
			if (Slim::Music::Info::isFileURL($song)) {
				$loc = Slim::Utils::Misc::pathFromFileURL($loc);
			}
			$loc = Slim::Utils::Misc::fixPath($loc);
			$songpath = $loc;
			my $curdir = Slim::Utils::Prefs::get('audiodir');
			if ($loc =~ /^\Q$curdir\E(.*)/) {
				$url = '/music';
				@path = splitdir($1);
				foreach my $item (@path) {
					$url .= '/' . Slim::Web::HTTP::escape($item);
				}
				$url =~ s/\/\//\//;
			} else {
				$url = $loc;				
			}
	
		}
		$$paramsref{'url'} = $url;
		$$paramsref{'songpath'} = $songpath;
		
		$$paramsref{'itempath'} = $song;
	}
}

sub songinfo {
	my($client, $paramsref) = @_;

	my $song = $$paramsref{'songurl'};
	addsonginfo($client, $song, $paramsref);
	return Slim::Web::HTTP::filltemplatefile("songinfo.html", $paramsref);
}

sub generate_pwd_list {
	my ($genre, $artist, $album, $player) = @_;
	my %list_form;
	my $pwd_list = "";

	if (defined($genre) && $genre eq '*' && 
	    defined($artist) && $artist eq '*') {
		%list_form=();
		$list_form{'song'} = '';
		$list_form{'album'} = '';
		$list_form{'artist'} = '*';
		$list_form{'genre'} = '*';
		$list_form{'player'} = $player;
		$list_form{'pwditem'} = string('BROWSE_BY_ALBUM');
		$pwd_list .= ${Slim::Web::HTTP::filltemplatefile("browseid3_pwdlist.html", \%list_form)};
	} elsif (defined($genre) && $genre eq '*') {
		%list_form=();
		$list_form{'song'} = '';
		$list_form{'artist'} = '';
		$list_form{'album'} = '';
		$list_form{'genre'} = '*';
		$list_form{'player'} = $player;
		$list_form{'pwditem'} = string('BROWSE_BY_ARTIST');
		$pwd_list .= ${Slim::Web::HTTP::filltemplatefile("browseid3_pwdlist.html", \%list_form)};
	} else {
		%list_form=();
		$list_form{'song'} = '';
		$list_form{'artist'} = '';
		$list_form{'album'} = '';
		$list_form{'genre'} = '';
		$list_form{'player'} = $player;
		$list_form{'pwditem'} = string('BROWSE_BY_GENRE');
		$pwd_list .= ${Slim::Web::HTTP::filltemplatefile("browseid3_pwdlist.html", \%list_form)};
	};

	if ($genre && $genre ne '*') {
		%list_form=();
		$list_form{'song'} = '';
		$list_form{'artist'} = '';
		$list_form{'album'} = '';
		$list_form{'genre'} = $genre;
		$list_form{'player'} = $player;
		$list_form{'pwditem'} = $genre;
		$pwd_list .= ${Slim::Web::HTTP::filltemplatefile("browseid3_pwdlist.html", \%list_form)};
	}

	if ($artist && $artist ne '*') {
		%list_form=();
		$list_form{'song'} = '';
		$list_form{'album'} = '';
		$list_form{'artist'} = $artist;
		$list_form{'genre'} = $genre;
		$list_form{'pwditem'} = $artist;
		$list_form{'player'} = $player;
		$pwd_list .= ${Slim::Web::HTTP::filltemplatefile("browseid3_pwdlist.html", \%list_form)};
	}

	if ($album && $album ne '*') {
		%list_form=();
		$list_form{'song'} = '';
		$list_form{'album'} = $album;
		$list_form{'artist'} = $artist;
		$list_form{'genre'} = $genre;
		$list_form{'pwditem'} = $album;
		$list_form{'player'} = $player;
		$pwd_list .= ${Slim::Web::HTTP::filltemplatefile("browseid3_pwdlist.html", \%list_form)};
	}
	
	return $pwd_list;
}

sub browseid3 {
	my($client, $paramsref) = @_;
	my @items = ();

	my $song = $$paramsref{'song'};
	my $artist = $$paramsref{'artist'};
	my $album = $$paramsref{'album'};
	my $genre = $$paramsref{'genre'};
	my $player = $$paramsref{'player'};
	my $descend;
	my %list_form;
	my $itemnumber = 0;
	my $lastAnchor = '';

	# warn the user if the scanning isn't complete.
	if (Slim::Utils::Misc::stillScanning()) {
		$$paramsref{'warn'} = 1;
	}

	if (Slim::Music::iTunes::useiTunesLibrary()) {
		$$paramsref{'itunes'} = 1;
	}

	my $genreref = [];  	if (defined($genre) && $genre ne '') { $genreref = [$genre]; }
	my $artistref = [];  	if (defined($artist) && $artist ne '') { $artistref = [$artist]; }
	my $albumref = [];  	if (defined($album) && $album ne '') { $albumref = [$album]; }
	my $songref = [];  		if (defined($song) && $song ne '') { $songref = [$song]; }
	
	addStats($paramsref, $genreref, $artistref, $albumref, $songref);

	if (defined($album) && $album eq '*' && 
	    defined($genre) && $genre eq '*' && 
	    defined($artist) && $artist eq '*') {
		%list_form=();
		$list_form{'song'} = '';
		$list_form{'album'} = '*';
		$list_form{'artist'} = '*';
		$list_form{'genre'} = '*';
		$list_form{'player'} = $player;
		$list_form{'pwditem'} = string('BROWSE_BY_SONG');
		$list_form{'skinOverride'} = $$paramsref{'skinOverride'};
		$$paramsref{'pwd_list'} .= ${Slim::Web::HTTP::filltemplatefile("browseid3_pwdlist.html", \%list_form)};
		$$paramsref{'browseby'} = 'BROWSE_BY_SONG';
	} elsif (defined($genre) && $genre eq '*' && 
	    defined($artist) && $artist eq '*') {
		%list_form=();
		$list_form{'song'} = '';
		$list_form{'album'} = '';
		$list_form{'artist'} = '*';
		$list_form{'genre'} = '*';
		$list_form{'player'} = $player;
		if ($$paramsref{'artwork'}) {
			$list_form{'pwditem'} = string('BROWSE_BY_ARTWORK');
			$list_form{'skinOverride'} = $$paramsref{'skinOverride'};
			$list_form{'artwork'} = 1;
			$$paramsref{'pwd_list'} .= ${Slim::Web::HTTP::filltemplatefile("browseid3_pwdlist.html", \%list_form)};
			$$paramsref{'browseby'} = 'BROWSE_BY_ARTWORK';
		} else {
			$list_form{'pwditem'} = string('BROWSE_BY_ALBUM');
			$list_form{'skinOverride'} = $$paramsref{'skinOverride'};
			$$paramsref{'pwd_list'} .= ${Slim::Web::HTTP::filltemplatefile("browseid3_pwdlist.html", \%list_form)};
			$$paramsref{'browseby'} = 'BROWSE_BY_ALBUM';
		}
	} elsif (defined($genre) && $genre eq '*') {
		%list_form=();
		$list_form{'song'} = '';
		$list_form{'artist'} = '';
		$list_form{'album'} = '';
		$list_form{'genre'} = '*';
		$list_form{'player'} = $player;
		$list_form{'pwditem'} = string('BROWSE_BY_ARTIST');
		$list_form{'skinOverride'} = $$paramsref{'skinOverride'};
		$$paramsref{'pwd_list'} .= ${Slim::Web::HTTP::filltemplatefile("browseid3_pwdlist.html", \%list_form)};
		$$paramsref{'browseby'} = 'BROWSE_BY_ARTIST';
	} else {
		%list_form=();
		$list_form{'song'} = '';
		$list_form{'artist'} = '';
		$list_form{'album'} = '';
		$list_form{'genre'} = '';
		$list_form{'player'} = $player;
		$list_form{'pwditem'} = string('BROWSE_BY_GENRE');
		$list_form{'skinOverride'} = $$paramsref{'skinOverride'};
		$$paramsref{'pwd_list'} .= ${Slim::Web::HTTP::filltemplatefile("browseid3_pwdlist.html", \%list_form)};
		$$paramsref{'browseby'} = 'BROWSE_BY_GENRE';
	};

	if ($genre && $genre ne '*') {
		%list_form=();
		$list_form{'song'} = '';
		$list_form{'artist'} = '';
		$list_form{'album'} = '';
		$list_form{'genre'} = $genre;
		$list_form{'player'} = $player;
		$list_form{'pwditem'} = $genre;
		$list_form{'skinOverride'} = $$paramsref{'skinOverride'};
		$$paramsref{'pwd_list'} .= ${Slim::Web::HTTP::filltemplatefile("browseid3_pwdlist.html", \%list_form)};
	}

	if ($artist && $artist ne '*') {
		%list_form=();
		$list_form{'song'} = '';
		$list_form{'album'} = '';
		$list_form{'artist'} = $artist;
		$list_form{'genre'} = $genre;
		$list_form{'pwditem'} = $artist;
		$list_form{'player'} = $player;
		$list_form{'skinOverride'} = $$paramsref{'skinOverride'};
		$$paramsref{'pwd_list'} .= ${Slim::Web::HTTP::filltemplatefile("browseid3_pwdlist.html", \%list_form)};
	}

	if ($album && $album ne '*') {
		%list_form=();
		$list_form{'song'} = '';
		$list_form{'album'} = $album;
		$list_form{'artist'} = $artist;
		$list_form{'genre'} = $genre;
		$list_form{'pwditem'} = $album;
		$list_form{'player'} = $player;
		$list_form{'skinOverride'} = $$paramsref{'skinOverride'};
		$$paramsref{'pwd_list'} .= ${Slim::Web::HTTP::filltemplatefile("browseid3_pwdlist.html", \%list_form)};
	}
	my $otherparams = 'player=' . Slim::Web::HTTP::escape($player) . 
							'&genre=' . Slim::Web::HTTP::escape($genre) . 
							'&artist=' . Slim::Web::HTTP::escape($artist) . 
							'&album=' . Slim::Web::HTTP::escape($album) . 
							'&song=' . Slim::Web::HTTP::escape($song) . '&';
	if (!$genre) {
		# Browse by Genre
		@items = Slim::Music::Info::genres([], [$artist], [$album], [$song]);
		if (scalar(@items)) {
				my ($start,$end);
				if (defined $paramsref->{'nopagebar'}){
					($start, $end) = simpleheader(scalar(@items),
											\$$paramsref{'start'},
											\$$paramsref{'browselist_header'},
											$$paramsref{'skinOverride'},
											$$paramsref{'itemsPerPage'},
											0);
				}
				else{
					($start,$end) = alphapagebar(\@items
							,$$paramsref{'path'}
							,$otherparams
							,\$$paramsref{'start'}
							,\$$paramsref{'browselist_pagebar'}
							,0
							,$$paramsref{'skinOverride'}
							,$$paramsref{'itemsPerPage'});
				}
			$descend = 'true';
			
			if (scalar(@items) > 1) {
				%list_form=();
				if ($$paramsref{'includeItemStats'} && !Slim::Utils::Misc::stillScanning()) {
					$list_form{'album_count'}	= Slim::Music::Info::albumCount(['*'],[],[],[]);
					$list_form{'song_count'}	= Slim::Music::Info::songCount(['*'],[],[],[]);
				}
				$list_form{'genre'}	  = '*';
				$list_form{'artist'}  = '*';
				$list_form{'album'}	  = $album;
				$list_form{'song'}	  = $song;
				$list_form{'title'}   = string('ALL_ALBUMS');
				$list_form{'descend'} = $descend;
				$list_form{'player'} = $player;
				$list_form{'odd'}	  = ($itemnumber + 1) % 2;
				$list_form{'skinOverride'} = $$paramsref{'skinOverride'};
				$itemnumber++;
				$$paramsref{'browse_list'} .= ${Slim::Web::HTTP::filltemplatefile("browseid3_list.html", \%list_form)};
			}
			
			foreach my $item ( @items[$start..$end] ) {
				%list_form=();
				$list_form{'genre'}	  = $item;
				if ($$paramsref{'includeItemStats'} && !Slim::Utils::Misc::stillScanning()) {
					$list_form{'artist_count'}	= Slim::Music::Info::artistCount([$item],[],[],[]);
					$list_form{'album_count'}	= Slim::Music::Info::albumCount([$item],[],[],[]);
					$list_form{'song_count'}	= Slim::Music::Info::songCount([$item],[],[],[]);
				}
				$list_form{'artist'}  = $artist;
				$list_form{'album'}	  = $album;
				$list_form{'song'}	  = $song;
				$list_form{'title'}   = $item;
				$list_form{'descend'} = $descend;
				$list_form{'player'} = $player;
				$list_form{'odd'}	  = ($itemnumber + 1) % 2;
				$list_form{'mixable_descend'} = Slim::Music::Info::isGenreMixable($item) && ($descend eq "true");
				$list_form{'skinOverride'} = $$paramsref{'skinOverride'};
				my $anchor = anchor($item);
				if ($lastAnchor ne $anchor) {
					$list_form{'anchor'}  = $anchor;
					$lastAnchor = $anchor;
				}
				$itemnumber++;
				$$paramsref{'browse_list'} .= ${Slim::Web::HTTP::filltemplatefile("browseid3_list.html", \%list_form)};
				
				::idleStreams();
			}
		}
	} elsif (!$artist) {
		# Browse by Artist
		@items = Slim::Music::Info::artists([$genre], [], [$album], [$song]);
		if (scalar(@items)) {
				my ($start,$end);
				if (defined $paramsref->{'nopagebar'}){
					($start, $end) = simpleheader(scalar(@items),
											\$$paramsref{'start'},
											\$$paramsref{'browselist_header'},
											$$paramsref{'skinOverride'},
											$$paramsref{'itemsPerPage'},
											(scalar(@items) > 1));
				}
				else{
					($start,$end) = alphapagebar(\@items
							,$$paramsref{'path'}
							,$otherparams
							,\$$paramsref{'start'}
							,\$$paramsref{'browselist_pagebar'}
							,1
							,$$paramsref{'skinOverride'}
							,$$paramsref{'itemsPerPage'});
				}
			$descend = 'true';

			if (scalar(@items) > 1) {
				%list_form=();
				if ($$paramsref{'includeItemStats'} && !Slim::Utils::Misc::stillScanning()) {
					$list_form{'album_count'}	= Slim::Music::Info::albumCount([$genre],['*'],[],[]);
					$list_form{'song_count'}	= Slim::Music::Info::songCount([$genre],['*'],[],[]);
				}
				$list_form{'genre'}	  = $genre;
				$list_form{'artist'}  = '*';
				$list_form{'album'}	  = $album;
				$list_form{'song'}	  = $song;
				$list_form{'title'}   = string('ALL_ALBUMS');
				$list_form{'descend'} = $descend;
				$list_form{'player'} = $player;
				$list_form{'odd'}	  = ($itemnumber + 1) % 2;
				$list_form{'skinOverride'} = $$paramsref{'skinOverride'};
				$itemnumber++;
				$$paramsref{'browse_list'} .= ${Slim::Web::HTTP::filltemplatefile("browseid3_list.html", \%list_form)};
			}
			
			foreach my $item ( @items[$start..$end] ) {
				%list_form=();
				if ($$paramsref{'includeItemStats'} && !Slim::Utils::Misc::stillScanning()) {
					$list_form{'album_count'}	= Slim::Music::Info::albumCount([$genre],[$item],[],[]);
					$list_form{'song_count'}	= Slim::Music::Info::songCount([$genre],[$item],[],[]);
				}
				$list_form{'genre'}	  = $genre;
				$list_form{'artist'}  = $item;
				$list_form{'album'}	  = $album;
				$list_form{'song'}	  = $song;
				$list_form{'title'}   = $item;
				$list_form{'descend'} = $descend;
				$list_form{'player'} = $player;
				$list_form{'odd'}	  = ($itemnumber + 1) % 2;
				$list_form{'mixable_descend'} = Slim::Music::Info::isArtistMixable($item) && ($descend eq "true");
				$list_form{'skinOverride'} = $$paramsref{'skinOverride'};
				my $anchor = anchor($item, 1);
				if ($lastAnchor ne $anchor) {
					$list_form{'anchor'}  = $anchor;
					$lastAnchor = $anchor;
				}
				$itemnumber++;
				$$paramsref{'browse_list'} .= ${Slim::Web::HTTP::filltemplatefile("browseid3_list.html", \%list_form)};
				::idleStreams();
			}
		}
	} elsif (!$album) {
		# Browse by Album
		if ($$paramsref{'artwork'} && !Slim::Utils::Prefs::get('includeNoArt')) {
			# get a list of only the albums with valid artwork
			@items = Slim::Music::Info::artwork();
		} else {
			@items = Slim::Music::Info::albums([$genre], [$artist], [], [$song]);
		}
		if (scalar(@items)) {
				my ($start,$end);
				if (defined $paramsref->{'nopagebar'}){
					($start, $end) = simpleheader(scalar(@items),
											\$$paramsref{'start'},
											\$$paramsref{'browselist_header'},
											$$paramsref{'skinOverride'},
											$$paramsref{'itemsPerPage'},
											$$paramsref{'itemsPerPage'},
											(scalar(@items) > 1));
				} else {
					if  ($$paramsref{'artwork'}) {
					  $otherparams .= 'artwork=1&';
					}
					if ($$paramsref{'artwork'}) {
						($start,$end) = pagebar(scalar(@items)
							,$$paramsref{'path'}
							,0
							,$otherparams
							,\$$paramsref{'start'}
							,\$$paramsref{'browselist_header'}
							,\$$paramsref{'browselist_pagebar'}
							,$$paramsref{'skinOverride'}
							,$$paramsref{'itemsPerPage'});
					} else {
						($start,$end) = alphapagebar(\@items
							,$$paramsref{'path'}
							,$otherparams
							,\$$paramsref{'start'}
							,\$$paramsref{'browselist_pagebar'}
							,1
							,$$paramsref{'skinOverride'}
							,$$paramsref{'itemsPerPage'});
					}
				}
			$descend = 'true';
			if (!$$paramsref{'artwork'}) {
				if (scalar(@items) > 1) {
					%list_form=();
					if ($$paramsref{'includeItemStats'} && !Slim::Utils::Misc::stillScanning()) {
						$list_form{'song_count'}	= Slim::Music::Info::songCount([$genre],[$artist],['*'],[]);
					}
					$list_form{'genre'}	  = $genre;
					$list_form{'artist'}  = $artist;
					$list_form{'album'}	  = '*';
					$list_form{'song'}	  = $song;
					$list_form{'title'}   = string('ALL_SONGS');
					$list_form{'descend'} = 1;
					$list_form{'player'} =  $player;
					$list_form{'odd'}	  = ($itemnumber + 1) % 2;
					$list_form{'skinOverride'} = $$paramsref{'skinOverride'};
					$itemnumber++;
					$$paramsref{'browse_list'} .= ${Slim::Web::HTTP::filltemplatefile("browseid3_list.html", \%list_form)};
				}
			}
			foreach my $item ( @items[$start..$end]) {
				%list_form=();
				if ($$paramsref{'includeItemStats'} && !Slim::Utils::Misc::stillScanning()) {
					$list_form{'song_count'}	= Slim::Music::Info::songCount([$genre],[$artist],[$item],[]);
				}
				$list_form{'genre'}	  = $genre;
				$list_form{'artist'}  = $artist;
				$list_form{'album'}	  = $item;
				$list_form{'song'}	  = $song;
				$list_form{'title'}   = $item;
				$list_form{'descend'} = $descend;
				$list_form{'player'} = $player;
				$list_form{'odd'}	  = ($itemnumber + 1) % 2;
				$list_form{'skinOverride'} = $$paramsref{'skinOverride'};
				my $anchor = anchor($item,1);
				if ($lastAnchor ne $anchor) {
					$list_form{'anchor'}  = $anchor;
					$lastAnchor = $anchor;
				}
				if ($$paramsref{'artwork'}) {
					my $song = Slim::Music::Info::pathFromAlbum($item);
					if (defined $song) {
						$list_form{'coverthumb'} = 1; 
						$list_form{'thumbartpath'} = $song;
					} else {
						$list_form{'coverthumb'} = 0;
					}
					$list_form{'itempath'} = $item;
					$list_form{'itemnumber'} = $itemnumber;
					$list_form{'artwork'} = 1;
					$list_form{'size'} = Slim::Utils::Prefs::get('thumbSize');
					$itemnumber++;
					$$paramsref{'browse_list'} .= ${Slim::Web::HTTP::filltemplatefile("browseid3_artwork.html", \%list_form)};
				} else {
					$itemnumber++;
					$$paramsref{'browse_list'} .= ${Slim::Web::HTTP::filltemplatefile("browseid3_list.html", \%list_form)};
				}
				::idleStreams();
			}
		}
	} else {
		# Browse by ?
		@items = Slim::Music::Info::songs([$genre], [$artist], [$album], [], ($album eq '*'));
		if (scalar(@items)) {
			my ($start,$end);
			if (defined $paramsref->{'nopagebar'}){
					($start, $end) = simpleheader(scalar(@items),
											\$$paramsref{'start'},
											\$$paramsref{'browselist_header'},
											$$paramsref{'skinOverride'},
											$$paramsref{'itemsPerPage'},
											(scalar(@items) > 1));
			}
			else{
				($start,$end) = pagebar(scalar(@items)
							,$$paramsref{'path'}
							,0
							,$otherparams
							,\$$paramsref{'start'}
							,\$$paramsref{'browselist_header'}
							,\$$paramsref{'browselist_pagebar'}
							,$$paramsref{'skinOverride'}
							,$$paramsref{'itemsPerPage'});
			}
			$descend = undef;
			
			if (scalar(@items) > 1) {
				%list_form=();
				$list_form{'genre'}	  = $genre;
				$list_form{'artist'}  = $artist;
				$list_form{'album'}	  = $album;
				$list_form{'song'}	  = '*';
				$list_form{'descend'} = 'true';
				$list_form{'title'}   = string('ALL_SONGS');
				$list_form{'player'} = $player;
				$list_form{'odd'}	  = ($itemnumber + 1) % 2;
				$list_form{'skinOverride'} = $$paramsref{'skinOverride'};
				$itemnumber++;
				$$paramsref{'browse_list'} .= ${Slim::Web::HTTP::filltemplatefile("browseid3_list.html", \%list_form)};
			}

			foreach my $item ( @items[$start..$end] ) {
				%list_form=();
				my $title = Slim::Music::Info::standardTitle(undef, $item);
				$list_form{'genre'}	  = Slim::Music::Info::genre($item);
				$list_form{'artist'}  = Slim::Music::Info::artist($item);
				$list_form{'album'}	  = Slim::Music::Info::album($item);
				$list_form{'itempath'} = $item; 
				$list_form{'item'} = $item;
				$list_form{'title'}   = $title;
				$list_form{'descend'} = $descend;
				$list_form{'player'} = $player;
				$list_form{'odd'}	  = ($itemnumber + 1) % 2;
				$list_form{'mixable_not_descend'} = Slim::Music::Info::isSongMixable($item);
				$list_form{'skinOverride'} = $$paramsref{'skinOverride'};
			my ($body, $type) =  Slim::Music::Info::coverArt($item);
			if (defined($body)) { $list_form{'coverart'} = 1; $list_form{'coverartpath'} = $item;}
				$itemnumber++;
				$$paramsref{'browse_list'} .= ${Slim::Web::HTTP::filltemplatefile("browseid3_list.html", \%list_form)};
				::idleStreams();
			}
			my ($body, $type) =  Slim::Music::Info::coverArt($items[$start]);
			if (defined($body)) { $$paramsref{'coverart'} = 1; $$paramsref{'coverartpath'} = $items[$start];}
		}
	}
	$$paramsref{'descend'} = $descend;

	return Slim::Web::HTTP::filltemplatefile("browseid3.html", $paramsref);
}

sub mood_wheel {
	my($client, $paramsref) = @_;
	my @items = ();

	my $song = $$paramsref{'song'};
	my $artist = $$paramsref{'artist'};
	my $album = $$paramsref{'album'};
	my $genre = $$paramsref{'genre'};
	my $player = $$paramsref{'player'};
	my $itemnumber = 0;
	
	if (defined $artist && $artist ne "") {
		@items = Slim::Music::MoodLogic::getMoodWheel(Slim::Music::Info::moodLogicArtistId($artist), 'artist');
	} elsif (defined $genre && $genre ne "" && $genre ne "*") {
		@items = Slim::Music::MoodLogic::getMoodWheel(Slim::Music::Info::moodLogicGenreId($genre), 'genre');
	} else {
		$::d_moodlogic && msg('no/unknown type specified for mood wheel');
		return undef;
	}

	$$paramsref{'pwd_list'} = &generate_pwd_list($genre, $artist, $album, $player);
	$$paramsref{'pwd_list'} .= ${Slim::Web::HTTP::filltemplatefile("mood_wheel_pwdlist.html", $paramsref)};

	foreach my $item ( @items ) {
		my %list_form=();
		$list_form{'mood'} = $item;
		$list_form{'genre'} = $genre;
		$list_form{'artist'}  = $artist;
		$list_form{'album'} = $album;
		$list_form{'player'} = $player;
		$list_form{'itempath'} = $item; 
		$list_form{'item'} = $item; 
		$list_form{'odd'} = ($itemnumber + 1) % 2;
		$itemnumber++;
		$$paramsref{'mood_list'} .= ${Slim::Web::HTTP::filltemplatefile("mood_wheel_list.html", \%list_form)};
	}

	return Slim::Web::HTTP::filltemplatefile("mood_wheel.html", $paramsref);
}

sub instant_mix {
	my($client, $paramsref) = @_;
	my $output = "";
	my @items = ();

	my $song = $$paramsref{'song'};
	my $artist = $$paramsref{'artist'};
	my $album = $$paramsref{'album'};
	my $genre = $$paramsref{'genre'};
	my $player = $$paramsref{'player'};
	my $mood = $$paramsref{'mood'};
	my $p0 = $$paramsref{'p0'};
	my $itemnumber = 0;

	$$paramsref{'pwd_list'} = &generate_pwd_list($genre, $artist, $album, $player);
	if (defined $mood && $mood ne "") {
		$$paramsref{'pwd_list'} .= ${Slim::Web::HTTP::filltemplatefile("mood_wheel_pwdlist.html", $paramsref)};
	}

	if (defined $song && $song ne "") {
		$$paramsref{'src_mix'} = Slim::Music::Info::standardTitle(undef, $song);
	} elsif (defined $mood && $mood ne "") {
		$$paramsref{'src_mix'} = $mood;
	}

	$$paramsref{'pwd_list'} .= ${Slim::Web::HTTP::filltemplatefile("instant_mix_pwdlist.html", $paramsref)};

	if (defined $song && $song ne "") {
		@items = Slim::Music::MoodLogic::getMix(Slim::Music::Info::moodLogicSongId($song), undef, 'song');
	} elsif (defined $artist && $artist ne "" && $artist ne "*" && $mood ne "") {
		@items = Slim::Music::MoodLogic::getMix(Slim::Music::Info::moodLogicArtistId($artist), $mood, 'artist');
	} elsif (defined $genre && $genre ne "" && $genre ne "*" && $mood ne "") {
		@items = Slim::Music::MoodLogic::getMix(Slim::Music::Info::moodLogicGenreId($genre), $mood, 'genre');
	} else {
		$::d_moodlogic && msg('no/unknown type specified for instant mix');
		return undef;
	}

	foreach my $item ( @items ) {
		my %list_form=();
		$list_form{'artist'} = $artist;
		$list_form{'album'} = $album;
		$list_form{'genre'} = $genre;
		$list_form{'player'} = $player;
		$list_form{'itempath'} = $item; 
		$list_form{'item'} = $item; 
		$list_form{'title'} = Slim::Music::Info::infoFormat($item, 'TITLE (ARTIST)', 'TITLE');
		$list_form{'odd'} = ($itemnumber + 1) % 2;
		$itemnumber++;
		$$paramsref{'instant_mix_list'} .= ${Slim::Web::HTTP::filltemplatefile("instant_mix_list.html", \%list_form)};
	}

	if (defined $p0) {
		Slim::Control::Command::execute($client, ["playlist", $p0 eq "append" ? "append" : "play", $items[0]]);
		
		for (my $i=1; $i<=$#items; $i++) {
			Slim::Control::Command::execute($client, ["playlist", "append", $items[$i]]);
		}
	}
	return Slim::Web::HTTP::filltemplatefile("instant_mix.html", $paramsref);
}

sub searchStringSplit {
	my $search_string = shift;
	my @strings = ();
	foreach my $ss (split(' ',$search_string)) {
		push @strings, "*" . $ss . "*";
	}
	return \@strings;
}

sub anchor {
	my $item = shift;
	my $suppressArticles = shift;
	
	if ($suppressArticles) {
		my $articles =  Slim::Utils::Prefs::get("ignoredarticles");
		$articles =~ s/\s+/|/g;
		$item =~ s/^($articles)\s+//i;
	}

	return Slim::Music::Info::matchCase(substr($item, 0, 1));
}

sub options {
	#pass in the selected value and a hash of value => text pairs to get the option list filled
	#with the correct option selected.
	my ($selected,$optionref,$skinOverride) = @_;
	my $optionlist = '';
	foreach my $curroption (sort { $optionref->{$a} cmp $optionref->{$b} } keys  %{$optionref}) {
		$optionlist .= ${Slim::Web::HTTP::filltemplatefile("select_option.html",{'selected' => ($curroption eq $selected)
											, 'key' => $curroption
											, 'value' => $optionref->{$curroption}
											, 'skinOverride' => $skinOverride})};
	}
	return $optionlist;
}

#
# Build a simple header 
#

sub simpleheader {
	my $itemcount = shift;
	my $startref = shift; #will be modified
	my $headerref = shift; #will be modified
	my $skinOverride = shift;
	my $count = shift || Slim::Utils::Prefs::get('itemsPerPage');
	my $offset = shift;
	
	my $start = (defined($$startref) && $$startref ne '') ? $$startref : 0;
	if ($start >= $itemcount) { $start = $itemcount - $count; }
	$$startref = $start;
	my $end = $start+$count-1-$offset;
	if ($end >= $itemcount) { $end = $itemcount - 1;}
	$$headerref = ${Slim::Web::HTTP::filltemplatefile("pagebarheader.html", { "start" => ($start), "end" => ($end), "itemcount" => ($itemcount-1), 'skinOverride' => $skinOverride})};
	return ($start,$end);
}


#
# Build a bar of links to multiple pages of items
#
sub pagebar {
	my $itemcount = shift;
	my $path = shift;
	my $currentitem = shift;
	my $otherparams = shift;
	my $startref = shift; #will be modified
	my $headerref = shift; #will be modified
	my $pagebarref = shift; #will be modified
	my $skinOverride = shift;
	my $count = shift || Slim::Utils::Prefs::get('itemsPerPage');

	my $start = (defined($$startref) && $$startref ne '') ? $$startref : (int($currentitem/$count)*$count);
	if ($start >= $itemcount) { $start = $itemcount - $count; }
	$$startref = $start;
	my $end = $start+$count-1;
	if ($end >= $itemcount) { $end = $itemcount - 1;}
	if ($itemcount > $count) {
		$$headerref = ${Slim::Web::HTTP::filltemplatefile("pagebarheader.html", { "start" => ($start+1), "end" => ($end+1), "itemcount" => $itemcount, 'skinOverride' => $skinOverride})};

		my %pagebar = ();

		my $numpages = ceil($itemcount/$count);
		my $curpage = int($start/$count);
		my $pagesperbar = 10; #make this a preference
		my $pagebarstart = (($curpage - int($pagesperbar/2)) < 0 || $numpages <= $pagesperbar) ? 0 : ($curpage - int($pagesperbar/2));
		my $pagebarend = ($pagebarstart + $pagesperbar) > $numpages ? $numpages : ($pagebarstart + $pagesperbar);

		$pagebar{'pagesstart'} = ($pagebarstart > 0);

		if ($pagebar{'pagesstart'}) {
			$pagebar{'pagesprev'} = ($curpage - $pagesperbar) * $count;
			if ($pagebar{'pagesprev'} < 0) { $pagebar{'pagesprev'} = 0; };
		}

		if ($pagebarend < $numpages) {
			$pagebar{'pagesend'} = ($numpages -1) * $count;
			$pagebar{'pagesnext'} = ($curpage + $pagesperbar) * $count;
			if ($pagebar{'pagesnext'} > $pagebar{'pagesend'}) { $pagebar{'pagesnext'} = $pagebar{'pagesend'}; }
		}

		$pagebar{'pageprev'} = $curpage > 0 ? (($curpage - 1) * $count) : undef;
		$pagebar{'pagenext'} = ($curpage < ($numpages - 1)) ? (($curpage + 1) * $count) : undef;
		$pagebar{'otherparams'} = defined($otherparams) ? $otherparams : '';
		$pagebar{'skinOverride'} = $skinOverride;
		$pagebar{'path'} = $path;

		for (my $j = $pagebarstart;$j < $pagebarend;$j++) {
			$pagebar{'pageslist'} .= ${Slim::Web::HTTP::filltemplatefile('pagebarlist.html'
							,{'currpage' => ($j == $curpage)
							,'itemnum0' => ($j * $count)
							,'itemnum1' => (($j * $count) + 1)
							,'pagenum' => ($j + 1)
							,'otherparams' => $otherparams
							,'skinOverride' => $skinOverride
							,'path' => $path})};
		}
		$$pagebarref = ${Slim::Web::HTTP::filltemplatefile("pagebar.html", \%pagebar)};
	}
	return ($start,$end);
}

sub alphapagebar {
	my $itemsref = shift;
	my $path = shift;
	my $otherparams = shift;
	my $startref = shift; #will be modified
	my $pagebarref = shift; #will be modified
	my $ignorearticles = shift;
	my $skinOverride = shift;
	my $maxcount = shift || Slim::Utils::Prefs::get('itemsPerPage');
	my $itemcount = scalar(@$itemsref);
	my $start = $$startref;
	if (!$start) { 
		$start = 0;
	}
	
	if ($start >= $itemcount) { 
		$start = $itemcount - $maxcount; 
	}
	
	$$startref = $start;
	
	my $end = $itemcount-1;
	if ($itemcount > $maxcount/2) {

		my %pagebar_params = ();
		if (!defined($otherparams)) {
			$otherparams = '';
		}
		$pagebar_params{'otherparams'} =  $otherparams;
		
		my $lastLetter = '';
		my $lastLetterIndex = 0;
		my $pageslist = '';
		$end = -1;
		for (my $j = 0; $j < $itemcount; $j++) {

			my $curLetter = anchor($$itemsref[$j], $ignorearticles);

			if ($lastLetter ne $curLetter) {

				if (($j - $lastLetterIndex) > $maxcount) {
					if ($end == -1 && $j > $start) {
						$end = $j - 1;
					}
					$lastLetterIndex = $j;
				}
				$pageslist .= ${Slim::Web::HTTP::filltemplatefile('alphapagebarlist.html'
								,{'currpage' => ($lastLetterIndex == $start)
								,'itemnum0' => $lastLetterIndex
								,'itemnum1' => ($lastLetterIndex + 1)
								,'pagenum' => $curLetter
								,'fragment' => ("#" . $curLetter)
								,'otherparams' => $otherparams
								,'skinOverride' => $skinOverride
								,'path' => $path})};
				
				$lastLetter = $curLetter;
			}
		}
		
		if ($end == -1) {
			$end = $itemcount - 1;
		}

		$pagebar_params{'pageslist'} = $pageslist;
		$pagebar_params{'skinOverride'} = $skinOverride;
		$$pagebarref = ${Slim::Web::HTTP::filltemplatefile("pagebar.html", \%pagebar_params)};
	}
	
	return ($start,$end);
}

sub firmware {
	my($client, $paramsref) = @_;
	return Slim::Web::HTTP::filltemplatefile("firmware.html", $paramsref);
}

sub update_firmware {
	my($client, $paramsref) = @_;
	my $result;
	$result = Slim::Player::Squeezebox::upgradeFirmware($paramsref->{'ipaddress'});
	$$paramsref{'warning'} = $result || string('UPGRADE_COMPLETE_DETAILS');
	
	return Slim::Web::HTTP::filltemplatefile("update_firmware.html", $paramsref);
}
