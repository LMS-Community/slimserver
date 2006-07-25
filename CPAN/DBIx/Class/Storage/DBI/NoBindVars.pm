package DBIx::Class::Storage::DBI::NoBindVars;

use strict;
use warnings;

use base 'DBIx::Class::Storage::DBI';

sub _execute {
  my ($self, $op, $extra_bind, $ident, @args) = @_;
  my ($sql, @bind) = $self->sql_maker->$op($ident, @args);
  unshift(@bind, @$extra_bind) if $extra_bind;
  if ($self->debug) {
    my @debug_bind = map { defined $_ ? qq{'$_'} : q{'NULL'} } @bind;
    $self->debugobj->query_start($sql, @debug_bind);
  }

  while(my $bvar = shift @bind) {
    $bvar = $self->dbh->quote($bvar);
    $sql =~ s/\?/$bvar/;
  }

  my $sth = eval { $self->sth($sql,$op) };

  if (!$sth || $@) {
    $self->throw_exception(
      'no sth generated via sql (' . ($@ || $self->_dbh->errstr) . "): $sql"
    );
  }

  my $rv;
  if ($sth) {
    my $time = time();
    $rv = eval { $sth->execute };

    if ($@ || !$rv) {
      $self->throw_exception("Error executing '$sql': ".($@ || $sth->errstr));
    }
  } else {
    $self->throw_exception("'$sql' did not generate a statement.");
  }
  if ($self->debug) {
    my @debug_bind = map { defined $_ ? qq{`$_'} : q{`NULL'} } @bind;
    $self->debugobj->query_end($sql, @debug_bind);
  }
  return (wantarray ? ($rv, $sth, @bind) : $rv);
}

1;

=head1 NAME 

DBIx::Class::Storage::DBI::NoBindVars - Sometime DBDs have poor to no support for bind variables

=head1 SYNOPSIS

=head1 DESCRIPTION

This class allows queries to work when the DBD or underlying library does not
support the usual C<?> placeholders, or at least doesn't support them very
well, as is the case with L<DBD::Sybase>

=head1 AUTHORS

Brandon Black <blblack@gmail.com>
Trym Skaar <trym@tryms.no>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut
