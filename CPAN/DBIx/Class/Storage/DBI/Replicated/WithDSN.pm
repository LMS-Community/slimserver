package DBIx::Class::Storage::DBI::Replicated::WithDSN;

use Moose::Role;
requires qw/_query_start/;

use namespace::clean -except => 'meta';

=head1 NAME

DBIx::Class::Storage::DBI::Replicated::WithDSN - A DBI Storage Role with DSN
information in trace output

=head1 SYNOPSIS

This class is used internally by L<DBIx::Class::Storage::DBI::Replicated>.
    
=head1 DESCRIPTION

This role adds C<DSN: > info to storage debugging output.

=head1 METHODS

This class defines the following methods.

=head2 around: _query_start

Add C<DSN: > to debugging output.

=cut

around '_query_start' => sub {
  my ($method, $self, $sql, @bind) = @_;
  my $dsn = $self->_dbi_connect_info->[0];
  $self->$method("DSN: $dsn SQL: $sql", @bind);
};

=head1 ALSO SEE

L<DBIx::Class::Storage::DBI>

=head1 AUTHOR

John Napiorkowski <john.napiorkowski@takkle.com>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

1;
