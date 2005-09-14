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

my ($currentDB, $elemstring, $validTypeRegex);

my (@elements, $elemRegex, %parsedFormats);

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
	# Allow external programs to use Slim::Utils::Misc, without needing
	# the entire DBI stack.
	require Slim::DataStores::DBI::DBIStore;

	$currentDB = Slim::DataStores::DBI::DBIStore->new();

	initParsedFormats();

	loadTypesConfig();

	# precompute the valid extensions
	validTypeExtensions();

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

	# Set info
	$MP3::Info::v2_to_v1_names{'TPA'} = 'SET';
	$MP3::Info::v2_to_v1_names{'TPOS'} = 'SEt';	

	# get conductors
	$MP3::Info::v2_to_v1_names{'TP3'} = 'CONDUCTOR';
	$MP3::Info::v2_to_v1_names{'TPE3'} = 'CONDUCTOR';
	
	$MP3::Info::v2_to_v1_names{'TBP'} = 'BPM';
	$MP3::Info::v2_to_v1_names{'TBPM'} = 'BPM';

	$MP3::Info::v2_to_v1_names{'ULT'} = 'LYRICS';
	$MP3::Info::v2_to_v1_names{'USLT'} = 'LYRICS';

	# iTunes writes out it's own tag denoting a compilation
	$MP3::Info::v2_to_v1_names{'TCMP'} = 'COMPILATION';
}

sub getCurrentDataStore {
	return $currentDB;
}

sub loadTypesConfig {
	my @typesFiles;
	$::d_info && msg("loading types config file...\n");
	
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

sub resetClientsToHomeMenu {

	# Force all clients back to the home menu - otherwise if they are in a
	# menu that has objects that might change out from under
	# them, we're hosed, and serve a ::Deleted object.
	for my $client (Slim::Player::Client->clients) {

		$client->showBriefly($client->string('RESCANNING_SHORT'), '');

		Slim::Buttons::Common::setMode($client, 'home');
	}
}

sub saveDBCache {
	$currentDB->forceCommit();
}

sub wipeDBCache {
	resetClientsToHomeMenu();
	$currentDB->wipeAllData();
}

sub clearStaleCacheEntries {
	resetClientsToHomeMenu();
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
	my $type = shift;

	if (!defined $currentDB) {
		return;
	}

	resetClientsToHomeMenu();
	$currentDB->wipeCaches;

	# Didn't specify a type? Clear everything
	if (!defined $type) {

		$currentDB->clearExternalPlaylists;
		$currentDB->clearInternalPlaylists;

		return;
	}

	if ($type eq 'internal') {

		$currentDB->clearInternalPlaylists;

	} else {

		$currentDB->clearExternalPlaylists($type);
	}
}

sub cacheItem {
	my $url = shift;
	my $item = shift;

	$::d_info_v && msg("CacheItem called for item $item in $url\n");

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
		msg("No URL specified for updateCacheEntry\n");
		msg(%{$cacheEntryHash});
		bt();
		return;
	}

	if (!isURL($url)) { 
		msg("Non-URL passed to updateCacheEntry::info ($url)\n");
		bt();
		$url = Slim::Utils::Misc::fileURLFromPath($url); 
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
		$::d_info && msg("Info: truncating content type.  Was: $type, now: $1\n");
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

	$::d_info && msg("Content type for $url is cached as $type\n");
}

sub title {
	my $url = shift;

	my $track = $currentDB->objectForUrl($url, 1, 1) || return '';

	if (ref($track)) {
		return $track->title;
	}
}

sub setTitle {
	my $url = shift;
	my $title = shift;

	$::d_info && msg("Adding title $title for $url\n");

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

sub initParsedFormats {
	%parsedFormats = ();

	# for relating track attributes to album/artist attributes
	my @trackAttrs = ();

	# Pull the class for the track attributes
	my $trackClass = $currentDB->classForType('track');

	# Subs for all regular track attributes
	for my $attr (keys %{$trackClass->attributes}) {

		$parsedFormats{uc $attr} = sub {

			my $output = $_[0]->get($attr);
			return (defined $output ? $output : '');
		};
	}

	# Override album
	$parsedFormats{'ALBUM'} = 
		sub {
			my $output = '';
			my $album = $_[0]->album();
			if ($album) {
				$output = $album->title();
				$output = '' if $output eq string('NO_ALBUM');
			}
			return (defined $output ? $output : '');
		};

	# add album related
	@trackAttrs = qw(ALBUMSORT DISC DISCC);
	for my $attr (qw(namesort  disc discc)) {
		$parsedFormats{shift @trackAttrs} = 
			sub {
				my $output = '';
				my $album = $_[0]->album();
				if ($album) {
					$output = $album->get($attr);
				}
				return (defined $output ? $output : '');
			};
	}

	# add artist related
	$parsedFormats{'ARTIST'} = 
		sub {
			my @output  = ();
			my @artists = $_[0]->artists;

			for my $artist (@artists) {

				my $name = $artist->get('name');

				next if $name eq string('NO_ARTIST');

				push @output, $name;
			}

			return (scalar @output ? join(' & ', @output) : '');
		};

	$parsedFormats{'ARTISTSORT'} = 
		sub {
			my $output = '';
			my $artist = $_[0]->artist();
			if ($artist) {
				$output = $artist->get('namesort');
			}
			return (defined $output ? $output : '');
		};

	# add other contributors
	for my $attr (qw(composer conductor band genre)) {
		$parsedFormats{uc($attr)} = 
			sub {
				my $output = '';
				my ($item) = $_[0]->$attr();
				if ($item) {
					$output = $item->name();
				}
				return (defined $output ? $output : '');
			};
	}

	# add genre
	$parsedFormats{'GENRE'} = 
		sub {
			my $output = '';
			my ($item) = $_[0]->genre();
			if ($item) {
				$output = $item->name();
				$output = '' if $output eq string('NO_GENRE');
			}
			return (defined $output ? $output : '');
		};

	# add comment and duration
	for my $attr (qw(comment duration)) {
		$parsedFormats{uc($attr)} = 
			sub {
				my $output = $_[0]->$attr();
				return (defined $output ? $output : '');
			};
	}
	
	# add file info
	$parsedFormats{'VOLUME'} =
		sub {
			my $output = '';
			my $url = $_[0]->get('url');
			my $filepath;
			if ($url) {
				if (isFileURL($url)) { $url=Slim::Utils::Misc::pathFromFileURL($url); }
				$output = (splitpath($url))[0];
			}
			return (defined $output ? $output : '');
		};
	$parsedFormats{'PATH'} =
		sub {
			my $output = '';
			my $url = $_[0]->get('url');
			my $filepath;
			if ($url) {
				if (isFileURL($url)) { $url=Slim::Utils::Misc::pathFromFileURL($url); }
				$output = (splitpath($url))[1];
			}
			return (defined $output ? $output : '');
		};
	$parsedFormats{'FILE'} =
		sub {
			my $output = '';
			my $url = $_[0]->get('url');
			my $filepath;
			if ($url) {
				if (isFileURL($url)) { $url=Slim::Utils::Misc::pathFromFileURL($url); }
				$output = (splitpath($url))[2];
				$output =~ s/\.[^\.]*?$//;
			}
			return (defined $output ? $output : '');
		};
	$parsedFormats{'EXT'} =
		sub {
			my $output = '';
			my $url = $_[0]->get('url');
			my $filepath;
			if ($url) {
				if (isFileURL($url)) { $url=Slim::Utils::Misc::pathFromFileURL($url); }
				my $file = (splitpath($url))[2];
				($output) = $file =~ /\.([^\.]*?)$/;
			}
			return (defined $output ? $output : '');
		};

	# Add date/time elements
	$parsedFormats{'LONGDATE'}  = \&Slim::Utils::Misc::longDateF;
	$parsedFormats{'SHORTDATE'} = \&Slim::Utils::Misc::shortDateF;
	$parsedFormats{'CURRTIME'}  = \&Slim::Utils::Misc::timeF;
	
	# Add localized from/by
	$parsedFormats{'FROM'} = sub { return string('FROM'); };
	$parsedFormats{'BY'}   = sub { return string('BY'); };

	# fill element related variables
	@elements = keys %parsedFormats;

	# add placeholder element for bracketed items
	push @elements, '_PLACEHOLDER_';

	$elemstring = join "|", @elements;
	$elemRegex = qr/$elemstring/;

	# Add lightweight FILE.EXT format
	$parsedFormats{'FILE.EXT'} =
		sub {
			my $output = '';
			my $url = $_[0]->get('url');
			my $filepath;
			if ($url) {
				if (isFileURL($url)) { $url=Slim::Utils::Misc::pathFromFileURL($url); }
				$output = (splitpath($url))[2];
			}
			return (defined $output ? $output : '');
		};

}

sub addFormat {
	my $format = shift;
	my $formatSubRef = shift;
	
	# only add format if it is not already defined
	if (!defined $parsedFormats{$format}) {
		$parsedFormats{$format} = $formatSubRef;
		$::d_info && msg("Format $format added.\n");
	} else {
		$::d_info && msg("Format $format already exists.\n");
	}
	
	if ($format !~ /\D/) {
		# format is a single word, so make it an element
		push @elements, $format;
		$elemstring = join "|", @elements;
		$elemRegex = qr/$elemstring/;
	}
}

my %endbrackets = (
		'(' => qr/(.+?)(\))/,
		'[' => qr/(.+?)(\])/,
		'{' => qr/(.+?)(\})/,
		'"' => qr/(.+?)(")/, # " # syntax highlighters are easily confused
		"'" => qr/(.+?)(')/, # ' # syntax highlighters are easily confused
		);

my $bracketstart = qr/(.*?)([{[("'])/; # '" # syntax highlighters are easily confused

# The fillFormat routine takes a track and references to parsed data arrays describing
# a desired information format and returns a string containing the formatted data.
# The prefix array contains separator elements that should only be included in the output
#   if the corresponding element contains data, and any element preceding it contained data.
# The indprefix array is like the prefix array, but it only requires the corresponding
#   element to contain data.
# The elemlookup array contains code references which are passed the track object and return
#   a string if that track has data for that element.
# The suffix array contains separator elements that should only be included if the corresponding
#   element contains data.
# The data for each item is placed in the string in the order prefix + indprefix + element + suffix.

sub fillFormat {
	my ($track, $prefix, $indprefix, $elemlookup, $suffix) = @_;
	my $output = '';
	my $hasPrev;
	my $index = 0;
	for my $elemref (@{$elemlookup}) {
		my $elementtext = $elemref->($track);
		if (defined($elementtext) && $elementtext gt '') {
			# The element had a value, so build this portion of the output.
			# Add in the prefix only if some previous element also had a value
			$output .= join('', ($hasPrev ? $prefix->[$index] : ''),
					$indprefix->[$index],
					$elementtext,
					$suffix->[$index]);
			$hasPrev ||= 1;
		}
		$index++;
	}
	return $output;
}

sub parseFormat {
	my $format = shift;
	my $formatparsed = $format; # $format will be modified, so stash the original value
	my $newstr = '';
	my (@parsed, @placeholders, @prefixes, @indprefixes, @elemlookups, @suffixes);

	# don't rebuild formats
	return $parsedFormats{$format} if exists $parsedFormats{$format};

	# find bracketed items so that we can collapse them correctly
	while ($format =~ s/$bracketstart//) {
		$newstr .= $1 . $2;
		my $endbracketRegex = $endbrackets{$2};
		if ($format =~ s/$endbracketRegex//) {
			push @placeholders, $1;
			$newstr .= '_PLACEHOLDER_' . $2;
		}
	}
	$format = $newstr . $format;

	# break up format string into separators and elements
	# elements must be separated by non-word characters
	@parsed = ($format =~ m/(.*?)\b($elemRegex)\b/gc);
	push @parsed, substr($format,pos($format) || 0);

	if (scalar(@parsed) < 2) {
		# pure text, just return that text as the function
		my $output = shift(@parsed);
		$parsedFormats{$formatparsed} = sub { return $output; };
		return $parsedFormats{$formatparsed};
	}

	# Every other item in the parsed array is an element, which will be replaced later
	# by a code reference which will return a string to replace the element
	while (scalar(@parsed) > 1) {
		push @prefixes, shift(@parsed);
		push @indprefixes, '';
		push @elemlookups, shift(@parsed);
		push @suffixes, '';
	}

	# the first item will never have anything before it, so move it from the prefixes array
	# to the independent prefixes array
	$indprefixes[0] = $prefixes[0];
	$prefixes[0] = '';

	# if anything is left in the parsed array (there were an odd number of items, put it in
	# as the last item in the suffixes array
	if (@parsed) {
		$suffixes[-1] = $parsed[0];
	}

	# replace placeholders with their original values, and replace the element text with the
	# code references to look up the value for the element.
	my $index = 0;
	for my $elem (@elemlookups) {
		if ($elem eq '_PLACEHOLDER_') {
			$elemlookups[$index] = shift @placeholders;
			if ($index < $#prefixes) {
				# move closing bracket from the prefix of the element following
				# to the suffix of the current element
				$suffixes[$index] = substr($prefixes[$index + 1],0,1,'');
			}
			if ($index) {
				# move opening bracket from the prefix dependent on previous content
				# to the independent prefix for this element, but only attempt this
				# when this isn't the first element, since that has already had the
				# prefix moved to the independent prefix
				$indprefixes[$index] = substr($prefixes[$index],length($prefixes[$index]) - 1,1,'');
			}
		}
		# replace element with code ref from parsed formats. If the element does not exist in
		# the hash, it needs to be parsed and created.
		$elemlookups[$index] = $parsedFormats{$elem} || parseFormat($elem);
		$index++;
	}

	$parsedFormats{$formatparsed} =
		sub {
			my $track = shift;
			return fillFormat($track, \@prefixes, \@indprefixes, \@elemlookups, \@suffixes);
		};
	
	return $parsedFormats{$formatparsed};
}

sub infoFormat {
	my $fileOrObj = shift; # item whose information will be formatted
	my $str = shift; # format string to use
	my $safestr = shift; # format string to use in the event that after filling the first string, there is nothing left
	my $output = '';
	my $format;

	my $track = ref $fileOrObj ? $fileOrObj  : $currentDB->objectForUrl($fileOrObj, 1);

	return '' unless defined $track;
	
	# use a safe format string if none specified
	# Users can input strings in any locale - we need to convert that to
	# UTF-8 first, otherwise perl will segfault in the nasty regex below.
	if ($str && $] > 5.007) {

		eval {
			Encode::from_to($str, $Slim::Utils::Unicode::locale, 'utf8');
			Encode::_utf8_on($str);
		};

	} elsif (!defined $str) {

		$str = 'TITLE';
	}

	# Get the formatting function from the hash, or parse it
	$format = $parsedFormats{$str} || parseFormat($str);

	$output = $format->($track) if ref($format) eq 'CODE';

	if ($output eq "" && defined($safestr)) {

		# if there isn't any output, use the safe string, if supplied
		return infoFormat($track,$safestr);

	} else {
		$output =~ s/%([0-9a-fA-F][0-9a-fA-F])%/chr(hex($1))/eg;
	}

	return $output;
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

	$::d_info && msg("Plain title for: " . $file . "\n");

	if (isRemoteURL($file)) {
		$title = Slim::Web::HTTP::unescape($file);
	} else {
		if (isFileURL($file)) {
			$file = Slim::Utils::Misc::pathFromFileURL($file);
			$file = Slim::Utils::Unicode::utf8decode_locale($file);
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
	
	$::d_info && msg(" is " . $title . "\n");

	return $title;
}

# get a potentially client specifically formatted title.
sub standardTitle {
	my $client    = shift;
	my $pathOrObj = shift; # item whose information will be formatted

	# Be sure to try and "readTags" - which may call into Formats::Parse for playlists.
	my $track     = ref $pathOrObj ? $pathOrObj : $currentDB->objectForUrl($pathOrObj, 1, 1);
	my $fullpath  = ref $track ? $track->url : $pathOrObj;
	my $format;

	if (isPlaylistURL($fullpath) || isList($track)) {

		$format = 'TITLE';

	} elsif (defined($client)) {

		# in array syntax this would be
		# $titleFormat[$clientTitleFormat[$clientTitleFormatCurr]] get
		# the title format

		$format = Slim::Utils::Prefs::getInd("titleFormat",
			# at the array index of the client titleformat array
			$client->prefGet("titleFormat",
				# which is currently selected
				$client->prefGet('titleFormatCurr')
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

	$::d_info && msg("Guessing tags for: $file\n");

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
		$pat =~ s/($elemRegex)/\(\[^\\\/\]\+\)/g;

		$::d_info && msg("Using format \"$guess\" = /$pat/...\n" );

		$pat = qr/$pat/;

		# Check if this format matches		
		my @matches = ();

		if (@matches = $file =~ $pat) {

			$::d_info && msg("Format string $guess matched $file\n" );

			my @tags = $guess =~ /($elemRegex)/g;

			my $i = 0;

			foreach my $match (@matches) {

				$::d_info && msg("$tags[$i] => $match\n");

				$match =~ tr/_/ / if (defined $match);

				$match = int($match) if $tags[$i] =~ /TRACKNUM|DISC{1,2}/;
				$taghash->{$tags[$i++]} = Slim::Utils::Unicode::utf8decode_locale($match);
			}

			return;
		}
	}
	
	# Nothing found; revert to plain title
	$taghash->{'TITLE'} = plainTitle($filename, $type);	
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

		if (defined $track && ref $track && $track->can('url')) {

			push @urls, $track->url();

		} else {

			$::d_info && msgf("Invalid track object for playlist [%s]!\n", $obj->url);
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
	
	$::d_info && msg("cached an " . (scalar @$list) . " item playlist for $url\n");
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

	return Slim::Utils::Unicode::utf8decode_locale($j);
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

	defined($$contentref) && length($$contentref) || $::d_artwork && msg("Image File empty or couldn't read: $path\n");
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
	
	$::d_artwork && msg("Updating image for $fullpath\n");
	
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
				$::d_artwork && msg("Looking for image in ID3 2.2 tag in file $file\n");
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
						
						$::d_artwork && msg( "PIC format: $format length: " . length($pic) . "\n");

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
							
							$::d_artwork && msg( "APIC format: $format length: " . length($data) . "\n");
	
							if (length($data)) {
								$contenttype = $format;
								$body = $data;
							}
						}
					}
				}
			}

		} elsif (isMOV($fullpath)) {

			$::d_artwork && msg("Looking for image in Movie metadata in file $file\n");

			loadTagFormatForType('mov');

			$body = Slim::Formats::Movie::getCoverArt($file);

			$::d_artwork && $body && msg("found image in $file of length " . length($body) . " bytes \n");
		}
		
		if ($body) {
			# iTunes sometimes puts PNG images in and says they are jpeg
			if ($body =~ /^\x89PNG\x0d\x0a\x1a\x0a/) {
				$::d_info && msg( "found PNG image\n");
				$contenttype = 'image/png';
			} elsif ($body =~ /^\xff\xd8\xff\xe0..JFIF/) {
				$::d_info && msg( "found JPEG image\n");
				$contenttype = 'image/jpeg';
			}
			
			# jpeg images must start with ff d8 ff e0 or they ain't jpeg, sometimes there is junk before.
			if ($contenttype && $contenttype eq 'image/jpeg')	{
				$body =~ s/^.*?\xff\xd8\xff\xe0/\xff\xd8\xff\xe0/;
			}
		}

 	} else {

 		$::d_info && msg("readCoverArtTags: Not a song, skipping: $fullpath\n");
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

	$::d_artwork && msg("Looking for image files in ".catdir(@components)."\n");

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

		$::d_artwork && msgf(
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

			$::d_artwork && msg("Found $image file: $artpath\n\n");

			$contentType = mimeType(Slim::Utils::Misc::fileURLFromPath($artpath));

			return ($body, $contentType, $artpath);
		}

	} elsif (defined $artwork) {

		unshift @filestotry, $artwork;
	}

	if (defined $artworkDir && $artworkDir eq catdir(@components)) {

		if (exists $lastFile{$image}  && $lastFile{$image} ne '1') {

			$::d_artwork && msg("Using existing $image: $lastFile{$image}\n");

			$body = getImageContent($lastFile{$image});

			$contentType = mimeType(Slim::Utils::Misc::fileURLFromPath($lastFile{$image}));

			$artwork = $lastFile{$image};

			return ($body, $contentType, $artwork);

		} elsif (exists $lastFile{$image}) {

			$::d_artwork && msg("No $image in $artworkDir\n");

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
			$::d_artwork && msg("Found $image file: $file\n\n");

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

	# Handle Vorbis comments where the tag can be an array.
	if (ref($tag) eq 'ARRAY') {

		return @$tag;
	}

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

				$::d_info && msg("Splitting $tag by $splitOn = @temp\n") unless scalar @temp <= 1;
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
	return 0 unless $suffixes{ lc((split /\./, $fullpath)[-1]) };

	my $stat = (-f $fullpath && -r $fullpath ? 1 : 0);

	$::d_info && msgf("isFile(%s) == %d\n", $fullpath, (1 * $stat));

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

	$validTypeRegex = qr/\.(?:$regex)$/i;

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
				$::d_info && msg("Converting $fullpath to $filepath\n");
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

	$::d_info && msg("$type file type for $fullpath\n");

	return $type;
}

# Dynamically load the formats modules.
sub loadTagFormatForType {
	my $type = shift;

	return if $tagFunctions{$type}->{'loaded'};

	$::d_info && msg("Trying to load $tagFunctions{$type}->{'module'}\n");

	eval "require $tagFunctions{$type}->{'module'}";

	if ($@) {

		msg("Couldn't load module: $tagFunctions{$type}->{'module'} : [$@]\n");
		bt();

	} else {

		$tagFunctions{$type}->{'loaded'} = 1;
	}
}

sub variousArtistString {

	return (Slim::Utils::Prefs::get('variousArtistsString') || string('VARIOUSARTISTS'));
}

1;

__END__


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
