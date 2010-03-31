package DBIx::Class::Cursor;

use strict;
use warnings;

use base qw/DBIx::Class/;

=head1 NAME

DBIx::Class::Cursor - Abstract object representing a query cursor on a
resultset.

=head1 SYNOPSIS

  my $cursor = $schema->resultset('CD')->cursor();
  my $first_cd = $cursor->next;

=head1 DESCRIPTION

A Cursor represents a query cursor on a L<DBIx::Class::ResultSet> object. It
allows for traversing the result set with L</next>, retrieving all results with
L</all> and resetting the cursor with L</reset>.

Usually, you would use the cursor methods built into L<DBIx::Class::ResultSet>
to traverse it. See L<DBIx::Class::ResultSet/next>,
L<DBIx::Class::ResultSet/reset> and L<DBIx::Class::ResultSet/all> for more
information.

=head1 METHODS

=head2 new

Virtual method. Returns a new L<DBIx::Class::Cursor> object.

=cut

sub new {
  die "Virtual method!";
}

=head2 next

Virtual method. Advances the cursor to the next row. Returns an array of
column values (the result of L<DBI/fetchrow_array> method).

=cut

sub next {
  die "Virtual method!";
}

=head2 reset

Virtual method. Resets the cursor to the beginning.

=cut

sub reset {
  die "Virtual method!";
}

=head2 all

Virtual method. Returns all rows in the L<DBIx::Class::ResultSet>.

=cut

sub all {
  my ($self) = @_;
  $self->reset;
  my @all;
  while (my @row = $self->next) {
    push(@all, \@row);
  }
  $self->reset;
  return @all;
}

1;
