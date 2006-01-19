#==============================================================================
# 
# Template::Plugin::DBI
#
# DESCRIPTION
#   A Template Toolkit plugin to provide access to a DBI data source.
#
# AUTHORS
#   Original version by Simon Matthews <sam@knowledgepool.com>
#   with some reworking by Andy Wardley <abw@kfs.org> and other
#   contributions from Craig Barratt <craig@arraycomm.com>,
#   Dave Hodgkinson <daveh@davehodgkinson.com> and Rafael Kitover
#   <caelum@debian.org>
#
# COPYRIGHT
#   Copyright (C) 1999-2000 Simon Matthews.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
# REVISION
#   $Id: DBI.pm,v 2.63 2004/01/30 19:33:14 abw Exp $
# 
#==============================================================================

package Template::Plugin::DBI;

require 5.004;

use strict;
use Template::Plugin;
use Template::Exception;
use DBI;

use vars qw( $VERSION $DEBUG $QUERY $ITERATOR );
use base qw( Template::Plugin );

$VERSION  = sprintf("%d.%02d", q$Revision: 2.63 $ =~ /(\d+)\.(\d+)/);
$DEBUG    = 0 unless defined $DEBUG;
$QUERY    = 'Template::Plugin::DBI::Query';
$ITERATOR = 'Template::Plugin::DBI::Iterator';

# alias _connect() to connect() for backwards compatability
*_connect = \*connect;


#------------------------------------------------------------------------
# new($context, @params)
#
# Constructor which returns a reference to a new DBI plugin object. 
# A connection string (dsn), user name and password may be passed as
# positional arguments or a hash array of connection parameters can be
# passed to initialise a connection.  Otherwise, an unconnected DBI 
# plugin object is returned.
#------------------------------------------------------------------------

sub new {
    my $class   = shift;
    my $context = shift;
    my $self    = ref $class ? $class : bless { 
	_CONTEXT => $context, 
	_STH     => [ ],
    }, $class;

    $self->connect(@_) if @_;

    return $self;
}


#------------------------------------------------------------------------
# connect( $data_source, $username, $password, $attributes )
# connect( { data_source => 'dbi:driver:database' 
#	     username    => 'foo' 
#	     password    => 'bar' } )
#
# Opens a DBI connection for the plugin. 
#------------------------------------------------------------------------

sub connect {
    my $self   = shift;
    my $params = ref $_[-1] eq 'HASH' ? pop(@_) : { };
    my ($dbh, $dsn, $user, $pass, $klobs);

    # set debug flag
    $DEBUG = $params->{ debug } if exists $params->{ debug };
    $self->{ _DEBUG } = $params->{ debug } || 0;

    # fetch 'dbh' named paramater or use positional arguments or named 
    # parameters to specify 'dsn', 'user' and 'pass'

    if ($dbh = $params->{ dbh }) {
	# disconnect any existing database handle that we previously opened
	$self->{ _DBH }->disconnect()
	    if $self->{ _DBH } && $self->{ _DBH_CONNECT };

	# store new dbh but leave _DBH_CONNECT false to prevent us 
	# from automatically closing it in the future
	$self->{ _DBH } = $dbh;
	$self->{ _DBH_CONNECT } = 0;
    }
    else {

	# certain Perl programmers are known to have problems with short 
	# term memory loss (see Tie::Hash::Cannabinol) so we let the poor
	# blighters fumble any kind of argument that looks like it might
	# identify the database 

	$dsn = shift 
	     || $params->{ data_source } 
	     || $params->{ database } 
	     || $params->{ connect } 
             || $params->{ dsn }
             || $params->{ db }
	     || $ENV{DBI_DSN}
	     || return $self->_throw('data source not defined');

	# add 'dbi:' prefix if it's not there
	$dsn = "dbi:$dsn" unless $dsn =~ /^dbi:/i;

	$user = shift
	     || $params->{ username } 
	     || $params->{ user };

	$pass = shift 
	     || $params->{ password } 
	     || $params->{ pass };

	# save connection data because we might need it later to do a tie()
	@$self{ qw( _DSN _USER _PASS ) } = ($dsn, $user, $pass);

	# reuse existing database handle if connection params match
	my $connect = join(':', $dsn || '', $user || '', $pass || '');
	return ''
	    if $self->{ _DBH } && $self->{ _DBH_CONNECT } eq $connect;
	
	# otherwise disconnect any existing database handle that we opened
	$self->{ _DBH }->disconnect()
	    if $self->{ _DBH } && $self->{ _DBH_CONNECT };
	    
	# don't need DBI to automatically print errors because all calls go 
	# via this plugin interface and we always check return values
	$params->{ PrintError } = 0
	    unless defined $params->{ PrintError };

	$self->{ _DBH } = DBI->connect_cached( $dsn, $user, $pass, $params )
 	    || return $self->_throw("DBI connect failed: $DBI::errstr");

	# store the connection parameters
	$self->{ _DBH_CONNECT } = $connect;
    }

    return '';
}


