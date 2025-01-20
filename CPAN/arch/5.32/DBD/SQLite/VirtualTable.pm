#======================================================================
package DBD::SQLite::VirtualTable;
#======================================================================
use strict;
use warnings;
use Scalar::Util    qw/weaken/;

our $VERSION = '1.76';
our @ISA;


#----------------------------------------------------------------------
# methods for registering/destroying the module
#----------------------------------------------------------------------

sub CREATE_MODULE  { my ($class, $mod_name) = @_; }
sub DESTROY_MODULE { my ($class, $mod_name) = @_; }

#----------------------------------------------------------------------
# methods for creating/destroying instances
#----------------------------------------------------------------------

sub CREATE         { my $class = shift; return $class->NEW(@_); }
sub CONNECT        { my $class = shift; return $class->NEW(@_); }

sub _PREPARE_SELF {
  my ($class, $dbh_ref, $module_name, $db_name, $vtab_name, @args) = @_;

  my @columns;
  my %options;

  # args containing '=' are options; others are column declarations
  foreach my $arg (@args) {
    if ($arg =~ /^([^=\s]+)\s*=\s*(.*)/) {
      my ($key, $val) = ($1, $2);
      $val =~ s/^"(.*)"$/$1/;
      $options{$key} = $val;
    }
    else {
      push @columns, $arg;
    }
  }

  # build $self
  my $self =  {
    dbh_ref     => $dbh_ref,
    module_name => $module_name,
    db_name     => $db_name,
    vtab_name   => $vtab_name,
    columns     => \@columns,
    options     => \%options,
   };
  weaken $self->{dbh_ref};

  return $self;
}

sub NEW {
  my $class = shift;

  my $self  = $class->_PREPARE_SELF(@_);
  bless $self, $class;
}


sub VTAB_TO_DECLARE {
  my $self = shift;

  local $" = ", ";
  my $sql = "CREATE TABLE $self->{vtab_name}(@{$self->{columns}})";

  return $sql;
}

sub DROP       { my $self = shift; }
sub DISCONNECT { my $self = shift; }


#----------------------------------------------------------------------
# methods for initiating a search
#----------------------------------------------------------------------

sub BEST_INDEX {
  my ($self, $constraints, $order_by) = @_;

  my $ix = 0;
  foreach my $constraint (grep {$_->{usable}} @$constraints) {
    $constraint->{argvIndex} = $ix++;
    $constraint->{omit}      = 0;
  }

  # stupid default values -- subclasses should put real values instead
  my $outputs = {
    idxNum           => 1,
    idxStr           => "",
    orderByConsumed  => 0,
    estimatedCost    => 1.0,
    estimatedRows    => undef,
   };

  return $outputs;
}


sub OPEN {
  my $self  = shift;
  my $class = ref $self;

  my $cursor_class = $class . "::Cursor";
  return $cursor_class->NEW($self, @_);
}


#----------------------------------------------------------------------
# methods for insert/delete/update
#----------------------------------------------------------------------

sub _SQLITE_UPDATE {
  my ($self, $old_rowid, $new_rowid, @values) = @_;

  if (! defined $old_rowid) {
    return $self->INSERT($new_rowid, @values);
  }
  elsif (!@values) {
    return $self->DELETE($old_rowid);
  }
  else {
    return $self->UPDATE($old_rowid, $new_rowid, @values);
  }
}

sub INSERT {
  my ($self, $new_rowid, @values) = @_;

  die "INSERT() should be redefined in subclass";
}

sub DELETE {
  my ($self, $old_rowid) = @_;

  die "DELETE() should be redefined in subclass";
}

sub UPDATE {
  my ($self, $old_rowid, $new_rowid, @values) = @_;

  die "UPDATE() should be redefined in subclass";
}

#----------------------------------------------------------------------
# remaining methods of the sqlite API
#----------------------------------------------------------------------

sub BEGIN_TRANSACTION    {return 0}
sub SYNC_TRANSACTION     {return 0}
sub COMMIT_TRANSACTION   {return 0}
sub ROLLBACK_TRANSACTION {return 0}
sub SAVEPOINT            {return 0}
sub RELEASE              {return 0}
sub ROLLBACK_TO          {return 0}
sub FIND_FUNCTION        {return 0}
sub RENAME               {return 0}


#----------------------------------------------------------------------
# utility methods
#----------------------------------------------------------------------

sub dbh {
  my $self = shift;
  return ${$self->{dbh_ref}};
}


sub sqlite_table_info {
  my $self = shift;

  my $sql = "PRAGMA table_info($self->{vtab_name})";
  return $self->dbh->selectall_arrayref($sql, {Slice => {}});
}

#======================================================================
package DBD::SQLite::VirtualTable::Cursor;
#======================================================================
use strict;
use warnings;

sub NEW {
  my ($class, $vtable, @args) = @_;
  my $self = {vtable => $vtable,
              args   => \@args};
  bless $self, $class;
}


sub FILTER {
  my ($self, $idxNum, $idxStr, @values) = @_;
  die "FILTER() should be redefined in cursor subclass";
}

sub EOF {
  my ($self) = @_;
  die "EOF() should be redefined in cursor subclass";
}

sub NEXT {
  my ($self) = @_;
  die "NEXT() should be redefined in cursor subclass";
}

sub COLUMN {
  my ($self, $idxCol) = @_;
  die "COLUMN() should be redefined in cursor subclass";
}

sub ROWID {
  my ($self) = @_;
  die "ROWID() should be redefined in cursor subclass";
}


1;

__END__

=head1 NAME

DBD::SQLite::VirtualTable -- SQLite virtual tables implemented in Perl

=head1 SYNOPSIS

  # register the virtual table module within sqlite
  $dbh->sqlite_create_module(mod_name => "DBD::SQLite::VirtualTable::Subclass");

  # create a virtual table
  $dbh->do("CREATE VIRTUAL TABLE vtbl USING mod_name(arg1, arg2, ...)")

  # use it as any regular table
  my $sth = $dbh->prepare("SELECT * FROM vtbl WHERE ...");

B<Note> : VirtualTable subclasses or instances are not called
directly from Perl code; everything happens indirectly through SQL
statements within SQLite.


=head1 DESCRIPTION

This module is an abstract class for implementing SQLite virtual tables,
written in Perl. Such tables look like regular tables, and are accessed
through regular SQL instructions and regular L<DBI> API; but the implementation
is done through hidden calls to a Perl class. 
This is the same idea as Perl's L<tied variables|perltie>, but
at the SQLite level.

The current abstract class cannot be used directly, so the
synopsis above is just to give a general idea. Concrete, usable
classes bundled with the present distribution are :

=over 

=item *

L<DBD::SQLite::VirtualTable::FileContent> : implements a virtual
column that exposes file contents. This is especially useful
in conjunction with a fulltext index; see L<DBD::SQLite::Fulltext_search>.

=item *

L<DBD::SQLite::VirtualTable::PerlData> : binds to a Perl array
within the Perl program. This can be used for simple import/export
operations, for debugging purposes, for joining data from different
sources, etc.

=back

Other Perl virtual tables may also be published separately on CPAN.

The following chapters document the structure of the abstract class
and explain how to write new subclasses; this is meant for 
B<module authors>, not for end users. If you just need to use a
virtual table module, refer to that module's documentation.


=head1 ARCHITECTURE

=head2 Classes

A virtual table module for SQLite is implemented through a pair
of classes :

=over

=item *

the B<table> class implements methods for creating or connecting
a virtual table, for destroying it, for opening new searches, etc.

=item *

the B<cursor> class implements methods for performing a specific
SQL statement

=back


=head2 Methods

Most methods in both classes are not called directly from Perl
code : instead, they are callbacks, called from the sqlite kernel.
Following common Perl conventions, such methods have names in
uppercase.


=head1 TABLE METHODS

=head2 Class methods for registering the module

=head3 CREATE_MODULE

  $class->CREATE_MODULE($sqlite_module_name);

Called when the client code invokes

  $dbh->sqlite_create_module($sqlite_module_name => $class);

The default implementation is empty.


=head3 DESTROY_MODULE

  $class->DESTROY_MODULE();

Called automatically when the database handle is disconnected.
The default implementation is empty.


=head2 Class methods for creating a vtable instance


=head3 CREATE

  $class->CREATE($dbh_ref, $module_name, $db_name, $vtab_name, @args);

Called when sqlite receives a statement

  CREATE VIRTUAL TABLE $db_name.$vtab_name USING $module_name(@args)

The default implementation just calls L</NEW>.

