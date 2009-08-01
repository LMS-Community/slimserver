package DBIx::Class::Storage::TxnScopeGuard;

use strict;
use warnings;
use Carp ();

sub new {
  my ($class, $storage) = @_;

  $storage->txn_begin;
  bless [ 0, $storage ], ref $class || $class;
}

sub commit {
  my $self = shift;

  $self->[1]->txn_commit;
  $self->[0] = 1;
}

sub DESTROY {
  my ($dismiss, $storage) = @{$_[0]};

  return if $dismiss;

  my $exception = $@;
  Carp::cluck("A DBIx::Class::Storage::TxnScopeGuard went out of scope without explicit commit or an error - bad")
    unless $exception; 
  {
    local $@;
    eval { $storage->txn_rollback };
    my $rollback_exception = $@;
    if($rollback_exception) {
      my $exception_class = "DBIx::Class::Storage::NESTED_ROLLBACK_EXCEPTION";

      $storage->throw_exception(
        "Transaction aborted: ${exception}. "
        . "Rollback failed: ${rollback_exception}"
      ) unless $rollback_exception =~ /$exception_class/;
    }
  }
}

1;

__END__

=head1 NAME

DBIx::Class::Storage::TxnScopeGuard - Scope-based transaction handling

=head1 SYNOPSIS

 sub foo {
   my ($self, $schema) = @_;

   my $guard = $schema->txn_scope_guard;

   # Multiple database operations here

   $guard->commit;
 }

=head1 DESCRIPTION

An object that behaves much like L<Scope::Guard>, but hardcoded to do the
right thing with transactions in DBIx::Class. 

=head1 METHODS

=head2 new

Creating an instance of this class will start a new transaction (by
implicitly calling L<DBIx::Class::Storage/txn_begin>. Expects a
L<DBIx::Class::Storage> object as its only argument.

=head2 commit

Commit the transaction, and stop guarding the scope. If this method is not
called and this object goes out of scope (i.e. an exception is thrown) then
the transaction is rolled back, via L<DBIx::Class::Storage/txn_rollback>

=cut

=head1 SEE ALSO

L<DBIx::Class::Schema/txn_scope_guard>.

=head1 AUTHOR

Ash Berlin, 2008.

Insipred by L<Scope::Guard> by chocolateboy.

This module is free software. It may be used, redistributed and/or modified
under the same terms as Perl itself.

=cut
