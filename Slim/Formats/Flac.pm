package Slim::Formats::Flac;


###############################################################################
# FILE: Slim::Formats::Flac.pm
#
# DESCRIPTION:
#   Extract Flac tag information and store in a hash for easy retrieval.
#
# NOTES:
#   This code has only been tested on Linux.  I would like to change this
#   to make calls directly to the vorbis libraries.
###############################################################################
use strict;

# Global vars
use vars qw(
	@ISA @EXPORT @EXPORT_OK %EXPORT_TAGS $VERSION $REVISION $AUTOLOAD
);

@ISA = 'Exporter';
@EXPORT = qw(
	get_flactag get_flacinfo
);

# Things that can be exported explicitly
@EXPORT_OK = qw(get_flactag get_flacinfo);

%EXPORT_TAGS = (
	all	=> [@EXPORT, @EXPORT_OK]
);

# Given a file, return a hash of name value pairs,
# where each name is a tag name.
sub get_flactag
{
   # Get the pathname to the file
   my $file = shift || "";

   # This hash will map the keys in the tag to their values.
   my $tag = {};

   # Make sure the file exists.
#   return undef unless -s $file;

	# Path to the ogginfo command.
	my $flacinfo_cmd = Slim::Utils::Misc::findbin("metaflac");
	if ($flacinfo_cmd) {
	   # Run the 'metaflac' command on the file to extract the tag.
	   my @output = `$flacinfo_cmd --list \"$file\"`;
	
	   # If the command returns non-zero, metaflac failed.
	   # This is actually not true.  Need to verify what the ogginfo return
	   # codes are.
	#   if ($? != 0)
	#   {
	#      return undef;
	#   }
	
	   # Foreach line of output, try to match a tag, and extract
	   # the name and value.
	   my $sampleRate;
	   my $nSamples;
	   foreach (@output)
	   {
	       if (/ARTIST=([^\n]*)\n/i)
	       {$tag->{'ARTIST'} =  $1; }

	       if (/ALBUM=([^\n]*)\n/i)
	       {$tag->{'ALBUM'} =  $1;}

	       if (/TITLE=([^\n]*)\n/i)
	       {$tag->{'TITLE'} =  $1;}

	       if (/TRACKNUMBER=([^\n]*)\n/i)
	       {$tag->{'TRACKNUM'} =  $1;}

	       if (/DATE=([^\n]*)\n/i)
	       {$tag->{'YEAR'} =  $1;}

	       if (/GENRE=([^\n]*)\n/i)
	       {$tag->{'GENRE'} =  $1;}

	       $tag->{'SIZE'} =  -s $file;
	       $tag->{'FS'}   = -s $file;;
	       $tag->{'CT'}   = "flac";

	       # Compute number of seconds from sample rate and num samples
	       if (/sample_rate: (\d*) Hz/i)
	       { 
		   $sampleRate = $1; 
		   $tag->{'RATE'} = $sampleRate;
	       }

	       if (/total samples: (\d*)/i)
	       { $nSamples = $1; }

	       if (defined($nSamples) && defined($sampleRate))
	       { $tag->{'SECS'} = $nSamples / $sampleRate; }
	       # Set this so to non-zero so it will play.
	       else
	       { $tag->{'SECS'} = 1; }
		   
	       if (/channels: (\*d)/i)
	       { $tag->{'CHANNELS'} = $1; }
	   }
       }
   return $tag;
}


sub get_flacinfo
{
# Return relavant info for Flac

#
#Returns hash reference containing file information for MP3 file.
#This data cannot be changed.  Returned data:
#
#        VERSION         MPEG audio version (1, 2, 2.5)
#        LAYER           MPEG layer description (1, 2, 3)
#        STEREO          boolean for audio is in stereo
#
#        VBR             boolean for variable bitrate
#        BITRATE         bitrate in kbps (average for VBR files)
#        FREQUENCY       frequency in kHz
#        SIZE            bytes in audio stream
#
#        SECS            total seconds
#        MM              minutes
#        SS              leftover seconds
#        MS              leftover milliseconds
#        TIME            time in MM:SS
#
#        COPYRIGHT       boolean for audio is copyrighted
#        PADDING         boolean for MP3 frames are padded
#        MODE            channel mode (0 = stereo, 1 = joint stereo,
#                        2 = dual channel, 3 = single channel)
#        FRAMES          approximate number of frames
#        FRAME_LENGTH    approximate length of a frame
#        VBR_SCALE       VBR scale from VBR header


   return undef;
}

1;
