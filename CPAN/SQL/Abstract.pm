package SQL::Abstract; # see doc at end of file

# LDNOTE : this code is heavy refactoring from original SQLA.
# Several design decisions will need discussion during
# the test / diffusion / acceptance phase; those are marked with flag
# 'LDNOTE' (note by laurent.dami AT free.fr)

use Carp;
use strict;
use warnings;
use List::Util   qw/first/;
use Scalar::Util qw/blessed/;

#======================================================================
# GLOBALS
#======================================================================

our $VERSION  = '1.56';

# This would confuse some packagers
#$VERSION      = eval $VERSION; # numify for warning-free dev releases

our $AUTOLOAD;

# special operators (-in, -between). May be extended/overridden by user.
# See section WHERE: BUILTIN SPECIAL OPERATORS below for implementation
my @BUILTIN_SPECIAL_OPS = (
  {regex => qr/^(not )?between$/i, handler => '_where_field_BETWEEN'},
  {regex => qr/^(not )?in$/i,      handler => '_where_field_IN'},
);

#======================================================================
# DEBUGGING AND ERROR REPORTING
#======================================================================

sub _debug {
  return unless $_[0]->{debug}; shift; # a little faster
  my $func = (caller(1))[3];
  warn "[$func] ", @_, "\n";
}

sub belch (@) {
  my($func) = (caller(1))[3];
  carp "[$func] Warning: ", @_;
}

sub puke (@) {
  my($func) = (caller(1))[3];
  croak "[$func] Fatal: ", @_;
}


#======================================================================
# NEW
#======================================================================

sub new {
  my $self = shift;
  my $class = ref($self) || $self;
  my %opt = (ref $_[0] eq 'HASH') ? %{$_[0]} : @_;

  # choose our case by keeping an option around
  delete $opt{case} if $opt{case} && $opt{case} ne 'lower';

  # default logic for interpreting arrayrefs
  $opt{logic} = $opt{logic} ? uc $opt{logic} : 'OR';

  # how to return bind vars
  # LDNOTE: changed nwiger code : why this 'delete' ??
  # $opt{bindtype} ||= delete($opt{bind_type}) || 'normal';
  $opt{bindtype} ||= 'normal';

  # default comparison is "=", but can be overridden
  $opt{cmp} ||= '=';

  # try to recognize which are the 'equality' and 'unequality' ops
  # (temporary quickfix, should go through a more seasoned API)
 $opt{equality_op}   = qr/^(\Q$opt{cmp}\E|is|(is\s+)?like)$/i;
 $opt{inequality_op} = qr/^(!=|<>|(is\s+)?not(\s+like)?)$/i;

  # SQL booleans
  $opt{sqltrue}  ||= '1=1';
  $opt{sqlfalse} ||= '0=1';

  # special operators 
  $opt{special_ops} ||= [];
  push @{$opt{special_ops}}, @BUILTIN_SPECIAL_OPS;

  return bless \%opt, $class;
}



#======================================================================
# INSERT methods
#======================================================================

sub insert {
  my $self  = shift;
  my $table = $self->_table(shift);
  my $data  = shift || return;

  my $method       = $self->_METHOD_FOR_refkind("_insert", $data);
  my ($sql, @bind) = $self->$method($data); 
  $sql = join " ", $self->_sqlcase('insert into'), $table, $sql;
  return wantarray ? ($sql, @bind) : $sql;
}

sub _insert_HASHREF { # explicit list of fields and then values
  my ($self, $data) = @_;

  my @fields = sort keys %$data;

  my ($sql, @bind) = $self->_insert_values($data);

  # assemble SQL
  $_ = $self->_quote($_) foreach @fields;
  $sql = "( ".join(", ", @fields).") ".$sql;

  return ($sql, @bind);
}

sub _insert_ARRAYREF { # just generate values(?,?) part (no list of fields)
  my ($self, $data) = @_;

  # no names (arrayref) so can't generate bindtype
  $self->{bindtype} ne 'columns'
    or belch "can't do 'columns' bindtype when called with arrayref";

  # fold the list of values into a hash of column name - value pairs
  # (where the column names are artificially generated, and their
  # lexicographical ordering keep the ordering of the original list)
  my $i = "a";  # incremented values will be in lexicographical order
  my $data_in_hash = { map { ($i++ => $_) } @$data };

  return $self->_insert_values($data_in_hash);
}

sub _insert_ARRAYREFREF { # literal SQL with bind
  my ($self, $data) = @_;

  my ($sql, @bind) = @${$data};
  $self->_assert_bindval_matches_bindtype(@bind);

  return ($sql, @bind);
}


sub _insert_SCALARREF { # literal SQL without bind
  my ($self, $data) = @_;

  return ($$data);
}

sub _insert_values {
  my ($self, $data) = @_;

  my (@values, @all_bind);
  foreach my $column (sort keys %$data) {
    my $v = $data->{$column};

    $self->_SWITCH_refkind($v, {

      ARRAYREF => sub { 
        if ($self->{array_datatypes}) { # if array datatype are activated
          push @values, '?';
          push @all_bind, $self->_bindtype($column, $v);
        }
        else {                          # else literal SQL with bind
          my ($sql, @bind) = @$v;
          $self->_assert_bindval_matches_bindtype(@bind);
          push @values, $sql;
          push @all_bind, @bind;
        }
      },

      ARRAYREFREF => sub { # literal SQL with bind
        my ($sql, @bind) = @${$v};
        $self->_assert_bindval_matches_bindtype(@bind);
        push @values, $sql;
        push @all_bind, @bind;
      },

      # THINK : anything useful to do with a HASHREF ? 
      HASHREF => sub {  # (nothing, but old SQLA passed it through)
        #TODO in SQLA >= 2.0 it will die instead
        belch "HASH ref as bind value in insert is not supported";
        push @values, '?';
        push @all_bind, $self->_bindtype($column, $v);
      },

      SCALARREF => sub {  # literal SQL without bind
        push @values, $$v;
      },

      SCALAR_or_UNDEF => sub {
        push @values, '?';
        push @all_bind, $self->_bindtype($column, $v);
      },

     });

  }

  my $sql = $self->_sqlcase('values')." ( ".join(", ", @values)." )";
  return ($sql, @all_bind);
}



#======================================================================
# UPDATE methods
#======================================================================


sub update {
  my $self  = shift;
  my $table = $self->_table(shift);
  my $data  = shift || return;
  my $where = shift;

  # first build the 'SET' part of the sql statement
  my (@set, @all_bind);
  puke "Unsupported data type specified to \$sql->update"
    unless ref $data eq 'HASH';

  for my $k (sort keys %$data) {
    my $v = $data->{$k};
    my $r = ref $v;
    my $label = $self->_quote($k);

    $self->_SWITCH_refkind($v, {
      ARRAYREF => sub { 
        if ($self->{array_datatypes}) { # array datatype
          push @set, "$label = ?";
          push @all_bind, $self->_bindtype($k, $v);
        }
        else {                          # literal SQL with bind
          my ($sql, @bind) = @$v;
          $self->_assert_bindval_matches_bindtype(@bind);
          push @set, "$label = $sql";
          push @all_bind, @bind;
        }
      },
      ARRAYREFREF => sub { # literal SQL with bind
        my ($sql, @bind) = @${$v};
        $self->_assert_bindval_matches_bindtype(@bind);
        push @set, "$label = $sql";
        push @all_bind, @bind;
      },
      SCALARREF => sub {  # literal SQL without bind
        push @set, "$label = $$v";
       },
      SCALAR_or_UNDEF => sub {
        push @set, "$label = ?";
        push @all_bind, $self->_bindtype($k, $v);
      },
    });
  }

  # generate sql
  my $sql = $self->_sqlcase('update') . " $table " . $self->_sqlcase('set ')
          . join ', ', @set;

  if ($where) {
    my($where_sql, @where_bind) = $self->where($where);
    $sql .= $where_sql;
    push @all_bind, @where_bind;
  }

  return wantarray ? ($sql, @all_bind) : $sql;
}




#======================================================================
# SELECT
#======================================================================


sub select {
  my $self   = shift;
  my $table  = $self->_table(shift);
  my $fields = shift || '*';
  my $where  = shift;
  my $order  = shift;

  my($where_sql, @bind) = $self->where($where, $order);

  my $f = (ref $fields eq 'ARRAY') ? join ', ', map { $self->_quote($_) } @$fields
                                   : $fields;
  my $sql = join(' ', $self->_sqlcase('select'), $f, 
                      $self->_sqlcase('from'),   $table)
          . $where_sql;

  return wantarray ? ($sql, @bind) : $sql; 
}

#======================================================================
# DELETE
#======================================================================


sub delete {
  my $self  = shift;
  my $table = $self->_table(shift);
  my $where = shift;


  my($where_sql, @bind) = $self->where($where);
  my $sql = $self->_sqlcase('delete from') . " $table" . $where_sql;

  return wantarray ? ($sql, @bind) : $sql; 
}


#======================================================================
# WHERE: entry point
#======================================================================



