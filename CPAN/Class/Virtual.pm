package Class::Virtual;

use strict;
use vars qw($VERSION @ISA);
$VERSION = '0.05';

use Carp::Assert qw(DEBUG);  # import only the tiny bit we need so it doesn't
                             # get inherited.
use Class::ISA;

use Class::Data::Inheritable;
@ISA = qw(Class::Data::Inheritable);
__PACKAGE__->mk_classdata('__Virtual_Methods');


=pod

=head1 NAME

Class::Virtual - Base class for virtual base classes.


=head1 SYNOPSIS

  package My::Virtual::Idaho;
  use base qw(Class::Virtual);

  __PACKAGE__->virtual_methods(qw(new foo bar this that));


  package My::Private::Idaho;
  use base qw(My::Virtual::Idaho);

  # Check to make sure My::Private::Idaho implemented everything
  my @missing = __PACKAGE__->missing_methods;
  die __PACKAGE__ . ' forgot to implement ' . join ', ', @missing 
      if @missing;

  # If My::Private::Idaho forgot to implement new(), the program will
  # halt and yell about that.
  my $idaho = My::Private::Idaho->new;

  # See what methods we're obligated to implement.
  my @must_implement = __PACKAGE__->virtual_methods;


=head1 DESCRIPTION

This is a base class for implementing virtual base classes (what some
people call an abstract class).  Kinda kooky.  It allows you to
explicitly declare what methods are virtual and that must be
implemented by subclasses.  This might seem silly, since your program
will halt and catch fire when an unimplemented virtual method is hit
anyway, but there's some benefits.

The error message is more informative.  Instead of the usual
"Can't locate object method" error, you'll get one explaining that a
virtual method was left unimplemented.

Subclass authors can explicitly check to make sure they've implemented
all the necessary virtual methods.  When used as part of a regression
test, it will shield against the virtual method requirements changing
out from under the subclass.

Finally, subclass authors can get an explicit list of everything
they're expected to implement.

Doesn't hurt and it doesn't slow you down.


=head2 Methods

=over 4

=item B<virtual_methods>

  Virtual::Class->virtual_methods(@virtual_methods);
  my @must_implement = Sub::Class->virtual_methods;

This is an accessor to the list of virtual_methods.  Virtual base
classes will declare their list of virtual methods.  Subclasses will
look at them.  Once the virtual methods are set they cannot be undone.

=for notes
I'm tempted to make it possible for the subclass to override the
virtual methods, perhaps add to them.  Too hairy to think about for
0.01.

=cut

#"#
sub virtual_methods {
    my($class) = shift;

    if( @_ ) {
        if( defined $class->__Virtual_Methods ) {
            require Carp;
            Carp::croak("Attempt to reset virtual methods.");
        }
        $class->_mk_virtual_methods(@_);
    }
    else {
        return @{$class->__Virtual_Methods};
    }
}


sub _mk_virtual_methods {
    no strict 'refs';   # symbol table mucking!  Getcher goloshes on.

    my($this_class, @methods) = @_;

    $this_class->__Virtual_Methods(\@methods);

    # private method to return the virtual base class
    *{$this_class.'::__virtual_base_class'} = sub {
        return $this_class;
    };

    foreach my $meth (@methods) {
        # Make sure the method doesn't already exist.
        if( $this_class->can($meth) ) {
            require Carp;
            Carp::croak("$this_class attempted to declare $meth() virtual ".
                        "but it appears to already be implemented!");
        }

        # Create a virtual method.
        *{$this_class.'::'.$meth} = sub {
            my($self) = shift;
            my($class) = ref $self || $self;

            require Carp;

            if( $class eq $this_class) {
                my $caller = caller;
                Carp::croak("$caller called the virtual base class ".
                            "$this_class directly!  Use a subclass instead");
            }
            else {
                Carp::croak("$class forgot to implement $meth()");
            }
        };
    }
}


=pod

=item B<missing_methods>

  my @missing_methods = Sub::Class->missing_methods;

Returns a list of methods Sub::Class has not yet implemented.

=cut

sub missing_methods {
    my($class) = shift;

    my @vmeths = $class->virtual_methods;
    my @super_classes = Class::ISA::self_and_super_path($class);
    my $vclass = $class->__virtual_base_class;

    # Remove everything in the hierarchy beyond, and including,
    # the virtual base class.  They don't concern us.
    my $sclass;
    do {
        $sclass = pop @super_classes;
        Carp::Assert::assert( defined $sclass ) if DEBUG;
    } until $sclass eq $vclass;

    my @missing = ();

    {
        no strict 'refs';
        METHOD: foreach my $meth (@vmeths) {
            CLASS: foreach my $class (@super_classes) {
                next METHOD if defined &{$class.'::'.$meth};
            }

            push @missing, $meth;
        }
    }

    return @missing;
}

=pod

=back

=head1 CAVEATS and BUGS

Autoloaded methods are currently not recognized.  I have no idea
how to solve this.


=head1 AUTHOR

Michael G Schwern E<lt>schwern@pobox.comE<gt>


=head1 LEGAL

Copyright 2000, 2001, 2003, 2004 Michael G Schwern

This program is free software; you can redistribute it and/or 
modify it under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>


=head1 SEE ALSO

L<Class::Virtually::Abstract>

=cut

return "Club sandwich";
