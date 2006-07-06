package Class::Data::Accessor;
use strict qw(vars subs);
use Carp;
use vars qw($VERSION);
$VERSION = '0.03';

sub mk_classaccessor {
    my ($declaredclass, $attribute, $data) = @_;

    if( ref $declaredclass ) {
        croak("mk_classaccessor() is a class method, not an object method");
    }

    if( $attribute eq 'DESTROY' ) {
        carp("Having a data accessor named DESTROY in '$declaredclass' is unwise.");
    }

    my $accessor = sub {
        if (ref $_[0]) {
          return $_[0]->{$attribute} = $_[1] if @_ > 1;
          return $_[0]->{$attribute} if exists $_[0]->{$attribute};
        }

        my $wantclass = ref($_[0]) || $_[0];

        return $wantclass->mk_classaccessor($attribute)->(@_)
          if @_>1 && $wantclass ne $declaredclass;

        $data = $_[1] if @_>1;
        return $data;
    };

    no warnings qw/redefine/;
    my $alias = "_${attribute}_accessor";
    *{$declaredclass.'::'.$attribute} = $accessor;
    *{$declaredclass.'::'.$alias}     = $accessor;
}

sub mk_classaccessors {
    my ($declaredclass, @attributes) = @_;

    foreach my $attribute (@attributes) {
        $declaredclass->mk_classaccessor($attribute);
    }
};

__END__

=head1 NAME

Class::Data::Accessor - Inheritable, overridable class and instance data accessor creation

=head1 SYNOPSIS

  package Stuff;
  use base qw(Class::Data::Accessor);

  # Set up DataFile as inheritable class data.
  Stuff->mk_classaccessor('DataFile');

  # Declare the location of the data file for this class.
  Stuff->DataFile('/etc/stuff/data');

  # Or, all in one shot:
  Stuff->mk_classaccessor(DataFile => '/etc/stuff/data');


  Stuff->DataFile; # returns /etc/stuff/data

  my $stuff = Stuff->new; # your new, not ours

  $stuff->DataFile; # returns /etc/stuff/data

  $stuff->DataFile('/etc/morestuff'); # sets it on the object

  Stuff->DataFile; # still returns /etc/stuff/data

=head1 DESCRIPTION

Class::Data::Accessor is the marriage of L<Class::Accessor> and
L<Class::Data::Inheritable> into a single module. It is used for creating
accessors to class data that overridable in subclasses as well as in
class instances.

For example:

  Pere::Ubu->mk_classaccessor('Suitcase');

will generate the method Suitcase() in the class Pere::Ubu.

This new method can be used to get and set a piece of class data.

  Pere::Ubu->Suitcase('Red');
  $suitcase = Pere::Ubu->Suitcase;

Taking this one step further, you can make a subclass that inherits from
Pere::Ubu:

  package Raygun;
  use base qw(Pere::Ubu);

  # Raygun's suitcase is Red.
  $suitcase = Raygun->Suitcase;

Raygun inherits its Suitcase class data from Pere::Ubu.

Inheritance of class data works analogous to method inheritance.  As
long as Raygun does not "override" its inherited class data (by using
Suitcase() to set a new value) it will continue to use whatever is set
in Pere::Ubu and inherit further changes:

  # Both Raygun's and Pere::Ubu's suitcases are now Blue
  Pere::Ubu->Suitcase('Blue');

However, should Raygun decide to set its own Suitcase() it has now
"overridden" Pere::Ubu and is on its own, just like if it had
overridden a method:

  # Raygun has an orange suitcase, Pere::Ubu's is still Blue.
  Raygun->Suitcase('Orange');

Now that Raygun has overridden Pere::Ubu, further changes by Pere::Ubu
no longer effect Raygun.

  # Raygun still has an orange suitcase, but Pere::Ubu is using Samsonite.
  Pere::Ubu->Suitcase('Samsonite');

You can also override this class data on a per-object basis.
If $obj isa Pere::Ubu then

  $obj->Suitcase; # will return Samsonite

  $obj->Suitcase('Purple'); # will set Suitcase *for this object only*

And after you've done that,

  $obj->Suitcase; # will return Purple

but

  Pere::Ubu->Suitcase; # will still return Samsonite

If you don't want this behaviour use L<Class::Data::Inheritable> instead.

C<mk_classaccessor> will die if used as an object method instead of as a
class method.

=head1 METHODS

=head2 mk_classaccessor

  Class->mk_classaccessor($data_accessor_name);
  Class->mk_classaccessor($data_accessor_name => $value);

This is a class method used to declare new class data accessors.
A new accessor will be created in the Class using the name from
$data_accessor_name, and optionally initially setting it to the given
value.

To facilitate overriding, mk_classaccessor creates an alias to the
accessor, _field_accessor().  So Suitcase() would have an alias
_Suitcase_accessor() that does the exact same thing as Suitcase().
This is useful if you want to alter the behavior of a single accessor
yet still get the benefits of inheritable class data.  For example.

  sub Suitcase {
      my($self) = shift;
      warn "Fashion tragedy" if @_ and $_[0] eq 'Plaid';

      $self->_Suitcase_accessor(@_);
  }

Overriding accessors does not work in the same class as you declare
the accessor in.  It only works in subclasses due to the fact that
subroutines are loaded at compile time and accessors are loaded at
runtime, thus overriding any subroutines with the same name in the
same class.

=head2 mk_classaccessors(@accessornames)

Takes a list of names and generates an accessor for each name in the list using
C<mk_classaccessor>.

=head1 AUTHORS

Based on the creative stylings of Damian Conway, Michael G Schwern,
Tony Bowden (Class::Data::Inheritable) and Michael G Schwern, Marty Pauley
(Class::Accessor).

Coded by Matt S Trout
Tweaks by Christopher H. Laco.

=head1 BUGS and QUERIES

If your object isn't hash-based, this will currently break. My modifications
aren't exactly sophisticated so far.

mstrout@cpan.org or bug me on irc.perl.org, nick mst
claco@cpan.org or irc.perl.org, nick claco

=head1 LICENSE

This module is free software. It may be used, redistributed and/or
modified under the terms of the Perl Artistic License (see
http://www.perl.com/perl/misc/Artistic.html)

=head1 SEE ALSO

L<perltootc> has a very elaborate discussion of class data in Perl.
L<Class::Accessor>, L<Class::Data::Inheritable>

=cut

1;
