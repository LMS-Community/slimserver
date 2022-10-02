=head1 NAME

common::sense - save a tree AND a kitten, use common::sense!

=head1 SYNOPSIS

 use common::sense;

 # roughly the same as, with much lower memory usage:
 #
 # use strict qw(vars subs);
 # use feature qw(say state switch);
 # no warnings;
 # use warnings qw(FATAL closed threads internal debugging pack substr malloc
 #                 unopened portable prototype inplace io pipe unpack regexp
 #                 deprecated exiting glob digit printf utf8 layer
 #                 reserved parenthesis taint closure semicolon);
 # no warnings qw(exec newline);

=head1 DESCRIPTION

This module implements some sane defaults for Perl programs, as defined by
two typical (or not so typical - use your common sense) specimens of Perl
coders.

=over 4

=item use strict qw(subs vars)

Using C<use strict> is definitely common sense, but C<use strict
'refs'> definitely overshoots its usefulness. After almost two
decades of Perl hacking, we decided that it does more harm than being
useful. Specifically, constructs like these:

   @{ $var->[0] }

Must be written like this (or similarly), when C<use strict 'refs'> is in
scope, and C<$var> can legally be C<undef>:

   @{ $var->[0] || [] }

This is annoying, and doesn't shield against obvious mistakes such as
using C<"">, so one would even have to write (at least for the time
being):

   @{ defined $var->[0] ? $var->[0] :  [] }

... which nobody with a bit of common sense would consider
writing.

Curiously enough, sometimes perl is not so strict, as this works even with
C<use strict> in scope:

   for (@{ $var->[0] }) { ...

If that isn't hypocrisy! And all that from a mere program!


=item use feature qw(say state given)

We found it annoying that we always have to enable extra features. If
something breaks because it didn't anticipate future changes, so be
it. 5.10 broke almost all our XS modules and nobody cared either (or at
least I know of nobody who really complained about gratuitous changes -
as opposed to bugs).

Few modules that are not actively maintained work with newer versions of
Perl, regardless of use feature or not, so a new major perl release means
changes to many modules - new keywords are just the tip of the iceberg.

If your code isn't alive, it's dead, Jim - be an active maintainer.


=item no warnings, but a lot of new errors

Ah, the dreaded warnings. Even worse, the horribly dreaded C<-w>
switch: Even though we don't care if other people use warnings (and
certainly there are useful ones), a lot of warnings simply go against the
spirit of Perl.

Most prominently, the warnings related to C<undef>. There is nothing wrong
with C<undef>: it has well-defined semantics, it is useful, and spitting
out warnings you never asked for is just evil.

The result was that every one of our modules did C<no warnings> in the
past, to avoid somebody accidentally using and forcing his bad standards
on our code. Of course, this switched off all warnings, even the useful
ones. Not a good situation. Really, the C<-w> switch should only enable
warnings for the main program only.

Funnily enough, L<perllexwarn> explicitly mentions C<-w> (and not in a
favourable way, calling it outright "wrong"), but standard utilities, such
as L<prove>, or MakeMaker when running C<make test>, still enable them
blindly.

For version 2 of common::sense, we finally sat down a few hours and went
through I<every single warning message>, identifiying - according to
common sense - all the useful ones.

This resulted in the rather impressive list in the SYNOPSIS. When we
weren't sure, we didn't include the warning, so the list might grow in
the future (we might have made a mistake, too, so the list might shrink
as well).

Note the presence of C<FATAL> in the list: we do not think that the
conditions caught by these warnings are worthy of a warning, we I<insist>
that they are worthy of I<stopping> your program, I<instantly>. They are
I<bugs>!

Therefore we consider C<common::sense> to be much stricter than C<use
warnings>, which is good if you are into strict things (we are not,
actually, but these things tend to be subjective).

After deciding on the list, we ran the module against all of our code that
uses C<common::sense> (that is almost all of our code), and found only one
occurence where one of them caused a problem: one of elmex's (unreleased)
modules contained:

   $fmt =~ s/([^\s\[]*)\[( [^\]]* )\]/\x0$1\x1$2\x0/xgo;

We quickly agreed that indeed the code should be changed, even though it
happened to do the right thing when the warning was switched off.


=item mucho reduced memory usage

Just using all those pragmas mentioned in the SYNOPSIS together wastes
<blink>I<< B<776> kilobytes >></blink> of precious memory in my perl, for
I<every single perl process using our code>, which on our machines, is a
lot. In comparison, this module only uses I<< B<four> >> kilobytes (I even
had to write it out so it looks like more) of memory on the same platform.

The money/time/effort/electricity invested in these gigabytes (probably
petabytes globally!) of wasted memory could easily save 42 trees, and a
kitten!

Unfortunately, until everybods applies more common sense, there will still
often be modules that pull in the monster pragmas. But one can hope...

=cut

package common::sense;

our $VERSION = '2.0';

# paste this into pelr to find bitmask

# no warnings;
# use warnings qw(FATAL closed threads internal debugging pack substr malloc unopened portable prototype
#                 inplace io pipe unpack regexp deprecated exiting glob digit printf
#                 utf8 layer reserved parenthesis taint closure semicolon);
# no warnings qw(exec newline);
# BEGIN { warn join "", map "\\x$_", unpack "(H2)*", ${^WARNING_BITS}; exit 0 };

# overload should be included

sub import {
   # verified with perl 5.8.0, 5.10.0
   ${^WARNING_BITS} = "\xfc\x3f\xf3\x00\x0f\xf3\xcf\xc0\xf3\xfc\x33\x03";

   # use strict vars subs
   $^H |= 0x00000600;

   # use feature
   $^H{feature_switch} =
   $^H{feature_say}    =
   $^H{feature_state}  = 1;
}

1;

=back

=head1 THERE IS NO 'no common::sense'!!!! !!!! !!

This module doesn't offer an unimport. First of all, it wastes even more
memory, second, and more importantly, who with even a bit of common sense
would want no common sense?

=head1 STABILITY AND FUTURE VERSIONS

Future versions might change just about everything in this module. We
might test our modules and upload new ones working with newer versions of
this module, and leave you standing in the rain because we didn't tell
you. In fact, we did so when switching from 1.0 to 2.0, which enabled gobs
of warnings, and made them FATAL on top.

Maybe we will load some nifty modules that try to emulate C<say> or so
with perls older than 5.10 (this module, of course, should work with older
perl versions - supporting 5.8 for example is just common sense at this
time. Maybe not in the future, but of course you can trust our common
sense to be consistent with, uhm, our opinion).

=head1 WHAT OTHER PEOPLE HAD TO SAY ABOUT THIS MODULE

apeiron

   "... wow"
   "I hope common::sense is a joke."

crab

   "i wonder how it would be if joerg schilling wrote perl modules."

H.Merijn Brand

   "Just one more reason to drop JSON::XS from my distribution list"

Pista Palo

   "Something in short supply these days..."

Steffen Schwigon

   "This module is quite for sure *not* just a repetition of all the other
   'use strict, use warnings'-approaches, and it's also not the opposite.
   [...] And for its chosen middle-way it's also not the worst name ever.
   And everything is documented."

BKB

   "[Deleted - thanks to Steffen Schwigon for pointing out this review was
   in error.]"

Somni

   "the arrogance of the guy"
   "I swear he tacked somenoe else's name onto the module
   just so he could use the royal 'we' in the documentation"

dngor

   "Heh.  '"<elmex at ta-sa.org>"'  The quotes are semantic
   distancing from that e-mail address."

Jerad Pierce

   "Awful name (not a proper pragma), and the SYNOPSIS doesn't tell you
   anything either. Nor is it clear what features have to do with "common
   sense" or discipline."

acme

   "THERE IS NO 'no common::sense'!!!! !!!! !!"

apeiron (meta-comment about us commenting^Wquoting his comment)

   How about quoting this: get a clue, you fucktarded amoeba.

=head1 AUTHOR

 Marc Lehmann <schmorp@schmorp.de>
 http://home.schmorp.de/

 Robin Redeker, "<elmex at ta-sa.org>".

=cut

