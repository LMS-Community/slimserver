package Audio::FLAC::Header;

# $Id$

use strict;
use vars qw($VERSION $HAVE_XS);
use File::Basename;

$VERSION = '1.4';

# First four bytes of stream are always fLaC
use constant FLACHEADERFLAG => 'fLaC';
use constant ID3HEADERFLAG  => 'ID3';

# Masks for METADATA_BLOCK_HEADER
use constant LASTBLOCKFLAG => 0x80000000;
use constant BLOCKTYPEFLAG => 0x7F000000;
use constant BLOCKLENFLAG  => 0x00FFFFFF;

# Enumerated Block Types
use constant BT_STREAMINFO     => 0;
use constant BT_PADDING        => 1;
use constant BT_APPLICATION    => 2;
use constant BT_SEEKTABLE      => 3;
use constant BT_VORBIS_COMMENT => 4;
use constant BT_CUESHEET       => 5;

XS_BOOT: {
        # If I inherit DynaLoader then I inherit AutoLoader
	require DynaLoader;

	# DynaLoader calls dl_load_flags as a static method.
	*dl_load_flags = DynaLoader->can('dl_load_flags');

	$HAVE_XS = eval {

		do {__PACKAGE__->can('bootstrap') || \&DynaLoader::bootstrap}->(__PACKAGE__, $VERSION);

		return 1;

	};

	# Try to use the faster code first.
	*new = $HAVE_XS ? \&new_XS : \&new_PP;
}

sub new_PP {
	my $class = shift;
	my $file  = shift;
	my $writeHack = shift;
	my $errflag = 0;

	my $self  = {};

	bless $self, $class;

	# open up the file
	open(FILE, $file) or do {
		warn "[$file] does not exist or cannot be read: $!";
		return undef;
	};

	# make sure dos-type systems can handle it...
	binmode FILE;

	$self->{'fileSize'}   = -s $file;
	$self->{'filename'}   = $file;
	$self->{'fileHandle'} = \*FILE;

	# Initialize FLAC analysis
	$errflag = $self->_init();
	if ($errflag < 0) {
		warn "[$file] does not appear to be a FLAC file!";
		close FILE;
		undef $self->{'fileHandle'};
		return undef;
	};

	# Grab the metadata blocks from the FLAC file
	$errflag = $self->_getMetadataBlocks();
	if ($errflag < 0) {
		warn "[$file] Unable to read metadata from FLAC!";
		close FILE;
		undef $self->{'fileHandle'};
		return undef;
	};

	# This is because we don't write out tags in XS yet.
	unless ($writeHack) {

		# Parse streaminfo
		$errflag = $self->_parseStreaminfo();
		if ($errflag < 0) {
			warn "[$file] Can't find streaminfo metadata block!";
			close FILE;
			undef $self->{'fileHandle'};
			return undef;
		};

		# Parse vorbis tags
		$errflag = $self->_parseVorbisComments();
		if ($errflag < 0) {
			warn "[$file] Can't find/parse vorbis comment metadata block!";
			close FILE;
			undef $self->{'fileHandle'};
			return undef;
		};

		# Parse cuesheet
		$errflag = $self->_parseCueSheet();
		if ($errflag < 0) {
			warn "[$file] Problem parsing cuesheet metadata block!";
			close FILE;
			undef $self->{'fileHandle'};
			return undef;
		};

		# Parse seekpoint table
		$errflag = $self->_parseSeekTable();
		if ($errflag < 0) {
			warn "[$file] Problem parsing seekpoint table!";
			close FILE;
			undef $self->{'fileHandle'};
			return undef;
		};

		# Parse third-party application metadata block
		$errflag = $self->_parseAppBlock();
		if ($errflag < 0) {
			warn "[$file] Problem parsing application metadata block!";
			close FILE;
			undef $self->{'fileHandle'};
			return undef;
		};
	}

	close FILE;
	undef $self->{'fileHandle'};

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

sub cuesheet {
	my $self = shift;

	# if the cuesheet block exists, return it as an arrayref
	return $self->{'cuesheet'} if exists($self->{'cuesheet'});

	# otherwise, return an empty arrayref
	return [];
}

sub seektable {
	my $self = shift;

	# if the seekpoint table block exists, return it as an arrayref
	return $self->{'seektable'} if exists($self->{'seektable'});

	# otherwise, return an empty arrayref
	return [];
}

sub application {
	my $self = shift;
	my $appID = shift || "default";

	# if the application block exists, return it's content
	return $self->{'application'}->{$appID} if exists($self->{'application'}->{$appID});

	# otherwise, return nothing
	return undef;
}

sub write {
	my $self = shift;

	# XXX - this is a hack until I do metadata writing in XS
	# Very ugly, I know.
	if ($HAVE_XS) {

		# Make a copy of these - otherwise we'll refcnt++
		my %tags = %{$self->{'tags'}};
		my %info = %{$self->{'info'}};

		my $filename = $self->{'filename'};
		my $class    = ref($self);

		undef $self;

		$self = $class->new_PP($filename, 1);

		$self->{'tags'} = \%tags;
		$self->{'info'} = \%info;
	}

	my @tagString = ();
	my $numTags   = 0;

	my ($idxVorbis,$idxPadding);
	my $totalAvail = 0;
	my $metadataBlocks = FLACHEADERFLAG;
	my $tmpnum;

	# Make a list of the tags and lengths for packing into the vorbis metadata block
	foreach (keys %{$self->{'tags'}}) {

		unless (/^VENDOR$/) {
			push @tagString, $_ . "=" . $self->{'tags'}{$_};
			$numTags++;
		}
	}

	# Create the contents of the vorbis comment metablock
	my $vorbisComment = '';

	# First, vendor tag (must be first)
	_addStringToComment(\$vorbisComment, $self->{'tags'}->{'VENDOR'});

	# Next, number of tags
	$vorbisComment .= _packInt32($numTags);

	# Finally, each tag string (with length)
	foreach (@tagString) {
		_addStringToComment(\$vorbisComment, $_);
	}

	# Is there enough space for this new header?
	# Determine the length of the old comment block and the length of the padding available
	$idxVorbis  = $self->_findMetadataIndex(BT_VORBIS_COMMENT);
	$idxPadding = $self->_findMetadataIndex(BT_PADDING);

	if ($idxVorbis >= 0) {
		# Add the length of the block
		$totalAvail += $self->{'metadataBlocks'}[$idxVorbis]->{'blockSize'};
	} else {
		# Subtract 4 (min size of block when added)
		$totalAvail -= 4;
	}

	if ($idxPadding >= 0) {
		# Add the length of the block
		$totalAvail += $self->{'metadataBlocks'}[$idxPadding]->{'blockSize'};
	} else {
		# Subtract 4 (min size of block when added)
		$totalAvail -= 4;
	}

	# Check for not enough space to write tag without
	# re-writing entire file (not within scope)
	if ($totalAvail - length($vorbisComment) < 0) {
		warn "Unable to write Vorbis tags - not enough header space!";
		return -1;
	}

	# Modify the metadata blocks to reflect new header sizes

	# Is there a Vorbis metadata block?
	if ($idxVorbis < 0) {
		# no vorbis block, so add one
		_addNewMetadataBlock($self, BT_VORBIS_COMMENT, $vorbisComment);
	} else {
		# update the vorbis block
		_updateMetadataBlock($self, $idxVorbis       , $vorbisComment);
	}

	# Is there a Padding block?
	# Change the padding to reflect the new vorbis comment size
	if ($idxPadding < 0) {
		# no padding block
		_addNewMetadataBlock($self, BT_PADDING , "\0" x ($totalAvail - length($vorbisComment)));
	} else {
		# update the padding block
		_updateMetadataBlock($self, $idxPadding, "\0" x ($totalAvail - length($vorbisComment)));
	}

	# Create the metadata block structure for the FLAC file
	foreach (@{$self->{'metadataBlocks'}}) {
		$tmpnum          = $_->{'lastBlockFlag'} << 31;
		$tmpnum         |= $_->{'blockType'}     << 24;
		$tmpnum         |= $_->{'blockSize'};
		$metadataBlocks .= pack "N", $tmpnum;
		$metadataBlocks .= $_->{'contents'};
	}

	# open FLAC file and write new metadata blocks
	open FLACFILE, "+<$self->{'filename'}" or return -1;
	binmode FLACFILE;

	# overwrite the existing metadata blocks
	print FLACFILE $metadataBlocks or return -1;

	close FLACFILE;

	return 0;
}

# private methods to this class
sub _init {
	my $self = shift;

	my $fh	 = $self->{'fileHandle'};

	# check the header to make sure this is actually a FLAC file
	my $byteCount = $self->_checkHeader() || 0;

	unless ($byteCount > 0) {
		# if it's not, we can't do anything
		return -1;
	}

	$self->{'startMetadataBlocks'} = $byteCount;

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

	# check that the first four bytes are 'fLaC'
	read($fh, my $buffer, 4) or return -1;

	if (substr($buffer,0,3) eq ID3HEADERFLAG) {

		$self->{'ID3V2Tag'} = 1;

		# How big is the ID3 header?
		# Skip the next two bytes - major & minor version number.
		read($fh, $buffer, 2) or return -1;

		# The size of the ID3 tag is a 'synchsafe' 4-byte uint
		# Read the next 4 bytes one at a time, unpack each one B7,
		# and concatenate.  When complete, do a bin2dec to determine size
		for (my $c = 0; $c < 4; $c++) {
			read ($fh, $buffer, 1) or return -1;
			$id3size .= substr(unpack ("B8", $buffer), 1);
		}

		seek $fh, _bin2dec($id3size) + 10, 0;
		read($fh, $buffer, 4) or return -1;
	}

	if ($buffer ne FLACHEADERFLAG) {
		warn "Unable to identify $self->{'filename'} as a FLAC bitstream!\n";
		return -2;
	}

	$byteCount = tell($fh);

	# at this point, we assume the bitstream is valid
	return $byteCount;
}

sub _getMetadataBlocks {
	my $self = shift;

	my $fh   = $self->{'fileHandle'};

	my $metadataBlockList = [];
	my $numBlocks         = 0;
	my $lastBlockFlag     = 0;
	my $buffer;

	# Loop through all of the metadata blocks
	while ($lastBlockFlag == 0) {

		# Read the next metadata_block_header
		read $fh, $buffer, 4 or return -1;

		my $metadataBlockHeader = unpack ('N', $buffer);

		# Break out the contents of the metadata_block_header
		my $metadataBlockType   = (BLOCKTYPEFLAG & $metadataBlockHeader)>>24;
		my $metadataBlockLength = (BLOCKLENFLAG  & $metadataBlockHeader);
		   $lastBlockFlag       = (LASTBLOCKFLAG & $metadataBlockHeader)>>31;

		# If the block size is zero go to the next block 
		next unless $metadataBlockLength;

		# Read the contents of the metadata_block
		read $fh, my $metadataBlockData, $metadataBlockLength or return -1;

		# Store the parts in the list
		$metadataBlockList->[$numBlocks++] = {
			'lastBlockFlag' => $lastBlockFlag,
			'blockType'     => $metadataBlockType,
			'blockSize'     => $metadataBlockLength,
			'contents'      => $metadataBlockData
		};
	}

	# Store the metadata blocks in the hash
	$self->{'metadataBlocks'} = $metadataBlockList;
	$self->{'startAudioData'} = tell $fh;

	return 0;
}

sub _parseStreaminfo {
	my $self = shift;
	my $info = {};
	my ($totalSeconds,$trackMinutes,$trackSeconds,$trackFrames,$bitRate);

	my $idx = $self->_findMetadataIndex(BT_STREAMINFO);

	if ($idx < 0) {
		return -1;
	}

	# Convert to binary string, since there's some unfriendly lengths ahead
	my $metaBinString = unpack('B144', $self->{'metadataBlocks'}[$idx]->{'contents'});

	$info->{'MINIMUMBLOCKSIZE'} = _bin2dec(substr($metaBinString, 0,16));
	$info->{'MAXIMUMBLOCKSIZE'} = _bin2dec(substr($metaBinString,16,32));
	$info->{'MINIMUMFRAMESIZE'} = _bin2dec(substr($metaBinString,32,24));
	$info->{'MAXIMUMFRAMESIZE'} = _bin2dec(substr($metaBinString,56,24));

	$info->{'SAMPLERATE'}       = _bin2dec(substr($metaBinString,80,20));
	$info->{'NUMCHANNELS'}      = _bin2dec(substr($metaBinString,100,3)) + 1;
	$info->{'BITSPERSAMPLE'}    = _bin2dec(substr($metaBinString,103,5)) + 1;

	# Calculate total samples in two parts
	my $highBits = _bin2dec(substr($metaBinString,108,4));
	$info->{'TOTALSAMPLES'} = $highBits * 2 ** 32 + _bin2dec(substr($metaBinString,112,32));

	# Return the MD5 as a 32-character hexadecimal string
	$info->{'MD5CHECKSUM'} = unpack('H32',substr($self->{'metadataBlocks'}[$idx]->{'contents'},18,16));

	# Store in the data hash
	$self->{'info'} = $info;

	# Calculate the track times
	$totalSeconds = $info->{'TOTALSAMPLES'} / $info->{'SAMPLERATE'};

	if ($totalSeconds == 0) {
		warn "totalSeconds is 0 - we couldn't find either TOTALSAMPLES or SAMPLERATE!\n" .
		     "setting totalSeconds to 1 to avoid divide by zero error!\n";

		$totalSeconds = 1;
	}

	$self->{'trackTotalLengthSeconds'} = $totalSeconds;

	$self->{'trackLengthMinutes'} = int(int($totalSeconds) / 60);
	$self->{'trackLengthSeconds'} = int($totalSeconds) % 60;
	$self->{'trackLengthFrames'}  = ($totalSeconds - int($totalSeconds)) * 75;
	$self->{'bitRate'}            = 8 * ($self->{'fileSize'} - $self->{'startAudioData'}) / $totalSeconds;

	return 0;
}

sub _parseVorbisComments {
	my $self = shift;
	my $tags = {};
	my $rawTags = [];
	my $idx  = $self->_findMetadataIndex(BT_VORBIS_COMMENT);

	# continue parsing, even if we can't find the comment.
	return 0 if $idx < 0;

	# Parse out the tags from the metadata block
	my $tmpBlock         = $self->{'metadataBlocks'}[$idx]->{'contents'};

	# First tag in block is the Vendor String
	my $tagLen        = _grabInt32(\$tmpBlock);
	$tags->{'VENDOR'} = substr($tmpBlock,0,$tagLen);
	$tmpBlock         = substr($tmpBlock,$tagLen);

	# Now, how many additional tags are there?
	my $numTags       = _grabInt32(\$tmpBlock);

	for (my $tagi = 0; $tagi < $numTags; $tagi++) {

		# Read the tag string
		$tagLen    = _grabInt32(\$tmpBlock);
		my $tagStr = substr($tmpBlock,0,$tagLen);
		$tmpBlock  = substr($tmpBlock,$tagLen);

		# Save the raw tag
		push(@$rawTags, $tagStr);

		# Match the key and value
		if ($tagStr =~ /^(.*?)=(.*?)[\r\n]*$/s) {
			# Make the key uppercase
			my $tkey = $1;
			$tkey =~ tr/a-z/A-Z/;

			# Stick it in the tag hash - and handle multiple tags
			# of the same name.
			if (exists $tags->{$tkey} && ref($tags->{$tkey}) ne 'ARRAY') {

				my $oldValue = $tags->{$tkey};

				$tags->{$tkey} = [ $oldValue, $2 ];

			} elsif (ref($tags->{$tkey}) eq 'ARRAY') {

				push @{$tags->{$tkey}}, $2;

			} else {

				$tags->{$tkey} = $2;
			}
		}
	}

	$self->{'tags'} = $tags;
	$self->{'rawTags'} = $rawTags;

	return 0;
}

sub _parseCueSheet {
	my $self = shift;

	my $idx  = $self->_findMetadataIndex(BT_CUESHEET);

        # No cuesheet block found. 
        # Not really an error, but no need to continue.
	return 0 if $idx < 0;

	my $cuesheet = [];

	# Parse out the tags from the metadata block
	my $tmpBlock  = $self->{'metadataBlocks'}[$idx]->{'contents'};

	# First field in block is the Media Catalog Number
	my $catalog   = substr($tmpBlock,0,128);
	$catalog =~ s/\x00+.*$//gs; # trim nulls off of the end

	push (@$cuesheet, "CATALOG $catalog\n") if length($catalog) > 0;
	$tmpBlock     = substr($tmpBlock,128);

	# metaflac uses "dummy.wav" but we're going to use the actual filename
	# this will help external parsers that have to associate the resulting
	# cuesheet with this flac file.
	push (@$cuesheet, "FILE \"" . basename("$self->{'filename'}") ."\" FLAC\n");

	# Next field is the number of lead-in samples for CD-DA
	my $highbits  = unpack('N', substr($tmpBlock,0,4));
	my $leadin    = $highbits * 2 ** 32 + unpack('N', (substr($tmpBlock,4,4)));
	$tmpBlock     = substr($tmpBlock,8);

	# Flag to determine if this represents a CD
	my $bits      = unpack('B8', substr($tmpBlock, 0, 1));
	my $isCD      = substr($bits, 0, 1);

	# Some sanity checking related to the CD flag
	if ($isCD && length($catalog) != 13 && length($catalog) != 0) {
		warn "Invalid Catalog entry\n";
		return -1;
	}

	if (!$isCD && $leadin > 0) {
		warn "Lead-in detected for non-CD cue sheet.\n";
		return -1;
	}

	# The next few bits should be zero.
	my $reserved  = _bin2dec(substr($bits, 1, 7));
	$reserved     += unpack('B*', substr($tmpBlock, 1, 258));

	if ($reserved != 0) {
		warn "Either the cue sheet is corrupt, or it's a newer revision than I can parse\n";
		#return -1; # ?? may be harmless to continue ...
	}

	$tmpBlock     = substr($tmpBlock,259);

	# Number of tracks
	my $numTracks = _bin2dec(unpack('B8',substr($tmpBlock,0,1)));
	$tmpBlock     = substr($tmpBlock,1);

	if ($numTracks < 1 || ($isCD && $numTracks > 100)) {
		warn "Invalid number of tracks $numTracks\n";
		return -1;
	}

	# Parse individual tracks now
	my %seenTracknumber = ();
	my $leadout = 0;
	my $leadouttracknum = 0;

	for (my $i = 1; $i <= $numTracks; $i++) {

		$highbits    = unpack('N', substr($tmpBlock,0,4));

		my $trackOffset   = $highbits * 2 ** 32 + unpack('N', (substr($tmpBlock,4,4)));

		if ($isCD && $trackOffset % 588) {
			warn "Invalid track offset $trackOffset\n";
			return -1;
		}

		my $tracknum = _bin2dec(unpack('B8',substr($tmpBlock,8,1))) || do {

			warn "Invalid track numbered \"0\" detected\n";
			return -1;
		};

		if ($isCD && $tracknum > 99 && $tracknum != 170) {
			warn "Invalid track number for a CD $tracknum\n";
			return -1;
		}

		if (defined $seenTracknumber{$tracknum}) {
			warn "Invalid duplicate track number $tracknum\n";
			return -1;
		}

		$seenTracknumber{$tracknum} = 1;

		my $isrc = substr($tmpBlock,9,12);
		   $isrc =~ s/\x00+.*$//;

		if ((length($isrc) != 0) && (length($isrc) != 12)) {
			warn "Invalid ISRC code $isrc\n";
			return -1;
		}

		$bits           = unpack('B8', substr($tmpBlock, 21, 1));
		my $isAudio     = !substr($bits, 0, 1);
		my $preemphasis = substr($bits, 1, 1);

		# The next few bits should be zero.
		$reserved  = _bin2dec(substr($bits, 2, 6));
		$reserved     += unpack('B*', substr($tmpBlock, 22, 13));

		if ($reserved != 0) {
			warn "Either the cue sheet is corrupt, " .
			     "or it's a newer revision than I can parse\n";
			#return -1; # ?? may be harmless to continue ...
		}

		my $numIndexes = _bin2dec(unpack('B8',substr($tmpBlock,35,1)));		

		$tmpBlock = substr($tmpBlock,36);

		# If we're on the lead-out track, stop before pushing TRACK info
		if ($i == $numTracks)  {
			$leadout = $trackOffset;

			if ($isCD && $tracknum != 170) {
				warn "Incorrect lead-out track number $tracknum for CD\n";
				return -1;
			}

			$leadouttracknum = $tracknum;
			next;
		}

		# Add TRACK info to cuesheet
		my $trackline = sprintf("  TRACK %02d %s\n", $tracknum, $isAudio ? "AUDIO" : "DATA");

		push (@$cuesheet, $trackline);
		push (@$cuesheet, "    FLAGS PRE\n") if ($preemphasis);
		push (@$cuesheet, "    ISRC " . $isrc . "\n") if ($isrc);

		if ($numIndexes < 1 || ($isCD && $numIndexes > 100)) {
			warn "Invalid number of Indexes $numIndexes for track $tracknum\n";
			return -1;
		}

		# Itterate through the indexes for this track
		for (my $j = 0; $j < $numIndexes; $j++) {

			$highbits    = unpack('N', substr($tmpBlock,0,4));

			my $indexOffset   = $highbits * 2 ** 32 + unpack('N', (substr($tmpBlock,4,4)));

			if ($isCD && $indexOffset % 588) {
				warn "Invalid index offset $indexOffset\n";
				return -1;
			}

			my $indexnum = _bin2dec(unpack('B8',substr($tmpBlock,8,1)));
			#TODO: enforce sequential indexes

			$reserved  = 0;
			$reserved += unpack('B*', substr($tmpBlock, 9, 3));

			if ($reserved != 0) {
				warn "Either the cue sheet is corrupt, " .
				     "or it's a newer revision than I can parse\n";
				#return -1; # ?? may be harmless to continue ...
			}

			my $timeoffset = _samplesToTime(($trackOffset + $indexOffset), $self->{'info'}->{'SAMPLERATE'});

			return -1 unless defined ($timeoffset);

			my $indexline = sprintf ("    INDEX %02d %s\n", $indexnum, $timeoffset);

			push (@$cuesheet, $indexline);

			$tmpBlock = substr($tmpBlock,12);
		}
	}

	# Add final comments just like metaflac would
	push (@$cuesheet, "REM FLAC__lead-in " . $leadin . "\n");
	push (@$cuesheet, "REM FLAC__lead-out " . $leadouttracknum . " " . $leadout . "\n");

	$self->{'cuesheet'} = $cuesheet;

	return 0;
}

sub _parseSeekTable {
	my $self = shift;
	my $seektable = [];

	my $idx  = $self->_findMetadataIndex(BT_SEEKTABLE);

	# seekpoint tables are optional, so return 0 if we don't have one
	if ($idx < 0) {
		return 0;
	}

	#grab the seekpoint table
	my $tmpBlock = $self->{'metadataBlocks'}[$idx]->{'contents'};

	#parse out the seekpoints
	while (my $seekpoint = substr($tmpBlock, 0, 18)) {
		# Sample number of first sample in the target frame
		my $highbits = unpack('N', substr($seekpoint,0,4));
		my $sampleNumber = $highbits * 2 ** 32 + unpack('N', (substr($seekpoint,4,4)));

		# Detect placeholder seekpoint
		# since the table is sorted, a placeholder means were finished
		last if ($sampleNumber == (0xFFFFFFFF * 2 ** 32 + 0xFFFFFFFF));

		# Offset (in bytes) from the first byte of the first frame header 
		# to the first byte of the target frame's header.
		$highbits = unpack('N', substr($seekpoint,8,4));
		my $streamOffset = $highbits * 2 ** 32 + unpack('N', (substr($seekpoint,12,4)));

		# Number of samples in the target frame
		my $frameSamples = unpack('n', (substr($seekpoint,16,2)));

		# remove this point from the tmpBlock
		$tmpBlock = substr($tmpBlock, 18);

		# add this point to our copy of the table
		push (@$seektable, { "sampleNumber" => $sampleNumber, 
				     "streamOffset" => $streamOffset,
				     "frameSamples" => $frameSamples });
	}

	# make it official
	$self->{'seektable'} = $seektable;

	return 0;
}

sub _parseAppBlock {
	my $self = shift;

	# there may be multiple application blocks with different ids
	# so we need to loop through them all.
	my $idx = $self->_findMetadataIndex(BT_APPLICATION);
	while ($idx >= 0) {
		my $appContent = [];

		# Parse out the tags from the metadata block
		my $tmpBlock  = $self->{'metadataBlocks'}[$idx]->{'contents'};

		# Find the application id
		my $appID   = unpack('N', substr($tmpBlock,0,4));
	
		$self->{'application'}->{$appID} = substr($tmpBlock,4);
		$idx  = $self->_findMetadataIndex(BT_APPLICATION, ++$idx);
	}
	return 0;
}

# Take an offset as number of flac samples
# and return CD-DA style mm:ss:ff
sub _samplesToTime {
	my $samples    = shift;
	my $samplerate = shift;

	if ($samplerate == 0) {
		warn "Couldn't find SAMPLERATE for time calculation!\n";
		return;
	}

	my $totalSeconds = $samples / $samplerate;

	if ($totalSeconds == 0) {
		# handled specially to avoid division by zero errors
		return "00:00:00";		
	}

	my $trackMinutes  = int(int($totalSeconds) / 60);
	my $trackSeconds  = int($totalSeconds % 60);
	my $trackFrames   = ($totalSeconds - int($totalSeconds)) * 75;

	# Poor man's rounding. Needed to match the output of metaflac.
	$trackFrames = int($trackFrames + 0.5);
	
	my $formattedTime = sprintf("%02d:%02d:%02d", $trackMinutes, $trackSeconds, $trackFrames); 

	return $formattedTime;
}

sub _bin2dec {
	# Freely swiped from Perl Cookbook p. 48 (May 1999)
	return unpack ('N', pack ('B32', substr(0 x 32 . shift, -32)));
}

sub _grabInt32 {
	# Pulls a little-endian unsigned int from a string and returns the remainder
	my $data  = shift;
	my $value = unpack('V',substr($$data,0,4));
	$$data    = substr($$data,4);
	return $value;
}

sub _packInt32 {
	# Packs an integer into a little-endian 32-bit unsigned int
	return pack('V',shift)
}

sub _findMetadataIndex {
	my $self  = shift;
	my $htype = shift;
	my $idx   = shift || 0;

	my $found = 0;

	# Loop through the metadata_blocks until one of $htype is found
	while ($idx < @{$self->{'metadataBlocks'}}) {
		# Check the type to see if it's a $htype block
		if ($self->{'metadataBlocks'}[$idx]->{'blockType'} == $htype) {
			$found++;
			last;
		}

		$idx++;
	}

	# No streaminfo found.  Error.
	return -1 if $found == 0;
	return $idx;
}

sub _addStringToComment {
	my $self      = shift;
	my $addString = shift;

	$$self .= _packInt32(length($addString));
	$$self .= $addString;
}

sub _addNewMetadataBlock {
	my $self     = shift;
	my $htype    = shift;
	my $contents = shift;

	my $numBlocks = @{$self->{'metadataBlocks'}};

	$self->{'metadataBlocks'}->[$numBlocks-1]->{'lastBlockFlag'}= 0;

	# create a new block
	$self->{'metadataBlocks'}->[$numBlocks]->{'lastBlockFlag'}  = 1;
	$self->{'metadataBlocks'}->[$numBlocks]->{'blockType'}      = $htype;
	$self->{'metadataBlocks'}->[$numBlocks]->{'blockSize'}      = length($contents);
	$self->{'metadataBlocks'}->[$numBlocks]->{'contents'}       = $contents;
}

sub _updateMetadataBlock {
	my $self     = shift;
	my $blockIdx = shift;
	my $contents = shift;

	# Update the block
	$self->{'metadataBlocks'}->[$blockIdx]->{'blockSize'} = length($contents);
	$self->{'metadataBlocks'}->[$blockIdx]->{'contents'} = $contents;
}

1;

__END__

=head1 NAME

Audio::FLAC::Header - interface to FLAC header metadata.

=head1 SYNOPSIS

	use Audio::FLAC::Header;
	my $flac = Audio::FLAC::Header->new("song.flac");

	my $info = $flac->info();

	foreach (keys %$info) {
		print "$_: $info->{$_}\n";
	}

	my $tags = $flac->tags();

	foreach (keys %$tags) {
		print "$_: $tags->{$_}\n";
	}

=head1 DESCRIPTION

This module returns a hash containing basic information about a FLAC file,
a representation of the embedded cue sheet if one exists,  as well as tag 
information contained in the FLAC file's Vorbis tags.
There is no complete list of tag keys for Vorbis tags, as they can be
defined by the user; the basic set of tags used for FLAC files include:

	ALBUM
	ARTIST
	TITLE
	DATE
	GENRE
	TRACKNUMBER
	COMMENT

The information returned by Audio::FLAC::info is keyed by:

	MINIMUMBLOCKSIZE
	MAXIMUMBLOCKSIZE
	MINIMUMFRAMESIZE
	MAXIMUMFRAMESIZE
	TOTALSAMPLES
	SAMPLERATE
	NUMCHANNELS
	BITSPERSAMPLE
	MD5CHECKSUM

Information stored in the main hash that relates to the file itself or is
calculated from some of the information fields is keyed by:

	trackLengthMinutes      : minutes field of track length
	trackLengthSeconds      : seconds field of track length
	trackLengthFrames       : frames field of track length (base 75)
	trackTotalLengthSeconds : total length of track in fractional seconds
	bitRate                 : average bits per second of file
	fileSize                : file size, in bytes

=head1 CONSTRUCTORS

=head2 C<new ($filename)>

Opens a FLAC file, ensuring that it exists and is actually an
FLAC stream, then loads the information and comment fields.

=head1 INSTANCE METHODS

=head2 C<info ([$key])>

Returns a hashref containing information about the FLAC file from
the file's information header.

The optional parameter, key, allows you to retrieve a single value from
the info hash.  Returns C<undef> if the key is not found.

=head2 C<tags ([$key])>

Returns a hashref containing tag keys and values of the FLAC file from
the file's Vorbis Comment header.

The optional parameter, key, allows you to retrieve a single value from
the tag hash.  Returns C<undef> if the key is not found.

=head2 C<cuesheet ()>

Returns an arrayref which contains a textual representation of the
cuesheet metada block. Each element in the array corresponds to one
line in a .cue file. If there is no cuesheet block in this FLAC file
the array will be empty. The resulting cuesheet should match the
output of metaflac's --export-cuesheet-to option, with the exception
of the FILE line, which includes the actual file name instead of 
"dummy.wav".

=head2 C<write ()>

Writes the current contents of the tag hash to the FLAC file, given that
there's enough space in the header to do so.  If there's insufficient
space available (using pre-existing padding), the file will remain
unchanged, and the function will return a non-zero value.

=head1 SEE ALSO

L<http://flac.sourceforge.net/format.html>

=head1 AUTHORS

Erik Reckase, E<lt>cerebusjam at hotmail dot comE<gt>, with lots of help
from Dan Sully, E<lt>daniel@cpan.orgE<gt>

Dan Sully, E<lt>daniel@cpan.orgE<gt> for XS code.

=head1 COPYRIGHT

Pure perl code Copyright (c) 2003-2005, Erik Reckase.

XS code Copyright (c) 2004-2005, Dan Sully.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.2 or,
at your option, any later version of Perl 5 you may have available.

=cut
