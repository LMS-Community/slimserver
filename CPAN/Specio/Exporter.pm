package Specio::Exporter;

use strict;
use warnings;

our $VERSION = '0.53';

use parent 'Exporter';

use Specio::Helpers qw( install_t_sub );
use Specio::Registry
    qw( exportable_types_for_package internal_types_for_package register );

my %Exported;

sub import {
    my $package  = shift;
    my $reexport = shift;

    my $caller = caller();

    return if $Exported{$caller}{$package};

    my $exported = exportable_types_for_package($package);

    while ( my ( $name, $type ) = each %{$exported} ) {
        register( $caller, $name, $type->clone, $reexport );
    }

    install_t_sub(
        $caller,
        internal_types_for_package($caller),
    );

    if ( $package->can('_also_export') ) {
        for my $sub ( $package->_also_export ) {
            ## no critic (TestingAndDebugging::ProhibitNoStrict)
            no strict 'refs';
            *{ $caller . '::' . $sub } = \&{ $package . '::' . $sub };
        }
    }

    $Exported{$caller}{$package} = 1;

    return;
}

1;

# ABSTRACT: Base class for type libraries

__END__

=pod

=encoding UTF-8

=head1 NAME

Specio::Exporter - Base class for type libraries

=head1 VERSION

version 0.53

=head1 SYNOPSIS

    package MyApp::Type::Library;

    use parent 'Specio::Exporter';

    use Specio::Declare;

    declare( ... );

    # more types here

    package MyApp::Foo;

    use MyApp::Type::Library

=head1 DESCRIPTION

Inheriting from this package makes your package a type exporter. By default,
types defined in a package are never visible outside of the package. When you
inherit from this package, all the types you define internally become available
via exports.

The exported types are available through the importing package's C<t>
subroutine.

By default, types your package imports are not re-exported:

  package MyApp::Type::Library;

  use parent 'Specio::Exporter';

  use Specio::Declare;
  use Specio::Library::Builtins;

In this case, the types provided by L<Specio::Library::Builtins> are not
exported to packages which C<use MyApp::Type::Library>.

You can explicitly ask for types to be re-exported:

  package MyApp::Type::Library;

  use parent 'Specio::Exporter';

  use Specio::Declare;
  use Specio::Library::Builtins -reexport;

In this case, packages which C<use MyApp::Type::Library> will get all the types
from L<Specio::Library::Builtins> as well as any types defined in
C<MyApp::Type::Library>.

=head1 ADDITIONAL EXPORTS

If you want to export some additional subroutines from a package which has
C<Specio::Exporter> as its parent, define a sub named C<_also_export>. This sub
should return a I<list> of subroutines defined in your package that should also
be exported. These subs will be exported unconditionally to any package that
uses your package.

=head1 COMBINING LIBRARIES WITH L<Specio::Subs>

You can combine loading libraries with subroutine generation using
L<Specio::Subs> by using C<_also_export> and
C<Specio::Subs::subs_installed_into>:

    package My::Library;

    use My::Library::Internal -reexport;
    use Specio::Library::Builtins -reexport;
    use Specio::Subs qw( My::Library::Internal Specio::Library::Builtins );

    sub _also_export {
        return Specio::Subs::subs_installed_into(__PACKAGE__);
    }

=head1 SUPPORT

Bugs may be submitted at L<https://github.com/houseabsolute/Specio/issues>.

=head1 SOURCE

The source code repository for Specio can be found at L<https://github.com/houseabsolute/Specio>.

=head1 AUTHOR

Dave Rolsky <autarch@urth.org>

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2012 - 2025 by Dave Rolsky.

This is free software, licensed under:

  The Artistic License 2.0 (GPL Compatible)

The full text of the license can be found in the
F<LICENSE> file included with this distribution.

=cut
