package Class::Data::Inheritable;

use strict qw(vars subs);
use vars qw($VERSION);
$VERSION = '0.02';


=head1 NAME

Class::Data::Inheritable - Inheritable, overridable class data

=head1 SYNOPSIS

  package Stuff;
  use base qw(Class::Data::Inheritable);

  # Set up DataFile as inheritable class data.
  Stuff->mk_classdata('DataFile');

  # Declare the location of the data file for this class.
  Stuff->DataFile('/etc/stuff/data');


=head1 DESCRIPTION

Class::Data::Inheritable is for creating accessor/mutators to class
data.  That is, if you want to store something about your class as a
whole (instead of about a single object).  This data is then inherited
by your subclasses and can be overriden.

For example:

  Pere::Ubu->mk_classdata('Suitcase');

will generate the method Suitcase() in the class Pere::Ubu.

This new method can be used to get and set a piece of class data.

  Pere::Ubu->Suitcase('Red');
  $suitcase = Pere::Ubu->Suitcase;

The interesting part happens when a class inherits from Pere::Ubu:

  package Raygun;
  use base qw(Pere::Ubu);

  # Raygun's suitcase is Red.
  $suitcase = Raygun->Suitcase;

Raygun inherits its Suitcase class data from Pere::Ubu.

Inheritance of class data works analgous to method inheritance.  As
long as Raygun does not "override" its inherited class data (by using
Suitcase() to set a new value) it will continue to use whatever is set
in Pere::Ubu and inherit further changes:

  # Both Raygun's and Pere::Ubu's suitcases are now Blue
  Pere::Ubu->Suitcase('Blue');

However, should Raygun decide to set its own Suitcase() it has now
"overridden" Pere::Ubu and is on its own, just like if it had
overriden a method:

  # Raygun has an orange suitcase, Pere::Ubu's is still Blue.
  Raygun->Suitcase('Orange');

Now that Raygun has overridden Pere::Ubu futher changes by Pere::Ubu
no longer effect Raygun.

  # Raygun still has an orange suitcase, but Pere::Ubu is using Samsonite.
  Pere::Ubu->Suitcase('Samsonite');


=head1 Methods

=over 4

=item B<mk_classdata>

  Class->mk_classdata($data_accessor_name);

This is a class method used to declare new class data accessors.  A
new accessor will be created in the Class using the name from
$data_accessor_name.

To facilitate overriding, mk_classdata creates an alias to the
accessor, _field_accessor().  So Suitcase() would have an alias
_Suitcase_accessor() that does the exact same thing as Suitcase().
This is useful if you want to alter the behavior of a single accessor
yet still get the benefits of inheritable class data.  For example.

  sub Suitcase {
      my($self) = shift;
      warn "Fashion tragedy" if @_ and $_[0] eq 'Plaid';

      $self->_Suitcase_accessor(@_);
  }

=cut

sub mk_classdata {
    my ($declaredclass, $attribute, $data) = @_;

    my $accessor = sub {
        my $wantclass = ref($_[0]) || $_[0];

        return $wantclass->mk_classdata($attribute)->(@_)
          if @_>1 && $wantclass ne $declaredclass;

        $data = $_[1] if @_>1;
        return $data;
    };

    my $alias = "_${attribute}_accessor";
    *{$declaredclass.'::'.$attribute} = $accessor;
    *{$declaredclass.'::'.$alias}     = $accessor;
}


=head1 COPYRIGHT

Copyright (c) 2000, Damian Conway and Michael G Schwern. All
Rights Reserved.  This module is free software. It may be used,
redistributed and/or modified under the terms of the Perl Artistic
License (see http://www.perl.com/perl/misc/Artistic.html)


=head1 AUTHOR

Original code by Damian Conway.

Maintained by Michael G Schwern <schwern@pobox.com>


=head1 SEE ALSO

L<perltootc> has a very elaborate discussion of class data in Perl.

=cut

1;
