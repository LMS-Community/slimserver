package DBIx::Class::Storage;

use strict;
use warnings;

use base qw/DBIx::Class/;
use mro 'c3';

use DBIx::Class::Exception;
use Scalar::Util();
use IO::File;
use DBIx::Class::Storage::TxnScopeGuard;

__PACKAGE__->mk_group_accessors('simple' => qw/debug debugobj schema/);
__PACKAGE__->mk_group_accessors('inherited' => 'cursor_class');

__PACKAGE__->cursor_class('DBIx::Class::Cursor');

sub cursor { shift->cursor_class(@_); }

package # Hide from PAUSE
    DBIx::Class::Storage::NESTED_ROLLBACK_EXCEPTION;

use overload '""' => sub {
  'DBIx::Class::Storage::NESTED_ROLLBACK_EXCEPTION'
};

sub new {
  my $class = shift;
  my $self = {};
  return bless $self, $class;
}

package DBIx::Class::Storage;

=head1 NAME

DBIx::Class::Storage - Generic Storage Handler

=head1 DESCRIPTION

A base implementation of common Storage methods.  For specific
information about L<DBI>-based storage, see L<DBIx::Class::Storage::DBI>.

=head1 METHODS

=head2 new

Arguments: $schema

Instantiates the Storage object.

=cut

sub new {
  my ($self, $schema) = @_;

  $self = ref $self if ref $self;

  my $new = {};
  bless $new, $self;

  $new->set_schema($schema);
  $new->debugobj(new DBIx::Class::Storage::Statistics());

  #my $fh;

  my $debug_env = $ENV{DBIX_CLASS_STORAGE_DBI_DEBUG}
                  || $ENV{DBIC_TRACE};

  $new->debug(1) if $debug_env;

  $new;
}

=head2 set_schema

Used to reset the schema class or object which owns this
storage object, such as during L<DBIx::Class::Schema/clone>.

=cut

sub set_schema {
  my ($self, $schema) = @_;
  $self->schema($schema);
  Scalar::Util::weaken($self->{schema}) if ref $self->{schema};
}

=head2 connected

Returns true if we have an open storage connection, false
if it is not (yet) open.

=cut

sub connected { die "Virtual method!" }

=head2 disconnect

Closes any open storage connection unconditionally.

=cut

sub disconnect { die "Virtual method!" }

=head2 ensure_connected

Initiate a connection to the storage if one isn't already open.

=cut

sub ensure_connected { die "Virtual method!" }

=head2 throw_exception

Throws an exception - croaks.

=cut

sub throw_exception {
  my $self = shift;

  if ($self->schema) {
    $self->schema->throw_exception(@_);
  }
  else {
    DBIx::Class::Exception->throw(@_);
  }
}

=head2 txn_do

=over 4

=item Arguments: C<$coderef>, @coderef_args?

=item Return Value: The return value of $coderef

=back

Executes C<$coderef> with (optional) arguments C<@coderef_args> atomically,
returning its result (if any). If an exception is caught, a rollback is issued
and the exception is rethrown. If the rollback fails, (i.e. throws an
exception) an exception is thrown that includes a "Rollback failed" message.

For example,

  my $author_rs = $schema->resultset('Author')->find(1);
  my @titles = qw/Night Day It/;

  my $coderef = sub {
    # If any one of these fails, the entire transaction fails
    $author_rs->create_related('books', {
      title => $_
    }) foreach (@titles);

    return $author->books;
  };

  my $rs;
  eval {
    $rs = $schema->txn_do($coderef);
  };

  if ($@) {                                  # Transaction failed
    die "something terrible has happened!"   #
      if ($@ =~ /Rollback failed/);          # Rollback failed

    deal_with_failed_transaction();
  }

In a nested transaction (calling txn_do() from within a txn_do() coderef) only
the outermost transaction will issue a L</txn_commit>, and txn_do() can be
called in void, scalar and list context and it will behave as expected.

Please note that all of the code in your coderef, including non-DBIx::Class
code, is part of a transaction.  This transaction may fail out halfway, or
it may get partially double-executed (in the case that our DB connection
failed halfway through the transaction, in which case we reconnect and
restart the txn).  Therefore it is best that any side-effects in your coderef
are idempotent (that is, can be re-executed multiple times and get the
same result), and that you check up on your side-effects in the case of
transaction failure.

=cut

sub txn_do {
  my ($self, $coderef, @args) = @_;

  ref $coderef eq 'CODE' or $self->throw_exception
    ('$coderef must be a CODE reference');

  my (@return_values, $return_value);

  $self->txn_begin; # If this throws an exception, no rollback is needed

  my $wantarray = wantarray; # Need to save this since the context
                             # inside the eval{} block is independent
                             # of the context that called txn_do()
  eval {

    # Need to differentiate between scalar/list context to allow for
    # returning a list in scalar context to get the size of the list
    if ($wantarray) {
      # list context
      @return_values = $coderef->(@args);
    } elsif (defined $wantarray) {
      # scalar context
      $return_value = $coderef->(@args);
    } else {
      # void context
      $coderef->(@args);
    }
    $self->txn_commit;
  };

  if ($@) {
    my $error = $@;

    eval {
      $self->txn_rollback;
    };

    if ($@) {
      my $rollback_error = $@;
      my $exception_class = "DBIx::Class::Storage::NESTED_ROLLBACK_EXCEPTION";
      $self->throw_exception($error)  # propagate nested rollback
        if $rollback_error =~ /$exception_class/;

      $self->throw_exception(
        "Transaction aborted: $error. Rollback failed: ${rollback_error}"
      );
    } else {
      $self->throw_exception($error); # txn failed but rollback succeeded
    }
  }

  return $wantarray ? @return_values : $return_value;
}

=head2 txn_begin

Starts a transaction.

See the preferred L</txn_do> method, which allows for
an entire code block to be executed transactionally.

=cut

sub txn_begin { die "Virtual method!" }

=head2 txn_commit

Issues a commit of the current transaction.

It does I<not> perform an actual storage commit unless there's a DBIx::Class
transaction currently in effect (i.e. you called L</txn_begin>).

=cut

sub txn_commit { die "Virtual method!" }

=head2 txn_rollback

Issues a rollback of the current transaction. A nested rollback will
throw a L<DBIx::Class::Storage::NESTED_ROLLBACK_EXCEPTION> exception,
which allows the rollback to propagate to the outermost transaction.

=cut

sub txn_rollback { die "Virtual method!" }

=head2 svp_begin

Arguments: $savepoint_name?

Created a new savepoint using the name provided as argument. If no name
is provided, a random name will be used.

=cut

sub svp_begin { die "Virtual method!" }

=head2 svp_release

Arguments: $savepoint_name?

Release the savepoint provided as argument. If none is provided,
release the savepoint created most recently. This will implicitly
release all savepoints created after the one explicitly released as well.

=cut

sub svp_release { die "Virtual method!" }

=head2 svp_rollback

Arguments: $savepoint_name?

Rollback to the savepoint provided as argument. If none is provided,
rollback to the savepoint created most recently. This will implicitly
release all savepoints created after the savepoint we rollback to.

=cut

sub svp_rollback { die "Virtual method!" }

=for comment

=head2 txn_scope_guard

An alternative way of transaction handling based on
L<DBIx::Class::Storage::TxnScopeGuard>:

 my $txn_guard = $storage->txn_scope_guard;

 $row->col1("val1");
 $row->update;

 $txn_guard->commit;

If an exception occurs, or the guard object otherwise leaves the scope
before C<< $txn_guard->commit >> is called, the transaction will be rolled
back by an explicit L</txn_rollback> call. In essence this is akin to
using a L</txn_begin>/L</txn_commit> pair, without having to worry
about calling L</txn_rollback> at the right places. Note that since there
is no defined code closure, there will be no retries and other magic upon
database disconnection. If you need such functionality see L</txn_do>.

