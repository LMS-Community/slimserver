package Slim::Control::Command;

# $Id$
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
use Scalar::Util qw(blessed);
use Time::HiRes;

use Slim::Control::Dispatch;
use Slim::DataStores::Base;
use Slim::Display::Display;
use Slim::Music::Import;
use Slim::Music::Info;
use Slim::Utils::Misc;
use Slim::Utils::Scan;
use Slim::Utils::Strings qw(string);

our %executeCallbacks = ();

our %searchMap = (

	'artist' => 'contributor.namesearch',
	'genre'  => 'genre.namesearch',
	'album'  => 'album.titlesearch',
	'track'  => 'track.titlesearch',
);

#$::d_command = 1;

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

	$::d_command && msg("Command::Executing command " . ($client ? $client->id() : "no client") . ": $p0 (" .
			(defined $p1 ? $p1 : "") . ") (" .
			(defined $p2 ? $p2 : "") . ") (" .
			(defined $p3 ? $p3 : "") . ") (" .
			(defined $p4 ? $p4 : "") . ") (" .
			(defined $p5 ? $p5 : "") . ") (" .
			(defined $p6 ? $p6 : "") . ") (" .
			(defined $p7 ? $p7 : "") . ")\n");

	# Try and go through dispatch

	# create a request from the array
	my $request = Slim::Control::Dispatch::requestFromArray($client, $parrayref);
	
	if (defined $request) {
		$::d_command && $request->dump();
	
		$request->execute();

		if ($request->wasStatusDispatched()){
	
			$::d_command && $request->dump();
		
			# make sure we don't execute again if ever dispatch knows
			# about a command still below
			$p0 .= "(was dispatched)";
		
			# prevent pushing $p0 again..
			$pushParams = 0;
	
			# patch the return array so that callbacks function as before
			@returnArray = $request->renderAsArray();
		}
	}
		
# END

	
	

# The first parameter is the client identifier to execute the command. Column C in the
# table below indicates if a client is required (Y) or not (N) for the command.
#
# If a parameter is "?" it is replaced by the current value in the array
# returned by the function
#
# COMMAND LIST #
  
# C     P0             P1                          P2                            P3            P4         P5        P6
#PLAYLISTS 
# Y    playlist        playtracks                  <searchterms>    
# Y    playlist        loadtracks                  <searchterms>    
# Y    playlist        addtracks                   <searchterms>    
# Y    playlist        inserttracks                <searchterms>    
# Y    playlist        deletetracks                <searchterms>   

# Y    playlist        play|load                   <item>                       [<title>] (item can be a song, playlist or directory)
# Y    playlist        add|append                  <item>                       [<title>] (item can be a song, playlist or directory)
# Y    playlist        insert|insertlist           <item> (item can be a song, playlist or directory)

# Y    playlist        resume                      <playlist>    
# Y    playlist        save                        <playlist>    


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

 		
 		
################################################################################
# The following commands require a valid client to be specified
################################################################################

	} elsif ($client) {

		if ($p0 eq "playlist") {

			my $results;

			# This should be undef - see bug 2085
			my $jumpToIndex;

			# Query for the passed params
#			if ($p1 =~ /^(play|load|add|insert|delete)album$/) {
#
#				my $sort = 'track';
#				# XXX - FIXME - searching for genre.name with
#				# anything else kills the database. As a
#				# stop-gap, don't add the search for
#				# genre.name if we have a more specific query.
#				if (specified($p2) && !specified($p3)) {
#					$find->{'genre.name'} = singletonRef($p2);
#				}
#
#				if (specified($p3)) {
#					$find->{'contributor.name'} = singletonRef($p3);
#				}
#
#				if (specified($p4)) {
#					$find->{'album.title'} = singletonRef($p4);
#					$sort = 'tracknum';
#				}
#
#				if (specified($p5)) {
#					$find->{'track.title'} = singletonRef($p5);
#				}
#
#				$results = $ds->find({
#					'field'  => 'lightweighttrack',
#					'find'   => $find,
#					'sortBy' => $sort,
#				});
#			}

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
					if (Slim::Music::Info::isRemoteURL($path) && $path =~ /%3A%2F%2F/) {

						$path = Slim::Utils::Misc::unescape($path);
					}
					
					if ($p1 =~ /^(play|load|resume)$/) {

						Slim::Player::Source::playmode($client, "stop");
						Slim::Player::Playlist::clear($client);

						my $fixpath = Slim::Utils::Misc::fixPath($path);

						$client->currentPlaylist($fixpath);
						$client->currentPlaylistModified(0);

					} elsif ($p1 =~ /^(add|append)$/) {

						my $fixpath = Slim::Utils::Misc::fixPath($path);
						$client->currentPlaylistModified(1);

					} else {

						$client->currentPlaylistModified(1);
					}

					$path = Slim::Utils::Misc::virtualToAbsolute($path);

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
			
#			} elsif ($p1 eq "loadalbum" || $p1 eq "playalbum") {
#
#				Slim::Player::Source::playmode($client, "stop");
#				Slim::Player::Playlist::clear($client);
#
#				push(@{Slim::Player::Playlist::playList($client)}, @$results);
#
#				Slim::Player::Playlist::reshuffle($client, 1);
#				Slim::Player::Source::jumpto($client, 0);
#				$client->currentPlaylist(undef);
#				$client->currentPlaylistChangeTime(time());
#			
#			} elsif ($p1 eq "addalbum") {
#
#				push(@{Slim::Player::Playlist::playList($client)}, @$results);
#
#				Slim::Player::Playlist::reshuffle($client);
#				$client->currentPlaylistModified(1);
#				$client->currentPlaylistChangeTime(time());
#			
#			} elsif ($p1 eq "insertalbum") {
#
#				my $playListSize = Slim::Player::Playlist::count($client);
#				my $size = scalar(@$results);
#
#				push(@{Slim::Player::Playlist::playList($client)}, @$results);
#					
#				insert_done($client, $playListSize, $size);
#				#Slim::Player::Playlist::reshuffle($client);
#				$client->currentPlaylistModified(1);
#				$client->currentPlaylistChangeTime(time());
			
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

#			} elsif ($p1 eq "deletealbum") {
#
#				Slim::Player::Playlist::removeMultipleTracks($client, $results);
#				$client->currentPlaylistModified(1);
#				$client->currentPlaylistChangeTime(time());
			
			}

			Slim::Player::Playlist::refreshPlaylist($client) if $client->currentPlaylistModified();
 		}
 	} else {
 		# to prevent problems with callbacks which check for defined $client
 		$client = undef;
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
	
	$::d_command && msg("Command::Returning array: " . $returnArray[0] . " (" .
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
}

sub clearExecuteCallback {
	my $callbackRef = shift;
	delete $executeCallbacks{$callbackRef};
}

sub executeCallback {
	my $client = shift;
	my $paramsRef = shift;

	no strict 'refs';
		
	for my $executecallback (keys %executeCallbacks) {
		$executecallback = $executeCallbacks{$executecallback};
		&$executecallback($client, $paramsRef);
	}
}

sub load_done {
	my ($client, $index, $callbackf, $callbackargs) = @_;

	# dont' keep current song on loading a playlist
	Slim::Player::Playlist::reshuffle($client,
		(Slim::Player::Source::playmode($client) eq "play" || ($client->power && Slim::Player::Source::playmode($client) eq "pause")) ? 0 : 1
	);

	if (defined($index)) {
		Slim::Player::Source::jumpto($client, $index);
	}

	$callbackf && (&$callbackf(@$callbackargs));

	Slim::Control::Command::executeCallback($client, ['playlist','load_done']);
}

sub insert_done {
	my ($client, $listsize, $size, $callbackf, $callbackargs) = @_;

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

	Slim::Control::Command::executeCallback($client, ['playlist','load_done']);
}

sub singletonRef {
	my $arg = shift;

	if (!defined($arg)) {
		return [];
	} elsif ($arg eq '*') {
		return [];
	} elsif ($arg) {
		# force stringification of a possible object.
		return [ "" . $arg ];
	} else {
		return [];
	}
}

sub parseSearchTerms {
	my $client = shift;
	my $terms  = shift;

	my $ds     = Slim::Music::Info::getCurrentDataStore();
	my %find   = ();
	my @fields = Slim::DataStores::Base->queryFields();
	my ($sort, $limit, $offset);

	for my $term (split '&', $terms) {

		if ($term =~ /(.*)=(.*)/ && grep $_ eq $1, @fields) {

			my $key   = URI::Escape::uri_unescape($1);
			my $value = URI::Escape::uri_unescape($2);

			$find{$key} = Slim::Utils::Text::ignoreCaseArticles($value);

		} elsif ($term =~ /^(fieldInfo)=(\w+)$/) {

			$find{$1} = $2;
		}

		# modifiers to the search
		$sort   = $2 if $1 eq 'sort';
		$limit  = $2 if $1 eq 'limit';
		$offset = $2 if $1 eq 'offset';
	}

	# default to a sort
	$sort ||= exists $find{'album'} ? 'tracknum' : 'track';

	# We can poke directly into the field info if requested - for more complicated queries.
	if ($find{'fieldInfo'}) {

		my $fieldInfo = Slim::DataStores::Base->fieldInfo;
		my $fieldKey  = $find{'fieldInfo'};

		return &{$fieldInfo->{$fieldKey}->{'find'}}($ds, 0, { 'audio' => 1 }, 1);

	} elsif ($find{'playlist'}) {

		# Treat playlists specially - they are containers.
		my $obj = $ds->objectForId('track', $find{'playlist'});

		if (blessed($obj) && $obj->can('tracks')) {

			# Side effect - (this would never fly in Haskell! :)
			# We want to add the playlist name to the client object.
			$client->currentPlaylist($obj);

			return $obj->tracks;
		}

		return ();

	} else {

		# Bug 2271 - allow VA albums.
		if ($find{'album.compilation'}) {

			delete $find{'artist'};
		}

		return @{ $ds->find({
			'field'  => 'lightweighttrack',
			'find'   => \%find,
			'sortBy' => $sort,
			'limit'  => $limit,
			'offset' => $offset,
		}) };
	}
}

sub parseListRef {
	my $client  = shift;
	my $term    = shift;
	my $listRef = shift;

	if ($term =~ /listref=(\w+)&?/i) {
		$listRef = $client->param($1);
	}

	if (defined $listRef && ref $listRef eq "ARRAY") {

		return @$listRef;
	}
}

# defined, but does not contain a *
sub specified {
	my $i = shift;

	return 0 if ref($i) eq 'ARRAY';
	return 0 unless defined $i;
	return $i !~ /\*/;
}

1;

__END__


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
