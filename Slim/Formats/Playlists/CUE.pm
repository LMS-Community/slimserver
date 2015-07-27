package Slim::Formats::Playlists::CUE;

# $Id$

# Logitech Media Server Copyright 2001-2011 Logitech.
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use base qw(Slim::Formats::Playlists::Base);

use File::Slurp;

use Slim::Music::Info;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;
use Slim::Utils::Unicode;

my $log = logger('formats.playlists');
my $prefs = preferences('server');

#List of the standard cuesheet commands.
# see http://en.wikipedia.org/wiki/Cue_sheet_%28computing%29
#     http://wiki.hydrogenaud.io/index.php?title=Cue_sheet
#
# here as an alternate source of CDRWIN help: 
# http://digitalx.org/cue-sheet/syntax/

my %standardCueCommands = (
	CATALOG    => 1,
	CDTEXTFILE => 1,
	FILE       => 1,
	FLAGS      => 1,
	INDEX      => 1,
	ISRC       => 1,
	PERFORMER  => 1,
	POSTGAP    => 1,
	PREGAP     => 1,
	REM        => 1,
	SONGWRITER => 1,
	TITLE      => 1,
	TRACK      => 1
);

# List of valid commands we want to ignore.
# PREGAP is calulated when INDEX = 00 (not sure is correct, but it does'nt hurt). 
# POSTGAP FLAGS CDTEXTFILE are just ignored by slimserver.

my %refusedCueCommands = (
	CDTEXTFILE => 1,
	FLAGS      => 1,
	PREGAP     => 1,
	POSTGAP    => 1
);

# List of rem commands or INFO we must get from standard commands or
# reading info from audiofile. Kind of 'reserved' words.
#
# refused commands (see above) dont need to be inclued here.
# Standard accepted commands are accepted also if issued as REM commands
# this is questionable, but does not hurt (the first found is stored).

my %refusedRemCommands = (
	ALBUM        => 1,
	AUDIO        => 1,
	CONTENT_TYPE => 1,
	DRM          => 1,
	FILE         => 1,
	FILENAME     => 1,
	FILESIZE     => 1,
	INDEX        => 1,
	LOSSLESS     => 1,
	OFFSET       => 1,
	SECS         => 1,
	SIZE         => 1,
	START        => 1,
	TIMESTAMP    => 1,
	TITLESORT    => 1,
	TRACK        => 1,
	URI          => 1,
	VIRTUAL      => 1
);

# the following values are only valid at the album level
my @albumOnlyCommands = qw(ALBUMARTIST ALBUMARTISTSORT ALBUMSORT COMPILATION DISCC CATALOG ISRC 
							MUSICBRAINZ_ALBUM_ID MUSICBRAINZ_ALBUMARTIST_ID MUSICBRAINZ_ALBUM_TYPE MUSICBRAINZ_ALBUM_STATUS 
							REPLAYGAIN_ALBUM_GAIN REPLAYGAIN_ALBUM_PEAK);

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

	my $inAlbum = 1;
	for my $line (@$lines) {

		my $enc = Slim::Utils::Unicode::encodingFromString($line);

		# Prefer UTF8 for CUE sheets.
		$line = Slim::Utils::Unicode::utf8decode_guess($line, 'utf8', $enc) unless $line =~ /^FILE\s+/i;

		# strip whitespace from end
		$line =~ s/\s*$//;

		# Most of the test were trusting on the absence of leading spaces
		# to determinate if the command was related to ALBUM or TRACK.
		# According with CUE SHEET specification, this is not enought:
		# Spaces or tabs can be used to indent; they're ignored but can 
		# make the file easier to understand when viewing or manually editing
		# http://www.hydrogenaudio.org/forums/index.php?act=ST&f=20&t=4586
		#
		# $currtrack was used to relate Commands to a specific Track or 
		# to Album if not defined, but if a Non Audio Track was encountered, 
		# subseguent commands were applied to the previous track.
		# 
		# $inAlbum variable was introduced: is turned on before the loop start
		# and turned off when the first TRACK command is encountered.
		#
		# $currentTrack is setted when a TRACK command with AUDIO is encountered.
		# if the TRACK command is not related to AUDIO, then $currentTrack is cleared.
		#
		# This way, any command issued after a NON AUDIO TRACK and before a valid
		# AUDIO TRACK is skipped, also if the NON AUDIO track is the first one,
		# instead of storing them as album / previous Track related as before.
		#
		# All checks on values that imply a lookup to other has been delayed at the
		# step after the line loop. 
		#
		# Here some basic validation check on single commands when:
		# 1. relative position has a meaning (i.e TRACK, INDEX, REM END, FILE)
		# 2. special syntax validation is needed (i.e. REPLAYGAIN, COMPILATION).
		#
		# Most of what was done here before has been moved after the line loop.
		# 
		my ($command, $value);

		if ($line =~ /^\s*(\S+)\s+(.*)/i) {
			$command = $1;
			$value   = $2;
		}

		if (!defined $command || !defined $value) {

			#No commads in line, skipping;

			main::DEBUGLOG && $log->is_debug && $log->debug('No command in line: Skipping ' . Data::Dump::dump({
				line	=> $line,
				command => $command,
				value	=> $value
			}));

		} elsif (!$standardCueCommands{$command} || $refusedCueCommands{$command}) {

			#Command refused;
			main::DEBUGLOG && $log->is_debug && $log->debug('Command refused ' . Data::Dump::dump({
				line	=> $line,
				command => $command,
				value	=> $value
			}));

		} elsif ($command eq 'TRACK') {

			$inAlbum = 0;

			#Skipping non audio tracks.
			if ($value =~ /^(\d+)\s+AUDIO/i) {

				$currtrack = int($1);

			} elsif ($value =~ /^(\d+)\s+.*/i) {

				$currtrack = undef;
			}

		} elsif ($command eq 'INDEX') {

			if (!defined $currtrack) {
				#Ignored
				main::DEBUGLOG && $log->debug("Index found for missing Track");

			} elsif ($value =~ /^00\s+(\d+):(\d+):(\d+)/i) {

				$tracks->{$currtrack}->{'PREGAP'} = ($1 * 60) + $2 + ($3 / 75);

			} elsif ($value =~ /^01\s+(\d+):(\d+):(\d+)/i) {

				$tracks->{$currtrack}->{'START'} = ($1 * 60) + $2 + ($3 / 75);
			}

		} elsif ($command eq 'REM') {

			my ($remCommand, $remValue);
	
			if ($value =~ /^\"(.*)\"/i) {
				$remValue = $1;
			} 
			elsif ($value =~ /^\s*(\S+)\s+(.*)/i) {
				$remCommand = $1;
				$remValue   = $2;
			}

			if (!defined $remCommand || !defined $remValue) {

				#No commads in rem, skipping;
				main::DEBUGLOG && $log->is_debug && $log->debug('No commads in rem, skipping ' . Data::Dump::dump({
					line		=> $line,
					command		=> $command,
					value		=> $value,
					remCommand	=> $remCommand,
					remValue	=> $remValue
				}));

			} elsif ($refusedRemCommands{$remCommand} || $refusedCueCommands{$remCommand}) {

				#Rem command refused;
				main::DEBUGLOG && $log->is_debug && $log->debug('Rem command refused ' . Data::Dump::dump({
					inAlbum		=> $inAlbum,
					currtrack	=> $currtrack,
					line		=> $line,
					command		=> $command,
					value		=> $value,
					remCommand	=> $remCommand,
					remValue	=> $remValue
				}));

			} elsif ($remCommand eq 'END') {

				if (!defined $currtrack) {
					#Ignored
					main::DEBUGLOG && $log->debug("End found for missing Track");

				} elsif ($remValue =~ /^(\d+):(\d+):(\d+)/i) {

					$tracks->{$currtrack}->{'END'} = ($1 * 60) + $2 + ($3 / 75);

				} elsif ($remValue =~ /^(.+)/i) {

					# Bug 11950, pass absolute end time in seconds (FLAC), since some loss of accuracy would
					# occur if passing in MM:SS:FF format			
					$tracks->{$currtrack}->{'END'} = $1;
				}

			} elsif ($remCommand eq 'REPLAYGAIN_ALBUM_GAIN' || $remCommand eq 'REPLAYGAIN_TRACK_GAIN') {

				if ($remValue =~ /^\"?(.*)dB/i) {

					($cuesheet, $tracks) = _addCommand($cuesheet, 
													 $tracks,
													 $inAlbum,
													 $currtrack,
													 $remCommand,
													 $1);
				} 

			} elsif ($remCommand eq 'COMPILATION') {

				if ($remValue && $remValue =~ /1|YES|Y/i) {

					($cuesheet, $tracks) = _addCommand($cuesheet, 
													 $tracks,
													 $inAlbum,
													 $currtrack,
													 $remCommand,
													 '1');
				}

			} else {

				# handle remaning REM commans as a list of keys and values.

				main::DEBUGLOG && $log->is_debug && $log->debug('Rem command ' . Data::Dump::dump({
					inAlbum		=> $inAlbum,
					currtrack	=> $currtrack,
					line		=> $line,
					command		=> $command,
					value		=> $value,
					remCommand	=> $remCommand,
					remValue	=> $remValue
				}));
				
				($cuesheet, $tracks) = _addCommand($cuesheet, 
												 $tracks,
												 $inAlbum,
												 $currtrack,
												 $remCommand,
												 _removeQuotes($remValue));
			}

		} elsif ($command eq 'FILE') {

			if ($inAlbum && $value =~ /^\"(.*)\"/i) {
				$filename = $embedded || $1;
				$filename = Slim::Utils::Misc::fixPath($filename, $baseDir);

				# Watch out for cue sheets with multiple FILE entries
				$filesSeen++;
				
				main::DEBUGLOG && $log->is_debug && $log->debug('Filename with quotes ' . Data::Dump::dump({
					line		=> $line,
					command		=> $command,
					value		=> $value,
					filename	=> $filename,
					returned	=> $1
				}));

			} elsif ($inAlbum && $value =~ /^\"?(\S+)\"?/i) {

				# Some cue sheets may not have quotes. Allow that, but
				# the filenames can't have any spaces in them."
				$filename = $embedded || $1;
				$filename = Slim::Utils::Misc::fixPath($filename, $baseDir);

				$filesSeen++;
				
				main::DEBUGLOG && $log->is_debug && $log->debug('Filename with no quotes ' . Data::Dump::dump({
					line		=> $line,
					command		=> $command,
					value		=> $value,
					filename	=> $filename,
					returned	=> $1
				}));

			} elsif ($inAlbum) {

				# Invalid filename, skipped.
				main::DEBUGLOG && $log->is_debug && $log->debug('Invalid filename ' . Data::Dump::dump({
					line		=> $line,
					command		=> $command,
					value		=> $value
				}));

			} elsif (defined $currtrack && defined $filename) {

				# Bug 5735, skip cue sheets with multiple FILE entries.
				# This is not the right thing to do, but let's at least not break
				# the existing functionality... See TODO comment below.
				#
				# Each track in a cue sheet can have a different
				# filename. See Bug 2126 &
				# http://www.hydrogenaudio.org/forums/index.php?act=ST&f=20&t=4586
			
				$tracks->{$currtrack}->{'FILENAME'} = $filename;
				$filesSeen++;
			} 
			
			# TODO: Correctly Handle Multiple file cue sheet.
			# http://www.hydrogenaudio.org/forums/index.php?act=ST&f=20&t=4586

		} else {

			# handle remaning Commands as a list of keys and values.
			($cuesheet, $tracks) = _addCommand($cuesheet, 
											 $tracks,
											 $inAlbum,
											 $currtrack,
											 $command,
											 _removeQuotes($value));
		}
		
		last if $filesSeen && $filesSeen > 1;
	}

	# Bug 5735, skip cue sheets with multiple FILE entries
	if ( $filesSeen > 1 ) {
		$log->warn('Skipping cuesheet with multiple FILE entries');
		return;
	}
	
	main::DEBUGLOG && $log->is_debug && $log->debug('After line parsing ' . Data::Dump::dump({
		cuesheet	=> $cuesheet,
		tracks		=> $tracks,
		filename	=> $filename
	}));

	# Here controls on the entire cuesheet structure, moving attributes
	# to the correct level, preventing duplicates and renaming when needed.

	_mergeCommand('TITLE', 'ALBUM', $cuesheet, $cuesheet);
	
	_mergeCommand('PERFORMER', 'ALBUMARTIST', $cuesheet, $cuesheet);
	$cuesheet->{'ARTIST'} = $cuesheet->{'ALBUMARTIST'} if !defined $cuesheet->{'ARTIST'};

	# Songwriter is the standard command for composer
	_mergeCommand('SONGWRITER', 'COMPOSER', $cuesheet, $cuesheet);

	_mergeCommand('DISCNUMBER', 'DISC', $cuesheet, $cuesheet);
	_mergeCommand('DISCTOTAL', 'DISCC', $cuesheet, $cuesheet);
	_mergeCommand('TOTALDISCS', 'DISCC', $cuesheet, $cuesheet);
	
	# EAC CUE sheet has REM DATE not REM YEAR, and no quotes	
	_mergeCommand('DATE', 'YEAR', $cuesheet, $cuesheet);

	for my $key (sort {$a <=> $b} keys %$tracks) {

		my $track = $tracks->{$key};
		
		# some values are only valid at the album level, keep the first found.
		foreach ( @albumOnlyCommands ) {
			_mergeCommand($_, $_, $track, $cuesheet);
		}

		my $performer = delete $track->{'PERFORMER'};
		if (defined $performer) {

			$track->{'ARTIST'}      = $performer;
			$track->{'TRACKARTIST'} = $performer;

			# Automatically flag a compilation album
			# since we are setting the artist.

			if (defined($cuesheet->{'ALBUMARTIST'}) && $cuesheet->{'ALBUMARTIST'} ne $performer) {
				$cuesheet->{'COMPILATION'} = '1';
				# Deleted the condition on 'defined', it could be defined
				# but equal NO, N, 0,... or what else.
				# we want it to be = 1 in this case.
			}
		}

		# Songwriter is the standard command for composer
		_mergeCommand('SONGWRITER', 'COMPOSER', $track, $track);

		_mergeCommand('DISCTOTAL', 'DISCC', $track, $cuesheet);
		_mergeCommand('TOTALDISCS', 'DISCC', $track, $cuesheet);

		# EAC CUE sheet has REM DATE not REM YEAR, and no quotes
		_mergeCommand('DATE', 'YEAR', $track, $track);

		_mergeCommand('DISCNUMBER', 'DISC', $track, $track);
	}

	#
	# WARNING: Compilation could be false if Album Artist is not defined,
	# even if artist is not the same in all the tracks. See my note below.
	#

	main::DEBUGLOG && $log->is_debug && $log->debug('Before merging ' . Data::Dump::dump({
		cuesheet	=> $cuesheet,
		tracks		=> $tracks,
		filename	=> $filename
	}));
	
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
		for my $file_attribute ( qw(CONTENT_TYPE ALBUMARTIST ARTIST ALBUM YEAR  
							GENRE DISC DISCNUMBER DISCC DISCTOTAL TOTALDISCS 
							REPLAYGAIN_ALBUM_GAIN REPLAYGAIN_ALBUM_PEAK 
							ARTISTSORT ALBUMARTISTSORT ALBUMSORT COMPILATION)) {

			my $attribute = $file_attribute;
			if ($file_attribute eq 'DISCNUMBER') {
				$attribute = 'DISC';
			} elsif ($file_attribute eq 'TOTALDISCS' or $file_attribute eq 'DISCTOTAL') {
				$attribute = 'DISCC';
			}

			if (!$cuesheet->{$attribute}) {

				my $fromFile = $tags->{$file_attribute};

				if (defined $fromFile) {
					$cuesheet->{$attribute} = $fromFile;
				}
			}
		}
	}
	# WARNING: 
	# if the Album artist was not defined in cue sheet, Compilation could be 
	# false, even if all the tracks are from different artists and Abum artist 
	# was defined in Audio file. 
	#
	# Lived untouched, sounds like an error to me, but different people 
	# use compilation with different meaning, so better stay as it was before.
	#
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

		main::DEBUGLOG && $log->debug("URL: $track->{'URI'}");

		$track->{'TRACKNUM'} = $key;

		# This loop is just for debugging purpose...
		if (main::DEBUGLOG && $log->is_debug) {
			for my $attribute ('TRACKNUM', Slim::Schema::Contributor->contributorRoles,
				qw(TITLE ALBUM YEAR GENRE REPLAYGAIN_TRACK_PEAK REPLAYGAIN_TRACK_GAIN)) {
	
				if (exists $track->{$attribute}) {
					$log->debug("    $attribute: $track->{$attribute}");
				}
			}
		}

		# Merge in file level attributes
		for my $attribute (keys %$cuesheet) {

			if (!exists $track->{$attribute} && defined $cuesheet->{$attribute}) {
					
				# Bug 18110 - only merge ALBUMARTIST/ARTISTSORT if the track's ALBUMARTIST/ARTIST is the same as the album's
				next if $attribute =~ /(.*)SORT$/ && $track->{$1} ne $cuesheet->{$1};

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

	main::DEBUGLOG && $log->is_debug && $log->debug('End of CUE sheet parsing ' . Data::Dump::dump($tracks));

	return $tracks;
}

sub _addCommand {
	my $cuesheet	= shift;
	my $tracks		= shift;
	my $inAlbum		= shift;
	my $currtrack	= shift;
	my $command		= shift;
	my $value		= shift;

	if ($inAlbum && !defined $cuesheet->{$command}) {
		$cuesheet->{$command} = $value;
	} elsif (defined $currtrack && !defined $tracks->{$currtrack}->{$command}) {
		$tracks->{$currtrack}->{$command} = $value;
	}

	return ($cuesheet,$tracks);
}

# little helper method to merge alternative command names
sub _mergeCommand {
	my ($oldCommand, $newCommand, $oldContext, $newContext) = @_;
	
	my $value = delete $oldContext->{$oldCommand};
	
	if (defined $value && !defined $newContext->{$newCommand}) {
		$newContext->{$newCommand} = $value;
	}
}

sub _removeQuotes {
	my $line	= shift;

	$line =~ s/^\"(.*?)\".*/$1/i;
	return $line;
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
				require Audio::Scan;
				
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
					require File::Spec::Functions;
				
					main::INFOLOG && $log->is_info && $log->info("Pre-caching MP3 gapless split data for $path");
				
					MP3::Cut::Gapless->new(
						file      => $path,
						cache_dir => File::Spec::Functions::catdir( $prefs->get('librarycachedir'), 'mp3cut' ),
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
