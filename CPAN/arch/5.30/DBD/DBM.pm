#######################################################################
#
#  DBD::DBM - a DBI driver for DBM files
#
#  Copyright (c) 2004 by Jeff Zucker < jzucker AT cpan.org >
#  Copyright (c) 2010-2013 by Jens Rehsack & H.Merijn Brand
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
require 5.008;
use strict;

#################
package DBD::DBM;
#################
use base qw( DBD::File );
use vars qw($VERSION $ATTRIBUTION $drh $methods_already_installed);
$VERSION     = '0.08';
$ATTRIBUTION = 'DBD::DBM by Jens Rehsack';

# no need to have driver() unless you need private methods
#
sub driver ($;$)
{
    my ( $class, $attr ) = @_;
    return $drh if ($drh);

    # do the real work in DBD::File
    #
    $attr->{Attribution} = 'DBD::DBM by Jens Rehsack';
    $drh = $class->SUPER::driver($attr);

    # install private methods
    #
    # this requires that dbm_ (or foo_) be a registered prefix
    # but you can write private methods before official registration
    # by hacking the $dbd_prefix_registry in a private copy of DBI.pm
    #
    unless ( $methods_already_installed++ )
    {
        DBD::DBM::st->install_method('dbm_schema');
    }

    return $drh;
}

sub CLONE
{
    undef $drh;
}

#####################
package DBD::DBM::dr;
#####################
$DBD::DBM::dr::imp_data_size = 0;
@DBD::DBM::dr::ISA           = qw(DBD::File::dr);

# you could put some :dr private methods here

# you may need to over-ride some DBD::File::dr methods here
# but you can probably get away with just letting it do the work
# in most cases

#####################
package DBD::DBM::db;
#####################
$DBD::DBM::db::imp_data_size = 0;
@DBD::DBM::db::ISA           = qw(DBD::File::db);

use Carp qw/carp/;

sub validate_STORE_attr
{
    my ( $dbh, $attrib, $value ) = @_;

    if ( $attrib eq "dbm_ext" or $attrib eq "dbm_lockfile" )
    {
        ( my $newattrib = $attrib ) =~ s/^dbm_/f_/g;
        carp "Attribute '$attrib' is depreciated, use '$newattrib' instead" if ($^W);
        $attrib = $newattrib;
    }

    return $dbh->SUPER::validate_STORE_attr( $attrib, $value );
}

sub validate_FETCH_attr
{
    my ( $dbh, $attrib ) = @_;

    if ( $attrib eq "dbm_ext" or $attrib eq "dbm_lockfile" )
    {
        ( my $newattrib = $attrib ) =~ s/^dbm_/f_/g;
        carp "Attribute '$attrib' is depreciated, use '$newattrib' instead" if ($^W);
        $attrib = $newattrib;
    }

    return $dbh->SUPER::validate_FETCH_attr($attrib);
}

sub set_versions
{
    my $this = $_[0];
    $this->{dbm_version} = $DBD::DBM::VERSION;
    return $this->SUPER::set_versions();
}

sub init_valid_attributes
{
    my $dbh = shift;

    # define valid private attributes
    #
    # attempts to set non-valid attrs in connect() or
    # with $dbh->{attr} will throw errors
    #
    # the attrs here *must* start with dbm_ or foo_
    #
    # see the STORE methods below for how to check these attrs
    #
    $dbh->{dbm_valid_attrs} = {
                                dbm_type           => 1,    # the global DBM type e.g. SDBM_File
                                dbm_mldbm          => 1,    # the global MLDBM serializer
                                dbm_cols           => 1,    # the global column names
                                dbm_version        => 1,    # verbose DBD::DBM version
                                dbm_store_metadata => 1,    # column names, etc.
                                dbm_berkeley_flags => 1,    # for BerkeleyDB
                                dbm_valid_attrs    => 1,    # DBD::DBM::db valid attrs
                                dbm_readonly_attrs => 1,    # DBD::DBM::db r/o attrs
                                dbm_meta           => 1,    # DBD::DBM public access for f_meta
                                dbm_tables         => 1,    # DBD::DBM public access for f_meta
                              };
    $dbh->{dbm_readonly_attrs} = {
                                   dbm_version        => 1,    # verbose DBD::DBM version
                                   dbm_valid_attrs    => 1,    # DBD::DBM::db valid attrs
                                   dbm_readonly_attrs => 1,    # DBD::DBM::db r/o attrs
                                   dbm_meta           => 1,    # DBD::DBM public access for f_meta
                                 };

    $dbh->{dbm_meta} = "dbm_tables";

    return $dbh->SUPER::init_valid_attributes();
}

sub init_default_attributes
{
    my ( $dbh, $phase ) = @_;

    $dbh->SUPER::init_default_attributes($phase);
    $dbh->{f_lockfile} = '.lck';

    return $dbh;
}

sub get_dbm_versions
{
    my ( $dbh, $table ) = @_;
    $table ||= '';

    my $meta;
    my $class = $dbh->{ImplementorClass};
    $class =~ s/::db$/::Table/;
    $table and ( undef, $meta ) = $class->get_table_meta( $dbh, $table, 1 );
    $meta or ( $meta = {} and $class->bootstrap_table_meta( $dbh, $meta, $table ) );

    my $dver;
    my $dtype = $meta->{dbm_type};
    eval {
        $dver = $meta->{dbm_type}->VERSION();

        # *) when we're still alive here, everything went ok - no need to check for $@
        $dtype .= " ($dver)";
    };
    if ( $meta->{dbm_mldbm} )
    {
        $dtype .= ' + MLDBM';
        eval {
            $dver = MLDBM->VERSION();
            $dtype .= " ($dver)";    # (*)
        };
        eval {
            my $ser_class = "MLDBM::Serializer::" . $meta->{dbm_mldbm};
            my $ser_mod   = $ser_class;
            $ser_mod =~ s|::|/|g;
            $ser_mod .= ".pm";
            require $ser_mod;
            $dver = $ser_class->VERSION();
            $dtype .= ' + ' . $ser_class;    # (*)
            $dver and $dtype .= " ($dver)";  # (*)
        };
    }
    return sprintf( "%s using %s", $dbh->{dbm_version}, $dtype );
}

# you may need to over-ride some DBD::File::db methods here
# but you can probably get away with just letting it do the work
# in most cases

#####################
package DBD::DBM::st;
#####################
$DBD::DBM::st::imp_data_size = 0;
@DBD::DBM::st::ISA           = qw(DBD::File::st);

sub FETCH
{
    my ( $sth, $attr ) = @_;

    if ( $attr eq "NULLABLE" )
    {
        my @colnames = $sth->sql_get_colnames();

        # XXX only BerkeleyDB fails having NULL values for non-MLDBM databases,
        #     none accept it for key - but it requires more knowledge between
        #     queries and tables storage to return fully correct information
        $attr eq "NULLABLE" and return [ map { 0 } @colnames ];
    }

    return $sth->SUPER::FETCH($attr);
}    # FETCH

sub dbm_schema
{
    my ( $sth, $tname ) = @_;
    return $sth->set_err( $DBI::stderr, 'No table name supplied!' ) unless $tname;
    my $tbl_meta = $sth->{Database}->func( $tname, "f_schema", "get_sql_engine_meta" )
      or return $sth->set_err( $sth->{Database}->err(), $sth->{Database}->errstr() );
    return $tbl_meta->{$tname}->{f_schema};
}
# you could put some :st private methods here

# you may need to over-ride some DBD::File::st methods here
# but you can probably get away with just letting it do the work
# in most cases

############################
package DBD::DBM::Statement;
############################

@DBD::DBM::Statement::ISA = qw(DBD::File::Statement);

########################
package DBD::DBM::Table;
########################
use Carp;
use Fcntl;

@DBD::DBM::Table::ISA = qw(DBD::File::Table);

my $dirfext = $^O eq 'VMS' ? '.sdbm_dir' : '.dir';

my %reset_on_modify = (
                        dbm_type  => "dbm_tietype",
                        dbm_mldbm => "dbm_tietype",
                      );
__PACKAGE__->register_reset_on_modify( \%reset_on_modify );

my %compat_map = (
                   ( map { $_ => "dbm_$_" } qw(type mldbm store_metadata) ),
                   dbm_ext      => 'f_ext',
                   dbm_file     => 'f_file',
                   dbm_lockfile => ' f_lockfile',
                 );
__PACKAGE__->register_compat_map( \%compat_map );

sub bootstrap_table_meta
{
    my ( $self, $dbh, $meta, $table ) = @_;

    $meta->{dbm_type} ||= $dbh->{dbm_type} || 'SDBM_File';
    $meta->{dbm_mldbm} ||= $dbh->{dbm_mldbm} if ( $dbh->{dbm_mldbm} );
    $meta->{dbm_berkeley_flags} ||= $dbh->{dbm_berkeley_flags};

    defined $meta->{f_ext}
      or $meta->{f_ext} = $dbh->{f_ext};
    unless ( defined( $meta->{f_ext} ) )
    {
        my $ext;
        if ( $meta->{dbm_type} eq 'SDBM_File' or $meta->{dbm_type} eq 'ODBM_File' )
        {
            $ext = '.pag/r';
        }
        elsif ( $meta->{dbm_type} eq 'NDBM_File' )
        {
            # XXX NDBM_File on FreeBSD (and elsewhere?) may actually be Berkeley
            # behind the scenes and so create a single .db file.
            if ( $^O =~ /bsd/i or lc($^O) eq 'darwin' )
            {
                $ext = '.db/r';
            }
            elsif ( $^O eq 'SunOS' or $^O eq 'Solaris' or $^O eq 'AIX' )
            {
                $ext = '.pag/r';    # here it's implemented like dbm - just a bit improved
            }
            # else wrapped GDBM
        }
        defined($ext) and $meta->{f_ext} = $ext;
    }

    $self->SUPER::bootstrap_table_meta( $dbh, $meta, $table );
}

sub init_table_meta
{
    my ( $self, $dbh, $meta, $table ) = @_;

    $meta->{f_dontopen} = 1;

    unless ( defined( $meta->{dbm_tietype} ) )
    {
        my $tie_type = $meta->{dbm_type};
        $INC{"$tie_type.pm"} or require "$tie_type.pm";
        $tie_type eq 'BerkeleyDB' and $tie_type = 'BerkeleyDB::Hash';

        if ( $meta->{dbm_mldbm} )
        {
            $INC{"MLDBM.pm"} or require "MLDBM.pm";
            $meta->{dbm_usedb} = $tie_type;
            $tie_type = 'MLDBM';
        }

        $meta->{dbm_tietype} = $tie_type;
    }

    unless ( defined( $meta->{dbm_store_metadata} ) )
    {
        my $store = $dbh->{dbm_store_metadata};
        defined($store) or $store = 1;
        $meta->{dbm_store_metadata} = $store;
    }

    unless ( defined( $meta->{col_names} ) )
    {
        defined( $dbh->{dbm_cols} ) and $meta->{col_names} = $dbh->{dbm_cols};
    }

    $self->SUPER::init_table_meta( $dbh, $meta, $table );
}

sub open_data
{
    my ( $className, $meta, $attrs, $flags ) = @_;
    $className->SUPER::open_data( $meta, $attrs, $flags );

    unless ( $flags->{dropMode} )
    {
        # TIEING
        #
        # XXX allow users to pass in a pre-created tied object
        #
        my @tie_args;
        if ( $meta->{dbm_type} eq 'BerkeleyDB' )
        {
            my $DB_CREATE = BerkeleyDB::DB_CREATE();
            my $DB_RDONLY = BerkeleyDB::DB_RDONLY();
            my %tie_flags;
            if ( my $f = $meta->{dbm_berkeley_flags} )
            {
                defined( $f->{DB_CREATE} ) and $DB_CREATE = delete $f->{DB_CREATE};
                defined( $f->{DB_RDONLY} ) and $DB_RDONLY = delete $f->{DB_RDONLY};
                %tie_flags = %$f;
            }
            my $open_mode = $flags->{lockMode} || $flags->{createMode} ? $DB_CREATE : $DB_RDONLY;
            @tie_args = (
                          -Filename => $meta->{f_fqbn},
                          -Flags    => $open_mode,
                          %tie_flags
                        );
        }
        else
        {
            my $open_mode = O_RDONLY;
            $flags->{lockMode}   and $open_mode = O_RDWR;
            $flags->{createMode} and $open_mode = O_RDWR | O_CREAT | O_TRUNC;

            @tie_args = ( $meta->{f_fqbn}, $open_mode, 0666 );
        }

        if ( $meta->{dbm_mldbm} )
        {
            $MLDBM::UseDB      = $meta->{dbm_usedb};
            $MLDBM::Serializer = $meta->{dbm_mldbm};
        }

        $meta->{hash} = {};
        my $tie_class = $meta->{dbm_tietype};
        eval { tie %{ $meta->{hash} }, $tie_class, @tie_args };
        $@ and croak "Cannot tie(\%h $tie_class @tie_args): $@";
        -f $meta->{f_fqfn} or croak( "No such file: '" . $meta->{f_fqfn} . "'" );
    }

    unless ( $flags->{createMode} )
    {
        my ( $meta_data, $schema, $col_names );
        if ( $meta->{dbm_store_metadata} )
        {
            $meta_data = $col_names = $meta->{hash}->{"_metadata \0"};
            if ( $meta_data and $meta_data =~ m~<dbd_metadata>(.+)</dbd_metadata>~is )
            {
                $schema = $col_names = $1;
                $schema    =~ s~.*<schema>(.+)</schema>.*~$1~is;
                $col_names =~ s~.*<col_names>(.+)</col_names>.*~$1~is;
            }
        }
        $col_names ||= $meta->{col_names} || [ 'k', 'v' ];
        $col_names = [ split /,/, $col_names ] if ( ref $col_names ne 'ARRAY' );
        if ( $meta->{dbm_store_metadata} and not $meta->{hash}->{"_metadata \0"} )
        {
            $schema or $schema = '';
            $meta->{hash}->{"_metadata \0"} =
                "<dbd_metadata>"
              . "<schema>$schema</schema>"
              . "<col_names>"
              . join( ",", @{$col_names} )
              . "</col_names>"
              . "</dbd_metadata>";
        }

        $meta->{schema}    = $schema;
        $meta->{col_names} = $col_names;
    }
}

# you must define drop
# it is called from execute of a SQL DROP statement
#
sub drop ($$)
{
    my ( $self, $data ) = @_;
    my $meta = $self->{meta};
    $meta->{hash} and untie %{ $meta->{hash} };
    $self->SUPER::drop($data);
    # XXX extra_files
    -f $meta->{f_fqbn} . $dirfext
      and $meta->{f_ext} eq '.pag/r'
      and unlink( $meta->{f_fqbn} . $dirfext );
    return 1;
}

# you must define fetch_row, it is called on all fetches;
# it MUST return undef when no rows are left to fetch;
# checking for $ary[0] is specific to hashes so you'll
# probably need some other kind of check for nothing-left.
# as Janis might say: "undef's just another word for
# nothing left to fetch" :-)
#
sub fetch_row ($$)
{
    my ( $self, $data ) = @_;
    my $meta = $self->{meta};
    # fetch with %each
    #
    my @ary = each %{ $meta->{hash} };
          $meta->{dbm_store_metadata}
      and $ary[0]
      and $ary[0] eq "_metadata \0"
      and @ary = each %{ $meta->{hash} };

    my ( $key, $val ) = @ary;
    unless ($key)
    {
        delete $self->{row};
        return;
    }
    my @row = ( ref($val) eq 'ARRAY' ) ? ( $key, @$val ) : ( $key, $val );
    $self->{row} = @row ? \@row : undef;
    return wantarray ? @row : \@row;
}

# you must define push_row except insert_new_row and update_specific_row is defined
# it is called on inserts and updates as primitive
#
sub insert_new_row ($$$)
{
    my ( $self, $data, $row_aryref ) = @_;
    my $meta   = $self->{meta};
    my $ncols  = scalar( @{ $meta->{col_names} } );
    my $nitems = scalar( @{$row_aryref} );
    $ncols == $nitems
      or croak "You tried to insert $nitems, but table is created with $ncols columns";

    my $key = shift @$row_aryref;
    my $exists;
    eval { $exists = exists( $meta->{hash}->{$key} ); };
    $exists and croak "Row with PK '$key' already exists";

    $meta->{hash}->{$key} = $meta->{dbm_mldbm} ? $row_aryref : $row_aryref->[0];

    return 1;
}

# this is where you grab the column names from a CREATE statement
# if you don't need to do that, it must be defined but can be empty
#
sub push_names ($$$)
{
    my ( $self, $data, $row_aryref ) = @_;
    my $meta = $self->{meta};

    # some sanity checks ...
    my $ncols = scalar(@$row_aryref);
    $ncols < 2 and croak "At least 2 columns are required for DBD::DBM tables ...";
    !$meta->{dbm_mldbm}
      and $ncols > 2
      and croak "Without serializing with MLDBM only 2 columns are supported, you give $ncols";
    $meta->{col_names} = $row_aryref;
    return unless $meta->{dbm_store_metadata};

    my $stmt      = $data->{sql_stmt};
    my $col_names = join( ',', @{$row_aryref} );
    my $schema    = $data->{Database}->{Statement};
    $schema =~ s/^[^\(]+\((.+)\)$/$1/s;
    $schema = $stmt->schema_str() if ( $stmt->can('schema_str') );
    $meta->{hash}->{"_metadata \0"} =
        "<dbd_metadata>"
      . "<schema>$schema</schema>"
      . "<col_names>$col_names</col_names>"
      . "</dbd_metadata>";
}

# fetch_one_row, delete_one_row, update_one_row
# are optimized for hash-style lookup without looping;
# if you don't need them, omit them, they're optional
# but, in that case you may need to define
# truncate() and seek(), see below
#
sub fetch_one_row ($$;$)
{
    my ( $self, $key_only, $key ) = @_;
    my $meta = $self->{meta};
    $key_only and return $meta->{col_names}->[0];
    exists $meta->{hash}->{$key} or return;
    my $val = $meta->{hash}->{$key};
    $val = ( ref($val) eq 'ARRAY' ) ? $val : [$val];
    my $row = [ $key, @$val ];
    return wantarray ? @{$row} : $row;
}

sub delete_one_row ($$$)
{
    my ( $self, $data, $aryref ) = @_;
    my $meta = $self->{meta};
    delete $meta->{hash}->{ $aryref->[0] };
}

sub update_one_row ($$$)
{
    my ( $self, $data, $aryref ) = @_;
    my $meta = $self->{meta};
    my $key  = shift @$aryref;
    defined $key or return;
    my $row = ( ref($aryref) eq 'ARRAY' ) ? $aryref : [$aryref];
    $meta->{hash}->{$key} = $meta->{dbm_mldbm} ? $row : $row->[0];
}

sub update_specific_row ($$$$)
{
    my ( $self, $data, $aryref, $origary ) = @_;
    my $meta   = $self->{meta};
    my $key    = shift @$origary;
    my $newkey = shift @$aryref;
    return unless ( defined $key );
    $key eq $newkey or delete $meta->{hash}->{$key};
    my $row = ( ref($aryref) eq 'ARRAY' ) ? $aryref : [$aryref];
    $meta->{hash}->{$newkey} = $meta->{dbm_mldbm} ? $row : $row->[0];
}

# you may not need to explicitly DESTROY the ::Table
# put cleanup code to run when the execute is done
#
sub DESTROY ($)
{
    my $self = shift;
    my $meta = $self->{meta};
    $meta->{hash} and untie %{ $meta->{hash} };

    $self->SUPER::DESTROY();
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
sub truncate ($$)
{
    # my ( $self, $data ) = @_;
    return 1;
}

# seek() is only needed if you use IO::File
# though it could be used for other non-file operations
# that you need to do before "writes" or truncate()
#
sub seek ($$$$)
{
    # my ( $self, $data, $pos, $whence ) = @_;
    return 1;
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
 $dbh = DBI->connect('dbi:DBM:');                    # defaults to SDBM_File
 $dbh = DBI->connect('DBI:DBM(RaiseError=1):');      # defaults to SDBM_File
 $dbh = DBI->connect('dbi:DBM:dbm_type=DB_File');    # defaults to DB_File
 $dbh = DBI->connect('dbi:DBM:dbm_mldbm=Storable');  # MLDBM with SDBM_File

 # or
 $dbh = DBI->connect('dbi:DBM:', undef, undef);
 $dbh = DBI->connect('dbi:DBM:', undef, undef, {
     f_ext              => '.db/r',
     f_dir              => '/path/to/dbfiles/',
     f_lockfile         => '.lck',
     dbm_type           => 'BerkeleyDB',
     dbm_mldbm          => 'FreezeThaw',
     dbm_store_metadata => 1,
     dbm_berkeley_flags => {
	 '-Cachesize' => 1000, # set a ::Hash flag
     },
 });

and other variations on connect() as shown in the L<DBI> docs,
L<DBD::File metadata|DBD::File/Metadata> and L</Metadata>
shown below.

Use standard DBI prepare, execute, fetch, placeholders, etc.,
see L<QUICK START> for an example.

=head1 DESCRIPTION

DBD::DBM is a database management system that works right out of the
box.  If you have a standard installation of Perl and DBI you can
begin creating, accessing, and modifying simple database tables
without any further modules.  You can add other modules (e.g.,
SQL::Statement, DB_File etc) for improved functionality.

The module uses a DBM file storage layer.  DBM file storage is common on
many platforms and files can be created with it in many programming
languages using different APIs. That means, in addition to creating
files with DBI/SQL, you can also use DBI/SQL to access and modify files
created by other DBM modules and programs and vice versa. B<Note> that
in those cases it might be necessary to use a common subset of the
provided features.

DBM files are stored in binary format optimized for quick retrieval
when using a key field.  That optimization can be used advantageously
to make DBD::DBM SQL operations that use key fields very fast.  There
are several different "flavors" of DBM which use different storage
formats supported by perl modules such as SDBM_File and MLDBM.  This
module supports all of the flavors that perl supports and, when used
with MLDBM, supports tables with any number of columns and insertion
of Perl objects into tables.

DBD::DBM has been tested with the following DBM types: SDBM_File,
NDBM_File, ODBM_File, GDBM_File, DB_File, BerkeleyDB.  Each type was
tested both with and without MLDBM and with the Data::Dumper,
Storable, FreezeThaw, YAML and JSON serializers using the DBI::SQL::Nano
or the SQL::Statement engines.

=head1 QUICK START

DBD::DBM operates like all other DBD drivers - it's basic syntax and
operation is specified by DBI.  If you're not familiar with DBI, you should
start by reading L<DBI> and the documents it points to and then come back
and read this file.  If you are familiar with DBI, you already know most of
what you need to know to operate this module.  Just jump in and create a
test script something like the one shown below.

You should be aware that there are several options for the SQL engine
underlying DBD::DBM, see L<Supported SQL syntax>.  There are also many
options for DBM support, see especially the section on L<Adding
multi-column support with MLDBM>.

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

This section will explain some usage cases in more detail. To get an
overview about the available attributes, see L</Metadata>.

=head2 Specifying Files and Directories

DBD::DBM will automatically supply an appropriate file extension for the
type of DBM you are using.  For example, if you use SDBM_File, a table
called "fruit" will be stored in two files called "fruit.pag" and
"fruit.dir".  You should B<never> specify the file extensions in your SQL
statements.

DBD::DBM recognizes following default extensions for following types:

=over 4

=item .pag/r

Chosen for dbm_type C<< SDBM_File >>, C<< ODBM_File >> and C<< NDBM_File >>
when an implementation is detected which wraps C<< -ldbm >> for
C<< NDBM_File >> (e.g. Solaris, AIX, ...).

For those types, the C<< .dir >> extension is recognized, too (for being
deleted when dropping a table).

=item .db/r

Chosen for dbm_type C<< NDBM_File >> when an implementation is detected
which wraps BerkeleyDB 1.x for C<< NDBM_File >> (typically BSD's, Darwin).

=back

C<< GDBM_File >>, C<< DB_File >> and C<< BerkeleyDB >> don't usually
use a file extension.

If your DBM type uses an extension other than one of the recognized
types of extensions, you should set the I<f_ext> attribute to the
extension B<and> file a bug report as described in DBI with the name
of the implementation and extension so we can add it to DBD::DBM.
Thanks in advance for that :-).

  $dbh = DBI->connect('dbi:DBM:f_ext=.db');  # .db extension is used
  $dbh = DBI->connect('dbi:DBM:f_ext=');     # no extension is used

  # or
  $dbh->{f_ext}='.db';                       # global setting
  $dbh->{f_meta}->{'qux'}->{f_ext}='.db';    # setting for table 'qux'

By default files are assumed to be in the current working directory.
To use other directories specify the I<f_dir> attribute in either the
connect string or by setting the database handle attribute.

For example, this will look for the file /foo/bar/fruit (or
/foo/bar/fruit.pag for DBM types that use that extension)

  my $dbh = DBI->connect('dbi:DBM:f_dir=/foo/bar');
  # and this will too:
  my $dbh = DBI->connect('dbi:DBM:');
  $dbh->{f_dir} = '/foo/bar';
  # but this is recommended
  my $dbh = DBI->connect('dbi:DBM:', undef, undef, { f_dir => '/foo/bar' } );

  # now you can do
  my $ary = $dbh->selectall_arrayref(q{ SELECT x FROM fruit });

You can also use delimited identifiers to specify paths directly in SQL
statements.  This looks in the same place as the two examples above but
without setting I<f_dir>:

   my $dbh = DBI->connect('dbi:DBM:');
   my $ary = $dbh->selectall_arrayref(q{
       SELECT x FROM "/foo/bar/fruit"
   });

You can also tell DBD::DBM to use a specified path for a specific table:

  $dbh->{dbm_tables}->{f}->{file} = q(/foo/bar/fruit);

Please be aware that you cannot specify this during connection.

If you have SQL::Statement installed, you can use table aliases:

   my $dbh = DBI->connect('dbi:DBM:');
   my $ary = $dbh->selectall_arrayref(q{
       SELECT f.x FROM "/foo/bar/fruit" AS f
   });

See the L<GOTCHAS AND WARNINGS> for using DROP on tables.

=head2 Table locking and flock()

Table locking is accomplished using a lockfile which has the same
basename as the table's file but with the file extension '.lck' (or a
lockfile extension that you supply, see below).  This lock file is
created with the table during a CREATE and removed during a DROP.
Every time the table itself is opened, the lockfile is flocked().  For
SELECT, this is a shared lock.  For all other operations, it is an
exclusive lock (except when you specify something different using the
I<f_lock> attribute).

Since the locking depends on flock(), it only works on operating
systems that support flock().  In cases where flock() is not
implemented, DBD::DBM will simply behave as if the flock() had
occurred although no actual locking will happen.  Read the
documentation for flock() for more information.

Even on those systems that do support flock(), locking is only
advisory - as is always the case with flock().  This means that if
another program tries to access the table file while DBD::DBM has the
table locked, that other program will *succeed* at opening unless
it is also using flock on the '.lck' file.  As a result DBD::DBM's
locking only really applies to other programs using DBD::DBM or other
program written to cooperate with DBD::DBM locking.

=head2 Specifying the DBM type

Each "flavor" of DBM stores its files in a different format and has
different capabilities and limitations. See L<AnyDBM_File> for a
comparison of DBM types.

By default, DBD::DBM uses the C<< SDBM_File >> type of storage since
C<< SDBM_File >> comes with Perl itself. If you have other types of
DBM storage available, you can use any of them with DBD::DBM. It is
strongly recommended to use at least C<< DB_File >>, because C<<
SDBM_File >> has quirks and limitations and C<< ODBM_file >>, C<<
NDBM_File >> and C<< GDBM_File >> are not always available.

You can specify the DBM type using the I<dbm_type> attribute which can
be set in the connection string or with C<< $dbh->{dbm_type} >> and
C<< $dbh->{f_meta}->{$table_name}->{type} >> for per-table settings in
cases where a single script is accessing more than one kind of DBM
file.

In the connection string, just set C<< dbm_type=TYPENAME >> where
C<< TYPENAME >> is any DBM type such as GDBM_File, DB_File, etc. Do I<not>
use MLDBM as your I<dbm_type> as that is set differently, see below.

 my $dbh=DBI->connect('dbi:DBM:');                # uses the default SDBM_File
 my $dbh=DBI->connect('dbi:DBM:dbm_type=GDBM_File'); # uses the GDBM_File

 # You can also use $dbh->{dbm_type} to set the DBM type for the connection:
 $dbh->{dbm_type} = 'DB_File';    # set the global DBM type
 print $dbh->{dbm_type};          # display the global DBM type

If you have several tables in your script that use different DBM
types, you can use the $dbh->{dbm_tables} hash to store different
settings for the various tables.  You can even use this to perform
joins on files that have completely different storage mechanisms.

 # sets global default of GDBM_File
 my $dbh->('dbi:DBM:type=GDBM_File');

 # overrides the global setting, but only for the tables called
 # I<foo> and I<bar>
 my $dbh->{f_meta}->{foo}->{dbm_type} = 'DB_File';
 my $dbh->{f_meta}->{bar}->{dbm_type} = 'BerkeleyDB';

 # prints the dbm_type for the table "foo"
 print $dbh->{f_meta}->{foo}->{dbm_type};

B<Note> that you must change the I<dbm_type> of a table before you access
it for first time.

=head2 Adding multi-column support with MLDBM

Most of the DBM types only support two columns and even if it would
support more, DBD::DBM would only use two. However a CPAN module
called MLDBM overcomes this limitation by allowing more than two
columns.  MLDBM does this by serializing the data - basically it puts
a reference to an array into the second column. It can also put almost
any kind of Perl object or even B<Perl coderefs> into columns.

If you want more than two columns, you B<must> install MLDBM. It's available
for many platforms and is easy to install.

MLDBM is by default distributed with three serializers - Data::Dumper,
Storable, and FreezeThaw. Data::Dumper is the default and Storable is the
fastest. MLDBM can also make use of user-defined serialization methods or
other serialization modules (e.g. L<YAML::MLDBM> or
L<MLDBM::Serializer::JSON>. You select the serializer using the
I<dbm_mldbm> attribute.

Some examples:

 $dbh=DBI->connect('dbi:DBM:dbm_mldbm=Storable');  # use MLDBM with Storable
 $dbh=DBI->connect(
    'dbi:DBM:dbm_mldbm=MySerializer' # use MLDBM with a user defined module
 );
 $dbh=DBI->connect('dbi::dbm:', undef,
     undef, { dbm_mldbm => 'YAML' }); # use 3rd party serializer
 $dbh->{dbm_mldbm} = 'YAML'; # same as above
 print $dbh->{dbm_mldbm} # show the MLDBM serializer
 $dbh->{f_meta}->{foo}->{dbm_mldbm}='Data::Dumper';   # set Data::Dumper for table "foo"
 print $dbh->{f_meta}->{foo}->{mldbm}; # show serializer for table "foo"

MLDBM works on top of other DBM modules so you can also set a DBM type
along with setting dbm_mldbm.  The examples above would default to using
SDBM_File with MLDBM.  If you wanted GDBM_File instead, here's how:

 # uses DB_File with MLDBM and Storable
 $dbh = DBI->connect('dbi:DBM:', undef, undef, {
     dbm_type  => 'DB_File',
     dbm_mldbm => 'Storable',
 });

SDBM_File, the default I<dbm_type> is quite limited, so if you are going to
use MLDBM, you should probably use a different type, see L<AnyDBM_File>.

See below for some L<GOTCHAS AND WARNINGS> about MLDBM.

=head2 Support for Berkeley DB

The Berkeley DB storage type is supported through two different Perl
modules - DB_File (which supports only features in old versions of Berkeley
DB) and BerkeleyDB (which supports all versions).  DBD::DBM supports
specifying either "DB_File" or "BerkeleyDB" as a I<dbm_type>, with or
without MLDBM support.

The "BerkeleyDB" dbm_type is experimental and it's interface is likely to
change.  It currently defaults to BerkeleyDB::Hash and does not currently
support ::Btree or ::Recno.

With BerkeleyDB, you can specify initialization flags by setting them in
your script like this:

 use BerkeleyDB;
 my $env = new BerkeleyDB::Env -Home => $dir;  # and/or other Env flags
 $dbh = DBI->connect('dbi:DBM:', undef, undef, {
     dbm_type  => 'BerkeleyDB',
     dbm_mldbm => 'Storable',
     dbm_berkeley_flags => {
	 'DB_CREATE'  => DB_CREATE,  # pass in constants
	 'DB_RDONLY'  => DB_RDONLY,  # pass in constants
	 '-Cachesize' => 1000,       # set a ::Hash flag
	 '-Env'       => $env,       # pass in an environment
     },
 });

Do I<not> set the -Flags or -Filename flags as those are determined and
overwritten by the SQL (e.g. -Flags => DB_RDONLY is set automatically
when you issue a SELECT statement).

Time has not permitted us to provide support in this release of DBD::DBM
for further Berkeley DB features such as transactions, concurrency,
locking, etc. We will be working on these in the future and would value
suggestions, patches, etc.

See L<DB_File> and L<BerkeleyDB> for further details.

=head2 Optimizing the use of key fields

Most "flavors" of DBM have only two physical columns (but can contain
multiple logical columns as explained above in
L<Adding multi-column support with MLDBM>). They work similarly to a
Perl hash with the first column serving as the key. Like a Perl hash, DBM
files permit you to do quick lookups by specifying the key and thus avoid
looping through all records (supported by DBI::SQL::Nano only). Also like
a Perl hash, the keys must be unique. It is impossible to create two
records with the same key.  To put this more simply and in SQL terms,
the key column functions as the I<PRIMARY KEY> or UNIQUE INDEX.

In DBD::DBM, you can take advantage of the speed of keyed lookups by using
DBI::SQL::Nano and a WHERE clause with a single equal comparison on the key
field. For example, the following SQL statements are optimized for keyed
lookup:

 CREATE TABLE user ( user_name TEXT, phone TEXT);
 INSERT INTO user VALUES ('Fred Bloggs','233-7777');
 # ... many more inserts
 SELECT phone FROM user WHERE user_name='Fred Bloggs';

The "user_name" column is the key column since it is the first
column. The SELECT statement uses the key column in a single equal
comparison - "user_name='Fred Bloggs'" - so the search will find it
very quickly without having to loop through all the names which were
inserted into the table.

In contrast, these searches on the same table are not optimized:

 1. SELECT phone FROM user WHERE user_name < 'Fred';
 2. SELECT user_name FROM user WHERE phone = '233-7777';

In #1, the operation uses a less-than (<) comparison rather than an equals
comparison, so it will not be optimized for key searching.  In #2, the key
field "user_name" is not specified in the WHERE clause, and therefore the
search will need to loop through all rows to find the requested row(s).

B<Note> that the underlying DBM storage needs to loop over all I<key/value>
pairs when the optimized fetch is used. SQL::Statement has a massively
improved where clause evaluation which costs around 15% of the evaluation
in DBI::SQL::Nano - combined with the loop in the DBM storage the speed
improvement isn't so impressive.

Even if lookups are faster by around 50%, DBI::SQL::Nano and
SQL::Statement can benefit from the key field optimizations on
updating and deleting rows - and here the improved where clause
evaluation of SQL::Statement might beat DBI::SQL::Nano every time the
where clause contains not only the key field (or more than one).

=head2 Supported SQL syntax

DBD::DBM uses a subset of SQL.  The robustness of that subset depends on
what other modules you have installed. Both options support basic SQL
operations including CREATE TABLE, DROP TABLE, INSERT, DELETE, UPDATE, and
SELECT.

B<Option #1:> By default, this module inherits its SQL support from
DBI::SQL::Nano that comes with DBI.  Nano is, as its name implies, a *very*
small SQL engine.  Although limited in scope, it is faster than option #2
for some operations (especially single I<primary key> lookups). See
L<DBI::SQL::Nano> for a description of the SQL it supports and comparisons
of it with option #2.

B<Option #2:> If you install the pure Perl CPAN module SQL::Statement,
DBD::DBM will use it instead of Nano.  This adds support for table aliases,
functions, joins, and much more.  If you're going to use DBD::DBM
for anything other than very simple tables and queries, you should install
SQL::Statement.  You don't have to change DBD::DBM or your scripts in any
way, simply installing SQL::Statement will give you the more robust SQL
capabilities without breaking scripts written for DBI::SQL::Nano.  See
L<SQL::Statement> for a description of the SQL it supports.

To find out which SQL module is working in a given script, you can use the
dbm_versions() method or, if you don't need the full output and version
numbers, just do this:

 print $dbh->{sql_handler}, "\n";

That will print out either "SQL::Statement" or "DBI::SQL::Nano".

Baring the section about optimized access to the DBM storage in mind,
comparing the benefits of both engines:

  # DBI::SQL::Nano is faster
  $sth = $dbh->prepare( "update foo set value='new' where key=15" );
  $sth->execute();
  $sth = $dbh->prepare( "delete from foo where key=27" );
  $sth->execute();
  $sth = $dbh->prepare( "select * from foo where key='abc'" );

  # SQL::Statement might faster (depending on DB size)
  $sth = $dbh->prepare( "update foo set value='new' where key=?" );
  $sth->execute(15);
  $sth = $dbh->prepare( "update foo set value=? where key=15" );
  $sth->execute('new');
  $sth = $dbh->prepare( "delete from foo where key=?" );
  $sth->execute(27);

  # SQL::Statement is faster
  $sth = $dbh->prepare( "update foo set value='new' where value='old'" );
  $sth->execute();
  # must be expressed using "where key = 15 or key = 27 or key = 42 or key = 'abc'"
  # in DBI::SQL::Nano
  $sth = $dbh->prepare( "delete from foo where key in (15,27,42,'abc')" );
  $sth->execute();
  # must be expressed using "where key > 10 and key < 90" in DBI::SQL::Nano
  $sth = $dbh->prepare( "select * from foo where key between (10,90)" );
  $sth->execute();

  # only SQL::Statement can handle
  $sth->prepare( "select * from foo,bar where foo.name = bar.name" );
  $sth->execute();
  $sth->prepare( "insert into foo values ( 1, 'foo' ), ( 2, 'bar' )" );
  $sth->execute();

=head2 Specifying Column Names

DBM files don't have a standard way to store column names.   DBD::DBM gets
around this issue with a DBD::DBM specific way of storing the column names.
B<If you are working only with DBD::DBM and not using files created by or
accessed with other DBM programs, you can ignore this section.>

DBD::DBM stores column names as a row in the file with the key I<_metadata
\0>.  So this code

 my $dbh = DBI->connect('dbi:DBM:');
 $dbh->do("CREATE TABLE baz (foo CHAR(10), bar INTEGER)");
 $dbh->do("INSERT INTO baz (foo,bar) VALUES ('zippy',1)");

Will create a file that has a structure something like this:

  _metadata \0 | <dbd_metadata><schema></schema><col_names>foo,bar</col_names></dbd_metadata>
  zippy        | 1

The next time you access this table with DBD::DBM, it will treat the
I<_metadata \0> row as a header rather than as data and will pull the column
names from there.  However, if you access the file with something other
than DBD::DBM, the row will be treated as a regular data row.

If you do not want the column names stored as a data row in the table you
can set the I<dbm_store_metadata> attribute to 0.

 my $dbh = DBI->connect('dbi:DBM:', undef, undef, { dbm_store_metadata => 0 });

 # or
 $dbh->{dbm_store_metadata} = 0;

 # or for per-table setting
 $dbh->{f_meta}->{qux}->{dbm_store_metadata} = 0;

By default, DBD::DBM assumes that you have two columns named "k" and "v"
(short for "key" and "value").  So if you have I<dbm_store_metadata> set to
1 and you want to use alternate column names, you need to specify the
column names like this:

 my $dbh = DBI->connect('dbi:DBM:', undef, undef, {
     dbm_store_metadata => 0,
     dbm_cols => [ qw(foo bar) ],
 });

 # or
 $dbh->{dbm_store_metadata} = 0;
 $dbh->{dbm_cols}           = 'foo,bar';

 # or to set the column names on per-table basis, do this:
 # sets the column names only for table "qux"
 $dbh->{f_meta}->{qux}->{dbm_store_metadata} = 0;
 $dbh->{f_meta}->{qux}->{col_names}          = [qw(foo bar)];

If you have a file that was created by another DBM program or created with
I<dbm_store_metadata> set to zero and you want to convert it to using
DBD::DBM's column name storage, just use one of the methods above to name
the columns but *without* specifying I<dbm_store_metadata> as zero.  You
only have to do that once - thereafter you can get by without setting
either I<dbm_store_metadata> or setting I<dbm_cols> because the names will
be stored in the file.

=head1 DBI database handle attributes

=head2 Metadata

=head3 Statement handle ($sth) attributes and methods

Most statement handle attributes such as NAME, NUM_OF_FIELDS, etc. are
available only after an execute.  The same is true of $sth->rows which is
available after the execute but does I<not> require a fetch.

=head3 Driver handle ($dbh) attributes

It is not supported anymore to use dbm-attributes without the dbm_-prefix.
Currently, if an DBD::DBM private attribute is accessed without an
underscore in it's name, dbm_ is prepended to that attribute and it's
processed further. If the resulting attribute name is invalid, an error is
thrown.

=head4 dbm_cols

Contains a comma separated list of column names or an array reference to
the column names.

=head4 dbm_type

Contains the DBM storage type. Currently known supported type are
C<< ODBM_File >>, C<< NDBM_File >>, C<< SDBM_File >>, C<< GDBM_File >>,
C<< DB_File >> and C<< BerkeleyDB >>. It is not recommended to use one
of the first three types - even if C<< SDBM_File >> is the most commonly
available I<dbm_type>.

=head4 dbm_mldbm

Contains the serializer for DBM storage (value column). Requires the
CPAN module L<MLDBM> installed.  Currently known supported serializers
are:

=over 8

=item Data::Dumper

Default serializer. Deployed with Perl core.

=item Storable

Faster serializer. Deployed with Perl core.

=item FreezeThaw

Pure Perl serializer, requires L<FreezeThaw> to be installed.

=item YAML

Portable serializer (between languages but not architectures).
Requires L<YAML::MLDBM> installation.

=item JSON

Portable, fast serializer (between languages but not architectures).
Requires L<MLDBM::Serializer::JSON> installation.

=back

=head4 dbm_store_metadata

Boolean value which determines if the metadata in DBM is stored or not.

=head4 dbm_berkeley_flags

Hash reference with additional flags for BerkeleyDB::Hash instantiation.

=head4 dbm_version

Readonly attribute containing the version of DBD::DBM.

=head4 f_meta

In addition to the attributes L<DBD::File> recognizes, DBD::DBM knows
about the (public) attributes C<col_names> (B<Note> not I<dbm_cols>
here!), C<dbm_type>, C<dbm_mldbm>, C<dbm_store_metadata> and
C<dbm_berkeley_flags>.  As in DBD::File, there are undocumented,
internal attributes in DBD::DBM.  Be very careful when modifying
attributes you do not know; the consequence might a destroyed or
corrupted table.

=head4 dbm_tables

This attribute provides restricted access to the table meta data. See
L<f_meta> and L<DBD::File/f_meta> for attribute details.

dbm_tables is a tied hash providing the internal table names as keys
(accessing unknown tables might create an entry) and their meta
data as another tied hash. The table meta storage is obtained via
the C<get_table_meta> method from the table implementation (see
L<DBD::File::Developers>). Attribute setting and getting within the
table meta data is handled via the methods C<set_table_meta_attr> and
C<get_table_meta_attr>.

=head3 Following attributes are no longer handled by DBD::DBM:

=head4 dbm_ext

This attribute is silently mapped to DBD::File's attribute I<f_ext>.
Later versions of DBI might show a depreciated warning when this attribute
is used and eventually it will be removed.

=head4 dbm_lockfile

This attribute is silently mapped to DBD::File's attribute I<f_lockfile>.
Later versions of DBI might show a depreciated warning when this attribute
is used and eventually it will be removed.

=head1 DBI database handle methods

=head2 The $dbh->dbm_versions() method

The private method dbm_versions() returns a summary of what other modules
are being used at any given time.  DBD::DBM can work with or without many
other modules - it can use either SQL::Statement or DBI::SQL::Nano as its
SQL engine, it can be run with DBI or DBI::PurePerl, it can use many kinds
of DBM modules, and many kinds of serializers when run with MLDBM.  The
dbm_versions() method reports all of that and more.

  print $dbh->dbm_versions;               # displays global settings
  print $dbh->dbm_versions($table_name);  # displays per table settings

An important thing to note about this method is that when it called
with no arguments, it displays the *global* settings.  If you override
these by setting per-table attributes, these will I<not> be shown
unless you specify a table name as an argument to the method call.

=head2 Storing Objects

If you are using MLDBM, you can use DBD::DBM to take advantage of its
serializing abilities to serialize any Perl object that MLDBM can handle.
To store objects in columns, you should (but don't absolutely need to)
declare it as a column of type BLOB (the type is *currently* ignored by
the SQL engine, but it's good form).

=head1 EXTENSIBILITY

=over 8

=item C<SQL::Statement>

Improved SQL engine compared to the built-in DBI::SQL::Nano - see
L<Supported SQL syntax>.

=item C<DB_File>

Berkeley DB version 1. This database library is available on many
systems without additional installation and most systems are
supported.

=item C<GDBM_File>

Simple dbm type (comparable to C<DB_File>) under the GNU license.
Typically not available (or requires extra installation) on non-GNU
operating systems.

=item C<BerkeleyDB>

Berkeley DB version up to v4 (and maybe higher) - requires additional
installation but is easier than GDBM_File on non-GNU systems.

db4 comes with a many tools which allow repairing and migrating
databases.  This is the B<recommended> dbm type for production use.

=item C<MLDBM>

Serializer wrapper to support more than one column for the files.
Comes with serializers using C<Data::Dumper>, C<FreezeThaw> and
C<Storable>.

=item C<YAML::MLDBM>

Additional serializer for MLDBM. YAML is very portable between languages.

=item C<MLDBM::Serializer::JSON>

Additional serializer for MLDBM. JSON is very portable between languages,
probably more than YAML.

=back

=head1 GOTCHAS AND WARNINGS

Using the SQL DROP command will remove any file that has the name specified
in the command with either '.pag' and '.dir', '.db' or your {f_ext} appended
to it.  So this be dangerous if you aren't sure what file it refers to:

 $dbh->do(qq{DROP TABLE "/path/to/any/file"});

Each DBM type has limitations.  SDBM_File, for example, can only store
values of less than 1,000 characters.  *You* as the script author must
ensure that you don't exceed those bounds.  If you try to insert a value
that is larger than DBM can store, the results will be unpredictable.
See the documentation for whatever DBM you are using for details.

Different DBM implementations return records in different orders.
That means that you I<should not> rely on the order of records unless
you use an ORDER BY statement.

DBM data files are platform-specific.  To move them from one platform to
another, you'll need to do something along the lines of dumping your data
to CSV on platform #1 and then dumping from CSV to DBM on platform #2.
DBD::AnyData and DBD::CSV can help with that.  There may also be DBM
conversion tools for your platforms which would probably be quicker.

When using MLDBM, there is a very powerful serializer - it will allow
you to store Perl code or objects in database columns.  When these get
de-serialized, they may be eval'ed - in other words MLDBM (or actually
Data::Dumper when used by MLDBM) may take the values and try to
execute them in Perl.  Obviously, this can present dangers, so if you
do not know what is in a file, be careful before you access it with
MLDBM turned on!

See the entire section on L<Table locking and flock()> for gotchas and
warnings about the use of flock().

=head1 BUGS AND LIMITATIONS

This module uses hash interfaces of two column file databases. While
none of supported SQL engines have support for indices, the following
statements really do the same (even if they mean something completely
different) for each dbm type which lacks C<EXISTS> support:

  $sth->do( "insert into foo values (1, 'hello')" );

  # this statement does ...
  $sth->do( "update foo set v='world' where k=1" );
  # ... the same as this statement
  $sth->do( "insert into foo values (1, 'world')" );

This is considered to be a bug and might change in a future release.

Known affected dbm types are C<ODBM_File> and C<NDBM_File>. We highly
recommended you use a more modern dbm type such as C<DB_File>.

=head1 GETTING HELP, MAKING SUGGESTIONS, AND REPORTING BUGS

If you need help installing or using DBD::DBM, please write to the DBI
users mailing list at dbi-users@perl.org or to the
comp.lang.perl.modules newsgroup on usenet.  I cannot always answer
every question quickly but there are many on the mailing list or in
the newsgroup who can.

DBD developers for DBD's which rely on DBD::File or DBD::DBM or use
one of them as an example are suggested to join the DBI developers
mailing list at dbi-dev@perl.org and strongly encouraged to join our
IRC channel at L<irc://irc.perl.org/dbi>.

If you have suggestions, ideas for improvements, or bugs to report, please
report a bug as described in DBI. Do not mail any of the authors directly,
you might not get an answer.

When reporting bugs, please send the output of $dbh->dbm_versions($table)
for a table that exhibits the bug and as small a sample as you can make of
the code that produces the bug.  And of course, patches are welcome, too
:-).

If you need enhancements quickly, you can get commercial support as
described at L<http://dbi.perl.org/support/> or you can contact Jens Rehsack
at rehsack@cpan.org for commercial support in Germany.

Please don't bother Jochen Wiedmann or Jeff Zucker for support - they
handed over further maintenance to H.Merijn Brand and Jens Rehsack.

=head1 ACKNOWLEDGEMENTS

Many, many thanks to Tim Bunce for prodding me to write this, and for
copious, wise, and patient suggestions all along the way. (Jeff Zucker)

I send my thanks and acknowledgements to H.Merijn Brand for his
initial refactoring of DBD::File and his strong and ongoing support of
SQL::Statement. Without him, the current progress would never have
been made.  And I have to name Martin J. Evans for each laugh (and
correction) of all those funny word creations I (as non-native
speaker) made to the documentation. And - of course - I have to thank
all those unnamed contributors and testers from the Perl
community. (Jens Rehsack)

=head1 AUTHOR AND COPYRIGHT

This module is written by Jeff Zucker < jzucker AT cpan.org >, who also
maintained it till 2007. After that, in 2010, Jens Rehsack & H.Merijn Brand
took over maintenance.

 Copyright (c) 2004 by Jeff Zucker, all rights reserved.
 Copyright (c) 2010-2013 by Jens Rehsack & H.Merijn Brand, all rights reserved.

You may freely distribute and/or modify this module under the terms of
either the GNU General Public License (GPL) or the Artistic License, as
specified in the Perl README file.

=head1 SEE ALSO

L<DBI>,
L<SQL::Statement>, L<DBI::SQL::Nano>,
L<AnyDBM_File>, L<DB_File>, L<BerkeleyDB>,
L<MLDBM>, L<YAML::MLDBM>, L<MLDBM::Serializer::JSON>

=cut
