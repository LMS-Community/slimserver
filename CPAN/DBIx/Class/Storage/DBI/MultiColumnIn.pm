package DBIx::Class::Storage::DBI::MultiColumnIn;

use strict;
use warnings;

use base 'DBIx::Class::Storage::DBI';
use mro 'c3';

=head1 NAME 

DBIx::Class::Storage::DBI::MultiColumnIn - Storage component for RDBMS supporting multicolumn in clauses

=head1 DESCRIPTION

While ANSI SQL does not define a multicolumn in operator, many databases can
in fact understand WHERE (cola, colb) IN ( SELECT subcol_a, subcol_b ... )
The storage class for any such RDBMS should inherit from this class, in order
to dramatically speed up update/delete operations on joined multipk resultsets.

At this point the only overriden method is C<_multipk_update_delete()>

=cut

sub _multipk_update_delete {
  my $self = shift;
  my ($rs, $op, $values) = @_;

  my $rsrc = $rs->result_source;
  my @pcols = $rsrc->primary_columns;
  my $attrs = $rs->_resolved_attrs;

  # naive check - this is an internal method after all, we should know what we are doing 
  $self->throw_exception ('Number of columns selected by supplied resultset does not match number of primary keys')
    if ( ref $attrs->{select} ne 'ARRAY' or @{$attrs->{select}} != @pcols );

  # This is hideously ugly, but SQLA does not understand multicol IN expressions
  my $sqla = $self->_sql_maker;
  my ($sql, @bind) = @${$rs->as_query};
  $sql = sprintf ('(%s) IN %s',   # the as_query stuff is already enclosed in ()s
    join (', ', map { $sqla->_quote ($_) } @pcols),
    $sql,
  );

  return $self->$op (
    $rsrc,
    $op eq 'update' ? $values : (),
    \[$sql, @bind],
  );

}

=head1 AUTHORS

See L<DBIx::Class/CONTRIBUTORS>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

1;
