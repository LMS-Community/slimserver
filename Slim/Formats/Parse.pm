package Slim::Formats::Parse;

# $Id$

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use File::Spec::Functions qw(:ALL);
use FileHandle;
use IO::Socket qw(:crlf);
use IO::String;
use XML::Simple;
use URI::Escape;

use Slim::Music::Info;
use Slim::Utils::Misc;

if ($] > 5.007) {
	require File::BOM;
	require Encode;
}

our %playlistInfo = ( 
	'm3u' => [\&readM3U, \&writeM3U, '.m3u'],
	'pls' => [\&readPLS, \&writePLS, '.pls'],
	'cue' => [\&readCUE, undef, undef],
	'wpl' => [\&readWPL, \&writeWPL, '.wpl'],
	'asx' => [\&readASX, undef, '.asx'],
	'wax' => [\&readASX, undef, '.wax'],
	'xml' => [\&readPodcast, undef, undef],
	'pod' => [\&readPodcast, undef, undef],
);

sub registerParser {
	my ($type, $readfunc, $writefunc, $suffix) = @_;

	$::d_parse && Slim::Utils::Misc::msg("Registering external parser for type $type\n");

	$playlistInfo{$type} = [$readfunc, $writefunc, $suffix];
}

sub parseList {
	my $list = shift;
	my $file = shift;
	my $base = shift;
	
	my $type = Slim::Music::Info::contentType($list);
	my $parser;
	my @items = ();

	# This should work..
	if ($] > 5.007) {
		binmode($file, ":encoding($Slim::Utils::Misc::locale)");
	}

	if (exists $playlistInfo{$type} && ($parser = $playlistInfo{$type}->[0])) {
		return &$parser($file, $base, $list);
	}
}

sub writeList {
	my $listref = shift;
	my $playlistname = shift;
	my $fulldir = shift;
    
	my $type = Slim::Music::Info::typeFromSuffix($fulldir);
	my $writer;

	if (exists $playlistInfo{$type} && ($writer = $playlistInfo{$type}->[1])) {
		return &$writer($listref, $playlistname, Slim::Utils::Misc::pathFromFileURL($fulldir));
	}
}

sub getPlaylistSuffix {
	my $filepath = shift;

	my $type = Slim::Music::Info::contentType($filepath);

	if (exists $playlistInfo{$type}) {
		return $playlistInfo{$type}->[2];
	}

	return undef;
}

sub _updateMetaData {
	my $entry = shift;
	my $title = shift;

	my $ds    = Slim::Music::Info::getCurrentDataStore();
	my $track = $ds->objectForUrl($entry);

	my $attributes = {};

	# Update title MetaData only if its not a local file with Title information already cached.
	if (defined($title) && !(Slim::Music::Info::cacheItem($entry, 'TITLE') && Slim::Music::Info::isFileURL($entry))) {
		$attributes->{TITLE} = $title;
	}	

	$ds->updateOrCreate({
		'url' => $entry,
		'attributes' => $attributes,
		'readTags' => 1
	});
}

sub readM3U {
	my $m3u    = shift;
	my $m3udir = shift;

	my @items  = ();
	my $title;
	my $mode   = $Slim::Utils::Misc::locale;

	# Try to find a BOM on the file - otherwise default to the current locale.
	# XXX - should this move to Slim::Utils::Scan::readList() ?
	if ($] > 5.007) {

		binmode($m3u, ":raw");

		# Although get_encoding_from_filehandle tries to determine if
		# the handle is seekable or not - the Protocol handlers don't
		# implement a seek() method, and even if they did, File::BOM
		# internally would try to read(), which doesn't mix with
		# sysread(). So skip those m3u files entirely.
		my $enc;

		if (ref($m3u) !~ /(?:Slim::Player::Protocols|IO::String)/) {

			$enc = File::BOM::get_encoding_from_filehandle($m3u);
		}

		$mode = $enc if $enc;

		binmode($m3u, ":encoding($mode)");
	}

	$::d_parse && Slim::Utils::Misc::msg("parsing M3U: $m3u\n");

	while (my $entry = <$m3u>) {

		my $donttranslate = 0;
		# Turn the UTF-8 back into a sequences of octets -
		# fileURLFromPath will turn it back into UTF-8
		if ($] > 5.007 && $mode =~ /utf-?8/i) {
			if (Encode::is_utf8($entry, 1)) {
				$entry = Encode::encode_utf8($entry);
				$donttranslate = 1;
			}
		}

		chomp($entry);
		# strip carriage return from dos playlists
		$entry =~ s/\cM//g;  

		# strip whitespace from beginning and end
		$entry =~ s/^\s*//; 
		$entry =~ s/\s*$//; 

		$::d_parse && Slim::Utils::Misc::msg("  entry from file: $entry\n");

		if ($entry =~ /^#EXTINF:.*?,(.*)$/) {
			$title = $1;	
		}
		
		next if $entry =~ /^#/;
		next if $entry eq "";

		$entry =~ s|$LF||g;
		
		$entry = Slim::Utils::Misc::fixPath($entry, $m3udir, $donttranslate);
		
		$::d_parse && Slim::Utils::Misc::msg("    entry: $entry\n");

		_updateMetaData($entry, $title);
		$title = undef;
		push @items, $entry;
	}

	$::d_parse && Slim::Utils::Misc::msg("parsed " . scalar(@items) . " items in m3u playlist\n");

	close $m3u;

	return @items;
}

sub readPLS {
	my $pls = shift;

	my @urls   = ();
	my @titles = ();
	my @items  = ();
	
	# parse the PLS file format
	if ($] > 5.007) {
		binmode($pls, ":encoding($Slim::Utils::Misc::locale)");
	}

	$::d_parse && Slim::Utils::Misc::msg("Parsing playlist: $pls \n");
	
	while (<$pls>) {
		$::d_parse && Slim::Utils::Misc::msg("Parsing line: $_\n");

		# strip carriage return from dos playlists
		s/\cM//g;  

		# strip whitespace from end
		s/\s*$//; 
		
		if (m|File(\d+)=(.*)|i) {
			$urls[$1] = $2;
			next;
		}
		
		if (m|Title(\d+)=(.*)|i) {
			$titles[$1] = $2;
			next;
		}	
	}

	for (my $i = 1; $i <= $#urls; $i++) {

		next unless defined $urls[$i];

		my $entry = $urls[$i];

		$entry = Slim::Utils::Misc::fixPath($entry);
		
		my $title = $titles[$i];

		_updateMetaData($entry, $title);

		push @items, $entry;
	}

	close $pls;

	return @items;
}

# This now just processes the cuesheet into tags. The calling process is
# responsible for adding the tracks into the datastore.
sub parseCUE {
	my $lines  = shift;
	my $cuedir = shift;
	my $noUTF8 = shift || 0;

	my $artist;
	my $album;
	my $year;
	my $genre;
	my $comment;
	my $filename;
	my $currtrack;
	my $tracks = {};

	$::d_parse && Slim::Utils::Misc::msg("parseCUE: cuedir: [$cuedir]\n");

	if (!@$lines) {
		$::d_parse && Slim::Utils::Misc::msg("parseCUE skipping empty cuesheet.\n");
		return;
	}

	for (@$lines) {

#		unless ($noUTF8) {
#
#			if ($] > 5.007) {
#				$_ = eval { Encode::decode("utf8", $_, Encode::FB_QUIET()) };
#			} else {
#				$_ = Slim::Utils::Misc::utf8toLatin1($_);
#			}
#		}

		# strip whitespace from end
		s/\s*$//;

		if (/^TITLE\s+\"(.*)\"/i) {
			$album = $1;

		} elsif (/^PERFORMER\s+\"(.*)\"/i) {
			$artist = $1;

		} elsif (/^(?:REM\s+)?YEAR\s+\"(.*)\"/i) {
			$year = $1;

		} elsif (/^(?:REM\s+)?GENRE\s+\"(.*)\"/i) {
			$genre = $1;

		} elsif (/^(?:REM\s+)?COMMENT\s+\"(.*)\"/i) {
			$comment = $1;

		} elsif (/^FILE\s+\"(.*)\"/i) {
			$filename = $1;
			$filename = Slim::Utils::Misc::fixPath($filename, $cuedir);

		} elsif (/^FILE\s+\"?(\S+)\"?/i) {
			# Some cue sheets may not have quotes. Allow that, but
			# the filenames can't have any spaces in them.
			$filename = $1;
			$filename = Slim::Utils::Misc::fixPath($filename, $cuedir);

		} elsif (/^\s+TRACK\s+(\d+)\s+AUDIO/i) {
			$currtrack = int ($1);

		} elsif (defined $currtrack and /^\s+PERFORMER\s+\"(.*)\"/i) {
			$tracks->{$currtrack}->{'ARTIST'} = $1;

		} elsif (defined $currtrack and
			 /^(?:\s+REM)?\s+(TITLE|YEAR|GENRE|COMMENT|COMPOSER|CONDUCTOR|BAND)\s+\"(.*)\"/i) {
		   $tracks->{$currtrack}->{uc $1} = $2;

		} elsif (defined $currtrack and
			 /^\s+INDEX\s+00\s+(\d+):(\d+):(\d+)/i) {
			$tracks->{$currtrack}->{'PREGAP'} = ($1 * 60) + $2 + ($3 / 75);

		} elsif (defined $currtrack and
			 /^\s+INDEX\s+01\s+(\d+):(\d+):(\d+)/i) {
			$tracks->{$currtrack}->{'START'} = ($1 * 60) + $2 + ($3 / 75);

		} elsif (defined $currtrack and
			 /^\s*REM\s+END\s+(\d+):(\d+):(\d+)/i) {
			$tracks->{$currtrack}->{'END'} = ($1 * 60) + $2 + ($3 / 75);			
		}
	}

	if (!$currtrack || $currtrack < 1) {
		$::d_parse && Slim::Utils::Misc::msg("parseCUE unable to extract tracks from cuesheet\n");
		return {};
	}

	# calc song ending times from start of next song from end to beginning.
	my $lastpos = $tracks->{$currtrack}->{'END'};

	# If we can't get $lastpos from the cuesheet, try and read it from the original file.
	if (!$lastpos) {

		$::d_parse && Slim::Utils::Misc::msg("Reading tags to get ending time of $filename\n");

		my $ds = Slim::Music::Info::getCurrentDataStore();
		my $track = $ds->updateOrCreate({
			'url'        => $filename,
			'readTags'   => 1,
		});

		$lastpos = $track->secs();

		$::d_parse && Slim::Utils::Misc::msg("Couldn't get duration of $filename\n") unless $lastpos;
	}

	for my $key (sort {$b <=> $a} keys %$tracks) {

		my $track = $tracks->{$key};

		if (!defined $track->{'END'}) {
			$track->{'END'} = $lastpos;
		}

		#defer pregap handling until we have continuous play through consecutive tracks
		#$lastpos = (exists $track->{'PREGAP'}) ? $track->{'PREGAP'} : $track->{'START'};
		$lastpos = $track->{'START'};
	}

	for my $key (sort {$a <=> $b} keys %$tracks) {

		my $track = $tracks->{$key};
	
		if (!defined $track->{'START'} || !defined $track->{'END'} || !defined $filename ) { next; }
#		if (!defined $track->{'START'} || !defined $filename ) { next; }

		# Don't use $track->{'URL'} or the db will break
		$track->{'URI'} = "$filename#".$track->{'START'}."-".$track->{'END'};

		$::d_parse && Slim::Utils::Misc::msg("    URL: " . $track->{'URI'} . "\n");

		# Ensure that we have a CT
		if (!defined $track->{'CT'}) {
			$track->{'CT'} = Slim::Music::Info::typeFromPath($filename, 'mp3');
		}
		
		$track->{'TRACKNUM'} = $key;
		$::d_parse && Slim::Utils::Misc::msg("    TRACKNUM: " . $track->{'TRACKNUM'} . "\n");

		$track->{'FILENAME'} = $filename;

		for my $attribute (qw(TITLE ARTIST ALBUM CONDUCTOR COMPOSER BAND YEAR GENRE)) {

			if (exists $track->{$attribute}) {
				$::d_parse && Slim::Utils::Misc::msg("    $attribute: " . $track->{$attribute} . "\n");
			}
		}

		# Merge in file level attributes
		if (!exists $track->{'ARTIST'} && defined $artist) {
			$track->{'ARTIST'} = $artist;
			$::d_parse && Slim::Utils::Misc::msg("    ARTIST: " . $track->{'ARTIST'} . "\n");
		}

		if (!exists $track->{'ALBUM'} && defined $album) {
			$track->{'ALBUM'} = $album;
			$::d_parse && Slim::Utils::Misc::msg("    ALBUM: " . $track->{'ALBUM'} . "\n");
		}

		if (!exists $track->{'YEAR'} && defined $year) {
			$track->{'YEAR'} = $year;
			$::d_parse && Slim::Utils::Misc::msg("    YEAR: " . $track->{'YEAR'} . "\n");
		}

		if (!exists $track->{'GENRE'} && defined $genre) {
			$track->{'GENRE'} = $genre;
			$::d_parse && Slim::Utils::Misc::msg("    GENRE: " . $track->{'GENRE'} . "\n");
		}

		if (!exists $track->{'COMMENT'} && defined $comment) {
			$track->{'COMMENT'} = $comment;
			$::d_parse && Slim::Utils::Misc::msg("    COMMENT: " . $track->{'COMMENT'} . "\n");
		}
	}

	return $tracks;
}

sub readCUE {
	my $cuefile = shift;
	my $cuedir  = shift;

	$::d_parse && Slim::Utils::Misc::msg("Parsing cue: $cuefile \n");

	my $ds = Slim::Music::Info::getCurrentDataStore();

	my @lines = ();
	my @items = ();

	# The cuesheet will/may be encoded.
	if ($] > 5.007) {
		binmode($cuefile, ":encoding($Slim::Utils::Misc::locale)");
	}

	while (my $line = <$cuefile>) {
		chomp($line);
		$line =~ s/\cM//g;  
		next if ($line =~ /^\s*$/);
		push @lines, $line;
	}

	close $cuefile;

	# Don't redecode it when parsing the cuesheet.
	my $tracks = (parseCUE([@lines], $cuedir, 1));
	return @items unless defined $tracks && keys %$tracks > 0;

	# Grab a random track to pull a filename from.
	# for now we only support one FILE statement in the cuesheet
	my ($sometrack) = (keys %$tracks);

	# We may or may not have run updateOrCreate on the base filename
	# during parseCUE, depending on the cuesheet contents.
	# Run it here just to be sure.
	# Set the content type on the base file to hide it from listings.
	# Grab data from the base file to pass on to our individual tracks.
	my $basetrack = $ds->updateOrCreate({
		'url'        => $tracks->{$sometrack}->{'FILENAME'},
		'attributes' => { 'CT' => 'cur' },
		'readTags'   => 1,
	});

	# Remove entries from other sources. This cuesheet takes precedence.
	my $find = {'url', $tracks->{$sometrack}->{'FILENAME'} . "#*" };

	my @oldtracks = $ds->find('url', $find);
	for my $oldtrack (@oldtracks) {
		$::d_parse && Slim::Utils::Misc::msg("Deleting previous entry for $oldtrack\n");
		$ds->delete($oldtrack);
	}

	# Process through the individual tracks
	for my $key (keys %$tracks) {
		my $track = $tracks->{$key};

		if (!defined $track->{'URI'}) {
			$::d_parse && Slim::Utils::Misc::msg("Skipping track without url\n");
			next;
		}

		push @items, $track->{'URI'}; #url;

		# our tracks won't be visible if we don't include some data from the base file
		for my $attribute (keys %$basetrack) {
			next if $attribute eq 'id';
			next if $attribute eq 'url';
			next if $attribute =~ /^_/;
			next unless exists $basetrack->{$attribute};
			$track->{uc $attribute} = $basetrack->{$attribute} unless exists $track->{uc $attribute};
		}

		processAnchor($track);

		# Do the actual data store
		# Skip readTags since we'd just be reading the same file over and over
		$ds->updateOrCreate({
			'url'        => $track->{'URI'},
			'attributes' => $track,
			'readTags'   => 0,  # no need to read tags, since we did it for the base file
		});

	}

	$::d_parse && Slim::Utils::Misc::msg("    returning: " . scalar(@items) . " items\n");	

	return @items;
}

sub processAnchor {
	my $attributesHash = shift;

	my ($start, $end) = Slim::Music::Info::isFragment($attributesHash->{'URI'});

	# rewrite the size, offset and duration if it's just a fragment
	# This is mostly (always?) for cue sheets.
	unless (defined $start && $end && $attributesHash->{'SECS'}) {
		$::d_parse && Slim::Utils::Misc::msg("parse: Couldn't process anchored file fragment for " . $attributesHash->{'URI'} . "\n");
		return 0;
	}

	my $duration = $end - $start;
	my $byterate = $attributesHash->{'SIZE'} / $attributesHash->{'SECS'};
	my $header = $attributesHash->{'OFFSET'} || 0;
	my $startbytes = int($byterate * $start);
	my $endbytes = int($byterate * $end);
			
	$startbytes -= $startbytes % $attributesHash->{'BLOCKALIGN'} if $attributesHash->{'BLOCKALIGN'};
	$endbytes -= $endbytes % $attributesHash->{'BLOCKALIGN'} if $attributesHash->{'BLOCKALIGN'};
			
	$attributesHash->{'OFFSET'} = $header + $startbytes;
	$attributesHash->{'SIZE'} = $endbytes - $startbytes;
	$attributesHash->{'SECS'} = $duration;

	if ($::d_parse) {
		Slim::Utils::Misc::msg("parse: calculating duration for anchor: $duration\n");
		Slim::Utils::Misc::msg("parse: calculating header $header, startbytes $startbytes and endbytes $endbytes\n");
	}		
}

sub writePLS {
	my $listref = shift;
	my $playlistname = shift || "SlimServer " . Slim::Utils::Strings::string("PLAYLIST");
	my $filename = shift;

	my $string = '';
	my $output = _filehandleFromNameOrString($filename, \$string) || return;

	print $output "[playlist]\nPlaylistName=$playlistname\n";

	my $itemnum = 0;
	my $ds      = Slim::Music::Info::getCurrentDataStore();

	for my $item (@{$listref}) {

		$itemnum++;

		my $track = $ds->objectForUrl($item);

		printf($output "File%d=%s\n", $itemnum, _pathForItem($item));

		my $title = $track->title();

		if ($title) {
			printf($output "Title%d=%s\n", $itemnum, $title);
		}

		printf($output "Length%d=%s\n", $itemnum, ($track->duration() || -1));
	}

	print $output "NumberOfItems=$itemnum\nVersion=2\n";

	close $output if $filename;
	return $string;
}

sub writeM3U {
	my $listref = shift;
	my $playlistname = shift;
	my $filename = shift;
	my $addTitles = shift;
	my $resumetrack = shift;

	my $string = '';
	my $output = _filehandleFromNameOrString($filename, \$string) || return;

	print $output "#CURTRACK $resumetrack\n" if defined($resumetrack);
	print $output "#EXTM3U\n" if $addTitles;

	my $ds = Slim::Music::Info::getCurrentDataStore();

	for my $item (@{$listref}) {

		if ($addTitles && Slim::Music::Info::isURL($item)) {

			my $track = $ds->objectForUrl($item) || do {
				Slim::Utils::Misc::msg("Couldn't retrieve objectForUrl: [$item] - skipping!\n");
				next;
			};
			
			my $title = $track->title();

			if ($] > 5.007) {
				$title = Encode::decode_utf8($title);
			}

			if ($title) {
				print $output "#EXTINF:-1,$title\n";
			}
		}

		my $path = _pathForItem($item, 1);

		if ($] > 5.007) {
			$path = Encode::decode_utf8($path);
		}

		print $output "$path\n";
	}

	close $output if $filename;

	return $string;
}

