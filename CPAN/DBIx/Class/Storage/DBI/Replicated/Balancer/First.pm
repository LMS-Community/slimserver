package DBIx::Class::Storage::DBI::Replicated::Balancer::First;

use Moose;
with 'DBIx::Class::Storage::DBI::Replicated::Balancer';
use namespace::clean -except => 'meta';

=head1 NAME

DBIx::Class::Storage::DBI::Replicated::Balancer::First - Just get the First Balancer

=head1 SYNOPSIS

This class is used internally by L<DBIx::Class::Storage::DBI::Replicated>.  You
shouldn't need to create instances of this class.

=head1 DESCRIPTION

Given a pool (L<DBIx::Class::Storage::DBI::Replicated::Pool>) of replicated
database's (L<DBIx::Class::Storage::DBI::Replicated::Replicant>), defines a
method by which query load can be spread out across each replicant in the pool.

This Balancer just get's whatever is the first replicant in the pool

=head1 ATTRIBUTES

This class defines the following attributes.

=head1 METHODS

This class defines the following methods.

=head2 next_storage

Just get the first storage.  Probably only good when you have one replicant.

=cut

sub next_storage {
  return  (shift->pool->active_replicants)[0];
}

=head1 AUTHOR

John Napiorkowski <john.napiorkowski@takkle.com>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

__PACKAGE__->meta->make_immutable;

1;
