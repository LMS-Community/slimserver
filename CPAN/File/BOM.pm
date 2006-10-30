package File::BOM;

=head1 NAME

File::BOM - Utilities for handling Byte Order Marks

=head1 SYNOPSIS

    use File::BOM qw( :all )

=head2 high-level functions

    # read a file with encoding from the BOM:
    open_bom(FH, $file)
    open_bom(FH, $file, ':utf8') # the same but with a default encoding

    # get encoding too
    $encoding = open_bom(FH, $file, ':utf8');

    # open a potentially unseekable file:
    ($encoding, $spillage) = open_bom(FH, $file, ':utf8');

    # change encoding of an open handle according to BOM
    $encoding = defuse(*HANDLE);
    ($encoding, $spillage) = defuse(*HANDLE);

    # Decode a string according to leading BOM:
    $unicode = decode_from_bom($string_with_bom);
    
    # Decode a string and get the encoding:
    ($unicode, $encoding) = decode_from_bom($string_with_bom)

=head2 PerlIO::via interface

    # Read the Right Thing from a unicode file with BOM:
    open(HANDLE, '<:via(File::BOM)', $filename)

    # Writing little-endian UTF-16 file with BOM:
    open(HANDLE, '>:encoding(UTF-16LE):via(File::BOM)', $filename)


=head2 lower-level functions

    # read BOM encoding from a filehandle:
    $encoding = get_encoding_from_filehandle(FH)

    # Get encoding even if FH is unseekable:
    ($encoding, $spillage) = get_encoding_from_filehandle(FH);

    # Get encoding from a known unseekable handle:
    ($encdoing, $spillage) = get_encoding_from_stream(FH);

    # get encoding and BOM length from BOM at start of string:
    ($encoding, $offset) = get_encoding_from_bom($string);

=head2 variables

    # print a BOM for a known encoding
    print FH $enc2bom{$encoding};

    # get an encoding from a known BOM
    $enc = $bom2enc{$bom}

=head1 DESCRIPTION

This module provides functions for handling unicode byte order marks, which are
to be found at the beginning of some files and streams.

For details about what a byte order mark is, see
L<http://www.unicode.org/unicode/faq/utf_bom.html#BOM>

The intention of File::BOM is for files with BOMs to be readable as seamlessly
as possible, regardless of the encoding used. To that end, several different
interfaces are available, as shown in the synopsis above. 

=cut

use strict;
use warnings;

# We don't want any character semantics at all
use bytes;

use base qw( Exporter );

use Readonly;

use Carp	qw( croak );
use Fcntl	qw( :seek );
use Encode	qw( :DEFAULT :fallbacks is_utf8 );
use Symbol	qw( gensym qualify_to_ref );

my @subs = qw(
	open_bom
	defuse
	decode_from_bom
	get_encoding_from_bom
	get_encoding_from_filehandle
	get_encoding_from_stream
    );

my @vars = qw( %bom2enc %enc2bom );

our $VERSION = '0.13';

our @EXPORT = ();
our @EXPORT_OK = ( @subs, @vars );
our %EXPORT_TAGS = (
	all  => \@EXPORT_OK,
	subs => \@subs,
	vars => \@vars
    );

=head1 EXPORTS

Nothing by default.

=head2 symbols

=over 4

=item * open_bom()

=item * defuse()

=item * decode_from_bom()

=item * get_encoding_from_filehandle()

=item * get_encoding_from_stream()

=item * get_encoding_from_bom()

=item * %bom2enc

=item * %enc2bom

=back

=head2 tags

=over 4

=item * :all

All of the above

=item * :subs

subroutines only

=item * :vars

just %bom2enc and %enc2bom

=back

=cut

=head1 VARIABLES

=head2 %bom2enc

Maps Byte Order marks to their encodings.

The keys of this hash are strings which represent the BOMs, the values are their
encodings, in a format which is understood by L<Encode>

The encodings represented in this hash are: UTF-8, UTF-16BE, UTF-16LE,
UTF-32BE and UTF-32LE

=head2 %enc2bom

