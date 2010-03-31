package DBIx::Class::ResultSource;

use strict;
use warnings;

use DBIx::Class::ResultSet;
use DBIx::Class::ResultSourceHandle;

use DBIx::Class::Exception;
use Carp::Clan qw/^DBIx::Class/;

use base qw/DBIx::Class/;

__PACKAGE__->mk_group_accessors('simple' => qw/_ordered_columns
  _columns _primaries _unique_constraints name resultset_attributes
  schema from _relationships column_info_from_storage source_info
  source_name sqlt_deploy_callback/);

__PACKAGE__->mk_group_accessors('component_class' => qw/resultset_class
  result_class/);

=head1 NAME

DBIx::Class::ResultSource - Result source object

=head1 SYNOPSIS

  # Create a table based result source, in a result class.

  package MyDB::Schema::Result::Artist;
  use base qw/DBIx::Class/;

  __PACKAGE__->load_components(qw/Core/);
  __PACKAGE__->table('artist');
  __PACKAGE__->add_columns(qw/ artistid name /);
  __PACKAGE__->set_primary_key('artistid');
  __PACKAGE__->has_many(cds => 'MyDB::Schema::Result::CD');

  1;

  # Create a query (view) based result source, in a result class
  package MyDB::Schema::Result::Year2000CDs;

  __PACKAGE__->load_components('Core');
  __PACKAGE__->table_class('DBIx::Class::ResultSource::View');

  __PACKAGE__->table('year2000cds');
  __PACKAGE__->result_source_instance->is_virtual(1);
  __PACKAGE__->result_source_instance->view_definition(
      "SELECT cdid, artist, title FROM cd WHERE year ='2000'"
      );


=head1 DESCRIPTION

A ResultSource is an object that represents a source of data for querying.

This class is a base class for various specialised types of result
sources, for example L<DBIx::Class::ResultSource::Table>. Table is the
default result source type, so one is created for you when defining a
result class as described in the synopsis above.

More specifically, the L<DBIx::Class::Core> component pulls in the
L<DBIx::Class::ResultSourceProxy::Table> as a base class, which
defines the L<table|DBIx::Class::ResultSourceProxy::Table/table>
method. When called, C<table> creates and stores an instance of
L<DBIx::Class::ResultSoure::Table>. Luckily, to use tables as result
sources, you don't need to remember any of this.

Result sources representing select queries, or views, can also be
created, see L<DBIx::Class::ResultSource::View> for full details.

=head2 Finding result source objects

As mentioned above, a result source instance is created and stored for
you when you define a L<Result Class|DBIx::Class::Manual::Glossary/Result Class>.

You can retrieve the result source at runtime in the following ways:

=over

=item From a Schema object:

   $schema->source($source_name);

=item From a Row object:

   $row->result_source;

=item From a ResultSet object:

   $rs->result_source;

=back

=head1 METHODS

=pod

=cut

sub new {
  my ($class, $attrs) = @_;
  $class = ref $class if ref $class;

  my $new = bless { %{$attrs || {}} }, $class;
  $new->{resultset_class} ||= 'DBIx::Class::ResultSet';
  $new->{resultset_attributes} = { %{$new->{resultset_attributes} || {}} };
  $new->{_ordered_columns} = [ @{$new->{_ordered_columns}||[]}];
  $new->{_columns} = { %{$new->{_columns}||{}} };
  $new->{_relationships} = { %{$new->{_relationships}||{}} };
  $new->{name} ||= "!!NAME NOT SET!!";
  $new->{_columns_info_loaded} ||= 0;
  $new->{sqlt_deploy_callback} ||= "default_sqlt_deploy_hook";
  return $new;
}

=pod

=head2 add_columns

=over

=item Arguments: @columns

=item Return value: The ResultSource object

=back

  $source->add_columns(qw/col1 col2 col3/);

  $source->add_columns('col1' => \%col1_info, 'col2' => \%col2_info, ...);

Adds columns to the result source. If supplied colname => hashref
pairs, uses the hashref as the L</column_info> for that column. Repeated
calls of this method will add more columns, not replace them.

The column names given will be created as accessor methods on your
L<DBIx::Class::Row> objects. You can change the name of the accessor
by supplying an L</accessor> in the column_info hash.

The contents of the column_info are not set in stone. The following
keys are currently recognised/used by DBIx::Class:

=over 4

=item accessor

   { accessor => '_name' }

   # example use, replace standard accessor with one of your own:
   sub name {
       my ($self, $value) = @_;

       die "Name cannot contain digits!" if($value =~ /\d/);
       $self->_name($value);

       return $self->_name();
   }

Use this to set the name of the accessor method for this column. If unset,
the name of the column will be used.

=item data_type

   { data_type => 'integer' }

This contains the column type. It is automatically filled if you use the
L<SQL::Translator::Producer::DBIx::Class::File> producer, or the
L<DBIx::Class::Schema::Loader> module. 

Currently there is no standard set of values for the data_type. Use
whatever your database supports.

=item size

   { size => 20 }

The length of your column, if it is a column type that can have a size
restriction. This is currently only used to create tables from your
schema, see L<DBIx::Class::Schema/deploy>.

=item is_nullable

   { is_nullable => 1 }

Set this to a true value for a columns that is allowed to contain NULL
values, default is false. This is currently only used to create tables
from your schema, see L<DBIx::Class::Schema/deploy>.

=item is_auto_increment

   { is_auto_increment => 1 }

Set this to a true value for a column whose value is somehow
automatically set, defaults to false. This is used to determine which
columns to empty when cloning objects using
L<DBIx::Class::Row/copy>. It is also used by
L<DBIx::Class::Schema/deploy>.

=item is_numeric

   { is_numeric => 1 }

Set this to a true or false value (not C<undef>) to explicitly specify
if this column contains numeric data. This controls how set_column
decides whether to consider a column dirty after an update: if
C<is_numeric> is true a numeric comparison C<< != >> will take place
instead of the usual C<eq>

If not specified the storage class will attempt to figure this out on
first access to the column, based on the column C<data_type>. The
result will be cached in this attribute.

=item is_foreign_key

   { is_foreign_key => 1 }

Set this to a true value for a column that contains a key from a
foreign table, defaults to false. This is currently only used to
create tables from your schema, see L<DBIx::Class::Schema/deploy>.

=item default_value

   { default_value => \'now()' }

Set this to the default value which will be inserted into a column by
the database. Can contain either a value or a function (use a
reference to a scalar e.g. C<\'now()'> if you want a function). This
is currently only used to create tables from your schema, see
L<DBIx::Class::Schema/deploy>.

See the note on L<DBIx::Class::Row/new> for more information about possible
issues related to db-side default values.

=item sequence

   { sequence => 'my_table_seq' }

Set this on a primary key column to the name of the sequence used to
generate a new key value. If not specified, L<DBIx::Class::PK::Auto>
will attempt to retrieve the name of the sequence from the database
automatically.

=item auto_nextval

Set this to a true value for a column whose value is retrieved automatically
from a sequence or function (if supported by your Storage driver.) For a
sequence, if you do not use a trigger to get the nextval, you have to set the
L</sequence> value as well.

Also set this for MSSQL columns with the 'uniqueidentifier'
L<DBIx::Class::ResultSource/data_type> whose values you want to automatically
generate using C<NEWID()>, unless they are a primary key in which case this will
be done anyway.

=item extra

This is used by L<DBIx::Class::Schema/deploy> and L<SQL::Translator>
to add extra non-generic data to the column. For example: C<< extra
=> { unsigned => 1} >> is used by the MySQL producer to set an integer
column to unsigned. For more details, see
L<SQL::Translator::Producer::MySQL>.

=back

=head2 add_column

=over

=item Arguments: $colname, \%columninfo?

=item Return value: 1/0 (true/false)

=back

  $source->add_column('col' => \%info);

Add a single column and optional column info. Uses the same column
info keys as L</add_columns>.

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

sub add_column { shift->add_columns(@_); } # DO NOT CHANGE THIS TO GLOB

=head2 has_column

=over

=item Arguments: $colname

=item Return value: 1/0 (true/false)

=back

  if ($source->has_column($colname)) { ... }

Returns true if the source has a column of this name, false otherwise.

=cut

sub has_column {
  my ($self, $column) = @_;
  return exists $self->_columns->{$column};
}

=head2 column_info

=over

=item Arguments: $colname

=item Return value: Hashref of info

=back

  my $info = $source->column_info($col);

Returns the column metadata hashref for a column, as originally passed
to L</add_columns>. See L</add_columns> above for information on the
contents of the hashref.

