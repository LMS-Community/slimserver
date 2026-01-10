#======================================================================
package DBD::SQLite::VirtualTable::PerlData;
#======================================================================
use strict;
use warnings;
use base 'DBD::SQLite::VirtualTable';
use DBD::SQLite;
use constant SQLITE_3010000 => $DBD::SQLite::sqlite_version_number >= 3010000 ? 1 : 0;
use constant SQLITE_3021000 => $DBD::SQLite::sqlite_version_number >= 3021000 ? 1 : 0;

# private data for translating comparison operators from Sqlite to Perl
my $TXT = 0;
my $NUM = 1;
my %SQLOP2PERLOP = (
#              TXT     NUM
  '='     => [ 'eq',   '==' ],
  '<'     => [ 'lt',   '<'  ],
  '<='    => [ 'le',   '<=' ],
  '>'     => [ 'gt',   '>'  ],
  '>='    => [ 'ge',   '>=' ],
  'MATCH' => [ '=~',   '=~' ],
  (SQLITE_3010000 ? (
  'LIKE'  => [ 'DBD::SQLite::strlike', 'DBD::SQLite::strlike' ],
  'GLOB'  => [ 'DBD::SQLite::strglob', 'DBD::SQLite::strglob' ],
  'REGEXP'=> [ '=~',   '=~' ],
  ) : ()),
  (SQLITE_3021000 ? (
  'NE'    => [ 'ne',   '!=' ],
  'ISNOT' => [ 'defined',   'defined' ],
  'ISNOTNULL' => [ 'defined',   'defined' ],
  'ISNULL'    => [ '!defined',  '!defined' ],
  'IS'    => [ '!defined',   '!defined' ],
  ) : ()),
);

#----------------------------------------------------------------------
# instanciation methods
#----------------------------------------------------------------------

sub NEW {
  my $class = shift;
  my $self  = $class->_PREPARE_SELF(@_);

  # verifications
  my $n_cols = @{$self->{columns}};
  $n_cols > 0
    or die "$class: no declared columns";
  !$self->{options}{colref} || $n_cols == 1
    or die "$class: must have exactly 1 column when using 'colref'";
  my $symbolic_ref = $self->{options}{arrayrefs}
                  || $self->{options}{hashrefs}
                  || $self->{options}{colref}
    or die "$class: missing option 'arrayrefs' or 'hashrefs' or 'colref'";

  # bind to the Perl variable
  no strict "refs";
  defined ${$symbolic_ref}
    or die "$class: can't find global variable \$$symbolic_ref";
  $self->{rows} = \ ${$symbolic_ref};

  bless $self, $class;
}

sub _build_headers_optypes {
  my $self = shift;

  my $cols = $self->sqlite_table_info;

  # headers : names of columns, without type information
  $self->{headers} = [ map {$_->{name}} @$cols ];

  # optypes : either $NUM or $TEXT for each column
  # (applying  algorithm from datatype3.html" for type affinity)
  $self->{optypes}
    = [ map {$_->{type} =~ /INT|REAL|FLOA|DOUB/i ? $NUM : $TXT} @$cols ];
}

#----------------------------------------------------------------------
# method for initiating a search
#----------------------------------------------------------------------

sub BEST_INDEX {
  my ($self, $constraints, $order_by) = @_;

  $self->_build_headers_optypes if !$self->{headers};

  # for each constraint, build a Perl code fragment. Those will be gathered
  # in FILTER() for deciding which rows match the constraints.
  my @conditions;
  my $ix = 0;
  foreach my $constraint (grep {$_->{usable} and exists $SQLOP2PERLOP{ $_->{op} } } @$constraints) {
    my $col = $constraint->{col};
    my ($member, $optype);

    # build a Perl code fragment. Those fragments will be gathered
    # and eval-ed in FILTER(), for deciding which rows match the constraints.
    if ($col == -1) {
      # constraint on rowid
      $member = '$i';
      $optype = $NUM;
    }
    else {
      # constraint on regular column
      my $opts = $self->{options};
      $member  = $opts->{arrayrefs} ? "\$row->[$col]"
               : $opts->{hashrefs}  ? "\$row->{$self->{headers}[$col]}"
               : $opts->{colref}    ? "\$row"
               :                      die "corrupted data in ->{options}";
      $optype  = $self->{optypes}[$col];
    }
    my $op = $SQLOP2PERLOP{$constraint->{op}}[$optype];
    if (SQLITE_3021000 && $op =~ /defined/) {
      if ($constraint->{op} =~ /NULL/) {
        push @conditions,
          "($op($member))";
      } else {
        push @conditions,
          "($op($member) && !defined(\$vals[$ix]))";
      }
    } elsif (SQLITE_3010000 && $op =~ /str/) {
      push @conditions,
        "(defined($member) && defined(\$vals[$ix]) && !$op(\$vals[$ix], $member))";
    } else {
      push @conditions,
        "(defined($member) && defined(\$vals[$ix]) && $member $op \$vals[$ix])";
    }
    # Note : $vals[$ix] refers to an array of values passed to the
    # FILTER method (see below); so the eval-ed perl code will be a
    # closure on those values
    # info passed back to the SQLite core -- see vtab.html in sqlite doc
    $constraint->{argvIndex} = $ix++;
    $constraint->{omit}      = 1;
  }

  # further info for the SQLite core
  my $outputs = {
    idxNum           => 1,
    idxStr           => (join(" && ", @conditions) || "1"),
    orderByConsumed  => 0,
    estimatedCost    => 1.0,
    estimatedRows    => undef,
  };

  return $outputs;
}


#----------------------------------------------------------------------
# methods for data update
#----------------------------------------------------------------------

sub _build_new_row {
  my ($self, $values) = @_;

  my $opts = $self->{options};
  return $opts->{arrayrefs} ? $values
       : $opts->{hashrefs}  ? { map {$self->{headers}->[$_], $values->[$_]}
                                    (0 .. @{$self->{headers}} - 1) }
       : $opts->{colref}    ? $values->[0]
       :                      die "corrupted data in ->{options}";
}

sub INSERT {
  my ($self, $new_rowid, @values) = @_;

  my $new_row = $self->_build_new_row(\@values);

  if (defined $new_rowid) {
    not ${$self->{rows}}->[$new_rowid]
      or die "can't INSERT : rowid $new_rowid already in use";
    ${$self->{rows}}->[$new_rowid] = $new_row;
  }
  else {
    push @${$self->{rows}}, $new_row;
    return $#${$self->{rows}};
  }
}

sub DELETE {
  my ($self, $old_rowid) = @_;

  delete ${$self->{rows}}->[$old_rowid];
}

sub UPDATE {
  my ($self, $old_rowid, $new_rowid, @values) = @_;

  my $new_row = $self->_build_new_row(\@values);

  if ($new_rowid == $old_rowid) {
    ${$self->{rows}}->[$old_rowid] = $new_row;
  }
  else {
    delete ${$self->{rows}}->[$old_rowid];
    ${$self->{rows}}->[$new_rowid] = $new_row;
  }
}


#======================================================================
package DBD::SQLite::VirtualTable::PerlData::Cursor;
#======================================================================
use strict;
use warnings;
use base "DBD::SQLite::VirtualTable::Cursor";


sub row {
  my ($self, $i) = @_;
  return ${$self->{vtable}{rows}}->[$i];
}

sub FILTER {
  my ($self, $idxNum, $idxStr, @vals) = @_;

  # build a method coderef to fetch matching rows
  my $perl_code = 'sub {my ($self, $i) = @_; my $row = $self->row($i); '
                .        $idxStr
                .     '}';

  # print STDERR "PERL CODE:\n", $perl_code, "\n";

  $self->{is_wanted_row} = do { no warnings; eval $perl_code }
    or die "couldn't eval q{$perl_code} : $@";

  # position the cursor to the first matching row (or to eof)
  $self->{row_ix} = -1;
  $self->NEXT;
}


sub EOF {
  my ($self) = @_;

  return $self->{row_ix} > $#${$self->{vtable}{rows}};
}

sub NEXT {
  my ($self) = @_;

  do {
    $self->{row_ix} += 1
  } until $self->EOF
       || eval {$self->{is_wanted_row}->($self, $self->{row_ix})};

  # NOTE: the eval above is required for cases when user data, injected
  # into Perl comparison operators, generates errors; for example
  # WHERE col MATCH '(foo' will die because the regex is not well formed
  # (no matching parenthesis). In such cases no row is selected and the
  # query just returns an empty list.
}


sub COLUMN {
  my ($self, $idxCol) = @_;

  my $row = $self->row($self->{row_ix});

  my $opts = $self->{vtable}{options};
  return $opts->{arrayrefs} ? $row->[$idxCol]
       : $opts->{hashrefs}  ? $row->{$self->{vtable}{headers}[$idxCol]}
       : $opts->{colref}    ? $row
       :                      die "corrupted data in ->{options}";
}

sub ROWID {
  my ($self) = @_;

  return $self->{row_ix} + 1; # rowids start at 1 in SQLite
}


1;

__END__

=head1 NAME

DBD::SQLite::VirtualTable::PerlData -- virtual table hooked to Perl data

=head1 SYNOPSIS

Within Perl :

  $dbh->sqlite_create_module(perl => "DBD::SQLite::VirtualTable::PerlData");

Then, within SQL :


  CREATE VIRTUAL TABLE atbl USING perl(foo, bar, etc,
                                       arrayrefs="some::global::var::aref")

  CREATE VIRTUAL TABLE htbl USING perl(foo, bar, etc,
                                       hashrefs="some::global::var::href")

  CREATE VIRTUAL TABLE ctbl USING perl(single_col
                                       colref="some::global::var::ref")


  SELECT foo, bar FROM atbl WHERE ...;


=head1 DESCRIPTION

A C<PerlData> virtual table is a database view on some datastructure
within a Perl program. The data can be read or modified both from SQL
and from Perl. This is useful for simple import/export
operations, for debugging purposes, for joining data from different
sources, etc.


=head1 PARAMETERS

Parameters for creating a C<PerlData> virtual table are specified
within the C<CREATE VIRTUAL TABLE> statement, mixed with regular
column declarations, but with an '=' sign.

The only authorized (and mandatory) parameter is the one that
specifies the Perl datastructure to which the virtual table is bound.
It must be given as the fully qualified name of a global variable;
the parameter can be one of three different kinds :

=over

=item C<arrayrefs>

arrayref that contains an arrayref for each row.
Each such row will have a size equivalent to the number
of columns declared for the virtual table.

=item C<hashrefs>

arrayref that contains a hashref for each row.
Keys in each hashref should correspond to the
columns declared for the virtual table.

=item C<colref>

arrayref that contains a single scalar for each row;
obviously, this is a single-column virtual table.

=back

=head1 USAGE

=head2 Common part of all examples : declaring the module

In all examples below, the common part is that the Perl
program should connect to the database and then declare the
C<PerlData> virtual table module, like this

  # connect to the database
  my $dbh = DBI->connect("dbi:SQLite:dbname=$dbfile", '', '',
                          {RaiseError => 1, AutoCommit => 1});
                          # or any other options suitable to your needs
  
  # register the module
  $dbh->sqlite_create_module(perl => "DBD::SQLite::VirtualTable::PerlData");

Then create a global arrayref variable, using C<our> instead of C<my>,
so that the variable is stored in the symbol table of the enclosing module.

  package Foo::Bar; # could as well be just "main"
  our $rows = [ ... ];

Finally, create the virtual table and bind it to the global
variable (here we assume that C<@$rows> contains arrayrefs) :

  $dbh->do('CREATE VIRTUAL TABLE temp.vtab'
          .'  USING perl(col1 INT, col2 TEXT, etc,
                         arrayrefs="Foo::Bar::rows');

In most cases, the virtual table will be for temporary use, which is
the reason why this example prepends C<temp.> in front of the table
name : this tells SQLite to cleanup that table when the database
handle will be disconnected, without the need to emit an explicit DROP
statement.

Column names (and optionally their types) are specified in the
virtual table declaration, just like for any regular table.

=head2 Arrayref example : statistics from files

Let's suppose we want to perform some searches over a collection of
files, where search constraints may be based on some of the fields
returned by L<stat>, such as the size of the file or its last modify
time.  Here is a way to do it with a virtual table :

  my @files = ... ; # list of files to inspect

  # apply the L<stat> function to each file
  our $file_stats = [ map { [ $_, stat $_ ] } @files];

  # create a temporary virtual table
  $dbh->do(<<"");
     CREATE VIRTUAL TABLE temp.file_stats'
        USING perl(path, dev, ino, mode, nlink, uid, gid, rdev, size,
                         atime, mtime, ctime, blksize, blocks,
                   arrayrefs="main::file_stats");

  # search files
  my $sth = $dbh->prepare(<<"");
    SELECT * FROM file_stats 
      WHERE mtime BETWEEN ? AND ?
        AND uid IN (...)

=head2 Hashref example : unicode characters

Given any unicode character, the L<Unicode::UCD/charinfo> function
returns a hashref with various bits of information about that character.
So this can be exploited in a virtual table :

  use Unicode::UCD 'charinfo';
  our $chars = [map {charinfo($_)} 0x300..0x400]; # arbitrary subrange

  # create a temporary virtual table
  $dbh->do(<<"");
    CREATE VIRTUAL TABLE charinfo USING perl(
      code, name, block, script, category,
      hashrefs="main::chars"
     )

  # search characters
  my $sth = $dbh->prepare(<<"");
    SELECT * FROM charinfo 
     WHERE script='Greek' 
       AND name LIKE '%SIGMA%'


=head2 Colref example: SELECT WHERE ... IN ...

I<Note: The idea for the following example is borrowed from the
C<test_intarray.h> file in SQLite's source
(L<http://www.sqlite.org/src>).>

A C<colref> virtual table is designed to facilitate using an
array of values as the right-hand side of an IN operator. The
usual syntax for IN is to prepare a statement like this:

    SELECT * FROM table WHERE x IN (?,?,?,...,?);

and then bind individual values to each of the ? slots; but this has
the disadvantage that the number of values must be known in
advance. Instead, we can store values in a Perl array, bind that array
to a virtual table, and then write a statement like this

    SELECT * FROM table WHERE x IN perl_array;

Here is how such a program would look like :

  # connect to the database
  my $dbh = DBI->connect("dbi:SQLite:dbname=$dbfile", '', '',
                          {RaiseError => 1, AutoCommit => 1});
  
  # Declare a global arrayref containing the values. Here we assume
  # they are taken from @ARGV, but any other datasource would do.
  # Note the use of "our" instead of "my".
  our $values = \@ARGV; 
  
  # register the module and declare the virtual table
  $dbh->sqlite_create_module(perl => "DBD::SQLite::VirtualTable::PerlData");
  $dbh->do('CREATE VIRTUAL TABLE temp.intarray'
          .'  USING perl(i INT, colref="main::values');
  
  # now we can SELECT from another table, using the intarray as a constraint
  my $sql    = "SELECT * FROM some_table WHERE some_col IN intarray";
  my $result = $dbh->selectall_arrayref($sql);


Beware that the virtual table is read-write, so the statement below
would push 99 into @ARGV !

  INSERT INTO intarray VALUES (99);



=head1 AUTHOR

Laurent Dami E<lt>dami@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright Laurent Dami, 2014.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
