package Audio::APE;

use Audio::APETags;

use strict;
use vars qw($VERSION);

$VERSION = '0.01';

# First four bytes of stream are always fLaC
use constant MACHEADERFLAG => 'MAC';
use constant ID3HEADERFLAG => 'ID3';
use constant APEHEADERFLAG => 'APETAGEX';

#	Flags for format version <=3.97
#	MONKEY_FLAG_8_BIT          = 1;  // Audio 8-bit
#	MONKEY_FLAG_CRC            = 2;  // New CRC32 error detection
#	MONKEY_FLAG_PEAK_LEVEL     = 4;  // Peak level stored
#	MONKEY_FLAG_24_BIT         = 8;  // Audio 24-bit
#	MONKEY_FLAG_SEEK_ELEMENTS  = 16; // Number of seek elements stored
#	MONKEY_FLAG_WAV_NOT_STORED = 32; // WAV header not stored
my %flags = (
	MONKEY_FLAG_8_BIT		=> 15,
	MONKEY_FLAG_CRC			=> 14,
	MONKEY_FLAG_PEAK_LEVEL		=> 13,
	MONKEY_FLAG_24_BIT		=> 12,
	MONKEY_FLAG_SEEK_ELEMENTS	=> 11,
	MONKEY_FLAG_WAV_NOT_STORED	=> 10,
);

sub new {
	my $class = shift;
	my $file  = shift;
	my $errflag = 0;
	my $tmp;

	my $self  = {};

	bless $self, $class;

	# open up the file
	open(FILE, $file) or do {
		warn "File $file does not exist or cannot be read.";
		return $self;
	};

	# make sure dos-type systems can handle it...
	binmode FILE;

	$self->{'fileSize'}   = -s $file;
	$self->{'filename'}   = $file;
	$self->{'fileHandle'} = \*FILE;

	# Initialize MPC analysis
	$errflag = $self->_init();
	if ($errflag < 0) {
		warn "File $self->{'filename'} does not appear to be a Musepack file!";
		close FILE;
		undef $self->{'fileHandle'};
		return $self;
	};

	# Grab the information from the MPC headers
	$errflag = $self->_getAudioInfo();
	if ($errflag < 0) {
		warn "Unable to read MPC information from file!";
		close FILE;
		undef $self->{'fileHandle'};
		return $self;
	};

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
	return $self unless $key;

	# otherwise, return the value for the given key
	return $self->{$key};
}

sub tags {
	my $self = shift;
	my $key  = shift;

	# if the user did not supply a key, return a hashref
	return $self->{'tags'} unless $key;

	# otherwise, return the value for the given key
	return $self->{'tags'}->{$key};
}


# "private" methods
sub _init {
	my $self = shift;

	my $fh	 = $self->{'fileHandle'};

	# check the header to make sure this is actually a MPC file
	my $byteCount = $self->_checkHeader() || 0;

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
	my $id3size = '';

	# stores how far into the file we've read,
	# so later reads into the file can skip right
	# past all of the header stuff
	my $byteCount = 0;

	# There are two possible variations here.
	# 1.  There's an ID3V2 tag present at the beginning of the file
	# 2.  There's an APE tag present at the beginning of the file
	#     (deprecated, but still possible)
	# For each type of tag, check for existence and then skip it before
	# looking for the MPC header

	# First, check for ID3V2
	read ($fh, my $buffer, 3) or return -1;

	if ($buffer eq ID3HEADERFLAG) {
		$self->{'ID3V2Tag'}=1;

		# How big is the ID3 header?
		# Skip the next two bytes
		read($fh, $buffer, 2) or return -1;

		# The size of the ID3 tag is a 'synchsafe' 4-byte uint
		# Read the next 4 bytes one at a time, unpack each one B7,
		# and concatenate.  When complete, do a bin2dec to determine size
		for (my $c=0; $c<4; $c++) {
			read ($fh, $buffer, 1) or return -1;
			$id3size .= substr(unpack ("B8", $buffer), 1);
		}

		seek $fh, _bin2dec($id3size) + 10, 0;
	} else {
		# set the pointer back to the original location
		seek $fh, -3, 1;
	}

	# Next, check for APE tag
	read ($fh, $buffer, 8) or return -1;

	if ($buffer eq APEHEADERFLAG) {

		read ($fh, $buffer, 24) or return -1;
		
		# Skip the ape tag structure
		seek $fh, unpack ("L",substr($buffer, 4, 4)), 1;
	} else {
		# set the pointer back to original location
		seek $fh, -8, 1;
	}
	
	# Finally, we should be at the location of the musepack header.
	read ($fh, $buffer, 3) or return -1;
	
	if ($buffer ne MACHEADERFLAG) {
		return -2;
	}

	$byteCount = tell $fh;

	# at this point, we assume the bitstream is valid
	return $byteCount;
}

sub _getAudioInfo {
	my $self = shift;

	my $fh   = $self->{'fileHandle'};

	my %profileNames = (
		1000 => 'Fast (poor)',
		2000 => 'Normal (good)',
		3000 => 'High (very good)',
		4000 => 'Extra high (best)',
		5000 => 'Insane',
		6000 => 'BrainDead',
	);

	my @StereoMode = qw(unknown Mono Stereo);
	my @samplFreq  = qw(44100 48000 37800 32000);
	
	my $buffer;
	my $compressionID;
	my $totalFrames;
	my $finalFrame;
	
	# Seek to beginning of header information
	seek $fh, $self->{'startHeaderInfo'}+1, 0;

	# Start parsing the bytes
	read $fh, $buffer, 4;
	$buffer = _getWord($buffer);
	$self->{'streamVersion'} = _bin2dec(substr($buffer,16,16));

	if ($self->{'streamVersion'} < 3980) {
		$compressionID = _bin2dec(substr($buffer,0,16));
		return -1 unless exists $profileNames{$compressionID};
		
		read $fh, $buffer, 4;
		$buffer = _getWord($buffer);
		$self->{'Flags'} = _parseFlags(substr($buffer,16,16));
		$self->{'Channels'} = $StereoMode[_bin2dec(substr($buffer,0,16))];
	
		read $fh, $buffer, 4;
		$self->{'SampleRate'} = _bin2dec(_getWord($buffer));
		return -1 unless $self->{'SampleRate'};
		
		read $fh, $buffer, 4;
		#HeaderSize
		
		read $fh, $buffer, 4;
		# TerminatingDataBytes
		
		read $fh, $buffer, 4;
		$totalFrames = _bin2dec(_getWord($buffer));
		
		read $fh, $buffer, 4;
		$finalFrame = _bin2dec(_getWord($buffer));
		$self->{'BlocksPerFrame'} = $self->{'streamVersion'} >= 3950 ? 73728 * 4 : 73728;
	} else { # Newer formats for 3.98 and higher
		read $fh, $buffer, 4;
		$self->{'DescriptorBytes'} = _bin2dec(_getWord($buffer));

		#read $fh, $buffer, 4;
		#HeaderBytes

		#read $fh, $buffer, 4;
		#SeekTableBytes'

		#read $fh, $buffer, 4;
		#HeaderDataBytes'

		#read $fh, $buffer, 4;
		#APEFrameDataBytes'

		#read $fh, $buffer, 4;
		#APEFrameDataBytesHigh

		#read $fh, $buffer, 4;
		# TerminatingDataBytes

		#read $fh, $buffer, 16;
		# MD5 data
		# end of Descriptor
		
		
		# Begin at Header block
		seek $fh, $self->{'DescriptorBytes'}, 0;
		read $fh, $buffer, 4;
		$buffer = _getWord($buffer);
		$compressionID = _bin2dec(substr($buffer,16,16));
		return -1 unless exists $profileNames{$compressionID};
		$self->{'Flags'} = substr($buffer,0,16);

		read $fh, $buffer, 4;
		$self->{'BlocksPerFrame'} = _bin2dec(_getWord($buffer));

		read $fh, $buffer, 4;
		$finalFrame = _bin2dec(_getWord($buffer));

		read $fh, $buffer, 4;
		$totalFrames = _bin2dec(_getWord($buffer));

		read $fh, $buffer, 4;
		$buffer = _getWord($buffer);
		$self->{'Bits'} = _bin2dec(substr($buffer,16,16));
		$self->{'Channels'} = $StereoMode[_bin2dec(substr($buffer,0,16))];

		read $fh, $buffer, 4;
		$self->{'SampleRate'} = _bin2dec(_getWord($buffer));
		return -1 unless $self->{'SampleRate'};
	}

	# Calculate other useful file info
	$self->{'TotalSamples'}   = $self->{'BlocksPerFrame'} * ($totalFrames-1) + $finalFrame;
	$self->{'duration'}       = $self->{'TotalSamples'}/$self->{'SampleRate'};
	$self->{'compression'}    = $profileNames{$compressionID};
	$self->{'streamVersion'} /= 1000;
	$self->{'bitRate'}        = 8 * ($self->{'fileSize'} - $self->{'startHeaderInfo'}) / $self->{'duration'};

	return 0;
}

sub _parseFlags {
	my $inWord = shift;
	my %flagbits;
	
	foreach my $bit (keys %flags) {
		$flagbits{$bit} = substr($inWord,$flags{$bit},1);
	}
	
	return \%flagbits;
}

sub _getWord {
	my $inWord = shift;

	# Read in four bytes in reverse order, convert to binary
	my $outWord = '';

	for (my $c = 0; $c < 4; $c++) {
		$outWord .= unpack "B8", substr($inWord, 3-$c, 1);
	}
	
	return $outWord;
}

sub _bin2dec {
	# Freely swiped from Perl Cookbook p. 48 (May 1999)
	return unpack ('N', pack ('B32', substr(0 x 32 . shift, -32)));
}

1;

__END__

=head1 NAME

Audio::APE - An object-oriented interface to Monkey's Audio file information
and APE tag fields, implemented entirely in Perl.

=head1 SYNOPSIS

	use Audio::APE;
	my $mac = Audio::APE->new("song.ape");

	foreach (keys %$mac) {
		print "$_: $mac->{$_}\n";
	}

	my $macTags = $mac->tags();

	foreach (keys %$macTags) {
		print "$_: $macTags->{$_}\n";
	}

=head1 DESCRIPTION

This module returns a hash containing basic information about a Monkey's Audio
file, as well as tag information contained in the Monkey's Audio file's APE tags.
See Audio::APETags for more information about the tags.

The information returned by Audio::APE is keyed (for different MAC versions) by:

Version 3.97 or earlier:
Flags => {
			MONKEY_FLAG_8_BIT
			MONKEY_FLAG_WAV_NOT_STORED
			MONKEY_FLAG_24_BIT
			MONKEY_FLAG_SEEK_ELEMENTS
			MONKEY_FLAG_PEAK_LEVEL
			MONKEY_FLAG_CRC
		},
	SampleRate			: sample rate of uncompressed data in Hz (usually 44100)
	startHeaderInfo		: offset for header info
	compression			: compression scheme (string)
	Channels			: Mono or Stereo
	streamVersion		: Monkey's Audio version used for compression
	TotalSamples		: calculated total samples in file
	bitRate				: bitrate in bps
	duration			: duration of track in seconds
	fileSize			: filesize in bytes
	filename			: filename with path
	BlocksPerFrame		: number of blocks in a frame (usually 73728)

Version 3.98+ adds the following:
	Flags				: reserved for later (not the same as 3.97)
	DescriptorBytes		: Size of v3.98+ Descriptor block
	Bits				: bits per sample (usually 16)

=head1 CONSTRUCTORS

=head2 C<new ($filename)>

Opens a Monkey's Audio file, ensuring that it exists and is actually an
Monkey's Audio stream, then loads the information and comment fields.

=head1 INSTANCE METHODS

=head2 C<tags ([$key])>

Returns a hashref containing tag keys and values of the Monkey's Audio file from
the file's APE tags.

The optional parameter, key, allows you to retrieve a single value from
the tag hash.  Returns C<undef> if the key is not found.

=head1 SEE ALSO

L<http://www.monkeysaudio.com/>

=head1 AUTHOR

Kevin Deane-Freeman, E<lt>kevindf at shaw dot caE<gt>, based on other work by
Erik Reckase, E<lt>cerebusjam at hotmail dot comE<gt>, and
Dan Sully, E<lt>daniel@cpan.orgE<gt>

=head1 COPYRIGHT

Copyright (c) 2004, Kevin Deane-Freeman.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.2 or,
at your option, any later version of Perl 5 you may have available.

=cut



