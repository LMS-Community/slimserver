package DBIx::Class::InflateColumn;

use strict;
use warnings;
use Scalar::Util qw/blessed/;

use base qw/DBIx::Class::Row/;

=head1 NAME

DBIx::Class::InflateColumn - Automatically create objects from column data

=head1 SYNOPSIS

    # In your table classes
    __PACKAGE__->inflate_column('column_name', {
        inflate => sub { ... },
        deflate => sub { ... },
    });

=head1 DESCRIPTION

This component translates column data into objects, i.e. "inflating"
the column data. It also "deflates" objects into an appropriate format
for the database.

It can be used, for example, to automatically convert to and from
L<DateTime> objects for your date and time fields.

=head1 METHODS

=head2 inflate_column

Instruct L<DBIx::Class> to inflate the given column.

In addition to the column name, you must provide C<inflate> and
C<deflate> methods. The C<inflate> method is called when you access
the field, while the C<deflate> method is called when the field needs
to used by the database.

For example, if you have a table C<events> with a timestamp field
named C<insert_time>, you could inflate the column in the
corresponding table class using something like:

    __PACKAGE__->inflate_column('insert_time', {
        inflate => sub { DateTime::Format::Pg->parse_datetime(shift); },
        deflate => sub { DateTime::Format::Pg->format_datetime(shift); },
    });

(Replace L<DateTime::Format::Pg> with the appropriate module for your
database, or consider L<DateTime::Format::DBI>.)

The coderefs you set for inflate and deflate are called with two parameters,
the first is the value of the column to be inflated/deflated, the second is the
row object itself. Thus you can call C<< ->result_source->schema->storage->dbh >> on
it, to feed to L<DateTime::Format::DBI>.

In this example, calls to an event's C<insert_time> accessor return a
L<DateTime> object. This L<DateTime> object is later "deflated" when
used in the database layer.

=cut

sub inflate_column {
  my ($self, $col, $attrs) = @_;
  $self->throw_exception("No such column $col to inflate")
    unless $self->has_column($col);
  $self->throw_exception("inflate_column needs attr hashref")
    unless ref $attrs eq 'HASH';
  $self->column_info($col)->{_inflate_info} = $attrs;
  $self->mk_group_accessors('inflated_column' => $col);
  return 1;
}

sub _inflated_column {
  my ($self, $col, $value) = @_;
  return $value unless defined $value; # NULL is NULL is NULL
  my $info = $self->column_info($col)
    or $self->throw_exception("No column info for $col");
  return $value unless exists $info->{_inflate_info};
  my $inflate = $info->{_inflate_info}{inflate};
  $self->throw_exception("No inflator for $col") unless defined $inflate;
  return $inflate->($value, $self);
}

sub _deflated_column {
  my ($self, $col, $value) = @_;
  return $value unless ref $value; # If it's not an object, don't touch it
  my $info = $self->column_info($col) or
    $self->throw_exception("No column info for $col");
  return $value unless exists $info->{_inflate_info};
  my $deflate = $info->{_inflate_info}{deflate};
  $self->throw_exception("No deflator for $col") unless defined $deflate;
  return $deflate->($value, $self);
}

=head2 get_inflated_column

  my $val = $obj->get_inflated_column($col);

Fetch a column value in its inflated state.  This is directly
analogous to L<DBIx::Class::Row/get_column> in that it only fetches a
column already retreived from the database, and then inflates it.
Throws an exception if the column requested is not an inflated column.

=cut

sub get_inflated_column {
  my ($self, $col) = @_;
  $self->throw_exception("$col is not an inflated column")
    unless exists $self->column_info($col)->{_inflate_info};
  return $self->{_inflated_column}{$col}
    if exists $self->{_inflated_column}{$col};
  return $self->{_inflated_column}{$col} =
           $self->_inflated_column($col, $self->get_column($col));
}

=head2 set_inflated_column

  my $copy = $obj->set_inflated_column($col => $val);

Sets a column value from an inflated value.  This is directly
analogous to L<DBIx::Class::Row/set_column>.

=cut

sub set_inflated_column {
  my ($self, $col, $obj) = @_;
  $self->set_column($col, $self->_deflated_column($col, $obj));
  if (blessed $obj) {
    $self->{_inflated_column}{$col} = $obj; 
  } else {
    delete $self->{_inflated_column}{$col};      
  }
  return $obj;
}

=head2 store_inflated_column

  my $copy = $obj->store_inflated_column($col => $val);

Sets a column value from an inflated value without marking the column
as dirty. This is directly analogous to L<DBIx::Class::Row/store_column>.

=cut

sub store_inflated_column {
  my ($self, $col, $obj) = @_;
  unless (blessed $obj) {
      delete $self->{_inflated_column}{$col};
      $self->store_column($col => $obj);
      return $obj;
  }
  delete $self->{_column_data}{$col};
  return $self->{_inflated_column}{$col} = $obj;
}

=head2 get_column

Gets a column value in the same way as L<DBIx::Class::Row/get_column>. If there
is an inflated value stored that has not yet been deflated, it is deflated
when the method is invoked.

=cut

sub get_column {
  my ($self, $col) = @_;
  if (exists $self->{_inflated_column}{$col}
        && !exists $self->{_column_data}{$col}) {
    $self->store_column($col, $self->_deflated_column($col, $self->{_inflated_column}{$col})); 
  }
  return $self->next::method($col);
}

=head2 get_columns 

Returns the get_column info for all columns as a hash,
just like L<DBIx::Class::Row/get_columns>.  Handles inflation just
like L</get_column>.

=cut

sub get_columns {
  my $self = shift;
  if (exists $self->{_inflated_column}) {
    foreach my $col (keys %{$self->{_inflated_column}}) {
      $self->store_column($col, $self->_deflated_column($col, $self->{_inflated_column}{$col}))
       unless exists $self->{_column_data}{$col};
    }
  }
  return $self->next::method;
}

=head2 has_column_loaded

Like L<DBIx::Class::Row/has_column_loaded>, but also returns true if there
is an inflated value stored.

=cut

sub has_column_loaded {
  my ($self, $col) = @_;
  return 1 if exists $self->{_inflated_column}{$col};
  return $self->next::method($col);
}

=head2 update

Updates a row in the same way as L<DBIx::Class::Row/update>, handling
inflation and deflation of columns appropriately.

=cut

sub update {
  my ($class, $attrs, @rest) = @_;
  foreach my $key (keys %{$attrs||{}}) {
    if (ref $attrs->{$key}
          && exists $class->column_info($key)->{_inflate_info}) {
      $class->set_inflated_column($key, delete $attrs->{$key});
    }
  }
  return $class->next::method($attrs, @rest);
}

=head2 new

Creates a row in the same way as L<DBIx::Class::Row/new>, handling
inflation and deflation of columns appropriately.

=cut

sub new {
  my ($class, $attrs, @rest) = @_;
  my $inflated;
  foreach my $key (keys %{$attrs||{}}) {
    $inflated->{$key} = delete $attrs->{$key} 
      if ref $attrs->{$key} && exists $class->column_info($key)->{_inflate_info};
  }
  my $obj = $class->next::method($attrs, @rest);
  $obj->{_inflated_column} = $inflated if $inflated;
  return $obj;
}

=head1 SEE ALSO

=over 4

=item L<DBIx::Class::Core> - This component is loaded as part of the
      "core" L<DBIx::Class> components; generally there is no need to
      load it directly

=back

=head1 AUTHOR

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 CONTRIBUTORS

Daniel Westermann-Clark <danieltwc@cpan.org> (documentation)

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

1;
