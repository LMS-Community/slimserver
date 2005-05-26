package Test::utf8;

use 5.007003;

use strict;
use warnings;

use Encode;
use charnames ':full';

use vars qw(@ISA @EXPORT $VERSION %allowed $valid_utf8_regexp);
$VERSION = "0.02";

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(is_valid_string is_dodgy_utf8 is_sane_utf8
	      is_within_ascii is_within_latin1 is_within_latin_1
              is_flagged_utf8 isnt_flagged_utf8);

# A Regexp string to match valid UTF8 bytes
# this info comes from page 78 of "The Unicode Standard 4.0"
# published by the Unicode Consortium
$valid_utf8_regexp = <<'.' ;
        [\x{00}-\x{7f}]
      | [\x{c2}-\x{df}][\x{80}-\x{bf}]
      |         \x{e0} [\x{a0}-\x{bf}][\x{80}-\x{bf}]
      | [\x{e1}-\x{ec}][\x{80}-\x{bf}][\x{80}-\x{bf}]
      |         \x{ed} [\x{80}-\x{9f}][\x{80}-\x{bf}]
      | [\x{ee}-\x{ef}][\x{80}-\x{bf}][\x{80}-\x{bf}]
      |         \x{f0} [\x{90}-\x{bf}][\x{80}-\x{bf}]
      | [\x{f1}-\x{f3}][\x{80}-\x{bf}][\x{80}-\x{bf}][\x{80}-\x{bf}]
      |         \x{f4} [\x{80}-\x{8f}][\x{80}-\x{bf}][\x{80}-\x{bf}]
.

=head1 NAME

Test::utf8 - handy utf8 tests

=head1 SYNOPSIS

  is_valid_string($string);   # check the string is valid
  is_sane_utf8($string);      # check not double encoded
  is_flagged_utf8($string);   # has utf8 flag set
  is_within_latin_1($string); # but only has latin_1 chars in it

=head1 DESCRIPTION

This module is a collection of tests that's useful when dealing
with utf8 strings in Perl.

=head2 Validity

These two tests check if a string is valid, and if you've probably
made a mistake with your string

=over

=item is_valid_string($string, $testname)

This passes and returns true true if and only if the scalar isn't a
invalid string; In short, it checks that the utf8 flag hasn't been set
for a string that isn't a valid utf8 encoding.

=cut

sub is_valid_string($;$)
{
  my $string = shift;
  my $name = shift || "valid string test";

  # check we're a utf8 string - if not, we pass.
  unless (Encode::is_utf8($string)) { return 1 }

  # work out at what byte (if any) we have an invalid byte sequence
  # and return the correct test result
  my $pos = _invalid_sequence_at_byte($string);

  return !defined($pos);
}

sub _invalid_sequence_at_byte($)
{
  my $string = shift;

  # examine the bytes that make up the string (not the chars)
  # by turning off the utf8 flag (no, use bytes doens't
  # work, we're dealing with a regexp)
  Encode::_utf8_off($string);

  # work out the index of the first non matching byte
  my $result = $string =~ m/^($valid_utf8_regexp)*/ogx;

  # if we matched all the string return the empty list
  my $pos = pos $string || 0;
  return if $pos == length($string);

  # otherwise return the position we found
  return $pos
}

=item is_sane_utf8($string, $name)

This test fails if the string contains something that looks like it
might be dodgy utf8, i.e. containing something that looks like the
multi-byte sequence for a latin-1 character but perl hasn't been
instructed to treat as such.  Strings that are not utf8 always
automatically pass.

Some examples may help:

  # This will pass as it's a normal latin-1 string
  is_sane_utf8("Hello L\x{e9}eon");

  # this will fail because the \x{c3}\x{a9} looks like the
  # utf8 byte sequence for e-acute
  my $string = "Hello L\x{c3}\x{a9}on";
  is_sane_utf8($string);

  # this will pass because the utf8 is correctly interpreted as utf8
  Encode::_utf8_on($string)
  is_sane_utf8($string);