# Finally, a separate routine just to handle WHERE clauses
sub where {
  my ($self, $where, $order) = @_;

  # where ?
  my ($sql, @bind) = $self->_recurse_where($where);
  $sql = $sql ? $self->_sqlcase(' where ') . "( $sql )" : '';

  # order by?
  if ($order) {
    $sql .= $self->_order_by($order);
  }

  return wantarray ? ($sql, @bind) : $sql; 
}


sub _recurse_where {
  my ($self, $where, $logic) = @_;

  # dispatch on appropriate method according to refkind of $where
  my $method = $self->_METHOD_FOR_refkind("_where", $where);


  my ($sql, @bind) =  $self->$method($where, $logic); 

  # DBIx::Class directly calls _recurse_where in scalar context, so 
  # we must implement it, even if not in the official API
  return wantarray ? ($sql, @bind) : $sql; 
}



#======================================================================
# WHERE: top-level ARRAYREF
#======================================================================


sub _where_ARRAYREF {
  my ($self, $where, $logic) = @_;

  $logic = uc($logic || $self->{logic});
  $logic eq 'AND' or $logic eq 'OR' or puke "unknown logic: $logic";

  my @clauses = @$where;

  my (@sql_clauses, @all_bind);
  # need to use while() so can shift() for pairs
  while (my $el = shift @clauses) { 

    # switch according to kind of $el and get corresponding ($sql, @bind)
    my ($sql, @bind) = $self->_SWITCH_refkind($el, {

      # skip empty elements, otherwise get invalid trailing AND stuff
      ARRAYREF  => sub {$self->_recurse_where($el)        if @$el},

      ARRAYREFREF => sub { @{${$el}}                 if @{${$el}}},

      HASHREF   => sub {$self->_recurse_where($el, 'and') if %$el},
           # LDNOTE : previous SQLA code for hashrefs was creating a dirty
           # side-effect: the first hashref within an array would change
           # the global logic to 'AND'. So [ {cond1, cond2}, [cond3, cond4] ]
           # was interpreted as "(cond1 AND cond2) OR (cond3 AND cond4)", 
           # whereas it should be "(cond1 AND cond2) OR (cond3 OR cond4)".

      SCALARREF => sub { ($$el);                                 },

      SCALAR    => sub {# top-level arrayref with scalars, recurse in pairs
                        $self->_recurse_where({$el => shift(@clauses)})},

      UNDEF     => sub {puke "not supported : UNDEF in arrayref" },
    });

    if ($sql) {
      push @sql_clauses, $sql;
      push @all_bind, @bind;
    }
  }

  return $self->_join_sql_clauses($logic, \@sql_clauses, \@all_bind);
}

#======================================================================
# WHERE: top-level ARRAYREFREF
#======================================================================

sub _where_ARRAYREFREF {
    my ($self, $where) = @_;
    my ($sql, @bind) = @{${$where}};

    return ($sql, @bind);
}

#======================================================================
# WHERE: top-level HASHREF
#======================================================================

sub _where_HASHREF {
  my ($self, $where) = @_;
  my (@sql_clauses, @all_bind);

  for my $k (sort keys %$where) { 
    my $v = $where->{$k};

    # ($k => $v) is either a special op or a regular hashpair
    my ($sql, @bind) = ($k =~ /^-(.+)/) ? $self->_where_op_in_hash($1, $v)
                                        : do {
         my $method = $self->_METHOD_FOR_refkind("_where_hashpair", $v);
         $self->$method($k, $v);
       };

    push @sql_clauses, $sql;
    push @all_bind, @bind;
  }

  return $self->_join_sql_clauses('and', \@sql_clauses, \@all_bind);
}


sub _where_op_in_hash {
  my ($self, $op_str, $v) = @_; 

  $op_str =~ /^ (AND|OR|NEST) ( \_? \d* ) $/xi
    or puke "unknown operator: -$op_str";

  my $op = uc($1); # uppercase, remove trailing digits
  if ($2) {
    belch 'Use of [and|or|nest]_N modifiers is deprecated and will be removed in SQLA v2.0. '
          . "You probably wanted ...-and => [ $op_str => COND1, $op_str => COND2 ... ]";
  }

  $self->_debug("OP(-$op) within hashref, recursing...");

  $self->_SWITCH_refkind($v, {

    ARRAYREF => sub {
      return $self->_where_ARRAYREF($v, $op eq 'NEST' ? '' : $op);
    },

    HASHREF => sub {
      if ($op eq 'OR') {
        return $self->_where_ARRAYREF([ map { $_ => $v->{$_} } (sort keys %$v) ], 'OR');
      } 
      else {                  # NEST | AND
        return $self->_where_HASHREF($v);
      }
    },

    SCALARREF  => sub {         # literal SQL
      $op eq 'NEST' 
        or puke "-$op => \\\$scalar not supported, use -nest => ...";
      return ($$v); 
    },

    ARRAYREFREF => sub {        # literal SQL
      $op eq 'NEST' 
        or puke "-$op => \\[..] not supported, use -nest => ...";
      return @{${$v}};
    },

    SCALAR => sub { # permissively interpreted as SQL
      $op eq 'NEST' 
        or puke "-$op => 'scalar' not supported, use -nest => \\'scalar'";
      belch "literal SQL should be -nest => \\'scalar' "
          . "instead of -nest => 'scalar' ";
      return ($v); 
    },

    UNDEF => sub {
      puke "-$op => undef not supported";
    },
   });
}


sub _where_hashpair_ARRAYREF {
  my ($self, $k, $v) = @_;

  if( @$v ) {
    my @v = @$v; # need copy because of shift below
    $self->_debug("ARRAY($k) means distribute over elements");

    # put apart first element if it is an operator (-and, -or)
    my $op = (
       (defined $v[0] && $v[0] =~ /^ - (?: AND|OR ) $/ix)
         ? shift @v
         : ''
    );
    my @distributed = map { {$k =>  $_} } @v;

    if ($op) {
      $self->_debug("OP($op) reinjected into the distributed array");
      unshift @distributed, $op;
    }

    my $logic = $op ? substr($op, 1) : '';

    return $self->_recurse_where(\@distributed, $logic);
  } 
  else {
    # LDNOTE : not sure of this one. What does "distribute over nothing" mean?
    $self->_debug("empty ARRAY($k) means 0=1");
    return ($self->{sqlfalse});
  }
}

sub _where_hashpair_HASHREF {
  my ($self, $k, $v, $logic) = @_;
  $logic ||= 'and';

  my ($all_sql, @all_bind);

  for my $op (sort keys %$v) {
    my $val = $v->{$op};

    # put the operator in canonical form
    $op =~ s/^-//;       # remove initial dash
    $op =~ tr/_/ /;      # underscores become spaces
    $op =~ s/^\s+//;     # no initial space
    $op =~ s/\s+$//;     # no final space
    $op =~ s/\s+/ /;     # multiple spaces become one

    my ($sql, @bind);

    # CASE: special operators like -in or -between
    my $special_op = first {$op =~ $_->{regex}} @{$self->{special_ops}};
    if ($special_op) {
      my $handler = $special_op->{handler};
      if (! $handler) {
        puke "No handler supplied for special operator matching $special_op->{regex}";
      }
      elsif (not ref $handler) {
        ($sql, @bind) = $self->$handler ($k, $op, $val);
      }
      elsif (ref $handler eq 'CODE') {
        ($sql, @bind) = $handler->($self, $k, $op, $val);
      }
      else {
        puke "Illegal handler for special operator matching $special_op->{regex} - expecting a method name or a coderef";
      }
    }
    else {
      $self->_SWITCH_refkind($val, {

        ARRAYREF => sub {       # CASE: col => {op => \@vals}
          ($sql, @bind) = $self->_where_field_op_ARRAYREF($k, $op, $val);
        },

        SCALARREF => sub {      # CASE: col => {op => \$scalar} (literal SQL without bind)
          $sql  = join ' ', $self->_convert($self->_quote($k)),
                            $self->_sqlcase($op),
                            $$val;
        },

        ARRAYREFREF => sub {    # CASE: col => {op => \[$sql, @bind]} (literal SQL with bind)
          my ($sub_sql, @sub_bind) = @$$val;
          $self->_assert_bindval_matches_bindtype(@sub_bind);
          $sql  = join ' ', $self->_convert($self->_quote($k)),
                            $self->_sqlcase($op),
                            $sub_sql;
          @bind = @sub_bind;
        },

        HASHREF => sub {
          ($sql, @bind) = $self->_where_hashpair_HASHREF($k, $val, $op);
        },

        UNDEF => sub {          # CASE: col => {op => undef} : sql "IS (NOT)? NULL"
          my $is = ($op =~ $self->{equality_op})   ? 'is'     :
                   ($op =~ $self->{inequality_op}) ? 'is not' :
               puke "unexpected operator '$op' with undef operand";
          $sql = $self->_quote($k) . $self->_sqlcase(" $is null");
        },
        
        FALLBACK => sub {       # CASE: col => {op => $scalar}
          $sql  = join ' ', $self->_convert($self->_quote($k)),
                            $self->_sqlcase($op),
                            $self->_convert('?');
          @bind = $self->_bindtype($k, $val);
        },
      });
    }

    ($all_sql) = (defined $all_sql and $all_sql) ? $self->_join_sql_clauses($logic, [$all_sql, $sql], []) : $sql;
    push @all_bind, @bind;
  }
  return ($all_sql, @all_bind);
}



sub _where_field_op_ARRAYREF {
  my ($self, $k, $op, $vals) = @_;

  my @vals = @$vals;  #always work on a copy

  if(@vals) {
    $self->_debug("ARRAY($vals) means multiple elements: [ @vals ]");

    # see if the first element is an -and/-or op
    my $logic;
    if ($vals[0] =~ /^ - ( AND|OR ) $/ix) {
      $logic = uc $1;
      shift @vals;
    }

    # distribute $op over each remaining member of @vals, append logic if exists
    return $self->_recurse_where([map { {$k => {$op, $_}} } @vals], $logic);

    # LDNOTE : had planned to change the distribution logic when 
    # $op =~ $self->{inequality_op}, because of Morgan laws : 
    # with {field => {'!=' => [22, 33]}}, it would be ridiculous to generate
    # WHERE field != 22 OR  field != 33 : the user probably means 
    # WHERE field != 22 AND field != 33.
    # To do this, replace the above to roughly :
    # my $logic = ($op =~ $self->{inequality_op}) ? 'AND' : 'OR';
    # return $self->_recurse_where([map { {$k => {$op, $_}} } @vals], $logic);

  } 
  else {
    # try to DWIM on equality operators 
    # LDNOTE : not 100% sure this is the correct thing to do ...
    return ($self->{sqlfalse}) if $op =~ $self->{equality_op};
    return ($self->{sqltrue})  if $op =~ $self->{inequality_op};

    # otherwise
    puke "operator '$op' applied on an empty array (field '$k')";
  }
}


sub _where_hashpair_SCALARREF {
  my ($self, $k, $v) = @_;
  $self->_debug("SCALAR($k) means literal SQL: $$v");
  my $sql = $self->_quote($k) . " " . $$v;
  return ($sql);
}

# literal SQL with bind
sub _where_hashpair_ARRAYREFREF {
  my ($self, $k, $v) = @_;
  $self->_debug("REF($k) means literal SQL: @${$v}");
  my ($sql, @bind) = @${$v};
  $self->_assert_bindval_matches_bindtype(@bind);
  $sql  = $self->_quote($k) . " " . $sql;
  return ($sql, @bind );
}

# literal SQL without bind
sub _where_hashpair_SCALAR {
  my ($self, $k, $v) = @_;
  $self->_debug("NOREF($k) means simple key=val: $k $self->{cmp} $v");
  my $sql = join ' ', $self->_convert($self->_quote($k)), 
                      $self->_sqlcase($self->{cmp}), 
                      $self->_convert('?');
  my @bind =  $self->_bindtype($k, $v);
  return ( $sql, @bind);
}


sub _where_hashpair_UNDEF {
  my ($self, $k, $v) = @_;
  $self->_debug("UNDEF($k) means IS NULL");
  my $sql = $self->_quote($k) . $self->_sqlcase(' is null');
  return ($sql);
}

#======================================================================
# WHERE: TOP-LEVEL OTHERS (SCALARREF, SCALAR, UNDEF)
#======================================================================


sub _where_SCALARREF {
  my ($self, $where) = @_;

  # literal sql
  $self->_debug("SCALAR(*top) means literal SQL: $$where");
  return ($$where);
}


sub _where_SCALAR {
  my ($self, $where) = @_;

  # literal sql
  $self->_debug("NOREF(*top) means literal SQL: $where");
  return ($where);
}


sub _where_UNDEF {
  my ($self) = @_;
  return ();
}


#======================================================================
# WHERE: BUILTIN SPECIAL OPERATORS (-in, -between)
#======================================================================


sub _where_field_BETWEEN {
  my ($self, $k, $op, $vals) = @_;

  (ref $vals eq 'ARRAY' && @$vals == 2) or 
  (ref $vals eq 'REF' && (@$$vals == 1 || @$$vals == 2 || @$$vals == 3))
    or puke "special op 'between' requires an arrayref of two values (or a scalarref or arrayrefref for literal SQL)";

  my ($clause, @bind, $label, $and, $placeholder);
  $label       = $self->_convert($self->_quote($k));
  $and         = ' ' . $self->_sqlcase('and') . ' ';
  $placeholder = $self->_convert('?');
  $op               = $self->_sqlcase($op);

  if (ref $vals eq 'REF') {
    ($clause, @bind) = @$$vals;
  }
  else {
    my (@all_sql, @all_bind);

    foreach my $val (@$vals) {
      my ($sql, @bind) = $self->_SWITCH_refkind($val, {
         SCALAR => sub {
           return ($placeholder, ($val));
         },
         SCALARREF => sub {
           return ($self->_convert($$val), ());
         },
      });
      push @all_sql, $sql;
      push @all_bind, @bind;
    }

    $clause = (join $and, @all_sql);
    @bind = $self->_bindtype($k, @all_bind);
  }
  my $sql = "( $label $op $clause )";
  return ($sql, @bind)
}


sub _where_field_IN {
  my ($self, $k, $op, $vals) = @_;

  # backwards compatibility : if scalar, force into an arrayref
  $vals = [$vals] if defined $vals && ! ref $vals;

  my ($label)       = $self->_convert($self->_quote($k));
  my ($placeholder) = $self->_convert('?');
  $op               = $self->_sqlcase($op);

  my ($sql, @bind) = $self->_SWITCH_refkind($vals, {
    ARRAYREF => sub {     # list of choices
      if (@$vals) { # nonempty list
        my $placeholders  = join ", ", (($placeholder) x @$vals);
        my $sql           = "$label $op ( $placeholders )";
        my @bind = $self->_bindtype($k, @$vals);

        return ($sql, @bind);
      }
      else { # empty list : some databases won't understand "IN ()", so DWIM
        my $sql = ($op =~ /\bnot\b/i) ? $self->{sqltrue} : $self->{sqlfalse};
        return ($sql);
      }
    },

    ARRAYREFREF => sub {  # literal SQL with bind
      my ($sql, @bind) = @$$vals;
      $self->_assert_bindval_matches_bindtype(@bind);
      return ("$label $op ( $sql )", @bind);
    },

    FALLBACK => sub {
      puke "special op 'in' requires an arrayref (or arrayref-ref)";
    },
  });

  return ($sql, @bind);
}






#======================================================================
# ORDER BY
#======================================================================

sub _order_by {
  my ($self, $arg) = @_;

  my (@sql, @bind);
  for my $c ($self->_order_by_chunks ($arg) ) {
    $self->_SWITCH_refkind ($c, {
      SCALAR => sub { push @sql, $c },
      ARRAYREF => sub { push @sql, shift @$c; push @bind, @$c },
    });
  }

  my $sql = @sql
    ? sprintf ('%s %s',
        $self->_sqlcase(' order by'),
        join (', ', @sql)
      )
    : ''
  ;

  return wantarray ? ($sql, @bind) : $sql;
}

sub _order_by_chunks {
  my ($self, $arg) = @_;

  return $self->_SWITCH_refkind($arg, {

    ARRAYREF => sub {
      map { $self->_order_by_chunks ($_ ) } @$arg;
    },

    ARRAYREFREF => sub { [ @$$arg ] },

    SCALAR    => sub {$self->_quote($arg)},

    UNDEF     => sub {return () },

    SCALARREF => sub {$$arg}, # literal SQL, no quoting

    HASHREF   => sub {
      # get first pair in hash
      my ($key, $val) = each %$arg;

      return () unless $key;

      if ( (keys %$arg) > 1 or not $key =~ /^-(desc|asc)/i ) {
        puke "hash passed to _order_by must have exactly one key (-desc or -asc)";
      }

      my $direction = $1;

      my @ret;
      for my $c ($self->_order_by_chunks ($val)) {
        my ($sql, @bind);

        $self->_SWITCH_refkind ($c, {
          SCALAR => sub {
            $sql = $c;
          },
          ARRAYREF => sub {
            ($sql, @bind) = @$c;
          },
        });

        $sql = $sql . ' ' . $self->_sqlcase($direction);

        push @ret, [ $sql, @bind];
      }

      return @ret;
    },
  });
}


#======================================================================
# DATASOURCE (FOR NOW, JUST PLAIN TABLE OR LIST OF TABLES)
#======================================================================

sub _table  {
  my $self = shift;
  my $from = shift;
  $self->_SWITCH_refkind($from, {
    ARRAYREF     => sub {join ', ', map { $self->_quote($_) } @$from;},
    SCALAR       => sub {$self->_quote($from)},
    SCALARREF    => sub {$$from},
    ARRAYREFREF  => sub {join ', ', @$from;},
  });
}


#======================================================================
# UTILITY FUNCTIONS
#======================================================================

sub _quote {
  my $self  = shift;
  my $label = shift;

  $label or puke "can't quote an empty label";

  # left and right quote characters
  my ($ql, $qr, @other) = $self->_SWITCH_refkind($self->{quote_char}, {
    SCALAR   => sub {($self->{quote_char}, $self->{quote_char})},
    ARRAYREF => sub {@{$self->{quote_char}}},
    UNDEF    => sub {()},
   });
  not @other
      or puke "quote_char must be an arrayref of 2 values";

  # no quoting if no quoting chars
  $ql or return $label;

  # no quoting for literal SQL
  return $$label if ref($label) eq 'SCALAR';

  # separate table / column (if applicable)
  my $sep = $self->{name_sep} || '';
  my @to_quote = $sep ? split /\Q$sep\E/, $label : ($label);

  # do the quoting, except for "*" or for `table`.*
  my @quoted = map { $_ eq '*' ? $_: $ql.$_.$qr} @to_quote;

  # reassemble and return. 
  return join $sep, @quoted;
}


# Conversion, if applicable
sub _convert ($) {
  my ($self, $arg) = @_;

# LDNOTE : modified the previous implementation below because
# it was not consistent : the first "return" is always an array,
# the second "return" is context-dependent. Anyway, _convert
# seems always used with just a single argument, so make it a 
# scalar function.
#     return @_ unless $self->{convert};
#     my $conv = $self->_sqlcase($self->{convert});
#     my @ret = map { $conv.'('.$_.')' } @_;
#     return wantarray ? @ret : $ret[0];
  if ($self->{convert}) {
    my $conv = $self->_sqlcase($self->{convert});
    $arg = $conv.'('.$arg.')';
  }
  return $arg;
}

# And bindtype
sub _bindtype (@) {
  my $self = shift;
  my($col, @vals) = @_;

  #LDNOTE : changed original implementation below because it did not make 
  # sense when bindtype eq 'columns' and @vals > 1.
#  return $self->{bindtype} eq 'columns' ? [ $col, @vals ] : @vals;

  return $self->{bindtype} eq 'columns' ? map {[$col, $_]} @vals : @vals;
}

# Dies if any element of @bind is not in [colname => value] format
# if bindtype is 'columns'.
sub _assert_bindval_matches_bindtype {
  my ($self, @bind) = @_;

  if ($self->{bindtype} eq 'columns') {
    foreach my $val (@bind) {
      if (!defined $val || ref($val) ne 'ARRAY' || @$val != 2) {
        die "bindtype 'columns' selected, you need to pass: [column_name => bind_value]"
      }
    }
  }
}

sub _join_sql_clauses {
  my ($self, $logic, $clauses_aref, $bind_aref) = @_;

  if (@$clauses_aref > 1) {
    my $join  = " " . $self->_sqlcase($logic) . " ";
    my $sql = '( ' . join($join, @$clauses_aref) . ' )';
    return ($sql, @$bind_aref);
  }
  elsif (@$clauses_aref) {
    return ($clauses_aref->[0], @$bind_aref); # no parentheses
  }
  else {
    return (); # if no SQL, ignore @$bind_aref
  }
}


# Fix SQL case, if so requested
sub _sqlcase {
  my $self = shift;

  # LDNOTE: if $self->{case} is true, then it contains 'lower', so we
  # don't touch the argument ... crooked logic, but let's not change it!
  return $self->{case} ? $_[0] : uc($_[0]);
}


#======================================================================
# DISPATCHING FROM REFKIND
#======================================================================

sub _refkind {
  my ($self, $data) = @_;
  my $suffix = '';
  my $ref;
  my $n_steps = 0;

  while (1) {
    # blessed objects are treated like scalars
    $ref = (blessed $data) ? '' : ref $data;
    $n_steps += 1 if $ref;
    last          if $ref ne 'REF';
    $data = $$data;
  }

  my $base = $ref || (defined $data ? 'SCALAR' : 'UNDEF');

  return $base . ('REF' x $n_steps);
}



sub _try_refkind {
  my ($self, $data) = @_;
  my @try = ($self->_refkind($data));
  push @try, 'SCALAR_or_UNDEF' if $try[0] eq 'SCALAR' || $try[0] eq 'UNDEF';
  push @try, 'FALLBACK';
  return @try;
}

sub _METHOD_FOR_refkind {
  my ($self, $meth_prefix, $data) = @_;
  my $method = first {$_} map {$self->can($meth_prefix."_".$_)} 
                              $self->_try_refkind($data)
    or puke "cannot dispatch on '$meth_prefix' for ".$self->_refkind($data);
  return $method;
}


sub _SWITCH_refkind {
  my ($self, $data, $dispatch_table) = @_;

  my $coderef = first {$_} map {$dispatch_table->{$_}} 
                               $self->_try_refkind($data)
    or puke "no dispatch entry for ".$self->_refkind($data);
  $coderef->();
}




#======================================================================
# VALUES, GENERATE, AUTOLOAD
#======================================================================

# LDNOTE: original code from nwiger, didn't touch code in that section
# I feel the AUTOLOAD stuff should not be the default, it should
# only be activated on explicit demand by user.

sub values {
    my $self = shift;
    my $data = shift || return;
    puke "Argument to ", __PACKAGE__, "->values must be a \\%hash"
        unless ref $data eq 'HASH';

    my @all_bind;
    foreach my $k ( sort keys %$data ) {
        my $v = $data->{$k};
        $self->_SWITCH_refkind($v, {
          ARRAYREF => sub { 
            if ($self->{array_datatypes}) { # array datatype
              push @all_bind, $self->_bindtype($k, $v);
            }
            else {                          # literal SQL with bind
              my ($sql, @bind) = @$v;
              $self->_assert_bindval_matches_bindtype(@bind);
              push @all_bind, @bind;
            }
          },
          ARRAYREFREF => sub { # literal SQL with bind
            my ($sql, @bind) = @${$v};
            $self->_assert_bindval_matches_bindtype(@bind);
            push @all_bind, @bind;
          },
          SCALARREF => sub {  # literal SQL without bind
          },
          SCALAR_or_UNDEF => sub {
            push @all_bind, $self->_bindtype($k, $v);
          },
        });
    }

    return @all_bind;
}

sub generate {
    my $self  = shift;

    my(@sql, @sqlq, @sqlv);

    for (@_) {
        my $ref = ref $_;
        if ($ref eq 'HASH') {
            for my $k (sort keys %$_) {
                my $v = $_->{$k};
                my $r = ref $v;
                my $label = $self->_quote($k);
                if ($r eq 'ARRAY') {
                    # literal SQL with bind
                    my ($sql, @bind) = @$v;
                    $self->_assert_bindval_matches_bindtype(@bind);
                    push @sqlq, "$label = $sql";
                    push @sqlv, @bind;
                } elsif ($r eq 'SCALAR') {
                    # literal SQL without bind
                    push @sqlq, "$label = $$v";
                } else { 
                    push @sqlq, "$label = ?";
                    push @sqlv, $self->_bindtype($k, $v);
                }
            }
            push @sql, $self->_sqlcase('set'), join ', ', @sqlq;
        } elsif ($ref eq 'ARRAY') {
            # unlike insert(), assume these are ONLY the column names, i.e. for SQL
            for my $v (@$_) {
                my $r = ref $v;
                if ($r eq 'ARRAY') {   # literal SQL with bind
                    my ($sql, @bind) = @$v;
                    $self->_assert_bindval_matches_bindtype(@bind);
                    push @sqlq, $sql;
                    push @sqlv, @bind;
                } elsif ($r eq 'SCALAR') {  # literal SQL without bind
                    # embedded literal SQL
                    push @sqlq, $$v;
                } else { 
                    push @sqlq, '?';
                    push @sqlv, $v;
                }
            }
            push @sql, '(' . join(', ', @sqlq) . ')';
        } elsif ($ref eq 'SCALAR') {
            # literal SQL
            push @sql, $$_;
        } else {
            # strings get case twiddled
            push @sql, $self->_sqlcase($_);
        }
    }

    my $sql = join ' ', @sql;

    # this is pretty tricky
    # if ask for an array, return ($stmt, @bind)
    # otherwise, s/?/shift @sqlv/ to put it inline
    if (wantarray) {
        return ($sql, @sqlv);
    } else {
        1 while $sql =~ s/\?/my $d = shift(@sqlv);
                             ref $d ? $d->[1] : $d/e;
        return $sql;
    }
}


sub DESTROY { 1 }

sub AUTOLOAD {
    # This allows us to check for a local, then _form, attr
    my $self = shift;
    my($name) = $AUTOLOAD =~ /.*::(.+)/;
    return $self->generate($name, @_);
}

1;



__END__

=head1 NAME

SQL::Abstract - Generate SQL from Perl data structures

=head1 SYNOPSIS

    use SQL::Abstract;

    my $sql = SQL::Abstract->new;

    my($stmt, @bind) = $sql->select($table, \@fields, \%where, \@order);

    my($stmt, @bind) = $sql->insert($table, \%fieldvals || \@values);

    my($stmt, @bind) = $sql->update($table, \%fieldvals, \%where);

    my($stmt, @bind) = $sql->delete($table, \%where);

    # Then, use these in your DBI statements
    my $sth = $dbh->prepare($stmt);
    $sth->execute(@bind);

    # Just generate the WHERE clause
    my($stmt, @bind) = $sql->where(\%where, \@order);

    # Return values in the same order, for hashed queries
    # See PERFORMANCE section for more details
    my @bind = $sql->values(\%fieldvals);

=head1 DESCRIPTION

This module was inspired by the excellent L<DBIx::Abstract>.
However, in using that module I found that what I really wanted
to do was generate SQL, but still retain complete control over my
statement handles and use the DBI interface. So, I set out to
create an abstract SQL generation module.

While based on the concepts used by L<DBIx::Abstract>, there are
several important differences, especially when it comes to WHERE
clauses. I have modified the concepts used to make the SQL easier
to generate from Perl data structures and, IMO, more intuitive.
The underlying idea is for this module to do what you mean, based
on the data structures you provide it. The big advantage is that
you don't have to modify your code every time your data changes,
as this module figures it out.

To begin with, an SQL INSERT is as easy as just specifying a hash
of C<key=value> pairs:

    my %data = (
        name => 'Jimbo Bobson',
        phone => '123-456-7890',
        address => '42 Sister Lane',
        city => 'St. Louis',
        state => 'Louisiana',
    );

The SQL can then be generated with this:

    my($stmt, @bind) = $sql->insert('people', \%data);

Which would give you something like this:

    $stmt = "INSERT INTO people
                    (address, city, name, phone, state)
                    VALUES (?, ?, ?, ?, ?)";
    @bind = ('42 Sister Lane', 'St. Louis', 'Jimbo Bobson',
             '123-456-7890', 'Louisiana');

These are then used directly in your DBI code:

    my $sth = $dbh->prepare($stmt);
    $sth->execute(@bind);

=head2 Inserting and Updating Arrays

If your database has array types (like for example Postgres),
activate the special option C<< array_datatypes => 1 >>
when creating the C<SQL::Abstract> object. 
Then you may use an arrayref to insert and update database array types:

    my $sql = SQL::Abstract->new(array_datatypes => 1);
    my %data = (
        planets => [qw/Mercury Venus Earth Mars/]
    );
  
    my($stmt, @bind) = $sql->insert('solar_system', \%data);

This results in:

    $stmt = "INSERT INTO solar_system (planets) VALUES (?)"

    @bind = (['Mercury', 'Venus', 'Earth', 'Mars']);


=head2 Inserting and Updating SQL

In order to apply SQL functions to elements of your C<%data> you may
specify a reference to an arrayref for the given hash value. For example,
if you need to execute the Oracle C<to_date> function on a value, you can
say something like this:

    my %data = (
        name => 'Bill',
        date_entered => \["to_date(?,'MM/DD/YYYY')", "03/02/2003"],
    ); 

The first value in the array is the actual SQL. Any other values are
optional and would be included in the bind values array. This gives
you:

    my($stmt, @bind) = $sql->insert('people', \%data);

    $stmt = "INSERT INTO people (name, date_entered) 
                VALUES (?, to_date(?,'MM/DD/YYYY'))";
    @bind = ('Bill', '03/02/2003');

An UPDATE is just as easy, all you change is the name of the function:

    my($stmt, @bind) = $sql->update('people', \%data);

Notice that your C<%data> isn't touched; the module will generate
the appropriately quirky SQL for you automatically. Usually you'll
want to specify a WHERE clause for your UPDATE, though, which is
where handling C<%where> hashes comes in handy...

=head2 Complex where statements

This module can generate pretty complicated WHERE statements
easily. For example, simple C<key=value> pairs are taken to mean
equality, and if you want to see if a field is within a set
of values, you can use an arrayref. Let's say we wanted to
SELECT some data based on this criteria:

    my %where = (
       requestor => 'inna',
       worker => ['nwiger', 'rcwe', 'sfz'],
       status => { '!=', 'completed' }
    );

    my($stmt, @bind) = $sql->select('tickets', '*', \%where);

The above would give you something like this:

    $stmt = "SELECT * FROM tickets WHERE
                ( requestor = ? ) AND ( status != ? )
                AND ( worker = ? OR worker = ? OR worker = ? )";
    @bind = ('inna', 'completed', 'nwiger', 'rcwe', 'sfz');

Which you could then use in DBI code like so:

    my $sth = $dbh->prepare($stmt);
    $sth->execute(@bind);

Easy, eh?

=head1 FUNCTIONS

The functions are simple. There's one for each major SQL operation,
and a constructor you use first. The arguments are specified in a
similar order to each function (table, then fields, then a where 
clause) to try and simplify things.




=head2 new(option => 'value')

The C<new()> function takes a list of options and values, and returns
a new B<SQL::Abstract> object which can then be used to generate SQL
through the methods below. The options accepted are:

=over

=item case

If set to 'lower', then SQL will be generated in all lowercase. By
default SQL is generated in "textbook" case meaning something like:

    SELECT a_field FROM a_table WHERE some_field LIKE '%someval%'

Any setting other than 'lower' is ignored.

=item cmp

This determines what the default comparison operator is. By default
it is C<=>, meaning that a hash like this:

    %where = (name => 'nwiger', email => 'nate@wiger.org');

Will generate SQL like this:

    WHERE name = 'nwiger' AND email = 'nate@wiger.org'

However, you may want loose comparisons by default, so if you set
C<cmp> to C<like> you would get SQL such as:

    WHERE name like 'nwiger' AND email like 'nate@wiger.org'

You can also override the comparsion on an individual basis - see
the huge section on L</"WHERE CLAUSES"> at the bottom.

=item sqltrue, sqlfalse

Expressions for inserting boolean values within SQL statements.
By default these are C<1=1> and C<1=0>. They are used
by the special operators C<-in> and C<-not_in> for generating
correct SQL even when the argument is an empty array (see below).

=item logic

This determines the default logical operator for multiple WHERE
statements in arrays or hashes. If absent, the default logic is "or"
for arrays, and "and" for hashes. This means that a WHERE
array of the form:

    @where = (
        event_date => {'>=', '2/13/99'}, 
        event_date => {'<=', '4/24/03'}, 
    );

will generate SQL like this:

    WHERE event_date >= '2/13/99' OR event_date <= '4/24/03'

This is probably not what you want given this query, though (look
at the dates). To change the "OR" to an "AND", simply specify:

    my $sql = SQL::Abstract->new(logic => 'and');

Which will change the above C<WHERE> to:

    WHERE event_date >= '2/13/99' AND event_date <= '4/24/03'

The logic can also be changed locally by inserting
a modifier in front of an arrayref :

    @where = (-and => [event_date => {'>=', '2/13/99'}, 
                       event_date => {'<=', '4/24/03'} ]);

See the L</"WHERE CLAUSES"> section for explanations.

=item convert

This will automatically convert comparisons using the specified SQL
function for both column and value. This is mostly used with an argument
of C<upper> or C<lower>, so that the SQL will have the effect of
case-insensitive "searches". For example, this:

    $sql = SQL::Abstract->new(convert => 'upper');
    %where = (keywords => 'MaKe iT CAse inSeNSItive');

Will turn out the following SQL:

    WHERE upper(keywords) like upper('MaKe iT CAse inSeNSItive')

The conversion can be C<upper()>, C<lower()>, or any other SQL function
that can be applied symmetrically to fields (actually B<SQL::Abstract> does
not validate this option; it will just pass through what you specify verbatim).

=item bindtype

This is a kludge because many databases suck. For example, you can't
just bind values using DBI's C<execute()> for Oracle C<CLOB> or C<BLOB> fields.
Instead, you have to use C<bind_param()>:

    $sth->bind_param(1, 'reg data');
    $sth->bind_param(2, $lots, {ora_type => ORA_CLOB});

The problem is, B<SQL::Abstract> will normally just return a C<@bind> array,
which loses track of which field each slot refers to. Fear not.

If you specify C<bindtype> in new, you can determine how C<@bind> is returned.
Currently, you can specify either C<normal> (default) or C<columns>. If you
specify C<columns>, you will get an array that looks like this:

    my $sql = SQL::Abstract->new(bindtype => 'columns');
    my($stmt, @bind) = $sql->insert(...);

    @bind = (
        [ 'column1', 'value1' ],
        [ 'column2', 'value2' ],
        [ 'column3', 'value3' ],
    );

You can then iterate through this manually, using DBI's C<bind_param()>.

    $sth->prepare($stmt);
    my $i = 1;
    for (@bind) {
        my($col, $data) = @$_;
        if ($col eq 'details' || $col eq 'comments') {
            $sth->bind_param($i, $data, {ora_type => ORA_CLOB});
        } elsif ($col eq 'image') {
            $sth->bind_param($i, $data, {ora_type => ORA_BLOB});
        } else {
            $sth->bind_param($i, $data);
        }
        $i++;
    }
    $sth->execute;      # execute without @bind now

Now, why would you still use B<SQL::Abstract> if you have to do this crap?
Basically, the advantage is still that you don't have to care which fields
are or are not included. You could wrap that above C<for> loop in a simple
sub called C<bind_fields()> or something and reuse it repeatedly. You still
get a layer of abstraction over manual SQL specification.

Note that if you set L</bindtype> to C<columns>, the C<\[$sql, @bind]>
construct (see L</Literal SQL with placeholders and bind values (subqueries)>)
will expect the bind values in this format.

=item quote_char

This is the character that a table or column name will be quoted
with.  By default this is an empty string, but you could set it to 
the character C<`>, to generate SQL like this:

  SELECT `a_field` FROM `a_table` WHERE `some_field` LIKE '%someval%'

Alternatively, you can supply an array ref of two items, the first being the left
hand quote character, and the second the right hand quote character. For
example, you could supply C<['[',']']> for SQL Server 2000 compliant quotes
that generates SQL like this:

  SELECT [a_field] FROM [a_table] WHERE [some_field] LIKE '%someval%'

Quoting is useful if you have tables or columns names that are reserved 
words in your database's SQL dialect.

=item name_sep

This is the character that separates a table and column name.  It is
necessary to specify this when the C<quote_char> option is selected,
so that tables and column names can be individually quoted like this:

  SELECT `table`.`one_field` FROM `table` WHERE `table`.`other_field` = 1

=item array_datatypes

When this option is true, arrayrefs in INSERT or UPDATE are 
interpreted as array datatypes and are passed directly 
to the DBI layer.
When this option is false, arrayrefs are interpreted
as literal SQL, just like refs to arrayrefs
(but this behavior is for backwards compatibility; when writing
new queries, use the "reference to arrayref" syntax
for literal SQL).


=item special_ops

Takes a reference to a list of "special operators" 
to extend the syntax understood by L<SQL::Abstract>.
See section L</"SPECIAL OPERATORS"> for details.



=back

=head2 insert($table, \@values || \%fieldvals)

This is the simplest function. You simply give it a table name
and either an arrayref of values or hashref of field/value pairs.
It returns an SQL INSERT statement and a list of bind values.
See the sections on L</"Inserting and Updating Arrays"> and
L</"Inserting and Updating SQL"> for information on how to insert
with those data types.

=head2 update($table, \%fieldvals, \%where)

This takes a table, hashref of field/value pairs, and an optional
hashref L<WHERE clause|/WHERE CLAUSES>. It returns an SQL UPDATE function and a list
of bind values.
See the sections on L</"Inserting and Updating Arrays"> and
L</"Inserting and Updating SQL"> for information on how to insert
with those data types.

=head2 select($source, $fields, $where, $order)

This returns a SQL SELECT statement and associated list of bind values, as 
specified by the arguments  :

=over

=item $source

Specification of the 'FROM' part of the statement. 
The argument can be either a plain scalar (interpreted as a table
name, will be quoted), or an arrayref (interpreted as a list
of table names, joined by commas, quoted), or a scalarref
(literal table name, not quoted), or a ref to an arrayref
(list of literal table names, joined by commas, not quoted).

=item $fields

Specification of the list of fields to retrieve from 
the source.
The argument can be either an arrayref (interpreted as a list
of field names, will be joined by commas and quoted), or a 
plain scalar (literal SQL, not quoted).
Please observe that this API is not as flexible as for
the first argument C<$table>, for backwards compatibility reasons.

=item $where

Optional argument to specify the WHERE part of the query.
The argument is most often a hashref, but can also be
an arrayref or plain scalar -- 
see section L<WHERE clause|/"WHERE CLAUSES"> for details.

=item $order

Optional argument to specify the ORDER BY part of the query.
The argument can be a scalar, a hashref or an arrayref 
-- see section L<ORDER BY clause|/"ORDER BY CLAUSES">
for details.

=back


=head2 delete($table, \%where)

This takes a table name and optional hashref L<WHERE clause|/WHERE CLAUSES>.
It returns an SQL DELETE statement and list of bind values.

=head2 where(\%where, \@order)

This is used to generate just the WHERE clause. For example,
if you have an arbitrary data structure and know what the
rest of your SQL is going to look like, but want an easy way
to produce a WHERE clause, use this. It returns an SQL WHERE
clause and list of bind values.


=head2 values(\%data)

This just returns the values from the hash C<%data>, in the same
order that would be returned from any of the other above queries.
Using this allows you to markedly speed up your queries if you
are affecting lots of rows. See below under the L</"PERFORMANCE"> section.

=head2 generate($any, 'number', $of, \@data, $struct, \%types)

Warning: This is an experimental method and subject to change.

This returns arbitrarily generated SQL. It's a really basic shortcut.
It will return two different things, depending on return context:

    my($stmt, @bind) = $sql->generate('create table', \$table, \@fields);
    my $stmt_and_val = $sql->generate('create table', \$table, \@fields);

These would return the following:

    # First calling form
    $stmt = "CREATE TABLE test (?, ?)";
    @bind = (field1, field2);

    # Second calling form
    $stmt_and_val = "CREATE TABLE test (field1, field2)";

Depending on what you're trying to do, it's up to you to choose the correct
format. In this example, the second form is what you would want.

By the same token:

    $sql->generate('alter session', { nls_date_format => 'MM/YY' });

Might give you:

    ALTER SESSION SET nls_date_format = 'MM/YY'

You get the idea. Strings get their case twiddled, but everything
else remains verbatim.




=head1 WHERE CLAUSES

=head2 Introduction

This module uses a variation on the idea from L<DBIx::Abstract>. It
is B<NOT>, repeat I<not> 100% compatible. B<The main logic of this
module is that things in arrays are OR'ed, and things in hashes
are AND'ed.>

The easiest way to explain is to show lots of examples. After
each C<%where> hash shown, it is assumed you used:

    my($stmt, @bind) = $sql->where(\%where);

However, note that the C<%where> hash can be used directly in any
of the other functions as well, as described above.

=head2 Key-value pairs

So, let's get started. To begin, a simple hash:

    my %where  = (
        user   => 'nwiger',
        status => 'completed'
    );

Is converted to SQL C<key = val> statements:

    $stmt = "WHERE user = ? AND status = ?";
    @bind = ('nwiger', 'completed');

One common thing I end up doing is having a list of values that
a field can be in. To do this, simply specify a list inside of
an arrayref:

    my %where  = (
        user   => 'nwiger',
        status => ['assigned', 'in-progress', 'pending'];
    );

This simple code will create the following:
    
    $stmt = "WHERE user = ? AND ( status = ? OR status = ? OR status = ? )";
    @bind = ('nwiger', 'assigned', 'in-progress', 'pending');

A field associated to an empty arrayref will be considered a 
logical false and will generate 0=1.

=head2 Specific comparison operators

If you want to specify a different type of operator for your comparison,
you can use a hashref for a given column:

    my %where  = (
        user   => 'nwiger',
        status => { '!=', 'completed' }
    );

Which would generate:

    $stmt = "WHERE user = ? AND status != ?";
    @bind = ('nwiger', 'completed');

To test against multiple values, just enclose the values in an arrayref:

    status => { '=', ['assigned', 'in-progress', 'pending'] };

Which would give you:

    "WHERE status = ? OR status = ? OR status = ?"


The hashref can also contain multiple pairs, in which case it is expanded
into an C<AND> of its elements:

    my %where  = (
        user   => 'nwiger',
        status => { '!=', 'completed', -not_like => 'pending%' }
    );

    # Or more dynamically, like from a form
    $where{user} = 'nwiger';
    $where{status}{'!='} = 'completed';
    $where{status}{'-not_like'} = 'pending%';

    # Both generate this
    $stmt = "WHERE user = ? AND status != ? AND status NOT LIKE ?";
    @bind = ('nwiger', 'completed', 'pending%');


To get an OR instead, you can combine it with the arrayref idea:

    my %where => (
         user => 'nwiger',
         priority => [ {'=', 2}, {'!=', 1} ]
    );

Which would generate:

    $stmt = "WHERE user = ? AND priority = ? OR priority != ?";
    @bind = ('nwiger', '2', '1');

If you want to include literal SQL (with or without bind values), just use a
scalar reference or array reference as the value:

    my %where  = (
        date_entered => { '>' => \["to_date(?, 'MM/DD/YYYY')", "11/26/2008"] },
        date_expires => { '<' => \"now()" }
    );

Which would generate:

    $stmt = "WHERE date_entered > "to_date(?, 'MM/DD/YYYY') AND date_expires < now()";
    @bind = ('11/26/2008');


=head2 Logic and nesting operators

In the example above,
there is a subtle trap if you want to say something like
this (notice the C<AND>):

    WHERE priority != ? AND priority != ?

Because, in Perl you I<can't> do this:

    priority => { '!=', 2, '!=', 1 }

As the second C<!=> key will obliterate the first. The solution
is to use the special C<-modifier> form inside an arrayref:

    priority => [ -and => {'!=', 2}, 
                          {'!=', 1} ]


Normally, these would be joined by C<OR>, but the modifier tells it
to use C<AND> instead. (Hint: You can use this in conjunction with the
C<logic> option to C<new()> in order to change the way your queries
work by default.) B<Important:> Note that the C<-modifier> goes
B<INSIDE> the arrayref, as an extra first element. This will
B<NOT> do what you think it might:

    priority => -and => [{'!=', 2}, {'!=', 1}]   # WRONG!

Here is a quick list of equivalencies, since there is some overlap:

    # Same
    status => {'!=', 'completed', 'not like', 'pending%' }
    status => [ -and => {'!=', 'completed'}, {'not like', 'pending%'}]

    # Same
    status => {'=', ['assigned', 'in-progress']}
    status => [ -or => {'=', 'assigned'}, {'=', 'in-progress'}]
    status => [ {'=', 'assigned'}, {'=', 'in-progress'} ]



=head2 Special operators : IN, BETWEEN, etc.

You can also use the hashref format to compare a list of fields using the
C<IN> comparison operator, by specifying the list as an arrayref:

    my %where  = (
        status   => 'completed',
        reportid => { -in => [567, 2335, 2] }
    );

Which would generate:

    $stmt = "WHERE status = ? AND reportid IN (?,?,?)";
    @bind = ('completed', '567', '2335', '2');

The reverse operator C<-not_in> generates SQL C<NOT IN> and is used in 
the same way.

If the argument to C<-in> is an empty array, 'sqlfalse' is generated
(by default : C<1=0>). Similarly, C<< -not_in => [] >> generates
'sqltrue' (by default : C<1=1>).



Another pair of operators is C<-between> and C<-not_between>, 
used with an arrayref of two values:

    my %where  = (
        user   => 'nwiger',
        completion_date => {
           -not_between => ['2002-10-01', '2003-02-06']
        }
    );

Would give you:

    WHERE user = ? AND completion_date NOT BETWEEN ( ? AND ? )

These are the two builtin "special operators"; but the 
list can be expanded : see section L</"SPECIAL OPERATORS"> below.

=head2 Nested conditions, -and/-or prefixes

So far, we've seen how multiple conditions are joined with a top-level
C<AND>.  We can change this by putting the different conditions we want in
hashes and then putting those hashes in an array. For example:

    my @where = (
        {
            user   => 'nwiger',
            status => { -like => ['pending%', 'dispatched'] },
        },
        {
            user   => 'robot',
            status => 'unassigned',
        }
    );

This data structure would create the following:

    $stmt = "WHERE ( user = ? AND ( status LIKE ? OR status LIKE ? ) )
                OR ( user = ? AND status = ? ) )";
    @bind = ('nwiger', 'pending', 'dispatched', 'robot', 'unassigned');


There is also a special C<-nest>
operator which adds an additional set of parens, to create a subquery.
For example, to get something like this:

    $stmt = "WHERE user = ? AND ( workhrs > ? OR geo = ? )";
    @bind = ('nwiger', '20', 'ASIA');

You would do:

    my %where = (
         user => 'nwiger',
        -nest => [ workhrs => {'>', 20}, geo => 'ASIA' ],
    );


Finally, clauses in hashrefs or arrayrefs can be
prefixed with an C<-and> or C<-or> to change the logic
inside :

    my @where = (
         -and => [
            user => 'nwiger',
            -nest => [
                -and => [workhrs => {'>', 20}, geo => 'ASIA' ],
                -and => [workhrs => {'<', 50}, geo => 'EURO' ]
            ],
        ],
    );

That would yield:

    WHERE ( user = ? AND 
          ( ( workhrs > ? AND geo = ? )
         OR ( workhrs < ? AND geo = ? ) ) )


=head2 Algebraic inconsistency, for historical reasons

C<Important note>: when connecting several conditions, the C<-and->|C<-or>
operator goes C<outside> of the nested structure; whereas when connecting
several constraints on one column, the C<-and> operator goes
C<inside> the arrayref. Here is an example combining both features :

   my @where = (
     -and => [a => 1, b => 2],
     -or  => [c => 3, d => 4],
      e   => [-and => {-like => 'foo%'}, {-like => '%bar'} ]
   )

yielding

  WHERE ( (    ( a = ? AND b = ? ) 
            OR ( c = ? OR d = ? ) 
            OR ( e LIKE ? AND e LIKE ? ) ) )

This difference in syntax is unfortunate but must be preserved for
historical reasons. So be careful : the two examples below would
seem algebraically equivalent, but they are not

  {col => [-and => {-like => 'foo%'}, {-like => '%bar'}]} 
  # yields : WHERE ( ( col LIKE ? AND col LIKE ? ) )

  [-and => {col => {-like => 'foo%'}, {col => {-like => '%bar'}}]] 
  # yields : WHERE ( ( col LIKE ? OR col LIKE ? ) )


=head2 Literal SQL

Finally, sometimes only literal SQL will do. If you want to include
literal SQL verbatim, you can specify it as a scalar reference, namely:

    my $inn = 'is Not Null';
    my %where = (
        priority => { '<', 2 },
        requestor => \$inn
    );

This would create:

    $stmt = "WHERE priority < ? AND requestor is Not Null";
    @bind = ('2');

Note that in this example, you only get one bind parameter back, since
the verbatim SQL is passed as part of the statement.

Of course, just to prove a point, the above can also be accomplished
with this:

    my %where = (
        priority  => { '<', 2 },
        requestor => { '!=', undef },
    );


TMTOWTDI.

Conditions on boolean columns can be expressed in the 
same way, passing a reference to an empty string :

    my %where = (
        priority  => { '<', 2 },
        is_ready  => \"";
    );

which yields

    $stmt = "WHERE priority < ? AND is_ready";
    @bind = ('2');


=head2 Literal SQL with placeholders and bind values (subqueries)

If the literal SQL to be inserted has placeholders and bind values,
use a reference to an arrayref (yes this is a double reference --
not so common, but perfectly legal Perl). For example, to find a date
in Postgres you can use something like this:

    my %where = (
       date_column => \[q/= date '2008-09-30' - ?::integer/, 10/]
    )

This would create:

    $stmt = "WHERE ( date_column = date '2008-09-30' - ?::integer )"
    @bind = ('10');

Note that you must pass the bind values in the same format as they are returned
by L</where>. That means that if you set L</bindtype> to C<columns>, you must
provide the bind values in the C<< [ column_meta => value ] >> format, where
C<column_meta> is an opaque scalar value; most commonly the column name, but
you can use any scalar value (including references and blessed references),
L<SQL::Abstract> will simply pass it through intact. So if C<bindtype> is set
to C<columns> the above example will look like:

    my %where = (
       date_column => \[q/= date '2008-09-30' - ?::integer/, [ dummy => 10 ]/]
    )

Literal SQL is especially useful for nesting parenthesized clauses in the
main SQL query. Here is a first example :

  my ($sub_stmt, @sub_bind) = ("SELECT c1 FROM t1 WHERE c2 < ? AND c3 LIKE ?",
                               100, "foo%");
  my %where = (
    foo => 1234,
    bar => \["IN ($sub_stmt)" => @sub_bind],
  );

This yields :

  $stmt = "WHERE (foo = ? AND bar IN (SELECT c1 FROM t1 
                                             WHERE c2 < ? AND c3 LIKE ?))";
  @bind = (1234, 100, "foo%");

Other subquery operators, like for example C<"E<gt> ALL"> or C<"NOT IN">, 
are expressed in the same way. Of course the C<$sub_stmt> and
its associated bind values can be generated through a former call 
to C<select()> :

  my ($sub_stmt, @sub_bind)
     = $sql->select("t1", "c1", {c2 => {"<" => 100}, 
                                 c3 => {-like => "foo%"}});
  my %where = (
    foo => 1234,
    bar => \["> ALL ($sub_stmt)" => @sub_bind],
  );

In the examples above, the subquery was used as an operator on a column;
but the same principle also applies for a clause within the main C<%where> 
hash, like an EXISTS subquery :

  my ($sub_stmt, @sub_bind) 
     = $sql->select("t1", "*", {c1 => 1, c2 => \"> t0.c0"});
  my %where = (
    foo   => 1234,
    -nest => \["EXISTS ($sub_stmt)" => @sub_bind],
  );

which yields

  $stmt = "WHERE (foo = ? AND EXISTS (SELECT * FROM t1 
                                        WHERE c1 = ? AND c2 > t0.c0))";
  @bind = (1234, 1);


Observe that the condition on C<c2> in the subquery refers to 
column C<t0.c0> of the main query : this is I<not> a bind 
value, so we have to express it through a scalar ref. 
Writing C<< c2 => {">" => "t0.c0"} >> would have generated
C<< c2 > ? >> with bind value C<"t0.c0"> ... not exactly
what we wanted here.

Another use of the subquery technique is when some SQL clauses need
parentheses, as it often occurs with some proprietary SQL extensions
like for example fulltext expressions, geospatial expressions, 
NATIVE clauses, etc. Here is an example of a fulltext query in MySQL :

  my %where = (
    -nest => \["MATCH (col1, col2) AGAINST (?)" => qw/apples/]
  );

Finally, here is an example where a subquery is used
for expressing unary negation:

  my ($sub_stmt, @sub_bind) 
     = $sql->where({age => [{"<" => 10}, {">" => 20}]});
  $sub_stmt =~ s/^ where //i; # don't want "WHERE" in the subclause
  my %where = (
        lname  => {like => '%son%'},
        -nest  => \["NOT ($sub_stmt)" => @sub_bind],
    );

This yields

  $stmt = "lname LIKE ? AND NOT ( age < ? OR age > ? )"
  @bind = ('%son%', 10, 20)



=head2 Conclusion

These pages could go on for a while, since the nesting of the data
structures this module can handle are pretty much unlimited (the
module implements the C<WHERE> expansion as a recursive function
internally). Your best bet is to "play around" with the module a
little to see how the data structures behave, and choose the best
format for your data based on that.

And of course, all the values above will probably be replaced with
variables gotten from forms or the command line. After all, if you
knew everything ahead of time, you wouldn't have to worry about
dynamically-generating SQL and could just hardwire it into your
script.




=head1 ORDER BY CLAUSES

Some functions take an order by clause. This can either be a scalar (just a 
column name,) a hash of C<< { -desc => 'col' } >> or C<< { -asc => 'col' } >>,
or an array of either of the two previous forms. Examples:

               Given            |         Will Generate
    ----------------------------------------------------------
                                |
    \'colA DESC'                | ORDER BY colA DESC
                                |
    'colA'                      | ORDER BY colA
                                |
    [qw/colA colB/]             | ORDER BY colA, colB
                                |
    {-asc  => 'colA'}           | ORDER BY colA ASC
                                |
    {-desc => 'colB'}           | ORDER BY colB DESC
                                |
    ['colA', {-asc => 'colB'}]  | ORDER BY colA, colB ASC
                                |
    { -asc => [qw/colA colB] }  | ORDER BY colA ASC, colB ASC
                                |
    [                           |
      { -asc => 'colA' },       | ORDER BY colA ASC, colB DESC,
      { -desc => [qw/colB/],    |          colC ASC, colD ASC
      { -asc => [qw/colC colD/],|
    ]                           |
    ===========================================================



=head1 SPECIAL OPERATORS

  my $sqlmaker = SQL::Abstract->new(special_ops => [
     {
      regex => qr/.../,
      handler => sub {
        my ($self, $field, $op, $arg) = @_;
        ...
      },
     },
     {
      regex => qr/.../,
      handler => 'method_name',
     },
   ]);

A "special operator" is a SQL syntactic clause that can be 
applied to a field, instead of a usual binary operator.
For example : 

   WHERE field IN (?, ?, ?)
   WHERE field BETWEEN ? AND ?
   WHERE MATCH(field) AGAINST (?, ?)

Special operators IN and BETWEEN are fairly standard and therefore
are builtin within C<SQL::Abstract> (as the overridable methods
C<_where_field_IN> and C<_where_field_BETWEEN>). For other operators,
like the MATCH .. AGAINST example above which is specific to MySQL,
you can write your own operator handlers - supply a C<special_ops>
argument to the C<new> method. That argument takes an arrayref of
operator definitions; each operator definition is a hashref with two
entries:

=over

=item regex

the regular expression to match the operator

=item handler

Either a coderef or a plain scalar method name. In both cases
the expected return is C<< ($sql, @bind) >>.

When supplied with a method name, it is simply called on the
L<SQL::Abstract/> object as:

 $self->$method_name ($field, $op, $arg)

 Where:

  $op is the part that matched the handler regex
  $field is the LHS of the operator
  $arg is the RHS

When supplied with a coderef, it is called as:

 $coderef->($self, $field, $op, $arg)


=back

For example, here is an implementation 
of the MATCH .. AGAINST syntax for MySQL

  my $sqlmaker = SQL::Abstract->new(special_ops => [
  
    # special op for MySql MATCH (field) AGAINST(word1, word2, ...)
    {regex => qr/^match$/i, 
     handler => sub {
       my ($self, $field, $op, $arg) = @_;
       $arg = [$arg] if not ref $arg;
       my $label         = $self->_quote($field);
       my ($placeholder) = $self->_convert('?');
       my $placeholders  = join ", ", (($placeholder) x @$arg);
       my $sql           = $self->_sqlcase('match') . " ($label) "
                         . $self->_sqlcase('against') . " ($placeholders) ";
       my @bind = $self->_bindtype($field, @$arg);
       return ($sql, @bind);
       }
     },
  
  ]);


=head1 PERFORMANCE

Thanks to some benchmarking by Mark Stosberg, it turns out that
this module is many orders of magnitude faster than using C<DBIx::Abstract>.
I must admit this wasn't an intentional design issue, but it's a
byproduct of the fact that you get to control your C<DBI> handles
yourself.

To maximize performance, use a code snippet like the following:

    # prepare a statement handle using the first row
    # and then reuse it for the rest of the rows
    my($sth, $stmt);
    for my $href (@array_of_hashrefs) {
        $stmt ||= $sql->insert('table', $href);
        $sth  ||= $dbh->prepare($stmt);
        $sth->execute($sql->values($href));
    }

The reason this works is because the keys in your C<$href> are sorted
internally by B<SQL::Abstract>. Thus, as long as your data retains
the same structure, you only have to generate the SQL the first time
around. On subsequent queries, simply use the C<values> function provided
by this module to return your values in the correct order.


=head1 FORMBUILDER

If you use my C<CGI::FormBuilder> module at all, you'll hopefully
really like this part (I do, at least). Building up a complex query
can be as simple as the following:

    #!/usr/bin/perl

    use CGI::FormBuilder;
    use SQL::Abstract;

    my $form = CGI::FormBuilder->new(...);
    my $sql  = SQL::Abstract->new;

    if ($form->submitted) {
        my $field = $form->field;
        my $id = delete $field->{id};
        my($stmt, @bind) = $sql->update('table', $field, {id => $id});
    }

Of course, you would still have to connect using C<DBI> to run the
query, but the point is that if you make your form look like your
table, the actual query script can be extremely simplistic.

If you're B<REALLY> lazy (I am), check out C<HTML::QuickTable> for
a fast interface to returning and formatting data. I frequently 
use these three modules together to write complex database query
apps in under 50 lines.


=head1 CHANGES

Version 1.50 was a major internal refactoring of C<SQL::Abstract>.
Great care has been taken to preserve the I<published> behavior
documented in previous versions in the 1.* family; however,
some features that were previously undocumented, or behaved 
differently from the documentation, had to be changed in order
to clarify the semantics. Hence, client code that was relying
on some dark areas of C<SQL::Abstract> v1.* 
B<might behave differently> in v1.50.

The main changes are :

=over

=item * 

support for literal SQL through the C<< \ [$sql, bind] >> syntax.

=item *

support for the { operator => \"..." } construct (to embed literal SQL)

=item *

support for the { operator => \["...", @bind] } construct (to embed literal SQL with bind values)

=item *

optional support for L<array datatypes|/"Inserting and Updating Arrays">

=item * 

defensive programming : check arguments

=item *

fixed bug with global logic, which was previously implemented
through global variables yielding side-effects. Prior versions would
interpret C<< [ {cond1, cond2}, [cond3, cond4] ] >>
as C<< "(cond1 AND cond2) OR (cond3 AND cond4)" >>.
Now this is interpreted
as C<< "(cond1 AND cond2) OR (cond3 OR cond4)" >>.


=item *

fixed semantics of  _bindtype on array args

=item * 

dropped the C<_anoncopy> of the %where tree. No longer necessary,
we just avoid shifting arrays within that tree.

=item *

dropped the C<_modlogic> function

=back



=head1 ACKNOWLEDGEMENTS

There are a number of individuals that have really helped out with
this module. Unfortunately, most of them submitted bugs via CPAN
so I have no idea who they are! But the people I do know are:

    Ash Berlin (order_by hash term support) 
    Matt Trout (DBIx::Class support)
    Mark Stosberg (benchmarking)
    Chas Owens (initial "IN" operator support)
    Philip Collins (per-field SQL functions)
    Eric Kolve (hashref "AND" support)
    Mike Fragassi (enhancements to "BETWEEN" and "LIKE")
    Dan Kubb (support for "quote_char" and "name_sep")
    Guillermo Roditi (patch to cleanup "IN" and "BETWEEN", fix and tests for _order_by)
    Laurent Dami (internal refactoring, multiple -nest, extensible list of special operators, literal SQL)
    Norbert Buchmuller (support for literal SQL in hashpair, misc. fixes & tests)
    Peter Rabbitson (rewrite of SQLA::Test, misc. fixes & tests)

Thanks!

=head1 SEE ALSO

L<DBIx::Class>, L<DBIx::Abstract>, L<CGI::FormBuilder>, L<HTML::QuickTable>.

=head1 AUTHOR

Copyright (c) 2001-2007 Nathan Wiger <nwiger@cpan.org>. All Rights Reserved.

This module is actively maintained by Matt Trout <mst@shadowcatsystems.co.uk>

For support, your best bet is to try the C<DBIx::Class> users mailing list.
While not an official support venue, C<DBIx::Class> makes heavy use of
C<SQL::Abstract>, and as such list members there are very familiar with
how to create queries.

=head1 LICENSE

This module is free software; you may copy this under the terms of
the GNU General Public License, or the Artistic License, copies of
which should have accompanied your Perl kit.

=cut