A reverse-lookup hash for bom2enc, with a few aliases used in L<Encode>, namely utf8, iso-10646-1 and UCS-2.

Note that UTF-16, UTF-32 and UCS-4 are not included in this hash. Mainly
because Encode::encode automatically puts BOMs on output. See L<Encode::Unicode>

=cut

our(%bom2enc, %enc2bom, $MAX_BOM_LENGTH, $bom_re);

# length in bytes of the longest BOM
$MAX_BOM_LENGTH = 4;

Readonly %bom2enc => (
	map { encode($_, "\x{feff}") => $_ } qw(
	    UTF-8
	    UTF-16BE
	    UTF-16LE
	    UTF-32BE
	    UTF-32LE
	)
    );

Readonly %enc2bom => (
	reverse(%bom2enc),
	map { $_ => encode($_, "\x{feff}") } qw(
	    UCS-2
	    iso-10646-1
	    utf8
	)
    );

{
    local $" = '|';

    my @bombs = sort { length $b <=> length $a } keys %bom2enc;

    Readonly $MAX_BOM_LENGTH => length $bombs[0];

    Readonly $bom_re => qr/^(@bombs)/o;
}

=head1 FUNCTIONS

=head2 open_bom

    $encoding = open_bom(HANDLE, $filename, $default_mode)

    ($encoding, $spill) = open_bom(HANDLE, $filename, $default_mode)

opens HANDLE for reading on $filename, setting the mode to the appropriate
encoding for the BOM stored in the file.

On failure, a fatal error is raised, see the DIAGNOSTICS section for details on
how to catch these. This is in order to allow the return value(s) to be used for
other purposes.

If the file doesn't contain a BOM, $default_mode is used instead. Hence:

    open_bom(FH, 'my_file.txt', ':utf8')

Opens my_file.txt for reading in an appropriate encoding found from the BOM in
that file, or as a UTF-8 file if none is found.

In the absense of a $default_mode argument, the following 2 calls should be equivalent:

    open_bom(FH, 'no_bom.txt');

    open(FH, '<', 'no_bom.txt');

If an undefined value is passed as the handle, a symbol will be generated for it
like open() does:

    # create filehandle on the fly
    $enc = open_bom(my $fh, $filename, ':utf8');
    $line = <$fh>;

The filehandle will be cued up to read after the BOM. Unseekable files (e.g.
fifos) will cause croaking, unless called in list context to catch spillage
from the handle. Any spillage will be automatically decoded from the encoding,
if found.

    e.g.

    # croak if my_socket is unseekable
    open_bom(FH, 'my_socket');

    # keep spillage if my_socket is unseekable
    ($encoding, $spillage) = open_bom(FH, 'my_socket');

    # discard any spillage from open_bom
    ($encoding) = open_bom(FH, 'my_socket');

=cut

sub open_bom (*$;$) {
    my($fh, $filename, $mode) = @_;
    if (defined $fh) {
	$fh = qualify_to_ref($fh, caller);
    }
    else {
	$fh = $_[0] = gensym();
    }

    my $enc;
    my $spill = '';

    open($fh, '<', $filename)
	or croak "Couldn't read '$filename': $!";

    if (wantarray) {
	($enc, $spill) = get_encoding_from_filehandle($fh);
    }
    else {
	$enc = get_encoding_from_filehandle($fh);
    }

    if ($enc) {
	$mode = ":encoding($enc)";

	$spill = decode($enc, $spill, FB_CROAK) if $spill;
    }

    if ($mode) {
	binmode($fh, $mode)
	    or croak "Couldn't set binmode of handle opened on '$filename' "
		   . "to '$mode': $!";
    }

    return wantarray ? ($enc, $spill) : $enc;
}

=head2 defuse

    $enc = defuse(FH);

    ($enc, $spill) = defuse(FH);

FH should be a filehandle opened for reading, it will have the relevant encoding
layer pushed onto it be binmode if a BOM is found. Spillage should be Unicode,
not bytes.

Any uncaptured spillage will be silently lost. If the handle is unseekable, use
list context to avoid data loss.

If no BOM is found, the mode will be unaffected.

=cut

sub defuse (*) {
    my $fh = qualify_to_ref(shift, caller);

    my($enc, $spill) = get_encoding_from_filehandle($fh);

    if ($enc) {
	binmode($fh, ":encoding($enc)");
	$spill = decode($enc, $spill, FB_CROAK) if $spill;
    }

    return wantarray ? ($enc, $spill) : $enc;
}

=head2 decode_from_bom

    $unicode_string = decode_from_bom($string, $default, $check)

    ($unicode_string, $encoding) = decode_from_bom($string, $default, $check)

Reads a BOM from the beginning of $string, decodes $string (minus the BOM) and
returns it to you as a perl unicode string.

if $string doesn't have a BOM, $default is used instead.

$check, if supplied, is passed to Encode::decode as the third argument.

If there's no BOM and no default, the original string is returned and encoding
is ''.

See L<Encode>

=cut

sub decode_from_bom ($;$$) {
    my($string, $default, $check) = @_;

    croak "No string" unless defined $string;

    my($enc, $off) = get_encoding_from_bom($string);
    $enc ||= $default;

    my $out;
    if (defined $enc) {
	$out = decode($enc, substr($string, $off), $check);
    }
    else {
	$out = $string;
	$enc = '';
    }

    return wantarray ? ($out, $enc) : $out;
}

=head2 get_encoding_from_filehandle

    $encoding = get_encoding_from_filehandle(HANDLE)

    ($encoding, $spillage) = get_encoding_from_filehandle(HANDLE)

Returns the encoding found in the given filehandle.

The handle should be opened in a non-unicode way (e.g. mode '<:bytes') so that
the BOM can be read in its natural state.

After calling, the handle will be set to read at a point after the BOM (or at
the beginning of the file if no BOM was found)

If called in scalar context, unseekable handles cause a croak().

If called in list context, unseekable handles will be read byte-by-byte and any
spillage will be returned. See get_encoding_from_stream()

=cut

sub get_encoding_from_filehandle (*) {
    my $fh = qualify_to_ref(shift, caller);

    my $enc;
    my $spill = '';
    if (seek($fh, 0, SEEK_SET)) {
	$enc = _get_encoding_seekable($fh);
    }
    elsif (wantarray) {
	($enc, $spill) = _get_encoding_unseekable($fh);
    }
    else {
	croak "Unseekable handle: $!";
    }

    return wantarray ? ($enc, $spill) : $enc;
}

=head2 get_encoding_from_stream

    ($encoding, $spillage) = get_encoding_from_stream(*FH);

Read a BOM from an unrewindable source. This means reading the stream one byte
at a time until either a BOM is found or every possible BOM is ruled out. Any
non-BOM bytes read from the handle will be returned in $spillage.

If a BOM is found and the spillage contains a partial character (judging by the
expected character width for the encoding) more bytes will be read from the
handle to ensure that a complete character is returned.

Spillage is always in bytes, not characters.

This function is less efficient than get_encoding_from_filehandle, but should
work just as well on a seekable handle as on an unseekable one.

=cut

sub get_encoding_from_stream (*) {
    my $fh = qualify_to_ref(shift, caller);

    _get_encoding_unseekable($fh);
}

# internal: 
#
# Return encoding and seek to position after BOM
sub _get_encoding_seekable (*) {
    my $fh = shift;

    defined(read($fh, my $bom, $MAX_BOM_LENGTH))
	or croak "Couldn't read from handle: $!";

    my($enc, $off) = get_encoding_from_bom($bom);

    seek($fh, $off, SEEK_SET) or croak "Couldn't reset read position: $!";

    return $enc;
}

# internal:
#
# Return encoding and non-BOM overspill
sub _get_encoding_unseekable (*) {
    my $fh = shift;

    my $so_far = '';
    for my $c (1 .. $MAX_BOM_LENGTH) {
        # read is supposed to return undef on error, but on some platforms it
        # seems to just return 0 and set $!
        local $!;
        my $status = read $fh, my $byte, 1;
        if (!$status && $!) { croak "Couldn't read byte: $!" }

	$so_far .= $byte;

	# find matching BOMs
	my @possible = grep { $so_far eq substr($_, 0, $c) } keys %bom2enc;

	if (@possible == 1 and my $enc = $bom2enc{$so_far}) {
	    # There's only one match, this must be it
	    return ($enc, '');
	}
	elsif (@possible == 0) {
	    # might need to backtrack one byte
	    my $spill = chop $so_far;

	    if (my $enc = $bom2enc{$so_far}) {
		my $char_length = _get_char_length($enc, $spill);

		read($fh, my $extra, $char_length - length $spill);
		$spill .= $extra;

		return ($enc, $spill);
	    }
	    else {
		# no BOM
		return ('', $so_far . $spill);
	    }
	}
    }
}

=head2 get_encoding_from_bom

    ($encoding, $offset) = get_encoding_from_bom($string)

Returns the encoding and length in bytes of the BOM in $string.

If there is no BOM, an empty string is returned and $offset is zero.

To get the data from the string, the following should work: 

    use Encode;

    my($encoding, $offset) = get_encoding_from_bom($string);

    if ($encoding) {
	$string = decode($encoding, substr($string, $offset))
    }

=cut

sub get_encoding_from_bom ($) {
    my $bom = shift;

    my $encoding = '';
    my $offset = 0;

    if (my($found) = $bom =~ $bom_re) {
	$encoding = $bom2enc{$found};
	$offset = length($found);
    }

    return ($encoding, $offset);
}

# Internal:
# Work out character length for given encoding and spillage byte
sub _get_char_length ($$) {
    my($enc, $byte) = @_;

    if ($enc eq 'UTF-8') {
	if (($byte & 0x80) == 0) {
	    return 1;
	}
	else {
	    my $length = 0;

	    1 while (($byte << $length++) & 0xc0) == 0xc0;

	    return $length;
	}
    }
    elsif ($enc =~ /^UTF-(16|32)/) {
	return $1 / 8;
    }
    else {
	return;
    }
}

=head1 PerlIO::via interface

File::BOM can be used as a PerlIO::via interface.

    open(HANDLE, '<:via(File::BOM)', 'my_file.txt');

    open(HANDLE, '>:encoding(UTF-16LE):via(File::BOM)', 'out_file.txt)
    print "foo\n"; # BOM is written to file here

This method is less prone to errors on non-seekable files as spillage is
incorporated into an internal buffer, but it doesn't give you any information
about the encoding being used, or indeed whether or not a BOM
was present.

There are a few known problems with this interface, especially surrounding
seek() and tell(), please see the BUGS section for more details about this.

=head2 Reading

The via(File::BOM) layer must be added before the handle is read from, otherwise
any BOM will be missed. If there is no BOM, no decoding will be done.

Because of a limitation in PerlIO::via, read() always works on bytes, not characters. BOM decoding will still be done but output will be bytes of UTF-8.

    open(BOM, '<:via(File::BOM)', $file)
    $bytes_read = read(BOM, $buffer, $length);
    $unicode = decode('UTF-8', $buffer, Encode::FB_QUIET);

    # Now $unicode is valid unicode and $buffer contains any left-over bytes

=head2 Writing

Add the via(File::BOM) layer on top of a unicode encoding layer to print a BOM
at the start of the output file. This needs to be done before any data is
written. The BOM is written as part of the first print command on the handle, so
if you don't print anything to the handle, you won't get a BOM.

There is a "Wide character in print" warning generated when the via(File::BOM)
layer doesn't receive utf8 on writing. This glitch was resolved in perl version
5.8.7, but if your perl version is older than that, you'll need to make sure
that the via(File::BOM) layer receives utf8 like this:

    # This works OK
    open(FH, '>:encoding(UTF-16LE):via(File::BOM):utf8', $filename)

    # This generates warnings with older perls
    open(FH, '>:encoding(UTF-16LE):via(File::BOM)', $filename)

=head2 Seeking

Seeking with SEEK_SET results in an offset equal to the length of any detected
BOM being applied to the position parameter. Thus:

    # Seek to end of BOM (not start of file!)
    seek(FILE_BOM_HANDLE, 0, SEEK_SET)

=head2 Telling

In order to work correctly with seek(), tell() also returns a postion adjusted
by the length of the BOM.

=cut

sub PUSHED { bless({offset => 0}, $_[0]) || -1 }

sub UTF8 {
  # There is a bug with this method previous to 5.8.7

    if ($] >= 5.008007) {
	return 1;
    }
    else {
	return 0;
    }
}

sub FILL {
    my($self, $fh) = @_;

    my $line;
    if (not defined $self->{enc}) {
	($self->{enc}, my $spill) = get_encoding_from_filehandle($fh);

	if ($self->{enc} ne '') {
	    binmode($fh, ":encoding($self->{enc})");
	    $line .= decode($self->{enc}, $spill, FB_CROAK) if $spill;

	    $self->{offset} = length $enc2bom{$self->{enc}};
	}

	$line .= <$fh>;
    }
    else {
	$line = <$fh>;
    }

    return $line;
}

sub WRITE {
    my($self, $buf, $fh) = @_;

    if (tell $fh == 0 and not $self->{wrote_bom}) {
	print $fh "\x{feff}";
	$self->{wrote_bom} = 1;
    }

    $buf = decode('UTF-8', $buf, FB_CROAK);

    print $fh $buf;

    return 1;
}

sub FLUSH { 0 }

sub SEEK {
    my $self = shift;

    my($pos, $whence, $fh) = @_;

    if ($whence == SEEK_SET) {
	$pos += $self->{offset};
    }

    if (seek($fh, $pos, $whence)) {
	return 0;
    }
    else {
	return -1;
    }
}

sub TELL {
    my($self, $fh) = @_;

    my $pos = tell $fh;

    if ($pos == -1) {
	return -1;
    }
    else {
	return $pos - $self->{offset};
    }
}

1;

__END__

=head1 SEE ALSO

=over 4

=item * L<Encode>

=item * L<Encode::Unicode>

=item * L<http://www.unicode.org/unicode/faq/utf_bom.html#BOM>

=back

=head1 DIAGNOSTICS

The following exceptions are raised via croak()

=over 4

=item * Couldn't read '<filename>': $!

open_bom() couldn't open the given file for reading

=item * Couldn't set binmode of handle opened on '<filename>' to '<mode>': $!

open_bom() couldn't set the binmode of the handle

=item * No string

decode_from_bom called on an undefined value

=item * Unseekable handle: $!

get_encoding_from_filehandle() or open_bom() called on an unseekable file or handle in scalar context.

=item * Couldn't read from handle: $!

_get_encoding_seekable() couldn't read the handle. This function is called from
get_encoding_from_filehandle(), defuse() and open_bom()

=item * Couldn't reset read position: $!

_get_encoding_seekable couldn't seek to the position after the BOM.

=item * Couldn't read byte: $!

get_encoding_from_stream couldn't read from the handle. This function is called
from get_encoding_from_filehandle() and open_bom() when the handle or file is
unseekable.

=back

=head1 BUGS

Older versions of PerlIO::via have a few problems with writing, see above.

The current version of PerlIO::via has limitations with regard to seek and tell,
currently only line-wise seek and tell are supported by this module. If read()
is used to read partial lines, tell() will still give the position of the end of
the last line read.

Under windows, tell() seems to return erroneously when reading files with unix
line endings.

Under windows, warnings may be generated when using the PerlIO::via interface to
read UTF-16LE and UTF-32LE encoded files. This seems to be a bug in the relevant
encoding(...) layers.

=head1 AUTHOR

Matt Lawrence E<lt>mattlaw@cpan.orgE<gt>

With thanks to Mark Fowler and Steve Purkis for additional tests and advice.

=head1 COPYRIGHT

Copyright 2005 Matt Lawrence, All Rights Reserved.

This program is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut

