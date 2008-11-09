package Ogg::Vorbis::Header::PurePerl;

use 5.005;
use strict;
use warnings;

# First four bytes of stream are always OggS
use constant OGGHEADERFLAG => 'OggS';

our $VERSION = '1.0';

sub new {
	my $class = shift;
	my $file  = shift;

	my %data  = ();

	if (ref $file) {
		binmode $file;

		%data = (
			'filesize'   => -s $file,
			'fileHandle' => $file,
		);

	} else {

		open FILE, $file or do {
			warn "$class: File $file does not exist or cannot be read: $!";
			return undef;
		};

		# make sure dos-type systems can handle it...
		binmode FILE;

		%data = (
			'filename'   => $file,
			'filesize'   => -s $file,
			'fileHandle' => \*FILE,
		);
	}

	if ( _init(\%data) ) {
		_loadInfo(\%data);
		_loadComments(\%data);
		_calculateTrackLength(\%data);
	}

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

	return wantarray 
		? @{$self->{'COMMENTS'}{lc $key}}
		: $self->{'COMMENTS'}{lc $key}->[0];
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
	
	return 1;
}

sub _skipID3Header {
	my $fh = shift;

	read $fh, my $buffer, 3;
	
	my $byteCount = 3;
	
	if ($buffer eq 'ID3') {

		while (read $fh, $buffer, 4096) {

			my $found;
			if (($found = index($buffer, OGGHEADERFLAG)) >= 0) {
				$byteCount += $found;
				seek $fh, $byteCount, 0;
				last;
			} else {
				$byteCount += 4096;
			}
		}

	} else {
		seek $fh, 0, 0;
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
	
	# Remember the start of the Ogg data
	$data->{startHeader} = $byteCount;

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
	my $fh    = $data->{'fileHandle'};

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

	my $fh    = $data->{'fileHandle'};
	my $start = $data->{'startHeader'};

	$data->{COMMENT_KEYS} = [];

	# Comment parsing code based on Image::ExifTool::Vorbis
	my $MAX_PACKETS = 2;
	my $done;
	my ($page, $packets, $streams) = (0,0,0,0);
	my ($buff, $flag, $stream, %val);

	seek $fh, $start, 0;

	while (1) {	
		if (!$done && read( $fh, $buff, 28 ) == 28) {
			# validate magic number
			unless ( $buff =~ /^OggS/ ) {
				warn "No comment header?";
				last;
			}

			$flag   = Get8u(\$buff, 5);	# page flag
			$stream = Get32u(\$buff, 14);	# stream serial number
			++$streams if $flag & 0x02;	# count start-of-stream pages
			++$packets unless $flag & 0x01; # keep track of packet count
		}
		else {
			# all done unless we have to process our last packet
			last unless %val;
			($stream) = sort keys %val;     # take a stream
			$flag = 0;                      # no continuation
			$done = 1;                      # flag for done reading
		}
		
		# can finally process previous packet from this stream
		# unless this is a continuation page
		if (defined $val{$stream} and not $flag & 0x01) {
			_processComments( $data, \$val{$stream} );
			delete $val{$stream};
			# only read the first $MAX_PACKETS packets from each stream
			if ($packets > $MAX_PACKETS * $streams) {
				# all done (success!)
				last unless %val;
				# process remaining stream(s)
				next;
			}
		}

		# stop processing Ogg Vorbis if we have scanned enough packets
		last if $packets > $MAX_PACKETS * $streams and not %val;
		
		# continue processing the current page
		# page sequence number
		my $pageNum = Get32u(\$buff, 18);

		# number of segments
		my $nseg    = Get8u(\$buff, 26);

		# calculate total data length
		my $dataLen = Get8u(\$buff, 27);
		
		if ($nseg) {
			read( $fh, $buff, $nseg-1 ) == $nseg-1 or last;
			my @segs = unpack('C*', $buff);
			# could check that all these (but the last) are 255...
			foreach (@segs) { $dataLen += $_ }
		}

		if (defined $page) {
			if ($page == $pageNum) {
				++$page;
			} else {
				warn "Missing page(s) in Ogg file\n";
				undef $page;
			}
		}
		
		# read page data
		read($fh, $buff, $dataLen) == $dataLen or last;

		if (defined $val{$stream}) {
			# add this continuation page
			$val{$stream} .= $buff;
		} elsif (not $flag & 0x01) {
			# ignore remaining pages of a continued packet
			# ignore the first page of any packet we aren't parsing
			if ($buff =~ /^(.)vorbis/s and ord($1) == 3) {
				# save this page, it has comments
				$val{$stream} = $buff;
			}
		}
		
		if (defined $val{$stream} and $flag & 0x04) {
			# process Ogg Vorbis packet now if end-of-stream bit is set
			_processComments($data, \$val{$stream});
			delete $val{$stream};
		}
	}
	
	$data->{'INFO'}{offset} = tell $fh;
}

sub _processComments {
	my ( $data, $dataPt ) = @_;
	
	my $pos = 7;
	my $end = length $$dataPt;
	
	my $num;
	my %comments;
	
	while (1) {
		last if $pos + 4 > $end;
		my $len = Get32u($dataPt, $pos);
		last if $pos + 4 + $len > $end;
		my $start = $pos + 4;
		my $buff = substr($$dataPt, $start, $len);
		$pos = $start + $len;
		my ($tag, $val);
		if (defined $num) {
			$buff =~ /(.*?)=(.*)/s or last;
			($tag, $val) = ($1, $2);
		} else {
			$tag = 'vendor';
			$val = $buff;
			$num = ($pos + 4 < $end) ? Get32u($dataPt, $pos) : 0;
			$pos += 4;
		}
		
		my $lctag = lc $tag;
		
		push @{$comments{$lctag}}, $val;
		push @{$data->{COMMENT_KEYS}}, $lctag;
		
		# all done if this was our last tag
		if ( !$num-- ) {
			$data->{COMMENTS} = \%comments;
			return 1;
		}
	}
	
	warn "format error in Vorbis comments\n";
	
	return 0;
}

sub Get8u {
	return unpack( "x$_[1] C", ${$_[0]} );
}

sub Get32u {
	return unpack( "x$_[1] V", ${$_[0]} );
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
		$data->{'INFO'}{'length'}          = int($granule_position / $data->{'INFO'}{'rate'});
		$data->{'INFO'}{'bitrate_average'} = sprintf( "%d", ( $data->{'filesize'} * 8 ) / $data->{'INFO'}{'length'} );
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

=head1 AUTHOR

Andrew Molloy E<lt>amolloy@kaizolabs.comE<gt>

Dan Sully E<lt>daniel | at | cpan.orgE<gt>

=head1 COPYRIGHT
 
Copyright (c) 2003, Andrew Molloy.  All Rights Reserved.
 
Copyright (c) 2005-2008, Dan Sully.  All Rights Reserved.

This program is free software; you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the
Free Software Foundation; either version 2 of the License, or (at
your option) any later version.  A copy of this license is included
with this module (LICENSE.GPL).

=head1 SEE ALSO

L<Ogg::Vorbis::Header>, L<Ogg::Vorbis::Decoder>

=cut
