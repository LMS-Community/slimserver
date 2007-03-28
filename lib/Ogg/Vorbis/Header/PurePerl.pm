package Ogg::Vorbis::Header::PurePerl;

use 5.005;
use strict;
use warnings;

# First four bytes of stream are always OggS
use constant OGGHEADERFLAG => 'OggS';

# Heavily modified by dsully - Logitech/Slim Devices.
our $VERSION = '0.1';

sub new {
	my $class = shift;
	my $file = shift;

	# open up the file
	open FILE, $file or do {
		warn "$class: File $file does not exist or cannot be read: $!";
		return undef;
	};

	# make sure dos-type systems can handle it...
	binmode FILE;

	my %data = (
		'filename'   => $file,
		'filesize'   => -s $file,
		'fileHandle' => \*FILE,
	);

	_init(\%data);
	_loadInfo(\%data);
	_loadComments(\%data);
	_calculateTrackLength(\%data);

	undef $data{'fileHandle'};
	close FILE;

	return bless \%data, $class;
}

sub info {
	my $self = shift;
	my $key = shift;

	# if the user did not supply a key, return the entire hash
	return $self->{'INFO'} unless $key;

	# otherwise, return the value for the given key
	return $self->{'INFO'}{lc $key};
}

sub comment_tags {
	my $self = shift;

	my %keys = ();

	return grep( !$keys{$_}++, @{$self->{'COMMENT_KEYS'}});
}

sub comment {
	my $self = shift;
	my $key = shift;

	# if the user supplied key does not exist, return undef
	return undef unless($self->{'COMMENTS'}{lc $key});

	return @{$self->{'COMMENTS'}{lc $key}};
}

sub path {
	my $self = shift;

	return $self->{'fileName'};
}

# "private" methods

sub _init {
	my $data = shift;

	# check the header to make sure this is actually an Ogg-Vorbis file
	$data->{'startInfoHeader'} = _checkHeader($data) || return undef;
}

sub _skipID3Header {
	my $fh = shift;

	my $byteCount = 0;

	while (read($fh, my $buffer, 4)) {

		if ($buffer eq OGGHEADERFLAG) {

			seek($fh, $byteCount, 0);
			last;
		}

		$byteCount++;
		seek($fh, $byteCount, 0);
	}

	return tell($fh);
}

