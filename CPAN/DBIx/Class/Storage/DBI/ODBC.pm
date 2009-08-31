package DBIx::Class::Storage::DBI::ODBC;
use strict;
use warnings;

use base qw/DBIx::Class::Storage::DBI/;
use mro 'c3';

sub _rebless {
    my ($self) = @_;

    my $dbtype = eval { $self->_get_dbh->get_info(17) };

    unless ( $@ ) {
        # Translate the backend name into a perl identifier
        $dbtype =~ s/\W/_/gi;
        my $subclass = "DBIx::Class::Storage::DBI::ODBC::${dbtype}";
        if ($self->load_optional_class($subclass) && !$self->isa($subclass)) {
            bless $self, $subclass;
            $self->_rebless;
        }
    }
}

sub _dbh_last_insert_id {
    my ($self, $dbh, $source, $col) = @_;

    # punt: if there is no derived class for the specific backend, attempt
    # to use the DBI->last_insert_id, which may not be sufficient (see the
    # discussion of last_insert_id in perldoc DBI)
    return $dbh->last_insert_id(undef, undef, $source->from, $col);
}

1;

=head1 NAME

DBIx::Class::Storage::DBI::ODBC - Base class for ODBC drivers

=head1 SYNOPSIS

  # In your table classes
  __PACKAGE__->load_components(qw/Core/);


=head1 DESCRIPTION

This class simply provides a mechanism for discovering and loading a sub-class
for a specific ODBC backend.  It should be transparent to the user.


=head1 AUTHORS

Marc Mims C<< <marc@questright.com> >>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut
