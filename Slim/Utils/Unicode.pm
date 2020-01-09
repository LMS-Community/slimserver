package Slim::Utils::Unicode;

# Logitech Media Server Copyright 2003-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

=head1 NAME

Slim::Utils::Unicode

=head1 SYNOPSIS

my $utf8 = Slim::Utils::Unicode::utf8decode($string, 'iso-8859-1');

my $enc  = Slim::Utils::Unicode::encodingFromString($string);

=head1 DESCRIPTION

This module is a wrapper around Encode:: functions, and comprises character
set guessing, encoding, decoding and translation. 

Most of these functions are non-ops on perl < 5.8.x

The recompose & decompose parts have been modified from Simon's defunct
Unicode::Decompose mdoule.

Unicode characters that somehow become decomposed. Sometimes we'll see a URI
encoding such as: o%CC%88 - which is an o with diaeresis. The correct
(composed) version of this should be %C3%B6

=head1 METHODS

=cut

use strict;
use Fcntl qw(:seek);
use File::BOM;
use POSIX qw(LC_CTYPE LC_TIME);
use Text::Unidecode;

use Slim::Utils::Log;

BEGIN {
	my $hasEDD;

	sub hasEDD {
		return $hasEDD if defined $hasEDD;
	
		$hasEDD = 0;
		eval {
			require Encode::Detect::Detector;
			$hasEDD = 1;
		};
	
		return $hasEDD;
	}
}

sub _printPath {
	use bytes;
	my $path = shift;
	return 'undef' unless defined $path;
	my $s = utf8::is_utf8($path) ? 'ON:' : 'OFF:';
	
	for (my $i = 0; $i < length($path); $i++) {
		my $c = substr($path, $i, 1);
		if (ord($c) > 127) {
			$s .= sprintf("#%02x", ord($c));
		} else {
			$s .= $c;
		}
	}
	return $s;
}


# Find out what code page we're in, so we can properly translate file/directory encodings.
our (
	$lc_ctype, $lc_time, $comb_re_bits, $bomRE, $FB_QUIET, $FB_CROAK,
);

{
	# We implement a decode() & encode(), so don't import those.
	require Encode;
	require Encode::Guess;
	
	$FB_QUIET = Encode::FB_QUIET();
	$FB_CROAK = Encode::FB_CROAK();

	$bomRE = qr/^(?:
		\xef\xbb\xbf     |
		\xfe\xff         |
		\xff\xfe         |
		\x00\x00\xfe\xff |
		\xff\xfe\x00\x00
	)/x;

	($lc_ctype, $lc_time) = Slim::Utils::OSDetect->getOS->localeDetails();

	# Setup Encode::Guess	 
	$Encode::Guess::NoUTFAutoGuess = 1;	 
	 	 
	# Setup suspects for Encode::Guess based on the locale - we might also	 
	# want to use our own Language pref?	 
	if ($lc_ctype ne 'utf8') {	 

		Encode::Guess->add_suspects($lc_ctype);	 
	}
	
	# Regex for determining if a string contains combining marks and needs to be decomposed
	# Combining Diacritical Marks + Combining Diacritical Marks Supplement
	$comb_re_bits = join "|", map { latin1toUTF8(chr($_)) } (0x300..0x36F, 0x1DC0..0x1DFF);
}

=head2 currentLocale()

Returns the current system locale. 

On Windows, this is the current code page.

On OS X, it's always utf-8.

On *nix, this is LC_CTYPE. 

=cut

sub currentLocale {
	return $lc_ctype;
}

=head2 utf8decode( $string )

Decode the current string to UTF-8

Return the newly decoded string.

=cut

sub utf8decode {
	return utf8decode_guess(@_);
}

=head2 utf8decode_guess( $string, @encodings )

Decode the current string to UTF-8, using @encodings to guess the encoding of
the string if it is not known.

Return the newly decoded string.

=cut

sub utf8decode_guess {
	my $string = shift;
	my @preferedEncodings = @_;

	# Bail early if it's just ascii
	if (looks_like_ascii($string) || utf8::is_utf8($string)) {
		return $string;
	}
	
	if ( @preferedEncodings ) {
		for my $encoding (@preferedEncodings) {

			my $decoded = eval { Encode::decode($encoding, $string, $FB_CROAK) };

			if ( !$@ && utf8::is_utf8($decoded) ) {
				return $decoded;
			}
		}
	}

	my $charset = encodingFromString($string);

	if ( $charset && $charset ne 'raw') {
		my $encoding;

		if (($encoding = Encode::find_encoding($charset)) && ref $encoding) {

			return $encoding->decode($string, $FB_QUIET);
		}
	}

	return $string;
}

=head2 utf8decode_locale( $string )

Decode the current string to UTF-8, using the current locale as the string's encoding.

This is a no-op if the string is already encoded as UTF-8

Return the newly decoded string.

=cut

sub utf8decode_locale {
	my $string = shift;

	if ($string && !utf8::is_utf8($string)) {

		my $decoded = eval { Encode::decode($lc_ctype, $string, $FB_CROAK) };
		$string = ($@) ? $string : $decoded;
	}

	return $string;
}

=head2 utf8encode( $string, $encoding )

Encode the current UTF-8 string to the passed encoding.

Return the newly encoded string.

=cut

sub utf8encode {
	my $string   = shift;
	my $encoding = shift || 'utf8';

	if ($string && $encoding ne 'utf8') {

		utf8::decode($string) unless utf8::is_utf8($string);
		$string = Encode::encode($encoding, $string, $FB_QUIET);

	} elsif ($string) {

		utf8::encode($string) if utf8::is_utf8($string);
	}

	return $string;
}

=head2 utf8encode_locale( $string )

Encode the current UTF-8 string to the current locale.

Return the newly encoded string.

=cut

sub utf8encode_locale {

	return utf8encode($_[0], $lc_ctype);
}

=head2 encode_locale( $string )

Encode the current (possibly Unicode) character-string to the current locale.
This guarantees that the internal utf-8 flag will be unset, even if it was
erroneously set for a string that contains only ASCII (as will be the case
with strings from preferences because of the behavior of YAML::Syck).

It will not handle the case where the string might actually contain UTF-8
but has not been decoded. Use utf8encode_local() in that case.

Return the newly encoded string.

=cut

sub encode_locale {
	my $string = shift;
	
	return Encode::encode($lc_ctype, $string, $FB_QUIET) if utf8::is_utf8($string);
	return $string;
}

=head2 utf8off( $string )

Alias for Encode::encode('utf8', $string)

Returns the new string.

=cut

sub utf8off {
	utf8::encode($_[0]) if utf8::is_utf8($_[0]);
	return $_[0];
}

=head2 utf8on( $string )

Alias for Encode::decode('utf8', $string)

Returns the new string.

=cut

sub utf8on {
	utf8::decode($_[0]) unless utf8::is_utf8($_[0]);
	return $_[0];
}

=head2 looks_like_ascii( $string )

Returns true if the passed string is US-ASCII

Returns false otherwise.

=cut

sub looks_like_ascii {
	use bytes;

	return 1 if !$_[0];
	return 1 if $_[0] !~ /[^\x00-\x7F]/;
	return 0;
}

=head2 looks_like_latin1( $string )

Returns true if the passed string is ISO-8859-1

Returns false otherwise.

=cut

sub looks_like_latin1 {
	use bytes;

	return 1 if $_[0] !~ /[^\x00-\x7F\xA0-\xFF]/;
	return 0;
}

=head2 looks_like_cp1252( $string )

Returns true if the passed string is Windows-1252

Returns false otherwise.

=cut

sub looks_like_cp1252 {
	use bytes;

	return 1 if $_[0] !~ /[^\x00-\xFF]/;
	return 0;
}

=head2 looks_like_utf8( $string )

Returns true if the passed string is UTF-8

Returns false otherwise.

=cut

sub looks_like_utf8 {
	# From http://keithdevens.com/weblog/archive/2004/Jun/29/UTF-8.regex
	# with a fix for the ASCII part
	return 1 if $_[0] =~ /^(?:
	     [\x00-\x7E]                        # ASCII
	   | [\xC2-\xDF][\x80-\xBF]             # non-overlong 2-byte
	   |  \xE0[\xA0-\xBF][\x80-\xBF]        # excluding overlongs
	   | [\xE1-\xEC\xEE\xEF][\x80-\xBF]{2}  # straight 3-byte
	   |  \xED[\x80-\x9F][\x80-\xBF]        # excluding surrogates
	   |  \xF0[\x90-\xBF][\x80-\xBF]{2}     # planes 1-3
	   | [\xF1-\xF3][\x80-\xBF]{3}          # planes 4-15
	   |  \xF4[\x80-\x8F][\x80-\xBF]{2}     # plane 16
	)*$/x;

	return 0;
}

=head2 looks_like_utf16( $string )

Returns true if the passed string is UTF-16

Returns false otherwise.

=cut

sub looks_like_utf16 {
	use bytes;

	return 1 if $_[0] =~ /^(?:\xfe\xff|\xff\xfe)/;
	return 0;
}

=head2 looks_like_utf32( $string )

Returns true if the passed string is UTF-32

Returns false otherwise.

=cut

sub looks_like_utf32 {
	use bytes;

	return 1 if $_[0] =~ /^(?:\x00\x00\xfe\xff|\xff\xfe\x00\x00)/;
	return 0;
}

=head2 latin1toUTF8( $string )

Returns a UTF-8 encoded string from a ISO-8859-1 string.

=cut

sub latin1toUTF8 {
	my $data = shift;

	$data = eval { Encode::encode('utf8', $data, $FB_QUIET) } || $data;

	return $data;
}

=head2 utf8toLatin1( $string )

Returns a ISO-8859-1 string from a UTF-8 encoded string.

=cut

sub utf8toLatin1 {
	my $data = shift;

	$data = eval { Encode::encode('iso-8859-1', $data, $FB_QUIET) } || $data;

	return $data;
}

=head2 utf8toLatin1Transliterate( $string )

Turn a UTF-8 string into it's US-ASCII equivalent.

See L<Text::Unidecode>.

=cut

sub utf8toLatin1Transliterate {
	my $data = shift;

	return utf8toLatin1( Text::Unidecode::unidecode($data) );
}

=head2 encodingFromString( $string, $ignore_utf8_flag )

Use a best guess effort to return the encoding of the passed string.

Returns 'raw' if not: ascii, utf-32, utf-16, utf-8, iso-8859-1 or cp1252

=cut

sub encodingFromString {
	my $string = shift;
	
	return 'utf8' if !$_[0] && utf8::is_utf8($string);

	# Don't copy a potentially large string - just read it from the stack.
	if (looks_like_ascii($string)) {

		return 'ascii';

	} elsif (looks_like_utf32($string)) {

		return 'utf-32';

	} elsif (looks_like_utf16($string)) {
	
		return 'utf-16';

	} elsif (looks_like_utf8($string)) {
	
		return 'utf8';
		
	} elsif (looks_like_latin1($string)) {
	
		return 'iso-8859-1';

	} elsif (looks_like_cp1252($string)) {
	
		return 'cp1252';
	}
	
	if ( !hasEDD() ) {
		return 'raw';
	}

	# Check Encode::Detect::Detector before ISO-8859-1, as it can find
	# overlapping charsets.
	my $charset = Encode::Detect::Detector::detect($string);

#	# Encode::Detect::Detector is mislead to to return Big5 with some characters
#	# In these cases Encode::Guess does a better job... (bug 9553)
	if ($charset =~ /^(?:big5|euc-jp|euc-kr|euc-cn|euc-tw)$/i) {

		eval {
			$charset = Encode::Guess::guess_encoding($string);
			$charset = $charset->name;
		};

		# Bug 10671: sometimes Encode::Guess returns ambiguous results like "ascii or utf8"
		if ($@) {
			logError($@);

			if ($charset =~ /utf8/i) {
				$charset = 'utf8';
				logError("Falling back to: $charset");
			}
			else {
				$charset = '';
			}
		}
	}

	$charset =~ s/utf-8/utf8/i;

	if ($charset) {

		return lc($charset);
	}



	return 'raw';
}

=head2 encodingFromFileHandle( $fh )

Use a best guess effort to return the encoding of the passed file handle.

Returns 'raw' if not: ascii, utf-32, utf-16, utf-8, iso-8859-1 or cp1252

=cut

sub encodingFromFileHandle {
	my $fh = shift;

	# If we didn't get a filehandle, not much we can do.
	if (!ref($fh) || !$fh->can('seek')) {

		logBacktrace("Didn't get a filehandle from caller!");
		return;
	}

	local $/ = undef;

	# Save the old position (if any)
	# And find the file size.
	#
	# These must be seek() and not sysseek(), as File::BOM uses seek(),
	# and they'll get confused otherwise.
	my $maxsz = 4096;
	my $pos   = tell($fh);
	my $size  = seek($fh, 0, SEEK_END) ? tell($fh) : $maxsz;

	# Set a limit on the size to read.
	if ($size > $maxsz || $size < 0) {
		$size = $maxsz;
	}

	# Don't do any translation.
	binmode($fh, ":raw");

	# Try to find a BOM on the file - otherwise check the string
	#
	# Although get_encoding_from_filehandle tries to determine if
	# the handle is seekable or not - the Protocol handlers don't
	# implement a seek() method, and even if they did, File::BOM
	# internally would try to read(), which doesn't mix with
	# sysread(). So skip those m3u files entirely.
	my $enc = '';

	# Explitly check for IO::String - as it does have a seek() method!
	if (ref($fh) && ref($fh) ne 'IO::String' && $fh->can('seek')) {
		$enc = File::BOM::get_encoding_from_filehandle($fh);
	}

	# File::BOM got something - let's get out of here.
	return $enc if $enc;

	# Seek to the beginning of the file.
	seek($fh, 0, SEEK_SET);

	#
	read($fh, my $string, $size);

	# Seek back to where we started.
	seek($fh, $pos, SEEK_SET);

	return encodingFromString($string);
}

=head2 encodingFromFile( $fh )

Use a best guess effort to return the encoding of the passed file name or file handle.

Returns 'raw' if not: ascii, utf-32, utf-16, utf-8, iso-8859-1 or cp1252

=cut

sub encodingFromFile {
	my $file = shift;

	my $encoding = $lc_ctype;

	if (ref($file) && $file->can('seek')) {

		$encoding = encodingFromFileHandle($file);

	} elsif (-r $file) {

		my $fh = FileHandle->new;

		$fh->open($file) or do {

			logError("Couldn't open file: [$file] : $!");

			return $encoding;
		};

		$encoding = encodingFromFileHandle($fh);

		$fh->close();

	} else {

		logBacktrace("Not a filename or filehandle: [$file]");
	}

	return $encoding;
}

=head2 recomposeUnicode( $string )

Recompose a decomposed UTF-8 string.

=cut

sub recomposeUnicode {
	my $string = shift;
	
	require Slim::Utils::Unicode::Recompose;

	$string =~ s/$Slim::Utils::Unicode::Recompose::regex/$Slim::Utils::Unicode::Recompose::table{$1}/go;

	return $string;
}

=head2 hasCombiningMarks( $string )

Returns 1 if the string contains any characters that are combining marks.

=cut

sub hasCombiningMarks {
	return $_[0] =~ /(?:$comb_re_bits)/o ? 1 : 0;
}

=head2 stripBOM( $string )

Removes UTF-8, UTF-16 & UTF-32 Byte Order Marks and returns the string.

=cut

sub stripBOM {
	my $string = shift;

	use bytes;

	$string =~ s/$bomRE//;

	return $string;
}

=head2 decode( $encoding, $string )

An alias for L<Encode::decode()>

=cut

*decode = \&Encode::decode;

=head2 encode( $encoding, $string )

An alias for L<Encode::encode()>

=cut

*encode = \&Encode::encode;

=head2 from_to( $string, $from_encoding, $to_encoding )

=cut

sub from_to {
	my $string = shift;
	my $from_encoding = shift;
	my $to_encoding = shift;
	
	return $string if $from_encoding eq $to_encoding;
	
	# wrap transformation in eval as utf8 -> iso8859-1 could break on wide characters
	eval {
		$string = decode($from_encoding, $string);
		$string = encode($to_encoding, $string);
	};
	
	if ($@) {
		Slim::Utils::Log->logger('server')->warn("Could not convert from $from_encoding to $to_encoding: $string ($@)");
	}
	
	return $string;
}

=head1 SEE ALSO

L<Encode>, L<Text::Unidecode>, L<File::BOM>

=cut

1;

__END__
