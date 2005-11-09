$Tie::Watch::VERSION = '1.2';

package Tie::Watch;

=head1 NAME

 Tie::Watch - place watchpoints on Perl variables.

=head1 SYNOPSIS

 use Tie::Watch;

 $watch = Tie::Watch->new(
     -variable => \$frog,
     -debug    => 1,
     -shadow   => 0,			  
     -fetch    => [\&fetch, 'arg1', 'arg2', ..., 'argn'],
     -store    => \&store,
     -destroy  => sub {print "Final value=$frog.\n"},
 }
 %vinfo = $watch->Info;
 $args  = $watch->Args(-fetch);
 $val   = $watch->Fetch;
 print "val=", $watch->Say($val), ".\n";
 $watch->Store('Hello');
 $watch->Unwatch;

=head1 DESCRIPTION

This class module binds one or more subroutines of your devising to a
Perl variable.  All variables can have B<FETCH>, B<STORE> and
B<DESTROY> callbacks.  Additionally, arrays can define B<CLEAR>,
B<DELETE>, B<EXISTS>, B<EXTEND>, B<FETCHSIZE>, B<POP>, B<PUSH>,
B<SHIFT>, B<SPLICE>, B<STORESIZE> and B<UNSHIFT> callbacks, and hashes
can define B<CLEAR>, B<DELETE>, B<EXISTS>, B<FIRSTKEY> and B<NEXTKEY>
callbacks.  If these term are unfamiliar to you, I I<really> suggest
you read L<perltie>.

With Tie::Watch you can:

 . alter a variable's value
 . prevent a variable's value from being changed
 . invoke a Perl/Tk callback when a variable changes
 . trace references to a variable

Callback format is patterned after the Perl/Tk scheme: supply either a
code reference, or, supply an array reference and pass the callback
code reference in the first element of the array, followed by callback
arguments.  (See examples in the Synopsis, above.)

Tie::Watch provides default callbacks for any that you fail to
specify.  Other than negatively impacting performance, they perform
the standard action that you'd expect, so the variable behaves
"normally".  Once you override a default callback, perhaps to insert
debug code like print statements, your callback normally finishes by
calling the underlying (overridden) method.  But you don't have to!

To map a tied method name to a default callback name simply lowercase
the tied method name and uppercase its first character.  So FETCH
becomes Fetch, NEXTKEY becomes Nextkey, etcetera.

Here are two callbacks for a scalar. The B<FETCH> (read) callback does
nothing other than illustrate the fact that it returns the value to
assign the variable.  The B<STORE> (write) callback uppercases the
variable and returns it.  In all cases the callback I<must> return the
correct read or write value - typically, it does this by invoking the
underlying method.

 my $fetch_scalar = sub {
     my($self) = @_;
     $self->Fetch;
 };

 my $store_scalar = sub {
     my($self, $new_val) = @_;
     $self->Store(uc $new_val);
 };

Here are B<FETCH> and B<STORE> callbacks for either an array or hash.
They do essentially the same thing as the scalar callbacks, but
provide a little more information.

 my $fetch = sub {
     my($self, $key) = @_;
     my $val = $self->Fetch($key);
     print "In fetch callback, key=$key, val=", $self->Say($val);
     my $args = $self->Args(-fetch);
     print ", args=('", join("', '",  @$args), "')" if $args;
     print ".\n";
     $val;
 };

 my $store = sub {
     my($self, $key, $new_val) = @_;
     my $val = $self->Fetch($key);
     $new_val = uc $new_val;
     $self->Store($key, $new_val);
     print "In store callback, key=$key, val=", $self->Say($val),
       ", new_val=", $self->Say($new_val);
     my $args = $self->Args(-store);
     print ", args=('", join("', '",  @$args), "')" if $args;
     print ".\n";
     $new_val;
 };

In all cases, the first parameter is a reference to the Watch object,
used to invoke the following class methods.

=head1 METHODS

=over 4

=item $watch = Tie::Watch->new(-options => values);

The watchpoint constructor method that accepts option/value pairs to
create and configure the Watch object.  The only required option is
B<-variable>.

B<-variable> is a I<reference> to a scalar, array or hash variable.

B<-debug> (default 0) is 1 to activate debug print statements internal
to Tie::Watch.

