package Audio::APETags;

use strict;
use vars qw($VERSION);

$VERSION = '0.01';

# First eight bytes of ape v2 tag block are always APETAGEX
use constant APEHEADERFLAG  => 'APETAGEX';

use constant ID3HEADERFLAG  => 'ID3';
use constant ID3V1FLAG      => 'TAG';

# Masks for TAGS FLAGS
use constant TF_HAS_HEADER => 0x80000000;
use constant TF_HAS_FOOTER => 0x40000000;
use constant TF_HEAD_FOOT  => 0x20000000;
use constant TF_CONTENTS   => 0x00000006;
use constant TF_READ_ONLY  => 0x00000001;

# useful constants
use constant ID3V1TAGSIZE  => 128;
use constant APEHEADFOOT   => 32;

sub getTags {
	my $class = shift;
	my $file  = shift;
	my $errflag = 0;

	my $self  = {};
	
	bless $self,$class;

	# open up the file
	open(FILE, $file) or do {
		warn "File does not exist or cannot be read.";
		return $self;
	};

	# make sure dos-type systems can handle it...
	binmode FILE;

	$self->{'fileHandle'} = \*FILE;

	# Initialize APE TAG analysis
	# File *may* have ID3V2 tags at the front, and/or
	# ID3V1 tags at the end of a valid file
	$errflag = $self->_init();
	if ($errflag < 0) {
		# Could not find the APE tag
		close FILE;
		undef $self->{'fileHandle'};
		return $self;
	};

	$errflag = $self->_parseTags();

	close FILE;
	undef $self->{'fileHandle'};
	return $self;
}

# "private" methods
sub _init {
	my $self = shift;

	my $fh	 = $self->{'fileHandle'};

	my ($apetest, $buffer, $id3size);

	# look at the end of the file first; APE tags are
	# more often found there than at the beginning

	# The end of the file may be an ID3V1 tag.  If so,
	# skip it and then look for the APE tag
	seek $fh, -(ID3V1TAGSIZE), 2;
	read $fh, my $id3chk, 3 or return -1;

	if ($id3chk eq ID3V1FLAG) {
		# Seek back to -128 as the 'end' of the APE tag
		seek $fh, -(ID3V1TAGSIZE), 2;
	} else {
		# No ID3V1, so go back to the end of the file
		seek $fh, 0, 2;
	}

	# Go back 32 bytes to check for an APE tag
	seek $fh, -(APEHEADFOOT), 1;

	# Is there an APE tag here? (At the end of the file)
	read $fh, $apetest, 8 or return -1;

	if ($apetest ne APEHEADERFLAG) {
		# OK, there's no APE tag here.  Try at the beginning
		# of the file.
		seek $fh, 0, 0;
		read $fh, $apetest, 8 or return -1;

		if (substr($apetest, 0, 3) eq ID3HEADERFLAG) {
			# There's an ID3V2 header on the file.
			# Skip past it.
			$self->{'ID3V2Tag'}=1;

			# Skip the next two bytes
			seek $fh, 2, 1;

			# The size of the ID3 tag is a 'synchsafe' 4-byte uint
			# Read the next 4 bytes one at a time, unpack each one B7,
			# and concatenate.  When complete, do a bin2dec to determine size
			$id3size = '';
			for (my $c=0; $c<4; $c++) {
				read ($fh, $buffer, 1) or return -1;
				$id3size .= substr(unpack ("B8", $buffer), 1);
			}

			# Skip the ID3 tag
			seek $fh, _bin2dec($id3size) + 10, 0;

			# Re-check for APE header
			read $fh, $apetest, 8 or return -1;

			if ($apetest ne APEHEADERFLAG) {
				# No APE tag to be found
				return -2;
			}
		}
	}

	$self->{'APETagLoc'} = (tell $fh)-8;

	return 0;
}

