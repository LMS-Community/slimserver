package enum;
use strict;
no strict 'refs';  # Let's just make this very clear right off

use Carp;
use vars qw($VERSION);
$VERSION = do { my @r = (q$Revision: 1.1 $ =~ /\d+/g); sprintf '%d.%03d'.'%02d' x ($#r-1), @r};

my $Ident = '[^\W_0-9]\w*';

sub ENUM    () { 1 }
sub BITMASK () { 2 }

sub import {
    my $class   = shift;
    @_ or return;       # Ignore 'use enum;'
    my $pkg     = caller() . '::';
    my $prefix  = '';   # default no prefix 
    my $index   = 0;    # default start index
    my $mode    = ENUM; # default to enum

    ## Pragmas should be as fast as they can be, so we inline some
    ## pieces.
    foreach (@_) {
        ## Plain tag is most common case
        if (/^$Ident$/o) {
            my $n = $index;

            if ($mode == ENUM) {
                $index++;
            }
            elsif ($mode == BITMASK) {
                $index ||= 1;
                $index *= 2;
                if ( $index & ($index - 1) ) {
                    croak (
                        "$index is not a valid single bitmask "
                        . " (Maybe you overflowed your system's max int value?)"
                    );
                }
            }
            else {
                confess qq(Can't Happen: mode $mode invalid);
            }

            *{"$pkg$prefix$_"} = sub () { $n };
        }

        ## Index change
        elsif (/^($Ident)=(-?)(.+)$/o) {
            my $name= $1;
            my $neg = $2;
            $index  = $3;

            ## Convert non-decimal numerics to decimal
            if ($index =~ /^0x[\da-f]+$/i) {    ## Hex
                $index = hex $index;
            }
            elsif ($index =~ /^0\d/) {          ## Octal
                $index = oct $index;
            }
            elsif ($index !~ /[^\d_]/) {        ## 123_456 notation
                $index =~ s/_//g;
            }

            ## Force numeric context, but only in numeric context
            if ($index =~ /\D/) {
                $index  = "$neg$index";
            }
            else {
                $index  = "$neg$index";
                $index  += 0;
            }

            my $n   = $index;

            if ($mode == BITMASK) {
                ($index & ($index - 1))
                    and croak "$index is not a valid single bitmask";
                $index *= 2;
            }
            elsif ($mode == ENUM) {
                $index++;
            }
            else {
                confess qq(Can't Happen: mode $mode invalid);
            }

            *{"$pkg$prefix$name"} = sub () { $n };
        }

        ## Prefix/option change
        elsif (/^([A-Z]*):($Ident)?(=?)(-?)(.*)/) {
            ## Option change
            if ($1) {
                if      ($1 eq 'ENUM')      { $mode = ENUM;     $index = 0 }
                elsif   ($1 eq 'BITMASK')   { $mode = BITMASK;  $index = 1 }
                else    { croak qq(Invalid enum option '$1') }
            }

            my $neg = $4;

            ## Index change too?
            if ($3) {
                if (length $5) {
                    $index = $5;

                    ## Convert non-decimal numerics to decimal
                    if ($index =~ /^0x[\da-f]+$/i) {    ## Hex
                        $index = hex $index;
                    }
                    elsif ($index =~ /^0\d/) {          ## Oct
                        $index = oct $index;
                    }
                    elsif ($index !~ /[^\d_]/) {        ## 123_456 notation
                        $index =~ s/_//g;
                    }

                    ## Force numeric context, but only in numeric context
                    if ($index =~ /\D/) {
                        $index  = "$neg$index";
                    }
                    else {
                        $index  = "$neg$index";
                        $index  += 0;
                    }

                    ## Bitmask mode must check index changes
                    if ($mode == BITMASK) {
                        ($index & ($index - 1))
                            and croak "$index is not a valid single bitmask";
                    }
                }
                else {
                    croak qq(No index value defined after "=");
                }
            }

            ## Incase it's a null prefix
            $prefix = defined $2 ? $2 : '';
        }

        ## A..Z case magic lists
        elsif (/^($Ident)\.\.($Ident)$/o) {
            ## Almost never used, so check last
            foreach my $name ("$1" .. "$2") {
                my $n = $index;

                if ($mode == BITMASK) {
                    ($index & ($index - 1))
                        and croak "$index is not a valid single bitmask";
                    $index *= 2;
                }
                elsif ($mode == ENUM) {
                    $index++;
                }
                else {
                    confess qq(Can't Happen: mode $mode invalid);
                }

                *{"$pkg$prefix$name"} = sub () { $n };
            }
        }

        else {
            croak qq(Can't define "$_" as enum type (name contains invalid characters));
        }
    }
}

1;

__END__


=head1 NAME

enum - C style enumerated types and bitmask flags in Perl

=head1 SYNOPSIS

  use enum qw(Sun Mon Tue Wed Thu Fri Sat);
  # Sun == 0, Mon == 1, etc

  use enum qw(Forty=40 FortyOne Five=5 Six Seven);
  # Yes, you can change the start indexs at any time as in C

  use enum qw(:Prefix_ One Two Three);
  ## Creates Prefix_One, Prefix_Two, Prefix_Three

  use enum qw(:Letters_ A..Z);
  ## Creates Letters_A, Letters_B, Letters_C, ...

  use enum qw(
      :Months_=0 Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec
      :Days_=0   Sun Mon Tue Wed Thu Fri Sat
      :Letters_=20 A..Z
  );
  ## Prefixes can be changed mid list and can have index changes too

  use enum qw(BITMASK:LOCK_ SH EX NB UN);
  ## Creates bitmask constants for LOCK_SH == 1, LOCK_EX == 2,
  ## LOCK_NB == 4, and LOCK_UN == 8.
  ## NOTE: This example is only valid on FreeBSD-2.2.5 however, so don't
  ## actually do this.  Import from Fnctl instead.

=head1 DESCRIPTION

Defines a set of symbolic constants with ordered numeric values ala B<C> B<enum> types.

Now capable of creating creating ordered bitmask constants as well.  See the B<BITMASKS>
section for details.

What are they good for?  Typical uses would be for giving mnemonic names to indexes of
arrays.  Such arrays might be a list of months, days, or a return value index from
a function such as localtime():

  use enum qw(
      :Months_=0 Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec
      :Days_=0   Sun Mon Tue Wed Thu Fri Sat
      :LC_=0     Sec Min Hour MDay Mon Year WDay YDay Isdst
  );

  if ((localtime)[LC_Mon] == Months_Jan) {
      print "It's January!\n";
  }
  if ((localtime)[LC_WDay] == Days_Fri) {
      print "It's Friday!\n";
  }

This not only reads easier, but can also be typo-checked at compile time when
run under B<use strict>.  That is, if you misspell B<Days_Fri> as B<Days_Fry>,
you'll generate a compile error.

=head1 BITMASKS, bitwise operations, and bitmask option values

The B<BITMASK> option allows the easy creation of bitmask constants such as
functions like flock() and sysopen() use.  These are also very useful for your
own code as they allow you to efficiently store many true/false options within
a single integer.

    use enum qw(BITMASK: MY_ FOO BAR CAT DOG);

    my $foo = 0;
    $foo |= MY_FOO;
    $foo |= MY_DOG;
    
    if ($foo & MY_DOG) {
        print "foo has the MY_DOG option set\n";
    }
    if ($foo & (MY_BAR | MY_DOG)) {
        print "foo has either the MY_BAR or MY_DOG option set\n"
    }

    $foo ^= MY_DOG;  ## Turn MY_DOG option off (set its bit to false)

When using bitmasks, remember that you must use the bitwise operators, B<|>, B<&>, B<^>,
and B<~>.  If you try to do an operation like C<$foo += MY_DOG;> and the B<MY_DOG> bit
has already been set, you'll end up setting other bits you probably didn't want to set.
You'll find the documentation for these operators in the B<perlop> manpage.

You can set a starting index for bitmasks just as you can for normal B<enum> values,
but if the given index isn't a power of 2 it won't resolve to a single bit and therefor
will generate a compile error.  Because of this, whenever you set the B<BITFIELD:>
directive, the index is automatically set to 1.  If you wish to go back to normal B<enum>
mode, use the B<ENUM:> directive.  Similarly to the B<BITFIELD> directive, the B<ENUM:>
directive resets the index to 0.  Here's an example:

  use enum qw(
      BITMASK:BITS_ FOO BAR CAT DOG
      ENUM: FALSE TRUE
      ENUM: NO YES
      BITMASK: ONE TWO FOUR EIGHT SIX_TEEN
  );

In this case, B<BITS_FOO, BITS_BAR, BITS_CAT, and BITS_DOG> equal 1, 2, 4 and
8 respectively.  B<FALSE and TRUE> equal 0 and 1.  B<NO and YES> also equal
0 and 1.  And B<ONE, TWO, FOUR, EIGHT, and SIX_TEEN> equal, you guessed it, 1,
2, 4, 8, and 16.

=head1 BUGS

Enum names can not be the same as method, function, or constant names.  This
is probably a Good Thing[tm].

No way (that I know of) to cause compile time errors when one of these enum names get
redefined.  IMHO, there is absolutely no time when redefining a sub is a Good Thing[tm],
and should be taken out of the language, or at least have a pragma that can cause it
to be a compile time error.

Enumerated types are package scoped just like constants, not block scoped as some
other pragma modules are.

It supports A..Z nonsense.  Can anyone give me a Real World[tm] reason why anyone would
ever use this feature...?

=head1 HISTORY

  $Log: enum.pm,v $
  Revision 1.1  2004/12/16 20:39:21  dsully
  Add Tim Bunce's live_object_key per class & search retreival to Class::DBI.

  Use Class::Accessor::Fast where we can.

  Additional modules for Caching & Abstract SQL Limiting.

  Fix UNIVSERAL::moniker directory name.

  Revision 1.16  1999/05/27 16:00:35  byron


  Fixed bug that caused bitwise operators to treat enum types as strings
  instead of numbers.

  Revision 1.15  1999/05/27 15:51:27  byron


  Add support for negative values.

  Added stricter hex value checks.

  Revision 1.14  1999/05/13 15:58:18  byron


  Fixed bug in hex index code that broke on 0xA.

  Revision 1.13  1999/05/13 10:52:30  byron


  Fixed auto-index bugs in new non-decimal numeric support.

  Revision 1.12  1999/05/13 10:00:45  byron


  Added support for non-decimal numeric representations ala 0x123, 0644, and
  123_456.

  First version committed to CVS.


  Revision 1.11  1998/07/18 17:53:05  byron
    -Added BITMASK and ENUM directives.
    -Revamped documentation.

  Revision 1.10  1998/06/12 20:12:50  byron
    -Removed test code
    -Released to CPAN

  Revision 1.9  1998/06/12 00:21:00  byron
    -Fixed -w warning when a null tag is used

  Revision 1.8  1998/06/11 23:04:53  byron
    -Fixed documentation bugs
    -Moved A..Z case to last as it's not going to be used
     as much as the other cases.

  Revision 1.7  1998/06/10 12:25:04  byron
    -Changed interface to match original design by Tom Phoenix
     as implemented in an early version of enum.pm by Benjamin Holzman.
    -Changed tag syntax to not require the 'PREFIX' string of Tom's
     interface.
    -Allow multiple prefix tags to be used at any point.
    -Allowed index value changes from tags.

  Revision 1.6  1998/06/10 03:37:57  byron
    -Fixed superfulous -w warning

  Revision 1.4  1998/06/10 01:07:03  byron
    -Changed behaver to closer resemble C enum types
    -Changed docs to match new behaver

=head1 AUTHOR

Zenin <zenin@archive.rhps.org>

aka Byron Brummer <byron@omix.com>.

Based off of the B<constant> module by Tom Phoenix.

Original implementation of an interface of Tom Phoenix's
design by Benjamin Holzman, for which we borrow the basic
parse algorithm layout.

=head1 COPYRIGHT

Copyright 1998 (c) Byron Brummer.
Copyright 1998 (c) OMIX, Inc.

Permission to use, modify, and redistribute this module granted under
the same terms as B<Perl>.

=head1 SEE ALSO

constant(3), perl(1).

=cut
