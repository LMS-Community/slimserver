package DBIx::Class::PK::Auto;

#use base qw/DBIx::Class::PK/;
use base qw/DBIx::Class/;
use strict;
use warnings;

=head1 NAME

DBIx::Class::PK::Auto - Automatic primary key class

=head1 SYNOPSIS

__PACKAGE__->load_components(qw/Core/);
__PACKAGE__->set_primary_key('id');

=head1 DESCRIPTION

This class overrides the insert method to get automatically incremented primary
keys.

  __PACKAGE__->load_components(qw/Core/);

PK::Auto is now part of Core.

See L<DBIx::Class::Manual::Component> for details of component interactions.

=head1 LOGIC

C<PK::Auto> does this by letting the database assign the primary key field and
fetching the assigned value afterwards.

=head1 METHODS

=head2 insert

The code that was handled here is now in Row for efficiency.

=head2 sequence

Manually define the correct sequence for your table, to avoid the overhead
associated with looking up the sequence automatically.

=cut

sub sequence {
    my ($self,$seq) = @_;
    foreach my $pri ($self->primary_columns) {
        $self->column_info($pri)->{sequence} = $seq;
    }
}

1;

=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut
