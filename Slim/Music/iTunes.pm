package Slim::Music::iTunes;

# SlimServer Copyright (C) 2001-2003 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

# todo:
#   Enable saving current playlist in iTunes playlist format

use strict;

use Fcntl ':flock'; # import LOCK_* constants
use File::Spec::Functions qw(:ALL);

use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);

my $lastMusicLibraryDate = undef;
my $lastMusicLibraryFinishTime = undef;
my $isScanning = 0;
my $opened = 0;
my $locked = 0;
my $iBase = '';
my $ITUNESSCANINTERVAL = 60;

#$::d_itunes = 1;
#$::d_itunes_verbose = 1;


my $inPlaylists;
my $inTracks;
my %tracks;
my @playlists;
my $applicationVersion;
my $majorVersion;
my $minorVersion;

my $ituneslibrary;

sub iTunesPlaylist {
#	'CT',	 # content type
#	'TITLE', # title
#	'LIST',	 # list items (array)
#	'AGE',   # list age
#	'GENRE', # genre
#	'TRACKNUM', # tracknumber as an int
#	'FS',	 # file size
#	'ARTIST', # artist
#	'ALBUM',  # album name
#	'COMMENT',	# ID3 comment
#	'YEAR',		# year
#	'SECS', 	# total seconds
#	'VBR_SCALE', # vbr/cbr
#	'BITRATE', # bitrate
#	'TAGSIZE', # size of ID3v2 tag
#	'COMPOSER', # composer

	my @items = ( 	'TITLE',
					'ARTIST',
					'COMPOSER',
					'ALBUM',
					'GENRE',
					'FS',
					'SECS',
					'DISC',
					'DISCC',
					'TRACKNUM',
					'COUNT',
					'YEAR',
					'MOD',
					'ADDED',
					'BITRATE',
					'SR',
					'VOL',
					'KIND',
					'EQ',
					'COMMENT',
					'PLAYCOUNT',
					'LASTPLAYED',
					'RATING');
	my @playlist = @_;
	my $playliststring = "Name\tArtist\tComposer\tAlbum\tGenre\tSize\tTime\tDisc Number\tDisc Count\tTrack Number\tTrack Count\tYear\tDate Modified\tDate Added\tBit Rate\tSample Rate\tVolume Adjustment\tKind\tEqualizer\tComments\tPlay Count\tLast Played\tMy Rating\tLocation\r";
	foreach my $item (@playlist) {
		my $t;
		
	}
}

# mac file types
my %filetypes = (
	1095321158 => 'aif', # AIFF
	1295270176 => 'mov', # M4A 
	1295274016 => 'm4p', # M4P  we don't support this, but it would be good to know they are there....
	1297101600 => 'mp3', # MP3 	
	1297101601 => 'mp3', # MP3! 
	1297106247 => 'mp3', # MPEG
	1297106738 => 'mp3', # MPG2 
	1297106739 => 'mp3', # MPG3 
	1299148630 => 'mov', # MooV
	1299198752 => 'mp3', # Mp3 
	1463899717 => 'wav', # WAVE
	1836069665 => 'mp3', # mp3! 
	1836082995 => 'mp3', # mpg3 
	1836082996 => 'mov', # mpg4
);

# this library imports the iTunes Music Library.xml file for use as the music
# database, instead of scanning the file system.

# should we use the itunes library?
sub useiTunesLibrary {
	
	my $newValue = shift;
	my $can = canUseiTunesLibrary();
	
	if (defined($newValue)) {
		if (!$can) {
			Slim::Utils::Prefs::set('itunes', 0);
		} else {
			Slim::Utils::Prefs::set('itunes', $newValue);
		}
	}
	
	my $use = Slim::Utils::Prefs::get('itunes');
	
	if (!defined($use) && $can) { 
		Slim::Utils::Prefs::set('itunes', 1);
	} elsif (!defined($use) && !$can) {
		Slim::Utils::Prefs::set('itunes', 0);
	}
	
	$use = Slim::Utils::Prefs::get('itunes');

	$::d_itunes && msg("using itunes library: $use\n");
	
	return $use && $can;
}

sub canUseiTunesLibrary {
	return (defined(findMusicLibraryFile()));
}

sub findMusicLibraryFile {
	my $filename;
	my $base = "";
	$base = $ENV{HOME} if $ENV{HOME};
	
	my $plist = $base . '/Library/Preferences/com.apple.iApps.plist';

	if (-r $plist) {
		open (PLIST, "< $plist");
		while (<PLIST>) {
			if ( /<string>(.*iTunes%20Music%20Library.xml)<\/string>$/) {
				$filename = Slim::Utils::Misc::pathFromFileURL($1);
				last;
			}
		}
	}

	if ($filename && -r $filename) {
		return $filename;
	}
	
	
	$filename = $base . '/Music/iTunes/iTunes Music Library.xml';
	if (-r $filename) {
		return $filename;
	}

	$filename = $base . '/Documents/iTunes/iTunes Music Library.xml';
	if (-r $filename) {
		return $filename;
	}


	if (Slim::Utils::OSDetect::OS() eq 'win') {
		if (!eval "use Win32::Registry;") {
			my $folder;
			if ($::HKEY_CURRENT_USER->Open("Software\\Microsoft\\Windows"
								   ."\\CurrentVersion\\Explorer\\Shell Folders", $folder)) {
				my ($type, $value);
				if ($folder->QueryValueEx("My Music", $type, $value)) {
					$filename = $value . '\\iTunes\\iTunes Music Library.xml';
					$::d_itunes && msg("iTunes: found My Music here: $value for $filename\n");
				} elsif ($folder->QueryValueEx("Personal", $type, $value)) {
					$filename = $value . '\\My Music\\iTunes\\iTunes Music Library.xml';
					$::d_itunes && msg("iTunes: found  Personal: $value for $filename\n");
				}
				
				if (-r $filename) {
					return $filename;
				} else {
					$::d_itunes && msg("iTunes: couldn't read $filename\n");
				}
			}
		}		
	}
	
	$filename = catdir($base, 'iTunes Music Library.xml');
	if (-r $filename) {
		return $filename;
	}		

	$base = Slim::Utils::Prefs::get('mp3dir');

	$filename = catdir($base, 'My Music', 'iTunes', 'iTunes Music Library.xml');

	if (-r $filename) {
		return $filename;
	}		
	

	$filename = catdir($base, 'iTunes', 'iTunes Music Library.xml');

	if (-r $filename) {
		return $filename;
	}		
	
	$filename = catdir($base, 'iTunes Music Library.xml');

	if (-r $filename) {
		return $filename;
	}		
	
	return undef;
}

sub playlists {
	return \@playlists;
}

sub isMusicLibraryFileChanged {
	my $file = findMusicLibraryFile();
	my $fileMTime = (stat $file)[9];
	
	# Only say "yes" if it has been more than one minute since we last finished scanning
	# and the file mod time has changed since we last scanned. Note that if we are
	# just starting, $lastMusicLibraryDate is undef, so both $fileMTime
	# will be greater than 0 and time()-0 will be greater than 180 :-)
	if ($file && $fileMTime > $lastMusicLibraryDate) {
		$::d_itunes && msg("music library has changed!\n");
		if (time()-$lastMusicLibraryFinishTime > $ITUNESSCANINTERVAL) {
			return 1;
		} else {
			$::d_itunes && msg("waiting for $ITUNESSCANINTERVAL seconds to pass before rescanning\n");
		}
	}
	
	return 0;
}

sub checker {
	if (useiTunesLibrary() && !stillScanning() && isMusicLibraryFileChanged()) {
		startScan();
	}

	# make sure we aren't doing this more than once...
	Slim::Utils::Timers::killTimers(0, \&checker);

	# Call ourselves again after 5 seconds
	Slim::Utils::Timers::setTimer(0, (Time::HiRes::time() + 5.0), \&checker);
}

sub startScan {
	if (!useiTunesLibrary()) {
		return;
	}
		
	my $file = findMusicLibraryFile();

	$::d_itunes && msg("startScan: iTunes file: $file\n");

	if (!defined($file)) {
		warn "Trying to scan an iTunes file that doesn't exist.";
		return;
	}
	
	stopScan();
	
	$::d_itunes && msg("Clearing ID3 cache\n");

	Slim::Music::Info::clearCache();

	Slim::Utils::Scheduler::add_task(\&scanFunction);
	$isScanning = 1;

	# start the checker
	checker();
	
} 

sub stopScan {
	if (stillScanning()) {
		Slim::Utils::Scheduler::remove_task(\&scanFunction);
		doneScanning();
	}
}

sub stillScanning {
	return $isScanning;
}

sub doneScanning {
	$::d_itunes && msg("iTunes: done Scanning: unlocking and closing\n");

	$locked = 0;

	$opened = 0;
	$ituneslibrary = undef;
	
	$lastMusicLibraryFinishTime = time();

	$isScanning = 0;
	@playlists = Slim::Music::Info::sortIgnoringCase(@playlists); 
}

###########################################################################################
	# This incredibly ugly parser is highly dependent on the iTunes 3.0 file format.
	# A wise man with more time would use a true XML parser and integrate the appropriate
	# libraries into the distribution to work cross platform, until then...

    # Abandon all hope ye who enter here...
###########################################################################################
sub scanFunction {
	# this assumes that iTunes uses file locking when writing the xml file out.
	if (!$opened) {
		my $file = findMusicLibraryFile();
		if (!open(ITUNESLIBRARY, "<$file")) {
			$::d_itunes && warn "Couldn't open iTunes Library: $file";
			return 0;	
		}
		$opened = 1;
		resetScanState();
		$lastMusicLibraryDate = (stat $file)[9];
	}
	
	if ($opened && !$locked) {
		$locked = 1;
		$locked = flock(ITUNESLIBRARY, LOCK_SH | LOCK_NB) unless ($^O eq 'MSWin32'); 
		if ($locked) {
			$::d_itunes && msg("Got file lock on iTunes Library\n");
			$locked = 1;
			my $len = read ITUNESLIBRARY, $ituneslibrary, -s findMusicLibraryFile();
			die "couldn't read itunes library!" if (!defined($len));
			flock(ITUNESLIBRARY, LOCK_UN) unless ($^O eq 'MSWin32');
			close ITUNESLIBRARY;
			$ituneslibrary =~ s/></>\n</g;
		} else {
			$::d_itunes && warn "Waiting on lock for iTunes Library";
			return 1;
		}
	}
	
	my $curLine = getLine();
	if (!defined($curLine)) {
		# done scanning
		$::d_itunes && msg("iTunes: finished scanning, leaving scan function\n");
		return 0;
	}
	
	if ($inTracks) {
		if ($curLine eq '</dict>') {
			$inTracks = 0;
		} elsif ($curLine =~ /<key>([^<]*)<\/key>/) {
			my $id = $1;
			my %curTrack = getDict();
			my %cacheEntry = ();
			# add this track to the library
			if ($id ne $curTrack{'Track ID'}) {
				warn "Danger, the Track ID (" . $curTrack{'Track ID'} . ") and the key ($id) don't match.\n";
			}
			
			$::d_itunes && msg("got a track named " . $curTrack{'Name'} . "\n");
			my $kind = $curTrack{'Kind'};
			my $location = $curTrack{'Location'};
			my $filetype = $curTrack{'File Type'};
			my $type = undef;
			if ($filetype) {
				if (exists $Slim::Music::Info::types{$filetype}) {
					$type = $Slim::Music::Info::types{$filetype};
				} else {
					$type = $filetypes{$filetype};
				}
			}
			
			if ($location && ($location =~ /automount/)) {
					#Strip out automounter 'private' paths.
					#OSX wants us to use file://Network/ or timeouts occur
					#There may be more combinations
					$location =~ s/private\/var\/automount\///;
					$location =~ s/private\/automount\///;
					$location =~ s/automount\/static\///;
			}

			if ($location && !defined($type)) {
				$type = Slim::Music::Info::typeFromPath($location, 'mp3');
			}
			
			if (Slim::Music::Info::isSong($location, $type) || Slim::Music::Info::isHTTPURL($location)) {
				$cacheEntry{'CT'} = $type;
				$cacheEntry{'TITLE'} = $curTrack{'Name'};
				$cacheEntry{'ARTIST'} = $curTrack{'Artist'};
				$cacheEntry{'COMPOSER'} = $curTrack{'Composer'};

				# Handle multi-disc sets with the same title (otherwise, same-numbered tracks are overridden)
				# by appending a disc count to the track's album name.
				# If "disc <num>" (localized or English) is present in the title, we assume it's already unique and don't
				# add the suffix.
				# If there's only one disc in the set, we don't bother with "disc 1 of 1"
				if (defined($curTrack{'Disc Number'}) && defined($curTrack{'Disc Count'}))
				{
				    my $discNum = $curTrack{'Disc Number'};
				    my $discCount = $curTrack{'Disc Count'};
				    my $discWord = string('DISC');
					
				    $cacheEntry{'DISC'} = $discNum;
				    $cacheEntry{'DISCC'} = $discCount;
				    
				    if ($discCount > 1 && !($curTrack{'Album'} =~ /(${discWord})|(Disc)\s+[0-9]+/i))
				    {
					# Add space to handle > 10 album sets and sorting. Is suppressed in the HTML.
					if ($discCount > 9 && $discNum < 10) { $discNum = ' ' . $discNum; };
						
					$curTrack{'Album'} = $curTrack{'Album'} . " ($discWord $discNum " . string('OF') . " $discCount)";
				    }
				}
				$cacheEntry{'ALBUM'} = $curTrack{'Album'};			
				
				$cacheEntry{'GENRE'} = $curTrack{'Genre'};
				$cacheEntry{'FS'} = $curTrack{'Size'};
				if ($curTrack{'Total Time'}) { $cacheEntry{'SECS'} = $curTrack{'Total Time'} / 1000; };
				$cacheEntry{'BITRATE'} = $curTrack{'Bit Rate'};
				$cacheEntry{'YEAR'} = $curTrack{'Year'};
				$cacheEntry{'TRACKNUM'} = $curTrack{'Track Number'};
				$cacheEntry{'COMMENT'} = $curTrack{'Comments'};
				# cacheEntry{'???'} = $curTrack{'Track Count'};
				# cacheEntry{'???'} = $curTrack{'Sample Rate'};
				my $url = $location;
				if (Slim::Music::Info::isFileURL($url)) {
					if (Slim::Utils::OSDetect::OS() eq 'unix') {
						my $base = Slim::Utils::Prefs::get('mp3dir');
						$::d_itunes && msg("Correcting for Linux: $iBase to $base\n");
						$url =~ s/$iBase/$base/isg;
						$url = Slim::Web::HTTP::unescape($url);
					};
					$url =~ s/\/$//;
				}
				if ($url) {
					Slim::Music::Info::updateCacheEntry($url, \%cacheEntry);
					Slim::Music::Info::updateGenreCache($url, \%cacheEntry);
	
					if ($::d_itunes) {
						if (Slim::Music::Info::isFileURL($url)) {
							my $file = Slim::Utils::Misc::pathFromFileURL($url);
							if ($file && !-f $file) { warn "iTunes: file not found: $file\n"; } 
						}
					}
					
					$tracks{$id} = $url;
				} else {
					$::d_itunes && warn "iTunes: missing Location " . %cacheEntry;
				}
			} else {
				$::d_itunes && warn "iTunes: unknown file type " . $curTrack{'Kind'} . " $location";
			} 

		}
	} elsif ($inPlaylists) {
		if ($curLine eq '</array>') {
			$inPlaylists = 0;
		} else {
			my %curPlaylist = getDict();
			my %cacheEntry = ();
			my $name = $curPlaylist{'Name'};
			my $url = 'itunesplaylist:' . Slim::Web::HTTP::escape($name);
			$::d_itunes && msg("got a playlist ($url) named $name\n");
			# add this playlist to our playlist library
#	'LIST',	 # list items (array)
#	'AGE',   # list age
			$cacheEntry{'TITLE'} = "iTunes: " . $name;
			$cacheEntry{'LIST'} = $curPlaylist{'Playlist Items'};
			$cacheEntry{'CT'} = 'itu';
			$cacheEntry{'TAG'} = 1;
			Slim::Music::Info::updateCacheEntry($url, \%cacheEntry);
			push @playlists, $url;
			$::d_itunes && msg("playlists now has " . scalar(@playlists) . " items...\n");
		}
	} else {
		if ($curLine eq "<key>Major Version</key>") {
			$majorVersion = getValue();
			$::d_itunes && msg("iTunes Major Version: $majorVersion\n");
		} elsif ($curLine eq "<key>Minor Version</key>") {
			$minorVersion = getValue();
			$::d_itunes && msg("iTunes Minor Version: $minorVersion\n");
		} elsif ($curLine eq "<key>Application Version</key>") {
			$applicationVersion = getValue();
			$::d_itunes && msg("iTunes application version: $applicationVersion\n");
		} elsif ($curLine eq "<key>Music Folder</key>") {
			$iBase = getValue();
			#$iBase = Slim::Utils::Misc::pathFromFileURL($iBase);
			$::d_itunes && msg("iTunes: found the music folder: $iBase\n");
#			Slim::Utils::Prefs::set("mp3dir", $musicPath);
		} elsif ($curLine eq "<key>Tracks</key>") {
			$inTracks = 1;
			$inPlaylists = 0;
			$::d_itunes && msg("iTunes: starting track parsing\n");
		} elsif ($curLine eq "<key>Playlists</key>") {
			$inPlaylists = 1;
			$inTracks = 0;
			$::d_itunes && msg("iTunes: starting playlist parsing\n");
		}
	}

	return 1;
}

sub getValue {
	my $curLine = getLine();
	my $data = '';
	if ($curLine =~ /^<(?=[ids])(?:integer|date|string)>([^<]*)<\/(?=[ids])(?:integer|date|string)>$/) {
               $data = $1;
	} elsif ($curLine eq '<true/>') {
		$data = 1;
	} elsif ($curLine eq '<data>') {
		$curLine = getLine();
		while (defined($curLine) && ($curLine ne '</data>')) {
			$data .= $curLine;
			$curLine = getLine();
		}
	} elsif ($curLine =~ /<string>([^<]*)/) {
			$data = $1;
			$curLine = getLine();
			while (defined($curLine) && ($curLine !~ /<\/string>/)) {
				$data .= $curLine;
				$curLine = getLine();
			}
			if ($curLine =~ /([^<]*)<\/string>/) {
				$data .= $1;
			}
	}
	$data =~ s/&#(\d*);/chr($1)/ge;
# 	$data  = pack("C*", unpack("U*", $data));	
	$data =~ s/([\xC0-\xDF])([\x80-\xBF])/chr(ord($1)<<6&0xC0|ord($2)&0x3F)/eg; 
	$data =~ s/[\xE2][\x80][\x99]/'/g;
	return $data;
}

sub getPlaylistTrackArray {
	my @playlist = ();
	my $curLine = getLine();
	$::d_itunes_verbose && msg("Starting parsing of playlist\n");
	if ($curLine ne '<array>') {
		warn "Unexpected $curLine in playlist track array while looking for <array>";
		return;
	}
		
	while (($curLine = getLine()) && ($curLine ne '</array>')) {

		if ($curLine ne '<dict>') {
			warn "Unexpected $curLine in playlist track array while looking for <dict>";
			return;
		}
		
		$curLine = getLine();
		
		if ($curLine ne '<key>Track ID</key>') {
			warn "Unexpected $curLine in playlist track array while looking for track id";
			return \@playlist;
		}
		my $value = getValue();
		if (defined($tracks{$value})) {
			push @playlist, $tracks{$value};
			$::d_itunes_verbose && msg("  pushing $value on to list: " . $tracks{$value} . "\n");
		} else {
			$::d_itunes_verbose && msg("  NOT pusing $value on to list, it's missing\n");
		}

		$curLine = getLine();
		if ($curLine ne '</dict>') {
			warn "Unexpected $curLine in playlist track array while looking for </dict>";
			return \@playlist;
		}
	}	
	
	$::d_itunes && msg("got a playlist array of " . scalar(@playlist) . " items\n");
	return \@playlist;
}

sub getLine {
#	my $curLine = <ITUNESLIBRARY>;
	my $curLine;
	
	$ituneslibrary =~ /([^\n]*)\n/g;	
	
	$curLine = $1;
	
	if (!defined($curLine)) {
		doneScanning();
		return undef;
	}
	
	$curLine =~ s/^\s+//;
	$curLine =~ s/\s$//;
	
	$::d_itunes_verbose && msg("Got line: $curLine\n");
	return $curLine;
}

sub getDict {
	my $curLine;
	my $nextLine;
	my %dict;
	while ($curLine = getLine()) {
		my $key = undef;
		my $value = undef;
		if ($curLine =~ /<key>([^<]*)<\/key>/) {
			$key = $1;
			if ($key eq "Playlist Items") {
				$value = getPlaylistTrackArray();
			} else {
				$value = getValue();
			}			
			if (defined($key) && defined($value)) { 
				$dict{$key} = $value;
				$::d_ttunes && msg("got dictionary entry: $key = $value\n");
			} else {
				warn "iTunes: Couldn't get key and value in dictionary, got $key and $value";
			}
		} elsif ($curLine eq '<dict>') {
			$::d_itunes_verbose && msg("found beginning of dictionary\n");
		} elsif ($curLine eq '</dict>') {
			$::d_itunes_verbose && msg("found end of dictionary\n");
			last;
		} else {
			warn "iTunes: Confused looking for key in dictionary";
		}
	}
	return %dict;
}

sub resetScanState {
	$inPlaylists = 0;
	$inTracks = 0;
	$applicationVersion = undef;
	$majorVersion = undef;
	$minorVersion = undef;
	%tracks = ();
	@playlists = ();
}

1;
__END__

