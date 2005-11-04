package Slim::Utils::Scan;
          
# $Id$

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
#              [N]	[Y]                                         |                       |
#               |         ->done                                |                       |
#               |                                               |                       |
#          read the contents of the directory                   |                       |
#               |                    	                        |                       |
#               |                                               |                       |
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
use Class::Struct;
use File::Basename;
use File::Spec::Functions qw(:ALL);
use FileHandle;
use IO::String;
use Path::Class;
use Scalar::Util qw(blessed);
use Time::HiRes;

use Slim::Music::Info;
use Slim::Utils::Misc;
use Slim::Formats::Parse;

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
	my $args = shift;

	# reference to the list which we're to append
	my $listref      = $args->{'listRef'} || [];

	# a file, directory, or URL to be scanned
	my $playlisturl  = $args->{'url'};

	# 1 = scan all subdirectories recursively
	my $recursive    = $args->{'recursive'};

	# Optional: function to call when finished
	my $callbackf    = $args->{'callback'};

	# Optional: callback args - number of items scanned will be appended.
	my $callbackArgs = $args->{'callbackArgs'} || [];

	$::d_scan && msg("Scan::addToList: $playlisturl\n");

	$recursive = 1 if (!defined($recursive));
	$callbackf = 0 if (!defined($callbackf));

	$playlisturl = Slim::Utils::Misc::fixPath($playlisturl);

	if (Slim::Music::Info::isWinShortcut($playlisturl)) {
		$playlisturl = Slim::Utils::Misc::pathFromWinShortcut($playlisturl);
	}

	# special case, if we try to add a song, then just add it
	if (Slim::Music::Info::isSong($playlisturl)) {

		push @$listref, $playlisturl;
		$callbackf && (&$callbackf(@{$callbackArgs}, 1));

	} elsif (Slim::Music::Info::isPlaylist($playlisturl)) {

		# regular playlists (m3u, pls, itu, cue) are parsed and loaded immediately and we never recurse and never sort
		my $count = readList($playlisturl, $listref);

		$callbackf && (&$callbackf(@{$callbackArgs}, $count));

	} else {	
		# Initialize the base directory, with index == -1 to indicate 
		# that we haven't read the dir yet
		my $basedir = addToList_dirState->new();

		$basedir->path($playlisturl);
		$basedir->numcontents(0);
		$basedir->index(-1);
	
		# Initialize the stack to one level, the basedir
		$addToList_jobs{$listref} = addToList_jobState->new();
		$addToList_jobs{$listref}->recursive($recursive);
		$addToList_jobs{$listref}->stack(0, $basedir);
		$addToList_jobs{$listref}->numstack(1);
		$addToList_jobs{$listref}->numitems(0);
		$addToList_jobs{$listref}->callbackf($callbackf);
		$addToList_jobs{$listref}->callbackargs($callbackArgs);
		$addToList_jobs{$listref}->playlisturl($playlisturl);
		
		# if we have a callback function, then schedule it if appropriate
		
		if ($callbackf) {
			# Run the task once.  If it still needs to go, set it running! 
			# The task is referenced by its $listref
			if (addToList_run($listref)) {
				Slim::Utils::Scheduler::add_task(\&addToList_run, $listref);
			}

			return;
		}

		# without a callback function, we block until it's done.
		while (addToList_run($listref)) {};
	}
}

sub stopAddToList {
	my $listref = shift;
	Slim::Utils::Scheduler::remove_task(\&addToList_run, $listref);

	addToList_done($listref);

	$addToList_jobs{$listref} = undef;
	delete $addToList_jobs{$listref};
}	

#
# called by the scheduler to incrementally build the list
#

