package # Hide from PAUSE
  DBIx::Class::SQLAHacks::MSSQL;

use base qw( DBIx::Class::SQLAHacks );
use Carp::Clan qw/^DBIx::Class|^SQL::Abstract/;

#
# MSSQL is retarded wrt TOP (crappy limit) and ordering.
# One needs to add a TOP to *all* ordered subqueries, if
# TOP has been used in the statement at least once.
# Do it here.
#
sub select {
  my $self = shift;

  my ($sql, @bind) = $self->SUPER::select (@_);

  # ordering was requested and there are at least 2 SELECT/FROM pairs
  # (thus subquery), and there is no TOP specified
  if (
    $sql =~ /\bSELECT\b .+? \bFROM\b .+? \bSELECT\b .+? \bFROM\b/isx
      &&
    $sql !~ /^ \s* SELECT \s+ TOP \s+ \d+ /xi
      &&
    scalar $self->_order_by_chunks ($_[3]->{order_by})
  ) {
    $sql =~ s/^ \s* SELECT \s/SELECT TOP 100 PERCENT /xi;
  }

  return wantarray ? ($sql, @bind) : $sql;
}

1;