#------------------------------------------------------------------------
# disconnect()
#
# Disconnects the current active database connection.
#------------------------------------------------------------------------

sub disconnect {
    my $self = shift;
    $self->{ _DBH }->disconnect() 
	if $self->{ _DBH };
    delete $self->{ _DBH };
    return '';
}


#------------------------------------------------------------------------
# tie( $table, $key )
#
# Return a hash tied to a table in the database, indexed by the specified
# key.
#------------------------------------------------------------------------

sub tie {
    my $self = shift;
    my $params = ref $_[-1] eq 'HASH' ? pop(@_) : { };
    my ($table, $key, $klobs, $debug, %hash);

    eval { require Tie::DBI };
    $self->_throw("failed to load Tie::DBI module: $@") if $@;

    $table = shift 
	|| $params->{ table } 
        || $self->_throw('table not defined');

    $key = shift 
	|| $params->{ key } 
        || $self->_throw('key not defined');

    # Achtung der Klobberman!
    $klobs = $params->{ clobber };
    $klobs = $params->{ CLOBBER } unless defined $klobs;

    # going the extra mile to allow user to use UPPER or lower case or 
    # inherit internel debug flag set by connect()
    $debug = $params->{ debug };
    $debug = $params->{ DEBUG } unless defined $debug;
    $debug = $self->{ _DEBUG } unless defined $debug;

    tie %hash, 'Tie::DBI', {
        %$params,   # any other Tie::DBI options like DEBUG, WARN, etc
        db       => $self->{ _DBH  } || $self->{ _DSN },
        user     => $self->{ _USER },
        password => $self->{ _PASS },
        table    => $table,
        key      => $key,
        CLOBBER  => $klobs || 0,
        DEBUG    => $debug || 0,
    };

    return \%hash;
}


#------------------------------------------------------------------------
# prepare($sql)
#
# Prepare a query and store the live statement handle internally for
# subsequent execute() calls.
#------------------------------------------------------------------------

sub prepare {
    my $self = shift;
    my $sql  = shift || return undef;

    my $sth = $self->dbh->prepare($sql) 
	|| return $self->_throw("DBI prepare failed: $DBI::errstr");
    
    # create wrapper object around handle to return to template client
    $sth = $QUERY->new($sth);
    push(@{ $self->{ _STH } }, $sth);

    return $sth;
}


#------------------------------------------------------------------------
# execute()
# 
# Calls execute() on the most recent statement created via prepare().
#------------------------------------------------------------------------

sub execute {
    my $self = shift;

    my $sth = $self->{ _STH }->[-1]
	|| return $self->_throw('no query prepared');

    $sth->execute(@_);
}

    
#------------------------------------------------------------------------
# query($sql, @params)
#
# Prepares and executes a SQL query.
#------------------------------------------------------------------------

sub query {
    my $self = shift;
    my $sql  = shift;

    $self->prepare($sql)->execute(@_);
}


#------------------------------------------------------------------------
# do($sql, \%attr, @bind)
#
# Prepares and executes a SQL statement.
#------------------------------------------------------------------------

sub do {
    my $self = shift;

    return $self->dbh->do(@_)
	|| $self->_throw("DBI do failed: $DBI::errstr");
}


#------------------------------------------------------------------------
# quote($value [, $data_type ])
#
# Returns a quoted string (correct for the connected database) from the 
# value passed in.
#------------------------------------------------------------------------

sub quote {
    my $self = shift;
    $self->dbh->quote(@_);
}


#------------------------------------------------------------------------
# dbh()
#
# Internal method to retrieve the database handle belonging to the
# instance or attempt to create a new one using connect.
#------------------------------------------------------------------------

sub dbh {
    my $self = shift;

    return $self->{ _DBH } || do {
        $self->connect;
	$self->{ _DBH };
    };
}


#------------------------------------------------------------------------
# DESTROY
#
# Called automatically when the plugin object goes out of scope to 
# disconnect the database handle cleanly
#------------------------------------------------------------------------

sub DESTROY {
    my $self = shift;
    delete($self->{ _STH });       # first DESTROY any queries
    $self->{ _DBH }->disconnect() 
	if $self->{ _DBH } && $self->{ _DBH_CONNECT };
}


#------------------------------------------------------------------------
# _throw($error)
#
# Raise an error by throwing it via die() as a Template::Exception 
# object of type 'DBI'.
#------------------------------------------------------------------------

sub _throw {
    my $self  = shift;
    my $error = shift || die "DBI throw() called without an error string\n";

    # throw error as DBI exception
    die (Template::Exception->new('DBI', $error));
}


#========================================================================
# Template::Plugin::DBI::Query
#========================================================================

package Template::Plugin::DBI::Query;
use vars qw( $DEBUG $ITERATOR );

*DEBUG    = \$Template::Plugin::DBI::DEBUG;
*ITERATOR = \$Template::Plugin::DBI::ITERATOR;


sub new {
    my ($class, $sth) = @_;
    bless \$sth, $class;
}

sub execute {
    my $self = shift;

    $$self->execute(@_) 
	|| return Template::Plugin::DBI->_throw("execute failed: $DBI::errstr");

    $ITERATOR->new($$self);
}

sub DESTROY {
    my $self = shift;
    $$self->finish();
}


#========================================================================
# Template::Plugin::DBI::Iterator;
#========================================================================

package Template::Plugin::DBI::Iterator;

use Template::Iterator;
use base qw( Template::Iterator );
use vars qw( $DEBUG );

*DEBUG = \$Template::Plugin::DBI::DEBUG;


sub new {
    my ($class, $sth, $params) = @_;

    my $rows = $sth->rows();

    my $self = bless { 
	_STH => $sth,
	SIZE => $rows,
	MAX  => $rows - 1,
    }, $class;

    
    return $self;
}


#------------------------------------------------------------------------
# get_first()
#
# Initialises iterator to read from statement handle.  We maintain a 
# one-record lookahead buffer to allow us to detect if the current 
# record is the last in the series.
#------------------------------------------------------------------------

sub get_first {
    my $self = shift;
    $self->{ _STARTED } = 1;

    # set some status variables into $self
    @$self{ qw(  PREV   ITEM FIRST LAST COUNT INDEX ) } 
            = ( undef, undef,    2,   0,    0,   -1 );

    # support 'number' as an alias for 'count' for backwards compatability
    $self->{ NUMBER  } = 0;

    print STDERR "get_first() called\n" if $DEBUG;

    # get the first row
    $self->_fetchrow();

    print STDERR "get_first() calling get_next()\n" if $DEBUG;

    return $self->get_next();
}


#------------------------------------------------------------------------
# get_next()
#
# Called to read remaining result records from statement handle.
#------------------------------------------------------------------------

sub get_next {
    my $self = shift;
    my ($data, $fixup);

    # increment the 'index' and 'count' counts
    $self->{ INDEX  }++;
    $self->{ COUNT  }++;
    $self->{ NUMBER }++;   # 'number' is old name for 'count'

    # decrement the 'first-record' flag
    $self->{ FIRST }-- if $self->{ FIRST };

    # we should have a row already cache in NEXT
    return (undef, Template::Constants::STATUS_DONE)
	unless $data = $self->{ NEXT };

    # set PREV to be current ITEM from last iteration
    $self->{ PREV } = $self->{ ITEM };

    # look ahead to the next row so that the rowcache is refilled
    $self->_fetchrow();

    $self->{ ITEM } = $data;
    return ($data, Template::Constants::STATUS_OK);
}


sub get {
    my $self = shift;
    my ($data, $error);

    ($data, $error) = $self->{ _STARTED } 
		    ? $self->get_next() : $self->get_first();

    return $data;
}


sub get_all {
    my $self = shift;
    my $sth  = $self->{ _STH };
    my $error;

    my $data = $sth->fetchall_arrayref({});
    $self->throw($error) if ($error = $sth->err());
    unshift(@$data, $self->{ NEXT }) if $self->{ NEXT };
    $self->{ LAST } = 1;
    $self->{ NEXT } = undef;
    $sth->finish();

    return $data;
}


#------------------------------------------------------------------------
# _fetchrow()
#
# Retrieve a record from the statement handle and store in row cache.
#------------------------------------------------------------------------

sub _fetchrow {
    my $self = shift;
    my $sth  = $self->{ _STH };

    my $data = $sth->fetchrow_hashref() || do {
	$self->{ LAST } = 1;
	$self->{ NEXT } = undef;
	$sth->finish();
	return;
    };
    $self->{ NEXT } = $data;
    return;
}

1;

__END__


#------------------------------------------------------------------------
# IMPORTANT NOTE
#   This documentation is generated automatically from source
#   templates.  Any changes you make here may be lost.
# 
#   The 'docsrc' documentation source bundle is available for download
#   from http://www.template-toolkit.org/docs.html and contains all
#   the source templates, XML files, scripts, etc., from which the
#   documentation for the Template Toolkit is built.
#------------------------------------------------------------------------

=head1 NAME

Template::Plugin::DBI - Template interface to the DBI module

=head1 SYNOPSIS

Making an implicit database connection:

    # ...using positional arguments
    [% USE DBI('dbi:driver:dbname', 'user', 'pass') %]

    # ...using named parameters
    [% USE DBI( database = 'dbi:driver:dbname',
                username = 'user', 
                password = 'pass' )
    %]

    # ...using short named parameters (4 lzy ppl and bad typsits)
    [% USE DBI( db   = 'driver:dbname',
                user = 'user', 
                pass = 'pass' )
    %]

    # ...or an existing DBI database handle
    [% USE DBI( dbh = my_dbh_ref ) %]

Making explicit database connections:

    [% USE DBI %]

    [% DBI.connect(db, user, pass) %]
       ...

    [% DBI.connect(new_db, new_user, new_pass) %]
       ...

    [% DBI.disconnect %]      # final disconnect is optional

Making an automagical database connection using DBI_DSN environment variable:

    [% USE DBI %]

Making database queries:

    # single step query
    [% FOREACH user = DBI.query('SELECT * FROM users') %]
       [% user.uid %] blah blah [% user.name %] etc. etc.
    [% END %]

    # two stage prepare/execute
    [% query = DBI.prepare('SELECT * FROM users WHERE uid = ?') %]

    [% FOREACH user = query.execute('sam') %]
       ...
    [% END %]

    [% FOREACH user = query.execute('abw') %]
       ...
    [% END %]

Making non-SELECT statements:

    [% IF DBI.do("DELETE FROM users WHERE uid = '$uid'") %]
       The user '[% uid %]' was successfully deleted.
    [% END %]

Using named DBI connections:

    [% USE one = DBI(...) %]
    [% USE two = DBI(...) %]

    [% FOREACH item = one.query("SELECT ...etc...") %]
       ...
    [% END %]

    [% FOREACH item = two.query("SELECT ...etc...") %]
       ...
    [% END %]

Tieing to a database table (via Tie::DBI):

    [% people = DBI.tie('users', 'uid') %]

    [% me = people.abw %]   # => SELECT * FROM users WHERE uid='abw'

    I am [% me.name %]

    # clobber option allows table updates (see Tie::DBI)
    [% people = DBI.tie('users', 'uid', clobber=1) %]

    [% people.abw.name = 'not a number' %]

    I am [% people.abw.name %]   # I am a free man!

=head1 DESCRIPTION

This Template Toolkit plugin module provides an interface to the Perl
DBI/DBD modules, allowing you to integrate SQL queries into your
template documents.  It also provides an interface via the Tie::DBI
module (if installed on your system) so that you can access database
records without having to embed any SQL in your templates.

A DBI plugin object can be created as follows:

    [% USE DBI %]

This creates an uninitialised DBI object.  You can then open a connection
to a database using the connect() method.

    [% DBI.connect('dbi:driver:dbname', 'user', 'pass') %]

The DBI connection can be opened when the plugin is created by passing
arguments to the constructor, called from the USE directive.

    [% USE DBI('dbi:driver:dbname', 'user', 'pass') %]

You can also use named parameters to provide the data source connection 
string, user name and password.

    [% USE DBI(database => 'dbi:driver:dbname',
               username => 'user',
               password => 'pass')  %]

