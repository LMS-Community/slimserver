package Slim::Formats::Ogg;

# $Id: Ogg.pm,v 1.2 2003/07/24 23:14:04 dean Exp $

# Slim Server Copyright (c) 2001, 2002, 2003 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

###############################################################################
# FILE: Slim::Formats::Ogg.pm
#
# DESCRIPTION:
#   Extract Ogg tag information and store in a hash for easy retrieval.
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
	get_oggtag get_ogginfo
);

# Things that can be exported explicitly
@EXPORT_OK = qw(get_oggtag get_ogginfo);

%EXPORT_TAGS = (
	all	=> [@EXPORT, @EXPORT_OK]
);

# Given a file, return a hash of name value pairs,
# where each name is a tag name.
sub get_oggtag {
	# Get the pathname to the file
	my $file = shift || "";

	# This hash will map the keys in the tag to their values.
	my $tag = {};

	# Make sure the file exists.
	# return undef unless -s $file;

	# Path to the ogginfo command.
	my $ogginfo_cmd = Slim::Utils::Misc::findbin("ogginfo");
	if ($ogginfo_cmd) {
		# Run the 'ogginfo' command on the file to extract the tag.
		my @output = `$ogginfo_cmd \"$file\"`;
		
		# If the command returns non-zero, ogginfo failed.
		# This is actually not true.  Need to verify what the ogginfo return
		# codes are.
		#   if ($? != 0)
		#   {
		#      return undef;
		#   }
		
		# Foreach line of output, try to match a tag, and extract
		# the name and value.
		foreach (@output) {
			if (/^\s+([^=]+)=(.+)/) {
				# Make sure the key is uppercase.
				$tag->{uc($1)} = $2;
			} elsif (/Playback length: (\d+)m\:(\d+)s/) {
				# Get the length of the song in seconds.
				my $min = $1;
				my $sec = $2;
				$sec += $min * 60;
				$tag->{'SECS'} = $sec;
			} elsif (/^Rate: (\d+)/i) {
				$tag->{'RATE'} = $1;
			} elsif (/^Channels: (\d+)/i) {
				$tag->{'CHANNELS'} = $1;
			}
		}
		# Correct ogginfo tags
		if (exists $tag->{'DATE'}) {
			$tag->{'YEAR'} = $tag->{'DATE'};
			delete $tag->{'DATE'};
		}
		if (exists $tag->{'TRACKNUMBER'}) {
			$tag->{'TRACKNUM'} = $tag->{'TRACKNUMBER'};
			delete $tag->{'TRACKNUMBER'}
		}
	}
	# Add additional tag needed
	$tag->{'SIZE'} = -s $file;

	return $tag;
}


sub get_ogginfo
{
# Return relavant info for Ogg

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
