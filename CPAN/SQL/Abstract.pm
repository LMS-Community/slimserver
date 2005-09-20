
package SQL::Abstract;

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
    my($stmt, @bind)  = $sql->where(\%where, \@order);

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

In addition, you can apply SQL functions to elements of your C<%data>
by specifying an arrayref for the given hash value. For example, if
you need to execute the Oracle C<to_date> function on a value, you
can say something like this:

    my %data = (
        name => 'Bill',
        date_entered => ["to_date(?,'MM/DD/YYYY')", "03/02/2003"],
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

=cut

use Carp;
use strict;
use vars qw($VERSION $AUTOLOAD);

$VERSION = do { my @r=(q$Revision: 1.20 $=~/\d+/g); sprintf "%d."."%02d"x$#r,@r };

# Fix SQL case, if so requested
sub _sqlcase {
    my $self = shift;
    return $self->{case} ? $_[0] : uc($_[0]);
}

# Anon copies of arrays/hashes
# Based on deep_copy example by merlyn
# http://www.stonehenge.com/merlyn/UnixReview/col30.html
sub _anoncopy {
    my $orig = shift;
    return (ref $orig eq 'HASH')  ? +{map { $_ => _anoncopy($orig->{$_}) } keys %$orig}
         : (ref $orig eq 'ARRAY') ? [map _anoncopy($_), @$orig]
         : $orig;
}

# Debug
sub _debug {
    return unless $_[0]->{debug}; shift;  # a little faster
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

# Utility functions
sub _table  {
    my $self = shift;
    my $tab  = shift;
    if (ref $tab eq 'ARRAY') {
        return join ', ', map { $self->_quote($_) } @$tab;
    } else {
        return $self->_quote($tab);
    }
}

sub _quote {
    my $self  = shift;
    my $label = shift;

    return $label
      if $label eq '*';

    return $self->{quote_char} . $label . $self->{quote_char}
      if !defined $self->{name_sep};

    return join $self->{name_sep},
        map { $self->{quote_char} . $_ . $self->{quote_char}  }
        split /\Q$self->{name_sep}\E/, $label;
}

# Conversion, if applicable
sub _convert ($) {
    my $self = shift;
    return @_ unless $self->{convert};
    my $conv = $self->_sqlcase($self->{convert});
    my @ret = map { $conv.'('.$_.')' } @_;
    return wantarray ? @ret : $ret[0];
}

# And bindtype
sub _bindtype (@) {
    my $self = shift;
    my($col,@val) = @_;
    return $self->{bindtype} eq 'columns' ? [ @_ ] : @val;
}

# Modified -logic or -nest
sub _modlogic ($) {
    my $self = shift;
    my $sym = @_ ? lc(shift) : $self->{logic};
    $sym =~ tr/_/ /;
    $sym = $self->{logic} if $sym eq 'nest';
    return $self->_sqlcase($sym);  # override join
}

=head2 new(option => 'value')

The C<new()> function takes a list of options and values, and returns
a new B<SQL::Abstract> object which can then be used to generate SQL
through the methods below. The options accepted are:

=over

=item case

If set to 'lower', then SQL will be generated in all lowercase. By
default SQL is generated in "textbook" case meaning something like:

    SELECT a_field FROM a_table WHERE some_field LIKE '%someval%'

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

=item logic

This determines the default logical operator for multiple WHERE
statements in arrays. By default it is "or", meaning that a WHERE
array of the form:

    @where = (
        event_date => {'>=', '2/13/99'}, 
        event_date => {'<=', '4/24/03'}, 
    );

Will generate SQL like this:

    WHERE event_date >= '2/13/99' OR event_date <= '4/24/03'

This is probably not what you want given this query, though (look
at the dates). To change the "OR" to an "AND", simply specify:

    my $sql = SQL::Abstract->new(logic => 'and');

Which will change the above C<WHERE> to:

    WHERE event_date >= '2/13/99' AND event_date <= '4/24/03'

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

=item quote_char

This is the character that a table or column name will be quoted
with.  By default this is an empty string, but you could set it to 
the character C<`>, to generate SQL like this:

  SELECT `a_field` FROM `a_table` WHERE `some_field` LIKE '%someval%'

This is useful if you have tables or columns that are reserved words
in your database's SQL dialect.

=item name_sep

This is the character that separates a table and column name.  It is
necessary to specify this when the C<quote_char> option is selected,
so that tables and column names can be individually quoted like this:

  SELECT `table`.`one_field` FROM `table` WHERE `table`.`other_field` = 1

=back

=cut

sub new {
    my $self = shift;
    my $class = ref($self) || $self;
    my %opt = (ref $_[0] eq 'HASH') ? %{$_[0]} : @_;

    # choose our case by keeping an option around
    delete $opt{case} if $opt{case} && $opt{case} ne 'lower';

    # override logical operator
    $opt{logic} = uc $opt{logic} if $opt{logic};

    # how to return bind vars
    $opt{bindtype} ||= delete($opt{bind_type}) || 'normal';

    # default comparison is "=", but can be overridden
    $opt{cmp} ||= '=';

    # default quotation character around tables/columns
    $opt{quote_char} ||= '';

    return bless \%opt, $class;
}

=head2 insert($table, \@values || \%fieldvals)

This is the simplest function. You simply give it a table name
and either an arrayref of values or hashref of field/value pairs.
It returns an SQL INSERT statement and a list of bind values.

=cut

sub insert {
    my $self  = shift;
    my $table = $self->_table(shift);
    my $data  = shift || return;

    my $sql   = $self->_sqlcase('insert into') . " $table ";
    my(@sqlf, @sqlv, @sqlq) = ();

    my $ref = ref $data;
    if ($ref eq 'HASH') {
        for my $k (sort keys %$data) {
            my $v = $data->{$k};
            my $r = ref $v;
            # named fields, so must save names in order
            push @sqlf, $self->_quote($k);
            if ($r eq 'ARRAY') {
                # SQL included for values
                my @val = @$v;
                push @sqlq, shift @val;
                push @sqlv, $self->_bindtype($k, @val);
            } elsif ($r eq 'SCALAR') {
                # embedded literal SQL
                push @sqlq, $$v;
            } else { 
                push @sqlq, '?';
                push @sqlv, $self->_bindtype($k, $v);
            }
        }
        $sql .= '(' . join(', ', @sqlf) .') '. $self->_sqlcase('values') . ' ('. join(', ', @sqlq) .')';
    } elsif ($ref eq 'ARRAY') {
        # just generate values(?,?) part
        # no names (arrayref) so can't generate bindtype
        carp "Warning: ",__PACKAGE__,"->insert called with arrayref when bindtype set"
            if $self->{bindtype} ne 'normal';
        for my $v (@$data) {
            my $r = ref $v;
            if ($r eq 'ARRAY') {
                my @val = @$v;
                push @sqlq, shift @val;
                push @sqlv, @val;
            } elsif ($r eq 'SCALAR') {
                # embedded literal SQL
                push @sqlq, $$v;
            } else { 
                push @sqlq, '?';
                push @sqlv, $v;
            }
        }
        $sql .= $self->_sqlcase('values') . ' ('. join(', ', @sqlq) .')';
    } elsif ($ref eq 'SCALAR') {
        # literal SQL
        $sql .= $$data;
    } else {
        puke "Unsupported data type specified to \$sql->insert";
    }

    return wantarray ? ($sql, @sqlv) : $sql;
}

=head2 update($table, \%fieldvals, \%where)

This takes a table, hashref of field/value pairs, and an optional
hashref WHERE clause. It returns an SQL UPDATE function and a list
of bind values.

=cut

sub update {
    my $self  = shift;
    my $table = $self->_table(shift);
    my $data  = shift || return;
    my $where = shift;

    my $sql   = $self->_sqlcase('update') . " $table " . $self->_sqlcase('set ');
    my(@sqlf, @sqlv) = ();

    puke "Unsupported data type specified to \$sql->update"
        unless ref $data eq 'HASH';

    for my $k (sort keys %$data) {
        my $v = $data->{$k};
        my $r = ref $v;
        my $label = $self->_quote($k);
        if ($r eq 'ARRAY') {
            # SQL included for values
            my @bind = @$v;
            my $sql = shift @bind;
            push @sqlf, "$label = $sql";
            push @sqlv, $self->_bindtype($k, @bind);
        } elsif ($r eq 'SCALAR') {
            # embedded literal SQL
            push @sqlf, "$label = $$v";
        } else { 
            push @sqlf, "$label = ?";
            push @sqlv, $self->_bindtype($k, $v);
        }
    }

    $sql .= join ', ', @sqlf;

    if ($where) {
        my($wsql, @wval) = $self->where($where);
        $sql .= $wsql;
        push @sqlv, @wval;
    }

    return wantarray ? ($sql, @sqlv) : $sql;
}

=head2 select($table, \@fields, \%where, \@order)

This takes a table, arrayref of fields (or '*'), optional hashref
WHERE clause, and optional arrayref order by, and returns the
corresponding SQL SELECT statement and list of bind values.

=cut

sub select {
    my $self   = shift;
    my $table  = $self->_table(shift);
    my $fields = shift || '*';
    my $where  = shift;
    my $order  = shift;

    my $f = (ref $fields eq 'ARRAY') ? join ', ', map { $self->_quote($_) } @$fields : $fields;
    my $sql = join ' ', $self->_sqlcase('select'), $f, $self->_sqlcase('from'), $table;

    my(@sqlf, @sqlv) = ();
    my($wsql, @wval) = $self->where($where, $order);
    $sql .= $wsql;
    push @sqlv, @wval;

    return wantarray ? ($sql, @sqlv) : $sql; 
}

=head2 delete($table, \%where)

This takes a table name and optional hashref WHERE clause.
It returns an SQL DELETE statement and list of bind values.

=cut

sub delete {
    my $self  = shift;
    my $table = $self->_table(shift);
    my $where = shift;

    my $sql = $self->_sqlcase('delete from') . " $table";
    my(@sqlf, @sqlv) = ();

    if ($where) {
        my($wsql, @wval) = $self->where($where);
        $sql .= $wsql;
        push @sqlv, @wval;
    }

    return wantarray ? ($sql, @sqlv) : $sql; 
}

=head2 where(\%where, \@order)

This is used to generate just the WHERE clause. For example,
if you have an arbitrary data structure and know what the
rest of your SQL is going to look like, but want an easy way
to produce a WHERE clause, use this. It returns an SQL WHERE
clause and list of bind values.

=cut

# Finally, a separate routine just to handle WHERE clauses
sub where {
    my $self  = shift;
    my $where = shift;
    my $order = shift;

    # Need a separate routine to properly wrap w/ "where"
    my $sql = '';
    my @ret = $self->_recurse_where($where);
    if (@ret) {
        my $wh = shift @ret;
        $sql .= $self->_sqlcase(' where ') . $wh if $wh;
    }

    # order by?
    if ($order) {
        $sql .= $self->_order_by($order);
    }

    return wantarray ? ($sql, @ret) : $sql; 
}


sub _recurse_where {
    local $^W = 0;  # really, you've gotta be fucking kidding me
    my $self  = shift;
    my $where = _anoncopy(shift);   # prevent destroying original
    my $ref   = ref $where || '';
    my $join  = shift || $self->{logic} ||
                    ($ref eq 'ARRAY' ? $self->_sqlcase('or') : $self->_sqlcase('and'));

    # For assembling SQL fields and values
    my(@sqlf, @sqlv) = ();

    # If an arrayref, then we join each element
    if ($ref eq 'ARRAY') {
        # need to use while() so can shift() for arrays
        my $subjoin;
        while (my $el = shift @$where) {

            # skip empty elements, otherwise get invalid trailing AND stuff
            if (my $ref2 = ref $el) {
                if ($ref2 eq 'ARRAY') {
                    next unless @$el;
                } elsif ($ref2 eq 'HASH') {
                    next unless %$el;
                    $subjoin ||= $self->_sqlcase('and');
                } elsif ($ref2 eq 'SCALAR') {
                    # literal SQL
                    push @sqlf, $$el;
                    next;
                }
                $self->_debug("$ref2(*top) means join with $subjoin");
            } else {
                # top-level arrayref with scalars, recurse in pairs
                $self->_debug("NOREF(*top) means join with $subjoin");
                $el = {$el => shift(@$where)};
            }
            my @ret = $self->_recurse_where($el, $subjoin);
            push @sqlf, shift @ret;
            push @sqlv, @ret;
        }
    }
    elsif ($ref eq 'HASH') {
        # Note: during recursion, the last element will always be a hashref,
        # since it needs to point a column => value. So this be the end.
        for my $k (sort keys %$where) {
            my $v = $where->{$k};
            my $label = $self->_quote($k);
            if ($k =~ /^-(.*)/) {
                # special nesting, like -and, -or, -nest, so shift over
                my $subjoin = $self->_modlogic($1);
                $self->_debug("OP(-$1) means special logic ($subjoin), recursing...");
                my @ret = $self->_recurse_where($v, $subjoin);
                push @sqlf, shift @ret;
                push @sqlv, @ret;
            } elsif (! defined($v)) {
                # undef = null
                $self->_debug("UNDEF($k) means IS NULL");
                push @sqlf, $label . $self->_sqlcase(' is null');
            } elsif (ref $v eq 'ARRAY') {
                my @v = @$v;
                
                # multiple elements: multiple options
                $self->_debug("ARRAY($k) means multiple elements: [ @v ]");

                # special nesting, like -and, -or, -nest, so shift over
                my $subjoin = $self->_sqlcase('or');
                if ($v[0] =~ /^-(.*)/) {
                    $subjoin = $self->_modlogic($1);    # override subjoin
                    $self->_debug("OP(-$1) means special logic ($subjoin), shifting...");
                    shift @v;
                }

                # map into an array of hashrefs and recurse
                my @ret = $self->_recurse_where([map { {$k => $_} } @v], $subjoin);

                # push results into our structure
                push @sqlf, shift @ret;
                push @sqlv, @ret;
            } elsif (ref $v eq 'HASH') {
                # modified operator { '!=', 'completed' }
                for my $f (sort keys %$v) {
                    my $x = $v->{$f};
                    $self->_debug("HASH($k) means modified operator: { $f }");

                    # check for the operator being "IN" or "BETWEEN" or whatever
                    if (ref $x eq 'ARRAY') {
                          if ($f =~ /^-?\s*(not[\s_]+)?(in|between)\s*$/i) {
                              my $u = $self->_modlogic($1 . $2);
                              $self->_debug("HASH($f => $x) uses special operator: [ $u ]");
                              if ($u =~ /between/i) {
                                  # SQL sucks
                                  push @sqlf, join ' ', $self->_convert($label), $u, $self->_convert('?'),
                                                        $self->_sqlcase('and'), $self->_convert('?');
                              } else {
                                  push @sqlf, join ' ', $self->_convert($label), $u, '(',
                                                  join(', ', map { $self->_convert('?') } @$x),
                                              ')';
                              }
                              push @sqlv, $self->_bindtype($k, @$x);
                          } else {
                              # multiple elements: multiple options
                              $self->_debug("ARRAY($x) means multiple elements: [ @$x ]");
                              
                              # map into an array of hashrefs and recurse
                              my @ret = $self->_recurse_where([map { {$k => {$f, $_}} } @$x]);
                              
                              # push results into our structure
                              push @sqlf, shift @ret;
                              push @sqlv, @ret;
                          }
                    } elsif (! defined($x)) {
                        # undef = NOT null
                        my $not = ($f eq '!=' || $f eq 'not like') ? ' not' : '';
                        push @sqlf, $label . $self->_sqlcase(" is$not null");
                    } else {
                        # regular ol' value
                        $f =~ s/^-//;   # strip leading -like =>
                        $f =~ s/_/ /;   # _ => " "
                        push @sqlf, join ' ', $self->_convert($label), $self->_sqlcase($f), $self->_convert('?');
                        push @sqlv, $self->_bindtype($k, $x);
                    }
                }
            } elsif (ref $v eq 'SCALAR') {
                # literal SQL
                $self->_debug("SCALAR($k) means literal SQL: $$v");
                push @sqlf, "$label $$v";
            } else {
                # standard key => val
                $self->_debug("NOREF($k) means simple key=val: $k $self->{cmp} $v");
                push @sqlf, join ' ', $self->_convert($label), $self->_sqlcase($self->{cmp}), $self->_convert('?');
                push @sqlv, $self->_bindtype($k, $v);
            }
        }
    }
    elsif ($ref eq 'SCALAR') {
        # literal sql
        $self->_debug("SCALAR(*top) means literal SQL: $$where");
        push @sqlf, $$where;
    }
    elsif (defined $where) {
        # literal sql
        $self->_debug("NOREF(*top) means literal SQL: $where");
        push @sqlf, $where;
    }

    # assemble and return sql
    my $wsql = @sqlf ? '( ' . join(" $join ", @sqlf) . ' )' : '';
    return wantarray ? ($wsql, @sqlv) : $wsql; 
}

sub _order_by {
    my $self = shift;
    my $ref = ref $_[0];

    my @vals = $ref eq 'ARRAY'  ? @{$_[0]} :
               $ref eq 'SCALAR' ? ${$_[0]} :
               $ref eq ''       ? $_[0]    :
               puke "Unsupported data struct $ref for ORDER BY";

    my $val = join ', ', map { $self->_quote($_) } @vals;
    return $val ? $self->_sqlcase(' order by')." $val" : '';
}

=head2 values(\%data)

This just returns the values from the hash C<%data>, in the same
order that would be returned from any of the other above queries.
Using this allows you to markedly speed up your queries if you
are affecting lots of rows. See below under the L</"PERFORMANCE"> section.

=cut

sub values {
    my $self = shift;
    my $data = shift || return;
    puke "Argument to ", __PACKAGE__, "->values must be a \\%hash"
        unless ref $data eq 'HASH';
    return map { $self->_bindtype($_, $data->{$_}) } sort keys %$data;
}

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

=cut

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
                    # SQL included for values
                    my @bind = @$v;
                    my $sql = shift @bind;
                    push @sqlq, "$label = $sql";
                    push @sqlv, $self->_bindtype($k, @bind);
                } elsif ($r eq 'SCALAR') {
                    # embedded literal SQL
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
                if ($r eq 'ARRAY') {
                    my @val = @$v;
                    push @sqlq, shift @val;
                    push @sqlv, @val;
                } elsif ($r eq 'SCALAR') {
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

=head1 WHERE CLAUSES

This module uses a variation on the idea from L<DBIx::Abstract>. It
is B<NOT>, repeat I<not> 100% compatible. B<The main logic of this
module is that things in arrays are OR'ed, and things in hashes
are AND'ed.>

The easiest way to explain is to show lots of examples. After
each C<%where> hash shown, it is assumed you used:

    my($stmt, @bind) = $sql->where(\%where);

However, note that the C<%where> hash can be used directly in any
of the other functions as well, as described above.

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

    status => { '!=', ['assigned', 'in-progress', 'pending'] };

Which would give you:

    "WHERE status != ? OR status != ? OR status != ?"

But, this is probably not what you want in this case (look at it). So
the hashref can also contain multiple pairs, in which case it is expanded
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

However, there is a subtle trap if you want to say something like
this (notice the C<AND>):

    WHERE priority != ? AND priority != ?

Because, in Perl you I<can't> do this:

    priority => { '!=', 2, '!=', 1 }

As the second C<!=> key will obliterate the first. The solution
is to use the special C<-modifier> form inside an arrayref:

    priority => [ -and => {'!=', 2}, {'!=', 1} ]

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

In addition to C<-and> and C<-or>, there is also a special C<-nest>
operator which adds an additional set of parens, to create a subquery.
For example, to get something like this:

    $stmt = WHERE user = ? AND ( workhrs > ? OR geo = ? )
    @bind = ('nwiger', '20', 'ASIA');

You would do:

    my %where = (
         user => 'nwiger',
        -nest => [ workhrs => {'>', 20}, geo => 'ASIA' ],
    );

You can also use the hashref format to compare a list of fields using the
C<IN> comparison operator, by specifying the list as an arrayref:

    my %where  = (
        status   => 'completed',
        reportid => { -in => [567, 2335, 2] }
    );

Which would generate:

    $stmt = "WHERE status = ? AND reportid IN (?,?,?)";
    @bind = ('completed', '567', '2335', '2');

You can use this same format to use other grouping functions, such
as C<BETWEEN>, C<SOME>, and so forth. For example:

    my %where  = (
        user   => 'nwiger',
        completion_date => {
           -not_between => ['2002-10-01', '2003-02-06']
        }
    );

Would give you:

    WHERE user = ? AND completion_date NOT BETWEEN ( ? AND ? )

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

This can be combined with the C<-nest> operator to properly group
SQL statements:

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

=head1 NOTES

There is not (yet) any explicit support for SQL compound logic
statements like "AND NOT". Instead, just do the de Morgan's
law transformations yourself. For example, this:

  "lname LIKE '%son%' AND NOT ( age < 10 OR age > 20 )"

Becomes:

  "lname LIKE '%son%' AND ( age >= 10 AND age <= 20 )"

With the corresponding C<%where> hash:

    %where = (
        lname => {like => '%son%'},
        age   => [-and => {'>=', 10}, {'<=', 20}],
    );

Again, remember that the C<-and> goes I<inside> the arrayref.

=head1 ACKNOWLEDGEMENTS

There are a number of individuals that have really helped out with
this module. Unfortunately, most of them submitted bugs via CPAN
so I have no idea who they are! But the people I do know are:

    Mark Stosberg (benchmarking)
    Chas Owens (initial "IN" operator support)
    Philip Collins (per-field SQL functions)
    Eric Kolve (hashref "AND" support)
    Mike Fragassi (enhancements to "BETWEEN" and "LIKE")
    Dan Kubb (support for "quote_char" and "name_sep")

Thanks!

=head1 BUGS

If found, please DO NOT submit anything via C<rt.cpan.org> - that
just causes me a ton of work. Email me a patch (or script demonstrating
the problem) to the below address, and include the VERSION string you'll
be seeing shortly.

=head1 SEE ALSO

L<DBIx::Abstract>, L<DBI|DBI>, L<CGI::FormBuilder>, L<HTML::QuickTable>

=head1 VERSION

$Id: Abstract.pm,v 1.20 2005/08/18 18:41:58 nwiger Exp $

=head1 AUTHOR

Copyright (c) 2001-2005 Nathan Wiger <nate@sun.com>. All Rights Reserved.

This module is free software; you may copy this under the terms of
the GNU General Public License, or the Artistic License, copies of
which should have accompanied your Perl kit.

=cut

