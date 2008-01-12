package Slim::Formats::WavPack;

###############################################################################
# FILE: Slim::Formats::WavPack.pm
#
# DESCRIPTION:
#   Extract APE tag or ID3v1 information from a WavPack file and store in a hash
#   for easy retrieval. Also reads the metadata from the file - sample rate etc.
#   WavPack also supports embedded album art, this is read using getCoverArt
#
#   Copyright (c) 2007 Peter McQuillan, beatofthedrum AT gmail DOT com
#
###############################################################################

use strict;
use base qw(Slim::Formats);
use Audio::APETags;
use Fcntl qw(:seek);
use MP3::Info;
use Slim::Utils::Misc;
use Slim::Utils::Log;

# First four bytes of stream are always wvpk in version 4 WavPack files

use constant WVPHEADERFLAG => 'wvpk';
use constant APEHEADERFLAG => 'APETAGEX';

my $log = logger('formats.audio');

my %tagMapping = (
	'TRACK'	     => 'TRACKNUM',
	'DATE'       => 'YEAR',
	'DISCNUMBER' => 'DISC',
);

# Given a file, return a hash of name value pairs,
# where each name is a tag name.
sub getTag {
	my $class = shift;
	my $file  = shift || return {};

	my $wvp = _new($class,$file);

	my $tags = tags($wvp) || {};

	# Check that the WAvPack file has been processed

	if (!defined $wvp->{'sampleFreq'}) {
		return {};
	}

	# There should be a TITLE tag if the APE tags are to be trusted
	if (defined $tags->{'TITLE'}) {

		# map the existing tag names to the expected tag names
		while (my ($old,$new) = each %tagMapping) {
			if (exists $tags->{$old}) {
				$tags->{$new} = $tags->{$old};
				delete $tags->{$old};
			}
		}

	} else {

		if (exists $wvp->{'ID3V1Tag'} && Slim::Formats->loadTagFormatForType('mp3')) {
			# Get the ID3V1 tag on there
			$tags = MP3::Info::get_mp3tag($file, 2);
		}
	}

	# add more information to these tags
	# these are not tags, but calculated values from the streaminfo
	$tags->{'SIZE'}    = $wvp->{'fileSize'};
	$tags->{'SECS'}    = $wvp->{'trackTotalLengthSeconds'};
	$tags->{'SAMPLESIZE'} = $wvp->{'bits_sample'};

	if (defined $wvp->{'encodingMode'})
	{
		if($wvp->{'encodingMode'} == 1)
		{
			$tags->{'VBR_SCALE'} = 1;
		}
	}

	$tags->{'BITRATE'}  = $wvp->{'bitRate'};

	$tags->{'RATE'}     = $wvp->{'sampleFreq'};
	$tags->{'CHANNELS'} = $wvp->{'channels'};

	# taken from MP3::Info
	$tags->{'MM'}	    = int $tags->{'SECS'} / 60;
	$tags->{'SS'}	    = int $tags->{'SECS'} % 60;
	$tags->{'MS'}	    = (($tags->{'SECS'} - ($tags->{'MM'} * 60) - $tags->{'SS'}) * 1000);
	$tags->{'TIME'}	    = sprintf "%.2d:%.2d", @{$tags}{'MM', 'SS'};

	return $tags;
}

=head2 getCoverArt( $filename )

Return any cover art embedded in the WavPack files tags.

=cut

sub getCoverArt {
        my $class = shift;
        my $file  = shift;

	my ($tmp,$len,$pos,$mysubs);

        my $wvp = _new($class,$file);

        my $tags = tags($wvp) || {};

        if (defined $tags->{'COVER ART (FRONT)'}) {
		$tmp = $tags->{'COVER ART (FRONT)'};
		$len  = length($tmp);

		# First we have the name of the file

                $pos = index($tmp, "\0", 0);

		# Skip past the null character at end of filename
		$pos = $pos + 1;

		$len = $len - $pos;

                $mysubs = substr $tmp, $pos, $len;

		$tags->{'ARTWORK'} = $mysubs;
	}

        return $tags->{'ARTWORK'};
}


sub _new {
	my $class = shift;
	my $file  = shift;
	my $errflag = 0;
	my $tmp;

	my $self  = {};

	bless $self, $class;

	# open up the file
	open(FILE, $file) or do {
		$log->warn("File $file does not exist or cannot be read.");
		return $self;
	};

	# make sure dos-type systems can handle it...
	binmode FILE;

	$self->{'fileSize'}   = -s $file;
	$self->{'filename'}   = $file;
	$self->{'fileHandle'} = \*FILE;

	# Initialize WVP analysis
	$errflag = _init($self);
	if ($errflag < 0) {
		$log->warn("File $self->{'filename'} does not appear to be a WavPack file!");
		close FILE;
		undef $self->{'fileHandle'};
		return $self;
	};

	# Grab the information from the WVP headers if not version 4 WavPack file
	if(! $self->{'oldWavPack'})
	{
		$errflag = _getAudioInfo($self);
		if ($errflag < 0) {
			$log->warn("Unable to read WVP information from file!");
			close FILE;
			undef $self->{'fileHandle'};
			return $self;
		};
	}

	close FILE;
	undef $self->{'fileHandle'};

	$tmp = Audio::APETags->getTags($self->{'filename'});

	$self->{'tags'} = $tmp->{'tags'};


	return $self;
}

sub info {
	my $self = shift;
	my $key  = shift;

	# if the user did not supply a key, return a hashref
	return $self->{'info'} unless $key;

	# otherwise, return the value for the given key
	return $self->{'info'}->{$key};
}

sub tags {
	my $self = shift;
	my $key  = shift;

	# if the user did not supply a key, return a hashref
	return $self->{'tags'} unless $key;

	# otherwise, return the value for the given key
	return $self->{'tags'}->{$key};
}


sub _init {
	my $self = shift;

	my $fh	 = $self->{'fileHandle'};

	# check the header to make sure this is actually a WVP file
	my $byteCount = _checkHeader($self) || 0;

	unless ($byteCount > 0) {
		# if it's not, we can't do anything
		return -1;
	}

	$self->{'startHeaderInfo'} = $byteCount;

	return 0;
}

sub _checkHeader {
	my $self = shift;

	my $fh	 = $self->{'fileHandle'};

	# Let MP3::Info test for the existance of a ID3v1 Tag
	my $v1h = MP3::Info::_get_v1tag($fh);

	if($v1h) {
		$self->{'ID3v1Tag'} = 1;
	}


	seek($fh, 0, SEEK_SET);

	# Next, check for APE tag
	my $buffer = '';
	read ($fh, $buffer, 8) or return -1;

	if ($buffer eq APEHEADERFLAG) {

		read ($fh, $buffer, 24) or return -1;
		
		# Skip the ape tag structure
		seek $fh, unpack ("L",substr($buffer, 4, 4)), 1;
	} else {
		# set the pointer back to original location
		seek $fh, -8, 1;
	}

	# Finally, we should be at the location of the WavPack header.
	read ($fh, $buffer, 4) or return -1;

	if ($buffer ne WVPHEADERFLAG) {
		# If file does not start with wvpk there is a possibility that it is
		# still a WavPack file - one of the earlier versions of WavPack

		_getAudioInfoUsingWvunpack($self);
		if(! $self->{'oldWavPack'}) {
			return -2;
		}
	}

	# at this point, we assume the bitstream is valid
	return tell($fh);
}

