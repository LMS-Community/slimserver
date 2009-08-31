package DBIx::Class::Storage::DBI::Sybase;

use strict;
use warnings;

use base qw/
    DBIx::Class::Storage::DBI::Sybase::Base
    DBIx::Class::Storage::DBI::NoBindVars
/;
use mro 'c3';

sub _rebless {
    my $self = shift;

    my $dbtype = eval {
      @{$self->_get_dbh
        ->selectrow_arrayref(qq{sp_server_info \@attribute_id=1})
      }[2]
    };
    unless ( $@ ) {
        $dbtype =~ s/\W/_/gi;
        my $subclass = "DBIx::Class::Storage::DBI::Sybase::${dbtype}";
        if ($self->load_optional_class($subclass) && !$self->isa($subclass)) {
            bless $self, $subclass;
            $self->_rebless;
        }
    }
}

sub _dbh_last_insert_id {
    my ($self, $dbh, $source, $col) = @_;
    return ($dbh->selectrow_array('select @@identity'))[0];
}

1;

=head1 NAME

DBIx::Class::Storage::DBI::Sybase - Storage::DBI subclass for Sybase

=head1 SYNOPSIS

This subclass supports L<DBD::Sybase> for real Sybase databases.  If
you are using an MSSQL database via L<DBD::Sybase>, see
L<DBIx::Class::Storage::DBI::Sybase::MSSQL>.

=head1 CAVEATS

This storage driver uses L<DBIx::Class::Storage::DBI::NoBindVars> as a base.
This means that bind variables will be interpolated (properly quoted of course)
into the SQL query itself, without using bind placeholders.

More importantly this means that caching of prepared statements is explicitly
disabled, as the interpolation renders it useless.

=head1 AUTHORS

Brandon L Black <blblack@gmail.com>

Justin Hunter <justin.d.hunter@gmail.com>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut
