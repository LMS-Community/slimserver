
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

    # Return values in the same order, for hashed queries (see below)
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
use vars qw($VERSION %SQL);

$VERSION = do { my @r=(q$Revision: 1.1 $=~/\d+/g); sprintf "%d."."%02d"x$#r,@r };

# Fix SQL case, if so requested
sub _sqlcase {
    my $self = shift;
    return $self->{case} ? $_[0] : uc($_[0]);
}

# Debug
sub _debug {
    return unless $_[0]->{debug}; shift;  # a little faster
    my $func = (caller(1))[3];
    warn "[$func] ", @_, "\n";
}

# Utility functions
sub _table ($) {
    my $tab = shift;
    my $ref = ref $tab || '';
    return ($ref eq 'ARRAY') ? join(', ', @$tab) : $tab;
}

# Conversion, if applicable
sub _convert ($) {
    my $self = shift;
    return @_ unless $self->{convert};
    my $conv = $self->_sqlcase($self->{convert});
    my @ret = map { $conv.'('.$_.')' } @_;
    return wantarray ? @ret : $ret[0];
}

=head2 new(case => 'lower', cmp => 'like', logic => 'and', convert => 'upper')

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
that can be applied symmetrically to fields, actually (B<SQL::Abstract> does not
validate this option; it will just pass through what you specify verbatim).

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

    # default comparison is "=", but can be overridden
    $opt{cmp} ||= '=';

    return bless \%opt, $class;
}

=head2 insert($table, \@values || \%fieldvals)

This is the simplest function. You simply give it a table name
and either an arrayref of values or hashref of field/value pairs.
It returns an SQL INSERT statement and a list of bind values.

=cut

sub insert {
    my $self  = shift;
    my $table = _table(shift);
    my $data  = shift || return;

    my $sql   = $self->_sqlcase('insert into') . " $table ";
    my(@sqlf, @sqlv, @sqlq) = ();

    my $ref = ref $data;
    if ($ref eq 'HASH') {
        for my $k (sort keys %$data) {
            my $v = $data->{$k};
            my $r = ref $v;
            # named fields, so must save names in order
            push @sqlf, $k;
            if ($r eq 'ARRAY') {
                # SQL included for values
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
        $sql .= '(' . join(', ', @sqlf) .') '. $self->_sqlcase('values') . ' ('. join(', ', @sqlq) .')';
    } elsif ($ref eq 'ARRAY') {
        # just generate values(?,?) part
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
        croak "Unsupported data type specified to \$sql->insert";
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
    my $table = _table(shift);
    my $data  = shift || return;
    my $where = shift;

    my $sql   = $self->_sqlcase('update') . " $table " . $self->_sqlcase('set ');
    my(@sqlf, @sqlv) = ();

    croak "Unsupported data type specified to \$sql->update"
        unless ref $data eq 'HASH';

    for my $k (sort keys %$data) {
        my $v = $data->{$k};
        my $r = ref $v;
        if ($r eq 'ARRAY') {
            # SQL included for values
            my @bind = @$v;
            my $sql = shift @bind;
            push @sqlf, "$k = $sql";
            push @sqlv, @bind;
        } elsif ($r eq 'SCALAR') {
            # embedded literal SQL
            push @sqlf, "$k = $$v";
        } else { 
            push @sqlf, "$k = ?";
            push @sqlv, $v;
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
    my $table  = _table(shift);
    my $fields = shift || '*';
    my $where  = shift;
    my $order  = shift;

    my $f = (ref $fields eq 'ARRAY') ? join ', ', @$fields : $fields;
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
    my $table = _table(shift);
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

    # need a separate routine to properly wrap w/ "where"
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
    my $self  = shift;
    my $where = shift;
    my $ref   = ref $where || '';
    my $join  = shift || $self->{logic} ||
                    ($ref eq 'ARRAY' ? $self->_sqlcase('or') : $self->_sqlcase('and'));

    # For assembling SQL fields and values
    my(@sqlf, @sqlv) = ();

    # If an arrayref, then we join each element
    if ($ref eq 'ARRAY') {
        # need to use while() so can shift() for arrays
        while (my $el = shift @$where) {
            my $subjoin = $self->_sqlcase('or');

            # skip empty elements, otherwise get invalid trailing AND stuff
            if (my $ref2 = ref $el) {
                if ($ref2 eq 'ARRAY') {
                    next unless @$el;
                } elsif ($ref2 eq 'HASH') {
                    next unless %$el;
                    $subjoin = $self->_sqlcase('and');
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
        for my $k (sort keys %$where) {
            my $v = $where->{$k};
            if (! defined($v)) {
                # undef = null
                $self->_debug("UNDEF($k) means IS NULL");
                push @sqlf, $k . $self->_sqlcase(' is null');
            } elsif (ref $v eq 'ARRAY') {
                # multiple elements: multiple options
                $self->_debug("ARRAY($k) means multiple elements: [ @$v ]");

                # map into an array of hashrefs and recurse
                my @w = ();
                push @w, { $k => $_ } for @$v;
                my @ret = $self->_recurse_where(\@w, $self->_sqlcase('or'));

                # push results into our structure
                push @sqlf, shift @ret;
                push @sqlv, @ret;
            } elsif (ref $v eq 'HASH') {
                # modified operator { '!=', 'completed' }
                my($f,$x) = each %$v;
                $self->_debug("HASH($k) means modified operator: { $f }");
 
                # check for the operator being "IN" or "BETWEEN" or whatever
                if ($f =~ /^([\s\w]+)$/i && ref $x eq 'ARRAY') {
                    my $u = $self->_sqlcase($1);
                    if ($u =~ /between/i) {
                        # SQL sucks
                        push @sqlf, join ' ', $self->_convert($k), $u, $self->_convert('?'),
                                              $self->_sqlcase('and'), $self->_convert('?');
                    } else {
                        push @sqlf, join ' ', $self->_convert($k), $u, '(',
                                        join(', ', map { $self->_convert('?') } @$x),
                                    ')';
                    }
                    push @sqlv, @$x;
                } elsif (ref $x eq 'ARRAY') {
                    # multiple elements: multiple options
                    $self->_debug("ARRAY($x) means multiple elements: [ @$x ]");

                    # map into an array of hashrefs and recurse
                    my @w = ();
                    push @w, { $k => { $f => $_ } } for @$x;
                    my @ret = $self->_recurse_where(\@w, $self->_sqlcase('or'));

                    # push results into our structure
                    push @sqlf, shift @ret;
                    push @sqlv, @ret;
                } elsif (! defined($x)) {
                    # undef = NOT null
                    my $not = ($f eq '!=' || $f eq 'not like') ? ' not' : '';
                    push @sqlf, $k . $self->_sqlcase(" is$not null");
                } else {
                    push @sqlf, join ' ', $self->_convert($k), $f, $self->_convert('?');
                    push @sqlv, $x;
                }

                keys %$v;   # reset iterator of each()
            } elsif (ref $v eq 'SCALAR') {
                # literal SQL
                $self->_debug("SCALAR($k) means literal SQL: $$v");
                push @sqlf, "$k $$v";
            } else {
                # standard key => val
                $self->_debug("NOREF($k) means simple key=val: $k $self->{cmp} $v");
                push @sqlf, join ' ', $self->_convert($k), $self->_sqlcase($self->{cmp}), $self->_convert('?');
                push @sqlv, $v;
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
    #warn "\@sqlf = '@sqlf'";

    # assemble and return sql
    my $wsql = @sqlf ? '( ' . join(" $join ", @sqlf) . ' )' : '';
    return wantarray ? ($wsql, @sqlv) : $wsql; 
}

sub _order_by {
    my $self = shift;
    my $ref = ref $_[0];
    my $val = undef;
    if ($ref eq 'ARRAY') {
        $val = join(', ', @{$_[0]});
    } elsif ($ref eq 'SCALAR') {
        $val = ${$_[0]};
    } elsif ($ref) {
        croak __PACKAGE__, ": Unsupported data struct $ref for ORDER BY";
    } else {
        # single field
        $val = $_[0];
    }
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
    croak "Argument to ", __PACKAGE__, "->values must be a \\%hash"
        unless ref $data eq 'HASH';
    return map { $data->{$_} } sort keys %$data;
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

Note this is NOT compatible with C<DBIx::Abstract>.

If you want to specify a different type of operator for your comparison,
you can use a hashref:

    my %where  = (
        user   => 'nwiger',
        status => { '!=', 'completed' }
    );

Which would generate:

    $stmt = "WHERE user = ? AND status != ?";
    @bind = ('nwiger', 'completed');

Note that this can be combined with the arrayref idea, to test for
values that are within a range:

    my %where => (
         user => 'nwiger'
         priority  => [ {'>', 3}, {'<', 1} ],
    );

Which would generate:

    $stmt = "WHERE user = ? AND ( priority > ? ) OR ( priority < ? )";
    @bind = ('nwiger', '3', '1');

You can use this same format to compare a list of fields using the
C<IN> comparison operator, by specifying the list as an arrayref:

    my %where  = (
        status   => 'completed',
        reportid => { 'in', [567, 2335, 2] }
    );

Which would generate:

    $stmt = "WHERE status = ? AND reportid IN (?,?,?)";
    @bind = ('completed', '567', '2335', '2');

You can use this same format to use other grouping functions, such
as C<BETWEEN>, C<SOME>, and so forth. For example:

    my %where  = (
        user   => 'nwiger',
        completion_date => {
            'not between', ['2002-10-01', '2003-02-06']
        }
    );

Would give you:

    WHERE user = ? AND completion_date NOT BETWEEN ? AND ?

So far, we've seen how multiple conditions are joined with C<AND>. However,
we can change this by putting the different conditions we want in hashes
and then putting those hashes in an array. For example:

    my @where = (
        {
            user   => 'nwiger',
            status => ['pending', 'dispatched'],
        },
        {
            user   => 'robot',
            status => 'unassigned',
        }
    );

This data structure would create the following:

    $stmt = "WHERE ( user = ? AND ( status = ? OR status = ? ) )
                OR ( user = ? AND status = ? ) )";
    @bind = ('nwiger', 'pending', 'dispatched', 'robot', 'unassigned');

Finally, sometimes only literal SQL will do. If you want to include
literal SQL verbatim, you can specify it as a scalar reference, namely:

    my $inn = 'is not null';
    my %where = (
        priority => { '<', 2 },
        requestor => \$inn
    );

This would create:

    $stmt = "WHERE priority < ? AND requestor is not null";
    @bind = ('2');

Note you only get one bind parameter back, since the verbatim SQL
is passed back as part of the statement.

Of course, just to prove a point, the above can also be accomplished
with this:

    my %where = (
        priority => { '<', 2 },
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
really like this part (I do, at least). Building up a complex
query can be as simple as the following:

    #!/usr/bin/perl

    use CGI::FormBuilder;
    use SQL::Abstract;

    my $form = CGI::FormBuilder->new(...);
    my $sql  = SQL::Abstract->new;

    if ($form->submitted) {
        my $field = $form->field;
        my($stmt, @bind) = $sql->select('table', '*', $field);
    }

Of course, you would still have to connect using C<DBI> to run the
query, but the point is that if you make your form look like your
table, the actual query script can be extremely simplistic.

If you're B<REALLY> lazy (I am), check out C<HTML::QuickTable> for
a fast interface to returning and formatting data. I frequently 
use these three modules together to write complex database query
apps in under 50 lines.

=head1 ACKNOWLEDGEMENTS

There are a number of individuals that have really helped out with
this module. Unfortunately, most of them submitted bugs via CPAN
so I have no idea who they are! But the people I do know are
Mark Stosberg (benchmarking), Chas Owens (initial "IN" operator
support), and Philip Collins (per-field SQL functions). Thanks!

=head1 BUGS

If found, please DO NOT submit anything via C<rt.cpan.org> - that
just causes me a ton of work. Email me a patch (or script demonstrating
the problem) at the below address, and include the VERSION string you'll
be seeing shortly.

=head1 SEE ALSO

L<DBIx::Abstract>, L<DBI|DBI>, L<CGI::FormBuilder>, L<HTML::QuickTable>

=head1 VERSION

$Id: Abstract.pm,v 1.1 2004/08/17 03:34:41 daniel Exp $

=head1 AUTHOR

Copyright (c) 2001-2003 Nathan Wiger <nate@sun.com>. All Rights Reserved.

This module is free software; you may copy this under the terms of
the GNU General Public License, or the Artistic License, copies of
which should have accompanied your Perl kit.

=cut
