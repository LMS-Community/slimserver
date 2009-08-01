package DBIx::Class::Storage::DBI::Role::QueryCounter;

use Moose::Role;
requires '_query_start';

=head1 NAME

DBIx::Class::Storage::DBI::Role::QueryCounter - Role to add a query counter

=head1 SYNOPSIS

    my $query_count = $schema->storage->query_count;

=head1 DESCRIPTION

Each time the schema does a query, increment the counter.

=head1 ATTRIBUTES

This package defines the following attributes.

head2 _query_count

Is the attribute holding the current query count.  It defines a public reader
called 'query_count' which you can use to access the total number of queries
that DBIC has run since connection.

=cut

has '_query_count' => (
  reader=>'query_count',
  writer=>'_set_query_count',
  isa=>'Int',
  required=>1,
  default=>0,
);


=head1 METHODS

This module defines the following methods.

=head2 _query_start

override on the method so that we count the queries.

=cut

around '_query_start' => sub {
  my ($_query_start, $self, @args) = @_;
  $self->_increment_query_count;
  return $self->$_query_start(@args);
};


=head2 _increment_query_count

Used internally.  You won't need this unless you enjoy messing with the query
count.

=cut

sub _increment_query_count {
  my $self = shift @_;
  my $current = $self->query_count;
  $self->_set_query_count(++$current);
}


=head1 AUTHORS

See L<DBIx::Class> for more information regarding authors.

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut


1;
