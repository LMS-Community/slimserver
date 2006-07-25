package DBIx::Class::Row;

use strict;
use warnings;

use base qw/DBIx::Class/;
use Carp::Clan qw/^DBIx::Class/;

__PACKAGE__->load_components(qw/AccessorGroup/);

__PACKAGE__->mk_group_accessors('simple' => 'result_source');

=head1 NAME

DBIx::Class::Row - Basic row methods

=head1 SYNOPSIS

=head1 DESCRIPTION

This class is responsible for defining and doing basic operations on rows
derived from L<DBIx::Class::ResultSource> objects.

=head1 METHODS

=head2 new

  my $obj = My::Class->new($attrs);

Creates a new row object from column => value mappings passed as a hash ref

=cut

sub new {
  my ($class, $attrs) = @_;
  $class = ref $class if ref $class;
  my $new = bless { _column_data => {} }, $class;
  if ($attrs) {
    $new->throw_exception("attrs must be a hashref")
      unless ref($attrs) eq 'HASH';
    foreach my $k (keys %$attrs) {
      $new->throw_exception("No such column $k on $class")
        unless $class->has_column($k);
      $new->store_column($k => $attrs->{$k});
    }
  }
  return $new;
}

=head2 insert

  $obj->insert;

Inserts an object into the database if it isn't already in there. Returns
the object itself. Requires the object's result source to be set, or the
class to have a result_source_instance method.

=cut

sub insert {
  my ($self) = @_;
  return $self if $self->in_storage;
  $self->{result_source} ||= $self->result_source_instance
    if $self->can('result_source_instance');
  my $source = $self->{result_source};
  $self->throw_exception("No result_source set on this object; can't insert")
    unless $source;
  #use Data::Dumper; warn Dumper($self);
  $source->storage->insert($source->from, { $self->get_columns });
  $self->in_storage(1);
  $self->{_dirty_columns} = {};
  $self->{related_resultsets} = {};
  return $self;
}

=head2 in_storage

  $obj->in_storage; # Get value
  $obj->in_storage(1); # Set value

Indicated whether the object exists as a row in the database or not

=cut

sub in_storage {
  my ($self, $val) = @_;
  $self->{_in_storage} = $val if @_ > 1;
  return $self->{_in_storage};
}

=head2 update

  $obj->update;

Must be run on an object that is already in the database; issues an SQL
UPDATE query to commit any changes to the object to the db if required.

=cut

sub update {
  my ($self, $upd) = @_;
  $self->throw_exception( "Not in database" ) unless $self->in_storage;
  $self->set_columns($upd) if $upd;
  my %to_update = $self->get_dirty_columns;
  return $self unless keys %to_update;
  my $ident_cond = $self->ident_condition;
  $self->throw_exception("Cannot safely update a row in a PK-less table")
    if ! keys %$ident_cond;
  my $rows = $self->result_source->storage->update(
               $self->result_source->from, \%to_update, $ident_cond);
  if ($rows == 0) {
    $self->throw_exception( "Can't update ${self}: row not found" );
  } elsif ($rows > 1) {
    $self->throw_exception("Can't update ${self}: updated more than one row");
  }
  $self->{_dirty_columns} = {};
  $self->{related_resultsets} = {};
  return $self;
}

=head2 delete

  $obj->delete

Deletes the object from the database. The object is still perfectly usable,
but ->in_storage() will now return 0 and the object must re inserted using
->insert() before ->update() can be used on it.

=cut

sub delete {
  my $self = shift;
  if (ref $self) {
    $self->throw_exception( "Not in database" ) unless $self->in_storage;
    my $ident_cond = $self->ident_condition;
    $self->throw_exception("Cannot safely delete a row in a PK-less table")
      if ! keys %$ident_cond;
    foreach my $column (keys %$ident_cond) {
            $self->throw_exception("Can't delete the object unless it has loaded the primary keys")
              unless exists $self->{_column_data}{$column};
    }
    $self->result_source->storage->delete(
      $self->result_source->from, $ident_cond);
    $self->in_storage(undef);
  } else {
    $self->throw_exception("Can't do class delete without a ResultSource instance")
      unless $self->can('result_source_instance');
    my $attrs = @_ > 1 && ref $_[$#_] eq 'HASH' ? { %{pop(@_)} } : {};
    my $query = ref $_[0] eq 'HASH' ? $_[0] : {@_};
    $self->result_source_instance->resultset->search(@_)->delete;
  }
  return $self;
}

=head2 get_column

  my $val = $obj->get_column($col);

Gets a column value from a row object. Currently, does not do
any queries; the column must have already been fetched from
the database and stored in the object.

=cut

sub get_column {
  my ($self, $column) = @_;
  $self->throw_exception( "Can't fetch data as class method" ) unless ref $self;
  return $self->{_column_data}{$column} if exists $self->{_column_data}{$column};
  $self->throw_exception( "No such column '${column}'" ) unless $self->has_column($column);
  return undef;
}

=head2 has_column_loaded

  if ( $obj->has_column_loaded($col) ) {
     print "$col has been loaded from db";
  }

Returns a true value if the column value has been loaded from the
database (or set locally).

=cut

sub has_column_loaded {
  my ($self, $column) = @_;
  $self->throw_exception( "Can't call has_column data as class method" ) unless ref $self;
  return exists $self->{_column_data}{$column};
}

=head2 get_columns

  my %data = $obj->get_columns;

Does C<get_column>, for all column values at once.

=cut

sub get_columns {
  my $self = shift;
  return %{$self->{_column_data}};
}

=head2 get_dirty_columns

  my %data = $obj->get_dirty_columns;

Identical to get_columns but only returns those that have been changed.

=cut

sub get_dirty_columns {
  my $self = shift;
  return map { $_ => $self->{_column_data}{$_} }
           keys %{$self->{_dirty_columns}};
}

=head2 set_column

  $obj->set_column($col => $val);

Sets a column value. If the new value is different from the old one,
the column is marked as dirty for when you next call $obj->update.

=cut

sub set_column {
  my $self = shift;
  my ($column) = @_;
  my $old = $self->get_column($column);
  my $ret = $self->store_column(@_);
  $self->{_dirty_columns}{$column} = 1
    if (defined $old ^ defined $ret) || (defined $old && $old ne $ret);
  return $ret;
}

=head2 set_columns

  my $copy = $orig->set_columns({ $col => $val, ... });

Sets more than one column value at once.

=cut

sub set_columns {
  my ($self,$data) = @_;
  foreach my $col (keys %$data) {
    $self->set_column($col,$data->{$col});
  }
  return $self;
}

=head2 copy

  my $copy = $orig->copy({ change => $to, ... });

Inserts a new row with the specified changes.

=cut

sub copy {
  my ($self, $changes) = @_;
  $changes ||= {};
  my $col_data = { %{$self->{_column_data}} };
  foreach my $col (keys %$col_data) {
    delete $col_data->{$col}
      if $self->result_source->column_info($col)->{is_auto_increment};
  }
  my $new = bless { _column_data => $col_data }, ref $self;
  $new->result_source($self->result_source);
  $new->set_columns($changes);
  $new->insert;
  foreach my $rel ($self->result_source->relationships) {
    my $rel_info = $self->result_source->relationship_info($rel);
    if ($rel_info->{attrs}{cascade_copy}) {
      my $resolved = $self->result_source->resolve_condition(
       $rel_info->{cond}, $rel, $new);
      foreach my $related ($self->search_related($rel)) {
        $related->copy($resolved);
      }
    }
  }
  return $new;
}

=head2 store_column

  $obj->store_column($col => $val);

Sets a column value without marking it as dirty.

=cut

sub store_column {
  my ($self, $column, $value) = @_;
  $self->throw_exception( "No such column '${column}'" )
    unless exists $self->{_column_data}{$column} || $self->has_column($column);
  $self->throw_exception( "set_column called for ${column} without value" )
    if @_ < 3;
  return $self->{_column_data}{$column} = $value;
}

=head2 inflate_result

  Class->inflate_result($result_source, \%me, \%prefetch?)

Called by ResultSet to inflate a result from storage

=cut

sub inflate_result {
  my ($class, $source, $me, $prefetch) = @_;
  #use Data::Dumper; print Dumper(@_);
  my $new = bless({ result_source => $source,
                    _column_data => $me,
                    _in_storage => 1
                  },
                  ref $class || $class);
  my $schema;
  foreach my $pre (keys %{$prefetch||{}}) {
    my $pre_val = $prefetch->{$pre};
    my $pre_source = $source->related_source($pre);
    $class->throw_exception("Can't prefetch non-existent relationship ${pre}")
      unless $pre_source;
    if (ref($pre_val->[0]) eq 'ARRAY') { # multi
      my @pre_objects;
      foreach my $pre_rec (@$pre_val) {
        unless ($pre_source->primary_columns == grep { exists $pre_rec->[0]{$_}
           and defined $pre_rec->[0]{$_} } $pre_source->primary_columns) {
          next;
        }
        push(@pre_objects, $pre_source->result_class->inflate_result(
                             $pre_source, @{$pre_rec}));
      }
      $new->related_resultset($pre)->set_cache(\@pre_objects);
    } elsif (defined $pre_val->[0]) {
      my $fetched;
      unless ($pre_source->primary_columns == grep { exists $pre_val->[0]{$_}
         and !defined $pre_val->[0]{$_} } $pre_source->primary_columns)
      {
        $fetched = $pre_source->result_class->inflate_result(
                      $pre_source, @{$pre_val});
      }
      my $accessor = $source->relationship_info($pre)->{attrs}{accessor};
      $class->throw_exception("No accessor for prefetched $pre")
       unless defined $accessor;
      if ($accessor eq 'single') {
        $new->{_relationship_data}{$pre} = $fetched;
      } elsif ($accessor eq 'filter') {
        $new->{_inflated_column}{$pre} = $fetched;
      } else {
       $class->throw_exception("Prefetch not supported with accessor '$accessor'");
      }
    }
  }
  return $new;
}

=head2 update_or_insert

  $obj->update_or_insert

Updates the object if it's already in the db, else inserts it.

=head2 insert_or_update

  $obj->insert_or_update

Alias for L</update_or_insert>

=cut

*insert_or_update = \&update_or_insert;
sub update_or_insert {
  my $self = shift;
  return ($self->in_storage ? $self->update : $self->insert);
}

=head2 is_changed

  my @changed_col_names = $obj->is_changed();
  if ($obj->is_changed()) { ... }

In array context returns a list of columns with uncommited changes, or
in scalar context returns a true value if there are uncommitted
changes.

=cut

sub is_changed {
  return keys %{shift->{_dirty_columns} || {}};
}

=head2 is_column_changed

  if ($obj->is_column_changed('col')) { ... }

Returns a true value if the column has uncommitted changes.

=cut

sub is_column_changed {
  my( $self, $col ) = @_;
  return exists $self->{_dirty_columns}->{$col};
}

=head2 result_source

  my $resultsource = $object->result_source;

Accessor to the ResultSource this object was created from

=head2 register_column

  $column_info = { .... };
  $class->register_column($column_name, $column_info);

Registers a column on the class. If the column_info has an 'accessor'
key, creates an accessor named after the value if defined; if there is
no such key, creates an accessor with the same name as the column

The column_info attributes are described in
L<DBIx::Class::ResultSource/add_columns>

=cut

sub register_column {
  my ($class, $col, $info) = @_;
  my $acc = $col;
  if (exists $info->{accessor}) {
    return unless defined $info->{accessor};
    $acc = [ $info->{accessor}, $col ];
  }
  $class->mk_group_accessors('column' => $acc);
}


=head2 throw_exception

See Schema's throw_exception.

=cut

sub throw_exception {
  my $self=shift;
  if (ref $self && ref $self->result_source) {
    $self->result_source->schema->throw_exception(@_);
  } else {
    croak(@_);
  }
}

1;

=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

