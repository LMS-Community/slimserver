package DBIx::Class::Storage::DBI::DB2;

use strict;
use warnings;

use base qw/DBIx::Class::Storage::DBI/;

# __PACKAGE__->load_components(qw/PK::Auto/);

sub last_insert_id
{
    my ($self) = @_;

    my $dbh = $self->_dbh;
    my $sth = $dbh->prepare_cached("VALUES(IDENTITY_VAL_LOCAL())", {}, 3);
    $sth->execute();

    my @res = $sth->fetchrow_array();

    return @res ? $res[0] : undef;
                         
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
