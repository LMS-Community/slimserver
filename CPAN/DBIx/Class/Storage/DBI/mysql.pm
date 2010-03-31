package DBIx::Class::Storage::DBI::mysql;

use strict;
use warnings;

use base qw/
  DBIx::Class::Storage::DBI::MultiColumnIn
  DBIx::Class::Storage::DBI::AmbiguousGlob
  DBIx::Class::Storage::DBI
/;
use mro 'c3';

__PACKAGE__->sql_maker_class('DBIx::Class::SQLAHacks::MySQL');

sub with_deferred_fk_checks {
  my ($self, $sub) = @_;

  $self->_do_query('SET FOREIGN_KEY_CHECKS = 0');
  $sub->();
  $self->_do_query('SET FOREIGN_KEY_CHECKS = 1');
}

sub connect_call_set_strict_mode {
  my $self = shift;

  # the @@sql_mode puts back what was previously set on the session handle
  $self->_do_query(q|SET SQL_MODE = CONCAT('ANSI,TRADITIONAL,ONLY_FULL_GROUP_BY,', @@sql_mode)|);
  $self->_do_query(q|SET SQL_AUTO_IS_NULL = 0|);
}

sub _dbh_last_insert_id {
  my ($self, $dbh, $source, $col) = @_;
  $dbh->{mysql_insertid};
}

# we need to figure out what mysql version we're running
sub sql_maker {
  my $self = shift;

  unless ($self->_sql_maker) {
    my $maker = $self->next::method (@_);

    # mysql 3 does not understand a bare JOIN
    my $mysql_ver = $self->_get_dbh->get_info(18);
    $maker->{_default_jointype} = 'INNER' if $mysql_ver =~ /^3/;
  }

  return $self->_sql_maker;
}

sub sqlt_type {
  return 'MySQL';
}

sub _svp_begin {
    my ($self, $name) = @_;

    $self->_get_dbh->do("SAVEPOINT $name");
}

sub _svp_release {
    my ($self, $name) = @_;

    $self->_get_dbh->do("RELEASE SAVEPOINT $name");
}

sub _svp_rollback {
    my ($self, $name) = @_;

    $self->_get_dbh->do("ROLLBACK TO SAVEPOINT $name")
}

sub is_replicating {
    my $status = shift->_get_dbh->selectrow_hashref('show slave status');
    return ($status->{Slave_IO_Running} eq 'Yes') && ($status->{Slave_SQL_Running} eq 'Yes');
}

sub lag_behind_master {
    return shift->_get_dbh->selectrow_hashref('show slave status')->{Seconds_Behind_Master};
}

# MySql can not do subquery update/deletes, only way is slow per-row operations.
# This assumes you have set proper transaction isolation and use innodb.
sub _subq_update_delete {
  return shift->_per_row_update_delete (@_);
}

1;

=head1 NAME

DBIx::Class::Storage::DBI::mysql - Storage::DBI class implementing MySQL specifics

=head1 SYNOPSIS

Storage::DBI autodetects the underlying MySQL database, and re-blesses the
C<$storage> object into this class.

  my $schema = MyDb::Schema->connect( $dsn, $user, $pass, { on_connect_call => 'set_strict_mode' } );

=head1 DESCRIPTION

This class implements MySQL specific bits of L<DBIx::Class::Storage::DBI>.

It also provides a one-stop on-connect macro C<set_strict_mode> which sets
session variables such that MySQL behaves more predictably as far as the
SQL standard is concerned.

=head1 AUTHORS

See L<DBIx::Class/CONTRIBUTORS>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut
