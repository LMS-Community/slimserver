#######################################################################
#
#  DBD::DBM - a DBI driver for DBM files
#
#  Copyright (c) 2004 by Jeff Zucker < jzucker AT cpan.org >
#
#  All rights reserved.
#
#  You may freely distribute and/or modify this  module under the terms
#  of either the GNU  General Public License (GPL) or the Artistic License,
#  as specified in the Perl README file.
#
#  USERS - see the pod at the bottom of this file
#
#  DBD AUTHORS - see the comments in the code
#
#######################################################################
require 5.005_03;
use strict;

#################
package DBD::DBM;
#################
use base qw( DBD::File );
use vars qw($VERSION $ATTRIBUTION $drh $methods_already_installed);
$VERSION     = '0.02';
$ATTRIBUTION = 'DBD::DBM by Jeff Zucker';

# no need to have driver() unless you need private methods
#
sub driver ($;$) {
    my($class, $attr) = @_;
    return $drh if $drh;

    # do the real work in DBD::File
    #
    $attr->{Attribution} = 'DBD::DBM by Jeff Zucker';
    my $this = $class->SUPER::driver($attr);

    # install private methods
    #
    # this requires that dbm_ (or foo_) be a registered prefix
    # but you can write private methods before official registration
    # by hacking the $dbd_prefix_registry in a private copy of DBI.pm
    #
    if ( $DBI::VERSION >= 1.37 and !$methods_already_installed++ ) {
        DBD::DBM::db->install_method('dbm_versions');
        DBD::DBM::st->install_method('dbm_schema');
    }

    $this;
}

sub CLONE {
    undef $drh;
}

#####################
package DBD::DBM::dr;
#####################
$DBD::DBM::dr::imp_data_size = 0;
@DBD::DBM::dr::ISA = qw(DBD::File::dr);

# you can get by without connect() if you don't have to check private
# attributes, DBD::File will gather the connection string arguements for you
#
sub connect ($$;$$$) {
    my($drh, $dbname, $user, $auth, $attr)= @_;

    # create a 'blank' dbh
    my $this = DBI::_new_dbh($drh, {
	Name => $dbname,
    });

    # parse the connection string for name=value pairs
    if ($this) {

        # define valid private attributes
        #
        # attempts to set non-valid attrs in connect() or
        # with $dbh->{attr} will throw errors
        #
        # the attrs here *must* start with dbm_ or foo_
        #
        # see the STORE methods below for how to check these attrs
        #
        $this->{dbm_valid_attrs} = {
            dbm_tables            => 1  # per-table information
          , dbm_type              => 1  # the global DBM type e.g. SDBM_File
          , dbm_mldbm             => 1  # the global MLDBM serializer
          , dbm_cols              => 1  # the global column names
          , dbm_version           => 1  # verbose DBD::DBM version
          , dbm_ext               => 1  # file extension
          , dbm_lockfile          => 1  # lockfile extension
          , dbm_store_metadata    => 1  # column names, etc.
          , dbm_berkeley_flags    => 1  # for BerkeleyDB
        };

	my($var, $val);
	$this->{f_dir} = $DBD::File::haveFileSpec ? File::Spec->curdir() : '.';
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

                # in the connect string the attr names
                # can either have dbm_ (or foo_) prepended or not
                # this will add the prefix if it's missing
                #
                $var = 'dbm_' . $var unless $var =~ /^dbm_/
                                     or     $var eq 'f_dir';
		# XXX should pass back to DBI via $attr for connect() to STORE
		$this->{$var} = $val;
	    }
	}
	$this->{f_version} = $DBD::File::VERSION;
        $this->{dbm_version} = $DBD::DBM::VERSION;
        for (qw( nano_version statement_version)) {
            $this->{'sql_'.$_} = $DBI::SQL::Nano::versions->{$_}||'';
        }
        $this->{sql_handler} = ($this->{sql_statement_version})
                             ? 'SQL::Statement'
   	                     : 'DBI::SQL::Nano';
    }
    $this->STORE('Active',1);
    return $this;
}

# you could put some :dr private methods here

# you may need to over-ride some DBD::File::dr methods here
# but you can probably get away with just letting it do the work
# in most cases

#####################
package DBD::DBM::db;
#####################
$DBD::DBM::db::imp_data_size = 0;
@DBD::DBM::db::ISA = qw(DBD::File::db);

# the ::db::STORE method is what gets called when you set
# a lower-cased database handle attribute such as $dbh->{somekey}=$someval;
#
# STORE should check to make sure that "somekey" is a valid attribute name
# but only if it is really one of our attributes (starts with dbm_ or foo_)
# You can also check for valid values for the attributes if needed
# and/or perform other operations
#
sub STORE ($$$) {
    my ($dbh, $attrib, $value) = @_;

    # use DBD::File's STORE unless its one of our own attributes
    #
    return $dbh->SUPER::STORE($attrib,$value) unless $attrib =~ /^dbm_/;

    # throw an error if it has our prefix but isn't a valid attr name
    #
    if ( $attrib ne 'dbm_valid_attrs'          # gotta start somewhere :-)
     and !$dbh->{dbm_valid_attrs}->{$attrib} ) {
        return $dbh->set_err( 1,"Invalid attribute '$attrib'!");
    }
    else {

        # check here if you need to validate values
        # or conceivably do other things as well
        #
	$dbh->{$attrib} = $value;
        return 1;
    }
}

