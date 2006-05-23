package DBIx::Class::ResultSet;

use strict;
use warnings;
use overload
        '0+'     => \&count,
        'bool'   => sub { 1; },
        fallback => 1;
use Data::Page;
use Storable;
use Scalar::Util qw/weaken/;

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
  weaken $source;
  $attrs = Storable::dclone($attrs || {}); # { %{ $attrs || {} } };
  #use Data::Dumper; warn Dumper($attrs);
  my $alias = ($attrs->{alias} ||= 'me');
  
  $attrs->{columns} ||= delete $attrs->{cols} if $attrs->{cols};
  delete $attrs->{as} if $attrs->{columns};
  $attrs->{columns} ||= [ $source->columns ] unless $attrs->{select};
  $attrs->{select} = [
    map { m/\./ ? $_ : "${alias}.$_" } @{delete $attrs->{columns}}
  ] if $attrs->{columns};
  $attrs->{as} ||= [
    map { m/^\Q$alias.\E(.+)$/ ? $1 : $_ } @{$attrs->{select}}
  ];
  if (my $include = delete $attrs->{include_columns}) {
    push(@{$attrs->{select}}, @$include);
    push(@{$attrs->{as}}, map { m/([^.]+)$/; $1; } @$include);
  }
  #use Data::Dumper; warn Dumper(@{$attrs}{qw/select as/});

  $attrs->{from} ||= [ { $alias => $source->from } ];
  $attrs->{seen_join} ||= {};
  my %seen;
  if (my $join = delete $attrs->{join}) {
    foreach my $j (ref $join eq 'ARRAY' ? @$join : ($join)) {
      if (ref $j eq 'HASH') {
        $seen{$_} = 1 foreach keys %$j;
      } else {
        $seen{$j} = 1;
      }
    }
    push(@{$attrs->{from}}, $source->resolve_join(
      $join, $attrs->{alias}, $attrs->{seen_join})
    );
  }
  
  $attrs->{group_by} ||= $attrs->{select} if delete $attrs->{distinct};
  $attrs->{order_by} = [ $attrs->{order_by} ] if
    $attrs->{order_by} and !ref($attrs->{order_by});
  $attrs->{order_by} ||= [];

  my $collapse = $attrs->{collapse} || {};
  if (my $prefetch = delete $attrs->{prefetch}) {
    my @pre_order;
    foreach my $p (ref $prefetch eq 'ARRAY' ? @$prefetch : ($prefetch)) {
      if ( ref $p eq 'HASH' ) {
        foreach my $key (keys %$p) {
          push(@{$attrs->{from}}, $source->resolve_join($p, $attrs->{alias}))
            unless $seen{$key};
        }
      } else {
        push(@{$attrs->{from}}, $source->resolve_join($p, $attrs->{alias}))
            unless $seen{$p};
      }
      my @prefetch = $source->resolve_prefetch(
           $p, $attrs->{alias}, {}, \@pre_order, $collapse);
      push(@{$attrs->{select}}, map { $_->[0] } @prefetch);
      push(@{$attrs->{as}}, map { $_->[1] } @prefetch);
    }
    push(@{$attrs->{order_by}}, @pre_order);
  }
  $attrs->{collapse} = $collapse;
#  use Data::Dumper; warn Dumper($collapse) if keys %{$collapse};

  if ($attrs->{page}) {
    $attrs->{rows} ||= 10;
    $attrs->{offset} ||= 0;
    $attrs->{offset} += ($attrs->{rows} * ($attrs->{page} - 1));
  }

  bless {
    result_source => $source,
    result_class => $attrs->{result_class} || $source->result_class,
    cond => $attrs->{where},
    from => $attrs->{from},
    collapse => $collapse,
    count => undef,
    page => delete $attrs->{page},
    pager => undef,
    attrs => $attrs
  }, $class;
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
call it as C<search(undef, \%attrs);>.

  # "SELECT name, artistid FROM $artist_table"
  my @all_artists = $schema->resultset('Artist')->search(undef, {
    columns => [qw/name artistid/],
  });

=cut

sub search {
  my $self = shift;

  my $rs;
  if( @_ ) {
    
    my $attrs = { %{$self->{attrs}} };
    my $having = delete $attrs->{having};
    $attrs = { %$attrs, %{ pop(@_) } } if @_ > 1 and ref $_[$#_] eq 'HASH';

    my $where = (@_
                  ? ((@_ == 1 || ref $_[0] eq "HASH")
                      ? shift
                      : ((@_ % 2)
                          ? $self->throw_exception(
                              "Odd number of arguments to search")
                          : {@_}))
                  : undef());
    if (defined $where) {
      $attrs->{where} = (defined $attrs->{where}
                ? { '-and' =>
                    [ map { ref $_ eq 'ARRAY' ? [ -or => $_ ] : $_ }
                        $where, $attrs->{where} ] }
                : $where);
    }

    if (defined $having) {
      $attrs->{having} = (defined $attrs->{having}
                ? { '-and' =>
                    [ map { ref $_ eq 'ARRAY' ? [ -or => $_ ] : $_ }
                        $having, $attrs->{having} ] }
                : $having);
    }

    $rs = (ref $self)->new($self->result_source, $attrs);
  }
  else {
    $rs = $self;
    $rs->reset;
  }
  return (wantarray ? $rs->all : $rs);
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

Finds a row based on its primary key or unique constraint. For example:

  my $cd = $schema->resultset('CD')->find(5);

Also takes an optional C<key> attribute, to search by a specific key or unique
constraint. For example:

  my $cd = $schema->resultset('CD')->find(
    {
      artist => 'Massive Attack',
      title  => 'Mezzanine',
    },
    { key => 'artist_title' }
  );

See also L</find_or_create> and L</update_or_create>.

=cut

sub find {
  my ($self, @vals) = @_;
  my $attrs = (@vals > 1 && ref $vals[$#vals] eq 'HASH' ? pop(@vals) : {});

  my @cols = $self->result_source->primary_columns;
  if (exists $attrs->{key}) {
    my %uniq = $self->result_source->unique_constraints;
    $self->throw_exception(
      "Unknown key $attrs->{key} on '" . $self->result_source->name . "'"
    ) unless exists $uniq{$attrs->{key}};
    @cols = @{ $uniq{$attrs->{key}} };
  }
  #use Data::Dumper; warn Dumper($attrs, @vals, @cols);
  $self->throw_exception(
    "Can't find unless a primary key or unique constraint is defined"
  ) unless @cols;

  my $query;
  if (ref $vals[0] eq 'HASH') {
    $query = { %{$vals[0]} };
  } elsif (@cols == @vals) {
    $query = {};
    @{$query}{@cols} = @vals;
  } else {
    $query = {@vals};
  }
  foreach my $key (grep { ! m/\./ } keys %$query) {
    $query->{"$self->{attrs}{alias}.$key"} = delete $query->{$key};
  }
  #warn Dumper($query);
  
  if (keys %$attrs) {
      my $rs = $self->search($query,$attrs);
      return keys %{$rs->{collapse}} ? $rs->next : $rs->single;
  } else {
      return keys %{$self->{collapse}} ?
	$self->search($query)->next :
	$self->single($query);
  }
}

=head2 search_related

=over 4

=item Arguments: $cond, \%attrs?

=item Return Value: $new_resultset

=back

  $new_rs = $cd_rs->search_related('artist', {
    name => 'Emo-R-Us',
  });

Search the specified relationship, optionally specify a condition and
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
  my $attrs = { %{$self->{attrs}} };
  return $self->{cursor}
    ||= $self->result_source->storage->select($self->{from}, $attrs->{select},
          $attrs->{where},$attrs);
}

=head2 single

=over 4

=item Arguments: $cond?

=item Return Value: $row_object?

=back

  my $cd = $schema->resultset('CD')->single({ year => 2001 });

Inflates the first result without creating a cursor if the resultset has
any records in it; if not returns nothing. Used by find() as an optimisation.

=cut

sub single {
  my ($self, $where) = @_;
  my $attrs = { %{$self->{attrs}} };
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
  my @data = $self->result_source->storage->select_single(
          $self->{from}, $attrs->{select},
          $attrs->{where},$attrs);
  return (@data ? $self->_construct_object(@data) : ());
}


=head2 search_like

=over 4

=item Arguments: $cond, \%attrs?

=item Return Value: $resultset (scalar context), @row_objs (list context)

=back

  # WHERE title LIKE '%blue%'
  $cd_rs = $rs->search_like({ title => '%blue%'});

Perform a search, but use C<LIKE> instead of C<=> as the condition. Note
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
resultset slice is called on.  Indexes are from 0 - i.e. to get the first
three records, call

  my ($one, $two, $three) = $rs->slice(0, 2);

=cut

sub slice {
  my ($self, $min, $max) = @_;
  my $attrs = { %{ $self->{attrs} || {} } };
  $attrs->{offset} ||= 0;
  $attrs->{offset} += $min;
  $attrs->{rows} = ($max ? ($max - $min + 1) : 1);
  my $slice = (ref $self)->new($self->result_source, $attrs);
  return (wantarray ? $slice->all : $slice);
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

=cut

sub next {
  my ($self) = @_;
  if (@{$self->{all_cache} || []}) {
    $self->{all_cache_position} ||= 0;
    return $self->{all_cache}->[$self->{all_cache_position}++];
  }
  if ($self->{attrs}{cache}) {
    $self->{all_cache_position} = 1;
    return ($self->all)[0];
  }
  my @row = (exists $self->{stashed_row} ?
	       @{delete $self->{stashed_row}} :
	       $self->cursor->next
  );
#  warn Dumper(\@row); use Data::Dumper;
  return unless (@row);
  return $self->_construct_object(@row);
}

sub _construct_object {
  my ($self, @row) = @_;
  my @as = @{ $self->{attrs}{as} };
  
  my $info = $self->_collapse_result(\@as, \@row);
  
  my $new = $self->result_class->inflate_result($self->result_source, @$info);
  
  $new = $self->{attrs}{record_filter}->($new)
    if exists $self->{attrs}{record_filter};
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

  my $info = [ {}, {} ];
  foreach my $key (keys %const) {
    if (length $key) {
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
    } keys %{$self->{collapse}}
  } else {
    @collapse = keys %{$self->{collapse}};
  };

  if (@collapse) {
    my ($c) = sort { length $a <=> length $b } @collapse;
    my $target = $info;
    foreach my $p (split(/\./, $c)) {
      $target = $target->[1]->{$p} ||= [];
    }
    my $c_prefix = (defined($prefix) ? "${prefix}.${c}" : $c);
    my @co_key = @{$self->{collapse}{$c_prefix}};
    my %co_check = map { ($_, $target->[0]->{$_}); } @co_key;
    my $tree = $self->_collapse_result($as, $row, $c_prefix);
    my (@final, @raw);
    while ( !(grep {
                !defined($tree->[0]->{$_}) ||
		$co_check{$_} ne $tree->[0]->{$_}
              } @co_key) ) {
      push(@final, $tree);
      last unless (@raw = $self->cursor->next);
      $row = $self->{stashed_row} = \@raw;
      $tree = $self->_collapse_result($as, $row, $c_prefix);
      #warn Data::Dumper::Dumper($tree, $row);
    }
    @$target = @final;
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
  return scalar @{ $self->get_cache } if @{ $self->get_cache };

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
  my $attrs = { %{ $self->{attrs} } };
  if (my $group_by = delete $attrs->{group_by}) {
    delete $attrs->{having};
    my @distinct = (ref $group_by ?  @$group_by : ($group_by));
    # todo: try CONCAT for multi-column pk
    my @pk = $self->result_source->primary_columns;
    if (@pk == 1) {
      foreach my $column (@distinct) {
        if ($column =~ qr/^(?:\Q$attrs->{alias}.\E)?$pk[0]$/) {
          @distinct = ($column);
          last;
        }
      } 
    }

    $select = { count => { distinct => \@distinct } };
    #use Data::Dumper; die Dumper $select;
  }

  $attrs->{select} = $select;
  $attrs->{as} = [qw/count/];

  # offset, order by and page are not needed to count. record_filter is cdbi
  delete $attrs->{$_} for qw/rows offset order_by page pager record_filter/;
        
  my ($count) = (ref $self)->new($self->result_source, $attrs)->cursor->next;
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
  return @{ $self->get_cache } if @{ $self->get_cache };

  my @obj;

  if (keys %{$self->{collapse}}) {
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

=cut

sub reset {
  my ($self) = @_;
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
resultset contains anything).

=cut

sub first {
  return $_[0]->reset->next;
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
  return $self->result_source->storage->update(
    $self->result_source->from, $values, $self->{cond}
  );
}

=head2 update_all

=over 4

=item Arguments: \%values

=item Return Value: 1

=back

Fetches all objects and updates them one at a time.  Note that C<update_all>
will run cascade triggers while L</update> will not.

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
will not run cascade triggers. See L</delete_all> if you need triggers to run.

=cut

sub delete {
  my ($self) = @_;
  my $del = {};

  if (!ref($self->{cond})) {

    # No-op. No condition, we're deleting everything

  } elsif (ref $self->{cond} eq 'ARRAY') {

    $del = [ map { my %hash;
      foreach my $key (keys %{$_}) {
        $key =~ /([^.]+)$/;
        $hash{$1} = $_->{$key};
      }; \%hash; } @{$self->{cond}} ];

  } elsif (ref $self->{cond} eq 'HASH') {

    if ((keys %{$self->{cond}})[0] eq '-and') {

      $del->{-and} = [ map { my %hash;
        foreach my $key (keys %{$_}) {
          $key =~ /([^.]+)$/;
          $hash{$1} = $_->{$key};
        }; \%hash; } @{$self->{cond}{-and}} ];

    } else {

      foreach my $key (keys %{$self->{cond}}) {
        $key =~ /([^.]+)$/;
        $del->{$1} = $self->{cond}{$key};
      }
    }

  } else {
    $self->throw_exception(
      "Can't delete on resultset with condition unless hash or array"
    );
  }

  $self->result_source->storage->delete($self->result_source->from, $del);
  return 1;
}

=head2 delete_all

=over 4

=item Arguments: none

=item Return Value: 1

=back

Fetches all objects and deletes them one at a time.  Note that C<delete_all>
will run cascade triggers while L</delete> will not.

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
    unless $self->{page};
  $attrs->{rows} ||= 10;
  return $self->{pager} ||= Data::Page->new(
    $self->_count, $attrs->{rows}, $self->{page});
}

=head2 page

=over 4

=item Arguments: $page_number

=item Return Value: $rs

=back

Returns a resultset for the $page_number page of the resultset on which page
is called, where each page contains a number of rows equal to the 'rows'
attribute set on the resultset, or 10 by default

=cut

sub page {
  my ($self, $page) = @_;
  my $attrs = { %{$self->{attrs}} };
  $attrs->{page} = $page;
  return (ref $self)->new($self->result_source, $attrs);
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
  my %new = %$values;
  my $alias = $self->{attrs}{alias};
  foreach my $key (keys %{$self->{cond}||{}}) {
    $new{$1} = $self->{cond}{$key} if ($key =~ m/^(?:\Q${alias}.\E)?([^.]+)$/);
  }
  my $obj = $self->result_class->new(\%new);
  $obj->result_source($self->result_source) if $obj->can('result_source');
  return $obj;
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

Searches for a record matching the search condition; if it doesn't find one,
creates one and returns that instead.

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
    { key => 'artist_title' }
  );

See also L</find> and L</update_or_create>.

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

First, search for an existing row matching one of the unique constraints
(including the primary key) on the source of this resultset.  If a row is
found, update it with the other given column values.  Otherwise, create a new
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
    { key => 'artist_title' }
  );

If no C<key> is specified, it searches on all unique constraints defined on the
source, including the primary key.

If the C<key> is specified as C<primary>, search only on the primary key.

See also L</find> and L</find_or_create>.

=cut

sub update_or_create {
  my $self = shift;
  my $attrs = (@_ > 1 && ref $_[$#_] eq 'HASH' ? pop(@_) : {});
  my $hash = ref $_[0] eq 'HASH' ? shift : {@_};

  my %unique_constraints = $self->result_source->unique_constraints;
  my @constraint_names   = (exists $attrs->{key}
                            ? ($attrs->{key})
                            : keys %unique_constraints);

  my @unique_hashes;
  foreach my $name (@constraint_names) {
    my @unique_cols = @{ $unique_constraints{$name} };
    my %unique_hash =
      map  { $_ => $hash->{$_} }
      grep { exists $hash->{$_} }
      @unique_cols;

    push @unique_hashes, \%unique_hash
      if (scalar keys %unique_hash == scalar @unique_cols);
  }

  if (@unique_hashes) {
    my $row = $self->single(\@unique_hashes);
    if (defined $row) {
      $row->set_columns($hash);
      $row->update;
      return $row;
    }
  }

  return $self->create($hash);
}

=head2 get_cache

=over 4

=item Arguments: none

=item Return Value: \@cache_objects?

=back

Gets the contents of the cache for the resultset if the cache is set

=cut

sub get_cache {
  shift->{all_cache} || [];
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
    if ref $data ne 'ARRAY';
  my $result_class = $self->result_class;
  foreach( @$data ) {
    $self->throw_exception(
      "cannot cache object of type '$_', expected '$result_class'"
    ) if ref $_ ne $result_class;
  }
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
  shift->set_cache([]);
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
  my ( $self, $rel ) = @_;
  $self->{related_resultsets} ||= {};
  return $self->{related_resultsets}{$rel} ||= do {
      #warn "fetching related resultset for rel '$rel'";
      my $rel_obj = $self->result_source->relationship_info($rel);
      $self->throw_exception(
        "search_related: result source '" . $self->result_source->name .
        "' has no such relationship ${rel}")
        unless $rel_obj; #die Dumper $self->{attrs};

      my $rs = $self->search(undef, { join => $rel });
      my $alias = defined $rs->{attrs}{seen_join}{$rel}
                    && $rs->{attrs}{seen_join}{$rel} > 1
                  ? join('_', $rel, $rs->{attrs}{seen_join}{$rel})
                  : $rel;

      $self->result_source->schema->resultset($rel_obj->{class}
           )->search( undef,
             { %{$rs->{attrs}},
               alias => $alias,
               select => undef,
               as => undef }
           );
  };
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

In simple terms, C<from> works as follows:

    [
        { <alias> => <table>, -join-type => 'inner|left|right' }
        [] # nested JOIN (optional)
        { <table.column> => <foreign_table.foreign_key> }
    ]

    JOIN
        <alias> <table>
        [JOIN ...]
    ON <table.column> = <foreign_table.foreign_key>

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
                    { father => 'person', -join-type => 'inner' },
                    { 'father.id' => 'child.father_id' }
                ],
            ]
        },
    );

    # Equivalent SQL:
    # SELECT child.* FROM person child
    # INNER JOIN person father ON child.father_id = father.id

=head2 page

=over 4

=item Value: $page

=back

Makes the resultset paged and specifies the page to retrieve. Effectively
identical to creating a non-pages resultset and then calling ->page($page)
on it.

=head2 rows

=over 4

=item Value: $rows

=back

Specifes the maximum number of rows for direct retrieval or the number of
rows per page if the page attribute or method is used.

=head2 group_by

=over 4

=item Value: \@columns

=back

A arrayref of columns to group by. Can include columns of joined tables.

  group_by => [qw/ column1 column2 ... /]

=head2 distinct

=over 4

=item Value: (0 | 1)

=back

Set to 1 to group by all columns.

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

=cut

1;
