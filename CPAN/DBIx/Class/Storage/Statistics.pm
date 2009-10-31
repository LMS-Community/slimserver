package DBIx::Class::Storage::Statistics;
use strict;
use warnings;

use base qw/DBIx::Class/;
use IO::File;

__PACKAGE__->mk_group_accessors(simple => qw/callback debugfh silence/);

=head1 NAME

DBIx::Class::Storage::Statistics - SQL Statistics

=head1 SYNOPSIS

=head1 DESCRIPTION

This class is called by DBIx::Class::Storage::DBI as a means of collecting
statistics on its actions.  Using this class alone merely prints the SQL
executed, the fact that it completes and begin/end notification for
transactions.

To really use this class you should subclass it and create your own method
for collecting the statistics as discussed in L<DBIx::Class::Manual::Cookbook>.

=head1 METHODS

=cut

=head2 new

Returns a new L<DBIx::Class::Storage::Statistics> object.

=cut
sub new {
  my $self = {};
  bless $self, (ref($_[0]) || $_[0]);

  return $self;
}

=head2 debugfh

Sets or retrieves the filehandle used for trace/debug output.  This should
be an IO::Handle compatible object (only the C<print> method is used). Initially
should be set to STDERR - although see information on the
L<DBIC_TRACE> environment variable.

=head2 print

Prints the specified string to our debugging filehandle, which we will attempt
to open if we haven't yet.  Provided to save our methods the worry of how
to display the message.

=cut
sub print {
  my ($self, $msg) = @_;

  return if $self->silence;

  if(!defined($self->debugfh())) {
    my $fh;
    my $debug_env = $ENV{DBIX_CLASS_STORAGE_DBI_DEBUG}
                  || $ENV{DBIC_TRACE};
    if (defined($debug_env) && ($debug_env =~ /=(.+)$/)) {
      $fh = IO::File->new($1, 'w')
        or die("Cannot open trace file $1");
    } else {
      $fh = IO::File->new('>&STDERR')
        or die('Duplication of STDERR for debug output failed (perhaps your STDERR is closed?)');
    }

    $fh->autoflush();
    $self->debugfh($fh);
  }

  $self->debugfh->print($msg);
}

=head2 silence

Turn off all output if set to true.

=head2 txn_begin

Called when a transaction begins.

=cut
sub txn_begin {
  my $self = shift;

  return if $self->callback;

  $self->print("BEGIN WORK\n");
}

=head2 txn_rollback

Called when a transaction is rolled back.

=cut
sub txn_rollback {
  my $self = shift;

  return if $self->callback;

  $self->print("ROLLBACK\n");
}

=head2 txn_commit

Called when a transaction is committed.

=cut
sub txn_commit {
  my $self = shift;

  return if $self->callback;

  $self->print("COMMIT\n");
}

=head2 svp_begin

Called when a savepoint is created.

=cut
sub svp_begin {
  my ($self, $name) = @_;

  return if $self->callback;

  $self->print("SAVEPOINT $name\n");
}

=head2 svp_release

Called when a savepoint is released.

=cut
sub svp_release {
  my ($self, $name) = @_;

  return if $self->callback;

  $self->print("RELEASE SAVEPOINT $name\n");
}

=head2 svp_rollback

Called when rolling back to a savepoint.

=cut
sub svp_rollback {
  my ($self, $name) = @_;

  return if $self->callback;

  $self->print("ROLLBACK TO SAVEPOINT $name\n");
}

=head2 query_start

Called before a query is executed.  The first argument is the SQL string being
executed and subsequent arguments are the parameters used for the query.

=cut
sub query_start {
  my ($self, $string, @bind) = @_;

  my $message = "$string: ".join(', ', @bind)."\n";

  if(defined($self->callback)) {
    $string =~ m/^(\w+)/;
    $self->callback->($1, $message);
    return;
  }

  $self->print($message);
}

=head2 query_end

Called when a query finishes executing.  Has the same arguments as query_start.

=cut
sub query_end {
  my ($self, $string) = @_;
}

1;

=head1 AUTHORS

Cory G. Watson <gphat@cpan.org>

=head1 LICENSE

You may distribute this code under the same license as Perl itself.

=cut