=head3 CONNECT

  $class->CONNECT($dbh_ref, $module_name, $db_name, $vtab_name, @args);

Called when attempting to access a virtual table that had been created
during previous database connection. The creation arguments were stored
within the sqlite database and are passed again to the CONNECT method.

The default implementation just calls L</NEW>.


=head3 _PREPARE_SELF

  $class->_PREPARE_SELF($dbh_ref, $module_name, $db_name, $vtab_name, @args);

Prepares the datastructure for a virtual table instance.  C<@args> is
 just the collection of strings (comma-separated) that were given
 within the C<CREATE VIRTUAL TABLE> statement; each subclass should
 decide what to do with this information,

The method parses C<@args> to differentiate between I<options>
(strings of shape C<$key>=C<$value> or C<$key>=C<"$value">, stored in
C<< $self->{options} >>), and I<columns> (other C<@args>, stored in
C<< $self->{columns} >>). It creates a hashref with the following fields :

=over

=item C<dbh_ref>

a weak reference to the C<$dbh> database handle (see
L<Scalar::Util> for an explanation of weak references).

=item C<module_name>

name of the module as declared to sqlite (not to be confounded
with the Perl class name).

=item C<db_name>

name of the database (usuallly C<'main'> or C<'temp'>), but it
may also be an attached database

=item C<vtab_name>

name of the virtual table

=item C<columns>

arrayref of column declarations

=item C<options>

hashref of option declarations

=back

This method should not be redefined, since it performs
general work which is supposed to be useful for all subclasses.
Instead, subclasses may override the L</NEW> method.


=head3 NEW

  $class->NEW($dbh_ref, $module_name, $db_name, $vtab_name, @args);

Instantiates a virtual table.


=head2 Instance methods called from the sqlite kernel


=head3 DROP

Called whenever a virtual table is destroyed from the
database through the C<DROP TABLE> SQL instruction.

Just after the C<DROP()> call, the Perl instance
will be destroyed (and will therefore automatically
call the C<DESTROY()> method if such a method is present).

The default implementation for DROP is empty.

B<Note> : this corresponds to the C<xDestroy> method
in the SQLite documentation; here it was not named
C<DESTROY>, to avoid any confusion with the standard
Perl method C<DESTROY> for object destruction.


=head3 DISCONNECT

Called for every virtual table just before the database handle
is disconnected.

Just after the C<DISCONNECT()> call, the Perl instance
will be destroyed (and will therefore automatically
call the C<DESTROY()> method if such a method is present).

The default implementation for DISCONNECT is empty.

=head3 VTAB_TO_DECLARE

This method is called automatically just after L</CREATE> or L</CONNECT>,
to register the columns of the virtual table within the sqlite kernel.
The method should return a string containing a SQL C<CREATE TABLE> statement;
but only the column declaration parts will be considered.
Columns may be declared with the special keyword "HIDDEN", which means that
they are used internally for the the virtual table implementation, and are
not visible to users -- see L<http://sqlite.org/c3ref/declare_vtab.html>
and L<http://www.sqlite.org/vtab.html#hiddencol> for detailed explanations.

The default implementation returns:

  CREATE TABLE $self->{vtab_name}(@{$self->{columns}})

=head3 BEST_INDEX

  my $index_info = $vtab->BEST_INDEX($constraints, $order_by)

This is the most complex method to redefined in subclasses.
This method will be called at the beginning of a new query on the
virtual table; the job of the method is to assemble some information
that will be used

=over

=item a)

by the sqlite kernel to decide about the best search strategy

=item b)

by the cursor L</FILTER> method to produce the desired subset
of rows from the virtual table.

=back

By calling this method, the SQLite core is saying to the virtual table
that it needs to access some subset of the rows in the virtual table
and it wants to know the most efficient way to do that access. The
C<BEST_INDEX> method replies with information that the SQLite core can
then use to conduct an efficient search of the virtual table.

The method takes as input a list of C<$constraints> and a list
of C<$order_by> instructions. It returns a hashref of indexing
properties, described below; furthermore, the method also adds
supplementary information within the input C<$constraints>.
Detailed explanations are given in
L<http://sqlite.org/vtab.html#xbestindex>.

=head4 Input constraints

Elements of the C<$constraints> arrayref correspond to
specific clauses of the C<WHERE ...> part of the SQL query.
Each constraint is a hashref with keys :

=over

=item C<col>

the integer index of the column on the left-hand side of the constraint

=item C<op>

the comparison operator, expressed as string containing
C<< '=' >>, C<< '>' >>, C<< '>=' >>, C<< '<' >>, C<< '<=' >> or C<< 'MATCH' >>.

=item C<usable>

a boolean indicating if that constraint is usable; some constraints
might not be usable because of the way tables are ordered in a join.

=back

The C<$constraints> arrayref is used both for input and for output.
While iterating over the array, the method should
add the following keys into usable constraints :

=over

=item C<argvIndex>

An index into the C<@values> array that will be passed to
the cursor's L</FILTER> method. In other words, if the current
constraint corresponds to the SQL fragment C<WHERE ... AND foo < 123 ...>,
and the corresponding C<argvIndex> takes value 5, this means that
the C<FILTER> method will receive C<123> in C<$values[5]>.

=item C<omit>

A boolean telling to the sqlite core that it can safely omit
to double check that constraint before returning the resultset
to the calling program; this means that the FILTER method has fulfilled
the filtering job on that constraint and there is no need to do any
further checking.

=back

The C<BEST_INDEX> method will not necessarily receive all constraints
from the SQL C<WHERE> clause : for example a constraint like
C<< col1 < col2 + col3 >> cannot be handled at this level.
Furthemore, the C<BEST_INDEX> might decide to ignore some of the 
received constraints. This is why a second pass over the results
will be performed by the sqlite core.


=head4 "order_by" input information

The C<$order_by> arrayref corresponds to the C<ORDER BY> clauses
in the SQL query. Each entry is a hashref with keys :

=over

=item C<col>

the integer index of the column being ordered

=item C<desc>

a boolean telling of the ordering is DESCending or ascending

=back

This information could be used by some subclasses for
optimizing the query strategfy; but usually the sqlite core will
perform another sorting pass once all results are gathered.

=head4 Hashref information returned by BEST_INDEX

The method should return a hashref with the following keys : 

=over

=item C<idxNum>

An arbitrary integer associated with that index; this information will
be passed back to L</FILTER>.

=item C<idxStr>

An arbitrary str associated with that index; this information will
be passed back to L</FILTER>.

=item C<orderByConsumed>

A boolean telling the sqlite core if the C<$order_by> information
has been taken into account or not.

=item C<estimatedCost>

A float that should be set to the estimated number of disk access
operations required to execute this query against the virtual
table. The SQLite core will often call BEST_INDEX multiple times with
different constraints, obtain multiple cost estimates, then choose the
query plan that gives the lowest estimate.

=item C<estimatedRows>

An integer giving the estimated number of rows returned by that query.

=back



=head3 OPEN

Called to instantiate a new cursor.
The default implementation appends C<"::Cursor"> to the current
classname and calls C<NEW()> within that cursor class.

=head3 _SQLITE_UPDATE

This is the dispatch method implementing the C<xUpdate()> callback
for virtual tables. The default implementation applies the algorithm
described in L<http://sqlite.org/vtab.html#xupdate> to decide
to call L</INSERT>, L</DELETE> or L</UPDATE>; so there is no reason
to override this method in subclasses.

=head3 INSERT

  my $rowid = $vtab->INSERT($new_rowid, @values);

This method should be overridden in subclasses to implement
insertion of a new row into the virtual table.
The size of the C<@values> array corresponds to the
number of columns declared through L</VTAB_TO_DECLARE>.
The C<$new_rowid> may be explicitly given, or it may be
C<undef>, in which case the method must compute a new id
and return it as the result of the method call.

=head3 DELETE

  $vtab->INSERT($old_rowid);

This method should be overridden in subclasses to implement
deletion of a row from the virtual table.

=head3 UPDATE

  $vtab->UPDATE($old_rowid, $new_rowid, @values);

This method should be overridden in subclasses to implement
a row update within the virtual table. Usually C<$old_rowid> is equal
to C<$new_rowid>, which is a regular update; however, the rowid
could be changed from a SQL statement such as

  UPDATE table SET rowid=rowid+1 WHERE ...; 

=head3 FIND_FUNCTION

  $vtab->FIND_FUNCTION($num_args, $func_name);

