=for gpg
-----BEGIN PGP SIGNED MESSAGE-----
Hash: SHA1

- -----BEGIN PGP SIGNED MESSAGE-----
Hash: SHA1

=head1 NAME

Readonly - Facility for creating read-only scalars, arrays, hashes.

=head1 VERSION

This documentation describes version 1.03 of Readonly.pm, April 20, 2004.

=cut

# Rest of documentation is after __END__.

use 5.005;
use strict;
#use warnings;
#no warnings 'uninitialized';

package Readonly;
$Readonly::VERSION = '1.03';    # Also change in the documentation!

# Autocroak (Thanks, MJD)
# Only load Carp.pm if module is croaking.
sub croak
{
    require Carp;
    goto &Carp::croak;
}

# These functions may be overridden by Readonly::XS, if installed.
sub is_sv_readonly   ($) { 0 }
sub make_sv_readonly ($) { die "make_sv_readonly called but not overridden" }
use vars qw/$XSokay/;     # Set to true in Readonly::XS, if available

# Common error messages, or portions thereof
use vars qw/$MODIFY $REASSIGN $ODDHASH/;
$MODIFY   = 'Modification of a read-only value attempted';
$REASSIGN = 'Attempt to reassign a readonly';
$ODDHASH  = 'May not store an odd number of values in a hash';

# See if we can use the XS stuff.
$Readonly::XS::MAGIC_COOKIE = "Do NOT use or require Readonly::XS unless you're me.";
eval 'use Readonly::XS';


# ----------------
# Read-only scalars
# ----------------
package Readonly::Scalar;

sub TIESCALAR
{
    my $whence = (caller 2)[3];    # Check if naughty user is trying to tie directly.
    Readonly::croak "Invalid tie"  unless $whence && $whence =~ /^Readonly::(?:Scalar1?|Readonly)$/;
    my $class = shift;
    Readonly::croak "No value specified for readonly scalar"        unless @_;
    Readonly::croak "Too many values specified for readonly scalar" unless @_ == 1;

    my $value = shift;
    return bless \$value, $class;
}

sub FETCH
{
    my $self = shift;
    return $$self;
}

*STORE = *UNTIE =
    sub {Readonly::croak $Readonly::MODIFY};


# ----------------
# Read-only arrays
# ----------------
package Readonly::Array;

sub TIEARRAY
{
    my $whence = (caller 1)[3];    # Check if naughty user is trying to tie directly.
    Readonly::croak "Invalid tie"  unless $whence =~ /^Readonly::Array1?$/;
    my $class = shift;
    my @self = @_;

    return bless \@self, $class;
}

sub FETCH
{
    my $self  = shift;
    my $index = shift;
    return $self->[$index];
}

sub FETCHSIZE
{
    my $self = shift;
    return scalar @$self;
}

BEGIN {
    eval q{
        sub EXISTS
           {
           my $self  = shift;
           my $index = shift;
           return exists $self->[$index];
           }
    } if $] >= 5.006;    # couldn't do "exists" on arrays before then
}

*STORE = *STORESIZE = *EXTEND = *PUSH = *POP = *UNSHIFT = *SHIFT = *SPLICE = *CLEAR = *UNTIE =
    sub {Readonly::croak $Readonly::MODIFY};


# ----------------
# Read-only hashes
# ----------------
package Readonly::Hash;

sub TIEHASH
{
    my $whence = (caller 1)[3];    # Check if naughty user is trying to tie directly.
    Readonly::croak "Invalid tie"  unless $whence =~ /^Readonly::Hash1?$/;

    my $class = shift;
    # must have an even number of values
    Readonly::croak $Readonly::ODDHASH unless (@_ %2 == 0);

    my %self = @_;
    return bless \%self, $class;
}

sub FETCH
{
    my $self = shift;
    my $key  = shift;

    return $self->{$key};
}

sub EXISTS
{
    my $self = shift;
    my $key  = shift;
    return exists $self->{$key};
}

sub FIRSTKEY
{
    my $self = shift;
    my $dummy = keys %$self;
    return scalar each %$self;
}

sub NEXTKEY
{
    my $self = shift;
    return scalar each %$self;
}

*STORE = *DELETE = *CLEAR = *UNTIE =
    sub {Readonly::croak $Readonly::MODIFY};


# ----------------------------------------------------------------
# Main package, containing convenience functions (so callers won't
# have to explicitly tie the variables themselves).
# ----------------------------------------------------------------
package Readonly;
use Exporter;
use vars qw/@ISA @EXPORT @EXPORT_OK %EXPORT_TAGS/;
push @ISA, 'Exporter';
push @EXPORT, qw/Readonly/;
push @EXPORT_OK, qw/Scalar Array Hash Scalar1 Array1 Hash1/;

# Predeclare the following, so we can use them recursively
sub Scalar ($$);
sub Array (\@;@);
sub Hash (\%;@);

# Returns true if a string begins with "Readonly::"
# Used to prevent reassignment of Readonly variables.
sub _is_badtype
{
    my $type = $_[0];
    return lc $type if $type =~ s/^Readonly:://;
    return;
}

# Shallow Readonly scalar
sub Scalar1 ($$)
{
    croak "$REASSIGN scalar" if is_sv_readonly $_[0];
    my $badtype = _is_badtype (ref tied $_[0]);
    croak "$REASSIGN $badtype" if $badtype;

    # xs method: flag scalar as readonly
    if ($XSokay)
    {
        $_[0] = $_[1];
        make_sv_readonly $_[0];
        return;
    }

    # pure-perl method: tied scalar
    my $tieobj = eval {tie $_[0], 'Readonly::Scalar', $_[1]};
    if ($@)
    {
        croak "$REASSIGN scalar" if substr($@,0,43) eq $MODIFY;
        die $@;    # some other error?
    }
    return $tieobj;
}

# Shallow Readonly array
sub Array1 (\@;@)
{
    my $badtype = _is_badtype (ref tied $_[0]);
    croak "$REASSIGN $badtype" if $badtype;

    my $aref = shift;
    return tie @$aref, 'Readonly::Array', @_;
}

# Shallow Readonly hash
sub Hash1 (\%;@)
{
    my $badtype = _is_badtype (ref tied $_[0]);
    croak "$REASSIGN $badtype" if $badtype;

    my $href = shift;

    # If only one value, and it's a hashref, expand it
    if (@_ == 1  &&  ref $_[0] eq 'HASH')
    {
        return tie %$href, 'Readonly::Hash', %{$_[0]};
    }

    # otherwise, must have an even number of values
    croak $ODDHASH unless (@_%2 == 0);

    return tie %$href, 'Readonly::Hash', @_;
}

# Deep Readonly scalar
sub Scalar ($$)
{
    croak "$REASSIGN scalar" if is_sv_readonly $_[0];
    my $badtype = _is_badtype (ref tied $_[0]);
    croak "$REASSIGN $badtype" if $badtype;

    my $value = $_[1];

    # Recursively check passed element for references; if any, make them Readonly
    foreach ($value)
    {
        if    (ref eq 'SCALAR') {Scalar my $v => $$_; $_ = \$v}
        elsif (ref eq 'ARRAY')  {Array  my @v => @$_; $_ = \@v}
        elsif (ref eq 'HASH')   {Hash   my %v =>  $_; $_ = \%v}
    }

    # xs method: flag scalar as readonly
    if ($XSokay)
    {
        $_[0] = $value;
        make_sv_readonly $_[0];
        return;
    }

    # pure-perl method: tied scalar
    my $tieobj = eval {tie $_[0], 'Readonly::Scalar', $value};
    if ($@)
    {
        croak "$REASSIGN scalar" if substr($@,0,43) eq $MODIFY;
        die $@;    # some other error?
    }
    return $tieobj;
}

# Deep Readonly array
sub Array (\@;@)
{
    my $badtype = _is_badtype (ref tied @{$_[0]});
    croak "$REASSIGN $badtype" if $badtype;

    my $aref = shift;
    my @values = @_;

    # Recursively check passed elements for references; if any, make them Readonly
    foreach (@values)
    {
        if    (ref eq 'SCALAR') {Scalar my $v => $$_; $_ = \$v}
        elsif (ref eq 'ARRAY')  {Array  my @v => @$_; $_ = \@v}
        elsif (ref eq 'HASH')   {Hash   my %v => $_;  $_ = \%v}
    }
    # Lastly, tie the passed reference
    return tie @$aref, 'Readonly::Array', @values;
}

# Deep Readonly hash
sub Hash (\%;@)
{
    my $badtype = _is_badtype (ref tied %{$_[0]});
    croak "$REASSIGN $badtype" if $badtype;

    my $href = shift;
    my @values = @_;

    # If only one value, and it's a hashref, expand it
    if (@_ == 1  &&  ref $_[0] eq 'HASH')
    {
        @values = %{$_[0]};
    }

    # otherwise, must have an even number of values
    croak $ODDHASH unless (@values %2 == 0);

    # Recursively check passed elements for references; if any, make them Readonly
    foreach (@values)
    {
        if    (ref eq 'SCALAR') {Scalar my $v => $$_; $_ = \$v}
        elsif (ref eq 'ARRAY')  {Array  my @v => @$_; $_ = \@v}
        elsif (ref eq 'HASH')   {Hash   my %v => $_;  $_ = \%v}
    }

    return tie %$href, 'Readonly::Hash', @values;
}


# Common entry-point for all supported data types
eval q{sub Readonly} . ( $] < 5.008 ? '' : '(\[$@%]@)' ) . <<'SUB_READONLY';
{
    if (ref $_[0] eq 'SCALAR')
    {
        croak $MODIFY if is_sv_readonly ${$_[0]};
        my $badtype = _is_badtype (ref tied ${$_[0]});
        croak "$REASSIGN $badtype" if $badtype;
        croak "Readonly scalar must have only one value" if @_ > 2;

        my $tieobj = eval {tie ${$_[0]}, 'Readonly::Scalar', $_[1]};
        # Tie may have failed because user tried to tie a constant, or we screwed up somehow.
        if ($@)
        {
            croak $MODIFY if $@ =~ /^$MODIFY at/;    # Point the finger at the user.
            die "$@\n";        # Not a modify read-only message; must be our fault.
        }
        return $tieobj;
    }
    elsif (ref $_[0] eq 'ARRAY')
    {
        my $aref = shift;
        return Array @$aref, @_;
    }
    elsif (ref $_[0] eq 'HASH')
    {
        my $href = shift;
        croak $ODDHASH  if @_%2 != 0  &&  !(@_ == 1  && ref $_[0] eq 'HASH');
        return Hash %$href, @_;
    }
    elsif (ref $_[0])
    {
        croak "Readonly only supports scalar, array, and hash variables.";
    }
    else
    {
        croak "First argument to Readonly must be a reference.";
    }
}
SUB_READONLY


1;
__END__

=head1 SYNOPSIS

 use Readonly;

 # Read-only scalar
 Readonly::Scalar     $sca => $initial_value;
 Readonly::Scalar  my $sca => $initial_value;

 # Read-only array
 Readonly::Array      @arr => @values;
 Readonly::Array   my @arr => @values;

 # Read-only hash
 Readonly::Hash       %has => (key => value, key => value, ...);
 Readonly::Hash    my %has => (key => value, key => value, ...);
 # or:
 Readonly::Hash       %has => {key => value, key => value, ...};

 # You can use the read-only variables like any regular variables:
 print $sca;
 $something = $sca + $arr[2];
 next if $has{$some_key};

 # But if you try to modify a value, your program will die:
 $sca = 7;
 push @arr, 'seven';
 delete $has{key};
 # The error message is "Modification of a read-only value
attempted"

 # Alternate form (Perl 5.8 and later)
 Readonly    $sca => $initial_value;
 Readonly my $sca => $initial_value;
 Readonly    @arr => @values;
 Readonly my @arr => @values;
 Readonly    %has => (key => value, key => value, ...);
 Readonly my %has => (key => value, key => value, ...);
 # Alternate form (for Perls earlier than v5.8)
 Readonly    \$sca => $initial_value;
 Readonly \my $sca => $initial_value;
 Readonly    \@arr => @values;
 Readonly \my @arr => @values;
 Readonly    \%has => (key => value, key => value, ...);
 Readonly \my %has => (key => value, key => value, ...);


=head1 DESCRIPTION

This is a facility for creating non-modifiable variables.  This is
useful for configuration files, headers, etc.  It can also be useful
as a development and debugging tool, for catching updates to variables
that should not be changed.

If any of the values you pass to C<Scalar>, C<Array>, or C<Hash> are
references, then those functions recurse over the data structures,
marking everything as Readonly.  Usually, this is what you want: the
entire structure nonmodifiable.  If you want only the top level to be
Readonly, use the alternate C<Scalar1>, C<Array1> and C<Hash1>
functions.

Please note that most users of Readonly will also want to install a
companion module Readonly::XS.  See the L</CONS> section below for more
details.

=head1 COMPARISON WITH "use constant"

Perl provides a facility for creating constant values, via the "use
constant" pragma.  There are several problems with this pragma.

=over 2

=item *

The constants created have no leading $ or @ character.

=item *

These constants cannot be interpolated into strings.

=item *

Syntax can get dicey sometimes.  For example:

 use constant CARRAY => (2, 3, 5, 7, 11, 13);
 $a_prime = CARRAY[2];        # wrong!
 $a_prime = (CARRAY)[2];      # right -- MUST use parentheses

=item *

You have to be very careful in places where barewords are allowed.
For example:

 use constant SOME_KEY => 'key';
 %hash = (key => 'value', other_key => 'other_value');
 $some_value = $hash{SOME_KEY};        # wrong!
 $some_value = $hash{+SOME_KEY};       # right

(who thinks to use a unary plus when using a hash?)

=item *

C<use constant> works for scalars and arrays, not hashes.

=item *

These constants are global ot the package in which they're declared;
cannot be lexically scoped.

=item *

Works only at compile time.

=item *

Can be overridden:

 use constant PI => 3.14159;
 ...
 use constant PI => 2.71828;

(this does generate a warning, however, if you have warnings enabled).

=item *

It is very difficult to make and use deep structures (complex data
structures) with C<use constant>.

=back

=head1 COMPARISON WITH TYPEGLOB CONSTANTS

Another popular way to create read-only scalars is to modify the symbol
table entry for the variable by using a typeglob:

 *a = \'value';

This works fine, but it only works for global variables ("my"
variables have no symbol table entry).  Also, the following similar
constructs do B<not> work:

 *a = [1, 2, 3];      # Does NOT create a read-only array
 *a = { a => 'A'};    # Does NOT create a read-only hash

=head1 PROS

Readonly.pm, on the other hand, will work with global variables and
with lexical ("my") variables.  It will create scalars, arrays, or
hashes, all of which look and work like normal, read-write Perl
variables.  You can use them in scalar context, in list context; you
can take references to them, pass them to functions, anything.

Readonly.pm also works well with complex data structures, allowing you
to tag the whole structure as nonmodifiable, or just the top level.

Also, Readonly variables may not be reassigned.  The following code
will die:

 Readonly::Scalar $pi => 3.14159;
 ...
 Readonly::Scalar $pi => 2.71828;

=head1 CONS

Readonly.pm does impose a performance penalty.  It's pretty slow.  How
slow?  Run the C<benchmark.pl> script that comes with Readonly.  On my
test system, "use constant", typeglob constants, and regular
read/write Perl variables were all about the same speed, and
Readonly.pm constants were about 1/20 the speed.

However, there is relief.  There is a companion module available,
Readonly::XS.  If it is installed on your system, Readonly.pm uses it
to make read-only scalars much faster.  With Readonly::XS, Readonly
scalars are as fast as the other types of variables.  Readonly arrays
and hashes will still be relatively slow.  But it's likely that most
of your Readonly variables will be scalars.

If you can't use Readonly::XS (for example, if you don't have a C
compiler, or your perl is statically linked and you don't want to
re-link it), you have to decide whether the benefits of Readonly
variables outweigh the speed issue. For most configuration variables
(and other things that Readonly is likely to be useful for), the speed
issue is probably not really a big problem.  But benchmark your
program if it might be.  If it turns out to be a problem, you may
still want to use Readonly.pm during development, to catch changes to
variables that should not be changed, and then remove it for
production:

 # For testing:
 Readonly::Scalar  $Foo_Directory => '/usr/local/foo';
 Readonly::Scalar  $Bar_Directory => '/usr/local/bar';
 # $Foo_Directory = '/usr/local/foo';
 # $Bar_Directory = '/usr/local/bar';

 # For production:
 # Readonly::Scalar  $Foo_Directory => '/usr/local/foo';
 # Readonly::Scalar  $Bar_Directory => '/usr/local/bar';
 $Foo_Directory = '/usr/local/foo';
 $Bar_Directory = '/usr/local/bar';


=head1 FUNCTIONS

=over 4

=item Readonly::Scalar $var => $value;

Creates a nonmodifiable scalar, C<$var>, and assigns a value of
C<$value> to it.  Thereafter, its value may not be changed.  Any
attempt to modify the value will cause your program to die.

A value I<must> be supplied.  If you want the variable to have
C<undef> as its value, you must specify C<undef>.

If C<$value> is a reference to a scalar, array, or hash, then this
function will mark the scalar, array, or hash it points to as being
Readonly as well, and it will recursively traverse the structure,
marking the whole thing as Readonly.  Usually, this is what you want.
However, if you want only the C<$value> marked as Readonly, use
C<Scalar1>.

If $var is already a Readonly variable, the program will die with
an error about reassigning Readonly variables.

=item Readonly::Array @arr => (value, value, ...);

Creates a nonmodifiable array, C<@arr>, and assigns the specified list
of values to it.  Thereafter, none of its values may be changed; the
array may not be lengthened or shortened or spliced.  Any attempt to
do so will cause your program to die.

If any of the values passed is a reference to a scalar, array, or hash,
then this function will mark the scalar, array, or hash it points to as
being Readonly as well, and it will recursively traverse the structure,
marking the whole thing as Readonly.  Usually, this is what you want.
However, if you want only the hash C<%@arr> itself marked as Readonly,
use C<Array1>.

If @arr is already a Readonly variable, the program will die with
an error about reassigning Readonly variables.

=item Readonly::Hash %h => (key => value, key => value, ...);

=item Readonly::Hash %h => {key => value, key => value, ...};

Creates a nonmodifiable hash, C<%h>, and assigns the specified keys
and values to it.  Thereafter, its keys or values may not be changed.
Any attempt to do so will cause your program to die.

A list of keys and values may be specified (with parentheses in the
synopsis above), or a hash reference may be specified (curly braces in
the synopsis above).  If a list is specified, it must have an even
number of elements, or the function will die.

If any of the values is a reference to a scalar, array, or hash, then
this function will mark the scalar, array, or hash it points to as
being Readonly as well, and it will recursively traverse the
structure, marking the whole thing as Readonly.  Usually, this is what
you want.  However, if you want only the hash C<%h> itself marked as
Readonly, use C<Hash1>.

If %h is already a Readonly variable, the program will die with
an error about reassigning Readonly variables.

=item Readonly $var => $value;

=item Readonly @arr => (value, value, ...);

=item Readonly %h => (key => value, ...);

=item Readonly %h => {key => value, ...};

The C<Readonly> function is an alternate to the C<Scalar>, C<Array>,
and C<Hash> functions.  It has the advantage (if you consider it an
advantage) of being one function.  That may make your program look
neater, if you're initializing a whole bunch of constants at once.
You may or may not prefer this uniform style.

It has the disadvantage of having a slightly different syntax for
versions of Perl prior to 5.8.  For earlier versions, you must supply
a backslash, because it requires a reference as the first parameter.

  Readonly \$var => $value;
  Readonly \@arr => (value, value, ...);
  Readonly \%h => (key => value, ...);
  Readonly \%h => {key => value, ...};

You may or may not consider this ugly.

=item Readonly::Scalar1 $var => $value;

=item Readonly::Array1 @arr => (value, value, ...);

=item Readonly::Hash1 %h => (key => value, key => value, ...);

=item Readonly::Hash1 %h => {key => value, key => value, ...};

These alternate functions create shallow Readonly variables, instead
of deep ones.  For example:

 Readonly::Array1 @shal => (1, 2, {perl=>'Rules', java=>'Bites'}, 4, 5);
 Readonly::Array  @deep => (1, 2, {perl=>'Rules', java=>'Bites'}, 4, 5);

 $shal[1] = 7;           # error
 $shal[2]{APL}='Weird';  # Allowed! since the hash isn't Readonly
 $deep[1] = 7;           # error
 $deep[2]{APL}='Weird';  # error, since the hash is Readonly


=back


=head1 EXAMPLES

 # SCALARS:

 # A plain old read-only value
 Readonly::Scalar $a => "A string value";

 # The value need not be a compile-time constant:
 Readonly::Scalar $a => $computed_value;


 # ARRAYS:

 # A read-only array:
 Readonly::Array @a => (1, 2, 3, 4);

 # The parentheses are optional:
 Readonly::Array @a => 1, 2, 3, 4;

 # You can use Perl's built-in array quoting syntax:
 Readonly::Array @a => qw/1 2 3 4/;

 # You can initialize a read-only array from a variable one:
 Readonly::Array @a => @computed_values;

 # A read-only array can be empty, too:
 Readonly::Array @a => ();
 Readonly::Array @a;        # equivalent


 # HASHES

 # Typical usage:
 Readonly::Hash %a => (key1 => 'value1', key2 => 'value2');

 # A read-only hash can be initialized from a variable one:
 Readonly::Hash %a => %computed_values;

 # A read-only hash can be empty:
 Readonly::Hash %a => ();
 Readonly::Hash %a;        # equivalent

 # If you pass an odd number of values, the program will die:
 Readonly::Hash %a => (key1 => 'value1', "value2");
     --> dies with "May not store an odd number of values in a hash"


=head1 EXPORTS

By default, this module exports the following symbol into the calling
program's namespace:

 Readonly

The following symbols are available for import into your program, if
you like:

 Scalar  Scalar1
 Array   Array1
 Hash    Hash1


=head1 REQUIREMENTS

 Perl 5.000
 Carp.pm (included with Perl)
 Exporter.pm (included with Perl)

 Readonly::XS is recommended but not required.

=head1 ACKNOWLEDGEMENTS

Thanks to Slaven Rezic for the idea of one common function
(Readonly) for all three types of variables (13 April 2002).

Thanks to Ernest Lergon for the idea (and initial code) for
deeply-Readonly data structures (21 May 2002).

Thanks to Damian Conway for the idea (and code) for making the
Readonly function work a lot smoother under perl 5.8+.


=head1 AUTHOR / COPYRIGHT

Eric J. Roode, roode@cpan.org

Copyright (c) 2001-2004 by Eric J. Roode. All Rights Reserved.  This
module is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

If you have suggestions for improvement, please drop me a line.  If
you make improvements to this software, I ask that you please send me
a copy of your changes. Thanks.

Readonly.pm is made from 100% recycled electrons.  No animals were
harmed during the development and testing of this module.  Not sold
in stores!  Readonly::XS sold separately.  Void where prohibited.

=cut

=begin gpg

-----BEGIN PGP SIGNATURE-----
Version: GnuPG v1.2.4 (MingW32)

iD8DBQFAhaGCY96i4h5M0egRAg++AJ0ar4ncojbOp0OOc2wo+E/1cBn5cQCg9eP9
qTzAC87PuyKB+vrcRykrDbo=
=39Ny
-----END PGP SIGNATURE-----

=cut