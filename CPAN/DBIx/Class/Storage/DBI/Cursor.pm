package DBIx::Class::Storage::DBI::Cursor;

use strict;
use warnings;

use base qw/DBIx::Class::Cursor/;

__PACKAGE__->mk_group_accessors('simple' =>
    qw/sth/
);

=head1 NAME

DBIx::Class::Storage::DBI::Cursor - Object representing a query cursor on a
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

Returns a new L<DBIx::Class::Storage::DBI::Cursor> object.

=cut

sub new {
  my ($class, $storage, $args, $attrs) = @_;
  $class = ref $class if ref $class;

  my $new = {
    storage => $storage,
    args => $args,
    pos => 0,
    attrs => $attrs,
    _dbh_gen => $storage->{_dbh_gen},
  };

  return bless ($new, $class);
}

=head2 next

=over 4

=item Arguments: none

=item Return Value: \@row_columns

=back

Advances the cursor to the next row and returns an array of column
values (the result of L<DBI/fetchrow_array> method).

=cut

sub _dbh_next {
  my ($storage, $dbh, $self) = @_;

  $self->_check_dbh_gen;
  if (
    $self->{attrs}{software_limit}
      && $self->{attrs}{rows}
        && $self->{pos} >= $self->{attrs}{rows}
  ) {
    $self->sth->finish if $self->sth->{Active};
    $self->sth(undef);
    $self->{done} = 1;
  }
  return if $self->{done};
  unless ($self->sth) {
    $self->sth(($storage->_select(@{$self->{args}}))[1]);
    if ($self->{attrs}{software_limit}) {
      if (my $offset = $self->{attrs}{offset}) {
        $self->sth->fetch for 1 .. $offset;
      }
    }
  }
  my @row = $self->sth->fetchrow_array;
  if (@row) {
    $self->{pos}++;
  } else {
    $self->sth(undef);
    $self->{done} = 1;
  }
  return @row;
}

sub next {
  my ($self) = @_;
  $self->{storage}->dbh_do($self->can('_dbh_next'), $self);
}

=head2 all

=over 4

=item Arguments: none

=item Return Value: \@row_columns+

=back

Returns a list of arrayrefs of column values for all rows in the
L<DBIx::Class::ResultSet>.

=cut

sub _dbh_all {
  my ($storage, $dbh, $self) = @_;

  $self->_check_dbh_gen;
  $self->sth->finish if $self->sth && $self->sth->{Active};
  $self->sth(undef);
  my ($rv, $sth) = $storage->_select(@{$self->{args}});
  return @{$sth->fetchall_arrayref};
}

sub all {
  my ($self) = @_;
  if ($self->{attrs}{software_limit}
        && ($self->{attrs}{offset} || $self->{attrs}{rows})) {
    return $self->next::method;
  }

  $self->{storage}->dbh_do($self->can('_dbh_all'), $self);
}

=head2 reset

Resets the cursor to the beginning of the L<DBIx::Class::ResultSet>.

=cut

sub reset {
  my ($self) = @_;

  # No need to care about failures here
  eval { $self->sth->finish if $self->sth && $self->sth->{Active} };
  $self->_soft_reset;
  return undef;
}

sub _soft_reset {
  my ($self) = @_;

  $self->sth(undef);
  delete $self->{done};
  $self->{pos} = 0;
}

sub _check_dbh_gen {
  my ($self) = @_;

  if($self->{_dbh_gen} != $self->{storage}->{_dbh_gen}) {
    $self->{_dbh_gen} = $self->{storage}->{_dbh_gen};
    $self->_soft_reset;
  }
}

sub DESTROY {
  my ($self) = @_;

  # None of the reasons this would die matter if we're in DESTROY anyways
  local $@;
  eval { $self->sth->finish if $self->sth && $self->sth->{Active} };
}

1;
