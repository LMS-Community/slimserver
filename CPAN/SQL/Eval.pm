# -*- perl -*-

require 5.004;
use strict;

require SQL::Statement;

package SQL::Eval;

sub new ($$) {
    my($proto, $attr) = @_;
    my($self) = { %$attr };
    bless($self, (ref($proto) || $proto));
    $self;
}

sub param ($$;$) {
    my($self, $paramNum, $param) = @_;
    if (@_ == 3) {
	$self->{'params'}->[$paramNum] = $param;
    } else {
	if ($paramNum < 0) {
	    die "Illegal parameter number: $paramNum";
	}
	$self->{'params'}->[$paramNum];
    }
}

sub params ($;$) {
    my($self, $array) = @_;
    if (@_ == 2) {
	$self->{'params'} = $array;
    } else {
	$self->{'params'};
    }
}


sub table ($$) {
    my($self, $table) = @_;
    $self->{'tables'}->{$table};
}

sub column ($$$;$) {
    my($self, $table, $column, $val) = @_;
    if (@_ == 4) {
	$self->table($table)->column($column, $val);
    } else {
	$self->table($table)->column($column);
    }
}


package SQL::Eval::Table;

sub new ($$) {
    my($proto, $attr) = @_;
    my($self) = { %$attr };
    bless($self, (ref($proto) || $proto));
    $self;
}

sub row ($;$) {
    my($self, $row) = @_;
    if (@_ == 2) {
	$self->{'row'} = $row;
    } else {
	$self->{'row'};
    }
}

sub column ($$;$) {
    my($self, $column, $val) = @_;
    if (@_ == 3) {
	$self->{'row'}->[$self->{'col_nums'}->{$column}] = $val;
    } else {
	$self->{'row'}->[$self->{'col_nums'}->{$column}];
    }
}

sub column_num ($$) {
    my($self, $col) = @_;
    $self->{'col_nums'}->{$col};
}

sub col_names ($) {
    shift->{'col_names'};
}

1;


__END__

=head1 NAME

SQL::Eval - Base for deriving evalution objects for SQL::Statement


=head1 SYNOPSIS

    require SQL::Statement;
    require SQL::Eval;

    # Create an SQL statement; use a concrete subclass of
    # SQL::Statement
    my $stmt = MyStatement->new("SELECT * FROM foo, bar",
			        SQL::Parser->new('Ansi'));

    # Get an eval object by calling open_tables; this
    # will call MyStatement::open_table
    my $eval = $stmt->open_tables($data);

    # Set parameter 0 to 'Van Gogh'
    $eval->param(0, 'Van Gogh');
    # Get parameter 2
    my $param = $eval->param(2);

    # Get the SQL::Eval::Table object referring the 'foo' table
    my $fooTable = $eval->table('foo');


=head1 DESCRIPTION

This module implements two classes that can be used for deriving
concrete subclasses to evaluate SQL::Statement objects. The
SQL::Eval object can be thought as an abstract state engine for
executing SQL queries, the SQL::Eval::Table object can be considered
a *very* table abstraction. It implements method for fetching or
storing rows, retrieving column names and numbers and so on.
See the C<test.pl> script as an example for implementing a concrete
subclass.

While reading on, keep in mind that these are abstract classes,
you *must* implement at least some of the methods describe below.
Even more, you need not derive from SQL::Eval or SQL::Eval::Table,
you just need to implement the method interface.

All methods just throw a Perl exception in case of errors.


=head2 Method interface of SQL::Eval

=over 8

=item new

Constructor; use it like this:

    $eval = SQL::Eval->new(\%attr);

Blesses the hash ref \%attr into the SQL::Eval class (or a subclass).

=item param

Used for getting or setting input parameters, as in the SQL query

    INSERT INTO foo VALUES (?, ?);

Example:

    $eval->param(0, $val);        # Set parameter 0
    $eval->param(0);              # Get parameter 0

=item params

Likewise used for getting or setting the complete array of input
parameters. Example:

    $eval->params($params);       # Set the array
    $eval->params();              # Get the array

=item table

Returns or sets a table object. Example:

    $eval->table('foo', $fooTable);  # Set the 'foo' table object
    $eval->table('foo');             # Return the 'foo' table object

=item column

Return the value of a column with a given name; example:

    $col = $eval->column('foo', 'id');  # Return the 'id' column of
                                        # the current row in the
                                        # 'foo' table

This is equivalent and just a shorthand for

    $col = $eval->table('foo')->column('id');

=back


=head2 Method interface of SQL::Eval::Table

=over 8

=item new

Constructor; use it like this:

    $eval = SQL::Eval::Table->new(\%attr);

Blesses the hash ref \%attr into the SQL::Eval::Table class (or a
subclass).

=item row

Used to get the current row as an array ref. Do not mismatch
getting the current row with the fetch_row method! In fact this
method is valid only after a successfull C<$table-E<gt>fetchrow()>.
Example:

    $row = $table->row();

=item column

Get the column with a given name in the current row. Valid only after
a successfull C<$table-E<gt>fetchrow()>. Example:

    $col = $table->column($colName);

=item column_num

Return the number of the given column name. Column numbers start with
0. Returns undef, if a column name is not defined, so that you can
well use this for verifying valid column names. Example:

    $colNum = $table->column_num($colNum);

=item column_names

Returns an array ref of column names.

=back

The above methods are implemented by SQL::Eval::Table. The following
methods aren't, so that they *must* be implemented by concrete
subclassed. See the C<test.pl> script for example.

=over 8

=item fetch_row

Fetches the next row from the table. Returns C<undef>, if the last
row was already fetched. The argument $data is for private use of
the concrete subclass. Example:

    $row = $table->fetch_row($data);

Note, that you may use

    $row = $table->row();

for retrieving the same row again, until the next call of C<fetch_row>.

=item push_row

Likewise for storing rows. Example:

    $table->push_row($data, $row);

=item push_names

Used by the I<CREATE TABLE> statement to set the column names of the
new table. Receives an array ref of names. Example:

    $table->push_names($data, $names);

=item seek

Similar to the seek method of a filehandle; used for setting the number
of the next row being written. Example:

    $table->seek($data, $whence, $rowNum);

Actually the current implementation is using only C<seek($data, 0,0)>
(first row) and C<seek($data, 2,0)> (last row, end of file).

=item truncate

Truncates a table after the current row. Example:

    $table->truncate($data);

=back


=head1 INTERNALS

The current implementation is quite simple: An SQL::Eval object is an
hash ref with only two attributes. The C<params> attribute is an array
ref of parameters. The C<tables> attribute is an hash ref of table
names (keys) and table objects (values).

SQL::Eval::Table instances are implemented as hash refs. Used attributes
are C<row> (the array ref of the current row), C<col_nums> (an hash ref
of column names as keys and column numbers as values) and C<col_names>,
an array ref of column names with the column numbers as indexes.


=head1 MULTITHREADING

All methods are working with instance-local data only, thus the module
is reentrant and thread safe, if you either don't share handles between
threads or grant serialized use.


=head1 AUTHOR AND COPYRIGHT

This module is Copyright (C) 1998 by

    Jochen Wiedmann
    Am Eisteich 9
    72555 Metzingen
    Germany

    Email: joe@ispsoft.de
    Phone: +49 7123 14887

All rights reserved.

You may distribute this module under the terms of either the GNU
General Public License or the Artistic License, as specified in
the Perl README file.


=head1 SEE ALSO

L<SQL::Statement(3)>


=cut