=cut

sub column_info {
  my ($self, $column) = @_;
  $self->throw_exception("No such column $column")
    unless exists $self->_columns->{$column};
  #warn $self->{_columns_info_loaded}, "\n";
  if ( ! $self->_columns->{$column}{data_type}
       and $self->column_info_from_storage
       and ! $self->{_columns_info_loaded}
       and $self->schema and $self->storage )
  {
    $self->{_columns_info_loaded}++;
    my $info = {};
    my $lc_info = {};
    # eval for the case of storage without table
    eval { $info = $self->storage->columns_info_for( $self->from ) };
    unless ($@) {
      for my $realcol ( keys %{$info} ) {
        $lc_info->{lc $realcol} = $info->{$realcol};
      }
      foreach my $col ( keys %{$self->_columns} ) {
        $self->_columns->{$col} = {
          %{ $self->_columns->{$col} },
          %{ $info->{$col} || $lc_info->{lc $col} || {} }
        };
      }
    }
  }
  return $self->_columns->{$column};
}

=head2 columns

=over

=item Arguments: None

=item Return value: Ordered list of column names

=back

  my @column_names = $source->columns;

Returns all column names in the order they were declared to L</add_columns>.

=cut

sub columns {
  my $self = shift;
  $self->throw_exception(
    "columns() is a read-only accessor, did you mean add_columns()?"
  ) if (@_ > 1);
  return @{$self->{_ordered_columns}||[]};
}

=head2 remove_columns

=over

=item Arguments: @colnames

=item Return value: undefined

=back

  $source->remove_columns(qw/col1 col2 col3/);

Removes the given list of columns by name, from the result source.

B<Warning>: Removing a column that is also used in the sources primary
key, or in one of the sources unique constraints, B<will> result in a
broken result source.

=head2 remove_column

=over

=item Arguments: $colname

=item Return value: undefined

=back

  $source->remove_column('col');

Remove a single column by name from the result source, similar to
L</remove_columns>.

B<Warning>: Removing a column that is also used in the sources primary
key, or in one of the sources unique constraints, B<will> result in a
broken result source.

=cut

sub remove_columns {
  my ($self, @to_remove) = @_;

  my $columns = $self->_columns
    or return;

  my %to_remove;
  for (@to_remove) {
    delete $columns->{$_};
    ++$to_remove{$_};
  }

  $self->_ordered_columns([ grep { not $to_remove{$_} } @{$self->_ordered_columns} ]);
}

sub remove_column { shift->remove_columns(@_); } # DO NOT CHANGE THIS TO GLOB

=head2 set_primary_key

=over 4

=item Arguments: @cols

=item Return value: undefined

=back

Defines one or more columns as primary key for this source. Must be
called after L</add_columns>.

Additionally, defines a L<unique constraint|add_unique_constraint>
named C<primary>.

The primary key columns are used by L<DBIx::Class::PK::Auto> to
retrieve automatically created values from the database. They are also
used as default joining columns when specifying relationships, see
L<DBIx::Class::Relationship>.

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

=over 4

=item Arguments: None

=item Return value: Ordered list of primary column names

=back

Read-only accessor which returns the list of primary keys, supplied by
L</set_primary_key>.

=cut

sub primary_columns {
  return @{shift->_primaries||[]};
}

=head2 add_unique_constraint

=over 4

=item Arguments: $name?, \@colnames

=item Return value: undefined

=back

Declare a unique constraint on this source. Call once for each unique
constraint.

  # For UNIQUE (column1, column2)
  __PACKAGE__->add_unique_constraint(
    constraint_name => [ qw/column1 column2/ ],
  );

Alternatively, you can specify only the columns:

  __PACKAGE__->add_unique_constraint([ qw/column1 column2/ ]);

This will result in a unique constraint named
C<table_column1_column2>, where C<table> is replaced with the table
name.

Unique constraints are used, for example, when you pass the constraint
name as the C<key> attribute to L<DBIx::Class::ResultSet/find>. Then
only columns in the constraint are searched.

Throws an error if any of the given column names do not yet exist on
the result source.

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

=over 4

=item Arguments: @colnames

=item Return value: Constraint name

=back

  $source->table('mytable');
  $source->name_unique_constraint('col1', 'col2');
  # returns
  'mytable_col1_col2'

