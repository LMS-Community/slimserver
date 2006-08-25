package DBIx::Class::ResultSource;

use strict;
use warnings;

use DBIx::Class::ResultSet;
use Carp::Clan qw/^DBIx::Class/;
use Storable;

use base qw/DBIx::Class/;
__PACKAGE__->load_components(qw/AccessorGroup/);

__PACKAGE__->mk_group_accessors('simple' => qw/_ordered_columns
  _columns _primaries _unique_constraints name resultset_attributes
  schema from _relationships source_name/);

__PACKAGE__->mk_group_accessors('component_class' => qw/resultset_class
  result_class/);

=head1 NAME

DBIx::Class::ResultSource - Result source object

=head1 SYNOPSIS

=head1 DESCRIPTION

A ResultSource is a component of a schema from which results can be directly
retrieved, most usually a table (see L<DBIx::Class::ResultSource::Table>)

=head1 METHODS

=pod

=head2 new

  $class->new();

  $class->new({attribute_name => value});

Creates a new ResultSource object.  Not normally called directly by end users.

=cut

sub new {
  my ($class, $attrs) = @_;
  $class = ref $class if ref $class;

  my $new = { %{$attrs || {}}, _resultset => undef };
  bless $new, $class;

  $new->{resultset_class} ||= 'DBIx::Class::ResultSet';
  $new->{resultset_attributes} = { %{$new->{resultset_attributes} || {}} };
  $new->{_ordered_columns} = [ @{$new->{_ordered_columns}||[]}];
  $new->{_columns} = { %{$new->{_columns}||{}} };
  $new->{_relationships} = { %{$new->{_relationships}||{}} };
  $new->{name} ||= "!!NAME NOT SET!!";
  $new->{_columns_info_loaded} ||= 0;
  return $new;
}

=pod

=head2 add_columns

  $table->add_columns(qw/col1 col2 col3/);

  $table->add_columns('col1' => \%col1_info, 'col2' => \%col2_info, ...);

Adds columns to the result source. If supplied key => hashref pairs, uses
the hashref as the column_info for that column. Repeated calls of this
method will add more columns, not replace them.

The contents of the column_info are not set in stone. The following
keys are currently recognised/used by DBIx::Class:

=over 4

=item accessor

Use this to set the name of the accessor for this column. If unset,
the name of the column will be used.

=item data_type

This contains the column type. It is automatically filled by the
L<SQL::Translator::Producer::DBIx::Class::File> producer, and the
L<DBIx::Class::Schema::Loader> module. If you do not enter a
data_type, DBIx::Class will attempt to retrieve it from the
database for you, using L<DBI>'s column_info method. The values of this
key are typically upper-cased.

Currently there is no standard set of values for the data_type. Use
whatever your database supports.

=item size

The length of your column, if it is a column type that can have a size
restriction. This is currently not used by DBIx::Class.

=item is_nullable

Set this to a true value for a columns that is allowed to contain
NULL values. This is currently not used by DBIx::Class.

=item is_auto_increment

Set this to a true value for a column whose value is somehow
automatically set. This is used to determine which columns to empty
when cloning objects using C<copy>.

=item is_foreign_key

Set this to a true value for a column that contains a key from a
foreign table. This is currently not used by DBIx::Class.

=item default_value

Set this to the default value which will be inserted into a column
by the database. Can contain either a value or a function. This is
currently not used by DBIx::Class.

=item sequence

Set this on a primary key column to the name of the sequence used to
generate a new key value. If not specified, L<DBIx::Class::PK::Auto>
will attempt to retrieve the name of the sequence from the database
automatically.

=back

=head2 add_column

  $table->add_column('col' => \%info?);

Convenience alias to add_columns.

=cut

sub add_columns {
  my ($self, @cols) = @_;
  $self->_ordered_columns(\@cols) unless $self->_ordered_columns;

  my @added;
  my $columns = $self->_columns;
  while (my $col = shift @cols) {
    # If next entry is { ... } use that for the column info, if not
    # use an empty hashref
    my $column_info = ref $cols[0] ? shift(@cols) : {};
    push(@added, $col) unless exists $columns->{$col};
    $columns->{$col} = $column_info;
  }
  push @{ $self->_ordered_columns }, @added;
  return $self;
}

*add_column = \&add_columns;

=head2 has_column

  if ($obj->has_column($col)) { ... }

Returns true if the source has a column of this name, false otherwise.

=cut

sub has_column {
  my ($self, $column) = @_;
  return exists $self->_columns->{$column};
}

=head2 column_info

  my $info = $obj->column_info($col);

Returns the column metadata hashref for a column. See the description
of add_column for information on the contents of the hashref.

=cut

sub column_info {
  my ($self, $column) = @_;
  $self->throw_exception("No such column $column")
    unless exists $self->_columns->{$column};
  #warn $self->{_columns_info_loaded}, "\n";
  if ( ! $self->_columns->{$column}{data_type}
       and ! $self->{_columns_info_loaded}
       and $self->schema and $self->storage )
  {
    $self->{_columns_info_loaded}++;
    my $info;
    my $lc_info;
    # eval for the case of storage without table
    eval { $info = $self->storage->columns_info_for( $self->from ) };
    unless ($@) {
      for my $realcol ( keys %{$info} ) {
        $lc_info->{lc $realcol} = $info->{$realcol};
      }
      foreach my $col ( keys %{$self->_columns} ) {
        $self->_columns->{$col} = { %{ $self->_columns->{$col}}, %{$info->{$col} || $lc_info->{lc $col}} };
      }
    }
  }
  return $self->_columns->{$column};
}

=head2 columns

  my @column_names = $obj->columns;

Returns all column names in the order they were declared to add_columns.

=cut

sub columns {
  my $self = shift;
  $self->throw_exception(
    "columns() is a read-only accessor, did you mean add_columns()?"
  ) if (@_ > 1);
  return @{$self->{_ordered_columns}||[]};
}

=head2 remove_columns

  $table->remove_columns(qw/col1 col2 col3/);

Removes columns from the result source.

=head2 remove_column

  $table->remove_column('col');

Convenience alias to remove_columns.

=cut

sub remove_columns {
  my ($self, @cols) = @_;

  return unless $self->_ordered_columns;

  my $columns = $self->_columns;
  my @remaining;

  foreach my $col (@{$self->_ordered_columns}) {
    push @remaining, $col unless grep(/$col/, @cols);
  }

  foreach (@cols) {
    undef $columns->{$_};
  };

  $self->_ordered_columns(\@remaining);
}

*remove_column = \&remove_columns;

=head2 set_primary_key

=over 4

=item Arguments: @cols

=back

Defines one or more columns as primary key for this source. Should be
called after C<add_columns>.

Additionally, defines a unique constraint named C<primary>.

The primary key columns are used by L<DBIx::Class::PK::Auto> to
retrieve automatically created values from the database.

=cut

sub set_primary_key {
  my ($self, @cols) = @_;
  # check if primary key columns are valid columns
  foreach my $col (@cols) {
    $self->throw_exception("No such column $col on table " . $self->name)
      unless $self->has_column($col);
  }
  $self->_primaries(\@cols);

  $self->add_unique_constraint(primary => \@cols);
}

=head2 primary_columns

Read-only accessor which returns the list of primary keys.

=cut

sub primary_columns {
  return @{shift->_primaries||[]};
}

=head2 add_unique_constraint

Declare a unique constraint on this source. Call once for each unique
constraint.

  # For UNIQUE (column1, column2)
  __PACKAGE__->add_unique_constraint(
    constraint_name => [ qw/column1 column2/ ],
  );

Alternatively, you can specify only the columns:

  __PACKAGE__->add_unique_constraint([ qw/column1 column2/ ]);

This will result in a unique constraint named C<table_column1_column2>, where
C<table> is replaced with the table name.

Unique constraints are used, for example, when you call
L<DBIx::Class::ResultSet/find>. Only columns in the constraint are searched.

=cut

sub add_unique_constraint {
  my $self = shift;
  my $cols = pop @_;
  my $name = shift;

  $name ||= $self->name_unique_constraint($cols);

  foreach my $col (@$cols) {
    $self->throw_exception("No such column $col on table " . $self->name)
      unless $self->has_column($col);
  }

  my %unique_constraints = $self->unique_constraints;
  $unique_constraints{$name} = $cols;
  $self->_unique_constraints(\%unique_constraints);
}

