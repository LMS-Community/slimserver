package Slim::Formats::Playlists::CUE;

# $Id$

# Logitech Media Server Copyright 2001-2011 Logitech.
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use base qw(Slim::Formats::Playlists::Base);

use Audio::Scan;
use File::Slurp;
use File::Spec::Functions qw(catdir);
use Scalar::Util qw(blessed);

use Slim::Music::Info;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;
use Slim::Utils::Unicode;

my $log = logger('formats.playlists');
my $prefs = preferences('server');

# This now just processes the cuesheet into tags. The calling process is
# responsible for adding the tracks into the datastore.
sub parse {
	my $class    = shift;
	my $lines    = shift;
	my $baseDir  = shift;
	my $embedded = shift || 0;

	my ($filename, $currtrack);
	my $filesSeen = 0;
	my $cuesheet  = {};
	my $tracks    = {};

	main::INFOLOG && $log->info("baseDir: [$baseDir]");

	if (!@$lines) {

		$log->warn("Skipping empty cuesheet.");

		return;
	}
	
	# Bug 11289, strip BOM from first line
	$lines->[0] = Slim::Utils::Unicode::stripBOM($lines->[0]);

	for my $line (@$lines) {

		my $enc = Slim::Utils::Unicode::encodingFromString($line);

		# Prefer UTF8 for CUE sheets.
		$line = Slim::Utils::Unicode::utf8decode_guess($line, 'utf8', $enc) unless $line =~ /^FILE\s+/i;

		# strip whitespace from end
		$line =~ s/\s*$//;

		if ($line =~ /^TITLE\s+\"(.*)\"/i) {

			if (defined $currtrack) {

				$tracks->{$currtrack}->{'TITLE'} = $1;

			} else {

				$cuesheet->{'ALBUM'} = $1;
			}

		} elsif ($line =~ /^PERFORMER\s+\"(.*)\"/i) {

			$cuesheet->{'ARTIST'} = $1;
			
		} elsif ($line =~ /^(?:REM\s+)?(YEAR|GENRE|DISC|DISCC|COMMENT|ARTISTSORT|ALBUMSORT|COMPILATION)\s+\"(.*)\"/i) {

			$cuesheet->{uc($1)} = $2;

		} elsif ($line =~ /^(?:REM\s+)?(DATE)\s+(.*)/i) {

			# EAC CUE sheet has REM DATE not REM YEAR, and no quotes
			$cuesheet->{'YEAR'} = $2;

		} elsif ($line =~ /^(?:REM\s+)?(GENRE)\s+(.*)/i) {

			# Single worded GENRE doesn't have quotes
			$cuesheet->{uc($1)} = $2;

		} elsif ($line =~ /^(?:REM\s+)?(REPLAYGAIN_ALBUM_GAIN)\s+(.*)dB/i) {

			$cuesheet->{uc($1)} = $2;

		} elsif ($line =~ /^(?:REM\s+)?(REPLAYGAIN_ALBUM_PEAK)\s+(.*)/i) {

			$cuesheet->{uc($1)} = $2;

		} elsif ($line =~ /^FILE\s+\"(.*)\"/i) {

			$filename = $embedded || $1;
			$filename = Slim::Utils::Misc::fixPath($filename, $baseDir);
			
			# Watch out for cue sheets with multiple FILE entries
			$filesSeen++;

		} elsif ($line =~ /^FILE\s+\"?(\S+)\"?/i) {

			# Some cue sheets may not have quotes. Allow that, but
			# the filenames can't have any spaces in them.
			$filename = $embedded || $1;
			$filename = Slim::Utils::Misc::fixPath($filename, $baseDir);
			
			$filesSeen++;

		} elsif ($line =~ /^\s*TRACK\s+(\d+)\s+AUDIO/i) {

			$currtrack = int($1);

		} elsif (defined $currtrack and $line =~ /^\s*PERFORMER\s+\"(.*)\"/i) {

			$tracks->{$currtrack}->{'ARTIST'} = $1;

		} elsif (defined $currtrack and $line =~ /^(?:\s+REM\s+)?REPLAYGAIN_TRACK_GAIN\s+(.*)dB/i) {

			$tracks->{$currtrack}->{'REPLAYGAIN_TRACK_GAIN'} = $1;

		} elsif (defined $currtrack and $line =~ /^(?:\s+REM\s+)?REPLAYGAIN_TRACK_PEAK\s+(.*)/i) {

			$tracks->{$currtrack}->{'REPLAYGAIN_TRACK_PEAK'} = $1;
			
		} elsif (defined $currtrack and

			$line =~ /^(?:\s+REM )?\s*(TITLE|YEAR|GENRE|COMMENT|COMPOSER|CONDUCTOR|BAND|DISC|DISCC)\s+\"(.*)\"/i) {

			$tracks->{$currtrack}->{uc $1} = $2;

		} elsif (defined $currtrack and $line =~ /^\s*INDEX\s+00\s+(\d+):(\d+):(\d+)/i) {

			$tracks->{$currtrack}->{'PREGAP'} = ($1 * 60) + $2 + ($3 / 75);

		} elsif (defined $currtrack and $line =~ /^\s*INDEX\s+01\s+(\d+):(\d+):(\d+)/i) {

			$tracks->{$currtrack}->{'START'} = ($1 * 60) + $2 + ($3 / 75);

		} elsif (defined $currtrack and $line =~ /^\s*REM\s+END\s+(\d+):(\d+):(\d+)/i) {

			$tracks->{$currtrack}->{'END'} = ($1 * 60) + $2 + ($3 / 75);
		
		} elsif (defined $currtrack and $line =~ /^\s*REM\s+END\s+(.+)/i) {
			# Bug 11950, pass absolute end time in seconds (FLAC), since some loss of accuracy would
			# occur if passing in MM:SS:FF format			
			$tracks->{$currtrack}->{'END'} = $1;

		} elsif (defined $currtrack and defined $filename) {
			# Each track in a cue sheet can have a different
			# filename. See Bug 2126 &
			# http://www.hydrogenaudio.org/forums/index.php?act=ST&f=20&t=4586
			$tracks->{$currtrack}->{'FILENAME'} = $filename;
		}
	}
	
	# Bug 5735, skip cue sheets with multiple FILE entries
	if ( $filesSeen > 1 ) {
		$log->warn('Skipping cuesheet with multiple FILE entries');
		return;
	}

	# Check to make sure that the files are actually on disk - so we don't
	# create bogus database entries.
	for my $key (sort {$b <=> $a} keys %$tracks) {

		my $filepath = Slim::Utils::Misc::pathFromFileURL(($tracks->{$key}->{'FILENAME'} || $filename));

		if (!$embedded && defined $filepath && !-r $filepath) {

			logError("Couldn't find referenced FILE: [$filepath] on disk! Skipping!");

			delete $tracks->{$key};
		}
	}

	if (scalar keys %$tracks == 0 || (!$currtrack || $currtrack < 1 || !$filename)) {

		$log->warn("Unable to extract tracks from cuesheet");

		return {};
	}

	# calc song ending times from start of next song from end to beginning.
	my $lastpos = $tracks->{$currtrack}->{'END'};

	# If we can't get $lastpos from the cuesheet, try and read it from the original file.
	if (!$lastpos && $filename) {

		main::INFOLOG && $log->info("Reading tags to get ending time of $filename");

		my $tags = Slim::Formats->readTags($filename);

		$lastpos = $tags->{SECS};

		# Also - check the original file for any information that may
		# not be in the cue sheet. Bug 2668
		for my $attribute (qw(CONTENT_TYPE ARTIST ALBUM YEAR GENRE REPLAYGAIN_ALBUM_GAIN REPLAYGAIN_ALBUM_PEAK ARTISTSORT ALBUMSORT COMPILATION)) {

			if (!$cuesheet->{$attribute}) {

				my $fromFile = $tags->{$attribute};

				if (defined $fromFile) {
					$cuesheet->{$attribute} = $fromFile;
				}
			}
		}
	}

	if (!$lastpos) {

		logError("Couldn't get duration of $filename");
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

		# Each track can have it's own FILE
		if (!defined $track->{'FILENAME'}) {

			$track->{'FILENAME'} = $filename;
		}

		my $file = $track->{'FILENAME'};
	
		if (!defined $track->{'START'} || !defined $track->{'END'} || !defined $file ) {

			next;
		}

		# Don't use $track->{'URL'} or the db will break
		$track->{'URI'} = "$file#".$track->{'START'}."-".$track->{'END'};

		main::DEBUGLOG && $log->debug("    URL: $track->{'URI'}");

		$track->{'TRACKNUM'} = $key;

		main::DEBUGLOG && $log->debug("    TRACKNUM: $track->{'TRACKNUM'}");

		for my $attribute (Slim::Schema::Contributor->contributorRoles,
			qw(TITLE ALBUM YEAR GENRE REPLAYGAIN_TRACK_PEAK REPLAYGAIN_TRACK_GAIN)) {

			if (exists $track->{$attribute}) {

				main::DEBUGLOG && $log->debug("    $attribute: $track->{$attribute}");
			}
		}

		# Merge in file level attributes
		for my $attribute (qw(CONTENT_TYPE ARTIST ALBUM YEAR GENRE COMMENT REPLAYGAIN_ALBUM_GAIN REPLAYGAIN_ALBUM_PEAK ARTISTSORT ALBUMSORT COMPILATION)) {

			if (!exists $track->{$attribute} && defined $cuesheet->{$attribute}) {

				$track->{$attribute} = $cuesheet->{$attribute};

				main::DEBUGLOG && $log->debug("    $attribute: $track->{$attribute}");
			}
		}
		
		# Ensure that we have a CONTENT_TYPE
		if (!defined $track->{'CONTENT_TYPE'}) {
			$track->{'CONTENT_TYPE'} = Slim::Music::Info::typeFromPath($file, 'mp3');
		}

		# Everything in a cue sheet should be marked as audio.
		$track->{'AUDIO'} = 1;
	}
	
	# Bug 8443, if no tracks contain a URI element, it's an invalid cue
	if ( !grep { defined $tracks->{$_}->{URI} } keys %{$tracks} ) {
		main::DEBUGLOG && $log->debug('Invalid cue sheet detected');
		return;
	}

	return $tracks;
}

sub read {
	my $class   = shift;
	my $file    = shift;
	my $baseDir = shift;
	my $url     = shift;

	main::INFOLOG && $log->info("Reading CUE: $url");

	my @items  = ();
	my @lines  = read_file($file);
	my $tracks = ($class->parse([ @lines ], $baseDir));

	return @items unless defined $tracks && keys %$tracks > 0;

	#
	my $basetrack = undef;

	# Process through the individual tracks
	for my $key (sort { $a <=> $b } keys %$tracks) {

		my $track = $tracks->{$key};

		if (!defined $track->{'URI'} || !defined $track->{'FILENAME'}) {

			$log->warn("Skipping track without url or filename");
			next;
		}

		# We may or may not have run updateOrCreate on the base filename
		# during parseCUE, depending on the cuesheet contents.
		# Run it here just to be sure.
		# Set the content type on the base file to hide it from listings.
		# Grab data from the base file to pass on to our individual tracks.
		if (!defined $basetrack || $basetrack->url ne $track->{'FILENAME'}) {

			main::INFOLOG && $log->info("Creating new track for: $track->{'FILENAME'}");

			$basetrack = Slim::Schema->updateOrCreate({
				'url'        => $track->{'FILENAME'},
				'attributes' => {
					'CONTENT_TYPE'    => 'cur',
					'AUDIO' => 0
				},
				'readTags'   => 1,
			});

			# Remove entries from other sources. This cuesheet takes precedence.
			Slim::Schema->search('Track', { 'url' => $track->{'FILENAME'} . '#%' })->delete_all;
		}

		push @items, $track->{'URI'}; #url;
		
		# Bug 1855: force track size metadata from basetrack into indexed track.
		# this forces the basetrack object expansion as well, so other metadata
		$track->{'SIZE'} = $basetrack->audio_size;

		# our tracks won't be visible if we don't include some data from the base file
		my %data = $basetrack->get_columns;

		for my $attribute (keys %data) {

			next if $attribute eq 'id';
			next if $attribute eq 'url';

			if (defined defined $data{$attribute} && !exists $track->{uc $attribute}) {
			
				$track->{uc $attribute} = $data{$attribute};
			}
		}
		
		# Mark track as virtual
		$track->{VIRTUAL} = 1;

		$class->processAnchor($track);

		# Do the actual data store
		# Skip readTags since we'd just be reading the same file over and over
		Slim::Schema->updateOrCreate({
			'url'        => $track->{'URI'},
			'attributes' => $track,
			'readTags'   => 0,  # no need to read tags, since we did it for the base file
		});
	}

	if ( main::INFOLOG && $log->is_info ) {
		$log->info("    returning: " . scalar(@items) . " items");
	}

	return @items;
}

sub processAnchor {
	my ($class, $attributesHash) = @_;

	my ($start, $end) = Slim::Music::Info::isFragment($attributesHash->{'URI'});

	# rewrite the size, offset and duration if it's just a fragment
	# This is mostly (always?) for cue sheets.
	if (!defined $start && !defined $end) {

		$log->warn("Couldn't process anchored file fragment for $attributesHash->{'URI'}");

		return 0;
	}

	my $duration = $end - $start;

	# Don't divide by 0
	if (!defined $attributesHash->{'SECS'} && $duration) {

		$attributesHash->{'SECS'} = $duration;

	} elsif (!$attributesHash->{'SECS'}) {

		$log->warn("Couldn't process undef or 0 SECS fragment for $attributesHash->{'URI'}");

		return 0;
	}
	
	my ($startbytes, $endbytes);
	
	my $header = $attributesHash->{'OFFSET'} || 0;
	
	# Bug 8877, use findFrameBoundaries to find the accurate split points if the format supports it
	my $ct = $attributesHash->{'CONTENT_TYPE'};
	my $formatclass = Slim::Formats->classForFormat($ct);
	
	if ( $formatclass->can('findFrameBoundaries') ) {		
		my $path = Slim::Utils::Misc::pathFromFileURL( $attributesHash->{'FILENAME'} );
		open my $fh, '<', $path;
		
		if ( $start > 0 ) {
			$startbytes = $formatclass->findFrameBoundaries( $fh, undef, $start );	
			$attributesHash->{'OFFSET'} = $startbytes;
		}
		else {
			$attributesHash->{'OFFSET'} = $header;
			
			if ( $ct eq 'mp3' && $attributesHash->{LAYER_ID} == 1 ) { # LAYER_ID 1 == mp3
				# MP3 only - We need to skip past the LAME header so the first chunk
				# doesn't get truncated by the firmware thinking it needs to remove encoder padding
				seek $fh, 0, 0;
				my $s = Audio::Scan->scan_fh( mp3 => $fh, { filter => 0x01 } );
				if ( $s->{info}->{lame_encoder_version} ) {
					my $next = Slim::Formats::MP3->findFrameBoundaries( $fh, $header + 1 );
					$attributesHash->{'OFFSET'} += $next;
				}
				
				eval {
					# Pre-scan the file with MP3::Cut::Gapless to create frame data cache file
					# that will be used during playback
					require MP3::Cut::Gapless;
				
					main::INFOLOG && $log->is_info && $log->info("Pre-caching MP3 gapless split data for $path");
				
					MP3::Cut::Gapless->new(
						file      => $path,
						cache_dir => catdir( $prefs->get('librarycachedir'), 'mp3cut' ),
					);
				};
				if ($@) {
					$log->warn("Unable to scan $path for gapless split data: $@");
				}
			}
		}
		
		if ( $attributesHash->{SECS} == $attributesHash->{END} ) {
			# Bug 11950, The last track should always extend to the end of the file
			$endbytes = $attributesHash->{SIZE};
		}
		else {		
			seek $fh, 0, 0;
		
			my $newend = $formatclass->findFrameBoundaries( $fh, undef, $end );
			if ( $newend ) {
				$endbytes = $newend;
			}
		}
		
		$attributesHash->{'SIZE'} = $endbytes - $attributesHash->{'OFFSET'};
		
		close $fh;
	}
	else {
		# Just take a guess as to the offset position
		my $byterate = $attributesHash->{'SIZE'} / $attributesHash->{'SECS'};
		
		$startbytes = int($byterate * $start);
		$endbytes   = int($byterate * $end);

		$startbytes -= $startbytes % $attributesHash->{'BLOCK_ALIGNMENT'} if $attributesHash->{'BLOCK_ALIGNMENT'};
		$endbytes   -= $endbytes % $attributesHash->{'BLOCK_ALIGNMENT'} if $attributesHash->{'BLOCK_ALIGNMENT'};
		
		$attributesHash->{'OFFSET'} = $header + $startbytes;
		$attributesHash->{'SIZE'} = $endbytes - $startbytes;
	}
	
	$attributesHash->{'SECS'} = $duration;
	
	# Remove existing TITLESORT value as it won't match the title for the cue entry
	delete $attributesHash->{TITLESORT};

	if ( main::DEBUGLOG && $log->is_debug ) {
		$log->debug( sprintf(
			"New virtual track ($start-$end): start: %d, end: %d, size: %d, length: %d",
			$attributesHash->{'OFFSET'},
			$attributesHash->{'SIZE'} + $attributesHash->{'OFFSET'},
			$attributesHash->{'SIZE'},
			$attributesHash->{'SECS'},
		) );
	}
}

1;

__END__
