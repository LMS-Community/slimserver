#   -*- cperl -*-

package DBD::mysql;
use strict;
use vars qw(@ISA $VERSION $err $errstr $drh);

use DBI ();
use DynaLoader();
use Carp ();
@ISA = qw(DynaLoader);

$VERSION = '3.0002';

bootstrap DBD::mysql $VERSION;


$err = 0;	# holds error code   for DBI::err
$errstr = "";	# holds error string for DBI::errstr
$drh = undef;	# holds driver handle once initialised

sub driver{
    return $drh if $drh;
    my($class, $attr) = @_;

    $class .= "::dr";

    # not a 'my' since we use it above to prevent multiple drivers
    $drh = DBI::_new_drh($class, 
        { 'Name' => 'mysql',
        'Version' => $VERSION,
        'Err'    => \$DBD::mysql::err,
        'Errstr' => \$DBD::mysql::errstr,
        'Attribution' => 'DBD::mysql by Rudy Lippan and Patrick Galbraith' });

    $drh;
}

sub CLONE {
  undef $drh;
}

sub _OdbcParse($$$) {
    my($class, $dsn, $hash, $args) = @_;
    my($var, $val);
    if (!defined($dsn)) {
	return;
    }
    while (length($dsn)) {
	if ($dsn =~ /([^:;]*)[:;](.*)/) {
	    $val = $1;
	    $dsn = $2;
	} else {
	    $val = $dsn;
	    $dsn = '';
	}
	if ($val =~ /([^=]*)=(.*)/) {
	    $var = $1;
	    $val = $2;
	    if ($var eq 'hostname'  ||  $var eq 'host') {
		$hash->{'host'} = $val;
	    } elsif ($var eq 'db'  ||  $var eq 'dbname') {
		$hash->{'database'} = $val;
	    } else {
		$hash->{$var} = $val;
	    }
	} else {
	    foreach $var (@$args) {
		if (!defined($hash->{$var})) {
		    $hash->{$var} = $val;
		    last;
		}
	    }
	}
    }
}

sub _OdbcParseHost ($$) {
    my($class, $dsn) = @_;
    my($hash) = {};
    $class->_OdbcParse($dsn, $hash, ['host', 'port']);
    ($hash->{'host'}, $hash->{'port'});
}

sub AUTOLOAD {
    my ($meth) = $DBD::mysql::AUTOLOAD;
    my ($smeth) = $meth;
    $smeth =~ s/(.*)\:\://;

    my $val = constant($smeth, @_ ? $_[0] : 0);
    if ($! == 0) { eval "sub $meth { $val }"; return $val; }

    Carp::croak "$meth: Not defined";
}

1;


package DBD::mysql::dr; # ====== DRIVER ======
use strict;
use DBI qw(:sql_types);

sub connect {
    my($drh, $dsn, $username, $password, $attrhash) = @_;
    my($port);
    my($cWarn);
    my $connect_ref= { 'Name' => $dsn };
    my $dbi_imp_data;

    # Avoid warnings for undefined values
    $username ||= '';
    $password ||= '';

    # create a 'blank' dbh
    my($this, $privateAttrHash) = (undef, $attrhash);
    $privateAttrHash = { %$privateAttrHash,
	'Name' => $dsn,
	'user' => $username,
	'password' => $password
    };

    DBD::mysql->_OdbcParse($dsn, $privateAttrHash,
				    ['database', 'host', 'port']);

    
    if ($DBI::VERSION >= 1.49)
    {
      $dbi_imp_data = delete $attrhash->{dbi_imp_data};
      $connect_ref->{'dbi_imp_data'} = $dbi_imp_data;
    }

    if (!defined($this = DBI::_new_dbh($drh,
            $connect_ref,
            $privateAttrHash)))
    {
      return undef;
    }

    # Call msqlConnect func in mSQL.xs file
    # and populate internal handle data.
    DBD::mysql::db::_login($this, $dsn, $username, $password)
	  or $this = undef;

    if ($this && ($ENV{MOD_PERL} || $ENV{GATEWAY_INTERFACE})) {
        $this->{mysql_auto_reconnect} = 1;
    }
    $this;
}

sub data_sources {
    my($self) = shift;
    my($attributes) = shift;
    my($host, $port, $user, $password) = ('', '', '', '');
    if ($attributes) {
      $host = $attributes->{host} || '';
      $port = $attributes->{port} || '';
      $user = $attributes->{user} || '';
      $password = $attributes->{password} || '';
    }
    my(@dsn) = $self->func($host, $port, $user, $password, '_ListDBs');
    my($i);
    for ($i = 0;  $i < @dsn;  $i++) {
	$dsn[$i] = "DBI:mysql:$dsn[$i]";
    }
    @dsn;
}

sub admin {
    my($drh) = shift;
    my($command) = shift;
    my($dbname) = ($command eq 'createdb'  ||  $command eq 'dropdb') ?
	shift : '';
    my($host, $port) = DBD::mysql->_OdbcParseHost(shift(@_) || '');
    my($user) = shift || '';
    my($password) = shift || '';

    $drh->func(undef, $command,
	       $dbname || '',
	       $host || '',
	       $port || '',
	       $user, $password, '_admin_internal');
}

package DBD::mysql::db; # ====== DATABASE ======
use strict;
use DBI qw(:sql_types);

%DBD::mysql::db::db2ANSI = ("INT"   =>  "INTEGER",
			   "CHAR"  =>  "CHAR",
			   "REAL"  =>  "REAL",
			   "IDENT" =>  "DECIMAL"
                          );

### ANSI datatype mapping to mSQL datatypes
%DBD::mysql::db::ANSI2db = ("CHAR"          => "CHAR",
			   "VARCHAR"       => "CHAR",
			   "LONGVARCHAR"   => "CHAR",
			   "NUMERIC"       => "INTEGER",
			   "DECIMAL"       => "INTEGER",
			   "BIT"           => "INTEGER",
			   "TINYINT"       => "INTEGER",
			   "SMALLINT"      => "INTEGER",
			   "INTEGER"       => "INTEGER",
			   "BIGINT"        => "INTEGER",
			   "REAL"          => "REAL",
			   "FLOAT"         => "REAL",
			   "DOUBLE"        => "REAL",
			   "BINARY"        => "CHAR",
			   "VARBINARY"     => "CHAR",
			   "LONGVARBINARY" => "CHAR",
			   "DATE"          => "CHAR",
			   "TIME"          => "CHAR",
			   "TIMESTAMP"     => "CHAR"
			  );

sub prepare {
    my($dbh, $statement, $attribs)= @_;

    # create a 'blank' dbh
    my $sth = DBI::_new_sth($dbh, {'Statement' => $statement});

    # Populate internal handle data.
    if (!DBD::mysql::st::_prepare($sth, $statement, $attribs)) {
	$sth = undef;
    }

    $sth;
}

sub db2ANSI {
    my $self = shift;
    my $type = shift;
    return $DBD::mysql::db::db2ANSI{"$type"};
}

sub ANSI2db {
    my $self = shift;
    my $type = shift;
    return $DBD::mysql::db::ANSI2db{"$type"};
}

sub admin {
    my($dbh) = shift;
    my($command) = shift;
    my($dbname) = ($command eq 'createdb'  ||  $command eq 'dropdb') ?
	shift : '';
    $dbh->{'Driver'}->func($dbh, $command, $dbname, '', '', '',
			   '_admin_internal');
}

sub _SelectDB ($$) {
    die "_SelectDB is removed from this module; use DBI->connect instead.";
}

{
    my $names = ['TABLE_CAT', 'TABLE_SCHEM', 'TABLE_NAME',
		 'TABLE_TYPE', 'REMARKS'];

    sub table_info ($) {
	my $dbh = shift;
	my $sth = $dbh->prepare("SHOW TABLES");
	return undef unless $sth;
	if (!$sth->execute()) {
	  return DBI::set_err($dbh, $sth->err(), $sth->errstr());
        }
	my @tables;
	while (my $ref = $sth->fetchrow_arrayref()) {
	  push(@tables, [ undef, undef, $ref->[0], 'TABLE', undef ]);
        }
	my $dbh2;
	if (!($dbh2 = $dbh->{'~dbd_driver~_sponge_dbh'})) {
	    $dbh2 = $dbh->{'~dbd_driver~_sponge_dbh'} =
		DBI->connect("DBI:Sponge:");
	    if (!$dbh2) {
	        DBI::set_err($dbh, 1, $DBI::errstr);
		return undef;
	    }
	}
	my $sth2 = $dbh2->prepare("SHOW TABLES", { 'rows' => \@tables,
						   'NAME' => $names,
						   'NUM_OF_FIELDS' => 5 });
	if (!$sth2) {
	    DBI::set_err($sth2, $dbh2->err(), $dbh2->errstr());
	}
	$sth2;
    }
}

sub _ListTables {
  my $dbh = shift;
  if (!$DBD::mysql::QUIET) {
    warn "_ListTables is deprecated, use \$dbh->tables()";
  }
  return map { $_ =~ s/.*\.//; $_ } $dbh->tables();
}


sub column_info {
    my ($dbh, $catalog, $schema, $table, $column) = @_;
    return $dbh->set_err(1, "column_info doesn't support table wildcard")
	if $table !~ /^\w+$/;
    return $dbh->set_err(1, "column_info doesn't support column selection")
	if $column ne "%";

    my $table_id = $dbh->quote_identifier($catalog, $schema, $table);

    my @names = qw(
	TABLE_CAT TABLE_SCHEM TABLE_NAME COLUMN_NAME
	DATA_TYPE TYPE_NAME COLUMN_SIZE BUFFER_LENGTH DECIMAL_DIGITS
	NUM_PREC_RADIX NULLABLE REMARKS COLUMN_DEF
	SQL_DATA_TYPE SQL_DATETIME_SUB CHAR_OCTET_LENGTH
	ORDINAL_POSITION IS_NULLABLE CHAR_SET_CAT
	CHAR_SET_SCHEM CHAR_SET_NAME COLLATION_CAT COLLATION_SCHEM COLLATION_NAME
	UDT_CAT UDT_SCHEM UDT_NAME DOMAIN_CAT DOMAIN_SCHEM DOMAIN_NAME
	SCOPE_CAT SCOPE_SCHEM SCOPE_NAME MAX_CARDINALITY
	DTD_IDENTIFIER IS_SELF_REF
	mysql_is_pri_key mysql_type_name mysql_values
    );
    my %col_info;

    local $dbh->{FetchHashKeyName} = 'NAME_lc';
    my $desc_sth = $dbh->prepare("DESCRIBE $table_id");
    my $desc = $dbh->selectall_arrayref($desc_sth, { Columns=>{} });
    my $ordinal_pos = 0;
    foreach my $row (@$desc) {
	my $type = $row->{type};
	$type =~ m/^(\w+)(?:\((.*?)\))?\s*(.*)/;
	my $basetype = lc($1);

	my $info = $col_info{ $row->{field} } = {
	    TABLE_CAT   => $catalog,
	    TABLE_SCHEM => $schema,
	    TABLE_NAME  => $table,
	    COLUMN_NAME => $row->{field},
	    NULLABLE    => ($row->{null} eq 'YES') ? 1 : 0,
	    IS_NULLABLE => ($row->{null} eq 'YES') ? "YES" : "NO",
	    TYPE_NAME   => uc($basetype),
	    COLUMN_DEF  => $row->{default},
	    ORDINAL_POSITION => ++$ordinal_pos,
	    mysql_is_pri_key => ($row->{key}  eq 'PRI'),
	    mysql_type_name  => $row->{type},
	};
	# This code won't deal with a pathalogical case where a value
	# contains a single quote followed by a comma, and doesn't unescape
	# any escaped values. But who would use those in an enum or set?
	my @type_params = ($2 && index($2,"'")>=0)
			? ("$2," =~ /'(.*?)',/g)  # assume all are quoted
			: split /,/, $2||'';      # no quotes, plain list
	s/''/'/g for @type_params;                # undo doubling of quotes
	my @type_attr = split / /, $3||'';
	#warn "$type: $basetype [@type_params] [@type_attr]\n";

	$info->{DATA_TYPE} = SQL_VARCHAR();
	if ($basetype =~ /^(char|varchar|\w*text|\w*blob)/) {
	    $info->{DATA_TYPE} = SQL_CHAR() if $basetype eq 'char';
	    if ($type_params[0]) {
		$info->{COLUMN_SIZE} = $type_params[0];
	    }
	    else {
		$info->{COLUMN_SIZE} = 65535;
		$info->{COLUMN_SIZE} = 255        if $basetype =~ /^tiny/;
		$info->{COLUMN_SIZE} = 16777215   if $basetype =~ /^medium/;
		$info->{COLUMN_SIZE} = 4294967295 if $basetype =~ /^long/;
	    }
	}
	elsif ($basetype =~ /^(binary|varbinary)/) {
	    $info->{COLUMN_SIZE} = $type_params[0];
	    # SQL_BINARY & SQL_VARBINARY are tempting here but don't match the
	    # semantics for mysql (not hex). SQL_CHAR &  SQL_VARCHAR are correct here.
	    $info->{DATA_TYPE} = ($basetype eq 'binary') ? SQL_CHAR() : SQL_VARCHAR();
	}
	elsif ($basetype =~ /^(enum|set)/) {
	    if ($basetype eq 'set') {
		$info->{COLUMN_SIZE} = length(join ",", @type_params);
	    }
	    else {
		my $max_len = 0;
		length($_) > $max_len and $max_len = length($_) for @type_params;
		$info->{COLUMN_SIZE} = $max_len;
	    }
	    $info->{"mysql_values"} = \@type_params;
	}
	elsif ($basetype =~ /int/) { # big/medium/small/tiny etc + unsigned?
	    $info->{DATA_TYPE} = SQL_INTEGER();
	    $info->{NUM_PREC_RADIX} = 10;
	    $info->{COLUMN_SIZE} = $type_params[0];
	}
	elsif ($basetype =~ /^decimal/) {
	    $info->{DATA_TYPE} = SQL_DECIMAL();
	    $info->{NUM_PREC_RADIX} = 10;
	    $info->{COLUMN_SIZE}    = $type_params[0];
	    $info->{DECIMAL_DIGITS} = $type_params[1];
	}
	elsif ($basetype =~ /^(float|double)/) {
	    $info->{DATA_TYPE} = ($basetype eq 'float') ? SQL_FLOAT() : SQL_DOUBLE();
	    $info->{NUM_PREC_RADIX} = 2;
	    $info->{COLUMN_SIZE} = ($basetype eq 'float') ? 32 : 64;
	}
	elsif ($basetype =~ /date|time/) { # date/datetime/time/timestamp
	    if ($basetype eq 'time' or $basetype eq 'date') {
		$info->{DATA_TYPE}   = ($basetype eq 'time') ? SQL_TYPE_TIME() : SQL_TYPE_DATE();
		$info->{COLUMN_SIZE} = ($basetype eq 'time') ? 8 : 10;
	    }
	    else { # datetime/timestamp
		$info->{DATA_TYPE}     = SQL_TYPE_TIMESTAMP();
		$info->{SQL_DATA_TYPE} = SQL_DATETIME();
	        $info->{SQL_DATETIME_SUB} = $info->{DATA_TYPE} - ($info->{SQL_DATA_TYPE} * 10);
		$info->{COLUMN_SIZE}   = ($basetype eq 'datetime') ? 19 : $type_params[0] || 14;
	    }
	    $info->{DECIMAL_DIGITS} = 0; # no fractional seconds
	}
	elsif ($basetype eq 'year') {	# no close standard so treat as int
	    $info->{DATA_TYPE} = SQL_INTEGER();
	    $info->{NUM_PREC_RADIX} = 10;
	    $info->{COLUMN_SIZE} = 4;
	}
	else {
	    Carp::carp("column_info: unrecognized column type '$basetype' of $table_id.$row->{field} treated as varchar");
	}
	$info->{SQL_DATA_TYPE} ||= $info->{DATA_TYPE};
	#warn Dumper($info);
    }

    my $sponge = DBI->connect("DBI:Sponge:", '','')
	or return $dbh->DBI::set_err($DBI::err, "DBI::Sponge: $DBI::errstr");
    my $sth = $sponge->prepare("column_info $table", {
	rows => [ map { [ @{$_}{@names} ] } values %col_info ],
	NUM_OF_FIELDS => scalar @names,
	NAME => \@names,
    }) or return $dbh->DBI::set_err($sponge->err(), $sponge->errstr());

    return $sth;
}



####################
# get_info()
# Generated by DBI::DBD::Metadata

sub get_info {
    my($dbh, $info_type) = @_;
    require DBD::mysql::GetInfo;
    my $v = $DBD::mysql::GetInfo::info{int($info_type)};
    $v = $v->($dbh) if ref $v eq 'CODE';
    return $v;
}



package DBD::mysql::st; # ====== STATEMENT ======
use strict;

1;

__END__

=pod

=head1 NAME

DBD::mysql - MySQL driver for the Perl5 Database Interface (DBI)

=head1 SYNOPSIS

    use DBI;

    $dsn = "DBI:mysql:database=$database;host=$hostname;port=$port";

    $dbh = DBI->connect($dsn, $user, $password);


    $drh = DBI->install_driver("mysql");
    @databases = DBI->data_sources("mysql");
       or
    @databases = DBI->data_sources("mysql",
				   {"host" => $host, "port" => $port});

    $sth = $dbh->prepare("SELECT * FROM foo WHERE bla");
       or
    $sth = $dbh->prepare("LISTFIELDS $table");
       or
    $sth = $dbh->prepare("LISTINDEX $table $index");
    $sth->execute;
    $numRows = $sth->rows;
    $numFields = $sth->{'NUM_OF_FIELDS'};
    $sth->finish;

    $rc = $drh->func('createdb', $database, $host, $user, $password, 'admin');
    $rc = $drh->func('dropdb', $database, $host, $user, $password, 'admin');
    $rc = $drh->func('shutdown', $host, $user, $password, 'admin');
    $rc = $drh->func('reload', $host, $user, $password, 'admin');

    $rc = $dbh->func('createdb', $database, 'admin');
    $rc = $dbh->func('dropdb', $database, 'admin');
    $rc = $dbh->func('shutdown', 'admin');
    $rc = $dbh->func('reload', 'admin');


=head1 EXAMPLE

  #!/usr/bin/perl

  use strict;
  use DBI();

  # Connect to the database.
  my $dbh = DBI->connect("DBI:mysql:database=test;host=localhost",
                         "joe", "joe's password",
                         {'RaiseError' => 1});

  # Drop table 'foo'. This may fail, if 'foo' doesn't exist.
  # Thus we put an eval around it.
  eval { $dbh->do("DROP TABLE foo") };
  print "Dropping foo failed: $@\n" if $@;

  # Create a new table 'foo'. This must not fail, thus we don't
  # catch errors.
  $dbh->do("CREATE TABLE foo (id INTEGER, name VARCHAR(20))");

  # INSERT some data into 'foo'. We are using $dbh->quote() for
  # quoting the name.
  $dbh->do("INSERT INTO foo VALUES (1, " . $dbh->quote("Tim") . ")");

  # Same thing, but using placeholders
  $dbh->do("INSERT INTO foo VALUES (?, ?)", undef, 2, "Jochen");

  # Now retrieve data from the table.
  my $sth = $dbh->prepare("SELECT * FROM foo");
  $sth->execute();
  while (my $ref = $sth->fetchrow_hashref()) {
    print "Found a row: id = $ref->{'id'}, name = $ref->{'name'}\n";
  }
  $sth->finish();

  # Disconnect from the database.
  $dbh->disconnect();


=head1 DESCRIPTION

B<DBD::mysql> is the Perl5 Database Interface driver for the MySQL
database. In other words: DBD::mysql is an interface between the Perl
programming language and the MySQL programming API that comes with
the MySQL relational database management system. Most functions
provided by this programming API are supported. Some rarely used
functions are missing, mainly because noone ever requested
them. :-)

In what follows we first discuss the use of DBD::mysql,
because this is what you will need the most. For installation, see the
sections on L<INSTALLATION>, and L<WIN32 INSTALLATION>
below. See L<EXAMPLE> for a simple example above.

From perl you activate the interface with the statement

    use DBI;

After that you can connect to multiple MySQL database servers
and send multiple queries to any of them via a simple object oriented
interface. Two types of objects are available: database handles and
statement handles. Perl returns a database handle to the connect
method like so:

  $dbh = DBI->connect("DBI:mysql:database=$db;host=$host",
		      $user, $password, {RaiseError => 1});

Once you have connected to a database, you can can execute SQL
statements with:

  my $query = sprintf("INSERT INTO foo VALUES (%d, %s)",
		      $number, $dbh->quote("name"));
  $dbh->do($query);

See L<DBI(3)> for details on the quote and do methods. An alternative
approach is

  $dbh->do("INSERT INTO foo VALUES (?, ?)", undef,
	   $number, $name);

in which case the quote method is executed automatically. See also
the bind_param method in L<DBI(3)>. See L<DATABASE HANDLES> below
for more details on database handles.

If you want to retrieve results, you need to create a so-called
statement handle with:

  $sth = $dbh->prepare("SELECT * FROM $table");
  $sth->execute();

This statement handle can be used for multiple things. First of all
you can retreive a row of data:

  my $row = $sth->fetchow_hashref();

If your table has columns ID and NAME, then $row will be hash ref with
keys ID and NAME. See L<STATEMENT HANDLES> below for more details on
statement handles.

But now for a more formal approach:


=head2 Class Methods

=over

=item B<connect>

    use DBI;

    $dsn = "DBI:mysql:$database";
    $dsn = "DBI:mysql:database=$database;host=$hostname";
    $dsn = "DBI:mysql:database=$database;host=$hostname;port=$port";

    $dbh = DBI->connect($dsn, $user, $password);

A C<database> must always be specified.

=over

=item host

=item port

The hostname, if not specified or specified as '', will default to an
MySQL daemon running on the local machine on the default port
for the UNIX socket.

Should the MySQL daemon be running on a non-standard port number,
you may explicitly state the port number to connect to in the C<hostname>
argument, by concatenating the I<hostname> and I<port number> together
separated by a colon ( C<:> ) character or by using the  C<port> argument.


=item mysql_client_found_rows

Enables (TRUE value) or disables (FALSE value) the flag CLIENT_FOUND_ROWS
while connecting to the MySQL server. This has a somewhat funny effect:
Without mysql_client_found_rows, if you perform a query like

  UPDATE $table SET id = 1 WHERE id = 1

then the MySQL engine will always return 0, because no rows have changed.
With mysql_client_found_rows however, it will return the number of rows
that have an id 1, as some people are expecting. (At least for compatibility
to other engines.)

=item mysql_compression

As of MySQL 3.22.3, a new feature is supported: If your DSN contains
the option "mysql_compression=1", then the communication between client
and server will be compressed.

=item mysql_connect_timeout

If your DSN contains the option "mysql_connect_timeout=##", the connect
request to the server will timeout if it has not been successful after
the given number of seconds.

=item mysql_read_default_file

=item mysql_read_default_group

These options can be used to read a config file like /etc/my.cnf or
~/.my.cnf. By default MySQL's C client library doesn't use any config
files unlike the client programs (mysql, mysqladmin, ...) that do, but
outside of the C client library. Thus you need to explicitly request
reading a config file, as in

    $dsn = "DBI:mysql:test;mysql_read_default_file=/home/joe/my.cnf";
    $dbh = DBI->connect($dsn, $user, $password)

The option mysql_read_default_group can be used to specify the default
group in the config file: Usually this is the I<client> group, but
see the following example:

    [client]
    host=localhost

    [perl]
    host=perlhost

(Note the order of the entries! The example won't work, if you reverse
the [client] and [perl] sections!)

If you read this config file, then you'll be typically connected to
I<localhost>. However, by using

    $dsn = "DBI:mysql:test;mysql_read_default_group=perl;"
        . "mysql_read_default_file=/home/joe/my.cnf";
    $dbh = DBI->connect($dsn, $user, $password);

you'll be connected to I<perlhost>. Note that if you specify a
default group and do not specify a file, then the default config
files will all be read.  See the documentation of
the C function mysql_options() for details.

=item mysql_socket

As of MySQL 3.21.15, it is possible to choose the Unix socket that is
used for connecting to the server. This is done, for example, with

    mysql_socket=/dev/mysql

Usually there's no need for this option, unless you are using another
location for the socket than that built into the client.

=item mysql_ssl

A true value turns on the CLIENT_SSL flag when connecting to the MySQL
database:

  mysql_ssl=1

This means that your communication with the server will be encrypted.

If you turn mysql_ssl on, you might also wish to use the following
flags:

=item mysql_ssl_client_key

=item mysql_ssl_client_cert

=item mysql_ssl_ca_file

=item mysql_ssl_ca_path

=item mysql_ssl_cipher

These are used to specify the respective parameters of a call
to mysql_ssl_set, if mysql_ssl is turned on.  


=item mysql_local_infile

As of MySQL 3.23.49, the LOCAL capability for LOAD DATA may be disabled
in the MySQL client library by default. If your DSN contains the option
"mysql_local_infile=1", LOAD DATA LOCAL will be enabled.  (However,
this option is *ineffective* if the server has also been configured to
disallow LOCAL.)

=item Prepared statement support (server side prepare)

To use server side prepared statements, all you need to do is set the variable 
mysql_server_prepare in the connect:

$dbh = DBI->connect(
                    "DBI:mysql:database=test;host=localhost:mysql_server_prepare=1",
                    "",
                    "",
                    { RaiseError => 1, AutoCommit => 1 }
                    );

To make sure that the 'make test' step tests whether server prepare works, you just
need to export the env variable MYSQL_SERVER_PREPARE:

export MYSQL_SERVER_PREPARE=1

Test first without server side prepare, then with.


=item mysql_embedded_options

The option <mysql_embedded_options> can be used to pass 'command-line' 
options to embedded server.

Example:

$testdsn="DBI:mysqlEmb:database=test;mysql_embedded_options=--help,--verbose";


=item mysql_embedded_groups

The option <mysql_embedded_groups> can be used to specify the groups in the 
config file(I<my.cnf>) which will be used to get options for embedded server. 
If not specified [server] and [embedded] groups will be used.

Example:

$testdsn="DBI:mysqlEmb:database=test;mysql_embedded_groups=embedded_server,common";


=back

=back


=head2 Private MetaData Methods

=over

=item B<ListDBs>

    my $drh = DBI->install_driver("mysql");
    @dbs = $drh->func("$hostname:$port", '_ListDBs');
    @dbs = $drh->func($hostname, $port, '_ListDBs');
    @dbs = $dbh->func('_ListDBs');

Returns a list of all databases managed by the MySQL daemon
running on C<$hostname>, port C<$port>. This method
is rarely needed for databases running on C<localhost>: You should
use the portable method

    @dbs = DBI->data_sources("mysql");