sub _checkHeader {
	my $data = shift;

	my $fh = $data->{'fileHandle'};
	my $buffer;
	my $pageSegCount;

	# stores how far into the file we've read, so later reads into the file can
	# skip right past all of the header stuff

	my $byteCount = _skipID3Header($fh);

	# check that the first four bytes are 'OggS'
	read($fh, $buffer, 27);

	if (substr($buffer, 0, 4) ne OGGHEADERFLAG) {
		warn "This is not an Ogg bitstream (no OggS header).";
		return undef;
	}

	$byteCount += 4;

	# check the stream structure version (1 byte, should be 0x00)
	if (ord(substr($buffer, 4, 1)) != 0x00) {
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
	if (ord(substr($buffer, 5, 1)) != 0x02) {
		warn "Invalid header type flag (trying to go ahead anyway).";
	}

	$byteCount += 1;

	# read the number of page segments
	$pageSegCount = ord(substr($buffer, 26, 1));
	$byteCount += 21;

	# read $pageSegCount bytes, then throw 'em out
	seek($fh, $pageSegCount, 1);
	$byteCount += $pageSegCount;

	# check packet type. Should be 0x01 (for indentification header)
	read($fh, $buffer, 7);
	if (ord(substr($buffer, 0, 1)) != 0x01) {
		warn "Wrong vorbis header type, giving up.";
		return undef;
	}

	$byteCount += 1;

	# check that the packet identifies itself as 'vorbis'
	if (substr($buffer, 1, 6) ne 'vorbis') {
		warn "This does not appear to be a vorbis stream, giving up.";
		return undef;
	}

	$byteCount += 6;

	# at this point, we assume the bitstream is valid
	return $byteCount;
}

sub _loadInfo {
	my $data = shift;

	my $start = $data->{'startInfoHeader'};
	my $fh = $data->{'fileHandle'};

	my $byteCount = $start + 23;
	my %info = ();

	seek($fh, $start, 0);

	# read the vorbis version
	read($fh, my $buffer, 23);
	$info{'version'} = _decodeInt(substr($buffer, 0, 4, ''));

	# read the number of audio channels
	$info{'channels'} = ord(substr($buffer, 0, 1, ''));

	# read the sample rate
	$info{'rate'} = _decodeInt(substr($buffer, 0, 4, ''));

	# read the bitrate maximum
	$info{'bitrate_upper'} = _decodeInt(substr($buffer, 0, 4, ''));

	# read the bitrate nominal
	$info{'bitrate_nominal'} = _decodeInt(substr($buffer, 0, 4, ''));

	# read the bitrate minimal
	$info{'bitrate_lower'} = _decodeInt(substr($buffer, 0, 4, ''));

	# read the blocksize_0 and blocksize_1
	# these are each 4 bit fields, whose actual value is 2 to the power
	# of the value of the field
	my $blocksize = substr($buffer, 0, 1, '');
	$info{'blocksize_0'} = 2 << ((ord($blocksize) & 0xF0) >> 4);
	$info{'blocksize_1'} = 2 << (ord($blocksize) & 0x0F);

	# read the framing_flag
	$info{'framing_flag'} = ord(substr($buffer, 0, 1, ''));

	# bitrate_window is -1 in the current version of vorbisfile
	$info{'bitrate_window'} = -1;

	$data->{'startCommentHeader'} = $byteCount;

	$data->{'INFO'} = \%info;
}

sub _loadComments {

	my $data = shift;
	my $fh = $data->{'fileHandle'};
	my $start = $data->{'startCommentHeader'};
	my $page_segments;
	my $vendor_length;
	my $user_comment_count;
	my $byteCount = $start;
	my %comments;

	seek($fh, $start, 0);
	read($fh, my $buffer, 8192);

	# check that the first four bytes are 'OggS'
	if (substr($buffer, 0, 4, '') ne OGGHEADERFLAG) {
		warn "No comment header?";
		return undef;
	}

	$byteCount += 4;

	# read the stream serial number
	substr($buffer, 0, 10, '');
	push @{$data->{'commentSerialNumber'}}, _decodeInt(substr($buffer, 0, 4, ''));
	$byteCount += 14;

	# read the page sequence number (should be 0x01)
	if (_decodeInt(substr($buffer, 0, 4, '')) != 0x01) {
		warn "Comment header page sequence number is not 0x01: " + _decodeInt($buffer);
		warn "Going to keep going anyway.";
	}
	$byteCount += 4;

	# get the number of entries in the segment_table...
	substr($buffer, 0, 4, '');
	$page_segments = _decodeInt(substr($buffer, 0, 1, ''));
	$byteCount += 5;

	# then skip on past it
	substr($buffer, 0, $page_segments, '');
	$byteCount += $page_segments;

	# check the header type (should be 0x03)
	if (ord(substr($buffer, 0, 1, '')) != 0x03) {
		warn "Wrong header type: " . ord($buffer);
	}
	$byteCount += 1;

	# now we should see 'vorbis'
	if (substr($buffer, 0, 6, '') ne 'vorbis') {
		warn "Missing comment header. Should have found 'vorbis', found $buffer\n";
	}
	$byteCount += 6;

	# get the vendor length
	$vendor_length = _decodeInt(substr($buffer, 0, 4, ''));
	$byteCount += 4;

	# read in the vendor
	$comments{'vendor'} = substr($buffer, 0, $vendor_length, '');
	$byteCount += $vendor_length;

	# read in the number of user comments
	$user_comment_count = _decodeInt(substr($buffer, 0, 4, ''));
	$byteCount += 4;

	# finally, read the comments
	$data->{'COMMENT_KEYS'} = [];

	for (my $i = 0; $i < $user_comment_count; $i++) {

	# first read the length
	my $comment_length = _decodeInt(substr($buffer, 0, 4, ''));
		$byteCount += 4;

		# then the comment itself
		$byteCount += $comment_length;

		my ($key, $value) = split(/=/, substr($buffer, 0, $comment_length, ''));

		my $lcKey = lc($key);

		push @{$comments{$lcKey}}, $value;
		push @{$data->{'COMMENT_KEYS'}}, $lcKey;
	}

	# read past the framing_bit
	$byteCount += 1;
	seek($fh, $byteCount, 1);

	$data->{'INFO'}{'offset'} = $byteCount;

	$data->{'COMMENTS'} = \%comments;
}

sub _calculateTrackLength {
	my $data = shift;

	my $fh = $data->{'fileHandle'};

	# The original author was doing something pretty lame, and was walking the
	# entire file to find the last granule_position. Instead, let's seek to
	# the end of the file - blocksize_0, and read from there.
	my $len = 0;

	# Bug 1155 - Seek further back to get the granule_position.
	# However, for short tracks, don't seek that far back.
	if (($data->{'filesize'} - $data->{'INFO'}{'offset'}) > ($data->{'INFO'}{'blocksize_0'} * 2)) {

		$len = $data->{'INFO'}{'blocksize_0'} * 2;
	} else {
		$len = $data->{'INFO'}{'blocksize_0'};
	}

	if ($len == 0) {
		print "Ogg::Vorbis::Header::PurePerl:\n";
		warn "blocksize_0 is 0! Should be a power of 2! http://www.xiph.org/ogg/vorbis/doc/vorbis-spec-ref.html\n";
		return;
	}

	seek($fh, -$len, 2);
	read($fh, my $buf, $len);

	my $foundHeader = 0;

	for (my $i = 0; $i < $len; $i++) {

		last if length($buf) < 4;

		if (substr($buf, $i, 4) eq OGGHEADERFLAG) {
			substr($buf, 0, ($i+4), '');
			$foundHeader = 1;
			last;
		}
	}

	unless ($foundHeader) {
		warn "Ogg::Vorbis::Header::PurePerl: Didn't find an ogg header - invalid file?\n";
		return;
	}

	# stream structure version - must be 0x00
	if (ord(substr($buf, 0, 1, '')) != 0x00) {
		warn "Ogg::Vorbis::Header::PurePerl: Invalid stream structure version: " . sprintf("%x", ord($buf));
		return;
 	}

 	# absolute granule position - this is what we need!
	substr($buf, 0, 1, '');

 	my $granule_position = _decodeInt(substr($buf, 0, 8, ''));

	if ($granule_position && $data->{'INFO'}{'rate'}) {
		$data->{'INFO'}{'length'} = int($granule_position / $data->{'INFO'}{'rate'});
	}
}

sub _decodeInt {
	my $bytes = shift;

	my $numBytes = length($bytes);
	my $num = 0;
	my $mult = 1;

	for (my $i = 0; $i < $numBytes; $i ++) {

		$num += ord(substr($bytes, 0, 1, '')) * $mult;
		$mult *= 256;
	}

	return $num;
}

1;

__END__

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
