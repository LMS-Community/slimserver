package Slim::Utils::Scan;
          
# $Id: Scan.pm,v 1.8 2004/04/28 13:10:54 kdf Exp $

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.  

#
# Scans a directory in the background, adding the contents to the specified list
#

#
#          addToList(path)
#               |
#               |		   
#          single file? [Y]----> add it ---> done
#              [N]
#               |
#               |
#          push this directory onto stack
#               |
#               |
#          is the stack empty? <-------------------------------<------------------------ 
#              [N]	[Y]											|                       |
#               |	  ->done									|                       |
#               |												|                       |
#          read the contents of the directory					|                       |
#               |                    	         				|                       |
#               |                             					|                       |
#    --->  have we done all items in this dir? [Y] ---> Sort these items, add then      |
#    |          [N]                                      to the main list, then         |
#    |           |                                       pop this dir from the stack    |
#    |           |                                                                      |
#    |      is this item a directory? [Y] --------> push this dir onto stack ------------
#    |          [N]
#    |           |
#    |           |
#    |      is this item a file? [N]  ---> unkown type; skip ---->
#    |          [Y]                                              |
#    |           |                                               |
#    |           |                                               |
#    |      look up ID3 track/tag for sort key                   |
#    |      and push this onto the list of items                 |
#    |      we found in this dir                                 |
#    |           |                                               |
#    |           |                                               |
#     <--- increment index <-------------------------------------

use strict;
use File::Spec::Functions qw(:ALL);
use FileHandle;
use IO::Socket qw(:DEFAULT :crlf);
use Class::Struct;        

        
use Slim::Display::Display;
use Slim::Utils::Misc;
use Slim::Formats::Parse;
use Slim::Web::RemoteStream;                

#my $::d_scan=1;  # scan debugging

struct (addToList_dirState => [
	path	    => '$', # path to this dir
	contents    => '@', # list of items in this dir
	numcontents => '$',
	index       => '$', # our position on contents[]
	itemsToAdd  => '@', # individual tracks we've found in the current directory
]);

struct (addToList_jobState => [
	stack          => '@', # each level in the hierarchy
	recursive      => '$', # do we descend directories
	sorted		   => '$', # 1 = return the entries in sorted order
	numstack       => '$', # number of levels on the stack
    numitems       => '$', # number of items currently in the list
    numitems_start => '$', # number of items in the list before addToList
	playlisturl	   => '$', # initial value of playlist URL

	callbackf      => '$', #function to call when we're done
	callbackargs   => '$', #ref to array of callback args
]);

my %addToList_jobs = ();    # each job is referenced by its listref.

# addToList - Add directory contents to a list, in the background
#
sub addToList {
	my($listref, 		# reference to the list which we're to append
	   $playlisturl, 	# a file, directory, or URL to be scanned
	   $recursive, 		# 1 = scan all subdirectories recursively
	   $sorted,			# 1 = return the entries in sorted order
	   $callbackf,		# Optional: function to call when finished
	   @callbackargs	# Optional: callback args - number of items scanned will be appended.
	) = @_;
	
	$::d_scan && msg("Scan::addToList: $playlisturl\n");

	$recursive = 1 if (!defined($recursive));
	$callbackf = 0 if (!defined($callbackf));

	$playlisturl = Slim::Utils::Misc::fixPath($playlisturl);

	if (!defined($sorted)) {
		if (Slim::Music::Info::isPlaylist($playlisturl)) { 
			$sorted = 0;
		} else {
			$sorted = 1;
		}
	}
	 	
	if (Slim::Music::Info::isWinShortcut($playlisturl)) {
		$playlisturl = Slim::Utils::Misc::pathFromWinShortcut($playlisturl);
	}
	
	# special case, if we try to add a song, then just add it
	if (Slim::Music::Info::isSong($playlisturl)) {
		push @$listref, $playlisturl;
		$callbackf && (&$callbackf(@callbackargs, 1));
	} elsif (Slim::Music::Info::isPlaylist($playlisturl) && !$sorted) {
		# regular playlists (m3u, pls, itu, cue) are parsed and loaded immediately and we never recurse and never sort
		my $count = readList($playlisturl, $listref, 0);
		$callbackf && (&$callbackf(@callbackargs, $count));
	} else {	
		# Initialize the base directory, with index == -1 to indicate 
		# that we haven't read the dir yet
		my $basedir = addToList_dirState -> new();
		$basedir->path($playlisturl);
		$basedir->numcontents(0);
		$basedir->index(-1);
	
		# Initialize the stack to one level, the basedir
	
		$addToList_jobs{$listref} = addToList_jobState -> new();
		$addToList_jobs{$listref}->recursive($recursive);
		$addToList_jobs{$listref}->sorted($sorted);
		$addToList_jobs{$listref}->stack(0, $basedir);
		$addToList_jobs{$listref}->numstack(1);
		$addToList_jobs{$listref}->numitems(0);
		$addToList_jobs{$listref}->callbackf($callbackf);
		$addToList_jobs{$listref}->callbackargs(\@callbackargs);
		$addToList_jobs{$listref}->playlisturl($playlisturl);
		
		# if we have a callback function, then schedule it if appropriate
		
		if ($callbackf) {
			# Run the task once.  If it still needs to go, set it running! 
			# The task is referenced by its $listref
			if (addToList_run($listref)) {
				Slim::Utils::Scheduler::add_task(\&addToList_run, $listref);
			}
		} else {
		# without a callback function, we block until it's done.
			while (addToList_run($listref)) {};
		}
	}
}

