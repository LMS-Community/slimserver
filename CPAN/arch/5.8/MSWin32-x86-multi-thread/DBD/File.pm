# -*- perl -*-
#
#   DBD::File - A base class for implementing DBI drivers that
#               act on plain files
#
#  This module is currently maintained by
#
#      Jeff Zucker < jzucker AT cpan.org >
#
#  The original author is Jochen Wiedmann.
#
#  Copyright (C) 2004 by Jeff Zucker
#  Copyright (C) 1998 by Jochen Wiedmann
#
#  All rights reserved.
#
#  You may distribute this module under the terms of either the GNU
#  General Public License or the Artistic License, as specified in
#  the Perl README file.
#
require 5.004;
use strict;

use DBI ();
require DBI::SQL::Nano;
my $haveFileSpec = eval { require File::Spec };

package DBD::File;

use vars qw(@ISA $VERSION $drh $valid_attrs);

$VERSION = '0.31';      # bumped from 0.22 to 0.30 with inclusion in DBI

$drh = undef;		# holds driver handle once initialised

sub driver ($;$) {
    my($class, $attr) = @_;
    return $drh if $drh;

    DBI->setup_driver('DBD::File');
    $attr ||= {};
    no strict qw(refs);
    if (!$attr->{Attribution}) {
	$attr->{Attribution} = "$class by Jeff Zucker"
	    if $class eq 'DBD::File';
	$attr->{Attribution} ||= ${$class . '::ATTRIBUTION'}
	    || "oops the author of $class forgot to define this";
    }
    $attr->{Version} ||= ${$class . '::VERSION'};
    ($attr->{Name} = $class) =~ s/^DBD\:\:// unless $attr->{Name};
    $drh = DBI::_new_drh($class . "::dr", $attr);
    return $drh;
}

sub CLONE {
    undef $drh;
}

package DBD::File::dr; # ====== DRIVER ======

$DBD::File::dr::imp_data_size = 0;

sub connect ($$;$$$) {
    my($drh, $dbname, $user, $auth, $attr)= @_;

    # create a 'blank' dbh
    my $this = DBI::_new_dbh($drh, {
	'Name' => $dbname,
	'USER' => $user,
	'CURRENT_USER' => $user,
    });

    if ($this) {
	my($var, $val);
	$this->{f_dir} = $haveFileSpec ? File::Spec->curdir() : '.';
	while (length($dbname)) {
	    if ($dbname =~ s/^((?:[^\\;]|\\.)*?);//s) {
		$var = $1;
	    } else {
		$var = $dbname;
		$dbname = '';
	    }
	    if ($var =~ /^(.+?)=(.*)/s) {
		$var = $1;
		($val = $2) =~ s/\\(.)/$1/g;
		$this->{$var} = $val;
	    }
	}
        $this->{f_valid_attrs} = {
            f_version    => 1  # DBD::File version
          , f_dir        => 1  # base directory
          , f_tables     => 1  # base directory
        };
        $this->{sql_valid_attrs} = {
            sql_handler           => 1  # Nano or S:S
          , sql_nano_version      => 1  # Nano version
          , sql_statement_version => 1  # S:S version
        };
    }
    $this->STORE('Active',1);
    return set_versions($this);
}

sub set_versions {
    my $this = shift;
    $this->{f_version} = $DBD::File::VERSION;
    for (qw( nano_version statement_version)) {
        $this->{'sql_'.$_} = $DBI::SQL::Nano::versions->{$_}||'';
    }
    $this->{sql_handler} = ($this->{sql_statement_version})
                         ? 'SQL::Statement'
	                 : 'DBI::SQL::Nano';
    return $this;
}

sub data_sources ($;$) {
    my($drh, $attr) = @_;
    my($dir) = ($attr and exists($attr->{'f_dir'})) ?
	$attr->{'f_dir'} : $haveFileSpec ? File::Spec->curdir() : '.';
    my($dirh) = Symbol::gensym();
    if (!opendir($dirh, $dir)) {
        $drh->set_err(1, "Cannot open directory $dir: $!");
	return undef;
    }
    my($file, @dsns, %names, $driver);
    if ($drh->{'ImplementorClass'} =~ /^dbd\:\:([^\:]+)\:\:/i) {
	$driver = $1;
    } else {
	$driver = 'File';
    }
    while (defined($file = readdir($dirh))) {
	my $d = $haveFileSpec ?
	    File::Spec->catdir($dir, $file) : "$dir/$file";
        # allow current dir ... it can be a data_source too
	if ( $file ne ($haveFileSpec ? File::Spec->updir() : '..')
	    and  -d $d) {
	    push(@dsns, "DBI:$driver:f_dir=$d");
	}
    }
    @dsns;
}

sub disconnect_all {
}

sub DESTROY {
    undef;
}


package DBD::File::db; # ====== DATABASE ======

$DBD::File::db::imp_data_size = 0;

sub prepare ($$;@) {
    my($dbh, $statement, @attribs)= @_;

    # create a 'blank' sth
    my $sth = DBI::_new_sth($dbh, {'Statement' => $statement});

    if ($sth) {
	my $class = $sth->FETCH('ImplementorClass');
	$class =~ s/::st$/::Statement/;
	my($stmt);

        # if using SQL::Statement version > 1
        # cache the parser object if the DBD supports parser caching
        # SQL::Nano and older SQL::Statements don't support this

	if ( $dbh->{sql_handler} eq 'SQL::Statement'
             and $dbh->{sql_statement_version} > 1)
           {
            my $parser = $dbh->{csv_sql_parser_object};
            $parser ||= eval { $dbh->func('csv_cache_sql_parser_object') };
            if ($@) {
  	        $stmt = eval { $class->new($statement) };
	    }
            else {
  	        $stmt = eval { $class->new($statement,$parser) };
	    }
        }
        else {
	    $stmt = eval { $class->new($statement) };
	}
	if ($@) {
	    $dbh->set_err(1, $@);
	    undef $sth;
	} else {
	    $sth->STORE('f_stmt', $stmt);
	    $sth->STORE('f_params', []);
	    $sth->STORE('NUM_OF_PARAMS', scalar($stmt->params()));
	}
    }
    $sth;
}
sub csv_cache_sql_parser_object {
    my $dbh = shift;
    my $parser = {
            dialect    => 'CSV',
            RaiseError => $dbh->FETCH('RaiseError'),
            PrintError => $dbh->FETCH('PrintError'),
        };
    my $sql_flags  = $dbh->FETCH('sql_flags') || {};
    %$parser = (%$parser,%$sql_flags);
    $parser = SQL::Parser->new($parser->{dialect},$parser);
    $dbh->{csv_sql_parser_object} = $parser;
    return $parser;
}
sub disconnect ($) {
    shift->STORE('Active',0);
    undef $DBD::File::drh;
    1;
}
sub FETCH ($$) {
    my ($dbh, $attrib) = @_;
    if ($attrib eq 'AutoCommit') {
	return 1;
    } elsif ($attrib eq (lc $attrib)) {
	# Driver private attributes are lower cased

        # Error-check for valid attributes
        # not implemented yet, see STORE
        #
        return $dbh->{$attrib};
    }
    # else pass up to DBI to handle
    return $dbh->SUPER::FETCH($attrib);
}

sub STORE ($$$) {
    my ($dbh, $attrib, $value) = @_;

    if ($attrib eq 'AutoCommit') {
	return 1 if $value; # is already set
	die("Can't disable AutoCommit");
    } elsif ($attrib eq (lc $attrib)) {
	# Driver private attributes are lower cased

  # I'm not implementing this yet becuase other drivers may be
  # setting f_ and sql_ attrs I don't know about
  # I'll investigate and publicize warnings to DBD authors
  # then implement this
  #
        # return to implementor if not f_ or sql_
        # not implemented yet
        # my $class = $dbh->FETCH('ImplementorClass');
        #
        # if ( !$dbh->{f_valid_attrs}->{$attrib}
        # and !$dbh->{sql_valid_attrs}->{$attrib}
        # ) {
	#    return $dbh->set_err( 1,"Invalid attribute '$attrib'");
        # }
        # else {
  	#    $dbh->{$attrib} = $value;
	# }

        if ($attrib eq 'f_dir') {
  	    return $dbh->set_err( 1,"No such directory '$value'")
                unless -d $value;
	}
	$dbh->{$attrib} = $value;
	return 1;
    }
    return $dbh->SUPER::STORE($attrib, $value);
}

