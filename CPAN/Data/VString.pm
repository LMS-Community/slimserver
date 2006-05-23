
package Data::VString;

use 5.008;
use strict;
use warnings;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
  parse_vstring 
  format_vstring
  vstring_satisfy
  vstring_cmp
);

our $VERSION = '0.000_003'; # '0.0.3'

use Carp qw(carp);

#use encoding 'utf8';

=head1 NAME

Data::VString - Perl extension to handle v-strings (often used as version strings)

=head1 SYNOPSIS

  use Data::VString qw(parse_vstring format_vstring vstring_cmp vstring_satisfy);

  # going from '0.0.1' to "\x{0}\x{0}\x{1}" and back
  $i_vstring = parse_vstring($vstring);
  $vstring = format_vstring($i_vstring);

  print 'ok' if vstring_cmp($VERSION, '>=', '0.0.1');

  my $bool = vstring_satisfy($vstring, $predicate)

=head1 DESCRIPTION

Most of the time, the so-called version numbers 
are not really numbers, but tuples of integers
like C<'0.2.3'>. With this concept of version,
C<'0.1'> is the same as C<'0.01'>. The ordering of
such tuples is usually defined by comparing each
part. And that makes 

  '0.1' > '0.2' 
  '0.2.1' < '0.1.3'
  '0.11.10' > '0.10.10.10' 

and also C<'0.1'> > C<'0.1.0'> (because the first one is shorter). 
There is also no need to define how many integers to accept
in the tuple, with C<'0.0.1.2.34.4.580.20'> being
a nice version.

Perl had (and still has) this concept as v-strings.
They had even deserved a syntax on their own:
C<v1.20.300.4000> or C<100.111.1111> (a literal
with two or more dots). But their fate is sealed:
in L<perldata/"Version Strings"> of 5.8 we read:

  Note: Version Strings (v-strings) have been deprecated.  
  They will not be available after Perl 5.8.  The marginal 
  benefits of v-strings were greatly outweighed by the 
  potential for Surprise and Confusion.

This module revives them as a simple module implementation.
Version strings are well suited in many version "numbering"
schemes and straightforward (if you always remember they
are not numbers). In Perl, most of the confusion
lies in that C<0.1> as a literal is a number and sorts
like a number, while C<0.1.0> is a v-string and sorts
like a v-string. Also from L<perldata/"Version Strings">:

  A literal of the form "v1.20.300.4000" is parsed as a string composed
  of characters with the specified ordinals.  This form, known as
  v-strings, provides an alternative, more readable way to construct
  strings, rather than use the somewhat less readable interpolation form
  "\x{1}\x{14}\x{12c}\x{fa0}".  This is useful for representing Unicode
  strings, and for comparing version "numbers" using the string compari-
  son operators, "cmp", "gt", "lt" etc.  If there are two or more dots in
  the literal, the leading "v" may be omitted.

    print v9786;              # prints UTF-8 encoded SMILEY, "\x{263a}"
    print v102.111.111;       # prints "foo"
    print 102.111.111;        # same

This text reveals how this notion of version as tuple
of integers can be represented efficiently if one
agreeds that each part is limited to 16 bits (0-65565),
which is more than enough for practical software
versioning schemes. Converting each part to a Unicode 
character, the version string ends up like a Unicode
string which can be compared with the usual string
comparators.

Here, functions are provided for converting between v-strings
(like C<'6.2.28'>) and their internal representation 
(C<"\x{6}\x{2}\x{1C}">) and to test them against other
v-strings.


=over 4

=item B<parse_vstring>

  $i_vstring = parse_vstring($vstring);

  parse_vstring('0.1.2') # return "\x{0}\x{1}\x{2}"

Converts a v-string into its internal representation
(the string made up the Unicode characters given
by the ordinals specified in v-string parts).

The syntax of a v-string can be defined by the
following syntax rule (in C<P::RD> style)

  <v-string>: /\d+/ ( /[._]/ /\d+/ )*

For the reverse operation, see C<format_vstring>.

=cut

sub _is_vstring {
  return shift =~ /^\d+([._]\d+)*$/;
}

sub parse_vstring {
  my $vs = shift;
  return undef unless defined $vs && _is_vstring($vs);
  #no warnings 'utf8'; # every 16-bit value is ok
  $vs =~ s/[._]?(\d+)/chr($1 & 0x0FFFF)/eg;
  return $vs
}

=item B<format_vstring>

  $vstring = format_vstring($i_vstring)

Converts the internal representation of a v-string
into a readable v-string. It does the reverse
operation of C<parse_vstring>.

=cut

sub format_vstring {
  my $vs = shift;
  return $vs unless $vs; # take care of ''
  #no warnings 'utf8'; # every 16-bit value is ok
  $vs =~ s/(.)/ord($1)."."/eg;
  chop $vs;
  return $vs
}

=item B<vstring_satisfy>

  vstring_satisfy($vstring, $predicate);

  vstring_satisfy('0.1.1', '0.1.1'); # true
  vstring_satisfy('0.1.1', '> 0, < 0.2, != 0.1.0'); # true
  vstring_satisfy('0.2.4', '0.2.5..0.3.4'); # false

Determines if a v-string satisfy a predicate.
The predicate is a list of simple predicates,
each one must be satisfied (that is, an I<and>).
Simple predicates takes one of three forms:

  '0.1.2'       - exact match 
  '>= 3.14.15'  - (relational operator) (v-string)
  '5.6 .. 10.8' - meaning '>= 5.6, <= 10.8'

A grammar for predicates in L<Parse::RecDescent>-like syntax
is:

  <p> : <p0> (',' <p>)*

  <p0>: <v-string>                  # the same as '==' <v-string>
      | <op> <v-string> 
      | <v-string> '..' <v-string>  # the same as ">= <v-string1>, <= <v-string2>"

  <op>: '==' | '!=' | '<=' | '>=' | '<' | '>'

Spaces are irrelevant in predicates.

=cut

sub vstring_satisfy {
  my $vs = shift;
  my $p = shift;
  $p =~ s/\s//g; # spaces are irrelevant
  my @p = split ',', $p;
  for (@p) {
    if (/^(\d+([._]\d+)*)$/) {
      next if _vstring_cmp($vs, '==', $1);
      return 0;
    }
    if (/^([=!<>]=|[<>])(\d+([._]\d+)*)$/) {
      next if _vstring_cmp($vs, $1, $2);
      return 0;
    }
    if (/^(\d+([._]\d+)*)\.\.(\d+([._]\d+)*)$/) {
      next if _vstring_cmp($1, '<=', $vs) &&
          _vstring_cmp($vs, '<=', $3); # !!!
      return 0;
    }
    carp "bad predicate $_"
      and return undef;
  }
  return 1;
}

my %cmp = (
  '==' => sub { shift eq shift },
  '!=' => sub { shift ne shift },
  '<=' => sub { shift le shift },
  '>=' => sub { shift ge shift },
  '<'  => sub { shift lt shift },
  '>'  => sub { shift gt shift }
);

#sub Dump_literal {
#  my $lit = shift;
#  use YAML;
#  my $y = YAML::Dump $lit;
#  $y =~ s/--- //;
#  $y =~ s/\n//g;
#  return $y
#}

sub _vstring_cmp {
  my $v1 = parse_vstring shift;
  my $op = shift; # op is one of '==', '!=', '<=', '>=', '<', '>'
  my $v2 = parse_vstring shift;
  #print "v1: ", Dump_literal($v1),
  #    " op: ", $op,
  #    " v2: ", Dump_literal($v2), "\n";
  return &{$cmp{$op}}($v1, $v2);
}

=item B<vstring_cmp>

  $ans = vstring_cmp($vs1, $op, $vs2)

  $eq = vstring_cmp('0.1.02', '==', '0.01.2'); # ok
  $le = vstring_cmp('1.2.3', '>=', '3.2.1'); # not ok

Makes a comparison between two v-strings. The supported operators
are '==', '!=', '<=', '>=', '<', and '>'.

=cut

sub vstring_cmp {
  my $v1 = parse_vstring shift;
  return undef unless $v1;
  my $op = shift;
  unless (exists $cmp{$op}) {
      carp "vstring_cmp: unknown op '$op'";
      return undef
  }
  my $v2 = parse_vstring shift;
  return undef unless $v2;
  return &{$cmp{$op}}($v1, $v2);
}

=back


=head2 EXPORT

None by default. C<parse_vstring>, C<format_vstring>,
C<vstring_cmp>, and C<vstring_satisfy> can be exported on demand.

=begin comment

Rewrite this section (DESCRIPTION) and move citations of
perldata to a new section (HISTORY), making the documentation
less centered in Perl documentation.

Document also the use of '_' as version part separator.
(A usual convention used in CPAN is that when a version
string contains '_', it is meant to be a developer's version).

Remember also the syntactical confusion that 'v65' is not
a v-string in a the right hand of C<< '=>' >>.

Include a link to the JSAN library when it is released.

Document the behavior on error of the functions of the module.

=end comment


=cut

=head1 SEE ALSO

L<perldata/"Version Strings">

L<version> by John Peacock. That module is older and more famous.
The main differences are:

=over 4

=item *

C<version> is OO, this module is a bunch of functions

=item *

C<version> does not represents version as Unicode strings
as we do (well, I think so after a quick glance of the code)

=item *

C<version> is much more tolerant with numeric versions.
This module is not concerned with backward compatibility.
Use it versions as strings from the beginning, 
stay out of trouble with numeric versions.

=item *

C<version> is also more tolerant with non-numeric versions.
On the contrary, C<Data::VString> is very strict about
syntax.

=item *

we don't dare to redefine C<UNIVERSAL::VERSION>.

=item *

v-strings are treated as data here and no attempt
to force semantics as Perl module version was made.
Indeed I started coding this module for
handling JSAN distributions (which are data from
the point of view of the Perl program).

=back

This module is a companion for the JSAN module
C<Data.VString>. This one implements the Perl side
while the other will implement the JavaScript side.

=head1 BUGS

There must be some. Because all trivial software
must have at least one bug. This is the actual
list of known bugs.

=over 4

=item *

There is a bug with certain version parts which are
illegal Unicode characters. So the full range 
(0..65535) is not actually usable.

=back

Please report bugs via CPAN RT L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Data-VString>.

=head1 AUTHOR

Adriano R. Ferreira, E<lt>ferreira@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2005 by Adriano R. Ferreira

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.


=cut

1;

