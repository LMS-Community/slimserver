package # Hide from PAUSE
  DBIx::Class::SQLAHacks;

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

      if (Carp::longmess() =~ /DBIx::Class::SQLAHacks::[\w]+\(\) called/) {
        __PACKAGE__->can($f)->(@_);
      }
      else {
        $orig->(@_);
      }
    }
  }
}

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
# around in/between arguments. A tentative x IN ( ( 1, 2 ,3) )
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

  croak '$order supplied to SQLAHacks limit emulators must be a hash'
    if (ref $order ne 'HASH');

  $order = { %$order }; #copy

  my $last = $rows + $offset;

  my $req_order = $self->_order_by ($order->{order_by});

  my $limit_order = $req_order ? $order->{order_by} : $order->{_virtual_order_by};

  delete $order->{$_} for qw/order_by _virtual_order_by/;
  my $grpby_having = $self->_order_by ($order);

  my ( $order_by_inner, $order_by_outer ) = $self->_order_directions($limit_order);

  $sql =~ s/^\s*(SELECT|select)//;

  $sql = <<"SQL";
  SELECT * FROM
  (
    SELECT TOP $rows * FROM
    (
        SELECT TOP $last $sql $grpby_having $order_by_inner
    ) AS foo
    $order_by_outer
  ) AS bar
  $req_order

SQL
    return $sql;
}



# While we're at it, this should make LIMIT queries more efficient,
#  without digging into things too deeply
sub _find_syntax {
  my ($self, $syntax) = @_;
  return $self->{_cached_syntax} ||= $self->SUPER::_find_syntax($syntax);
}

sub select {
  my ($self, $table, $fields, $where, $order, @rest) = @_;

  $self->{"${_}_bind"} = [] for (qw/having from order/);

  if (ref $table eq 'SCALAR') {
    $table = $$table;
  }
  elsif (not ref $table) {
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
  $sql .= 
    $self->{for} ?
    (
      $self->{for} eq 'update' ? ' FOR UPDATE' :
      $self->{for} eq 'shared' ? ' FOR SHARE'  :
      ''
    ) :
    ''
  ;
  return wantarray ? ($sql, @{$self->{from_bind}}, @where_bind, @{$self->{having_bind}}, @{$self->{order_bind}} ) : $sql;
}

sub insert {
  my $self = shift;
  my $table = shift;
  $table = $self->_quote($table) unless ref($table);

  # SQLA will emit INSERT INTO $table ( ) VALUES ( )
  # which is sadly understood only by MySQL. Change default behavior here,
  # until SQLA2 comes with proper dialect support
  if (! $_[0] or (ref $_[0] eq 'HASH' and !keys %{$_[0]} ) ) {
    return "INSERT INTO ${table} DEFAULT VALUES"
  }

  $self->SUPER::insert($table, @_);
}

sub update {
  my $self = shift;
  my $table = shift;
  $table = $self->_quote($table) unless ref($table);
  $self->SUPER::update($table, @_);
}

sub delete {
  my $self = shift;
  my $table = shift;
  $table = $self->_quote($table) unless ref($table);
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
  } elsif ($ref eq 'HASH') {
    foreach my $func (keys %$fields) {
      if ($func eq 'distinct') {
        my $_fields = $fields->{$func};
        if (ref $_fields eq 'ARRAY' && @{$_fields} > 1) {
          croak (
            'The select => { distinct => ... } syntax is not supported for multiple columns.'
           .' Instead please use { group_by => [ qw/' . (join ' ', @$_fields) . '/ ] }'
           .' or { select => [ qw/' . (join ' ', @$_fields) . '/ ], distinct => 1 }'
          );
        }
        else {
          $_fields = @{$_fields}[0] if ref $_fields eq 'ARRAY';
          carp (
            'The select => { distinct => ... } syntax will be deprecated in DBIC version 0.09,'
           ." please use { group_by => '${_fields}' } or { select => '${_fields}', distinct => 1 }"
          );
        }
      }
      return $self->_sqlcase($func)
        .'( '.$self->_recurse_fields($fields->{$func}).' )';
    }
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

    if (defined $arg->{group_by}) {
      $ret = $self->_sqlcase(' group by ')
        .$self->_recurse_fields($arg->{group_by}, { no_rownum_hack => 1 });
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
    my $join_clause = '';
    my $to_jt = ref($to) eq 'ARRAY' ? $to->[0] : $to;
    if (ref($to_jt) eq 'HASH' and exists($to_jt->{-join_type})) {
      $join_clause = ' '.uc($to_jt->{-join_type}).' JOIN ';
    } else {
      $join_clause = ' JOIN ';
    }
    push(@sqlf, $join_clause);

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

sub quote_char {
    my $self = shift;
    $self->{quote_char} = shift if @_;
    return $self->{quote_char};
}

sub name_sep {
    my $self = shift;
    $self->{name_sep} = shift if @_;
    return $self->{name_sep};
}

1;

__END__

=pod

=head1 NAME

DBIx::Class::SQLAHacks - This module is a subclass of SQL::Abstract::Limit
and includes a number of DBIC-specific workarounds, not yet suitable for
inclusion into SQLA proper.

=head1 METHODS

=head2 new

Tries to determine limit dialect.

=head2 select

Quotes table names, handles "limit" dialects (e.g. where rownum between x and
y), supports SELECT ... FOR UPDATE and SELECT ... FOR SHARE.

=head2 insert update delete

Just quotes table names.

=head2 limit_dialect

Specifies the dialect of used for implementing an SQL "limit" clause for
restricting the number of query results returned.  Valid values are: RowNum.

See L<DBIx::Class::Storage::DBI/connect_info> for details.

=head2 name_sep

Character separating quoted table names.

See L<DBIx::Class::Storage::DBI/connect_info> for details.

=head2 quote_char

Set to an array-ref to specify separate left and right quotes for table names.

See L<DBIx::Class::Storage::DBI/connect_info> for details.

=cut

