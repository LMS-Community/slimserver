package DBIx::Class::ResultSet;

use strict;
use warnings;
use overload
        '0+'     => \&count,
        'bool'   => sub { 1; },
        fallback => 1;
use Carp::Clan qw/^DBIx::Class/;
use Data::Page;
use Storable;
use DBIx::Class::ResultSetColumn;
use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/AccessorGroup/);
__PACKAGE__->mk_group_accessors('simple' => qw/result_source result_class/);

=head1 NAME

DBIx::Class::ResultSet - Responsible for fetching and creating resultset.

=head1 SYNOPSIS

  my $rs   = $schema->resultset('User')->search(registered => 1);
  my @rows = $schema->resultset('CD')->search(year => 2005);

=head1 DESCRIPTION

The resultset is also known as an iterator. It is responsible for handling
queries that may return an arbitrary number of rows, e.g. via L</search>
or a C<has_many> relationship.

In the examples below, the following table classes are used:

  package MyApp::Schema::Artist;
  use base qw/DBIx::Class/;
  __PACKAGE__->load_components(qw/Core/);
  __PACKAGE__->table('artist');
  __PACKAGE__->add_columns(qw/artistid name/);
  __PACKAGE__->set_primary_key('artistid');
  __PACKAGE__->has_many(cds => 'MyApp::Schema::CD');
  1;

  package MyApp::Schema::CD;
  use base qw/DBIx::Class/;
  __PACKAGE__->load_components(qw/Core/);
  __PACKAGE__->table('cd');
  __PACKAGE__->add_columns(qw/cdid artist title year/);
  __PACKAGE__->set_primary_key('cdid');
  __PACKAGE__->belongs_to(artist => 'MyApp::Schema::Artist');
  1;

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
  #weaken $source;

  if ($attrs->{page}) {
    $attrs->{rows} ||= 10;
    $attrs->{offset} ||= 0;
    $attrs->{offset} += ($attrs->{rows} * ($attrs->{page} - 1));
  }

  $attrs->{alias} ||= 'me';

  my $self = {
    result_source => $source,
    result_class => $attrs->{result_class} || $source->result_class,
    cond => $attrs->{where},
    count => undef,
    pager => undef,
    attrs => $attrs
  };

  bless $self, $class;

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

