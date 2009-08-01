package Scope::Guard;

use strict;
use warnings;

use vars qw($VERSION);

$VERSION = '0.03';

sub new {
    my $class = shift;
    my $handler = shift() || die "Scope::Guard::new: no handler supplied";
    my $ref = ref $handler || '';

    die "Scope::Guard::new: invalid handler - expected CODE ref, got: '$ref'"
	unless (UNIVERSAL::isa($handler, 'CODE'));

    bless [ 0, $handler ], ref $class || $class;
}

sub dismiss {
    my $self = shift;
    my $dismiss = @_ ? shift : 1;

    $self->[0] = $dismiss;
}

sub DESTROY {
    my $self = shift;
    my ($dismiss, $handler) = @$self;

    $handler->() unless ($dismiss);
}

1;

__END__

=pod

=head1 NAME

Scope::Guard - lexically scoped resource management

=head1 SYNOPSIS

	my $sg = Scope::Guard->new(sub { ... });

	  # or

	my $sg = Scope::Guard->new(\&handler);

	$sg->dismiss(); # disable the handler

=head1 DESCRIPTION

This module provides a convenient way to perform cleanup or other forms of resource
management at the end of a scope. It is particularly useful when dealing with exceptions:
the Scope::Guard constructor takes a reference to a subroutine that is guaranteed to
be called even if the thread of execution is aborted prematurely. This effectively allows
lexically-scoped "promises" to be made that are automatically honoured by perl's garbage
collector.

For more information, see: L<http://www.cuj.com/documents/s=8000/cujcexp1812alexandr/>

=head2 new

=head3 usage

    my $sg = Scope::Guard->new(sub { ... });

	  # or

    my $sg = Scope::Guard->new(\&handler);

=head3 description

Create a new Scope::Guard object which calls the supplied handler when its C<DESTROY> method is
called, typically when it goes out of scope.

=head2 dismiss

=head3 usage

    $sg->dismiss();

	  # or

    $sg->dismiss(1);

=head3 description

Detach the handler from the Scope::Guard object. This revokes the "promise" to call the
handler when the object is destroyed.

The handler can be re-enabled by calling:

	$sg->dismiss(0);

=head1 VERSION

0.03

=head1 SEE ALSO

=over

=item * L<Hook::LexWrap|Hook::LexWrap>

=item * L<Hook::Scope|Hook::Scope>

=item * L<Sub::ScopeFinalizer|Sub::ScopeFinalizer>

=item * L<Object::Destroyer|Object::Destroyer>

=back

=head1 AUTHOR

chocolateboy: <chocolate.boy@email.com>

=head1 COPYRIGHT

Copyright (c) 2005-2007, chocolateboy.

This module is free software. It may be used, redistributed and/or modified under the same terms
as Perl itself.

=cut