Return a name for a unique constraint containing the specified
columns. The name is created by joining the table name and each column
name, using an underscore character.

For example, a constraint on a table named C<cd> containing the columns
C<artist> and C<title> would result in a constraint name of C<cd_artist_title>.

This is used by L</add_unique_constraint> if you do not specify the
optional constraint name.

=cut

sub name_unique_constraint {
  my ($self, $cols) = @_;

  my $name = $self->name;
  $name = $$name if (ref $name eq 'SCALAR');

  return join '_', $name, @$cols;
}

=head2 unique_constraints

=over 4

=item Arguments: None

=item Return value: Hash of unique constraint data

=back

  $source->unique_constraints();

Read-only accessor which returns a hash of unique constraints on this
source.

The hash is keyed by constraint name, and contains an arrayref of
column names as values.

=cut

sub unique_constraints {
  return %{shift->_unique_constraints||{}};
}

=head2 unique_constraint_names

=over 4

=item Arguments: None

=item Return value: Unique constraint names

=back

  $source->unique_constraint_names();

Returns the list of unique constraint names defined on this source.

=cut

sub unique_constraint_names {
  my ($self) = @_;

  my %unique_constraints = $self->unique_constraints;

  return keys %unique_constraints;
}

=head2 unique_constraint_columns

=over 4

=item Arguments: $constraintname

=item Return value: List of constraint columns

=back

  $source->unique_constraint_columns('myconstraint');

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

=head2 sqlt_deploy_callback

=over

=item Arguments: $callback

=back

  __PACKAGE__->sqlt_deploy_callback('mycallbackmethod');

An accessor to set a callback to be called during deployment of
the schema via L<DBIx::Class::Schema/create_ddl_dir> or
L<DBIx::Class::Schema/deploy>.

The callback can be set as either a code reference or the name of a
method in the current result class.

If not set, the L</default_sqlt_deploy_hook> is called.

Your callback will be passed the $source object representing the
ResultSource instance being deployed, and the
L<SQL::Translator::Schema::Table> object being created from it. The
callback can be used to manipulate the table object or add your own
customised indexes. If you need to manipulate a non-table object, use
the L<DBIx::Class::Schema/sqlt_deploy_hook>.

See L<DBIx::Class::Manual::Cookbook/Adding Indexes And Functions To
Your SQL> for examples.

This sqlt deployment callback can only be used to manipulate
SQL::Translator objects as they get turned into SQL. To execute
post-deploy statements which SQL::Translator does not currently
handle, override L<DBIx::Class::Schema/deploy> in your Schema class
and call L<dbh_do|DBIx::Class::Storage::DBI/dbh_do>.

=head2 default_sqlt_deploy_hook

=over

=item Arguments: $source, $sqlt_table

=item Return value: undefined

=back

This is the sensible default for L</sqlt_deploy_callback>.

If a method named C<sqlt_deploy_hook> exists in your Result class, it
will be called and passed the current C<$source> and the
C<$sqlt_table> being deployed.

=cut

sub default_sqlt_deploy_hook {
  my $self = shift;

  my $class = $self->result_class;

  if ($class and $class->can('sqlt_deploy_hook')) {
    $class->sqlt_deploy_hook(@_);
  }
}

sub _invoke_sqlt_deploy_hook {
  my $self = shift;
  if ( my $hook = $self->sqlt_deploy_callback) {
    $self->$hook(@_);
  }
}

=head2 resultset

=over 4

=item Arguments: None

=item Return value: $resultset

=back

Returns a resultset for the given source. This will initially be created
on demand by calling

  $self->resultset_class->new($self, $self->resultset_attributes)

but is cached from then on unless resultset_class changes.

=head2 resultset_class

=over 4

=item Arguments: $classname

=item Return value: $classname

=back

  package My::Schema::ResultSet::Artist;
  use base 'DBIx::Class::ResultSet';
  ...

  # In the result class
  __PACKAGE__->resultset_class('My::Schema::ResultSet::Artist');

  # Or in code
  $source->resultset_class('My::Schema::ResultSet::Artist');

Set the class of the resultset. This is useful if you want to create your
own resultset methods. Create your own class derived from
L<DBIx::Class::ResultSet>, and set it here. If called with no arguments,
this method returns the name of the existing resultset class, if one
exists.

=head2 resultset_attributes

=over 4

=item Arguments: \%attrs

=item Return value: \%attrs

=back

  # In the result class
  __PACKAGE__->resultset_attributes({ order_by => [ 'id' ] });

  # Or in code
  $source->resultset_attributes({ order_by => [ 'id' ] });

Store a collection of resultset attributes, that will be set on every
L<DBIx::Class::ResultSet> produced from this result source. For a full
list see L<DBIx::Class::ResultSet/ATTRIBUTES>.

=cut

sub resultset {
  my $self = shift;
  $self->throw_exception(
    'resultset does not take any arguments. If you want another resultset, '.
    'call it on the schema instead.'
  ) if scalar @_;

  return $self->resultset_class->new(
    $self,
    {
      %{$self->{resultset_attributes}},
      %{$self->schema->default_resultset_attributes}
    },
  );
}

=head2 source_name

=over 4

=item Arguments: $source_name

=item Result value: $source_name

=back

Set an alternate name for the result source when it is loaded into a schema.
This is useful if you want to refer to a result source by a name other than
its class name.

  package ArchivedBooks;
  use base qw/DBIx::Class/;
  __PACKAGE__->table('books_archive');
  __PACKAGE__->source_name('Books');

  # from your schema...
  $schema->resultset('Books')->find(1);

=head2 from

=over 4

=item Arguments: None

=item Return value: FROM clause

=back

  my $from_clause = $source->from();

Returns an expression of the source to be supplied to storage to specify
retrieval from this source. In the case of a database, the required FROM
clause contents.

=head2 schema

=over 4

=item Arguments: None

=item Return value: A schema object

=back

  my $schema = $source->schema();

Returns the L<DBIx::Class::Schema> object that this result source 
belongs to.

=head2 storage

=over 4

=item Arguments: None

=item Return value: A Storage object

=back

  $source->storage->debug(1);

Returns the storage handle for the current schema.

See also: L<DBIx::Class::Storage>

=cut

sub storage { shift->schema->storage; }

=head2 add_relationship

=over 4

=item Arguments: $relname, $related_source_name, \%cond, [ \%attrs ]

=item Return value: 1/true if it succeeded

=back

  $source->add_relationship('relname', 'related_source', $cond, $attrs);

L<DBIx::Class::Relationship> describes a series of methods which
create pre-defined useful types of relationships. Look there first
before using this method directly.

The relationship name can be arbitrary, but must be unique for each
relationship attached to this result source. 'related_source' should
be the name with which the related result source was registered with
the current schema. For example:

  $schema->source('Book')->add_relationship('reviews', 'Review', {
    'foreign.book_id' => 'self.id',
  });

The condition C<$cond> needs to be an L<SQL::Abstract>-style
representation of the join between the tables. For example, if you're
creating a relation from Author to Book,

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

Throws an exception if the condition is improperly supplied, or cannot
be resolved.

=cut

sub add_relationship {
  my ($self, $rel, $f_source_name, $cond, $attrs) = @_;
  $self->throw_exception("Can't create relationship without join condition")
    unless $cond;
  $attrs ||= {};

  # Check foreign and self are right in cond
  if ( (ref $cond ||'') eq 'HASH') {
    for (keys %$cond) {
      $self->throw_exception("Keys of condition should be of form 'foreign.col', not '$_'")
        if /\./ && !/^foreign\./;
    }
  }

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

  eval { $self->_resolve_join($rel, 'me', {}, []) };

  if ($@) { # If the resolve failed, back out and re-throw the error
    delete $rels{$rel}; #
    $self->_relationships(\%rels);
    $self->throw_exception("Error creating relationship $rel: $@");
  }
  1;
}

=head2 relationships

=over 4

=item Arguments: None

=item Return value: List of relationship names

=back

  my @relnames = $source->relationships();

Returns all relationship names for this source.

=cut

sub relationships {
  return keys %{shift->_relationships};
}

=head2 relationship_info

=over 4

=item Arguments: $relname

=item Return value: Hashref of relation data,

=back

Returns a hash of relationship information for the specified relationship
name. The keys/values are as specified for L</add_relationship>.

=cut

sub relationship_info {
  my ($self, $rel) = @_;
  return $self->_relationships->{$rel};
}

=head2 has_relationship

=over 4

=item Arguments: $rel

=item Return value: 1/0 (true/false)

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

=item Return value: Hashref of relationship data

=back

