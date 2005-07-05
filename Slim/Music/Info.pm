package Slim::Music::Info;

# $Id$

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use Fcntl;
use File::Spec::Functions qw(:ALL);
use FindBin qw($Bin);

use MP3::Info;
use Tie::Cache::LRU;

use Slim::DataStores::DBI::DBIStore;

use Slim::Utils::Misc;
use Slim::Utils::OSDetect;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Text;

# three hashes containing the types we know about, populated by the loadTypesConfig routine below
# hash of default mime type index by three letter content type e.g. 'mp3' => audio/mpeg
our %types = ();

# hash of three letter content type, indexed by mime type e.g. 'text/plain' => 'txt'
our %mimeTypes = ();

# hash of three letter content types, indexed by file suffixes (past the dot)  'aiff' => 'aif'
our %suffixes = ();

# hash of types that the slim server recoginzes internally e.g. aif => audio
our %slimTypes = ();

# Global caches:
my $artworkDir   = '';

# do we ignore articles?
our $articles = undef;

#
my %lastFile      = ();
my %display_cache = ();

tie our %currentTitles, 'Tie::Cache::LRU', 64;
our %currentTitleCallbacks = ();

my ($currentDB, $localDB, $ncElemstring, $ncElems, $elemstring, $elems, $validTypeRegex);

# Save our stats.
tie our %isFile, 'Tie::Cache::LRU', 16;

# No need to do this over and over again either.
tie our %urlToTypeCache, 'Tie::Cache::LRU', 16;

# Map our tag functions - so they can be dynamically loaded.
our %tagFunctions = (
	'mp3' => {
		'module' => 'Slim::Formats::MP3',
		'loaded' => 0,
		'getTag' => \&Slim::Formats::MP3::getTag,
	},

	'mp2' => {
		'module' => 'Slim::Formats::MP3',
		'loaded' => 0,
		'getTag' => \&Slim::Formats::MP3::getTag,
	},

	'ogg' => {
		'module' => 'Slim::Formats::Ogg',
		'loaded' => 0,
		'getTag' => \&Slim::Formats::Ogg::getTag,
	},

	'flc' => {
		'module' => 'Slim::Formats::FLAC',
		'loaded' => 0,
		'getTag' => \&Slim::Formats::FLAC::getTag,
	},

	'wav' => {
		'module' => 'Slim::Formats::Wav',
		'loaded' => 0,
		'getTag' => \&Slim::Formats::Wav::getTag,
	},

	'aif' => {
		'module' => 'Slim::Formats::AIFF',
		'loaded' => 0,
		'getTag' => \&Slim::Formats::AIFF::getTag,
	},

	'wma' => {
		'module' => 'Slim::Formats::WMA',
		'loaded' => 0,
		'getTag' => \&Slim::Formats::WMA::getTag,
	},

	'mov' => {
		'module' => 'Slim::Formats::Movie',
		'loaded' => 0,
		'getTag' => \&Slim::Formats::Movie::getTag,
	},

	'shn' => {
		'module' => 'Slim::Formats::Shorten',
		'loaded' => 0,
		'getTag' => \&Slim::Formats::Shorten::getTag,
	},

	'mpc' => {
		'module' => 'Slim::Formats::Musepack',
		'loaded' => 0,
		'getTag' => \&Slim::Formats::Musepack::getTag,
	},

	'ape' => {
		'module' => 'Slim::Formats::APE',
		'loaded' => 0,
		'getTag' => \&Slim::Formats::APE::getTag,
	},
);

sub init {

	# non-cached elements
	$ncElemstring = "VOLUME|PATH|FILE|EXT|DURATION|LONGDATE|SHORTDATE|CURRTIME|FROM|BY";
	$ncElems = qr/$ncElemstring/;

	$elemstring = (join '|', map { uc $_ } 
		keys %{Slim::DataStores::DBI::Track->attributes()},
		$ncElemstring,
		"ARTIST|COMPOSER|CONDUCTOR|BAND|ALBUM|GENRE|ALBUMSORT|ARTISTSORT|DISC|DISCC|COMMENT"
	);

	#. "|VOLUME|PATH|FILE|EXT" #file data (not in infoCache)
	#. "|DURATION" # SECS expressed as mm:ss (not in infoCache)
	#. "|LONGDATE|SHORTDATE|CURRTIME" #current date/time (not in infoCache)
	$elems = qr/$elemstring/;

	loadTypesConfig();

	# precompute the valid extensions
	validTypeExtensions();

	$currentDB = $localDB = Slim::DataStores::DBI::DBIStore->new();
	
	# use all the genres we know about...
	MP3::Info::use_winamp_genres();
	
	# also get the album, performer and title sort information
	$MP3::Info::v2_to_v1_names{'TSOA'} = 'ALBUMSORT';
	$MP3::Info::v2_to_v1_names{'TSOP'} = 'ARTISTSORT';
	$MP3::Info::v2_to_v1_names{'XSOP'} = 'ARTISTSORT';
	$MP3::Info::v2_to_v1_names{'TSOT'} = 'TITLESORT';

	# get composers
	$MP3::Info::v2_to_v1_names{'TCM'} = 'COMPOSER';
	$MP3::Info::v2_to_v1_names{'TCOM'} = 'COMPOSER';

	# get band/orchestra
	$MP3::Info::v2_to_v1_names{'TP2'} = 'BAND';
	$MP3::Info::v2_to_v1_names{'TPE2'} = 'BAND';	

	# get artwork
	$MP3::Info::v2_to_v1_names{'PIC'} = 'PIC';
	$MP3::Info::v2_to_v1_names{'APIC'} = 'PIC';	

	# get conductors
	$MP3::Info::v2_to_v1_names{'TP3'} = 'CONDUCTOR';
	$MP3::Info::v2_to_v1_names{'TPE3'} = 'CONDUCTOR';
	
	$MP3::Info::v2_to_v1_names{'TBP'} = 'BPM';
	$MP3::Info::v2_to_v1_names{'TBPM'} = 'BPM';
}

sub getCurrentDataStore {
	return $currentDB;
}

sub loadTypesConfig {
	my @typesFiles;
	$::d_info && Slim::Utils::Misc::msg("loading types config file...\n");
	
	push @typesFiles, catdir($Bin, 'types.conf');
	if (Slim::Utils::OSDetect::OS() eq 'mac') {
		push @typesFiles, $ENV{'HOME'} . "/Library/SlimDevices/types.conf";
		push @typesFiles, "/Library/SlimDevices/types.conf";
		push @typesFiles, $ENV{'HOME'} . "/Library/SlimDevices/custom-types.conf";
		push @typesFiles, "/Library/SlimDevices/custom-types.conf";
	}

	push @typesFiles, catdir($Bin, 'custom-types.conf');
	push @typesFiles, catdir($Bin, '.custom-types.conf');
	
	foreach my $typeFileName (@typesFiles) {
		if (open my $typesFile, $typeFileName) {
			for my $line (<$typesFile>) {
				# get rid of comments and leading and trailing white space
				$line =~ s/#.*$//;
				$line =~ s/^\s//;
				$line =~ s/\s$//;
	
				if ($line =~ /^(\S+)\s+(\S+)\s+(\S+)\s+(\S+)/) {
					my $type = $1;
					my @suffixes = split ',', $2;
					my @mimeTypes = split ',', $3;
					my @slimTypes = split ',', $4;
					
					foreach my $suffix (@suffixes) {
						next if ($suffix eq '-');
						$suffixes{$suffix} = $type;
					}
					
					foreach my $mimeType (@mimeTypes) {
						next if ($mimeType eq '-');
						$mimeTypes{$mimeType} = $type;
					}

					foreach my $slimType (@slimTypes) {
						next if ($slimType eq '-');
						$slimTypes{$type} = $slimType;
					}
					
					# the first one is the default
					if ($mimeTypes[0] ne '-') {
						$types{$type} = $mimeTypes[0];
					}				
				}
			}
			close $typesFile;
		}
	}
}

sub clearCache {
	my $item = shift;

	if ($item) {
		$currentDB->delete($item);
	} else {
		$currentDB->markAllEntriesStale();
		$::d_info && Slim::Utils::Misc::msg("clearing validity for rescan\n");
	}

	saveDBCache();
}

sub saveDBCache {
	$currentDB->forceCommit();
}

sub wipeDBCache {
	$currentDB->wipeAllData();
}

sub clearStaleCacheEntries {
	$currentDB->clearStaleEntries();
}

# Mark an item as having been rescanned
sub markAsScanned {
	my $item = shift;

	$currentDB->markEntryAsValid($item);
}

sub total_time {
	return $currentDB->totalTime();
}

sub playlistForClient {
	my $client = shift;

	return $currentDB->getPlaylistForClient($client);
}

sub clearPlaylists {
	return $currentDB->clearExternalPlaylists(shift) if defined($currentDB);
}

sub playlists {
	return [$currentDB->getInternalPlaylists, $currentDB->getExternalPlaylists];
}

sub cacheItem {
	my $url = shift;
	my $item = shift;

	$::d_info_v && Slim::Utils::Misc::msg("CacheItem called for item $item in $url\n");

	my $track = $currentDB->objectForUrl($url, 0) || return undef;

	if ($item eq 'ALBUM') {
		return $track->album()->title();
	}

	return $track->get(lc $item) || undef;
}

sub updateCacheEntry {
	my $url = shift;
	my $cacheEntryHash = shift;

	if (!defined($url)) {
		Slim::Utils::Misc::msg("No URL specified for updateCacheEntry\n");
		Slim::Utils::Misc::msg(%{$cacheEntryHash});
		Slim::Utils::Misc::bt();
		return;
	}

	if (!isURL($url)) { 
		Slim::Utils::Misc::msg("Non-URL passed to updateCacheEntry::info ($url)\n");
		Slim::Utils::Misc::bt();
		$url=Slim::Utils::Misc::fileURLFromPath($url); 
	}

	my $list;
	if ($cacheEntryHash->{'LIST'}) {
		$list = $cacheEntryHash->{'LIST'};
	}
	
	my $song = $currentDB->updateOrCreate({
		'url'        => $url,
		'attributes' => $cacheEntryHash,
	});

	if ($list) {
		my @tracks = map { $currentDB->objectForUrl($_, 1, 0); } @$list;
		$song->setTracks(\@tracks);
	}
}

##################################################################################
# this routine accepts both our three letter content types as well as mime types.
# if neither match, we guess from the URL.
sub setContentType {
	my $url = shift;
	my $type = shift;

	if ($type =~ /(.*);(.*)/) {
		# content type has ";" followed by encoding
		$::d_info && Slim::Utils::Misc::msg("Info: truncating content type.  Was: $type, now: $1\n");
		# TODO: remember encoding as it could be useful later
		$type = $1; # truncate at ";"
	}

	$type = lc($type);

	if ($types{$type}) {
		# we got it
	} elsif ($mimeTypes{$type}) {
		$type = $mimeTypes{$type};
	} else {
		my $guessedtype = typeFromPath($url);
		if ($guessedtype ne 'unk') {
			$type = $guessedtype;
		}
	}

	# Update the cache set by typeFrompath as well.
	$urlToTypeCache{$url} = $type;

	# Commit, since we might use it again right away.
	$currentDB->updateOrCreate({
		'url'        => $url,
		'attributes' => { 'CT' => $type },
		'commit'     => 1,
		'readTags'   => 1,
	});

	$::d_info && Slim::Utils::Misc::msg("Content type for $url is cached as $type\n");
}

sub title {
	my $url = shift;

	return info($url, 'title');
}

sub setTitle {
	my $url = shift;
	my $title = shift;

	$::d_info && Slim::Utils::Misc::msg("Adding title $title for $url\n");

	$currentDB->updateOrCreate({
		'url'        => $url,
		'attributes' => { 'TITLE' => $title },
		'readTags'   => 1,
	});
}

sub setBitrate {
	my $url = shift;
	my $bitrate = shift;

	$currentDB->updateOrCreate({
		'url'        => $url,
		'attributes' => { 'BITRATE' => $bitrate },
		'readTags'   => 1,
	});
}

sub setCurrentTitleChangeCallback {
	my $callbackRef = shift;
	$currentTitleCallbacks{$callbackRef} = $callbackRef;
}

sub clearCurrentTitleChangeCallback {
	my $callbackRef = shift;
	$currentTitleCallbacks{$callbackRef} = undef;
}

sub setCurrentTitle {
	my $url = shift;
	my $title = shift;

	if (($currentTitles{$url} || '') ne ($title || '')) {
		no strict 'refs';
		
		for my $changecallback (values %currentTitleCallbacks) {
			&$changecallback($url, $title);
		}
	}

	$currentTitles{$url} = $title;
}

# Can't do much if we don't have a url.
sub getCurrentTitle {
	my $client = shift;
	my $url    = shift || return undef;

	return $currentTitles{$url} || standardTitle($client, $url);
}

sub elemLookup {
	my $element     = shift;
	my $infoHashref = shift;

	# don't return disc number if known to be single disc set
	if ($element eq "DISC") {
		my $discCount = $infoHashref->{"DISCC"};
		return undef if defined $discCount and $discCount == 1;
	}
	return undef if defined $infoHashref->{$element} and Slim::Utils::Strings::stringExists("NO_".$element) and $infoHashref->{$element} eq string("NO_".$element);

	return $infoHashref->{$element};
}

# used by infoFormat to add items not in infoCache to hash of info
sub addToinfoHash {
	my $infoHashref = shift;
	my $file = shift;
	my $str = shift;
	
	if ($str =~ /VOLUME|PATH|FILE|EXT/) {
		if (isFileURL($file)) { $file=Slim::Utils::Misc::pathFromFileURL($file); }
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

# formats information about a file using a provided format string
sub infoFormat {
	no warnings; # this is to allow using null values with string concatenation, it only effects this procedure
	my $fileOrObj = shift; # item whose information will be formatted
	my $str = shift; # format string to use
	my $safestr = shift; # format string to use in the event that after filling the first string, there is nothing left
	my $pos = 0; # keeps track of position within the format string

	my $track = ref $fileOrObj ? $fileOrObj  : $currentDB->objectForUrl($fileOrObj, 1);
	my $file  = ref $fileOrObj ? $track->url : $fileOrObj;

	return '' unless defined $file && $track;
	
	my $infoRef = infoHash($track, $file) || return '';

	my %infoHash = %{$infoRef}; # hash of data elements not cached in the main repository

	# use a safe format string if none specified
	# Users can input strings in any locale - we need to convert that to
	# UTF-8 first, otherwise perl will segfault in the nasty regex below.
	if ($str && $] > 5.007) {

		eval {
			Encode::from_to($str, $Slim::Utils::Misc::locale, 'utf8');
			Encode::_utf8_on($str);
		};

	} elsif (!defined $str) {

		$str = 'TITLE';
	}

	if ($str =~ $ncElems) {
		addToinfoHash(\%infoHash,$file,$str);
	}

	# So formats with high-bit chars will work.
	use bytes;

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
					my $out = ''; # replacement string for this substitution
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

	# same regex as above, but the last element is the end of the string
	$str =~ s{\G(.*?)?(?:=>(.*?)=>)?(?:=>(.*?)=>)?($elems)(?:<=(.*?)<=)?(.*?)?(?:<#(.*?)#>)?$}
				{
					my $out = '';
					my $value = elemLookup($4, \%infoHash);
					if (defined($value)) {
						#fill with all the separators
						#no need to do the <##> conversion since this is the end of the string
						$out = $1 . $2 . $3 . $value . $5 . $6 . $7;

					} else {
						# value not defined
						# only use the bare separators if there were framed ones as well
						$out  = (defined($2) || defined($3)) ? $1 : "";
						$out .= (defined($5) || defined($7)) ? $6 : "";
					}
					$out;
				}e;

	if ($str eq "" && defined($safestr)) {

		# if there isn't anything left of the format string after the replacements, use the safe string, if supplied
		return infoFormat($track,$safestr);

	} else {
		$str =~ s/%([0-9a-fA-F][0-9a-fA-F])%/chr(hex($1))/eg;
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

	$::d_info && Slim::Utils::Misc::msg("Plain title for: " . $file . "\n");

	if (isRemoteURL($file)) {
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
				$title =~ s/\.[^. ]+$//;
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
	my $client    = shift;
	my $pathOrObj = shift; # item whose information will be formatted

	# Be sure to try and "readTags" - which may call into Formats::Parse for playlists.
	my $track     = ref $pathOrObj ? $pathOrObj : $currentDB->objectForUrl($pathOrObj, 1, 1);
	my $fullpath  = ref $pathOrObj ? $track->url : $pathOrObj;
	my $format;

	if (isPlaylistURL($fullpath) || isList($track)) {

		$format = 'TITLE';

	} elsif (defined($client)) {

		# in array syntax this would be
		# $titleFormat[$clientTitleFormat[$clientTitleFormatCurr]] get
		# the title format

		$format = Slim::Utils::Prefs::getInd("titleFormat",
			# at the array index of the client titleformat array
			Slim::Utils::Prefs::clientGet($client, "titleFormat",
				# which is currently selected
				Slim::Utils::Prefs::clientGet($client,'titleFormatCurr')
			)
		);

	} else {

		# in array syntax this would be $titleFormat[$titleFormatWeb]
		$format = Slim::Utils::Prefs::getInd("titleFormat", Slim::Utils::Prefs::get("titleFormatWeb"));
	}
	
	# Client may not be defined, but we still want to use the cache.
	$client ||= 'NOCLIENT';

	my $ref = $display_cache{$client} ||= {
		'fullpath' => '',
		'format'   => '',
	};

	if ($fullpath ne $ref->{'fullpath'} || $format ne $ref->{'format'}) {

		$ref = $display_cache{$client} = {
			'fullpath' => $fullpath,
			'format'   => $format,
			'display'  => infoFormat($track, $format, 'TITLE'),
		};
	}

	return $ref->{'display'};
}

#
# Guess the important tags from the filename; use the strings in preference
# 'guessFileFormats' to generate candidate regexps for matching. First
# match is accepted and applied to the argument tag hash.
#
sub guessTags {
	my $filename = shift;
	my $type = shift;
	my $taghash = shift;
	
	my $file = $filename;
	$::d_info && Slim::Utils::Misc::msg("Guessing tags for: $file\n");

	# Rip off from plainTitle()
	if (isRemoteURL($file)) {
		$file = Slim::Web::HTTP::unescape($file);
	} else {
		if (isFileURL($file)) {
			$file = Slim::Utils::Misc::pathFromFileURL($file);
		}
		# directories don't get the suffixes
		if ($file && !($type && $type eq 'dir')) {
				$file =~ s/\.[^.]+$//;
		}
	}

	# Replace all backslashes in the filename
	$file =~ s/\\/\//g;
	
	# Get the candidate file name formats
	my @guessformats = Slim::Utils::Prefs::getArray("guessFileFormats");

	# Check each format
	foreach my $guess ( @guessformats ) {
		# Create pattern from string format
		my $pat = $guess;
		
		# Escape _all_ regex special chars
		$pat =~ s/([{}[\]()^\$.|*+?\\])/\\$1/g;

		# Replace the TAG string in the candidate format string
		# with regex (\d+) for TRACKNUM, DISC, and DISCC and
		# ([^\/+) for all other tags
		
		$pat =~ s/(TRACKNUM|DISC{1,2})/\(\\d+\)/g;
		$pat =~ s/($elems)/\(\[^\\\/\]\+\)/g;
		$::d_info && Slim::Utils::Misc::msg("Using format \"$guess\" = /$pat/...\n" );
		$pat = qr/$pat/;

		# Check if this format matches		
		my @matches;
		if (@matches = $file =~ $pat) {
			$::d_info && Slim::Utils::Misc::msg("Format string $guess matched $file\n" );
			my @tags = $guess =~ /($elems)/g;
			my $i = 0;
			foreach my $match (@matches) {
				$::d_info && Slim::Utils::Misc::msg("$tags[$i] => $match\n");
				$match =~ tr/_/ / if (defined $match);
				$match = int($match) if $tags[$i] =~ /TRACKNUM|DISC{1,2}/;
				$taghash->{$tags[$i++]} = $match;
			}
			return;
		}
	}
	
	# Nothing found; revert to plain title
	$taghash->{'TITLE'} = plainTitle($filename, $type);	
}


#
# Return a structure containing the ID3 tag attributes of the given MP3 file.
#
sub infoHash {
	my $track = shift;
	my $file  = shift;

	if (!defined($file) || $file eq "") { 
		$::d_info && Slim::Utils::Misc::msg("trying to get infoHash on an empty file name\n");
		$::d_info && Slim::Utils::Misc::bt();
		return; 
	};

	if (!defined($track)) { 
		$::d_info && Slim::Utils::Misc::msg("trying to get infoHash on an empty track\n");
		$::d_info && Slim::Utils::Misc::bt();
		return; 
	};
	
	if (!isURL($file)) { 
		Slim::Utils::Misc::msg("Non-URL passed to InfoHash::info ($file)\n");
		Slim::Utils::Misc::bt();
		$file = Slim::Utils::Misc::fileURLFromPath($file); 
	}
	
	my $cacheEntryHash = {};

	# Make as few get requests as possible.
	my $album  = $track->album();
	my $artist = $track->artist();
	my $genre  = $track->genre();

	# 
	if ($album) {
		$cacheEntryHash->{'ALBUM'} = $album->title();

		my @values = $album->get(qw(titlesort disc discc));

		for my $attr (qw(ALBUMSORT DISC DISCC)) {

			my $value = shift @values;

			if (defined $value) {
				$cacheEntryHash->{$attr} = $value;
			}
		}
	}

	my @attributes = grep { !/^album$/ } keys %{Slim::DataStores::DBI::Track->attributes};
	my @values     = $track->get(@attributes);

	for my $attr (@attributes) {
		$cacheEntryHash->{uc $attr} = shift @values;
	}

	if ($artist) {
		($cacheEntryHash->{"ARTIST"}, $cacheEntryHash->{"ARTISTSORT"}) = $artist->get(qw(name namesort));
	}

	for my $contributorType (qw(COMPOSER CONDUCTOR BAND)) {

		# $contributor must be in array context, otherwise
		# we'll get an iterator.
		my $method        = lc($contributorType);
		my ($contributor) = $track->$method();

		if ($contributor) {
			$cacheEntryHash->{$contributorType} = $contributor->name();
		}
	}

	if ($genre) {
		$cacheEntryHash->{"GENRE"}   = $genre->name();
	}

	if (my $comment = $track->comment()) {
		$cacheEntryHash->{"COMMENT"} = $comment;
	}

	return $cacheEntryHash;
}

sub info {
	my $file    = shift;
	my $tagname = shift;

	if (!defined $file || $file eq '' || !defined $tagname || $tagname eq '') { 
		$::d_info && Slim::Utils::Misc::msg("trying to get info on an empty file name\n");
		$::d_info && Slim::Utils::Misc::bt();
		return; 
	};
	
	$::d_info && Slim::Utils::Misc::msg("Request for $tagname on file $file\n");
	
	if (!isURL($file)) { 
		$::d_info && Slim::Utils::Misc::msg("Non-URL passed to Info::info ($file)\n");
		$::d_info && Slim::Utils::Misc::bt();

		$file = Slim::Utils::Misc::fileURLFromPath($file); 
	}
	
	my $track = $currentDB->objectForUrl($file, 0) || return;

	if ($tagname =~ /^(?:ALBUM|ALBUMSORT|DISC|DISCC)$/o) {

		my $album = $track->album() || return;

		return $album->title()     if $tagname eq 'ALBUM';
		return $album->titlesort() if $tagname eq 'ALBUMSORT';
		return $album->disc()      if $tagname eq 'DISC';
		return $album->discc()     if $tagname eq 'DISCC';
	}

	#FIXME
	if ($tagname =~ /^(?:COMPOSER|BAND|CONDUCTOR)$/o) {
		return undef;
	}
	
	# Fall through
	my $lcTag = lc($tagname);

	# These need to go through their overridden methods.
	if ($tagname =~ /^(?:GENRE|ARTIST|ARTISTSORT|COMMENT)$/o) {
		return $track->$lcTag();
	}

	return $track->get($lcTag);
}

sub cleanTrackNumber {
	my $tracknumber = shift;

	if (defined($tracknumber)) {
		# extracts the first digits only sequence then converts it to int
		$tracknumber =~ /(\d*)/;
		$tracknumber = $1 ? int($1) : undef;
	}
	
	return $tracknumber;
}

sub cachedPlaylist {
	my $urlOrObj = shift || return;

	# We might have gotten an object passed in for effeciency. Check for
	# that, and if not, make sure we get a valid object from the db.
	my $obj = ref $urlOrObj ? $urlOrObj : $currentDB->objectForUrl($urlOrObj, 0);

	return undef unless $obj;

	# We want any PlayListTracks this item may have
	my @urls = ();

	for my $track ($obj->tracks()) {

		if (defined $track && $track->can('url')) {

			push @urls, $track->url();

		} else {

			$::d_info && Slim::Utils::Misc::msgf("Invalid track object for playlist [%s]!\n", $obj->url);
		}
	}

	# Otherwise, we're actually a directory.
	if (!scalar @urls) {
		@urls = $obj->diritems();
	}

	return \@urls if scalar(@urls);

	return undef;
}

sub cacheDirectory {
	my ($url, $list, $age) = @_;

	my $obj = $currentDB->objectForUrl($url, 1, 1) || return;

	$obj->setDirItems($list);
	$obj->timestamp( ($age || time) );

	$currentDB->updateTrack($obj);
	
	$::d_info && Slim::Utils::Misc::msg("cached an " . (scalar @$list) . " item playlist for $url\n");
}

sub sortByTrack {

	$articles = undef;

	#get info for items and ignoreCaseArticles it
	my @sortinfo =  map { getInfoForSort($_) } @_;

	#return the first element of each entry in the sorted array
	return map {$_->[0]} sort sortByTrackAlg @sortinfo;
}

sub sortByAlbum {

	$articles = undef;

	#get info for items and ignoreCaseArticles it
	my @sortinfo =  map { getInfoForSort($_) } @_;

	#return an array of first elements of the entries in the sorted array
	return map {$_->[0]} sort sortByAlbumAlg @sortinfo;
}

sub sortByTitles {

	$articles = undef;

	#get info for items and ignoreCaseArticles it
	my @sortinfo =  map { getInfoForSort($_) } @_;

	#return an array of first elements of the entries in the sorted array
	return map {$_->[0]} sort sortByTitlesAlg @sortinfo;
}

#algorithm for sorting by just titles
sub sortByTitlesAlg ($$) {
	my $j = $_[0];
	my $k = $_[1];

	# compare titles
	return ($j->[5] || 0) cmp ($k->[5] || 0);
}

# Sets up an array entry for performing complex sorts
sub getInfoForSort {
	my $item = shift;

	my $obj  = $currentDB->objectForUrl($item) || return [ $item, 0, undef, undef, undef, '', undef ];

	my $list  = isList($obj);
	my $album = $obj->album();

	my ($trackTitleSort, $trackNum) = $obj->get(qw(titlesort tracknum));
	my ($albumTitleSort, $disc);

	if (defined $album) {
		($albumTitleSort, $disc) = $album->get(qw(titlesort disc));
	}

	return [
		$item,
		$list,
		$list ? undef : $obj->artistsort(),
		$list ? undef : $albumTitleSort,
		$list ? undef : $trackNum,
		$trackTitleSort,
		$list ? undef : $disc,
	];
}	

#algorithm for sorting by Artist, Album, Track
sub sortByTrackAlg ($$) {
	my $j = $_[0];
	my $k = $_[1];

	my $result;
	#If both lists compare titles
	if ($j->[1] && $k->[1]) {
		# compare titles
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
	
	# compare artists
	if (defined($j->[2]) && defined($k->[2])) {
		$result = $j->[2] cmp $k->[2];
		if ($result) { return $result; }
	} elsif (defined($j->[2])) {
		return -1;
	} elsif (defined($k->[2])) {
		return 1;
	}
	
	# compare albums
	if (defined($j->[3]) && defined($k->[3])) {
		$result = $j->[3] cmp $k->[3];
		if ($result) { return $result; }
	} elsif (defined($j->[3])) {
		return -1;
	} elsif (defined($k->[3])) {
		return 1;
	}
	
	# compare discs
	if (defined $j->[6] && defined $k->[6]) {
	   $result = $j->[6] <=> $k->[6];
	   return $result if $result;
	}

	# compare track numbers
	if ($j->[4] && $k->[4]) {
		$result = $j->[4] <=> $k->[4];
		if ($result) { return $result; }
	} elsif ($j->[4]) {
		return -1;
	} elsif ($k->[4]) {
		return 1;
	}

	# compare titles
	return $j->[5] cmp $k->[5];
}

# algorithm for sorting by Album, Track
sub sortByAlbumAlg ($$) {
	my $j = $_[0];
	my $k = $_[1];

	my $result;

	# If both are lists compare titles
	if ($j->[1] && $k->[1]) { 

		# compare titles
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
	
	# compare albums
	if (defined($j->[3]) && defined($k->[3])) {
		$result = $j->[3] cmp $k->[3];
		if ($result) { return $result; }
	} elsif (defined($j->[3])) {
		return -1;
	} elsif (defined($k->[3])) {
		return 1;
	}
	
	# compare discs
	if (defined $j->[6] && defined $k->[6]) {

		$result = $j->[6] <=> $k->[6];
		return $result if $result;
	}

	# compare track numbers
	if ($j->[4] && $k->[4]) {
		$result = $j->[4] <=> $k->[4];
		if ($result) { return $result; }
	} elsif ($j->[4]) {
		return -1;
	} elsif ($k->[4]) {
		return 1;
	}

	# titles might be undef.
	$j->[5] ||= '';
	$k->[5] ||= '';

	# compare titles
	return $j->[5] cmp $k->[5];
}

sub fileName {
	my $j = shift;

	if (isFileURL($j)) {
		$j = Slim::Utils::Misc::pathFromFileURL($j);
		if ($j) {
			$j = (splitdir($j))[-1];
		}
	} elsif (isRemoteURL($j)) {
		$j = Slim::Web::HTTP::unescape($j);
	} else {
		$j = (splitdir($j))[-1];
	}

	return $j;
}

sub sortFilename {
	# build the sort index
	# File sorting should look like ls -l, Windows Explorer, or Finder -
	# really, we shouldn't be doing any of this, but we'll ignore
	# punctuation, and fold the case. DON'T strip articles.
	my @nocase = map { Slim::Utils::Text::ignorePunct(Slim::Utils::Text::matchCase(fileName($_))) } @_;

	# return the input array sliced by the sorted array
	return @_[sort {$nocase[$a] cmp $nocase[$b]} 0..$#_];
}

sub isFragment {
	my $fullpath = shift;
	
	return unless isURL($fullpath);

	my $anchor = Slim::Utils::Misc::anchorFromURL($fullpath);

	if ($anchor && $anchor =~ /([\d\.]+)-([\d\.]+)/) {
		return ($1, $2);
	}
}

sub addDiscNumberToAlbumTitle {
	my ($title, $discNum, $discCount) = @_;

	# Unless the groupdiscs preference is selected:
	# Handle multi-disc sets with the same title
	# by appending a disc count to the track's album name.
	# If "disc <num>" (localized or English) is present in 
	# the title, we assume it's already unique and don't
	# add the suffix.
	# If it seems like there is only one disc in the set, 
	# avoid adding "disc 1 of 1"
	return $title unless defined $discNum and $discNum > 0;

	if (defined $discCount) {
		return $title if $discCount == 1;
		undef $discCount if $discCount < 1; # errornous count
	}

	my $discWord = string('DISC');

	return $title if $title =~ /\b(${discWord})|(Disc)\s+\d+/i;

	if (defined $discCount) {
		# add spaces to discNum to help plain text sorting
		my $discCountLen = length($discCount);
		$title .= sprintf(" (%s %${discCountLen}d %s %d)", $discWord, $discNum, string('OF'), $discCount);
	} else {
		$title .= " ($discWord $discNum)";
	}

	return $title;
}

sub getImageContent {
	my $path = shift;

	use bytes;
	my $contentref;

	if (open (TEMPLATE, $path)) { 
		local $/ = undef;
		binmode(TEMPLATE);
		$$contentref = <TEMPLATE>;
		close TEMPLATE;
	}

	defined($$contentref) && length($$contentref) || $::d_artwork && Slim::Utils::Misc::msg("Image File empty or couldn't read: $path\n");
	return $$contentref;
}

sub readCoverArt {
	my $fullpath = shift;
	my $image    = shift || 'cover';

	my ($body,$contenttype,$path) = readCoverArtTags($fullpath);

	if (!defined $body) {
		($body,$contenttype,$path) = readCoverArtFiles($fullpath,$image);
	}

	return ($body,$contenttype,$path);
}
	
sub readCoverArtTags {
	use bytes;
	my $fullpath = shift;
	my $tags = shift;

	return undef unless Slim::Utils::Prefs::get('lookForArtwork');

	my $body;	
	my $contenttype;
	
	$::d_artwork && Slim::Utils::Misc::msg("Updating image for $fullpath\n");
	
	if (isSong($fullpath) && isFile($fullpath)) {
	
		my $file = Slim::Utils::Misc::virtualToAbsolute($fullpath);
	
		if (isFileURL($file)) {
			$file = Slim::Utils::Misc::pathFromFileURL($file);
		} else {
			$file = $fullpath;
		}
			
		if (isMP3($fullpath) || isWav($fullpath) || isAIFF($fullpath)) {
	
			$tags = MP3::Info::get_mp3tag($file, 2, 1);
			if (defined $tags) {
				$::d_artwork && Slim::Utils::Misc::msg("Looking for image in ID3 2.2 tag in file $file\n");
				# look for ID3 v2.2 picture
				my $pic = $tags->{'PIC'};
				if (defined($pic)) {
					if (ref($pic) eq 'ARRAY') {
						$pic = (@$pic)[0];
					}					
					my ($encoding, $format, $picturetype, $description) = unpack 'Ca3CZ*', $pic;
					my $len = length($description) + 1 + 5;
					if ($encoding) { $len++; } # skip extra terminating null if unicode
					
					if ($len < (length($pic))) {		
						my ($data) = unpack "x$len A*", $pic;
						
						$::d_artwork && Slim::Utils::Misc::msg( "PIC format: $format length: " . length($pic) . "\n");

						if (length($pic)) {
							if ($format eq 'PNG') {
									$contenttype = 'image/png';
									$body = $data;
							} elsif ($format eq 'JPG') {
									$contenttype = 'image/jpeg';
									$body = $data;
							}
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
						if ($len < length($pic)) {
							my ($picturetype, $description) = unpack "x$len C Z*", $pic;
							$len += 1 + length($description) + 1;
							if ($encoding) { $len++; } # skip extra terminating null if unicode
							
							my ($data) = unpack"x$len A*", $pic;
							
							$::d_artwork && Slim::Utils::Misc::msg( "APIC format: $format length: " . length($data) . "\n");
	
							if (length($data)) {
								$contenttype = $format;
								$body = $data;
							}
						}
					}
				}
			}

		} elsif (isMOV($fullpath)) {

			$::d_artwork && Slim::Utils::Misc::msg("Looking for image in Movie metadata in file $file\n");

			loadTagFormatForType('mov');

			$body = Slim::Formats::Movie::getCoverArt($file);

			$::d_artwork && $body && Slim::Utils::Misc::msg("found image in $file of length " . length($body) . " bytes \n");
		}
		
		if ($body) {
			# iTunes sometimes puts PNG images in and says they are jpeg
			if ($body =~ /^\x89PNG\x0d\x0a\x1a\x0a/) {
				$::d_info && Slim::Utils::Misc::msg( "found PNG image\n");
				$contenttype = 'image/png';
			} elsif ($body =~ /^\xff\xd8\xff\xe0..JFIF/) {
				$::d_info && Slim::Utils::Misc::msg( "found JPEG image\n");
				$contenttype = 'image/jpeg';
			}
			
			# jpeg images must start with ff d8 ff e0 or they ain't jpeg, sometimes there is junk before.
			if ($contenttype && $contenttype eq 'image/jpeg')	{
				$body =~ s/^.*?\xff\xd8\xff\xe0/\xff\xd8\xff\xe0/;
			}
		}

 	} else {

 		$::d_info && Slim::Utils::Misc::msg("readCoverArtTags: Not a song, skipping: $fullpath\n");
 	}
 	
	return ($body, $contenttype, 1);
}

sub readCoverArtFiles {
	my $fullpath = shift;
	my $image    = shift || 'cover';

	my ($artwork, $contentType, $body);
	my @filestotry = ();
	my @names      = qw(cover thumb album albumartsmall folder);
	my @ext        = qw(jpg gif);

	use bytes;

	my $file = isFileURL($fullpath) ? Slim::Utils::Misc::pathFromFileURL($fullpath) : $fullpath;

	my @components = splitdir($file);
	pop @components;

	$::d_artwork && Slim::Utils::Misc::msg("Looking for image files in ".catdir(@components)."\n");

	my %nameslist = map { $_ => [do { my $t = $_; map { "$t.$_" } @ext }] } @names;
	
	if ($image eq 'thumb') {

		# these seem to be in a particular order - not sure if that means anything.
		@filestotry = map { @{$nameslist{$_}} } qw(thumb albumartsmall cover folder album);

		if (Slim::Utils::Prefs::get('coverThumb')) {
			$artwork = Slim::Utils::Prefs::get('coverThumb');
		}

	} else {

		# these seem to be in a particular order - not sure if that means anything.
		@filestotry = map { @{$nameslist{$_}} } qw(cover folder album thumb albumartsmall);

		if (Slim::Utils::Prefs::get('coverArt')) {
			$artwork = Slim::Utils::Prefs::get('coverArt');
		}
	}

	if (defined($artwork) && $artwork =~ /^%(.*?)(\..*?){0,1}$/) {

		my $suffix = $2 ? $2 : ".jpg";

		$artwork = infoFormat(Slim::Utils::Misc::fileURLFromPath($fullpath), $1)."$suffix";

		$::d_artwork && Slim::Utils::Misc::msgf(
			"Variable %s: %s from %s\n", ($image eq 'thumb' ? 'Thumbnail' : 'Cover'), $artwork, $1
		);

		my $artpath = catdir(@components, $artwork);

		$body = getImageContent($artpath);

		my $artfolder = Slim::Utils::Prefs::get('artfolder');

		if (!$body && defined $artfolder) {

			$artpath = catdir(Slim::Utils::Prefs::get('artfolder'),$artwork);
			$body = getImageContent($artpath);
		}

		if ($body) {

			$::d_artwork && Slim::Utils::Misc::msg("Found $image file: $artpath\n\n");

			$contentType = mimeType(Slim::Utils::Misc::fileURLFromPath($artpath));

			return ($body, $contentType, $artpath);
		}

	} elsif (defined $artwork) {

		unshift @filestotry, $artwork;
	}

	if (defined $artworkDir && $artworkDir eq catdir(@components)) {

		if (exists $lastFile{$image}  && $lastFile{$image} ne '1') {

			$::d_artwork && Slim::Utils::Misc::msg("Using existing $image: $lastFile{$image}\n");

			$body = getImageContent($lastFile{$image});

			$contentType = mimeType(Slim::Utils::Misc::fileURLFromPath($lastFile{$image}));

			$artwork = $lastFile{$image};

			return ($body, $contentType, $artwork);

		} elsif (exists $lastFile{$image}) {

			$::d_artwork && Slim::Utils::Misc::msg("No $image in $artworkDir\n");

			return undef;
		}

	} else {

		$artworkDir = catdir(@components);
		%lastFile = ();
	}

	foreach my $file (@filestotry) {

		$file = catdir(@components, $file);

		next unless -r $file;

		$body = getImageContent($file);

		if ($body) {
			$::d_artwork && Slim::Utils::Misc::msg("Found $image file: $file\n\n");

			$contentType = mimeType(Slim::Utils::Misc::fileURLFromPath($file));

			$artwork = $file;
			$lastFile{$image} = $file;

			last;

		} else {

			$lastFile{$image} = '1';
		}
	}

	return ($body, $contentType, $artwork);
}

sub splitTag {
	my $tag = shift;

	# Splitting this is probably not what the user wants.
	# part of bug #774
	if ($tag =~ /^\s*R\s*\&\s*B\s*$/oi) {
		return $tag;
	}

	my @splitTags = ();
	my $splitList = Slim::Utils::Prefs::get('splitList');

	# only bother if there are some characters in the pref
	if ($splitList) {

		for my $splitOn (split(/\s+/, $splitList),'\x00') {

			my @temp = ();

			for my $item (split(/\Q$splitOn\E/, $tag)) {

				$item =~ s/^\s*//go;
				$item =~ s/\s*$//go;

				push @temp, $item if $item !~ /^\s*$/;

				$::d_info && Slim::Utils::Misc::msg("Splitting $tag by $splitOn = @temp\n") unless scalar @temp <= 1;
			}

			# store this for return only if there has been a successfil split
			if (scalar @temp > 1) {
				push @splitTags, @temp;
			}
		}
	}

	# return the split array, or just return the whole tag is we know there hasn't been any splitting.
	if (scalar @splitTags > 1) {

		return @splitTags;
	}

	return $tag;
}

sub isFile {
	my $url = shift;

	# We really don't need to check this every time.
	if (defined $isFile{$url}) {
		return $isFile{$url};
	}

	my $fullpath = isFileURL($url) ? Slim::Utils::Misc::pathFromFileURL($url) : $url;
	
	return 0 if (isURL($fullpath));
	
	# check against types.conf
	return 0 unless $suffixes{ (split /\./, $fullpath)[-1] };

	my $stat = (-f $fullpath && -r $fullpath ? 1 : 0);

	$::d_info && Slim::Utils::Misc::msgf("isFile(%s) == %d\n", $fullpath, (1 * $stat));

	$isFile{$url} = $stat;

	return $stat;
}

sub isFileURL {
	my $url = shift;

	return (defined($url) && ($url =~ /^file:\/\//i));
}

sub isHTTPURL {
	my $url = shift;

	return (defined($url) && ($url =~ /^(http|icy):\/\//i));
}

sub isRemoteURL {
	my $url = shift;
	return (defined($url) && ($url =~ /^([a-zA-Z0-9\-]+):/) && $Slim::Player::Source::protocolHandlers{$1});
}

sub isPlaylistURL {
	my $url = shift;
	return (defined($url) && ($url =~ /^([a-zA-Z0-9\-]+):/) && exists($Slim::Player::Source::protocolHandlers{$1}) && !isFileURL($url));
}

sub isURL {
	my $url = shift;
	return (defined($url) && ($url =~ /^([a-zA-Z0-9\-]+):/) && exists($Slim::Player::Source::protocolHandlers{$1}));
}

sub isType {
	my $pathOrObj = shift || return 0;
	my $testtype  = shift;

	my $type = ref $pathOrObj ? $pathOrObj->content_type : $currentDB->contentType($pathOrObj);

	if ($type && ($type eq $testtype)) {
		return 1;
	} else {
		return 0;
	}
}

sub isWinShortcut {
	my $pathOrObj = shift;

	return isType($pathOrObj, 'lnk');
}

sub isMP3 {
	my $pathOrObj = shift;

	return isType($pathOrObj, 'mp3') || isType($pathOrObj, 'mp2');
}

sub isOgg {
	my $pathOrObj = shift;

	return isType($pathOrObj, 'ogg');
}

sub isWav {
	my $pathOrObj = shift;

	return isType($pathOrObj, 'wav');
}

sub isMOV {
	my $pathOrObj = shift;

	return isType($pathOrObj, 'mov');
}

sub isAIFF {
	my $pathOrObj = shift;

	return isType($pathOrObj, 'aif');
}

sub isSong {
	my $pathOrObj = shift;
	my $type = shift;

	$type = ref $pathOrObj ? $pathOrObj->content_type : $currentDB->contentType($pathOrObj) unless defined $type;

	if ($type && $slimTypes{$type} && $slimTypes{$type} eq 'audio') {
		return $type;
	}
}

sub isDir {
	my $pathOrObj = shift;

	return isType($pathOrObj, 'dir');
}

sub isM3U {
	my $pathOrObj = shift;

	return isType($pathOrObj, 'm3u');
}

sub isPLS {
	my $pathOrObj = shift;

	return isType($pathOrObj, 'pls');
}

sub isCUE {
	my $pathOrObj = shift;

	return isType($pathOrObj, 'cue') || isType($pathOrObj, 'fec');
}

sub isKnownType {
	my $pathOrObj = shift;

	return !isType($pathOrObj, 'unk');
}

sub isList {
	my $pathOrObj = shift;
	my $type = shift;

	$type = ref $pathOrObj ? $pathOrObj->content_type : $currentDB->contentType($pathOrObj) unless defined $type;

	if ($type && $slimTypes{$type} && $slimTypes{$type} =~ /list/) {
		return $type;
	}
}

sub isPlaylist {
	my $pathOrObj = shift;
	my $type = shift;

	$type = ref $pathOrObj ? $pathOrObj->content_type : $currentDB->contentType($pathOrObj) unless defined $type;

	if ($type && $slimTypes{$type} && $slimTypes{$type} eq 'playlist') {
		return $type;
	}
}

sub isContainer {
	my $pathOrObj = shift;

	for my $type (qw{cur fec}) {
		if (isType($pathOrObj, $type)) {
			return 1;
		}
	}

	return 0;
}

sub validTypeExtensions {

	# Try and use the pre-computed version
	if ($validTypeRegex) {
		return $validTypeRegex;
	}

	my @extensions = ();

	while (my ($ext, $type) = each %slimTypes) {

		next unless $type;
		next unless $type =~ /(?:list|audio)/;

		while (my ($suffix, $value) = each %suffixes) {

			if ($ext eq $value && $suffix !~ /playlist:/) {
				push @extensions, $suffix;
			}
		}
	}

	my $regex = join('|', @extensions);

	$validTypeRegex = qr/\.(?:$regex)$/;

	return $validTypeRegex;
}

sub mimeType {
	my $file = shift;

	my $contentType = contentType($file);

	foreach my $mt (keys %mimeTypes) {
		if ($contentType eq $mimeTypes{$mt}) {
			return $mt;
		}
	}
	return undef;
};

sub mimeToType {
	return $mimeTypes{lc(shift)};
}

sub contentType { 
	my $url = shift;

	return $currentDB->contentType($url); 
}

sub typeFromSuffix {
	my $path = shift;
	my $defaultType = shift || 'unk';
	
	if (defined $path && $path =~ /\.([^.]+)$/) {
		return $suffixes{lc($1)};
	}

	return $defaultType;
}

sub typeFromPath {
	my $fullpath = shift;
	my $defaultType = shift || 'unk';
	my $type;

	if (defined($fullpath) && $fullpath ne "" && $fullpath !~ /\x00/) {

		# Return quickly if we have it in the cache.
		if (defined $urlToTypeCache{$fullpath}) {

			$type = $urlToTypeCache{$fullpath};
			
			return $type if $type ne 'unk';

		} elsif ($fullpath =~ /^([a-z]+:)/ && defined($suffixes{$1})) {

			$type = $suffixes{$1};

		} elsif (isRemoteURL($fullpath)) {

			$type = typeFromSuffix($fullpath, $defaultType);

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
					# file doesn't exist, go ahead and do typeFromSuffix
					$type = typeFromSuffix($filepath, $defaultType);
				}
			}
		}
	}
	
	if (!defined($type) || $type eq 'unk') {
		$type = $defaultType;
	}

	$urlToTypeCache{$fullpath} = $type;

	$::d_info && Slim::Utils::Misc::msg("$type file type for $fullpath\n");

	return $type;
}

# Dynamically load the formats modules.
sub loadTagFormatForType {
	my $type = shift;

	return if $tagFunctions{$type}->{'loaded'};

	$::d_info && Slim::Utils::Misc::msg("Trying to load $tagFunctions{$type}->{'module'}\n");

	eval "require $tagFunctions{$type}->{'module'}";

	if ($@) {

		Slim::Utils::Misc::msg("Couldn't load module: $tagFunctions{$type}->{'module'} : [$@]\n");
		Slim::Utils::Misc::bt();

	} else {

		$tagFunctions{$type}->{'loaded'} = 1;
	}
}

1;

__END__


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