sub addToList_run {
	my $listref = shift;

	my $jobState = $addToList_jobs{$listref};
	my $stackRef = $jobState->stack;
	my $ds       = Slim::Music::Info::getCurrentDataStore();

	# The directory we're currently in is stack[numstack-1]
	my $curdirState = @$stackRef[$jobState->numstack-1];

	$::d_scan && msgf("numitems: %d\n", $jobState->numitems);

	if (!$curdirState) {
		$::d_scan && msg("couldn't find curdirstate in addToList_run");
		&addToList_done($listref);
		return 0;
	}

	my $item = '';
	my $itempath;

	########## index==-1 means we need to read the directory

	$::d_scan && msgf("index: %d\n", $curdirState->index);

	if ($curdirState->index == -1) {

		# check to see if it's a list.  assume it's a list if it's our initial path
		if (Slim::Music::Info::isList($curdirState->path) || ($jobState->playlisturl eq $curdirState->path)) {

			my $contentsref = $curdirState->contents;

			@$contentsref = ();

			my $numcontents = readList($curdirState->path, $contentsref);

			$curdirState->index(0);
			$curdirState->numcontents($numcontents);

			# $numcontents can be set to undef if it's a bogus windows shortcut.
			# 0 is a valid value for an empty playlist.
			# 
			# So return 1 and continue scanning.
			unless (defined $numcontents) {

				$::d_scan && msgf("numcontents was 0 for path: %s - ascending.\n", $curdirState->path);

				$jobState->numstack($jobState->numstack - 1);

				if ($jobState->numstack) {
					return 1;
				} else {
					addToList_done($listref);
					return 0;
				}
			}

			my $itemsToAddref  = $curdirState->itemsToAdd;
			my $cachedPlaylist = Slim::Music::Info::cachedPlaylist($curdirState->path);

			if (Slim::Music::Info::isWinShortcut($curdirState->path) && Slim::Music::Info::isDir(@{$cachedPlaylist})) {

				$curdirState->path(@{$cachedPlaylist});
			}

			# Special case if we're not recursing.
			# Just iterate through the list and confirm that it's
			# a known type. We then return immediately if not
			# sorting. Note that this path will NOT create new
			# entries in the database - it's up to the calling
			# code to do the right thing.
			elsif (!$jobState->recursive) { 

				my @list = ();

				# Iterate through the list looking for
				# items with known types.
				for $item (@$contentsref) {
					next if ($item =~ /^\s+$/);
					$itempath = Slim::Utils::Misc::fixPath($item, $curdirState->path);
					if (Slim::Music::Info::isList($itempath) ||
					    Slim::Music::Info::isSong($itempath)) {
						push @list, $itempath;
						$jobState->numitems($jobState->numitems+1);
					}
				}

				$jobState->numstack($jobState->numstack - 1);

				@list = (Slim::Music::Info::sortFilename(@list));

				$curdirState->index($numcontents);

				if ($jobState->numstack) {
					push @$itemsToAddref, @list;
					return 1;
				} else {
					push @$listref, @list;
					addToList_done($listref);
					return 0;
				}
			}

			@$itemsToAddref = ();

			$::d_scan && msg("Descending into ".$curdirState->path.", contains ".$curdirState->numcontents." items\n");

			return 1;
		}

		# special case - single item at the top
		$::d_scan && msg("special case - single item at top: " . $curdirState->path . "\n");

		push @$listref, $curdirState->path();

		addToList_done($listref);

		return 0;
	}
	
	########## OK, the directory has been opened, and index points to the entry we should look at

	if (defined($curdirState->numcontents) && $curdirState->index == $curdirState->numcontents) {

		### todo: move sorting out of scan.pm
		#### we've made it to the end of this directory. 
		#### Sort it, append it to the big list, and then pop it from the stack
		#### if the stack is now empty, we're done!

		my $itemstoaddref = $curdirState->itemsToAdd;

		$::d_scan && msg("Beginning scan sort...\n");

		push @$listref, (Slim::Music::Info::sortFilename(@{$itemstoaddref}));

		$::d_scan && msg("...sort done.\n");

		$jobState->numstack($jobState->numstack - 1);

		if ($jobState->numstack) {
			$::d_scan && msg("Got to end of dir, ascending...\n");
			return 1;
		} else {
			$::d_scan && msg("Got to end of dir, done!\n");
			addToList_done($listref);
			return 0;
		}
	}

	######## Go to the next item:

	$item = $curdirState->contents($curdirState->index);
	$curdirState->index($curdirState->index + 1);

	# if $item is all spaces, that means we just get the path again
	# so break this loop.
	if ($item =~ /^\s+$/) {
		return 1;
	}

	$itempath = Slim::Utils::Misc::fixPath($item, $curdirState->path);

	$::d_scan && msg("itempath: $item and " . $curdirState->path . " made $itempath\n");

	######### If it's a directory or playlist and we're recursing, push it onto the stack, othwerwise add it to the list

	$::d_scan && msg("isList($itempath) == ". (Slim::Music::Info::isList($itempath) || 0) . "\n");

	# todo: don't let us recurse indefinitely
	if (Slim::Music::Info::isList($itempath)) {

		if ($jobState->recursive && !Slim::Music::Info::isRemoteURL($itempath)) {

			my $newdir = addToList_dirState->new();
			$newdir->path($itempath);
			$newdir->index(-1);		

			$jobState->stack($jobState->numstack, $newdir);
			$jobState->numstack($jobState->numstack + 1);
			return 1;
		}

		my $arrayref = $curdirState->itemsToAdd;
		push @$arrayref, $itempath;
		$jobState->numitems($jobState->numitems+1);

		return 1;
	}

	######### Else if it's a single item - look up the sort key (takes a while)
	$::d_scan && msg("not a list: $itempath\n");

	if (Slim::Music::Info::isSong($itempath)) {

		$::d_scan && msg("adding single item: $itempath, type " . Slim::Music::Info::contentType($itempath) . "\n");

		my $arrayref = $curdirState->itemsToAdd;
		push @$arrayref, $itempath;
		$jobState->numitems($jobState->numitems+1);
		
		# force the loading of tag data. the 3rd argument to
		# objectForUrl tells it to read the tags.
		my $ds = Slim::Music::Info::getCurrentDataStore();
		my $track = $ds->objectForUrl($itempath, 1, 1);

		$ds->markEntryAsValid($itempath);

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

		msgf("addToList_done. returning %d items\n", $jobState->numitems);

		for my $item (@$listref) {
			msg("  $item\n");
		}
	}

	$callbackf && (&$callbackf(@$callbackargs, $jobState->numitems));
}

sub readList {   # reads a directory or playlist and returns the contents as an array
	my ($playlisturl, $listref) = @_;

	$::d_scan && msg("Scan::readList gonna read $playlisturl\n");

	my ($playlist_filehandle, $numitems);
	
	$numitems = 0;
	my $startingsize = scalar @$listref;
	my $ds = Slim::Music::Info::getCurrentDataStore();

	my $playlistpath = $playlisturl;
	
	if (Slim::Music::Info::isRemoteURL($playlisturl)) {
		$::d_scan && msg("Scan::readList opening remote stream $playlisturl\n");
		$playlist_filehandle = Slim::Player::Source::openRemoteStream($playlisturl);

		unless ($playlist_filehandle) {
			warn "cannot connect to http daemon to get playlist";
			return 0;
		}

		# Check if it's still a playlist after we open the
		# remote stream. We may have got a different content
		# type while loading.
		if (Slim::Music::Info::isSong($playlisturl)) {

			$::d_scan && msg("Scan::readList found that $playlisturl is a song\n");

			$numitems = (push @$listref, $playlisturl) - $startingsize;

			$playlist_filehandle->close if defined($playlist_filehandle);

			$playlist_filehandle = undef;
		}

	} else {

		# it's pointing to a local file...
		if (Slim::Music::Info::isWinShortcut($playlisturl)) {

			$playlistpath = Slim::Utils::Misc::fileURLFromWinShortcut($playlisturl) || return 0;

			# Bug: 2485:
			#
			# Use Path::Class to determine if the $playlistpath
			# points to a directory above $playlisturl - if so,
			# that's a loop and we need to break it.
			if (dir($playlistpath)->subsumes(dir($playlisturl))) {

				errorMsg("Found an infinite loop! Breaking out: $playlisturl -> $playlistpath\n");

				return 0;
			}

			if (Slim::Music::Info::isSong($playlistpath) || Slim::Music::Info::isWinShortcut($playlistpath)) {
				push @$listref , $playlistpath;
				return 1;
			}
		}

		$playlistpath = Slim::Utils::Misc::fixPath($playlistpath);
		
		$::d_scan && msg("Gonna try to open playlist $playlistpath\n");

		if ($playlistpath =~ /\.\.[\/\\]/) {
			# bogus path containing .. is illegal
			$::d_scan && msg("Ignoring playlist name with .. in it: $playlistpath\n");
			return 0;
		}

		# only do this stat once.
		my $playlistpathpath;
		my $playlistpathAge;

		if (Slim::Music::Info::isFileURL($playlistpath)) {
			$playlistpathpath = Slim::Utils::Misc::pathFromFileURL($playlistpath);
			$playlistpathAge = (stat($playlistpathpath))[9];
		}

		# 315529200 is a bogus windows time value
		my $obj = $ds->objectForUrl($playlistpath, 0);
		my $pls = Slim::Music::Info::cachedPlaylist($obj);

		if (Slim::Music::Info::isPlaylistURL($playlistpath) ||
			(
				defined $pls && 
			  	(Slim::Music::Info::isDir($playlistpath) && 
			  	($playlistpathAge == $obj->timestamp())) &&
			  	($playlistpathAge != 315529200)
			  )
			) {
			
			$::d_scan && msg("*** found a current entry for $playlisturl in playlist cache ***\n");

			if ($pls) {

				for my $entry (@$pls) {

					push @$listref, $entry;
				}

				$numitems = (scalar @$listref) - $startingsize;

			} else {

				$numitems = 0;
			}
			
		} elsif (Slim::Music::Info::isDir($playlistpath)) {

			$::d_scan && msg("*** didn't find $playlistpath in playlist cache ***\n");
			$::d_scan && msg("Treating directory like a playlist\n");

			$numitems = 0;

			my @dircontents = Slim::Utils::Misc::readDirectory($playlistpathpath);

			for my $item (@dircontents) {

				my $url = Slim::Utils::Misc::fileURLFromPath(catfile($playlistpathpath, $item));

				$::d_scan && msg(" directory entry: $url\n");

				push @$listref, $ds->objectForUrl($url, 1);

				$numitems++;
			}

			# add the loaded dir to the cache...
			if ($numitems) {

				my @cachelist = @$listref[ (0 - $numitems) .. -1];

				#Slim::Music::Info::cacheDirectory($playlistpath, \@cachelist, $playlistpathAge);

				$::d_scan && msg("adding $numitems to playlist cache: $playlistpath\n"); 
			}

		} elsif (Slim::Music::Info::isContainer($playlistpath)) {

			# read the items inside the container
			# first, let's see if we can grab this from the existing cache
			my $find = {'url', $playlistpath . "#*" };

			my @cachedtracks = $ds->find({
				'field' => 'url',
				'find'  => $find,
			});

			$::d_scan && msg("*** found " . @cachedtracks . " cached entries for $playlisturl ***\n");

			if (!@cachedtracks) {
				#TODO: rescan container if it's not type 'cur'
				$::d_scan && msg("*** scanning container $playlisturl to get contents ***\n");

			}
			
			for my $track (@cachedtracks) {
				push @$listref, $track;
				$numitems++;
			}

			# Add contained tracks as if they were playlist entries
			# This allows them to be read in Browse Music Folder
			# but we can still avoid showing up in Browse Playlists
			# as long as we don't add playlist:// urls
			if ($numitems && scalar @$listref) {

				# Create a playlist container
				my $title = Slim::Music::Info::plainTitle($playlisturl);
				$title =~ s/\.\w{3,4}$//;

				my $ct    = Slim::Music::Info::contentType($playlisturl);

				Slim::Music::Info::updateCacheEntry($playlisturl, {
					'TITLE' => $title,
					'CT'    => $ct,
					'LIST'  => $listref,
				});
			}

		# Bug 1701 - Don't add playlist files when we've pressed
		# 'Play' in BMF, if the user has cue sheets, etc under that
		# directory. We want to if we're scanning though.
		#
		# Bug 2048 - Don't add playlist files from the audiodir,
		# unless they are cue sheets.
		} elsif ((Slim::Music::Import::stillScanning() && Slim::Music::Info::isCUE($playlisturl)) || 
			Slim::Utils::Misc::inPlaylistFolder($playlisturl)) {

			# it's a playlist file
			$playlist_filehandle = FileHandle->new();

			open($playlist_filehandle, $playlistpathpath) || do {

				errorMsg("Couldn't open playlist file $playlistpath : $!\n");

				$playlist_filehandle = undef;
				$numitems = undef;
			};
		}
	}
	
	if ($playlist_filehandle) {
		my $playlist_base = undef;

		if (Slim::Music::Info::isFileURL($playlisturl)) {
			#XXX This was removed before in 3427, but it really works best this way
			#XXX There is another method that comes close if this shouldn't be used.
			my $path = Slim::Utils::Misc::pathFromFileURL($playlisturl);
			my @parts = splitdir($path);
			pop(@parts);
			$playlist_base = Slim::Utils::Misc::fileURLFromPath(catdir(@parts));
			$::d_scan && msg("gonna scan $playlisturl, with path $playlistpath, for base: $playlist_base\n");
		}

		if (ref($playlist_filehandle) eq 'Slim::Player::Protocols::HTTP') {
			# we've just opened a remote playlist.  Due to the synchronous
			# nature of our parsing code and our http socket code, we have
			# to make sure we download the entire file right now, before
			# parsing.  To do that, we use the content() method.  Then we
			# convert the resulting string into the stream expected by the
			# parsers.
			my $playlist_str = $playlist_filehandle->content();

			# Be sure to close the socket before reusing the
			# scalar - otherwise we'll leave the socket in a
			# CLOSE_WAIT state.
			$playlist_filehandle->close;
			$playlist_filehandle = undef;

			$playlist_filehandle = IO::String->new($playlist_str);
		}

		$::d_scan && msg("Scan::readList loading $playlisturl with base $playlist_base\n");
		$numitems = (push @$listref, Slim::Formats::Parse::parseList($playlisturl, $playlist_filehandle, $playlist_base)) - $startingsize;

		if (ref($playlist_filehandle) eq 'IO::String') {
			untie $playlist_filehandle;
		}

		undef $playlist_filehandle;

		# Add playlists to the database.
		if ($numitems && scalar @$listref) {

			# Create a playlist container
			my $title = Slim::Web::HTTP::unescape(basename($playlisturl));
			   $title =~ s/\.\w{3}$//;

			my $ct    = Slim::Music::Info::contentType($playlisturl);

			# With the special url if the playlist is in the
			# designated playlist folder. Otherwise, Dean wants
			# people to still be able to browse into playlists
			# from the Music Folder, but for those items not to
			# show up under Browse Playlists.
			#
			# Don't include the Shoutcast playlists or cuesheets
			# in our Browse Playlist view either.
			if (Slim::Music::Info::isFileURL($playlisturl) &&
				Slim::Utils::Misc::inPlaylistFolder($playlisturl) &&
				$playlisturl !~ /ShoutcastBrowser_Recently_Played/ &&
				!Slim::Music::Info::isCUE($playlisturl)
			) {
				$ct = 'ssp';
			}

			Slim::Music::Info::updateCacheEntry($playlisturl, {
				'TITLE' => $title,
				'CT'    => $ct,
				'LIST'  => $listref,
			});
		}

		$::d_scan && msg("Scan::readList loaded playlist with $numitems items\n");
	}

	# If we started out a with a lnk but ended up with a dir, the lnk is
	# still valid and we don't want it removed from the datastore.
	if ($playlistpath ne $playlisturl) {
		Slim::Music::Info::markAsScanned($playlisturl);
	}

	Slim::Music::Info::markAsScanned($playlistpath);
	
	return $numitems
}

1;

__END__