Looks through all the relationships on the source this relationship
points to, looking for one whose condition is the reverse of the
condition on this relationship.

A common use of this is to find the name of the C<belongs_to> relation
opposing a C<has_many> relation. For definition of these look in
L<DBIx::Class::Relationship>.

The returned hashref is keyed by the name of the opposing
relationship, and contains its data in the same manner as
L</relationship_info>.

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
    next unless $back->source_name eq $self->source_name;

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
      next if (!$self->_compare_relationship_keys(\@refkeys, \@other_keys) ||
               !$self->_compare_relationship_keys(\@other_refkeys, \@keys));
      $ret->{$otherrel} =  $otherrel_info;
    }
  }
  return $ret;
}

sub compare_relationship_keys {
  carp 'compare_relationship_keys is a private method, stop calling it';
  my $self = shift;
  $self->_compare_relationship_keys (@_);
}

# Returns true if both sets of keynames are the same, false otherwise.
sub _compare_relationship_keys {
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

sub resolve_join {
  carp 'resolve_join is a private method, stop calling it';
  my $self = shift;
  $self->_resolve_join (@_);
}

# Returns the {from} structure used to express JOIN conditions
sub _resolve_join {
  my ($self, $join, $alias, $seen, $jpath, $parent_force_left) = @_;

  # we need a supplied one, because we do in-place modifications, no returns
  $self->throw_exception ('You must supply a seen hashref as the 3rd argument to _resolve_join')
    unless ref $seen eq 'HASH';

  $self->throw_exception ('You must supply a joinpath arrayref as the 4th argument to _resolve_join')
    unless ref $jpath eq 'ARRAY';

  $jpath = [@$jpath];

  if (not defined $join) {
    return ();
  }
  elsif (ref $join eq 'ARRAY') {
    return
      map {
        $self->_resolve_join($_, $alias, $seen, $jpath, $parent_force_left);
      } @$join;
  }
  elsif (ref $join eq 'HASH') {

    my @ret;
    for my $rel (keys %$join) {

      my $rel_info = $self->relationship_info($rel)
        or $self->throw_exception("No such relationship ${rel}");

      my $force_left = $parent_force_left;
      $force_left ||= lc($rel_info->{attrs}{join_type}||'') eq 'left';

      # the actual seen value will be incremented by the recursion
      my $as = ($seen->{$rel} ? join ('_', $rel, $seen->{$rel} + 1) : $rel);

      push @ret, (
        $self->_resolve_join($rel, $alias, $seen, [@$jpath], $force_left),
        $self->related_source($rel)->_resolve_join(
          $join->{$rel}, $as, $seen, [@$jpath, $rel], $force_left
        )
      );
    }
    return @ret;

  }
  elsif (ref $join) {
    $self->throw_exception("No idea how to resolve join reftype ".ref $join);
  }
  else {
    my $count = ++$seen->{$join};
    my $as = ($count > 1 ? "${join}_${count}" : $join);

    my $rel_info = $self->relationship_info($join)
      or $self->throw_exception("No such relationship ${join}");

    my $rel_src = $self->related_source($join);
    return [ { $as => $rel_src->from,
               -source_handle => $rel_src->handle,
               -join_type => $parent_force_left
                  ? 'left'
                  : $rel_info->{attrs}{join_type}
                ,
               -join_path => [@$jpath, $join],
               -alias => $as,
               -relation_chain_depth => $seen->{-relation_chain_depth} || 0,
             },
             $self->_resolve_condition($rel_info->{cond}, $as, $alias) ];
  }
}

sub pk_depends_on {
  carp 'pk_depends_on is a private method, stop calling it';
  my $self = shift;
  $self->_pk_depends_on (@_);
}

# Determines whether a relation is dependent on an object from this source
# having already been inserted. Takes the name of the relationship and a
# hashref of columns of the related object.
sub _pk_depends_on {
  my ($self, $relname, $rel_data) = @_;

  my $relinfo = $self->relationship_info($relname);

  # don't assume things if the relationship direction is specified
  return $relinfo->{attrs}{is_foreign_key_constraint}
    if exists ($relinfo->{attrs}{is_foreign_key_constraint});

  my $cond = $relinfo->{cond};
  return 0 unless ref($cond) eq 'HASH';

  # map { foreign.foo => 'self.bar' } to { bar => 'foo' }
  my $keyhash = { map { my $x = $_; $x =~ s/.*\.//; $x; } reverse %$cond };

  # assume anything that references our PK probably is dependent on us
  # rather than vice versa, unless the far side is (a) defined or (b)
  # auto-increment
  my $rel_source = $self->related_source($relname);

  foreach my $p ($self->primary_columns) {
    if (exists $keyhash->{$p}) {
      unless (defined($rel_data->{$keyhash->{$p}})
              || $rel_source->column_info($keyhash->{$p})
                            ->{is_auto_increment}) {
        return 0;
      }
    }
  }

  return 1;
}

sub resolve_condition {
  carp 'resolve_condition is a private method, stop calling it';
  my $self = shift;
  $self->_resolve_condition (@_);
}

# Resolves the passed condition to a concrete query fragment. If given an alias,
# returns a join condition; if given an object, inverts that object to produce
# a related conditional from that object.
our $UNRESOLVABLE_CONDITION = \'1 = 0';

sub _resolve_condition {
  my ($self, $cond, $as, $for) = @_;
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
        unless ($for->has_column_loaded($v)) {
          if ($for->in_storage) {
            $self->throw_exception(sprintf
              'Unable to resolve relationship from %s to %s: column %s.%s not '
            . 'loaded from storage (or not passed to new() prior to insert()). '
            . 'Maybe you forgot to call ->discard_changes to get defaults from the db.',

              $for->result_source->source_name,
              $as,
              $as, $v,
            );
          }
          return $UNRESOLVABLE_CONDITION;
        }
        $ret{$k} = $for->get_column($v);
        #$ret{$k} = $for->get_column($v) if $for->has_column_loaded($v);
        #warn %ret;
      } elsif (!defined $for) { # undef, i.e. "no object"
        $ret{$k} = undef;
      } elsif (ref $as eq 'HASH') { # reverse hashref
        $ret{$v} = $as->{$k};
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
    return [ map { $self->_resolve_condition($_, $as, $for) } @$cond ];
  } else {
   die("Can't handle condition $cond yet :(");
  }
}

# Legacy code, needs to go entirely away (fully replaced by _resolve_prefetch)
sub resolve_prefetch {
  carp 'resolve_prefetch is a private method, stop calling it';

  my ($self, $pre, $alias, $seen, $order, $collapse) = @_;
  $seen ||= {};
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
      my $dots = @{[$as_prefix =~ m/\./g]} + 1; # +1 to match the ".${as_prefix}"
      if (my ($fail) = grep { @{[$_ =~ m/\./g]} == $dots }
                         keys %{$collapse}) {
        my ($last) = ($fail =~ /([^\.]+)$/);
        carp (
          "Prefetching multiple has_many rels ${last} and ${pre} "
          .(length($as_prefix)
            ? "at the same level (${as_prefix}) "
            : "at top level "
          )
          . 'will explode the number of row objects retrievable via ->next or ->all. '
          . 'Use at your own risk.'
        );
      }
      #my @col = map { (/^self\.(.+)$/ ? ("${as_prefix}.$1") : ()); }
      #              values %{$rel_info->{cond}};
      $collapse->{".${as_prefix}${pre}"} = [ $rel_source->primary_columns ];
        # action at a distance. prepending the '.' allows simpler code
        # in ResultSet->_collapse_result
      my @key = map { (/^foreign\.(.+)$/ ? ($1) : ()); }
                    keys %{$rel_info->{cond}};
      my @ord = (ref($rel_info->{attrs}{order_by}) eq 'ARRAY'
                   ? @{$rel_info->{attrs}{order_by}}
                   : (defined $rel_info->{attrs}{order_by}
                       ? ($rel_info->{attrs}{order_by})
                       : ()));
      push(@$order, map { "${as}.$_" } (@key, @ord));
    }

    return map { [ "${as}.$_", "${as_prefix}${pre}.$_", ] }
      $rel_source->columns;
  }
}

# Accepts one or more relationships for the current source and returns an
# array of column names for each of those relationships. Column names are
# prefixed relative to the current source, in accordance with where they appear
# in the supplied relationships. Needs an alias_map generated by
# $rs->_joinpath_aliases

sub _resolve_prefetch {
  my ($self, $pre, $alias, $alias_map, $order, $collapse, $pref_path) = @_;
  $pref_path ||= [];

  if (not defined $pre) {
    return ();
  }
  elsif( ref $pre eq 'ARRAY' ) {
    return
      map { $self->_resolve_prefetch( $_, $alias, $alias_map, $order, $collapse, [ @$pref_path ] ) }
        @$pre;
  }
  elsif( ref $pre eq 'HASH' ) {
    my @ret =
    map {
      $self->_resolve_prefetch($_, $alias, $alias_map, $order, $collapse, [ @$pref_path ] ),
      $self->related_source($_)->_resolve_prefetch(
               $pre->{$_}, "${alias}.$_", $alias_map, $order, $collapse, [ @$pref_path, $_] )
    } keys %$pre;
    return @ret;
  }
  elsif( ref $pre ) {
    $self->throw_exception(
      "don't know how to resolve prefetch reftype ".ref($pre));
  }
  else {
    my $p = $alias_map;
    $p = $p->{$_} for (@$pref_path, $pre);

    $self->throw_exception (
      "Unable to resolve prefetch '$pre' - join alias map does not contain an entry for path: "
      . join (' -> ', @$pref_path, $pre)
    ) if (ref $p->{-join_aliases} ne 'ARRAY' or not @{$p->{-join_aliases}} );

    my $as = shift @{$p->{-join_aliases}};

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
      my $dots = @{[$as_prefix =~ m/\./g]} + 1; # +1 to match the ".${as_prefix}"
      if (my ($fail) = grep { @{[$_ =~ m/\./g]} == $dots }
                         keys %{$collapse}) {
        my ($last) = ($fail =~ /([^\.]+)$/);
        carp (
          "Prefetching multiple has_many rels ${last} and ${pre} "
          .(length($as_prefix)
            ? "at the same level (${as_prefix}) "
            : "at top level "
          )
          . 'will explode the number of row objects retrievable via ->next or ->all. '
          . 'Use at your own risk.'
        );
      }
      #my @col = map { (/^self\.(.+)$/ ? ("${as_prefix}.$1") : ()); }
      #              values %{$rel_info->{cond}};
      $collapse->{".${as_prefix}${pre}"} = [ $rel_source->primary_columns ];
        # action at a distance. prepending the '.' allows simpler code
        # in ResultSet->_collapse_result
      my @key = map { (/^foreign\.(.+)$/ ? ($1) : ()); }
                    keys %{$rel_info->{cond}};
      my @ord = (ref($rel_info->{attrs}{order_by}) eq 'ARRAY'
                   ? @{$rel_info->{attrs}{order_by}}
                   : (defined $rel_info->{attrs}{order_by}
                       ? ($rel_info->{attrs}{order_by})
                       : ()));
      push(@$order, map { "${as}.$_" } (@key, @ord));
    }

    return map { [ "${as}.$_", "${as_prefix}${pre}.$_", ] }
      $rel_source->columns;
  }
}

