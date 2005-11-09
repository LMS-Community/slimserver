package Class::Virtually::Abstract;

require Class::Virtual;
@ISA = qw(Class::Virtual);

use strict;

use vars qw(%Registered $VERSION);
$VERSION = '0.03';

{
    no strict 'refs';

    sub virtual_methods {
        my($base_class) = shift;

        if( @_ and !$Registered{$base_class} ) {
            $Registered{$base_class} = 1;

            my($has_orig_import) = 0;

            # Shut up "subroutine import redefined"
            local $^W = 0;

            if( defined &{$base_class.'::import'} ) {
                # Divert the existing import method.
                $has_orig_import = 1;
                *{$base_class.'::__orig_import'} = \&{$base_class.'::import'};
            }

            # We can't use a closure here, SUPER wouldn't work right. :(
            eval <<"IMPORT";
            package $base_class;

            sub import {
                my \$class = shift;
                return if \$class eq '$base_class';

                my \@missing_methods = \$class->missing_methods;
                if (\@missing_methods) {
                    require Carp;
                    Carp::croak("Class \$class must define ".
                                join(', ', \@missing_methods).
                                " for class $base_class");
                }

                # Since import() is typically caller() sensitive, these
                # must be gotos.
                if( $has_orig_import ) {
                    goto &${base_class}::__orig_import;
                }
                elsif( my \$super_import = \$class->can('SUPER::import') ) {
                    goto &\$super_import;
                }
            }
IMPORT

        }

        $base_class->SUPER::virtual_methods(@_);
    }
}

1;


=pod

=head1 NAME

Class::Virtually::Abstract - Compile-time enforcement of Class::Virtual


=head1 SYNOPSIS

  package My::Virtual::Idaho;
  use base qw(Class::Virtually::Abstract);

  __PACKAGE__->virtual_methods(qw(new foo bar this that));


  package My::Private::Idaho;
  use base qw(My::Virtual::Idaho);

  sub new { ... }
  sub foo { ... }
  sub bar { ... }
  sub this { ... }
  # oops, forgot to implement that()!!  Whatever will happen?!


  # Meanwhile, in another piece of code!
  # KA-BLAM!  My::Private::Idaho fails to compile because it didn't
  # fully implement My::Virtual::Idaho.
  use My::Private::Idaho;

=head1 DESCRIPTION

This subclass of Class::Virtual provides B<compile-time> enforcement.
That means subclasses of your virtual class are B<required> to
implement all virtual methods or else it will not compile.


=head1 BUGS and CAVEATS

Because this relies on import() it is important that your classes are
B<use>d instead of B<require>d.  This is a problem, and I'm trying to
figure a way around it.

Also, if a subclass defines its own import() routine (I've done it)
Class::Virtually::Abstract's compile-time checking is defeated.

Got to think of a better way to do this besides import().


=head1 AUTHOR

Original idea and code from Ben Tilly's AbstractClass
http://www.perlmonks.org/index.pl?node_id=44300&lastnode_id=45341

Embraced and Extended by Michael G Schwern E<lt>schwern@pobox.comE<gt>


=head1 SEE ALSO

L<Class::Virtual>

=cut

1;