# and FETCH is done similar to STORE
#
sub FETCH ($$) {
    my ($dbh, $attrib) = @_;

    return $dbh->SUPER::FETCH($attrib) unless $attrib =~ /^dbm_/;

    # throw an error if it has our prefix but isn't a valid attr name
    #
    if ( $attrib ne 'dbm_valid_attrs'          # gotta start somewhere :-)
     and !$dbh->{dbm_valid_attrs}->{$attrib} ) {
        return $dbh->set_err( 1,"Invalid attribute '$attrib'");
    }
    else {

        # check here if you need to validate values
        # or conceivably do other things as well
        #
	return $dbh->{$attrib};
    }
}


# this is an example of a private method
# these used to be done with $dbh->func(...)
# see above in the driver() sub for how to install the method
#
sub dbm_versions {
    my $dbh   = shift;
    my $table = shift || '';
    my $dtype = $dbh->{dbm_tables}->{$table}->{type}
             || $dbh->{dbm_type}
             || 'SDBM_File';
    my $mldbm = $dbh->{dbm_tables}->{$table}->{mldbm}
             || $dbh->{dbm_mldbm}
             || '';
    $dtype   .= ' + MLDBM + ' . $mldbm if $mldbm;

    my %version = ( DBI => $DBI::VERSION );
    $version{"DBI::PurePerl"} = $DBI::PurePerl::VERSION	if $DBI::PurePerl;
    $version{OS}   = "$^O ($Config::Config{osvers})";
    $version{Perl} = "$] ($Config::Config{archname})";
    my $str = sprintf "%-16s %s\n%-16s %s\n%-16s %s\n",
      'DBD::DBM'         , $dbh->{Driver}->{Version} . " using $dtype"
    , '  DBD::File'      , $dbh->{f_version}
    , '  DBI::SQL::Nano' , $dbh->{sql_nano_version}
    ;
    $str .= sprintf "%-16s %s\n",
    , '  SQL::Statement' , $dbh->{sql_statement_version}
      if $dbh->{sql_handler} eq 'SQL::Statement';
    for (sort keys %version) {
        $str .= sprintf "%-16s %s\n", $_, $version{$_};
    }
    return "$str\n";
}

# you may need to over-ride some DBD::File::db methods here
# but you can probably get away with just letting it do the work
# in most cases

#####################
package DBD::DBM::st;
#####################
$DBD::DBM::st::imp_data_size = 0;
@DBD::DBM::st::ISA = qw(DBD::File::st);

sub dbm_schema {
    my($sth,$tname)=@_;
    return $sth->set_err(1,'No table name supplied!') unless $tname;
    return $sth->set_err(1,"Unknown table '$tname'!")
       unless $sth->{Database}->{dbm_tables}
          and $sth->{Database}->{dbm_tables}->{$tname};
    return $sth->{Database}->{dbm_tables}->{$tname}->{schema};
}
# you could put some :st private methods here

# you may need to over-ride some DBD::File::st methods here
# but you can probably get away with just letting it do the work
# in most cases

############################
package DBD::DBM::Statement;
############################
use base qw( DBD::File::Statement );
use IO::File;  # for locking only
use Fcntl;

my $HAS_FLOCK = eval { flock STDOUT, 0; 1 };

# you must define open_table;
# it is done at the start of all executes;
# it doesn't necessarily have to "open" anything;
# you must define the $tbl and at least the col_names and col_nums;
# anything else you put in depends on what you need in your
# ::Table methods below; you must bless the $tbl into the
# appropriate class as shown
#
# see also the comments inside open_table() showing the difference
# between global, per-table, and default settings
#
sub open_table ($$$$$) {
    my($self, $data, $table, $createMode, $lockMode) = @_;
    my $dbh = $data->{Database};

    my $tname = $table || $self->{tables}->[0]->{name};
    my $file;
    ($table,$file) = $self->get_file_name($data,$tname);

    # note the use of three levels of attribute settings below
    # first it looks for a per-table setting
    # if none is found, it looks for a global setting
    # if none is found, it sets a default
    #
    # your DBD may not need this, gloabls and defaults may be enough
    #
    my $dbm_type = $dbh->{dbm_tables}->{$tname}->{type}
                || $dbh->{dbm_type}
                || 'SDBM_File';
    $dbh->{dbm_tables}->{$tname}->{type} = $dbm_type;

    my $serializer = $dbh->{dbm_tables}->{$tname}->{mldbm}
                  || $dbh->{dbm_mldbm}
                  || '';
    $dbh->{dbm_tables}->{$tname}->{mldbm} = $serializer if $serializer;

    my $ext =  '' if $dbm_type eq 'GDBM_File'
                  or $dbm_type eq 'DB_File'
                  or $dbm_type eq 'BerkeleyDB';
    # XXX NDBM_File on FreeBSD (and elsewhere?) may actually be Berkeley
    # behind the scenes and so create a single .db file.
    $ext = '.pag' if $dbm_type eq 'NDBM_File'
                  or $dbm_type eq 'SDBM_File'
                  or $dbm_type eq 'ODBM_File';
    $ext = $dbh->{dbm_ext} if defined $dbh->{dbm_ext};
    $ext = $dbh->{dbm_tables}->{$tname}->{ext}
        if defined $dbh->{dbm_tables}->{$tname}->{ext};
    $ext = '' unless defined $ext;

    my $open_mode = O_RDONLY;
       $open_mode = O_RDWR                 if $lockMode;
       $open_mode = O_RDWR|O_CREAT|O_TRUNC if $createMode;

    my($tie_type);

    if ( $serializer ) {
       require 'MLDBM.pm';
       $MLDBM::UseDB      = $dbm_type;
       $MLDBM::UseDB      = 'BerkeleyDB::Hash' if $dbm_type eq 'BerkeleyDB';
       $MLDBM::Serializer = $serializer;
       $tie_type = 'MLDBM';
    }
    else {
       require "$dbm_type.pm";
       $tie_type = $dbm_type;
    }

    # Second-guessing the file extension isn't great here (or in general)
    # could replace this by trying to open the file in non-create mode
    # first and dieing if that succeeds.
    # Currently this test doesn't work where NDBM is actually Berkeley (.db)
    die "Cannot CREATE '$file$ext' because it already exists"
        if $createMode and (-e "$file$ext");

    # LOCKING
    #
    my($nolock,$lockext,$lock_table);
    $lockext = $dbh->{dbm_tables}->{$tname}->{lockfile};
    $lockext = $dbh->{dbm_lockfile} if !defined $lockext;
    if ( (defined $lockext and $lockext == 0) or !$HAS_FLOCK
    ) {
        undef $lockext;
        $nolock = 1;
    }
    else {
        $lockext ||= '.lck';
    }
    # open and flock the lockfile, creating it if necessary
    #
    if (!$nolock) {
        $lock_table = $self->SUPER::open_table(
            $data, "$table$lockext", $createMode, $lockMode
        );
    }

    # TIEING
    #
    # allow users to pass in a pre-created tied object
    #
    my @tie_args;
    if ($dbm_type eq 'BerkeleyDB') {
       my $DB_CREATE = 1;  # but import constants if supplied
       my $DB_RDONLY = 16; #
       my %flags;
       if (my $f = $dbh->{dbm_berkeley_flags}) {
           $DB_CREATE  = $f->{DB_CREATE} if $f->{DB_CREATE};
           $DB_RDONLY  = $f->{DB_RDONLY} if $f->{DB_RDONLY};
           delete $f->{DB_CREATE};
           delete $f->{DB_RDONLY};
           %flags = %$f;
       }
       $flags{'-Flags'} = $DB_RDONLY;
       $flags{'-Flags'} = $DB_CREATE if $lockMode or $createMode;
        my $t = 'BerkeleyDB::Hash';
           $t = 'MLDBM' if $serializer;
	@tie_args = ($t, -Filename=>$file, %flags);
    }
    else {
        @tie_args = ($tie_type, $file, $open_mode, 0666);
    }
    my %h;
    if ( $self->{command} ne 'DROP') {
	my $tie_class = shift @tie_args;
	eval { tie %h, $tie_class, @tie_args };
	die "Cannot tie(%h $tie_class @tie_args): $@" if $@;
    }


    # COLUMN NAMES
    #
    my $store = $dbh->{dbm_tables}->{$tname}->{store_metadata};
       $store = $dbh->{dbm_store_metadata} unless defined $store;
       $store = 1 unless defined $store;
    $dbh->{dbm_tables}->{$tname}->{store_metadata} = $store;

    my($meta_data,$schema,$col_names);
    $meta_data = $col_names = $h{"_metadata \0"} if $store;
    if ($meta_data and $meta_data =~ m~<dbd_metadata>(.+)</dbd_metadata>~is) {
        $schema  = $col_names = $1;
        $schema  =~ s~.*<schema>(.+)</schema>.*~$1~is;
        $col_names =~ s~.*<col_names>(.+)</col_names>.*~$1~is;
    }
    $col_names ||= $dbh->{dbm_tables}->{$tname}->{c_cols}
               || $dbh->{dbm_tables}->{$tname}->{cols}
               || $dbh->{dbm_cols}
               || ['k','v'];
    $col_names = [split /,/,$col_names] if (ref $col_names ne 'ARRAY');
    $dbh->{dbm_tables}->{$tname}->{cols}   = $col_names;
    $dbh->{dbm_tables}->{$tname}->{schema} = $schema;

    my $i;
    my %col_nums  = map { $_ => $i++ } @$col_names;

    my $tbl = {
	table_name     => $tname,
	file           => $file,
	ext            => $ext,
        hash           => \%h,
        dbm_type       => $dbm_type,
        store_metadata => $store,
        mldbm          => $serializer,
        lock_fh        => $lock_table->{fh},
        lock_ext       => $lockext,
        nolock         => $nolock,
	col_nums       => \%col_nums,
	col_names      => $col_names
    };

    my $class = ref($self);
    $class =~ s/::Statement/::Table/;
    bless($tbl, $class);
    $tbl;
}

# DELETE is only needed for backward compat with old SQL::Statement
# it can be removed when the next SQL::Statement is released
#
# It is an example though of how you can subclass SQL::Statement/Nano
# in your DBD ... if you needed to, you could over-ride CREATE
# SELECT, etc.
#
# Note also the use of $dbh->{sql_handler} to differentiate
# between SQL::Statement and DBI::SQL::Nano
#
# Your driver may support only one of those two SQL engines, but
# your users will have more options if you support both
#
# Generally, you don't need to do anything to support both, but
# if you subclass them like this DELETE function does, you may
# need some minor changes to support both (similar to the first
# if statement in DELETE, everything else is the same)
#
sub DELETE ($$$) {
    my($self, $data, $params) = @_;
    my $dbh   = $data->{Database};
    my($table,$tname,@where_args);
    if ($dbh->{sql_handler} eq 'SQL::Statement') {
       my($eval,$all_cols) = $self->open_tables($data, 0, 1);
       return undef unless $eval;
       $eval->params($params);
       $self->verify_columns($eval, $all_cols);
       $table = $eval->table($self->tables(0)->name());
       @where_args = ($eval,$self->tables(0)->name());
    }
    else {
        $table = $self->open_tables($data, 0, 1);
        $self->verify_columns($table);
        @where_args = ($table);
    }
    my($affected) = 0;
    my(@rows, $array);
    if ( $table->can('delete_one_row') ) {
        while (my $array = $table->fetch_row($data)) {
            if ($self->eval_where(@where_args,$array)) {
                ++$affected;
                $array = $self->{fetched_value} if $self->{fetched_from_key};
                $table->delete_one_row($data,$array);
                return ($affected, 0) if $self->{fetched_from_key};
            }
        }
        return ($affected, 0);
    }
    while ($array = $table->fetch_row($data)) {
        if ($self->eval_where($table,$array)) {
            ++$affected;
        } else {
            push(@rows, $array);
        }
    }
    $table->seek($data, 0, 0);
    foreach $array (@rows) {
        $table->push_row($data, $array);
    }
    $table->truncate($data);
    return ($affected, 0);
}

########################
package DBD::DBM::Table;
########################
use base qw( DBD::File::Table );

# you must define drop
# it is called from execute of a SQL DROP statement
#
sub drop ($$) {
    my($self,$data) = @_;
    untie %{$self->{hash}} if $self->{hash};
    my $ext = $self->{ext};
    unlink $self->{file}.$ext if -f $self->{file}.$ext;
    unlink $self->{file}.'.dir' if -f $self->{file}.'.dir'
                               and $ext eq '.pag';
    if (!$self->{nolock}) {
        $self->{lock_fh}->close if $self->{lock_fh};
        unlink $self->{file}.$self->{lock_ext}
            if -f $self->{file}.$self->{lock_ext};
    }
    return 1;
}

# you must define fetch_row, it is called on all fetches;
# it MUST return undef when no rows are left to fetch;
# checking for $ary[0] is specific to hashes so you'll
# probably need some other kind of check for nothing-left.
# as Janis might say: "undef's just another word for
# nothing left to fetch" :-)
#
sub fetch_row ($$$) {
    my($self, $data, $row) = @_;
    # fetch with %each
    #
    my @ary = each %{$self->{hash}};
    @ary = each %{$self->{hash}} if $self->{store_metadata}
                                 and $ary[0]
                                 and $ary[0] eq "_metadata \0";

    return undef unless defined $ary[0];
    if (ref $ary[1] eq 'ARRAY') {
       @ary = ( $ary[0], @{$ary[1]} );
    }
    return (@ary) if wantarray;
    return \@ary;

    # fetch without %each
    #
    # $self->{keys} = [sort keys %{$self->{hash}}] unless $self->{keys};
    # my $key = shift @{$self->{keys}};
    # $key = shift @{$self->{keys}} if $self->{store_metadata}
    #                             and $key
    #                             and $key eq "_metadata \0";
    # return undef unless defined $key;
    # my @ary;
    # $row = $self->{hash}->{$key};
    # if (ref $row eq 'ARRAY') {
    #   @ary = ( $key, @{$row} );
    # }
    # else {
    #    @ary = ($key,$row);
    # }
    # return (@ary) if wantarray;
    # return \@ary;
}

# you must define push_row
# it is called on inserts and updates
#
sub push_row ($$$) {
    my($self, $data, $row_aryref) = @_;
    my $key = shift @$row_aryref;
    if ( $self->{mldbm} ) {
        $self->{hash}->{$key}= $row_aryref;
    }
    else {
        $self->{hash}->{$key}=$row_aryref->[0];
    }
    1;
}

# this is where you grab the column names from a CREATE statement
# if you don't need to do that, it must be defined but can be empty
#
sub push_names ($$$) {
    my($self, $data, $row_aryref) = @_;
    $data->{Database}->{dbm_tables}->{$self->{table_name}}->{c_cols}
       = $row_aryref;
    next unless $self->{store_metadata};
    my $stmt = $data->{f_stmt};
    my $col_names = join ',', @{$row_aryref};
    my $schema = $data->{Database}->{Statement};
       $schema =~ s/^[^\(]+\((.+)\)$/$1/s;
       $schema = $stmt->schema_str if $stmt->can('schema_str');
    $self->{hash}->{"_metadata \0"} = "<dbd_metadata>"
                                    . "<schema>$schema</schema>"
                                    . "<col_names>$col_names</col_names>"
                                    . "</dbd_metadata>"
                                    ;
}

# fetch_one_row, delete_one_row, update_one_row
# are optimized for hash-style lookup without looping;
# if you don't need them, omit them, they're optional
# but, in that case you may need to define
# truncate() and seek(), see below
#
sub fetch_one_row ($$;$) {
    my($self,$key_only,$value) = @_;
    return $self->{col_names}->[0] if $key_only;
    return [$value, $self->{hash}->{$value}];
}
sub delete_one_row ($$$) {
    my($self,$data,$aryref) = @_;
    delete $self->{hash}->{$aryref->[0]};
}
sub update_one_row ($$$) {
    my($self,$data,$aryref) = @_;
    my $key = shift @$aryref;
    return undef unless defined $key;
    if( ref $aryref->[0] eq 'ARRAY'){
        return  $self->{hash}->{$key}=$aryref;
    }
    $self->{hash}->{$key}=$aryref->[0];
}

# you may not need to explicitly DESTROY the ::Table
# put cleanup code to run when the execute is done
#
sub DESTROY ($) {
    my $self=shift;
    untie %{$self->{hash}} if $self->{hash};
    # release the flock on the lock file
    $self->{lock_fh}->close if !$self->{nolock} and $self->{lock_fh};
}

# truncate() and seek() must be defined to satisfy DBI::SQL::Nano
# *IF* you define the *_one_row methods above, truncate() and
# seek() can be empty or you can use them without actually
# truncating or seeking anything but if you don't define the
# *_one_row methods, you may need to define these

# if you need to do something after a series of
# deletes or updates, you can put it in truncate()
# which is called at the end of executing
#
sub truncate ($$) {
    my($self,$data) = @_;
    1;
}

# seek() is only needed if you use IO::File
# though it could be used for other non-file operations
# that you need to do before "writes" or truncate()
#
sub seek ($$$$) {
    my($self, $data, $pos, $whence) = @_;
}

# Th, th, th, that's all folks!  See DBD::File and DBD::CSV for other
# examples of creating pure perl DBDs.  I hope this helped.
# Now it's time to go forth and create your own DBD!
# Remember to check in with dbi-dev@perl.org before you get too far.
# We may be able to make suggestions or point you to other related
# projects.

1;
__END__

=pod

=head1 NAME

DBD::DBM - a DBI driver for DBM & MLDBM files

=head1 SYNOPSIS

 use DBI;
 $dbh = DBI->connect('dbi:DBM:');                # defaults to SDBM_File
 $dbh = DBI->connect('DBI:DBM(RaiseError=1):');  # defaults to SDBM_File
 $dbh = DBI->connect('dbi:DBM:type=GDBM_File');  # defaults to GDBM_File
 $dbh = DBI->connect('dbi:DBM:mldbm=Storable');  # MLDBM with SDBM_File
                                                 # and Storable

or

 $dbh = DBI->connect('dbi:DBM:', undef, undef);
 $dbh = DBI->connect('dbi:DBM:', undef, undef, { dbm_type => 'ODBM_File' });

and other variations on connect() as shown in the DBI docs and with
the dbm_ attributes shown below

... and then use standard DBI prepare, execute, fetch, placeholders, etc.,
see L<QUICK START> for an example

=head1 DESCRIPTION

DBD::DBM is a database management sytem that can work right out of the box.  If you have a standard installation of Perl and a standard installation of DBI, you can begin creating, accessing, and modifying database tables without any further installation.  You can also add some other modules to it for more robust capabilities if you wish.

The module uses a DBM file storage layer.  DBM file storage is common on many platforms and files can be created with it in many languges.  That means that, in addition to creating files with DBI/SQL, you can also use DBI/SQL to access and modify files created by other DBM modules and programs.  You can also use those programs to access files created with DBD::DBM.

DBM files are stored in binary format optimized for quick retrieval when using a key field.  That optimization can be used advantageously to make DBD::DBM SQL operations that use key fields very fast.  There are several different "flavors" of DBM - different storage formats supported by different sorts of perl modules such as SDBM_File and MLDBM.  This module supports all of the flavors that perl supports and, when used with MLDBM, supports tables with any number of columns and insertion of Perl objects into tables.

DBD::DBM has been tested with the following DBM types: SDBM_File, NDBM_File, ODBM_File, GDBM_File, DB_File, BerekeleyDB.  Each type was tested both with and without MLDBM.

=head1 QUICK START

DBD::DBM operates like all other DBD drivers - it's basic syntax and operation is specified by DBI.  If you're not familiar with DBI, you should start by reading L<DBI> and the documents it points to and then come back and read this file.  If you are familiar with DBI, you already know most of what you need to know to operate this module.  Just jump in and create a test script something like the one shown below.

You should be aware that there are several options for the SQL engine underlying DBD::DBM, see L<Supported SQL>.  There are also many options for DBM support, see especially the section on L<Adding multi-column support with MLDBM>.

But here's a sample to get you started.

 use DBI;
 my $dbh = DBI->connect('dbi:DBM:');
 $dbh->{RaiseError} = 1;
 for my $sql( split /;\n+/,"
     CREATE TABLE user ( user_name TEXT, phone TEXT );
     INSERT INTO user VALUES ('Fred Bloggs','233-7777');
     INSERT INTO user VALUES ('Sanjay Patel','777-3333');
     INSERT INTO user VALUES ('Junk','xxx-xxxx');
     DELETE FROM user WHERE user_name = 'Junk';
     UPDATE user SET phone = '999-4444' WHERE user_name = 'Sanjay Patel';
     SELECT * FROM user
 "){
     my $sth = $dbh->prepare($sql);
     $sth->execute;
     $sth->dump_results if $sth->{NUM_OF_FIELDS};
 }
 $dbh->disconnect;

=head1 USAGE

=head2 Specifiying Files and Directories

DBD::DBM will automatically supply an appropriate file extension for the type of DBM you are using.  For example, if you use SDBM_File, a table called "fruit" will be stored in two files called "fruit.pag" and "fruit.dir".  You should I<never> specify the file extensions in your SQL statements.

However, I am not aware (and therefore DBD::DBM is not aware) of all possible extensions for various DBM types.  If your DBM type uses an extension other than .pag and .dir, you should set the I<dbm_ext> attribute to the extension. B<And> you should write me with the name of the implementation and extension so I can add it to DBD::DBM!  Thanks in advance for that :-).

    $dbh = DBI->connect('dbi:DBM:ext=.db');  # .db extension is used
    $dbh = DBI->connect('dbi:DBM:ext=');     # no extension is used

or

    $dbh->{dbm_ext}='.db';                      # global setting
    $dbh->{dbm_tables}->{'qux'}->{ext}='.db';   # setting for table 'qux'

By default files are assumed to be in the current working directory.  To have the module look in a different directory, specify the I<f_dir> attribute in either the connect string or by setting the database handle attribute.

For example, this will look for the file /foo/bar/fruit (or /foo/bar/fruit.pag for DBM types that use that extension)

   my $dbh = DBI->connect('dbi:DBM:f_dir=/foo/bar');
   my $ary = $dbh->selectall_arrayref(q{ SELECT * FROM fruit });

And this will too:

   my $dbh = DBI->connect('dbi:DBM:');
   $dbh->{f_dir} = '/foo/bar';
   my $ary = $dbh->selectall_arrayref(q{ SELECT x FROM fruit });

You can also use delimited identifiers to specify paths directly in SQL statements.  This looks in the same place as the two examples above but without setting I<f_dir>:

   my $dbh = DBI->connect('dbi:DBM:');
   my $ary = $dbh->selectall_arrayref(q{
       SELECT x FROM "/foo/bar/fruit"
   });

If you have SQL::Statement installed, you can use table aliases:

   my $dbh = DBI->connect('dbi:DBM:');
   my $ary = $dbh->selectall_arrayref(q{
       SELECT f.x FROM "/foo/bar/fruit" AS f
   });

See the L<GOTCHAS AND WARNINGS> for using DROP on tables.

=head2 Table locking and flock()

Table locking is accomplished using a lockfile which has the same name as the table's file but with the file extension '.lck' (or a lockfile extension that you suppy, see belwo).  This file is created along with the table during a CREATE and removed during a DROP.  Every time the table itself is opened, the lockfile is flocked().  For SELECT, this is an shared lock.  For all other operations, it is an exclusive lock.

Since the locking depends on flock(), it only works on operating systems that support flock().  In cases where flock() is not implemented, DBD::DBM will not complain, it will simply behave as if the flock() had occurred although no actual locking will happen.  Read the documentation for flock() if you need to understand this.

Even on those systems that do support flock(), the locking is only advisory - as is allways the case with flock().  This means that if some other program tries to access the table while DBD::DBM has the table locked, that other program will *succeed* at opening the table.  DBD::DBM's locking only applies to DBD::DBM.  An exception to this would be the situation in which you use a lockfile with the other program that has the same name as the lockfile used in DBD::DBM and that program also uses flock() on that lockfile.  In that case, DBD::DBM and your other program will respect each other's locks.

If you wish to use a lockfile extension other than '.lck', simply specify the dbm_lockfile attribute:

  $dbh = DBI->connect('dbi:DBM:lockfile=.foo');
  $dbh->{dbm_lockfile} = '.foo';
  $dbh->{dbm_tables}->{qux}->{lockfile} = '.foo';

If you wish to disable locking, set the dbm_lockfile equal to 0.

  $dbh = DBI->connect('dbi:DBM:lockfile=0');
  $dbh->{dbm_lockfile} = 0;
  $dbh->{dbm_tables}->{qux}->{lockfile} = 0;

=head2 Specifying the DBM type

Each "flavor" of DBM stores its files in a different format and has different capabilities and different limitations.  See L<AnyDBM_File> for a comparison of DBM types.

By default, DBD::DBM uses the SDBM_File type of storage since SDBM_File comes with Perl itself.  But if you have other types of DBM storage available, you can use any of them with DBD::DBM also.

You can specify the DBM type using the "dbm_type" attribute which can be set in the connection string or with the $dbh->{dbm_type} attribute for global settings or with the $dbh->{dbm_tables}->{$table_name}->{type} attribute for per-table settings in cases where a single script is accessing more than one kind of DBM file.

In the connection string, just set type=TYPENAME where TYPENAME is any DBM type such as GDBM_File, DB_File, etc.  Do I<not> use MLDBM as your dbm_type, that is set differently, see below.

 my $dbh=DBI->connect('dbi:DBM:');               # uses the default SDBM_File
 my $dbh=DBI->connect('dbi:DBM:type=GDBM_File'); # uses the GDBM_File

You can also use $dbh->{dbm_type} to set global DBM type:

 $dbh->{dbm_type} = 'GDBM_File';  # set the global DBM type
 print $dbh->{dbm_type};          # display the global DBM type

If you are going to have several tables in your script that come from different DBM types, you can use the $dbh->{dbm_tables} hash to store different settings for the various tables.  You can even use this to perform joins on files that have completely different storage mechanisms.

 my $dbh->('dbi:DBM:type=GDBM_File');
 #
 # sets global default of GDBM_File

 my $dbh->{dbm_tables}->{foo}->{type} = 'DB_File';
 #
 # over-rides the global setting, but only for the table called "foo"

 print $dbh->{dbm_tables}->{foo}->{type};
 #
 # prints the dbm_type for the table "foo"

=head2 Adding multi-column support with MLDBM

Most of the DBM types only support two columns.  However a CPAN module called MLDBM overcomes this limitation by allowing more than two columns.  It does this by serializing the data - basically it puts a reference to an array into the second column.  It can also put almost any kind of Perl object or even Perl coderefs into columns.

If you want more than two columns, you must install MLDBM.  It's available for many platforms and is easy to install.

MLDBM can use three different modules to serialize the column - Data::Dumper, Storable, and FreezeThaw.  Data::Dumper is the default, Storable is the fastest.  MLDBM can also make use of user-defined serialization methods.  All of this is available to you through DBD::DBM with just one attribute setting.

To use MLDBM with DBD::DBM, you need to set the dbm_mldbm attribute to the name of the serialization module.

Some examples:

 $dbh=DBI->connect('dbi:DBM:mldbm=Storable');  # use MLDBM with Storable
 $dbh=DBI->connect(
    'dbi:DBM:mldbm=MySerializer'           # use MLDBM with a user defined module
 );
 $dbh->{dbm_mldbm} = 'MySerializer';       # same as above
 print $dbh->{dbm_mldbm}                   # show the MLDBM serializer
 $dbh->{dbm_tables}->{foo}->{mldbm}='Data::Dumper';   # set Data::Dumper for table "foo"
 print $dbh->{dbm_tables}->{foo}->{mldbm}; # show serializer for table "foo"

MLDBM works on top of other DBM modules so you can also set a DBM type along with setting dbm_mldbm.  The examples above would default to using SDBM_File with MLDBM.  If you wanted GDBM_File instead, here's how:

 $dbh = DBI->connect('dbi:DBM:type=GDBM_File;mldbm=Storable');
 #
 # uses GDBM_File with MLDBM and Storable

SDBM_File, the default file type is quite limited, so if you are going to use MLDBM, you should probably use a different type, see L<AnyDBM_File>.

See below for some L<Gotchas and Warnings> about MLDBM.

=head2 Support for Berkeley DB

The Berkeley DB storage type is supported through two different Perl modules - DB_File (which supports only features in old versions of Berkeley DB) and BerkeleyDB (which supports all versions).  DBD::DBM supports specifying either "DB_File" or "BerkeleyDB" as a I<dbm_type>, with or without MLDBM support.

The "BerkeleyDB" dbm_type is experimental and its interface is likely to chagne.  It currently defaults to BerkeleyDB::Hash and does not currently support ::Btree or ::Recno.

With BerkeleyDB, you can specify initialization flags by setting them in your script like this:

 my $dbh = DBI->connect('dbi:DBM:type=BerkeleyDB;mldbm=Storable');
 use BerkeleyDB;
 my $env = new BerkeleyDB::Env -Home => $dir;  # and/or other Env flags
 $dbh->{dbm_berkeley_flags} = {
      'DB_CREATE'  => DB_CREATE  # pass in constants
    , 'DB_RDONLY'  => DB_RDONLY  # pass in constants
    , '-Cachesize' => 1000       # set a ::Hash flag
    , '-Env'       => $env       # pass in an environment
 };

Do I<not> set the -Flags or -Filename flags, those are determined by the SQL (e.g. -Flags => DB_RDONLY is set automatically when you issue a SELECT statement).

Time has not permitted me to provide support in this release of DBD::DBM for further Berkeley DB features such as transactions, concurrency, locking, etc.  I will be working on these in the future and would value suggestions, patches, etc.

See L<DB_File> and L<BerkeleyDB> for further details.

=head2 Supported SQL syntax

DBD::DBM uses a subset of SQL.  The robustness of that subset depends on what other modules you have installed. Both options support basic SQL operations including CREATE TABLE, DROP TABLE, INSERT, DELETE, UPDATE, and SELECT.

B<Option #1:> By default, this module inherits its SQL support from DBI::SQL::Nano that comes with DBI.  Nano is, as its name implies, a *very* small SQL engine.  Although limited in scope, it is faster than option #2 for some operations.  See L<DBI::SQL::Nano> for a description of the SQL it supports and comparisons of it with option #2.

B<Option #2:> If you install the pure Perl CPAN module SQL::Statement, DBD::DBM will use it instead of Nano.  This adds support for table aliases, for functions, for joins, and much more.  If you're going to use DBD::DBM for anything other than very simple tables and queries, you should install SQL::Statement.  You don't have to change DBD::DBM or your scripts in any way, simply installing SQL::Statement will give you the more robust SQL capabilities without breaking scripts written for DBI::SQL::Nano.  See L<SQL::Statement> for a description of the SQL it supports.

To find out which SQL module is working in a given script, you can use the dbm_versions() method or, if you don't need the full output and version numbers, just do this:

 print $dbh->{sql_handler};

That will print out either "SQL::Statement" or "DBI::SQL::Nano".

=head2 Optimizing use of key fields

Most "flavors" of DBM have only two physical columns (but can contain multiple logical columns as explained below).  They work similarly to a Perl hash with the first column serving as the key.  Like a Perl hash, DBM files permit you to do quick lookups by specifying the key and thus avoid looping through all records.  Also like a Perl hash, the keys must be unique.  It is impossible to create two records with the same key.  To put this all more simply and in SQL terms, the key column functions as the PRIMARY KEY.

In DBD::DBM, you can take advantage of the speed of keyed lookups by using a WHERE clause with a single equal comparison on the key field.  For example, the following SQL statements are optimized for keyed lookup:

 CREATE TABLE user ( user_name TEXT, phone TEXT);
 INSERT INTO user VALUES ('Fred Bloggs','233-7777');
 # ... many more inserts
 SELECT phone FROM user WHERE user_name='Fred Bloggs';

The "user_name" column is the key column since it is the first column. The SELECT statement uses the key column in a single equal comparision - "user_name='Fred Bloggs' - so the search will find it very quickly without having to loop through however many names were inserted into the table.

In contrast, thes searches on the same table are not optimized:

 1. SELECT phone FROM user WHERE user_name < 'Fred';
 2. SELECT user_name FROM user WHERE phone = '233-7777';

In #1, the operation uses a less-than (<) comparison rather than an equals comparison, so it will not be optimized for key searching.  In #2, the key field "user_name" is not specified in the WHERE clause, and therefore the search will need to loop through all rows to find the desired result.

=head2 Specifying Column Names

DBM files don't have a standard way to store column names.   DBD::DBM gets around this issue with a DBD::DBM specific way of storing the column names.  B<If you are working only with DBD::DBM and not using files created by or accessed with other DBM programs, you can ignore this section.>

DBD::DBM stores column names as a row in the file with the key I<_metadata \0>.  So this code

 my $dbh = DBI->connect('dbi:DBM:');
 $dbh->do("CREATE TABLE baz (foo CHAR(10), bar INTEGER)");
 $dbh->do("INSERT INTO baz (foo,bar) VALUES ('zippy',1)");

Will create a file that has a structure something like this:

  _metadata \0 | foo,bar
  zippy        | 1

The next time you access this table with DBD::DBM, it will treat the _metadata row as a header rather than as data and will pull the column names from there.  However, if you access the file with something other than DBD::DBM, the row will be treated as a regular data row.

If you do not want the column names stored as a data row in the table you can set the I<dbm_store_metadata> attribute to 0.

 my $dbh = DBI->connect('dbi:DBM:store_metadata=0');

or

 $dbh->{dbm_store_metadata} = 0;

or, for per-table setting

 $dbh->{dbm_tables}->{qux}->{store_metadata} = 0;

By default, DBD::DBM assumes that you have two columns named "k" and "v" (short for "key" and "value").  So if you have I<dbm_store_metadata> set to 1 and you want to use alternate column names, you need to specify the column names like this:

 my $dbh = DBI->connect('dbi:DBM:store_metadata=0;cols=foo,bar');

or

 $dbh->{dbm_store_metadata} = 0;
 $dbh->{dbm_cols}           = 'foo,bar';

To set the column names on per-table basis, do this:

 $dbh->{dbm_tables}->{qux}->{store_metadata} = 0;
 $dbh->{dbm_tables}->{qux}->{cols}           = 'foo,bar';
 #
 # sets the column names only for table "qux"

If you have a file that was created by another DBM program or created with I<dbm_store_metadata> set to zero and you want to convert it to using DBD::DBM's column name storage, just use one of the methods above to name the columns but *without* specifying I<dbm_store_metadata> as zero.  You only have to do that once - thereafter you can get by without setting either I<dbm_store_metadata> or setting I<dbm_cols> because the names will be stored in the file.

=head2 Statement handle ($sth) attributes and methods

Most statement handle attributes such as NAME, NUM_OF_FIELDS, etc. are available only after an execute.  The same is true of $sth->rows which is available after the execute but does I<not> require a fetch.

=head2 The $dbh->dbm_versions() method

The private method dbm_versions() presents a summary of what other modules are being used at any given time.  DBD::DBM can work with or without many other modules - it can use either SQL::Statement or DBI::SQL::Nano as its SQL engine, it can be run with DBI or DBI::PurePerl, it can use many kinds of DBM modules, and many kinds of serializers when run with MLDBM.  The dbm_versions() method reports on all of that and more.

  print $dbh->dbm_versions;               # displays global settings
  print $dbh->dbm_versions($table_name);  # displays per table settings

An important thing to note about this method is that when called with no arguments, it displays the *global* settings.  If you over-ride these by setting per-table attributes, these will I<not> be shown unless you specifiy a table name as an argument to the method call.

=head2 Storing Objects

If you are using MLDBM, you can use DBD::DBM to take advantage of its serializing abilities to serialize any Perl object that MLDBM can handle.  To store objects in columns, you should (but don't absolutely need to) declare it as a column of type BLOB (the type is *currently* ignored by the SQL engine, but heh, it's good form).

You *must* use placeholders to insert or refer to the data.

=head1 GOTCHAS AND WARNINGS

Using the SQL DROP command will remove any file that has the name specified in the command with either '.pag' or '.dir' or your {dbm_ext} appended to it.  So
this be dangerous if you aren't sure what file it refers to:

 $dbh->do(qq{DROP TABLE "/path/to/any/file"});

Each DBM type has limitations.  SDBM_File, for example, can only store values of less than 1,000 characters.  *You* as the script author must ensure that you don't exceed those bounds.  If you try to insert a value that is bigger than the DBM can store, the results will be unpredictable.  See the documentation for whatever DBM you are using for details.

Different DBM implementations return records in different orders.  That means that you can I<not> depend on the order of records unless you use an ORDER BY statement.  DBI::SQL::Nano does not currently support ORDER BY (though it may soon) so if you need ordering, you'll have to install SQL::Statement.

DBM data files are platform-specific.  To move them from one platform to another, you'll need to do something along the lines of dumping your data to CSV on platform #1 and then dumping from CSV to DBM on platform #2.  DBD::AnyData and DBD::CSV can help with that.  There may also be DBM conversion tools for your platforms which would probably be quickest.

When using MLDBM, there is a very powerful serializer - it will allow you to store Perl code or objects in database columns.  When these get de-serialized, they may be evaled - in other words MLDBM (or actually Data::Dumper when used by MLDBM) may take the values and try to execute them in Perl.  Obviously, this can present dangers, so if you don't know what's in a file, be careful before you access it with MLDBM turned on!

See the entire section on L<Table locking and flock()> for gotchas and warnings about the use of flock().

=head1 GETTING HELP, MAKING SUGGESTIONS, AND REPORTING BUGS

If you need help installing or using DBD::DBM, please write to the DBI users mailing list at dbi-users@perl.org or to the comp.lang.perl.modules newsgroup on usenet.  I'm afraid I can't always answer these kinds of questions quickly and there are many on the mailing list or in the newsgroup who can.

If you have suggestions, ideas for improvements, or bugs to report, please write me directly at the email shown below.

When reporting bugs, please send the output of $dbh->dbm_versions($table) for a table that exhibits the bug and, if possible, as small a sample as you can make of the code that produces the bug.  And of course, patches are welcome too :-).

=head1 ACKNOWLEDGEMENTS

Many, many thanks to Tim Bunce for prodding me to write this, and for copious, wise, and patient suggestions all along the way.

=head1 AUTHOR AND COPYRIGHT

This module is written and maintained by

Jeff Zucker < jzucker AT cpan.org >

Copyright (c) 2004 by Jeff Zucker, all rights reserved.

You may freely distribute and/or modify this module under the terms of either the GNU General Public License (GPL) or the Artistic License, as specified in the Perl README file.

=head1 SEE ALSO

L<DBI>, L<SQL::Statement>, L<DBI::SQL::Nano>, L<AnyDBM_File>, L<MLDBM>

=cut