=head2 related_source

=over 4

=item Arguments: $relname

=item Return value: $source

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

=item Return value: $classname

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

=head2 handle

Obtain a new handle to this source. Returns an instance of a 
L<DBIx::Class::ResultSourceHandle>.

=cut

sub handle {
    return new DBIx::Class::ResultSourceHandle({
        schema         => $_[0]->schema,
        source_moniker => $_[0]->source_name
    });
}

=head2 throw_exception

See L<DBIx::Class::Schema/"throw_exception">.

=cut

sub throw_exception {
  my $self = shift;

  if (defined $self->schema) {
    $self->schema->throw_exception(@_);
  }
  else {
    DBIx::Class::Exception->throw(@_);
  }
}

=head2 source_info

Stores a hashref of per-source metadata.  No specific key names
have yet been standardized, the examples below are purely hypothetical
and don't actually accomplish anything on their own:

  __PACKAGE__->source_info({
    "_tablespace" => 'fast_disk_array_3',
    "_engine" => 'InnoDB',
  });

=head2 new

  $class->new();

  $class->new({attribute_name => value});

Creates a new ResultSource object.  Not normally called directly by end users.

=head2 column_info_from_storage

=over

=item Arguments: 1/0 (default: 0)

=item Return value: 1/0

=back

  __PACKAGE__->column_info_from_storage(1);

Enables the on-demand automatic loading of the above column
metadata from storage as neccesary.  This is *deprecated*, and
should not be used.  It will be removed before 1.0.


=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

1;
