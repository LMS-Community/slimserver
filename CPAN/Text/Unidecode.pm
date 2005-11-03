
require 5.006;
package Text::Unidecode;  # Time-stamp: "2001-07-14 02:29:41 MDT"
use utf8;
use strict;
use integer; # vroom vroom!
use vars qw($VERSION @ISA @EXPORT @Char $NULLMAP);
$VERSION = '0.04';
require Exporter;
@ISA = ('Exporter');
@EXPORT = ('unidecode');

BEGIN { *DEBUG = sub () {0} unless defined &DEBUG }

$NULLMAP = [('[?] ') x 0x100];  # for blocks we can't load

#--------------------------------------------------------------------------
{
  my $x = join '', "\x00" .. "\x7F";
  die "the 7-bit purity test fails!" unless $x eq unidecode($x);
}

#--------------------------------------------------------------------------

sub unidecode {
  # Destructive in void context -- in other contexts, nondestructive.

  unless(@_) {
    # Nothing coming in
    return() if wantarray;
    return '';
  }
  @_ = map $_, @_ if defined wantarray;
   # We're in list or scalar context, NOT void context.
   #  So make @_'s items no longer be aliases.
   # Otherwise, let @_ be aliases, and alter in-place.

  foreach my $x (@_) {
    next unless defined $x;    
    $x =~ s~([^\x00-\x7f])~${$Char[ord($1)>>8]||t($1)}[ord($1)&255]~egs;
      # Replace character 0xABCD with $Char[0xAB][0xCD], loading
      #  the table as needed.
  }

  return unless defined wantarray; # void context
  return @_ if wantarray;  # normal list context -- return the copies
  # Else normal scalar context:
  return $_[0] if @_ == 1;
  return join '', @_;      # rarer fallthru: a list in, but a scalar out.
}

sub t {
 # load (and return) a char table for this character
 # this should get called only once per table per session.
 my $bank = ord($_[0]) >> 8;
 return $Char[$bank] if $Char[$bank];
 
        {
           DEBUG and printf "Loading %s::x%02x\n", __PACKAGE__, $bank;
           local $SIG{'__DIE__'};
           eval(sprintf 'require %s::x%02x;', __PACKAGE__, $bank);
        }
        
        # Now see how that fared...
        if(ref($Char[$bank] || '') ne 'ARRAY') {
          DEBUG > 1 and print
            " Loading failed for bank $bank (err $@).  Using null map.\n";
          return $Char[$bank] = $NULLMAP;
        } else {
          DEBUG > 1 and print " Succeeded.\n";
          if(DEBUG) {
            # Sanity-check it:
            my $cb = $Char[$bank];
            unless(@$cb == 256) {
              printf "Block x%02x is of size %d -- chopping to 256\n",
                  scalar(@$cb);
              $#$cb = 255;   # pre-extend the array, or chop it to size.
            }
            for(my $i = 0; $i < 256; ++$i) {
              unless(defined $cb->[$i]) {
                printf "Undef at position %d in block x%02x\n",
                  $i, $bank;
                $cb->[$i] = '';
              }
            }
          }
          return $Char[$bank];
        }
}

#--------------------------------------------------------------------------
1;
__END__

=head1 NAME

Text::Unidecode -- US-ASCII transliterations of Unicode text

=head1 SYNOPSIS

  use utf8;
  use Text::Unidecode;
  print unidecode(
    "\x{5317}\x{4EB0}\n"
     # those are the Chinese characters for Beijing
  );
  
  # That prints: Bei Jing 

=head1 DESCRIPTION

It often happens that you have non-Roman text data in Unicode, but
you can't display it -- usually because you're trying to
show it to a user via an application that doesn't support Unicode,
or because the fonts you need aren't accessible.  You could
represent the Unicode characters as "???????" or
"\15BA\15A0\1610...", but that's nearly useless to the user who
actually wants to read what the text says.

What Text::Unidecode provides is a function, C<unidecode(...)> that
takes Unicode data and tries to represent it in US-ASCII characters
(i.e., the universally displayable characters between 0x00 and
0x7F).  The representation is
almost always an attempt at I<transliteration> -- i.e., conveying,
in Roman letters, the pronunciation expressed by the text in
some other writing system.  (See the example in the synopsis.)

Unidecode's ability to transliterate is limited by two factors:

=over

=item * The amount and quality of data in the original

So if you have Hebrew data
that has no vowel points in it, then Unidecode cannot guess what
vowels should appear in a pronounciation.
S f y hv n vwls n th npt, y wn't gt ny vwls
n th tpt.  (This is a specific application of the general principle
of "Garbage In, Garbage Out".)

