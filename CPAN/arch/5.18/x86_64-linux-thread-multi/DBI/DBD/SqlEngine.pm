# -*- perl -*-
#
#   DBI::DBD::SqlEngine - A base class for implementing DBI drivers that
#               have not an own SQL engine
#
#  This module is currently maintained by
#
#      H.Merijn Brand & Jens Rehsack
#
#  The original author is Jochen Wiedmann.
#
#  Copyright (C) 2009-2013 by H.Merijn Brand & Jens Rehsack
#  Copyright (C) 2004 by Jeff Zucker
#  Copyright (C) 1998 by Jochen Wiedmann
#
#  All rights reserved.
#
#  You may distribute this module under the terms of either the GNU
#  General Public License or the Artistic License, as specified in
#  the Perl README file.

require 5.008;

use strict;

use DBI ();
require DBI::SQL::Nano;

package DBI::DBD::SqlEngine;

use strict;

use Carp;
use vars qw( @ISA $VERSION $drh %methods_installed);

$VERSION = "0.06";

$drh = undef;    # holds driver handle(s) once initialized

DBI->setup_driver("DBI::DBD::SqlEngine");    # only needed once but harmless to repeat

my %accessors = (
                  versions   => "get_driver_versions",
                  get_meta   => "get_sql_engine_meta",
                  set_meta   => "set_sql_engine_meta",
                  clear_meta => "clear_sql_engine_meta",
                );

sub driver ($;$)
{
    my ( $class, $attr ) = @_;

    # Drivers typically use a singleton object for the $drh
    # We use a hash here to have one singleton per subclass.
    # (Otherwise DBD::CSV and DBD::DBM, for example, would
    # share the same driver object which would cause problems.)
    # An alternative would be to not cache the $drh here at all
    # and require that subclasses do that. Subclasses should do
    # their own caching, so caching here just provides extra safety.
    $drh->{$class} and return $drh->{$class};

    $attr ||= {};
    {
        no strict "refs";
        unless ( $attr->{Attribution} )
        {
            $class eq "DBI::DBD::SqlEngine"
              and $attr->{Attribution} = "$class by Jens Rehsack";
            $attr->{Attribution} ||= ${ $class . "::ATTRIBUTION" }
              || "oops the author of $class forgot to define this";
        }
        $attr->{Version} ||= ${ $class . "::VERSION" };
        $attr->{Name} or ( $attr->{Name} = $class ) =~ s/^DBD\:\://;
    }

    $drh->{$class} = DBI::_new_drh( $class . "::dr", $attr );
    $drh->{$class}->STORE( ShowErrorStatement => 1 );

    my $prefix = DBI->driver_prefix($class);
    if ($prefix)
    {
        my $dbclass = $class . "::db";
        while ( my ( $accessor, $funcname ) = each %accessors )
        {
            my $method = $prefix . $accessor;
            $dbclass->can($method) and next;
            my $inject = sprintf <<'EOI', $dbclass, $method, $dbclass, $funcname;
sub %s::%s
{
    my $func = %s->can (q{%s});
    goto &$func;
    }
EOI
            eval $inject;
            $dbclass->install_method($method);
        }
    }

    # XXX inject DBD::XXX::Statement unless exists

    my $stclass = $class . "::st";
    $stclass->install_method("sql_get_colnames") unless ( $methods_installed{__PACKAGE__}++ );

    return $drh->{$class};
}    # driver

sub CLONE
{
    undef $drh;
}    # CLONE

# ====== DRIVER ================================================================

package DBI::DBD::SqlEngine::dr;

use strict;
use warnings;

use vars qw(@ISA $imp_data_size);

use Carp qw/carp/;

$imp_data_size = 0;

sub connect ($$;$$$)
{
    my ( $drh, $dbname, $user, $auth, $attr ) = @_;

    # create a 'blank' dbh
    my $dbh = DBI::_new_dbh(
                             $drh,
                             {
                                Name         => $dbname,
                                USER         => $user,
                                CURRENT_USER => $user,
                             }
                           );

    if ($dbh)
    {
        # must be done first, because setting flags implicitly calls $dbdname::db->STORE
        $dbh->func( 0, "init_default_attributes" );
        my $two_phased_init;
        defined $dbh->{sql_init_phase} and $two_phased_init = ++$dbh->{sql_init_phase};
        my %second_phase_attrs;
        my @func_inits;

        # this must be done to allow DBI.pm reblessing got handle after successful connecting
        exists $attr->{RootClass} and $second_phase_attrs{RootClass} = delete $attr->{RootClass};

        my ( $var, $val );
        while ( length $dbname )
        {
            if ( $dbname =~ s/^((?:[^\\;]|\\.)*?);//s )
            {
                $var = $1;
            }
            else
            {
                $var    = $dbname;
                $dbname = "";
            }

            if ( $var =~ m/^(.+?)=(.*)/s )
            {
                $var = $1;
                ( $val = $2 ) =~ s/\\(.)/$1/g;
                exists $attr->{$var}
                  and carp("$var is given in DSN *and* \$attr during DBI->connect()")
                  if ($^W);
                exists $attr->{$var} or $attr->{$var} = $val;
            }
            elsif ( $var =~ m/^(.+?)=>(.*)/s )
            {
                $var = $1;
                ( $val = $2 ) =~ s/\\(.)/$1/g;
                my $ref = eval $val;
                # $dbh->$var($ref);
                push( @func_inits, $var, $ref );
            }
        }

        # The attributes need to be sorted in a specific way as the
        # assignment is through tied hashes and calls STORE on each
        # attribute.  Some attributes require to be called prior to
        # others
        # e.g. f_dir *must* be done before xx_tables in DBD::File
        # The dbh attribute sql_init_order is a hash with the order
        # as key (low is first, 0 .. 100) and the attributes that
        # are set to that oreder as anon-list as value:
        # {  0 => [qw( AutoCommit PrintError RaiseError Profile ... )],
        #   10 => [ list of attr to be dealt with immediately after first ],
        #   50 => [ all fields that are unspecified or default sort order ],
        #   90 => [ all fields that are needed after other initialisation ],
        #   }

        my %order = map {
            my $order = $_;
            map { ( $_ => $order ) } @{ $dbh->{sql_init_order}{$order} };
        } sort { $a <=> $b } keys %{ $dbh->{sql_init_order} || {} };
        my @ordered_attr =
          map  { $_->[0] }
          sort { $a->[1] <=> $b->[1] }
          map  { [ $_, defined $order{$_} ? $order{$_} : 50 ] }
          keys %$attr;

        # initialize given attributes ... lower weighted before higher weighted
        foreach my $a (@ordered_attr)
        {
            exists $attr->{$a} or next;
            $two_phased_init and eval {
                $dbh->{$a} = $attr->{$a};
                delete $attr->{$a};
            };
            $@ and $second_phase_attrs{$a} = delete $attr->{$a};
            $two_phased_init or $dbh->STORE( $a, delete $attr->{$a} );
        }

        $two_phased_init and $dbh->func( 1, "init_default_attributes" );
        %$attr = %second_phase_attrs;

        for ( my $i = 0; $i < scalar(@func_inits); $i += 2 )
        {
            my $func = $func_inits[$i];
            my $arg  = $func_inits[ $i + 1 ];
            $dbh->$func($arg);
        }

        $dbh->func("init_done");

        $dbh->STORE( Active => 1 );
    }

    return $dbh;
}    # connect

sub data_sources ($;$)
{
    my ( $drh, $attr ) = @_;

    my $tbl_src;
    $attr
      and defined $attr->{sql_table_source}
      and $attr->{sql_table_source}->isa('DBI::DBD::SqlEngine::TableSource')
      and $tbl_src = $attr->{sql_table_source};

    !defined($tbl_src)
      and $drh->{ImplementorClass}->can('default_table_source')
      and $tbl_src = $drh->{ImplementorClass}->default_table_source();
    defined($tbl_src) or return;

    $tbl_src->data_sources( $drh, $attr );
}    # data_sources

sub disconnect_all
{
}    # disconnect_all

sub DESTROY
{
    undef;
}    # DESTROY

# ====== DATABASE ==============================================================

package DBI::DBD::SqlEngine::db;

use strict;
use warnings;

use vars qw(@ISA $imp_data_size);

use Carp;

if ( eval { require Clone; } )
{
    Clone->import("clone");
}
else
{
    require Storable;    # in CORE since 5.7.3
    *clone = \&Storable::dclone;
}

$imp_data_size = 0;

sub ping
{
    ( $_[0]->FETCH("Active") ) ? 1 : 0;
}    # ping

sub data_sources
{
    my ( $dbh, $attr, @other ) = @_;
    my $drh = $dbh->{Driver};    # XXX proxy issues?
    ref($attr) eq 'HASH' or $attr = {};
    defined( $attr->{sql_table_source} ) or $attr->{sql_table_source} = $dbh->{sql_table_source};
    return $drh->data_sources( $attr, @other );
}

sub prepare ($$;@)
{
    my ( $dbh, $statement, @attribs ) = @_;

    # create a 'blank' sth
    my $sth = DBI::_new_sth( $dbh, { Statement => $statement } );

    if ($sth)
    {
        my $class = $sth->FETCH("ImplementorClass");
        $class =~ s/::st$/::Statement/;
        my $stmt;

        # if using SQL::Statement version > 1
        # cache the parser object if the DBD supports parser caching
        # SQL::Nano and older SQL::Statements don't support this

        if ( $class->isa("SQL::Statement") )
        {
            my $parser = $dbh->{sql_parser_object};
            $parser ||= eval { $dbh->func("sql_parser_object") };
            if ($@)
            {
                $stmt = eval { $class->new($statement) };
            }
            else
            {
                $stmt = eval { $class->new( $statement, $parser ) };
            }
        }
        else
        {
            $stmt = eval { $class->new($statement) };
        }
        if ( $@ || $stmt->{errstr} )
        {
            $dbh->set_err( $DBI::stderr, $@ || $stmt->{errstr} );
            undef $sth;
        }
        else
        {
            $sth->STORE( "sql_stmt", $stmt );
            $sth->STORE( "sql_params", [] );
            $sth->STORE( "NUM_OF_PARAMS", scalar( $stmt->params() ) );
            my @colnames = $sth->sql_get_colnames();
            $sth->STORE( "NUM_OF_FIELDS", scalar @colnames );
        }
    }
    return $sth;
}    # prepare

sub set_versions
{
    my $dbh = $_[0];
    $dbh->{sql_engine_version} = $DBI::DBD::SqlEngine::VERSION;
    for (qw( nano_version statement_version ))
    {
        defined $DBI::SQL::Nano::versions->{$_} or next;
        $dbh->{"sql_$_"} = $DBI::SQL::Nano::versions->{$_};
    }
    $dbh->{sql_handler} =
      $dbh->{sql_statement_version}
      ? "SQL::Statement"
      : "DBI::SQL::Nano";

    return $dbh;
}    # set_versions

sub init_valid_attributes
{
    my $dbh = $_[0];

    $dbh->{sql_valid_attrs} = {
                             sql_engine_version         => 1,    # DBI::DBD::SqlEngine version
                             sql_handler                => 1,    # Nano or S:S
                             sql_nano_version           => 1,    # Nano version
                             sql_statement_version      => 1,    # S:S version
                             sql_flags                  => 1,    # flags for SQL::Parser
                             sql_dialect                => 1,    # dialect for SQL::Parser
                             sql_quoted_identifier_case => 1,    # case for quoted identifiers
                             sql_identifier_case        => 1,    # case for non-quoted identifiers
                             sql_parser_object          => 1,    # SQL::Parser instance
                             sql_sponge_driver          => 1,    # Sponge driver for table_info ()
                             sql_valid_attrs            => 1,    # SQL valid attributes
                             sql_readonly_attrs         => 1,    # SQL readonly attributes
                             sql_init_phase             => 1,    # Only during initialization
                             sql_meta                   => 1,    # meta data for tables
                             sql_meta_map               => 1,    # mapping table for identifier case
                              };
    $dbh->{sql_readonly_attrs} = {
                               sql_engine_version         => 1,    # DBI::DBD::SqlEngine version
                               sql_handler                => 1,    # Nano or S:S
                               sql_nano_version           => 1,    # Nano version
                               sql_statement_version      => 1,    # S:S version
                               sql_quoted_identifier_case => 1,    # case for quoted identifiers
                               sql_parser_object          => 1,    # SQL::Parser instance
                               sql_sponge_driver          => 1,    # Sponge driver for table_info ()
                               sql_valid_attrs            => 1,    # SQL valid attributes
                               sql_readonly_attrs         => 1,    # SQL readonly attributes
                                 };

    return $dbh;
}    # init_valid_attributes

sub init_default_attributes
{
    my ( $dbh, $phase ) = @_;
    my $given_phase = $phase;

    unless ( defined($phase) )
    {
        # we have an "old" driver here
        $phase = defined $dbh->{sql_init_phase};
        $phase and $phase = $dbh->{sql_init_phase};
    }

    if ( 0 == $phase )
    {
        # must be done first, because setting flags implicitly calls $dbdname::db->STORE
        $dbh->func("init_valid_attributes");

        $dbh->func("set_versions");

        $dbh->{sql_identifier_case}        = 2;    # SQL_IC_LOWER
        $dbh->{sql_quoted_identifier_case} = 3;    # SQL_IC_SENSITIVE

        $dbh->{sql_dialect} = "CSV";

        $dbh->{sql_init_phase} = $given_phase;

        # complete derived attributes, if required
        ( my $drv_class = $dbh->{ImplementorClass} ) =~ s/::db$//;
        my $drv_prefix  = DBI->driver_prefix($drv_class);
        my $valid_attrs = $drv_prefix . "valid_attrs";
        my $ro_attrs    = $drv_prefix . "readonly_attrs";

        # check whether we're running in a Gofer server or not (see
        # validate_FETCH_attr for details)
        $dbh->{sql_engine_in_gofer} =
          ( defined $INC{"DBD/Gofer.pm"} && ( caller(5) )[0] eq "DBI::Gofer::Execute" );
        $dbh->{sql_meta}     = {};
        $dbh->{sql_meta_map} = {};    # choose new name because it contains other keys

        # init_default_attributes calls inherited routine before derived DBD's
        # init their default attributes, so we don't override something here
        #
        # defining an order of attribute initialization from connect time
        # specified ones with a magic baarier (see next statement)
        my $drv_pfx_meta = $drv_prefix . "meta";
        $dbh->{sql_init_order} = {
                           0  => [qw( Profile RaiseError PrintError AutoCommit )],
                           90 => [ "sql_meta", $dbh->{$drv_pfx_meta} ? $dbh->{$drv_pfx_meta} : () ],
        };
        # ensuring Profile, RaiseError, PrintError, AutoCommit are initialized
        # first when initializing attributes from connect time specified
        # attributes
        # further, initializations to predefined tables are happens after any
        # unspecified attribute initialization (that default to order 50)

        my @comp_attrs = qw(valid_attrs version readonly_attrs);

        if ( exists $dbh->{$drv_pfx_meta} and !$dbh->{sql_engine_in_gofer} )
        {
            my $attr = $dbh->{$drv_pfx_meta};
                  defined $attr
              and defined $dbh->{$valid_attrs}
              and !defined $dbh->{$valid_attrs}{$attr}
              and $dbh->{$valid_attrs}{$attr} = 1;

            my %h;
            tie %h, "DBI::DBD::SqlEngine::TieTables", $dbh;
            $dbh->{$attr} = \%h;

            push @comp_attrs, "meta";
        }

        foreach my $comp_attr (@comp_attrs)
        {
            my $attr = $drv_prefix . $comp_attr;
            defined $dbh->{$valid_attrs}
              and !defined $dbh->{$valid_attrs}{$attr}
              and $dbh->{$valid_attrs}{$attr} = 1;
            defined $dbh->{$ro_attrs}
              and !defined $dbh->{$ro_attrs}{$attr}
              and $dbh->{$ro_attrs}{$attr} = 1;
        }
    }

    return $dbh;
}    # init_default_attributes

sub init_done
{
    defined $_[0]->{sql_init_phase} and delete $_[0]->{sql_init_phase};
    delete $_[0]->{sql_valid_attrs}->{sql_init_phase};
    return;
}

sub sql_parser_object
{
    my $dbh = $_[0];
    my $dialect = $dbh->{sql_dialect} || "CSV";
    my $parser = {
                   RaiseError => $dbh->FETCH("RaiseError"),
                   PrintError => $dbh->FETCH("PrintError"),
                 };
    my $sql_flags = $dbh->FETCH("sql_flags") || {};
    %$parser = ( %$parser, %$sql_flags );
    $parser = SQL::Parser->new( $dialect, $parser );
    $dbh->{sql_parser_object} = $parser;
    return $parser;
}    # sql_parser_object

sub sql_sponge_driver
{
    my $dbh  = $_[0];
    my $dbh2 = $dbh->{sql_sponge_driver};
    unless ($dbh2)
    {
        $dbh2 = $dbh->{sql_sponge_driver} = DBI->connect("DBI:Sponge:");
        unless ($dbh2)
        {
            $dbh->set_err( $DBI::stderr, $DBI::errstr );
            return;
        }
    }
}

sub disconnect ($)
{
    %{ $_[0]->{sql_meta} }     = ();
    %{ $_[0]->{sql_meta_map} } = ();
    $_[0]->STORE( Active => 0 );
    return 1;
}    # disconnect

sub validate_FETCH_attr
{
    my ( $dbh, $attrib ) = @_;

    # If running in a Gofer server, access to our tied compatibility hash
    # would force Gofer to serialize the tieing object including it's
    # private $dbh reference used to do the driver function calls.
    # This will result in nasty exceptions. So return a copy of the
    # sql_meta structure instead, which is the source of for the compatibility
    # tie-hash. It's not as good as liked, but the best we can do in this
    # situation.
    if ( $dbh->{sql_engine_in_gofer} )
    {
        ( my $drv_class = $dbh->{ImplementorClass} ) =~ s/::db$//;
        my $drv_prefix = DBI->driver_prefix($drv_class);
        exists $dbh->{ $drv_prefix . "meta" } && $attrib eq $dbh->{ $drv_prefix . "meta" }
          and $attrib = "sql_meta";
    }

    return $attrib;
}

sub FETCH ($$)
{
    my ( $dbh, $attrib ) = @_;
    $attrib eq "AutoCommit"
      and return 1;

    # Driver private attributes are lower cased
    if ( $attrib eq ( lc $attrib ) )
    {
        # first let the implementation deliver an alias for the attribute to fetch
        # after it validates the legitimation of the fetch request
        $attrib = $dbh->func( $attrib, "validate_FETCH_attr" ) or return;

        my $attr_prefix;
        $attrib =~ m/^([a-z]+_)/ and $attr_prefix = $1;
        unless ($attr_prefix)
        {
            ( my $drv_class = $dbh->{ImplementorClass} ) =~ s/::db$//;
            $attr_prefix = DBI->driver_prefix($drv_class);
            $attrib      = $attr_prefix . $attrib;
        }
        my $valid_attrs = $attr_prefix . "valid_attrs";
        my $ro_attrs    = $attr_prefix . "readonly_attrs";

        exists $dbh->{$valid_attrs}
          and ( $dbh->{$valid_attrs}{$attrib}
                or return $dbh->set_err( $DBI::stderr, "Invalid attribute '$attrib'" ) );
        exists $dbh->{$ro_attrs}
          and $dbh->{$ro_attrs}{$attrib}
          and defined $dbh->{$attrib}
          and refaddr( $dbh->{$attrib} )
          and return clone( $dbh->{$attrib} );

        return $dbh->{$attrib};
    }
    # else pass up to DBI to handle
    return $dbh->SUPER::FETCH($attrib);
}    # FETCH

sub validate_STORE_attr
{
    my ( $dbh, $attrib, $value ) = @_;

    if (     $attrib eq "sql_identifier_case" || $attrib eq "sql_quoted_identifier_case"
         and $value < 1 || $value > 4 )
    {
        croak "attribute '$attrib' must have a value from 1 .. 4 (SQL_IC_UPPER .. SQL_IC_MIXED)";
        # XXX correctly a remap of all entries in sql_meta/sql_meta_map is required here
    }

    ( my $drv_class = $dbh->{ImplementorClass} ) =~ s/::db$//;
    my $drv_prefix = DBI->driver_prefix($drv_class);

    exists $dbh->{ $drv_prefix . "meta" }
      and $attrib eq $dbh->{ $drv_prefix . "meta" }
      and $attrib = "sql_meta";

    return ( $attrib, $value );
}

# the ::db::STORE method is what gets called when you set
# a lower-cased database handle attribute such as $dbh->{somekey}=$someval;
#
# STORE should check to make sure that "somekey" is a valid attribute name
# but only if it is really one of our attributes (starts with dbm_ or foo_)
# You can also check for valid values for the attributes if needed
# and/or perform other operations
#
sub STORE ($$$)
{
    my ( $dbh, $attrib, $value ) = @_;

    if ( $attrib eq "AutoCommit" )
    {
        $value and return 1;    # is already set
        croak "Can't disable AutoCommit";
    }

    if ( $attrib eq lc $attrib )
    {
        # Driver private attributes are lower cased

        ( $attrib, $value ) = $dbh->func( $attrib, $value, "validate_STORE_attr" );
        $attrib or return;

        my $attr_prefix;
        $attrib =~ m/^([a-z]+_)/ and $attr_prefix = $1;
        unless ($attr_prefix)
        {
            ( my $drv_class = $dbh->{ImplementorClass} ) =~ s/::db$//;
            $attr_prefix = DBI->driver_prefix($drv_class);
            $attrib      = $attr_prefix . $attrib;
        }
        my $valid_attrs = $attr_prefix . "valid_attrs";
        my $ro_attrs    = $attr_prefix . "readonly_attrs";

        exists $dbh->{$valid_attrs}
          and ( $dbh->{$valid_attrs}{$attrib}
                or return $dbh->set_err( $DBI::stderr, "Invalid attribute '$attrib'" ) );
        exists $dbh->{$ro_attrs}
          and $dbh->{$ro_attrs}{$attrib}
          and defined $dbh->{$attrib}
          and return $dbh->set_err( $DBI::stderr,
                                    "attribute '$attrib' is readonly and must not be modified" );

        if ( $attrib eq "sql_meta" )
        {
            while ( my ( $k, $v ) = each %$value )
            {
                $dbh->{$attrib}{$k} = $v;
            }
        }
        else
        {
            $dbh->{$attrib} = $value;
        }

        return 1;
    }

    return $dbh->SUPER::STORE( $attrib, $value );
}    # STORE

sub get_driver_versions
{
    my ( $dbh, $table ) = @_;
    my %vsn = (
                OS   => "$^O ($Config::Config{osvers})",
                Perl => "$] ($Config::Config{archname})",
                DBI  => $DBI::VERSION,
              );
    my %vmp;

    my $sql_engine_verinfo =
      join " ",
      $dbh->{sql_engine_version}, "using", $dbh->{sql_handler},
      $dbh->{sql_handler} eq "SQL::Statement"
      ? $dbh->{sql_statement_version}
      : $dbh->{sql_nano_version};

    my $indent   = 0;
    my @deriveds = ( $dbh->{ImplementorClass} );
    while (@deriveds)
    {
        my $derived = shift @deriveds;
        $derived eq "DBI::DBD::SqlEngine::db" and last;
        $derived->isa("DBI::DBD::SqlEngine::db") or next;
        #no strict 'refs';
        eval "push \@deriveds, \@${derived}::ISA";
        #use strict;
        ( my $drv_class = $derived ) =~ s/::db$//;
        my $drv_prefix  = DBI->driver_prefix($drv_class);
        my $ddgv        = $dbh->{ImplementorClass}->can("get_${drv_prefix}versions");
        my $drv_version = $ddgv ? &$ddgv( $dbh, $table ) : $dbh->{ $drv_prefix . "version" };
        $drv_version ||=
          eval { $derived->VERSION() };    # XXX access $drv_class::VERSION via symbol table
        $vsn{$drv_class} = $drv_version;
        $indent and $vmp{$drv_class} = " " x $indent . $drv_class;
        $indent += 2;
    }

    $vsn{"DBI::DBD::SqlEngine"} = $sql_engine_verinfo;
    $indent and $vmp{"DBI::DBD::SqlEngine"} = " " x $indent . "DBI::DBD::SqlEngine";

    $DBI::PurePerl and $vsn{"DBI::PurePerl"} = $DBI::PurePerl::VERSION;

    $indent += 20;
    my @versions = map { sprintf "%-${indent}s %s", $vmp{$_} || $_, $vsn{$_} }
      sort {
        $a->isa($b)                    and return -1;
        $b->isa($a)                    and return 1;
        $a->isa("DBI::DBD::SqlEngine") and return -1;
        $b->isa("DBI::DBD::SqlEngine") and return 1;
        return $a cmp $b;
      } keys %vsn;

    return wantarray ? @versions : join "\n", @versions;
}    # get_versions

sub get_single_table_meta
{
    my ( $dbh, $table, $attr ) = @_;
    my $meta;

    $table eq "."
      and return $dbh->FETCH($attr);

    ( my $class = $dbh->{ImplementorClass} ) =~ s/::db$/::Table/;
    ( undef, $meta ) = $class->get_table_meta( $dbh, $table, 1 );
    $meta or croak "No such table '$table'";

    # prevent creation of undef attributes
    return $class->get_table_meta_attr( $meta, $attr );
}    # get_single_table_meta

sub get_sql_engine_meta
{
    my ( $dbh, $table, $attr ) = @_;

    my $gstm = $dbh->{ImplementorClass}->can("get_single_table_meta");

    $table eq "*"
      and $table = [ ".", keys %{ $dbh->{sql_meta} } ];
    $table eq "+"
      and $table = [ grep { m/^[_A-Za-z0-9]+$/ } keys %{ $dbh->{sql_meta} } ];
    ref $table eq "Regexp"
      and $table = [ grep { $_ =~ $table } keys %{ $dbh->{sql_meta} } ];

    ref $table || ref $attr
      or return &$gstm( $dbh, $table, $attr );

    ref $table or $table = [$table];
    ref $attr  or $attr  = [$attr];
    "ARRAY" eq ref $table
      or return
      $dbh->set_err( $DBI::stderr,
          "Invalid argument for \$table - SCALAR, Regexp or ARRAY expected but got " . ref $table );
    "ARRAY" eq ref $attr
      or return $dbh->set_err(
                    "Invalid argument for \$attr - SCALAR or ARRAY expected but got " . ref $attr );

    my %results;
    foreach my $tname ( @{$table} )
    {
        my %tattrs;
        foreach my $aname ( @{$attr} )
        {
            $tattrs{$aname} = &$gstm( $dbh, $tname, $aname );
        }
        $results{$tname} = \%tattrs;
    }

    return \%results;
}    # get_sql_engine_meta

sub set_single_table_meta
{
    my ( $dbh, $table, $attr, $value ) = @_;
    my $meta;

    $table eq "."
      and return $dbh->STORE( $attr, $value );

    ( my $class = $dbh->{ImplementorClass} ) =~ s/::db$/::Table/;
    ( undef, $meta ) = $class->get_table_meta( $dbh, $table, 1 );
    $meta or croak "No such table '$table'";
    $class->set_table_meta_attr( $meta, $attr, $value );

    return $dbh;
}    # set_single_table_meta

sub set_sql_engine_meta
{
    my ( $dbh, $table, $attr, $value ) = @_;

    my $sstm = $dbh->{ImplementorClass}->can("set_single_table_meta");

    $table eq "*"
      and $table = [ ".", keys %{ $dbh->{sql_meta} } ];
    $table eq "+"
      and $table = [ grep { m/^[_A-Za-z0-9]+$/ } keys %{ $dbh->{sql_meta} } ];
    ref($table) eq "Regexp"
      and $table = [ grep { $_ =~ $table } keys %{ $dbh->{sql_meta} } ];

    ref $table || ref $attr
      or return &$sstm( $dbh, $table, $attr, $value );

    ref $table or $table = [$table];
    ref $attr or $attr = { $attr => $value };
    "ARRAY" eq ref $table
      or croak "Invalid argument for \$table - SCALAR, Regexp or ARRAY expected but got "
      . ref $table;
    "HASH" eq ref $attr
      or croak "Invalid argument for \$attr - SCALAR or HASH expected but got " . ref $attr;

    foreach my $tname ( @{$table} )
    {
        my %tattrs;
        while ( my ( $aname, $aval ) = each %$attr )
        {
            &$sstm( $dbh, $tname, $aname, $aval );
        }
    }

    return $dbh;
}    # set_file_meta

sub clear_sql_engine_meta
{
    my ( $dbh, $table ) = @_;

    ( my $class = $dbh->{ImplementorClass} ) =~ s/::db$/::Table/;
    my ( undef, $meta ) = $class->get_table_meta( $dbh, $table, 1 );
    $meta and %{$meta} = ();

    return;
}    # clear_file_meta

sub DESTROY ($)
{
    my $dbh = shift;
    $dbh->SUPER::FETCH("Active") and $dbh->disconnect;
    undef $dbh->{sql_parser_object};
}    # DESTROY

sub type_info_all ($)
{
    [
       {
          TYPE_NAME          => 0,
          DATA_TYPE          => 1,
          PRECISION          => 2,
          LITERAL_PREFIX     => 3,
          LITERAL_SUFFIX     => 4,
          CREATE_PARAMS      => 5,
          NULLABLE           => 6,
          CASE_SENSITIVE     => 7,
          SEARCHABLE         => 8,
          UNSIGNED_ATTRIBUTE => 9,
          MONEY              => 10,
          AUTO_INCREMENT     => 11,
          LOCAL_TYPE_NAME    => 12,
          MINIMUM_SCALE      => 13,
          MAXIMUM_SCALE      => 14,
       },
       [
          "VARCHAR", DBI::SQL_VARCHAR(), undef, "'", "'", undef, 0, 1, 1, 0, 0, 0, undef, 1, 999999,
       ],
       [ "CHAR", DBI::SQL_CHAR(), undef, "'", "'", undef, 0, 1, 1, 0, 0, 0, undef, 1, 999999, ],
       [ "INTEGER", DBI::SQL_INTEGER(), undef, "", "", undef, 0, 0, 1, 0, 0, 0, undef, 0, 0, ],
       [ "REAL",    DBI::SQL_REAL(),    undef, "", "", undef, 0, 0, 1, 0, 0, 0, undef, 0, 0, ],
       [
          "BLOB", DBI::SQL_LONGVARBINARY(), undef, "'", "'", undef, 0, 1, 1, 0, 0, 0, undef, 1,
          999999,
       ],
       [
          "BLOB", DBI::SQL_LONGVARBINARY(), undef, "'", "'", undef, 0, 1, 1, 0, 0, 0, undef, 1,
          999999,
       ],
       [
          "TEXT", DBI::SQL_LONGVARCHAR(), undef, "'", "'", undef, 0, 1, 1, 0, 0, 0, undef, 1,
          999999,
       ],
    ];
}    # type_info_all

sub get_avail_tables
{
    my $dbh    = $_[0];
    my @tables = ();

    if ( $dbh->{sql_handler} eq "SQL::Statement" and $dbh->{sql_ram_tables} )
    {
        # XXX map +[ undef, undef, $_, "TABLE", "TEMP" ], keys %{...}
        foreach my $table ( keys %{ $dbh->{sql_ram_tables} } )
        {
            push @tables, [ undef, undef, $table, "TABLE", "TEMP" ];
        }
    }

    my $tbl_src;
    defined $dbh->{sql_table_source}
      and $dbh->{sql_table_source}->isa('DBI::DBD::SqlEngine::TableSource')
      and $tbl_src = $dbh->{sql_table_source};

    !defined($tbl_src)
      and $dbh->{Driver}->{ImplementorClass}->can('default_table_source')
      and $tbl_src = $dbh->{Driver}->{ImplementorClass}->default_table_source();
    defined($tbl_src) and push( @tables, $tbl_src->avail_tables($dbh) );

    return @tables;
}    # get_avail_tables

{
    my $names = [qw( TABLE_QUALIFIER TABLE_OWNER TABLE_NAME TABLE_TYPE REMARKS )];

    sub table_info ($)
    {
        my $dbh = shift;

        my @tables = $dbh->func("get_avail_tables");

        # Temporary kludge: DBD::Sponge dies if @tables is empty. :-(
        # this no longer seems to be true @tables or return;

        my $dbh2 = $dbh->func("sql_sponge_driver");
        my $sth = $dbh2->prepare(
                                  "TABLE_INFO",
                                  {
                                     rows => \@tables,
                                     NAME => $names,
                                  }
                                );
        $sth or return $dbh->set_err( $DBI::stderr, $dbh2->errstr );
        $sth->execute or return;
        return $sth;
    }    # table_info
}

sub list_tables ($)
{
    my $dbh = shift;
    my @table_list;

    my @tables = $dbh->func("get_avail_tables") or return;
    foreach my $ref (@tables)
    {
        # rt69260 and rt67223 - the same issue in 2 different queues
        push @table_list, $ref->[2];
    }

    return @table_list;
}    # list_tables

sub quote ($$;$)
{
    my ( $self, $str, $type ) = @_;
    defined $str or return "NULL";
    defined $type && (    $type == DBI::SQL_NUMERIC()
                       || $type == DBI::SQL_DECIMAL()
                       || $type == DBI::SQL_INTEGER()
                       || $type == DBI::SQL_SMALLINT()
                       || $type == DBI::SQL_FLOAT()
                       || $type == DBI::SQL_REAL()
                       || $type == DBI::SQL_DOUBLE()
                       || $type == DBI::SQL_TINYINT() )
      and return $str;

    $str =~ s/\\/\\\\/sg;
    $str =~ s/\0/\\0/sg;
    $str =~ s/\'/\\\'/sg;
    $str =~ s/\n/\\n/sg;
    $str =~ s/\r/\\r/sg;
    return "'$str'";
}    # quote

sub commit ($)
{
    my $dbh = shift;
    $dbh->FETCH("Warn")
      and carp "Commit ineffective while AutoCommit is on", -1;
    return 1;
}    # commit

sub rollback ($)
{
    my $dbh = shift;
    $dbh->FETCH("Warn")
      and carp "Rollback ineffective while AutoCommit is on", -1;
    return 0;
}    # rollback

# ====== Tie-Meta ==============================================================

package DBI::DBD::SqlEngine::TieMeta;

use Carp qw(croak);
require Tie::Hash;
@DBI::DBD::SqlEngine::TieMeta::ISA = qw(Tie::Hash);

sub TIEHASH
{
    my ( $class, $tblClass, $tblMeta ) = @_;

    my $self = bless(
                      {
                         tblClass => $tblClass,
                         tblMeta  => $tblMeta,
                      },
                      $class
                    );
    return $self;
}    # new

sub STORE
{
    my ( $self, $meta_attr, $meta_val ) = @_;

    $self->{tblClass}->set_table_meta_attr( $self->{tblMeta}, $meta_attr, $meta_val );

    return;
}    # STORE

sub FETCH
{
    my ( $self, $meta_attr ) = @_;

    return $self->{tblClass}->get_table_meta_attr( $self->{tblMeta}, $meta_attr );
}    # FETCH

sub FIRSTKEY
{
    my $a = scalar keys %{ $_[0]->{tblMeta} };
    each %{ $_[0]->{tblMeta} };
}    # FIRSTKEY

sub NEXTKEY
{
    each %{ $_[0]->{tblMeta} };
}    # NEXTKEY

sub EXISTS
{
    exists $_[0]->{tblMeta}{ $_[1] };
}    # EXISTS

sub DELETE
{
    croak "Can't delete single attributes from table meta structure";
}    # DELETE

sub CLEAR
{
    %{ $_[0]->{tblMeta} } = ();
}    # CLEAR

sub SCALAR
{
    scalar %{ $_[0]->{tblMeta} };
}    # SCALAR

# ====== Tie-Tables ============================================================

package DBI::DBD::SqlEngine::TieTables;

use Carp qw(croak);
require Tie::Hash;
@DBI::DBD::SqlEngine::TieTables::ISA = qw(Tie::Hash);

sub TIEHASH
{
    my ( $class, $dbh ) = @_;

    ( my $tbl_class = $dbh->{ImplementorClass} ) =~ s/::db$/::Table/;
    my $self = bless(
                      {
                         dbh      => $dbh,
                         tblClass => $tbl_class,
                      },
                      $class
                    );
    return $self;
}    # new

sub STORE
{
    my ( $self, $table, $tbl_meta ) = @_;

    "HASH" eq ref $tbl_meta
      or croak "Invalid data for storing as table meta data (must be hash)";

    ( undef, my $meta ) = $self->{tblClass}->get_table_meta( $self->{dbh}, $table, 1 );
    $meta or croak "Invalid table name '$table'";

    while ( my ( $meta_attr, $meta_val ) = each %$tbl_meta )
    {
        $self->{tblClass}->set_table_meta_attr( $meta, $meta_attr, $meta_val );
    }

    return;
}    # STORE

sub FETCH
{
    my ( $self, $table ) = @_;

    ( undef, my $meta ) = $self->{tblClass}->get_table_meta( $self->{dbh}, $table, 1 );
    $meta or croak "Invalid table name '$table'";

    my %h;
    tie %h, "DBI::DBD::SqlEngine::TieMeta", $self->{tblClass}, $meta;

    return \%h;
}    # FETCH

sub FIRSTKEY
{
    my $a = scalar keys %{ $_[0]->{dbh}->{sql_meta} };
    each %{ $_[0]->{dbh}->{sql_meta} };
}    # FIRSTKEY

sub NEXTKEY
{
    each %{ $_[0]->{dbh}->{sql_meta} };
}    # NEXTKEY

sub EXISTS
{
    exists $_[0]->{dbh}->{sql_meta}->{ $_[1] }
      or exists $_[0]->{dbh}->{sql_meta_map}->{ $_[1] };
}    # EXISTS

sub DELETE
{
    my ( $self, $table ) = @_;

    ( undef, my $meta ) = $self->{tblClass}->get_table_meta( $self->{dbh}, $table, 1 );
    $meta or croak "Invalid table name '$table'";

    delete $_[0]->{dbh}->{sql_meta}->{ $meta->{table_name} };
}    # DELETE

sub CLEAR
{
    %{ $_[0]->{dbh}->{sql_meta} }     = ();
    %{ $_[0]->{dbh}->{sql_meta_map} } = ();
}    # CLEAR

sub SCALAR
{
    scalar %{ $_[0]->{dbh}->{sql_meta} };
}    # SCALAR

# ====== STATEMENT =============================================================

package DBI::DBD::SqlEngine::st;

use strict;
use warnings;

use vars qw(@ISA $imp_data_size);

$imp_data_size = 0;

sub bind_param ($$$;$)
{
    my ( $sth, $pNum, $val, $attr ) = @_;
    if ( $attr && defined $val )
    {
        my $type = ref $attr eq "HASH" ? $attr->{TYPE} : $attr;
        if (    $type == DBI::SQL_BIGINT()
             || $type == DBI::SQL_INTEGER()
             || $type == DBI::SQL_SMALLINT()
             || $type == DBI::SQL_TINYINT() )
        {
            $val += 0;
        }
        elsif (    $type == DBI::SQL_DECIMAL()
                || $type == DBI::SQL_DOUBLE()
                || $type == DBI::SQL_FLOAT()
                || $type == DBI::SQL_NUMERIC()
                || $type == DBI::SQL_REAL() )
        {
            $val += 0.;
        }
        else
        {
            $val = "$val";
        }
    }
    $sth->{sql_params}[ $pNum - 1 ] = $val;
    return 1;
}    # bind_param

sub execute
{
    my $sth = shift;
    my $params = @_ ? ( $sth->{sql_params} = [@_] ) : $sth->{sql_params};

    $sth->finish;
    my $stmt = $sth->{sql_stmt};

    # must not proved when already executed - SQL::Statement modifies
    # received params
    unless ( $sth->{sql_params_checked}++ )
    {
        # SQL::Statement and DBI::SQL::Nano will return the list of required params
        # when called in list context. Do not look into the several items, they're
        # implementation specific and may change without warning
        unless ( ( my $req_prm = $stmt->params() ) == ( my $nparm = @$params ) )
        {
            my $msg = "You passed $nparm parameters where $req_prm required";
            return $sth->set_err( $DBI::stderr, $msg );
        }
    }

    my @err;
    my $result;
    eval {
        local $SIG{__WARN__} = sub { push @err, @_ };
        $result = $stmt->execute( $sth, $params );
    };
    unless ( defined $result )
    {
        $sth->set_err( $DBI::stderr, $@ || $stmt->{errstr} || $err[0] );
        return;
    }

    if ( $stmt->{NUM_OF_FIELDS} )
    {    # is a SELECT statement
        $sth->STORE( Active => 1 );
        $sth->FETCH("NUM_OF_FIELDS")
          or $sth->STORE( "NUM_OF_FIELDS", $stmt->{NUM_OF_FIELDS} );
    }
    return $result;
}    # execute

sub finish
{
    my $sth = $_[0];
    $sth->SUPER::STORE( Active => 0 );
    delete $sth->{sql_stmt}{data};
    return 1;
}    # finish

sub fetch ($)
{
    my $sth  = $_[0];
    my $data = $sth->{sql_stmt}{data};
    if ( !$data || ref $data ne "ARRAY" )
    {
        $sth->set_err(
            $DBI::stderr,
            "Attempt to fetch row without a preceding execute () call or from a non-SELECT statement"
        );
        return;
    }
    my $dav = shift @$data;
    unless ($dav)
    {
        $sth->finish;
        return;
    }
    if ( $sth->FETCH("ChopBlanks") )    # XXX: (TODO) Only chop on CHAR fields,
    {                                   # not on VARCHAR or NUMERIC (see DBI docs)
        $_ && $_ =~ s/ +$// for @$dav;
    }
    return $sth->_set_fbav($dav);
}    # fetch

no warnings 'once';
*fetchrow_arrayref = \&fetch;

use warnings;

sub sql_get_colnames
{
    my $sth = $_[0];
    # Being a bit dirty here, as neither SQL::Statement::Structure nor
    # DBI::SQL::Nano::Statement_ does not offer an interface to the
    # required data
    my @colnames;
    if ( $sth->{sql_stmt}->{NAME} and "ARRAY" eq ref( $sth->{sql_stmt}->{NAME} ) )
    {
        @colnames = @{ $sth->{sql_stmt}->{NAME} };
    }
    elsif ( $sth->{sql_stmt}->isa('SQL::Statement') )
    {
        my $stmt = $sth->{sql_stmt} || {};
        my @coldefs = @{ $stmt->{column_defs} || [] };
        @colnames = map { $_->{name} || $_->{value} } @coldefs;
    }
    @colnames = $sth->{sql_stmt}->column_names() unless (@colnames);

    @colnames = () if ( grep { m/\*/ } @colnames );

    return @colnames;
}

sub FETCH ($$)
{
    my ( $sth, $attrib ) = @_;

    $attrib eq "NAME" and return [ $sth->sql_get_colnames() ];

    $attrib eq "TYPE"      and return [ ( DBI::SQL_VARCHAR() ) x scalar $sth->sql_get_colnames() ];
    $attrib eq "TYPE_NAME" and return [ ("VARCHAR") x scalar $sth->sql_get_colnames() ];
    $attrib eq "PRECISION" and return [ (0) x scalar $sth->sql_get_colnames() ];
    $attrib eq "NULLABLE"  and return [ (1) x scalar $sth->sql_get_colnames() ];

    if ( $attrib eq lc $attrib )
    {
        # Private driver attributes are lower cased
        return $sth->{$attrib};
    }

    # else pass up to DBI to handle
    return $sth->SUPER::FETCH($attrib);
}    # FETCH

sub STORE ($$$)
{
    my ( $sth, $attrib, $value ) = @_;
    if ( $attrib eq lc $attrib )    # Private driver attributes are lower cased
    {
        $sth->{$attrib} = $value;
        return 1;
    }
    return $sth->SUPER::STORE( $attrib, $value );
}    # STORE

sub DESTROY ($)
{
    my $sth = shift;
    $sth->SUPER::FETCH("Active") and $sth->finish;
    undef $sth->{sql_stmt};
    undef $sth->{sql_params};
}    # DESTROY

sub rows ($)
{
    return $_[0]->{sql_stmt}{NUM_OF_ROWS};
}    # rows

# ====== TableSource ===========================================================

package DBI::DBD::SqlEngine::TableSource;

use strict;
use warnings;

use Carp;

sub data_sources ($;$)
{
    my ( $class, $drh, $attrs ) = @_;
    croak( ( ref( $_[0] ) ? ref( $_[0] ) : $_[0] ) . " must implement data_sources" );
}

sub avail_tables
{
    my ( $self, $dbh ) = @_;
    croak( ( ref( $_[0] ) ? ref( $_[0] ) : $_[0] ) . " must implement avail_tables" );
}

# ====== DataSource ============================================================

package DBI::DBD::SqlEngine::DataSource;

use strict;
use warnings;

use Carp;

sub complete_table_name ($$;$)
{
    my ( $self, $meta, $table, $respect_case ) = @_;
    croak( ( ref( $_[0] ) ? ref( $_[0] ) : $_[0] ) . " must implement complete_table_name" );
}

sub open_data ($)
{
    my ( $self, $meta, $attrs, $flags ) = @_;
    croak( ( ref( $_[0] ) ? ref( $_[0] ) : $_[0] ) . " must implement open_data" );
}

# ====== SQL::STATEMENT ========================================================

package DBI::DBD::SqlEngine::Statement;

use strict;
use warnings;

use Carp;

@DBI::DBD::SqlEngine::Statement::ISA = qw(DBI::SQL::Nano::Statement);

sub open_table ($$$$$)
{
    my ( $self, $data, $table, $createMode, $lockMode ) = @_;

    my $class = ref $self;
    $class =~ s/::Statement/::Table/;

    my $flags = {
                  createMode => $createMode,
                  lockMode   => $lockMode,
                };
    $self->{command} eq "DROP" and $flags->{dropMode} = 1;

    # because column name mapping is initialized in constructor ...
    # and therefore specific opening operations might be done before
    # reaching DBI::DBD::SqlEngine::Table->new(), we need to intercept
    # ReadOnly here
    my $write_op = $createMode || $lockMode || $flags->{dropMode};
    if ($write_op)
    {
        my ( $tblnm, $table_meta ) = $class->get_table_meta( $data->{Database}, $table, 1 )
          or croak "Cannot find appropriate file for table '$table'";
        $table_meta->{readonly}
          and croak "Table '$table' is marked readonly - "
          . $self->{command}
          . ( $lockMode ? " with locking" : "" )
          . " command forbidden";
    }

    return $class->new( $data, { table => $table }, $flags );
}    # open_table

# ====== SQL::TABLE ============================================================

package DBI::DBD::SqlEngine::Table;

use strict;
use warnings;

use Carp;

@DBI::DBD::SqlEngine::Table::ISA = qw(DBI::SQL::Nano::Table);

sub bootstrap_table_meta
{
    my ( $self, $dbh, $meta, $table ) = @_;

    defined $dbh->{ReadOnly}
      and !defined( $meta->{readonly} )
      and $meta->{readonly} = $dbh->{ReadOnly};
    defined $meta->{sql_identifier_case}
      or $meta->{sql_identifier_case} = $dbh->{sql_identifier_case};

    exists $meta->{sql_data_source} or $meta->{sql_data_source} = $dbh->{sql_data_source};

    $meta;
}

sub init_table_meta
{
    my ( $self, $dbh, $meta, $table ) = @_ if (0);

    return;
}    # init_table_meta

sub get_table_meta ($$$;$)
{
    my ( $self, $dbh, $table, $respect_case, @other ) = @_;
    unless ( defined $respect_case )
    {
        $respect_case = 0;
        $table =~ s/^\"// and $respect_case = 1;    # handle quoted identifiers
        $table =~ s/\"$//;
    }

    unless ($respect_case)
    {
        defined $dbh->{sql_meta_map}{$table} and $table = $dbh->{sql_meta_map}{$table};
    }

    my $meta = {};
    defined $dbh->{sql_meta}{$table} and $meta = $dbh->{sql_meta}{$table};

  do_initialize:
    unless ( $meta->{initialized} )
    {
        $self->bootstrap_table_meta( $dbh, $meta, $table, @other );
        $meta->{sql_data_source}->complete_table_name( $meta, $table, $respect_case, @other )
          or return;

        if ( defined $meta->{table_name} and $table ne $meta->{table_name} )
        {
            $dbh->{sql_meta_map}{$table} = $meta->{table_name};
            $table = $meta->{table_name};
        }

        # now we know a bit more - let's check if user can't use consequent spelling
        # XXX add know issue about reset sql_identifier_case here ...
        if ( defined $dbh->{sql_meta}{$table} )
        {
            $meta = delete $dbh->{sql_meta}{$table};    # avoid endless loop
            $meta->{initialized}
              or goto do_initialize;
            #or $meta->{sql_data_source}->complete_table_name( $meta, $table, $respect_case, @other )
            #or return;
        }

        unless ( $dbh->{sql_meta}{$table}{initialized} )
        {
            $self->init_table_meta( $dbh, $meta, $table );
            $meta->{initialized} = 1;
            $dbh->{sql_meta}{$table} = $meta;
        }
    }

    return ( $table, $meta );
}    # get_table_meta

my %reset_on_modify = ();
my %compat_map      = ();

sub register_reset_on_modify
{
    my ( $proto, $extra_resets ) = @_;
    foreach my $cv ( keys %$extra_resets )
    {
        #%reset_on_modify = ( %reset_on_modify, %$extra_resets );
        push @{ $reset_on_modify{$cv} },
          ref $extra_resets->{$cv} ? @{ $extra_resets->{$cv} } : ( $extra_resets->{$cv} );
    }
    return;
}    # register_reset_on_modify

sub register_compat_map
{
    my ( $proto, $extra_compat_map ) = @_;
    %compat_map = ( %compat_map, %$extra_compat_map );
    return;
}    # register_compat_map

sub get_table_meta_attr
{
    my ( $class, $meta, $attrib ) = @_;
    exists $compat_map{$attrib}
      and $attrib = $compat_map{$attrib};
    exists $meta->{$attrib}
      and return $meta->{$attrib};
    return;
}    # get_table_meta_attr

sub set_table_meta_attr
{
    my ( $class, $meta, $attrib, $value ) = @_;
    exists $compat_map{$attrib}
      and $attrib = $compat_map{$attrib};
    $class->table_meta_attr_changed( $meta, $attrib, $value );
    $meta->{$attrib} = $value;
}    # set_table_meta_attr

sub table_meta_attr_changed
{
    my ( $class, $meta, $attrib, $value ) = @_;
    defined $reset_on_modify{$attrib}
      and delete @$meta{ @{ $reset_on_modify{$attrib} } }
      and $meta->{initialized} = 0;
}    # table_meta_attr_changed

sub open_data
{
    my ( $self, $meta, $attrs, $flags ) = @_;

    $meta->{sql_data_source}
      or croak "Table " . $meta->{table_name} . " not completely initialized";
    $meta->{sql_data_source}->open_data( $meta, $attrs, $flags );

    return;
}    # open_data

# ====== SQL::Eval API =========================================================

sub new
{
    my ( $className, $data, $attrs, $flags ) = @_;
    my $dbh = $data->{Database};

    my ( $tblnm, $meta ) = $className->get_table_meta( $dbh, $attrs->{table}, 1 )
      or croak "Cannot find appropriate table '$attrs->{table}'";
    $attrs->{table} = $tblnm;

    # Being a bit dirty here, as SQL::Statement::Structure does not offer
    # me an interface to the data I want
    $flags->{createMode} && $data->{sql_stmt}{table_defs}
      and $meta->{table_defs} = $data->{sql_stmt}{table_defs};

    # open_file must be called before inherited new is invoked
    # because column name mapping is initialized in constructor ...
    $className->open_data( $meta, $attrs, $flags );

    my $tbl = {
                %{$attrs},
                meta      => $meta,
                col_names => $meta->{col_names} || [],
              };
    return $className->SUPER::new($tbl);
}    # new

1;

=pod

=head1 NAME

DBI::DBD::SqlEngine - Base class for DBI drivers without their own SQL engine

=head1 SYNOPSIS

    package DBD::myDriver;

    use base qw(DBI::DBD::SqlEngine);

    sub driver
    {
	...
	my $drh = $proto->SUPER::driver($attr);
	...
	return $drh->{class};
	}

    package DBD::myDriver::dr;

    @ISA = qw(DBI::DBD::SqlEngine::dr);

    sub data_sources { ... }
    ...

    package DBD::myDriver::db;

    @ISA = qw(DBI::DBD::SqlEngine::db);

    sub init_valid_attributes { ... }
    sub init_default_attributes { ... }
    sub set_versions { ... }
    sub validate_STORE_attr { my ($dbh, $attrib, $value) = @_; ... }
    sub validate_FETCH_attr { my ($dbh, $attrib) = @_; ... }
    sub get_myd_versions { ... }
    sub get_avail_tables { ... }

    package DBD::myDriver::st;

    @ISA = qw(DBI::DBD::SqlEngine::st);

    sub FETCH { ... }
    sub STORE { ... }

    package DBD::myDriver::Statement;

    @ISA = qw(DBI::DBD::SqlEngine::Statement);

    sub open_table { ... }

    package DBD::myDriver::Table;

    @ISA = qw(DBI::DBD::SqlEngine::Table);

    sub new { ... }

=head1 DESCRIPTION

DBI::DBD::SqlEngine abstracts the usage of SQL engines from the
DBD. DBD authors can concentrate on the data retrieval they want to
provide.

It is strongly recommended that you read L<DBD::File::Developers> and
L<DBD::File::Roadmap>, because many of the DBD::File API is provided
by DBI::DBD::SqlEngine.

Currently the API of DBI::DBD::SqlEngine is experimental and will
likely change in the near future to provide the table meta data basics
like DBD::File.

=head2 Metadata

The following attributes are handled by DBI itself and not by
DBI::DBD::SqlEngine, thus they all work as expected:

    Active
    ActiveKids
    CachedKids
    CompatMode             (Not used)
    InactiveDestroy
    AutoInactiveDestroy
    Kids
    PrintError
    RaiseError
    Warn                   (Not used)

=head3 The following DBI attributes are handled by DBI::DBD::SqlEngine:

=head4 AutoCommit

Always on.

=head4 ChopBlanks

Works.

=head4 NUM_OF_FIELDS

Valid after C<< $sth->execute >>.

=head4 NUM_OF_PARAMS

Valid after C<< $sth->prepare >>.

=head4 NAME

Valid after C<< $sth->execute >>; probably undef for Non-Select statements.

=head4 NULLABLE

Not really working, always returns an array ref of ones, as DBD::CSV
does not verify input data. Valid after C<< $sth->execute >>; undef for
non-select statements.

=head3 The following DBI attributes and methods are not supported:

=over 4

=item bind_param_inout

=item CursorName

=item LongReadLen

=item LongTruncOk

=back

=head3 DBI::DBD::SqlEngine specific attributes

In addition to the DBI attributes, you can use the following dbh
attributes:

=head4 sql_engine_version

Contains the module version of this driver (B<readonly>)

=head4 sql_nano_version

Contains the module version of DBI::SQL::Nano (B<readonly>)

=head4 sql_statement_version

Contains the module version of SQL::Statement, if available (B<readonly>)

=head4 sql_handler

Contains the SQL Statement engine, either DBI::SQL::Nano or SQL::Statement
(B<readonly>).

=head4 sql_parser_object

Contains an instantiated instance of SQL::Parser (B<readonly>).
This is filled when used first time (only when used with SQL::Statement).

=head4 sql_sponge_driver

Contains an internally used DBD::Sponge handle (B<readonly>).

=head4 sql_valid_attrs

Contains the list of valid attributes for each DBI::DBD::SqlEngine based
driver (B<readonly>).

=head4 sql_readonly_attrs

Contains the list of those attributes which are readonly (B<readonly>).

=head4 sql_identifier_case

Contains how DBI::DBD::SqlEngine deals with non-quoted SQL identifiers:

  * SQL_IC_UPPER (1) means all identifiers are internally converted
    into upper-cased pendants
  * SQL_IC_LOWER (2) means all identifiers are internally converted
    into lower-cased pendants
  * SQL_IC_MIXED (4) means all identifiers are taken as they are

These conversions happen if (and only if) no existing identifier matches.
Once existing identifier is used as known.

The SQL statement execution classes doesn't have to care, so don't expect
C<sql_identifier_case> affects column names in statements like

  SELECT * FROM foo

=head4 sql_quoted_identifier_case

Contains how DBI::DBD::SqlEngine deals with quoted SQL identifiers
(B<readonly>). It's fixated to SQL_IC_SENSITIVE (3), which is interpreted
as SQL_IC_MIXED.

=head4 sql_flags

Contains additional flags to instantiate an SQL::Parser. Because an
SQL::Parser is instantiated only once, it's recommended to set this flag
before any statement is executed.

=head4 sql_dialect

Controls the dialect understood by SQL::Parser. Possible values (delivery
state of SQL::Statement):

  * ANSI
  * CSV
  * AnyData

Defaults to "CSV".  Because an SQL::Parser is instantiated only once and
SQL::Parser doesn't allow to modify the dialect once instantiated,
it's strongly recommended to set this flag before any statement is
executed (best place is connect attribute hash).

=head4 sql_engine_in_gofer

This value has a true value in case of this driver is operated via
L<DBD::Gofer>. The impact of being operated via Gofer is a read-only
driver (not read-only databases!), so you cannot modify any attributes
later - neither any table settings. B<But> you won't get an error in
cases you modify table attributes, so please carefully watch
C<sql_engine_in_gofer>.

=head4 sql_meta

Private data area which contains information about the tables this
module handles. Table meta data might not be available until the
table has been accessed for the first time e.g., by issuing a select
on it however it is possible to pre-initialize attributes for each table
you use.

DBI::DBD::SqlEngine recognizes the (public) attributes C<col_names>,
C<table_name>, C<readonly>, C<sql_data_source> and C<sql_identifier_case>.
Be very careful when modifying attributes you do not know, the consequence
might be a destroyed or corrupted table.

While C<sql_meta> is a private and readonly attribute (which means, you
cannot modify it's values), derived drivers might provide restricted
write access through another attribute. Well known accessors are
C<csv_tables> for L<DBD::CSV>, C<ad_tables> for L<DBD::AnyData> and
C<dbm_tables> for L<DBD::DBM>.

=head4 sql_table_source

Controls the class which will be used for fetching available tables.

See L</DBI::DBD::SqlEngine::TableSource> for details.

=head4 sql_data_source

Contains the class name to be used for opening tables.

See L</DBI::DBD::SqlEngine::DataSource> for details.

=head2 Driver private methods

=head3 Default DBI methods

=head4 data_sources

The C<data_sources> method returns a list of subdirectories of the current
directory in the form "dbi:CSV:f_dir=$dirname".

If you want to read the subdirectories of another directory, use

    my ($drh)  = DBI->install_driver ("CSV");
    my (@list) = $drh->data_sources (f_dir => "/usr/local/csv_data");

=head4 list_tables

This method returns a list of file names inside $dbh->{f_dir}.
Example:

    my ($dbh)  = DBI->connect ("dbi:CSV:f_dir=/usr/local/csv_data");
    my (@list) = $dbh->func ("list_tables");

Note that the list includes all files contained in the directory, even
those that have non-valid table names, from the view of SQL.

=head3 Additional methods

The following methods are only available via their documented name when
DBI::DBD::SQlEngine is used directly. Because this is only reasonable for
testing purposes, the real names must be used instead. Those names can be
computed by replacing the C<sql_> in the method name with the driver prefix.

=head4 sql_versions

Signature:

  sub sql_versions (;$) {
    my ($table_name) = @_;
    $table_name ||= ".";
    ...
    }

Returns the versions of the driver, including the DBI version, the Perl
version, DBI::PurePerl version (if DBI::PurePerl is active) and the version
of the SQL engine in use.

    my $dbh = DBI->connect ("dbi:File:");
    my $sql_versions = $dbh->func( "sql_versions" );
    print "$sql_versions\n";
    __END__
    # DBI::DBD::SqlEngine  0.05 using SQL::Statement 1.402
    # DBI                  1.623
    # OS                   netbsd (6.99.12)
    # Perl                 5.016002 (x86_64-netbsd-thread-multi)

Called in list context, sql_versions will return an array containing each
line as single entry.

Some drivers might use the optional (table name) argument and modify
version information related to the table (e.g. DBD::DBM provides storage
backend information for the requested table, when it has a table name).

=head4 sql_get_meta

Signature:

    sub sql_get_meta ($$)
    {
	my ($table_name, $attrib) = @_;
	...
    }

Returns the value of a meta attribute set for a specific table, if any.
See L<sql_meta> for the possible attributes.

A table name of C<"."> (single dot) is interpreted as the default table.
This will retrieve the appropriate attribute globally from the dbh.
This has the same restrictions as C<< $dbh->{$attrib} >>.

=head4 sql_set_meta

Signature:

    sub sql_set_meta ($$$)
    {
	my ($table_name, $attrib, $value) = @_;
	...
    }

Sets the value of a meta attribute set for a specific table.
See L<sql_meta> for the possible attributes.

A table name of C<"."> (single dot) is interpreted as the default table
which will set the specified attribute globally for the dbh.
This has the same restrictions as C<< $dbh->{$attrib} = $value >>.

=head4 sql_clear_meta

Signature:

    sub sql_clear_meta ($)
    {
	my ($table_name) = @_;
	...
    }

Clears the table specific meta information in the private storage of the
dbh.

=head2 Extensibility

=head3 DBI::DBD::SqlEngine::TableSource

Provides data sources and table information on database driver and database
handle level.

  package DBI::DBD::SqlEngine::TableSource;

  sub data_sources ($;$)
  {
    my ( $class, $drh, $attrs ) = @_;
    ...
  }

  sub avail_tables
  {
    my ( $class, $drh ) = @_;
    ...
  }

The C<data_sources> method is called when the user invokes any of the
following:

  @ary = DBI->data_sources($driver);
  @ary = DBI->data_sources($driver, \%attr);
  
  @ary = $dbh->data_sources();
  @ary = $dbh->data_sources(\%attr);

The C<avail_tables> method is called when the user invokes any of the
following:

  @names = $dbh->tables( $catalog, $schema, $table, $type );
  
  $sth = $dbh->table_info( $catalog, $schema, $table, $type );
  $sth = $dbh->table_info( $catalog, $schema, $table, $type, \%attr );

  $dbh->func( "list_tables" );

Every time where an C<\%attr> argument can be specified, this C<\%attr>
object's C<sql_table_source> attribute is preferred over the C<$dbh>
attribute or the driver default, eg.

  @ary = DBI->data_sources("dbi:CSV:", {
    f_dir => "/your/csv/tables",
    # note: this class doesn't comes with DBI
    sql_table_source => "DBD::File::Archive::Tar::TableSource",
    # scan tarballs instead of directories
  });

When you're going to implement such a DBD::File::Archive::Tar::TableSource
class, remember to add correct attributes (including C<sql_table_source>
and C<sql_data_source>) to the returned DSN's.

=head3 DBI::DBD::SqlEngine::DataSource

Provides base functionality for dealing with tables. It is primarily
designed for allowing transparent access to files on disk or already
opened (file-)streams (eg. for DBD::CSV).

Derived classes shall be restricted to similar functionality, too (eg.
opening streams from an archive, transparently compress/uncompress
log files before parsing them, 

  package DBI::DBD::SqlEngine::DataSource;

  sub complete_table_name ($$;$)
  {
    my ( $self, $meta, $table, $respect_case ) = @_;
    ...
  }

The method C<complete_table_name> is called when first setting up the
I<meta information> for a table:

  "SELECT user.id, user.name, user.shell FROM user WHERE ..."

results in opening the table C<user>. First step of the table open
process is completing the name. Let's imagine you're having a L<DBD::CSV>
handle with following settings:

  $dbh->{sql_identifier_case} = SQL_IC_LOWER;
  $dbh->{f_ext} = '.lst';
  $dbh->{f_dir} = '/data/web/adrmgr';

Those settings will result in looking for files matching
C<[Uu][Ss][Ee][Rr](\.lst)?$> in C</data/web/adrmgr/>. The scanning of the
directory C</data/web/adrmgr/> and the pattern match check will be done
in C<DBD::File::DataSource::File> by the C<complete_table_name> method.

If you intend to provide other sources of data streams than files, in
addition to provide an appropriate C<complete_table_name> method, a method
to open the resource is required:

  package DBI::DBD::SqlEngine::DataSource;

  sub open_data ($)
  {
    my ( $self, $meta, $attrs, $flags ) = @_;
    ...
  }

After the method C<open_data> has been run successfully, the table's meta
information are in a state which allowes the table's data accessor methods
will be able to fetch/store row information. Implementation details heavily
depends on the table implementation, whereby the most famous is surely
L<DBD::File::Table|DBD::File/DBD::File::Table>.

=head1 SQL ENGINES

DBI::DBD::SqlEngine currently supports two SQL engines:
L<SQL::Statement|SQL::Statement> and
L<DBI::SQL::Nano::Statement_|DBI::SQL::Nano>. DBI::SQL::Nano supports a
I<very> limited subset of SQL statements, but it might be faster for some
very simple tasks. SQL::Statement in contrast supports a much larger subset
of ANSI SQL.

To use SQL::Statement, you need at least version 1.401 of
SQL::Statement and the environment variable C<DBI_SQL_NANO> must not
be set to a true value.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc DBI::DBD::SqlEngine

You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=DBI>
L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=SQL-Statement>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/DBI>
L<http://annocpan.org/dist/SQL-Statement>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/DBI>

=item * Search CPAN

L<http://search.cpan.org/dist/DBI/>

=back

=head2 Where can I go for more help?

For questions about installation or usage, please ask on the
dbi-dev@perl.org mailing list.

If you have a bug report, patch or suggestion, please open
a new report ticket on CPAN, if there is not already one for
the issue you want to report. Of course, you can mail any of the
module maintainers, but it is less likely to be missed if
it is reported on RT.

Report tickets should contain a detailed description of the bug or
enhancement request you want to report and at least an easy way to
verify/reproduce the issue and any supplied fix. Patches are always
welcome, too.

=head1 ACKNOWLEDGEMENTS

Thanks to Tim Bunce, Martin Evans and H.Merijn Brand for their continued
support while developing DBD::File, DBD::DBM and DBD::AnyData.
Their support, hints and feedback helped to design and implement this
module.

=head1 AUTHOR

This module is currently maintained by

H.Merijn Brand < h.m.brand at xs4all.nl > and
Jens Rehsack  < rehsack at googlemail.com >

The original authors are Jochen Wiedmann and Jeff Zucker.

=head1 COPYRIGHT AND LICENSE

 Copyright (C) 2009-2013 by H.Merijn Brand & Jens Rehsack
 Copyright (C) 2004-2009 by Jeff Zucker
 Copyright (C) 1998-2004 by Jochen Wiedmann

All rights reserved.

You may freely distribute and/or modify this module under the terms of
either the GNU General Public License (GPL) or the Artistic License, as
specified in the Perl README file.

=head1 SEE ALSO

L<DBI>, L<DBD::File>, L<DBD::AnyData> and L<DBD::Sys>.

=cut