whenever possible. It is a design problem of this method, that there's
no way of supplying a host name or port number to C<data_sources>, that's
the only reason why we still support C<ListDBs>. :-(

=back


=head2 Server Administration

=over

=item admin

    $rc = $drh->func("createdb", $dbname, [host, user, password,], 'admin');
    $rc = $drh->func("dropdb", $dbname, [host, user, password,], 'admin');
    $rc = $drh->func("shutdown", [host, user, password,], 'admin');
    $rc = $drh->func("reload", [host, user, password,], 'admin');

      or

    $rc = $dbh->func("createdb", $dbname, 'admin');
    $rc = $dbh->func("dropdb", $dbname, 'admin');
    $rc = $dbh->func("shutdown", 'admin');
    $rc = $dbh->func("reload", 'admin');

For server administration you need a server connection. For obtaining
this connection you have two options: Either use a driver handle (drh)
and supply the appropriate arguments (host, defaults localhost, user,
defaults to '' and password, defaults to ''). A driver handle can be
obtained with

    $drh = DBI->install_driver('mysql');

Otherwise reuse the existing connection of a database handle (dbh).

There's only one function available for administrative purposes, comparable
to the m(y)sqladmin programs. The command being execute depends on the
first argument:

=over

=item createdb

Creates the database $dbname. Equivalent to "m(y)sqladmin create $dbname".

=item dropdb

Drops the database $dbname. Equivalent to "m(y)sqladmin drop $dbname".

It should be noted that database deletion is
I<not prompted for> in any way.  Nor is it undo-able from DBI.

    Once you issue the dropDB() method, the database will be gone!

These method should be used at your own risk.

=item shutdown

Silently shuts down the database engine. (Without prompting!)
Equivalent to "m(y)sqladmin shutdown".

=item reload

Reloads the servers configuration files and/or tables. This can be particularly
important if you modify access privileges or create new users.

=back

=back


=head1 DATABASE HANDLES

The DBD::mysql driver supports the following attributes of database
handles (read only):

  $errno = $dbh->{'mysql_errno'};
  $error = $dbh->{'mysql_error};
  $info = $dbh->{'mysql_hostinfo'};
  $info = $dbh->{'mysql_info'};
  $insertid = $dbh->{'mysql_insertid'};
  $info = $dbh->{'mysql_protoinfo'};
  $info = $dbh->{'mysql_serverinfo'};
  $info = $dbh->{'mysql_stat'};
  $threadId = $dbh->{'mysql_thread_id'};

These correspond to mysql_errno(), mysql_error(), mysql_get_host_info(),
mysql_info(), mysql_insert_id(), mysql_get_proto_info(),
mysql_get_server_info(), mysql_stat() and mysql_thread_id(),
respectively.


 $info_hashref = $dhb->{mysql_dbd_stats}

DBD::mysql keeps track of some statistics in the mysql_dbd_stats attribute.
The following stats are being maintained:

=over

=item auto_reconnects_ok

The number of times that DBD::mysql successfully reconnected to the mysql 
server.

=item auto_reconnects_failed

The number of times that DBD::mysql tried to reconnect to mysql but failed.

=back

The DBD::mysql driver also supports the following attribute(s) of database
handles (read/write):

 $bool_value = $dbh->{mysql_auto_reconnect};
 $dbh->{mysql_auto_reconnect} = $AutoReconnect ? 1 : 0;


=item mysql_auto_reconnect

This attribute determines whether DBD::mysql will automatically reconnect
to mysql if the connection be lost. This feature defaults to off; however,
if either the GATEWAY_INTERFACE or MOD_PERL envionment variable is set, 
DBD::mysql will turn mysql_auto_reconnect on.  Setting mysql_auto_reconnect 
to on is not advised if 'lock tables' is used because if DBD::mysql reconnect 
to mysql all table locks will be lost.  This attribute is ignored when
AutoCommit is turned off, and when AutoCommit is turned off, DBD::mysql will
not automatically reconnect to the server.

=item mysql_use_result

This attribute forces the driver to use mysql_use_result rather than
mysql_store_result. The former is faster and less memory consuming, but
tends to block other processes. (That's why mysql_store_result is the
default.)

It is possible to set default value of the C<mysql_use_result> attribute 
for $dbh using several ways:

 - through DSN 

   $dbh= DBI->connect("DBI:mysql:test;mysql_use_result=1", "root", "");

 - after creation of database handle

   $dbh->{'mysql_use_result'}=0; #disable
   $dbh->{'mysql_use_result'}=1; #enable

It is possible to set/unset the C<mysql_use_result> attribute after 
creation of statement handle. See below.


=head1 STATEMENT HANDLES

The statement handles of DBD::mysql support a number
of attributes. You access these by using, for example,

  my $numFields = $sth->{'NUM_OF_FIELDS'};

Note, that most attributes are valid only after a successfull I<execute>.
An C<undef> value will returned in that case. The most important exception
is the C<mysql_use_result> attribute: This forces the driver to use
mysql_use_result rather than mysql_store_result. The former is faster
and less memory consuming, but tends to block other processes. (That's why
mysql_store_result is the default.)

To set the C<mysql_use_result> attribute, use either of the following:

  my $sth = $dbh->prepare("QUERY", { "mysql_use_result" => 1});

or

  my $sth = $dbh->prepare("QUERY");
  $sth->{"mysql_use_result"} = 1;

Column dependent attributes, for example I<NAME>, the column names,
are returned as a reference to an array. The array indices are
corresponding to the indices of the arrays returned by I<fetchrow>
and similar methods. For example the following code will print a
header of table names together with all rows:

  my $sth = $dbh->prepare("SELECT * FROM $table");
  if (!$sth) {
      die "Error:" . $dbh->errstr . "\n";
  }
  if (!$sth->execute) {
      die "Error:" . $sth->errstr . "\n";
  }
  my $names = $sth->{'NAME'};
  my $numFields = $sth->{'NUM_OF_FIELDS'};
  for (my $i = 0;  $i < $numFields;  $i++) {
      printf("%s%s", $i ? "," : "", $$names[$i]);
  }
  print "\n";
  while (my $ref = $sth->fetchrow_arrayref) {
      for (my $i = 0;  $i < $numFields;  $i++) {
	  printf("%s%s", $i ? "," : "", $$ref[$i]);
      }
      print "\n";
  }

For portable applications you should restrict yourself to attributes with
capitalized or mixed case names. Lower case attribute names are private
to DBD::mysql. The attribute list includes:

=over

=item ChopBlanks

this attribute determines whether a I<fetchrow> will chop preceding
and trailing blanks off the column values. Chopping blanks does not
have impact on the I<max_length> attribute.

=item mysql_insertid

MySQL has the ability to choose unique key values automatically. If this
happened, the new ID will be stored in this attribute. An alternative
way for accessing this attribute is via $dbh->{'mysql_insertid'}.
(Note we are using the $dbh in this case!)

=item mysql_is_blob

Reference to an array of boolean values; TRUE indicates, that the
respective column is a blob. This attribute is valid for MySQL only.

=item mysql_is_key

Reference to an array of boolean values; TRUE indicates, that the
respective column is a key. This is valid for MySQL only.

=item mysql_is_num

Reference to an array of boolean values; TRUE indicates, that the
respective column contains numeric values.

=item mysql_is_pri_key

Reference to an array of boolean values; TRUE indicates, that the
respective column is a primary key.

=item mysql_is_auto_increment

Reference to an array of boolean values; TRUE indicates that the
respective column is an AUTO_INCREMENT column.  This is only valid
for MySQL.

=item mysql_length

=item mysql_max_length

A reference to an array of maximum column sizes. The I<max_length> is
the maximum physically present in the result table, I<length> gives
the theoretically possible maximum. I<max_length> is valid for MySQL
only.

=item NAME

A reference to an array of column names.

=item NULLABLE

A reference to an array of boolean values; TRUE indicates that this column
may contain NULL's.

=item NUM_OF_FIELDS

Number of fields returned by a I<SELECT> or I<LISTFIELDS> statement.
You may use this for checking whether a statement returned a result:
A zero value indicates a non-SELECT statement like I<INSERT>,
I<DELETE> or I<UPDATE>.

=item mysql_table

A reference to an array of table names, useful in a I<JOIN> result.

=item TYPE

A reference to an array of column types. The engine's native column
types are mapped to portable types like DBI::SQL_INTEGER() or
DBI::SQL_VARCHAR(), as good as possible. Not all native types have
a meaningfull equivalent, for example DBD::mysql::FIELD_TYPE_INTERVAL
is mapped to DBI::SQL_VARCHAR().
If you need the native column types, use I<mysql_type>. See below.

=item mysql_type

A reference to an array of MySQL's native column types, for example
DBD::mysql::FIELD_TYPE_SHORT() or DBD::mysql::FIELD_TYPE_STRING().
Use the I<TYPE> attribute, if you want portable types like
DBI::SQL_SMALLINT() or DBI::SQL_VARCHAR().

=item mysql_type_name

Similar to mysql, but type names and not numbers are returned.
Whenever possible, the ANSI SQL name is preferred.

=back


=head1 TRANSACTION SUPPORT

Beginning with DBD::mysql 2.0416, transactions are supported.
The transaction support works as follows:

=over

=item *

By default AutoCommit mode is on, following the DBI specifications.

=item *

If you execute

    $dbh->{'AutoCommit'} = 0;

or

    $dbh->{'AutoCommit'} = 1;

then the driver will set the MySQL server variable autocommit to 0 or
1, respectively. Switching from 0 to 1 will also issue a COMMIT,
following the DBI specifications.

=item *

The methods

    $dbh->rollback();
    $dbh->commit();

will issue the commands COMMIT and ROLLBACK, respectively. A
ROLLBACK will also be issued if AutoCommit mode is off and the
database handles DESTROY method is called. Again, this is following
the DBI specifications.

=back

Given the above, you should note the following:

=over

=item *

You should never change the server variable autocommit manually,
unless you are ignoring DBI's transaction support.

=item *

Switching AutoCommit mode from on to off or vice versa may fail.
You should always check for errors, when changing AutoCommit mode.
The suggested way of doing so is using the DBI flag RaiseError.
If you don't like RaiseError, you have to use code like the
following:

  $dbh->{'AutoCommit'} = 0;
  if ($dbh->{'AutoCommit'}) {
    # An error occurred!
  }

=item *

If you detect an error while changing the AutoCommit mode, you
should no longer use the database handle. In other words, you
should disconnect and reconnect again, because the transaction
mode is unpredictable. Alternatively you may verify the transaction
mode by checking the value of the server variable autocommit.
However, such behaviour isn't portable.

=item *

DBD::mysql has a "reconnect" feature that handles the so-called
MySQL "morning bug": If the server has disconnected, most probably
due to a timeout, then by default the driver will reconnect and
attempt to execute the same SQL statement again. However, this
behaviour is disabled when AutoCommit is off: Otherwise the
transaction state would be completely unpredictable after a
reconnect.  

=item *

The "reconnect" feature of DBD::mysql can be toggled by using the
L<mysql_auto_reconnect> attribute. This behaviour should be turned off
in code that uses LOCK TABLE because if the database server time out
and DBD::mysql reconnect, table locks will be lost without any 
indication of such loss.

=back


=head1 SQL EXTENSIONS

Certain metadata functions of MySQL that are available on the
C API level, haven't been implemented here. Instead they are implemented
as "SQL extensions" because they return in fact nothing else but the
equivalent of a statement handle. These are:

=over

=item LISTFIELDS $table

Returns a statement handle that describes the columns of $table.
Ses the docs of mysql_list_fields (C API) for details.

=back



=head1 COMPATIBILITY ALERT

The statement attribute I<TYPE> has changed its meaning, as of
DBD::mysql 2.0119. Formerly it used to be the an array
of native engine's column types, but it is now an array of
portable SQL column types. The old attribute is still available
as I<mysql_type>.

DBD::mysql is a moving target, due to a number of reasons:

=over

=item -

Of course we have to conform the DBI guidelines and developments.

=item -

We have to keep track with the latest MySQL developments.

=item -

And, surprisingly, we have to be as close to ODBC as possible: This is
due to the current direction of DBI.

=item -

And, last not least, as any tool it has a little bit life of its own.

=back

This means that a lot of things had to and have to be changed.
As I am not interested in maintaining a lot of compatibility kludges,
which only increase the drivers code without being really usefull,
I did and will remove some features, methods or attributes.

To ensure a smooth upgrade, the following policy will be applied:

=over

=item Obsolete features

The first step is to declare something obsolete. This means, that no code
is changed, but the feature appears in the list of obsolete features. See
L<Obsolete Features> below.

=item Deprecated features

If the feature has been obsolete for quite some time, typically in the
next major stable release, warnings will be inserted in the code. You
can suppress these warnings by setting

    $DBD::mysql = 1;

In the docs the feature will be moved from the list of obsolete features
to the list of deprecated features. See L<Deprecated Features> below.

=item Removing features

Finally features will be removed silently in the next major stable
release. The feature will be shown in the list of historic features.
See L<Historic Features> below.

=back

Example: The statement handle attribute

    $sth->{'LENGTH'}

was declared obsolete in DBD::mysql 2.00xy. It was considered
deprecated in DBD::mysql 2.02xy and removed in 2.04xy.


=head2 Obsolete Features

=over

=item Database handle attributes

The following database handle attributes are declared obsolete
in DBD::mysql 2.09. They will be deprecated in 2.11 and removed
in 2.13.

=over

=item C<$dbh->{'errno'}>

Replaced by C<$dbh->{'mysql_errno'}>

=item C<$dbh->{'errmsg'}>

Replaced by C<$dbh->{'mysql_error'}>

=item C<$dbh->{'hostinfo'}>

Replaced by C<$dbh->{'mysql_hostinfo'}>

=item C<$dbh->{'info'}>

Replaced by C<$dbh->{'mysql_info'}>

=item C<$dbh->{'protoinfo'}>

Replaced by C<$dbh->{'mysql_protoinfo'}>

=item C<$dbh->{'serverinfo'}>

Replaced by C<$dbh->{'mysql_serverinfo'}>

=item C<$dbh->{'stats'}>

Replaced by C<$dbh->{'mysql_stat'}>

=item C<$dbh->{'thread_id'}>

Replaced by C<$dbh->{'mysql_thread_id'}>

=back

=back


=head2 Deprecated Features

=over

=item _ListTables

Replace with the standard DBI method C<$dbh->tables()>. See also
C<$dbh->table_info()>. Portable applications will prefer

    @tables = map { $_ =~ s/.*\.//; $_ } $dbh->tables()

because, depending on the engine, the string "user.table" will be
returned, user being the table owner. The method will be removed
in DBD::mysql version 2.11xy.

=back


=head2 Historic Features

=over

=item _CreateDB

=item _DropDB

The methods

    $dbh->func($db, '_CreateDB');
    $dbh->func($db, '_DropDB');

have been used for creating or dropping databases. They have been removed
in 1.21_07 in favour of

    $drh->func("createdb", $dbname, $host, "admin")
    $drh->func("dropdb", $dbname, $host, "admin")

=item _ListFields

The method

    $sth = $dbh->func($table, '_ListFields');

has been used to list a tables columns names, types and other attributes.
This method has been removed in 1.21_07 in favour of

    $sth = $dbh->prepare("LISTFIELDS $table");

=item _ListSelectedFields

The method

    $sth->func('_ListSelectedFields');

use to return a hash ref of attributes like 'IS_NUM', 'IS_KEY' and so
on. These attributes are now accessible via

    $sth->{'mysql_is_num'};
    $sth->{'mysql_is_key'};

and so on. Thus the method has been removed in 1.21_07.

=item _NumRows

The method

    $sth->func('_NumRows');

used to be equivalent to

    $sth->rows();

and has been removed in 1.21_07.

=item _InsertID

The method

    $dbh->func('_InsertID');

used to be equivalent with

    $dbh->{'mysql_insertid'};

=item Statement handle attributes

=over

=item affected_rows

Replaced with $sth->{'mysql_affected_rows'} or the result
of $sth->execute().

=item format_default_size

Replaced with $sth->{'PRECISION'}.

=item format_max_size

Replaced with $sth->{'mysql_max_length'}.

=item format_type_name

Replaced with $sth->{'TYPE'} (portable) or
$sth->{'mysql_type_name'} (MySQL specific).

=item format_right_justify

Replaced with $sth->->{'TYPE'} (portable) or
$sth->{'mysql_is_num'} (MySQL specific).

=item insertid

Replaced with $sth->{'mysql_insertid'}.

=item IS_BLOB

Replaced with $sth->{'TYPE'} (portable) or
$sth->{'mysql_is_blob'} (MySQL specific).

=item is_blob

Replaced with $sth->{'TYPE'} (portable) or
$sth->{'mysql_is_blob'} (MySQL specific).

=item IS_PRI_KEY

Replaced with $sth->{'mysql_is_pri_key'}.

=item is_pri_key

Replaced with $sth->{'mysql_is_pri_key'}.

=item IS_NOT_NULL

Replaced with $sth->{'NULLABLE'} (do not forget to invert
the boolean values).

=item is_not_null

Replaced with $sth->{'NULLABLE'} (do not forget to invert
the boolean values).

=item IS_NUM

Replaced with $sth->{'TYPE'} (portable) or
$sth->{'mysql_is_num'} (MySQL specific).

=item is_num

Replaced with $sth->{'TYPE'} (portable) or
$sth->{'mysql_is_num'} (MySQL specific).

=item IS_KEY

Replaced with $sth->{'mysql_is_key'}.

=item is_key

Replaced with $sth->{'mysql_is_key'}.

=item MAXLENGTH

Replaced with $sth->{'mysql_max_length'}.

=item maxlength

Replaced with $sth->{'mysql_max_length'}.

=item LENGTH

Replaced with $sth->{'PRECISION'} (portable) or
$sth->{'mysql_length'} (MySQL specific)

=item length

Replaced with $sth->{'PRECISION'} (portable) or
$sth->{'mysql_length'} (MySQL specific)

=item NUMFIELDS

Replaced with $sth->{'NUM_OF_FIELDS'}.

=item numfields

Replaced with $sth->{'NUM_OF_FIELDS'}.

=item NUMROWS

Replaced with the result of $sth->execute() or
$sth->{'mysql_affected_rows'}.

=item TABLE

Replaced with $sth->{'mysql_table'}.

=item table

Replaced with $sth->{'mysql_table'}.

=back

=back


=head1 MULTITHREADING

The multithreading capabilities of DBD::mysql depend completely
on the underlying C libraries: The modules are working with handle data
only, no global variables are accessed or (to the best of my knowledge)
thread unsafe functions are called. Thus DBD::mysql is believed
to be completely thread safe, if the C libraries are thread safe
and you don't share handles among threads.

The obvious question is: Are the C libraries thread safe?
In the case of MySQL the answer is "mostly" and, in theory, you should
be able to get a "yes", if the C library is compiled for being thread
safe (By default it isn't.) by passing the option -with-thread-safe-client
to configure. See the section on I<How to make a threadsafe client> in
the manual.


=head1 INSTALLATION

Windows users may skip this section and pass over to L<WIN32
INSTALLATION> below. Others, go on reading.

First of all, you do not need an installed MySQL server for installing
DBD::mysql. However, you need at least the client
libraries and possibly the header files, if you are compiling DBD::mysql
from source. In the case of MySQL you can create a
client-only version by using the configure option --without-server.
If you are using precompiled binaries, then it may be possible to
use just selected RPM's like MySQL-client and MySQL-devel or something
similar, depending on the distribution.

First you need to install the DBI module. For using I<dbimon>, a
simple DBI shell it is recommended to install Data::ShowTable another
Perl module.

I recommend trying automatic installation via the CPAN module. Try

  perl -MCPAN -e shell

If you are using the CPAN module for the first time, it will prompt
you a lot of questions. If you finally receive the CPAN prompt, enter

  install Bundle::DBD::mysql

If this fails (which may be the case for a number of reasons, for
example because you are behind a firewall or don't have network
access), you need to do a manual installation. First of all you
need to fetch the archives from any CPAN mirror, for example

  ftp://ftp.funet.fi/pub/languages/perl/CPAN/modules/by-module

The following archives are required (version numbers may have
changed, I choose those which are current as of this writing):

  DBI/DBI-1.15.tar.gz
  Data/Data-ShowTable-3.3.tar.gz
  DBD/DBD-mysql-2.1001.tar.gz

Then enter the following commands:

  gzip -cd DBI-1.15.tar.gz | tar xf -
  cd DBI-1.15
  perl Makefile.PL
  make
  make test
  make install

  cd ..
  gzip -cd Data-ShowTable-3.3.tar.gz | tar xf -
  cd Data-ShowTable-3.3
  perl Makefile.PL
  make
  make install  # Don't try make test, the test suite is broken

  cd ..
  gzip -cd DBD-mysql-2.1001.tar.gz | tar xf -
  cd DBD-mysql-2.1001
  perl Makefile.PL
  make
  make test
  make install

During "perl Makefile.PL" you will be prompted some questions.
Other questions are the directories with header files and libraries.
For example, of your file F<mysql.h> is in F</usr/include/mysql/mysql.h>,
then enter the header directory F</usr>, likewise for
F</usr/lib/mysql/libmysqlclient.a> or F</usr/lib/libmysqlclient.so>.


=head1 WIN32 INSTALLATION

If you are using ActivePerl, you may use ppm to install DBD-mysql.
For Perl 5.6, upgrade to Build 623 or later, then it is sufficient
to run

  ppm install DBI
  ppm install DBD::mysql

If you need an HTTP proxy, you might need to set the environment
variable http_proxy, for example like this:

  set http_proxy=http://myproxy.com:8080/

As of this writing, DBD::mysql is missing in the ActivePerl 5.8.0
repository. However, Randy Kobes has kindly donated an own
distribution and the following might succeed:

  ppm install http://theoryx5.uwinnipeg.ca/ppms/DBD-mysql.ppd

Otherwise you definitely *need* a C compiler. And it *must* be the same
compiler that was being used for compiling Perl itself. If you don't
have a C compiler, the file README.win32 from the Perl source
distribution tells you where to obtain freely distributable C compilers
like egcs or gcc. The Perl sources are available on any CPAN mirror in
the src directory, for example

    ftp://ftp.funet.fi/pub/languages/perl/CPAN/src/latest.tar.gz

I recommend using the win32clients package for installing DBD::mysql
under Win32, available for download on www.tcx.se. The following steps
have been required for me:

=over

=item -

The current Perl versions (5.6, as of this writing) do have a problem
with detecting the C libraries. I recommend to apply the following
patch:

  *** c:\Perl\lib\ExtUtils\Liblist.pm.orig Sat Apr 15 20:03:40 2000
  --- c:\Perl\lib\ExtUtils\Liblist.pm      Sat Apr 15 20:03:45 2000
  ***************
  *** 230,235 ****
  --- 230,239 ----
      # add "$Config{installarchlib}/CORE" to default search path
      push @libpath, "$Config{installarchlib}/CORE";

  +     if ($VC  and  exists($ENV{LIB})  and  defined($ENV{LIB})) {
  +       push(@libpath, split(/;/, $ENV{LIB}));
  +     }
  +
      foreach (Text::ParseWords::quotewords('\s+', 0, $potential_libs)){

        $thislib = $_;
                                                                       
=item -

Extract sources into F<C:\>. This will create a directory F<C:\mysql>
with subdirectories include and lib.

IMPORTANT: Make sure this subdirectory is not shared by other TCX
files! In particular do *not* store the MySQL server in the same
directory. If the server is already installed in F<C:\mysql>,
choose a location like F<C:\tmp>, extract the win32clients there.
Note that you can remove this directory entirely once you have
installed DBD::mysql.

=item -

Extract the DBD::mysql sources into another directory, for
example F<C:\src\siteperl>

=item -

Open a DOS shell and change directory to F<C:\src\siteperl>.

=item -

The next step is only required if you repeat building the modules: Make
sure that you have a clean build tree by running

  nmake realclean

If you don't have VC++, replace nmake with your flavour of make. If
error messages are reported in this step, you may safely ignore them.

=item -

Run

  perl Makefile.PL

which will prompt you for some settings. The really important ones are:

  Which DBMS do you want to use?

enter a 1 here (MySQL only), and

  Where is your mysql installed? Please tell me the directory that
  contains the subdir include.

where you have to enter the win32clients directory, for example
F<C:\mysql> or F<C:\tmp\mysql>.

=item -

Continued in the usual way:

  nmake
  nmake install

=back

If you want to create a PPM package for the ActiveState Perl version, then
modify the above steps as follows: Run

  perl Makefile.PL NAME=DBD-mysql BINARY_LOCATION=DBD-mysql.tar.gz
  nmake ppd
  nmake

Once that is done, use tar and gzip (for example those from the CygWin32
distribution) to create an archive:

  mkdir x86
  tar cf x86/DBD-mysql.tar blib
  gzip x86/DBD-mysql.tar

Put the files x86/DBD-mysql.tar.gz and DBD-mysql.ppd onto some WWW server
and install them by typing

  install http://your.server.name/your/directory/DBD-mysql.ppd

in the PPM program.


=head1 AUTHORS

The current version of B<DBD::mysql> is almost completely written
by Jochen Wiedmann, and is now being maintained by
Rudy Lippan (I<rlippan@remotelinux.com>). The first version's author
was Alligator Descartes (I<descarte@symbolstone.org>), who has been
aided and abetted by Gary Shea, Andreas König and Tim Bunce
amongst others.

The B<Mysql> module was originally written by Andreas König
<koenig@kulturbox.de>. The current version, mainly an emulation
layer, is from Jochen Wiedmann.


=head1 COPYRIGHT


This module is Copyright (c) 2003 Rudolf Lippan; Large Portions 
Copyright (c) 1997-2003 Jochen Wiedmann, with code portions 
Copyright (c)1994-1997 their original authors This module is
released under the same license as Perl itself. See the Perl README
for details.


=head1 MAILING LIST SUPPORT

This module is maintained and supported on a mailing list,

    perl@lists.mysql.com

To subscribe to this list, send a mail to

    perl-subscribe@lists.mysql.com

or

    perl-digest-subscribe@lists.mysql.com

Mailing list archives are available at

    http://www.progressive-comp.com/Lists/?l=msql-mysql-modules


Additionally you might try the dbi-user mailing list for questions about
DBI and its modules in general. Subscribe via

    http://www.fugue.com/dbi

Mailing list archives are at

     http://www.rosat.mpe-garching.mpg.de/mailing-lists/PerlDB-Interest/
     http://outside.organic.com/mail-archives/dbi-users/
     http://www.coe.missouri.edu/~faq/lists/dbi.html


=head1 ADDITIONAL DBI INFORMATION

Additional information on the DBI project can be found on the World
Wide Web at the following URL:

    http://www.symbolstone.org/technology/perl/DBI

where documentation, pointers to the mailing lists and mailing list
archives and pointers to the most current versions of the modules can
be used.

Information on the DBI interface itself can be gained by typing:

    perldoc DBI

right now!

=cut