For backwards compatability with previous versions of this plugin, you can
also spell 'database' as 'data_source'.

    [% USE DBI(data_source => 'dbi:driver:dbname',
               username    => 'user',
               password    => 'pass')  %]

Lazy Template hackers may prefer to use 'db', 'dsn' or 'connect' as a
shorthand form of the 'database' parameter, and 'user' and 'pass' as
shorthand forms of 'username' and 'password', respectively.  You can
also drop the 'dbi:' prefix from the database connect string because
the plugin will add it on for you automagically.

    [% USE DBI(db   => 'driver:dbname',
               user => 'user',
               pass => 'pass')  %]

Any additional DBI attributes can be specified as named parameters.
The 'PrintError' attribute defaults to 0 unless explicitly set true.

    [% USE DBI(db, user, pass, ChopBlanks=1) %]

An alternate variable name can be provided for the plugin as per regular
Template Toolkit syntax:

    [% USE mydb = DBI('dbi:driver:dbname', 'user', 'pass') %]

    [% FOREACH item = mydb.query('SELECT * FROM users') %]
       ...
    [% END %]

You can also specify the DBI plugin name in lower case if you prefer:

    [% USE dbi(dsn, user, pass) %]

    [% FOREACH item = dbi.query('SELECT * FROM users') %]
       ...
    [% END %]

The disconnect() method can be called to explicitly disconnect the
current database, but this generally shouldn't be necessary as it is
called automatically when the plugin goes out of scope.  You can call
connect() at any time to open a connection to another database.  The
previous connection will be closed automatically.

Internally, the DBI connect_cached() method is used instead of the
connect() method.  This allows for connection caching in a server
environment, such as when the Template Toolkit is used from an Apache
mod_perl handler.  In such a case, simply enable the mod_env module
and put in a line such as:

    SetEnv DBI_DSN "dbi:mysql:dbname;host=dbhost; 
                              user=uname;password=pword"

(NOTE: the string shown here is split across 2 lines for the sake of
reasonable page formatting, but you should specify it all as one long
string with no spaces or newlines).

You can then use the DBI plugin without any parameters or the need
to explicitly call connect().

Once you've loaded a DBI plugin and opened a database connection using 
one of the techniques shown above, you can then make queries on the database
using the familiar dotted notation:

    [% FOREACH user = DBI.query('SELECT * FROM users') %]
       [% user.uid %] blah blah [% user.name %] etc. etc.
    [% END %]

The query() method prepares a query and executes it all in one go.
If you want to repeat a query with different parameters then you 
can use a separate prepare/execute cycle.

    [% query = DBI.prepare('SELECT * FROM users WHERE uid = ?') %]

    [% FOREACH user = query.execute('sam') %]
       ...
    [% END %]

    [% FOREACH user = query.execute('abw') %]
       ...
    [% END %]

The query() and execute() methods return an iterator object which
manages the result set returned.  You can save a reference to the
iterator and access methods like size() to determine the number of
rows returned by a query.

    [% users = DBI.query('SELECT * FROM users') %]
    [% users.size %] records returned

or even

    [% DBI.query('SELECT * FROM users').size %]

When used within a FOREACH loop, the iterator is always aliased to the 
special C<loop> variable.  This makes it possible to do things like this:

    [% FOREACH user = DBI.query('SELECT * FROM users') %]
       [% loop.count %]/[% loop.size %]: [% user.name %]
    [% END %]

to generate a result set of the form:

    1/3: Jerry Garcia
    2/3: Kurt Cobain
    3/3: Freddie Mercury

See L<Template::Iterator> for further details on iterators and the
methods that they implement.

The DBI plugin also provides the do() method to execute non-SELECT
statements like this:

    [% IF DBI.do("DELETE FROM users WHERE uid = '$uid'") %]
       The user '[% uid %]' was successfully deleted.
    [% END %]

The plugin also allows you to create a tie to a table in the database
using the Tie::DBI module.  Simply call the tie() method, passing the
name of the table and the primary key as arguments.

    [% people = DBI.tie('person', 'uid') %]

You can then access records in the database table as if they were
entries in the 'people' hash.

    My name is [% people.abw.name %]

IMPORTANT NOTE: the XS Stash (Template::Stash::XS) does not currently
support access to tied hashes.  If you are using the XS stash and having
problems then you should try enabling the regular stash instead.  You 
can do this by setting $Template::Config::STASH to 'Template::Stash' 
before instantiating the Template object.

=head1 OBJECT METHODS

=head2 connect($database, $username, $password)

Establishes a database connection.  This method accepts both positional 
and named parameter syntax.  e.g. 

    [% DBI.connect( 'dbi:driver:dbname', 'timmy', 'sk8D00Dz' ) %]

    [% DBI.connect( database = 'dbi:driver:dbname'
                    username = 'timmy' 
                    password = 'sk8D00Dz' ) %]

The connect method allows you to connect to a data source explicitly.
It can also be used to reconnect an exisiting object to a different
data source.  

If you already have a database handle then you can instruct the plugin
to reuse it by passing it as the 'dbh' parameter.

    [% DBI.connect( dbh = my_dbh_ref ) %]

=head2 query($sql)

This method submits an SQL query to the database and creates an iterator 
object to return the results.  This may be used directly in a FOREACH 
directive as shown below.  Data is automatically fetched a row at a time
from the query result set as required for memory efficiency.

    [% FOREACH user = DBI.query('SELECT * FROM users') %]
       Each [% user.field %] can be printed here
    [% END %]

=head2 prepare($sql)

Prepare a query for later execution.  This returns a compiled query
object (of the Template::Plugin::DBI::Query class) on which the
execute() method can subsequently be called.

    [% query = DBI.prepare('SELECT * FROM users WHERE id = ?') %]

=head2 execute(@args)

Execute a previously prepared query.  This method should be called on
the query object returned by the prepare() method.  Returns an
iterator object which can be used directly in a FOREACH directive.

    [% query = DBI.prepare('SELECT * FROM users WHERE manager = ?') %]

    [% FOREACH minion = query.execute('abw') %]
       [% minion.name %]
    [% END %]

    [% FOREACH minion = query.execute('sam') %]
       [% minion.name %]
    [% END %]

=head2 do($sql)

The do() method executes a sql statement from which no records are
returned.  It will return true if the statement was successful

    [% IF DBI.do("DELETE FROM users WHERE uid = 'sam'") %]
       The user was successfully deleted.
    [% END %]

=head2 tie($table, $key, \%args)

Returns a reference to a hash array tied to a table in the database,
implemented using the Tie::DBI module.  You should pass the name of
the table and the key field as arguments.

    [% people = DBI.tie('users', 'uid') %]

Or if you prefer, you can use the 'table' and 'key' named parameters.

    [% people = DBI.tie(table='users', key='uid') %]

In this example, the Tie::DBI module will convert the accesses into
the 'people' hash into SQL queries of the form:

    SELECT * FROM users WHERE uid=?

For example:

    [% me = people.abw %]

The record returned can then be accessed just like a normal hash.

    I am [% me.name %]

You can also do things like this to iterate through all the records
in a table.

    [% FOREACH uid = people.keys.sort;
            person = people.$uid 
    %] 
        * [% person.id %] : [% person.name %]
    [% END %]

With the 'clobber' (or 'CLOBBER') option set you can update the record
and have those changes automatically permeated back into the database.

    [% people = DBI.tie('users', 'uid', clobber=1) %]

    [% people.abw.name = 'not a number' %]

    I am [% people.abw.name %]  # I am a free man!

And you can also add new records.
 
    [% people.newguy = {
           name = 'Nobby Newguy'
	   ...other fields...
       }
    %]

See L<Tie::DBI> for further information on the 'CLOBBER' option.

=head2 quote($value, $type)

Calls the quote() method on the underlying DBI handle to quote the value
specified in the appropriate manner for its type.

=head2 dbh()

Return the database handle currently in use by the plugin.

=head2 disconnect()

Disconnects the current database.

=head1 AUTHORS

The DBI plugin was originally written by Simon A Matthews, and
distributed as a separate module.  It was integrated into the Template
Toolkit distribution for version 2.00 and includes contributions from
Andy Wardley, Craig Barratt, Dave Hodgkinson and Rafael Kitover.

=head1 VERSION

2.63, distributed as part of the
Template Toolkit version 2.14, released on 04 October 2004.



=head1 COPYRIGHT

Copyright (C) 1999-2001 Simon Matthews.  All Rights Reserved

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Template::Plugin|Template::Plugin>, L<DBI|DBI>, L<Tie::DBI|Tie::DBI>

