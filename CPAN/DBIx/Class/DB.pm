package DBIx::Class::DB;

use strict;
use warnings;

use base qw/DBIx::Class/;
use DBIx::Class::Schema;
use DBIx::Class::Storage::DBI;
use DBIx::Class::ClassResolver::PassThrough;
use DBI;
use Scalar::Util;

unless ($INC{"DBIx/Class/CDBICompat.pm"}) {
  warn "IMPORTANT: DBIx::Class::DB is DEPRECATED AND *WILL* BE REMOVED. DO NOT USE.\n";
}

__PACKAGE__->load_components(qw/ResultSetProxy/);

{
    no warnings 'once';
    *dbi_commit = \&txn_commit;
    *dbi_rollback = \&txn_rollback;
}

sub storage { shift->schema_instance(@_)->storage; }

=head1 NAME

DBIx::Class::DB - (DEPRECATED) classdata schema component

=head1 DESCRIPTION

This class is designed to support the Class::DBI connection-as-classdata style
for DBIx::Class. You are *strongly* recommended to use a DBIx::Class::Schema
instead; DBIx::Class::DB will not undergo new development and will be moved
to being a CDBICompat-only component before 1.0. In order to discourage further
use, documentation has been removed as of 0.08000

=begin HIDE_BECAUSE_THIS_CLASS_IS_DEPRECATED

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
  $_[0]->result_source_instance->resultset
}

=head2 result_source_instance

Returns an instance of the result source for this class

=cut

__PACKAGE__->mk_classdata('_result_source_instance' => []);

# Yep. this is horrific. Basically what's happening here is that
# (with good reason) DBIx::Class::Schema copies the result source for
# registration. Because we have a retarded setup order forced on us we need
# to actually make our ->result_source_instance -be- the source used, and we
# need to get the source name and schema into ourselves. So this makes it
# happen.

sub _maybe_attach_source_to_schema {
  my ($class, $source) = @_;
  if (my $meth = $class->can('schema_instance')) {
    if (my $schema = $class->$meth) {
      $schema->register_class($class, $class);
      my $new_source = $schema->source($class);
      %$source = %$new_source;
      $schema->source_registrations->{$class} = $source;
    }
  }
}

sub result_source_instance {
  my $class = shift;
  $class = ref $class || $class;

  if (@_) {
    my $source = $_[0];
    $class->_result_source_instance([$source, $class]);
    $class->_maybe_attach_source_to_schema($source);
    return $source;
  }

  my($source, $result_class) = @{$class->_result_source_instance};
  return unless Scalar::Util::blessed($source);

  if ($result_class ne $class) {  # new class
    # Give this new class its own source and register it.
    $source = $source->new({ 
        %$source, 
        source_name  => $class,
        result_class => $class
    } );
    $class->_result_source_instance([$source, $class]);
    $class->_maybe_attach_source_to_schema($source);
  }
  return $source;
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

=end HIDE_BECAUSE_THIS_CLASS_IS_DEPRECATED

=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

1;
