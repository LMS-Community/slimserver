package Ogg::Vorbis::Header::PurePerl;

use 5.005;
use strict;
use warnings;

our $VERSION = '0.02';

sub new 
{
    my $class = shift;
    my $file = shift;

    return load($class, $file);
}

sub load 
{
    my $class = shift;
    my $file = shift;

    my %data;

    # check that the file exists and is readable
    unless ( -e $file && -r _ )
    {
	warn "File does not exist or cannot be read.";
	# file does not exist, can't do anything
	return undef;
    }
    # open up the file
    open FILE, $file;
    # make sure dos-type systems can handle it...
    binmode FILE;

    $data{'filename'} = $file;
    $data{'fileHandle'} = \*FILE;

    _init(\%data);
    _loadInfo(\%data);
    _loadComments(\%data);
#    $data{'INFO'}{'length'} = 0;
    _calculateTrackLength(\%data);

    close FILE;

    return bless \%data, $class;
}

sub info 
{
    my $self = shift;
    my $key = shift;

    # if the user did not supply a key, return the entire hash
    unless ($key)
    {
	return $self->{'INFO'};
    }

    # otherwise, return the value for the given key
    return $self->{'INFO'}{lc $key};
}

sub comment_tags 
{
    my $self = shift;

    return @{$self->{'COMMENT_KEYS'}};
}

sub comment 
{
    my $self = shift;
    my $key = shift;

    # if the user supplied key does not exist, return undef
    unless($self->{'COMMENTS'}{lc $key})
    {
	return undef;
    }

    return @{$self->{'COMMENTS'}{lc $key}};
}

sub add_comments 
{
    warn "Ogg::Vorbis::Header::PurePerl add_comments() unimplemented.";
}

sub edit_comment 
{
    warn "Ogg::Vorbis::Header::PurePerl edit_comment() unimplemented.";
}

sub delete_comment 
{
    warn "Ogg::Vorbis::Header::PurePerl delete_comment() unimplemented.";
}

sub clear_comments 
{
    warn "Ogg::Vorbis::Header::PurePerl clear_comments() unimplemented.";
}

sub path 
{
    my $self = shift;

    return $self->{'fileName'};
}

sub write_vorbis
{
    warn "Ogg::Vorbis::Header::PurePerl write_vorbis unimplemented.";
}

# "private" methods

sub _init
{
    my $data = shift;
    my $fh = $data->{'fileHandle'};
    my $byteCount = 0;

    # check the header to make sure this is actually an Ogg-Vorbis file
    $byteCount = _checkHeader($data);

    unless($byteCount)
    {
	# if it's not, we can't do anything
	return undef;
    }

    $data->{'startInfoHeader'} = $byteCount;
}

sub _checkHeader
{
    my $data = shift;
    my $fh = $data->{'fileHandle'};
    my $buffer;
    my $pageSegCount;
    my $byteCount = 0; # stores how far into the file we've read,
                       # so later reads into the file can skip right
                       # past all of the header stuff

    # check that the first four bytes are 'OggS'
    read($fh, $buffer, 4);
    if ($buffer ne 'OggS')
    {
	warn "This is not an Ogg bitstream (no OggS header).";
	return undef;
    }
    $byteCount += 4;

    # check the stream structure version (1 byte, should be 0x00)
    read($fh, $buffer, 1);
    if (ord($buffer) != 0x00)
    {
	warn "This is not an Ogg bitstream (invalid structure version).";
	return undef;
    }
    $byteCount += 1;

    # check the header type flag 
    # This is a bitfield, so technically we should check all of the bits
    # that could potentially be set. However, the only value this should
    # possibly have at the beginning of a proper Ogg-Vorbis file is 0x02,
    # so we just check for that. If it's not that, we go on anyway, but
    # give a warning (this behavior may (should?) be modified in the future.
    read($fh, $buffer, 1);
    if (ord($buffer) != 0x02)
    {
	warn "Invalid header type flag (trying to go ahead anyway).";
    }
    $byteCount += 1;

    # skip to the page_segments count
    read($fh, $buffer, 20);
    $byteCount += 20;
    # we do nothing with this data

    # read the number of page segments
    read($fh, $buffer, 1);
    $pageSegCount = ord($buffer);
    $byteCount += 1;

    # read $pageSegCount bytes, then throw 'em out
    read($fh, $buffer, $pageSegCount);
    $byteCount += $pageSegCount;

    # check packet type. Should be 0x01 (for indentification header)
    read($fh, $buffer, 1);
    if (ord($buffer) != 0x01)
    {
	warn "Wrong vorbis header type, giving up.";
	return undef;
    }
    $byteCount += 1;

    # check that the packet identifies itself as 'vorbis'
    read($fh, $buffer, 6);
    if ($buffer ne 'vorbis')
    {
	warn "This does not appear to be a vorbis stream, giving up.";
	return undef;
    }
    $byteCount += 6;

    # at this point, we assume the bitstream is valid
    return $byteCount;
}

sub _loadInfo
{
    my $data = shift;
    my $start = $data->{'startInfoHeader'};
    my $fh = $data->{'fileHandle'};
    my $buffer;
    my $byteCount = $start;
    my %info;
    
    seek $fh, $start, 0;
    
    # read the vorbis version
    read($fh, $buffer, 4);
    $info{'version'} = _decodeInt($buffer);
    $byteCount += 4;
    
    # read the number of audio channels
    read($fh, $buffer, 1);
    $info{'channels'} = ord($buffer);
    $byteCount += 1;

    # read the sample rate
    read($fh, $buffer, 4);
    $info{'rate'} = _decodeInt($buffer);
    $byteCount += 4;
    
    # read the bitrate maximum
    read($fh, $buffer, 4);
    $info{'bitrate_upper'} = _decodeInt($buffer);
    $byteCount += 4;

    # read the bitrate nominal
    read($fh, $buffer, 4);
    $info{'bitrate_nominal'} = _decodeInt($buffer);
    $byteCount += 4;

    # read the bitrate minimal
    read($fh, $buffer, 4);
    $info{'bitrate_lower'} = _decodeInt($buffer);
    $byteCount += 4;

    # read the blocksize_0 and blocksize_1
    read($fh, $buffer, 1);
    # these are each 4 bit fields, whose actual value is 2 to the power
    # of the value of the field
    $info{'blocksize_0'} = 2 << ((ord($buffer) & 0xF0) >> 4);
    $info{'blocksize_1'} = 2 << (ord($buffer) & 0x0F);
    $byteCount += 1;

    # read the framing_flag
    read($fh, $buffer, 1);
    $info{'framing_flag'} = ord($buffer);
    $byteCount += 1;

    # bitrate_window is -1 in the current version of vorbisfile
    $info{'bitrate_window'} = -1;

    $data->{'startCommentHeader'} = $byteCount;

    $data->{'INFO'} = \%info;
}

sub _loadComments
{
    my $data = shift;
    my $fh = $data->{'fileHandle'};
    my $start = $data->{'startCommentHeader'};
    my $buffer;
    my $page_segments;
    my $vendor_length;
    my $user_comment_count;
    my $byteCount = $start;
    my %comments;

    seek $fh, $start, 0;

    # check that the first four bytes are 'OggS'
    read($fh, $buffer, 4);
    if ($buffer ne 'OggS')
    {
	warn "No comment header?";
	return undef;
    }
    $byteCount += 4;

    # skip over next ten bytes
    read($fh, $buffer, 10);
    $byteCount += 10;

    # read the stream serial number
    read($fh, $buffer, 4);
    push @{$data->{'commentSerialNumber'}}, _decodeInt($buffer);
    $byteCount += 4;

    # read the page sequence number (should be 0x01)
    read($fh, $buffer, 4);
    if (_decodeInt($buffer) != 0x01)
    {
	warn "Comment header page sequence number is not 0x01: " + 
	    _decodeInt($buffer);
	warn "Going to keep going anyway.";
    }
    $byteCount += 4;

    # and ignore the page checksum for now
    read($fh, $buffer, 4);
    $byteCount += 4;

    # get the number of entries in the segment_table...
    read($fh, $buffer, 1);
    $page_segments = _decodeInt($buffer);
    $byteCount += 1;
    # then skip on past it
    read($fh, $buffer, $page_segments);
    $byteCount += $page_segments;

    # check the header type (should be 0x03)
    read($fh, $buffer, 1);
    if (ord($buffer) != 0x03)
    {
	warn "Wrong header type: " . ord($buffer);
    }    
    $byteCount += 1;

    # now we should see 'vorbis'
    read($fh, $buffer, 6);
    if ($buffer ne 'vorbis')
    {
	warn "Missing comment header. Should have found 'vorbis', found " .
	    $buffer;
    }
    $byteCount += 6;

    # get the vendor length
    read($fh, $buffer, 4);
    $vendor_length = _decodeInt($buffer);
    $byteCount += 4;

    # read in the vendor
    read($fh, $buffer, $vendor_length);
    $comments{'vendor'} = $buffer;
    $byteCount += $vendor_length;

    # read in the number of user comments
    read($fh, $buffer, 4);
    $user_comment_count = _decodeInt($buffer);
    $byteCount += 4;

    # finally, read the comments
    $data->{'COMMENT_KEYS'} = [];
    for (my $i = 0; $i < $user_comment_count; $i++)
    {
	# first read the length
	read($fh, $buffer, 4);
	my $comment_length = _decodeInt($buffer);
	$byteCount += 4;

	# then the comment itself
	read($fh, $buffer, $comment_length);
	$byteCount += $comment_length;

	my ($key, $value) = split(/=/, $buffer);

	push @{$comments{lc $key}}, $value;
	push @{$data->{'COMMENT_KEYS'}}, lc $key;
    }
    
    # read past the framing_bit
    read($fh, $buffer, 1);
    $byteCount += 1;

    $data->{'INFO'}{'offset'} = $byteCount;

    $data->{'COMMENTS'} = \%comments;
}

sub _calculateTrackLength
{
    my $data = shift;
    my $fh = $data->{'fileHandle'};
    my $buffer;
    my $pageSize;
    my $granule_position;

    # we just keep looking through the headers until we get to the last one
    while(_findPage($fh))
    {
	# stream structure version - must be 0x00
	read($fh, $buffer, 1);
	if (ord($buffer) != 0x00)
	{
	    warn "Invalid stream structure version: " .
		sprintf("%x", ord($buffer));
	    return;
 	}

 	# header type flag
 	read($fh, $buffer, 1);
 	# we should check this, but for now we'll just ignore it

 	# absolute granule position - this is what we need!
 	read($fh, $buffer, 8);
 	$granule_position = _decodeInt($buffer);

	# skip past stream_serial_number, page_sequence_number, and crc
	read($fh, $buffer, 12);

	# page_segments
	read($fh, $buffer, 1);
	my $page_segments = ord($buffer);

	# reset pageSize
	$pageSize = 0;
	
	# calculate approx. page size
	for (my $i = 0; $i < $page_segments; $i++)
	{
	    read($fh, $buffer, 1);
	    $pageSize += ord($buffer);
	}

	seek $fh, $pageSize, 1;
    }

    $data->{'INFO'}{'length'} = 
	int($granule_position / $data->{'INFO'}{'rate'});
}

sub _findPage
{
    # search forward in the file for the 'OggS' page header
    my $fh = shift;
    my $char;
    my $curStr = '';

    while (read($fh, $char, 1))
    {
	$curStr = $char . $curStr;
	$curStr = substr($curStr, 0, 4);

	# we are actually looking for the string 'SggO' because we
	# tack character on to our test string backwards, to make
	# trimming it to 4 characters easier.
	if ($curStr eq 'SggO')
	{
	    return 1;
	}
    }

    return undef;
}

sub _decodeInt
{
    my $bytes = shift;
    my $num = 0;
    my @byteList = split //, $bytes;
    my $numBytes = @byteList;
    my $mult = 1;

    for (my $i = 0; $i < $numBytes; $i ++)
    {
	$num += ord($byteList[$i]) * $mult;
	$mult *= 256;
    }

    return $num;
}

sub _decodeInt5Bit
{
    my $byte = ord(shift);

    $byte = $byte & 0xF8; # clear out the bottm 3 bits
    $byte = $byte >> 3; # and shifted down to where it belongs

    return $byte;
}

sub _decodeInt4Bit
{
    my $byte = ord(shift);

    $byte = $byte & 0xFC; # clear out the bottm 4 bits
    $byte = $byte >> 4; # and shifted down to where it belongs

    return $byte;
}

sub _ilog
{
    my $x = shift;
    my $ret = 0;

    unless ($x > 0)
    {
	return 0;
    }

    while ($x > 0)
    {
	$ret++;
	$x = $x >> 1;
    }

    return $ret;
}

1;
__DATA__

=head1 NAME

Ogg::Vorbis::Header::PurePerl - An object-oriented interface to Ogg Vorbis
information and comment fields, implemented entirely in Perl.  Intended to be 
a drop in replacement for Ogg::Vobis::Header.

Unlike Ogg::Vorbis::Header, this module will go ahead and fill in all of the
information fields as soon as you construct the object.  In other words,
the C<new> and C<load> constructors have identical behavior. 

=head1 SYNOPSIS

	use Ogg::Vorbis::Header::PurePerl;
	my $ogg = Ogg::Vorbis::Header::PurePerl->new("song.ogg");
	while (my ($k, $v) = each %{$ogg->info}) {
		print "$k: $v\n";
	}
	foreach my $com ($ogg->comment_tags) {
		print "$com: $_\n" foreach $ogg->comment($com);
	}

=head1 DESCRIPTION

This module is intended to be a drop in replacement for Ogg::Vorbis::Header,
implemented entirely in Perl.  It provides an object-oriented interface to
Ogg Vorbis information and comment fields.  (NOTE: This module currently 
supports only read operations).

=head1 CONSTRUCTORS

=head2 C<new ($filename)>

Opens an Ogg Vorbis file, ensuring that it exists and is actually an
Ogg Vorbis stream.  This method does not actually read any of the
information or comment fields, and closes the file immediately. 

=head2 C<load ([$filename])>

Opens an Ogg Vorbis file, ensuring that it exists and is actually an
Ogg Vorbis stream, then loads the information and comment fields.  This
method can also be used without a filename to load the information
and fields of an already constructed instance.

=head1 INSTANCE METHODS

=head2 C<info ([$key])>

Returns a hashref containing information about the Ogg Vorbis file from
the file's information header.  Hash fields are: version, channels, rate,
bitrate_upper, bitrate_nominal, bitrate_lower, bitrate_window, and length.
The bitrate_window value is not currently used by the vorbis codec, and 
will always be -1.  

The optional parameter, key, allows you to retrieve a single value from
the object's hash.  Returns C<undef> if the key is not found.

=head2 C<comment_tags ()>

Returns an array containing the key values for the comment fields. 
These values can then be passed to C<comment> to retrieve their values.

=head2 C<comment ($key)>

Returns an array of comment values associated with the given key.

=head2 C<add_comments ($key, $value, [$key, $value, ...])>

Unimplemented.

=head2 C<edit_comment ($key, $value, [$num])>

Unimplemented.

=head2 C<delete_comment ($key, [$num])>

Unimplemented.

=head2 C<clear_comments ([@keys])>

Unimplemented.

=head2 C<write_vorbis ()>

Unimplemented.

=head2 C<path ()>

Returns the path/filename of the file the object represents.

=head1 NOTE

This is ALPHA SOFTWARE.  It may very well be very broken.  Do not use it in
a production environment.  You have been warned.

=head1 AUTHOR

Andrew Molloy E<lt>amolloy@kaizolabs.comE<gt>

=head1 COPYRIGHT

Copyright (c) 2003, Andrew Molloy.  All Rights Reserved.

This program is free software; you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the
Free Software Foundation; either version 2 of the License, or (at
your option) any later version.  A copy of this license is included
with this module (LICENSE.GPL).

=head1 SEE ALSO

L<Ogg::Vorbis::Header>, L<Ogg::Vorbis::Decoder>

=cut