=head2 name_unique_constraint

Return a name for a unique constraint containing the specified columns. These
names consist of the table name and each column name, separated by underscores.

For example, a constraint on a table named C<cd> containing the columns
C<artist> and C<title> would result in a constraint name of C<cd_artist_title>.

=cut

sub name_unique_constraint {
  my ($self, $cols) = @_;

  return join '_', $self->name, @$cols;
}

=head2 unique_constraints

Read-only accessor which returns the list of unique constraints on this source.

=cut

sub unique_constraints {
  return %{shift->_unique_constraints||{}};
}

=head2 unique_constraint_names

Returns the list of unique constraint names defined on this source.

=cut

sub unique_constraint_names {
  my ($self) = @_;

  my %unique_constraints = $self->unique_constraints;

  return keys %unique_constraints;
}

=head2 unique_constraint_columns

Returns the list of columns that make up the specified unique constraint.

=cut

sub unique_constraint_columns {
  my ($self, $constraint_name) = @_;

  my %unique_constraints = $self->unique_constraints;

  $self->throw_exception(
    "Unknown unique constraint $constraint_name on '" . $self->name . "'"
  ) unless exists $unique_constraints{$constraint_name};

  return @{ $unique_constraints{$constraint_name} };
}

=head2 from

Returns an expression of the source to be supplied to storage to specify
retrieval from this source. In the case of a database, the required FROM
clause contents.

=head2 schema

Returns the L<DBIx::Class::Schema> object that this result source 
belongs too.

=head2 storage

Returns the storage handle for the current schema.

See also: L<DBIx::Class::Storage>

=cut

sub storage { shift->schema->storage; }

=head2 add_relationship

  $source->add_relationship('relname', 'related_source', $cond, $attrs);

The relationship name can be arbitrary, but must be unique for each
relationship attached to this result source. 'related_source' should
be the name with which the related result source was registered with
the current schema. For example:

  $schema->source('Book')->add_relationship('reviews', 'Review', {
    'foreign.book_id' => 'self.id',
  });

The condition C<$cond> needs to be an L<SQL::Abstract>-style
representation of the join between the tables. For example, if you're
creating a rel from Author to Book,

  { 'foreign.author_id' => 'self.id' }

will result in the JOIN clause

  author me JOIN book foreign ON foreign.author_id = me.id

You can specify as many foreign => self mappings as necessary.

Valid attributes are as follows:

=over 4

=item join_type

Explicitly specifies the type of join to use in the relationship. Any
SQL join type is valid, e.g. C<LEFT> or C<RIGHT>. It will be placed in
the SQL command immediately before C<JOIN>.

=item proxy

An arrayref containing a list of accessors in the foreign class to proxy in
the main class. If, for example, you do the following:

  CD->might_have(liner_notes => 'LinerNotes', undef, {
    proxy => [ qw/notes/ ],
  });

Then, assuming LinerNotes has an accessor named notes, you can do:

  my $cd = CD->find(1);
  # set notes -- LinerNotes object is created if it doesn't exist
  $cd->notes('Notes go here');

=item accessor

Specifies the type of accessor that should be created for the
relationship. Valid values are C<single> (for when there is only a single
related object), C<multi> (when there can be many), and C<filter> (for
when there is a single related object, but you also want the relationship
accessor to double as a column accessor). For C<multi> accessors, an
add_to_* method is also created, which calls C<create_related> for the
relationship.

=back

=cut

sub add_relationship {
  my ($self, $rel, $f_source_name, $cond, $attrs) = @_;
  $self->throw_exception("Can't create relationship without join condition")
    unless $cond;
  $attrs ||= {};

  my %rels = %{ $self->_relationships };
  $rels{$rel} = { class => $f_source_name,
                  source => $f_source_name,
                  cond  => $cond,
                  attrs => $attrs };
  $self->_relationships(\%rels);

  return $self;

  # XXX disabled. doesn't work properly currently. skip in tests.

  my $f_source = $self->schema->source($f_source_name);
  unless ($f_source) {
    $self->ensure_class_loaded($f_source_name);
    $f_source = $f_source_name->result_source;
    #my $s_class = ref($self->schema);
    #$f_source_name =~ m/^${s_class}::(.*)$/;
    #$self->schema->register_class(($1 || $f_source_name), $f_source_name);
    #$f_source = $self->schema->source($f_source_name);
  }
  return unless $f_source; # Can't test rel without f_source

  eval { $self->resolve_join($rel, 'me') };

  if ($@) { # If the resolve failed, back out and re-throw the error
    delete $rels{$rel}; #
    $self->_relationships(\%rels);
    $self->throw_exception("Error creating relationship $rel: $@");
  }
  1;
}