When a function uses a column from a virtual table as its first
argument, this method is called to see if the virtual table would like
to overload the function. Parameters are the number of arguments to
the function, and the name of the function. If no overloading is
desired, this method should return false. To overload the function,
this method should return a coderef to the function implementation.

Each virtual table keeps a cache of results from L<FIND_FUNCTION> calls,
so the method will be called only once for each pair 
C<< ($num_args, $func_name) >>.


=head3 BEGIN_TRANSACTION

Called to begin a transaction on the virtual table.

=head3 SYNC_TRANSACTION

Called to signal the start of a two-phase commit on the virtual table.

=head3 SYNC_TRANSACTION

Called to commit a virtual table transaction.

=head3 ROLLBACK_TRANSACTION

Called to rollback a virtual table transaction.

=head3 RENAME

  $vtab->RENAME($new_name)

Called to rename a virtual table.

=head3 SAVEPOINT

  $vtab->SAVEPOINT($savepoint)

Called to signal the virtual table to save its current state
at savepoint C<$savepoint> (an integer).

=head3 ROLLBACK_TO

  $vtab->ROLLBACK_TO($savepoint)

Called to signal the virtual table to return to the state
C<$savepoint>.  This will invalidate all savepoints with values
greater than C<$savepoint>.

=head3 RELEASE

  $vtab->RELEASE($savepoint)

Called to invalidate all savepoints with values
greater or equal to C<$savepoint>.


=head2 Utility instance methods

Methods in this section are in lower case, because they
are not called directly from the sqlite kernel; these
are utility methods to be called from other methods
described above.

=head3 dbh

This method returns the database handle (C<$dbh>) associated with
the current virtual table.


=head1 CURSOR METHODS

=head2 Class methods

=head3 NEW

  my $cursor = $cursor_class->NEW($vtable, @args)

Instantiates a new cursor. 
The default implementation just returns a blessed hashref
with keys C<vtable> and C<args>.

=head2 Instance methods

=head3 FILTER

  $cursor->FILTER($idxNum, $idxStr, @values);

This method begins a search of a virtual table.

The C<$idxNum> and C<$idxStr> arguments correspond to values returned
by L</BEST_INDEX> for the chosen index. The specific meanings of
those values are unimportant to SQLite, as long as C<BEST_INDEX> and
C<FILTER> agree on what that meaning is.

The C<BEST_INDEX> method may have requested the values of certain
expressions using the C<argvIndex> values of the
C<$constraints> list. Those values are passed to C<FILTER> through
the C<@values> array.

If the virtual table contains one or more rows that match the search
criteria, then the cursor must be left point at the first
row. Subsequent calls to L</EOF> must return false. If there are
no rows match, then the cursor must be left in a state that will cause
L</EOF> to return true. The SQLite engine will use the
L</COLUMN> and L</ROWID> methods to access that row content. The L</NEXT>
method will be used to advance to the next row.


=head3 EOF

This method must return false if the cursor currently points to a
valid row of data, or true otherwise. This method is called by the SQL
engine immediately after each L</FILTER> and L</NEXT> invocation.

=head3 NEXT

This method advances the cursor to the next row of a
result set initiated by L</FILTER>. If the cursor is already pointing at
the last row when this method is called, then the cursor no longer
points to valid data and a subsequent call to the L</EOF> method must
return true. If the cursor is successfully advanced to
another row of content, then subsequent calls to L</EOF> must return
false.

=head3 COLUMN

  my $value = $cursor->COLUMN($idxCol);

The SQLite core invokes this method in order to find the value for the
N-th column of the current row. N is zero-based so the first column is
numbered 0.

=head3 ROWID

  my $value = $cursor->ROWID;

Returns the I<rowid> of row that the cursor is currently pointing at.


=head1 SEE ALSO

L<SQLite::VirtualTable> is another module for virtual tables written
in Perl, but designed for the reverse use case : instead of starting a
Perl program, and embedding the SQLite library into it, the intended
use is to start an sqlite program, and embed the Perl interpreter
into it.

=head1 AUTHOR

Laurent Dami E<lt>dami@cpan.orgE<gt>


=head1 COPYRIGHT AND LICENSE

Copyright Laurent Dami, 2014.

Parts of the code are borrowed from L<SQLite::VirtualTable>,
copyright (C) 2006, 2009 by Qindel Formacion y Servicios, S. L.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
