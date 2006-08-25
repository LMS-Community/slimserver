package DBIx::Class::DB;

use strict;
use warnings;

use base qw/DBIx::Class/;
use DBIx::Class::Schema;
use DBIx::Class::Storage::DBI;
use DBIx::Class::ClassResolver::PassThrough;
use DBI;

__PACKAGE__->load_components(qw/ResultSetProxy/);

{
    no warnings 'once';
    *dbi_commit = \&txn_commit;
    *dbi_rollback = \&txn_rollback;
}

sub storage { shift->schema_instance(@_)->storage; }

=head1 NAME

DBIx::Class::DB - (DEPRECATED) classdata schema component

=head1 SYNOPSIS

  package MyDB;

  use base qw/DBIx::Class/;
  __PACKAGE__->load_components('DB');

  __PACKAGE__->connection('dbi:...', 'user', 'pass', \%attrs);

  package MyDB::MyTable;

  use base qw/MyDB/;
  __PACKAGE__->load_components('Core'); # just load this in MyDB if it will
                                        # always be there

  ...

=head1 DESCRIPTION

This class is designed to support the Class::DBI connection-as-classdata style
for DBIx::Class. You are *strongly* recommended to use a DBIx::Class::Schema
instead; DBIx::Class::DB will not undergo new development and will be moved
to being a CDBICompat-only component before 1.0.

=head1 METHODS

=head2 storage

Sets or gets the storage backend. Defaults to L<DBIx::Class::Storage::DBI>.

=head2 class_resolver

****DEPRECATED****

Sets or gets the class to use for resolving a class. Defaults to
L<DBIx::Class::ClassResolver::Passthrough>, which returns whatever you give
it. See resolve_class below.

=cut

__PACKAGE__->mk_classdata('class_resolver' =>
                          'DBIx::Class::ClassResolver::PassThrough');

=head2 connection

  __PACKAGE__->connection($dsn, $user, $pass, $attrs);

Specifies the arguments that will be passed to DBI->connect(...) to
instantiate the class dbh when required.

=cut

sub connection {
  my ($class, @info) = @_;
  $class->setup_schema_instance unless $class->can('schema_instance');
  $class->schema_instance->connection(@info);
}

=head2 setup_schema_instance

Creates a class method ->schema_instance which contains a DBIx::Class::Schema;
all class-method operations are proxies through to this object. If you don't
call ->connection in your DBIx::Class::DB subclass at load time you *must*
call ->setup_schema_instance in order for subclasses to find the schema and
register themselves with it.

=cut

sub setup_schema_instance {
  my $class = shift;
  my $schema = {};
  bless $schema, 'DBIx::Class::Schema';
  $class->mk_classdata('schema_instance' => $schema);
}

=head2 txn_begin

Begins a transaction (does nothing if AutoCommit is off).

=cut

sub txn_begin { shift->schema_instance->txn_begin(@_); }

=head2 txn_commit

Commits the current transaction.

=cut

sub txn_commit { shift->schema_instance->txn_commit(@_); }

=head2 txn_rollback

Rolls back the current transaction.

=cut

sub txn_rollback { shift->schema_instance->txn_rollback(@_); }

=head2 txn_do

Executes a block of code transactionally. If this code reference
throws an exception, the transaction is rolled back and the exception
is rethrown. See L<DBIx::Class::Schema/"txn_do"> for more details.

=cut

sub txn_do { shift->schema_instance->txn_do(@_); }

{
  my $warn;

  sub resolve_class {
    warn "resolve_class deprecated as of 0.04999_02" unless $warn++;
    return shift->class_resolver->class(@_);
  }
}

=head2 resultset_instance

Returns an instance of a resultset for this class - effectively
mapping the L<Class::DBI> connection-as-classdata paradigm into the
native L<DBIx::Class::ResultSet> system.

=cut

sub resultset_instance {
  my $class = ref $_[0] || $_[0];
  my $source = $class->result_source_instance;
  if ($source->result_class ne $class) {
    $source = $source->new($source);
    $source->result_class($class);
  }
  return $source->resultset;
}

=head2 resolve_class

****DEPRECATED****

See L<class_resolver>

=head2 dbi_commit

****DEPRECATED****

Alias for L<txn_commit>

=head2 dbi_rollback

****DEPRECATED****

Alias for L<txn_rollback>

=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

1;
