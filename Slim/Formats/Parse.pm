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

our %playlistInfo = ( 
	'm3u' => [\&readM3U, \&writeM3U, '.m3u'],
	'pls' => [\&readPLS, \&writePLS, '.pls'],
	'cue' => [\&readCUE, undef, undef],
	'wpl' => [\&readWPL, \&writeWPL, '.wpl'],
	'asx' => [\&readASX, undef, '.asx'],
	'wax' => [\&readASX, undef, '.wax'],
);

sub registerParser {
	my ($type, $readfunc, $writefunc, $suffix) = @_;

	$::d_parse && Slim::Utils::Misc::msg("Resistering external parser for type $type\n");

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

	if ($track) {

		if (!Slim::Music::Info::isKnownType($track)) {

			$::d_parse && Slim::Utils::Misc::msg("    entry: $entry not known type\n"); 

			# Track will work because we stringify to the url.
			Slim::Music::Info::setContentType($track, 'mp3');
		}

	} else {

		$::d_parse && Slim::Utils::Misc::msg("    entry: $entry forcing type to mp3\n"); 
		Slim::Music::Info::setContentType($entry, 'mp3');
	}

	# Update title MetaData only if its not a local file with Title information already cached.
	if (defined($title) && !(Slim::Music::Info::cacheItem($entry, 'TITLE') && Slim::Music::Info::isFileURL($entry))) {
		Slim::Music::Info::setTitle($entry, $title);
		$title = undef;
	}
}

sub readM3U {
	my $m3u    = shift;
	my $m3udir = shift;

	my @items  = ();
	my $title;

	if ($] > 5.007) {
		binmode($m3u, ":encoding($Slim::Utils::Misc::locale)");
	}

	$::d_parse && Slim::Utils::Misc::msg("parsing M3U: $m3u\n");

	while (my $entry = <$m3u>) {

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
		
		$entry = Slim::Utils::Misc::fixPath($entry, $m3udir);
		
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

# $noUTF8 comes from readCUE - which means it's an external cue sheet.
# If that's the case, we don't want to readTags (in newTrack() either, since
# all the data will be coming from the cuesheet.
#
# If we are an internal cuesheet, then readTags() needs to be called, which
# will invoke Slim::Formats::FLAC->getTags() - with an anchor, which will
# return before the cuesheet parsing - avoiding the infinite loop.

sub parseCUE {
	my $lines  = shift;
	my $cuedir = shift;
	my $secs   = shift || 0;
	my $noUTF8 = shift || 0;
	my @items;

	my $album;
	my $year;
	my $genre;
	my $comment;
	my $filename;
	my $currtrack;
	my %tracks;
	my $ds = Slim::Music::Info::getCurrentDataStore();

	$::d_parse && Slim::Utils::Misc::msg("parseCUE: cuedir: [$cuedir] secs: [$secs] noUTF8: [$noUTF8]\n");

	if (!@$lines) {
		$::d_parse && Slim::Utils::Misc::msg("parseCUE skipping empty cuesheet.\n");
		return;
	}

	for (@$lines) {

		unless ($noUTF8) {

			if ($] > 5.007) {
				$_ = eval { Encode::decode("utf8", $_, Encode::FB_QUIET()) };
			} else {
				$_ = Slim::Utils::Misc::utf8toLatin1($_);
			}
		}

		# strip whitespace from end
		s/\s*$//; 

		if (/^TITLE\s+\"(.*)\"/i) {
			$album = $1;
		} elsif (/^YEAR\s+\"(.*)\"/i) {
			$year = $1;
		} elsif (/^GENRE\s+\"(.*)\"/i) {
			$genre = $1;
		} elsif (/^COMMENT\s+\"(.*)\"/i) {
			$comment = $1;
		} elsif (/^FILE\s+\"(.*)\"/i) {
			$filename = $1;
			$filename = Slim::Utils::Misc::fixPath($filename, $cuedir);
		} elsif (/^\s+TRACK\s+(\d+)\s+AUDIO/i) {
			$currtrack = int ($1);
		} elsif (defined $currtrack and /^\s+PERFORMER\s+\"(.*)\"/i) {
			$tracks{$currtrack}->{'ARTIST'} = $1;
		} elsif (defined $currtrack and
			 /^\s+(TITLE|YEAR|GENRE|COMMENT)\s+\"(.*)\"/i) {
		   $tracks{$currtrack}->{uc $1} = $2;
		} elsif (defined $currtrack and
			 /^\s+INDEX\s+01\s+(\d+):(\d+):(\d+)/i) {
			$tracks{$currtrack}->{'START'} = ($1 * 60) + $2 + ($3 / 75);
		} elsif (defined $currtrack and
			 /^\s*REM\s+END\s+(\d+):(\d+):(\d+)/i) {
			$tracks{$currtrack}->{'END'} = ($1 * 60) + $2 + ($3 / 75);
		}
	}

	# calc song ending times from start of next song from end to beginning.
	my $lastpos = (defined $tracks{$currtrack}->{'END'}) ? $tracks{$currtrack}->{'END'} : $secs;

	# If we can't get $lastpos from the cuesheet, try and read it from the original file.
	if (!$lastpos) {

		my $track = $ds->updateOrCreate({
			'url'        => $filename,
			'attributes' => {},
			'readTags'   => 1,
		});

		$lastpos = $secs = $track->secs();

		$::d_parse && Slim::Utils::Misc::msg("Couldn't get duration of $filename\n") unless $lastpos;
	}

	for my $key (sort {$b <=> $a} keys %tracks) {

		my $track = $tracks{$key};

		if (!defined $track->{'END'}) {
			$track->{'END'} = $lastpos;
		}

		$lastpos = $track->{'START'};
	}

	for my $key (sort {$a <=> $b} keys %tracks) {

		my $track = $tracks{$key};
	
		if (!defined $track->{'START'} || !defined $filename ) { next; }

		if (!defined $track->{'END'}) {

			$track->{'END'} = $secs || '';
		}

		my $url = "$filename#".$track->{'START'}."-".$track->{'END'};

		$::d_parse && Slim::Utils::Misc::msg("    URL: $url\n");

		push @items, $url;

		my $cacheEntry = {};
		
		$cacheEntry->{'CT'} = Slim::Music::Info::typeFromPath($url, 'mp3');
		
		$cacheEntry->{'TRACKNUM'} = $key;
		$::d_parse && Slim::Utils::Misc::msg("    TRACKNUM: $key\n");

		if (exists $track->{'TITLE'}) {
			$cacheEntry->{'TITLE'} = $track->{'TITLE'};
			$::d_parse && Slim::Utils::Misc::msg("    TITLE: " . $cacheEntry->{'TITLE'} . "\n");
		}

		if (exists $track->{'ARTIST'}) {
			$cacheEntry->{'ARTIST'} = $track->{'ARTIST'};
			$::d_parse && Slim::Utils::Misc::msg("    ARTIST: " . $cacheEntry->{'ARTIST'} . "\n");
		}

		if (exists $track->{'YEAR'}) {

			$cacheEntry->{'YEAR'} = $track->{'YEAR'};
			$::d_parse && Slim::Utils::Misc::msg("    YEAR: " . $cacheEntry->{'YEAR'} . "\n");

		} elsif (defined $year) {

			$cacheEntry->{'YEAR'} = $year;
			$::d_parse && Slim::Utils::Misc::msg("    YEAR: " . $year . "\n");
		}

		if (exists $track->{'GENRE'}) {

			$cacheEntry->{'GENRE'} = $track->{'GENRE'};
			$::d_parse && Slim::Utils::Misc::msg("    GENRE: " . $cacheEntry->{'GENRE'} . "\n");

		} elsif (defined $genre) {

			$cacheEntry->{'GENRE'} = $genre;
			$::d_parse && Slim::Utils::Misc::msg("    GENRE: " . $genre . "\n");
		}

		if (exists $track->{'COMMENT'}) {

			$cacheEntry->{'COMMENT'} = $track->{'COMMENT'};
			$::d_parse && Slim::Utils::Misc::msg("    COMMENT: " . $cacheEntry->{'COMMENT'} . "\n");

		} elsif (defined $comment) {

			$cacheEntry->{'COMMENT'} = $comment;
			$::d_parse && Slim::Utils::Misc::msg("    COMMENT: " . $comment . "\n");
		}

		if (defined $album) {
			$cacheEntry->{'ALBUM'} = $album;
			$::d_parse && Slim::Utils::Misc::msg("    ALBUM: " . $cacheEntry->{'ALBUM'} . "\n");
		}

		# $noUTF8 will be set if this is an external cuesheet, in
		# which case we want to set the content type on the source file
		# so it won't show up in music listings

		if ($noUTF8) {

			$ds->updateOrCreate({
				'url'        => $filename,
				'attributes' => { 'CT' => 'cur' },
				'readTags'   => 0,
			});
		}

		$ds->updateOrCreate({
			'url'        => $url,
			'attributes' => $cacheEntry,
			'readTags'   => 1,
		});
	}

	$::d_parse && Slim::Utils::Misc::msg("    returning: " . scalar(@items) . " items\n");	

	return @items;
}

sub readCUE {
	my $cuefile = shift;
	my $cuedir  = shift;

	$::d_parse && Slim::Utils::Misc::msg("Parsing cue: $cuefile \n");

	my @lines = ();

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

	# Don't redecode it.
	return (parseCUE([@lines], $cuedir, undef, 1));
}

sub writePLS {
	my $listref = shift;
	my $playlistname = shift || "SlimServer " . Slim::Utils::Strings::string("PLAYLIST");
	my $filename = shift;

	my $string = '';
	my $output = _filehandleFromNameOrString($filename, $string);

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

	close $output;
	return $string;
}

sub writeM3U {
	my $listref = shift;
	my $playlistname = shift;
	my $filename = shift;
	my $addTitles = shift;
	my $resumetrack = shift;

	my $string = '';
	my $output = _filehandleFromNameOrString($filename, $string);

	print $output "#CURTRACK $resumetrack\n" if defined($resumetrack);
	print $output "#EXTM3U\n" if $addTitles;

	my $ds = Slim::Music::Info::getCurrentDataStore();

	for my $item (@{$listref}) {

		if ($addTitles && Slim::Music::Info::isURL($item)) {

			my $track = $ds->objectForUrl($item);
			my $title = $track->title();

			if ($title) {
				print $output "#EXTINF:-1,$title\n";
			}
		}

		printf($output "%s\n", _pathForItem($item));
	}

	close $output;
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

		for my $entry_info (@{$wpl_playlist->{body}->{seq}->{media}}) {

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

	my $output = _filehandleFromNameOrString($filename, $string);
	print $output $wplfile;
	close $output;

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

sub _pathForItem {
	my $item = shift;

	if (Slim::Music::Info::isFileURL($item) && !Slim::Music::Info::isFragment($item)) {
		return Slim::Utils::Misc::pathFromFileURL($item);
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
			return;
		};

		if ($] > 5.007) {
			binmode($output, ":encoding($Slim::Utils::Misc::locale)");
		}

	} else {

		$output = IO::String->new($outstring);
	}

	return $output;
}

1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