=item * Basic limitations in the Unidecode design

Writing a real and clever transliteration algorithm for any single
language usually requires a lot of time, and at least a passable
knowledge of the language involved.  But Unicode text can convey
more languages than I could possibly learn (much less create a
transliterator for) in the entire rest of my lifetime.  So I put
a cap on how intelligent Unidecode could be, by insisting that
it support only context-I<in>sensitive transliteration.  That means
missing the finer details of any given writing system,
while still hopefully being useful.

=back

Unidecode, in other words, is quick and
dirty.  Sometimes the output is not so dirty at all:
Russian and Greek seem to work passably; and
while Thaana (Divehi, AKA Maldivian) is a definitely non-Western
writing system, setting up a mapping from it to Roman letters
seems to work pretty well.  But sometimes the output is I<very
dirty:> Unidecode does quite badly on Japanese and Thai.

If you want a smarter transliteration for a particular language
than Unidecode provides, then you should look for (or write)
a transliteration algorithm specific to that language, and apply
it instead of (or at least before) applying Unidecode.

In other words, Unidecode's
approach is broad (knowing about dozens of writing systems), but
shallow (not being meticulous about any of them).

=head1 FUNCTIONS

Text::Unidecode provides one function, C<unidecode(...)>, which
is exported by default.  It can be used in a variety of calling contexts:

=over

=item C<$out = unidecode($in);> # scalar context

This returns a copy of $in, transliterated.

=item C<$out = unidecode(@in);> # scalar context

This is the same as C<$out = unidecode(join '', @in);>

=item C<@out = unidecode(@in);> # list context

This returns a list consisting of copies of @in, each transliterated.  This
is the same as C<@out = map scalar(unidecode($_)), @in;>

=item C<unidecode(@items);> # void context

=item C<unidecode(@bar, $foo, @baz);> # void context

Each item on input is replaced with its transliteration.  This
is the same as C<for(@bar, $foo, @baz) { $_ = unidecode($_) }>

=back

