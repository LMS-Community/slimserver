package DBIx::Class::Storage::DBI::ODBC;
use strict;
use warnings;

use base qw/DBIx::Class::Storage::DBI/;

sub _rebless {
    my ($self) = @_;

    my $dbh = $self->_dbh;
    my $dbtype = eval { $dbh->get_info(17) };
    unless ( $@ ) {
        # Translate the backend name into a perl identifier
        $dbtype =~ s/\W/_/gi;
        my $class = "DBIx::Class::Storage::DBI::ODBC::${dbtype}";
        eval "require $class";
        bless $self, $class unless $@;
    }
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

Marc Mims C<< <marc@sssonline.com> >>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut
