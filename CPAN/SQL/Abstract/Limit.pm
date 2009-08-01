package SQL::Abstract::Limit;
use strict;
use warnings;
use Carp();

use DBI::Const::GetInfoType ();

use SQL::Abstract 1.20;

use base 'SQL::Abstract';

=head1 NAME

SQL::Abstract::Limit - portable LIMIT emulation

=cut    

our $VERSION = '0.141';

# additions / error reports welcome !
our %SyntaxMap = (  mssql    => 'Top',
                    access   => 'Top',
                    sybase   => 'GenericSubQ',
                    oracle   => 'RowNum',
                    db2      => 'FetchFirst',
                    ingres   => '',
                    adabasd  => '',
                    informix => 'Skip',
    
                    # asany    => '',
    
                    # more recent MySQL versions support LimitOffset as well
                    mysql    => 'LimitXY',
                    mysqlpp  => 'LimitXY',
                    maxdb    => 'LimitXY', # MySQL
    
                    pg       => 'LimitOffset',
                    pgpp     => 'LimitOffset',
    
                    sqlite   => 'LimitOffset',
                    sqlite2  => 'LimitOffset',
    
                    interbase => 'RowsTo',
    
                    unify     => '',
                    primebase => '',
                    mimer     => '',
    
                    # anything that uses SQL::Statement can use LimitXY, I think
                    sprite   => 'LimitXY',
                    wtsprite => 'LimitXY',
                    anydata  => 'LimitXY',
                    csv      => 'LimitXY',
                    ram      => 'LimitXY',
                    dbm      => 'LimitXY',
                    excel    => 'LimitXY',
                    google   => 'LimitXY',
                    );


=head1 SYNOPSIS

    use SQL::Abstract::Limit;

    my $sql = SQL::Abstract::Limit->new( limit_dialect => 'LimitOffset' );;

    # or autodetect from a DBI $dbh:
    my $sql = SQL::Abstract::Limit->new( limit_dialect => $dbh );

    # or from a Class::DBI class:
    my $sql = SQL::Abstract::Limit->new( limit_dialect => 'My::CDBI::App' );

    # or object:
    my $obj = My::CDBI::App->retrieve( $id );
    my $sql = SQL::Abstract::Limit->new( limit_dialect => $obj );

    # generate SQL:
    my ( $stmt, @bind ) = $sql->select( $table, \@fields, \%where, \@order, $limit, $offset );

    # Then, use these in your DBI statements
    my $sth = $dbh->prepare( $stmt );
    $sth->execute( @bind );

    # Just generate the WHERE clause (only available for some syntaxes)
    my ( $stmt, @bind )  = $sql->where( \%where, \@order, $limit, $offset );

=head1 DESCRIPTION

Portability layer for LIMIT emulation.

=over 4

=item new( case => 'lower', cmp => 'like', logic => 'and', convert => 'upper', limit_dialect => 'Top' )

All settings are optional.

=over 8

=item limit_dialect

Sets the default syntax model to use for emulating a C<LIMIT $rows OFFSET $offset>
clause. Default setting is C<GenericSubQ>. You can still pass other syntax
settings in method calls, this just sets the default. Possible values are:

    LimitOffset     PostgreSQL, SQLite
    LimitXY         MySQL, MaxDB, anything that uses SQL::Statement
    LimitYX         SQLite (optional)
    RowsTo          InterBase/FireBird

    Top             SQL/Server, MS Access
    RowNum          Oracle
    FetchFirst      DB2
    Skip            Informix
    GenericSubQ     Sybase, plus any databases not recognised by this module

    $dbh            a DBI database handle

    CDBI subclass
    CDBI object

    other DBI-based thing

The first group are implemented by appending a short clause to the end of the
statement. The second group require more intricate wrapping of the original
statement in subselects.

You can pass a L<DBI|DBI> database handle, and the module will figure out which
dialect to use.

You can pass a L<Class::DBI|Class::DBI> subclass or object, and the module will
find the C<$dbh> and use it to find the dialect.

Anything else based on L<DBI|DBI> can be easily added by locating the C<$dbh>.
Patches or suggestions welcome.

=back

Other options are described in L<SQL::Abstract|SQL::Abstract>.

=item select( $table, \@fields, $where, [ \@order, [ $rows, [ $offset ], [ $dialect ] ] ] )

Same as C<SQL::Abstract::select>, but accepts additional C<$rows>, C<$offset>
and C<$dialect> parameters.

The C<$order> parameter is required if C<$rows> is specified.

The C<$fields> parameter is required, but can be set to C<undef>, C<''> or
C<'*'> (all these get set to C<'*'>).

The C<$where> parameter is also required. It can be a hashref 
or an arrayref, or C<undef>.

=cut

sub select {
    my $self   = shift;
    my $table  = $self->_table(shift);
    my $fields = shift;
    my $where  = shift; #  if ref( $_[0] ) eq 'HASH';

    my ( $order, $rows, $offset, $syntax ) = $self->_get_args( @_ );
    
    $fields ||= '*';    # in case someone supplies '' or undef

    # with no LIMIT parameters, defer to SQL::Abstract [ don't know why the first way fails ]
    # return $self->SUPER::select( $table, $fields, $where, $order ) unless $rows;
    return SQL::Abstract->new->select( $table, $fields, $where, $order ) unless $rows;
    
    # with LIMIT parameters, get the basic SQL without the ORDER BY clause
    my ( $sql, @bind ) = $self->SUPER::select( $table, $fields, $where );

    my $syntax_name = $self->_find_syntax( $syntax );

    $sql = $self->_emulate_limit( $syntax_name, $sql, $order, $rows, $offset );

    return wantarray ? ( $sql, @bind ) : $sql;
}

=item where( [ $where, [ \@order, [ $rows, [ $offset ], [ $dialect ] ] ] ] )

Same as C<SQL::Abstract::where>, but accepts additional C<$rows>, C<$offset>
and C<$dialect> parameters.

Some SQL dialects support syntaxes that can be applied as simple phrases
tacked on to the end of the WHERE clause. These are:

    LimitOffset
    LimitXY
    LimitYX
    RowsTo

This method returns a modified WHERE clause, if the limit syntax is set to one
of these options (either in the call to C<where> or in the constructor), and
if C<$rows> is passed in.

Dies via C<croak> if you try to use it for other syntaxes.

C<$order> is required if C<$rows> is set.

C<$where> is required if any other parameters are specified. It can be a hashref 
or an arrayref, or C<undef>.

Returns a regular C<WHERE> clause if no limits are set.

=cut

sub where 
{
    my $self   = shift;
    my $where  = shift; # if ref( $_[0] ) eq 'HASH';

    my ( $order, $rows, $offset, $syntax ) = $self->_get_args( @_ );

    my ( $sql, @bind );

    if ( $rows )
    {
        ( $sql, @bind ) = $self->SUPER::where( $where );
        
        my $syntax_name = $self->_find_syntax( $syntax );

        Carp::croak( "can't build a stand-alone WHERE clause for $syntax_name" )
            unless $syntax_name =~ /(?:LimitOffset|LimitXY|LimitYX|RowsTo)/i;

        $sql = $self->_emulate_limit( $syntax_name, $sql, $order, $rows, $offset );
    }
    else
    {
        #
        ( $sql, @bind ) = $self->SUPER::where( $where, $order );
    }

    return wantarray ? ( $sql, @bind ) : $sql;
}

sub _get_args {
    my $self = shift;

    my $order  = shift;
    my $rows   = shift;
    my $offset = shift if ( $_[0] && $_[0] =~ /^\d+$/ );
    my $syntax = shift || $self->_default_limit_syntax;

    return $order, $rows, $offset, $syntax;
}

=item insert

=item update

=item delete

=item values

=item generate

See L<SQL::Abstract|SQL::Abstract> for these methods.

C<update> and C<delete> are not provided with any C<LIMIT> emulation in this
release, and no support is planned at the moment. But patches would be welcome.

=back

=cut

sub _default_limit_syntax { $_[0]->{limit_dialect} || 'GenericSubQ' }

sub _emulate_limit {
    my ( $self, $syntax, $sql, $order, $rows, $offset ) = @_;

    $offset ||= 0;

    Carp::croak( "rows must be a number (got $rows)" )     unless $rows   =~ /^\d+$/;
    Carp::croak( "offset must be a number (got $offset)" ) unless $offset =~ /^\d+$/;

    my $method = $self->can( 'emulate_limit' ) || "_$syntax";

    $sql = $self->$method( $sql, $order, $rows, $offset );

    return $sql;
}

sub _find_syntax 
{
    my ($self, $syntax) = @_;
    
    # $syntax is a dialect name, database name, $dbh, or CDBI class or object

    Carp::croak('no syntax') unless $syntax;
    
    my $db;
    
    # note: tests arranged so that the eval isn't run against a scalar $syntax
    #           see rt #15000
    if (ref $syntax)        # a $dbh or a CDBI object
    {           
        if ( UNIVERSAL::isa($syntax => 'Class::DBI') )
        {   
            $db = $self->_find_database_from_cdbi($syntax);
        }
        elsif ( eval { $syntax->{Driver}->{Name} } ) # or use isa DBI::db ?
        {
            $db = $self->_find_database_from_dbh($syntax);
        }
    }
    else                    # string - CDBI class, db name, or dialect name
    {           
        if (exists $SyntaxMap{lc $syntax})
        {
            # the name of a database
            $db = $syntax;
        }
        elsif (UNIVERSAL::isa($syntax => 'Class::DBI'))
        {
            # a CDBI class
            $db = $self->_find_database_from_cdbi($syntax);
        }
        else
        {
            # or it's already a syntax dialect
            return $syntax;
        }            
    }
    
    return $self->_find_syntax_from_database($db) if $db;

    # if you get here, you might like to provide a patch to determine the
    # syntax model for your object or ref e.g. by getting at the $dbh stored in it
    warn "can't determine syntax model for $syntax - using default";

    return $self->_default_limit_syntax;
}

# most of this code modified from DBIx::AnyDBD::rebless
sub _find_database_from_dbh {
    my ( $self, $dbh ) = @_;

    my $driver = ucfirst( $dbh->{Driver}->{Name} ) || Carp::croak( "no driver in $dbh" );

    if ( $driver eq 'Proxy' )
    {
        # Looking into the internals of DBD::Proxy is maybe a little questionable
        ( $driver ) = $dbh->{proxy_client}->{application} =~ /^DBI:(.+?):/;
    }

    # what about DBD::JDBC ?
    my ( $odbc, $ado ) = ( $driver eq 'ODBC', $driver eq 'ADO' );

    if ( $odbc || $ado )
    {
        my $name;

        # $name = $dbh->func( 17, 'GetInfo' ) if $odbc;
        $name = $dbh->get_info( $DBI::Const::GetInfoType::GetInfoType{SQL_DBMS_NAME} ) if $odbc;
        $name = $dbh->{ado_conn}->Properties->Item( 'DBMS Name' )->Value if $ado;

        die "can't determine driver name for ODBC or ADO handle: $dbh" unless $name;

CASE: {
        $driver = 'MSSQL',   last CASE if $name eq 'Microsoft SQL Server';
        $driver = 'Sybase',  last CASE if $name eq 'SQL Server';
        $driver = 'Oracle',  last CASE if $name =~ /Oracle/;
        $driver = 'ASAny',   last CASE if $name eq 'Adaptive Server Anywhere';
        $driver = 'AdabasD', last CASE if $name eq 'ADABAS D';

        # this should catch Access (ACCESS) and Informix (Informix)
        $driver = lc( $name );
        $driver =~ s/\b(\w)/uc($1)/eg;
        $driver =~ s/\s+/_/g;
        }
    }

    die "couldn't find DBD driver in $dbh" unless $driver;

    # $driver now holds a string identifying the database server - in the future,
    # it might return an object with extra information e.g. version
    return $driver;
}

# $cdbi can be a class or object
sub _find_database_from_cdbi
{
    my ($self, $cdbi) = @_;
    
    # inherits from Ima::DBI
    my ($dbh) = $cdbi->db_handles;
    
    Carp::croak "no \$dbh in $cdbi" unless $dbh;
    
    return $self->_find_database_from_dbh($dbh);
}

# currently expects a string (database moniker), but this may become an object
# with e.g. version string etc.
sub _find_syntax_from_database {
    my ( $self, $db ) = @_;

    my $syntax = $SyntaxMap{ lc( $db ) };

    return $syntax if $syntax;

    my $msg = defined $syntax ?
        "no dialect known for $db - using GenericSubQ dialect" :
        "unknown database $db - using GenericSubQ dialect";

    warn $msg;

    return 'GenericSubQ';
}

# DBIx::SearchBuilder LIMIT emulation:
#   Oracle - RowNum
#   Pg     - LimitOffset
#   Sybase - doesn't emulate
#   Informix - First - but can only retrieve 1st page
#   SQLite - default
#   MySQL - default

#   default - LIMIT $offset, $rows
#   or        LIMIT $rows
#   if $offset == 0

# DBIx::Compat also tries, but only for the easy ones


# ---------------------------------
# LIMIT emulation routines

# utility for some emulations
sub _order_directions {
    my ( $self, $order ) = @_;

    return unless $order;

    my $ref = ref $order;

    my @order;

CASE: {
    @order = @$order,     last CASE if $ref eq 'ARRAY';
    @order = ( $order ),  last CASE unless $ref;
    @order = ( $$order ), last CASE if $ref eq 'SCALAR';
    Carp::croak __PACKAGE__ . ": Unsupported data struct $ref for ORDER BY";
}

    my ( $order_by_up, $order_by_down );

    foreach my $spec ( @order )
    {
        my @spec = split ' ', $spec;
        Carp::croak( "bad column order spec: $spec" ) if @spec > 2;
        push( @spec, 'ASC' ) unless @spec == 2;
        my ( $col, $up ) = @spec; # or maybe down
        $up = uc( $up );
        Carp::croak( "bad direction: $up" ) unless $up =~ /^(?:ASC|DESC)$/;
        $order_by_up .= ", $col $up";
        my $down = $up eq 'ASC' ? 'DESC' : 'ASC';
        $order_by_down .= ", $col $down";
    }

    s/^,/ORDER BY/ for ( $order_by_up, $order_by_down );

    return $order_by_up, $order_by_down;
}

# From http://phplens.com/lens/adodb/tips_portable_sql.htm

# When writing SQL to retrieve the first 10 rows for paging, you could write...
#   Database 	                        SQL Syntax
#   DB2 	                            select * from table fetch first 10 rows only
#   Informix 	                        select first 10 * from table
#   Microsoft SQL Server and Access 	select top 10 * from table
#   MySQL and PostgreSQL 	            select * from table limit 10
#   Oracle 8i 	                        select * from (select * from table) where rownum <= 10

=head2 Limit emulation

The following dialects are available for emulating the LIMIT clause. In each
case, C<$sql> represents the SQL statement generated by C<SQL::Abstract::select>,
minus the ORDER BY clause, e.g.

    SELECT foo, bar FROM my_table WHERE some_conditions

C<$sql_after_select> represents C<$sql> with the leading C<SELECT> keyword
removed.

C<order_cols_up> represents the sort column(s) and direction(s) specified in
the C<order> parameter.

C<order_cols_down> represents the opposite sort.

C<$last = $rows + $offset>

=over 4

=item LimitOffset

=over 8

=item Syntax

    $sql ORDER BY order_cols_up LIMIT $rows OFFSET $offset

or

    $sql ORDER BY order_cols_up LIMIT $rows

if C<$offset == 0>.

=item Databases

    PostgreSQL
    SQLite

=back

=cut

sub _LimitOffset {
    my ( $self, $sql, $order, $rows, $offset ) = @_;
    $sql .= $self->_order_by( $order ) . " LIMIT $rows";
    $sql .= " OFFSET $offset" if +$offset;
    return $sql;
}

=item LimitXY

=over 8

=item Syntax

    $sql ORDER BY order_cols_up LIMIT $offset, $rows

or

     $sql ORDER BY order_cols_up LIMIT $rows

if C<$offset == 0>.

=item Databases

    MySQL

=back

=cut

sub _LimitXY {
    my ( $self, $sql, $order, $rows, $offset ) = @_;
    $sql .= $self->_order_by( $order ) . " LIMIT ";
    $sql .= "$offset, " if +$offset;
    $sql .= $rows;
    return $sql;
}

=item LimitYX

=over 8

=item Syntax

    $sql ORDER BY order_cols_up LIMIT $rows, $offset

or

    $sql ORDER BY order_cols_up LIMIT $rows

if C<$offset == 0>.

=item Databases

    SQLite understands this syntax, or LimitOffset. If autodetecting the
           dialect, it will be set to LimitOffset.

=back

=cut

sub _LimitYX {
    my ( $self, $sql, $order, $rows, $offset ) = @_;
    $sql .= $self->_order_by( $order ) . " LIMIT $rows";
    $sql .= " $offset" if +$offset;
    return $sql;
}

=item RowsTo

=over 8

=item Syntax

    $sql ORDER BY order_cols_up ROWS $offset TO $last

=item Databases

    InterBase
    FireBird

=back

=cut

# InterBase/FireBird
sub _RowsTo {
    my ( $self, $sql, $order, $rows, $offset ) = @_;
    my $last = $rows + $offset;
    $sql .= $self->_order_by( $order ) . " ROWS $offset TO $last";
    return $sql;
}

=item Top

=over 8

=item Syntax

    SELECT * FROM
    (
        SELECT TOP $rows * FROM
        (
            SELECT TOP $last $sql_after_select
            ORDER BY order_cols_up
        ) AS foo
        ORDER BY order_cols_down
    ) AS bar
    ORDER BY order_cols_up


=item Databases

    SQL/Server
    MS Access

=back

=cut

sub _Top {
    my ( $self, $sql, $order, $rows, $offset ) = @_;

    my $last = $rows + $offset;

    my ( $order_by_up, $order_by_down ) = $self->_order_directions( $order );

    $sql =~ s/^\s*(SELECT|select)//;

    $sql = <<"";
SELECT * FROM
(
    SELECT TOP $rows * FROM
    (
        SELECT TOP $last $sql $order_by_up
    ) AS foo
    $order_by_down
) AS bar
$order_by_up

    return $sql;
}



=item RowNum

=over 8

=item Syntax

Oracle numbers rows from 1, not zero, so here $offset has been incremented by 1.

    SELECT * FROM
    (
        SELECT A.*, ROWNUM r FROM
        (
            $sql ORDER BY order_cols_up
        ) A
        WHERE ROWNUM <= $last
    ) B
    WHERE r >= $offset

=item Databases

    Oracle

=back

=cut

sub _RowNum {
    my ( $self, $sql, $order, $rows, $offset ) = @_;

    # Oracle orders from 1 not zero
    $offset++;

    my $last = $rows + $offset;

    my $order_by = $self->_order_by( $order );

    $sql = <<"";
SELECT * FROM
(
    SELECT A.*, ROWNUM r FROM
    (
        $sql $order_by
    ) A
    WHERE ROWNUM < $last
) B
WHERE r >= $offset

    return $sql;
}

# DBIx::SearchBuilder::Handle::Oracle does this:

# Transform an SQL query from:
#
# SELECT main.*
#   FROM Tickets main
#  WHERE ((main.EffectiveId = main.id))
#    AND ((main.Type = 'ticket'))
#    AND ( ( (main.Status = 'new')OR(main.Status = 'open') )
#    AND ( (main.Queue = '1') ) )
#
# to:
#
# SELECT * FROM (
#     SELECT limitquery.*,rownum limitrownum FROM (
#             SELECT main.*
#               FROM Tickets main
#              WHERE ((main.EffectiveId = main.id))
#                AND ((main.Type = 'ticket'))
#                AND ( ( (main.Status = 'new')OR(main.Status = 'open') )
#                AND ( (main.Queue = '1') ) )
#     ) limitquery WHERE rownum <= 50
# ) WHERE limitrownum >= 1
#
#if ($per_page) {
#    # Oracle orders from 1 not zero
#    $first++;
#    # Make current query a sub select
#    $$statementref = "SELECT * FROM ( SELECT limitquery.*,rownum limitrownum FROM ( $$statementref ) limitquery WHERE rownum <= " . ($first + $per_page - 1) . " ) WHERE limitrownum >= " . $first;
#}

# DBIx::SQLEngine::Driver::Oracle does this:

    #sub sql_limit {
    #    my $self = shift;
    #    my ( $limit, $offset, $sql, @params ) = @_;
    #
    #    # remove tablealiases and group-functions from outer query properties
    #    my ($properties) = ($sql =~ /^\s*SELECT\s(.*?)\sFROM\s/i);
    #    $properties =~ s/[^\s]+\s*as\s*//ig;
    #    $properties =~ s/\w+\.//g;
    #
    #    $offset ||= 0;
    #    my $position = ( $offset + $limit );
    #
    #    $sql = <<"";
#SELECT $properties FROM (
#    SELECT $properties, ROWNUM AS sqle_position FROM (
#        $sql
#    )
#)
#WHERE sqle_position > $offset AND sqle_position <= $position


    #
    #    return ($sql, @params);
    #}

=item FetchFirst

=over 8

=item Syntax

    SELECT * FROM (
        SELECT * FROM (
            $sql
            ORDER BY order_cols_up
            FETCH FIRST $last ROWS ONLY
        ) foo
        ORDER BY order_cols_down
        FETCH FIRST $rows ROWS ONLY
    ) bar
    ORDER BY order_cols_up

=item Databases

IBM DB2

=back

=cut

sub _FetchFirst {
    my ( $self, $sql, $order, $rows, $offset ) = @_;

    my $last = $rows + $offset;

    my ( $order_by_up, $order_by_down ) = $self->_order_directions( $order );

    $sql = <<"";
SELECT * FROM (
    SELECT * FROM (
        $sql
        $order_by_up
        FETCH FIRST $last ROWS ONLY
    ) foo
    $order_by_down
    FETCH FIRST $rows ROWS ONLY
) bar
$order_by_up

    return $sql;
}

=item GenericSubQ

When all else fails, this should work for many databases, but it is probably
fairly slow.

This method relies on having a column with unique values as the first column in
the C<SELECT> clause (i.e. the first column in the C<\@fields> parameter). The
results will be sorted by that unique column, so any C<$order> parameter is
ignored, unless it matches the unique column, in which case the direction of
the sort is honoured.

=over 8

=item Syntax

    SELECT field_list FROM $table X WHERE where_clause AND
    (
        SELECT COUNT(*) FROM $table WHERE $pk > X.$pk
    )
    BETWEEN $offset AND $last
    ORDER BY $pk $asc_desc

C<$pk> is the first column in C<field_list>.

C<$asc_desc> is the opposite direction to that specified in the method call. So
if you want the final results sorted C<ASC>, say so, and it gets flipped
internally, but the results come out as you'd expect. I think.

The C<BETWEEN $offset AND $last> clause is replaced with C<E<lt> $rows> if
<$offset == 0>.

=item Databases

Sybase
Anything not otherwise known to this module.

=back

=cut

sub _GenericSubQ {
    my ( $self, $sql, $order, $rows, $offset ) = @_;

    my $last = $rows + $offset;

    my $order_by = $self->_order_by( $order );

    my ( $pk, $table ) = $sql =~ /^\s*SELECT\s+(\w+),?.*\sFROM\s+([\w]+)/i;

    #warn "pk: $pk";
    #warn "table: $table";

    # get specified sort order and swap it to get the expected output (I think?)
    my ( $asc_desc ) = $order_by =~ /\b$pk\s+(ASC|DESC)\s*/i;
    $asc_desc = uc( $asc_desc ) || 'ASC';
    $asc_desc = $asc_desc eq 'ASC' ? 'DESC' : 'ASC';

    $sql =~ s/FROM $table /FROM $table X /;

    my $limit = $offset ? "BETWEEN $offset AND $last" : "< $rows";

    $sql = <<"";
$sql AND
(
    SELECT COUNT(*) FROM $table WHERE $pk > X.$pk
)
$limit
ORDER BY $pk $asc_desc

    return $sql;
}


=begin notes

1st page:

    SELECT id, field1, fieldn
    FROM table_xyz X
    WHERE
    (
        SELECT COUNT(*) FROM table_xyz WHERE id > X.id
    )
    < 100
    ORDER BY id DESC

Next page:

    SELECT id, field1, fieldn
    FROM table_xyz X
    WHERE
    (
        SELECT COUNT(*) FROM table_xyz WHERE id > X.id
    )
    BETWEEN 100 AND 199
    ORDER BY id DESC


http://expertanswercenter.techtarget.com/eac/knowledgebaseAnswer/0,,sid63_gci978197,00.html

We can adapt the generic Top N query to this task. I would not use the generic
method when TOP or LIMIT is available, but you're right, the previous answer
is incomplete without this.

Using the same table and column names, the top 100 ids are given by:

SELECT id, field1, fieldn FROM table_xyz X
 WHERE ( SELECT COUNT(*)
           FROM table_xyz
          WHERE id > X.id ) < 100
 ORDER BY id DESC

The subquery is correlated, which means that it will be evaluated for each row
of the outer query. The subquery says "count the number of rows that have an
id that is greater than this id." Note that the sort order is descending, so
we are looking for ids that are greater, i.e. higher up in the result set. If
that number is less than 100, then this row must be one of the top 100. Simple,
eh? Unfortunately, it runs quite slowly. Furthermore, it takes ties into
consideration, which is good, but this means that the number of rows returned
isn't always going to be exactly 100 -- there will be extra rows if there are
ties extending across the 100th place.

Next, we need the second set of 100:

select id
     , field1
     , fieldn
  from table_xyz X
 where ( select count(*)
           from table_xyz
          where id > X.id ) between 100 and 199
 order by id desc

See the pattern? Note that the same caveat applies about ties that extend
across 200th place.

=end notes


=begin notes

=item First

=over 8

=item Syntax

Looks to be identical to C<Top>, e.g. C<SELECT FIRST 10 * FROM table>. Can
probably be implemented in a very similar way, but not done yet.

=item Databases

Informix

=back


sub _First {
    my ( $self, $sql, $order, $rows, $offset ) = @_;
    die 'FIRST not implemented';

    # fetch first 20 rows

    # might need to add to regex in 'where' method

}

=end notes

=cut

=item Skip

=over 8 

=item Syntax

  select skip 5 limit 5 * from customer

which will take rows 6 through 10 in the select.
  
=item Databases

Informix

=back

=cut

sub _Skip {
    my ( $self, $sql, $order, $rows, $offset ) = @_;

    my $last = $rows + $offset;
    
    my ( $order_by_up, $order_by_down ) = $self->_order_directions( $order );

    $sql =~ s/^\s*(SELECT|select)//;

    $sql = "select skip $offset limit $rows ".$sql." ".$self->_order_by( $order );

    return $sql;
}



1;

__END__

=back

=head1 SUBCLASSING

You can create your own syntax by making a subclass that provides an
C<emulate_limit> method. This might be useful if you are using stored procedures
to provide more efficient paging.

=over 4

=item emulate_limit( $self, $sql, $order, $rows, $offset )

=over 4

=item $sql

This is the SQL statement built by L<SQL::Abstract|SQL::Abstract>, but without
the ORDER BY clause, e.g.

    SELECT foo, bar FROM my_table WHERE conditions

or just

    WHERE conditions

if calling C<where> instead of C<select>.

=item $order

The C<order> parameter passed to the C<select> or C<where> call. You can get
an C<ORDER BY> clause from this by calling

    my $order_by = $self->_order_by( $order );

You can get a pair of C<ORDER BY> clauses that sort in opposite directions by
saying

    my ( $up, $down ) = $self->_order_directions( $order );

=back

The method should return a suitably modified SQL statement.

=back

=head1 AUTO-DETECTING THE DIALECT

The C<$dialect> parameter that can be passed to the constructor or to the
C<select> and C<where> methods can be a number of things. The module will
attempt to determine the appropriate syntax to use.

Supported C<$dialect> things are:

    dialect name (e.g. LimitOffset, RowsTo, Top etc.)
    database moniker (e.g. Oracle, SQLite etc.)
    DBI database handle
    Class::DBI subclass or object

=head1 CAVEATS

Paging results sets is a complicated undertaking, with several competing factors
to take into account. This module does B<not> magically give you the optimum
paging solution for your situation. It gives you a solution that may be good
enough in many situations. But if your tables are large, the SQL generated here
will often not be efficient. Or if your queries involve joins or other
complications, you will probably need to look elsewhere.

But if your tables aren't too huge, and your queries straightforward, you can
just plug this module in and move on to your next task.

=head1 ACKNOWLEDGEMENTS

Thanks to Aaron Johnson for the Top syntax model (SQL/Server and MS Access).

Thanks to Emanuele Zeppieri for the IBM DB2 syntax model.

Thanks to Paul Falbe for the Informix implementation.

=head1 TODO

Find more syntaxes to implement.

Test the syntaxes against real databases. I only have access to MySQL. Reports
of success or failure would be great.

=head1 DEPENDENCIES

L<SQL::Abstract|SQL::Abstract>,
L<DBI::Const::GetInfoType|DBI::Const::GetInfoType>,
L<Carp|Carp>.

=head1 SEE ALSO

L<DBIx::SQLEngine|DBIx::SQLEngine>,
L<DBIx::SearchBuilder|DBIx::SearchBuilder>,
L<DBIx::RecordSet|DBIx::RecordSet>.

=head1 BUGS

Please report all bugs via the CPAN Request Tracker at
L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=SQL-Abstract-Limit>.

=head1 COPYRIGHT AND LICENSE

Copyright 2004 by David Baird.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

David Baird, C<cpan@riverside-cms.co.uk>

=head1 HOW IS IT DONE ELSEWHERE

A few CPAN modules do this for a few databases, but the most comprehensive
seem to be DBIx::SQLEngine, DBIx::SearchBuilder and DBIx::RecordSet.

Have a look in the source code for my notes on how these modules tackle
similar problems.

=begin notes

    =over 4

    =item DBIx::SearchBuilder::Handle::Oracle

        Transform an SQL query from:

        SELECT main.*
          FROM Tickets main
         WHERE ((main.EffectiveId = main.id))
           AND ((main.Type = 'ticket'))
           AND ( ( (main.Status = 'new')OR(main.Status = 'open') )
           AND ( (main.Queue = '1') ) )

        to:

        SELECT * FROM (
            SELECT limitquery.*,rownum limitrownum FROM (
                    SELECT main.*
                      FROM Tickets main
                     WHERE ((main.EffectiveId = main.id))
                       AND ((main.Type = 'ticket'))
                       AND ( ( (main.Status = 'new')OR(main.Status = 'open') )
                       AND ( (main.Queue = '1') ) )
            ) limitquery WHERE rownum <= 50
        ) WHERE limitrownum >= 1

        if ($per_page) {
            # Oracle orders from 1 not zero
            $first++;
            # Make current query a sub select
            $$statementref = "SELECT * FROM ( SELECT limitquery.*,rownum limitrownum FROM ( $$statementref ) limitquery WHERE rownum <= " . ($first + $per_page - 1) . " ) WHERE limitrownum >= " . $first;
        }

    =item DBIx::SQLEngine::Driver

        sub sql_limit {
          my $self = shift;
          my ( $limit, $offset, $sql, @params ) = @_;

          $sql .= " limit $limit" if $limit;
          $sql .= " offset $offset" if $offset;

          return ($sql, @params);
        }

    =item DBIx::SQLEngine::Driver::AnyData

    Also:

        DBIx::SQLEngine::Driver::CSV

    Adds support for SQL select limit clause.

    TODO: Needs workaround to support offset.

        sub sql_limit {
          my $self = shift;
          my ( $limit, $offset, $sql, @params ) = @_;

          # You can't apply "limit" to non-table fetches
          $sql .= " limit $limit" if ( $sql =~ / from / );

          return ($sql, @params);
        }

    =item DBIx::SQLEngine::Driver::Informix - Support DBD::Informix and DBD::ODBC/Informix

        =item sql_limit()

        Not yet supported. Perhaps we should use "first $maxrows" and throw out the first $offset?

        =back

        =cut

        sub sql_limit {
          confess("Not yet supported")
        }

    =item DBIx::SQLEngine::Driver::MSSQL - Support DBD::ODBC with Microsoft SQL Server

        =item sql_limit()

        Adds support for SQL select limit clause.

        =back

        =cut

        sub sql_limit {
          my $self = shift;
          my ( $limit, $offset, $sql, @params ) = @_;

          # You can't apply "limit" to non-table fetches like "select LAST_INSERT_ID"
          if ( $sql =~ /\bfrom\b/ and defined $limit or defined $offset) {
            $sql .= " limit $limit" if $limit;
            $sql .= " offset $offset" if $offset;
          }

          return ($sql, @params);
        }



    =item DBIx::SQLEngine::Driver::Mysql - Support DBD::mysql

        =item sql_limit()

        Adds support for SQL select limit clause.

        =back

        =cut

        sub sql_limit {
          my $self = shift;
          my ( $limit, $offset, $sql, @params ) = @_;

          # You can't apply "limit" to non-table fetches like "select LAST_INSERT_ID"
          if ( $sql =~ /\bfrom\b/ and $limit or $offset) {
            $limit ||= 1_000_000; # MySQL select with offset requires a limit
            $sql .= " limit " . ( $offset ? "$offset," : '' ) . $limit;
          }

          return ($sql, @params);
        }

    =item DBIx::SQLEngine::Driver::Oracle - Support DBD::Oracle and DBD::ODBC/Oracle

        =item sql_limit()

        Adds support for SQL select limit clause.

        Implemented as a subselect with ROWNUM.

        =back

        =cut

        sub sql_limit {
            my $self = shift;
            my ( $limit, $offset, $sql, @params ) = @_;

            # remove tablealiases and group-functions from outer query properties
            my ($properties) = ($sql =~ /^\s*SELECT\s(.*?)\sFROM\s/i);
            $properties =~ s/[^\s]+\s*as\s*//ig;
            $properties =~ s/\w+\.//g;

            $offset ||= 0;
            my $position = ( $offset + $limit );

            $sql = <<"";
        SELECT $properties FROM (
            SELECT $properties, ROWNUM AS sqle_position FROM (
                $sql
            )
        )
        WHERE sqle_position > $offset AND sqle_position <= $position

            return ($sql, @params);
        }

    =item DBIx::SQLEngine::Driver::Pg - Support DBD::Pg

        =head2 sql_limit

          $sqldb->sql_limit( $limit, $offset, $sql, @params ) : $sql, @params

        Adds support for SQL select limit clause.

        =cut

        sub sql_limit {
          my $self = shift;
          my ( $limit, $offset, $sql, @params ) = @_;

          # You can't apply "limit" to non-table fetches like "select LAST_INSERT_ID"
          if ( $sql =~ /\bfrom\b/ and defined $limit or defined $offset) {
            $sql .= " limit $limit" if $limit;
            $sql .= " offset $offset" if $offset;
          }

          return ($sql, @params);
        }

    =item DBIx::SQLEngine::Driver::SQLite - Support DBD::SQLite driver

        =head2 sql_limit

        Adds support for SQL select limit clause.

        =cut

        sub sql_limit {
          my $self = shift;
          my ( $limit, $offset, $sql, @params ) = @_;

          # You can't apply "limit" to non-table fetches like "select LAST_INSERT_ID"
          if ( $sql =~ /\bfrom\b/ and defined $limit or defined $offset) {
            $sql .= " limit $limit" if $limit;
            $sql .= " offset $offset" if $offset;
          }

          return ($sql, @params);
        }

    =item DBIx::SQLEngine::Driver::Sybase - Extends SQLEngine for DBMS Idiosyncrasies

        =item sql_limit()

        Not yet supported.

        See http://www.isug.com/Sybase_FAQ/ASE/section6.2.html#6.2.12

        =back

        =cut

        sub sql_limit {
          confess("Not yet supported")
        }


    =item DBIx::SQLEngine::Driver::Sybase::MSSQL - Support DBD::Sybase with Microsoft SQL

    Nothing.

    =back

    =cut

=end notes