You should make a minimum of assumptions about the output of
C<unidecode(...)>.  For example, if you assume an all-alphabetic
(Unicode) string passed to C<unidecode(...)> will return an all-alphabetic
string, you're wrong -- some alphabetic Unicode characters are
transliterated as strings containing punctuation (e.g., the
Armenian letter at 0x0539 currently transliterates as C<T`>.

However, these are the assumptions you I<can> make:

=over

=item *

Each character 0x0000 - 0x007F transliterates as itself.  That is,
C<unidecode(...)> is 7-bit pure.

=item *

The output of C<unidecode(...)> always consists entirely of US-ASCII
characters -- i.e., characters 0x0000 - 0x007F.

=item *

All Unicode characters translate to a sequence of (any number of)
characters that are newline ("\n") or in the range 0x0020-0x007E.  That
is, no Unicode character translates to "\x01", for example.  (Altho if
you have a "\x01" on input, you'll get a "\x01" in output.)

=item *

Yes, some transliterations produce a "\n" -- but just a few, and only
with good reason.  Note that the value of newline ("\n") varies
from platform to platform -- see L<perlport/perlport>.

=item *

Some Unicode characters may transliterate to nothing (i.e., empty string).

=item *

Very many Unicode characters transliterate to multi-character sequences.
E.g., Han character 0x5317 transliterates as the four-character string
"Bei ".

=item *

Within these constraints, I may change the transliteration of characters
in future versions.  For example, if someone convinces me that
the Armenian letter at 0x0539, currently transliterated as "T`", would
be better transliterated as "D", I may well make that change.

=back

=head1 DESIGN GOALS AND CONSTRAINTS

Text::Unidecode is meant to be a transliterator-of-last resort,
to be used once you've decided that you can't just display the
Unicode data as is, and once you've decided you don't have a
more clever, language-specific transliterator available.  It
transliterates context-insensitively -- that is, a given character is
replaced with the same US-ASCII (7-bit ASCII) character or characters,
no matter what the surrounding character are.

The main reason I'm making Text::Unidecode work with only
context-insensitive substitution is that it's fast, dumb, and
straightforward enough to be feasable.  It doesn't tax my
(quite limited) knowledge of world languages.  It doesn't require
me writing a hundred lines of code to get the Thai syllabification
right (and never knowing whether I've gotten it wrong, because I
don't know Thai), or spending a year trying to get Text::Unidecode
to use the ChaSen algorithm for Japanese, or trying to write heuristics
for telling the difference between Japanese, Chinese, or Korean, so
it knows how to transliterate any given Uni-Han glyph.  And
moreover, context-insensitive substitution is still mostly useful,
but still clearly couldn't be mistaken for authoritative.

Text::Unidecode is an example of the 80/20 rule in
action -- you get 80% of the usefulness using just 20% of a
"real" solution.

A "real" approach to transliteration for any given language can
involve such increasingly tricky contextual factors as these

=over

=item The previous / preceding character(s)

What a given symbol "X" means, could
depend on whether it's followed by a consonant, or by vowel, or
by some diacritic character.

=item Syllables

A character "X" at end of a syllable could mean something
different from when it's at the start -- which is especially problematic
when the language involved doesn't explicitly mark where one syllable
stops and the next starts.

=item Parts of speech

What "X" sounds like at the end of a word,
depends on whether that word is a noun, or a verb, or what.

=item Meaning

By semantic context, you can tell that this ideogram "X" means "shoe"
(pronounced one way) and not "time" (pronounced another),
and that's how you know to transliterate it one way instead of the other.

=item Origin of the word

"X" means one thing in loanwords and/or placenames (and
derivatives thereof), and another in native words.

=item "It's just that way"

"X" normally makes
the /X/ sound, except for this list of seventy exceptions (and words based
on them, sometimes indirectly).  Or: you never can tell which of the three
ways to pronounce "X" this word actually uses; you just have to know
which it is, so keep a dictionary on hand!

=item Language

The character "X" is actually used in several different languages, and you
have to figure out which you're looking at before you can determine how
to transliterate it.

=back

Out of a desire to avoid being mired in I<any> of these kinds of
contextual factors, I chose to exclude I<all of them> and just stick
with context-insensitive replacement.

=head1 TODO

Things that need tending to are detailed in the TODO.txt file, included
in this distribution.  Normal installs probably don't leave the TODO.txt
lying around, but if nothing else, you can see it at
http://search.cpan.org/search?dist=Text::Unidecode

=head1 MOTTO

The Text::Unidecode motto is:

  It's better than nothing!

...in both meanings: 1) seeing the output of C<unidecode(...)> is
better than just having all font-unavailable Unicode characters
replaced with "?"'s, or rendered as gibberish; and 2) it's the
worst, i.e., there's nothing that Text::Unidecode's algorithm is
better than.

=head1 CAVEATS

If you get really implausible nonsense out of C<unidecode(...)>, make
sure that the input data really is a utf8 string.  See
L<perlunicode/perlunicode>.

=head1 THANKS

Thanks to Harald Tveit Alvestrand,
Abhijit Menon-Sen, and Mark-Jason Dominus.

=head1 SEE ALSO

Unicode Consortium: http://www.unicode.org/

Geoffrey Sampson.  1990.  I<Writing Systems: A Linguistic Introduction.>
ISBN: 0804717567

Randall K. Barry (editor).  1997.  I<ALA-LC Romanization Tables:
Transliteration Schemes for Non-Roman Scripts.>
ISBN: 0844409405
[ALA is the American Library Association; LC is the Library of
Congress.]

Rupert Snell.  2000.  I<Beginner's Hindi Script (Teach Yourself
Books).>  ISBN: 0658009109

=head1 COPYRIGHT AND DISCLAIMERS

Copyright (c) 2001 Sean M. Burke. All rights reserved.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

This program is distributed in the hope that it will be useful, but
without any warranty; without even the implied warranty of
merchantability or fitness for a particular purpose.

Much of Text::Unidecode's internal data is based on data from The
Unicode Consortium, with which I am unafiliated.

=head1 AUTHOR

Sean M. Burke C<sburke@cpan.org>

=cut

#################### SCOOBIE SNACK ####################

Lest there be any REMAINING doubt that the Unicode Consortium has
a sense of humor, the CDROM that comes with /The Unicode Standard,
Version 3.0/ book, has an audio track of the Unicode anthem [!].
The lyrics are:

	Unicode, Oh Unicode!
	--------------------

	Oh, beautiful for Uni-Han,
	for spacious User Zone!
	For rampant scripts of India
	and polar Nunavut!

	  Chorus:
		Unicode, Oh Unicode!
		May all your code points shine forever
		and your beacon light the world!

	Oh, marvelous for sixteen bits,
	for precious surrogates!
	For Bi-Di algorithm dear
	and stalwart I-P-A!

	Oh, glorious for Hangul fair,
	for symbols mathematical!
	For myriad exotic scripts
	and punctuation we adore!

# End.

