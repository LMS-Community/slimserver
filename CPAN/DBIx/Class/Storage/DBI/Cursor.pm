package DBIx::Class::Storage::DBI::Cursor;

use base qw/DBIx::Class::Cursor/;

use strict;
use warnings;

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
  #use Data::Dumper; warn Dumper(@_);
  $class = ref $class if ref $class;
  my $new = {
    storage => $storage,
    args => $args,
    pos => 0,
    attrs => $attrs,
    pid => $$,
  };

  $new->{tid} = threads->tid if $INC{'threads.pm'};
  
  return bless ($new, $class);
}

=head2 next

=over 4

=item Arguments: none

=item Return Value: \@row_columns

=back

Advances the cursor to the next row and returns an arrayref of column values.

=cut

sub next {
  my ($self) = @_;

  $self->_check_forks_threads;
  if ($self->{attrs}{rows} && $self->{pos} >= $self->{attrs}{rows}) {
    $self->{sth}->finish if $self->{sth}->{Active};
    delete $self->{sth};
    $self->{done} = 1;
  }
  return if $self->{done};
  unless ($self->{sth}) {
    $self->{sth} = ($self->{storage}->_select(@{$self->{args}}))[1];
    if ($self->{attrs}{software_limit}) {
      if (my $offset = $self->{attrs}{offset}) {
        $self->{sth}->fetch for 1 .. $offset;
      }
    }
  }
  my @row = $self->{sth}->fetchrow_array;
  if (@row) {
    $self->{pos}++;
  } else {
    delete $self->{sth};
    $self->{done} = 1;
  }
  return @row;
}

=head2 all

=over 4

=item Arguments: none

=item Return Value: \@row_columns+

=back

Returns a list of arrayrefs of column values for all rows in the
L<DBIx::Class::ResultSet>.

=cut

sub all {
  my ($self) = @_;

  $self->_check_forks_threads;
  return $self->SUPER::all if $self->{attrs}{rows};
  $self->{sth}->finish if $self->{sth}->{Active};
  delete $self->{sth};
  my ($rv, $sth) = $self->{storage}->_select(@{$self->{args}});
  return @{$sth->fetchall_arrayref};
}

=head2 reset

Resets the cursor to the beginning of the L<DBIx::Class::ResultSet>.

=cut

sub reset {
  my ($self) = @_;

  $self->_check_forks_threads;
  $self->{sth}->finish if $self->{sth}->{Active};
  $self->_soft_reset;
}

sub _soft_reset {
  my ($self) = @_;

  delete $self->{sth};
  $self->{pos} = 0;
  delete $self->{done};
  return $self;
}

sub _check_forks_threads {
  my ($self) = @_;

  if($INC{'threads.pm'} && $self->{tid} != threads->tid) {
      $self->_soft_reset;
      $self->{tid} = threads->tid;
  }

  if($self->{pid} != $$) {
      $self->_soft_reset;
      $self->{pid} = $$;
  }
}

sub DESTROY {
  my ($self) = @_;

  $self->_check_forks_threads;
  $self->{sth}->finish if $self->{sth}->{Active};
}

1;