sub DESTROY ($) {
    # for backwards compatibility only, remove eventually
    shift->STORE('Active',0);
    undef;
}

sub type_info_all ($) {
    [
     {   TYPE_NAME         => 0,
	 DATA_TYPE         => 1,
	 PRECISION         => 2,
	 LITERAL_PREFIX    => 3,
	 LITERAL_SUFFIX    => 4,
	 CREATE_PARAMS     => 5,
	 NULLABLE          => 6,
	 CASE_SENSITIVE    => 7,
	 SEARCHABLE        => 8,
	 UNSIGNED_ATTRIBUTE=> 9,
	 MONEY             => 10,
	 AUTO_INCREMENT    => 11,
	 LOCAL_TYPE_NAME   => 12,
	 MINIMUM_SCALE     => 13,
	 MAXIMUM_SCALE     => 14,
     },
     [ 'VARCHAR', DBI::SQL_VARCHAR(),
       undef, "'","'", undef,0, 1,1,0,0,0,undef,1,999999
       ],
     [ 'CHAR', DBI::SQL_CHAR(),
       undef, "'","'", undef,0, 1,1,0,0,0,undef,1,999999
       ],
     [ 'INTEGER', DBI::SQL_INTEGER(),
       undef,  "", "", undef,0, 0,1,0,0,0,undef,0,  0
       ],
     [ 'REAL', DBI::SQL_REAL(),
       undef,  "", "", undef,0, 0,1,0,0,0,undef,0,  0
       ],
     [ 'BLOB', DBI::SQL_LONGVARBINARY(),
       undef, "'","'", undef,0, 1,1,0,0,0,undef,1,999999
       ],
     [ 'BLOB', DBI::SQL_LONGVARBINARY(),
       undef, "'","'", undef,0, 1,1,0,0,0,undef,1,999999
       ],
     [ 'TEXT', DBI::SQL_LONGVARCHAR(),
       undef, "'","'", undef,0, 1,1,0,0,0,undef,1,999999
       ]
     ]
}


{
    my $names = ['TABLE_QUALIFIER', 'TABLE_OWNER', 'TABLE_NAME',
                 'TABLE_TYPE', 'REMARKS'];

    sub table_info ($) {
	my($dbh) = @_;
	my($dir) = $dbh->{f_dir};
	my($dirh) = Symbol::gensym();
	if (!opendir($dirh, $dir)) {
	    $dbh->set_err(1, "Cannot open directory $dir: $!");
	    return undef;
	}
	my($file, @tables, %names);
	while (defined($file = readdir($dirh))) {
	    if ($file ne '.'  &&  $file ne '..'  &&  -f "$dir/$file") {
		my $user = eval { getpwuid((stat(_))[4]) };
		push(@tables, [undef, $user, $file, "TABLE", undef]);
	    }
	}
	if (!closedir($dirh)) {
	    $dbh->set_err(1, "Cannot close directory $dir: $!");
	    return undef;
	}

	my $dbh2 = $dbh->{'csv_sponge_driver'};
	if (!$dbh2) {
	    $dbh2 = $dbh->{'csv_sponge_driver'} = DBI->connect("DBI:Sponge:");
	    if (!$dbh2) {
	        $dbh->set_err(1, $DBI::errstr);
		return undef;
	    }
	}

	# Temporary kludge: DBD::Sponge dies if @tables is empty. :-(
	return undef if !@tables;

	my $sth = $dbh2->prepare("TABLE_INFO", { 'rows' => \@tables,
						 'NAMES' => $names });
	if (!$sth) {
	    $dbh->set_err(1, $dbh2->errstr);
	}
	$sth;
    }
}
sub list_tables ($) {
    my $dbh = shift;
    my($sth, @tables);
    if (!($sth = $dbh->table_info())) {
	return ();
    }
    while (my $ref = $sth->fetchrow_arrayref()) {
	push(@tables, $ref->[2]);
    }
    @tables;
}

sub quote ($$;$) {
    my($self, $str, $type) = @_;
    if (defined($type)  &&
	($type == DBI::SQL_NUMERIC()   ||
	 $type == DBI::SQL_DECIMAL()   ||
	 $type == DBI::SQL_INTEGER()   ||
	 $type == DBI::SQL_SMALLINT()  ||
	 $type == DBI::SQL_FLOAT()     ||
	 $type == DBI::SQL_REAL()      ||
	 $type == DBI::SQL_DOUBLE()    ||
	 $type == DBI::TINYINT())) {
	return $str;
    }
    if (!defined($str)) { return "NULL" }
    $str =~ s/\\/\\\\/sg;
    $str =~ s/\0/\\0/sg;
    $str =~ s/\'/\\\'/sg;
    $str =~ s/\n/\\n/sg;
    $str =~ s/\r/\\r/sg;
    "'$str'";
}

sub commit ($) {
    my($dbh) = shift;
    if ($dbh->FETCH('Warn')) {
	warn("Commit ineffective while AutoCommit is on", -1);
    }
    1;
}

sub rollback ($) {
    my($dbh) = shift;
    if ($dbh->FETCH('Warn')) {
	warn("Rollback ineffective while AutoCommit is on", -1);
    }
    0;
}

package DBD::File::st; # ====== STATEMENT ======

$DBD::File::st::imp_data_size = 0;

sub bind_param ($$$;$) {
    my($sth, $pNum, $val, $attr) = @_;
    $sth->{f_params}->[$pNum-1] = $val;
    1;
}

sub execute {
    my $sth = shift;
    my $params;
    if (@_) {
	$sth->{'f_params'} = ($params = [@_]);
    } else {
	$params = $sth->{'f_params'};
    }

    # start of by finishing any previous execution if still active
    $sth->finish if $sth->{Active};
    $sth->{'Active'}=1;
    my $stmt = $sth->{'f_stmt'};
    my $result = eval { $stmt->execute($sth, $params); };
    return $sth->set_err(1,$@) if $@;
    if ($stmt->{'NUM_OF_FIELDS'}  &&  !$sth->FETCH('NUM_OF_FIELDS')) {
	$sth->STORE('NUM_OF_FIELDS', $stmt->{'NUM_OF_FIELDS'});
    }
    return $result;
}
sub finish {
    my $sth = shift;
    $sth->{Active}=0;
    delete $sth->{f_stmt}->{data};
}
sub fetch ($) {
    my $sth = shift;
    my $data = $sth->{f_stmt}->{data};
    if (!$data  ||  ref($data) ne 'ARRAY') {
	$sth->set_err(1, "Attempt to fetch row from a Non-SELECT statement");
	return undef;
    }
    my $dav = shift @$data;
    if (!$dav) {
        $sth->{Active} = 0; # mark as no longer active
	return undef;
    }
    if ($sth->FETCH('ChopBlanks')) {
	map { $_ =~ s/\s+$// if $_; $_ } @$dav;
    }
    $sth->_set_fbav($dav);
}
*fetchrow_arrayref = \&fetch;

sub FETCH ($$) {
    my ($sth, $attrib) = @_;
    return undef if ($attrib eq 'TYPE'); # Workaround for a bug in DBI 0.93
    return $sth->FETCH('f_stmt')->{'NAME'} if ($attrib eq 'NAME');
    if ($attrib eq 'NULLABLE') {
	my($meta) = $sth->FETCH('f_stmt')->{'NAME'}; # Intentional !
	if (!$meta) {
	    return undef;
	}
	my($names) = [];
	my($col);
	foreach $col (@$meta) {
	    push(@$names, 1);
	}
	return $names;
    }
    if ($attrib eq (lc $attrib)) {
	# Private driver attributes are lower cased
	return $sth->{$attrib};
    }
    # else pass up to DBI to handle
    return $sth->SUPER::FETCH($attrib);
}

sub STORE ($$$) {
    my ($sth, $attrib, $value) = @_;
    if ($attrib eq (lc $attrib)) {
	# Private driver attributes are lower cased
 	$sth->{$attrib} = $value;
	return 1;
    }
    return $sth->SUPER::STORE($attrib, $value);
}

sub DESTROY ($) {
    undef;
}

sub rows ($) { shift->{'f_stmt'}->{'NUM_OF_ROWS'} };


package DBD::File::Statement;

# We may have a working flock() built-in but that doesn't mean that locking
# will work on NFS (flock() may hang hard)
my $locking = eval { flock STDOUT, 0; 1 };

# Jochen's old check for flock()
#
# my $locking = $^O ne 'MacOS'  &&
#               ($^O ne 'MSWin32' || !Win32::IsWin95())  &&
#               $^O ne 'VMS';

@DBD::File::Statement::ISA = qw(DBI::SQL::Nano::Statement);

my $open_table_re =
    $haveFileSpec ?
    sprintf('(?:%s|%s¦%s)',
	    quotemeta(File::Spec->curdir()),
	    quotemeta(File::Spec->updir()),
	    quotemeta(File::Spec->rootdir()))
    : '(?:\.?\.)?\/';

sub get_file_name($$$) {
    my($self,$data,$table)=@_;
    $table =~ s/^\"//; # handle quoted identifiers
    $table =~ s/\"$//;
    my $file = $table;
    if ( $file !~ /^$open_table_re/o
     and $file !~ m!^[/\\]!   # root
     and $file !~ m!^[a-z]\:! # drive letter
    ) {
	$file = $haveFileSpec ?
	    File::Spec->catfile($data->{Database}->{'f_dir'}, $table)
		: $data->{Database}->{'f_dir'} . "/$table";
    }
    return($table,$file);
}

sub open_table ($$$$$) {
    my($self, $data, $table, $createMode, $lockMode) = @_;
    my $file;
    ($table,$file) = $self->get_file_name($data,$table);
    my $fh;
    my $safe_drop = 1 if $self->{ignore_missing_table};
    if ($createMode) {
	if (-f $file) {
	    die "Cannot create table $table: Already exists";
	}
	if (!($fh = IO::File->new($file, "a+"))) {
	    die "Cannot open $file for writing: $!";
	}
	if (!$fh->seek(0, 0)) {
	    die " Error while seeking back: $!";
	}
    } else {
	if (!($fh = IO::File->new($file, ($lockMode ? "r+" : "r")))) {
	    die " Cannot open $file: $!" unless $safe_drop;
	}
    }
    binmode($fh) if $fh;
    if ($locking and $fh) {
	if ($lockMode) {
	    if (!flock($fh, 2)) {
		die " Cannot obtain exclusive lock on $file: $!";
	    }
	} else {
	    if (!flock($fh, 1)) {
		die "Cannot obtain shared lock on $file: $!";
	    }
	}
    }
    my $columns = {};
    my $array = [];
    my $pos = $fh->tell() if $fh;
    my $tbl = {
	file => $file,
	fh => $fh,
	col_nums => $columns,
	col_names => $array,
	first_row_pos => $pos,
    };
    my $class = ref($self);
    $class =~ s/::Statement/::Table/;
    bless($tbl, $class);
    $tbl;
}


package DBD::File::Table;

@DBD::File::Table::ISA = qw(DBI::SQL::Nano::Table);

sub drop ($) {
    my($self) = @_;
    # We have to close the file before unlinking it: Some OS'es will
    # refuse the unlink otherwise.
    $self->{'fh'}->close() if $self->{fh};
    unlink($self->{'file'});
    return 1;
}

sub seek ($$$$) {
    my($self, $data, $pos, $whence) = @_;
    if ($whence == 0  &&  $pos == 0) {
	$pos = $self->{'first_row_pos'};
    } elsif ($whence != 2  ||  $pos != 0) {
	die "Illegal seek position: pos = $pos, whence = $whence";
    }
    if (!$self->{'fh'}->seek($pos, $whence)) {
	die "Error while seeking in " . $self->{'file'} . ": $!";
    }
}

sub truncate ($$) {
    my($self, $data) = @_;
    if (!$self->{'fh'}->truncate($self->{'fh'}->tell())) {
	die "Error while truncating " . $self->{'file'} . ": $!";
    }
    1;
}

1;


__END__

=head1 NAME

DBD::File - Base class for writing DBI drivers

=head1 SYNOPSIS

 This module is a base class for writing other DBDs.
 It is not intended to function as a DBD itself.
 If you want to access flatfiles, use DBD::AnyData, or DBD::CSV,
 (both of which are subclasses of DBD::File).

=head1 DESCRIPTION

The DBD::File module is not a true DBI driver, but an abstract
base class for deriving concrete DBI drivers from it. The implication is,
that these drivers work with plain files, for example CSV files or
INI files. The module is based on the SQL::Statement module, a simple
SQL engine.

See L<DBI(3)> for details on DBI, L<SQL::Statement(3)> for details on
SQL::Statement and L<DBD::CSV(3)> or L<DBD::IniFile(3)> for example
drivers.


=head2 Metadata

The following attributes are handled by DBI itself and not by DBD::File,
thus they all work like expected:

    Active
    ActiveKids
    CachedKids
    CompatMode             (Not used)
    InactiveDestroy
    Kids
    PrintError
    RaiseError
    Warn                   (Not used)

The following DBI attributes are handled by DBD::File:

=over 4

=item AutoCommit

Always on

=item ChopBlanks

Works

=item NUM_OF_FIELDS

Valid after C<$sth->execute>

=item NUM_OF_PARAMS

Valid after C<$sth->prepare>

=item NAME

Valid after C<$sth->execute>; undef for Non-Select statements.

=item NULLABLE

Not really working, always returns an array ref of one's, as DBD::CSV
doesn't verify input data. Valid after C<$sth->execute>; undef for
Non-Select statements.

=back

These attributes and methods are not supported:

    bind_param_inout
    CursorName
    LongReadLen
    LongTruncOk

Additional to the DBI attributes, you can use the following dbh
attribute:

=over 4

=item f_dir

This attribute is used for setting the directory where CSV files are
opened. Usually you set it in the dbh, it defaults to the current
directory ("."). However, it is overwritable in the statement handles.

=back


=head2 Driver private methods

=over 4

=item data_sources

The C<data_sources> method returns a list of subdirectories of the current
directory in the form "DBI:CSV:f_dir=$dirname".

If you want to read the subdirectories of another directory, use

    my($drh) = DBI->install_driver("CSV");
    my(@list) = $drh->data_sources('f_dir' => '/usr/local/csv_data' );

=item list_tables

This method returns a list of file names inside $dbh->{'f_dir'}.
Example:

    my($dbh) = DBI->connect("DBI:CSV:f_dir=/usr/local/csv_data");
    my(@list) = $dbh->func('list_tables');

Note that the list includes all files contained in the directory, even
those that have non-valid table names, from the view of SQL. See
L<Creating and dropping tables> above.

=back

=head1 KNOWN BUGS

=over 8

=item *

The module is using flock() internally. However, this function is not
available on all platforms. Using flock() is disabled on MacOS and
Windows 95: There's no locking at all (perhaps not so important on
MacOS and Windows 95, as there's a single user anyways).

=back


=head1 AUTHOR AND COPYRIGHT

This module is currently maintained by

Jeff Zucker < jzucker @ cpan.org >

The original author is Jochen Wiedmann.

Copyright (C) 2004 by Jeff Zucker
Copyright (C) 1998 by Jochen Wiedmann

All rights reserved.

You may freely distribute and/or modify this module under the terms of either the GNU General Public License (GPL) or the Artistic License, as specified in
the Perl README file.

=head1 SEE ALSO

L<DBI(3)>, L<Text::CSV_XS(3)>, L<SQL::Statement(3)>


=cut
