package Data::Lazy;
use vars qw($VERSION);
$VERSION='0.6';

require Tie::Scalar;
require Exporter;
@ISA=qw(Exporter Tie::Scalar);

@EXPORT = qw(LAZY_STOREVALUE LAZY_STORECODE LAZY_READONLY);

use Carp;

sub LAZY_STOREVALUE () {0}
sub LAZY_STORECODE  () {1}
sub LAZY_READONLY   () {2}
sub LAZY_UNTIE      () {croak "pass reference to tied var, not LAZY_UNTIE"}

use strict;

sub TIESCALAR {
  my $pack = shift;
  my $self = {};
  $self->{code} = shift;
  $self->{'store'} = $_[0] if $_[0];
  $self->{'type'} = 0;
  bless $self => $pack;		# That's it?  Yup!
}

sub TIEARRAY {
  my $pack = shift;
  my $self = {};
  $self->{code} = shift;
  $self->{'store'} = $_[0] if $_[0];
  $self->{'type'} = 1;
  $self->{'size'} = 0;
  bless $self => $pack;		# That's it?  Yup!
}

sub FETCHSIZE {
    my $self = shift;
    return $self->{'size'};
}

sub TIEHASH {
  my $pack = shift;
  my $self = {};
  $self->{code} = shift;
  $self->{'store'} = $_[0] if $_[0];
  $self->{'type'} = 2;
  ${$self->{'value'}}{$;} = $self->{code};
  bless $self => $pack;		# That's it?  Yup!
}

sub FETCH {

  my $self = shift;
  if ($self->{'type'} == 0) {
      # scalar
   return $self->{value} if exists $self->{value};
   if (ref $self->{code} eq 'CODE') {
         $self->{value} = &{$self->{code}};
   } else {
         $self->{value} = eval $self->{code};
   }
   if (ref $self->{store}) {
       untie(${ delete $self->{store} });
   }
   $self->{value};
  } elsif ($self->{'type'} == 1) {
      # array
   if ($_[0] < 0) {
    $_[0] %= $self->{'size'}
   } elsif ($_[0] - $self->{'size'} >= 0) {
    $self->{'size'} = $_[0]+1;
   }
   return ${$self->{'value'}}[$_[0]] if defined ${$self->{'value'}}[$_[0]];
   if (ref $self->{code} eq 'CODE') {
         ${$self->{'value'}}[$_[0]] = &{$self->{code}}(@_);
   } else {
         ${$self->{'value'}}[$_[0]] = eval $self->{code};
   }
   ${$self->{'value'}}[$_[0]];
  } else {
      # hash
   unless (exists ${$self->{'value'}}{$_[0]}) {
       if (ref $self->{code} eq 'CODE') {
	   ${$self->{'value'}}{$_[0]} = &{$self->{code}}(@_);
       } else {
	   ${$self->{'value'}}{$_[0]} = eval $self->{code};
       }
   }
   ${$self->{'value'}}{$_[0]};
  }
}

sub STORE {
    
  my $self = shift;
  if ($self->{'type'} == 0) {
   if ($self->{'store'}) {

      delete $self->{value};
      if (defined $_[0]) {
       if ($self->{'store'} == LAZY_READONLY) {
        croak "Modification of a read-only value attempted";
    } elsif (ref $self->{store}) {
	# LAZY_UNTIE
	untie(${ delete $self->{store} });
	return shift;
    } else {
	   # $self->{'store'} == LAZY_STORECODE
        $self->{code} = $_[0];
       }
      }
    } else {
      $self->{value} = $_[0];
    }
  } elsif ($self->{'type'} == 1) {
      if ($_[0] - $self->{'size'} >= 0) {
	  $self->{'size'} = $_[0]+1;
      }
      ${$self->{'value'}}[$_[0]] = $_[1];
  } else {
    if ($_[0] eq $;) {
     %{$self->{'value'}} = ();
     $self->{'code'} = $_[1];
     ${$self->{'value'}}{$;} = $self->{code};
    } else {
     ${$self->{'value'}}{$_[0]} = $_[1];
    }
  }
}

sub EXISTS {1}

sub DELETE {undef}

sub CLEAR {%{$_[0]->{'value'}} = ()}

sub FIRSTKEY {
    my ($key,$val) = each %{$_[0]->{'value'}};
    ($key,$val) = each %{$_[0]->{'value'}}if ($key eq $;);
    $key
}
sub NEXTKEY {
    my ($key,$val) = each %{$_[0]->{'value'}};
    ($key,$val) = each %{$_[0]->{'value'}}if ($key eq $;);
    $key
}

no strict 'refs';
sub import {
  my $caller_pack = caller;
  my $my_pack = shift;
#  print STDERR "exporter args: (@_); caller pack: $caller_pack\n";
#  if (@_ % 2) {
#    croak "Argument list in `use $my_pack' must be list of pairs; aborting";
#  }
  while (@_) {
    my $varname = shift;
    my $function = shift;
    my $store = (($_[0] and $_[0] =~ /^[012]$/)
		 ? shift
		 : ($function
		    ? LAZY_STOREVALUE
		    : LAZY_STORECODE));

    if ($varname =~ /^\%(.*)$/) {  #<???>
     my %fakehash;
     tie %fakehash, $my_pack, $function, $store;          #<???>
     *{$caller_pack . '::' . $1} = \%fakehash;
    } elsif ($varname =~ /^\@(.*)$/) {  #<???>
     my @fakearray;
     tie @fakearray, $my_pack, $function, $store;          #<???>
     *{$caller_pack . '::' . $1} = \@fakearray;
    } else {
     $varname =~ s/^\$//;
     my $fakescalar;
     tie $fakescalar, $my_pack, $function, $store;          #<???>
     *{$caller_pack . '::' . $varname} = \$fakescalar;
    }
  }
 @_ = ($my_pack);
 goto &Exporter::import;
}
use strict 'refs';

1;

__END__

=head1 NAME

Data::Lazy.pm - "lazy" (defered/on-demand) variables

version 0.6

(obsoletes and replaces Lazy.pm)

=head1 SYNOPSIS

  # short form
  use Data::Lazy variablename => 'code';
  use Data::Lazy variablename => \&fun;
  use Data::Lazy '@variablename' => \&fun;

  # to use options, you need to `use' the module first.
  use Data::Lazy;
  tie $variable, 'Data::Lazy', sub { ... }, LAZY_READONLY;

  # magic untie - slow on (broken) Perl 5.8.0
  tie $variable, 'Data::Lazy' => \$variable, sub { ... };

=head1 DESCRIPTION

A very little module for generic on-demand computation of values in a
scalar, array or hash.

It provides scalars that are "lazy", that is their value is computed
only when accessed, and at most once.

=head2 Scalars

  tie $variable_often_unnecessary, 'Data::Lazy',
    sub {a function taking a long time} [, $store_options];

  tie $var, 'Data::Lazy', 'a string containing some code' [, $store_options];

  use Data::Lazy variablename => 'code' [, $store_options];

  use Data::Lazy '$variablename' => \&function [, $store_options];

The first time you access the variable, the code gets executed
and the result is saved for later as well as returned to you.
Next accesses will use this value without executing anything.

You may specify what will happen if you try to reset the variable.
You may either change the value or the code.

=over

=item 1. LAZY_STOREVALUE

In this mode - the default mode - changes to the variable are saved as
if the variable was not tied at all.  For example;

    tie $var, 'Data::Lazy', 'sleep 1; 1';
    # or tie $var, 'Data::Lazy', 'sleep 1; 1', LAZY_STOREVALUE;
    $var = 'sleep 2; 2';
    print "'$var'\n";

will return:

    'sleep 2; 2'

=item 2. LAZY_STORECODE

In this mode, writes to the variable are assumed to be updating the
CODE that affects the value fetched, not the value of the variable.

    tie $var, 'Data::Lazy', 'sleep 1; 1', LAZY_STORECODE;
    $var = 'sub { "4" }'

will return

    '4'

with no delay.

If you tie the variable with LAZY_STORECODE option and then undefine
the variable (via C<undef($variable)>), only the stored value is
forgotten, and next time you access this variable, the code is
re-evaluated.


=item 3. LAZY_READONLY

In this mode, writes to the variable raise an error message via
C<croak()> (see L<Carp>).  That is,

    tie $var, 'Data::Lazy', 'sleep 1; 1', LAZY_READONLY;
    $var = 'sleep 2; 2';
    print "'$var'\n";

Will give you an error message :

   Modification of a read-only value attempted at ...

=item 4. LAZY_UNTIE

