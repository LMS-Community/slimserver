package Slim::Music::Info;

# $Id$

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use File::Path;
use File::Spec::Functions qw(:ALL);
use Path::Class;
use Scalar::Util qw(blessed);
use Tie::Cache::LRU;

use Slim::Music::TitleFormatter;
use Slim::Player::ProtocolHandlers;
use Slim::Utils::Misc;
use Slim::Utils::PluginManager;
use Slim::Utils::OSDetect;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Text;
use Slim::Utils::Unicode;

# three hashes containing the types we know about, populated by the loadTypesConfig routine below
# hash of default mime type index by three letter content type e.g. 'mp3' => audio/mpeg
our %types = ();

# hash of three letter content type, indexed by mime type e.g. 'text/plain' => 'txt'
our %mimeTypes = ();

# hash of three letter content types, indexed by file suffixes (past the dot)  'aiff' => 'aif'
our %suffixes = ();

# hash of types that the slim server recoginzes internally e.g. aif => audio
our %slimTypes = ();

# Make sure that these can't grow forever.
tie our %displayCache, 'Tie::Cache::LRU', 64;
tie our %currentTitles, 'Tie::Cache::LRU', 64;

our %currentTitleCallbacks = ();
our $validTypeRegex = undef;

# Save our stats.
tie our %isFile, 'Tie::Cache::LRU', 16;

# No need to do this over and over again either.
tie our %urlToTypeCache, 'Tie::Cache::LRU', 16;

# Map our tag functions - so they can be dynamically loaded.
our (%tagClasses, %loadedTagClasses);

sub init {

	# Allow external programs to use Slim::Utils::Misc, without needing
	# the entire DBI stack.
	require Slim::Schema;
	Slim::Schema->init;

	Slim::Music::TitleFormatter::init();

	loadTypesConfig();

	# precompute the valid extensions
	validTypeExtensions();

	# Our loader classes for tag formats.
	%tagClasses = (
		'mp3' => 'Slim::Formats::MP3',
		'mp2' => 'Slim::Formats::MP3',
		'ogg' => 'Slim::Formats::Ogg',
		'flc' => 'Slim::Formats::FLAC',
		'wav' => 'Slim::Formats::Wav',
		'aif' => 'Slim::Formats::AIFF',
		'wma' => 'Slim::Formats::WMA',
		'mov' => 'Slim::Formats::Movie',
		'shn' => 'Slim::Formats::Shorten',
		'mpc' => 'Slim::Formats::Musepack',
		'ape' => 'Slim::Formats::APE',

		# Playlist types
		'asx' => 'Slim::Formats::Playlists::ASX',
		'cue' => 'Slim::Formats::Playlists::CUE',
		'm3u' => 'Slim::Formats::Playlists::M3U',
		'pls' => 'Slim::Formats::Playlists::PLS',
		'wpl' => 'Slim::Formats::Playlists::WPL',
		'wax' => 'Slim::Formats::Playlists::ASX',
		'xpf' => 'Slim::Formats::Playlists::XSPF',

		# Remote types
		'http' => 'Slim::Formats::HTTP',
		'mms'  => 'Slim::Formats::MMS',
	);
}

sub getCurrentDataStore {
	msg("Warning: Slim::Music::Info::getCurrentDataStore() is deprecated. Please use Slim::Schema directly.\n");

	return 'Slim::Schema';
}

sub loadTypesConfig {
	my @typesFiles = ();

	$::d_info && msg("loading types config file...\n");

	# custom types file allowed at server root or root of plugin directories
	for my $baseDir (Slim::Utils::OSDetect::dirsFor('types')) {
	
		push @typesFiles, catdir($baseDir, 'types.conf');
		push @typesFiles, catdir($baseDir, 'custom-types.conf');
	}

	foreach my $baseDir (Slim::Utils::PluginManager::pluginRootDirs()) {

		push @typesFiles, catdir($baseDir, 'custom-types.conf');
	}

	foreach my $typeFileName (@typesFiles) {

		if (open my $typesFile, $typeFileName) {

			for my $line (<$typesFile>) {

				# get rid of comments and leading and trailing white space
				$line =~ s/#.*$//;
				$line =~ s/^\s//;
				$line =~ s/\s$//;
	
				if ($line =~ /^(\S+)\s+(\S+)\s+(\S+)\s+(\S+)/) {

					my $type = $1;
					my @suffixes  = split ',', $2;
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

	if (!$INC{'Slim/Player/Client.pm'}) {
		return;
	}

	# Force all clients back to the home menu - otherwise if they are in a
	# menu that has objects that might change out from under
	# them, we're hosed, and serve a ::Deleted object.
	for my $client (Slim::Player::Client->clients) {

		$client->showBriefly($client->string('RESCANNING_SHORT'), '');

		Slim::Buttons::Common::setMode($client, 'home');
	}
}

sub wipeDBCache {

	resetClientsToHomeMenu();
	clearFormatDisplayCache();

	Slim::Schema->wipeAllData();

	# Remove any HTML templates we have around.
	if ($INC{'Slim/Web/HTTP.pm'}) {

		rmtree( Slim::Web::HTTP::templateCacheDir() );
	}
}

sub clearStaleCacheEntries {
	resetClientsToHomeMenu();
	Slim::Schema->clearStaleEntries();
}

sub clearFormatDisplayCache {

	%displayCache  = ();
	%currentTitles = ();
}

sub playlistForClient {
	my $client = shift;

	return Slim::Schema->rs('Playlist')->getPlaylistForClient($client);
}

sub clearPlaylists {
	my $type = shift;

	resetClientsToHomeMenu();

	Slim::Schema->forceCommit;

	my $rs = Slim::Schema->rs('Playlist');

	# Didn't specify a type? Clear everything
	if (!defined $type) {

		$rs->clearExternalPlaylists;
		$rs->clearInternalPlaylists;

		return;
	}

	if ($type eq 'internal') {

		$rs->clearInternalPlaylists;

	} else {

		$rs->clearExternalPlaylists($type);
	}
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

	my $list     = $cacheEntryHash->{'LIST'} || [];

	my $playlist = Slim::Schema->updateOrCreate({
		'url'        => $url,
		'playlist'   => 1,
		'attributes' => $cacheEntryHash,
	});

	if (ref($list) eq 'ARRAY' && blessed($playlist) && $playlist->can('setTracks')) {

		my @tracks = ();

		for my $url (@$list) {

			push @tracks, Slim::Schema->objectForUrl({
				'url'    => $url,
				'create' => 1,
			});
		}

		if (scalar @tracks) {
			$playlist->setTracks(\@tracks);
		}
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
	Slim::Schema->updateOrCreate({
		'url'        => $url,
		'attributes' => { 'CT' => $type },
		'commit'     => 1,
		'readTags'   => isRemoteURL($url) ? 0 : 1,
	});

	$::d_info && msg("Content type for $url is cached as $type\n");
}

sub title {
	my $url = shift;

	my $track = Slim::Schema->updateOrCreate({
		'url'      => $url,
		'commit'   => 1,
		'readTags' => isRemoteURL($url) ? 0 : 1,
	});

	return $track->title;
}

sub setTitle {
	my $url = shift;
	my $title = shift;

	$::d_info && msg("Adding title $title for $url\n");

	# Only readTags if we're not a remote URL. Otherwise, we'll
	# overwrite the title with the URL.
	Slim::Schema->updateOrCreate({
		'url'        => $url,
		'attributes' => { 'TITLE' => $title },
		'readTags'   => isRemoteURL($url) ? 0 : 1,
	});
}

sub setBitrate {
	my $url = shift;
	my $bitrate = shift;

	Slim::Schema->updateOrCreate({
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
		$title = Slim::Utils::Misc::unescape($file);
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
	# XXX - exception should go here. comming soon.
	my $track     = Slim::Schema->objectForUrl({ 'url' => $pathOrObj, 'create' => 1, 'readTags' => 1 });
	my $fullpath  = blessed($track) && $track->can('url') ? $track->url : $track;
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

	my $ref = $displayCache{$client} ||= {
		'fullpath' => '',
		'format'   => '',
	};

	if ($fullpath ne $ref->{'fullpath'} || $format ne $ref->{'format'}) {

		$ref = $displayCache{$client} = {
			'fullpath' => $fullpath,
			'format'   => $format,
			'display'  => Slim::Music::TitleFormatter::infoFormat($track, $format, 'TITLE'),
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

		$file = Slim::Utils::Misc::unescape($file);

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
		$pat =~ s/($Slim::Music::TitleFormatter::elemRegex)/\(\[^\\\/\]\+\)/g;

		$::d_info && msg("Using format \"$guess\" = /$pat/...\n" );

		$pat = qr/$pat/;

		# Check if this format matches		
		my @matches = ();

		if (@matches = $file =~ $pat) {

			$::d_info && msg("Format string $guess matched $file\n" );

			my @tags = $guess =~ /($Slim::Music::TitleFormatter::elemRegex)/g;

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
	my $playlist = Slim::Schema->objectForUrl({
		'url'      => $urlOrObj,
		'playlist' => 1,
	});

	if (!blessed($playlist) || !$playlist->can('tracks')) {

		return undef;
	}

	# We want any PlayListTracks this item may have
	my @urls = ();

	for my $track ($playlist->tracks) {

		if (blessed($track) && $track->can('url')) {

			push @urls, $track->url;

		} else {

			$::d_info && msgf("Invalid track object for playlist [%s]!\n", $playlist->url);
		}
	}

	# Otherwise, we're actually a directory.
	if (!scalar @urls) {
		@urls = $playlist->diritems;
	}

	return \@urls if scalar(@urls);

	return undef;
}

sub fileName {
	my $j = shift;

	if (isFileURL($j)) {
		$j = Slim::Utils::Misc::pathFromFileURL($j);
		if ($j) {
			$j = (splitdir($j))[-1];
		}
	} elsif (isRemoteURL($j)) {
		$j = Slim::Utils::Misc::unescape($j);
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
	
	# We access MMS via HTTP, so it counts as an HTTP URL
	return 1 if isMMSURL($url);

	return (defined($url) && ($url =~ /^(http|icy):\/\//i));
}

sub isMMSURL {
	my $url = shift;

	return (defined($url) && ($url =~ /^mms:\/\//i));
}

sub isRemoteURL {
	my $url = shift || return 0;

	if ($url =~ /^([a-zA-Z0-9\-]+):/ && Slim::Player::ProtocolHandlers->isValidHandler($1)) {

		return 1;
	}

	return 0;
}

sub isPlaylistURL {
	my $url = shift || return 0;

	if ($url =~ /^([a-zA-Z0-9\-]+):/ && Slim::Player::ProtocolHandlers->isValidHandler($1) && !isFileURL($url)) {

		return 1;
	}

	return 0;
}

sub isURL {
	my $url = shift || return 0;

	if ($url =~ /^([a-zA-Z0-9\-]+):/ && defined Slim::Player::ProtocolHandlers->isValidHandler($1)) {

		return 1;
	}

	return 0;
}

sub _isContentTypeHelper {
	my $pathOrObj = shift;
	my $type      = shift;

	if (!defined $type) {

		# XXX - exception should go here. comming soon.
		if (blessed($pathOrObj) && $pathOrObj->can('content_type')) {

			$type = $pathOrObj->content_type;

		} else {

			$type = Slim::Schema->contentType($pathOrObj);
		}
	}

	return $type;
}

sub isType {
	my $pathOrObj = shift || return 0;
	my $testType  = shift;
	my $type      = shift || _isContentTypeHelper($pathOrObj);

	if ($type && ($type eq $testType)) {
		return 1;
	} else {
		return 0;
	}
}

sub isWinShortcut {
	my $pathOrObj = shift;

	return isType($pathOrObj, 'lnk', @_);
}

sub isMP3 {
	my $pathOrObj = shift;
	my $type      = shift;

	return isType($pathOrObj, 'mp3', $type) || isType($pathOrObj, 'mp2', $type);
}

sub isOgg {
	my $pathOrObj = shift;

	return isType($pathOrObj, 'ogg', @_);
}

sub isWav {
	my $pathOrObj = shift;

	return isType($pathOrObj, 'wav', @_);
}

sub isMOV {
	my $pathOrObj = shift;

	return isType($pathOrObj, 'mov', @_);
}

sub isFLAC {
	my $pathOrObj = shift;

	return isType($pathOrObj, 'flc', @_);
}

sub isAIFF {
	my $pathOrObj = shift;

	return isType($pathOrObj, 'aif', @_);
}

sub isSong {
	my $pathOrObj = shift;
	my $type      = shift || _isContentTypeHelper($pathOrObj);

	if ($type && $slimTypes{$type} && $slimTypes{$type} eq 'audio') {
		return $type;
	}
}

sub isDir {
	my $pathOrObj = shift;

	return isType($pathOrObj, 'dir', @_);
}

sub isM3U {
	my $pathOrObj = shift;

	return isType($pathOrObj, 'm3u', @_);
}

sub isPLS {
	my $pathOrObj = shift;

	return isType($pathOrObj, 'pls', @_);
}

sub isCUE {
	my $pathOrObj = shift;
	my $type      = shift;

	return isType($pathOrObj, 'cue', $type) || isType($pathOrObj, 'fec', $type);
}

sub isKnownType {
	my $pathOrObj = shift;
	my $type      = shift;

	return !isType($pathOrObj, 'unk', $type);
}

sub isList {
	my $pathOrObj = shift;
	my $type      = shift || _isContentTypeHelper($pathOrObj);

	if ($type && $slimTypes{$type} && $slimTypes{$type} =~ /list/) {
		return $type;
	}
}

sub isPlaylist {
	my $pathOrObj = shift;
	my $type      = shift || _isContentTypeHelper($pathOrObj);

	if ($type && $slimTypes{$type} && $slimTypes{$type} eq 'playlist') {
		return $type;
	}
}

sub isContainer {
	my $pathOrObj = shift;
	my $type      = shift || _isContentTypeHelper($pathOrObj);

	for my $testType (qw(cur fec)) {

		if ($type eq $testType) {
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
	my $osType     = Slim::Utils::OSDetect::OS();

	while (my ($ext, $type) = each %slimTypes) {

		next unless $type;
		next unless $type =~ /(?:list|audio)/;

		while (my ($suffix, $value) = each %suffixes) {

			# Don't display .lnk files on Non-Windows machines!
			# We can't parse them. Bug: 2654
			if ($osType ne 'win' && $suffix eq 'lnk') {
				next;
			}

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

	return Slim::Schema->contentType($url); 
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

	# Remove the anchor if we're checking the suffix.
	my ($type, $anchorlessPath);

	if ($fullpath && $fullpath !~ /\x00/) {

		# Return quickly if we have it in the cache.
		if (defined $urlToTypeCache{$fullpath}) {

			$type = $urlToTypeCache{$fullpath};
			
			return $type if $type ne 'unk';

		}
		elsif ($fullpath =~ /^([a-z]+:)/ && defined($suffixes{$1})) {

			$type = $suffixes{$1};

		} 
		elsif ( $fullpath =~ /^(?:radioio|live365)/ ) {
			# Force mp3 for protocol handlers
			return 'mp3';
		}
		else {

			$anchorlessPath = Slim::Utils::Misc::stripAnchorFromURL($fullpath);

			# strip any parameters trailing url to allow types to be inferred from url ending
			if (isRemoteURL($anchorlessPath) && $anchorlessPath =~ /(.*)\?(.*)/) {
				$anchorlessPath = $1;
			}

			$type = typeFromSuffix($anchorlessPath, $defaultType);
		}
	}

	# We didn't get a type from above - try a little harder.
	if ((!defined($type) || $type eq 'unk') && $fullpath && $fullpath !~ /\x00/) {

		my $filepath;

		if (isFileURL($fullpath)) {
			$filepath = Slim::Utils::Misc::pathFromFileURL($fullpath);
		} else {
			$filepath = $fullpath;
		}

		if ($filepath) {

			$anchorlessPath = Slim::Utils::Misc::stripAnchorFromURL($filepath);

			if (-f $filepath) {

				if ($filepath =~ /\.lnk$/i && Slim::Utils::OSDetect::OS() eq 'win') {
					require Win32::Shortcut;
					if ((Win32::Shortcut->new($filepath)) ? 1 : 0) {
						$type = 'lnk';
					}

				} else {

					$type = typeFromSuffix($anchorlessPath, $defaultType);
				}

			} elsif (-d $filepath) {

				$type = 'dir';

			} else {

				# file doesn't exist, go ahead and do typeFromSuffix
				$type = typeFromSuffix($anchorlessPath, $defaultType);
			}
		}
	}

	if (!defined($type) || $type eq 'unk') {
		$type = $defaultType;
	}

	# Don't cache remote URL types, as they may change.
	if (!isRemoteURL($fullpath)) {

		$urlToTypeCache{$fullpath} = $type;
	}

	$::d_info && msg("$type file type for $fullpath\n");

	return $type;
}

# Dynamically load the formats modules.
sub loadTagFormatForType {
	my $type  = shift;

	return if $loadedTagClasses{$type};

	$::d_info && msg("Trying to load $tagClasses{$type}\n");

	eval "require $tagClasses{$type}";

	if ($@) {

		msg("Couldn't load module: $tagClasses{$type} : [$@]\n");
		bt();

	} else {

		$loadedTagClasses{$type} = 1;
	}
}

sub classForFormat {
	my $type  = shift;

	return $tagClasses{$type};
}

sub variousArtistString {

	return (Slim::Utils::Prefs::get('variousArtistsString') || string('VARIOUSARTISTS'));
}

sub infoFormat {

	errorMsg("Slim::Music::Info::infoFormat() has been deprecated!\n");
	errorMsg("Please notify the Plugin author to use Slim::Music::TitleFormatter::infoFormat() instead!\n");

	return Slim::Music::TitleFormatter::infoFormat(@_);
}

1;

__END__


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
