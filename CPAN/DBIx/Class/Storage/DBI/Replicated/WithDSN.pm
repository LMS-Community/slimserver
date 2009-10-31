package DBIx::Class::Storage::DBI::Replicated::WithDSN;

use Moose::Role;
use Scalar::Util 'reftype';
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

  my $dsn = eval { $self->dsn } || $self->_dbi_connect_info->[0];

  my($op, $rest) = (($sql=~m/^(\w+)(.+)$/),'NOP', 'NO SQL');
  my $storage_type = $self->can('active') ? 'REPLICANT' : 'MASTER';

  my $query = do {
    if ((reftype($dsn)||'') ne 'CODE') {
      "$op [DSN_$storage_type=$dsn]$rest";
    }
    elsif (my $id = eval { $self->id }) {
      "$op [$storage_type=$id]$rest";
    }
    else {
      "$op [$storage_type]$rest";
    }
  };

  $self->$method($query, @bind);
};

=head1 ALSO SEE

L<DBIx::Class::Storage::DBI>

=head1 AUTHOR

John Napiorkowski <john.napiorkowski@takkle.com>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

1;