=head2 relationships

Returns all relationship names for this source.

=cut

sub relationships {
  return keys %{shift->_relationships};
}

=head2 relationship_info

=over 4

=item Arguments: $relname

=back

Returns a hash of relationship information for the specified relationship
name.

=cut

sub relationship_info {
  my ($self, $rel) = @_;
  return $self->_relationships->{$rel};
}

=head2 has_relationship

=over 4

=item Arguments: $rel

=back

Returns true if the source has a relationship of this name, false otherwise.

=cut

sub has_relationship {
  my ($self, $rel) = @_;
  return exists $self->_relationships->{$rel};
}

=head2 reverse_relationship_info

=over 4

=item Arguments: $relname

=back

Returns an array of hash references of relationship information for
the other side of the specified relationship name.

=cut

sub reverse_relationship_info {
  my ($self, $rel) = @_;
  my $rel_info = $self->relationship_info($rel);
  my $ret = {};

  return $ret unless ((ref $rel_info->{cond}) eq 'HASH');

  my @cond = keys(%{$rel_info->{cond}});
  my @refkeys = map {/^\w+\.(\w+)$/} @cond;
  my @keys = map {$rel_info->{cond}->{$_} =~ /^\w+\.(\w+)$/} @cond;

  # Get the related result source for this relationship
  my $othertable = $self->related_source($rel);

  # Get all the relationships for that source that related to this source
  # whose foreign column set are our self columns on $rel and whose self
  # columns are our foreign columns on $rel.
  my @otherrels = $othertable->relationships();
  my $otherrelationship;
  foreach my $otherrel (@otherrels) {
    my $otherrel_info = $othertable->relationship_info($otherrel);

    my $back = $othertable->related_source($otherrel);
    next unless $back->name eq $self->name;

    my @othertestconds;

    if (ref $otherrel_info->{cond} eq 'HASH') {
      @othertestconds = ($otherrel_info->{cond});
    }
    elsif (ref $otherrel_info->{cond} eq 'ARRAY') {
      @othertestconds = @{$otherrel_info->{cond}};
    }
    else {
      next;
    }

    foreach my $othercond (@othertestconds) {
      my @other_cond = keys(%$othercond);
      my @other_refkeys = map {/^\w+\.(\w+)$/} @other_cond;
      my @other_keys = map {$othercond->{$_} =~ /^\w+\.(\w+)$/} @other_cond;
      next if (!$self->compare_relationship_keys(\@refkeys, \@other_keys) ||
               !$self->compare_relationship_keys(\@other_refkeys, \@keys));
      $ret->{$otherrel} =  $otherrel_info;
    }
  }
  return $ret;
}

=head2 compare_relationship_keys

=over 4

=item Arguments: $keys1, $keys2

=back

Returns true if both sets of keynames are the same, false otherwise.

=cut

sub compare_relationship_keys {
  my ($self, $keys1, $keys2) = @_;

  # Make sure every keys1 is in keys2
  my $found;
  foreach my $key (@$keys1) {
    $found = 0;
    foreach my $prim (@$keys2) {
      if ($prim eq $key) {
        $found = 1;
        last;
      }
    }
    last unless $found;
  }

  # Make sure every key2 is in key1
  if ($found) {
    foreach my $prim (@$keys2) {
      $found = 0;
      foreach my $key (@$keys1) {
        if ($prim eq $key) {
          $found = 1;
          last;
        }
      }
      last unless $found;
    }
  }

  return $found;
}

=head2 resolve_join

=over 4

=item Arguments: $relation

=back

Returns the join structure required for the related result source.

=cut

sub resolve_join {
  my ($self, $join, $alias, $seen) = @_;
  $seen ||= {};
  if (ref $join eq 'ARRAY') {
    return map { $self->resolve_join($_, $alias, $seen) } @$join;
  } elsif (ref $join eq 'HASH') {
    return
      map {
        my $as = ($seen->{$_} ? $_.'_'.($seen->{$_}+1) : $_);
        ($self->resolve_join($_, $alias, $seen),
          $self->related_source($_)->resolve_join($join->{$_}, $as, $seen));
      } keys %$join;
  } elsif (ref $join) {
    $self->throw_exception("No idea how to resolve join reftype ".ref $join);
  } else {
    my $count = ++$seen->{$join};
    #use Data::Dumper; warn Dumper($seen);
    my $as = ($count > 1 ? "${join}_${count}" : $join);
    my $rel_info = $self->relationship_info($join);
    $self->throw_exception("No such relationship ${join}") unless $rel_info;
    my $type = $rel_info->{attrs}{join_type} || '';
    return [ { $as => $self->related_source($join)->from,
               -join_type => $type },
             $self->resolve_condition($rel_info->{cond}, $as, $alias) ];
  }
}

=head2 resolve_condition

=over 4

=item Arguments: $cond, $as, $alias|$object

=back

Resolves the passed condition to a concrete query fragment. If given an alias,
returns a join condition; if given an object, inverts that object to produce
a related conditional from that object.

=cut

sub resolve_condition {
  my ($self, $cond, $as, $for) = @_;
  #warn %$cond;
  if (ref $cond eq 'HASH') {
    my %ret;
    foreach my $k (keys %{$cond}) {
      my $v = $cond->{$k};
      # XXX should probably check these are valid columns
      $k =~ s/^foreign\.// ||
        $self->throw_exception("Invalid rel cond key ${k}");
      $v =~ s/^self\.// ||
        $self->throw_exception("Invalid rel cond val ${v}");
      if (ref $for) { # Object
        #warn "$self $k $for $v";
        $ret{$k} = $for->get_column($v);
        #warn %ret;
      } elsif (!defined $for) { # undef, i.e. "no object"
        $ret{$k} = undef;
      } elsif (ref $as) { # reverse object
        $ret{$v} = $as->get_column($k);
      } elsif (!defined $as) { # undef, i.e. "no reverse object"
        $ret{$v} = undef;
      } else {
        $ret{"${as}.${k}"} = "${for}.${v}";
      }
    }
    return \%ret;
  } elsif (ref $cond eq 'ARRAY') {
    return [ map { $self->resolve_condition($_, $as, $for) } @$cond ];
  } else {
   die("Can't handle this yet :(");
  }
}

=head2 resolve_prefetch

=over 4

=item Arguments: hashref/arrayref/scalar

=back

Accepts one or more relationships for the current source and returns an
array of column names for each of those relationships. Column names are
prefixed relative to the current source, in accordance with where they appear
in the supplied relationships. Examples:

  my $source = $schema->resultset('Tag')->source;
  @columns = $source->resolve_prefetch( { cd => 'artist' } );

  # @columns =
  #(
  #  'cd.cdid',
  #  'cd.artist',
  #  'cd.title',
  #  'cd.year',
  #  'cd.artist.artistid',
  #  'cd.artist.name'
  #)

  @columns = $source->resolve_prefetch( qw[/ cd /] );

  # @columns =
  #(
  #   'cd.cdid',
  #   'cd.artist',
  #   'cd.title',
  #   'cd.year'
  #)

  $source = $schema->resultset('CD')->source;
  @columns = $source->resolve_prefetch( qw[/ artist producer /] );

  # @columns =
  #(
  #  'artist.artistid',
  #  'artist.name',
  #  'producer.producerid',
  #  'producer.name'
  #)

=cut

sub resolve_prefetch {
  my ($self, $pre, $alias, $seen, $order, $collapse) = @_;
  $seen ||= {};
  #$alias ||= $self->name;
  #warn $alias, Dumper $pre;
  if( ref $pre eq 'ARRAY' ) {
    return
      map { $self->resolve_prefetch( $_, $alias, $seen, $order, $collapse ) }
        @$pre;
  }
  elsif( ref $pre eq 'HASH' ) {
    my @ret =
    map {
      $self->resolve_prefetch($_, $alias, $seen, $order, $collapse),
      $self->related_source($_)->resolve_prefetch(
               $pre->{$_}, "${alias}.$_", $seen, $order, $collapse)
    } keys %$pre;
    #die Dumper \@ret;
    return @ret;
  }
  elsif( ref $pre ) {
    $self->throw_exception(
      "don't know how to resolve prefetch reftype ".ref($pre));
  }
  else {
    my $count = ++$seen->{$pre};
    my $as = ($count > 1 ? "${pre}_${count}" : $pre);
    my $rel_info = $self->relationship_info( $pre );
    $self->throw_exception( $self->name . " has no such relationship '$pre'" )
      unless $rel_info;
    my $as_prefix = ($alias =~ /^.*?\.(.+)$/ ? $1.'.' : '');
    my $rel_source = $self->related_source($pre);

    if (exists $rel_info->{attrs}{accessor}
         && $rel_info->{attrs}{accessor} eq 'multi') {
      $self->throw_exception(
        "Can't prefetch has_many ${pre} (join cond too complex)")
        unless ref($rel_info->{cond}) eq 'HASH';
      my @key = map { (/^foreign\.(.+)$/ ? ($1) : ()); }
                    keys %{$rel_info->{cond}};
      $collapse->{"${as_prefix}${pre}"} = \@key;
      my @ord = (ref($rel_info->{attrs}{order_by}) eq 'ARRAY'
                   ? @{$rel_info->{attrs}{order_by}}
                   : (defined $rel_info->{attrs}{order_by}
                       ? ($rel_info->{attrs}{order_by})
                       : ()));
      push(@$order, map { "${as}.$_" } (@key, @ord));
    }

    return map { [ "${as}.$_", "${as_prefix}${pre}.$_", ] }
      $rel_source->columns;
    #warn $alias, Dumper (\@ret);
    #return @ret;
  }
}

=head2 related_source

=over 4

=item Arguments: $relname

=back

Returns the result source object for the given relationship.

=cut

sub related_source {
  my ($self, $rel) = @_;
  if( !$self->has_relationship( $rel ) ) {
    $self->throw_exception("No such relationship '$rel'");
  }
  return $self->schema->source($self->relationship_info($rel)->{source});
}

=head2 related_class

=over 4

=item Arguments: $relname

=back

Returns the class name for objects in the given relationship.

=cut

sub related_class {
  my ($self, $rel) = @_;
  if( !$self->has_relationship( $rel ) ) {
    $self->throw_exception("No such relationship '$rel'");
  }
  return $self->schema->class($self->relationship_info($rel)->{source});
}

=head2 resultset

Returns a resultset for the given source. This will initially be created
on demand by calling

  $self->resultset_class->new($self, $self->resultset_attributes)

but is cached from then on unless resultset_class changes.

=head2 resultset_class

Set the class of the resultset, this is useful if you want to create your
own resultset methods. Create your own class derived from
L<DBIx::Class::ResultSet>, and set it here.

=head2 resultset_attributes

Specify here any attributes you wish to pass to your specialised resultset.

=cut

sub resultset {
  my $self = shift;
  $self->throw_exception(
    'resultset does not take any arguments. If you want another resultset, '.
    'call it on the schema instead.'
  ) if scalar @_;

  # disabled until we can figure out a way to do it without consistency issues
  #
  #return $self->{_resultset}
  #  if ref $self->{_resultset} eq $self->resultset_class;
  #return $self->{_resultset} =

  return $self->resultset_class->new(
    $self, $self->{resultset_attributes}
  );
}

=head2 source_name

=over 4

=item Arguments: $source_name

=back

Set the name of the result source when it is loaded into a schema.
This is usefull if you want to refer to a result source by a name other than
its class name.

  package ArchivedBooks;
  use base qw/DBIx::Class/;
  __PACKAGE__->table('books_archive');
  __PACKAGE__->source_name('Books');

  # from your schema...
  $schema->resultset('Books')->find(1);

=head2 throw_exception

See L<DBIx::Class::Schema/"throw_exception">.

=cut

sub throw_exception {
  my $self = shift;
  if (defined $self->schema) {
    $self->schema->throw_exception(@_);
  } else {
    croak(@_);
  }
}

=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

