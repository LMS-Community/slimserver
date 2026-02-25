package Specio::Exception;

use strict;
use warnings;

use overload
    q{""}    => 'as_string',
    fallback => 1;

our $VERSION = '0.53';

use Devel::StackTrace;
use Scalar::Util qw( blessed );
use Specio::OO;

{
    my $attrs = {
        message => {
            isa      => 'Str',
            required => 1,
        },
        type => {
            does     => 'Specio::Constraint::Role::Interface',
            required => 1,
        },
        value => {
            required => 1,
        },
        stack_trace => {
            init_arg => undef,
        },
    };

    ## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
    sub _attrs {
        return $attrs;
    }
}

sub BUILD {
    my $self = shift;

    $self->{stack_trace}
        = Devel::StackTrace->new( ignore_package => __PACKAGE__ );

    return;
}

sub as_string {
    my $self = shift;

    my $str = $self->message;
    $str .= "\n\n" . $self->stack_trace->as_string;

    return $str;
}

sub throw {
    my $self = shift;

    die $self if blessed $self;

    die $self->new(@_);
}

__PACKAGE__->_ooify;

1;

# ABSTRACT: An exception class for type constraint failures

__END__

=pod

=encoding UTF-8

=head1 NAME

Specio::Exception - An exception class for type constraint failures

=head1 VERSION

version 0.53

=head1 SYNOPSIS

  use Try::Tiny;

  try {
      $type->validate_or_die($value);
  }
  catch {
      if ( $_->isa('Specio::Exception') ) {
          print $_->message, "\n";
          print $_->type->name, "\n";
          print $_->value, "\n";
      }
  };

=head1 DESCRIPTION

This exception class is thrown by Specio when a type check fails. It emulates
the L<Throwable::Error> API, but doesn't use that module to avoid adding a
dependency on L<Moo>.

=for Pod::Coverage BUILD throw

=head1 API

This class provides the following methods:

=head2 $exception->message

The error message associated with the exception.

=head2 $exception->stack_trace

A L<Devel::StackTrace> object for the exception.

=head2 $exception->type

The type constraint object against which the value failed.

=head2 $exception->value

The value that failed the type check.

=head2 $exception->as_string

The exception as a string. This includes the method and the stack trace.

=head1 OVERLOADING

This class overloads stringification to call the C<as_string> method.

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
