package DBIx::Class::Storage::DBI::ODBC::DB2_400_SQL;
use strict;
use warnings;

use base qw/DBIx::Class::Storage::DBI::ODBC/;

sub _dbh_last_insert_id {
    my ($self, $dbh, $source, $col) = @_;

    # get the schema/table separator:
    #    '.' when SQL naming is active
    #    '/' when system naming is active
    my $sep = $dbh->get_info(41);
    my $sth = $dbh->prepare_cached(
        "SELECT IDENTITY_VAL_LOCAL() FROM SYSIBM${sep}SYSDUMMY1", {}, 3);
    $sth->execute();

    my @res = $sth->fetchrow_array();

    return @res ? $res[0] : undef;
}

sub _sql_maker_opts {
    my ($self) = @_;
    
    $self->dbh_do(sub {
        my ($self, $dbh) = @_;

        return {
            limit_dialect => 'FetchFirst',
            name_sep => $dbh->get_info(41)
        };
    });
}

1;

=head1 NAME

DBIx::Class::Storage::DBI::ODBC::DB2_400_SQL - Support specific to DB2/400
over ODBC

=head1 SYNOPSIS

  # In your table classes
  __PACKAGE__->load_components(qw/PK::Auto Core/);
  __PACKAGE__->set_primary_key('id');


=head1 DESCRIPTION

This class implements support specific to DB2/400 over ODBC, including
auto-increment primary keys, SQL::Abstract::Limit dialect, and name separator
for connections using either SQL naming or System naming.


=head1 AUTHORS

Marc Mims C<< <marc@questright.com> >>

Based on DBIx::Class::Storage::DBI::DB2 by Jess Robinson.

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut
