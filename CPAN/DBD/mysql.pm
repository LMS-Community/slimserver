#   -*- cperl -*-

package DBD::mysql;
use strict;
use vars qw(@ISA $VERSION $err $errstr $drh);

use DBI ();
use DynaLoader();
use Carp ();
@ISA = qw(DynaLoader);

$VERSION = '4.011';

bootstrap DBD::mysql $VERSION;


$err = 0;	# holds error code   for DBI::err
$errstr = "";	# holds error string for DBI::errstr
$drh = undef;	# holds driver handle once initialised

sub driver{
    return $drh if $drh;
    my($class, $attr) = @_;

    $class .= "::dr";

    # not a 'my' since we use it above to prevent multiple drivers
    $drh = DBI::_new_drh($class, { 'Name' => 'mysql',
				   'Version' => $VERSION,
				   'Err'    => \$DBD::mysql::err,
				   'Errstr' => \$DBD::mysql::errstr,
				   'Attribution' => 'DBD::mysql by Patrick Galbraith'
				 });

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
use DBI::Const::GetInfoType;

sub connect {
    my($drh, $dsn, $username, $password, $attrhash) = @_;
    my($port);
    my($cWarn);
    my $connect_ref= { 'Name' => $dsn };
    my $dbi_imp_data;

    # Avoid warnings for undefined values
    $username ||= '';
    $password ||= '';
    $attrhash ||= {};

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

sub table_info ($) {
  my ($dbh, $catalog, $schema, $table, $type, $attr) = @_;
  $dbh->{mysql_server_prepare}||= 0;
  my $mysql_server_prepare_save= $dbh->{mysql_server_prepare};
  $dbh->{mysql_server_prepare}= 0;
  my @names = qw(TABLE_CAT TABLE_SCHEM TABLE_NAME TABLE_TYPE REMARKS);
  my @rows;

  my $sponge = DBI->connect("DBI:Sponge:", '','')
    or return $dbh->DBI::set_err($DBI::err, "DBI::Sponge: $DBI::errstr");

# Return the list of catalogs
  if (defined $catalog && $catalog eq "%" &&
      (!defined($schema) || $schema eq "") &&
      (!defined($table) || $table eq ""))
  {
    @rows = (); # Empty, because MySQL doesn't support catalogs (yet)
  }
  # Return the list of schemas
  elsif (defined $schema && $schema eq "%" &&
      (!defined($catalog) || $catalog eq "") &&
      (!defined($table) || $table eq ""))
  {
    my $sth = $dbh->prepare("SHOW DATABASES")
      or ($dbh->{mysql_server_prepare}= $mysql_server_prepare_save && 
          return undef);

    $sth->execute()
      or ($dbh->{mysql_server_prepare}= $mysql_server_prepare_save && 
        return DBI::set_err($dbh, $sth->err(), $sth->errstr()));

    while (my $ref = $sth->fetchrow_arrayref())
    {
      push(@rows, [ undef, $ref->[0], undef, undef, undef ]);
    }
  }
  # Return the list of table types
  elsif (defined $type && $type eq "%" &&
      (!defined($catalog) || $catalog eq "") &&
      (!defined($schema) || $schema eq "") &&
      (!defined($table) || $table eq ""))
  {
    @rows = (
        [ undef, undef, undef, "TABLE", undef ],
        [ undef, undef, undef, "VIEW",  undef ],
        );
  }
  # Special case: a catalog other than undef, "", or "%"
  elsif (defined $catalog && $catalog ne "" && $catalog ne "%")
  {
    @rows = (); # Nothing, because MySQL doesn't support catalogs yet.
  }
  # Uh oh, we actually have a meaty table_info call. Work is required!
  else
  {
    my @schemas;
    # If no table was specified, we want them all
    $table ||= "%";

    # If something was given for the schema, we need to expand it to
    # a list of schemas, since it may be a wildcard.
    if (defined $schema && $schema ne "")
    {
      my $sth = $dbh->prepare("SHOW DATABASES LIKE " .
          $dbh->quote($schema))
        or ($dbh->{mysql_server_prepare}= $mysql_server_prepare_save && 
        return undef);
      $sth->execute()
        or ($dbh->{mysql_server_prepare}= $mysql_server_prepare_save && 
        return DBI::set_err($dbh, $sth->err(), $sth->errstr()));

      while (my $ref = $sth->fetchrow_arrayref())
      {
        push @schemas, $ref->[0];
      }
    }
    # Otherwise we want the current database
    else
    {
      push @schemas, $dbh->selectrow_array("SELECT DATABASE()");
    }

    # Figure out which table types are desired
    my ($want_tables, $want_views);
    if (defined $type && $type ne "")
    {
      $want_tables = ($type =~ m/table/i);
      $want_views  = ($type =~ m/view/i);
    }
    else
    {
      $want_tables = $want_views = 1;
    }

    for my $database (@schemas)
    {
      my $sth = $dbh->prepare("SHOW /*!50002 FULL*/ TABLES FROM " .
          $dbh->quote_identifier($database) .
          " LIKE " .  $dbh->quote($table))
          or ($dbh->{mysql_server_prepare}= $mysql_server_prepare_save && 
          return undef);

      $sth->execute() or
          ($dbh->{mysql_server_prepare}= $mysql_server_prepare_save &&
          return DBI::set_err($dbh, $sth->err(), $sth->errstr()));

      while (my $ref = $sth->fetchrow_arrayref())
      {
        my $type = (defined $ref->[1] &&
            $ref->[1] =~ /view/i) ? 'VIEW' : 'TABLE';
        next if $type eq 'TABLE' && not $want_tables;
        next if $type eq 'VIEW'  && not $want_views;
        push @rows, [ undef, $database, $ref->[0], $type, undef ];
      }
    }
  }

  my $sth = $sponge->prepare("table_info",
  {
    rows          => \@rows,
    NUM_OF_FIELDS => scalar @names,
    NAME          => \@names,
  }) 
    or ($dbh->{mysql_server_prepare}= $mysql_server_prepare_save && 
      return $dbh->DBI::set_err($sponge->err(), $sponge->errstr()));

  $dbh->{mysql_server_prepare}= $mysql_server_prepare_save;
  return $sth;
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
  $dbh->{mysql_server_prepare}||= 0;
  my $mysql_server_prepare_save= $dbh->{mysql_server_prepare};
  $dbh->{mysql_server_prepare}= 0;

  # ODBC allows a NULL to mean all columns, so we'll accept undef
  $column = '%' unless defined $column;

  my $ER_NO_SUCH_TABLE= 1146;

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
      mysql_is_auto_increment
      );
  my %col_info;

  local $dbh->{FetchHashKeyName} = 'NAME_lc';
  # only ignore ER_NO_SUCH_TABLE in internal_execute if issued from here
  my $desc_sth = $dbh->prepare("DESCRIBE $table_id " . $dbh->quote($column));
  my $desc = $dbh->selectall_arrayref($desc_sth, { Columns=>{} });

  #return $desc_sth if $desc_sth->err();
  if (my $err = $desc_sth->err())
  {
    # return the error, unless it is due to the table not 
    # existing per DBI spec
    if ($err != $ER_NO_SUCH_TABLE)
    {
      $dbh->{mysql_server_prepare}= $mysql_server_prepare_save;
      return undef;
    }
    $dbh->set_err(undef,undef);
    $desc = [];
  }

  my $ordinal_pos = 0;
  for my $row (@$desc)
  {
    my $type = $row->{type};
    $type =~ m/^(\w+)(?:\((.*?)\))?\s*(.*)/;
    my $basetype  = lc($1);
    my $typemod   = $2;
    my $attr      = $3;

    my $info = $col_info{ $row->{field} }= {
	    TABLE_CAT               => $catalog,
	    TABLE_SCHEM             => $schema,
	    TABLE_NAME              => $table,
	    COLUMN_NAME             => $row->{field},
	    NULLABLE                => ($row->{null} eq 'YES') ? 1 : 0,
	    IS_NULLABLE             => ($row->{null} eq 'YES') ? "YES" : "NO",
	    TYPE_NAME               => uc($basetype),
	    COLUMN_DEF              => $row->{default},
	    ORDINAL_POSITION        => ++$ordinal_pos,
	    mysql_is_pri_key        => ($row->{key}  eq 'PRI'),
	    mysql_type_name         => $row->{type},
      mysql_is_auto_increment => ($row->{extra} =~ /auto_increment/i ? 1 : 0),
    };
    #
	  # This code won't deal with a pathalogical case where a value
	  # contains a single quote followed by a comma, and doesn't unescape
	  # any escaped values. But who would use those in an enum or set?
    #
	  my @type_params= ($typemod && index($typemod,"'")>=0) ?
      ("$typemod," =~ /'(.*?)',/g)  # assume all are quoted
			: split /,/, $typemod||'';      # no quotes, plain list
	  s/''/'/g for @type_params;                # undo doubling of quotes

	  my @type_attr= split / /, $attr||'';

  	$info->{DATA_TYPE}= SQL_VARCHAR();
    if ($basetype =~ /^(char|varchar|\w*text|\w*blob)/)
    {
      $info->{DATA_TYPE}= SQL_CHAR() if $basetype eq 'char';
      if ($type_params[0])
      {
        $info->{COLUMN_SIZE} = $type_params[0];
      }
      else
      {
        $info->{COLUMN_SIZE} = 65535;
        $info->{COLUMN_SIZE} = 255        if $basetype =~ /^tiny/;
        $info->{COLUMN_SIZE} = 16777215   if $basetype =~ /^medium/;
        $info->{COLUMN_SIZE} = 4294967295 if $basetype =~ /^long/;
      }
    }
	  elsif ($basetype =~ /^(binary|varbinary)/)
    {
      $info->{COLUMN_SIZE} = $type_params[0];
	    # SQL_BINARY & SQL_VARBINARY are tempting here but don't match the
	    # semantics for mysql (not hex). SQL_CHAR &  SQL_VARCHAR are correct here.
	    $info->{DATA_TYPE} = ($basetype eq 'binary') ? SQL_CHAR() : SQL_VARCHAR();
    }
    elsif ($basetype =~ /^(enum|set)/)
    {
	    if ($basetype eq 'set')
      {
		    $info->{COLUMN_SIZE} = length(join ",", @type_params);
	    }
	    else
      {
        my $max_len = 0;
        length($_) > $max_len and $max_len = length($_) for @type_params;
        $info->{COLUMN_SIZE} = $max_len;
	    }
	    $info->{"mysql_values"} = \@type_params;
    }
    elsif ($basetype =~ /int/)
    { 
      # big/medium/small/tiny etc + unsigned?
	    $info->{DATA_TYPE} = SQL_INTEGER();
	    $info->{NUM_PREC_RADIX} = 10;
	    $info->{COLUMN_SIZE} = $type_params[0];
    }
    elsif ($basetype =~ /^decimal/)
    {
      $info->{DATA_TYPE} = SQL_DECIMAL();
      $info->{NUM_PREC_RADIX} = 10;
      $info->{COLUMN_SIZE}    = $type_params[0];
      $info->{DECIMAL_DIGITS} = $type_params[1];
    }
    elsif ($basetype =~ /^(float|double)/)
    {
	    $info->{DATA_TYPE} = ($basetype eq 'float') ? SQL_FLOAT() : SQL_DOUBLE();
	    $info->{NUM_PREC_RADIX} = 2;
	    $info->{COLUMN_SIZE} = ($basetype eq 'float') ? 32 : 64;
    }
    elsif ($basetype =~ /date|time/)
    { 
      # date/datetime/time/timestamp
	    if ($basetype eq 'time' or $basetype eq 'date')
      {
		    #$info->{DATA_TYPE}   = ($basetype eq 'time') ? SQL_TYPE_TIME() : SQL_TYPE_DATE();
        $info->{DATA_TYPE}   = ($basetype eq 'time') ? SQL_TIME() : SQL_DATE(); 
        $info->{COLUMN_SIZE} = ($basetype eq 'time') ? 8 : 10;
      }
	    else
      {
        # datetime/timestamp
        #$info->{DATA_TYPE}     = SQL_TYPE_TIMESTAMP();
		    $info->{DATA_TYPE}        = SQL_TIMESTAMP();
		    $info->{SQL_DATA_TYPE}    = SQL_DATETIME();
        $info->{SQL_DATETIME_SUB} = $info->{DATA_TYPE} - ($info->{SQL_DATA_TYPE} * 10);
        $info->{COLUMN_SIZE}      = ($basetype eq 'datetime') ? 19 : $type_params[0] || 14;
	    }
	    $info->{DECIMAL_DIGITS}= 0; # no fractional seconds
    }
    elsif ($basetype eq 'year')
    {	
      # no close standard so treat as int
	    $info->{DATA_TYPE}      = SQL_INTEGER();
	    $info->{NUM_PREC_RADIX} = 10;
	    $info->{COLUMN_SIZE}    = 4;
	  }
	  else
    {
	    Carp::carp("column_info: unrecognized column type '$basetype' of $table_id.$row->{field} treated as varchar");
    }
    $info->{SQL_DATA_TYPE} ||= $info->{DATA_TYPE};
    #warn Dumper($info);
  }

  my $sponge = DBI->connect("DBI:Sponge:", '','')
    or (  $dbh->{mysql_server_prepare}= $mysql_server_prepare_save &&
          return $dbh->DBI::set_err($DBI::err, "DBI::Sponge: $DBI::errstr"));

  my $sth = $sponge->prepare("column_info $table", {
      rows          => [ map { [ @{$_}{@names} ] } values %col_info ],
      NUM_OF_FIELDS => scalar @names,
      NAME          => \@names,
      }) or
  return ($dbh->{mysql_server_prepare}= $mysql_server_prepare_save &&
          $dbh->DBI::set_err($sponge->err(), $sponge->errstr()));

  $dbh->{mysql_server_prepare}= $mysql_server_prepare_save;
  return $sth;
}


sub primary_key_info {
  my ($dbh, $catalog, $schema, $table) = @_;
  $dbh->{mysql_server_prepare}||= 0;
  my $mysql_server_prepare_save= $dbh->{mysql_server_prepare};

  my $table_id = $dbh->quote_identifier($catalog, $schema, $table);

  my @names = qw(
      TABLE_CAT TABLE_SCHEM TABLE_NAME COLUMN_NAME KEY_SEQ PK_NAME
      );
  my %col_info;

  local $dbh->{FetchHashKeyName} = 'NAME_lc';
  my $desc_sth = $dbh->prepare("SHOW KEYS FROM $table_id");
  my $desc= $dbh->selectall_arrayref($desc_sth, { Columns=>{} });
  my $ordinal_pos = 0;
  for my $row (grep { $_->{key_name} eq 'PRIMARY'} @$desc)
  {
    $col_info{ $row->{column_name} }= {
      TABLE_CAT   => $catalog,
      TABLE_SCHEM => $schema,
      TABLE_NAME  => $table,
      COLUMN_NAME => $row->{column_name},
      KEY_SEQ     => $row->{seq_in_index},
      PK_NAME     => $row->{key_name},
    };
  }

  my $sponge = DBI->connect("DBI:Sponge:", '','')
    or 
     ($dbh->{mysql_server_prepare}= $mysql_server_prepare_save &&
      return $dbh->DBI::set_err($DBI::err, "DBI::Sponge: $DBI::errstr"));

  my $sth= $sponge->prepare("primary_key_info $table", {
      rows          => [ map { [ @{$_}{@names} ] } values %col_info ],
      NUM_OF_FIELDS => scalar @names,
      NAME          => \@names,
      }) or 
       ($dbh->{mysql_server_prepare}= $mysql_server_prepare_save &&
        return $dbh->DBI::set_err($sponge->err(), $sponge->errstr()));

  $dbh->{mysql_server_prepare}= $mysql_server_prepare_save;

  return $sth;
}


sub foreign_key_info {
    my ($dbh,
        $pk_catalog, $pk_schema, $pk_table,
        $fk_catalog, $fk_schema, $fk_table,
       ) = @_;

    # INFORMATION_SCHEMA.KEY_COLUMN_USAGE was added in 5.0.6
    my ($maj, $min, $point) = _version($dbh);
    return if $maj < 5 || ($maj == 5 && $point < 6);

    my $sql = <<'EOF';
SELECT NULL AS PKTABLE_CAT,
       A.REFERENCED_TABLE_SCHEMA AS PKTABLE_SCHEM,
       A.REFERENCED_TABLE_NAME AS PKTABLE_NAME,
       A.REFERENCED_COLUMN_NAME AS PKCOLUMN_NAME,
       A.TABLE_CATALOG AS FKTABLE_CAT,
       A.TABLE_SCHEMA AS FKTABLE_SCHEM,
       A.TABLE_NAME AS FKTABLE_NAME,
       A.COLUMN_NAME AS FKCOLUMN_NAME,
       A.ORDINAL_POSITION AS KEY_SEQ,
       NULL AS UPDATE_RULE,
       NULL AS DELETE_RULE,
       A.CONSTRAINT_NAME AS FK_NAME,
       NULL AS PK_NAME,
       NULL AS DEFERABILITY,
       NULL AS UNIQUE_OR_PRIMARY
  FROM INFORMATION_SCHEMA.KEY_COLUMN_USAGE A,
       INFORMATION_SCHEMA.TABLE_CONSTRAINTS B
 WHERE A.TABLE_SCHEMA = B.TABLE_SCHEMA AND A.TABLE_NAME = B.TABLE_NAME
   AND A.CONSTRAINT_NAME = B.CONSTRAINT_NAME AND B.CONSTRAINT_TYPE IS NOT NULL
EOF

    my @where;
    my @bind;

    # catalogs are not yet supported by MySQL

#    if (defined $pk_catalog) {
#        push @where, 'A.REFERENCED_TABLE_CATALOG = ?';
#        push @bind, $pk_catalog;
#    }

    if (defined $pk_schema) {
        push @where, 'A.REFERENCED_TABLE_SCHEMA = ?';
        push @bind, $pk_schema;
    }

    if (defined $pk_table) {
        push @where, 'A.REFERENCED_TABLE_NAME = ?';
        push @bind, $pk_table;
    }

#    if (defined $fk_catalog) {
#        push @where, 'A.TABLE_CATALOG = ?';
#        push @bind,  $fk_schema;
#    }

    if (defined $fk_schema) {
        push @where, 'A.TABLE_SCHEMA = ?';
        push @bind,  $fk_schema;
    }

    if (defined $fk_table) {
        push @where, 'A.TABLE_NAME = ?';
        push @bind,  $fk_table;
    }

    if (@where) {
        $sql .= ' AND ';
        $sql .= join ' AND ', @where;
    }
    $sql .= " ORDER BY A.TABLE_SCHEMA, A.TABLE_NAME, A.ORDINAL_POSITION";

    local $dbh->{FetchHashKeyName} = 'NAME_uc';
    my $sth = $dbh->prepare($sql);
    $sth->execute(@bind);

    return $sth;
}


sub _version {
    my $dbh = shift;

    return
        $dbh->get_info($DBI::Const::GetInfoType::GetInfoType{SQL_DBMS_VER})
            =~ /(\d+)\.(\d+)\.(\d+)/;
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
      {"host" => $host, "port" => $port, "user" => $user, password => $pass});

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

  my $row = $sth->fetchrow_hashref();

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

The hostname, if not specified or specified as '' or 'localhost', will
default to a MySQL server running on the local machine using the default for
the UNIX socket. To connect to a MySQL server on the local machine via TCP,
you must specify the loopback IP address (127.0.0.1) as the host.

Should the MySQL server be running on a non-standard port number,
you may explicitly state the port number to connect to in the C<hostname>
argument, by concatenating the I<hostname> and I<port number> together
separated by a colon ( C<:> ) character or by using the  C<port> argument.

To connect to a MySQL server on localhost using TCP/IP, you must specify the
hostname as 127.0.0.1 (with the optional port).

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

=item mysql_multi_statements

As of MySQL 4.1, support for multiple statements seperated by a semicolon
(;) may be enabled by using this option. Enabling this option may cause
problems if server-side prepared statements are also enabled.

=item Prepared statement support (server side prepare)

As of 3.0002_1, server side prepare statements were on by default (if your
server was >= 4.1.3). As of 3.0009, they were off by default again due to 
issues with the prepared statement API (all other mysql connectors are
set this way until C API issues are resolved). The requirement to use
prepared statements still remains that you have a server >= 4.1.3

To use server side prepared statements, all you need to do is set the variable 
mysql_server_prepare in the connect:

$dbh = DBI->connect(
                    "DBI:mysql:database=test;host=localhost;mysql_server_prepare=1",
                    "",
                    "",
                    { RaiseError => 1, AutoCommit => 1 }
                    );

* Note: delimiter for this param is ';'

There are many benefits to using server side prepare statements, mostly if you are 
performing many inserts because of that fact that a single statement is prepared 
to accept multiple insert values.

To make sure that the 'make test' step tests whether server prepare works, you just
need to export the env variable MYSQL_SERVER_PREPARE:

export MYSQL_SERVER_PREPARE=1


=item mysql_embedded_options

The option <mysql_embedded_options> can be used to pass 'command-line' 
options to embedded server.

Example:

use DBI;
$testdsn="DBI:mysqlEmb:database=test;mysql_embedded_options=--help,--verbose";
$dbh = DBI->connect($testdsn,"a","b");

This would cause the command line help to the embedded MySQL server library
to be printed.


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

Returns a list of all databases managed by the MySQL server
running on C<$hostname>, port C<$port>. This is a legacy
method.  Instead, you should use the portable method

    @dbs = DBI->data_sources("mysql");

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
  $error = $dbh->{'mysql_error'};
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

=item mysql_enable_utf8

This attribute determines whether DBD::mysql should assume strings
stored in the database are utf8.  This feature defaults to off.

When set, a data retrieved from a textual column type (char, varchar,
etc) will have the UTF-8 flag turned on if necessary.  This enables
character semantics on that string.  You will also need to ensure that
your database / table / column is configured to use UTF8.  See Chapter
10 of the mysql manual for details.

Additionally, turning on this flag tells MySQL that incoming data should
be treated as UTF-8.  This will only take effect if used as part of the
call to connect().  If you turn the flag on after connecting, you will
need to issue the command C<SET NAMES utf8> to get the same effect.

This option is experimental and may change in future versions.

=item mysql_bind_type_guessing

This attribute causes the driver (emulated prepare statements) 
to attempt to guess if a value being bound is a numeric value,
and if so, doesn't quote the value.  This was created by 
Dragonchild and is one way to deal with the performance issue 
of using quotes in a statement that is inserting or updating a
large numeric value. This was previously called 
C<unsafe_bind_type_guessing> because it is experimental. I have 
successfully run the full test suite with this option turned on,
the name can now be simply C<mysql_bind_type_guessing>. 

See bug: https://rt.cpan.org/Ticket/Display.html?id=43822

C<mysql_bind_type_guessing> can be turned on via 

 - through DSN 

  my $dbh= DBI->connect('DBI:mysql:test', 'username', 'pass',
  { mysql_bind_type_guessing => 1})

  - OR after handle creation

  $dbh->{mysql_bind_type_guessing} = 1;



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

=item mysql_warning_count

The number of warnings generated during execution of the SQL statement.

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

=over

=head1 MULTIPLE RESULT SETS

As of version 3.0002_5, DBD::mysql supports multiple result sets (Thanks
to Guy Harrison!). This is the first release of this functionality, so 
there may be issues. Please report bugs if you run into them!

The basic usage of multiple result sets is

  do 
  {
    while (@row= $sth->fetchrow_array())
    {
      do stuff;
    }
  } while ($sth->more_results)

An example would be:

  $dbh->do("drop procedure if exists someproc") or print $DBI::errstr;

  $dbh->do("create procedure somproc() deterministic
   begin
   declare a,b,c,d int;
   set a=1;
   set b=2;
   set c=3;
   set d=4;
   select a, b, c, d;
   select d, c, b, a;
   select b, a, c, d;
   select c, b, d, a;
  end") or print $DBI::errstr;

  $sth=$dbh->prepare('call someproc()') || 
  die $DBI::err.": ".$DBI::errstr;

  $sth->execute || die DBI::err.": ".$DBI::errstr; $rowset=0;
  do {
    print "\nRowset ".++$i."\n---------------------------------------\n\n";
    foreach $colno (0..$sth->{NUM_OF_FIELDS}) {
      print $sth->{NAME}->[$colno]."\t";
    }
    print "\n";
    while (@row= $sth->fetchrow_array())  {
      foreach $field (0..$#row) {
        print $row[$field]."\t";
      }
      print "\n";
    }
  } until (!$sth->more_results)
 
For more examples, please see the eg/ directory. This is where helpful
DBD::mysql code snippits will be added in the future.

=head2 Issues with Multiple result sets

So far, the main issue is if your result sets are "jagged", meaning, the
number of columns of your results vary. Varying numbers of columns could
result in your script crashing. This is something that will be fixed soon.


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
need to fetch the modules from CPAN search

   http://search.cpan.org/ 

The following modules are required

  DBI
  Data::ShowTable
  DBD::mysql

Then enter the following commands (note - versions are just examples):

  gzip -cd DBI-(version).tar.gz | tar xf -
  cd DBI-(version)
  perl Makefile.PL
  make
  make test
  make install

  cd ..
  gzip -cd Data-ShowTable-(version).tar.gz | tar xf -
  cd Data-ShowTable-3.3
  perl Makefile.PL
  make
  make install

  cd ..
  gzip -cd DBD-mysql-(version)-tar.gz | tar xf -
  cd DBD-mysql-(version)
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
like egcs or gcc. The Perl sources are available via CPAN search

  http://search.cpan.org

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
Patrick Galbraith (I<patg@mysql.com>). 
The first version's author was Alligator Descartes, who was aided
and abetted by Gary Shea, Andreas König and Tim Bunce amongst others.

The B<Mysql> module was originally written by Andreas König
<koenig@kulturbox.de>. The current version, mainly an emulation
layer, is from Jochen Wiedmann.


=head1 COPYRIGHT


This module is 
Large Portions Copyright (c) 2004-2006 MySQL Patrick Galbraith, Alexey Stroganov,
Large Portions Copyright (c) 2003-2005 Rudolf Lippan; Large Portions 
Copyright (c) 1997-2003 Jochen Wiedmann, with code portions 
Copyright (c)1994-1997 their original authors This module is
released under the same license as Perl itself. See the Perl README
for details.


=head1 MAILING LIST SUPPORT

This module is maintained and supported on a mailing list,

    perl@lists.mysql.com

To subscribe to this list, go to

http://lists.mysql.com/perl?sub=1

Mailing list archives are available at

http://lists.mysql.com/perl

Additionally you might try the dbi-user mailing list for questions about
DBI and its modules in general. Subscribe via

dbi-users-subscribe@perl.org

Mailing list archives are at

http://groups.google.com/group/perl.dbi.users?hl=en&lr=

Also, the main DBI site is at

http://dbi.perl.org/

=head1 ADDITIONAL DBI INFORMATION

Additional information on the DBI project can be found on the World
Wide Web at the following URL:

    http://dbi.perl.org

where documentation, pointers to the mailing lists and mailing list
archives and pointers to the most current versions of the modules can
be used.

Information on the DBI interface itself can be gained by typing:

    perldoc DBI

right now!


=head1 BUG REPORTING, ENHANCEMENT/FEATURE REQUESTS

Please report bugs, including all the information needed
such as DBD::mysql version, MySQL version, OS type/version, etc
to this link:

http://bugs.mysql.com/


=cut


