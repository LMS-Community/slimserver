package DBIx::Class::Storage::DBI::AmbiguousGlob;

use strict;
use warnings;

use base 'DBIx::Class::Storage::DBI';
use mro 'c3';

=head1 NAME

DBIx::Class::Storage::DBI::AmbiguousGlob - Storage component for RDBMS supporting multicolumn in clauses

=head1 DESCRIPTION

Some servers choke on things like:

  COUNT(*) FROM (SELECT tab1.col, tab2.col FROM tab1 JOIN tab2 ... )

claiming that col is a duplicate column (it loses the table specifiers by
the time it gets to the *). Thus for any subquery count we select only the
primary keys of the main table in the inner query. This hopefully still
hits the indexes and keeps the server happy.

At this point the only overriden method is C<_subq_count_select()>

=cut

sub _subq_count_select {
  my ($self, $source, $rs_attrs) = @_;
  my @pcols = map { join '.', $rs_attrs->{alias}, $_ } ($source->primary_columns);
  return @pcols ? \@pcols : [ 1 ];
}

=head1 AUTHORS

See L<DBIx::Class/CONTRIBUTORS>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

1;
