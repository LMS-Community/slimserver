package Slim::Music::Info;

# $Id: Info.pm,v 1.25 2003/12/01 23:02:46 dean Exp $

# SlimServer Copyright (c) 2001, 2002, 2003 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use Fcntl;
use File::Spec::Functions qw(:ALL);
use FindBin qw($Bin);

use MP3::Info;

use Slim::Formats::Movie;
use Slim::Formats::AIFF;
use Slim::Formats::FLAC;
use Slim::Formats::Wav;
use Slim::Formats::Ogg;
use Slim::Utils::Misc;
use Slim::Utils::OSDetect;
use Slim::Utils::Strings qw(string);

#
# constants
#

# the items in the infocache that we actually use
# NOTE: THE ORDER MATTERS HERE FOR THE PERSISTANT DB
# IF YOU ADD SOMETHING, PUT IT AT THE END
my @infoCacheItems = (
	'CT',	 # content type
	'TITLE', # title
	'LIST',	 # list items (array)
	'AGE',   # list age
	'GENRE', # genre
	'TRACKNUM', # tracknumber as an int
	'FS',	 # file size
	'SIZE',	 # audio data size in bytes
	'OFFSET', # offset to start of song
	'ARTIST', # artist
	'ALBUM',  # album name
	'COMMENT',	# ID3 comment
	'YEAR',		# year
	'SECS', 	# total seconds
	'VBR_SCALE', # vbr/cbr
	'BITRATE', # bitrate
	'TAGVERSION', # ID3 tag version
	'COMPOSER', # composer
	'TAGSIZE', # tagsize
	'DISC', # album number in a set 
	'DISCC', # number of albums in a set
	'MOODLOGIC_SONG_ID', # MoodLogic fields
	'MOODLOGIC_ARTIST_ID', #
	'MOODLOGIC_GENRE_ID', #
	'MOODLOGIC_SONG_MIXABLE', #
	'MOODLOGIC_ARTIST_MIXABLE', #
	'MOODLOGIC_GENRE_MIXABLE', #
	'COVER', # cover art
	'COVERTYPE', # cover art content type
	'THUMB', # thumbnail cover art
	'THUMBTYPE', #thumnail content type
	'TAG', # have we read the tags yet?
	'ALBUMSORT',
	'ARTISTSORT',
	'TITLESORT',
	'RATE', # Sample rate
	'SAMPLESIZE', # Sample size
	'CHANNELS', # number of channels
	'BAND'
);



# three hashes containing the types we know about, populated b tye loadTypesConfig routine below
# hash of default mime type index by three letter content type e.g. 'mp3' => audio/mpeg
%Slim::Music::Info::types = ();

# hash of three letter content type, indexed by mime type e.g. 'text/plain' => 'txt'
%Slim::Music::Info::mimeTypes = ();

# hash of three letter content types, indexed by file suffixes (past the dot)  'aiff' => 'aif'
%Slim::Music::Info::suffixes = ();

#
# global caches
#

# a hierarchical cache of genre->artist->album->tracknum based on ID3 information
my %genreCache = ();

# a cache of the titles used for uniquely identifing and sorting items 
my %caseCache = ();

my %sortCache = ();

# the main cache of ID3 and other metadata
my %infoCache = ();
my %infoCacheDB = (); # slow, persistent cache structure

# moodlogic cache for genre and artist mix indicator; empty if moodlogic isn't
# used
my %genreMixCache = ();
my %artistMixCache = ();

my $songCount = 0;
my $total_time = 0;

my %songCountMemoize = ();
my %artistCountMemoize = ();
my %albumCountMemoize = ();
my %genreCountMemoize = ();
my %caseArticlesMemoize = ();

my %infoCacheItemsIndex;

##################################################################################
# these routines deal with the caches directly
##################################################################################
sub init {

	loadTypesConfig();
	
	my $dbname;

	my $i = 0;
	foreach my $tag (@infoCacheItems) {
		$infoCacheItemsIndex{$tag} = $i;
		$i++;
	}
	
	if (Slim::Utils::Prefs::get('usetagdatabase')) {

		# TODO: MacOS X should really store this in a visible, findable place.
		if (Slim::Utils::OSDetect::OS() eq 'unix') {
			$dbname = '.slimp3info.db';
		} elsif (Slim::Utils::OSDetect::OS() eq 'win')  {
			$dbname = 'SLIMP3INFO.DB';
		} else {
			$dbname ='slimp3info.db';
		}
		
		# put it in the same folder as the preferences.
		$dbname = catdir(Slim::Utils::Prefs::preferencesPath(), $dbname);

		$::d_info && Slim::Utils::Misc::msg("ID3 tag database support is ON, saving into: $dbname\n");

		tie (%infoCacheDB, 'MLDBM', $dbname, O_CREAT|O_RDWR, 0666)
			or warn "Error opening tag database $dbname: $!";

		foreach my $file (keys %infoCacheDB) {
			if (isSong($file)) {
				my $cacheEntryArray =  $infoCacheDB{$file};
				my $cacheEntryHash;

				my $i = 0;
				foreach my $key (@infoCacheItems) {
					$cacheEntryHash->{$key} = $cacheEntryArray->[$i];
					$i++;
				}

				updateGenreCache($file, $cacheEntryHash);

				$total_time += $cacheEntryHash->{SECS};
				$songCount++;
			}
		}
		$::d_info && Slim::Utils::Misc::msg("done loading genre cache from DB\n");
	}
	
	# use all the genres we know about...
	MP3::Info::use_winamp_genres();
	
	# also get the album, performer and title sort information
	$MP3::Info::v2_to_v1_names{'TSOA'} = 'ALBUMSORT';
	$MP3::Info::v2_to_v1_names{'TSOP'} = 'ARTISTSORT';
	$MP3::Info::v2_to_v1_names{'TSOT'} = 'TITLESORT';

	# get composers
	$MP3::Info::v2_to_v1_names{'TCM'} = 'COMPOSER';
	$MP3::Info::v2_to_v1_names{'TCOM'} = 'COMPOSER';

	# get band/orchestra
	$MP3::Info::v2_to_v1_names{'TP2'} = 'BAND';
	$MP3::Info::v2_to_v1_names{'TPE2'} = 'BAND';	

	#turn on unicode support
#	if (!MP3::Info::use_mp3_utf8(1)) {	
#		$::d_info && Slim::Utils::Misc::msg("Couldn't turn on unicode support.\n");
#	};
}

sub loadTypesConfig {
	my @typesFiles;
	$::d_info && Slim::Utils::Misc::msg("loading types config file...\n");
	
	push @typesFiles, catdir($Bin, 'types.conf');
	if (Slim::Utils::OSDetect::OS() eq 'mac') {
		push @typesFiles, $ENV{'HOME'} . "/Library/SlimDevices/types.conf";
		push @typesFiles, "/Library/SlimDevices/types.conf";
		push @typesFiles, $ENV{'HOME'} . "/Library/SlimDevices/slimserver-types.conf";
		push @typesFiles, "/Library/SlimDevices/slimserver-types.conf";
	}
	push @typesFiles, catdir($Bin, 'slimserver-types.conf');
	push @typesFiles, catdir($Bin, '.slimserver-types.conf');
	
	
	foreach my $typeFileName (@typesFiles) {
		if (open my $typesFile, "<$typeFileName") {
			for my $line (<$typesFile>) {
				# get rid of comments and leading and trailing white space
				$line =~ s/#.*$//;
				$line =~ s/^\s//;
				$line =~ s/\s$//;
	
				if ($line =~ /^(\S+)\s+(\S+)\s+(\S+)/) {
					my $type = $1;
					my @suffixes = split ',', $2;
					my @mimeTypes = split ',', $3;
					
					foreach my $suffix (@suffixes) {
						next if ($suffix eq '-');
						$Slim::Music::Info::suffixes{$suffix} = $type;
					}
					
					foreach my $mimeType (@mimeTypes) {
						next if ($mimeType eq '-');
						$Slim::Music::Info::mimeTypes{$mimeType} = $type
					}
					
					# the first one is the default
					if ($mimeTypes[0] ne '-') {
						$Slim::Music::Info::types{$type} = $mimeTypes[0];
					}				
				}
			}
			close $typesFile;
		}
	}
}
sub stopCache {
	untie (%infoCacheDB);
}

sub clearCache {
	my $item = shift;
	if ($item) {
		delete $infoCache{$item};
		$::d_info && Slim::Utils::Misc::msg("cleared $item from cache\n");
	} else {
		%infoCache = ();
		# a hierarchical cache of genre->artist->album->song based on ID3 information
		%genreCache = ();
		%caseCache = ();
		%sortCache = ();
        %genreMixCache = ();
        %artistMixCache = ();
        
		$songCount = 0;
		$total_time = 0;
		
		%songCountMemoize=();
		%artistCountMemoize=();
		%albumCountMemoize=();
		%genreCountMemoize=();
		%caseArticlesMemoize=();
	}
}

sub total_time {
	return $total_time;
}

sub memoizedCount {
	my ($memoized,$function,$genre,$artist,$album,$track)=@_;
	if (!defined($genre)) { $genre = [] }
	if (!defined($artist)) { $artist = [] }
	if (!defined($album)) { $album = [] }
	if (!defined($track)) { $track = [] }

	my $key=join("\1",@$genre) . "\0" .
		    join("\1",@$artist). "\0" .
			join("\1",@$album) . "\0" .
			join("\1",@$track);
	if (defined($$memoized{$key})) {
		return $$memoized{$key};
	}
	my $count = &$function($genre,$artist,$album,$track);
	if (!Slim::Utils::Misc::stillScanning()) {
		return ($$memoized{$key}=$count);
	}
	return $count;
}

# called:
#   undef,undef,undef,undef
sub songCount {
	my ($genre,$artist,$album,$track)=@_;
	if (!defined($genre)) { $genre = [] }
	if (!defined($artist)) { $artist = [] }
	if (!defined($album)) { $album = [] }
	if (!defined($track)) { $track = [] }
	
	if ((scalar @$genre == 0 || $$genre[0] eq '*') &&
		(scalar @$artist == 0 || $$artist[0] eq '*') &&
		(scalar @$album == 0 || $$album[0] eq '*') &&
		(scalar @$track == 0 || $$track[0] eq '*')
	) {
		return $songCount;	
	}
	
	return memoizedCount(\%songCountMemoize,\&songs,($genre,$artist,$album,$track,'count'));
}

# called:
#   undef,undef,undef,undef
#	[$item],[],[],[]
#	$genreref,$artistref,$albumref,$songref
sub artistCount {
	return memoizedCount(\%artistCountMemoize,\&artists,@_, 1);
}

# called:
#   undef,undef,undef,undef
#   [$item],[],[],[]
#	[$genre],['*'],[],[]
#   [$genre],[$item],[],[]
#	$genreref,$artistref,$albumref,$songref
sub albumCount { 
	return memoizedCount(\%albumCountMemoize,\&albums,@_, 1);
}

# called:
#   undef,undef,undef,undef
sub genreCount { 
	return memoizedCount(\%genreCountMemoize,\&genres,@_, 1);
}

sub isCached {
	my $url = shift;
	return exists $infoCache{$url};
}

sub cacheItem {
	my $url = shift;
	my $item = shift;
	my $cacheEntryArray;
	
	if (!defined($url)) {
		Slim::Utils::Misc::msg("Null cache item!\n"); 
		Slim::Utils::Misc::bt();
		return undef;
	}
	
	if (exists $infoCache{$url}) {
		$cacheEntryArray = $infoCache{$url};
		my $index = $infoCacheItemsIndex{$item};
		if (exists $cacheEntryArray->[$index]) {
			return $cacheEntryArray->[$index];
		} else {
			return undef;
		}
	}

	# cache miss from memory, check the disk
	if (Slim::Utils::Prefs::get('usetagdatabase') &&
			!defined $cacheEntryArray &&
			exists $infoCacheDB{$url}) {
		$cacheEntryArray = $infoCacheDB{$url};
		$infoCache{$url} = $cacheEntryArray;
		my $index = $infoCacheItemsIndex{$item};
		if (defined $cacheEntryArray && exists $cacheEntryArray->[$index]) {
			return $cacheEntryArray->[$index];
		}
	}
	
	return undef;
}

sub cacheEntry {
	my $url = shift;
	my $cacheEntryHash = {};
	my $cacheEntryArray;

	if ($::d_info && !defined($url)) {die;}
	
	if ( exists $infoCache{$url}) {
		$cacheEntryArray = $infoCache{$url};
	};

	# cache miss from memory, check the disk
	if (Slim::Utils::Prefs::get('usetagdatabase') &&
			!defined $cacheEntryArray &&
			exists $infoCacheDB{$url}) {
		$cacheEntryArray = $infoCacheDB{$url};
		$infoCache{$url} = $cacheEntryArray;
	}
	
	my $i = 0;
	foreach my $key (@infoCacheItems) {
		if ($cacheEntryArray->[$i]) {
			$cacheEntryHash->{$key} = $cacheEntryArray->[$i];
		}
		$i++;
	}

	return $cacheEntryHash;
}

sub updateCacheEntry {
	my $url = shift;
	my $cacheEntryHash = shift;
	my $cacheEntryArray;
	
	if ($::d_info && !defined($url)) { Slim::Utils::Misc::msg(%{$cacheEntryHash}); Slim::Utils::Misc::bt();  die "No URL specified for updateCacheEntry"; }
	if ($::d_info && !defined($cacheEntryHash)) {Slim::Utils::Misc::bt(); die "No cacheEntryHash for $url"; }

	if (!defined($url)) { return; }
	if (!defined($cacheEntryHash)) { return; }

	#$::d_info && Slim::Utils::Misc::bt();
	my $newsong = 0;
	
	if (Slim::Utils::Prefs::get('useinfocache')) {
		# if we've already got this in the cache, then merge the new over the old
		if (exists($infoCache{$url})) {
			my %merged = (%{cacheEntry($url)}, %{$cacheEntryHash});
			$cacheEntryHash = \%merged;
			$::d_info && Slim::Utils::Misc::msg("merging $url\n");
		} else {
			$newsong = 1;
		}
		my $i = 0;
		foreach my $key (@infoCacheItems) {
			my $val = $cacheEntryHash->{$key};
			if (defined $val) {
				$cacheEntryArray->[$i] = $val;
			}
			$::d_info && $cacheEntryHash->{$key} && 
				Slim::Utils::Misc::msg("updating $url with " . $cacheEntryHash->{$key} . " for $key\n");
			$i++;
		}

		$infoCache{$url} = $cacheEntryArray;
		if (Slim::Utils::Prefs::get('usetagdatabase')) {
			$infoCacheDB{$url} = $cacheEntryArray;
		}
		
		if ($newsong && isSong($url)) {
			$songCount++;
			my $time = $cacheEntryHash->{SECS};
			if ($time) {
				$total_time += $time;
			}
		}
	}
}

sub updateGenreMixCache {
        my $cacheEntry = shift;

        if (defined $cacheEntry->{MOODLOGIC_GENRE_MIXABLE} &&
                $cacheEntry->{MOODLOGIC_GENRE_MIXABLE} == 1) {
                $genreMixCache{$cacheEntry->{'GENRE'}} = $cacheEntry->{'MOODLOGIC_GENRE_ID'};
        }
}

sub updateArtistMixCache {
        my $cacheEntry = shift;

        if (defined $cacheEntry->{MOODLOGIC_ARTIST_MIXABLE} &&
            $cacheEntry->{MOODLOGIC_ARTIST_MIXABLE} == 1) {
            $artistMixCache{$cacheEntry->{'ARTIST'}} = $cacheEntry->{'MOODLOGIC_ARTIST_ID'};
        }
}

##################################################################################
# this routine accepts both our three letter content types as well as mime types.
# if neither match, we guess from the URL.
sub setContentType {
	my $url = shift;
	my $type = shift;
	
	my $cacheEntry = cacheEntry($url);

	$type = lc($type);
	
	if ($Slim::Music::Info::types{$type}) {
		# we got it
	} elsif ($Slim::Music::Info::mimeTypes{$type}) {
		$type = $Slim::Music::Info::mimeTypes{$type};
	} else {
		my $guessedtype = typeFromPath($url);
		if ($guessedtype ne 'unk') {
			$type = $guessedtype;
		}
	}
	
	$cacheEntry->{'CT'} = $type;

	updateCacheEntry($url, $cacheEntry);
	$::d_info && Slim::Utils::Misc::msg("Content type for $url is cached as $type\n");
}

sub setTitle {
	my $url = shift;
	my $title = shift;

	$::d_info && Slim::Utils::Misc::msg("Adding title $title for $url\n");
	$::d_info && Slim::Utils::Misc::bt();
	
	my $cacheEntry = cacheEntry($url);

	$cacheEntry->{'TITLE'} = $title;
	updateCacheEntry($url, $cacheEntry);
}

my $ncElemstring = "VOLUME|PATH|FILE|EXT|DURATION|LONGDATE|SHORTDATE|CURRTIME"; #non-cached elements
my $ncElems = qr/$ncElemstring/;

my $elemstring = (join '|',@infoCacheItems,$ncElemstring);
#		. "|VOLUME|PATH|FILE|EXT" #file data (not in infoCache)
#		. "|DURATION" # SECS expressed as mm:ss (not in infoCache)
#		. "|LONGDATE|SHORTDATE|CURRTIME" #current date/time (not in infoCache)
my $elems = qr/$elemstring/;


#TODO Add elements for size dependent items (volume bar, progress bar)
#my $sdElemstring = "VOLBAR|PROGBAR"; #size dependent elements (also not cached)
#my $sdElems = qr/$sdElemstring/;

sub elemLookup {
	my $element = shift;
	#my $file = shift;
	my $infoHashref = shift;
	my $value;

	$value = $infoHashref->{$element};

	return $value;
}

# used by infoFormat to add items not in infoCache to hash of info
sub addToinfoHash {
	my $infoHashref = shift;
	my $file = shift;
	my $str = shift;
	
	if ($str =~ /VOLUME|PATH|FILE|EXT/) {
		my ($volume, $path, $filename) = splitpath($file);
		$filename =~ s/\.([^\.]*?)$//;
		my $ext = $1;
		$infoHashref->{'VOLUME'} = $volume;
		$infoHashref->{'PATH'} = $path;
		$infoHashref->{'FILE'} = $filename;
		$infoHashref->{'EXT'} = $ext;
	}
	
	if ($str =~ /LONGDATE|SHORTDATE|CURRTIME/) {
		$infoHashref->{'LONGDATE'} = Slim::Utils::Misc::longDateF();
		$infoHashref->{'SHORTDATE'} = Slim::Utils::Misc::shortDateF();
		$infoHashref->{'CURRTIME'} = Slim::Utils::Misc::timeF();
	}
	
	if ($str =~ /DURATION/ && defined($infoHashref->{'SECS'})) {
		$infoHashref->{'DURATION'} = int($infoHashref->{'SECS'}/60) . ":" 
			. ((($infoHashref->{'SECS'}%60) < 10) ? ("0" . $infoHashref->{'SECS'}%60) : $infoHashref->{'SECS'}%60)
	}
	
	$infoHashref->{'FROM'} = string('FROM');
	$infoHashref->{'BY'} = string('BY'); 
}

#formats information about a file using a provided format string
sub infoFormat {
	no warnings; # this is to allow using null values with string concatenation, it only effects this procedure
	my $file = shift; # item whose information will be formatted
	my $str = shift; # format string to use
	my $safestr = shift; # format string to use in the event that after filling the first string, there is nothing left
	my $pos = 0; # keeps track of position within the format string
	
	if (!defined($file)) {
		return "";
	}
	
	my $infoRef = infoHash($file);
	
	if (!defined($infoRef)) {
		return "";
	}

	my %infoHash = %{$infoRef}; # hash of data elements not cached in the main repository

	if (!defined($str)) { #use a safe format string if none specified
		$str = 'TITLE';
	}
	if ($str =~ $ncElems) {
		addToinfoHash(\%infoHash,$file,$str);
	}

	#here is a breakdown of the following regex:
	#\G -> start at the current pos() for the string
	#(.*?)? -> match 0 or 1 instances of any string 0 or more characters in length (non-greedy),capture as $1
	#(?:=>(.*?)=>)? -> 0 or 1 instances of any string in a =>=> frame, capture as $2 (excluding =>=>)
	#(?:=>(.*?)=>)? -> same, captured as $3
	#($elems) -> match one of the precompiled list of allowed data elements, capture as $4
	#(?:<=(.*?)<=)? -> 0 or 1 instances of any string in a <=<= frame, capture as $5 (excluding <=<=)
	#(.*?)? -> 0 or 1 instances of any string, capture as $6
	#(?:<#(.*?)#>)? -> 0 or 1 instances of any string in a <##> frame, capture as $7 (excluding <##>)
	#($elems|(?:=>.*?=>)) -> either another data element or a =>=> frame in front of another data element, as $8 (includes =>=>)
	while ($str =~ s{\G(.*?)?(?:=>(.*?)=>)?(?:=>(.*?)=>)?($elems)(?:<=(.*?)<=)?(.*?)?(?:<#(.*?)#>)?($elems|(?:=>.*?=>))}
				{
					my $out = ''; #replacement string for this substitution
					#look up the value corresponding to the first data element
					my $value = elemLookup($4,\%infoHash);
					#if another data element comes next replace <##> frames with =>=> frames
					#otherwise leave off the frames
					my $frame = defined($8) ? "=>" : "";
					if (defined($value)) { #the data element had a value, so include all the separators
						#pos() is set to the first character of the match by the s/// function
						#so adjust it to be where we want the next s/// to start
						#$pos is used to hold the value of pos() that we want, because pos()
						#gets reset to 0 since we aren't using /g.  We aren't using /g because we need
						#do do some backtracking and that is not allowed all in one go.
						#we want the next replace to start at the beginning of either
						#the next data element or the =>=> frame preceding it
						$pos = pos($str) + length($1) + length($2) + length($3) + length($value);
						if (!(defined($5) || defined($7))) {
							#neither a <=<= or a <##> frame is present so treat a bare
							#separator like one framed with <##>
							$out = $1 . $2 . $3 . $value . $frame . $6 . $frame . $8;
						} else {
							#either <=<= or <##> was present, so always write out a bare separator
							#if no <##> was present, don't add a =>=> frame
							$out = $1 . $2 . $3 . $value . $5 . $6 . (defined($7) ? ($frame . $7 . $frame) : "") . $8;
							#we want the next replace to start at the beginning of either
							#the next data element or the =>=> frame preceding it
							$pos += length($5) + length($6);
						}
					} else { #the data element did not have a value, so collapse the string
						#initialize $pos
						$pos = pos($str);
						if (defined($2) || defined($3)) {
							#a =>=> frame exists so always write a preceding bare separator
							#which should only happen in the first iteration if ever
							$out = $1;
							$pos += length($1);
							if (defined($6)) {
								#the bare separator is always used if a <=<= or a <##> frame was present
								#otherwise since there was a =>=> frame preceding the missing element convert
								#a bare separator to a =>=>
								$out .= (defined($5) || defined($7)) ? $6 : $frame . $6 . $frame;
								$pos += (defined($5) || defined($7)) ? length($6) : 0;
							}
							if (defined($7)) {
								#since there was a =>=> frame preceding the missing element convert
								#the <##> separator to a =>=>
								$out .= $frame . $7 . $frame;
							}
						} else {
							#treat a non-zero length bare separator as a data element for the purpose of determining
							#whether to convert a bare separator or a <##> to a =>=>
							$out = "";
							if (defined($6)) {
								$out .= (defined($5) || defined($7)) ? $6 : (length($1) ? ($frame . $6 . $frame) : "");
								$pos += (defined($5) || defined($7)) ? length($6) : 0;
							}
							if (defined($7)) {
								$out .= (length($1) || length($6)) ? ($frame . $7 . $frame) : "";
							}
						}
						$out .= $8;
					}
					$out;
				}e) {
		# since we aren't using s///g we need to reset the string position after each pass
		pos($str) = $pos;
	}
	# reset the string position which the failed match set to 0
	pos($str) = $pos;
	#same regex as above, but the last element is the end of the string
	$str =~ s{\G(.*?)?(?:=>(.*?)=>)?(?:=>(.*?)=>)?($elems)(?:<=(.*?)<=)?(.*?)?(?:<#(.*?)#>)?$}
				{
					my $out = '';
					my $value = elemLookup($4,\%infoHash);
					if (defined($value)) {
						#fill with all the separators
						#no need to do the <##> conversion since this is the end of the string
						$out = $1 . $2 . $3 . $value . $5 . $6 . $7;
					} else {#value not defined
						#only use the bare separators if there were framed ones as well
						$out  = (defined($2) || defined($3)) ? $1 : "";
						$out .= (defined($5) || defined($7)) ? $6 : "";
					}
					$out;
				}e;
	if ($str eq "" && defined($safestr)) {
		# if there isn't anything left of the format string after the replacements, use the safe string, if supplied
		return infoFormat($file,$safestr);
	} else {
		$str=~ s/%([0-9a-fA-F][0-9a-fA-F])%/chr(hex($1))/eg;
	}

	return $str;
}

#
# if no ID3 information is available,
# use this to get a title, which is derived from the file path or URL.
# Also used to get human readable titles for playlist files and directories.
#
# for files, file URLs and directories:
#             Any ending .mp3 is stripped off and only last part of the path
#             is returned
# for HTTP URLs:
#             URL unescaping is undone.
#

sub plainTitle {
	my $file = shift;
	my $type = shift;

	my $title = "";

	$::d_info && Slim::Utils::Misc::msg("Plain title for: " . $file);

	if (isHTTPURL($file)) {
		$title = Slim::Web::HTTP::unescape($file);
	} else {
		if (isFileURL($file)) {
			$file = Slim::Utils::Misc::pathFromFileURL($file);
		}
		if ($file) {
			$title = (splitdir($file))[-1];
		}
		# directories don't get the suffixes
		if ($title && !($type && $type eq 'dir')) {
				$title =~ s/\.[^.]+$//;
		}
	}

	if ($title) {
		$title =~ s/_/ /g;
	}
	
	$::d_info && Slim::Utils::Misc::msg(" is " . $title . "\n");

	return $title;
}

# get a potentially client specifically formatted title.
sub standardTitle {
	my $client = shift;
	my $fullpath = shift;
	my $title;
	my $format;

	if (isITunesPlaylistURL($fullpath)) {
		$format = 'TITLE';
	} elsif (defined($client)) {
		#in array syntax this would be $titleFormat[$clientTitleFormat[$clientTitleFormatCurr]]
		#get the title format
		$format = Slim::Utils::Prefs::getInd("titleFormat"
				#at the array index of the client titleformat array
				,Slim::Utils::Prefs::clientGet($client, "titleFormat"
					#which is currently selected
					,Slim::Utils::Prefs::clientGet($client,'titleFormatCurr')));
	} else {
		#in array syntax this would be $titleFormat[$titleFormatWeb]
		$format = Slim::Utils::Prefs::getInd("titleFormat",Slim::Utils::Prefs::get("titleFormatWeb"));
	}
	
	$title = infoFormat($fullpath, $format, "TITLE");

	return $title;
}

#
# Return a structure containing the ID3 tag attributes of the given MP3 file.
#
sub infoHash {
	my $file = shift;

	if (!defined($file) || $file eq "") { 
		$::d_info && Slim::Utils::Misc::msg("trying to get infoHash on an empty file name\n");
		$::d_info && Slim::Utils::Misc::bt();
		return; 
	};
	
	my $item = cacheEntry($file);
	
	# we'll update the cache if we don't have a valid title in the cache
	if (!defined($item) || !exists($item->{'TAG'})) {
		$::d_info && Slim::Utils::Misc::msg("cache miss for $file\n");
		$::d_info && Slim::Utils::Misc::bt();
		$item = readTags($file)
	}
	
	return $item;
}

sub info {
	my $file = shift;
	my $tagname = shift;

	if (!defined($file) || $file eq "" || !defined($tagname)) { 
		$::d_info && Slim::Utils::Misc::msg("trying to get info on an empty file name\n");
		$::d_info && Slim::Utils::Misc::bt();
		return; 
	};
	
	my $item = cacheItem($file, $tagname);

	# we'll update the cache if we don't have a valid title in the cache
	if (!defined($item)) {
		# defer cover information until needed
		if ($tagname =~ /^(COVER|COVERTYPE)$/) {
			updateCoverArt($file, 'cover');
			$item = cacheItem($file, $tagname);
		# load up item information if we've never seen it or we haven't loaded the tags
		} elsif ($tagname =~ /^(THUMB|THUMBTYPE)$/) {
			updateCoverArt($file,'thumb');
			$item = cacheItem($file, $tagname);
		# load up item information if we've never seen it or we haven't loaded the tags
		} elsif ($tagname =~ /^(THUMB|THUMBTYPE)$/) {
			updateCoverArt($file,1);
			$item = cacheItem($file, $tagname);
		# load up item information if we've never seen it or we haven't loaded the tags
		} elsif (!exists($infoCache{$file}) || !cacheItem($file, 'TAG')) {
			$::d_info && Slim::Utils::Misc::bt();
			$::d_info && Slim::Utils::Misc::msg("cache miss for $file\n");
			$item = readTags($file)->{$tagname};
		}	
	}
	return $item;
}

sub trackNumber {
	my $file = shift;
	return (info($file,'TRACKNUM'));
}

sub cleanTrackNumber {
	my $tracknumber = shift;

	if (defined($tracknumber)) {
		#extracts the first digits only sequence then converts it to int
		$tracknumber =~ /(\d*)/;
		$tracknumber = $1 ? int($1) : undef;
	}
	
	return $tracknumber;
}

sub genre {
	my $file = shift;
	return (info($file,'GENRE'));
}

sub title {
	my $file = shift;
	return (info($file,'TITLE'));
}

sub artist {
	my $file = shift;
	return (info($file,'ARTIST'));
}

sub artistSort {
	my $file = shift;
	my $artistSort = info($file,'ARTISTSORT');
	if (!defined($artistSort)) {
		$artistSort = ignoreCaseArticles(artist($file));
	}
	return $artistSort;
}

sub albumSort {
	my $file = shift;
	my $albumSort = info($file,'ALBUMSORT');
	if (!defined($albumSort)) {
		$albumSort = ignoreCaseArticles(album($file));
	}
	return $albumSort;
}

sub titleSort {
	my $file = shift;
	my $titleSort = info($file,'TITLESORT');
	if (!defined($titleSort)) {
		$titleSort = ignoreCaseArticles(title($file));
	}
	return $titleSort;
}

sub composer {
	my $file = shift;
	return (info($file,'COMPOSER'));
}

sub band {
	my $file = shift;
	return (info($file,'BAND'));
}

sub album {
	my $file = shift;
	return (info($file,'ALBUM'));
}

sub year {
	my $file = shift;
	return (info($file,'YEAR'));
}

sub disc {
	my $file = shift;
	return (info($file,'DISC'));
}

sub discCount {
	my $file = shift;
	return (info($file,'DISCC'));
}

sub comment {
	my $file = shift;
	my $comment;
	my @comments;

	if (ref(info($file,'COMMENT')) eq 'ARRAY') {
		@comments = @{info($file,'COMMENT')};
	} else {
		@comments = (info($file,'COMMENT'));
	}
	# extract multiple comments and concatenate them
	if (@comments) {
		foreach my $c (@comments) {
			if ($c) {
				# ignore SoundJam CDDB comments
				if (
					$c =~ /SoundJam_CDDB_/ ||
					$c =~ /iTunes_CDDB_/ ||
					$c =~ /^\s*[0-9A-Fa-f]{8}(\+|\s)/
				) {
					#ignore
				} else {
					# put a slash between multiple comments.
					if ($comment) {
						$comment .= ' / ';
					}
					$c =~ s/^eng(.*)/$1/;
					$comment .= $c;
				}
			}
		}
	}
	return $comment;
}

sub duration {
	my $file = shift;
	my $secs = info($file,'SECS');

	if (defined $secs) {
		return sprintf('%s:%02s',int($secs / 60),$secs % 60);
	} else {
		return;
	}
}

sub durationSeconds {
	my $file = shift;
	return info($file,'SECS');
}

sub offset {
	my $file = shift;
	return info($file,'OFFSET');
}

sub size {
	my $file = shift;
	return info($file,'SIZE');
}

sub bitrate {
	my $file = shift;
	my $mode = (defined info($file,'VBR_SCALE')) ? 'VBR' : 'CBR';
	if (info($file,'BITRATE')) {
		return info($file,'BITRATE').Slim::Utils::Strings::string('KBPS').' '.$mode;
	} else {
		return;
	}
}

sub bitratenum {
	my $file = shift;
	return info($file,'BITRATE') * 1000;
}
sub samplerate {
	my $file = shift;
	return info($file,'RATE');
}

sub channels {
	my $file = shift;
	return info($file, 'CHANNELS');
}

# we cache whether we had success reading the cover art.
sub haveCoverArt {
	my $file = shift;
	return info($file, 'COVER');
}

sub haveThumbArt {
	my $file = shift;
	return info($file, 'THUMB');
}

sub coverArt {
	my $file = shift;
	my $art = shift || 'cover';
	my $image;

	$::d_info && Slim::Utils::Misc::msg("Cover Art ($art) for: $file\n");

	my ($body, $contenttype);

	if ( (($art eq 'cover') && haveCoverArt($file)) || 
	     (($art eq 'thumb') && haveThumbArt($file)) ) {
		($body, $contenttype) = readCoverArt($file,$art);
	}

 	return ($body, $contenttype);
}

sub tagVersion {
	my $file = shift;
	return info($file,'TAGVERSION');
};

sub cachePlaylist {
	my $path = shift;

	my $inforef = infoHash($path);

	$inforef->{'LIST'} = shift;
	my $age = shift;

	if (!defined($age)) { $age = Time::HiRes::time(); };
	$inforef->{'AGE'} = $age;

	updateCacheEntry($path, $inforef);
	
	$::d_info && Slim::Utils::Misc::msg("cached an " . (scalar @{$inforef->{'LIST'}}) . " item playlist for $path\n");
}

sub cachedPlaylist {
	my $path = shift;

	return info($path, 'LIST');
}

sub age {
	my $path = shift;
	return info($path, 'AGE');
}

sub filterPrep {
	my $pattern = shift;
	#the following transformations assume that the pattern provided uses * to indicate
	#matching any character 0 or more times, and that . ^ and $ are not escaped
	$pattern =~ s/\\([^\*]|$)/($1 eq "\\")? "\\\\" : $1/eg; #remove single backslashes except those before a *
	$pattern =~ s/([\.\^\$\(\)\[\]\{\}\|\+\?])/\\$1/g; #escape metachars (other than * or \) in $pattern {}[]()^$.|+?
	$pattern =~ s/^(.*)$/\^$1\$/; #add beginning and end of string requirements
	$pattern =~ s/(?<=[^\\])\*/\.\*/g; #replace * (unescaped) with .*
	return qr/$pattern/i;
}

sub filterPats {
	my ($inpats) = @_;
	my @outpats = ();
	foreach my $pat (@$inpats) {
		push @outpats, filterPrep(ignoreCaseArticles($pat));
	}
	return \@outpats;
}

sub filter {
	my ($patterns, $const, @items) = @_;
	if (!defined($patterns) || ! @{$patterns}) {
		return @items;
	}

	my @filtereditems;
	# Gross, but this seems to be a relevant optimization.
	if ($const eq '') {
		ITEM: foreach my $item (@items) {
			foreach my $regexpattern (@{$patterns}) {
				if ($item !~ $regexpattern) {
					next ITEM;
				}
			}
			push @filtereditems, $item;
		}
	  } else {
		ITEM: foreach my $item (@items) {
			my $item_const = $item . ' ' . $const;
			foreach my $regexpattern (@{$patterns}) {
				if ($item_const !~ $regexpattern) {
					next ITEM;
				}
			}
			push @filtereditems, $item;
		}
	}

	return @filtereditems;
}

sub filterHashByValue {
	my ($patterns, $hashref) = @_;
	if (!defined($hashref)) {
		return;
	}

	if (!defined($patterns) || ! @{$patterns}) {
		return keys %{$hashref};
	}
	my @filtereditems;
	my ($k,$v);
	ENTRY: while (($k,$v) = each %{$hashref}) {
		foreach my $pat (@{$patterns}) {
			if ($v !~ $pat) {
				next ENTRY;
			}
		}
		push @filtereditems, $k;
	}

	return @filtereditems;
}

# genres|artists|albums|songs(genre,artist,album,song)
#===========================================================================
# Return list of matching keys at the given level in the genre tree.  Each
# of the arguments is an array reference of file glob type patterns to match.
# In order to match, all the elements of the list must match at the given
# level of the genre tree.

sub genres {
	my $genre = shift;
	my $artist = shift;
	my $album = shift;
	my $song = shift;
	my $count = shift;
	$::d_info && Slim::Utils::Misc::msg("genres: $genre - $artist - $album - $song\n"	);

	my $genre_pats = filterPats($genre);
	my @genres = filter($genre_pats,"",keys %genreCache);
	
	if ($count) {
		return scalar @genres;
	} else {
		return fixCase(sortuniq(@genres));
	}
}

sub artists {
	my $genre = shift;
	my $artist = shift;
	my $album = shift;
	my $song = shift;
	my $count = shift;
	my @artists = ();
	$::d_info && Slim::Utils::Misc::msg("artists: $genre - $artist - $album - $song\n"	);

	my $genre_pats = filterPats($genre);
	my $artist_pats = filterPats($artist);

	if (defined($album) && scalar(@$album) && $$album[0]) {
		my $album_pats = filterPats($album);
		foreach my $g (filter($genre_pats,"",keys %genreCache)) {
			foreach my $art (filter($artist_pats,"",keys %{$genreCache{$g}})) {
				foreach my $alb (filter($album_pats,"",keys %{$genreCache{$g}{$art}})) {
					push @artists, $art;				
				}
			}
		}
	} else {
		foreach my $g (filter($genre_pats,"",keys %genreCache)) {
			push @artists, filter($artist_pats,"",keys %{$genreCache{$g}});
		}
	}
	if ($count) {
		return scalar @artists;
	} else {
		return fixCase(sortuniq_ignore_articles(@artists));
	}
}

sub albums {
	my $genre = shift;
	my $artist = shift;
	my $album = shift;
	my $song = shift;
	my $count = shift;
	my @albums = ();
	$::d_info && Slim::Utils::Misc::msg("albums: $genre - $artist - $album - $song\n"	);

	my $genre_pats = filterPats($genre);
	my $artist_pats = filterPats($artist);
	my $album_pats = filterPats($album);

	foreach my $g (filter($genre_pats,"",keys %genreCache)) {
		foreach my $art (filter($artist_pats,"",keys %{$genreCache{$g}})) {
			if (Slim::Utils::Prefs::get("artistinalbumsearch")) {
				push @albums, filter($album_pats,$art,keys %{$genreCache{$g}{$art}});
			}
			else {
				push @albums, filter($album_pats,"",keys %{$genreCache{$g}{$art}});
			}
		::idleStreams();
		}
	}
	if ($count) {
		return scalar(@albums);
	} else {
 		return fixCase(sortuniq_ignore_articles(@albums));
 	}
}


# return all songs for a given genre, artist, and album
sub songs {
	my $genre = shift;
	my $artist = shift;
	my $album = shift;
	my $track = shift;
	my $sortbytitle = shift;
	
	my $multalbums = (scalar(@$album) == 1 && $album->[0] !~ /\*/  && (!defined($artist->[0]) || $artist->[0] eq '*'));
	my $tracksort = !$multalbums && !$sortbytitle;
	
	my $genre_pats = filterPats($genre);
	my $artist_pats = filterPats($artist);
	my $album_pats = filterPats($album);
	my $track_pats = filterPats($track);

	my @alltracks = ();

	$::d_info && Slim::Utils::Misc::msg("songs: $genre - $artist - $album - $track\n"	);
	foreach my $g (sortIgnoringCase(filter($genre_pats,'',keys %genreCache))) {
		foreach my $art (sortIgnoringCase(filter($artist_pats,'',keys %{$genreCache{$g}}))) {
			foreach my $alb (sortIgnoringCase(filter($album_pats,'',keys %{$genreCache{$g}{$art}}))) {
				my %songs = ();
				foreach my $trk (values %{$genreCache{$g}{$art}{$alb}}) {
					$songs{$trk} = ignoreCaseArticles(title($trk));
				}
				if ($tracksort) {
					push @alltracks, sortByTrack(filterHashByValue($track_pats,\%songs));
				} else {
					push @alltracks, filterHashByValue($track_pats,\%songs);
				}
			}
		::idleStreams();
		}
	}

	# remove duplicate tracks
	my %seen = ();
	my @uniq = ();
	
	foreach my $item (@alltracks) {
		push(@uniq, $item) unless (!defined($item) || ($item eq '') || $seen{ignoreCaseArticles($item)}++);
	}
		
	if ($sortbytitle && $sortbytitle ne 'count') {		

		@uniq =  sortByTitles(@uniq);
	# if we are getting a specific album with an unspecific artist, re-sort the tracks
	} elsif ($multalbums) {
		# if there are duplicate track numbers, then sort as multiple albums
		my $duptracknum = 0;
		my @seen = ();
		foreach my $item (@uniq) {
			my $trnum = trackNumber($item);
			if ($trnum && $seen[$trnum]) {
				$duptracknum = 1;
				last;
			}
			$seen[$trnum]++;
		}
		if ($duptracknum) {
			@uniq =  sortByTrack(@uniq);
		} else {
			@uniq =  sortByAlbum(@uniq);
		}
	}
	if ($sortbytitle && $sortbytitle eq 'count') {
		return scalar @uniq;
	} else {
	 	return @uniq;
	 }
}

my $articles;

sub sortByTrack {
	$articles = undef;
	#get info for items and ignoreCaseArticles it
	my @sortinfo =  map {getInfoForSort($_)} @_;
	#return the first element of each entry in the sorted array
	return map {$_->[0]} sort sortByTrackAlg @sortinfo;
}

sub sortByAlbum {
	$articles = undef;
	#get info for items and ignoreCaseArticles it
	my @sortinfo =  map {getInfoForSort($_)} @_;
	#return an array of first elements of the entries in the sorted array
	return map {$_->[0]} sort sortByAlbumAlg @sortinfo;
}

sub sortByTitles {
	$articles = undef;
	#get info for items and ignoreCaseArticles it
	my @sortinfo =  map {getInfoForSort($_)} @_;
	#return an array of first elements of the entries in the sorted array
	return map {$_->[0]} sort sortByTitlesAlg @sortinfo;
}

sub ignoreArticles {
	my $item = shift;
	if ($item) {
		if (!defined($articles)) {
			$articles =  Slim::Utils::Prefs::get("ignoredarticles");
			# allow a space seperated list in preferences (easier for humans to deal with)
			$articles =~ s/\s+/|/g;
		}
		
		#set up array for sorting items without leading articles
		$item =~ s/^($articles)\s+//i;
	}
	return $item;
}

#algorithm for sorting by just titles
sub sortByTitlesAlg ($$) {
	my $j = $_[0];
	my $k = $_[1];

	#compare titles
	return $j->[5] cmp $k->[5];
}


#Sets up an array entry for performing complex sorts
sub getInfoForSort {
	my ($item) = @_;
	return [$item
		,isList($item)
		,artistSort($item)
		,albumSort($item)
		,trackNumber($item)
		,titleSort($item)];
}	

#algorithm for sorting by Artist, Album, Track
sub sortByTrackAlg ($$) {
	my $j = $_[0];
	my $k = $_[1];

	my $result;
	#If both lists compare titles
	if ($j->[1] && $k->[1]) {
		#compare titles
		if (defined($j->[5]) && defined($k->[5])) {
			return $j->[5] cmp $k->[5];
		} elsif (defined($j->[5])) {
			return -1;
		} elsif (defined($k->[5])) {
			return 1;
		} else {
			return 0;
		}
	}
	
	#compare artists
	if (defined($j->[2]) && defined($k->[2])) {
		$result = $j->[2] cmp $k->[2];
		if ($result) { return $result; }
	} elsif (defined($j->[2])) {
		return -1;
	} elsif (defined($k->[2])) {
		return 1;
	}
	
	#compare albums
	if (defined($j->[3]) && defined($k->[3])) {
		$result = $j->[3] cmp $k->[3];
		if ($result) { return $result; }
	} elsif (defined($j->[3])) {
		return -1;
	} elsif (defined($k->[3])) {
		return 1;
	}
	
	#compare track numbers
	if ($j->[4] && $k->[4]) {
		$result = $j->[4] <=> $k->[4];
		if ($result) { return $result; }
	} elsif ($j->[4]) {
		return -1;
	} elsif ($k->[4]) {
		return 1;
	}

	#compare titles
	return $j->[5] cmp $k->[5];
}

#algorithm for sorting by Album, Track
sub sortByAlbumAlg ($$) {
	my $j = $_[0];
	my $k = $_[1];

	my $result;
	#If both are lists compare titles
	if ($j->[1] && $k->[1]) { 
		#compare titles
		if (defined($j->[5]) && defined($k->[5])) {
			return $j->[5] cmp $k->[5];
		} elsif (defined($j->[5])) {
			return -1;
		} elsif (defined($k->[5])) {
			return 1;
		} else {
			return 0;
		}
	}
	
	#compare albums
	if (defined($j->[3]) && defined($k->[3])) {
		$result = $j->[3] cmp $k->[3];
		if ($result) { return $result; }
	} elsif (defined($j->[3])) {
		return -1;
	} elsif (defined($k->[3])) {
		return 1;
	}
	
	#compare track numbers
	if ($j->[4] && $k->[4]) {
		$result = $j->[4] <=> $k->[4];
		if ($result) { return $result; }
	} elsif ($j->[4]) {
		return -1;
	} elsif ($k->[4]) {
		return 1;
	}

	#compare titles
	return $j->[5] cmp $k->[5];
}

sub fileName {
	my $j = shift;

	if (isFileURL($j)) {
		$j = Slim::Utils::Misc::pathFromFileURL($j);
		if ($j) {
			$j = (splitdir($j))[-1];
		}
	} elsif (isHTTPURL($j)) {
		$j = Slim::Web::HTTP::unescape($j);
	} else {
		$j = (splitdir($j))[-1];
	}
	return $j;
}


sub sortFilename {
	#build the sort index
	my @nocase = map {ignoreCaseArticles(fileName($_))} @_;
	#return the input array sliced by the sorted array
	return @_[sort {$nocase[$a] cmp $nocase[$b]} 0..$#_];
}


sub songPath {
	my $genre = shift;
	my $artist = shift;
	my $album = shift;
	my $track = shift;

	return $genreCache{ignoreCaseArticles($genre)}{ignoreCaseArticles($artist)}{ignoreCaseArticles($album)}{ignoreCaseArticles($track)};
}

sub isFragment {
	my $fullpath = shift;
	
	my $is = 0;
	if (isURL($fullpath)) {
		my $anchor = Slim::Utils::Misc::anchorFromURL($fullpath);
		if ($anchor && $anchor =~ /([\d\.]+)-([\d\.]+)/) {
			return ($1, $2);
		}
	}
}

sub readTags {
	my $file = shift;
	my ($track, $song, $artistName,$albumName);
	my $filepath;
	my $type;
	my $tempCacheEntry;

	if (!defined($file) || $file eq "") { return; };

	# get the type without updating the cache
	$type = typeFromPath($file);
	if (	$type eq 'unk' && 
			exists($infoCache{$file}) && 
			exists(cacheEntry($file)->{'CT'})
		) {
		$type = cacheEntry($file)->{'CT'};
	}


	$::d_info && Slim::Utils::Misc::msg("Updating cache for: " . $file . "\n");
	
	if (isSong($file, $type) ) {
		if (isHTTPURL($file)) {
			# if it's an HTTP URL, guess the title from the the last part of the URL,
			# and don't bother with the other parts
			if (!defined(cacheItem($file, 'TITLE'))) {
				$::d_info && Slim::Utils::Misc::msg("Info: no title found, calculating title from url for $file\n");
				$tempCacheEntry->{'TITLE'} = plainTitle($file, $type);
			}
		} else {
			my $anchor;
			if (isFileURL($file)) {
				$filepath = Slim::Utils::Misc::pathFromFileURL($file);
				$anchor = Slim::Utils::Misc::anchorFromURL($file);
			} else {
				$filepath = $file;
			}

			# we only know how to extract ID3 information from file paths and file URLs.
			if ($type=~/^mp[23]$/) {
				my $info;
				# get the MP3 tag information
				$tempCacheEntry = MP3::Info::get_mp3tag($filepath);
				# get the MP3 info information
				$info = MP3::Info::get_mp3info($filepath);
				# put everything we've got into $tempCacheEntry
				if ($info && $tempCacheEntry) {
					%{$tempCacheEntry} = (%{$tempCacheEntry}, %{$info});
				} elsif ($info && !$tempCacheEntry) {
					$tempCacheEntry = $info;
				}
			} elsif ($type eq "ogg") {
				# get the Ogg comments
				$tempCacheEntry = Slim::Formats::Ogg::get_oggtag($filepath);
			} elsif ($type eq "flc") {
				# get the FLAC comments
				$tempCacheEntry = Slim::Formats::FLAC::get_flactag($filepath);
			} elsif ($type eq "wav") {
				# get the Wav comments
				$tempCacheEntry = Slim::Formats::Wav::get_wavtag($filepath);
			} elsif ($type eq "aif") {
				$tempCacheEntry = Slim::Formats::AIFF::get_aifftag($filepath);		
			} elsif ($type eq "mov") {
				$tempCacheEntry = Slim::Formats::Movie::get_movietag($filepath);		
			}

			$::d_info && !defined($tempCacheEntry) && Slim::Utils::Misc::msg("Info: no tags found for $filepath\n");

			
			if ($tempCacheEntry->{'TRACKNUM'}) {
				$tempCacheEntry->{'TRACKNUM'} = cleanTrackNumber($tempCacheEntry->{'TRACKNUM'});
			}
			
			if ($tempCacheEntry->{'SET'}) {
				my $discNum = $tempCacheEntry->{'SET'};
				my $discCount;
				
				$discNum =~ /(\d+)\/(\d+)/;
				
				if ($1) {
					$discNum = $1;
				}
				
				$tempCacheEntry->{'DISC'} = $discNum;
				
				if ($2) {
					$discCount = $2;
					$tempCacheEntry->{'DISCC'} = $discCount;
				}
				
				my $discWord = string('DISC');
				
				if ($discNum && $tempCacheEntry->{'ALBUM'} && ($tempCacheEntry->{'ALBUM'} !~ /(${discWord})|(Disc)\s+[0-9]+/i)) {
					# disc 1 of 1 isn't interesting
					if (!($discCount && $discNum && $discCount == 1 && $discNum == 1)) {
						# Add space to handle > 10 album sets and sorting. Is suppressed in the HTML.
						if ($discCount && $discCount > 9 && $discNum < 10) { $discNum = ' ' . $discNum; };
							
						$tempCacheEntry->{'ALBUM'} = $tempCacheEntry->{'ALBUM'} . " ($discWord $discNum";
						if ($discCount) {
							$tempCacheEntry->{'ALBUM'} .= " ". string('OF') . " $discCount)";
						} else {
							$tempCacheEntry->{'ALBUM'} .= ")";
						}
					}
				}
			}
			
			if (!$tempCacheEntry->{'TITLE'} && !defined(cacheItem($file, 'TITLE'))) {
				$::d_info && Slim::Utils::Misc::msg("Info: no title found, using plain title for $file\n");
				$tempCacheEntry->{'TITLE'} = plainTitle($file, $type);					
			}

			# fix the genre
			if (defined($tempCacheEntry->{'GENRE'}) && $tempCacheEntry->{'GENRE'} =~ /^\((\d+)\)$/) {
				# some programs (SoundJam) put their genres in as text digits surrounded by parens.
				# in this case, look it up in the table and use the real value...
				if (defined($MP3::Info::mp3_genres[$1])) {
					$tempCacheEntry->{'GENRE'} = $MP3::Info::mp3_genres[$1];
				}
			}

			# cache the file size & date
			$tempCacheEntry->{'FS'} = -s $filepath;					
			$tempCacheEntry->{'AGE'} = (stat($filepath))[9];
			
			# rewrite the size, offset and duration if it's just a fragment
			if ($anchor && $anchor =~ /([\d\.]+)-([\d\.]+)/ && $tempCacheEntry->{'SECS'}) {
				my $start = $1;
				my $end = $2;
				
				my $duration = $end - $start;
				my $byterate = $tempCacheEntry->{'SIZE'} / $tempCacheEntry->{'SECS'};
				my $header = $tempCacheEntry->{'OFFSET'};
				my $startbytes = int($byterate * $start);
				my $endbytes = int($byterate * $end);
				
				$tempCacheEntry->{'OFFSET'} = $header + $startbytes;
				$tempCacheEntry->{'SIZE'} = $endbytes - $startbytes;
				$tempCacheEntry->{'SECS'} = $duration;
				
				$::d_info && Slim::Utils::Misc::msg("readTags: calculating duration for anchor: $duration\n");
				$::d_info && Slim::Utils::Misc::msg("readTags: calculating header $header, startbytes $startbytes and endbytes $endbytes\n");
			}

			# cache the content type
			$tempCacheEntry->{'CT'} = $type;
			
			updateGenreCache($file,$tempCacheEntry);
			
			if (exists($tempCacheEntry->{'ARTISTSORT'})) {
				$tempCacheEntry->{'ARTISTSORT'} = ignoreCaseArticles($tempCacheEntry->{'ARTISTSORT'});
				
				if (exists($tempCacheEntry->{'ARTIST'})) { 
					$sortCache{ignoreCaseArticles($tempCacheEntry->{'ARTIST'})} = $tempCacheEntry->{'ARTISTSORT'};
				};
			};
			
			if (exists($tempCacheEntry->{'ALBUMSORT'})) {
				$tempCacheEntry->{'ALBUMSORT'} = ignoreCaseArticles($tempCacheEntry->{'ALBUMSORT'});
				
				if (exists($tempCacheEntry->{'ALBUM'})) { 
					$sortCache{ignoreCaseArticles($tempCacheEntry->{'ALBUM'})} = $tempCacheEntry->{'ALBUMSORT'};
				};
			};
			
			if (exists($tempCacheEntry->{'TITLESORT'})) {
				$tempCacheEntry->{'TITLESORT'} = ignoreCaseArticles($tempCacheEntry->{'TITLESORT'});

				if (exists($tempCacheEntry->{'TITLE'})) { 
					$sortCache{ignoreCaseArticles($tempCacheEntry->{'TITLE'})} = $tempCacheEntry->{'TITLESORT'};
				};
			};
			
		} 
	} else {
		if (!defined(cacheItem($file, 'TITLE'))) {
			my $title = plainTitle($file, $type);
			$tempCacheEntry->{'TITLE'} = $title;
		}
	}
	
	if (!defined($tempCacheEntry->{'CT'})) {
		$tempCacheEntry->{'CT'} = $type;
	}
	
	# note that we've read in the tags.
	$tempCacheEntry->{'TAG'} = 1;
	
	updateCacheEntry($file, $tempCacheEntry);

	return $tempCacheEntry;
}

sub getImageContent {
	my $path = shift;
	my $contentref;

	if (open (TEMPLATE, $path)) { 
		binmode(TEMPLATE);
		$$contentref=join('',<TEMPLATE>);
		close TEMPLATE;
	} else {
		$::d_info && Slim::Utils::Misc::msg("Couldn't open image $path\n");
	}
	
	defined($$contentref) && length($$contentref) || $::d_http && Slim::Utils::Misc::msg("Image File empty or couldn't read: $path\n");
	return $$contentref;
}

sub readCoverArt {
	use bytes;
	my $fullpath = shift;
	my $filepath;
	my $image = shift || 'cover';

	my $body;	
	my $contenttype;
	
	$::d_info && Slim::Utils::Misc::msg("Updating image for $fullpath\n");
	
	if (isFileURL($fullpath)) {
		$filepath = Slim::Utils::Misc::pathFromFileURL($fullpath);
	} else {
		$filepath = $fullpath;
	}

	if (isSong($filepath) && isFile($filepath)) {
		
		my $file = Slim::Utils::Misc::virtualToAbsolute($filepath);
		
		if (isMP3($filepath) || isWav($filepath)) {
			$::d_info && Slim::Utils::Misc::msg("Looking for image in ID3 tag\n");
				
			my $tags = MP3::Info::get_mp3tag($file, 2, 1);
			if ($tags) {
				# look for ID3 v2.2 picture
				my $pic = $tags->{'PIC'};
				if (defined($pic)) {
					if (ref($pic) eq 'ARRAY') {
						$pic = (@$pic)[0];
					}					
					my ($encoding, $format, $picturetype, $description) = unpack 'Ca3CZ*', $pic;
					my $len = length($description) + 1 + 5;
					if ($encoding) { $len++; } # skip extra terminating null if unicode
					
					if ($len < length($pic)) {		
						my ($data) = unpack "x$len A*", $pic;
						
						$::d_info && SliMP3::Misc::msg( "PIC format: $format length: " . length($pic) . "\n");

						if ($format eq 'PNG') {
								$contenttype = 'image/png';
								$body = $data;
						} elsif ($format eq 'JPG') {
								$contenttype = 'image/jpeg';
								$body = $data;
						}
					}
				} else {
					# look for ID3 v2.3 picture
					$pic = $tags->{'APIC'};
					if (defined($pic)) {
						# if there are more than one pictures, just grab the first one.
						if (ref($pic) eq 'ARRAY') {
							$pic = (@$pic)[0];
						}					
						my ($encoding, $format) = unpack 'C Z*', $pic;
						my $len = length($format) + 2;
						
						my ($picturetype, $description) = unpack "x$len C Z*", $pic;
						$len += 1 + length($description) + 1;
						if ($encoding) { $len++; } # skip extra terminating null if unicode
						
						my ($data) = unpack"x$len A*", $pic;
						
						$::d_info && Slim::Utils::Misc::msg( "APIC format: $format length: " . length($data) . "\n");

						$contenttype = $format;
						$body = $data;
					}
				}
			}
		}	
		
		if ($body) {
				
			# iTunes sometimes puts PNG images in and says they are jpeg
			if ($body =~ /^\x89PNG\x0d\x0a\x1a\x0a/) {
				$contenttype = 'image/png';
			}
			
			# jpeg images must start with ff d8 ff e0 or they ain't jpeg, sometimes there is junk before.
			if ($contenttype && $contenttype eq 'image/jpeg')	{
				$body =~ s/^.*?\xff\xd8\xff\xe0/\xff\xd8\xff\xe0/;
			}
			
		} else {
			my @components = splitdir($file);
			pop @components;
			$::d_info && Slim::Utils::Misc::msg("Looking for image files\n");

			my @filestotry = ();

			if ($image eq 'thumb') {
				if (Slim::Utils::Prefs::get('coverThumb')) { push @filestotry, Slim::Utils::Prefs::get('coverThumb'); }
				push @filestotry, ('thumb.jpg', 'albumartsmall.jpg', 'cover.jpg',  'folder.jpg', 'album.jpg');
			} else {
				if (Slim::Utils::Prefs::get('coverArt')) { push @filestotry, Slim::Utils::Prefs::get('coverArt'); }
				push @filestotry, ('cover.jpg', 'albumartsmall.jpg', 'folder.jpg', 'album.jpg', 'thumb.jpg');
			}
									
			foreach my $file (@filestotry) {
				$file = catdir(@components, $file);
				$body = getImageContent($file);
				if ($body) {
					$::d_info && Slim::Utils::Misc::msg("Found image file: $file\n");
					$contenttype = mimeType($file);
					last;
				}
			}
		}
 	}
	return ($body, $contenttype);
}

sub updateCoverArt {
	my $fullpath = shift;
	my $type = shift || 'cover';
	my $body;	
	my $contenttype;
	
	($body, $contenttype) = readCoverArt($fullpath, $type);
	 	
 	my $info;
 	
 	if (defined($body)) {
 		if ($type eq 'cover') {
 			$info->{'COVER'} = '1';
 		} elsif ($type eq 'thumb') {
 			$info->{'THUMB'} = '1';
 		}
 	} else {
		if ($type eq 'cover') {
 			$info->{'COVER'} = '0';
 		} elsif ($type eq 'thumb') {
 			$info->{'THUMB'} = '0';
 		}
 	}
 		
 	if (defined($contenttype)) {
 		if ($type eq 'cover') {
 			$info->{'COVERTYPE'} = '1';
 		} elsif ($type eq 'thumb') {
 			$info->{'THUMBTYPE'} = '1';
 		}
 	} else {
		if ($type eq 'cover') {
 			$info->{'COVERTYPE'} = '0';
 		} elsif ($type eq 'thumb') {
 			$info->{'THUMBTYPE'} = '0';
 		}
 	}

 	$::d_info && $body && Slim::Utils::Misc::msg("Got image!\n");

 	updateCacheEntry($fullpath, $info);
}

sub updateGenreCache {
	my $file = shift;
	my $cacheEntry = shift;

	# cache songs  uniquely
	my $genre = $cacheEntry->{'GENRE'};
	if (!defined ($genre) || !$genre) {
		$genre = string('NO_GENRE');
	}

	my $artist = $cacheEntry->{'ARTIST'};
	if (!defined ($artist) || !$artist) {
		$artist = string('NO_ARTIST');
	}

	my $album = $cacheEntry->{'ALBUM'};
	if (!defined ($album) || !$album) {
		$album = string('NO_ALBUM');
	}
	
	my $track = cleanTrackNumber($cacheEntry->{'TRACKNUM'});

	if (!$track) {
		# we always have a title
		$track = $cacheEntry->{'TITLE'};
		if (!defined ($track) || !$track) {
			$track = string('NO_TITLE');
		}
	}
	my $genreCase = ignoreCaseArticles($genre);
	my $artistCase = ignoreCaseArticles($artist);
	my $albumCase = ignoreCaseArticles($album);
	my $trackCase = ignoreCaseArticles($track);
	
	$genreCache{$genreCase}{$artistCase}{$albumCase}{$trackCase} = $file;

	$caseCache{$genreCase} = $genre;
	$caseCache{$artistCase} = $artist;
	$caseCache{$albumCase} = $album;
	$caseCache{$trackCase} = $track;

	if (Slim::Utils::Prefs::get('composerInArtists')) {
		my $composer = $cacheEntry->{'COMPOSER'};	
		if ($composer) { 
			my $composerCase = ignoreCaseArticles($composer);
			$genreCache{$genreCase}{$composerCase}{$albumCase}{$trackCase} = $file;
			$caseCache{$composerCase} = $composer; 
		}
		
		my $band = $cacheEntry->{'BAND'};	
		if ($band) { 
			my $bandCase = ignoreCaseArticles($band);
			$genreCache{$genreCase}{$bandCase}{$albumCase}{$trackCase} = $file;
			$caseCache{$bandCase} = $band; 
		}
	}
		
	$::d_info && Slim::Utils::Misc::msg("updating genre cache with: $genre - $artist - $album - $track\n--- for:$file\n");
}

sub fileLength {
	my $file = shift;
	return (info($file,'FS'));
}

sub isFile {
	my $fullpath = shift;

	$fullpath !~ /\.(?:mp2|mp3|m3u|pls|ogg|cue|wav|aiff|aif|m4a|mov|flac)$/i && return 0;

	my $stat = (-f $fullpath && -r $fullpath ? 1 : 0);

	$::d_info && Slim::Utils::Misc::msgf("isFile(%s) == %d\n", $fullpath, (1 * $stat));

	return $stat;
}

sub isFileURL {
	my $url = shift;

	return (defined($url) && ($url =~ /^file:\/\//i));
}

sub isITunesPlaylistURL { 
	my $url = shift;

	return (defined($url) && ($url =~ /^itunesplaylist:/i));
}

sub isHTTPURL {
	my $url = shift;

	return (defined($url) && ($url =~ /^(http|icy):\/\//i));
}

sub isURL {
	my $url = shift;

	return (defined($url) && ($url =~ /^[a-z]{2,}:/i) );
}

sub isType {
	my $fullpath = shift;
	my $testtype = shift;
	my $type = contentType($fullpath);
	if ($type && ($type eq $testtype)) {
		return 1;
	} else {
		return 0;
	}
}

sub isWinShortcut {
	my $fullpath = shift;
	my $type = contentType($fullpath);
	return ($type && ($type eq 'lnk'));
}

sub isMP3 {
	my $fullpath = shift;
	my $type = contentType($fullpath);
	return ($type && (($type eq 'mp3') || ($type eq 'mp2')));
}

sub isOgg {
	my $fullpath = shift;
	my $type = contentType($fullpath);
	return ($type && ($type eq 'ogg'));
}

sub isWav {
	my $fullpath = shift;
	my $type = contentType( $fullpath);
	return( $type && ( $type eq 'wav'));
}

sub isMOV {
	my $fullpath = shift;
	my $type = contentType( $fullpath);
	return( $type && ( $type eq 'mov'));
}

sub isAIFF {
	my $fullpath = shift;
	my $type = contentType( $fullpath);
	return( $type && ( $type eq 'aif'));
}

sub isSong {
	my $fullpath = shift;
	my $type = shift;
	if (!defined($type)) {
		$type = contentType($fullpath);
	}
	return ($type && (($type eq 'mp3') || 
					  ($type eq 'mp2') || 
					  ($type eq 'mov') || 
					  ($type eq 'flc') || 
					  ($type eq 'ogg') || 
					  ($type eq 'wav') || 
					  ($type eq 'aif')));
}

sub isDir {
	my $fullpath = shift;
	my $type = contentType($fullpath);
	return ($type && ($type eq 'dir'));
}

sub isM3U {
	my $fullpath = shift;
	my $type = contentType($fullpath);
	return ($type && ($type eq 'm3u'));
}

sub isPLS {
	my $fullpath = shift;
	my $type = contentType($fullpath);
	return ($type && ($type eq 'pls'));
}

sub isCUE {
	my $fullpath = shift;
	my $type = contentType($fullpath);
	return ($type && ($type eq 'cue'));
}

sub isKnownType {
	my $fullpath = shift;
	my $type = contentType($fullpath);
	return !(!$type || ($type eq 'unk'));
}

sub isList {
	my $fullpath = shift;
	my $is = 0;

	my $type = contentType($fullpath);
	return ($type && ( $type eq 'dir' || $type eq 'm3u' || $type eq 'pls' || $type eq 'cue' || $type eq 'lnk' || $type eq 'itu'));

# -- inlined!
#	if (isPlaylist($fullpath) ||
#		isDir($fullpath) ||
#		isWinShortcut($fullpath)
#	) {
#		$is = 1;
#	}
#
#	$::d_info && Slim::Utils::Misc::msgf("isList(%s) == %d\n", $fullpath, $is );
#
#	return $is;
}

sub isPlaylist {
	my $fullpath = shift;

	my $type = contentType($fullpath);
	return ($type && ( $type eq 'm3u' || $type eq 'pls' || $type eq 'cue' || $type eq 'itu'));

# -- inlined!
#	my $is = 0;
#	
#	if (isM3U($fullpath) ||
#		isPLS($fullpath) ||
#		isCUE($fullpath) ||
#		isITunesPlaylistURL($fullpath)) {
#		$is = 1;
#	}
#
#	$::d_info && Slim::Utils::Misc::msgf("isPlaylist(%s) == %d\n", $fullpath, $is );
#
#	return $is;
}

sub isSongMixable {
        my $file = shift;
        return info($file,'MOODLOGIC_SONG_MIXABLE');
}

sub isArtistMixable {
        my $artist = shift;
        return defined $artistMixCache{$artist} ? 1 : 0;
}

sub isGenreMixable {
        my $genre = shift;
        return defined $genreMixCache{$genre} ? 1 : 0;
}

sub moodLogicSongId {
        my $file = shift;
        return info($file,'MOODLOGIC_SONG_ID');
}

sub moodLogicArtistId {
        my $artist = shift;
        return $artistMixCache{$artist};
}

sub moodLogicGenreId {
        my $genre = shift;
        return $genreMixCache{$genre};
}

sub mimeType {
	my $file = shift;
	my $contentType = contentType($file);
	foreach my $mt (keys %Slim::Music::Info::mimeTypes) {
		if ($contentType eq $Slim::Music::Info::mimeTypes{ $mt }) {
			return $mt;
		}
	}
	return undef;
};

sub contentType {
	my $file = shift;
	return (info($file,'CT'));
}

sub typeFromSuffix {
	my $path = shift;
	my $defaultType = shift || 'unk';
	
	my $type;
	
	if (defined($path)) {
		if ($path =~ /\.([^.]+)$/) {
			my $suffix = lc($1);
			$type = $Slim::Music::Info::suffixes{$suffix};
		}
	}
	if (!defined($type)) { $type = $defaultType; }

	return $type;
}

sub typeFromPath {
	my $fullpath = shift;
	my $defaultType = shift || 'unk';
	my $type;

	if (defined($fullpath) && $fullpath ne "" && $fullpath !~ /\x00/) {
		if (isHTTPURL($fullpath)) {
			$type = typeFromSuffix($fullpath, $defaultType);
		} elsif ( $fullpath =~ /^([a-z]+:)/ && defined($Slim::Music::Info::suffixes{$1})) {
			$type = $Slim::Music::Info::suffixes{$1};
		} else {
			my $filepath;

			if (isFileURL($fullpath)) {
				$filepath = Slim::Utils::Misc::pathFromFileURL($fullpath);
				$::d_info && Slim::Utils::Misc::msg("Converting $fullpath to $filepath\n");
			} else {
				$filepath = $fullpath;
			}

#			$filepath = Slim::Utils::Misc::fixPath($filepath);
			if (defined($filepath) && $filepath ne "") {
				if (-f $filepath) {
					if ($filepath =~ /\.lnk$/i && Slim::Utils::OSDetect::OS() eq 'win') {
						require Win32::Shortcut;
						if ((Win32::Shortcut->new($filepath)) ? 1 : 0) {
							$type = 'lnk';
						}
					} else {
						$type = typeFromSuffix($filepath, $defaultType);
					}
				} elsif (-d $filepath) {
					$type = 'dir';
				} else {
					#file doesn't exist, go ahead and do typeFromSuffix
					$type = typeFromSuffix($filepath, $defaultType);
				}
			}
		}
	}
	
	if (!defined($type)) {
		$type = $defaultType;
	}

	$::d_info && Slim::Utils::Misc::msg("$type file type for $fullpath\n");
	return $type;
}

sub matchCase {
	my $s = shift;
	return undef unless defined($s);
	# Upper case and fold latin1 diacritical characters into their plain versions, surprisingly useful.
 	$s =~ tr{abcdefghijklmnopqrstuvwxyz¿¡¬√ƒ≈«»… ÀÃÕŒœ—“”‘’÷ÿŸ⁄€‹‡·‚„‰ÂÁËÈÍÎÏÌÓÔÒÚÛÙıˆ¯˘˙˚¸ˇ}
 			{ABCDEFGHIJKLMNOPQRSTUVWXYZAAAAAACEEEEIIIINOOOOOOUUUUAAAAAACEEEEIIIINOOOOOOUUUUY};
	return $s;
}

sub ignoreCaseArticles {
	my $s = shift;
	return undef unless defined($s);
	if (defined $caseArticlesMemoize{$s}) {
		return $caseArticlesMemoize{$s};
	}

	return ($caseArticlesMemoize{$s} = ignoreArticles(matchCase($s)));
}

sub clearCaseArticleCache {
	%caseArticlesMemoize = ();
}

sub sortIgnoringCase {
	#set up an array without case for sorting
	my @nocase = map {ignoreCaseArticles($_)} @_;
	#return the original array sliced by the sorted caseless array
	return @_[sort {$nocase[$a] cmp $nocase[$b]} 0..$#_];
}

sub fixCase {
	my @fixed = ();
	foreach my $item (@_) {
		push @fixed, $caseCache{$item};
	}
	return @fixed;
}

sub sortuniq {
	my %seen = ();
	my @uniq = ();

	foreach my $item (@_) {
		if (defined($item) && ($item ne '') && !$seen{ignoreCaseArticles($item)}++) {
			push(@uniq, $item);
		}
	}

	return sort @uniq ;
}

# similar to above but ignore preceeding articles when sorting
sub sortuniq_ignore_articles {
	my %seen = ();
	my @uniq = ();
	my $articles =  Slim::Utils::Prefs::get("ignoredarticles");
	# allow a space seperated list in preferences (easier for humans to deal with)
	$articles =~ s/\s+/|/g;

	foreach my $item (@_) {
		if (defined($item) && ($item ne '') && !$seen{ignoreCaseArticles($item)}++) {
			push(@uniq, $item);
		}
	}
	#set up array for sorting items without leading articles
	my @noarts = map {
		my $item = $_; 
		exists($sortCache{$item}) ? $item = $sortCache{$item} : $item =~ s/^($articles)\s+//i; 
		$item; } @uniq;
		
	#return the uniq array sliced by the sorted articleless array
	return @uniq[sort {$noarts[$a] cmp $noarts[$b]} 0..$#uniq];
}


1;
__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