In this mode, the variable is untie'd once it has been read for the
first time.  This requires that a reference to the variable be passed
into the `tie' operation;

   tie $var, 'Data::Lazy', \$var, "sleep 1; 1";

Note that LAZY_UNTIE was not specified; the reference to the variable
was automatically spotted in the input list.

=back

It's possible to create several variables in one "use Data::Lazy ..."
statement.

=head2 Array

The default tie mode for arrays makes I<individual items> subject to
similar behaviour as scalars.

eg.

  tie @variable, 'Data::Lazy', sub { my $index = shift; ... };

  tie @var, 'Data::Lazy', 'my $index = shift; ...';

  use Data::Lazy '@variablename' => \&function;

The first time you access some item of the list, the code gets
executed with $_[0] being the index and the result is saved for later
as well as returned to you.  Next accesses will use this value without
executing anything.

You may change the values in the array, but there is no way
(currently) to change the code, other than C<(tied @foo)-E<gt>{'code'}
= sub {...}> (which is considered cheating).

eg.

    tie @var, 'Data::Lazy', sub {$_[0]*1.5+15};
    print ">$var[1]<\n";
    $var[2]=1;
    print ">$var[2]<\n";

    tie @fib, 'Data::Lazy', sub {
        if ($_[0] < 0) {0}
        elsif ($_[0] == 0) {1}
        elsif ($_[0] == 1) {1}
        else {$fib[$_[0]-1]+$fib[$_[0]-2]}
    };
    print $fib[15];

Currently it's next to imposible to change the code to be evaluated in
a Data::Lazy array.  Any options you pass to tie() are ignored.
Patches welcome.

The size of an array, as returned by evaluating it in scalar context
or the C<$#var> syntax, will return the highest index returned already
- or 0 if nothing has been read from it yet.  Note that this behaviour
has changed from version 0.5, where 1 was returned on a fresh tied
array.

=head2 Hash

 Eg.

  tie %variable, Data::Lazy, sub {a function taking a long time};

  tie %var, Data::Lazy, 'a string containing some code';

  use Data::Lazy '%variablename' => \&function;

The first time you access some item of the hash, the code gets executed
with $_[0] being the key and the result is saved for later as well as
returned to you. Next accesses will use this value without executing
anything.

If you want to get or set the code that's being evaluated for the previously
unknown items you will find it in $variable{$;}. If you change the code
all previously computed values are discarded.

 Ex.
    tie %var, Data::Lazy, sub {reverse $_[0]};
    print ">$var{'Hello world'}<\n";
    $var{Jenda}='Jan Krynicky';
    print ">$var{'Jenda'}<\n";
    $fun = $var{$;};
    $var{$;} = sub {$_ = $_[0];tr/a-z/A-Z/g;$_};
    print ">$var[2]<\n";

If you write something like

  while (($key,$value) = each %lazy_hash) {
   print " $key = $value\n"; #
  };

only the previously fetched items are returned.
Otherwise the listing could be infinite :-)

=head2 Internals

If you want to access the code or value stored in the variable
directly you may use

    ${tied $var}{code}
    and
    ${tied $var}{value} # scalar $var
    ${tied @var}{value}[$i] # array @var
    ${tied %var}{value}{$name} # hash %var

This way you may modify the code even for arrays and hashes, but be very
careful with this. Of course if you redefine the code, you'll want to
undef the {value}!

There are two more internal variables:

    ${tied $var}{type}
     0 => scalar
     1 => array
     2 => hash
    ${tied $var}{store}
     0 => LAZY_STOREVALUE
     1 => LAZY_STORECODE
     2 => LAZY_READONLY

If you touch these, prepare for very strange results!

An object-oriented interface to setting these variables would be
easily added (patches welcome).

=head2 Examples

 1.
 use Data::Lazy;
 tie $x, 'Data::Lazy', sub{sleep 3; 3};
 # or
 # use Data::Lazy '$x' => sub{sleep 3; 3};

 print "1. ";
 print "$x\n";
 print "2. ";
 print "$x\n";

 $x = 'sleep 10; 10';

 print "3. ";
 print "$x\n";
 print "4. ";
 print "$x\n";


 2. (from Win32::FileOp)
 tie $Win32::FileOp::SHAddToRecentDocs, 'Data::Lazy', sub {
    new Win32::API("shell32", "SHAddToRecentDocs", ['I','P'], 'I')
    or
    die "new Win32::API::SHAddToRecentDocs: $!\n"
 };
 ...


=head2 Comment

Please note that there are single guotes around the variable names in
"use Data::Lazy '...' => ..." statements. The guotes are REQUIRED as soon as
you use any variable type characters ($, @ or %)!

=head1 SIMILAR ALTERNATIVES TO THIS MODULE

There are several notable alternatives to this module; if you come
across another, please forward mention to the author for inclusion in
this list.

=over

=item B<Memoize>

Now a core module, this module performs similarly to the tied hash
variant of this module.  However, it is more geared towards
static/global methods that already return the same value, whereas this
module works on a per-object basis.

=item B<Object::Realize::Later>

This module also provides for defered execution of code.  This module
"expands" objects to their full state via (declared) methods, and
works via re-blessing objects into their new state.  The principal
advantage of this approach is that your reference addresses do not
change, so existing pointers to these objects can stay as-is.

=item B<Tie::Discovery>

Almost identical to the hash variant of this module, the principle
extra feature provided by Tie::Discovery is that instead of a single
code reference which must supply all fetched values, individual
"handlers" are registered for each key for which values are wanted.
This makes it particularly useful for configuration files.

=back

=head1 BUGS

Due to incomplete support for tie'ing arrays in very old versions of
Perl (ie, before 5.004), to fetch the size of an array, you cannot
just evaluate it in scalar context; you have to use:

   tied(@a)->{'size'}

the usual;

   scalar(@a);  #  or ($#a + 1)

will return zero! :-(

=head2 AUTHOR

 Jan Krynicky <Jenda@Krynicky.cz>

=head2 COPYRIGHT

Copyright (c) 2001 Jan Krynicky <Jenda@Krynicky.cz>. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

Some changes copyright (c) 2004, Sam Vilain <samv@cpan.org>.  All
rights reserved.  Changes distributed under terms of original license.

=cut
