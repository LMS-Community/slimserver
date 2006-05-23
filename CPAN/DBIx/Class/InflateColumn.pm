package DBIx::Class::InflateColumn;

use strict;
use warnings;


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

sub get_inflated_column {
  my ($self, $col) = @_;
  $self->throw_exception("$col is not an inflated column")
    unless exists $self->column_info($col)->{_inflate_info};

  return $self->{_inflated_column}{$col}
    if exists $self->{_inflated_column}{$col};
  return $self->{_inflated_column}{$col} =
           $self->_inflated_column($col, $self->get_column($col));
}

sub set_inflated_column {
  my ($self, $col, @rest) = @_;
  my $ret = $self->_inflated_column_op('set', $col, @rest);
  return $ret;
}

sub store_inflated_column {
  my ($self, $col, @rest) = @_;
  my $ret = $self->_inflated_column_op('store', $col, @rest);
  return $ret;
}

sub _inflated_column_op {
  my ($self, $op, $col, $obj) = @_;
  my $meth = "${op}_column";
  unless (ref $obj) {
    delete $self->{_inflated_column}{$col};
    return $self->$meth($col, $obj);
  }

  my $deflated = $self->_deflated_column($col, $obj);
           # Do this now so we don't store if it's invalid

  $self->{_inflated_column}{$col} = $obj;
  $self->$meth($col, $deflated);
  return $obj;
}

sub update {
  my ($class, $attrs, @rest) = @_;
  $attrs ||= {};
  foreach my $key (keys %$attrs) {
    if (ref $attrs->{$key}
          && exists $class->column_info($key)->{_inflate_info}) {
#      $attrs->{$key} = $class->_deflated_column($key, $attrs->{$key});
      $class->set_inflated_column ($key, delete $attrs->{$key});
    }
  }
  return $class->next::method($attrs, @rest);
}

sub new {
  my ($class, $attrs, @rest) = @_;
  $attrs ||= {};
  foreach my $key (keys %$attrs) {
    if (ref $attrs->{$key}
          && exists $class->column_info($key)->{_inflate_info}) {
      $attrs->{$key} = $class->_deflated_column($key, $attrs->{$key});
    }
  }
  return $class->next::method($attrs, @rest);
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
