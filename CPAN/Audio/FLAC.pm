package Audio::FLAC;

# $Id: FLAC.pm,v 1.4 2004/01/12 23:34:41 daniel Exp $

use strict;
use vars qw($VERSION);

$VERSION = '0.5';

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

sub new {
	my $class = shift;
	my $file  = shift;
	my $errflag = 0;

	my $self  = {};

	bless $self, $class;

	# open up the file
	open(FILE, $file) or do {
		warn "File does not exist or cannot be read.";
		return $self;
	};

	# make sure dos-type systems can handle it...
	binmode FILE;

	$self->{'fileSize'}   = -s $file;
	$self->{'filename'}   = $file;
	$self->{'fileHandle'} = \*FILE;

	# Initialize FLAC analysis
	$errflag = $self->_init();
	if ($errflag < 0) {
		warn "File does not appear to be a FLAC file!";
		close FILE;
		undef $self->{'fileHandle'};
		return $self;
	};

	# Grab the metadata blocks from the FLAC file
	$errflag = $self->_getMetadataBlocks();
	if ($errflag < 0) {
		warn "Unable to read metadata from FLAC file!";
		close FILE;
		undef $self->{'fileHandle'};
		return $self;
	};

	# Parse streaminfo
	$errflag = $self->_parseStreaminfo();
	if ($errflag < 0) {
		warn "Can't find streaminfo metadata block!";
		close FILE;
		undef $self->{'fileHandle'};
		return $self;
	};

	# Parse vorbis tags
	$errflag = $self->_parseVorbisComments();
	if ($errflag < 0) {
		warn "Can't find vorbis comment metadata block!";
		close FILE;
		undef $self->{'fileHandle'};
		return $self;
	};

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

sub write {
	my $self = shift;

	my @tagString = ();
	my $numTags   = 0;

	my ($idxVorbis,$idxPadding);
	my $totalAvail = 0;
	my $metadataBlocks = '';
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
	if ($idxPadding<0) {
		# no padding block
		_addNewMetadataBlock($self, BT_PADDING , ' ' x ($totalAvail - length($vorbisComment)));
	} else {
		# update the padding block
		_updateMetadataBlock($self, $idxPadding, ' ' x ($totalAvail - length($vorbisComment)));
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

	# seek to the location of the existing metadata blocks
	seek FLACFILE, ($self->{'startMetadataBlocks'})-4, 0;

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
		# Skip the next two bytes
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
	my $idx  = $self->_findMetadataIndex(BT_VORBIS_COMMENT);

	if ($idx < 0) {
		return -1;
	}

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

		# Match the key and value
		if ($tagStr =~ /^(.*?)=(.*)$/) {
			# Make the key uppercase
			my $tkey = $1;
			   $tkey =~ tr/a-z/A-Z/;

			# Stick it in the tag hash
			$tags->{$tkey} = $2;
		}
	}

	$self->{'tags'} = $tags;

	return 0;
}

sub _bin2dec {
	# Freely swiped from Perl Cookbook p. 48 (May 1999)
	return unpack ('N', pack ('B32', substr(0 x 32 . shift, -32)));
}

sub _grabInt32 {
	# Pulls a little-endian unsigned int from a string and returns the remainder
	my $data  = shift;
	my $value = unpack('L',substr($$data,0,4));
	$$data    = substr($$data,4);
	return $value;
}

sub _packInt32 {
	# Packs an integer into a little-endian 32-bit unsigned int
	return pack('L',shift)
}

sub _findMetadataIndex {
	my $self  = shift;
	my $htype = shift;

	my ($idx, $found) = (0, 0);

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

Audio::FLAC - An object-oriented interface to FLAC file information and
comment fields, implemented entirely in Perl.

=head1 SYNOPSIS

	use Audio::FLAC;
	my $flac = Audio::FLAC->new("song.flac");

	my $flacInfo = $flac->info();

	foreach (keys %$flacInfo) {
		print "$_: $flacInfo->{$_}\n";
	}

	my $flacTags = $flac->tags();

	foreach (keys %$flacTags) {
		print "$_: $flacTags->{$_}\n";
	}

=head1 DESCRIPTION

This module returns a hash containing basic information about a FLAC file,
as well as tag information contained in the FLAC file's Vorbis tags.
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
	filename                : filename with path

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

=head2 C<write ()>

Writes the current contents of the tag hash to the FLAC file, given that
there's enough space in the header to do so.  If there's insufficient
space available (using pre-existing padding), the file will remain
unchanged, and the function will return a non-zero value.

=head1 SEE ALSO

L<http://flac.sourceforge.net/format.html>

=head1 AUTHOR

Erik Reckase, E<lt>cerebusjam at hotmail dot comE<gt>, with lots of help
from Dan Sully, E<lt>daniel@cpan.orgE<gt>

=head1 COPYRIGHT

Copyright (c) 2003, Erik Reckase.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.2 or,
at your option, any later version of Perl 5 you may have available.

=cut
