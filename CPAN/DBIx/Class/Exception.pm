package DBIx::Class::Exception;

use strict;
use warnings;

use Carp::Clan qw/^DBIx::Class/;
use Scalar::Util qw/blessed/;

use overload
    '""' => sub { shift->{msg} },
    fallback => 1;

=head1 NAME

DBIx::Class::Exception - Exception objects for DBIx::Class

=head1 DESCRIPTION

Exception objects of this class are used internally by
the default error handling of L<DBIx::Class::Schema/throw_exception>
to prevent confusing and/or redundant re-application of L<Carp>'s
stack trace information.

These objects stringify to the contained error message, and use
overload fallback to give natural boolean/numeric values.

=head1 METHODS

=head2 throw

=over 4

=item Arguments: $exception_scalar, $stacktrace

=back

This is meant for internal use by L<DBIx::Class>'s C<throw_exception>
code, and shouldn't be used directly elsewhere.

Expects a scalar exception message.  The optional argument
C<$stacktrace> tells it to use L<Carp/longmess> instead of
L<Carp::Clan/croak>.

  DBIx::Class::Exception->throw('Foo');
  eval { ... }; DBIx::Class::Exception->throw($@) if $@;

=cut

sub throw {
    my ($class, $msg, $stacktrace) = @_;

    # Don't re-encapsulate exception objects of any kind
    die $msg if blessed($msg);

    # use Carp::Clan's croak if we're not stack tracing
    if(!$stacktrace) {
        local $@;
        eval { croak $msg };
        $msg = $@
    }
    else {
        $msg = Carp::longmess($msg);
    }

    my $self = { msg => $msg };
    bless $self => $class;

    die $self;
}

=head2 rethrow

This method provides some syntactic sugar in order to
re-throw exceptions.

=cut

sub rethrow {
    die shift;
}

=head1 AUTHORS

Brandon L. Black <blblack@gmail.com>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

1;