B<-shadow> (default 1) is 0 to disable array and hash shadowing.  To
prevent infinite recursion Tie::Watch maintains parallel variables for
arrays and hashes.  When the watchpoint is created the parallel shadow
variable is initialized with the watched variable's contents, and when
the watchpoint is deleted the shadow variable is copied to the original
variable.  Thus, changes made during the watch process are not lost.
Shadowing is on my default.  If you disable shadowing any changes made
to an array or hash are lost when the watchpoint is deleted.

Specify any of the following relevant callback parameters, in the
format described above: B<-fetch>, B<-store>, B<-destroy>.
Additionally for arrays: B<-clear>, B<-extend>, B<-fetchsize>,
B<-pop>, B<-push>, B<-shift>, B<-splice>, B<-storesize> and
B<-unshift>.  Additionally for hashes: B<-clear>, B<-delete>,
B<-exists>, B<-firstkey> and B<-nextkey>.

=item $args = $watch->Args(-fetch);

Returns a reference to a list of arguments for the specified callback,
or undefined if none.

=item $watch->Fetch();  $watch->Fetch($key);

Returns a variable's current value.  $key is required for an array or
hash.

=item %vinfo = $watch->Info();

Returns a hash detailing the internals of the Watch object, with these
keys:

 %vinfo = {
     -variable =>  SCALAR(0x200737f8)
     -debug    =>  '0'
     -shadow   =>  '1'
     -value    =>  'HELLO SCALAR'
     -destroy  =>  ARRAY(0x200f86cc)
     -fetch    =>  ARRAY(0x200f8558)
     -store    =>  ARRAY(0x200f85a0)
     -legible  =>  above data formatted as a list of string, for printing
 }

For array and hash Watch objects, the B<-value> key is replaced with a
B<-ptr> key which is a reference to the parallel array or hash.
Additionally, for an array or hash, there are key/value pairs for
all the variable specific callbacks.

=item $watch->Say($val);

Used mainly for debugging, it returns $val in quotes if required, or
the string "undefined" for undefined values.

=item $watch->Store($new_val);  $watch->Store($key, $new_val);

Store a variable's new value.  $key is required for an array or hash.

=item $watch->Unwatch();

Stop watching the variable.

=back

=head1 EFFICIENCY CONSIDERATIONS

If you can live using the class methods provided, please do so.  You
can meddle with the object hash directly and improved watch
performance, at the risk of your code breaking in the future.

=head1 AUTHOR

Stephen O. Lidie

=head1 HISTORY

 lusol@Lehigh.EDU, LUCC, 96/05/30
 . Original version 0.92 release, based on the Trace module from Hans Mulder,
   and ideas from Tim Bunce.

 lusol@Lehigh.EDU, LUCC, 96/12/25
 . Version 0.96, release two inner references detected by Perl 5.004.

 lusol@Lehigh.EDU, LUCC, 97/01/11
 . Version 0.97, fix Makefile.PL and MANIFEST (thanks Andreas Koenig).
   Make sure test.pl doesn't fail if Tk isn't installed.

 Stephen.O.Lidie@Lehigh.EDU, Lehigh University Computing Center, 97/10/03
 . Version 0.98, implement -shadow option for arrays and hashes.

 Stephen.O.Lidie@Lehigh.EDU, Lehigh University Computing Center, 98/02/11
 . Version 0.99, finally, with Perl 5.004_57, we can completely watch arrays.
   With tied array support this module is essentially complete, so its been
   optimized for speed at the expense of clarity - sorry about that. The
   Delete() method has been renamed Unwatch() because it conflicts with the
   builtin delete().

 Stephen.O.Lidie@Lehigh.EDU, Lehigh University Computing Center, 99/04/04
 . Version 1.0, for Perl 5.005_03, update Makefile.PL for ActiveState, and
   add two examples (one for Perl/Tk).

 sol0@lehigh.edu, Lehigh University Computing Center, 2003/06/07
 . Version 1.1, for Perl 5.8, can trace a reference now, patch from Slaven
   Rezic.

 sol0@lehigh.edu, Lehigh University Computing Center, 2005/05/17
 . Version 1.2, for Perl 5.8, per Rob Seegel's suggestion, support array
   DELETE and EXISTS.

=head1 COPYRIGHT

Copyright (C) 1996 - 2005 Stephen O. Lidie. All rights reserved.

This program is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut

use 5.004_57;;
use Carp;
use strict;
use subs qw/normalize_callbacks/;
use vars qw/@array_callbacks @hash_callbacks @scalar_callbacks/;

@array_callbacks  = qw/-clear -delete -destroy -exists -extend -fetch
                       -fetchsize -pop -push -shift -splice -store
                       -storesize -unshift/;
@hash_callbacks   = qw/-clear -delete -destroy -exists -fetch -firstkey 
                       -nextkey -store/;
@scalar_callbacks = qw/-destroy -fetch -store/;

sub new {

    # Watch constructor.  The *real* constructor is Tie::Watch->base_watch(),
    # invoked by methods in other Watch packages, depending upon the variable's
    # type.  Here we supply defaulted parameter values and then verify them,
    # normalize all callbacks and bind the variable to the appropriate package.

    my($class, %args) = @_;
    my $version = $Tie::Watch::VERSION;
    my (%arg_defaults) = (-debug => 0, -shadow  => 1);
    my $variable = $args{-variable};
    croak "Tie::Watch::new(): -variable is required." if not defined $variable;

    my($type, $watch_obj) = (ref $variable, undef);
    if ($type =~ /(SCALAR|REF)/) {
	@arg_defaults{@scalar_callbacks} = (
	    [\&Tie::Watch::Scalar::Destroy],  [\&Tie::Watch::Scalar::Fetch],
	    [\&Tie::Watch::Scalar::Store]);
    } elsif ($type =~ /ARRAY/) {
	@arg_defaults{@array_callbacks}  = (
	    [\&Tie::Watch::Array::Clear],     [\&Tie::Watch::Array::Delete],
	    [\&Tie::Watch::Array::Destroy],   [\&Tie::Watch::Array::Exists],
	    [\&Tie::Watch::Array::Extend],    [\&Tie::Watch::Array::Fetch],
	    [\&Tie::Watch::Array::Fetchsize], [\&Tie::Watch::Array::Pop],
            [\&Tie::Watch::Array::Push],      [\&Tie::Watch::Array::Shift],
            [\&Tie::Watch::Array::Splice],    [\&Tie::Watch::Array::Store],
            [\&Tie::Watch::Array::Storesize], [\&Tie::Watch::Array::Unshift]);
    } elsif ($type =~ /HASH/) {
	@arg_defaults{@hash_callbacks}   = (
	    [\&Tie::Watch::Hash::Clear],      [\&Tie::Watch::Hash::Delete],
	    [\&Tie::Watch::Hash::Destroy],    [\&Tie::Watch::Hash::Exists],
            [\&Tie::Watch::Hash::Fetch],      [\&Tie::Watch::Hash::Firstkey],
            [\&Tie::Watch::Hash::Nextkey],    [\&Tie::Watch::Hash::Store]);
    } else {
	croak "Tie::Watch::new() - not a variable reference.";
    }
    my(@margs, %ahsh, $args, @args);
    @margs = grep ! defined $args{$_}, keys %arg_defaults;
    %ahsh = %args;                         # argument hash
    @ahsh{@margs} = @arg_defaults{@margs}; # fill in missing values
    normalize_callbacks \%ahsh;

    if ($type =~ /(SCALAR|REF)/) {
        $watch_obj = tie $$variable, 'Tie::Watch::Scalar', %ahsh;
    } elsif ($type =~ /ARRAY/) {
        $watch_obj = tie @$variable, 'Tie::Watch::Array',  %ahsh;
    } elsif ($type =~ /HASH/) {
        $watch_obj = tie %$variable, 'Tie::Watch::Hash',   %ahsh;
    }
    $watch_obj;

} # end new, Watch constructor

sub Args {

    # Return a reference to a list of callback arguments, or undef if none.
    #
    # $_[0] = self
    # $_[1] = callback type

    defined $_[0]->{$_[1]}->[1] ? [@{$_[0]->{$_[1]}}[1 .. $#{$_[0]->{$_[1]}}]]
	: undef;

} # end Args

sub Info {

    # Info() method subclassed by other Watch modules.
    #
    # $_[0] = self
    # @_[1 .. $#_] = optional callback types

    my(%vinfo, @results);
    my(@info) = (qw/-variable -debug -shadow/);
    push @info, @_[1 .. $#_] if scalar @_ >= 2;
    foreach my $type (@info) {
	push @results, 	sprintf('%-10s: ', substr $type, 1) .
	    $_[0]->Say($_[0]->{$type});
	$vinfo{$type} = $_[0]->{$type};
    }
    $vinfo{-legible} = [@results];
    %vinfo;

} # end Info

sub Say {

    # For debugging, mainly.
    #
    # $_[0] = self
    # $_[1] = value

    defined $_[1] ? (ref($_[1]) ne '' ? $_[1] : "'$_[1]'") : "undefined";

} # end Say

sub Unwatch {

    # Stop watching a variable by releasing the last reference and untieing it.
    # Update the original variable with its shadow, if appropriate.
    #
    # $_[0] = self

    my $variable = $_[0]->{-variable};
    my $type = ref $variable;
    my $copy = $_[0]->{-ptr} if $type !~ /(SCALAR|REF)/;
    my $shadow = $_[0]->{-shadow};
    undef $_[0];
    if ($type =~ /(SCALAR|REF)/) {
	untie $$variable;
    } elsif ($type =~ /ARRAY/) {
	untie @$variable;
	@$variable = @$copy if $shadow;
    } elsif ($type =~ /HASH/) {
	untie %$variable;
	%$variable = %$copy if $shadow;
    } else {
	croak "Tie::Watch::Delete() - not a variable reference.";
    }

} # end Unwatch

# Watch private methods.

sub base_watch {

    # Watch base class constructor invoked by other Watch modules.

    my($class, %args) = @_;
    my $watch_obj = {%args}; 
    $watch_obj;

} # end base_watch

sub callback {
    
    # Execute a Watch callback, either the default or user specified.
    # Note that the arguments are those supplied by the tied method,
    # not those (if any) specified by the user when the watch object
    # was instantiated.  This is for performance reasons, and why the
    # Args() method exists.
    #
    # $_[0] = self
    # $_[1] = callback type
    # $_[2] through $#_ = tied arguments

    &{$_[0]->{$_[1]}->[0]} ($_[0], @_[2 .. $#_]);

} # end callback

sub normalize_callbacks {

    # Ensure all callbacks are normalized in [\&code, @args] format.

    my($args_ref) = @_;
    my($cb, $ref);
    foreach my $arg (keys %$args_ref) {
	next if $arg =~ /variable|debug|shadow/;
	$cb = $args_ref->{$arg};
	$ref = ref $cb;
	if ($ref =~ /CODE/) {
	    $args_ref->{$arg} = [$cb];
	} elsif ($ref !~ /ARRAY/) {
	    croak "Tie::Watch:  malformed callback $arg=$cb.";
	}
    }

} # end normalize_callbacks

###############################################################################

package Tie::Watch::Scalar;

use Carp;
@Tie::Watch::Scalar::ISA = qw/Tie::Watch/;

sub TIESCALAR {

    my($class, %args) = @_;
    my $variable = $args{-variable};
    my $watch_obj = Tie::Watch->base_watch(%args);
    $watch_obj->{-value} = $$variable;
    print "WatchScalar new: $variable created, \@_=", join(',', @_), "!\n"
	if $watch_obj->{-debug};
    bless $watch_obj, $class;

} # end TIESCALAR

sub Info {$_[0]->SUPER::Info('-value', @Tie::Watch::scalar_callbacks)}

# Default scalar callbacks.

sub Destroy {undef %{$_[0]}}
sub Fetch   {$_[0]->{-value}}
sub Store   {$_[0]->{-value} = $_[1]}

# Scalar access methods.

sub DESTROY {$_[0]->callback('-destroy')}
sub FETCH   {$_[0]->callback('-fetch')}
sub STORE   {$_[0]->callback('-store', $_[1])}

###############################################################################

package Tie::Watch::Array;

use Carp;
@Tie::Watch::Array::ISA = qw/Tie::Watch/;

sub TIEARRAY {

    my($class, %args) = @_;
    my($variable, $shadow) = @args{-variable, -shadow};
    my @copy = @$variable if $shadow; # make a private copy of user's array
    $args{-ptr} = $shadow ? \@copy : [];
    my $watch_obj = Tie::Watch->base_watch(%args);
    print "WatchArray new: $variable created, \@_=", join(',', @_), "!\n"
	if $watch_obj->{-debug};
    bless $watch_obj, $class;

} # end TIEARRAY

sub Info {$_[0]->SUPER::Info('-ptr', @Tie::Watch::array_callbacks)}

# Default array callbacks.

sub Clear     {$_[0]->{-ptr} = ()}
sub Delete    {delete $_[0]->{-ptr}->[$_[1]]}
sub Destroy   {undef %{$_[0]}}
sub Exists    {exists $_[0]->{-ptr}->[$_[1]]}
sub Extend    {}
sub Fetch     {$_[0]->{-ptr}->[$_[1]]}
sub Fetchsize {scalar @{$_[0]->{-ptr}}}
sub Pop       {pop @{$_[0]->{-ptr}}}
sub Push      {push @{$_[0]->{-ptr}}, @_[1 .. $#_]}
sub Shift     {shift @{$_[0]->{-ptr}}}
sub Splice    {
    my $n = scalar @_;		# splice() is wierd!
    return splice @{$_[0]->{-ptr}}, $_[1]                      if $n == 2;
    return splice @{$_[0]->{-ptr}}, $_[1], $_[2]               if $n == 3;
    return splice @{$_[0]->{-ptr}}, $_[1], $_[2], @_[3 .. $#_] if $n >= 4;
}
sub Store     {$_[0]->{-ptr}->[$_[1]] = $_[2]}
sub Storesize {$#{@{$_[0]->{-ptr}}} = $_[1] - 1}
sub Unshift   {unshift @{$_[0]->{-ptr}}, @_[1 .. $#_]}

# Array access methods.

sub CLEAR     {$_[0]->callback('-clear')}
sub DELETE    {$_[0]->callback('-delete', $_[1])}
sub DESTROY   {$_[0]->callback('-destroy')}
sub EXISTS    {$_[0]->callback('-exists', $_[1])}
sub EXTEND    {$_[0]->callback('-extend', $_[1])}
sub FETCH     {$_[0]->callback('-fetch', $_[1])}
sub FETCHSIZE {$_[0]->callback('-fetchsize')}
sub POP       {$_[0]->callback('-pop')}
sub PUSH      {$_[0]->callback('-push', @_[1 .. $#_])}
sub SHIFT     {$_[0]->callback('-shift')}
sub SPLICE    {$_[0]->callback('-splice', @_[1 .. $#_])}
sub STORE     {$_[0]->callback('-store', $_[1], $_[2])}
sub STORESIZE {$_[0]->callback('-storesize', $_[1])}
sub UNSHIFT   {$_[0]->callback('-unshift', @_[1 .. $#_])}

###############################################################################

package Tie::Watch::Hash;

use Carp;
@Tie::Watch::Hash::ISA = qw/Tie::Watch/;

sub TIEHASH {

    my($class, %args) = @_;
    my($variable, $shadow) = @args{-variable, -shadow};
    my %copy = %$variable if $shadow; # make a private copy of user's hash
    $args{-ptr} = $shadow ? \%copy : {};
    my $watch_obj = Tie::Watch->base_watch(%args);
    print "WatchHash new: $variable created, \@_=", join(',', @_), "!\n"
	if $watch_obj->{-debug};
    bless $watch_obj, $class;

} # end TIEHASH

sub Info {$_[0]->SUPER::Info('-ptr', @Tie::Watch::hash_callbacks)}

# Default hash callbacks.

sub Clear    {$_[0]->{-ptr} = ()}
sub Delete   {delete $_[0]->{-ptr}->{$_[1]}}
sub Destroy  {undef %{$_[0]}}
sub Exists   {exists $_[0]->{-ptr}->{$_[1]}}
sub Fetch    {$_[0]->{-ptr}->{$_[1]}}
sub Firstkey {my $c = keys %{$_[0]->{-ptr}}; each %{$_[0]->{-ptr}}}
sub Nextkey  {each %{$_[0]->{-ptr}}}
sub Store    {$_[0]->{-ptr}->{$_[1]} = $_[2]}

# Hash access methods.

sub CLEAR    {$_[0]->callback('-clear')}
sub DELETE   {$_[0]->callback('-delete', $_[1])}
sub DESTROY  {$_[0]->callback('-destroy')}
sub EXISTS   {$_[0]->callback('-exists', $_[1])}
sub FETCH    {$_[0]->callback('-fetch', $_[1])}
sub FIRSTKEY {$_[0]->callback('-firstkey')}
sub NEXTKEY  {$_[0]->callback('-nextkey')}
sub STORE    {$_[0]->callback('-store', $_[1], $_[2])}

1;