sub _getAudioInfo {
	my $self = shift;

	my $fh   = $self->{'fileHandle'};

	my @samplFreq = (6000, 8000, 9600, 11025, 12000, 16000, 22050, 24000, 32000, 44100, 48000, 64000, 88200, 96000, 192000);

	my ($buffer,$earlyVer,$wvpHdrFlags,$totalSamples,$totalSeconds,$tmp,$bytesPerSample,$metatmp,$wpmdid,$read_buffer,$numread,$output_time,$input_size);

	# Seek to beginning of header information
	seek $fh, $self->{'startHeaderInfo'}, 0;

	# Start parsing the bytes

	# Next 4 bytes are the block size
	$numread = read $fh, $buffer, 4;

	if($numread != 4)
	{
		return -1;
	}

	# We do certain checks on the block size to ensure this is a WavPack file

	my @sizechars = split '', $buffer;

	$tmp = unpack "C", $sizechars[2];

	if($tmp > 15)
	{
		return -1;
	}

	$tmp = unpack "C", $sizechars[3];

	if($tmp != 0)
	{
		return -1;
	}

	# Next 2 bytes are the version of WavPack used to encode the file

	$numread = read $fh, $buffer, 2;

	if($numread != 2)
	{
		return -1;
	}

	# Check that this is a valid WavPack header (we check the version used to encode this file)

	my @chars = split '', $buffer;

	$tmp = unpack "C", $chars[1];

	if($tmp != 4)
	{
		return -1;
	}

	# Next 2 bytes are the track number and index number

	$numread = read $fh, $buffer, 2;

	if($numread != 2)
	{
		return -1;
	}

	# Next 4 bytes are the total samples in the WavPack file

	$numread = read $fh, $buffer, 4;

	if($numread != 4)
	{
		return -1;
	}

	$totalSamples =  unpack "L", $buffer;

	# Next 8 bytes are the block index and block samples

	$numread = read $fh, $buffer, 8;

	if($numread != 8)
	{
		return -1;
	}

	# Next 4 bytes are the WavPack header flags for the WavPack file

	$numread = read $fh, $buffer, 4;

	if($numread != 4)
	{
		return -1;
	}

	$wvpHdrFlags =  unpack "L", $buffer;

	# Final 4 bytes are the CRC checksum for the block

	$numread = read $fh, $buffer, 4;

	if($numread != 4)
	{
		return -1;
	}

	# Now we go through the header to get extra information

	($tmp,$wpmdid,$read_buffer) = _read_metadata_buff($fh);

	while ($tmp == 1 && $wpmdid != 0xa)
	{
		# We are interested if wpmdid is 0x27, this corresponds to sample rate
		# This means that the file has a sample rate that is not one of the defaults

		if($wpmdid == 0x27)
		{
			$tmp = _read_sample_rate($read_buffer);
			$self->{'sampleFreq'} = $tmp;
		}

		# Another interesting wpmdid is 0xd, this corresponds to channel info

		if($wpmdid == 0xd)
		{
                        $tmp = _read_channel_info($read_buffer);
                        $self->{'channels'} = $tmp;
		}
	
		($tmp,$wpmdid,$read_buffer) = _read_metadata_buff($fh);
	}


	$bytesPerSample = ($wvpHdrFlags & 3) + 1;

	$self->{'bits_sample'} = 8 * $bytesPerSample;

	# If the sample rate is not defined in the metadata then it the file is using one
	# of the standard sample rates
	
	if(! $self->{'sampleFreq'})
	{
		$self->{'sampleFreq'} = @samplFreq[(($wvpHdrFlags & (0xf << 23)) >> 23)];

		if( $self->{'sampleFreq'} == 0)
		{
			$tmp = 44100;
			$self->{'sampleFreq'} = $tmp;
		}
	}

	# Calculate the average bitrate of the WavPack file

	if($totalSamples > 0 && $self->{'fileSize'} > 0)
	{
		$output_time = $totalSamples / $self->{'sampleFreq'};
		$input_size =  $self->{'fileSize'};

		if($output_time >= 1.0 && $input_size >= 1.0)
		{
			$tmp = $input_size * 8.0 / $output_time;
			$tmp = $tmp + 500.0;
			$self->{'bitRate'} = $tmp;
		}
	}

	# Calculate if file is lossless or lossy
	# Determines VBR or CBR for bitrate. We assume file is lossless unless proved otherwise

	# 0 lossy, 1 is lossless

	$self->{'encodingMode'} = 1;
	if( ($wvpHdrFlags & 8) > 0)
	{
		$self->{'encodingMode'} = 0;
	}
		
	$tmp = $totalSamples / $self->{'sampleFreq'};

	$self->{'trackTotalLengthSeconds'} = $tmp;

	$self->{'trackLengthMinutes'} = $tmp / 60;

	# If we have not already read the number of channels from the header, then we calculate the 
	# number of channels. Simple rule, if file is mono then only has one channel, otherwise we 
	# assume it has 2 channels (otherwise the channel info metadata would be set).

	if(! $self->{'channels'})
	{
		$tmp = $wvpHdrFlags & 4;
		if( $tmp > 0 )
		{
			$self->{'channels'} = 1;
		}
		else
		{
			$self->{'channels'} = 2;
		}
	}

	return 0;
}

sub _read_sample_rate
{
	my $read_buffer = shift;
	
	my ($sample_rate, $val0,$val1,$val2);

	my @chars = split '', $read_buffer;

	$val0= unpack "C", $chars[0];
	$val1= unpack "C", $chars[1];
	$val2= unpack "C", $chars[2];

	$sample_rate = $val0;
	$sample_rate |= (($val1 & 0xff) << 8);
	$sample_rate |= (($val2 & 0xff) << 16);

	return $sample_rate;

}

sub _read_channel_info
{
	my $read_buffer = shift;

	my ($channel_info);

	my @chars = split '', $read_buffer;

	$channel_info = unpack "C", $chars[0];

	return $channel_info;

}
sub _read_metadata_buff {
	my $fh = shift;

	my ($buffer,$numread,$wpmdid,$tchar,$bytelength,$bytes_to_read,$read_buffer);

	$numread = read $fh, $buffer, 1;

	if($numread != 1)
	{
		return (0, 0, " ");
	}

	$wpmdid = unpack "C", $buffer;

	$numread = read $fh, $buffer, 1;

	if($numread != 1)
	{
		return (0, 0, " ");
	}

	$tchar = unpack "C", $buffer;

	$bytelength = $tchar << 1;

	if (($wpmdid & 0x80) != 0)	# id large
	{
		$wpmdid &= ~0x80;
		$numread = read $fh, $buffer, 1;

		if($numread != 1)
		{
			return (0, 0, " ");
		}

		$tchar = unpack "C", $buffer;

		$bytelength = $bytelength + ($tchar << 9);

		$numread = read $fh, $buffer, 1;

		if($numread != 1)
		{
			return (0, 0, " ");
		}

		$tchar = unpack "C", $buffer;

		$bytelength = $bytelength + ($tchar << 17);
	}

	if (($wpmdid & 0x40) != 0)	# odd size
	{
		$wpmdid &= ~0x40;
		$bytelength--;
	}

	if ($bytelength == 0 || $wpmdid == 0xa )  # check if ID_WV_BITSTREAM)
	{
		return (1, 0xa, " ");
	}

	$bytes_to_read = $bytelength + ($bytelength & 1);

	$numread = read $fh, $read_buffer, $bytes_to_read;

	if($numread != $bytes_to_read)
	{
		return (0, 0, " ");
	}

	return (1, $wpmdid, $read_buffer);
}

# If the WavPack file is an old version, we use the command line application wvunpack to
# read the required metadata from the file

sub _getAudioInfoUsingWvunpack {
	my $self = shift;
	my $fh   = $self->{'fileHandle'};

	# locate the wvunpack binary

	my $wvunpack = Slim::Utils::Misc::findbin('wvunpack') || return undef;

	# run wvunpack with the -s option which prints all the details of the file without unpacking file

	my @output = `$wvunpack -q -s \"$self->{'filename'}\"`;
	return -1 unless @output;

	# Assume file is lossless unless find otherwise
	$self->{'encodingMode'} = 1;

	my $sourceString = "source:";
	my $channelString = "channels:";
	my $durationString = "duration:";
	my $avgBitrateString1 = "ave";
	my $avgBitrateString2 = "bitrate:";
	my $modalitiesString = "modalities:";
	my $hybridString = "hybrid";

	while (my $line = shift @output){
		chomp $line;


		# replace 2 or more spaces with one space
		$line=~s/ {2,}/ /g;

		my @words = split(/ /, $line);
		if ( $words[0] )
		{
			if($words[0] eq $modalitiesString)
			{
				if($words[1] eq $hybridString)
				{
					$self->{'encodingMode'} = 0;
				}
			}

			if($words[0] eq $avgBitrateString1 && $words[1] eq $avgBitrateString2 )
			{
				# wvunpack reports back in kbps format, we need it in bps format

				$self->{'bitRate'} = $words[2] * 1000;
			}

			if ($words[0] eq $sourceString)
			{
				$self->{'sampleFreq'} = $words[4];
				my $tmpBps = $words[1];

				my $bitString = "-bit";

				$tmpBps=~s/$bitString//g;
				if($tmpBps == 0)
				{
					# Should never happen, but cover divide by zero with this
					$tmpBps = 16;
				}

				$self->{'bits_sample'} = $tmpBps;

				$self->{'oldWavPack'} = 1;
			}

			if ($words[0] eq $channelString)
			{
				$self->{'channels'} = $words[1];
			}

			if ($words[0] eq $durationString)
			{
				my @numsections = split(/:/, $words[1]);
				my $durationCalc;

				$durationCalc = $numsections[0] * 60 * 60;
				$durationCalc = $durationCalc + ($numsections[1] * 60);
				$durationCalc = $durationCalc + $numsections[2];
				$self->{'trackTotalLengthSeconds'} = $durationCalc;
			}

		}

	}

	return 0;
}

1;