Obviously this isn't a hundred percent reliable.  The edge case where
this will fail is where you have C<\x{c2}> (which is "LATIN CAPITAL
LETTER WITH CIRCUMFLEX") or C<\x{c3}> (which is "LATIN CAPITAL LETTER
WITH TILDE") followed by one of the latin-1 punctuation symbols.

  # a capital letter A with tilde surrounded by smart quotes
  # this will fail because it'll see the "\x{c2}\x{94}" and think
  # it's actually the utf8 sequence for the end smart quote
  is_sane_utf8("\x{93}\x{c2}\x{94}");

However, since this hardly comes up this test is reasonably reliable
in most cases.  Still, care should be applied in cases where dynamic
data is placed next to latin-1 punctuation to avoid false negatives.

There exists two situations to cause this test to fail; The string
contains utf8 byte sequences and the string hasn't been flagged as
utf8 (this normally means that you got it from an external source like
a C library; When Perl needs to store a string internally as utf8 it
does it's own encoding and flagging transparently) or a utf8 flagged
string contains byte sequences that when translated to characters
themselves look like a utf8 byte sequence.  The test diagnostics tells
you which is the case.

=cut

# build my regular expression out of the latin-1 bytes
# NOTE: This won't work if our locale is nonstandard will it?
my $re_bit = join "|", map { Encode::encode("utf8",chr($_)) } (127..255);

#binmode STDERR, ":utf8";
#print STDERR $re_bit;

sub is_sane_utf8($;$)
{
  my $string = shift;
  my $name   = shift || "sane utf8";

  # regexp in scalar context with 'g', meaning this loop will run for
  # each match.  Should only have to run it once, but will redo if
  # the failing case turns out to be allowed in %allowed.
  #use bytes;
  while ($string =~ /($re_bit)/o)
  {
    # work out what the double encoded string was
    my $bytes = $1;

    my $index = $+[0] - length($bytes);
    my $codes = join '', map { sprintf '<%00x>', ord($_) } split //, $bytes;

    # what charecter does that represent?
    my $char = Encode::decode("utf8",$bytes);
    my $ord  = ord($char);
    my $hex  = sprintf '%00x', $ord;
    $char = charnames::viacode($ord);

    # print out diagnostic messages
    #warn(qq{Found dodgy chars "$codes" at char $index\n});
    #if (Encode::is_utf8($string))
    #  { warn("Chars in utf8 string look like utf8 byte sequence.") }
    #else
    #  { warn("String not flagged as utf8...was it meant to be?\n") }
    #warn("Probably originally a $char char - codepoint $ord (dec), $hex (hex)\n");

    return 0;
  }

  # got this far, must have passed.
  return 1;
}

# historic name of method; deprecated
sub is_dodgy_utf8
{
  # report errors not here but further up the calling stack
  local $Test::Builder::Level = $Test::Builder::Level + 1;

  # call without prototype with all args
  &is_sane_utf8(@_);
}

=back

=head2 Checking the Range of Characters in a String

These routines allow you to check the range of characters in a string.
Note that these routines are blind to the actual encoding perl
internally uses to store the characters, they just check if the
string contains only characters that can be represented in the named
encoding.

=over

=item is_within_ascii

Tests that a string only contains characters that are in the ASCII
charecter set.

=cut

sub is_within_ascii($;$)
{
  my $string = shift;
  my $name   = shift || "within ascii";

  # look for anything that isn't ascii or pass
  $string =~ /([^\x{00}-\x{7f}])/ or return pass($name);

  # explain why we failed
  my $dec = ord($1);
  my $hex = sprintf '%02x', $dec;

  warn("Char $+[0] not ASCII (it's $dec dec / $hex hex)");

  return 0;
}

=item is_within_latin_1

Tests that a string only contains characters that are in latin-1.

=cut

sub is_within_latin_1($;$)
{
  my $string = shift;
  my $name   = shift || "within latin-1";

  # look for anything that isn't ascii or pass
  $string =~ /([^\x{00}-\x{ff}])/ or return 1;

  # explain why we failed
  my $dec = ord($1);
  my $hex = sprintf '%x', $dec;

  warn("Char $+[0] not Latin-1 (it's $dec dec / $hex hex)");

  return 0;
}

sub is_within_latin1
{
  # report errors not here but further up the calling stack
  local $Test::Builder::Level = $Test::Builder::Level + 1;

  # call without prototype with all args
  &is_within_latin_1(@_);
}

=back

=head2 Simple utf8 Flag Tests

Simply check if a scalar is or isn't flagged as utf8 by perl's
internals.

=over

=item is_flagged_utf8($string, $name)

Passes if the string is flagged by perl's internals as utf8, fails if
it's not.

=cut

sub is_flagged_utf8
{
  my $string = shift;
  my $name = shift || "flagged as utf8";
  return Encode::is_utf8($string);
}

=item isnt_flagged_utf8($string,$name)

The opposite of C<is_flagged_utf8>, passes if and only if the string
isn't flagged as utf8 by perl's internals.

Note: you can refer to this function as C<isn't_flagged_utf8> if you
really want to.

=cut

sub isnt_flagged_utf8($;$)
{
  my $string = shift;
  my $name   = shift || "not flagged as utf8";
  return !Encode::is_utf8($string);
}

sub isn::t_flagged_utf8($;$)
{
  my $string = shift;
  my $name   = shift || "not flagged as utf8";
  return !Encode::is_utf8($string);
}

=back

=head1 AUTHOR

  Copyright Mark Fowler 2004.  All rights reserved.

  This program is free software; you can redistribute it
  and/or modify it under the same terms as Perl itself.

=head1 BUGS

None known.  Please report any to me via the CPAN RT system.  See
http://rt.cpan.org/ for more details.

=head1 SEE ALSO

L<Test::DoubleEncodedEntities> for testing for double encoded HTML
entities.

=cut

##########

# shortcuts for Test::Builder.

1;