sub _parseTags {
	my $self = shift;

	my $fh	 = $self->{'fileHandle'};
	my ($tmp,$tagLen,$tagItemKey,$tagFlags,$tagItemVal);

	# Seek to the location of the known APE header/footer
	seek $fh, $self->{'APETagLoc'}, 0;

	read $fh, $tmp, APEHEADFOOT or return -1;

	# Skip the first 8 bytes
	$tmp = substr $tmp, 8;

	$self->{'tagVersion'}     = _grabInt32(\$tmp);
	$self->{'tagTotalSize'}   = _grabInt32(\$tmp);
	$self->{'tagTotalItems'}  = _grabInt32(\$tmp);
	$self->{'tagGlobalFlags'} = _grabInt32(\$tmp);

	# Check the tagGlobalFlags to determine whether or not this
	# tag is a footer or a header
	if ( ($self->{'tagGlobalFlags'} & TF_HEAD_FOOT) == 0) {
		# this is a footer,
		# so seek backwards tagTotalSize to get to
		# the beginning of the actual tag info
		seek $fh, -($self->{'tagTotalSize'}), 1;
	} else {
		# this is a header,
		# so we are already at the beginning of the
		# actual tag info
	}
	
	if (!$self->{'tagTotalSize'} || ($self->{'tagTotalSize'} < 0) || ($self->{'tagTotalSize'} > -s $fh) ) {
		warn "tagTotalSize error, these do not appear to be valid APEtags";
		return -1;
	}
	
	# Read in the entire tag structure
	read($fh, $tmp, $self->{'tagTotalSize'}) or return -1;

	$self->{'tags'} = {};
	$self->{'tagFlags'} = {};

	# Parse it for contents
	for (my $c=0; $c < $self->{'tagTotalItems'}; $c++) {
		# Loop through the tag items
		$tagLen   = _grabInt32(\$tmp);
		$tagFlags = _grabInt32(\$tmp);

		if ($tmp =~ /^(.*?)\0/) {
			$tagItemKey = uc($1);
		}

		$tmp =~ s/^.*?\0//;

		$tagItemVal = substr $tmp, 0, $tagLen;
		$tmp        = substr $tmp, $tagLen;

		# Stuff in hash
		$self->{'tags'}    ->{$tagItemKey} = $tagItemVal;
		$self->{'tagFlags'}->{$tagItemKey} = $tagFlags;
	}

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

1;

__END__

=head1 NAME

Audio::ApeTags - An interface to the APE tagging structure implemented 
entirely in Perl.

=head1 SYNOPSIS

	use Audio::ApeTags;
	my $ape = getTags("song.flac");
	
	$apeTags = $ape->{'tags'};

	foreach (keys %{$apeTags}) {
		print "$_: $apeTags->{$_}\n";
	}

=head1 DESCRIPTION

This module returns a hash containing the contents of the Ape tags
associated with an audio file. There is no complete list of tag keys
for Ape tags, as they can be defined by the user; the basic set of
tags used in the Ape convention include (but will not likely all be
defined for a most audio files):

	Title
	Subtitle
	Artist
	Album
	Debut Album
	Publisher
	Conductor
	Track
	Composer
	Comment
	Copyright
	Publicationright
	File
	EAN/UPC
	ISBN
	Catalog
	LC
	Year
	Record Date
	Record Location
	Genre
	Media
	Index
	Related
	ISRC
	Abstract
	Language
	Bibliography
	Introplay

Associated with each key is a set of flags; these flags contain
information about the editability of the tag/item as well as
the type of contents.

=head1 CONSTRUCTORS

=head2 C<getTags ($filename)>

Opens an audio file and attempts to read APE tags from the 
top and bottom of the file, skipping ID3 tags if present.

=head1 SEE ALSO

L<http://www.personal.uni-jena.de/~pfk/mpp/sv8/apetag.html>

=head1 AUTHOR

Erik Reckase, E<lt>cerebusjam at hotmail dot comE<gt>, with lots of help
from Dan Sully, E<lt>daniel@cpan.orgE<gt>

=head1 COPYRIGHT

Copyright (c) 2003, Erik Reckase.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.2 or,
at your option, any later version of Perl 5 you may have available.

=cut



