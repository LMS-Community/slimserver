{
    package DBD::ExampleP;

    use Symbol;

    use DBI qw(:sql_types);

    require File::Spec;

    @EXPORT = qw(); # Do NOT @EXPORT anything.
    $VERSION = "12.014311";

#   $Id: ExampleP.pm 14310 2010-08-02 06:35:25Z Jens $
#
#   Copyright (c) 1994,1997,1998 Tim Bunce
#
#   You may distribute under the terms of either the GNU General Public
#   License or the Artistic License, as specified in the Perl README file.

    @statnames = qw(dev ino mode nlink
	uid gid rdev size
	atime mtime ctime
	blksize blocks name);
    @statnames{@statnames} = (0 .. @statnames-1);

    @stattypes = (SQL_INTEGER, SQL_INTEGER, SQL_INTEGER, SQL_INTEGER,
	SQL_INTEGER, SQL_INTEGER, SQL_INTEGER, SQL_INTEGER,
	SQL_INTEGER, SQL_INTEGER, SQL_INTEGER,
	SQL_INTEGER, SQL_INTEGER, SQL_VARCHAR);
    @stattypes{@statnames} = @stattypes;
    @statprec = ((10) x (@statnames-1), 1024);
    @statprec{@statnames} = @statprec;
    die unless @statnames == @stattypes;
    die unless @statprec  == @stattypes;

    $drh = undef;	# holds driver handle once initialised
    #$gensym = "SYM000"; # used by st::execute() for filehandles

    sub driver{
	return $drh if $drh;
	my($class, $attr) = @_;
	$class .= "::dr";
	($drh) = DBI::_new_drh($class, {
	    'Name' => 'ExampleP',
	    'Version' => $VERSION,
	    'Attribution' => 'DBD Example Perl stub by Tim Bunce',
	    }, ['example implementors private data '.__PACKAGE__]);
	$drh;
    }

    sub CLONE {
	undef $drh;
    }
}


{   package DBD::ExampleP::dr; # ====== DRIVER ======
    $imp_data_size = 0;
    use strict;

    sub connect { # normally overridden, but a handy default
        my($drh, $dbname, $user, $auth)= @_;
        my ($outer, $dbh) = DBI::_new_dbh($drh, {
            Name => $dbname,
            examplep_private_dbh_attrib => 42, # an example, for testing
        });
        $dbh->{examplep_get_info} = {
            29 => '"',  # SQL_IDENTIFIER_QUOTE_CHAR
            41 => '.',  # SQL_CATALOG_NAME_SEPARATOR
            114 => 1,   # SQL_CATALOG_LOCATION
        };
        #$dbh->{Name} = $dbname;
        $dbh->STORE('Active', 1);
        return $outer;
    }

    sub data_sources {
	return ("dbi:ExampleP:dir=.");	# possibly usefully meaningless
    }

}


{   package DBD::ExampleP::db; # ====== DATABASE ======
    $imp_data_size = 0;
    use strict;

    sub prepare {
	my($dbh, $statement)= @_;
	my @fields;
	my($fields, $dir) = $statement =~ m/^\s*select\s+(.*?)\s+from\s+(\S*)/i;

	if (defined $fields and defined $dir) {
	    @fields = ($fields eq '*')
			? keys %DBD::ExampleP::statnames
			: split(/\s*,\s*/, $fields);
	}
	else {
	    return $dbh->set_err($DBI::stderr, "Syntax error in select statement (\"$statement\")")
		unless $statement =~ m/^\s*set\s+/;
	    # the SET syntax is just a hack so the ExampleP driver can
	    # be used to test non-select statements.
	    # Now we have DBI::DBM etc., ExampleP should be deprecated
	}

	my ($outer, $sth) = DBI::_new_sth($dbh, {
	    'Statement'     => $statement,
            examplep_private_sth_attrib => 24, # an example, for testing
	}, ['example implementors private data '.__PACKAGE__]);

	my @bad = map {
	    defined $DBD::ExampleP::statnames{$_} ? () : $_
	} @fields;
	return $dbh->set_err($DBI::stderr, "Unknown field names: @bad")
		if @bad;

	$outer->STORE('NUM_OF_FIELDS' => scalar(@fields));

	$sth->{examplep_ex_dir} = $dir if defined($dir) && $dir !~ /\?/;
	$outer->STORE('NUM_OF_PARAMS' => ($dir) ? $dir =~ tr/?/?/ : 0);

	if (@fields) {
	    $outer->STORE('NAME'     => \@fields);
	    $outer->STORE('NULLABLE' => [ (0) x @fields ]);
	    $outer->STORE('SCALE'    => [ (0) x @fields ]);
	}

	$outer;
    }


    sub table_info {
	my $dbh = shift;
	my ($catalog, $schema, $table, $type) = @_;

	my @types = split(/["']*,["']/, $type || 'TABLE');
	my %types = map { $_=>$_ } @types;

	# Return a list of all subdirectories
	my $dh = Symbol::gensym(); # "DBD::ExampleP::".++$DBD::ExampleP::gensym;
	my $dir = $catalog || File::Spec->curdir();
	my @list;
	if ($types{VIEW}) {	# for use by test harness
	    push @list, [ undef, "schema",  "table",  'VIEW', undef ];
	    push @list, [ undef, "sch-ema", "table",  'VIEW', undef ];
	    push @list, [ undef, "schema",  "ta-ble", 'VIEW', undef ];
	    push @list, [ undef, "sch ema", "table",  'VIEW', undef ];
	    push @list, [ undef, "schema",  "ta ble", 'VIEW', undef ];
	}
	if ($types{TABLE}) {
	    no strict 'refs';
	    opendir($dh, $dir)
		or return $dbh->set_err(int($!), "Failed to open directory $dir: $!");
	    while (defined(my $item = readdir($dh))) {
                if ($^O eq 'VMS') {
                    # if on VMS then avoid warnings from catdir if you use a file
                    # (not a dir) as the item below
                    next if $item !~ /\.dir$/oi;
                }
                my $file = File::Spec->catdir($dir,$item);
		next unless -d $file;
		my($dev, $ino, $mode, $nlink, $uid) = lstat($file);
		my $pwnam = undef; # eval { scalar(getpwnam($uid)) } || $uid;
		push @list, [ $dir, $pwnam, $item, 'TABLE', undef ];
	    }
	    close($dh);
	}
	# We would like to simply do a DBI->connect() here. However,
	# this is wrong if we are in a subclass like DBI::ProxyServer.
	$dbh->{'dbd_sponge_dbh'} ||= DBI->connect("DBI:Sponge:", '','')
	    or return $dbh->set_err($DBI::err,
			"Failed to connect to DBI::Sponge: $DBI::errstr");

	my $attr = {
	    'rows' => \@list,
	    'NUM_OF_FIELDS' => 5,
	    'NAME' => ['TABLE_CAT', 'TABLE_SCHEM', 'TABLE_NAME',
		    'TABLE_TYPE', 'REMARKS'],
	    'TYPE' => [DBI::SQL_VARCHAR(), DBI::SQL_VARCHAR(),
		    DBI::SQL_VARCHAR(), DBI::SQL_VARCHAR(), DBI::SQL_VARCHAR() ],
	    'NULLABLE' => [1, 1, 1, 1, 1]
	};
	my $sdbh = $dbh->{'dbd_sponge_dbh'};
	my $sth = $sdbh->prepare("SHOW TABLES FROM $dir", $attr)
	    or return $dbh->set_err($sdbh->err(), $sdbh->errstr());
	$sth;
    }


    sub type_info_all {
	my ($dbh) = @_;
	my $ti = [
	    {	TYPE_NAME	=> 0,
		DATA_TYPE	=> 1,
		COLUMN_SIZE	=> 2,
		LITERAL_PREFIX	=> 3,
		LITERAL_SUFFIX	=> 4,
		CREATE_PARAMS	=> 5,
		NULLABLE	=> 6,
		CASE_SENSITIVE	=> 7,
		SEARCHABLE	=> 8,
		UNSIGNED_ATTRIBUTE=> 9,
		FIXED_PREC_SCALE=> 10,
		AUTO_UNIQUE_VALUE => 11,
		LOCAL_TYPE_NAME	=> 12,
		MINIMUM_SCALE	=> 13,
		MAXIMUM_SCALE	=> 14,
	    },
	    [ 'VARCHAR', DBI::SQL_VARCHAR, 1024, "'","'", undef, 0, 1, 1, 0, 0,0,undef,0,0 ],
	    [ 'INTEGER', DBI::SQL_INTEGER,   10, "","",   undef, 0, 0, 1, 0, 0,0,undef,0,0 ],
	];
	return $ti;
    }


    sub ping {
	(shift->FETCH('Active')) ? 2 : 0;    # the value 2 is checked for by t/80proxy.t
    }


    sub disconnect {
	shift->STORE(Active => 0);
	return 1;
    }


    sub get_info {
	my ($dbh, $info_type) = @_;
	return $dbh->{examplep_get_info}->{$info_type};
    }


    sub FETCH {
	my ($dbh, $attrib) = @_;
	# In reality this would interrogate the database engine to
	# either return dynamic values that cannot be precomputed
	# or fetch and cache attribute values too expensive to prefetch.
	# else pass up to DBI to handle
	return $INC{"DBD/ExampleP.pm"} if $attrib eq 'example_driver_path';
	return $dbh->SUPER::FETCH($attrib);
    }


    sub STORE {
	my ($dbh, $attrib, $value) = @_;
	# would normally validate and only store known attributes
	# else pass up to DBI to handle
	if ($attrib eq 'AutoCommit') {
	    # convert AutoCommit values to magic ones to let DBI
	    # know that the driver has 'handled' the AutoCommit attribute
	    $value = ($value) ? -901 : -900;
	}
	return $dbh->{$attrib} = $value if $attrib =~ /^examplep_/;
	return $dbh->SUPER::STORE($attrib, $value);
    }

    sub DESTROY {
	my $dbh = shift;
	$dbh->disconnect if $dbh->FETCH('Active');
	undef
    }


    # This is an example to demonstrate the use of driver-specific
    # methods via $dbh->func().
    # Use it as follows:
    #   my @tables = $dbh->func($re, 'examplep_tables');
    #
    # Returns all the tables that match the regular expression $re.
    sub examplep_tables {
	my $dbh = shift; my $re = shift;
	grep { $_ =~ /$re/ } $dbh->tables();
    }

    sub parse_trace_flag {
	my ($h, $name) = @_;
	return 0x01000000 if $name eq 'foo';
	return 0x02000000 if $name eq 'bar';
	return 0x04000000 if $name eq 'baz';
	return 0x08000000 if $name eq 'boo';
	return 0x10000000 if $name eq 'bop';
	return $h->SUPER::parse_trace_flag($name);
    }

    sub private_attribute_info {
        return { example_driver_path => undef };
    }
}


{   package DBD::ExampleP::st; # ====== STATEMENT ======
    $imp_data_size = 0;
    use strict; no strict 'refs'; # cause problems with filehandles

    sub bind_param {
	my($sth, $param, $value, $attribs) = @_;
	$sth->{'dbd_param'}->[$param-1] = $value;
	return 1;
    }


    sub execute {
	my($sth, @dir) = @_;
	my $dir;

	if (@dir) {
	    $sth->bind_param($_, $dir[$_-1]) or return
		foreach (1..@dir);
	}

	my $dbd_param = $sth->{'dbd_param'} || [];
	return $sth->set_err(2, @$dbd_param." values bound when $sth->{NUM_OF_PARAMS} expected")
	    unless @$dbd_param == $sth->{NUM_OF_PARAMS};

	return 0 unless $sth->{NUM_OF_FIELDS}; # not a select

	$dir = $dbd_param->[0] || $sth->{examplep_ex_dir};
	return $sth->set_err(2, "No bind parameter supplied")
	    unless defined $dir;

	$sth->finish;

	#
	# If the users asks for directory "long_list_4532", then we fake a
	# directory with files "file4351", "file4350", ..., "file0".
	# This is a special case used for testing, especially DBD::Proxy.
	#
	if ($dir =~ /^long_list_(\d+)$/) {
	    $sth->{dbd_dir} = [ $1 ];	# array ref indicates special mode
	    $sth->{dbd_datahandle} = undef;
	}
	else {
	    $sth->{dbd_dir} = $dir;
	    my $sym = Symbol::gensym(); # "DBD::ExampleP::".++$DBD::ExampleP::gensym;
	    opendir($sym, $dir)
                or return $sth->set_err(2, "opendir($dir): $!");
	    $sth->{dbd_datahandle} = $sym;
	}
	$sth->STORE(Active => 1);
	return 1;
    }


    sub fetch {
	my $sth = shift;
	my $dir = $sth->{dbd_dir};
	my %s;

	if (ref $dir) {		# special fake-data test mode
	    my $num = $dir->[0]--;
	    unless ($num > 0) {
		$sth->finish();
		return;
	    }
	    my $time = time;
	    @s{@DBD::ExampleP::statnames} =
		( 2051, 1000+$num, 0644, 2, $>, $), 0, 1024,
	          $time, $time, $time, 512, 2, "file$num")
	}
	else {			# normal mode
            my $dh  = $sth->{dbd_datahandle}
                or return $sth->set_err($DBI::stderr, "fetch without successful execute");
	    my $f = readdir($dh);
	    unless ($f) {
		$sth->finish;
		return;
	    }
	    # untaint $f so that we can use this for DBI taint tests
	    ($f) = ($f =~ m/^(.*)$/);
	    my $file = File::Spec->catfile($dir, $f);
	    # put in all the data fields
	    @s{ @DBD::ExampleP::statnames } = (lstat($file), $f);
	}

	# return just what fields the query asks for
	my @new = @s{ @{$sth->{NAME}} };

	return $sth->_set_fbav(\@new);
    }
    *fetchrow_arrayref = \&fetch;


    sub finish {
	my $sth = shift;
	closedir($sth->{dbd_datahandle}) if $sth->{dbd_datahandle};
	$sth->{dbd_datahandle} = undef;
	$sth->{dbd_dir} = undef;
	$sth->SUPER::finish();
	return 1;
    }


    sub FETCH {
	my ($sth, $attrib) = @_;
	# In reality this would interrogate the database engine to
	# either return dynamic values that cannot be precomputed
	# or fetch and cache attribute values too expensive to prefetch.
	if ($attrib eq 'TYPE'){
	    return [ @DBD::ExampleP::stattypes{ @{ $sth->FETCH(q{NAME_lc}) } } ];
	}
	elsif ($attrib eq 'PRECISION'){
	    return [ @DBD::ExampleP::statprec{  @{ $sth->FETCH(q{NAME_lc}) } } ];
	}
	elsif ($attrib eq 'ParamValues') {
	    my $dbd_param = $sth->{dbd_param} || [];
	    my %pv = map { $_ => $dbd_param->[$_-1] } 1..@$dbd_param;
	    return \%pv;
	}
	# else pass up to DBI to handle
	return $sth->SUPER::FETCH($attrib);
    }


    sub STORE {
	my ($sth, $attrib, $value) = @_;
	# would normally validate and only store known attributes
	# else pass up to DBI to handle
	return $sth->{$attrib} = $value
	    if $attrib eq 'NAME' or $attrib eq 'NULLABLE' or $attrib eq 'SCALE' or $attrib eq 'PRECISION';
	return $sth->SUPER::STORE($attrib, $value);
    }

    *parse_trace_flag = \&DBD::ExampleP::db::parse_trace_flag;
}

1;
# vim: sw=4:ts=8
