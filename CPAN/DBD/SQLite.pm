package DBD::SQLite;

use 5.006;
use strict;
use DBI   1.57 ();
use DynaLoader ();

use vars qw($VERSION @ISA);
use vars qw{$err $errstr $drh $sqlite_version};
BEGIN {
    $VERSION = '1.25';
    @ISA     = ('DynaLoader');

    # Initialize errors
    $err     = undef;
    $errstr  = undef;

    # Driver singleton
    $drh = undef;

    # sqlite_version cache
    $sqlite_version = undef;
}

__PACKAGE__->bootstrap($VERSION);

sub driver {
    $drh or
    $drh = DBI::_new_drh( "$_[0]::dr", {
        Name        => 'SQLite',
        Version     => $VERSION,
        Attribution => 'DBD::SQLite by Matt Sergeant et al',
    } );
}

sub CLONE {
    undef $drh;
}

package DBD::SQLite::dr;

sub connect {
    my ($drh, $dbname, $user, $auth, $attr) = @_;

    # Default PrintWarn to the value of $^W
    unless ( defined $attr->{PrintWarn} ) {
        $attr->{PrintWarn} = $^W ? 1 : 0;
    }

    my $dbh = DBI::_new_dbh( $drh, {
        Name => $dbname,
    } );

    my $real = $dbname;
    if ( $dbname =~ /=/ ) {
        foreach my $attrib ( split(/;/, $dbname) ) {
            my ($key, $value) = split(/=/, $attrib, 2);
            if ( $key eq 'dbname' ) {
                $real = $value;
            } else {
                $attr->{$key} = $value;
            }
        }
    }

    # To avoid unicode and long file name problems on Windows,
    # convert to the shortname if the file (or parent directory) exists.
    if ( $^O =~ /MSWin32|cygwin/ and $real ne ':memory:' ) {
        require Win32;
        require File::Basename;
        my ($file, $dir, $suffix) = File::Basename::fileparse($real);
        my $short = Win32::GetShortPathName($real);
        if ( $short && -f $short ) {
            # Existing files will work directly.
            $real = $short;
        } elsif ( -d $dir ) {
            # We are creating a new file.
            # Does the directory it's in at least exist?
            $real = join '', grep { defined } Win32::GetShortPathName($dir), $file, $suffix;
        } else {
            # SQLite can't do mkpath anyway.
            # So let it go through as it and fail.
        }
        if ( $^O eq 'cygwin' ) {
            if ( $] >= 5.010 ) {
                $real = Cygwin::win_to_posix_path($real, 'absolute');
            }
            else {
                require Filesys::CygwinPaths;
                $real = Filesys::CygwinPaths::fullposixpath($real);
            }
        }
    }

    # Hand off to the actual login function
    DBD::SQLite::db::_login($dbh, $real, $user, $auth) or return undef;

    # Install perl collations
    my $perl_collation        = sub { $_[0] cmp $_[1] };
    my $perl_locale_collation = sub { use locale; $_[0] cmp $_[1] };
    $dbh->func( "perl",       $perl_collation,        "create_collation" );
    $dbh->func( "perllocale", $perl_locale_collation, "create_collation" );

    # HACK: Since PrintWarn = 0 doesn't seem to actually prevent warnings
    # in DBD::SQLite we set Warn to false if PrintWarn is false.
    unless ( $attr->{PrintWarn} ) {
        $attr->{Warn} = 0;
    }

    return $dbh;
}

package DBD::SQLite::db;

sub prepare {
    my $dbh = shift;
    my $sql = shift;

    my $sth = DBI::_new_sth( $dbh, {
        Statement => $sql,
    } );

    DBD::SQLite::st::_prepare($sth, $sql, @_) or return undef;

    return $sth;
}

sub _get_version {
    return ( DBD::SQLite::db::FETCH($_[0], 'sqlite_version') );
}

my %info = (
    17 => 'SQLite',       # SQL_DBMS_NAME
    18 => \&_get_version, # SQL_DBMS_VER
    29 => '"',            # SQL_IDENTIFIER_QUOTE_CHAR
);

sub get_info {
    my($dbh, $info_type) = @_;
    my $v = $info{int($info_type)};
    $v = $v->($dbh) if ref $v eq 'CODE';
    return $v;
}

# SQL/CLI (ISO/IEC JTC 1/SC 32 N 0595), 6.63 Tables
# Based on DBD::Oracle's
# See also http://www.ch-werner.de/sqliteodbc/html/sqliteodbc_8c.html#a117
sub table_info {
    my ($dbh, $cat_val, $sch_val, $tbl_val, $typ_val) = @_;

    my @where = ();
    my $sql;
    if (   defined($cat_val) && $cat_val eq '%'
       && defined($sch_val) && $sch_val eq '' 
       && defined($tbl_val) && $tbl_val eq '')  { # Rule 19a
            $sql = <<'END_SQL';
SELECT NULL TABLE_CAT
     , NULL TABLE_SCHEM
     , NULL TABLE_NAME
     , NULL TABLE_TYPE
     , NULL REMARKS
END_SQL
    }
    elsif (   defined($sch_val) && $sch_val eq '%' 
          && defined($cat_val) && $cat_val eq '' 
          && defined($tbl_val) && $tbl_val eq '') { # Rule 19b
            $sql = <<'END_SQL';
SELECT NULL      TABLE_CAT
     , NULL      TABLE_SCHEM
     , NULL      TABLE_NAME
     , NULL      TABLE_TYPE
     , NULL      REMARKS
END_SQL
    }
    elsif (    defined($typ_val) && $typ_val eq '%' 
           && defined($cat_val) && $cat_val eq '' 
           && defined($sch_val) && $sch_val eq '' 
           && defined($tbl_val) && $tbl_val eq '') { # Rule 19c
            $sql = <<'END_SQL';
SELECT NULL TABLE_CAT
     , NULL TABLE_SCHEM
     , NULL TABLE_NAME
     , t.tt TABLE_TYPE
     , NULL REMARKS
FROM (
     SELECT 'TABLE' tt                  UNION
     SELECT 'VIEW' tt                   UNION
     SELECT 'LOCAL TEMPORARY' tt
) t
ORDER BY TABLE_TYPE
END_SQL
    }
    else {
            $sql = <<'END_SQL';
SELECT *
FROM
(
SELECT NULL         TABLE_CAT
     , NULL         TABLE_SCHEM
     , tbl_name     TABLE_NAME
     ,              TABLE_TYPE
     , NULL         REMARKS
     , sql          sqlite_sql
FROM (
    SELECT tbl_name, upper(type) TABLE_TYPE, sql
    FROM sqlite_master
    WHERE type IN ( 'table','view')
UNION ALL
    SELECT tbl_name, 'LOCAL TEMPORARY' TABLE_TYPE, sql
    FROM sqlite_temp_master
    WHERE type IN ( 'table','view')
UNION ALL
    SELECT 'sqlite_master'      tbl_name, 'SYSTEM TABLE' TABLE_TYPE, NULL sql
UNION ALL
    SELECT 'sqlite_temp_master' tbl_name, 'SYSTEM TABLE' TABLE_TYPE, NULL sql
)
)
END_SQL
            if ( defined $tbl_val ) {
                    push @where, "TABLE_NAME LIKE '$tbl_val'";
            }
            if ( defined $typ_val ) {
                    my $table_type_list;
                    $typ_val =~ s/^\s+//;
                    $typ_val =~ s/\s+$//;
                    my @ttype_list = split (/\s*,\s*/, $typ_val);
                    foreach my $table_type (@ttype_list) {
                            if ($table_type !~ /^'.*'$/) {
                                    $table_type = "'" . $table_type . "'";
                            }
                            $table_type_list = join(", ", @ttype_list);
                    }
                    push @where, "TABLE_TYPE IN (\U$table_type_list)" if $table_type_list;
            }
            $sql .= ' WHERE ' . join("\n   AND ", @where ) . "\n" if @where;
            $sql .= " ORDER BY TABLE_TYPE, TABLE_SCHEM, TABLE_NAME\n";
    }
    my $sth = $dbh->prepare($sql) or return undef;
    $sth->execute or return undef;
    $sth;
}

sub primary_key_info {
    my($dbh, $catalog, $schema, $table) = @_;

    # This is a hack but much simpler than using pragma index_list etc
    # also the pragma doesn't list 'INTEGER PRIMARK KEY' autoinc PKs!
    my @pk_info;
    my $sth_tables = $dbh->table_info($catalog, $schema, $table, '');
    while ( my $row = $sth_tables->fetchrow_hashref ) {
        my $sql = $row->{sqlite_sql} or next;
        next unless $sql =~ /(.*?)\s*PRIMARY\s+KEY\s*(?:\(\s*(.*?)\s*\))?/si;
        my @pk = split /\s*,\s*/, $2 || '';
        unless ( @pk ) {
            my $prefix = $1;
            $prefix =~ s/.*create\s+table\s+.*?\(\s*//si;
            $prefix = (split /\s*,\s*/, $prefix)[-1];
            @pk = (split /\s+/, $prefix)[0]; # take first word as name
        }
        my $key_seq = 0;
        foreach my $pk_field (@pk) {
            push @pk_info, {
                TABLE_SCHEM => $row->{TABLE_SCHEM},
                TABLE_NAME  => $row->{TABLE_NAME},
                COLUMN_NAME => $pk_field,
                KEY_SEQ     => ++$key_seq,
                PK_NAME     => 'PRIMARY KEY',
            };
        }
    }

    my $sponge = DBI->connect("DBI:Sponge:", '','')
        or return $dbh->DBI::set_err($DBI::err, "DBI::Sponge: $DBI::errstr");
    my @names = qw(TABLE_CAT TABLE_SCHEM TABLE_NAME COLUMN_NAME KEY_SEQ PK_NAME);
    my $sth = $sponge->prepare( "column_info $table", {
        rows          => [ map { [ @{$_}{@names} ] } @pk_info ],
        NUM_OF_FIELDS => scalar @names,
        NAME          => \@names,
    }) or return $dbh->DBI::set_err(
        $sponge->err(),
        $sponge->errstr()
    );
    return $sth;
}

sub type_info_all {
    return; # XXX code just copied from DBD::Oracle, not yet thought about
#    return [
#        {
#            TYPE_NAME          =>  0,
#            DATA_TYPE          =>  1,
#            COLUMN_SIZE        =>  2,
#            LITERAL_PREFIX     =>  3,
#            LITERAL_SUFFIX     =>  4,
#            CREATE_PARAMS      =>  5,
#            NULLABLE           =>  6,
#            CASE_SENSITIVE     =>  7,
#            SEARCHABLE         =>  8,
#            UNSIGNED_ATTRIBUTE =>  9,
#            FIXED_PREC_SCALE   => 10,
#            AUTO_UNIQUE_VALUE  => 11,
#            LOCAL_TYPE_NAME    => 12,
#            MINIMUM_SCALE      => 13,
#            MAXIMUM_SCALE      => 14,
#            SQL_DATA_TYPE      => 15,
#            SQL_DATETIME_SUB   => 16,
#            NUM_PREC_RADIX     => 17,
#        },
#        [ 'CHAR', 1, 255, '\'', '\'', 'max length', 1, 1, 3,
#            undef, '0', '0', undef, undef, undef, 1, undef, undef
#        ],
#        [ 'NUMBER', 3, 38, undef, undef, 'precision,scale', 1, '0', 3,
#            '0', '0', '0', undef, '0', 38, 3, undef, 10
#        ],
#        [ 'DOUBLE', 8, 15, undef, undef, undef, 1, '0', 3,
#            '0', '0', '0', undef, undef, undef, 8, undef, 10
#        ],
#        [ 'DATE', 9, 19, '\'', '\'', undef, 1, '0', 3,
#            undef, '0', '0', undef, '0', '0', 11, undef, undef
#        ],
#        [ 'VARCHAR', 12, 1024*1024, '\'', '\'', 'max length', 1, 1, 3,
#            undef, '0', '0', undef, undef, undef, 12, undef, undef
#        ]
#    ];
}

# Taken from Fey::Loader::SQLite
sub column_info {
    my($dbh, $catalog, $schema, $table, $column) = @_;

    if ( defined $column and $column eq '%' ) {
        $column = undef;
    }

    my $sth_columns = $dbh->prepare( "PRAGMA table_info('$table')" );
    $sth_columns->execute;

    my @names = qw(
        TABLE_CAT TABLE_SCHEM TABLE_NAME COLUMN_NAME
        DATA_TYPE TYPE_NAME COLUMN_SIZE BUFFER_LENGTH
        DECIMAL_DIGITS NUM_PREC_RADIX NULLABLE
        REMARKS COLUMN_DEF SQL_DATA_TYPE SQL_DATETIME_SUB
        CHAR_OCTET_LENGTH ORDINAL_POSITION IS_NULLABLE
    );

    my @cols;
    while ( my $col_info = $sth_columns->fetchrow_hashref ) {
        next if defined $column && $column ne $col_info->{name};

        my %col = (
            TABLE_NAME  => $table,
            COLUMN_NAME => $col_info->{name},
        );

        my $type = $col_info->{type};
        if ( $type =~ s/(\w+)\((\d+)(?:,(\d+))?\)/$1/ ) {
            $col{COLUMN_SIZE}    = $2;
            $col{DECIMAL_DIGITS} = $3;
        }

        $col{TYPE_NAME} = $type;

        if ( defined $col_info->{dflt_value} ) {
            $col{COLUMN_DEF} = $col_info->{dflt_value}
        }

        if ( $col_info->{notnull} ) {
            $col{NULLABLE}    = 0;
            $col{IS_NULLABLE} = 'NO';
        } else {
            $col{NULLABLE}    = 1;
            $col{IS_NULLABLE} = 'YES';
        }

        foreach my $key ( @names ) {
            next if exists $col{$key};
            $col{$key} = undef;
        }

        push @cols, \%col;
    }

    my $sponge = DBI->connect("DBI:Sponge:", '','')
        or return $dbh->DBI::set_err($DBI::err, "DBI::Sponge: $DBI::errstr");
    my $sth = $sponge->prepare( "column_info $table", {
        rows          => [ map { [ @{$_}{@names} ] } @cols ],
        NUM_OF_FIELDS => scalar @names,
        NAME          => \@names,
    } ) or return $dbh->DBI::set_err(
        $sponge->err,
        $sponge->errstr,
    );
    return $sth;
}

1;

__END__

=pod

=head1 NAME

DBD::SQLite - Self-contained RDBMS in a DBI Driver

=head1 SYNOPSIS

  use DBI;
  my $dbh = DBI->connect("dbi:SQLite:dbname=dbfile","","");

=head1 DESCRIPTION

SQLite is a public domain RDBMS database engine that you can find
at L<http://www.sqlite.org/>.

Rather than ask you to install SQLite first, because SQLite is public
domain, B<DBD::SQLite> includes the entire thing in the distribution.
So in order to get a fast transaction capable RDBMS working for your
perl project you simply have to install this module, and B<nothing>
else.

SQLite supports the following features:

=over 4

=item Implements a large subset of SQL92

See L<http://www.sqlite.org/lang.html> for details.

=item A complete DB in a single disk file

Everything for your database is stored in a single disk file, making it
easier to move things around than with L<DBD::CSV>.

=item Atomic commit and rollback

Yes, B<DBD::SQLite> is small and light, but it supports full transactions!

=item Extensible

User-defined aggregate or regular functions can be registered with the
SQL parser.

=back

There's lots more to it, so please refer to the docs on the SQLite web
page, listed above, for SQL details. Also refer to L<DBI> for details
on how to use DBI itself.

=head1 CONFORMANCE WITH DBI SPECIFICATION

The API works like every DBI module does. Please see L<DBI> for more
details about core features.

Currently many statement attributes are not implemented or are
limited by the typeless nature of the SQLite database.

=head1 DRIVER PRIVATE ATTRIBUTES

=head2 Database Handle Attributes

=over 4

=item sqlite_version

Returns the version of the SQLite library which B<DBD::SQLite> is using,
e.g., "2.8.0". Can only be read.

=item unicode

If set to a true value, B<DBD::SQLite> will turn the UTF-8 flag on for all text
strings coming out of the database (this feature is currently disabled for perl < 5.8.5). For more details on the UTF-8 flag see
L<perlunicode>. The default is for the UTF-8 flag to be turned off.

Also note that due to some bizarreness in SQLite's type system (see
L<http://www.sqlite.org/datatype3.html>), if you want to retain
blob-style behavior for B<some> columns under C<< $dbh->{unicode} = 1
>> (say, to store images in the database), you have to state so
explicitly using the 3-argument form of L<DBI/bind_param> when doing
updates:

  use DBI qw(:sql_types);
  $dbh->{unicode} = 1;
  my $sth = $dbh->prepare("INSERT INTO mytable (blobcolumn) VALUES (?)");
  
  # Binary_data will be stored as is.
  $sth->bind_param(1, $binary_data, SQL_BLOB);

Defining the column type as C<BLOB> in the DDL is B<not> sufficient.

=back

=head1 DRIVER PRIVATE METHODS

=head2 $dbh->func('last_insert_rowid')

This method returns the last inserted rowid. If you specify an INTEGER PRIMARY
KEY as the first column in your table, that is the column that is returned.
Otherwise, it is the hidden ROWID column. See the sqlite docs for details.

Generally you should not be using this method. Use the L<DBI> last_insert_id
method instead. The usage of this is:

  $h->last_insert_id($catalog, $schema, $table_name, $field_name [, \%attr ])

Running C<$h-E<gt>last_insert_id("","","","")> is the equivalent of running
C<$dbh-E<gt>func('last_insert_rowid')> directly.

=head2 $dbh->func('busy_timeout')

Retrieve the current busy timeout.

=head2 $dbh->func( $ms, 'busy_timeout' )

Set the current busy timeout. The timeout is in milliseconds.

=head2 $dbh->func( $name, $argc, $code_ref, "create_function" )

This method will register a new function which will be useable in an SQL
query. The method's parameters are:

=over

=item $name

The name of the function. This is the name of the function as it will
be used from SQL.

=item $argc

The number of arguments taken by the function. If this number is -1,
the function can take any number of arguments.

=item $code_ref

This should be a reference to the function's implementation.

=back

For example, here is how to define a now() function which returns the
current number of seconds since the epoch:

  $dbh->func( 'now', 0, sub { return time }, 'create_function' );

After this, it could be use from SQL as:

  INSERT INTO mytable ( now() );

=head2 $dbh->func( $name, $code_ref, "create_collation" )

This method will register a new function which will be useable in an SQL
query as a COLLATE option for sorting. The method's parameters are:

=over

=item $name

The name of the function. This is the name of the function as it will
be used from SQL.

=item $code_ref

This should be a reference to the function's implementation.
The driver will check that this is a proper sorting function.

=back

Collations C<binary> and C<nocase> are builtin within SQLite.
Collations C<perl> and C<perllocale> are builtin within 
the B<DBD::SQLite> driver, and correspond to the 
Perl C<cmp> operator with or without the L<locale> pragma; 
so you can write for example 

  CREATE TABLE foo(
      txt1 COLLATE perl,
      txt2 COLLATE perllocale,
      txt3 COLLATE nocase
  )

or

  SELECT * FROM foo ORDER BY name COLLATE perllocale

If the attribute C<< $dbh->{unicode} >> is set, strings coming from
the database and passed to the collation function will be properly
tagged with the utf8 flag; but this only works if the 
C<unicode> attribute is set B<before> the call to 
C<create_collation>. The recommended way to activate unicode
is to set the parameter at connection time :

  my $dbh = DBI->connect(
      "dbi:SQLite:dbname=foo", "", "", 
      {
          RaiseError => 1,
          unicode    => 1,
      }
  );

=head2 $dbh->func( $name, $argc, $pkg, 'create_aggregate' )

This method will register a new aggregate function which can then be used
from SQL. The method's parameters are:

=over

=item $name

The name of the aggregate function, this is the name under which the
function will be available from SQL.

=item $argc

This is an integer which tells the SQL parser how many arguments the
function takes. If that number is -1, the function can take any number
of arguments.

=item $pkg

This is the package which implements the aggregator interface.

=back

The aggregator interface consists of defining three methods:

=over

=item new()

This method will be called once to create an object which should
be used to aggregate the rows in a particular group. The step() and
finalize() methods will be called upon the reference return by
the method.

=item step(@_)

This method will be called once for each row in the aggregate.

=item finalize()

This method will be called once all rows in the aggregate were
processed and it should return the aggregate function's result. When
there is no rows in the aggregate, finalize() will be called right
after new().

=back

Here is a simple aggregate function which returns the variance
(example adapted from pysqlite):

  package variance;
  
  sub new { bless [], shift; }
  
  sub step {
      my ( $self, $value ) = @_;
  
      push @$self, $value;
  }
  
  sub finalize {
      my $self = $_[0];
  
      my $n = @$self;
  
      # Variance is NULL unless there is more than one row
      return undef unless $n || $n == 1;
  
      my $mu = 0;
      foreach my $v ( @$self ) {
          $mu += $v;
      }
      $mu /= $n;
  
      my $sigma = 0;
      foreach my $v ( @$self ) {
          $sigma += ($x - $mu)**2;
      }
      $sigma = $sigma / ($n - 1);
  
      return $sigma;
  }
  
  $dbh->func( "variance", 1, 'variance', "create_aggregate" );

The aggregate function can then be used as:

  SELECT group_name, variance(score)
  FROM results
  GROUP BY group_name;

For more examples, see the L<DBD::SQLite::Cookbook>.

=head2 $dbh->func( $n_opcodes, $code_ref, 'progress_handler' )

This method registers a handler to be invoked periodically during long
running calls to SQLite.

An example use for this interface is to keep a GUI updated during a
large query. The parameters are:

=over

=item $n_opcodes

The progress handler is invoked once for every C<$n_opcodes>
virtual machine opcodes in SQLite.

=item $handler

Reference to the handler subroutine.  If the progress handler returns
non-zero, the SQLite operation is interrupted. This feature can be used to
implement a "Cancel" button on a GUI dialog box.

Set this argument to C<undef> if you want to unregister a previous
progress handler.

=back

=head1 BLOBS

As of version 1.11, blobs should "just work" in SQLite as text columns.
However this will cause the data to be treated as a string, so SQL
statements such as length(x) will return the length of the column as a NUL
terminated string, rather than the size of the blob in bytes. In order to
store natively as a BLOB use the following code:

  use DBI qw(:sql_types);
  my $dbh = DBI->connect("dbi:SQLite:dbfile","","");
  
  my $blob = `cat foo.jpg`;
  my $sth = $dbh->prepare("INSERT INTO mytable VALUES (1, ?)");
  $sth->bind_param(1, $blob, SQL_BLOB);
  $sth->execute();

And then retrieval just works:

  $sth = $dbh->prepare("SELECT * FROM mytable WHERE id = 1");
  $sth->execute();
  my $row = $sth->fetch;
  my $blobo = $row->[1];
  
  # now $blobo == $blob

=head1 NOTES

Although the database is stored in a single file, the directory containing the
database file must be writable by SQLite because the library will create
several temporary files there.

To access the database from the command line, try using dbish which comes with
the DBI module. Just type:

  dbish dbi:SQLite:foo.db

On the command line to access the file F<foo.db>.

Alternatively you can install SQLite from the link above without conflicting
with B<DBD::SQLite> and use the supplied C<sqlite> command line tool.

=head1 PERFORMANCE

SQLite is fast, very fast. I recently processed my 72MB log file with it,
inserting the data (400,000+ rows) by using transactions and only committing
every 1000 rows (otherwise the insertion is quite slow), and then performing
queries on the data.

Queries like count(*) and avg(bytes) took fractions of a second to return,
but what surprised me most of all was:

  SELECT url, count(*) as count
  FROM access_log
  GROUP BY url
  ORDER BY count desc
  LIMIT 20

To discover the top 20 hit URLs on the site (L<http://axkit.org>), and it
returned within 2 seconds. I'm seriously considering switching my log
analysis code to use this little speed demon!

Oh yeah, and that was with no indexes on the table, on a 400MHz PIII.

For best performance be sure to tune your hdparm settings if you are
using linux. Also you might want to set:

  PRAGMA default_synchronous = OFF

Which will prevent sqlite from doing fsync's when writing (which
slows down non-transactional writes significantly) at the expense of some
peace of mind. Also try playing with the cache_size pragma.

The memory usage of SQLite can also be tuned using the cache_size pragma.

  $dbh->do("PRAGMA cache_size = 800000");

The above will allocate 800M for DB cache; the default is 2M. Your sweet spot
probably lies somewhere in between.

=head1 TO DO

The following items remain to be done.

=head2 Warnings Upgrade

We currently use a horridly hacky method to issue and suppress warnings.
It suffices for now, but just barely.

Migrate all of the warning code to use the recommended DBI warnings.

=head2 Leak Detection

Implement one or more leak detection tests that only run during
AUTOMATED_TESTING and RELEASE_TESTING and validate that none of the C
code we work with leaks.

=head1 SUPPORT

Bugs should be reported via the CPAN bug tracker at

L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=DBD-SQLite>

=head1 TO DO

There're several pended RT bugs/patches at the moment
(mainly due to the lack of tests/patches or segfaults on tests).

Here's the list.

L<http://rt.cpan.org/Public/Bug/Display.html?id=35449>
(breaks tests)

L<http://rt.cpan.org/Public/Bug/Display.html?id=29629>
(requires a patch)

L<http://rt.cpan.org/Public/Bug/Display.html?id=29058>
(requires a patch)

Switch tests to L<Test::More> to support more advanced testing behaviours

=head1 AUTHOR

Matt Sergeant E<lt>matt@sergeant.orgE<gt>

Francis J. Lacoste E<lt>flacoste@logreport.orgE<gt>

Wolfgang Sourdeau E<lt>wolfgang@logreport.orgE<gt>

Adam Kennedy E<lt>adamk@cpan.orgE<gt>

Max Maischein E<lt>corion@cpan.orgE<gt>

=head1 COPYRIGHT

The bundled SQLite code in this distribution is Public Domain.

DBD::SQLite is copyright 2002 - 2007 Matt Sergeant.

Some parts copyright 2008 Francis J. Lacoste.

Some parts copyright 2008 Wolfgang Sourdeau.

Some parts copyright 2008 - 2009 Adam Kennedy.

Some parts derived from L<DBD::SQLite::Amalgamation>
copyright 2008 Audrey Tang.

This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

The full text of the license can be found in the
LICENSE file included with this module.

=cut
