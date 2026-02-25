package Module::Implementation;
# git description: v0.08-2-gd599347
$Module::Implementation::VERSION = '0.09';

use strict;
use warnings;

use Module::Runtime 0.012 qw( require_module );
use Try::Tiny;

# This is needed for the benefit of Test::CleanNamespaces, which in turn loads
# Package::Stash, which in turn loads this module and expects a minimum
# version.
unless ( exists $Module::Implementation::{VERSION}
    && ${ $Module::Implementation::{VERSION} } ) {

    $Module::Implementation::{VERSION} = \42;
}

my %Implementation;

sub build_loader_sub {
    my $caller = caller();

    return _build_loader( $caller, @_ );
}

sub _build_loader {
    my $package = shift;
    my %args    = @_;

    my @implementations = @{ $args{implementations} };
    my @symbols = @{ $args{symbols} || [] };

    my $implementation;
    my $env_var = uc $package;
    $env_var =~ s/::/_/g;
    $env_var .= '_IMPLEMENTATION';

    return sub {
        my ( $implementation, $loaded ) = _load_implementation(
            $package,
            $ENV{$env_var},
            \@implementations,
        );

        $Implementation{$package} = $implementation;

        _copy_symbols( $loaded, $package, \@symbols );

        return $loaded;
    };
}

sub implementation_for {
    my $package = shift;

    return $Implementation{$package};
}

sub _load_implementation {
    my $package         = shift;
    my $env_value       = shift;
    my $implementations = shift;

    if ($env_value) {
        die "$env_value is not a valid implementation for $package"
            unless grep { $_ eq $env_value } @{$implementations};

        my $requested = "${package}::$env_value";

        # Values from the %ENV hash are tainted. We know it's safe to untaint
        # this value because the value was one of our known implementations.
        ($requested) = $requested =~ /^(.+)$/;

        try {
            require_module($requested);
        }
        catch {
            require Carp;
            Carp::croak("Could not load $requested: $_");
        };

        return ( $env_value, $requested );
    }
    else {
        my $err;
        for my $possible ( @{$implementations} ) {
            my $try = "${package}::$possible";

            my $ok;
            try {
                require_module($try);
                $ok = 1;
            }
            catch {
                $err .= $_ if defined $_;
            };

            return ( $possible, $try ) if $ok;
        }

        require Carp;
        if ( defined $err && length $err ) {
            Carp::croak(
                "Could not find a suitable $package implementation: $err");
        }
        else {
            Carp::croak(
                'Module::Runtime failed to load a module but did not throw a real error. This should never happen. Something is very broken'
            );
        }
    }
}

sub _copy_symbols {
    my $from_package = shift;
    my $to_package   = shift;
    my $symbols      = shift;

    for my $sym ( @{$symbols} ) {
        my $type = $sym =~ s/^([\$\@\%\&\*])// ? $1 : '&';

        my $from = "${from_package}::$sym";
        my $to   = "${to_package}::$sym";

        {
            no strict 'refs';
            no warnings 'once';

            # Copied from Exporter
            *{$to}
                = $type eq '&' ? \&{$from}
                : $type eq '$' ? \${$from}
                : $type eq '@' ? \@{$from}
                : $type eq '%' ? \%{$from}
                : $type eq '*' ? *{$from}
                : die
                "Can't copy symbol from $from_package to $to_package: $type$sym";
        }
    }
}

1;

# ABSTRACT: Loads one of several alternate underlying implementations for a module

__END__

=pod

=encoding UTF-8

=head1 NAME

Module::Implementation - Loads one of several alternate underlying implementations for a module

=head1 VERSION

version 0.09

=head1 SYNOPSIS

  package Foo::Bar;

  use Module::Implementation;

  BEGIN {
      my $loader = Module::Implementation::build_loader_sub(
          implementations => [ 'XS',  'PurePerl' ],
          symbols         => [ 'run', 'check' ],
      );

      $loader->();
  }

  package Consumer;

  # loads the first viable implementation
  use Foo::Bar;

=head1 DESCRIPTION

This module abstracts out the process of choosing one of several underlying
implementations for a module. This can be used to provide XS and pure Perl
implementations of a module, or it could be used to load an implementation for
a given OS or any other case of needing to provide multiple implementations.

This module is only useful when you know all the implementations ahead of
time. If you want to load arbitrary implementations then you probably want
something like a plugin system, not this module.

=head1 API

This module provides two subroutines, neither of which are exported.

=head2 Module::Implementation::build_loader_sub(...)

This subroutine takes the following arguments.

=over 4

=item * implementations

This should be an array reference of implementation names. Each name should
correspond to a module in the caller's namespace.

In other words, using the example in the L</SYNOPSIS>, this module will look
for the C<Foo::Bar::XS> and C<Foo::Bar::PurePerl> modules.

This argument is required.

=item * symbols

A list of symbols to copy from the implementation package to the calling
package.

These can be prefixed with a variable type: C<$>, C<@>, C<%>, C<&>, or
C<*)>. If no prefix is given, the symbol is assumed to be a subroutine.

This argument is optional.

=back

This subroutine I<returns> the implementation loader as a sub reference.

It is up to you to call this loader sub in your code.

I recommend that you I<do not> call this loader in an C<import()> sub. If a
caller explicitly requests no imports, your C<import()> sub will not be run at
all, which can cause weird breakage.

=head2 Module::Implementation::implementation_for($package)

Given a package name, this subroutine returns the implementation that was
loaded for the package. This is not a full package name, just the suffix that
identifies the implementation. For the L</SYNOPSIS> example, this subroutine
would be called as C<Module::Implementation::implementation_for('Foo::Bar')>,
and it would return "XS" or "PurePerl".

=head1 HOW THE IMPLEMENTATION LOADER WORKS

The implementation loader works like this ...

First, it checks for an C<%ENV> var specifying the implementation to load. The
env var is based on the package name which loads the implementations. The
C<::> package separator is replaced with C<_>, and made entirely
upper-case. Finally, we append "_IMPLEMENTATION" to this name.

So in our L</SYNOPSIS> example, the corresponding C<%ENV> key would be
C<FOO_BAR_IMPLEMENTATION>.

If this is set, then the loader will B<only> try to load this one
implementation.

If the env var requests an implementation which doesn't match one of the
implementations specified when the loader was created, an error is thrown.

If this one implementation fails to load then loader throws an error. This is
useful for testing. You can request a specific implementation in a test file
by writing something like this:

  BEGIN { $ENV{FOO_BAR_IMPLEMENTATION} = 'XS' }
  use Foo::Bar;

If the environment variable is I<not> set, then the loader simply tries the
implementations originally passed to C<Module::Implementation>. The
implementations are tried in the order in which they were originally passed.

The loader will use the first implementation that loads without an error. It
will copy any requested symbols from this implementation.

If none of the implementations can be loaded, then the loader throws an
exception.

The loader returns the name of the package it loaded.

=head1 AUTHOR

Dave Rolsky <autarch@urth.org>

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2014 by Dave Rolsky.

This is free software, licensed under:

  The Artistic License 2.0 (GPL Compatible)

=cut
