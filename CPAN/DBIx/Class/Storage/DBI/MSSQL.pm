package DBIx::Class::Storage::DBI::MSSQL;

use strict;
use warnings;

use base qw/DBIx::Class::Storage::DBI/;

sub _dbh_last_insert_id {
  my ($self, $dbh, $source, $col) = @_;
  my ($id) = $dbh->selectrow_array('SELECT SCOPE_IDENTITY()');
  return $id;
}

sub build_datetime_parser {
  my $self = shift;
  my $type = "DateTime::Format::Strptime";
  eval "use ${type}";
  $self->throw_exception("Couldn't load ${type}: $@") if $@;
  return $type->new( pattern => '%Y-%m-%d %H:%M:%S' );  # %F %T
}

sub sqlt_type { 'SQLServer' }

sub _sql_maker_opts {
    my ( $self, $opts ) = @_;

    if ( $opts ) {
        $self->{_sql_maker_opts} = { %$opts };
    }

    return { limit_dialect => 'Top', %{$self->{_sql_maker_opts}||{}} };
}

1;

=head1 NAME

DBIx::Class::Storage::DBI::MSSQL - Storage::DBI subclass for MSSQL

=head1 SYNOPSIS

This subclass supports MSSQL, and can in theory be used directly
via the C<storage_type> mechanism:

  $schema->storage_type('::DBI::MSSQL');
  $schema->connect_info('dbi:....', ...);

However, as there is no L<DBD::MSSQL>, you will probably want to use
one of the other DBD-specific MSSQL classes, such as
L<DBIx::Class::Storage::DBI::Sybase::MSSQL>.  These classes will
merge this class with a DBD-specific class to obtain fully
correct behavior for your scenario.

=head1 METHODS

=head2 last_insert_id

=head2 sqlt_type

=head2 build_datetime_parser

The resulting parser handles the MSSQL C<DATETIME> type, but is almost
certainly not sufficient for the other MSSQL 2008 date/time types.

=head1 AUTHORS

Brian Cassidy <bricas@cpan.org>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut
