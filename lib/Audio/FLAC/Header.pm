package Audio::FLAC::Header;

# $Id$

use strict;
use File::Basename;

our $VERSION = '1.4';
our $HAVE_XS = 0;

# First four bytes of stream are always fLaC
my $FLACHEADERFLAG = 'fLaC';
my $ID3HEADERFLAG  = 'ID3';

# Masks for METADATA_BLOCK_HEADER
my $LASTBLOCKFLAG = 0x80000000;
my $BLOCKTYPEFLAG = 0x7F000000;
my $BLOCKLENFLAG  = 0x00FFFFFF;

# Enumerated Block Types
my $BT_STREAMINFO     = 0;
my $BT_PADDING        = 1;
my $BT_APPLICATION    = 2;
my $BT_SEEKTABLE      = 3;
my $BT_VORBIS_COMMENT = 4;
my $BT_CUESHEET       = 5;
my $BT_PICTURE        = 6;

my %BLOCK_TYPES = (
	$BT_STREAMINFO     => '_parseStreamInfo',
	$BT_APPLICATION    => '_parseAppBlock',
# The seektable isn't actually useful yet, and is a big performance hit. 
#	$BT_SEEKTABLE      => '_parseSeekTable',
	$BT_VORBIS_COMMENT => '_parseVorbisComments',
	$BT_CUESHEET       => '_parseCueSheet',
	$BT_PICTURE        => '_parsePicture',
);

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
	my ($class, $file, $writeHack) = @_;

	# open up the file
	open(my $fh, $file) or die "[$file] does not exist or cannot be read: $!";

	# make sure dos-type systems can handle it...
	binmode($fh);

	my $self  = {
		'fileSize' => -s $file,
		'filename' => $file,
	};

	bless $self, $class;

	# check the header to make sure this is actually a FLAC file
	my $byteCount = $self->_checkHeader($fh) || 0;

	if ($byteCount <= 0) {

		close($fh);
		die "[$file] does not appear to be a FLAC file!";
	}

	$self->{'startMetadataBlocks'} = $byteCount;

	# Grab the metadata blocks from the FLAC file
	if (!$self->_getMetadataBlocks($fh)) {

		close($fh);
		die "[$file] Unable to read metadata from FLAC!";
	};

	# This is because we don't write out tags in XS yet.
	if (!$writeHack) {

		for my $block (@{$self->{'metadataBlocks'}}) {

			my $method = $BLOCK_TYPES{ $block->{'blockType'} } || next;

			$self->$method($block);
		}
	}

	close($fh);

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

sub picture {
	my $self = shift;
	my $type = shift || 3; # front cover

	# if the picture block exists, return it's content
	return $self->{'picture'}->{$type} if exists($self->{'picture'}->{$type});

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
	my $metadataBlocks = $FLACHEADERFLAG;
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
	$idxVorbis  = $self->_findMetadataIndex($BT_VORBIS_COMMENT);
	$idxPadding = $self->_findMetadataIndex($BT_PADDING);

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
		_addNewMetadataBlock($self, $BT_VORBIS_COMMENT, $vorbisComment);
	} else {
		# update the vorbis block
		_updateMetadataBlock($self, $idxVorbis       , $vorbisComment);
	}

	# Is there a Padding block?
	# Change the padding to reflect the new vorbis comment size
	if ($idxPadding < 0) {
		# no padding block
		_addNewMetadataBlock($self, $BT_PADDING , "\0" x ($totalAvail - length($vorbisComment)));
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
sub _checkHeader {
	my ($self, $fh) = @_;

	# check that the first four bytes are 'fLaC'
	read($fh, my $buffer, 4) or return -1;

	if (substr($buffer,0,3) eq $ID3HEADERFLAG) {

		$self->{'ID3V2Tag'} = 1;

		my $id3size = '';

		# How big is the ID3 header?
		# Skip the next two bytes - major & minor version number.
		read($fh, $buffer, 2) or return -1;

		# The size of the ID3 tag is a 'synchsafe' 4-byte uint
		# Read the next 4 bytes one at a time, unpack each one B7,
		# and concatenate.  When complete, do a bin2dec to determine size
		for (my $c = 0; $c < 4; $c++) {
			read($fh, $buffer, 1) or return -1;
			$id3size .= substr(unpack ("B8", $buffer), 1);
		}

		seek $fh, _bin2dec($id3size) + 10, 0;
		read($fh, $buffer, 4) or return -1;
	}

	if ($buffer ne $FLACHEADERFLAG) {
		warn "Unable to identify $self->{'filename'} as a FLAC bitstream!\n";
		return -2;
	}

	# at this point, we assume the bitstream is valid
	return tell($fh);
}

sub _getMetadataBlocks {
	my ($self, $fh) = @_;

	my $metadataBlockList = [];
	my $numBlocks         = 0;
	my $lastBlockFlag     = 0;
	my $buffer;

	# Loop through all of the metadata blocks
	while ($lastBlockFlag == 0) {

		# Read the next metadata_block_header
		read($fh, $buffer, 4) or return 0;

		my $metadataBlockHeader = unpack('N', $buffer);

		# Break out the contents of the metadata_block_header
		my $metadataBlockType   = ($BLOCKTYPEFLAG & $metadataBlockHeader)>>24;
		my $metadataBlockLength = ($BLOCKLENFLAG  & $metadataBlockHeader);
		   $lastBlockFlag       = ($LASTBLOCKFLAG & $metadataBlockHeader)>>31;

		# If the block size is zero go to the next block 
		next unless $metadataBlockLength;

		# Read the contents of the metadata_block
		read($fh, my $metadataBlockData, $metadataBlockLength) or return 0;

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

	return 1;
}

sub _parseStreamInfo {
	my ($self, $block) = @_;

	my $info = {};

	# Convert to binary string, since there's some unfriendly lengths ahead
	my $metaBinString = unpack('B144', $block->{'contents'});

	my $x32 = 0 x 32;

	$info->{'MINIMUMBLOCKSIZE'} = unpack('N', pack('B32', substr($x32 . substr($metaBinString, 0, 16), -32)));
	$info->{'MAXIMUMBLOCKSIZE'} = unpack('N', pack('B32', substr($x32 . substr($metaBinString, 16, 32), -32)));
	$info->{'MINIMUMFRAMESIZE'} = unpack('N', pack('B32', substr($x32 . substr($metaBinString, 32, 24), -32)));
	$info->{'MINIMUMFRAMESIZE'} = unpack('N', pack('B32', substr($x32 . substr($metaBinString, 56, 24), -32)));

	$info->{'SAMPLERATE'}       = unpack('N', pack('B32', substr($x32 . substr($metaBinString, 80, 20), -32)));
	$info->{'NUMCHANNELS'}      = unpack('N', pack('B32', substr($x32 . substr($metaBinString, 100, 3), -32))) + 1;
	$info->{'BITSPERSAMPLE'}    = unpack('N', pack('B32', substr($x32 . substr($metaBinString, 100, 5), -32))) + 1;

	# Calculate total samples in two parts
	my $highBits = unpack('N', pack('B32', substr($x32 . substr($metaBinString, 108, 4), -32)));

	$info->{'TOTALSAMPLES'} = $highBits * 2 ** 32 + 
		unpack('N', pack('B32', substr($x32 . substr($metaBinString, 112, 32), -32)));

	# Return the MD5 as a 32-character hexadecimal string
	#$info->{'MD5CHECKSUM'} = unpack('H32',substr($self->{'metadataBlocks'}[$idx]->{'contents'},18,16));
	$info->{'MD5CHECKSUM'} = unpack('H32',substr($block->{'contents'}, 18, 16));

	# Store in the data hash
	$self->{'info'} = $info;

	# Calculate the track times
	my $totalSeconds = $info->{'TOTALSAMPLES'} / $info->{'SAMPLERATE'};

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

	return 1;
}

sub _parseVorbisComments {
	my ($self, $block) = @_;

	my $tags    = {};
	my $rawTags = [];

	# Parse out the tags from the metadata block
	my $tmpBlock = $block->{'contents'};
	my $offset   = 0;

	# First tag in block is the Vendor String
	my $tagLen = unpack('V', substr($tmpBlock, $offset, 4));
	$tags->{'VENDOR'} = substr($tmpBlock, ($offset += 4), $tagLen);

	# Now, how many additional tags are there?
	my $numTags = unpack('V', substr($tmpBlock, ($offset += $tagLen), 4));

	$offset += 4;

	for (my $tagi = 0; $tagi < $numTags; $tagi++) {

		# Read the tag string
		my $tagLen = unpack('V', substr($tmpBlock, $offset, 4));
		my $tagStr = substr($tmpBlock, ($offset += 4), $tagLen);

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

		$offset += $tagLen;
	}

	$self->{'tags'} = $tags;
	$self->{'rawTags'} = $rawTags;

	return 1;
}

sub _parseCueSheet {
	my ($self, $block) = @_;

	my $cuesheet = [];

	# Parse out the tags from the metadata block
	my $tmpBlock = $block->{'contents'};

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

	return 1;
}

sub _parsePicture {
	my ($self, $block) = @_;

	# Parse out the tags from the metadata block
	my $tmpBlock  = $block->{'contents'};
	my $offset    = 0;

	my $pictureType   = unpack('N', substr($tmpBlock, $offset, 4));
	my $mimeLength    = unpack('N', substr($tmpBlock, ($offset += 4), 4));
	my $mimeType      = substr($tmpBlock, ($offset += 4), $mimeLength);
	my $descLength    = unpack('N', substr($tmpBlock, ($offset += $mimeLength), 4));
	my $description   = substr($tmpBlock, ($offset += 4), $descLength);
	my $width         = unpack('N', substr($tmpBlock, ($offset += $descLength), 4));
	my $height        = unpack('N', substr($tmpBlock, ($offset += 4), 4));
	my $depth         = unpack('N', substr($tmpBlock, ($offset += 4), 4));
	my $colorIndex    = unpack('N', substr($tmpBlock, ($offset += 4), 4));
	my $imageLength   = unpack('N', substr($tmpBlock, ($offset += 4), 4));
	my $imageData     = substr($tmpBlock, ($offset += 4), $imageLength);

	$self->{'picture'}->{$pictureType}->{'mimeType'}    = $mimeType;
	$self->{'picture'}->{$pictureType}->{'description'} = $description;
	$self->{'picture'}->{$pictureType}->{'width'}       = $width;
	$self->{'picture'}->{$pictureType}->{'height'}      = $height;
	$self->{'picture'}->{$pictureType}->{'depth'}       = $depth;
	$self->{'picture'}->{$pictureType}->{'colorIndex'}  = $colorIndex;
	$self->{'picture'}->{$pictureType}->{'imageData'}   = $imageData;

	return 1;
}

sub _parseSeekTable {
	my ($self, $block) = @_;

	my $seektable = [];

	# grab the seekpoint table
	my $tmpBlock = $block->{'contents'};
	my $offset   = 0;

	# parse out the seekpoints
	while (my $seekpoint = substr($tmpBlock, $offset, 18)) {

		# Sample number of first sample in the target frame
		my $highbits     = unpack('N', substr($seekpoint,0,4));
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

		# add this point to our copy of the table
		push (@$seektable, {
			'sampleNumber' => $sampleNumber, 
			'streamOffset' => $streamOffset,
			'frameSamples' => $frameSamples,
		});

		$offset += 18;
	}

	$self->{'seektable'} = $seektable;

	return 1;
}

sub _parseAppBlock {
	my ($self, $block) = @_;

	# Parse out the tags from the metadata block
	my $appID = unpack('N', substr($block->{'contents'}, 0, 4, ''));

	$self->{'application'}->{$appID} = $block->{'contents'};

	return 1;
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

sub _packInt32 {
	# Packs an integer into a little-endian 32-bit unsigned int
	return pack('V', shift)
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

Pure perl code Copyright (c) 2003-2004, Erik Reckase.

Pure perl code Copyright (c) 2003-2006, Dan Sully.

XS code Copyright (c) 2004-2006, Dan Sully.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.2 or,
at your option, any later version of Perl 5 you may have available.

=cut