sub stopAddToList {
	my $listref = shift;
	Slim::Utils::Scheduler::remove_task(\&addToList_run, $listref);
	&addToList_done($listref);
	$addToList_jobs{$listref} = undef;
}	

#
# called by the scheduler to incrementally build the list
#

sub addToList_run {
	my $listref = shift;

	my $jobState = $addToList_jobs{$listref};
	my $stackRef = $jobState->stack;
	my $curdirState = @$stackRef[$jobState->numstack-1]; # The directory we're currently in is stack[numstack-1]
	$::d_scan && msg("numitems: ".$jobState->numitems."\n");
	if (!$curdirState) {
		$::d_scan && msg("couldn't find curdirstate in addToList_run");
		&addToList_done($listref);
		return 0;
	}
########## index==-1 means we need to read the directory

	$::d_scan && msg("index: ".$curdirState->index."\n");
	if ($curdirState->index == -1) {
		# check to see if it's a list.  assume it's a list if it's our initial path
		if (Slim::Music::Info::isList($curdirState->path) || ($jobState->playlisturl eq $curdirState->path)) {
			my $contentsref = $curdirState->contents;
			@$contentsref=();
			my $numcontents = readList($curdirState->path, $contentsref, $jobState->sorted);
			$curdirState->index(0);
			$curdirState->numcontents($numcontents);
			if (Slim::Music::Info::isWinShortcut($curdirState->path) && 
					Slim::Music::Info::isDir(@{Slim::Music::Info::cachedPlaylist($curdirState->path)})) {
				$curdirState->path(@{Slim::Music::Info::cachedPlaylist($curdirState->path)});
			}
			my $itemsToAddref = $curdirState->itemsToAdd;
			@$itemsToAddref=();
			$::d_scan && msg("Descending into ".$curdirState->path.", contains ".$curdirState->numcontents." items\n");
			return 1;
		} else {
			# special case - single item at the top
			$::d_scan && msg("special case - single item at top: $curdirState->path\n");
			push @$listref, $curdirState->path();
			&addToList_done($listref);
			return 0;
		}
	}
	
########## OK, the directory has been opened, and index points to the entry we should look at

	my $item = '';

	if (defined($curdirState->numcontents) && $curdirState->index == $curdirState->numcontents) {
		### todo: move sorting out of scan.pm
		#### we've made it to the end of this directory. 
		#### Sort it, append it to the big list, and then pop it from the stack
		#### if the stack is now empty, we're done!

		my $itemstoaddref = $curdirState->itemsToAdd;

		if ($jobState->sorted)  {
			$::d_scan && msg("Beginning scan sort...\n");
			if (Slim::Utils::Prefs::get('filesort')) {
				push @$listref, (Slim::Music::Info::sortFilename(@{$itemstoaddref}));
			} else {
				# if there are duplicate track numbers, then sort as multiple albums
				my $duptracknum = 0;
				my @seen = ();
				foreach my $item (@{$itemstoaddref}) {
					my $trnum = Slim::Music::Info::trackNumber($item);
					if ($trnum) { 
						if ($seen[$trnum]) {
							$duptracknum = 1;
							last;
						}
						$seen[$trnum]++;
					}
				}
				
				if ($duptracknum) {
					push @$listref, (Slim::Music::Info::sortByTrack(@{$itemstoaddref}));
				} else {
					push @$listref, (Slim::Music::Info::sortByAlbum(@{$itemstoaddref}));
				}
			}
			$::d_scan && msg("...sort done.\n");
		} else {
			push @$listref, @$itemstoaddref;		
		}
		
		$jobState->numstack($jobState->numstack - 1);

		if ($jobState->numstack) {
			$::d_scan && msg("Got to end of dir, ascending...\n");
			return 1;
		} else {
			$::d_scan && msg("Got to end of dir, done!\n");
			&addToList_done($listref);
			return 0;
		}
	}

######## Go to the next item:

	$item = $curdirState->contents($curdirState->index);
	$curdirState->index($curdirState->index + 1);

	my $itempath = Slim::Utils::Misc::fixPath($item, $curdirState->path);
	$::d_scan && msg("itempath: $item and " .  $curdirState->path . " made $itempath\n");

######### If it's a directory or playlist and we're recursing, push it onto the stack, othwerwise add it to the list

	$::d_scan && msg("isList(".$itempath.") == ".Slim::Music::Info::isList($itempath)."\n");

	# todo: don't let us recurse indefinitely
	if (Slim::Music::Info::isList($itempath)) {
		# if we're recursing and it's a remote playlist, then recurse
		if ($jobState->recursive && !Slim::Music::Info::isHTTPURL($itempath)) {
			# don't recurse into playlists, only into directories	
			if (Slim::Music::Info::isPlaylist($itempath) && !Slim::Music::Info::isCUE($itempath) && !Slim::Utils::Misc::inPlaylistFolder($itempath)) { 
				return 1;
			}
			my $newdir =  addToList_dirState -> new();
			$newdir->path($itempath);
			$newdir->index(-1);		

			$jobState->stack($jobState->numstack, $newdir);
			$jobState->numstack($jobState->numstack + 1);
			return 1;
		} else {
			my $arrayref = $curdirState->itemsToAdd;
			push @$arrayref, $itempath;
			$jobState->numitems($jobState->numitems+1);
			return 1;
		}
	}

######### Else if it's a single item - look up the sort key (takes a while)
	$::d_scan && msg("not a list: $itempath\n");
	if (Slim::Music::Info::isSong($itempath)) {
		$::d_scan && msg("adding single item: $itempath, type " . Slim::Music::Info::contentType($itempath) . "\n");
		my $arrayref = $curdirState->itemsToAdd;
		push @$arrayref, $itempath;
		$jobState->numitems($jobState->numitems+1);
		
#	force the loading of ID3 data
		Slim::Music::Info::title($itempath);
				
		return 1;
	}

######## Else we don't know what it is

	$::d_scan && msg("Skipping unknown type: $itempath\n");
	return 1;
}

sub addToList_done {
	my($listref) = @_;
	
	my $jobState = $addToList_jobs{$listref};
	my $callbackf = $jobState->callbackf;
	my $callbackargs = $jobState->callbackargs;
	
	if ($::d_scan) {
		msg("addToList_done. returning ".$jobState->numitems." items\n");
		my @list = @$listref;
		my $item;

		foreach $item (@list) {
			msg("  $item\n");
		}
	}

	$callbackf && (&$callbackf(@$callbackargs, $jobState->numitems));
}

sub readList {   # reads a directory or playlist and returns the contents as an array
	my($playlisturl, $listref, $sorted) = @_;

	$::d_scan && msg("Scan::readList gonna read $playlisturl\n");

	my ($playlist_filehandle, $playlistpath, $numitems);
	
	$numitems = 0;
	my $startingsize = scalar @$listref;

	if (Slim::Music::Info::isHTTPURL($playlisturl)) {
		$::d_scan && msg("Scan::readList opening remote stream $playlisturl\n");
		$playlist_filehandle = Slim::Web::RemoteStream::openRemoteStream($playlisturl);

		unless ($playlist_filehandle) {
			warn "cannot connect to http daemon to get playlist";
			return 0;
		}
	  
	} else {

		# it's pointing to a local file...

		if (Slim::Music::Info::isWinShortcut($playlisturl)) {
			if (defined Slim::Music::Info::cachedPlaylist($playlisturl)) {
				$playlistpath = ${Slim::Music::Info::cachedPlaylist($playlisturl)}[0];
			} else {
				$playlistpath = Slim::Utils::Misc::pathFromWinShortcut($playlisturl);
				Slim::Music::Info::cachePlaylist($playlisturl, [$playlistpath]);
			}
			if ($playlistpath eq "") {
				return 0;
			}
			$playlistpath=Slim::Utils::Misc::fileURLFromPath($playlistpath);
			if (Slim::Music::Info::isSong($playlistpath) || Slim::Music::Info::isWinShortcut($playlistpath)) {
				push @$listref , $playlistpath;
				return 1;
			}
		} else {
			$playlistpath = $playlisturl;
		}
		
		$playlistpath = Slim::Utils::Misc::fixPath($playlistpath);
		
		$::d_scan && msg("Gonna try to open playlist $playlistpath\n");
		if ($playlistpath =~ /\.\.[\/\\]/) {
			# bogus path containing .. is illegal
			$::d_scan && msg("Ignoring playlist name with .. in it: $playlistpath\n");
			return 0;
		}

		if (Slim::Music::Info::isITunesPlaylistURL($playlistpath) || Slim::Music::Info::isMoodLogicPlaylistURL($playlistpath) ||
			(defined Slim::Music::Info::cachedPlaylist($playlistpath) && 
			(Slim::Music::Info::isDir($playlistpath) && (((stat(Slim::Utils::Misc::pathFromFileURL($playlistpath)))[9]) == Slim::Music::Info::age($playlistpath))))
			) {
			
			$::d_scan && msg("*** found a current entry for $playlisturl in playlist cache ***\n");
			my $cacheentryref = Slim::Music::Info::cachedPlaylist( $playlistpath );
			if ($cacheentryref) {
				$numitems = (push @$listref, @{$cacheentryref}) - $startingsize;
			} else {
				$numitems = 0;
			}
			
		} elsif (Slim::Music::Info::isDir($playlistpath)) {
			$::d_scan && msg("*** didn't find $playlistpath in playlist cache ***\n");
			$::d_scan && msg("Treating directory like a playlist\n");
			my @dircontents;
			$numitems = 0;
			@dircontents = Slim::Utils::Misc::readDirectory(Slim::Utils::Misc::pathFromFileURL($playlistpath));

			foreach my $dir ( @dircontents ) {

				my $itempath = Slim::Utils::Misc::fileURLFromPath(catfile(Slim::Utils::Misc::pathFromFileURL($playlistpath), $dir));

				$::d_scan && msg(" directory entry: $itempath\n");

				push @$listref, $dir;
				$numitems++;
			}
			# add the loaded dir to the cache...
			if ($numitems) {
				my @cachelist = @$listref[ (0 - $numitems) .. -1];
				Slim::Music::Info::cachePlaylist($playlistpath, \@cachelist, (stat(Slim::Utils::Misc::pathFromFileURL($playlistpath)))[9]);	
				$::d_scan && msg("adding $numitems to playlist cache: $playlistpath\n"); 
			}
		} else {
			# it's a playlist file
			$playlist_filehandle = new FileHandle;
			if (!open($playlist_filehandle, Slim::Utils::Misc::pathFromFileURL($playlistpath))) {
				$::d_scan && msg("Couldn't open playlist file $playlistpath : $!");
				$playlist_filehandle = undef;
			}
		}
	}
	
	if ($playlist_filehandle) {
		$::d_scan && msg("Scan::readList loading $playlisturl\n");
		$numitems = (push @$listref, Slim::Formats::Parse::parseList($playlisturl,$playlist_filehandle, (splitpath(Slim::Utils::Misc::pathFromFileURL($playlisturl)))[0] . (splitpath(Slim::Utils::Misc::pathFromFileURL($playlisturl)))[1])) - $startingsize;
		$::d_scan && msg("Scan::readList loaded playlist with $numitems items\n");
	}
	
	return $numitems
}

1;