sub readWPL {
	my $wplfile = shift;
	my $wpldir  = shift;

	my @items  = ();

	# Handles version 1.0 WPL Windows Medial Playlist files...
	my $wpl_playlist = {};

	eval {
		$wpl_playlist = XMLin($wplfile);
	};

	$::d_parse && Slim::Utils::Misc::msg("parsing WPL: $wplfile\n");

	if (exists($wpl_playlist->{body}->{seq}->{media})) {
		
		my @media;
		if (ref $wpl_playlist->{body}->{seq}->{media} ne 'ARRAY') {
			push @media, $wpl_playlist->{body}->{seq}->{media};
		} else {
			@media = @{$wpl_playlist->{body}->{seq}->{media}};
		}
		
		for my $entry_info (@media) {

			my $entry=$entry_info->{src};

			$::d_parse && Slim::Utils::Misc::msg("  entry from file: $entry\n");
		
			$entry = Slim::Utils::Misc::fixPath($entry, $wpldir);
		
			$::d_parse && Slim::Utils::Misc::msg("    entry: $entry\n");

			_updateMetaData($entry, undef);
			push @items, $entry;
		}
	}

	$::d_parse && Slim::Utils::Misc::msg("parsed " . scalar(@items) . " items in wpl playlist\n");

	return @items;
}

sub writeWPL {
	my $listref = shift;
	my $playlistname = shift || "SlimServer " . Slim::Utils::Strings::string("PLAYLIST");
	my $filename = shift;

	# Handles version 1.0 WPL Windows Medial Playlist files...

	# Load the original if it exists (so we don't lose all of the extra crazy info in the playlist...
	my $wpl_playlist = {};

	eval {
		$wpl_playlist = XMLin($filename, KeepRoot => 1, ForceArray => 1);
	};

	if($wpl_playlist) {
		# Clear out the current playlist entries...
		$wpl_playlist->{smil}->[0]->{body}->[0]->{seq}->[0]->{media} = [];

	} else {
		# Create a skeleton of the structure we'll need to output a compatible WPL file...
		$wpl_playlist={
			smil => [{
				body => [{
					seq => [{
						media => [
						]
					}]
				}],
				head => [{
					title => [''],
					author => [''],
					meta => {
						Generator => {
							content => '',
						}
					}
				}]
			}]
		};
	}

	for my $item (@{$listref}) {

		if (Slim::Music::Info::isURL($item)) {
			my $url=uri_unescape($item);
			$url=~s/^file:[\/\\]+//;
			push(@{$wpl_playlist->{smil}->[0]->{body}->[0]->{seq}->[0]->{media}},{src => $url});
		}
	}

	# XXX - Windows Media Player 9 has problems with directories,
	# and files that have an &amp; in them...

	# Generate our XML for output...
	# (the ForceArray option when we do "XMLin" makes the hash messy,
	# but ensures that we get the same style of XML layout back on
	# "XMLout")
	my $wplfile = XMLout($wpl_playlist, XMLDecl => '<?wpl version="1.0"?>', RootName => undef);

	my $string;

	my $output = _filehandleFromNameOrString($filename, \$string) || return;
	print $output $wplfile;
	close $output if $filename;

	return $string;
}

sub readASX {
	my $asxfile = shift;
	my $asxdir  = shift;

	my @items  = ();

	my $asx_playlist={};
	my $asxstr = '';
	while (<$asxfile>) {
		$asxstr .= $_;
	}
	close $asxfile;

	# First try for version 3.0 ASX
	if ($asxstr =~ /<ASX/i) {
		# Deal with the common parsing problem of unescaped ampersands
		# found in many ASX files on the web.
		$asxstr =~ s/&(?!(#|amp;|quot;|lt;|gt;|apos;))/&amp;/g;

		eval {
			$asx_playlist = XMLin($asxstr, ForceArray => ['entry', 'Entry', 'ENTRY', 'ref', 'Ref', 'REF']);
		};
		
		$::d_parse && Slim::Utils::Misc::msg("parsing ASX: $asxfile\n");
		
		my $entries = $asx_playlist->{entry} || $asx_playlist->{Entry} || $asx_playlist->{ENTRY};

		if (defined($entries)) {

			for my $entry (@$entries) {
				
				my $title = $entry->{title} || $entry->{Title} || $entry->{TITLE};

				$::d_parse && Slim::Utils::Misc::msg("Found an entry title: $title\n");

				my $path;
				my $refs = $entry->{ref} || $entry->{Ref} || $entry->{REF};

				if (defined($refs)) {

					for my $ref (@$refs) {

						my $href = $ref->{href} || $ref->{Href} || $ref->{HREF};
						my $url = URI->new($href);

						$::d_parse && Slim::Utils::Misc::msg("Checking if we can handle the url: $url\n");
						
						my $scheme = $url->scheme();

						if (exists $Slim::Player::Source::protocolHandlers{lc $scheme}) {

							$::d_parse && Slim::Utils::Misc::msg("Found a handler for: $url\n");
							$path = $href;
							last;
						}
					}
				}
				
				if (defined($path)) {
					$path = Slim::Utils::Misc::fixPath($path, $asxdir);
					
					_updateMetaData($path, $title);
					push @items, $path;
				}
			}
		}
	}

	# Next is version 2.0 ASX
	elsif ($asxstr =~ /[Reference]/) {
		while ($asxstr =~ /^Ref(\d+)=(.*)$/gm) {
			my $url = URI->new($2);
			# XXX We've found that ASX 2.0 refers to http: URLs, when it
			# really means mms: URLs. Wouldn't it be nice if there were
			# a real spec?
			if ($url->scheme() eq 'http') {
				$url->scheme('mms');
			}
			push @items, $url->as_string;
		}
	}

	# And finally version 1.0 ASX
	else {
		while ($asxstr =~ /^(.*)$/gm) {
			push @items, $1;
		}
	}

	$::d_parse && Slim::Utils::Misc::msg("parsed " . scalar(@items) . " items in asx playlist\n");

	return @items;
}

sub readPodcast {
	my $in = shift;

	$::d_parse && Slim::Utils::Misc::msg("Parsing podcast...\n");

	my @urls = ();

	# async http request succeeded.  Parse XML
	# forcearray to treat items as array,
	# keyattr => [] prevents id attrs from overriding
	my $xml = eval { XMLin($in,
						   forcearray => ["item"], keyattr => []) };

	if ($@) {
		$::d_plugins && msg("Podcast: failed to parse feed because:\n$@\n");
		# TODO: how can we get error message to client?
		return undef;
	}

	# some feeds (slashdot) have items at same level as channel
	my $items;
	if ($xml->{item}) {
		$items = $xml->{item};
	} else {
		$items = $xml->{channel}->{item};
	}

	for my $item (@$items) {
		my $enclosure = $item->{enclosure};
		if ($enclosure) {
			if ($enclosure->{type} =~ /audio/) {
				push @urls, $enclosure->{url};
				if ($item->{title}) {
					# associate a title with the url
					# XXX calling routine beginning with "_"
					Slim::Formats::Parse::_updateMetaData($enclosure->{url},
														  $item->{title});
				}
			}
		}
	}

	# it seems like the caller of this sub should be the one to close,
	# since they openned it.  But I'm copying other read routines
	# which call close at the end.
	close $in;

	$::d_plugins && msg("Podcast: parsed podcast.  Returning urls:\n" . join("\n", @urls) . "\n");

	return @urls;
}



sub _pathForItem {
	my $item = shift;
	my $dontencode = shift;

	if (Slim::Music::Info::isFileURL($item) && !Slim::Music::Info::isFragment($item)) {
		return Slim::Utils::Misc::pathFromFileURL($item, $dontencode);
	}

	return $item;
}

sub _filehandleFromNameOrString {
	my $filename  = shift;
	my $outstring = shift;

	my $output;

	if ($filename) {

		$output = FileHandle->new($filename, "w") || do {
			Slim::Utils::Misc::msg("Could not open $filename for writing.\n");
			return undef;
		};

		# Always write out in UTF-8 with a BOM.
		if ($] > 5.007) {

			binmode($output, ":raw");

			print $output $File::BOM::enc2bom{'utf8'};

			binmode($output, ":encoding(utf8)");
		}

	} else {

		$output = IO::String->new($$outstring);
	}

	return $output;
}

1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
