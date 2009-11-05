package DBIx::Class::ResultSet;

use strict;
use warnings;
use overload
        '0+'     => "count",
        'bool'   => "_bool",
        fallback => 1;
use Carp::Clan qw/^DBIx::Class/;
use DBIx::Class::Exception;
use Data::Page;
use Storable;
use DBIx::Class::ResultSetColumn;
use DBIx::Class::ResultSourceHandle;
use List::Util ();
use Scalar::Util ();
use base qw/DBIx::Class/;

__PACKAGE__->mk_group_accessors('simple' => qw/_result_class _source_handle/);

=head1 NAME

DBIx::Class::ResultSet - Represents a query used for fetching a set of results.

=head1 SYNOPSIS

  my $users_rs   = $schema->resultset('User');
  my $registered_users_rs   = $schema->resultset('User')->search({ registered => 1 });
  my @cds_in_2005 = $schema->resultset('CD')->search({ year => 2005 })->all();

=head1 DESCRIPTION

A ResultSet is an object which stores a set of conditions representing
a query. It is the backbone of DBIx::Class (i.e. the really
important/useful bit).

No SQL is executed on the database when a ResultSet is created, it
just stores all the conditions needed to create the query.

A basic ResultSet representing the data of an entire table is returned
by calling C<resultset> on a L<DBIx::Class::Schema> and passing in a
L<Source|DBIx::Class::Manual::Glossary/Source> name.

  my $users_rs = $schema->resultset('User');

A new ResultSet is returned from calling L</search> on an existing
ResultSet. The new one will contain all the conditions of the
original, plus any new conditions added in the C<search> call.

A ResultSet also incorporates an implicit iterator. L</next> and L</reset>
can be used to walk through all the L<DBIx::Class::Row>s the ResultSet
represents.

The query that the ResultSet represents is B<only> executed against
the database when these methods are called:
L</find> L</next> L</all> L</first> L</single> L</count>

=head1 EXAMPLES

=head2 Chaining resultsets

Let's say you've got a query that needs to be run to return some data
to the user. But, you have an authorization system in place that
prevents certain users from seeing certain information. So, you want
to construct the basic query in one method, but add constraints to it in
another.

  sub get_data {
    my $self = shift;
    my $request = $self->get_request; # Get a request object somehow.
    my $schema = $self->get_schema;   # Get the DBIC schema object somehow.

    my $cd_rs = $schema->resultset('CD')->search({
      title => $request->param('title'),
      year => $request->param('year'),
    });

    $self->apply_security_policy( $cd_rs );

    return $cd_rs->all();
  }

  sub apply_security_policy {
    my $self = shift;
    my ($rs) = @_;

    return $rs->search({
      subversive => 0,
    });
  }

=head3 Resolving conditions and attributes

When a resultset is chained from another resultset, conditions and
attributes with the same keys need resolving.

L</join>, L</prefetch>, L</+select>, L</+as> attributes are merged
into the existing ones from the original resultset.

The L</where>, L</having> attribute, and any search conditions are
merged with an SQL C<AND> to the existing condition from the original
resultset.

All other attributes are overridden by any new ones supplied in the
search attributes.

=head2 Multiple queries

Since a resultset just defines a query, you can do all sorts of
things with it with the same object.

  # Don't hit the DB yet.
  my $cd_rs = $schema->resultset('CD')->search({
    title => 'something',
    year => 2009,
  });

  # Each of these hits the DB individually.
  my $count = $cd_rs->count;
  my $most_recent = $cd_rs->get_column('date_released')->max();
  my @records = $cd_rs->all;

And it's not just limited to SELECT statements.

  $cd_rs->delete();

This is even cooler:

  $cd_rs->create({ artist => 'Fred' });

Which is the same as:

  $schema->resultset('CD')->create({
    title => 'something',
    year => 2009,
    artist => 'Fred'
  });

See: L</search>, L</count>, L</get_column>, L</all>, L</create>.

=head1 OVERLOADING

If a resultset is used in a numeric context it returns the L</count>.
However, if it is used in a booleand context it is always true.  So if
you want to check if a resultset has any results use C<if $rs != 0>.
C<if $rs> will always be true.

=head1 METHODS

=head2 new

=over 4

=item Arguments: $source, \%$attrs

=item Return Value: $rs

=back

The resultset constructor. Takes a source object (usually a
L<DBIx::Class::ResultSourceProxy::Table>) and an attribute hash (see
L</ATTRIBUTES> below).  Does not perform any queries -- these are
executed as needed by the other methods.

Generally you won't need to construct a resultset manually.  You'll
automatically get one from e.g. a L</search> called in scalar context:

  my $rs = $schema->resultset('CD')->search({ title => '100th Window' });

IMPORTANT: If called on an object, proxies to new_result instead so

  my $cd = $schema->resultset('CD')->new({ title => 'Spoon' });

will return a CD object, not a ResultSet.

=cut

sub new {
  my $class = shift;
  return $class->new_result(@_) if ref $class;

  my ($source, $attrs) = @_;
  $source = $source->handle
    unless $source->isa('DBIx::Class::ResultSourceHandle');
  $attrs = { %{$attrs||{}} };

  if ($attrs->{page}) {
    $attrs->{rows} ||= 10;
  }

  $attrs->{alias} ||= 'me';

  # Creation of {} and bless separated to mitigate RH perl bug
  # see https://bugzilla.redhat.com/show_bug.cgi?id=196836
  my $self = {
    _source_handle => $source,
    cond => $attrs->{where},
    count => undef,
    pager => undef,
    attrs => $attrs
  };

  bless $self, $class;

  $self->result_class(
    $attrs->{result_class} || $source->resolve->result_class
  );

  return $self;
}

=head2 search

=over 4

=item Arguments: $cond, \%attrs?

=item Return Value: $resultset (scalar context), @row_objs (list context)

=back

  my @cds    = $cd_rs->search({ year => 2001 }); # "... WHERE year = 2001"
  my $new_rs = $cd_rs->search({ year => 2005 });

  my $new_rs = $cd_rs->search([ { year => 2005 }, { year => 2004 } ]);
                 # year = 2005 OR year = 2004

If you need to pass in additional attributes but no additional condition,
call it as C<search(undef, \%attrs)>.

  # "SELECT name, artistid FROM $artist_table"
  my @all_artists = $schema->resultset('Artist')->search(undef, {
    columns => [qw/name artistid/],
  });

For a list of attributes that can be passed to C<search>, see
L</ATTRIBUTES>. For more examples of using this function, see
L<Searching|DBIx::Class::Manual::Cookbook/Searching>. For a complete
documentation for the first argument, see L<SQL::Abstract>.

For more help on using joins with search, see L<DBIx::Class::Manual::Joining>.

=cut

sub search {
  my $self = shift;
  my $rs = $self->search_rs( @_ );
  return (wantarray ? $rs->all : $rs);
}

=head2 search_rs

=over 4

=item Arguments: $cond, \%attrs?

=item Return Value: $resultset

=back

This method does the same exact thing as search() except it will
always return a resultset, even in list context.

=cut

sub search_rs {
  my $self = shift;

  # Special-case handling for (undef, undef).
  if ( @_ == 2 && !defined $_[1] && !defined $_[0] ) {
    pop(@_); pop(@_);
  }

  my $attrs = {};
  $attrs = pop(@_) if @_ > 1 and ref $_[$#_] eq 'HASH';
  my $our_attrs = { %{$self->{attrs}} };
  my $having = delete $our_attrs->{having};
  my $where = delete $our_attrs->{where};

  my $rows;

  my %safe = (alias => 1, cache => 1);

  unless (
    (@_ && defined($_[0])) # @_ == () or (undef)
    ||
    (keys %$attrs # empty attrs or only 'safe' attrs
    && List::Util::first { !$safe{$_} } keys %$attrs)
  ) {
    # no search, effectively just a clone
    $rows = $self->get_cache;
  }

  my $new_attrs = { %{$our_attrs}, %{$attrs} };

  # merge new attrs into inherited
  foreach my $key (qw/join prefetch +select +as bind/) {
    next unless exists $attrs->{$key};
    $new_attrs->{$key} = $self->_merge_attr($our_attrs->{$key}, $attrs->{$key});
  }

  my $cond = (@_
    ? (
        (@_ == 1 || ref $_[0] eq "HASH")
          ? (
              (ref $_[0] eq 'HASH')
                ? (
                    (keys %{ $_[0] }  > 0)
                      ? shift
                      : undef
                   )
                :  shift
             )
          : (
              (@_ % 2)
                ? $self->throw_exception("Odd number of arguments to search")
                : {@_}
             )
      )
    : undef
  );

  if (defined $where) {
    $new_attrs->{where} = (
      defined $new_attrs->{where}
        ? { '-and' => [
              map {
                ref $_ eq 'ARRAY' ? [ -or => $_ ] : $_
              } $where, $new_attrs->{where}
            ]
          }
        : $where);
  }

  if (defined $cond) {
    $new_attrs->{where} = (
      defined $new_attrs->{where}
        ? { '-and' => [
              map {
                ref $_ eq 'ARRAY' ? [ -or => $_ ] : $_
              } $cond, $new_attrs->{where}
            ]
          }
        : $cond);
  }

  if (defined $having) {
    $new_attrs->{having} = (
      defined $new_attrs->{having}
        ? { '-and' => [
              map {
                ref $_ eq 'ARRAY' ? [ -or => $_ ] : $_
              } $having, $new_attrs->{having}
            ]
          }
        : $having);
  }

  my $rs = (ref $self)->new($self->result_source, $new_attrs);
  if ($rows) {
    $rs->set_cache($rows);
  }
  return $rs;
}

=head2 search_literal

=over 4

=item Arguments: $sql_fragment, @bind_values

=item Return Value: $resultset (scalar context), @row_objs (list context)

=back

  my @cds   = $cd_rs->search_literal('year = ? AND title = ?', qw/2001 Reload/);
  my $newrs = $artist_rs->search_literal('name = ?', 'Metallica');

Pass a literal chunk of SQL to be added to the conditional part of the
resultset query.

CAVEAT: C<search_literal> is provided for Class::DBI compatibility and should
only be used in that context. C<search_literal> is a convenience method.
It is equivalent to calling $schema->search(\[]), but if you want to ensure
columns are bound correctly, use C<search>.

Example of how to use C<search> instead of C<search_literal>

  my @cds = $cd_rs->search_literal('cdid = ? AND (artist = ? OR artist = ?)', (2, 1, 2));
  my @cds = $cd_rs->search(\[ 'cdid = ? AND (artist = ? OR artist = ?)', [ 'cdid', 2 ], [ 'artist', 1 ], [ 'artist', 2 ] ]);


See L<DBIx::Class::Manual::Cookbook/Searching> and
L<DBIx::Class::Manual::FAQ/Searching> for searching techniques that do not
require C<search_literal>.

=cut

sub search_literal {
  my ($self, $sql, @bind) = @_;
  my $attr;
  if ( @bind && ref($bind[-1]) eq 'HASH' ) {
    $attr = pop @bind;
  }
  return $self->search(\[ $sql, map [ __DUMMY__ => $_ ], @bind ], ($attr || () ));
}

=head2 find

=over 4

=item Arguments: @values | \%cols, \%attrs?

=item Return Value: $row_object | undef

=back

Finds a row based on its primary key or unique constraint. For example, to find
a row by its primary key:

  my $cd = $schema->resultset('CD')->find(5);

You can also find a row by a specific unique constraint using the C<key>
attribute. For example:

  my $cd = $schema->resultset('CD')->find('Massive Attack', 'Mezzanine', {
    key => 'cd_artist_title'
  });

Additionally, you can specify the columns explicitly by name:

  my $cd = $schema->resultset('CD')->find(
    {
      artist => 'Massive Attack',
      title  => 'Mezzanine',
    },
    { key => 'cd_artist_title' }
  );

If the C<key> is specified as C<primary>, it searches only on the primary key.

If no C<key> is specified, it searches on all unique constraints defined on the
source for which column data is provided, including the primary key.

If your table does not have a primary key, you B<must> provide a value for the
C<key> attribute matching one of the unique constraints on the source.

In addition to C<key>, L</find> recognizes and applies standard
L<resultset attributes|/ATTRIBUTES> in the same way as L</search> does.

Note: If your query does not return only one row, a warning is generated:

  Query returned more than one row

See also L</find_or_create> and L</update_or_create>. For information on how to
declare unique constraints, see
L<DBIx::Class::ResultSource/add_unique_constraint>.

=cut

sub find {
  my $self = shift;
  my $attrs = (@_ > 1 && ref $_[$#_] eq 'HASH' ? pop(@_) : {});

  # Default to the primary key, but allow a specific key
  my @cols = exists $attrs->{key}
    ? $self->result_source->unique_constraint_columns($attrs->{key})
    : $self->result_source->primary_columns;
  $self->throw_exception(
    "Can't find unless a primary key is defined or unique constraint is specified"
  ) unless @cols;

  # Parse out a hashref from input
  my $input_query;
  if (ref $_[0] eq 'HASH') {
    $input_query = { %{$_[0]} };
  }
  elsif (@_ == @cols) {
    $input_query = {};
    @{$input_query}{@cols} = @_;
  }
  else {
    # Compatibility: Allow e.g. find(id => $value)
    carp "Find by key => value deprecated; please use a hashref instead";
    $input_query = {@_};
  }

  my (%related, $info);

  KEY: foreach my $key (keys %$input_query) {
    if (ref($input_query->{$key})
        && ($info = $self->result_source->relationship_info($key))) {
      my $val = delete $input_query->{$key};
      next KEY if (ref($val) eq 'ARRAY'); # has_many for multi_create
      my $rel_q = $self->result_source->_resolve_condition(
                    $info->{cond}, $val, $key
                  );
      die "Can't handle OR join condition in find" if ref($rel_q) eq 'ARRAY';
      @related{keys %$rel_q} = values %$rel_q;
    }
  }
  if (my @keys = keys %related) {
    @{$input_query}{@keys} = values %related;
  }


  # Build the final query: Default to the disjunction of the unique queries,
  # but allow the input query in case the ResultSet defines the query or the
  # user is abusing find
  my $alias = exists $attrs->{alias} ? $attrs->{alias} : $self->{attrs}{alias};
  my $query;
  if (exists $attrs->{key}) {
    my @unique_cols = $self->result_source->unique_constraint_columns($attrs->{key});
    my $unique_query = $self->_build_unique_query($input_query, \@unique_cols);
    $query = $self->_add_alias($unique_query, $alias);
  }
  elsif ($self->{attrs}{accessor} and $self->{attrs}{accessor} eq 'single') {
    # This means that we got here after a merger of relationship conditions
    # in ::Relationship::Base::search_related (the row method), and furthermore
    # the relationship is of the 'single' type. This means that the condition
    # provided by the relationship (already attached to $self) is sufficient,
    # as there can be only one row in the databse that would satisfy the 
    # relationship
  }
  else {
    my @unique_queries = $self->_unique_queries($input_query, $attrs);
    $query = @unique_queries
      ? [ map { $self->_add_alias($_, $alias) } @unique_queries ]
      : $self->_add_alias($input_query, $alias);
  }

  # Run the query
  my $rs = $self->search ($query, $attrs);
  if (keys %{$rs->_resolved_attrs->{collapse}}) {
    my $row = $rs->next;
    carp "Query returned more than one row" if $rs->next;
    return $row;
  }
  else {
    return $rs->single;
  }
}

# _add_alias
#
# Add the specified alias to the specified query hash. A copy is made so the
# original query is not modified.

sub _add_alias {
  my ($self, $query, $alias) = @_;

  my %aliased = %$query;
  foreach my $col (grep { ! m/\./ } keys %aliased) {
    $aliased{"$alias.$col"} = delete $aliased{$col};
  }

  return \%aliased;
}

# _unique_queries
#
# Build a list of queries which satisfy unique constraints.

sub _unique_queries {
  my ($self, $query, $attrs) = @_;

  my @constraint_names = exists $attrs->{key}
    ? ($attrs->{key})
    : $self->result_source->unique_constraint_names;

  my $where = $self->_collapse_cond($self->{attrs}{where} || {});
  my $num_where = scalar keys %$where;

  my (@unique_queries, %seen_column_combinations);
  foreach my $name (@constraint_names) {
    my @constraint_cols = $self->result_source->unique_constraint_columns($name);

    my $constraint_sig = join "\x00", sort @constraint_cols;
    next if $seen_column_combinations{$constraint_sig}++;

    my $unique_query = $self->_build_unique_query($query, \@constraint_cols);

    my $num_cols = scalar @constraint_cols;
    my $num_query = scalar keys %$unique_query;

    my $total = $num_query + $num_where;
    if ($num_query && ($num_query == $num_cols || $total == $num_cols)) {
      # The query is either unique on its own or is unique in combination with
      # the existing where clause
      push @unique_queries, $unique_query;
    }
  }

  return @unique_queries;
}

# _build_unique_query
#
# Constrain the specified query hash based on the specified column names.

sub _build_unique_query {
  my ($self, $query, $unique_cols) = @_;

  return {
    map  { $_ => $query->{$_} }
    grep { exists $query->{$_} }
      @$unique_cols
  };
}

=head2 search_related

=over 4

=item Arguments: $rel, $cond, \%attrs?

=item Return Value: $new_resultset

=back

  $new_rs = $cd_rs->search_related('artist', {
    name => 'Emo-R-Us',
  });

Searches the specified relationship, optionally specifying a condition and
attributes for matching records. See L</ATTRIBUTES> for more information.

=cut

sub search_related {
  return shift->related_resultset(shift)->search(@_);
}

=head2 search_related_rs

This method works exactly the same as search_related, except that
it guarantees a restultset, even in list context.

=cut

sub search_related_rs {
  return shift->related_resultset(shift)->search_rs(@_);
}

=head2 cursor

=over 4

=item Arguments: none

=item Return Value: $cursor

=back

Returns a storage-driven cursor to the given resultset. See
L<DBIx::Class::Cursor> for more information.

=cut

sub cursor {
  my ($self) = @_;

  my $attrs = $self->_resolved_attrs_copy;

  return $self->{cursor}
    ||= $self->result_source->storage->select($attrs->{from}, $attrs->{select},
          $attrs->{where},$attrs);
}

=head2 single

=over 4

=item Arguments: $cond?

=item Return Value: $row_object?

=back

  my $cd = $schema->resultset('CD')->single({ year => 2001 });

Inflates the first result without creating a cursor if the resultset has
any records in it; if not returns nothing. Used by L</find> as a lean version of
L</search>.

While this method can take an optional search condition (just like L</search>)
being a fast-code-path it does not recognize search attributes. If you need to
add extra joins or similar, call L</search> and then chain-call L</single> on the
L<DBIx::Class::ResultSet> returned.

=over

=item B<Note>

As of 0.08100, this method enforces the assumption that the preceeding
query returns only one row. If more than one row is returned, you will receive
a warning:

  Query returned more than one row

In this case, you should be using L</next> or L</find> instead, or if you really
know what you are doing, use the L</rows> attribute to explicitly limit the size
of the resultset.

This method will also throw an exception if it is called on a resultset prefetching
has_many, as such a prefetch implies fetching multiple rows from the database in
order to assemble the resulting object.

=back

=cut

sub single {
  my ($self, $where) = @_;
  if(@_ > 2) {
      $self->throw_exception('single() only takes search conditions, no attributes. You want ->search( $cond, $attrs )->single()');
  }

  my $attrs = $self->_resolved_attrs_copy;

  if (keys %{$attrs->{collapse}}) {
    $self->throw_exception(
      'single() can not be used on resultsets prefetching has_many. Use find( \%cond ) or next() instead'
    );
  }

  if ($where) {
    if (defined $attrs->{where}) {
      $attrs->{where} = {
        '-and' =>
            [ map { ref $_ eq 'ARRAY' ? [ -or => $_ ] : $_ }
               $where, delete $attrs->{where} ]
      };
    } else {
      $attrs->{where} = $where;
    }
  }

#  XXX: Disabled since it doesn't infer uniqueness in all cases
#  unless ($self->_is_unique_query($attrs->{where})) {
#    carp "Query not guaranteed to return a single row"
#      . "; please declare your unique constraints or use search instead";
#  }

  my @data = $self->result_source->storage->select_single(
    $attrs->{from}, $attrs->{select},
    $attrs->{where}, $attrs
  );

  return (@data ? ($self->_construct_object(@data))[0] : undef);
}


# _is_unique_query
#
# Try to determine if the specified query is guaranteed to be unique, based on
# the declared unique constraints.

sub _is_unique_query {
  my ($self, $query) = @_;

  my $collapsed = $self->_collapse_query($query);
  my $alias = $self->{attrs}{alias};

  foreach my $name ($self->result_source->unique_constraint_names) {
    my @unique_cols = map {
      "$alias.$_"
    } $self->result_source->unique_constraint_columns($name);

    # Count the values for each unique column
    my %seen = map { $_ => 0 } @unique_cols;

    foreach my $key (keys %$collapsed) {
      my $aliased = $key =~ /\./ ? $key : "$alias.$key";
      next unless exists $seen{$aliased};  # Additional constraints are okay
      $seen{$aliased} = scalar keys %{ $collapsed->{$key} };
    }

    # If we get 0 or more than 1 value for a column, it's not necessarily unique
    return 1 unless grep { $_ != 1 } values %seen;
  }

  return 0;
}

# _collapse_query
#
# Recursively collapse the query, accumulating values for each column.

sub _collapse_query {
  my ($self, $query, $collapsed) = @_;

  $collapsed ||= {};

  if (ref $query eq 'ARRAY') {
    foreach my $subquery (@$query) {
      next unless ref $subquery;  # -or
      $collapsed = $self->_collapse_query($subquery, $collapsed);
    }
  }
  elsif (ref $query eq 'HASH') {
    if (keys %$query and (keys %$query)[0] eq '-and') {
      foreach my $subquery (@{$query->{-and}}) {
        $collapsed = $self->_collapse_query($subquery, $collapsed);
      }
    }
    else {
      foreach my $col (keys %$query) {
        my $value = $query->{$col};
        $collapsed->{$col}{$value}++;
      }
    }
  }

  return $collapsed;
}

=head2 get_column

=over 4

=item Arguments: $cond?

=item Return Value: $resultsetcolumn

=back

  my $max_length = $rs->get_column('length')->max;

Returns a L<DBIx::Class::ResultSetColumn> instance for a column of the ResultSet.

=cut

sub get_column {
  my ($self, $column) = @_;
  my $new = DBIx::Class::ResultSetColumn->new($self, $column);
  return $new;
}

=head2 search_like

=over 4

=item Arguments: $cond, \%attrs?

=item Return Value: $resultset (scalar context), @row_objs (list context)

=back

  # WHERE title LIKE '%blue%'
  $cd_rs = $rs->search_like({ title => '%blue%'});

Performs a search, but uses C<LIKE> instead of C<=> as the condition. Note
that this is simply a convenience method retained for ex Class::DBI users.
You most likely want to use L</search> with specific operators.

For more information, see L<DBIx::Class::Manual::Cookbook>.

This method is deprecated and will be removed in 0.09. Use L</search()>
instead. An example conversion is:

  ->search_like({ foo => 'bar' });

  # Becomes

  ->search({ foo => { like => 'bar' } });

=cut

sub search_like {
  my $class = shift;
  carp (
    'search_like() is deprecated and will be removed in DBIC version 0.09.'
   .' Instead use ->search({ x => { -like => "y%" } })'
   .' (note the outer pair of {}s - they are important!)'
  );
  my $attrs = (@_ > 1 && ref $_[$#_] eq 'HASH' ? pop(@_) : {});
  my $query = ref $_[0] eq 'HASH' ? { %{shift()} }: {@_};
  $query->{$_} = { 'like' => $query->{$_} } for keys %$query;
  return $class->search($query, { %$attrs });
}

=head2 slice

=over 4

=item Arguments: $first, $last

=item Return Value: $resultset (scalar context), @row_objs (list context)

=back

Returns a resultset or object list representing a subset of elements from the
resultset slice is called on. Indexes are from 0, i.e., to get the first
three records, call:

  my ($one, $two, $three) = $rs->slice(0, 2);

=cut

sub slice {
  my ($self, $min, $max) = @_;
  my $attrs = {}; # = { %{ $self->{attrs} || {} } };
  $attrs->{offset} = $self->{attrs}{offset} || 0;
  $attrs->{offset} += $min;
  $attrs->{rows} = ($max ? ($max - $min + 1) : 1);
  return $self->search(undef(), $attrs);
  #my $slice = (ref $self)->new($self->result_source, $attrs);
  #return (wantarray ? $slice->all : $slice);
}

=head2 next

=over 4

=item Arguments: none

=item Return Value: $result?

=back

Returns the next element in the resultset (C<undef> is there is none).

Can be used to efficiently iterate over records in the resultset:

  my $rs = $schema->resultset('CD')->search;
  while (my $cd = $rs->next) {
    print $cd->title;
  }

Note that you need to store the resultset object, and call C<next> on it.
Calling C<< resultset('Table')->next >> repeatedly will always return the
first record from the resultset.

=cut

sub next {
  my ($self) = @_;
  if (my $cache = $self->get_cache) {
    $self->{all_cache_position} ||= 0;
    return $cache->[$self->{all_cache_position}++];
  }
  if ($self->{attrs}{cache}) {
    $self->{all_cache_position} = 1;
    return ($self->all)[0];
  }
  if ($self->{stashed_objects}) {
    my $obj = shift(@{$self->{stashed_objects}});
    delete $self->{stashed_objects} unless @{$self->{stashed_objects}};
    return $obj;
  }
  my @row = (
    exists $self->{stashed_row}
      ? @{delete $self->{stashed_row}}
      : $self->cursor->next
  );
  return undef unless (@row);
  my ($row, @more) = $self->_construct_object(@row);
  $self->{stashed_objects} = \@more if @more;
  return $row;
}

sub _construct_object {
  my ($self, @row) = @_;

  my $info = $self->_collapse_result($self->{_attrs}{as}, \@row)
    or return ();
  my @new = $self->result_class->inflate_result($self->result_source, @$info);
  @new = $self->{_attrs}{record_filter}->(@new)
    if exists $self->{_attrs}{record_filter};
  return @new;
}

sub _collapse_result {
  my ($self, $as_proto, $row) = @_;

  # if the first row that ever came in is totally empty - this means we got
  # hit by a smooth^Wempty left-joined resultset. Just noop in that case
  # instead of producing a {}
  #
  my $has_def;
  for (@$row) {
    if (defined $_) {
      $has_def++;
      last;
    }
  }
  return undef unless $has_def;

  my @copy = @$row;

  # 'foo'         => [ undef, 'foo' ]
  # 'foo.bar'     => [ 'foo', 'bar' ]
  # 'foo.bar.baz' => [ 'foo.bar', 'baz' ]

  my @construct_as = map { [ (/^(?:(.*)\.)?([^.]+)$/) ] } @$as_proto;

  my %collapse = %{$self->{_attrs}{collapse}||{}};

  my @pri_index;

  # if we're doing collapsing (has_many prefetch) we need to grab records
  # until the PK changes, so fill @pri_index. if not, we leave it empty so
  # we know we don't have to bother.

  # the reason for not using the collapse stuff directly is because if you
  # had for e.g. two artists in a row with no cds, the collapse info for
  # both would be NULL (undef) so you'd lose the second artist

  # store just the index so we can check the array positions from the row
  # without having to contruct the full hash

  if (keys %collapse) {
    my %pri = map { ($_ => 1) } $self->result_source->primary_columns;
    foreach my $i (0 .. $#construct_as) {
      next if defined($construct_as[$i][0]); # only self table
      if (delete $pri{$construct_as[$i][1]}) {
        push(@pri_index, $i);
      }
      last unless keys %pri; # short circuit (Johnny Five Is Alive!)
    }
  }

  # no need to do an if, it'll be empty if @pri_index is empty anyway

  my %pri_vals = map { ($_ => $copy[$_]) } @pri_index;

  my @const_rows;

  do { # no need to check anything at the front, we always want the first row

    my %const;

    foreach my $this_as (@construct_as) {
      $const{$this_as->[0]||''}{$this_as->[1]} = shift(@copy);
    }

    push(@const_rows, \%const);

  } until ( # no pri_index => no collapse => drop straight out
      !@pri_index
    or
      do { # get another row, stash it, drop out if different PK

        @copy = $self->cursor->next;
        $self->{stashed_row} = \@copy;

        # last thing in do block, counts as true if anything doesn't match

        # check xor defined first for NULL vs. NOT NULL then if one is
        # defined the other must be so check string equality

        grep {
          (defined $pri_vals{$_} ^ defined $copy[$_])
          || (defined $pri_vals{$_} && ($pri_vals{$_} ne $copy[$_]))
        } @pri_index;
      }
  );

  my $alias = $self->{attrs}{alias};
  my $info = [];

  my %collapse_pos;

  my @const_keys;

  foreach my $const (@const_rows) {
    scalar @const_keys or do {
      @const_keys = sort { length($a) <=> length($b) } keys %$const;
    };
    foreach my $key (@const_keys) {
      if (length $key) {
        my $target = $info;
        my @parts = split(/\./, $key);
        my $cur = '';
        my $data = $const->{$key};
        foreach my $p (@parts) {
          $target = $target->[1]->{$p} ||= [];
          $cur .= ".${p}";
          if ($cur eq ".${key}" && (my @ckey = @{$collapse{$cur}||[]})) {
            # collapsing at this point and on final part
            my $pos = $collapse_pos{$cur};
            CK: foreach my $ck (@ckey) {
              if (!defined $pos->{$ck} || $pos->{$ck} ne $data->{$ck}) {
                $collapse_pos{$cur} = $data;
                delete @collapse_pos{ # clear all positioning for sub-entries
                  grep { m/^\Q${cur}.\E/ } keys %collapse_pos
                };
                push(@$target, []);
                last CK;
              }
            }
          }
          if (exists $collapse{$cur}) {
            $target = $target->[-1];
          }
        }
        $target->[0] = $data;
      } else {
        $info->[0] = $const->{$key};
      }
    }
  }

  return $info;
}

=head2 result_source

=over 4

=item Arguments: $result_source?

=item Return Value: $result_source

=back

An accessor for the primary ResultSource object from which this ResultSet
is derived.

=head2 result_class

=over 4

=item Arguments: $result_class?

=item Return Value: $result_class

=back

An accessor for the class to use when creating row objects. Defaults to
C<< result_source->result_class >> - which in most cases is the name of the
L<"table"|DBIx::Class::Manual::Glossary/"ResultSource"> class.

Note that changing the result_class will also remove any components
that were originally loaded in the source class via
L<DBIx::Class::ResultSource/load_components>. Any overloaded methods
in the original source class will not run.

=cut

sub result_class {
  my ($self, $result_class) = @_;
  if ($result_class) {
    $self->ensure_class_loaded($result_class);
    $self->_result_class($result_class);
  }
  $self->_result_class;
}

=head2 count

=over 4

=item Arguments: $cond, \%attrs??

=item Return Value: $count

=back

Performs an SQL C<COUNT> with the same query as the resultset was built
with to find the number of elements. Passing arguments is equivalent to
C<< $rs->search ($cond, \%attrs)->count >>

=cut

sub count {
  my $self = shift;
  return $self->search(@_)->count if @_ and defined $_[0];
  return scalar @{ $self->get_cache } if $self->get_cache;

  my $attrs = $self->_resolved_attrs_copy;

  # this is a little optimization - it is faster to do the limit
  # adjustments in software, instead of a subquery
  my $rows = delete $attrs->{rows};
  my $offset = delete $attrs->{offset};

  my $crs;
  if ($self->_has_resolved_attr (qw/collapse group_by/)) {
    $crs = $self->_count_subq_rs ($attrs);
  }
  else {
    $crs = $self->_count_rs ($attrs);
  }
  my $count = $crs->next;

  $count -= $offset if $offset;
  $count = $rows if $rows and $rows < $count;
  $count = 0 if ($count < 0);

  return $count;
}

=head2 count_rs

=over 4

=item Arguments: $cond, \%attrs??

=item Return Value: $count_rs

=back

Same as L</count> but returns a L<DBIx::Class::ResultSetColumn> object.
This can be very handy for subqueries:

  ->search( { amount => $some_rs->count_rs->as_query } )

As with regular resultsets the SQL query will be executed only after
the resultset is accessed via L</next> or L</all>. That would return
the same single value obtainable via L</count>.

=cut

sub count_rs {
  my $self = shift;
  return $self->search(@_)->count_rs if @_;

  # this may look like a lack of abstraction (count() does about the same)
  # but in fact an _rs *must* use a subquery for the limits, as the
  # software based limiting can not be ported if this $rs is to be used
  # in a subquery itself (i.e. ->as_query)
  if ($self->_has_resolved_attr (qw/collapse group_by offset rows/)) {
    return $self->_count_subq_rs;
  }
  else {
    return $self->_count_rs;
  }
}

#
# returns a ResultSetColumn object tied to the count query
#
sub _count_rs {
  my ($self, $attrs) = @_;

  my $rsrc = $self->result_source;
  $attrs ||= $self->_resolved_attrs;

  my $tmp_attrs = { %$attrs };

  # take off any limits, record_filter is cdbi, and no point of ordering a count 
  delete $tmp_attrs->{$_} for (qw/select as rows offset order_by record_filter/);

  # overwrite the selector (supplied by the storage)
  $tmp_attrs->{select} = $rsrc->storage->_count_select ($rsrc, $tmp_attrs);
  $tmp_attrs->{as} = 'count';

  # read the comment on top of the actual function to see what this does
  $tmp_attrs->{from} = $self->_switch_to_inner_join_if_needed (
    $tmp_attrs->{from}, $tmp_attrs->{alias}
  );

  my $tmp_rs = $rsrc->resultset_class->new($rsrc, $tmp_attrs)->get_column ('count');

  return $tmp_rs;
}

#
# same as above but uses a subquery
#
sub _count_subq_rs {
  my ($self, $attrs) = @_;

  my $rsrc = $self->result_source;
  $attrs ||= $self->_resolved_attrs_copy;

  my $sub_attrs = { %$attrs };

  # extra selectors do not go in the subquery and there is no point of ordering it
  delete $sub_attrs->{$_} for qw/collapse select _prefetch_select as order_by/;

  # if we prefetch, we group_by primary keys only as this is what we would get out
  # of the rs via ->next/->all. We DO WANT to clobber old group_by regardless
  if ( keys %{$attrs->{collapse}} ) {
    $sub_attrs->{group_by} = [ map { "$attrs->{alias}.$_" } ($rsrc->primary_columns) ]
  }

  $sub_attrs->{select} = $rsrc->storage->_subq_count_select ($rsrc, $sub_attrs);

  # read the comment on top of the actual function to see what this does
  $sub_attrs->{from} = $self->_switch_to_inner_join_if_needed (
    $sub_attrs->{from}, $sub_attrs->{alias}
  );

  # this is so that ordering can be thrown away in things like Top limit
  $sub_attrs->{-for_count_only} = 1;

  my $sub_rs = $rsrc->resultset_class->new ($rsrc, $sub_attrs);

  $attrs->{from} = [{
    -alias => 'count_subq',
    -source_handle => $rsrc->handle,
    count_subq => $sub_rs->as_query,
  }];

  # the subquery replaces this
  delete $attrs->{$_} for qw/where bind collapse group_by having having_bind rows offset/;

  return $self->_count_rs ($attrs);
}


# The DBIC relationship chaining implementation is pretty simple - every
# new related_relationship is pushed onto the {from} stack, and the {select}
# window simply slides further in. This means that when we count somewhere
# in the middle, we got to make sure that everything in the join chain is an
# actual inner join, otherwise the count will come back with unpredictable
# results (a resultset may be generated with _some_ rows regardless of if
# the relation which the $rs currently selects has rows or not). E.g.
# $artist_rs->cds->count - normally generates:
# SELECT COUNT( * ) FROM artist me LEFT JOIN cd cds ON cds.artist = me.artistid
# which actually returns the number of artists * (number of cds || 1)
#
# So what we do here is crawl {from}, determine if the current alias is at
# the top of the stack, and if not - make sure the chain is inner-joined down
# to the root.
#
sub _switch_to_inner_join_if_needed {
  my ($self, $from, $alias) = @_;

  # subqueries and other oddness is naturally not supported
  return $from if (
    ref $from ne 'ARRAY'
      ||
    @$from <= 1
      ||
    ref $from->[0] ne 'HASH'
      ||
    ! $from->[0]{-alias}
      ||
    $from->[0]{-alias} eq $alias
  );

  my $switch_branch;
  JOINSCAN:
  for my $j (@{$from}[1 .. $#$from]) {
    if ($j->[0]{-alias} eq $alias) {
      $switch_branch = $j->[0]{-join_path};
      last JOINSCAN;
    }
  }

  # something else went wrong
  return $from unless $switch_branch;

  # So it looks like we will have to switch some stuff around.
  # local() is useless here as we will be leaving the scope
  # anyway, and deep cloning is just too fucking expensive
  # So replace the inner hashref manually
  my @new_from = ($from->[0]);
  my $sw_idx = { map { $_ => 1 } @$switch_branch };

  for my $j (@{$from}[1 .. $#$from]) {
    my $jalias = $j->[0]{-alias};

    if ($sw_idx->{$jalias}) {
      my %attrs = %{$j->[0]};
      delete $attrs{-join_type};
      push @new_from, [
        \%attrs,
        @{$j}[ 1 .. $#$j ],
      ];
    }
    else {
      push @new_from, $j;
    }
  }

  return \@new_from;
}


sub _bool {
  return 1;
}

=head2 count_literal

=over 4

=item Arguments: $sql_fragment, @bind_values

=item Return Value: $count

=back

Counts the results in a literal query. Equivalent to calling L</search_literal>
with the passed arguments, then L</count>.

=cut

sub count_literal { shift->search_literal(@_)->count; }

=head2 all

=over 4

=item Arguments: none

=item Return Value: @objects

=back

Returns all elements in the resultset. Called implicitly if the resultset
is returned in list context.

=cut

sub all {
  my $self = shift;
  if(@_) {
      $self->throw_exception("all() doesn't take any arguments, you probably wanted ->search(...)->all()");
  }

  return @{ $self->get_cache } if $self->get_cache;

  my @obj;

  if (keys %{$self->_resolved_attrs->{collapse}}) {
    # Using $self->cursor->all is really just an optimisation.
    # If we're collapsing has_many prefetches it probably makes
    # very little difference, and this is cleaner than hacking
    # _construct_object to survive the approach
    $self->cursor->reset;
    my @row = $self->cursor->next;
    while (@row) {
      push(@obj, $self->_construct_object(@row));
      @row = (exists $self->{stashed_row}
               ? @{delete $self->{stashed_row}}
               : $self->cursor->next);
    }
  } else {
    @obj = map { $self->_construct_object(@$_) } $self->cursor->all;
  }

  $self->set_cache(\@obj) if $self->{attrs}{cache};

  return @obj;
}

=head2 reset

=over 4

=item Arguments: none

=item Return Value: $self

=back

Resets the resultset's cursor, so you can iterate through the elements again.
Implicitly resets the storage cursor, so a subsequent L</next> will trigger
another query.

=cut

sub reset {
  my ($self) = @_;
  delete $self->{_attrs} if exists $self->{_attrs};
  $self->{all_cache_position} = 0;
  $self->cursor->reset;
  return $self;
}

=head2 first

=over 4

=item Arguments: none

=item Return Value: $object?

=back

Resets the resultset and returns an object for the first result (if the
resultset returns anything).

=cut

sub first {
  return $_[0]->reset->next;
}


# _rs_update_delete
#
# Determines whether and what type of subquery is required for the $rs operation.
# If grouping is necessary either supplies its own, or verifies the current one
# After all is done delegates to the proper storage method.

sub _rs_update_delete {
  my ($self, $op, $values) = @_;

  my $rsrc = $self->result_source;

  my $needs_group_by_subq = $self->_has_resolved_attr (qw/collapse group_by -join/);
  my $needs_subq = $self->_has_resolved_attr (qw/row offset/);

  if ($needs_group_by_subq or $needs_subq) {

    # make a new $rs selecting only the PKs (that's all we really need)
    my $attrs = $self->_resolved_attrs_copy;

    delete $attrs->{$_} for qw/collapse select as/;
    $attrs->{columns} = [ map { "$attrs->{alias}.$_" } ($self->result_source->primary_columns) ];

    if ($needs_group_by_subq) {
      # make sure no group_by was supplied, or if there is one - make sure it matches
      # the columns compiled above perfectly. Anything else can not be sanely executed
      # on most databases so croak right then and there

      if (my $g = $attrs->{group_by}) {
        my @current_group_by = map
          { $_ =~ /\./ ? $_ : "$attrs->{alias}.$_" }
          @$g
        ;

        if (
          join ("\x00", sort @current_group_by)
            ne
          join ("\x00", sort @{$attrs->{columns}} )
        ) {
          $self->throw_exception (
            "You have just attempted a $op operation on a resultset which does group_by"
            . ' on columns other than the primary keys, while DBIC internally needs to retrieve'
            . ' the primary keys in a subselect. All sane RDBMS engines do not support this'
            . ' kind of queries. Please retry the operation with a modified group_by or'
            . ' without using one at all.'
          );
        }
      }
      else {
        $attrs->{group_by} = $attrs->{columns};
      }
    }

    my $subrs = (ref $self)->new($rsrc, $attrs);

    return $self->result_source->storage->_subq_update_delete($subrs, $op, $values);
  }
  else {
    return $rsrc->storage->$op(
      $rsrc,
      $op eq 'update' ? $values : (),
      $self->_cond_for_update_delete,
    );
  }
}


# _cond_for_update_delete
#
# update/delete require the condition to be modified to handle
# the differing SQL syntax available.  This transforms the $self->{cond}
# appropriately, returning the new condition.

sub _cond_for_update_delete {
  my ($self, $full_cond) = @_;
  my $cond = {};

  $full_cond ||= $self->{cond};
  # No-op. No condition, we're updating/deleting everything
  return $cond unless ref $full_cond;

  if (ref $full_cond eq 'ARRAY') {
    $cond = [
      map {
        my %hash;
        foreach my $key (keys %{$_}) {
          $key =~ /([^.]+)$/;
          $hash{$1} = $_->{$key};
        }
        \%hash;
      } @{$full_cond}
    ];
  }
  elsif (ref $full_cond eq 'HASH') {
    if ((keys %{$full_cond})[0] eq '-and') {
      $cond->{-and} = [];
      my @cond = @{$full_cond->{-and}};
       for (my $i = 0; $i < @cond; $i++) {
        my $entry = $cond[$i];
        my $hash;
        if (ref $entry eq 'HASH') {
          $hash = $self->_cond_for_update_delete($entry);
        }
        else {
          $entry =~ /([^.]+)$/;
          $hash->{$1} = $cond[++$i];
        }
        push @{$cond->{-and}}, $hash;
      }
    }
    else {
      foreach my $key (keys %{$full_cond}) {
        $key =~ /([^.]+)$/;
        $cond->{$1} = $full_cond->{$key};
      }
    }
  }
  else {
    $self->throw_exception("Can't update/delete on resultset with condition unless hash or array");
  }

  return $cond;
}


=head2 update

=over 4

=item Arguments: \%values

=item Return Value: $storage_rv

=back

Sets the specified columns in the resultset to the supplied values in a
single query. Return value will be true if the update succeeded or false
if no records were updated; exact type of success value is storage-dependent.

=cut

sub update {
  my ($self, $values) = @_;
  $self->throw_exception('Values for update must be a hash')
    unless ref $values eq 'HASH';

  return $self->_rs_update_delete ('update', $values);
}

=head2 update_all

=over 4

=item Arguments: \%values

=item Return Value: 1

=back

Fetches all objects and updates them one at a time. Note that C<update_all>
will run DBIC cascade triggers, while L</update> will not.

=cut

sub update_all {
  my ($self, $values) = @_;
  $self->throw_exception('Values for update_all must be a hash')
    unless ref $values eq 'HASH';
  foreach my $obj ($self->all) {
    $obj->set_columns($values)->update;
  }
  return 1;
}

=head2 delete

=over 4

=item Arguments: none

=item Return Value: $storage_rv

=back

Deletes the contents of the resultset from its result source. Note that this
will not run DBIC cascade triggers. See L</delete_all> if you need triggers
to run. See also L<DBIx::Class::Row/delete>.

Return value will be the amount of rows deleted; exact type of return value
is storage-dependent.

=cut

sub delete {
  my $self = shift;
  $self->throw_exception('delete does not accept any arguments')
    if @_;

  return $self->_rs_update_delete ('delete');
}

=head2 delete_all

=over 4

=item Arguments: none

=item Return Value: 1

=back

Fetches all objects and deletes them one at a time. Note that C<delete_all>
will run DBIC cascade triggers, while L</delete> will not.

=cut

sub delete_all {
  my $self = shift;
  $self->throw_exception('delete_all does not accept any arguments')
    if @_;

  $_->delete for $self->all;
  return 1;
}

=head2 populate

=over 4

=item Arguments: \@data;

=back

Accepts either an arrayref of hashrefs or alternatively an arrayref of arrayrefs.
For the arrayref of hashrefs style each hashref should be a structure suitable
forsubmitting to a $resultset->create(...) method.

In void context, C<insert_bulk> in L<DBIx::Class::Storage::DBI> is used
to insert the data, as this is a faster method.

Otherwise, each set of data is inserted into the database using
L<DBIx::Class::ResultSet/create>, and the resulting objects are
accumulated into an array. The array itself, or an array reference
is returned depending on scalar or list context.

Example:  Assuming an Artist Class that has many CDs Classes relating:

  my $Artist_rs = $schema->resultset("Artist");

  ## Void Context Example
  $Artist_rs->populate([
     { artistid => 4, name => 'Manufactured Crap', cds => [
        { title => 'My First CD', year => 2006 },
        { title => 'Yet More Tweeny-Pop crap', year => 2007 },
      ],
     },
     { artistid => 5, name => 'Angsty-Whiny Girl', cds => [
        { title => 'My parents sold me to a record company' ,year => 2005 },
        { title => 'Why Am I So Ugly?', year => 2006 },
        { title => 'I Got Surgery and am now Popular', year => 2007 }
      ],
     },
  ]);

  ## Array Context Example
  my ($ArtistOne, $ArtistTwo, $ArtistThree) = $Artist_rs->populate([
    { name => "Artist One"},
    { name => "Artist Two"},
    { name => "Artist Three", cds=> [
    { title => "First CD", year => 2007},
    { title => "Second CD", year => 2008},
  ]}
  ]);

  print $ArtistOne->name; ## response is 'Artist One'
  print $ArtistThree->cds->count ## reponse is '2'

For the arrayref of arrayrefs style,  the first element should be a list of the
fieldsnames to which the remaining elements are rows being inserted.  For
example:

  $Arstist_rs->populate([
    [qw/artistid name/],
    [100, 'A Formally Unknown Singer'],
    [101, 'A singer that jumped the shark two albums ago'],
    [102, 'An actually cool singer.'],
  ]);

Please note an important effect on your data when choosing between void and
wantarray context. Since void context goes straight to C<insert_bulk> in
L<DBIx::Class::Storage::DBI> this will skip any component that is overriding
C<insert>.  So if you are using something like L<DBIx-Class-UUIDColumns> to
create primary keys for you, you will find that your PKs are empty.  In this
case you will have to use the wantarray context in order to create those
values.

=cut

sub populate {
  my $self = shift @_;
  my $data = ref $_[0][0] eq 'HASH'
    ? $_[0] : ref $_[0][0] eq 'ARRAY' ? $self->_normalize_populate_args($_[0]) :
    $self->throw_exception('Populate expects an arrayref of hashes or arrayref of arrayrefs');

  if(defined wantarray) {
    my @created;
    foreach my $item (@$data) {
      push(@created, $self->create($item));
    }
    return wantarray ? @created : \@created;
  } else {
    my ($first, @rest) = @$data;

    my @names = grep {!ref $first->{$_}} keys %$first;
    my @rels = grep { $self->result_source->has_relationship($_) } keys %$first;
    my @pks = $self->result_source->primary_columns;

    ## do the belongs_to relationships
    foreach my $index (0..$#$data) {

      # delegate to create() for any dataset without primary keys with specified relationships
      if (grep { !defined $data->[$index]->{$_} } @pks ) {
        for my $r (@rels) {
          if (grep { ref $data->[$index]{$r} eq $_ } qw/HASH ARRAY/) {  # a related set must be a HASH or AoH
            my @ret = $self->populate($data);
            return;
          }
        }
      }

      foreach my $rel (@rels) {
        next unless ref $data->[$index]->{$rel} eq "HASH";
        my $result = $self->related_resultset($rel)->create($data->[$index]->{$rel});
        my ($reverse) = keys %{$self->result_source->reverse_relationship_info($rel)};
        my $related = $result->result_source->_resolve_condition(
          $result->result_source->relationship_info($reverse)->{cond},
          $self,
          $result,
        );

        delete $data->[$index]->{$rel};
        $data->[$index] = {%{$data->[$index]}, %$related};

        push @names, keys %$related if $index == 0;
      }
    }

    ## do bulk insert on current row
    my @values = map { [ @$_{@names} ] } @$data;

    $self->result_source->storage->insert_bulk(
      $self->result_source,
      \@names,
      \@values,
    );

    ## do the has_many relationships
    foreach my $item (@$data) {

      foreach my $rel (@rels) {
        next unless $item->{$rel} && ref $item->{$rel} eq "ARRAY";

        my $parent = $self->find(map {{$_=>$item->{$_}} } @pks)
     || $self->throw_exception('Cannot find the relating object.');

        my $child = $parent->$rel;

        my $related = $child->result_source->_resolve_condition(
          $parent->result_source->relationship_info($rel)->{cond},
          $child,
          $parent,
        );

        my @rows_to_add = ref $item->{$rel} eq 'ARRAY' ? @{$item->{$rel}} : ($item->{$rel});
        my @populate = map { {%$_, %$related} } @rows_to_add;

        $child->populate( \@populate );
      }
    }
  }
}

=head2 _normalize_populate_args ($args)

Private method used by L</populate> to normalize its incoming arguments.  Factored
out in case you want to subclass and accept new argument structures to the
L</populate> method.

=cut

sub _normalize_populate_args {
  my ($self, $data) = @_;
  my @names = @{shift(@$data)};
  my @results_to_create;
  foreach my $datum (@$data) {
    my %result_to_create;
    foreach my $index (0..$#names) {
      $result_to_create{$names[$index]} = $$datum[$index];
    }
    push @results_to_create, \%result_to_create;
  }
  return \@results_to_create;
}

=head2 pager

=over 4

=item Arguments: none

=item Return Value: $pager

=back

Return Value a L<Data::Page> object for the current resultset. Only makes
sense for queries with a C<page> attribute.

To get the full count of entries for a paged resultset, call
C<total_entries> on the L<Data::Page> object.

=cut

sub pager {
  my ($self) = @_;

  return $self->{pager} if $self->{pager};

  my $attrs = $self->{attrs};
  $self->throw_exception("Can't create pager for non-paged rs")
    unless $self->{attrs}{page};
  $attrs->{rows} ||= 10;

  # throw away the paging flags and re-run the count (possibly
  # with a subselect) to get the real total count
  my $count_attrs = { %$attrs };
  delete $count_attrs->{$_} for qw/rows offset page pager/;
  my $total_count = (ref $self)->new($self->result_source, $count_attrs)->count;

  return $self->{pager} = Data::Page->new(
    $total_count,
    $attrs->{rows},
    $self->{attrs}{page}
  );
}

=head2 page

=over 4

=item Arguments: $page_number

=item Return Value: $rs

=back

Returns a resultset for the $page_number page of the resultset on which page
is called, where each page contains a number of rows equal to the 'rows'
attribute set on the resultset (10 by default).

=cut

sub page {
  my ($self, $page) = @_;
  return (ref $self)->new($self->result_source, { %{$self->{attrs}}, page => $page });
}

=head2 new_result

=over 4

=item Arguments: \%vals

=item Return Value: $rowobject

=back

Creates a new row object in the resultset's result class and returns
it. The row is not inserted into the database at this point, call
L<DBIx::Class::Row/insert> to do that. Calling L<DBIx::Class::Row/in_storage>
will tell you whether the row object has been inserted or not.

Passes the hashref of input on to L<DBIx::Class::Row/new>.

=cut

sub new_result {
  my ($self, $values) = @_;
  $self->throw_exception( "new_result needs a hash" )
    unless (ref $values eq 'HASH');

  my %new;
  my $alias = $self->{attrs}{alias};

  if (
    defined $self->{cond}
    && $self->{cond} eq $DBIx::Class::ResultSource::UNRESOLVABLE_CONDITION
  ) {
    %new = %{ $self->{attrs}{related_objects} || {} };  # nothing might have been inserted yet
    $new{-from_resultset} = [ keys %new ] if keys %new;
  } else {
    $self->throw_exception(
      "Can't abstract implicit construct, condition not a hash"
    ) if ($self->{cond} && !(ref $self->{cond} eq 'HASH'));

    my $collapsed_cond = (
      $self->{cond}
        ? $self->_collapse_cond($self->{cond})
        : {}
    );

    # precendence must be given to passed values over values inherited from
    # the cond, so the order here is important.
    my %implied =  %{$self->_remove_alias($collapsed_cond, $alias)};
    while( my($col,$value) = each %implied ){
      if(ref($value) eq 'HASH' && keys(%$value) && (keys %$value)[0] eq '='){
        $new{$col} = $value->{'='};
        next;
      }
      $new{$col} = $value if $self->_is_deterministic_value($value);
    }
  }

  %new = (
    %new,
    %{ $self->_remove_alias($values, $alias) },
    -source_handle => $self->_source_handle,
    -result_source => $self->result_source, # DO NOT REMOVE THIS, REQUIRED
  );

  return $self->result_class->new(\%new);
}

# _is_deterministic_value
#
# Make an effor to strip non-deterministic values from the condition,
# to make sure new_result chokes less

sub _is_deterministic_value {
  my $self = shift;
  my $value = shift;
  my $ref_type = ref $value;
  return 1 if $ref_type eq '' || $ref_type eq 'SCALAR';
  return 1 if Scalar::Util::blessed($value);
  return 0;
}

# _has_resolved_attr
#
# determines if the resultset defines at least one
# of the attributes supplied
#
# used to determine if a subquery is neccessary
#
# supports some virtual attributes:
#   -join
#     This will scan for any joins being present on the resultset.
#     It is not a mere key-search but a deep inspection of {from}
#

sub _has_resolved_attr {
  my ($self, @attr_names) = @_;

  my $attrs = $self->_resolved_attrs;

  my %extra_checks;

  for my $n (@attr_names) {
    if (grep { $n eq $_ } (qw/-join/) ) {
      $extra_checks{$n}++;
      next;
    }

    my $attr =  $attrs->{$n};

    next if not defined $attr;

    if (ref $attr eq 'HASH') {
      return 1 if keys %$attr;
    }
    elsif (ref $attr eq 'ARRAY') {
      return 1 if @$attr;
    }
    else {
      return 1 if $attr;
    }
  }

  # a resolved join is expressed as a multi-level from
  return 1 if (
    $extra_checks{-join}
      and
    ref $attrs->{from} eq 'ARRAY'
      and
    @{$attrs->{from}} > 1
  );

  return 0;
}

# _collapse_cond
#
# Recursively collapse the condition.

sub _collapse_cond {
  my ($self, $cond, $collapsed) = @_;

  $collapsed ||= {};

  if (ref $cond eq 'ARRAY') {
    foreach my $subcond (@$cond) {
      next unless ref $subcond;  # -or
      $collapsed = $self->_collapse_cond($subcond, $collapsed);
    }
  }
  elsif (ref $cond eq 'HASH') {
    if (keys %$cond and (keys %$cond)[0] eq '-and') {
      foreach my $subcond (@{$cond->{-and}}) {
        $collapsed = $self->_collapse_cond($subcond, $collapsed);
      }
    }
    else {
      foreach my $col (keys %$cond) {
        my $value = $cond->{$col};
        $collapsed->{$col} = $value;
      }
    }
  }

  return $collapsed;
}

# _remove_alias
#
# Remove the specified alias from the specified query hash. A copy is made so
# the original query is not modified.

sub _remove_alias {
  my ($self, $query, $alias) = @_;

  my %orig = %{ $query || {} };
  my %unaliased;

  foreach my $key (keys %orig) {
    if ($key !~ /\./) {
      $unaliased{$key} = $orig{$key};
      next;
    }
    $unaliased{$1} = $orig{$key}
      if $key =~ m/^(?:\Q$alias\E\.)?([^.]+)$/;
  }

  return \%unaliased;
}

=head2 as_query (EXPERIMENTAL)

=over 4

=item Arguments: none

=item Return Value: \[ $sql, @bind ]

=back

Returns the SQL query and bind vars associated with the invocant.

This is generally used as the RHS for a subquery.

B<NOTE>: This feature is still experimental.

=cut

sub as_query {
  my $self = shift;

  my $attrs = $self->_resolved_attrs_copy;

  # For future use:
  #
  # in list ctx:
  # my ($sql, \@bind, \%dbi_bind_attrs) = _select_args_to_query (...)
  # $sql also has no wrapping parenthesis in list ctx
  #
  my $sqlbind = $self->result_source->storage
    ->_select_args_to_query ($attrs->{from}, $attrs->{select}, $attrs->{where}, $attrs);

  return $sqlbind;
}

=head2 find_or_new

=over 4

=item Arguments: \%vals, \%attrs?

=item Return Value: $rowobject

=back

  my $artist = $schema->resultset('Artist')->find_or_new(
    { artist => 'fred' }, { key => 'artists' });

  $cd->cd_to_producer->find_or_new({ producer => $producer },
                                   { key => 'primary });

Find an existing record from this resultset, based on its primary
key, or a unique constraint. If none exists, instantiate a new result
object and return it. The object will not be saved into your storage
until you call L<DBIx::Class::Row/insert> on it.

You most likely want this method when looking for existing rows using
a unique constraint that is not the primary key, or looking for
related rows.

If you want objects to be saved immediately, use L</find_or_create>
instead.

B<Note>: Take care when using C<find_or_new> with a table having
columns with default values that you intend to be automatically
supplied by the database (e.g. an auto_increment primary key column).
In normal usage, the value of such columns should NOT be included at
all in the call to C<find_or_new>, even when set to C<undef>.

=cut

sub find_or_new {
  my $self     = shift;
  my $attrs    = (@_ > 1 && ref $_[$#_] eq 'HASH' ? pop(@_) : {});
  my $hash     = ref $_[0] eq 'HASH' ? shift : {@_};
  if (keys %$hash and my $row = $self->find($hash, $attrs) ) {
    return $row;
  }
  return $self->new_result($hash);
}

=head2 create

=over 4

=item Arguments: \%vals

=item Return Value: a L<DBIx::Class::Row> $object

=back

Attempt to create a single new row or a row with multiple related rows
in the table represented by the resultset (and related tables). This
will not check for duplicate rows before inserting, use
L</find_or_create> to do that.

To create one row for this resultset, pass a hashref of key/value
pairs representing the columns of the table and the values you wish to
store. If the appropriate relationships are set up, foreign key fields
can also be passed an object representing the foreign row, and the
value will be set to its primary key.

To create related objects, pass a hashref of related-object column values
B<keyed on the relationship name>. If the relationship is of type C<multi>
(L<DBIx::Class::Relationship/has_many>) - pass an arrayref of hashrefs.
The process will correctly identify columns holding foreign keys, and will
transparrently populate them from the keys of the corresponding relation.
This can be applied recursively, and will work correctly for a structure
with an arbitrary depth and width, as long as the relationships actually
exists and the correct column data has been supplied.


Instead of hashrefs of plain related data (key/value pairs), you may
also pass new or inserted objects. New objects (not inserted yet, see
L</new>), will be inserted into their appropriate tables.

Effectively a shortcut for C<< ->new_result(\%vals)->insert >>.

Example of creating a new row.

  $person_rs->create({
    name=>"Some Person",
    email=>"somebody@someplace.com"
  });

Example of creating a new row and also creating rows in a related C<has_many>
or C<has_one> resultset.  Note Arrayref.

  $artist_rs->create(
     { artistid => 4, name => 'Manufactured Crap', cds => [
        { title => 'My First CD', year => 2006 },
        { title => 'Yet More Tweeny-Pop crap', year => 2007 },
      ],
     },
  );

Example of creating a new row and also creating a row in a related
C<belongs_to>resultset. Note Hashref.

  $cd_rs->create({
    title=>"Music for Silly Walks",
    year=>2000,
    artist => {
      name=>"Silly Musician",
    }
  });

=over

=item WARNING

When subclassing ResultSet never attempt to override this method. Since
it is a simple shortcut for C<< $self->new_result($attrs)->insert >>, a
lot of the internals simply never call it, so your override will be
bypassed more often than not. Override either L<new|DBIx::Class::Row/new>
or L<insert|DBIx::Class::Row/insert> depending on how early in the
L</create> process you need to intervene.

=back

=cut

sub create {
  my ($self, $attrs) = @_;
  $self->throw_exception( "create needs a hashref" )
    unless ref $attrs eq 'HASH';
  return $self->new_result($attrs)->insert;
}

=head2 find_or_create

=over 4

=item Arguments: \%vals, \%attrs?

=item Return Value: $rowobject

=back

  $cd->cd_to_producer->find_or_create({ producer => $producer },
                                      { key => 'primary' });

Tries to find a record based on its primary key or unique constraints; if none
is found, creates one and returns that instead.

  my $cd = $schema->resultset('CD')->find_or_create({
    cdid   => 5,
    artist => 'Massive Attack',
    title  => 'Mezzanine',
    year   => 2005,
  });

Also takes an optional C<key> attribute, to search by a specific key or unique
constraint. For example:

  my $cd = $schema->resultset('CD')->find_or_create(
    {
      artist => 'Massive Attack',
      title  => 'Mezzanine',
    },
    { key => 'cd_artist_title' }
  );

B<Note>: Because find_or_create() reads from the database and then
possibly inserts based on the result, this method is subject to a race
condition. Another process could create a record in the table after
the find has completed and before the create has started. To avoid
this problem, use find_or_create() inside a transaction.

B<Note>: Take care when using C<find_or_create> with a table having
columns with default values that you intend to be automatically
supplied by the database (e.g. an auto_increment primary key column).
In normal usage, the value of such columns should NOT be included at
all in the call to C<find_or_create>, even when set to C<undef>.

See also L</find> and L</update_or_create>. For information on how to declare
unique constraints, see L<DBIx::Class::ResultSource/add_unique_constraint>.

=cut

sub find_or_create {
  my $self     = shift;
  my $attrs    = (@_ > 1 && ref $_[$#_] eq 'HASH' ? pop(@_) : {});
  my $hash     = ref $_[0] eq 'HASH' ? shift : {@_};
  if (keys %$hash and my $row = $self->find($hash, $attrs) ) {
    return $row;
  }
  return $self->create($hash);
}

=head2 update_or_create

=over 4

=item Arguments: \%col_values, { key => $unique_constraint }?

=item Return Value: $rowobject

=back

  $resultset->update_or_create({ col => $val, ... });

First, searches for an existing row matching one of the unique constraints
(including the primary key) on the source of this resultset. If a row is
found, updates it with the other given column values. Otherwise, creates a new
row.

Takes an optional C<key> attribute to search on a specific unique constraint.
For example:

  # In your application
  my $cd = $schema->resultset('CD')->update_or_create(
    {
      artist => 'Massive Attack',
      title  => 'Mezzanine',
      year   => 1998,
    },
    { key => 'cd_artist_title' }
  );

  $cd->cd_to_producer->update_or_create({
    producer => $producer,
    name => 'harry',
  }, {
    key => 'primary,
  });


If no C<key> is specified, it searches on all unique constraints defined on the
source, including the primary key.

If the C<key> is specified as C<primary>, it searches only on the primary key.

See also L</find> and L</find_or_create>. For information on how to declare
unique constraints, see L<DBIx::Class::ResultSource/add_unique_constraint>.

B<Note>: Take care when using C<update_or_create> with a table having
columns with default values that you intend to be automatically
supplied by the database (e.g. an auto_increment primary key column).
In normal usage, the value of such columns should NOT be included at
all in the call to C<update_or_create>, even when set to C<undef>.

=cut

sub update_or_create {
  my $self = shift;
  my $attrs = (@_ > 1 && ref $_[$#_] eq 'HASH' ? pop(@_) : {});
  my $cond = ref $_[0] eq 'HASH' ? shift : {@_};

  my $row = $self->find($cond, $attrs);
  if (defined $row) {
    $row->update($cond);
    return $row;
  }

  return $self->create($cond);
}

=head2 update_or_new

=over 4

=item Arguments: \%col_values, { key => $unique_constraint }?

=item Return Value: $rowobject

=back

  $resultset->update_or_new({ col => $val, ... });

First, searches for an existing row matching one of the unique constraints
(including the primary key) on the source of this resultset. If a row is
found, updates it with the other given column values. Otherwise, instantiate
a new result object and return it. The object will not be saved into your storage
until you call L<DBIx::Class::Row/insert> on it.

Takes an optional C<key> attribute to search on a specific unique constraint.
For example:

  # In your application
  my $cd = $schema->resultset('CD')->update_or_new(
    {
      artist => 'Massive Attack',
      title  => 'Mezzanine',
      year   => 1998,
    },
    { key => 'cd_artist_title' }
  );

  if ($cd->in_storage) {
      # the cd was updated
  }
  else {
      # the cd is not yet in the database, let's insert it
      $cd->insert;
  }

B<Note>: Take care when using C<update_or_new> with a table having
columns with default values that you intend to be automatically
supplied by the database (e.g. an auto_increment primary key column).
In normal usage, the value of such columns should NOT be included at
all in the call to C<update_or_new>, even when set to C<undef>.

See also L</find>, L</find_or_create> and L</find_or_new>.

=cut

sub update_or_new {
    my $self  = shift;
    my $attrs = ( @_ > 1 && ref $_[$#_] eq 'HASH' ? pop(@_) : {} );
    my $cond  = ref $_[0] eq 'HASH' ? shift : {@_};

    my $row = $self->find( $cond, $attrs );
    if ( defined $row ) {
        $row->update($cond);
        return $row;
    }

    return $self->new_result($cond);
}

=head2 get_cache

=over 4

=item Arguments: none

=item Return Value: \@cache_objects?

=back

Gets the contents of the cache for the resultset, if the cache is set.

The cache is populated either by using the L</prefetch> attribute to
L</search> or by calling L</set_cache>.

=cut

sub get_cache {
  shift->{all_cache};
}

=head2 set_cache

=over 4

=item Arguments: \@cache_objects

=item Return Value: \@cache_objects

=back

Sets the contents of the cache for the resultset. Expects an arrayref
of objects of the same class as those produced by the resultset. Note that
if the cache is set the resultset will return the cached objects rather
than re-querying the database even if the cache attr is not set.

The contents of the cache can also be populated by using the
L</prefetch> attribute to L</search>.

=cut

sub set_cache {
  my ( $self, $data ) = @_;
  $self->throw_exception("set_cache requires an arrayref")
      if defined($data) && (ref $data ne 'ARRAY');
  $self->{all_cache} = $data;
}

=head2 clear_cache

=over 4

=item Arguments: none

=item Return Value: []

=back

Clears the cache for the resultset.

=cut

sub clear_cache {
  shift->set_cache(undef);
}

=head2 related_resultset

=over 4

=item Arguments: $relationship_name

=item Return Value: $resultset

=back

Returns a related resultset for the supplied relationship name.

  $artist_rs = $schema->resultset('CD')->related_resultset('Artist');

=cut

sub related_resultset {
  my ($self, $rel) = @_;

  $self->{related_resultsets} ||= {};
  return $self->{related_resultsets}{$rel} ||= do {
    my $rel_info = $self->result_source->relationship_info($rel);

    $self->throw_exception(
      "search_related: result source '" . $self->result_source->source_name .
        "' has no such relationship $rel")
      unless $rel_info;

    my ($from,$seen) = $self->_chain_relationship($rel);

    my $join_count = $seen->{$rel};
    my $alias = ($join_count > 1 ? join('_', $rel, $join_count) : $rel);

    #XXX - temp fix for result_class bug. There likely is a more elegant fix -groditi
    my %attrs = %{$self->{attrs}||{}};
    delete @attrs{qw(result_class alias)};

    my $new_cache;

    if (my $cache = $self->get_cache) {
      if ($cache->[0] && $cache->[0]->related_resultset($rel)->get_cache) {
        $new_cache = [ map { @{$_->related_resultset($rel)->get_cache} }
                        @$cache ];
      }
    }

    my $rel_source = $self->result_source->related_source($rel);

    my $new = do {

      # The reason we do this now instead of passing the alias to the
      # search_rs below is that if you wrap/overload resultset on the
      # source you need to know what alias it's -going- to have for things
      # to work sanely (e.g. RestrictWithObject wants to be able to add
      # extra query restrictions, and these may need to be $alias.)

      my $attrs = $rel_source->resultset_attributes;
      local $attrs->{alias} = $alias;

      $rel_source->resultset
                 ->search_rs(
                     undef, {
                       %attrs,
                       join => undef,
                       prefetch => undef,
                       select => undef,
                       as => undef,
                       where => $self->{cond},
                       seen_join => $seen,
                       from => $from,
                   });
    };
    $new->set_cache($new_cache) if $new_cache;
    $new;
  };
}

=head2 current_source_alias

=over 4

=item Arguments: none

=item Return Value: $source_alias

=back

Returns the current table alias for the result source this resultset is built
on, that will be used in the SQL query. Usually it is C<me>.

Currently the source alias that refers to the result set returned by a
L</search>/L</find> family method depends on how you got to the resultset: it's
C<me> by default, but eg. L</search_related> aliases it to the related result
source name (and keeps C<me> referring to the original result set). The long
term goal is to make L<DBIx::Class> always alias the current resultset as C<me>
(and make this method unnecessary).

Thus it's currently necessary to use this method in predefined queries (see
L<DBIx::Class::Manual::Cookbook/Predefined searches>) when referring to the
source alias of the current result set:

  # in a result set class
  sub modified_by {
    my ($self, $user) = @_;

    my $me = $self->current_source_alias;

    return $self->search(
      "$me.modified" => $user->id,
    );
  }

=cut

sub current_source_alias {
  my ($self) = @_;

  return ($self->{attrs} || {})->{alias} || 'me';
}

# This code is called by search_related, and makes sure there
# is clear separation between the joins before, during, and
# after the relationship. This information is needed later
# in order to properly resolve prefetch aliases (any alias
# with a relation_chain_depth less than the depth of the
# current prefetch is not considered)
#
# The increments happen in 1/2s to make it easier to correlate the
# join depth with the join path. An integer means a relationship
# specified via a search_related, whereas a fraction means an added
# join/prefetch via attributes
sub _chain_relationship {
  my ($self, $rel) = @_;
  my $source = $self->result_source;
  my $attrs = $self->{attrs};

  my $from = [ @{
      $attrs->{from}
        ||
      [{
        -source_handle => $source->handle,
        -alias => $attrs->{alias},
        $attrs->{alias} => $source->from,
      }]
  }];

  my $seen = { %{$attrs->{seen_join} || {} } };
  my $jpath = ($attrs->{seen_join} && keys %{$attrs->{seen_join}}) 
    ? $from->[-1][0]{-join_path} 
    : [];


  # we need to take the prefetch the attrs into account before we
  # ->_resolve_join as otherwise they get lost - captainL
  my $merged = $self->_merge_attr( $attrs->{join}, $attrs->{prefetch} );

  my @requested_joins = $source->_resolve_join(
    $merged,
    $attrs->{alias},
    $seen,
    $jpath,
  );

  push @$from, @requested_joins;

  $seen->{-relation_chain_depth} += 0.5;

  # if $self already had a join/prefetch specified on it, the requested
  # $rel might very well be already included. What we do in this case
  # is effectively a no-op (except that we bump up the chain_depth on
  # the join in question so we could tell it *is* the search_related)
  my $already_joined;


  # we consider the last one thus reverse
  for my $j (reverse @requested_joins) {
    if ($rel eq $j->[0]{-join_path}[-1]) {
      $j->[0]{-relation_chain_depth} += 0.5;
      $already_joined++;
      last;
    }
  }

# alternative way to scan the entire chain - not backwards compatible
#  for my $j (reverse @$from) {
#    next unless ref $j eq 'ARRAY';
#    if ($j->[0]{-join_path} && $j->[0]{-join_path}[-1] eq $rel) {
#      $j->[0]{-relation_chain_depth} += 0.5;
#      $already_joined++;
#      last;
#    }
#  }

  unless ($already_joined) {
    push @$from, $source->_resolve_join(
      $rel,
      $attrs->{alias},
      $seen,
      $jpath,
    );
  }

  $seen->{-relation_chain_depth} += 0.5;

  return ($from,$seen);
}

# too many times we have to do $attrs = { %{$self->_resolved_attrs} }
sub _resolved_attrs_copy {
  my $self = shift;
  return { %{$self->_resolved_attrs (@_)} };
}

sub _resolved_attrs {
  my $self = shift;
  return $self->{_attrs} if $self->{_attrs};

  my $attrs  = { %{ $self->{attrs} || {} } };
  my $source = $self->result_source;
  my $alias  = $attrs->{alias};

  $attrs->{columns} ||= delete $attrs->{cols} if exists $attrs->{cols};
  my @colbits;

  # build columns (as long as select isn't set) into a set of as/select hashes
  unless ( $attrs->{select} ) {

    my @cols = ( ref($attrs->{columns}) eq 'ARRAY' )
      ? @{ delete $attrs->{columns}}
      : (
          ( delete $attrs->{columns} )
            ||
          $source->columns
        )
    ;

    @colbits = map {
      ( ref($_) eq 'HASH' )
      ? $_
      : {
          (
            /^\Q${alias}.\E(.+)$/
              ? "$1"
              : "$_"
          )
            =>
          (
            /\./
              ? "$_"
              : "${alias}.$_"
          )
        }
    } @cols;
  }

  # add the additional columns on
  foreach ( 'include_columns', '+columns' ) {
      push @colbits, map {
          ( ref($_) eq 'HASH' )
            ? $_
            : { ( split( /\./, $_ ) )[-1] => ( /\./ ? $_ : "${alias}.$_" ) }
      } ( ref($attrs->{$_}) eq 'ARRAY' ) ? @{ delete $attrs->{$_} } : delete $attrs->{$_} if ( $attrs->{$_} );
  }

  # start with initial select items
  if ( $attrs->{select} ) {
    $attrs->{select} =
        ( ref $attrs->{select} eq 'ARRAY' )
      ? [ @{ $attrs->{select} } ]
      : [ $attrs->{select} ];
    $attrs->{as} = (
      $attrs->{as}
      ? (
        ref $attrs->{as} eq 'ARRAY'
        ? [ @{ $attrs->{as} } ]
        : [ $attrs->{as} ]
        )
      : [ map { m/^\Q${alias}.\E(.+)$/ ? $1 : $_ } @{ $attrs->{select} } ]
    );
  }
  else {

    # otherwise we intialise select & as to empty
    $attrs->{select} = [];
    $attrs->{as}     = [];
  }

  # now add colbits to select/as
  push( @{ $attrs->{select} }, map { values( %{$_} ) } @colbits );
  push( @{ $attrs->{as} },     map { keys( %{$_} ) } @colbits );

  my $adds;
  if ( $adds = delete $attrs->{'+select'} ) {
    $adds = [$adds] unless ref $adds eq 'ARRAY';
    push(
      @{ $attrs->{select} },
      map { /\./ || ref $_ ? $_ : "${alias}.$_" } @$adds
    );
  }
  if ( $adds = delete $attrs->{'+as'} ) {
    $adds = [$adds] unless ref $adds eq 'ARRAY';
    push( @{ $attrs->{as} }, @$adds );
  }

  $attrs->{from} ||= [ {
    -source_handle => $source->handle,
    -alias => $self->{attrs}{alias},
    $self->{attrs}{alias} => $source->from,
  } ];

  if ( $attrs->{join} || $attrs->{prefetch} ) {

    $self->throw_exception ('join/prefetch can not be used with a custom {from}')
      if ref $attrs->{from} ne 'ARRAY';

    my $join = delete $attrs->{join} || {};

    if ( defined $attrs->{prefetch} ) {
      $join = $self->_merge_attr( $join, $attrs->{prefetch} );
    }

    $attrs->{from} =    # have to copy here to avoid corrupting the original
      [
        @{ $attrs->{from} },
        $source->_resolve_join(
          $join,
          $alias,
          { %{ $attrs->{seen_join} || {} } },
          ($attrs->{seen_join} && keys %{$attrs->{seen_join}})
            ? $attrs->{from}[-1][0]{-join_path}
            : []
          ,
        )
      ];
  }

  if ( defined $attrs->{order_by} ) {
    $attrs->{order_by} = (
      ref( $attrs->{order_by} ) eq 'ARRAY'
      ? [ @{ $attrs->{order_by} } ]
      : [ $attrs->{order_by} || () ]
    );
  }

  if ($attrs->{group_by} and ref $attrs->{group_by} ne 'ARRAY') {
    $attrs->{group_by} = [ $attrs->{group_by} ];
  }

  # generate the distinct induced group_by early, as prefetch will be carried via a
  # subquery (since a group_by is present)
  if (delete $attrs->{distinct}) {
    if ($attrs->{group_by}) {
      # XXX comment this out, we have some queries that have both distinct and group_by -andy
      #carp ("Useless use of distinct on a grouped resultset ('distinct' is ignored when a 'group_by' is present)");
    }
    else {
      $attrs->{group_by} = [ grep { !ref($_) || (ref($_) ne 'HASH') } @{$attrs->{select}} ];
    }
  }

  $attrs->{collapse} ||= {};
  if ( my $prefetch = delete $attrs->{prefetch} ) {
    $prefetch = $self->_merge_attr( {}, $prefetch );

    my $prefetch_ordering = [];

    my $join_map = $self->_joinpath_aliases ($attrs->{from}, $attrs->{seen_join});

    my @prefetch =
      $source->_resolve_prefetch( $prefetch, $alias, $join_map, $prefetch_ordering, $attrs->{collapse} );

    # we need to somehow mark which columns came from prefetch
    $attrs->{_prefetch_select} = [ map { $_->[0] } @prefetch ];

    push @{ $attrs->{select} }, @{$attrs->{_prefetch_select}};
    push @{ $attrs->{as} }, (map { $_->[1] } @prefetch);

    push( @{$attrs->{order_by}}, @$prefetch_ordering );
    $attrs->{_collapse_order_by} = \@$prefetch_ordering;
  }

  # if both page and offset are specified, produce a combined offset
  # even though it doesn't make much sense, this is what pre 081xx has
  # been doing
  if (my $page = delete $attrs->{page}) {
    $attrs->{offset} = 
      ($attrs->{rows} * ($page - 1))
            +
      ($attrs->{offset} || 0)
    ;
  }

  return $self->{_attrs} = $attrs;
}

sub _joinpath_aliases {
  my ($self, $fromspec, $seen) = @_;

  my $paths = {};
  return $paths unless ref $fromspec eq 'ARRAY';

  my $cur_depth = $seen->{-relation_chain_depth} || 0;

  if (int ($cur_depth) != $cur_depth) {
    $self->throw_exception ("-relation_chain_depth is not an integer, something went horribly wrong ($cur_depth)");
  }

  for my $j (@$fromspec) {

    next if ref $j ne 'ARRAY';
    next if ($j->[0]{-relation_chain_depth} || 0) < $cur_depth;

    my $jpath = $j->[0]{-join_path};

    my $p = $paths;
    $p = $p->{$_} ||= {} for @{$jpath}[$cur_depth .. $#$jpath];
    push @{$p->{-join_aliases} }, $j->[0]{-alias};
  }

  return $paths;
}

sub _rollout_attr {
  my ($self, $attr) = @_;

  if (ref $attr eq 'HASH') {
    return $self->_rollout_hash($attr);
  } elsif (ref $attr eq 'ARRAY') {
    return $self->_rollout_array($attr);
  } else {
    return [$attr];
  }
}

sub _rollout_array {
  my ($self, $attr) = @_;

  my @rolled_array;
  foreach my $element (@{$attr}) {
    if (ref $element eq 'HASH') {
      push( @rolled_array, @{ $self->_rollout_hash( $element ) } );
    } elsif (ref $element eq 'ARRAY') {
      #  XXX - should probably recurse here
      push( @rolled_array, @{$self->_rollout_array($element)} );
    } else {
      push( @rolled_array, $element );
    }
  }
  return \@rolled_array;
}

sub _rollout_hash {
  my ($self, $attr) = @_;

  my @rolled_array;
  foreach my $key (keys %{$attr}) {
    push( @rolled_array, { $key => $attr->{$key} } );
  }
  return \@rolled_array;
}

sub _calculate_score {
  my ($self, $a, $b) = @_;

  if (defined $a xor defined $b) {
    return 0;
  }
  elsif (not defined $a) {
    return 1;
  }

  if (ref $b eq 'HASH') {
    my ($b_key) = keys %{$b};
    if (ref $a eq 'HASH') {
      my ($a_key) = keys %{$a};
      if ($a_key eq $b_key) {
        return (1 + $self->_calculate_score( $a->{$a_key}, $b->{$b_key} ));
      } else {
        return 0;
      }
    } else {
      return ($a eq $b_key) ? 1 : 0;
    }
  } else {
    if (ref $a eq 'HASH') {
      my ($a_key) = keys %{$a};
      return ($b eq $a_key) ? 1 : 0;
    } else {
      return ($b eq $a) ? 1 : 0;
    }
  }
}

sub _merge_attr {
  my ($self, $orig, $import) = @_;

  return $import unless defined($orig);
  return $orig unless defined($import);

  $orig = $self->_rollout_attr($orig);
  $import = $self->_rollout_attr($import);

  my $seen_keys;
  foreach my $import_element ( @{$import} ) {
    # find best candidate from $orig to merge $b_element into
    my $best_candidate = { position => undef, score => 0 }; my $position = 0;
    foreach my $orig_element ( @{$orig} ) {
      my $score = $self->_calculate_score( $orig_element, $import_element );
      if ($score > $best_candidate->{score}) {
        $best_candidate->{position} = $position;
        $best_candidate->{score} = $score;
      }
      $position++;
    }
    my ($import_key) = ( ref $import_element eq 'HASH' ) ? keys %{$import_element} : ($import_element);

    if ($best_candidate->{score} == 0 || exists $seen_keys->{$import_key}) {
      push( @{$orig}, $import_element );
    } else {
      my $orig_best = $orig->[$best_candidate->{position}];
      # merge orig_best and b_element together and replace original with merged
      if (ref $orig_best ne 'HASH') {
        $orig->[$best_candidate->{position}] = $import_element;
      } elsif (ref $import_element eq 'HASH') {
        my ($key) = keys %{$orig_best};
        $orig->[$best_candidate->{position}] = { $key => $self->_merge_attr($orig_best->{$key}, $import_element->{$key}) };
      }
    }
    $seen_keys->{$import_key} = 1; # don't merge the same key twice
  }

  return $orig;
}

sub result_source {
    my $self = shift;

    if (@_) {
        $self->_source_handle($_[0]->handle);
    } else {
        $self->_source_handle->resolve;
    }
}

=head2 throw_exception

See L<DBIx::Class::Schema/throw_exception> for details.

=cut

sub throw_exception {
  my $self=shift;

  if (ref $self && $self->_source_handle->schema) {
    $self->_source_handle->schema->throw_exception(@_)
  }
  else {
    DBIx::Class::Exception->throw(@_);
  }
}

# XXX: FIXME: Attributes docs need clearing up

=head1 ATTRIBUTES

Attributes are used to refine a ResultSet in various ways when
searching for data. They can be passed to any method which takes an
C<\%attrs> argument. See L</search>, L</search_rs>, L</find>,
L</count>.

These are in no particular order:

=head2 order_by

=over 4

=item Value: ( $order_by | \@order_by | \%order_by )

=back

Which column(s) to order the results by. 

[The full list of suitable values is documented in
L<SQL::Abstract/"ORDER BY CLAUSES">; the following is a summary of
common options.]

If a single column name, or an arrayref of names is supplied, the
argument is passed through directly to SQL. The hashref syntax allows
for connection-agnostic specification of ordering direction:

 For descending order:

  order_by => { -desc => [qw/col1 col2 col3/] }

 For explicit ascending order:

  order_by => { -asc => 'col' }

The old scalarref syntax (i.e. order_by => \'year DESC') is still
supported, although you are strongly encouraged to use the hashref
syntax as outlined above.

=head2 columns

=over 4

=item Value: \@columns

=back

Shortcut to request a particular set of columns to be retrieved. Each
column spec may be a string (a table column name), or a hash (in which
case the key is the C<as> value, and the value is used as the C<select>
expression). Adds C<me.> onto the start of any column without a C<.> in
it and sets C<select> from that, then auto-populates C<as> from
C<select> as normal. (You may also use the C<cols> attribute, as in
earlier versions of DBIC.)

=head2 +columns

=over 4

=item Value: \@columns

=back

Indicates additional columns to be selected from storage. Works the same
as L</columns> but adds columns to the selection. (You may also use the
C<include_columns> attribute, as in earlier versions of DBIC). For
example:-

  $schema->resultset('CD')->search(undef, {
    '+columns' => ['artist.name'],
    join => ['artist']
  });

would return all CDs and include a 'name' column to the information
passed to object inflation. Note that the 'artist' is the name of the
column (or relationship) accessor, and 'name' is the name of the column
accessor in the related table.

=head2 include_columns

=over 4

=item Value: \@columns

=back

Deprecated.  Acts as a synonym for L</+columns> for backward compatibility.

=head2 select

=over 4

=item Value: \@select_columns

=back

Indicates which columns should be selected from the storage. You can use
column names, or in the case of RDBMS back ends, function or stored procedure
names:

  $rs = $schema->resultset('Employee')->search(undef, {
    select => [
      'name',
      { count => 'employeeid' },
      { sum => 'salary' }
    ]
  });

When you use function/stored procedure names and do not supply an C<as>
attribute, the column names returned are storage-dependent. E.g. MySQL would
return a column named C<count(employeeid)> in the above example.

=head2 +select

=over 4

Indicates additional columns to be selected from storage.  Works the same as
L</select> but adds columns to the selection.

=back

=head2 +as

=over 4

Indicates additional column names for those added via L</+select>. See L</as>.

=back

=head2 as

=over 4

=item Value: \@inflation_names

=back

Indicates column names for object inflation. That is, C<as>
indicates the name that the column can be accessed as via the
C<get_column> method (or via the object accessor, B<if one already
exists>).  It has nothing to do with the SQL code C<SELECT foo AS bar>.

The C<as> attribute is used in conjunction with C<select>,
usually when C<select> contains one or more function or stored
procedure names:

  $rs = $schema->resultset('Employee')->search(undef, {
    select => [
      'name',
      { count => 'employeeid' }
    ],
    as => ['name', 'employee_count'],
  });

  my $employee = $rs->first(); # get the first Employee

If the object against which the search is performed already has an accessor
matching a column name specified in C<as>, the value can be retrieved using
the accessor as normal:

  my $name = $employee->name();

If on the other hand an accessor does not exist in the object, you need to
use C<get_column> instead:

  my $employee_count = $employee->get_column('employee_count');

You can create your own accessors if required - see
L<DBIx::Class::Manual::Cookbook> for details.

Please note: This will NOT insert an C<AS employee_count> into the SQL
statement produced, it is used for internal access only. Thus
attempting to use the accessor in an C<order_by> clause or similar
will fail miserably.

To get around this limitation, you can supply literal SQL to your
C<select> attibute that contains the C<AS alias> text, eg:

  select => [\'myfield AS alias']

=head2 join

=over 4

=item Value: ($rel_name | \@rel_names | \%rel_names)

=back

Contains a list of relationships that should be joined for this query.  For
example:

  # Get CDs by Nine Inch Nails
  my $rs = $schema->resultset('CD')->search(
    { 'artist.name' => 'Nine Inch Nails' },
    { join => 'artist' }
  );

Can also contain a hash reference to refer to the other relation's relations.
For example:

  package MyApp::Schema::Track;
  use base qw/DBIx::Class/;
  __PACKAGE__->table('track');
  __PACKAGE__->add_columns(qw/trackid cd position title/);
  __PACKAGE__->set_primary_key('trackid');
  __PACKAGE__->belongs_to(cd => 'MyApp::Schema::CD');
  1;

  # In your application
  my $rs = $schema->resultset('Artist')->search(
    { 'track.title' => 'Teardrop' },
    {
      join     => { cd => 'track' },
      order_by => 'artist.name',
    }
  );

You need to use the relationship (not the table) name in  conditions,
because they are aliased as such. The current table is aliased as "me", so
you need to use me.column_name in order to avoid ambiguity. For example:

  # Get CDs from 1984 with a 'Foo' track
  my $rs = $schema->resultset('CD')->search(
    {
      'me.year' => 1984,
      'tracks.name' => 'Foo'
    },
    { join => 'tracks' }
  );

If the same join is supplied twice, it will be aliased to <rel>_2 (and
similarly for a third time). For e.g.

  my $rs = $schema->resultset('Artist')->search({
    'cds.title'   => 'Down to Earth',
    'cds_2.title' => 'Popular',
  }, {
    join => [ qw/cds cds/ ],
  });

will return a set of all artists that have both a cd with title 'Down
to Earth' and a cd with title 'Popular'.

If you want to fetch related objects from other tables as well, see C<prefetch>
below.

For more help on using joins with search, see L<DBIx::Class::Manual::Joining>.

=head2 prefetch

=over 4

=item Value: ($rel_name | \@rel_names | \%rel_names)

=back

Contains one or more relationships that should be fetched along with
the main query (when they are accessed afterwards the data will
already be available, without extra queries to the database).  This is
useful for when you know you will need the related objects, because it
saves at least one query:

  my $rs = $schema->resultset('Tag')->search(
    undef,
    {
      prefetch => {
        cd => 'artist'
      }
    }
  );

The initial search results in SQL like the following:

  SELECT tag.*, cd.*, artist.* FROM tag
  JOIN cd ON tag.cd = cd.cdid
  JOIN artist ON cd.artist = artist.artistid

L<DBIx::Class> has no need to go back to the database when we access the
C<cd> or C<artist> relationships, which saves us two SQL statements in this
case.

Simple prefetches will be joined automatically, so there is no need
for a C<join> attribute in the above search.

C<prefetch> can be used with the following relationship types: C<belongs_to>,
C<has_one> (or if you're using C<add_relationship>, any relationship declared
with an accessor type of 'single' or 'filter'). A more complex example that
prefetches an artists cds, the tracks on those cds, and the tags associted
with that artist is given below (assuming many-to-many from artists to tags):

 my $rs = $schema->resultset('Artist')->search(
   undef,
   {
     prefetch => [
       { cds => 'tracks' },
       { artist_tags => 'tags' }
     ]
   }
 );


B<NOTE:> If you specify a C<prefetch> attribute, the C<join> and C<select>
attributes will be ignored.

B<CAVEATs>: Prefetch does a lot of deep magic. As such, it may not behave
exactly as you might expect.

=over 4

=item * 

Prefetch uses the L</cache> to populate the prefetched relationships. This
may or may not be what you want.

=item * 

If you specify a condition on a prefetched relationship, ONLY those
rows that match the prefetched condition will be fetched into that relationship.
This means that adding prefetch to a search() B<may alter> what is returned by
traversing a relationship. So, if you have C<< Artist->has_many(CDs) >> and you do

  my $artist_rs = $schema->resultset('Artist')->search({
      'cds.year' => 2008,
  }, {
      join => 'cds',
  });

  my $count = $artist_rs->first->cds->count;

  my $artist_rs_prefetch = $artist_rs->search( {}, { prefetch => 'cds' } );

  my $prefetch_count = $artist_rs_prefetch->first->cds->count;

  cmp_ok( $count, '==', $prefetch_count, "Counts should be the same" );

that cmp_ok() may or may not pass depending on the datasets involved. This
behavior may or may not survive the 0.09 transition.

=back

=head2 page

=over 4

=item Value: $page

=back

Makes the resultset paged and specifies the page to retrieve. Effectively
identical to creating a non-pages resultset and then calling ->page($page)
on it.

If L<rows> attribute is not specified it defaults to 10 rows per page.

When you have a paged resultset, L</count> will only return the number
of rows in the page. To get the total, use the L</pager> and call
C<total_entries> on it.

=head2 rows

=over 4

=item Value: $rows

=back

Specifes the maximum number of rows for direct retrieval or the number of
rows per page if the page attribute or method is used.

=head2 offset

=over 4

=item Value: $offset

=back

Specifies the (zero-based) row number for the  first row to be returned, or the
of the first row of the first page if paging is used.

=head2 group_by

=over 4

=item Value: \@columns

=back

A arrayref of columns to group by. Can include columns of joined tables.

  group_by => [qw/ column1 column2 ... /]

=head2 having

=over 4

=item Value: $condition

=back

HAVING is a select statement attribute that is applied between GROUP BY and
ORDER BY. It is applied to the after the grouping calculations have been
done.

  having => { 'count(employee)' => { '>=', 100 } }

=head2 distinct

=over 4

=item Value: (0 | 1)

=back

Set to 1 to group by all columns. If the resultset already has a group_by
attribute, this setting is ignored and an appropriate warning is issued.

=head2 where

=over 4

Adds to the WHERE clause.

  # only return rows WHERE deleted IS NULL for all searches
  __PACKAGE__->resultset_attributes({ where => { deleted => undef } }); )

Can be overridden by passing C<{ where => undef }> as an attribute
to a resulset.

=back

=head2 cache

Set to 1 to cache search results. This prevents extra SQL queries if you
revisit rows in your ResultSet:

  my $resultset = $schema->resultset('Artist')->search( undef, { cache => 1 } );

  while( my $artist = $resultset->next ) {
    ... do stuff ...
  }

  $rs->first; # without cache, this would issue a query

By default, searches are not cached.

For more examples of using these attributes, see
L<DBIx::Class::Manual::Cookbook>.

=head2 for

=over 4

=item Value: ( 'update' | 'shared' )

=back

Set to 'update' for a SELECT ... FOR UPDATE or 'shared' for a SELECT
... FOR SHARED.

=cut

1;