For a list of attributes that can be passed to C<search>, see L</ATTRIBUTES>. For more examples of using this function, see L<Searching|DBIx::Class::Manual::Cookbook/Searching>.

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

  my $rows;

  unless (@_) {                 # no search, effectively just a clone
    $rows = $self->get_cache;
  }

  my $attrs = {};
  $attrs = pop(@_) if @_ > 1 and ref $_[$#_] eq 'HASH';
  my $our_attrs = { %{$self->{attrs}} };
  my $having = delete $our_attrs->{having};
  my $where = delete $our_attrs->{where};

  my $new_attrs = { %{$our_attrs}, %{$attrs} };

  # merge new attrs into inherited
  foreach my $key (qw/join prefetch/) {
    next unless exists $attrs->{$key};
    $new_attrs->{$key} = $self->_merge_attr($our_attrs->{$key}, $attrs->{$key});
  }

  my $cond = (@_
    ? (
        (@_ == 1 || ref $_[0] eq "HASH")
          ? shift
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

=cut

sub search_literal {
  my ($self, $cond, @vals) = @_;
  my $attrs = (ref $vals[$#vals] eq 'HASH' ? { %{ pop(@vals) } } : {});
  $attrs->{bind} = [ @{$self->{attrs}{bind}||[]}, @vals ];
  return $self->search(\$cond, $attrs);
}

=head2 find

=over 4

=item Arguments: @values | \%cols, \%attrs?

=item Return Value: $row_object

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
source, including the primary key.

If your table does not have a primary key, you B<must> provide a value for the
C<key> attribute matching one of the unique constraints on the source.

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

  my @unique_queries = $self->_unique_queries($input_query, $attrs);

  # Build the final query: Default to the disjunction of the unique queries,
  # but allow the input query in case the ResultSet defines the query or the
  # user is abusing find
  my $alias = exists $attrs->{alias} ? $attrs->{alias} : $self->{attrs}{alias};
  my $query = @unique_queries
    ? [ map { $self->_add_alias($_, $alias) } @unique_queries ]
    : $self->_add_alias($input_query, $alias);

  # Run the query
  if (keys %$attrs) {
    my $rs = $self->search($query, $attrs);
    return keys %{$rs->_resolved_attrs->{collapse}} ? $rs->next : $rs->single;
  }
  else {
    return keys %{$self->_resolved_attrs->{collapse}}
      ? $self->search($query)->next
      : $self->single($query);
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

  my @unique_queries;
  foreach my $name (@constraint_names) {
    my @unique_cols = $self->result_source->unique_constraint_columns($name);
    my $unique_query = $self->_build_unique_query($query, \@unique_cols);

    my $num_query = scalar keys %$unique_query;
    next unless $num_query;

    # XXX: Assuming quite a bit about $self->{attrs}{where}
    my $num_cols = scalar @unique_cols;
    my $num_where = exists $self->{attrs}{where}
      ? scalar keys %{ $self->{attrs}{where} }
      : 0;
    push @unique_queries, $unique_query
      if $num_query + $num_where == $num_cols;
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

  my $attrs = { %{$self->_resolved_attrs} };
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
any records in it; if not returns nothing. Used by L</find> as an optimisation.

Can optionally take an additional condition *only* - this is a fast-code-path
method; if you need to add extra joins or similar call ->search and then
->single without a condition on the $rs returned from that.

=cut

sub single {
  my ($self, $where) = @_;
  my $attrs = { %{$self->_resolved_attrs} };
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

  return (@data ? $self->_construct_object(@data) : ());
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
#      warn "ARRAY: " . Dumper $subquery;
      $collapsed = $self->_collapse_query($subquery, $collapsed);
    }
  }
  elsif (ref $query eq 'HASH') {
    if (keys %$query and (keys %$query)[0] eq '-and') {
      foreach my $subquery (@{$query->{-and}}) {
#        warn "HASH: " . Dumper $subquery;
        $collapsed = $self->_collapse_query($subquery, $collapsed);
      }
    }
    else {
#      warn "LEAF: " . Dumper $query;
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
that this is simply a convenience method. You most likely want to use
L</search> with specific operators.

For more information, see L<DBIx::Class::Manual::Cookbook>.

=cut

sub search_like {
  my $class = shift;
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
  my @row = (
    exists $self->{stashed_row}
      ? @{delete $self->{stashed_row}}
      : $self->cursor->next
  );
  return unless (@row);
  return $self->_construct_object(@row);
}

sub _construct_object {
  my ($self, @row) = @_;
  my $info = $self->_collapse_result($self->{_attrs}{as}, \@row);
  my $new = $self->result_class->inflate_result($self->result_source, @$info);
  $new = $self->{_attrs}{record_filter}->($new)
    if exists $self->{_attrs}{record_filter};
  return $new;
}

sub _collapse_result {
  my ($self, $as, $row, $prefix) = @_;

  my %const;
  my @copy = @$row;
  
  foreach my $this_as (@$as) {
    my $val = shift @copy;
    if (defined $prefix) {
      if ($this_as =~ m/^\Q${prefix}.\E(.+)$/) {
        my $remain = $1;
        $remain =~ /^(?:(.*)\.)?([^.]+)$/;
        $const{$1||''}{$2} = $val;
      }
    } else {
      $this_as =~ /^(?:(.*)\.)?([^.]+)$/;
      $const{$1||''}{$2} = $val;
    }
  }

  my $alias = $self->{attrs}{alias};
  my $info = [ {}, {} ];
  foreach my $key (keys %const) {
    if (length $key && $key ne $alias) {
      my $target = $info;
      my @parts = split(/\./, $key);
      foreach my $p (@parts) {
        $target = $target->[1]->{$p} ||= [];
      }
      $target->[0] = $const{$key};
    } else {
      $info->[0] = $const{$key};
    }
  }
  
  my @collapse;
  if (defined $prefix) {
    @collapse = map {
        m/^\Q${prefix}.\E(.+)$/ ? ($1) : ()
    } keys %{$self->{_attrs}{collapse}}
  } else {
    @collapse = keys %{$self->{_attrs}{collapse}};
  };

  if (@collapse) {
    my ($c) = sort { length $a <=> length $b } @collapse;
    my $target = $info;
    foreach my $p (split(/\./, $c)) {
      $target = $target->[1]->{$p} ||= [];
    }
    my $c_prefix = (defined($prefix) ? "${prefix}.${c}" : $c);
    my @co_key = @{$self->{_attrs}{collapse}{$c_prefix}};
    my $tree = $self->_collapse_result($as, $row, $c_prefix);
    my %co_check = map { ($_, $tree->[0]->{$_}); } @co_key;
    my (@final, @raw);

    while (
      !(
        grep {
          !defined($tree->[0]->{$_}) || $co_check{$_} ne $tree->[0]->{$_}
        } @co_key
        )
    ) {
      push(@final, $tree);
      last unless (@raw = $self->cursor->next);
      $row = $self->{stashed_row} = \@raw;
      $tree = $self->_collapse_result($as, $row, $c_prefix);
    }
    @$target = (@final ? @final : [ {}, {} ]);
      # single empty result to indicate an empty prefetched has_many
  }

  #print "final info: " . Dumper($info);
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

=cut


=head2 count

=over 4

=item Arguments: $cond, \%attrs??

=item Return Value: $count

=back

Performs an SQL C<COUNT> with the same query as the resultset was built
with to find the number of elements. If passed arguments, does a search
on the resultset and counts the results of that.

Note: When using C<count> with C<group_by>, L<DBIX::Class> emulates C<GROUP BY>
using C<COUNT( DISTINCT( columns ) )>. Some databases (notably SQLite) do
not support C<DISTINCT> with multiple columns. If you are using such a
database, you should only use columns from the main table in your C<group_by>
clause.

=cut

sub count {
  my $self = shift;
  return $self->search(@_)->count if @_ and defined $_[0];
  return scalar @{ $self->get_cache } if $self->get_cache;
  my $count = $self->_count;
  return 0 unless $count;

  $count -= $self->{attrs}{offset} if $self->{attrs}{offset};
  $count = $self->{attrs}{rows} if
    $self->{attrs}{rows} and $self->{attrs}{rows} < $count;
  return $count;
}

sub _count { # Separated out so pager can get the full count
  my $self = shift;
  my $select = { count => '*' };

  my $attrs = { %{$self->_resolved_attrs} };
  if (my $group_by = delete $attrs->{group_by}) {
    delete $attrs->{having};
    my @distinct = (ref $group_by ?  @$group_by : ($group_by));
    # todo: try CONCAT for multi-column pk
    my @pk = $self->result_source->primary_columns;
    if (@pk == 1) {
      my $alias = $attrs->{alias};
      foreach my $column (@distinct) {
        if ($column =~ qr/^(?:\Q${alias}.\E)?$pk[0]$/) {
          @distinct = ($column);
          last;
        }
      }
    }

    $select = { count => { distinct => \@distinct } };
  }

  $attrs->{select} = $select;
  $attrs->{as} = [qw/count/];

  # offset, order by and page are not needed to count. record_filter is cdbi
  delete $attrs->{$_} for qw/rows offset order_by page pager record_filter/;

  my $tmp_rs = (ref $self)->new($self->result_source, $attrs);
  my ($count) = $tmp_rs->cursor->next;
  return $count;
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
  my ($self) = @_;
  return @{ $self->get_cache } if $self->get_cache;

  my @obj;

  # TODO: don't call resolve here
  if (keys %{$self->_resolved_attrs->{collapse}}) {
#  if ($self->{attrs}{prefetch}) {
      # Using $self->cursor->all is really just an optimisation.
      # If we're collapsing has_many prefetches it probably makes
      # very little difference, and this is cleaner than hacking
      # _construct_object to survive the approach
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

# _cond_for_update_delete
#
# update/delete require the condition to be modified to handle
# the differing SQL syntax available.  This transforms the $self->{cond}
# appropriately, returning the new condition.

sub _cond_for_update_delete {
  my ($self) = @_;
  my $cond = {};

  # No-op. No condition, we're updating/deleting everything
  return $cond unless ref $self->{cond};

  if (ref $self->{cond} eq 'ARRAY') {
    $cond = [
      map {
        my %hash;
        foreach my $key (keys %{$_}) {
          $key =~ /([^.]+)$/;
          $hash{$1} = $_->{$key};
        }
        \%hash;
      } @{$self->{cond}}
    ];
  }
  elsif (ref $self->{cond} eq 'HASH') {
    if ((keys %{$self->{cond}})[0] eq '-and') {
      $cond->{-and} = [];

      my @cond = @{$self->{cond}{-and}};
      for (my $i = 0; $i < @cond; $i++) {
        my $entry = $cond[$i];

        my %hash;
        if (ref $entry eq 'HASH') {
          foreach my $key (keys %{$entry}) {
            $key =~ /([^.]+)$/;
            $hash{$1} = $entry->{$key};
          }
        }
        else {
          $entry =~ /([^.]+)$/;
          $hash{$1} = $cond[++$i];
        }

        push @{$cond->{-and}}, \%hash;
      }
    }
    else {
      foreach my $key (keys %{$self->{cond}}) {
        $key =~ /([^.]+)$/;
        $cond->{$1} = $self->{cond}{$key};
      }
    }
  }
  else {
    $self->throw_exception(
      "Can't update/delete on resultset with condition unless hash or array"
    );
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
  $self->throw_exception("Values for update must be a hash")
    unless ref $values eq 'HASH';

  my $cond = $self->_cond_for_update_delete;

  return $self->result_source->storage->update(
    $self->result_source->from, $values, $cond
  );
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
  $self->throw_exception("Values for update must be a hash")
    unless ref $values eq 'HASH';
  foreach my $obj ($self->all) {
    $obj->set_columns($values)->update;
  }
  return 1;
}

=head2 delete

=over 4

=item Arguments: none

=item Return Value: 1

=back

Deletes the contents of the resultset from its result source. Note that this
will not run DBIC cascade triggers. See L</delete_all> if you need triggers
to run. See also L<DBIx::Class::Row/delete>.

=cut

sub delete {
  my ($self) = @_;

  my $cond = $self->_cond_for_update_delete;

  $self->result_source->storage->delete($self->result_source->from, $cond);
  return 1;
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
  my ($self) = @_;
  $_->delete for $self->all;
  return 1;
}

=head2 pager

=over 4

=item Arguments: none

=item Return Value: $pager

=back

Return Value a L<Data::Page> object for the current resultset. Only makes
sense for queries with a C<page> attribute.

=cut

sub pager {
  my ($self) = @_;
  my $attrs = $self->{attrs};
  $self->throw_exception("Can't create pager for non-paged rs")
    unless $self->{attrs}{page};
  $attrs->{rows} ||= 10;
  return $self->{pager} ||= Data::Page->new(
    $self->_count, $attrs->{rows}, $self->{attrs}{page});
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

=item Return Value: $object

=back

Creates an object in the resultset's result class and returns it.

=cut

sub new_result {
  my ($self, $values) = @_;
  $self->throw_exception( "new_result needs a hash" )
    unless (ref $values eq 'HASH');
  $self->throw_exception(
    "Can't abstract implicit construct, condition not a hash"
  ) if ($self->{cond} && !(ref $self->{cond} eq 'HASH'));

  my $alias = $self->{attrs}{alias};
  my $collapsed_cond = $self->{cond} ? $self->_collapse_cond($self->{cond}) : {};
  my %new = (
    %{ $self->_remove_alias($values, $alias) },
    %{ $self->_remove_alias($collapsed_cond, $alias) },
  );

  my $obj = $self->result_class->new(\%new);
  $obj->result_source($self->result_source) if $obj->can('result_source');
  return $obj;
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
#      warn "ARRAY: " . Dumper $subcond;
      $collapsed = $self->_collapse_cond($subcond, $collapsed);
    }
  }
  elsif (ref $cond eq 'HASH') {
    if (keys %$cond and (keys %$cond)[0] eq '-and') {
      foreach my $subcond (@{$cond->{-and}}) {
#        warn "HASH: " . Dumper $subcond;
        $collapsed = $self->_collapse_cond($subcond, $collapsed);
      }
    }
    else {
#      warn "LEAF: " . Dumper $cond;
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

  my %unaliased = %{ $query || {} };
  foreach my $key (keys %unaliased) {
    $unaliased{$1} = delete $unaliased{$key}
      if $key =~ m/^(?:\Q$alias\E\.)?([^.]+)$/;
  }

  return \%unaliased;
}

=head2 find_or_new

=over 4

=item Arguments: \%vals, \%attrs?

=item Return Value: $object

=back

Find an existing record from this resultset. If none exists, instantiate a new
result object and return it. The object will not be saved into your storage
until you call L<DBIx::Class::Row/insert> on it.

If you want objects to be saved immediately, use L</find_or_create> instead.

=cut

sub find_or_new {
  my $self     = shift;
  my $attrs    = (@_ > 1 && ref $_[$#_] eq 'HASH' ? pop(@_) : {});
  my $hash     = ref $_[0] eq 'HASH' ? shift : {@_};
  my $exists   = $self->find($hash, $attrs);
  return defined $exists ? $exists : $self->new_result($hash);
}

=head2 create

=over 4

=item Arguments: \%vals

=item Return Value: $object

=back

Inserts a record into the resultset and returns the object representing it.

Effectively a shortcut for C<< ->new_result(\%vals)->insert >>.

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

=item Return Value: $object

=back

  $class->find_or_create({ key => $val, ... });

Tries to find a record based on its primary key or unique constraint; if none
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

See also L</find> and L</update_or_create>. For information on how to declare
unique constraints, see L<DBIx::Class::ResultSource/add_unique_constraint>.

=cut

sub find_or_create {
  my $self     = shift;
  my $attrs    = (@_ > 1 && ref $_[$#_] eq 'HASH' ? pop(@_) : {});
  my $hash     = ref $_[0] eq 'HASH' ? shift : {@_};
  my $exists   = $self->find($hash, $attrs);
  return defined $exists ? $exists : $self->create($hash);
}

=head2 update_or_create

=over 4

=item Arguments: \%col_values, { key => $unique_constraint }?

=item Return Value: $object

=back

  $class->update_or_create({ col => $val, ... });

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

If no C<key> is specified, it searches on all unique constraints defined on the
source, including the primary key.

If the C<key> is specified as C<primary>, it searches only on the primary key.

See also L</find> and L</find_or_create>. For information on how to declare
unique constraints, see L<DBIx::Class::ResultSource/add_unique_constraint>.

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

=head2 get_cache

=over 4

=item Arguments: none

=item Return Value: \@cache_objects?

=back

Gets the contents of the cache for the resultset, if the cache is set.

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
    my $rel_obj = $self->result_source->relationship_info($rel);

    $self->throw_exception(
      "search_related: result source '" . $self->result_source->name .
        "' has no such relationship $rel")
      unless $rel_obj;
    
    my ($from,$seen) = $self->_resolve_from($rel);

    my $join_count = $seen->{$rel};
    my $alias = ($join_count > 1 ? join('_', $rel, $join_count) : $rel);

    $self->result_source->schema->resultset($rel_obj->{class})->search_rs(
      undef, {
        %{$self->{attrs}||{}},
        join => undef,
        prefetch => undef,
        select => undef,
        as => undef,
        alias => $alias,
        where => $self->{cond},
        seen_join => $seen,
        from => $from,
    });
  };
}

sub _resolve_from {
  my ($self, $extra_join) = @_;
  my $source = $self->result_source;
  my $attrs = $self->{attrs};
  
  my $from = $attrs->{from}
    || [ { $attrs->{alias} => $source->from } ];
    
  my $seen = { %{$attrs->{seen_join}||{}} };

  my $join = ($attrs->{join}
               ? [ $attrs->{join}, $extra_join ]
               : $extra_join);
  $from = [
    @$from,
    ($join ? $source->resolve_join($join, $attrs->{alias}, $seen) : ()),
  ];

  return ($from,$seen);
}

sub _resolved_attrs {
  my $self = shift;
  return $self->{_attrs} if $self->{_attrs};

  my $attrs = { %{$self->{attrs}||{}} };
  my $source = $self->{result_source};
  my $alias = $attrs->{alias};

  $attrs->{columns} ||= delete $attrs->{cols} if exists $attrs->{cols};
  if ($attrs->{columns}) {
    delete $attrs->{as};
  } elsif (!$attrs->{select}) {
    $attrs->{columns} = [ $source->columns ];
  }
 
  $attrs->{select} = 
    ($attrs->{select}
      ? (ref $attrs->{select} eq 'ARRAY'
          ? [ @{$attrs->{select}} ]
          : [ $attrs->{select} ])
      : [ map { m/\./ ? $_ : "${alias}.$_" } @{delete $attrs->{columns}} ]
    );
  $attrs->{as} =
    ($attrs->{as}
      ? (ref $attrs->{as} eq 'ARRAY'
          ? [ @{$attrs->{as}} ]
          : [ $attrs->{as} ])
      : [ map { m/^\Q${alias}.\E(.+)$/ ? $1 : $_ } @{$attrs->{select}} ]
    );
  
  my $adds;
  if ($adds = delete $attrs->{include_columns}) {
    $adds = [$adds] unless ref $adds eq 'ARRAY';
    push(@{$attrs->{select}}, @$adds);
    push(@{$attrs->{as}}, map { m/([^.]+)$/; $1 } @$adds);
  }
  if ($adds = delete $attrs->{'+select'}) {
    $adds = [$adds] unless ref $adds eq 'ARRAY';
    push(@{$attrs->{select}},
           map { /\./ || ref $_ ? $_ : "${alias}.$_" } @$adds);
  }
  if (my $adds = delete $attrs->{'+as'}) {
    $adds = [$adds] unless ref $adds eq 'ARRAY';
    push(@{$attrs->{as}}, @$adds);
  }

  $attrs->{from} ||= [ { 'me' => $source->from } ];

  if (exists $attrs->{join} || exists $attrs->{prefetch}) {
    my $join = delete $attrs->{join} || {};

    if (defined $attrs->{prefetch}) {
      $join = $self->_merge_attr(
        $join, $attrs->{prefetch}
      );
    }

    $attrs->{from} =   # have to copy here to avoid corrupting the original
      [
        @{$attrs->{from}}, 
        $source->resolve_join($join, $alias, { %{$attrs->{seen_join}||{}} })
      ];
  }

  $attrs->{group_by} ||= $attrs->{select} if delete $attrs->{distinct};
  if ($attrs->{order_by}) {
    $attrs->{order_by} = (ref($attrs->{order_by}) eq 'ARRAY'
                           ? [ @{$attrs->{order_by}} ]
                           : [ $attrs->{order_by} ]);
  } else {
    $attrs->{order_by} = [];    
  }

  my $collapse = $attrs->{collapse} || {};
  if (my $prefetch = delete $attrs->{prefetch}) {
    $prefetch = $self->_merge_attr({}, $prefetch);
    my @pre_order;
    my $seen = $attrs->{seen_join} || {};
    foreach my $p (ref $prefetch eq 'ARRAY' ? @$prefetch : ($prefetch)) {
      # bring joins back to level of current class
      my @prefetch = $source->resolve_prefetch(
        $p, $alias, $seen, \@pre_order, $collapse
      );
      push(@{$attrs->{select}}, map { $_->[0] } @prefetch);
      push(@{$attrs->{as}}, map { $_->[1] } @prefetch);
    }
    push(@{$attrs->{order_by}}, @pre_order);
  }
  $attrs->{collapse} = $collapse;

  return $self->{_attrs} = $attrs;
}

sub _merge_attr {
  my ($self, $a, $b) = @_;
  return $b unless defined($a);
  return $a unless defined($b);
  
  if (ref $b eq 'HASH' && ref $a eq 'HASH') {
    foreach my $key (keys %{$b}) {
      if (exists $a->{$key}) {
        $a->{$key} = $self->_merge_attr($a->{$key}, $b->{$key});
      } else {
        $a->{$key} = $b->{$key};
      }
    }
    return $a;
  } else {
    $a = [$a] unless ref $a eq 'ARRAY';
    $b = [$b] unless ref $b eq 'ARRAY';

    my $hash = {};
    my @array;
    foreach my $x ($a, $b) {
      foreach my $element (@{$x}) {
        if (ref $element eq 'HASH') {
          $hash = $self->_merge_attr($hash, $element);
        } elsif (ref $element eq 'ARRAY') {
          push(@array, @{$element});
        } else {
          push(@array, $element) unless $b == $x
            && grep { $_ eq $element } @array;
        }
      }
    }
    
    @array = grep { !exists $hash->{$_} } @array;

    return keys %{$hash}
      ? ( scalar(@array)
            ? [$hash, @array]
            : $hash
        )
      : \@array;
  }
}

=head2 throw_exception

See L<DBIx::Class::Schema/throw_exception> for details.

=cut

sub throw_exception {
  my $self=shift;
  $self->result_source->schema->throw_exception(@_);
}

# XXX: FIXME: Attributes docs need clearing up

=head1 ATTRIBUTES

The resultset takes various attributes that modify its behavior. Here's an
overview of them:

=head2 order_by

=over 4

=item Value: ($order_by | \@order_by)

=back

Which column(s) to order the results by. This is currently passed
through directly to SQL, so you can give e.g. C<year DESC> for a
descending order on the column `year'.

Please note that if you have quoting enabled (see
L<DBIx::Class::Storage/quote_char>) you will need to do C<\'year DESC' > to
specify an order. (The scalar ref causes it to be passed as raw sql to the DB,
so you will need to manually quote things as appropriate.)

=head2 columns

=over 4

=item Value: \@columns

=back

Shortcut to request a particular set of columns to be retrieved.  Adds
C<me.> onto the start of any column without a C<.> in it and sets C<select>
from that, then auto-populates C<as> from C<select> as normal. (You may also
use the C<cols> attribute, as in earlier versions of DBIC.)

=head2 include_columns

=over 4

=item Value: \@columns

=back

Shortcut to include additional columns in the returned results - for example

  $schema->resultset('CD')->search(undef, {
    include_columns => ['artist.name'],
    join => ['artist']
  });

would return all CDs and include a 'name' column to the information
passed to object inflation

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
L<select> but adds columns to the selection.

=back

=head2 +as

=over 4

Indicates additional column names for those added via L<+select>.

=back

=head2 as

=over 4

=item Value: \@inflation_names

=back

Indicates column names for object inflation. This is used in conjunction with
C<select>, usually when C<select> contains one or more function or stored
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

=head2 prefetch

=over 4

=item Value: ($rel_name | \@rel_names | \%rel_names)

=back

Contains one or more relationships that should be fetched along with the main
query (when they are accessed afterwards they will have already been
"prefetched").  This is useful for when you know you will need the related
objects, because it saves at least one query:

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
for a C<join> attribute in the above search. If you're prefetching to
depth (e.g. { cd => { artist => 'label' } or similar), you'll need to
specify the join as well.

C<prefetch> can be used with the following relationship types: C<belongs_to>,
C<has_one> (or if you're using C<add_relationship>, any relationship declared
with an accessor type of 'single' or 'filter').

=head2 page

=over 4

=item Value: $page

=back

Makes the resultset paged and specifies the page to retrieve. Effectively
identical to creating a non-pages resultset and then calling ->page($page)
on it.

If L<rows> attribute is not specified it defualts to 10 rows per page.

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

Set to 1 to group by all columns.

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

=head2 from

=over 4

=item Value: \@from_clause

=back

The C<from> attribute gives you manual control over the C<FROM> clause of SQL
statements generated by L<DBIx::Class>, allowing you to express custom C<JOIN>
clauses.

NOTE: Use this on your own risk.  This allows you to shoot off your foot!

C<join> will usually do what you need and it is strongly recommended that you
avoid using C<from> unless you cannot achieve the desired result using C<join>.
And we really do mean "cannot", not just tried and failed. Attempting to use
this because you're having problems with C<join> is like trying to use x86
ASM because you've got a syntax error in your C. Trust us on this.

Now, if you're still really, really sure you need to use this (and if you're
not 100% sure, ask the mailing list first), here's an explanation of how this
works.

The syntax is as follows -

  [
    { <alias1> => <table1> },
    [
      { <alias2> => <table2>, -join_type => 'inner|left|right' },
      [], # nested JOIN (optional)
      { <table1.column1> => <table2.column2>, ... (more conditions) },
    ],
    # More of the above [ ] may follow for additional joins
  ]

  <table1> <alias1>
  JOIN
    <table2> <alias2>
    [JOIN ...]
  ON <table1.column1> = <table2.column2>
  <more joins may follow>

An easy way to follow the examples below is to remember the following:

    Anything inside "[]" is a JOIN
    Anything inside "{}" is a condition for the enclosing JOIN

The following examples utilize a "person" table in a family tree application.
In order to express parent->child relationships, this table is self-joined:

    # Person->belongs_to('father' => 'Person');
    # Person->belongs_to('mother' => 'Person');

C<from> can be used to nest joins. Here we return all children with a father,
then search against all mothers of those children:

  $rs = $schema->resultset('Person')->search(
      undef,
      {
          alias => 'mother', # alias columns in accordance with "from"
          from => [
              { mother => 'person' },
              [
                  [
                      { child => 'person' },
                      [
                          { father => 'person' },
                          { 'father.person_id' => 'child.father_id' }
                      ]
                  ],
                  { 'mother.person_id' => 'child.mother_id' }
              ],
          ]
      },
  );

  # Equivalent SQL:
  # SELECT mother.* FROM person mother
  # JOIN (
  #   person child
  #   JOIN person father
  #   ON ( father.person_id = child.father_id )
  # )
  # ON ( mother.person_id = child.mother_id )

The type of any join can be controlled manually. To search against only people
with a father in the person table, we could explicitly use C<INNER JOIN>:

    $rs = $schema->resultset('Person')->search(
        undef,
        {
            alias => 'child', # alias columns in accordance with "from"
            from => [
                { child => 'person' },
                [
                    { father => 'person', -join_type => 'inner' },
                    { 'father.id' => 'child.father_id' }
                ],
            ]
        },
    );

    # Equivalent SQL:
    # SELECT child.* FROM person child
    # INNER JOIN person father ON child.father_id = father.id

=cut

1;