=cut

sub txn_scope_guard {
  return DBIx::Class::Storage::TxnScopeGuard->new($_[0]);
}

=head2 sql_maker

Returns a C<sql_maker> object - normally an object of class
C<DBIx::Class::SQLAHacks>.

=cut

sub sql_maker { die "Virtual method!" }

=head2 debug

Causes trace information to be emitted on the C<debugobj> object.
(or C<STDERR> if C<debugobj> has not specifically been set).

This is the equivalent to setting L</DBIC_TRACE> in your
shell environment.

=head2 debugfh

Set or retrieve the filehandle used for trace/debug output.  This should be
an IO::Handle compatible ojbect (only the C<print> method is used.  Initially
set to be STDERR - although see information on the
L<DBIC_TRACE> environment variable.

=cut

sub debugfh {
    my $self = shift;

    if ($self->debugobj->can('debugfh')) {
        return $self->debugobj->debugfh(@_);
    }
}

=head2 debugobj

Sets or retrieves the object used for metric collection. Defaults to an instance
of L<DBIx::Class::Storage::Statistics> that is compatible with the original
method of using a coderef as a callback.  See the aforementioned Statistics
class for more information.

=head2 debugcb

Sets a callback to be executed each time a statement is run; takes a sub
reference.  Callback is executed as $sub->($op, $info) where $op is
SELECT/INSERT/UPDATE/DELETE and $info is what would normally be printed.

See L<debugobj> for a better way.

=cut

sub debugcb {
    my $self = shift;

    if ($self->debugobj->can('callback')) {
        return $self->debugobj->callback(@_);
    }
}

=head2 cursor_class

The cursor class for this Storage object.

=cut

=head2 deploy

Deploy the tables to storage (CREATE TABLE and friends in a SQL-based
Storage class). This would normally be called through
L<DBIx::Class::Schema/deploy>.

=cut

sub deploy { die "Virtual method!" }

=head2 connect_info

The arguments of C<connect_info> are always a single array reference,
and are Storage-handler specific.

This is normally accessed via L<DBIx::Class::Schema/connection>, which
encapsulates its argument list in an arrayref before calling
C<connect_info> here.

=cut

sub connect_info { die "Virtual method!" }

=head2 select

Handle a select statement.

=cut

sub select { die "Virtual method!" }

=head2 insert

Handle an insert statement.

=cut

sub insert { die "Virtual method!" }

=head2 update

Handle an update statement.

=cut

sub update { die "Virtual method!" }

=head2 delete

Handle a delete statement.

=cut

sub delete { die "Virtual method!" }

=head2 select_single

Performs a select, fetch and return of data - handles a single row
only.

=cut

sub select_single { die "Virtual method!" }

=head2 columns_info_for

Returns metadata for the given source's columns.  This
is *deprecated*, and will be removed before 1.0.  You should
be specifying the metadata yourself if you need it.

=cut

sub columns_info_for { die "Virtual method!" }

=head1 ENVIRONMENT VARIABLES

=head2 DBIC_TRACE

If C<DBIC_TRACE> is set then trace information
is produced (as when the L<debug> method is set).

If the value is of the form C<1=/path/name> then the trace output is
written to the file C</path/name>.

This environment variable is checked when the storage object is first
created (when you call connect on your schema).  So, run-time changes 
to this environment variable will not take effect unless you also 
re-connect on your schema.

=head2 DBIX_CLASS_STORAGE_DBI_DEBUG

Old name for DBIC_TRACE

=head1 SEE ALSO

L<DBIx::Class::Storage::DBI> - reference storage implementation using
SQL::Abstract and DBI.

=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

Andy Grundman <andy@hybridized.org>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

1;
