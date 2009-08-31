package DBIx::Class::Storage::DBI::DB2;

use strict;
use warnings;

use base qw/DBIx::Class::Storage::DBI/;
use mro 'c3';

sub _dbh_last_insert_id {
    my ($self, $dbh, $source, $col) = @_;

    my $sth = $dbh->prepare_cached('VALUES(IDENTITY_VAL_LOCAL())', {}, 3);
    $sth->execute();

    my @res = $sth->fetchrow_array();

    return @res ? $res[0] : undef;
}

sub datetime_parser_type { "DateTime::Format::DB2"; }

sub _sql_maker_opts {
    my ( $self, $opts ) = @_;

    if ( $opts ) {
        $self->{_sql_maker_opts} = { %$opts };
    }

    return { limit_dialect => 'RowNumberOver', %{$self->{_sql_maker_opts}||{}} };
}

1;

=head1 NAME

DBIx::Class::Storage::DBI::DB2 - Automatic primary key class for DB2

=head1 SYNOPSIS

  # In your table classes
  __PACKAGE__->load_components(qw/PK::Auto Core/);
  __PACKAGE__->set_primary_key('id');

=head1 DESCRIPTION

This class implements autoincrements for DB2.

=head1 AUTHORS

Jess Robinson

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut
