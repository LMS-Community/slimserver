package DBIx::Class::Row;

use strict;
use warnings;

use base qw/DBIx::Class/;

use DBIx::Class::Exception;
use Scalar::Util ();

###
### Internal method
### Do not use
###
BEGIN {
  *MULTICREATE_DEBUG =
    $ENV{DBIC_MULTICREATE_DEBUG}
      ? sub () { 1 }
      : sub () { 0 };
}

__PACKAGE__->mk_group_accessors('simple' => qw/_source_handle/);

=head1 NAME

DBIx::Class::Row - Basic row methods

=head1 SYNOPSIS

=head1 DESCRIPTION

This class is responsible for defining and doing basic operations on rows
derived from L<DBIx::Class::ResultSource> objects.

Row objects are returned from L<DBIx::Class::ResultSet>s using the
L<create|DBIx::Class::ResultSet/create>, L<find|DBIx::Class::ResultSet/find>,
L<next|DBIx::Class::ResultSet/next> and L<all|DBIx::Class::ResultSet/all> methods,
as well as invocations of 'single' (
L<belongs_to|DBIx::Class::Relationship/belongs_to>,
L<has_one|DBIx::Class::Relationship/has_one> or
L<might_have|DBIx::Class::Relationship/might_have>)
relationship accessors of L<DBIx::Class::Row> objects.

=head1 METHODS

=head2 new

  my $row = My::Class->new(\%attrs);

  my $row = $schema->resultset('MySource')->new(\%colsandvalues);

=over

=item Arguments: \%attrs or \%colsandvalues

=item Returns: A Row object

=back

While you can create a new row object by calling C<new> directly on
this class, you are better off calling it on a
L<DBIx::Class::ResultSet> object.

When calling it directly, you will not get a complete, usable row
object until you pass or set the C<source_handle> attribute, to a
L<DBIx::Class::ResultSource> instance that is attached to a
L<DBIx::Class::Schema> with a valid connection.

C<$attrs> is a hashref of column name, value data. It can also contain
some other attributes such as the C<source_handle>.

Passing an object, or an arrayref of objects as a value will call
L<DBIx::Class::Relationship::Base/set_from_related> for you. When
passed a hashref or an arrayref of hashrefs as the value, these will
be turned into objects via new_related, and treated as if you had
passed objects.

For a more involved explanation, see L<DBIx::Class::ResultSet/create>.

Please note that if a value is not passed to new, no value will be sent
in the SQL INSERT call, and the column will therefore assume whatever
default value was specified in your database. While DBIC will retrieve the
value of autoincrement columns, it will never make an explicit database
trip to retrieve default values assigned by the RDBMS. You can explicitly
request that all values be fetched back from the database by calling
L</discard_changes>, or you can supply an explicit C<undef> to columns
with NULL as the default, and save yourself a SELECT.

 CAVEAT:

 The behavior described above will backfire if you use a foreign key column
 with a database-defined default. If you call the relationship accessor on
 an object that doesn't have a set value for the FK column, DBIC will throw
 an exception, as it has no way of knowing the PK of the related object (if
 there is one).

=cut

## It needs to store the new objects somewhere, and call insert on that list later when insert is called on this object. We may need an accessor for these so the user can retrieve them, if just doing ->new().
## This only works because DBIC doesnt yet care to check whether the new_related objects have been passed all their mandatory columns
## When doing the later insert, we need to make sure the PKs are set.
## using _relationship_data in new and funky ways..
## check Relationship::CascadeActions and Relationship::Accessor for compat
## tests!

sub __new_related_find_or_new_helper {
  my ($self, $relname, $data) = @_;
  if ($self->__their_pk_needs_us($relname, $data)) {
    MULTICREATE_DEBUG and warn "MC $self constructing $relname via new_result";
    return $self->result_source
                ->related_source($relname)
                ->resultset
                ->new_result($data);
  }
  if ($self->result_source->_pk_depends_on($relname, $data)) {
    MULTICREATE_DEBUG and warn "MC $self constructing $relname via find_or_new";
    return $self->result_source
                ->related_source($relname)
                ->resultset
                ->find_or_new($data);
  }
  MULTICREATE_DEBUG and warn "MC $self constructing $relname via find_or_new_related";
  return $self->find_or_new_related($relname, $data);
}

sub __their_pk_needs_us { # this should maybe be in resultsource.
  my ($self, $relname, $data) = @_;
  my $source = $self->result_source;
  my $reverse = $source->reverse_relationship_info($relname);
  my $rel_source = $source->related_source($relname);
  my $us = { $self->get_columns };
  foreach my $key (keys %$reverse) {
    # if their primary key depends on us, then we have to
    # just create a result and we'll fill it out afterwards
    return 1 if $rel_source->_pk_depends_on($key, $us);
  }
  return 0;
}

sub new {
  my ($class, $attrs) = @_;
  $class = ref $class if ref $class;

  my $new = {
      _column_data          => {},
  };
  bless $new, $class;

  if (my $handle = delete $attrs->{-source_handle}) {
    $new->_source_handle($handle);
  }

  my $source;
  if ($source = delete $attrs->{-result_source}) {
    $new->result_source($source);
  }

  if (my $related = delete $attrs->{-from_resultset}) {
    @{$new->{_ignore_at_insert}={}}{@$related} = ();
  }

  if ($attrs) {
    $new->throw_exception("attrs must be a hashref")
      unless ref($attrs) eq 'HASH';

    my ($related,$inflated);

    foreach my $key (keys %$attrs) {
      if (ref $attrs->{$key}) {
        ## Can we extract this lot to use with update(_or .. ) ?
        $new->throw_exception("Can't do multi-create without result source")
          unless $source;
        my $info = $source->relationship_info($key);
        if ($info && $info->{attrs}{accessor}
          && $info->{attrs}{accessor} eq 'single')
        {
          my $rel_obj = delete $attrs->{$key};
          if(!Scalar::Util::blessed($rel_obj)) {
            $rel_obj = $new->__new_related_find_or_new_helper($key, $rel_obj);
          }

          if ($rel_obj->in_storage) {
            $new->{_rel_in_storage}{$key} = 1;
            $new->set_from_related($key, $rel_obj);
          } else {
            MULTICREATE_DEBUG and warn "MC $new uninserted $key $rel_obj\n";
          }

          $related->{$key} = $rel_obj;
          next;
        } elsif ($info && $info->{attrs}{accessor}
            && $info->{attrs}{accessor} eq 'multi'
            && ref $attrs->{$key} eq 'ARRAY') {
          my $others = delete $attrs->{$key};
          my $total = @$others;
          my @objects;
          foreach my $idx (0 .. $#$others) {
            my $rel_obj = $others->[$idx];
            if(!Scalar::Util::blessed($rel_obj)) {
              $rel_obj = $new->__new_related_find_or_new_helper($key, $rel_obj);
            }

            if ($rel_obj->in_storage) {
              $rel_obj->throw_exception ('A multi relationship can not be pre-existing when doing multicreate. Something went wrong');
            } else {
              MULTICREATE_DEBUG and
                warn "MC $new uninserted $key $rel_obj (${\($idx+1)} of $total)\n";
            }
            push(@objects, $rel_obj);
          }
          $related->{$key} = \@objects;
          next;
        } elsif ($info && $info->{attrs}{accessor}
          && $info->{attrs}{accessor} eq 'filter')
        {
          ## 'filter' should disappear and get merged in with 'single' above!
          my $rel_obj = delete $attrs->{$key};
          if(!Scalar::Util::blessed($rel_obj)) {
            $rel_obj = $new->__new_related_find_or_new_helper($key, $rel_obj);
          }
          if ($rel_obj->in_storage) {
            $new->{_rel_in_storage}{$key} = 1;
          }
          else {
            MULTICREATE_DEBUG and warn "MC $new uninserted $key $rel_obj";
          }
          $inflated->{$key} = $rel_obj;
          next;
        } elsif ($class->has_column($key)
            && $class->column_info($key)->{_inflate_info}) {
          $inflated->{$key} = $attrs->{$key};
          next;
        }
      }
      $new->throw_exception("No such column $key on $class")
        unless $class->has_column($key);
      $new->store_column($key => $attrs->{$key});
    }

    $new->{_relationship_data} = $related if $related;
    $new->{_inflated_column} = $inflated if $inflated;
  }

  return $new;
}

=head2 insert

  $row->insert;

=over

=item Arguments: none

=item Returns: The Row object

=back

Inserts an object previously created by L</new> into the database if
it isn't already in there. Returns the object itself. Requires the
object's result source to be set, or the class to have a
result_source_instance method. To insert an entirely new row into
the database, use C<create> (see L<DBIx::Class::ResultSet/create>).

To fetch an uninserted row object, call
L<new|DBIx::Class::ResultSet/new> on a resultset.

This will also insert any uninserted, related objects held inside this
one, see L<DBIx::Class::ResultSet/create> for more details.

=cut

sub insert {
  my ($self) = @_;
  return $self if $self->in_storage;
  my $source = $self->result_source;
  $source ||=  $self->result_source($self->result_source_instance)
    if $self->can('result_source_instance');
  $self->throw_exception("No result_source set on this object; can't insert")
    unless $source;

  my $rollback_guard;

  # Check if we stored uninserted relobjs here in new()
  my %related_stuff = (%{$self->{_relationship_data} || {}},
                       %{$self->{_inflated_column} || {}});

  # insert what needs to be inserted before us
  my %pre_insert;
  for my $relname (keys %related_stuff) {
    my $rel_obj = $related_stuff{$relname};

    if (! $self->{_rel_in_storage}{$relname}) {
      next unless (Scalar::Util::blessed($rel_obj)
                    && $rel_obj->isa('DBIx::Class::Row'));

      next unless $source->_pk_depends_on(
                    $relname, { $rel_obj->get_columns }
                  );

      # The guard will save us if we blow out of this scope via die
      $rollback_guard ||= $source->storage->txn_scope_guard;

      MULTICREATE_DEBUG and warn "MC $self pre-reconstructing $relname $rel_obj\n";

      my $them = { %{$rel_obj->{_relationship_data} || {} }, $rel_obj->get_inflated_columns };
      my $re = $self->result_source
                    ->related_source($relname)
                    ->resultset
                    ->find_or_create($them);

      %{$rel_obj} = %{$re};
      $self->{_rel_in_storage}{$relname} = 1;
    }

    $self->set_from_related($relname, $rel_obj);
    delete $related_stuff{$relname};
  }

  # start a transaction here if not started yet and there is more stuff
  # to insert after us
  if (keys %related_stuff) {
    $rollback_guard ||= $source->storage->txn_scope_guard
  }

  MULTICREATE_DEBUG and do {
    no warnings 'uninitialized';
    warn "MC $self inserting (".join(', ', $self->get_columns).")\n";
  };
  my $updated_cols = $source->storage->insert($source, { $self->get_columns });
  foreach my $col (keys %$updated_cols) {
    $self->store_column($col, $updated_cols->{$col});
  }

  ## PK::Auto
  my @auto_pri = grep {
                  (not defined $self->get_column($_))
                    ||
                  (ref($self->get_column($_)) eq 'SCALAR')
                 } $self->primary_columns;

  if (@auto_pri) {
    MULTICREATE_DEBUG and warn "MC $self fetching missing PKs ".join(', ', @auto_pri)."\n";
    my $storage = $self->result_source->storage;
    $self->throw_exception( "Missing primary key but Storage doesn't support last_insert_id" )
      unless $storage->can('last_insert_id');
    my @ids = $storage->last_insert_id($self->result_source,@auto_pri);
    $self->throw_exception( "Can't get last insert id" )
      unless (@ids == @auto_pri);
    $self->store_column($auto_pri[$_] => $ids[$_]) for 0 .. $#ids;
  }


  $self->{_dirty_columns} = {};
  $self->{related_resultsets} = {};

  foreach my $relname (keys %related_stuff) {
    next unless $source->has_relationship ($relname);

    my @cands = ref $related_stuff{$relname} eq 'ARRAY'
      ? @{$related_stuff{$relname}}
      : $related_stuff{$relname}
    ;

    if (@cands
          && Scalar::Util::blessed($cands[0])
            && $cands[0]->isa('DBIx::Class::Row')
    ) {
      my $reverse = $source->reverse_relationship_info($relname);
      foreach my $obj (@cands) {
        $obj->set_from_related($_, $self) for keys %$reverse;
        my $them = { %{$obj->{_relationship_data} || {} }, $obj->get_inflated_columns };
        if ($self->__their_pk_needs_us($relname, $them)) {
          if (exists $self->{_ignore_at_insert}{$relname}) {
            MULTICREATE_DEBUG and warn "MC $self skipping post-insert on $relname";
          } else {
            MULTICREATE_DEBUG and warn "MC $self re-creating $relname $obj";
            my $re = $self->result_source
                          ->related_source($relname)
                          ->resultset
                          ->create($them);
            %{$obj} = %{$re};
            MULTICREATE_DEBUG and warn "MC $self new $relname $obj";
          }
        } else {
          MULTICREATE_DEBUG and warn "MC $self post-inserting $obj";
          $obj->insert();
        }
      }
    }
  }

  $self->in_storage(1);
  delete $self->{_orig_ident};
  delete $self->{_ignore_at_insert};
  $rollback_guard->commit if $rollback_guard;

  return $self;
}

=head2 in_storage

  $row->in_storage; # Get value
  $row->in_storage(1); # Set value

=over

=item Arguments: none or 1|0

=item Returns: 1|0

=back

Indicates whether the object exists as a row in the database or
not. This is set to true when L<DBIx::Class::ResultSet/find>,
L<DBIx::Class::ResultSet/create> or L<DBIx::Class::ResultSet/insert>
are used.

Creating a row object using L<DBIx::Class::ResultSet/new>, or calling
L</delete> on one, sets it to false.

=cut

sub in_storage {
  my ($self, $val) = @_;
  $self->{_in_storage} = $val if @_ > 1;
  return $self->{_in_storage};
}

=head2 update

  $row->update(\%columns?)

=over

=item Arguments: none or a hashref

=item Returns: The Row object

=back

Throws an exception if the row object is not yet in the database,
according to L</in_storage>.

This method issues an SQL UPDATE query to commit any changes to the
object to the database if required.

Also takes an optional hashref of C<< column_name => value> >> pairs
to update on the object first. Be aware that the hashref will be
passed to C<set_inflated_columns>, which might edit it in place, so
don't rely on it being the same after a call to C<update>.  If you
need to preserve the hashref, it is sufficient to pass a shallow copy
to C<update>, e.g. ( { %{ $href } } )

If the values passed or any of the column values set on the object
contain scalar references, eg:

  $row->last_modified(\'NOW()');
  # OR
  $row->update({ last_modified => \'NOW()' });

The update will pass the values verbatim into SQL. (See
L<SQL::Abstract> docs).  The values in your Row object will NOT change
as a result of the update call, if you want the object to be updated
with the actual values from the database, call L</discard_changes>
after the update.

  $row->update()->discard_changes();

To determine before calling this method, which column values have
changed and will be updated, call L</get_dirty_columns>.

To check if any columns will be updated, call L</is_changed>.

To force a column to be updated, call L</make_column_dirty> before
this method.

=cut

sub update {
  my ($self, $upd) = @_;
  $self->throw_exception( "Not in database" ) unless $self->in_storage;
  my $ident_cond = $self->ident_condition;
  $self->throw_exception("Cannot safely update a row in a PK-less table")
    if ! keys %$ident_cond;

  $self->set_inflated_columns($upd) if $upd;
  my %to_update = $self->get_dirty_columns;
  return $self unless keys %to_update;
  my $rows = $self->result_source->storage->update(
               $self->result_source, \%to_update,
               $self->{_orig_ident} || $ident_cond
             );
  if ($rows == 0) {
    $self->throw_exception( "Can't update ${self}: row not found" );
  } elsif ($rows > 1) {
    $self->throw_exception("Can't update ${self}: updated more than one row");
  }
  $self->{_dirty_columns} = {};
  $self->{related_resultsets} = {};
  undef $self->{_orig_ident};
  return $self;
}

=head2 delete

  $row->delete

=over

=item Arguments: none

=item Returns: The Row object

=back

Throws an exception if the object is not in the database according to
L</in_storage>. Runs an SQL DELETE statement using the primary key
values to locate the row.

The object is still perfectly usable, but L</in_storage> will
now return 0 and the object must be reinserted using L</insert>
before it can be used to L</update> the row again.

If you delete an object in a class with a C<has_many> relationship, an
attempt is made to delete all the related objects as well. To turn
this behaviour off, pass C<< cascade_delete => 0 >> in the C<$attr>
hashref of the relationship, see L<DBIx::Class::Relationship>. Any
database-level cascade or restrict will take precedence over a
DBIx-Class-based cascading delete.

If you delete an object within a txn_do() (see L<DBIx::Class::Storage/txn_do>)
and the transaction subsequently fails, the row object will remain marked as
not being in storage. If you know for a fact that the object is still in
storage (i.e. by inspecting the cause of the transaction's failure), you can
use C<< $obj->in_storage(1) >> to restore consistency between the object and
the database. This would allow a subsequent C<< $obj->delete >> to work
as expected.

See also L<DBIx::Class::ResultSet/delete>.

=cut

sub delete {
  my $self = shift;
  if (ref $self) {
    $self->throw_exception( "Not in database" ) unless $self->in_storage;
    my $ident_cond = $self->{_orig_ident} || $self->ident_condition;
    $self->throw_exception("Cannot safely delete a row in a PK-less table")
      if ! keys %$ident_cond;
    foreach my $column (keys %$ident_cond) {
            $self->throw_exception("Can't delete the object unless it has loaded the primary keys")
              unless exists $self->{_column_data}{$column};
    }
    $self->result_source->storage->delete(
      $self->result_source, $ident_cond);
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

  my $val = $row->get_column($col);

=over

=item Arguments: $columnname

=item Returns: The value of the column

=back

Throws an exception if the column name given doesn't exist according
to L</has_column>.

Returns a raw column value from the row object, if it has already
been fetched from the database or set by an accessor.

If an L<inflated value|DBIx::Class::InflateColumn> has been set, it
will be deflated and returned.

Note that if you used the C<columns> or the C<select/as>
L<search attributes|DBIx::Class::ResultSet/ATTRIBUTES> on the resultset from
which C<$row> was derived, and B<did not include> C<$columnname> in the list,
this method will return C<undef> even if the database contains some value.

To retrieve all loaded column values as a hash, use L</get_columns>.

=cut

sub get_column {
  my ($self, $column) = @_;
  $self->throw_exception( "Can't fetch data as class method" ) unless ref $self;
  return $self->{_column_data}{$column} if exists $self->{_column_data}{$column};
  if (exists $self->{_inflated_column}{$column}) {
    return $self->store_column($column,
      $self->_deflated_column($column, $self->{_inflated_column}{$column}));
  }
  $self->throw_exception( "No such column '${column}'" ) unless $self->has_column($column);
  return undef;
}

=head2 has_column_loaded

  if ( $row->has_column_loaded($col) ) {
     print "$col has been loaded from db";
  }

=over

=item Arguments: $columnname

=item Returns: 0|1

=back

Returns a true value if the column value has been loaded from the
database (or set locally).

=cut

sub has_column_loaded {
  my ($self, $column) = @_;
  $self->throw_exception( "Can't call has_column data as class method" ) unless ref $self;
  return 1 if exists $self->{_inflated_column}{$column};
  return exists $self->{_column_data}{$column};
}

=head2 get_columns

  my %data = $row->get_columns;

=over

=item Arguments: none

=item Returns: A hash of columnname, value pairs.

=back

Returns all loaded column data as a hash, containing raw values. To
get just one value for a particular column, use L</get_column>.

See L</get_inflated_columns> to get the inflated values.

=cut

sub get_columns {
  my $self = shift;
  if (exists $self->{_inflated_column}) {
    foreach my $col (keys %{$self->{_inflated_column}}) {
      $self->store_column($col, $self->_deflated_column($col, $self->{_inflated_column}{$col}))
        unless exists $self->{_column_data}{$col};
    }
  }
  return %{$self->{_column_data}};
}

=head2 get_dirty_columns

  my %data = $row->get_dirty_columns;

=over

=item Arguments: none

=item Returns: A hash of column, value pairs

=back

Only returns the column, value pairs for those columns that have been
changed on this object since the last L</update> or L</insert> call.

See L</get_columns> to fetch all column/value pairs.

=cut

sub get_dirty_columns {
  my $self = shift;
  return map { $_ => $self->{_column_data}{$_} }
           keys %{$self->{_dirty_columns}};
}

=head2 make_column_dirty

  $row->make_column_dirty($col)

=over

=item Arguments: $columnname

=item Returns: undefined

=back

Throws an exception if the column does not exist.

Marks a column as having been changed regardless of whether it has
really changed.

=cut
sub make_column_dirty {
  my ($self, $column) = @_;

  $self->throw_exception( "No such column '${column}'" )
    unless exists $self->{_column_data}{$column} || $self->has_column($column);

  # the entire clean/dirty code relies on exists, not on true/false
  return 1 if exists $self->{_dirty_columns}{$column};

  $self->{_dirty_columns}{$column} = 1;

  # if we are just now making the column dirty, and if there is an inflated
  # value, force it over the deflated one
  if (exists $self->{_inflated_column}{$column}) {
    $self->store_column($column,
      $self->_deflated_column(
        $column, $self->{_inflated_column}{$column}
      )
    );
  }
}

=head2 get_inflated_columns

  my %inflated_data = $obj->get_inflated_columns;

=over

=item Arguments: none

=item Returns: A hash of column, object|value pairs

=back

Returns a hash of all column keys and associated values. Values for any
columns set to use inflation will be inflated and returns as objects.

See L</get_columns> to get the uninflated values.

See L<DBIx::Class::InflateColumn> for how to setup inflation.

=cut

sub get_inflated_columns {
  my $self = shift;
  return map {
    my $accessor = $self->column_info($_)->{'accessor'} || $_;
    ($_ => $self->$accessor);
  } grep $self->has_column_loaded($_), $self->columns;
}

=head2 set_column

  $row->set_column($col => $val);

=over

=item Arguments: $columnname, $value

=item Returns: $value

=back

Sets a raw column value. If the new value is different from the old one,
the column is marked as dirty for when you next call L</update>.

If passed an object or reference as a value, this method will happily
attempt to store it, and a later L</insert> or L</update> will try and
stringify/numify as appropriate. To set an object to be deflated
instead, see L</set_inflated_columns>.

=cut

sub set_column {
  my ($self, $column, $new_value) = @_;

  $self->{_orig_ident} ||= $self->ident_condition;
  my $old_value = $self->get_column($column);

  $self->store_column($column, $new_value);

  my $dirty;
  if (!$self->in_storage) { # no point tracking dirtyness on uninserted data
    $dirty = 1;
  }
  elsif (defined $old_value xor defined $new_value) {
    $dirty = 1;
  }
  elsif (not defined $old_value) {  # both undef
    $dirty = 0;
  }
  elsif ($old_value eq $new_value) {
    $dirty = 0;
  }
  else {  # do a numeric comparison if datatype allows it
    my $colinfo = $self->column_info ($column);

    # cache for speed (the object may *not* have a resultsource instance)
    if (not defined $colinfo->{is_numeric} && $self->_source_handle) {
      $colinfo->{is_numeric} =
        $self->result_source->schema->storage->is_datatype_numeric ($colinfo->{data_type})
          ? 1
          : 0
        ;
    }

    if ($colinfo->{is_numeric}) {
      $dirty = $old_value != $new_value;
    }
    else {
      $dirty = 1;
    }
  }

  # sadly the update code just checks for keys, not for their value
  $self->{_dirty_columns}{$column} = 1 if $dirty;

  # XXX clear out the relation cache for this column
  delete $self->{related_resultsets}{$column};

  return $new_value;
}

=head2 set_columns

  $row->set_columns({ $col => $val, ... });

=over

=item Arguments: \%columndata

=item Returns: The Row object

=back

Sets multiple column, raw value pairs at once.

Works as L</set_column>.

=cut

sub set_columns {
  my ($self,$data) = @_;
  foreach my $col (keys %$data) {
    $self->set_column($col,$data->{$col});
  }
  return $self;
}

=head2 set_inflated_columns

  $row->set_inflated_columns({ $col => $val, $relname => $obj, ... });

=over

=item Arguments: \%columndata

=item Returns: The Row object

=back

Sets more than one column value at once. Any inflated values are
deflated and the raw values stored.

Any related values passed as Row objects, using the relation name as a
key, are reduced to the appropriate foreign key values and stored. If
instead of related row objects, a hashref of column, value data is
passed, will create the related object first then store.

Will even accept arrayrefs of data as a value to a
L<DBIx::Class::Relationship/has_many> key, and create the related
objects if necessary.

Be aware that the input hashref might be edited in place, so dont rely
on it being the same after a call to C<set_inflated_columns>. If you
need to preserve the hashref, it is sufficient to pass a shallow copy
to C<set_inflated_columns>, e.g. ( { %{ $href } } )

See also L<DBIx::Class::Relationship::Base/set_from_related>.

=cut

sub set_inflated_columns {
  my ( $self, $upd ) = @_;
  foreach my $key (keys %$upd) {
    if (ref $upd->{$key}) {
      my $info = $self->relationship_info($key);
      if ($info && $info->{attrs}{accessor}
        && $info->{attrs}{accessor} eq 'single')
      {
        my $rel = delete $upd->{$key};
        $self->set_from_related($key => $rel);
        $self->{_relationship_data}{$key} = $rel;
      } elsif ($info && $info->{attrs}{accessor}
        && $info->{attrs}{accessor} eq 'multi') {
          $self->throw_exception(
            "Recursive update is not supported over relationships of type multi ($key)"
          );
      }
      elsif ($self->has_column($key)
        && exists $self->column_info($key)->{_inflate_info})
      {
        $self->set_inflated_column($key, delete $upd->{$key});
      }
    }
  }
  $self->set_columns($upd);
}

=head2 copy

  my $copy = $orig->copy({ change => $to, ... });

=over

=item Arguments: \%replacementdata

=item Returns: The Row object copy

=back

Inserts a new row into the database, as a copy of the original
object. If a hashref of replacement data is supplied, these will take
precedence over data in the original. Also any columns which have
the L<column info attribute|DBIx::Class::ResultSource/add_columns>
C<< is_auto_increment => 1 >> are explicitly removed before the copy,
so that the database can insert its own autoincremented values into
the new object.

Relationships will be followed by the copy procedure B<only> if the
relationship specifes a true value for its
L<cascade_copy|DBIx::Class::Relationship::Base> attribute. C<cascade_copy>
is set by default on C<has_many> relationships and unset on all others.

=cut

sub copy {
  my ($self, $changes) = @_;
  $changes ||= {};
  my $col_data = { %{$self->{_column_data}} };
  foreach my $col (keys %$col_data) {
    delete $col_data->{$col}
      if $self->result_source->column_info($col)->{is_auto_increment};
  }

  my $new = { _column_data => $col_data };
  bless $new, ref $self;

  $new->result_source($self->result_source);
  $new->set_inflated_columns($changes);
  $new->insert;

  # Its possible we'll have 2 relations to the same Source. We need to make
  # sure we don't try to insert the same row twice esle we'll violate unique
  # constraints
  my $rels_copied = {};

  foreach my $rel ($self->result_source->relationships) {
    my $rel_info = $self->result_source->relationship_info($rel);

    next unless $rel_info->{attrs}{cascade_copy};

    my $resolved = $self->result_source->_resolve_condition(
      $rel_info->{cond}, $rel, $new
    );

    my $copied = $rels_copied->{ $rel_info->{source} } ||= {};
    foreach my $related ($self->search_related($rel)) {
      my $id_str = join("\0", $related->id);
      next if $copied->{$id_str};
      $copied->{$id_str} = 1;
      my $rel_copy = $related->copy($resolved);
    }

  }
  return $new;
}

=head2 store_column

  $row->store_column($col => $val);

=over

=item Arguments: $columnname, $value

=item Returns: The value sent to storage

=back

Set a raw value for a column without marking it as changed. This
method is used internally by L</set_column> which you should probably
be using.

This is the lowest level at which data is set on a row object,
extend this method to catch all data setting methods.

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

=over

=item Arguments: $result_source, \%columndata, \%prefetcheddata

=item Returns: A Row object

=back

All L<DBIx::Class::ResultSet> methods that retrieve data from the
database and turn it into row objects call this method.

Extend this method in your Result classes to hook into this process,
for example to rebless the result into a different class.

Reblessing can also be done more easily by setting C<result_class> in
your Result class. See L<DBIx::Class::ResultSource/result_class>.

Different types of results can also be created from a particular
L<DBIx::Class::ResultSet>, see L<DBIx::Class::ResultSet/result_class>.

=cut

sub inflate_result {
  my ($class, $source, $me, $prefetch) = @_;

  my ($source_handle) = $source;

  if ($source->isa('DBIx::Class::ResultSourceHandle')) {
      $source = $source_handle->resolve
  } else {
      $source_handle = $source->handle
  }

  my $new = {
    _source_handle => $source_handle,
    _column_data => $me,
  };
  bless $new, (ref $class || $class);

  my $schema;
  foreach my $pre (keys %{$prefetch||{}}) {
    my $pre_val = $prefetch->{$pre};
    my $pre_source = $source->related_source($pre);
    $class->throw_exception("Can't prefetch non-existent relationship ${pre}")
      unless $pre_source;
    if (ref($pre_val->[0]) eq 'ARRAY') { # multi
      my @pre_objects;

      for my $me_pref (@$pre_val) {

        # the collapser currently *could* return bogus elements with all
        # columns set to undef
        my $has_def;
        for (values %{$me_pref->[0]}) {
          if (defined $_) {
            $has_def++;
            last;
          }
        }
        next unless $has_def;

        push @pre_objects, $pre_source->result_class->inflate_result(
          $pre_source, @$me_pref
        );
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
       $class->throw_exception("Implicit prefetch (via select/columns) not supported with accessor '$accessor'");
      }
      $new->related_resultset($pre)->set_cache([ $fetched ]);
    }
  }

  $new->in_storage (1);
  return $new;
}

=head2 update_or_insert

  $row->update_or_insert

=over

=item Arguments: none

=item Returns: Result of update or insert operation

=back

L</Update>s the object if it's already in the database, according to
L</in_storage>, else L</insert>s it.

=head2 insert_or_update

  $obj->insert_or_update

Alias for L</update_or_insert>

=cut

sub insert_or_update { shift->update_or_insert(@_) }

sub update_or_insert {
  my $self = shift;
  return ($self->in_storage ? $self->update : $self->insert);
}

=head2 is_changed

  my @changed_col_names = $row->is_changed();
  if ($row->is_changed()) { ... }

=over

=item Arguments: none

=item Returns: 0|1 or @columnnames

=back

In list context returns a list of columns with uncommited changes, or
in scalar context returns a true value if there are uncommitted
changes.

=cut

sub is_changed {
  return keys %{shift->{_dirty_columns} || {}};
}

=head2 is_column_changed

  if ($row->is_column_changed('col')) { ... }

=over

=item Arguments: $columname

=item Returns: 0|1

=back

Returns a true value if the column has uncommitted changes.

=cut

sub is_column_changed {
  my( $self, $col ) = @_;
  return exists $self->{_dirty_columns}->{$col};
}

=head2 result_source

  my $resultsource = $row->result_source;

=over

=item Arguments: none

=item Returns: a ResultSource instance

=back

Accessor to the L<DBIx::Class::ResultSource> this object was created from.

=cut

sub result_source {
    my $self = shift;

    if (@_) {
        $self->_source_handle($_[0]->handle);
    } else {
        $self->_source_handle->resolve;
    }
}

=head2 register_column

  $column_info = { .... };
  $class->register_column($column_name, $column_info);

=over

=item Arguments: $columnname, \%columninfo

=item Returns: undefined

=back

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

=head2 get_from_storage

  my $copy = $row->get_from_storage($attrs)

=over

=item Arguments: \%attrs

=item Returns: A Row object

=back

Fetches a fresh copy of the Row object from the database and returns it.

If passed the \%attrs argument, will first apply these attributes to
the resultset used to find the row.

This copy can then be used to compare to an existing row object, to
determine if any changes have been made in the database since it was
created.

To just update your Row object with any latest changes from the
database, use L</discard_changes> instead.

The \%attrs argument should be compatible with
L<DBIx::Class::ResultSet/ATTRIBUTES>.

=cut

sub get_from_storage {
    my $self = shift @_;
    my $attrs = shift @_;
    my $resultset = $self->result_source->resultset;

    if(defined $attrs) {
      $resultset = $resultset->search(undef, $attrs);
    }

    return $resultset->find($self->{_orig_ident} || $self->ident_condition);
}

=head2 discard_changes ($attrs)

Re-selects the row from the database, losing any changes that had
been made.

This method can also be used to refresh from storage, retrieving any
changes made since the row was last read from storage.

$attrs is expected to be a hashref of attributes suitable for passing as the
second argument to $resultset->search($cond, $attrs);

=cut

sub discard_changes {
  my ($self, $attrs) = @_;
  delete $self->{_dirty_columns};
  return unless $self->in_storage; # Don't reload if we aren't real!

  # add a replication default to read from the master only
  $attrs = { force_pool => 'master', %{$attrs||{}} };

  if( my $current_storage = $self->get_from_storage($attrs)) {

    # Set $self to the current.
    %$self = %$current_storage;

    # Avoid a possible infinite loop with
    # sub DESTROY { $_[0]->discard_changes }
    bless $current_storage, 'Do::Not::Exist';

    return $self;
  }
  else {
    $self->in_storage(0);
    return $self;
  }
}


=head2 throw_exception

See L<DBIx::Class::Schema/throw_exception>.

=cut

sub throw_exception {
  my $self=shift;

  if (ref $self && ref $self->result_source && $self->result_source->schema) {
    $self->result_source->schema->throw_exception(@_)
  }
  else {
    DBIx::Class::Exception->throw(@_);
  }
}

=head2 id

  my @pk = $row->id;

=over

=item Arguments: none

=item Returns: A list of primary key values

=back

Returns the primary key(s) for a row. Can't be called as a class method.
Actually implemented in L<DBIx::Class::PK>

=head2 discard_changes

  $row->discard_changes

=over

=item Arguments: none

=item Returns: nothing (updates object in-place)

=back

Retrieves and sets the row object data from the database, losing any
local changes made.

This method can also be used to refresh from storage, retrieving any
changes made since the row was last read from storage. Actually
implemented in L<DBIx::Class::PK>

Note: If you are using L<DBIx::Class::Storage::DBI::Replicated> as your
storage, please kept in mind that if you L</discard_changes> on a row that you
just updated or created, you should wrap the entire bit inside a transaction.
Otherwise you run the risk that you insert or update to the master database
but read from a replicant database that has not yet been updated from the
master.  This will result in unexpected results.

=cut

1;

=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut
