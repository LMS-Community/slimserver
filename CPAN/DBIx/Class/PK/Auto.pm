package DBIx::Class::PK::Auto;

#use base qw/DBIx::Class::PK/;
use base qw/DBIx::Class/;
use strict;
use warnings;

=head1 NAME 

DBIx::Class::PK::Auto - Automatic primary key class

=head1 SYNOPSIS

__PACKAGE__->load_components(qw/PK::Auto Core/);
__PACKAGE__->set_primary_key('id');

=head1 DESCRIPTION

This class overrides the insert method to get automatically incremented primary
keys.

  __PACKAGE__->load_components(qw/PK::Auto Core/);

Note that C<PK::Auto> is specified as the left of the Core component.
See L<DBIx::Class::Manual::Component> for details of component interactions.

=head1 LOGIC

C<PK::Auto> does this by letting the database assign the primary key field and
fetching the assigned value afterwards.

=head1 METHODS

=head2 insert

Overrides C<insert> so that it will get the value of autoincremented primary
keys.

=cut

sub insert {
  my ($self, @rest) = @_;
  my $ret = $self->next::method(@rest);

  my ($pri, $too_many) = grep { !defined $self->get_column($_) } $self->primary_columns;
  return $ret unless defined $pri; # if all primaries are already populated, skip auto-inc
  $self->throw_exception( "More than one possible key found for auto-inc on ".ref $self )
    if defined $too_many;

  my $storage = $self->result_source->storage;
  $self->throw_exception( "Missing primary key but Storage doesn't support last_insert_id" ) unless $storage->can('last_insert_id');
  my $id = $storage->last_insert_id($self->result_source,$pri);
  $self->throw_exception( "Can't get last insert id" ) unless $id;
  $self->store_column($pri => $id);

  return $ret;
}

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
