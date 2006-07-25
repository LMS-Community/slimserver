package DBIx::Class::ResultSetColumn;
use strict;
use warnings;
use base 'DBIx::Class';

=head1 NAME

  DBIx::Class::ResultSetColumn - helpful methods for messing
  with a single column of the resultset

=head1 SYNOPSIS

  $rs = $schema->resultset('CD')->search({ artist => 'Tool' });
  $rs_column = $rs->get_column('year');
  $max_year = $rs_column->max; #returns latest year

=head1 DESCRIPTION

A convenience class used to perform operations on a specific column of a resultset.

=cut

=head1 METHODS

=head2 new

  my $obj = DBIx::Class::ResultSetColumn->new($rs, $column);

Creates a new resultset column object from the resultset and column passed as params

=cut

sub new {
  my ($class, $rs, $column) = @_;
  $class = ref $class if ref $class;

  my $object_ref = { _column => $column,
		     _parent_resultset => $rs };
  
  my $new = bless $object_ref, $class;
  $new->throw_exception("column must be supplied") unless ($column);
  return $new;
}

=head2 next

=over 4

=item Arguments: none

=item Return Value: $value

=back

Returns the next value of the column in the resultset (C<undef> is there is none).

Much like $rs->next but just returning the one value

=cut

sub next {
  my $self = shift;
    
  $self->{_resultset} = $self->{_parent_resultset}->search(undef, {select => [$self->{_column}], as => [$self->{_column}]}) unless ($self->{_resultset});
  my ($row) = $self->{_resultset}->cursor->next;
  return $row;
}

=head2 all

=over 4

=item Arguments: none

=item Return Value: @values

=back

Returns all values of the column in the resultset (C<undef> is there are none).

Much like $rs->all but returns values rather than row objects

=cut

sub all {
  my $self = shift;
  return map {$_->[0]} $self->{_parent_resultset}->search(undef, {select => [$self->{_column}], as => [$self->{_column}]})->cursor->all;
}

=head2 min

=over 4

=item Arguments: none

=item Return Value: $lowest_value

=back

Wrapper for ->func. Returns the lowest value of the column in the resultset (C<undef> is there are none).

=cut

sub min {
  my $self = shift;
  return $self->func('MIN');
}

=head2 max

=over 4

=item Arguments: none

=item Return Value: $highest_value

=back

Wrapper for ->func. Returns the highest value of the column in the resultset (C<undef> is there are none).

=cut

sub max {
  my $self = shift;
  return $self->func('MAX');
}

=head2 sum

=over 4

=item Arguments: none

=item Return Value: $sum_of_values

=back

Wrapper for ->func. Returns the sum of all the values in the column of the resultset. Use on varchar-like columns at your own risk.

=cut

sub sum {
  my $self = shift;
  return $self->func('SUM');
}

=head2 func

=over 4

=item Arguments: $function

=item Return Value: $function_return_value

=back

Runs a query using the function on the column and returns the value. For example 
  $rs = $schema->resultset("CD")->search({});
  $length = $rs->get_column('title')->func('LENGTH');

Produces the following SQL
  SELECT LENGTH( title ) from cd me

=cut

sub func {
  my $self = shift;
  my $function = shift;

  my ($row) = $self->{_parent_resultset}->search(undef, {select => {$function => $self->{_column}}, as => [$self->{_column}]})->cursor->next;
  return $row;
}

1;

=head1 AUTHORS

Luke Saunders <luke.saunders@gmail.com>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut
