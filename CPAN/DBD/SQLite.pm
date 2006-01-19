# $Id: SQLite.pm,v 1.51 2005/12/02 17:31:57 matt Exp $

package DBD::SQLite;
use strict;

use DBI;
use vars qw($err $errstr $state $drh $VERSION @ISA);
$VERSION = '1.11';

use DynaLoader();
@ISA = ('DynaLoader');

__PACKAGE__->bootstrap($VERSION);

$drh = undef;

sub driver {
    return $drh if $drh;
    my ($class, $attr) = @_;

    $class .= "::dr";

    $drh = DBI::_new_drh($class, {
        Name        => 'SQLite',
        Version     => $VERSION,
        Attribution => 'DBD::SQLite by Matt Sergeant',
    });

    return $drh;
}

sub CLONE {
    undef $drh;
}

package DBD::SQLite::dr;

sub connect {
    my ($drh, $dbname, $user, $auth, $attr) = @_;

    my $dbh = DBI::_new_dbh($drh, {
        Name => $dbname,
        });

    my $real_dbname = $dbname;
    if ($dbname =~ /=/) {
        foreach my $attrib (split(/;/, $dbname)) {
            my ($k, $v) = split(/=/, $attrib, 2);
            if ($k eq 'dbname') {
                $real_dbname = $v;
            }
            else {
                # TODO: add to attribs
            }
        }
    }
    DBD::SQLite::db::_login($dbh, $real_dbname, $user, $auth)
        or return undef;

    return $dbh;
}

package DBD::SQLite::db;

sub prepare {
    my ($dbh, $statement, @attribs) = @_;

    my $sth = DBI::_new_sth($dbh, {
        Statement => $statement,
    });

    DBD::SQLite::st::_prepare($sth, $statement, @attribs)
        or return undef;

    return $sth;
}

sub _get_version {
    my ($dbh) = @_;
    return (DBD::SQLite::db::FETCH($dbh, 'sqlite_version'));
}

my %info = (
    17 => 'SQLite',         # SQL_DBMS_NAME
    18 => \&_get_version,   # SQL_DBMS_VER
    29 => '"',              # SQL_IDENTIFIER_QUOTE_CHAR
);
	
sub get_info {
    my($dbh, $info_type) = @_;
    my $v = $info{int($info_type)};
    $v = $v->($dbh) if ref $v eq 'CODE';
    return $v;
}

sub table_info {
    my ($dbh, $CatVal, $SchVal, $TblVal, $TypVal) = @_;
    # SQL/CLI (ISO/IEC JTC 1/SC 32 N 0595), 6.63 Tables
    # Based on DBD::Oracle's
    # See also http://www.ch-werner.de/sqliteodbc/html/sqliteodbc_8c.html#a117

    my @Where = ();
    my $Sql;
    if (   defined($CatVal) && $CatVal eq '%'
       && defined($SchVal) && $SchVal eq '' 
       && defined($TblVal) && $TblVal eq '')  { # Rule 19a
            $Sql = <<'SQL';
SELECT NULL TABLE_CAT
     , NULL TABLE_SCHEM
     , NULL TABLE_NAME
     , NULL TABLE_TYPE
     , NULL REMARKS
SQL
    }
    elsif (   defined($SchVal) && $SchVal eq '%' 
          && defined($CatVal) && $CatVal eq '' 
          && defined($TblVal) && $TblVal eq '') { # Rule 19b
            $Sql = <<'SQL';
SELECT NULL      TABLE_CAT
     , NULL      TABLE_SCHEM
     , NULL      TABLE_NAME
     , NULL      TABLE_TYPE
     , NULL      REMARKS
SQL
    }
    elsif (    defined($TypVal) && $TypVal eq '%' 
           && defined($CatVal) && $CatVal eq '' 
           && defined($SchVal) && $SchVal eq '' 
           && defined($TblVal) && $TblVal eq '') { # Rule 19c
            $Sql = <<'SQL';
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
SQL
    }
    else {
            $Sql = <<'SQL';
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
SQL
            if ( defined $TblVal ) {
                    push @Where, "TABLE_NAME  LIKE '$TblVal'";
            }
            if ( defined $TypVal ) {
                    my $table_type_list;
                    $TypVal =~ s/^\s+//;
                    $TypVal =~ s/\s+$//;
                    my @ttype_list = split (/\s*,\s*/, $TypVal);
                    foreach my $table_type (@ttype_list) {
                            if ($table_type !~ /^'.*'$/) {
                                    $table_type = "'" . $table_type . "'";
                            }
                            $table_type_list = join(", ", @ttype_list);
                    }
                    push @Where, "TABLE_TYPE IN (\U$table_type_list)"
			if $table_type_list;
            }
            $Sql .= ' WHERE ' . join("\n   AND ", @Where ) . "\n" if @Where;
            $Sql .= " ORDER BY TABLE_TYPE, TABLE_SCHEM, TABLE_NAME\n";
    }
    my $sth = $dbh->prepare($Sql) or return undef;
    $sth->execute or return undef;
    $sth;
}


sub primary_key_info {
    my($dbh, $catalog, $schema, $table) = @_;

    my @pk_info;

    my $sth_tables = $dbh->table_info($catalog, $schema, $table, '');

    # this is a hack but much simpler than using pragma index_list etc
    # also the pragma doesn't list 'INTEGER PRIMARK KEY' autoinc PKs!
    while ( my $row = $sth_tables->fetchrow_hashref ) {
        my $sql = $row->{sqlite_sql} or next;
	next unless $sql =~ /(.*?)\s*PRIMARY\s+KEY\s*(?:\(\s*(.*?)\s*\))?/si;
	my @pk = split /\s*,\s*/, $2 || '';
	unless (@pk) {
	    my $prefix = $1;
	    $prefix =~ s/.*create\s+table\s+.*?\(\s*//i;
	    $prefix = (split /\s*,\s*/, $prefix)[-1];
	    @pk = (split /\s+/, $prefix)[0]; # take first word as name
	}
	#warn "GOT PK $row->{TABLE_NAME} (@pk)\n";
	my $key_seq = 0;
	for my $pk_field (@pk) {
	    push @pk_info, {
		TABLE_SCHEM => $row->{TABLE_SCHEM},
		TABLE_NAME  => $row->{TABLE_NAME},
		COLUMN_NAME => $pk_field,
		KEY_SEQ => ++$key_seq,
		PK_NAME => 'PRIMARY KEY',
	    };
	}
    }

    my $sponge = DBI->connect("DBI:Sponge:", '','')
        or return $dbh->DBI::set_err($DBI::err, "DBI::Sponge: $DBI::errstr");
    my @names = qw(TABLE_CAT TABLE_SCHEM TABLE_NAME COLUMN_NAME KEY_SEQ PK_NAME);
    my $sth = $sponge->prepare("column_info $table", {
        rows => [ map { [ @{$_}{@names} ] } @pk_info ],
        NUM_OF_FIELDS => scalar @names,
        NAME => \@names,
    }) or return $dbh->DBI::set_err($sponge->err(), $sponge->errstr());
    return $sth;
}

sub type_info_all {
    my ($dbh) = @_;
return; # XXX code just copied from DBD::Oracle, not yet thought about
    my $names = {
	TYPE_NAME	=> 0,
	DATA_TYPE	=> 1,
	COLUMN_SIZE	=> 2,
	LITERAL_PREFIX	=> 3,
	LITERAL_SUFFIX	=> 4,
	CREATE_PARAMS	=> 5,
	NULLABLE	=> 6,
	CASE_SENSITIVE	=> 7,
	SEARCHABLE	=> 8,
	UNSIGNED_ATTRIBUTE	=> 9,
	FIXED_PREC_SCALE	=>10,
	AUTO_UNIQUE_VALUE	=>11,
	LOCAL_TYPE_NAME	=>12,
	MINIMUM_SCALE	=>13,
	MAXIMUM_SCALE	=>14,
	SQL_DATA_TYPE	=>15,
	SQL_DATETIME_SUB=>16,
	NUM_PREC_RADIX	=>17,
    };
    my $ti = [
      $names,
      [ 'CHAR', 1, 255, '\'', '\'', 'max length', 1, 1, 3,
	undef, '0', '0', undef, undef, undef, 1, undef, undef
      ],
      [ 'NUMBER', 3, 38, undef, undef, 'precision,scale', 1, '0', 3,
	'0', '0', '0', undef, '0', 38, 3, undef, 10
      ],
      [ 'DOUBLE', 8, 15, undef, undef, undef, 1, '0', 3,
	'0', '0', '0', undef, undef, undef, 8, undef, 10
      ],
      [ 'DATE', 9, 19, '\'', '\'', undef, 1, '0', 3,
	undef, '0', '0', undef, '0', '0', 11, undef, undef
      ],
      [ 'VARCHAR', 12, 1024*1024, '\'', '\'', 'max length', 1, 1, 3,
	undef, '0', '0', undef, undef, undef, 12, undef, undef
      ]
    ];
    return $ti;
}


1;
__END__

=head1 NAME

DBD::SQLite - Self Contained RDBMS in a DBI Driver

=head1 SYNOPSIS

  use DBI;
  my $dbh = DBI->connect("dbi:SQLite:dbname=dbfile","","");

=head1 DESCRIPTION

SQLite is a public domain RDBMS database engine that you can find
at http://www.hwaci.com/sw/sqlite/.

Rather than ask you to install SQLite first, because SQLite is public
domain, DBD::SQLite includes the entire thing in the distribution. So
in order to get a fast transaction capable RDBMS working for your
perl project you simply have to install this module, and B<nothing>
else.

SQLite supports the following features:

=over 4

=item Implements a large subset of SQL92

See http://www.hwaci.com/sw/sqlite/lang.html for details.

=item A complete DB in a single disk file

Everything for your database is stored in a single disk file, making it
easier to move things around than with DBD::CSV.

=item Atomic commit and rollback

Yes, DBD::SQLite is small and light, but it supports full transactions!

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

Returns the version of the SQLite library which DBD::SQLite is using,
e.g., "2.8.0". Can only be read.

=item unicode

If set to a true value, DBD::SQLite will turn the UTF-8 flag on for all text
strings coming out of the database. For more details on the UTF-8 flag see
L<perlunicode>. The default is for the UTF-8 flag to be turned off.

Also note that due to some bizareness in SQLite's type system (see
http://www.sqlite.org/datatype3.html), if you want to retain
blob-style behavior for B<some> columns under C<< $dbh->{unicode} = 1
>> (say, to store images in the database), you have to state so
explicitely using the 3-argument form of L<DBI/bind_param> when doing
updates:

    use DBI qw(:sql_types);
    $dbh->{unicode} = 1;
    my $sth = $dbh->prepare
         ("INSERT INTO mytable (blobcolumn) VALUES (?)");
    $sth->bind_param(1, $binary_data, SQL_BLOB); # binary_data will
    # be stored as-is.

Defining the column type as BLOB in the DDL is B<not> sufficient.

=back

=head1 DRIVER PRIVATE METHODS

=head2 $dbh->func('last_insert_rowid')

This method returns the last inserted rowid. If you specify an INTEGER PRIMARY
KEY as the first column in your table, that is the column that is returned.
Otherwise, it is the hidden ROWID column. See the sqlite docs for details.

Note: You can now use $dbh->last_insert_id() if you have a recent version of
DBI.

=head2 $dbh->func( 'busy_timeout' )

Retrieve the current busy timeout.

=head2 $dbh->func( $ms, 'busy_timeout' )

Set the current busy timeout. The timeout is in milliseconds.

=head2 $dbh->func( $name, $argc, $func_ref, "create_function" )

This method will register a new function which will be useable in SQL
query. The method's parameters are:

=over

=item $name

The name of the function. This is the name of the function as it will
be used from SQL.

=item $argc

The number of arguments taken by the function. If this number is -1,
the function can take any number of arguments.

=item $func_ref

This should be a reference to the function's implementation.

=back

For example, here is how to define a now() function which returns the
current number of seconds since the epoch:

    $dbh->func( 'now', 0, sub { return time }, 'create_function' );

After this, it could be use from SQL as:

    INSERT INTO mytable ( now() );

=head2 $dbh->func( $name, $argc, $pkg, 'create_aggregate' )

This method will register a new aggregate function which can then used
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

This method will be called once for each rows in the aggregate.

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

    SELECT group_name, variance(score) FROM results
    GROUP BY group_name;

=head1 BLOBS

As of version 1.11, blobs should "just work" in SQLite as text columns. However
this will cause the data to be treated as a string, so SQL statements such
as length(x) will return the length of the column as a NUL terminated string,
rather than the size of the blob in bytes. In order to store natively as a
BLOB use the following code:

  use DBI qw(:sql_types);
  my $dbh = DBI->connect("dbi:sqlite:/path/to/db");
  
  my $blob = `cat foo.jpg`;
  my $sth = $dbh->prepare("INSERT INTO mytable VALUES (1, ?)");
  $sth->bind_param(1, $blob, SQL_BLOB);
  $sth->execute();

And then retreival just works:

  $sth = $dbh->prepare("SELECT * FROM mytable WHERE id = 1");
  $sth->execute();
  my $row = $sth->fetch;
  my $blobo = $row->[1];
  
  # now $blobo == $blob

=head1 NOTES

To access the database from the command line, try using dbish which comes with
the DBI module. Just type:

  dbish dbi:SQLite:foo.db

On the command line to access the file F<foo.db>.

Alternatively you can install SQLite from the link above without conflicting
with DBD::SQLite and use the supplied C<sqlite> command line tool.

=head1 PERFORMANCE

SQLite is fast, very fast. I recently processed my 72MB log file with it,
inserting the data (400,000+ rows) by using transactions and only committing
every 1000 rows (otherwise the insertion is quite slow), and then performing
queries on the data.

Queries like count(*) and avg(bytes) took fractions of a second to return,
but what surprised me most of all was:

  SELECT url, count(*) as count FROM access_log
    GROUP BY url
    ORDER BY count desc
    LIMIT 20

To discover the top 20 hit URLs on the site (http://axkit.org), and it
returned within 2 seconds. I'm seriously considering switching my log
analysis code to use this little speed demon!

Oh yeah, and that was with no indexes on the table, on a 400MHz PIII.

For best performance be sure to tune your hdparm settings if you are
using linux. Also you might want to set:

  PRAGMA default_synchronous = OFF

Which will prevent sqlite from doing fsync's when writing (which
slows down non-transactional writes significantly) at the expense of some
peace of mind. Also try playing with the cache_size pragma.

=head1 BUGS

Likely to be many, please use http://rt.cpan.org/ for reporting bugs.

=head1 AUTHOR

Matt Sergeant, matt@sergeant.org

Perl extension functions contributed by Francis J. Lacoste
<flacoste@logreport.org> and Wolfgang Sourdeau
<wolfgang@logreport.org>

=head1 SEE ALSO

L<DBI>.

=cut
