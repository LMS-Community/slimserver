package namespace::clean;

use warnings;
use strict;

our $VERSION = '0.27';
$VERSION = eval $VERSION if $VERSION =~ /_/; # numify for warning-free dev releases

our $STORAGE_VAR = '__NAMESPACE_CLEAN_STORAGE';

use B::Hooks::EndOfScope 'on_scope_end';

# FIXME This is a crock of shit, needs to go away
# currently here to work around https://rt.cpan.org/Ticket/Display.html?id=74151
# kill with fire when PS::XS is *finally* fixed
BEGIN {
  my $provider;

  if ( "$]" < 5.008007 ) {
    require Package::Stash::PP;
    $provider = 'Package::Stash::PP';
  }
  else {
    require Package::Stash;
    $provider = 'Package::Stash';
  }
  eval <<"EOS" or die $@;

sub stash_for (\$) {
  $provider->new(\$_[0]);
}

1;

EOS
}

use namespace::clean::_Util qw( DEBUGGER_NEEDS_CV_RENAME DEBUGGER_NEEDS_CV_PIVOT );

# Built-in debugger CV-retrieval fixups necessary before perl 5.15.5:
# since we are deleting the glob where the subroutine was originally
# defined, the assumptions below no longer hold.
#
# In 5.8.9 ~ 5.13.5 (inclusive) the debugger assumes that a CV can
# always be found under sub_fullname($sub)
# Workaround: use sub naming to properly name the sub hidden in the package's
# deleted-stash
#
# In the rest of the range ( ... ~ 5.8.8 and 5.13.6 ~ 5.15.4 ) the debugger
# assumes the name of the glob passed to entersub can be used to find the CV
# Workaround: realias the original glob to the deleted-stash slot
#
# While the errors manifest themselves inside perl5db.pl, they are caused by
# problems inside the interpreter.  If enabled ($^P & 0x01) and existent,
# the DB::sub sub will be called by the interpreter for any sub call rather
# that call the sub directly.  It is provided the real sub to call in $DB::sub,
# but the value given has the issues described above.  We only have to enable
# the workaround if DB::sub will be used.
#
# Can not tie constants to the current value of $^P directly,
# as the debugger can be enabled during runtime (kinda dubious)
#

my $RemoveSubs = sub {
    my $cleanee = shift;
    my $store   = shift;
    my $cleanee_stash = stash_for($cleanee);
    my $deleted_stash;

  SYMBOL:
    for my $f (@_) {

        # ignore already removed symbols
        next SYMBOL if $store->{exclude}{ $f };

        my $sub = $cleanee_stash->get_symbol("&$f")
          or next SYMBOL;

        my $need_debugger_fixup =
          ( DEBUGGER_NEEDS_CV_RENAME or DEBUGGER_NEEDS_CV_PIVOT )
            &&
          $^P & 0x01
            &&
          defined &DB::sub
            &&
          ref(my $globref = \$cleanee_stash->namespace->{$f}) eq 'GLOB'
            &&
         ( $deleted_stash ||= stash_for("namespace::clean::deleted::$cleanee") )
        ;

        # convince the Perl debugger to work
        # see the comment on top
        if ( DEBUGGER_NEEDS_CV_RENAME and $need_debugger_fixup ) {
          #
          # Note - both get_subname and set_subname are only compiled when CV_RENAME
          # is true ( the 5.8.9 ~ 5.12 range ). On other perls this entire block is
          # constant folded away, and so are the definitions in ::_Util
          #
          # Do not be surprised that they are missing without DEBUGGER_NEEDS_CV_RENAME
          #
          namespace::clean::_Util::get_subname( $sub ) eq  ( $cleanee_stash->name . "::$f" )
            and
          $deleted_stash->add_symbol(
            "&$f",
            namespace::clean::_Util::set_subname( $deleted_stash->name . "::$f", $sub ),
          );
        }
        elsif ( DEBUGGER_NEEDS_CV_PIVOT and $need_debugger_fixup ) {
          $deleted_stash->add_symbol("&$f", $sub);
        }

        my @symbols = map {
            my $name = $_ . $f;
            my $def = $cleanee_stash->get_symbol($name);
            defined($def) ? [$name, $def] : ()
        } '$', '@', '%', '';

        $cleanee_stash->remove_glob($f);

        # if this perl needs no renaming trick we need to
        # rename the original glob after the fact
        DEBUGGER_NEEDS_CV_PIVOT
          and
        $need_debugger_fixup
          and
        *$globref = $deleted_stash->namespace->{$f};

        $cleanee_stash->add_symbol(@$_) for @symbols;
    }
};

sub clean_subroutines {
    my ($nc, $cleanee, @subs) = @_;
    $RemoveSubs->($cleanee, {}, @subs);
}

sub import {
    my ($pragma, @args) = @_;

    my (%args, $is_explicit);

  ARG:
    while (@args) {

        if ($args[0] =~ /^\-/) {
            my $key = shift @args;
            my $value = shift @args;
            $args{ $key } = $value;
        }
        else {
            $is_explicit++;
            last ARG;
        }
    }

    my $cleanee = exists $args{ -cleanee } ? $args{ -cleanee } : scalar caller;
    if ($is_explicit) {
        on_scope_end {
            $RemoveSubs->($cleanee, {}, @args);
        };
    }
    else {

        # calling class, all current functions and our storage
        my $functions = $pragma->get_functions($cleanee);
        my $store     = $pragma->get_class_store($cleanee);
        my $stash     = stash_for($cleanee);

        # except parameter can be array ref or single value
        my %except = map {( $_ => 1 )} (
            $args{ -except }
            ? ( ref $args{ -except } eq 'ARRAY' ? @{ $args{ -except } } : $args{ -except } )
            : ()
        );

        # register symbols for removal, if they have a CODE entry
        for my $f (keys %$functions) {
            next if     $except{ $f };
            next unless $stash->has_symbol("&$f");
            $store->{remove}{ $f } = 1;
        }

        on_scope_end {
            $RemoveSubs->($cleanee, $store, keys %{ $store->{remove} });
        };

        return 1;
    }
}

sub unimport {
    my ($pragma, %args) = @_;

    # the calling class, the current functions and our storage
    my $cleanee   = exists $args{ -cleanee } ? $args{ -cleanee } : scalar caller;
    my $functions = $pragma->get_functions($cleanee);
    my $store     = $pragma->get_class_store($cleanee);

    # register all unknown previous functions as excluded
    for my $f (keys %$functions) {
        next if $store->{remove}{ $f }
             or $store->{exclude}{ $f };
        $store->{exclude}{ $f } = 1;
    }

    return 1;
}

sub get_class_store {
    my ($pragma, $class) = @_;
    my $stash = stash_for($class);
    my $var = "%$STORAGE_VAR";
    $stash->add_symbol($var, {})
        unless $stash->has_symbol($var);
    return $stash->get_symbol($var);
}

sub get_functions {
    my ($pragma, $class) = @_;

    my $stash = stash_for($class);
    return {
        map { $_ => $stash->get_symbol("&$_") }
            $stash->list_all_symbols('CODE')
    };
}

'Danger! Laws of Thermodynamics may not apply.'

__END__

=head1 NAME

namespace::clean - Keep imports and functions out of your namespace

=head1 SYNOPSIS

  package Foo;
  use warnings;
  use strict;

  use Carp qw(croak);   # 'croak' will be removed

  sub bar { 23 }        # 'bar' will be removed

  # remove all previously defined functions
  use namespace::clean;

  sub baz { bar() }     # 'baz' still defined, 'bar' still bound

  # begin to collection function names from here again
  no namespace::clean;

  sub quux { baz() }    # 'quux' will be removed

  # remove all functions defined after the 'no' unimport
  use namespace::clean;

  # Will print: 'No', 'No', 'Yes' and 'No'
  print +(__PACKAGE__->can('croak') ? 'Yes' : 'No'), "\n";
  print +(__PACKAGE__->can('bar')   ? 'Yes' : 'No'), "\n";
  print +(__PACKAGE__->can('baz')   ? 'Yes' : 'No'), "\n";
  print +(__PACKAGE__->can('quux')  ? 'Yes' : 'No'), "\n";

  1;

=head1 DESCRIPTION

=head2 Keeping packages clean

When you define a function, or import one, into a Perl package, it will
naturally also be available as a method. This does not per se cause
problems, but it can complicate subclassing and, for example, plugin
classes that are included via multiple inheritance by loading them as
base classes.

The C<namespace::clean> pragma will remove all previously declared or
imported symbols at the end of the current package's compile cycle.
Functions called in the package itself will still be bound by their
name, but they won't show up as methods on your class or instances.

By unimporting via C<no> you can tell C<namespace::clean> to start
collecting functions for the next C<use namespace::clean;> specification.

You can use the C<-except> flag to tell C<namespace::clean> that you
don't want it to remove a certain function or method. A common use would
be a module exporting an C<import> method along with some functions:

  use ModuleExportingImport;
  use namespace::clean -except => [qw( import )];

If you just want to C<-except> a single sub, you can pass it directly.
For more than one value you have to use an array reference.

=head3 Late binding caveat

Note that the L<technique used by this module|/IMPLEMENTATION DETAILS> relies
on perl having resolved all names to actual code references during the
compilation of a scope. While this is almost always what the interpreter does,
there are some exceptions, notably the L<sort SUBNAME|perlfunc/sort> style of
the C<sort> built-in invocation. The following example will not work, because
C<sort> does not try to resolve the function name to an actual code reference
until B<runtime>.

 use MyApp::Utils 'my_sorter';
 use namespace::clean;

 my @sorted = sort my_sorter @list;

You need to work around this by forcing a compile-time resolution like so:

 use MyApp::Utils 'my_sorter';
 use namespace::clean;

 my $my_sorter_cref = \&my_sorter;

 my @sorted = sort $my_sorter_cref @list;

=head2 Explicitly removing functions when your scope is compiled

It is also possible to explicitly tell C<namespace::clean> what packages
to remove when the surrounding scope has finished compiling. Here is an
example:

  package Foo;
  use strict;

  # blessed NOT available

  sub my_class {
      use Scalar::Util qw( blessed );
      use namespace::clean qw( blessed );

      # blessed available
      return blessed shift;
  }

  # blessed NOT available

=head2 Moose

When using C<namespace::clean> together with L<Moose> you want to keep
the installed C<meta> method. So your classes should look like:

  package Foo;
  use Moose;
  use namespace::clean -except => 'meta';
  ...

Same goes for L<Moose::Role>.

=head2 Cleaning other packages

You can tell C<namespace::clean> that you want to clean up another package
instead of the one importing. To do this you have to pass in the C<-cleanee>
option like this:

  package My::MooseX::namespace::clean;
  use strict;

  use namespace::clean (); # no cleanup, just load

  sub import {
      namespace::clean->import(
        -cleanee => scalar(caller),
        -except  => 'meta',
      );
  }

If you don't care about C<namespace::clean>s discover-and-C<-except> logic, and
just want to remove subroutines, try L</clean_subroutines>.

=head1 METHODS

=head2 clean_subroutines

This exposes the actual subroutine-removal logic.

  namespace::clean->clean_subroutines($cleanee, qw( subA subB ));

will remove C<subA> and C<subB> from C<$cleanee>. Note that this will remove the
subroutines B<immediately> and not wait for scope end. If you want to have this
effect at a specific time (e.g. C<namespace::clean> acts on scope compile end)
it is your responsibility to make sure it runs at that time.

=head2 import

Makes a snapshot of the current defined functions and installs a
L<B::Hooks::EndOfScope> hook in the current scope to invoke the cleanups.


=head2 unimport

This method will be called when you do a

  no namespace::clean;

It will start a new section of code that defines functions to clean up.

=head2 get_class_store

This returns a reference to a hash in a passed package containing
information about function names included and excluded from removal.

=head2 get_functions

Takes a class as argument and returns all currently defined functions
in it as a hash reference with the function name as key and a typeglob
reference to the symbol as value.

=head1 IMPLEMENTATION DETAILS

This module works through the effect that a

  delete $SomePackage::{foo};

will remove the C<foo> symbol from C<$SomePackage> for run time lookups
(e.g., method calls) but will leave the entry alive to be called by
already resolved names in the package itself. C<namespace::clean> will
restore and therefor in effect keep all glob slots that aren't C<CODE>.

A test file has been added to the perl core to ensure that this behaviour
will be stable in future releases.

Just for completeness sake, if you want to remove the symbol completely,
use C<undef> instead.

=head1 SEE ALSO

L<B::Hooks::EndOfScope>

=head1 THANKS

Many thanks to Matt S Trout for the inspiration on the whole idea.

=head1 AUTHORS

=over

=item *

Robert 'phaylon' Sedlacek <rs@474.at>

=item *

Florian Ragwitz <rafl@debian.org>

=item *

Jesse Luehrs <doy@tozt.net>

=item *

Peter Rabbitson <ribasushi@cpan.org>

=item *

Father Chrysostomos <sprout@cpan.org>

=back

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2011 by L</AUTHORS>

This is free software; you can redistribute it and/or modify it under the same terms as the Perl 5 programming language system itself.
