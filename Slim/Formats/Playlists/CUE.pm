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

use Data::Dump qw(dump); #could be removed in production, usefull in debug.

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
#
my @standardCueCommands = qw(CATALOG CDTEXTFILE FILE FLAGS INDEX ISRC PERFORMER
                             POSTGAP PREGAP REM SONGWRITER TITLE TRACK);

# List of valid commands we want to ignore.
# PREGAP is calulated when INDEX = 00 (not sure is correct, but it does'nt hurt). 
# POSTGAP FLAGS CDTEXTFILE are just ignored by slimserver.
#
my @refusedCueCommands = qw(PREGAP POSTGAP FLAGS CDTEXTFILE);

# List of rem commands or INFO we must get from standard commands or
# reading info from audiofile. Kind of 'reserved' words.
#
# refused commands (see above) dont need to be inclued here.
# Standard accepted commands are accepted also if issued as REM commands
# this is questionable, but does not hurt (the first found is stored).
#
my @refusedRemCommands =qw(URI FILENAME CONTENT_TYPE AUDIO LOSSLESS
                           VIRTUAL START FILE TRACK INDEX SECS OFFSET
                           TIMESTAMP SIZE FILESIZE DRM ALBUM TITLESORT);

# This now just processes the cuesheet into tags. The calling process is
# responsible for adding the tracks into the datastore.
sub parse {
	my $class    = shift;
	my $lines    = shift;
	my $baseDir  = shift;
	my $embedded = shift || 0;

	my ($filename, $inAlbum, $currtrack);
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
       
        $inAlbum = 1;
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
                my($command,$value)= _getCommandFromLine($line);

                if (!defined $command or !defined $value){
                    
                    #No commads in line, skipping;

                    #my $msg = {};
                    #$msg->{'message'}  = 'Skipping the line';
                    #$msg->{'line'}  = $line;
                    #$msg->{'command'}   = $command;
                    #$msg->{'value'} = $value;

                    #dump $msg;
                    main::DEBUGLOG && $log->debug("No command in line : $line");
  
                } elsif (!_isCommandAccepted($command)){

                    #Command refused;

                    #my $msg = {};
                    #$msg->{'message'}  = 'Command refused';
                    #$msg->{'line'}  = $line;
                    #$msg->{'command'}   = $command;
                    #$msg->{'value'} = $value;

                    #dump $msg;
                    main::DEBUGLOG && $log->debug("Command refused: $command");
                
                } elsif ($command eq 'TRACK'){
                    
                    $inAlbum=0;

                    #Skipping non audio tracks.
                    if ($value =~ /^(\d+)\s+AUDIO/i) {

                        $currtrack = int($1);

                    } elsif ($value =~ /^(\d+)\s+.*/i){
                        
                        $currtrack=undef;
                    }

                } elsif ($command eq 'INDEX'){
                    
                    if (!defined $currtrack){
                        #Ignored
                        main::DEBUGLOG && $log->debug("Index found for missing Track");

                    }elsif ($value =~ /^00\s+(\d+):(\d+):(\d+)/i) {  
                
			$tracks->{$currtrack}->{'PREGAP'} = ($1 * 60) + $2 + ($3 / 75);
                    
                    } elsif ($value =~ /^01\s+(\d+):(\d+):(\d+)/i){

			$tracks->{$currtrack}->{'START'} = ($1 * 60) + $2 + ($3 / 75);
                    }

		} elsif ($command eq 'REM') {
                        
                        my($remCommand,$remValue)= _getRemCommandFromLine($value);
                        
                        if (!defined $remCommand or !defined $remValue){
                    
                            #No commads in rem, skipping;

                            #my $msg = {};
                            #$msg->{'message'}  = 'No commads in rem, skipping';
                            #$msg->{'line'}  = $line;
                            #$msg->{'command'}   = $command;
                            #$msg->{'value'} = $value;
                            #$msg->{'remCommand'}   = $remCommand;
                            #$msg->{'remValue'} = $remValue;

                            #dump $msg;
                            main::DEBUGLOG && $log->debug("No command in rem : $line"); 

                        } elsif (!_isRemCommandAccepted($remCommand)){
                        
                            #Rem command refused;

                            #my $msg = {};
                            #$msg->{'message'}      = 'Rem command refused';
                            #$msg->{'inAlbum'}      = $inAlbum;
                            #$msg->{'currtrack'}    = $currtrack;
                            #$msg->{'line'}         = $line;
                            #$msg->{'command'}      = $command;
                            #$msg->{'value'}        = $value;
                            #$msg->{'remCommand'}   = $remCommand;
                            #$msg->{'remValue'}     = $remValue;

                            #dump $msg;
                            main::DEBUGLOG && $log->debug("Rem Command refused: $line");
                            
                        } elsif ($remCommand eq 'END'){
                            
                            if (!defined $currtrack){
                                #Ignored
                                main::DEBUGLOG && $log->debug("End found for missing Track");

                            }elsif ($remValue =~ /^(\d+):(\d+):(\d+)/i) {

                                $tracks->{$currtrack}->{'END'} = ($1 * 60) + $2 + ($3 / 75);
                            
                            } elsif ($remValue =~ /^(.+)/i) {
                            
                                # Bug 11950, pass absolute end time in seconds (FLAC), since some loss of accuracy would
                                # occur if passing in MM:SS:FF format			
                                $tracks->{$currtrack}->{'END'} = $1;
                            }
                        } elsif ($remCommand eq 'REPLAYGAIN_ALBUM_GAIN'){
                                
                            if ($remValue =~ /^\"(.*)dB\"/i) {#"

                                ($cuesheet, $tracks)=_addCommand($cuesheet, 
                                                                 $tracks,
                                                                 $inAlbum,
                                                                 $currtrack,
                                                                 $remCommand,
                                                                 $1);

                            } elsif ($remValue =~ /^(.*)dB/i)  {

                                ($cuesheet, $tracks)=_addCommand($cuesheet, 
                                                                 $tracks,
                                                                 $inAlbum,
                                                                 $currtrack,
                                                                 $remCommand,
                                                                 $1);
                            } 

                        } elsif ($remCommand eq 'REPLAYGAIN_TRACK_GAIN'){
                               
                            if ($remValue =~ /^\"(.*)dB\"/i) {#"

                                ($cuesheet, $tracks)=_addCommand($cuesheet, 
                                                                 $tracks,
                                                                 $inAlbum,
                                                                 $currtrack,
                                                                 $remCommand,
                                                                 $1);

                            } elsif ($remValue =~ /^(.*)dB/i) {

                                ($cuesheet, $tracks)=_addCommand($cuesheet, 
                                                                 $tracks,
                                                                 $inAlbum,
                                                                 $currtrack,
                                                                 $remCommand,
                                                                 $1);
                            }
                        } elsif ($remCommand eq 'COMPILATION'){

                            if(_validateBoolean($remValue)){
                               
                                ($cuesheet, $tracks)=_addCommand($cuesheet, 
                                                                 $tracks,
                                                                 $inAlbum,
                                                                 $currtrack,
                                                                 $remCommand,
                                                                 '1');
                            }
                            
                        }else {

                            # handle remaning REM commans as a list of keys and values.
                            
                            #my $msg = {};
                            #$msg->{'message'}       = 'REM commans';
                            #$msg->{'inAlbum'}       = $inAlbum;
                            #$msg->{'currtrack'}     = $currtrack;
                            #$msg->{'line'}          = $line;
                            #$msg->{'command'}       = $command;
                            #$msg->{'value'}         = $value;
                            #$msg->{'remCommand'}    = $remCommand;
                            #$msg->{'remValue'}      = $remValue;

                            #dump $msg;

                            ($cuesheet, $tracks)=_addCommand($cuesheet, 
                                                             $tracks,
                                                             $inAlbum,
                                                             $currtrack,
                                                             $remCommand,
                                                             _removeQuotes($remValue));
                        }

		} elsif ($command eq 'FILE') {

                    if ($inAlbum and $value =~ /^\"(.*)\"/i){ #"
                        $filename = $embedded || $1;
                        $filename = Slim::Utils::Misc::fixPath($filename, $baseDir);
                        
                        # Watch out for cue sheets with multiple FILE entries
                        $filesSeen++;
                        
                        #my $msg = {};
                        #$msg->{'message'}   = 'filename with quotes';
                        #$msg->{'line'}      = $line;
                        #$msg->{'command'}   = $command;
                        #$msg->{'value'}     = $value;
                        #$msg->{'filename'}  = $filename;
                        #$msg->{'val'}       = $1;
    
                        #dump $msg;

                    } elsif ($inAlbum and $value =~ /^\"?(\S+)\"?/i) {

                        # Some cue sheets may not have quotes. Allow that, but
                        # the filenames can't have any spaces in them."
                        $filename = $embedded || $1;
                        $filename = Slim::Utils::Misc::fixPath($filename, $baseDir);

                        $filesSeen++;
                        
                        #my $msg = {};
                        #$msg->{'message'}   = 'filename with no quotes';
                        #$msg->{'line'}      = $line;
                        #$msg->{'command'}   = $command;
                        #$msg->{'value'}     = $value;
                        #$msg->{'filename'}  = $filename;
                        #$msg->{'val'}       = $1;

                        #dump $msg;

                    } elsif ($inAlbum){
                       
                        # Invalid filename, skipped.

                        #my $msg = {};
                        #$msg->{'message'}  = 'Invalid filename';
                        #$msg->{'line'}  = $line;
                        #$msg->{'command'}   = $command;
                        #$msg->{'value'} = $value;

                        #dump $msg;
                        main::DEBUGLOG && $log->debug("Invalid filename: $value");
                        
                    } elsif (defined $currtrack and defined $filename){
                        
                        # Better remove this point.
                        # To me it doesn't do what its was meant to do.
                        #
                        # In any case it will not take effect due to 
                        # the patch below marked : 
                        #
                        # Bug 5735, skip cue sheets with multiple FILE entries.
                        # 
                        # Here original comments:
                        #
                        # Each track in a cue sheet can have a different
			# filename. See Bug 2126 &
			# http://www.hydrogenaudio.org/forums/index.php?act=ST&f=20&t=4586
			
                        $tracks->{$currtrack}->{'FILENAME'} = $filename;
                    } 
                    # TODO: Correctly Handle Multiple file cue sheet.
                    # http://www.hydrogenaudio.org/forums/index.php?act=ST&f=20&t=4586

                } else {
                
                    # handle remaning Commands as a list of keys and values.
                    ($cuesheet, $tracks)=_addCommand($cuesheet, 
                                                     $tracks,
                                                     $inAlbum,
                                                     $currtrack,
                                                     $command,
                                                     _removeQuotes($value));
                }   
        }

        #dump $cuesheet;
        #dump $tracks;
        #dump $filename;

	# Bug 5735, skip cue sheets with multiple FILE entries
	if ( $filesSeen > 1 ) {
		$log->warn('Skipping cuesheet with multiple FILE entries');
		return;
	}
        # Here controls on the entyre cuesheet structure, moving attributes
        # to the correct level, preventing duplicates and renaming when needed.
        #
        if (defined $cuesheet->{'TITLE'}){
            $cuesheet->{'ALBUM'} = $cuesheet->{'TITLE'};
            delete $cuesheet->{'TITLE'};
        }
        if (defined $cuesheet->{'PERFORMER'}){
            
            $cuesheet->{'ARTIST'} = $cuesheet->{'PERFORMER'};
            $cuesheet->{'ALBUMARTIST'} = $cuesheet->{'PERFORMER'};
            delete $cuesheet->{'PERFORMER'};
        }
        if (defined $cuesheet->{'SONGWRITER'}){
            
            # Songwriiter is the standard command for composer
            $cuesheet->{'COMPOSER'} = $cuesheet->{'SONGWRITER'};
            delete $cuesheet->{'SONGWRITER'};
        }
        if (defined $cuesheet->{'DISCNUMBER'}){

            if (!defined $cuesheet->{'DISC'}){
                $cuesheet->{'DISC'} = $cuesheet->{'DISCNUMBER'};
            }   
            delete $cuesheet->{'DISCNUMBER'};
        }
        if (defined $cuesheet->{'DISCTOTAL'}){
            
            if (!defined $cuesheet->{'DISCC'}){
                $cuesheet->{'DISCC'} = $cuesheet->{'DISCTOTAL'};
            }
            delete $cuesheet->{'DISCTOTAL'};
        }
        if (defined $cuesheet->{'TOTALDISCS'}){
            
            if (!defined $cuesheet->{'DISCC'}){
                $cuesheet->{'DISCC'} = $cuesheet->{'TOTALDISCS'};
            }
            delete $cuesheet->{'TOTALDISCS'};
        }
        if (defined $cuesheet->{'DATE'}){

            # EAC CUE sheet has REM DATE not REM YEAR, and no quotes	
            if (!defined $cuesheet->{'YEAR'}) {
                $cuesheet->{'YEAR'} = $cuesheet->{'DATE'};
            }
            delete $cuesheet->{'DATE'};
        } 
        for my $key (sort {$a <=> $b} keys %$tracks) {

            my $track = $tracks->{$key};

            if (defined $track->{'ALBUMARTIST'}){
                
                # ALBUMARTIST is valid only at ALBUM level, keep the first found.
                if (!defined $cuesheet->{'ALBUMARTIST'}){
                    $cuesheet->{'ALBUMARTIST'} = $track->{'ALBUMARTIST'};
                }
                delete $track->{'ALBUMARTIST'};
            }
            if (defined $track->{'PERFORMER'}) {

		$track->{'ARTIST'} = $track->{'PERFORMER'};
                $track->{'TRACKARTIST'} = $track->{'PERFORMER'};

                # Automatically flag a compilation album
		# since we are setting the artist.
		if (defined($cuesheet->{'ALBUMARTIST'}) && 
                    ($track->{'PERFORMER'} ne $cuesheet->{'ALBUMARTIST'})) {
                        
                        $cuesheet->{'COMPILATION'} = '1'; # if not defined($cuesheet->{'COMPILATION'})
                        # Deleted the condition on 'defined', it could be defined
                        # but equal NO, N, 0,... or what else.
                        # we want it to be = 1 in this case.
                }

                delete $track->{'PERFORMER'};
            }
            if (defined $track->{'SONGWRITER'}){
            
                # Songwriiter is the standard command for composer
                $track->{'COMPOSER'} = $track->{'SONGWRITER'};
                delete $track->{'SONGWRITER'};
            }
            if (defined $track->{'CATALOG'}){
                
                # CATALOG is valid only at ALBUM level, keep the first found.
                if (!defined $cuesheet->{'CATALOG'}){
                    $cuesheet->{'CATALOG'} = $track->{'CATALOG'};
                }
                delete $track->{'CATALOG'};
            }
            if (defined $track->{'ISRC'}){
                
                # ISRC is valid only at ALBUM level, keep the first found.
                if (!defined $cuesheet->{'ISRC'}){
                    $cuesheet->{'ISRC'} = $track->{'ISRC'};
                }
                delete $track->{'ISRC'};
            }
            
            if (defined $track->{'ALBUMARTISTSORT'}){
                
                # ALBUMARTISTSORT is valid only at ALBUM level, keep the first found.
                if (!defined $cuesheet->{'ALBUMARTISTSORT'}){
                    $cuesheet->{'ALBUMARTISTSORT'} = $track->{'ALBUMARTISTSORT'};
                }
                delete $track->{'ALBUMARTISTSORT'};
            }
            if (defined $track->{'ALBUMSORT'}){
                
                # ALBUMSORT is valid only at ALBUM level, keep the first found.
                if (!defined $cuesheet->{'ALBUMSORT'}){
                    $cuesheet->{'ALBUMSORT'} = $track->{'ALBUMSORT'};
                }
                delete $track->{'ALBUMSORT'};
            }
            if (defined $track->{'COMPILATION'}){
                
                # COMPILATION is valid only at ALBUM level, 1 if 1 in any trace.
                if (!defined $cuesheet->{'COMPILATION'}){
                    $cuesheet->{'COMPILATION'} = $track->{'COMPILATION'};
                }
                delete $track->{'COMPILATION'};
            }
            if (defined $track->{'MUSICBRAINZ_ALBUM_ID'}){
                
                # MUSICBRAINZ_ALBUM_ID is valid only at ALBUM level, keep the first found.
                if (!defined $cuesheet->{'MUSICBRAINZ_ALBUM_ID'}){
                    $cuesheet->{'MUSICBRAINZ_ALBUM_ID'} = $track->{'MUSICBRAINZ_ALBUM_ID'};
                }
                delete $track->{'MUSICBRAINZ_ALBUM_ID'};
            }
            if (defined $track->{'MUSICBRAINZ_ALBUMARTIST_ID'}){
                
                # MUSICBRAINZ_ALBUMARTIST_ID is valid only at ALBUM level, keep the first found.
                if (!defined $cuesheet->{'MUSICBRAINZ_ALBUMARTIST_ID'}){
                    $cuesheet->{'MUSICBRAINZ_ALBUMARTIST_ID'} = $track->{'MUSICBRAINZ_ALBUMARTIST_ID'};
                }
                delete $track->{'MUSICBRAINZ_ALBUMARTIST_ID'};
            }
            if (defined $track->{'MUSICBRAINZ_ALBUM_TYPE'}){
                
                # MUSICBRAINZ_ALBUM_TYPE is valid only at ALBUM level, keep the first found.
                if (!defined $cuesheet->{'MUSICBRAINZ_ALBUM_TYPE'}){
                    $cuesheet->{'MUSICBRAINZ_ALBUM_TYPE'} = $track->{'MUSICBRAINZ_ALBUM_TYPE'};
                }
                delete $track->{'MUSICBRAINZ_ALBUM_TYPE'};
            }
            if (defined $track->{'MUSICBRAINZ_ALBUM_STATUS'}){
                
                # MUSICBRAINZ_ALBUM_STATUS is valid only at ALBUM level, keep the first found.
                if (!defined $cuesheet->{'MUSICBRAINZ_ALBUM_STATUS'}){
                    $cuesheet->{'MUSICBRAINZ_ALBUM_STATUS'} = $track->{'MUSICBRAINZ_ALBUM_STATUS'};
                }
                delete $track->{'MUSICBRAINZ_ALBUM_STATUS'};
            }
            if (defined $track->{'DISCC'}){
                
                # DISCC is valid only at ALBUM level, keep the first found.
                if (!defined $cuesheet->{'DISCC'}){
                    $cuesheet->{'DISCC'} = $track->{'DISCC'};
                }
                delete $track->{'DISCC'};
            }
            if (defined $track->{'DISCTOTAL'}){
                
                # DISCC is valid only at ALBUM level, keep the first found.
                if (!defined $cuesheet->{'DISCC'}){
                    $cuesheet->{'DISCC'} = $track->{'DISCTOTAL'};
                }
                delete $track->{'DISCTOTAL'};
            }
            if (defined $track->{'TOTALDISCS'}){
                
                # DISCC is valid only at ALBUM level, keep the first found.
                if (!defined $cuesheet->{'DISCC'}){
                    $cuesheet->{'DISCC'} = $track->{'TOTALDISCS'};
                }
                delete $track->{'TOTALDISCS'};
            }
            if (defined $track->{'REPLAYGAIN_ALBUM_GAIN'}){
                
                # REPLAYGAIN_ALBUM_GAIN is valid only at ALBUM level, keep the first found.
                if (!defined $cuesheet->{'REPLAYGAIN_ALBUM_GAIN'}){
                    $cuesheet->{'REPLAYGAIN_ALBUM_GAIN'} = $track->{'REPLAYGAIN_ALBUM_GAIN'};
                }
                delete $track->{'REPLAYGAIN_ALBUM_GAIN'};
            }
            if (defined $track->{'REPLAYGAIN_ALBUM_PEAK'}){
                
                # REPLAYGAIN_ALBUM_PEAK is valid only at ALBUM level, keep the first found.
                if (!defined $cuesheet->{'REPLAYGAIN_ALBUM_PEAK'}){
                    $cuesheet->{'REPLAYGAIN_ALBUM_PEAK'} = $track->{'REPLAYGAIN_ALBUM_PEAK'};
                }
                delete $track->{'REPLAYGAIN_ALBUM_PEAK'};
            }
            if (defined $track->{'DATE'}){

                # EAC CUE sheet has REM DATE not REM YEAR, and no quotes	
                if (!defined $track->{'YEAR'}) {
                    $track->{'YEAR'} = $track->{'DATE'};
                }
                delete $track->{'DATE'};
            }
            if (defined $track->{'DISCNUMBER'}){

                if (!defined $track->{'DISC'}) {
                    $track->{'DISC'} = $track->{'DISCNUMBER'};
                }
                delete $track->{'DISCNUMBER'};
            }
            
            $tracks->{$key} = $track;
        }
        #
        # WARNING: Compilation could be false if Album Artist is not defined,
        # even if artist is not the same in all the tracks. See my note below.
        #
        #dump $cuesheet;
        #dump $tracks;
        #dump $filename;

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
		for my $file_attribute ( qw(CONTENT_TYPE ALBUMARTIST ARTIST ALBUM YEAR GENRE DISC DISCNUMBER DISCC DISCTOTAL TOTALDISCS 
			                        REPLAYGAIN_ALBUM_GAIN REPLAYGAIN_ALBUM_PEAK ARTISTSORT ALBUMARTISTSORT ALBUMSORT COMPILATION)) {

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
        # false, even if all the tracks are from different artists and  Abum artist 
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

		main::DEBUGLOG && $log->debug("    TRACKNUM: $track->{'TRACKNUM'}");
                
                # This loop is just for debugging purpose...
		for my $attribute (Slim::Schema::Contributor->contributorRoles,
			qw(TITLE ALBUM YEAR GENRE REPLAYGAIN_TRACK_PEAK REPLAYGAIN_TRACK_GAIN)) {

			if (exists $track->{$attribute}) {

				main::DEBUGLOG && $log->debug("    $attribute: $track->{$attribute}");
			}
		}

		# Merge in file level attributes
                # Removed in order to consider all the attributes at Album level.
                #
                # for my $attribute (qw(CONTENT_TYPE ALBUMARTIST ARTIST ALBUM YEAR GENRE DISC DISCC COMMENT 
		#	                  REPLAYGAIN_ALBUM_GAIN REPLAYGAIN_ALBUM_PEAK ARTISTSORT ALBUMARTISTSORT ALBUMSORT COMPILATION))
                for my $attribute (keys %$cuesheet){
            
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

        #dump $tracks;
	return $tracks;
}
sub _addCommand{
        my $cuesheet        = shift;
	my $tracks          = shift;
        my $inAlbum         = shift;
        my $currtrack       = shift;
        my $command         = shift;
        my $value           = shift;
        
        if ($inAlbum and !defined $cuesheet->{$command}){
            $cuesheet->{$command} = $value;
        } elsif (defined $currtrack and !defined $tracks->{$currtrack}->{$command}){
            $tracks->{$currtrack}->{$command} = $value;
        }
        return ($cuesheet,$tracks);
}
sub _isRemCommandAccepted {
        
        my $remCommand  = shift;

        for my $attribute (@refusedRemCommands){

            if ($remCommand eq $attribute){
              
                return 0;
            }
        }
        # we don't want to accept from a REM a command to be ignored.
        if (_isCommandToIgnore($remCommand)){
        
            return 0;
        }
        return 1;
}
sub _isCommandAccepted{
        my $command  = shift;
    
        if (!_isStandardCommand($command)){
        
            return 0;
        }
        if (_isCommandToIgnore($command)){
        
            return 0;
        }
        return 1;
}
sub _isStandardCommand{
        my $command  = shift;

        for my $attribute (@standardCueCommands){

            if ($command eq $attribute){
                return 1;
            }
        }
        return 0;
}
sub _isCommandToIgnore{
        my $command  = shift;

        for my $attribute (@refusedCueCommands){

            if ($command eq $attribute){
            
                return 1;
            }
        }
        return 0;
}
sub _getCommandFromLine{
        my $line  = shift;
        
        if ($line =~ /^\s*(\S+)\s+(.*)/i){

            return ($1,$2);
        }
        return (undef,undef);

}
sub _getRemCommandFromLine{
        my $line  = shift;
        if ($line =~ /^\"(.*)\"/i){ #"

            return (undef,$1);

        }elsif ($line =~ /^\s*(\S+)\s+(.*)/i){

            return ($1,$2);
        }
        return (undef,undef);

}
sub _removeQuotes{
        my $line  = shift;

        if ($line =~ /^\"(.*)\"/i){ #"
            
            return ($1);
        }
        return $line;
}
sub _validateBoolean{
        my $value  = shift;
        
        if (!defined $value){return 0;}
        if (uc($value) =~ qw(1|YES|Y)){return 1;}
        return 0;
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
