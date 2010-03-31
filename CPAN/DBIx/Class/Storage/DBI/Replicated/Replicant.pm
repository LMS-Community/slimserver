package DBIx::Class::Storage::DBI::Replicated::Replicant;

use Moose::Role;
requires qw/_query_start/;
with 'DBIx::Class::Storage::DBI::Replicated::WithDSN';
use MooseX::Types::Moose qw/Bool Str/;

use namespace::clean -except => 'meta';

=head1 NAME

DBIx::Class::Storage::DBI::Replicated::Replicant - A replicated DBI Storage Role

=head1 SYNOPSIS

This class is used internally by L<DBIx::Class::Storage::DBI::Replicated>.

=head1 DESCRIPTION

Replicants are DBI Storages that follow a master DBI Storage.  Typically this
is accomplished via an external replication system.  Please see the documents
for L<DBIx::Class::Storage::DBI::Replicated> for more details.

This class exists to define methods of a DBI Storage that only make sense when
it's a classic 'slave' in a pool of slave databases which replicate from a
given master database.

=head1 ATTRIBUTES

This class defines the following attributes.

=head2 active

This is a boolean which allows you to programmatically activate or deactivate a
replicant from the pool.  This way to you do stuff like disallow a replicant
when it get's too far behind the master, if it stops replicating, etc.

This attribute DOES NOT reflect a replicant's internal status, i.e. if it is
properly replicating from a master and has not fallen too many seconds behind a
reliability threshold.  For that, use L</is_replicating>  and L</lag_behind_master>.
Since the implementation of those functions database specific (and not all DBIC
supported DB's support replication) you should refer your database specific
storage driver for more information.

=cut

has 'active' => (
  is=>'rw',
  isa=>Bool,
  lazy=>1,
  required=>1,
  default=>1,
);

has dsn => (is => 'rw', isa => Str);
has id  => (is => 'rw', isa => Str);

=head1 METHODS

This class defines the following methods.

=head2 debugobj

Override the debugobj method to redirect this method call back to the master.

=cut

sub debugobj {
    return shift->schema->storage->debugobj;
}

=head1 ALSO SEE

L<http://en.wikipedia.org/wiki/Replicant>,
L<DBIx::Class::Storage::DBI::Replicated>

=head1 AUTHOR

John Napiorkowski <john.napiorkowski@takkle.com>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

1;
