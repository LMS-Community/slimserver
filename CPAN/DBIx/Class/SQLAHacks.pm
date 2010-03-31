package # Hide from PAUSE
  DBIx::Class::SQLAHacks;

# This module is a subclass of SQL::Abstract::Limit and includes a number
# of DBIC-specific workarounds, not yet suitable for inclusion into the
# SQLA core

use base qw/SQL::Abstract::Limit/;
use strict;
use warnings;
use Carp::Clan qw/^DBIx::Class|^SQL::Abstract/;

BEGIN {
  # reinstall the carp()/croak() functions imported into SQL::Abstract
  # as Carp and Carp::Clan do not like each other much
  no warnings qw/redefine/;
  no strict qw/refs/;
  for my $f (qw/carp croak/) {

    my $orig = \&{"SQL::Abstract::$f"};
    *{"SQL::Abstract::$f"} = sub {

      local $Carp::CarpLevel = 1;   # even though Carp::Clan ignores this, $orig will not

      if (Carp::longmess() =~ /DBIx::Class::SQLAHacks::[\w]+ .+? called \s at/x) {
        __PACKAGE__->can($f)->(@_);
      }
      else {
        $orig->(@_);
      }
    }
  }
}


# Tries to determine limit dialect.
#
sub new {
  my $self = shift->SUPER::new(@_);

  # This prevents the caching of $dbh in S::A::L, I believe
  # If limit_dialect is a ref (like a $dbh), go ahead and replace
  #   it with what it resolves to:
  $self->{limit_dialect} = $self->_find_syntax($self->{limit_dialect})
    if ref $self->{limit_dialect};

  $self;
}

# Some databases (sqlite) do not handle multiple parenthesis
# around in/between arguments. A tentative x IN ( (1, 2 ,3) )
# is interpreted as x IN 1 or something similar.
#
# Since we currently do not have access to the SQLA AST, resort
# to barbaric mutilation of any SQL supplied in literal form
sub _strip_outer_paren {
  my ($self, $arg) = @_;

  return $self->_SWITCH_refkind ($arg, {
    ARRAYREFREF => sub {
      $$arg->[0] = __strip_outer_paren ($$arg->[0]);
      return $arg;
    },
    SCALARREF => sub {
      return \__strip_outer_paren( $$arg );
    },
    FALLBACK => sub {
      return $arg
    },
  });
}

sub __strip_outer_paren {
  my $sql = shift;

  if ($sql and not ref $sql) {
    while ($sql =~ /^ \s* \( (.*) \) \s* $/x ) {
      $sql = $1;
    }
  }

  return $sql;
}

sub _where_field_IN {
  my ($self, $lhs, $op, $rhs) = @_;
  $rhs = $self->_strip_outer_paren ($rhs);
  return $self->SUPER::_where_field_IN ($lhs, $op, $rhs);
}

sub _where_field_BETWEEN {
  my ($self, $lhs, $op, $rhs) = @_;
  $rhs = $self->_strip_outer_paren ($rhs);
  return $self->SUPER::_where_field_BETWEEN ($lhs, $op, $rhs);
}

# Slow but ANSI standard Limit/Offset support. DB2 uses this
sub _RowNumberOver {
  my ($self, $sql, $order, $rows, $offset ) = @_;

  $offset += 1;
  my $last = $rows + $offset - 1;
  my ( $order_by ) = $self->_order_by( $order );

  $sql = <<"SQL";
SELECT * FROM
(
   SELECT Q1.*, ROW_NUMBER() OVER( ) AS ROW_NUM FROM (
      $sql
      $order_by
   ) Q1
) Q2
WHERE ROW_NUM BETWEEN $offset AND $last

SQL

  return $sql;
}

# Crappy Top based Limit/Offset support. MSSQL uses this currently,
# but may have to switch to RowNumberOver one day
sub _Top {
  my ( $self, $sql, $order, $rows, $offset ) = @_;

  # mangle the input sql so it can be properly aliased in the outer queries
  $sql =~ s/^ \s* SELECT \s+ (.+?) \s+ (?=FROM)//ix
    or croak "Unrecognizable SELECT: $sql";
  my $sql_select = $1;
  my @sql_select = split (/\s*,\s*/, $sql_select);

  # we can't support subqueries (in fact MSSQL can't) - croak
  if (@sql_select != @{$self->{_dbic_rs_attrs}{select}}) {
    croak (sprintf (
      'SQL SELECT did not parse cleanly - retrieved %d comma separated elements, while '
    . 'the resultset select attribure contains %d elements: %s',
      scalar @sql_select,
      scalar @{$self->{_dbic_rs_attrs}{select}},
      $sql_select,
    ));
  }

  my $name_sep = $self->name_sep || '.';
  my $esc_name_sep = "\Q$name_sep\E";
  my $col_re = qr/ ^ (?: (.+) $esc_name_sep )? ([^$esc_name_sep]+) $ /x;

  my $rs_alias = $self->{_dbic_rs_attrs}{alias};
  my $quoted_rs_alias = $self->_quote ($rs_alias);

  # construct the new select lists, rename(alias) some columns if necessary
  my (@outer_select, @inner_select, %seen_names, %col_aliases, %outer_col_aliases);

  for (@{$self->{_dbic_rs_attrs}{select}}) {
    next if ref $_;
    my ($table, $orig_colname) = ( $_ =~ $col_re );
    next unless $table;
    $seen_names{$orig_colname}++;
  }

  for my $i (0 .. $#sql_select) {

    my $colsel_arg = $self->{_dbic_rs_attrs}{select}[$i];
    my $colsel_sql = $sql_select[$i];

    # this may or may not work (in case of a scalarref or something)
    my ($table, $orig_colname) = ( $colsel_arg =~ $col_re );

    my $quoted_alias;
    # do not attempt to understand non-scalar selects - alias numerically
    if (ref $colsel_arg) {
      $quoted_alias = $self->_quote ('column_' . (@inner_select + 1) );
    }
    # column name seen more than once - alias it
    elsif ($orig_colname &&
          ($seen_names{$orig_colname} && $seen_names{$orig_colname} > 1) ) {
      $quoted_alias = $self->_quote ("${table}__${orig_colname}");
    }

    # we did rename - make a record and adjust
    if ($quoted_alias) {
      # alias inner
      push @inner_select, "$colsel_sql AS $quoted_alias";

      # push alias to outer
      push @outer_select, $quoted_alias;

      # Any aliasing accumulated here will be considered
      # both for inner and outer adjustments of ORDER BY
      $self->__record_alias (
        \%col_aliases,
        $quoted_alias,
        $colsel_arg,
        $table ? $orig_colname : undef,
      );
    }

    # otherwise just leave things intact inside, and use the abbreviated one outside
    # (as we do not have table names anymore)
    else {
      push @inner_select, $colsel_sql;

      my $outer_quoted = $self->_quote ($orig_colname);  # it was not a duplicate so should just work
      push @outer_select, $outer_quoted;
      $self->__record_alias (
        \%outer_col_aliases,
        $outer_quoted,
        $colsel_arg,
        $table ? $orig_colname : undef,
      );
    }
  }

  my $outer_select = join (', ', @outer_select );
  my $inner_select = join (', ', @inner_select );

  %outer_col_aliases = (%outer_col_aliases, %col_aliases);

  # deal with order
  croak '$order supplied to SQLAHacks limit emulators must be a hash'
    if (ref $order ne 'HASH');

  $order = { %$order }; #copy

  my $req_order = $order->{order_by};

  # examine normalized version, collapses nesting
  my $limit_order;
  if (scalar $self->_order_by_chunks ($req_order)) {
    $limit_order = $req_order;
  }
  else {
    $limit_order = [ map
      { join ('', $rs_alias, $name_sep, $_ ) }
      ( $self->{_dbic_rs_attrs}{_source_handle}->resolve->primary_columns )
    ];
  }

  my ( $order_by_inner, $order_by_outer ) = $self->_order_directions($limit_order);
  my $order_by_requested = $self->_order_by ($req_order);

  # generate the rest
  delete $order->{order_by};
  my $grpby_having = $self->_order_by ($order);

  # short circuit for counts - the ordering complexity is needless
  if ($self->{_dbic_rs_attrs}{-for_count_only}) {
    return "SELECT TOP $rows $inner_select $sql $grpby_having $order_by_outer";
  }

  # we can't really adjust the order_by columns, as introspection is lacking
  # resort to simple substitution
  for my $col (keys %outer_col_aliases) {
    for ($order_by_requested, $order_by_outer) {
      $_ =~ s/\s+$col\s+/ $outer_col_aliases{$col} /g;
    }
  }
  for my $col (keys %col_aliases) {
    $order_by_inner =~ s/\s+$col\s+/ $col_aliases{$col} /g;
  }


  my $inner_lim = $rows + $offset;

  $sql = "SELECT TOP $inner_lim $inner_select $sql $grpby_having $order_by_inner";

  if ($offset) {
    $sql = <<"SQL";

    SELECT TOP $rows $outer_select FROM
    (
      $sql
    ) $quoted_rs_alias
    $order_by_outer
SQL

  }

  if ($order_by_requested) {
    $sql = <<"SQL";

    SELECT $outer_select FROM
      ( $sql ) $quoted_rs_alias
    $order_by_requested
SQL

  }

  $sql =~ s/\s*\n\s*/ /g; # parsing out multiline statements is harder than a single line
  return $sql;
}

# action at a distance to shorten Top code above
sub __record_alias {
  my ($self, $register, $alias, $fqcol, $col) = @_;

  # record qualified name
  $register->{$fqcol} = $alias;
  $register->{$self->_quote($fqcol)} = $alias;

  return unless $col;

  # record unqualified name, undef (no adjustment) if a duplicate is found
  if (exists $register->{$col}) {
    $register->{$col} = undef;
  }
  else {
    $register->{$col} = $alias;
  }

  $register->{$self->_quote($col)} = $register->{$col};
}



# While we're at it, this should make LIMIT queries more efficient,
#  without digging into things too deeply
sub _find_syntax {
  my ($self, $syntax) = @_;
  return $self->{_cached_syntax} ||= $self->SUPER::_find_syntax($syntax);
}

my $for_syntax = {
  update => 'FOR UPDATE',
  shared => 'FOR SHARE',
};
# Quotes table names, handles "limit" dialects (e.g. where rownum between x and
# y), supports SELECT ... FOR UPDATE and SELECT ... FOR SHARE.
sub select {
  my ($self, $table, $fields, $where, $order, @rest) = @_;

  $self->{"${_}_bind"} = [] for (qw/having from order/);

  if (not ref($table) or ref($table) eq 'SCALAR') {
    $table = $self->_quote($table);
  }

  local $self->{rownum_hack_count} = 1
    if (defined $rest[0] && $self->{limit_dialect} eq 'RowNum');
  @rest = (-1) unless defined $rest[0];
  croak "LIMIT 0 Does Not Compute" if $rest[0] == 0;
    # and anyway, SQL::Abstract::Limit will cause a barf if we don't first
  my ($sql, @where_bind) = $self->SUPER::select(
    $table, $self->_recurse_fields($fields), $where, $order, @rest
  );
  if (my $for = delete $self->{_dbic_rs_attrs}{for}) {
    $sql .= " $for_syntax->{$for}" if $for_syntax->{$for};
  }

  return wantarray ? ($sql, @{$self->{from_bind}}, @where_bind, @{$self->{having_bind}}, @{$self->{order_bind}} ) : $sql;
}

# Quotes table names, and handles default inserts
sub insert {
  my $self = shift;
  my $table = shift;
  $table = $self->_quote($table);

  # SQLA will emit INSERT INTO $table ( ) VALUES ( )
  # which is sadly understood only by MySQL. Change default behavior here,
  # until SQLA2 comes with proper dialect support
  if (! $_[0] or (ref $_[0] eq 'HASH' and !keys %{$_[0]} ) ) {
    return "INSERT INTO ${table} DEFAULT VALUES"
  }

  $self->SUPER::insert($table, @_);
}

# Just quotes table names.
sub update {
  my $self = shift;
  my $table = shift;
  $table = $self->_quote($table);
  $self->SUPER::update($table, @_);
}

# Just quotes table names.
sub delete {
  my $self = shift;
  my $table = shift;
  $table = $self->_quote($table);
  $self->SUPER::delete($table, @_);
}

sub _emulate_limit {
  my $self = shift;
  if ($_[3] == -1) {
    return $_[1].$self->_order_by($_[2]);
  } else {
    return $self->SUPER::_emulate_limit(@_);
  }
}

sub _recurse_fields {
  my ($self, $fields, $params) = @_;
  my $ref = ref $fields;
  return $self->_quote($fields) unless $ref;
  return $$fields if $ref eq 'SCALAR';

  if ($ref eq 'ARRAY') {
    return join(', ', map {
      $self->_recurse_fields($_)
        .(exists $self->{rownum_hack_count} && !($params && $params->{no_rownum_hack})
          ? ' AS col'.$self->{rownum_hack_count}++
          : '')
      } @$fields);
  }
  elsif ($ref eq 'HASH') {
    my %hash = %$fields;

    my $as = delete $hash{-as};   # if supplied

    my ($func, $args) = each %hash;
    delete $hash{$func};

    if (lc ($func) eq 'distinct' && ref $args eq 'ARRAY' && @$args > 1) {
      croak (
        'The select => { distinct => ... } syntax is not supported for multiple columns.'
       .' Instead please use { group_by => [ qw/' . (join ' ', @$args) . '/ ] }'
       .' or { select => [ qw/' . (join ' ', @$args) . '/ ], distinct => 1 }'
      );
    }

    my $select = sprintf ('%s( %s )%s',
      $self->_sqlcase($func),
      $self->_recurse_fields($args),
      $as
        ? sprintf (' %s %s', $self->_sqlcase('as'), $as)
        : ''
    );

    # there should be nothing left
    if (keys %hash) {
      croak "Malformed select argument - too many keys in hash: " . join (',', keys %$fields );
    }

    return $select;
  }
  # Is the second check absolutely necessary?
  elsif ( $ref eq 'REF' and ref($$fields) eq 'ARRAY' ) {
    return $self->_fold_sqlbind( $fields );
  }
  else {
    croak($ref . qq{ unexpected in _recurse_fields()})
  }
}

sub _order_by {
  my ($self, $arg) = @_;

  if (ref $arg eq 'HASH' and keys %$arg and not grep { $_ =~ /^-(?:desc|asc)/i } keys %$arg ) {

    my $ret = '';

    if (my $g = $self->_recurse_fields($arg->{group_by}, { no_rownum_hack => 1 }) ) {
      $ret = $self->_sqlcase(' group by ') . $g;
    }

    if (defined $arg->{having}) {
      my ($frag, @bind) = $self->_recurse_where($arg->{having});
      push(@{$self->{having_bind}}, @bind);
      $ret .= $self->_sqlcase(' having ').$frag;
    }

    if (defined $arg->{order_by}) {
      my ($frag, @bind) = $self->SUPER::_order_by($arg->{order_by});
      push(@{$self->{order_bind}}, @bind);
      $ret .= $frag;
    }

    return $ret;
  }
  else {
    my ($sql, @bind) = $self->SUPER::_order_by ($arg);
    push(@{$self->{order_bind}}, @bind);
    return $sql;
  }
}

sub _order_directions {
  my ($self, $order) = @_;

  # strip bind values - none of the current _order_directions users support them
  return $self->SUPER::_order_directions( [ map
    { ref $_ ? $_->[0] : $_ }
    $self->_order_by_chunks ($order)
  ]);
}

sub _table {
  my ($self, $from) = @_;
  if (ref $from eq 'ARRAY') {
    return $self->_recurse_from(@$from);
  } elsif (ref $from eq 'HASH') {
    return $self->_make_as($from);
  } else {
    return $from; # would love to quote here but _table ends up getting called
                  # twice during an ->select without a limit clause due to
                  # the way S::A::Limit->select works. should maybe consider
                  # bypassing this and doing S::A::select($self, ...) in
                  # our select method above. meantime, quoting shims have
                  # been added to select/insert/update/delete here
  }
}

sub _recurse_from {
  my ($self, $from, @join) = @_;
  my @sqlf;
  push(@sqlf, $self->_make_as($from));
  foreach my $j (@join) {
    my ($to, $on) = @$j;


    # check whether a join type exists
    my $to_jt = ref($to) eq 'ARRAY' ? $to->[0] : $to;
    my $join_type;
    if (ref($to_jt) eq 'HASH' and defined($to_jt->{-join_type})) {
      $join_type = $to_jt->{-join_type};
      $join_type =~ s/^\s+ | \s+$//xg;
    }

    $join_type = $self->{_default_jointype} if not defined $join_type;

    my $join_clause = sprintf ('%s JOIN ',
      $join_type ?  ' ' . uc($join_type) : ''
    );
    push @sqlf, $join_clause;

    if (ref $to eq 'ARRAY') {
      push(@sqlf, '(', $self->_recurse_from(@$to), ')');
    } else {
      push(@sqlf, $self->_make_as($to));
    }
    push(@sqlf, ' ON ', $self->_join_condition($on));
  }
  return join('', @sqlf);
}

sub _fold_sqlbind {
  my ($self, $sqlbind) = @_;

  my @sqlbind = @$$sqlbind; # copy
  my $sql = shift @sqlbind;
  push @{$self->{from_bind}}, @sqlbind;

  return $sql;
}

sub _make_as {
  my ($self, $from) = @_;
  return join(' ', map { (ref $_ eq 'SCALAR' ? $$_
                        : ref $_ eq 'REF'    ? $self->_fold_sqlbind($_)
                        : $self->_quote($_))
                       } reverse each %{$self->_skip_options($from)});
}

sub _skip_options {
  my ($self, $hash) = @_;
  my $clean_hash = {};
  $clean_hash->{$_} = $hash->{$_}
    for grep {!/^-/} keys %$hash;
  return $clean_hash;
}

sub _join_condition {
  my ($self, $cond) = @_;
  if (ref $cond eq 'HASH') {
    my %j;
    for (keys %$cond) {
      my $v = $cond->{$_};
      if (ref $v) {
        croak (ref($v) . qq{ reference arguments are not supported in JOINS - try using \"..." instead'})
            if ref($v) ne 'SCALAR';
        $j{$_} = $v;
      }
      else {
        my $x = '= '.$self->_quote($v); $j{$_} = \$x;
      }
    };
    return scalar($self->_recurse_where(\%j));
  } elsif (ref $cond eq 'ARRAY') {
    return join(' OR ', map { $self->_join_condition($_) } @$cond);
  } else {
    die "Can't handle this yet!";
  }
}

sub _quote {
  my ($self, $label) = @_;
  return '' unless defined $label;
  return $$label if ref($label) eq 'SCALAR';
  return "*" if $label eq '*';
  return $label unless $self->{quote_char};
  if(ref $self->{quote_char} eq "ARRAY"){
    return $self->{quote_char}->[0] . $label . $self->{quote_char}->[1]
      if !defined $self->{name_sep};
    my $sep = $self->{name_sep};
    return join($self->{name_sep},
        map { $self->{quote_char}->[0] . $_ . $self->{quote_char}->[1]  }
       split(/\Q$sep\E/,$label));
  }
  return $self->SUPER::_quote($label);
}

sub limit_dialect {
    my $self = shift;
    $self->{limit_dialect} = shift if @_;
    return $self->{limit_dialect};
}

# Set to an array-ref to specify separate left and right quotes for table names.
# A single scalar is equivalen to [ $char, $char ]
sub quote_char {
    my $self = shift;
    $self->{quote_char} = shift if @_;
    return $self->{quote_char};
}

# Character separating quoted table names.
sub name_sep {
    my $self = shift;
    $self->{name_sep} = shift if @_;
    return $self->{name_sep};
}

1;
