package DBIx::Class::PK;

use strict;
use warnings;

use base qw/DBIx::Class::Row/;

=head1 NAME

DBIx::Class::PK - Primary Key class

=head1 SYNOPSIS

=head1 DESCRIPTION

This class contains methods for handling primary keys and methods
depending on them.

=head1 METHODS

=cut

sub _ident_values {
  my ($self) = @_;
  return (map { $self->{_column_data}{$_} } $self->primary_columns);
}

=head2 discard_changes ($attrs)

Re-selects the row from the database, losing any changes that had
been made.

This method can also be used to refresh from storage, retrieving any
changes made since the row was last read from storage.

$attrs is expected to be a hashref of attributes suitable for passing as the
second argument to $resultset->search($cond, $attrs);

=cut

sub discard_changes {
  my ($self, $attrs) = @_;
  delete $self->{_dirty_columns};
  return unless $self->in_storage; # Don't reload if we aren't real!
  
  if( my $current_storage = $self->get_from_storage($attrs)) {
  	
    # Set $self to the current.
  	%$self = %$current_storage;
  	
    # Avoid a possible infinite loop with
    # sub DESTROY { $_[0]->discard_changes }
    bless $current_storage, 'Do::Not::Exist';
    
    return $self;  	
  } else {
    $self->in_storage(0);
    return $self;  	
  }
}

=head2 id

Returns the primary key(s) for a row. Can't be called as
a class method.

=cut

sub id {
  my ($self) = @_;
  $self->throw_exception( "Can't call id() as a class method" )
    unless ref $self;
  my @pk = $self->_ident_values;
  return (wantarray ? @pk : $pk[0]);
}

=head2 ID

Returns a unique id string identifying a row object by primary key.
Used by L<DBIx::Class::CDBICompat::LiveObjectIndex> and
L<DBIx::Class::ObjectCache>.

=cut

sub ID {
  my ($self) = @_;
  $self->throw_exception( "Can't call ID() as a class method" )
    unless ref $self;
  return undef unless $self->in_storage;
  return $self->_create_ID(map { $_ => $self->{_column_data}{$_} }
                             $self->primary_columns);
}

sub _create_ID {
  my ($self,%vals) = @_;
  return undef unless 0 == grep { !defined } values %vals;
  return join '|', ref $self || $self, $self->result_source->name,
    map { $_ . '=' . $vals{$_} } sort keys %vals;
}

=head2 ident_condition

  my $cond = $result_source->ident_condition();

  my $cond = $result_source->ident_condition('alias');

Produces a condition hash to locate a row based on the primary key(s).

=cut

sub ident_condition {
  my ($self, $alias) = @_;
  my %cond;
  my $prefix = defined $alias ? $alias.'.' : '';
  $cond{$prefix.$_} = $self->get_column($_) for $self->primary_columns;
  return \%cond;
}

1;

=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

