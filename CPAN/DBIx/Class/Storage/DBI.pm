package DBIx::Class::Storage::DBI;
# -*- mode: cperl; cperl-indent-level: 2 -*-

use strict;
use warnings;

use base 'DBIx::Class::Storage';
use mro 'c3';

use Carp::Clan qw/^DBIx::Class/;
use DBI;
use DBIx::Class::Storage::DBI::Cursor;
use DBIx::Class::Storage::Statistics;
use Scalar::Util();
use List::Util();

# what version of sqlt do we require if deploy() without a ddl_dir is invoked
# when changing also adjust the corresponding author_require in Makefile.PL
my $minimum_sqlt_version = '0.11002';


__PACKAGE__->mk_group_accessors('simple' =>
  qw/_connect_info _dbi_connect_info _dbh _sql_maker _sql_maker_opts _conn_pid
     _conn_tid transaction_depth _dbh_autocommit _driver_determined savepoints/
);

# the values for these accessors are picked out (and deleted) from
# the attribute hashref passed to connect_info
my @storage_options = qw/
  on_connect_call on_disconnect_call on_connect_do on_disconnect_do
  disable_sth_caching unsafe auto_savepoint
/;
__PACKAGE__->mk_group_accessors('simple' => @storage_options);


# default cursor class, overridable in connect_info attributes
__PACKAGE__->cursor_class('DBIx::Class::Storage::DBI::Cursor');

__PACKAGE__->mk_group_accessors('inherited' => qw/sql_maker_class/);
__PACKAGE__->sql_maker_class('DBIx::Class::SQLAHacks');


=head1 NAME

DBIx::Class::Storage::DBI - DBI storage handler

=head1 SYNOPSIS

  my $schema = MySchema->connect('dbi:SQLite:my.db');

  $schema->storage->debug(1);

  my @stuff = $schema->storage->dbh_do(
    sub {
      my ($storage, $dbh, @args) = @_;
      $dbh->do("DROP TABLE authors");
    },
    @column_list
  );

  $schema->resultset('Book')->search({
     written_on => $schema->storage->datetime_parser(DateTime->now)
  });

=head1 DESCRIPTION

This class represents the connection to an RDBMS via L<DBI>.  See
L<DBIx::Class::Storage> for general information.  This pod only
documents DBI-specific methods and behaviors.

=head1 METHODS

=cut

sub new {
  my $new = shift->next::method(@_);

  $new->transaction_depth(0);
  $new->_sql_maker_opts({});
  $new->{savepoints} = [];
  $new->{_in_dbh_do} = 0;
  $new->{_dbh_gen} = 0;

  $new;
}

=head2 connect_info

This method is normally called by L<DBIx::Class::Schema/connection>, which
encapsulates its argument list in an arrayref before passing them here.

The argument list may contain:

=over

=item *

The same 4-element argument set one would normally pass to
L<DBI/connect>, optionally followed by
L<extra attributes|/DBIx::Class specific connection attributes>
recognized by DBIx::Class:

  $connect_info_args = [ $dsn, $user, $password, \%dbi_attributes?, \%extra_attributes? ];

=item *

A single code reference which returns a connected
L<DBI database handle|DBI/connect> optionally followed by
L<extra attributes|/DBIx::Class specific connection attributes> recognized
by DBIx::Class:

  $connect_info_args = [ sub { DBI->connect (...) }, \%extra_attributes? ];

=item *

A single hashref with all the attributes and the dsn/user/password
mixed together:

  $connect_info_args = [{
    dsn => $dsn,
    user => $user,
    password => $pass,
    %dbi_attributes,
    %extra_attributes,
  }];

  $connect_info_args = [{
    dbh_maker => sub { DBI->connect (...) },
    %dbi_attributes,
    %extra_attributes,
  }];

This is particularly useful for L<Catalyst> based applications, allowing the
following config (L<Config::General> style):

  <Model::DB>
    schema_class   App::DB
    <connect_info>
      dsn          dbi:mysql:database=test
      user         testuser
      password     TestPass
      AutoCommit   1
    </connect_info>
  </Model::DB>

The C<dsn>/C<user>/C<password> combination can be substituted by the
C<dbh_maker> key whose value is a coderef that returns a connected
L<DBI database handle|DBI/connect>

=back

Please note that the L<DBI> docs recommend that you always explicitly
set C<AutoCommit> to either I<0> or I<1>.  L<DBIx::Class> further
recommends that it be set to I<1>, and that you perform transactions
via our L<DBIx::Class::Schema/txn_do> method.  L<DBIx::Class> will set it
to I<1> if you do not do explicitly set it to zero.  This is the default
for most DBDs. See L</DBIx::Class and AutoCommit> for details.

=head3 DBIx::Class specific connection attributes

In addition to the standard L<DBI|DBI/ATTRIBUTES_COMMON_TO_ALL_HANDLES>
L<connection|DBI/Database_Handle_Attributes> attributes, DBIx::Class recognizes
the following connection options. These options can be mixed in with your other
L<DBI> connection attributes, or placed in a seperate hashref
(C<\%extra_attributes>) as shown above.

Every time C<connect_info> is invoked, any previous settings for
these options will be cleared before setting the new ones, regardless of
whether any options are specified in the new C<connect_info>.


=over

=item on_connect_do

Specifies things to do immediately after connecting or re-connecting to
the database.  Its value may contain:

=over

=item a scalar

This contains one SQL statement to execute.

=item an array reference

This contains SQL statements to execute in order.  Each element contains
a string or a code reference that returns a string.

=item a code reference

This contains some code to execute.  Unlike code references within an
array reference, its return value is ignored.

=back

=item on_disconnect_do

Takes arguments in the same form as L</on_connect_do> and executes them
immediately before disconnecting from the database.

Note, this only runs if you explicitly call L</disconnect> on the
storage object.

=item on_connect_call

A more generalized form of L</on_connect_do> that calls the specified
C<connect_call_METHOD> methods in your storage driver.

  on_connect_do => 'select 1'

is equivalent to:

  on_connect_call => [ [ do_sql => 'select 1' ] ]

Its values may contain:

=over

=item a scalar

Will call the C<connect_call_METHOD> method.

=item a code reference

Will execute C<< $code->($storage) >>

=item an array reference

Each value can be a method name or code reference.

=item an array of arrays

For each array, the first item is taken to be the C<connect_call_> method name
or code reference, and the rest are parameters to it.

=back

Some predefined storage methods you may use:

=over

=item do_sql

Executes a SQL string or a code reference that returns a SQL string. This is
what L</on_connect_do> and L</on_disconnect_do> use.

It can take:

=over

=item a scalar

Will execute the scalar as SQL.

=item an arrayref

Taken to be arguments to L<DBI/do>, the SQL string optionally followed by the
attributes hashref and bind values.

=item a code reference

Will execute C<< $code->($storage) >> and execute the return array refs as
above.

=back

=item datetime_setup

Execute any statements necessary to initialize the database session to return
and accept datetime/timestamp values used with
L<DBIx::Class::InflateColumn::DateTime>.

Only necessary for some databases, see your specific storage driver for
implementation details.

=back

=item on_disconnect_call

Takes arguments in the same form as L</on_connect_call> and executes them
immediately before disconnecting from the database.

Calls the C<disconnect_call_METHOD> methods as opposed to the
C<connect_call_METHOD> methods called by L</on_connect_call>.

Note, this only runs if you explicitly call L</disconnect> on the
storage object.

=item disable_sth_caching

If set to a true value, this option will disable the caching of
statement handles via L<DBI/prepare_cached>.

=item limit_dialect

Sets the limit dialect. This is useful for JDBC-bridge among others
where the remote SQL-dialect cannot be determined by the name of the
driver alone. See also L<SQL::Abstract::Limit>.

=item quote_char

Specifies what characters to use to quote table and column names. If
you use this you will want to specify L</name_sep> as well.

C<quote_char> expects either a single character, in which case is it
is placed on either side of the table/column name, or an arrayref of length
2 in which case the table/column name is placed between the elements.

For example under MySQL you should use C<< quote_char => '`' >>, and for
SQL Server you should use C<< quote_char => [qw/[ ]/] >>.

=item name_sep

This only needs to be used in conjunction with C<quote_char>, and is used to
specify the charecter that seperates elements (schemas, tables, columns) from
each other. In most cases this is simply a C<.>.

The consequences of not supplying this value is that L<SQL::Abstract>
will assume DBIx::Class' uses of aliases to be complete column
names. The output will look like I<"me.name"> when it should actually
be I<"me"."name">.

=item unsafe

This Storage driver normally installs its own C<HandleError>, sets
C<RaiseError> and C<ShowErrorStatement> on, and sets C<PrintError> off on
all database handles, including those supplied by a coderef.  It does this
so that it can have consistent and useful error behavior.

If you set this option to a true value, Storage will not do its usual
modifications to the database handle's attributes, and instead relies on
the settings in your connect_info DBI options (or the values you set in
your connection coderef, in the case that you are connecting via coderef).

Note that your custom settings can cause Storage to malfunction,
especially if you set a C<HandleError> handler that suppresses exceptions
and/or disable C<RaiseError>.

=item auto_savepoint

If this option is true, L<DBIx::Class> will use savepoints when nesting
transactions, making it possible to recover from failure in the inner
transaction without having to abort all outer transactions.

=item cursor_class

Use this argument to supply a cursor class other than the default
L<DBIx::Class::Storage::DBI::Cursor>.

=back

Some real-life examples of arguments to L</connect_info> and
L<DBIx::Class::Schema/connect>

  # Simple SQLite connection
  ->connect_info([ 'dbi:SQLite:./foo.db' ]);

  # Connect via subref
  ->connect_info([ sub { DBI->connect(...) } ]);

  # Connect via subref in hashref
  ->connect_info([{
    dbh_maker => sub { DBI->connect(...) },
    on_connect_do => 'alter session ...',
  }]);

  # A bit more complicated
  ->connect_info(
    [
      'dbi:Pg:dbname=foo',
      'postgres',
      'my_pg_password',
      { AutoCommit => 1 },
      { quote_char => q{"}, name_sep => q{.} },
    ]
  );

  # Equivalent to the previous example
  ->connect_info(
    [
      'dbi:Pg:dbname=foo',
      'postgres',
      'my_pg_password',
      { AutoCommit => 1, quote_char => q{"}, name_sep => q{.} },
    ]
  );

  # Same, but with hashref as argument
  # See parse_connect_info for explanation
  ->connect_info(
    [{
      dsn         => 'dbi:Pg:dbname=foo',
      user        => 'postgres',
      password    => 'my_pg_password',
      AutoCommit  => 1,
      quote_char  => q{"},
      name_sep    => q{.},
    }]
  );

  # Subref + DBIx::Class-specific connection options
  ->connect_info(
    [
      sub { DBI->connect(...) },
      {
          quote_char => q{`},
          name_sep => q{@},
          on_connect_do => ['SET search_path TO myschema,otherschema,public'],
          disable_sth_caching => 1,
      },
    ]
  );



=cut

sub connect_info {
  my ($self, $info_arg) = @_;

  return $self->_connect_info if !$info_arg;

  my @args = @$info_arg;  # take a shallow copy for further mutilation
  $self->_connect_info([@args]); # copy for _connect_info


  # combine/pre-parse arguments depending on invocation style

  my %attrs;
  if (ref $args[0] eq 'CODE') {     # coderef with optional \%extra_attributes
    %attrs = %{ $args[1] || {} };
    @args = $args[0];
  }
  elsif (ref $args[0] eq 'HASH') { # single hashref (i.e. Catalyst config)
    %attrs = %{$args[0]};
    @args = ();
    if (my $code = delete $attrs{dbh_maker}) {
      @args = $code;

      my @ignored = grep { delete $attrs{$_} } (qw/dsn user password/);
      if (@ignored) {
        carp sprintf (
            'Attribute(s) %s in connect_info were ignored, as they can not be applied '
          . "to the result of 'dbh_maker'",

          join (', ', map { "'$_'" } (@ignored) ),
        );
      }
    }
    else {
      @args = delete @attrs{qw/dsn user password/};
    }
  }
  else {                # otherwise assume dsn/user/password + \%attrs + \%extra_attrs
    %attrs = (
      % { $args[3] || {} },
      % { $args[4] || {} },
    );
    @args = @args[0,1,2];
  }

  # Kill sql_maker/_sql_maker_opts, so we get a fresh one with only
  #  the new set of options
  $self->_sql_maker(undef);
  $self->_sql_maker_opts({});

  if(keys %attrs) {
    for my $storage_opt (@storage_options, 'cursor_class') {    # @storage_options is declared at the top of the module
      if(my $value = delete $attrs{$storage_opt}) {
        $self->$storage_opt($value);
      }
    }
    for my $sql_maker_opt (qw/limit_dialect quote_char name_sep/) {
      if(my $opt_val = delete $attrs{$sql_maker_opt}) {
        $self->_sql_maker_opts->{$sql_maker_opt} = $opt_val;
      }
    }
  }

  if (ref $args[0] eq 'CODE') {
    # _connect() never looks past $args[0] in this case
    %attrs = ()
  } else {
    %attrs = (
      %{ $self->_default_dbi_connect_attributes || {} },
      %attrs,
    );
  }

  $self->_dbi_connect_info([@args, keys %attrs ? \%attrs : ()]);
  $self->_connect_info;
}

sub _default_dbi_connect_attributes {
  return {
    AutoCommit => 1,
    RaiseError => 1,
    PrintError => 0,
  };
}

=head2 on_connect_do

This method is deprecated in favour of setting via L</connect_info>.

=cut

=head2 on_disconnect_do

This method is deprecated in favour of setting via L</connect_info>.

=cut

sub _parse_connect_do {
  my ($self, $type) = @_;

  my $val = $self->$type;
  return () if not defined $val;

  my @res;

  if (not ref($val)) {
    push @res, [ 'do_sql', $val ];
  } elsif (ref($val) eq 'CODE') {
    push @res, $val;
  } elsif (ref($val) eq 'ARRAY') {
    push @res, map { [ 'do_sql', $_ ] } @$val;
  } else {
    $self->throw_exception("Invalid type for $type: ".ref($val));
  }

  return \@res;
}

=head2 dbh_do

Arguments: ($subref | $method_name), @extra_coderef_args?

Execute the given $subref or $method_name using the new exception-based
connection management.

The first two arguments will be the storage object that C<dbh_do> was called
on and a database handle to use.  Any additional arguments will be passed
verbatim to the called subref as arguments 2 and onwards.

Using this (instead of $self->_dbh or $self->dbh) ensures correct
exception handling and reconnection (or failover in future subclasses).

Your subref should have no side-effects outside of the database, as
there is the potential for your subref to be partially double-executed
if the database connection was stale/dysfunctional.

Example:

  my @stuff = $schema->storage->dbh_do(
    sub {
      my ($storage, $dbh, @cols) = @_;
      my $cols = join(q{, }, @cols);
      $dbh->selectrow_array("SELECT $cols FROM foo");
    },
    @column_list
  );

=cut

sub dbh_do {
  my $self = shift;
  my $code = shift;

  my $dbh = $self->_get_dbh;

  return $self->$code($dbh, @_) if $self->{_in_dbh_do}
      || $self->{transaction_depth};

  local $self->{_in_dbh_do} = 1;

  my @result;
  my $want_array = wantarray;

  eval {

    if($want_array) {
        @result = $self->$code($dbh, @_);
    }
    elsif(defined $want_array) {
        $result[0] = $self->$code($dbh, @_);
    }
    else {
        $self->$code($dbh, @_);
    }
  };

  # ->connected might unset $@ - copy
  my $exception = $@;
  if(!$exception) { return $want_array ? @result : $result[0] }

  $self->throw_exception($exception) if $self->connected;

  # We were not connected - reconnect and retry, but let any
  #  exception fall right through this time
  carp "Retrying $code after catching disconnected exception: $exception"
    if $ENV{DBIC_DBIRETRY_DEBUG};
  $self->_populate_dbh;
  $self->$code($self->_dbh, @_);
}

# This is basically a blend of dbh_do above and DBIx::Class::Storage::txn_do.
# It also informs dbh_do to bypass itself while under the direction of txn_do,
#  via $self->{_in_dbh_do} (this saves some redundant eval and errorcheck, etc)
sub txn_do {
  my $self = shift;
  my $coderef = shift;

  ref $coderef eq 'CODE' or $self->throw_exception
    ('$coderef must be a CODE reference');

  return $coderef->(@_) if $self->{transaction_depth} && ! $self->auto_savepoint;

  local $self->{_in_dbh_do} = 1;

  my @result;
  my $want_array = wantarray;

  my $tried = 0;
  while(1) {
    eval {
      $self->_get_dbh;

      $self->txn_begin;
      if($want_array) {
          @result = $coderef->(@_);
      }
      elsif(defined $want_array) {
          $result[0] = $coderef->(@_);
      }
      else {
          $coderef->(@_);
      }
      $self->txn_commit;
    };

    # ->connected might unset $@ - copy
    my $exception = $@;
    if(!$exception) { return $want_array ? @result : $result[0] }

    if($tried++ || $self->connected) {
      eval { $self->txn_rollback };
      my $rollback_exception = $@;
      if($rollback_exception) {
        my $exception_class = "DBIx::Class::Storage::NESTED_ROLLBACK_EXCEPTION";
        $self->throw_exception($exception)  # propagate nested rollback
          if $rollback_exception =~ /$exception_class/;

        $self->throw_exception(
          "Transaction aborted: ${exception}. "
          . "Rollback failed: ${rollback_exception}"
        );
      }
      $self->throw_exception($exception)
    }

    # We were not connected, and was first try - reconnect and retry
    # via the while loop
    carp "Retrying $coderef after catching disconnected exception: $exception"
      if $ENV{DBIC_DBIRETRY_DEBUG};
    $self->_populate_dbh;
  }
}

=head2 disconnect

Our C<disconnect> method also performs a rollback first if the
database is not in C<AutoCommit> mode.

=cut

sub disconnect {
  my ($self) = @_;

  if( $self->_dbh ) {
    my @actions;

    push @actions, ( $self->on_disconnect_call || () );
    push @actions, $self->_parse_connect_do ('on_disconnect_do');

    $self->_do_connection_actions(disconnect_call_ => $_) for @actions;

    $self->_dbh_rollback unless $self->_dbh_autocommit;

    $self->_dbh->disconnect;
    $self->_dbh(undef);
    $self->{_dbh_gen}++;
  }
}

=head2 with_deferred_fk_checks

=over 4

=item Arguments: C<$coderef>

=item Return Value: The return value of $coderef

=back

Storage specific method to run the code ref with FK checks deferred or
in MySQL's case disabled entirely.

=cut

# Storage subclasses should override this
sub with_deferred_fk_checks {
  my ($self, $sub) = @_;

  $sub->();
}

=head2 connected

=over

=item Arguments: none

=item Return Value: 1|0

=back

Verifies that the the current database handle is active and ready to execute
an SQL statement (i.e. the connection did not get stale, server is still
answering, etc.) This method is used internally by L</dbh>.

=cut

sub connected {
  my $self = shift;
  return 0 unless $self->_seems_connected;

  #be on the safe side
  local $self->_dbh->{RaiseError} = 1;

  return $self->_ping;
}

sub _seems_connected {
  my $self = shift;

  my $dbh = $self->_dbh
    or return 0;

  if(defined $self->_conn_tid && $self->_conn_tid != threads->tid) {
    $self->_dbh(undef);
    $self->{_dbh_gen}++;
    return 0;
  }
  else {
    $self->_verify_pid;
    return 0 if !$self->_dbh;
  }

  return $dbh->FETCH('Active');
}

sub _ping {
  my $self = shift;

  my $dbh = $self->_dbh or return 0;

  return $dbh->ping;
}

# handle pid changes correctly
#  NOTE: assumes $self->_dbh is a valid $dbh
sub _verify_pid {
  my ($self) = @_;

  return if defined $self->_conn_pid && $self->_conn_pid == $$;

  $self->_dbh->{InactiveDestroy} = 1;
  $self->_dbh(undef);
  $self->{_dbh_gen}++;

  return;
}

sub ensure_connected {
  my ($self) = @_;

  unless ($self->connected) {
    $self->_populate_dbh;
  }
}

=head2 dbh

Returns a C<$dbh> - a data base handle of class L<DBI>. The returned handle
is guaranteed to be healthy by implicitly calling L</connected>, and if
necessary performing a reconnection before returning. Keep in mind that this
is very B<expensive> on some database engines. Consider using L<dbh_do>
instead.

=cut

sub dbh {
  my ($self) = @_;

  if (not $self->_dbh) {
    $self->_populate_dbh;
  } else {
    $self->ensure_connected;
  }
  return $self->_dbh;
}

# this is the internal "get dbh or connect (don't check)" method
sub _get_dbh {
  my $self = shift;
  $self->_verify_pid if $self->_dbh;
  $self->_populate_dbh unless $self->_dbh;
  return $self->_dbh;
}

sub _sql_maker_args {
    my ($self) = @_;

    return (
      bindtype=>'columns',
      array_datatypes => 1,
      limit_dialect => $self->_get_dbh,
      %{$self->_sql_maker_opts}
    );
}

sub sql_maker {
  my ($self) = @_;
  unless ($self->_sql_maker) {
    my $sql_maker_class = $self->sql_maker_class;
    $self->ensure_class_loaded ($sql_maker_class);
    $self->_sql_maker($sql_maker_class->new( $self->_sql_maker_args ));
  }
  return $self->_sql_maker;
}

# nothing to do by default
sub _rebless {}
sub _init {}

sub _populate_dbh {
  my ($self) = @_;

  my @info = @{$self->_dbi_connect_info || []};
  $self->_dbh(undef); # in case ->connected failed we might get sent here
  $self->_dbh($self->_connect(@info));

  $self->_conn_pid($$);
  $self->_conn_tid(threads->tid) if $INC{'threads.pm'};

  $self->_determine_driver;

  # Always set the transaction depth on connect, since
  #  there is no transaction in progress by definition
  $self->{transaction_depth} = $self->_dbh_autocommit ? 0 : 1;

  $self->_run_connection_actions unless $self->{_in_determine_driver};
}

sub _run_connection_actions {
  my $self = shift;
  my @actions;

  push @actions, ( $self->on_connect_call || () );
  push @actions, $self->_parse_connect_do ('on_connect_do');

  $self->_do_connection_actions(connect_call_ => $_) for @actions;
}

sub _determine_driver {
  my ($self) = @_;

  if ((not $self->_driver_determined) && (not $self->{_in_determine_driver})) {
    my $started_unconnected = 0;
    local $self->{_in_determine_driver} = 1;

    if (ref($self) eq __PACKAGE__) {
      my $driver;
      if ($self->_dbh) { # we are connected
        $driver = $self->_dbh->{Driver}{Name};
      } else {
        # if connect_info is a CODEREF, we have no choice but to connect
        if (ref $self->_dbi_connect_info->[0] &&
            Scalar::Util::reftype($self->_dbi_connect_info->[0]) eq 'CODE') {
          $self->_populate_dbh;
          $driver = $self->_dbh->{Driver}{Name};
        }
        else {
          # try to use dsn to not require being connected, the driver may still
          # force a connection in _rebless to determine version
          ($driver) = $self->_dbi_connect_info->[0] =~ /dbi:([^:]+):/i;
          $started_unconnected = 1;
        }
      }

      my $storage_class = "DBIx::Class::Storage::DBI::${driver}";
      if ($self->load_optional_class($storage_class)) {
        mro::set_mro($storage_class, 'c3');
        bless $self, $storage_class;
        $self->_rebless();
      }
    }

    $self->_driver_determined(1);

    $self->_init; # run driver-specific initializations

    $self->_run_connection_actions
        if $started_unconnected && defined $self->_dbh;
  }
}

sub _do_connection_actions {
  my $self          = shift;
  my $method_prefix = shift;
  my $call          = shift;

  if (not ref($call)) {
    my $method = $method_prefix . $call;
    $self->$method(@_);
  } elsif (ref($call) eq 'CODE') {
    $self->$call(@_);
  } elsif (ref($call) eq 'ARRAY') {
    if (ref($call->[0]) ne 'ARRAY') {
      $self->_do_connection_actions($method_prefix, $_) for @$call;
    } else {
      $self->_do_connection_actions($method_prefix, @$_) for @$call;
    }
  } else {
    $self->throw_exception (sprintf ("Don't know how to process conection actions of type '%s'", ref($call)) );
  }

  return $self;
}

sub connect_call_do_sql {
  my $self = shift;
  $self->_do_query(@_);
}

sub disconnect_call_do_sql {
  my $self = shift;
  $self->_do_query(@_);
}

# override in db-specific backend when necessary
sub connect_call_datetime_setup { 1 }

sub _do_query {
  my ($self, $action) = @_;

  if (ref $action eq 'CODE') {
    $action = $action->($self);
    $self->_do_query($_) foreach @$action;
  }
  else {
    # Most debuggers expect ($sql, @bind), so we need to exclude
    # the attribute hash which is the second argument to $dbh->do
    # furthermore the bind values are usually to be presented
    # as named arrayref pairs, so wrap those here too
    my @do_args = (ref $action eq 'ARRAY') ? (@$action) : ($action);
    my $sql = shift @do_args;
    my $attrs = shift @do_args;
    my @bind = map { [ undef, $_ ] } @do_args;

    $self->_query_start($sql, @bind);
    $self->_get_dbh->do($sql, $attrs, @do_args);
    $self->_query_end($sql, @bind);
  }

  return $self;
}

sub _connect {
  my ($self, @info) = @_;

  $self->throw_exception("You failed to provide any connection info")
    if !@info;

  my ($old_connect_via, $dbh);

  if ($INC{'Apache/DBI.pm'} && $ENV{MOD_PERL}) {
    $old_connect_via = $DBI::connect_via;
    $DBI::connect_via = 'connect';
  }

  eval {
    if(ref $info[0] eq 'CODE') {
       $dbh = &{$info[0]}
    }
    else {
       $dbh = DBI->connect(@info);
    }

    if($dbh && !$self->unsafe) {
      my $weak_self = $self;
      Scalar::Util::weaken($weak_self);
      $dbh->{HandleError} = sub {
          if ($weak_self) {
            $weak_self->throw_exception("DBI Exception: $_[0]");
          }
          else {
            # the handler may be invoked by something totally out of
            # the scope of DBIC
            croak ("DBI Exception: $_[0]");
          }
      };
      $dbh->{ShowErrorStatement} = 1;
      $dbh->{RaiseError} = 1;
      $dbh->{PrintError} = 0;
    }
  };

  $DBI::connect_via = $old_connect_via if $old_connect_via;

  $self->throw_exception("DBI Connection failed: " . ($@||$DBI::errstr))
    if !$dbh || $@;

  $self->_dbh_autocommit($dbh->{AutoCommit});

  $dbh;
}

sub svp_begin {
  my ($self, $name) = @_;

  $name = $self->_svp_generate_name
    unless defined $name;

  $self->throw_exception ("You can't use savepoints outside a transaction")
    if $self->{transaction_depth} == 0;

  $self->throw_exception ("Your Storage implementation doesn't support savepoints")
    unless $self->can('_svp_begin');

  push @{ $self->{savepoints} }, $name;

  $self->debugobj->svp_begin($name) if $self->debug;

  return $self->_svp_begin($name);
}

sub svp_release {
  my ($self, $name) = @_;

  $self->throw_exception ("You can't use savepoints outside a transaction")
    if $self->{transaction_depth} == 0;

  $self->throw_exception ("Your Storage implementation doesn't support savepoints")
    unless $self->can('_svp_release');

  if (defined $name) {
    $self->throw_exception ("Savepoint '$name' does not exist")
      unless grep { $_ eq $name } @{ $self->{savepoints} };

    # Dig through the stack until we find the one we are releasing.  This keeps
    # the stack up to date.
    my $svp;

    do { $svp = pop @{ $self->{savepoints} } } while $svp ne $name;
  } else {
    $name = pop @{ $self->{savepoints} };
  }

  $self->debugobj->svp_release($name) if $self->debug;

  return $self->_svp_release($name);
}

sub svp_rollback {
  my ($self, $name) = @_;

  $self->throw_exception ("You can't use savepoints outside a transaction")
    if $self->{transaction_depth} == 0;

  $self->throw_exception ("Your Storage implementation doesn't support savepoints")
    unless $self->can('_svp_rollback');

  if (defined $name) {
      # If they passed us a name, verify that it exists in the stack
      unless(grep({ $_ eq $name } @{ $self->{savepoints} })) {
          $self->throw_exception("Savepoint '$name' does not exist!");
      }

      # Dig through the stack until we find the one we are releasing.  This keeps
      # the stack up to date.
      while(my $s = pop(@{ $self->{savepoints} })) {
          last if($s eq $name);
      }
      # Add the savepoint back to the stack, as a rollback doesn't remove the
      # named savepoint, only everything after it.
      push(@{ $self->{savepoints} }, $name);
  } else {
      # We'll assume they want to rollback to the last savepoint
      $name = $self->{savepoints}->[-1];
  }

  $self->debugobj->svp_rollback($name) if $self->debug;

  return $self->_svp_rollback($name);
}

sub _svp_generate_name {
    my ($self) = @_;

    return 'savepoint_'.scalar(@{ $self->{'savepoints'} });
}

sub txn_begin {
  my $self = shift;
  if($self->{transaction_depth} == 0) {
    $self->debugobj->txn_begin()
      if $self->debug;
    $self->_dbh_begin_work;
  }
  elsif ($self->auto_savepoint) {
    $self->svp_begin;
  }
  $self->{transaction_depth}++;
}

sub _dbh_begin_work {
  my $self = shift;

  # if the user is utilizing txn_do - good for him, otherwise we need to
  # ensure that the $dbh is healthy on BEGIN.
  # We do this via ->dbh_do instead of ->dbh, so that the ->dbh "ping"
  # will be replaced by a failure of begin_work itself (which will be
  # then retried on reconnect)
  if ($self->{_in_dbh_do}) {
    $self->_dbh->begin_work;
  } else {
    $self->dbh_do(sub { $_[1]->begin_work });
  }
}

sub txn_commit {
  my $self = shift;
  if ($self->{transaction_depth} == 1) {
    my $dbh = $self->_dbh;
    $self->debugobj->txn_commit()
      if ($self->debug);
    $self->_dbh_commit;
    $self->{transaction_depth} = 0
      if $self->_dbh_autocommit;
  }
  elsif($self->{transaction_depth} > 1) {
    $self->{transaction_depth}--;
    $self->svp_release
      if $self->auto_savepoint;
  }
}

sub _dbh_commit {
  my $self = shift;
  $self->_dbh->commit;
}

sub txn_rollback {
  my $self = shift;
  my $dbh = $self->_dbh;
  eval {
    if ($self->{transaction_depth} == 1) {
      $self->debugobj->txn_rollback()
        if ($self->debug);
      $self->{transaction_depth} = 0
        if $self->_dbh_autocommit;
      $self->_dbh_rollback;
    }
    elsif($self->{transaction_depth} > 1) {
      $self->{transaction_depth}--;
      if ($self->auto_savepoint) {
        $self->svp_rollback;
        $self->svp_release;
      }
    }
    else {
      die DBIx::Class::Storage::NESTED_ROLLBACK_EXCEPTION->new;
    }
  };
  if ($@) {
    my $error = $@;
    my $exception_class = "DBIx::Class::Storage::NESTED_ROLLBACK_EXCEPTION";
    $error =~ /$exception_class/ and $self->throw_exception($error);
    # ensure that a failed rollback resets the transaction depth
    $self->{transaction_depth} = $self->_dbh_autocommit ? 0 : 1;
    $self->throw_exception($error);
  }
}

sub _dbh_rollback {
  my $self = shift;
  $self->_dbh->rollback;
}

# This used to be the top-half of _execute.  It was split out to make it
#  easier to override in NoBindVars without duping the rest.  It takes up
#  all of _execute's args, and emits $sql, @bind.
sub _prep_for_execute {
  my ($self, $op, $extra_bind, $ident, $args) = @_;

  if( Scalar::Util::blessed($ident) && $ident->isa("DBIx::Class::ResultSource") ) {
    $ident = $ident->from();
  }

  my ($sql, @bind) = $self->sql_maker->$op($ident, @$args);

  unshift(@bind,
    map { ref $_ eq 'ARRAY' ? $_ : [ '!!dummy', $_ ] } @$extra_bind)
      if $extra_bind;
  return ($sql, \@bind);
}


sub _fix_bind_params {
    my ($self, @bind) = @_;

    ### Turn @bind from something like this:
    ###   ( [ "artist", 1 ], [ "cdid", 1, 3 ] )
    ### to this:
    ###   ( "'1'", "'1'", "'3'" )
    return
        map {
            if ( defined( $_ && $_->[1] ) ) {
                map { qq{'$_'}; } @{$_}[ 1 .. $#$_ ];
            }
            else { q{'NULL'}; }
        } @bind;
}

sub _query_start {
    my ( $self, $sql, @bind ) = @_;

    if ( $self->debug ) {
        @bind = $self->_fix_bind_params(@bind);

        $self->debugobj->query_start( $sql, @bind );
    }
}

sub _query_end {
    my ( $self, $sql, @bind ) = @_;

    if ( $self->debug ) {
        @bind = $self->_fix_bind_params(@bind);
        $self->debugobj->query_end( $sql, @bind );
    }
}

sub _dbh_execute {
  my ($self, $dbh, $op, $extra_bind, $ident, $bind_attributes, @args) = @_;

  my ($sql, $bind) = $self->_prep_for_execute($op, $extra_bind, $ident, \@args);

  $self->_query_start( $sql, @$bind );

  my $sth = $self->sth($sql,$op);

  my $placeholder_index = 1;

  foreach my $bound (@$bind) {
    my $attributes = {};
    my($column_name, @data) = @$bound;

    if ($bind_attributes) {
      $attributes = $bind_attributes->{$column_name}
      if defined $bind_attributes->{$column_name};
    }

    foreach my $data (@data) {
      my $ref = ref $data;
      $data = $ref && $ref ne 'ARRAY' ? ''.$data : $data; # stringify args (except arrayrefs)

      $sth->bind_param($placeholder_index, $data, $attributes);
      $placeholder_index++;
    }
  }

  # Can this fail without throwing an exception anyways???
  my $rv = $sth->execute();
  $self->throw_exception($sth->errstr) if !$rv;

  $self->_query_end( $sql, @$bind );

  return (wantarray ? ($rv, $sth, @$bind) : $rv);
}

sub _execute {
    my $self = shift;
    $self->dbh_do('_dbh_execute', @_);  # retry over disconnects
}

sub insert {
  my ($self, $source, $to_insert) = @_;

# redispatch to insert method of storage we reblessed into, if necessary
  if (not $self->_driver_determined) {
    $self->_determine_driver;
    goto $self->can('insert');
  }

  my $ident = $source->from;
  my $bind_attributes = $self->source_bind_attributes($source);

  my $updated_cols = {};

  foreach my $col ( $source->columns ) {
    if ( !defined $to_insert->{$col} ) {
      my $col_info = $source->column_info($col);

      if ( $col_info->{auto_nextval} ) {
        $updated_cols->{$col} = $to_insert->{$col} = $self->_sequence_fetch(
          'nextval',
          $col_info->{sequence} ||
            $self->_dbh_get_autoinc_seq($self->_get_dbh, $source)
        );
      }
    }
  }

  $self->_execute('insert' => [], $source, $bind_attributes, $to_insert);

  return $updated_cols;
}

## Still not quite perfect, and EXPERIMENTAL
## Currently it is assumed that all values passed will be "normal", i.e. not
## scalar refs, or at least, all the same type as the first set, the statement is
## only prepped once.
sub insert_bulk {
  my ($self, $source, $cols, $data) = @_;

# redispatch to insert_bulk method of storage we reblessed into, if necessary
  if (not $self->_driver_determined) {
    $self->_determine_driver;
    goto $self->can('insert_bulk');
  }

  my %colvalues;
  my $table = $source->from;
  @colvalues{@$cols} = (0..$#$cols);
  my ($sql, @bind) = $self->sql_maker->insert($table, \%colvalues);

  $self->_query_start( $sql, @bind );
  my $sth = $self->sth($sql);

#  @bind = map { ref $_ ? ''.$_ : $_ } @bind; # stringify args

  ## This must be an arrayref, else nothing works!
  my $tuple_status = [];

  ## Get the bind_attributes, if any exist
  my $bind_attributes = $self->source_bind_attributes($source);

  ## Bind the values and execute
  my $placeholder_index = 1;

  foreach my $bound (@bind) {

    my $attributes = {};
    my ($column_name, $data_index) = @$bound;

    if( $bind_attributes ) {
      $attributes = $bind_attributes->{$column_name}
      if defined $bind_attributes->{$column_name};
    }

    my @data = map { $_->[$data_index] } @$data;

    $sth->bind_param_array( $placeholder_index, [@data], $attributes );
    $placeholder_index++;
  }
  my $rv = eval { $sth->execute_array({ArrayTupleStatus => $tuple_status}) };
  if (my $err = $@) {
    my $i = 0;
    ++$i while $i <= $#$tuple_status && !ref $tuple_status->[$i];

    $self->throw_exception($sth->errstr || "Unexpected populate error: $err")
      if ($i > $#$tuple_status);

    require Data::Dumper;
    local $Data::Dumper::Terse = 1;
    local $Data::Dumper::Indent = 1;
    local $Data::Dumper::Useqq = 1;
    local $Data::Dumper::Quotekeys = 0;
    local $Data::Dumper::Sortkeys = 1;

    $self->throw_exception(sprintf "%s for populate slice:\n%s",
      $tuple_status->[$i][1],
      Data::Dumper::Dumper(
        { map { $cols->[$_] => $data->[$i][$_] } (0 .. $#$cols) }
      ),
    );
  }
  $self->throw_exception($sth->errstr) if !$rv;

  $self->_query_end( $sql, @bind );
  return (wantarray ? ($rv, $sth, @bind) : $rv);
}

sub update {
  my ($self, $source, @args) = @_; 

# redispatch to update method of storage we reblessed into, if necessary
  if (not $self->_driver_determined) {
    $self->_determine_driver;
    goto $self->can('update');
  }

  my $bind_attributes = $self->source_bind_attributes($source);

  return $self->_execute('update' => [], $source, $bind_attributes, @args);
}


sub delete {
  my $self = shift @_;
  my $source = shift @_;
  $self->_determine_driver;
  my $bind_attrs = $self->source_bind_attributes($source);

  return $self->_execute('delete' => [], $source, $bind_attrs, @_);
}

# We were sent here because the $rs contains a complex search
# which will require a subquery to select the correct rows
# (i.e. joined or limited resultsets)
#
# Genarating a single PK column subquery is trivial and supported
# by all RDBMS. However if we have a multicolumn PK, things get ugly.
# Look at _multipk_update_delete()
sub _subq_update_delete {
  my $self = shift;
  my ($rs, $op, $values) = @_;

  my $rsrc = $rs->result_source;

  # we already check this, but double check naively just in case. Should be removed soon
  my $sel = $rs->_resolved_attrs->{select};
  $sel = [ $sel ] unless ref $sel eq 'ARRAY';
  my @pcols = $rsrc->primary_columns;
  if (@$sel != @pcols) {
    $self->throw_exception (
      'Subquery update/delete can not be called on resultsets selecting a'
     .' number of columns different than the number of primary keys'
    );
  }

  if (@pcols == 1) {
    return $self->$op (
      $rsrc,
      $op eq 'update' ? $values : (),
      { $pcols[0] => { -in => $rs->as_query } },
    );
  }

  else {
    return $self->_multipk_update_delete (@_);
  }
}

# ANSI SQL does not provide a reliable way to perform a multicol-PK
# resultset update/delete involving subqueries. So by default resort
# to simple (and inefficient) delete_all style per-row opearations,
# while allowing specific storages to override this with a faster
# implementation.
#
sub _multipk_update_delete {
  return shift->_per_row_update_delete (@_);
}

# This is the default loop used to delete/update rows for multi PK
# resultsets, and used by mysql exclusively (because it can't do anything
# else).
#
# We do not use $row->$op style queries, because resultset update/delete
# is not expected to cascade (this is what delete_all/update_all is for).
#
# There should be no race conditions as the entire operation is rolled
# in a transaction.
#
sub _per_row_update_delete {
  my $self = shift;
  my ($rs, $op, $values) = @_;

  my $rsrc = $rs->result_source;
  my @pcols = $rsrc->primary_columns;

  my $guard = $self->txn_scope_guard;

  # emulate the return value of $sth->execute for non-selects
  my $row_cnt = '0E0';

  my $subrs_cur = $rs->cursor;
  while (my @pks = $subrs_cur->next) {

    my $cond;
    for my $i (0.. $#pcols) {
      $cond->{$pcols[$i]} = $pks[$i];
    }

    $self->$op (
      $rsrc,
      $op eq 'update' ? $values : (),
      $cond,
    );

    $row_cnt++;
  }

  $guard->commit;

  return $row_cnt;
}

sub _select {
  my $self = shift;

  # localization is neccessary as
  # 1) there is no infrastructure to pass this around before SQLA2
  # 2) _select_args sets it and _prep_for_execute consumes it
  my $sql_maker = $self->sql_maker;
  local $sql_maker->{_dbic_rs_attrs};

  return $self->_execute($self->_select_args(@_));
}

sub _select_args_to_query {
  my $self = shift;

  # localization is neccessary as
  # 1) there is no infrastructure to pass this around before SQLA2
  # 2) _select_args sets it and _prep_for_execute consumes it
  my $sql_maker = $self->sql_maker;
  local $sql_maker->{_dbic_rs_attrs};

  # my ($op, $bind, $ident, $bind_attrs, $select, $cond, $order, $rows, $offset)
  #  = $self->_select_args($ident, $select, $cond, $attrs);
  my ($op, $bind, $ident, $bind_attrs, @args) =
    $self->_select_args(@_);

  # my ($sql, $prepared_bind) = $self->_prep_for_execute($op, $bind, $ident, [ $select, $cond, $order, $rows, $offset ]);
  my ($sql, $prepared_bind) = $self->_prep_for_execute($op, $bind, $ident, \@args);
  $prepared_bind ||= [];

  return wantarray
    ? ($sql, $prepared_bind, $bind_attrs)
    : \[ "($sql)", @$prepared_bind ]
  ;
}

sub _select_args {
  my ($self, $ident, $select, $where, $attrs) = @_;

  my ($alias2source, $rs_alias) = $self->_resolve_ident_sources ($ident);

  my $sql_maker = $self->sql_maker;
  $sql_maker->{_dbic_rs_attrs} = {
    %$attrs,
    select => $select,
    from => $ident,
    where => $where,
    $rs_alias
      ? ( _source_handle => $alias2source->{$rs_alias}->handle )
      : ()
    ,
  };

  # calculate bind_attrs before possible $ident mangling
  my $bind_attrs = {};
  for my $alias (keys %$alias2source) {
    my $bindtypes = $self->source_bind_attributes ($alias2source->{$alias}) || {};
    for my $col (keys %$bindtypes) {

      my $fqcn = join ('.', $alias, $col);
      $bind_attrs->{$fqcn} = $bindtypes->{$col} if $bindtypes->{$col};

      # Unqialified column names are nice, but at the same time can be
      # rather ambiguous. What we do here is basically go along with
      # the loop, adding an unqualified column slot to $bind_attrs,
      # alongside the fully qualified name. As soon as we encounter
      # another column by that name (which would imply another table)
      # we unset the unqualified slot and never add any info to it
      # to avoid erroneous type binding. If this happens the users
      # only choice will be to fully qualify his column name

      if (exists $bind_attrs->{$col}) {
        $bind_attrs->{$col} = {};
      }
      else {
        $bind_attrs->{$col} = $bind_attrs->{$fqcn};
      }
    }
  }

  # adjust limits
  if (
    $attrs->{software_limit}
      ||
    $sql_maker->_default_limit_syntax eq "GenericSubQ"
  ) {
    $attrs->{software_limit} = 1;
  }
  else {
    $self->throw_exception("rows attribute must be positive if present")
      if (defined($attrs->{rows}) && !($attrs->{rows} > 0));

    # MySQL actually recommends this approach.  I cringe.
    $attrs->{rows} = 2**48 if not defined $attrs->{rows} and defined $attrs->{offset};
  }

  my @limit;

  # see if we need to tear the prefetch apart (either limited has_many or grouped prefetch)
  # otherwise delegate the limiting to the storage, unless software limit was requested
  if (
    ( $attrs->{rows} && keys %{$attrs->{collapse}} )
       ||
    ( $attrs->{group_by} && @{$attrs->{group_by}} &&
      $attrs->{_prefetch_select} && @{$attrs->{_prefetch_select}} )
  ) {
    ($ident, $select, $where, $attrs)
      = $self->_adjust_select_args_for_complex_prefetch ($ident, $select, $where, $attrs);
  }
  elsif (! $attrs->{software_limit} ) {
    push @limit, $attrs->{rows}, $attrs->{offset};
  }

###
  # This would be the point to deflate anything found in $where
  # (and leave $attrs->{bind} intact). Problem is - inflators historically
  # expect a row object. And all we have is a resultsource (it is trivial
  # to extract deflator coderefs via $alias2source above).
  #
  # I don't see a way forward other than changing the way deflators are
  # invoked, and that's just bad...
###

  my $order = { map
    { $attrs->{$_} ? ( $_ => $attrs->{$_} ) : ()  }
    (qw/order_by group_by having/ )
  };

  return ('select', $attrs->{bind}, $ident, $bind_attrs, $select, $where, $order, @limit);
}

#
# This is the code producing joined subqueries like:
# SELECT me.*, other.* FROM ( SELECT me.* FROM ... ) JOIN other ON ... 
#
sub _adjust_select_args_for_complex_prefetch {
  my ($self, $from, $select, $where, $attrs) = @_;

  $self->throw_exception ('Nothing to prefetch... how did we get here?!')
    if not @{$attrs->{_prefetch_select}};

  $self->throw_exception ('Complex prefetches are not supported on resultsets with a custom from attribute')
    if (ref $from ne 'ARRAY' || ref $from->[0] ne 'HASH' || ref $from->[1] ne 'ARRAY');


  # generate inner/outer attribute lists, remove stuff that doesn't apply
  my $outer_attrs = { %$attrs };
  delete $outer_attrs->{$_} for qw/where bind rows offset group_by having/;

  my $inner_attrs = { %$attrs };
  delete $inner_attrs->{$_} for qw/for collapse _prefetch_select _collapse_order_by select as/;


  # bring over all non-collapse-induced order_by into the inner query (if any)
  # the outer one will have to keep them all
  delete $inner_attrs->{order_by};
  if (my $ord_cnt = @{$outer_attrs->{order_by}} - @{$outer_attrs->{_collapse_order_by}} ) {
    $inner_attrs->{order_by} = [
      @{$outer_attrs->{order_by}}[ 0 .. $ord_cnt - 1]
    ];
  }


  # generate the inner/outer select lists
  # for inside we consider only stuff *not* brought in by the prefetch
  # on the outside we substitute any function for its alias
  my $outer_select = [ @$select ];
  my $inner_select = [];
  for my $i (0 .. ( @$outer_select - @{$outer_attrs->{_prefetch_select}} - 1) ) {
    my $sel = $outer_select->[$i];

    if (ref $sel eq 'HASH' ) {
      $sel->{-as} ||= $attrs->{as}[$i];
      $outer_select->[$i] = join ('.', $attrs->{alias}, ($sel->{-as} || "inner_column_$i") );
    }

    push @$inner_select, $sel;
  }

  # normalize a copy of $from, so it will be easier to work with further
  # down (i.e. promote the initial hashref to an AoH)
  $from = [ @$from ];
  $from->[0] = [ $from->[0] ];
  my %original_join_info = map { $_->[0]{-alias} => $_->[0] } (@$from);


  # decide which parts of the join will remain in either part of
  # the outer/inner query

  # First we compose a list of which aliases are used in restrictions
  # (i.e. conditions/order/grouping/etc). Since we do not have
  # introspectable SQLA, we fall back to ugly scanning of raw SQL for
  # WHERE, and for pieces of ORDER BY in order to determine which aliases
  # need to appear in the resulting sql.
  # It may not be very efficient, but it's a reasonable stop-gap
  # Also unqualified column names will not be considered, but more often
  # than not this is actually ok
  #
  # In the same loop we enumerate part of the selection aliases, as
  # it requires the same sqla hack for the time being
  my ($restrict_aliases, $select_aliases, $prefetch_aliases);
  {
    # produce stuff unquoted, so it can be scanned
    my $sql_maker = $self->sql_maker;
    local $sql_maker->{quote_char};
    my $sep = $self->_sql_maker_opts->{name_sep} || '.';
    $sep = "\Q$sep\E";

    my $non_prefetch_select_sql = $sql_maker->_recurse_fields ($inner_select);
    my $prefetch_select_sql = $sql_maker->_recurse_fields ($outer_attrs->{_prefetch_select});
    my $where_sql = $sql_maker->where ($where);
    my $group_by_sql = $sql_maker->_order_by({
      map { $_ => $inner_attrs->{$_} } qw/group_by having/
    });
    my @non_prefetch_order_by_chunks = (map
      { ref $_ ? $_->[0] : $_ }
      $sql_maker->_order_by_chunks ($inner_attrs->{order_by})
    );


    for my $alias (keys %original_join_info) {
      my $seen_re = qr/\b $alias $sep/x;

      for my $piece ($where_sql, $group_by_sql, @non_prefetch_order_by_chunks ) {
        if ($piece =~ $seen_re) {
          $restrict_aliases->{$alias} = 1;
        }
      }

      if ($non_prefetch_select_sql =~ $seen_re) {
          $select_aliases->{$alias} = 1;
      }

      if ($prefetch_select_sql =~ $seen_re) {
          $prefetch_aliases->{$alias} = 1;
      }

    }
  }

  # Add any non-left joins to the restriction list (such joins are indeed restrictions)
  for my $j (values %original_join_info) {
    my $alias = $j->{-alias} or next;
    $restrict_aliases->{$alias} = 1 if (
      (not $j->{-join_type})
        or
      ($j->{-join_type} !~ /^left (?: \s+ outer)? $/xi)
    );
  }

  # mark all join parents as mentioned
  # (e.g.  join => { cds => 'tracks' } - tracks will need to bring cds too )
  for my $collection ($restrict_aliases, $select_aliases) {
    for my $alias (keys %$collection) {
      $collection->{$_} = 1
        for (@{ $original_join_info{$alias}{-join_path} || [] });
    }
  }

  # construct the inner $from for the subquery
  my %inner_joins = (map { %{$_ || {}} } ($restrict_aliases, $select_aliases) );
  my @inner_from;
  for my $j (@$from) {
    push @inner_from, $j if $inner_joins{$j->[0]{-alias}};
  }

  # if a multi-type join was needed in the subquery ("multi" is indicated by
  # presence in {collapse}) - add a group_by to simulate the collapse in the subq
  unless ($inner_attrs->{group_by}) {
    for my $alias (keys %inner_joins) {

      # the dot comes from some weirdness in collapse
      # remove after the rewrite
      if ($attrs->{collapse}{".$alias"}) {
        $inner_attrs->{group_by} ||= $inner_select;
        last;
      }
    }
  }

  # demote the inner_from head
  $inner_from[0] = $inner_from[0][0];

  # generate the subquery
  my $subq = $self->_select_args_to_query (
    \@inner_from,
    $inner_select,
    $where,
    $inner_attrs,
  );

  my $subq_joinspec = {
    -alias => $attrs->{alias},
    -source_handle => $inner_from[0]{-source_handle},
    $attrs->{alias} => $subq,
  };

  # Generate the outer from - this is relatively easy (really just replace
  # the join slot with the subquery), with a major caveat - we can not
  # join anything that is non-selecting (not part of the prefetch), but at
  # the same time is a multi-type relationship, as it will explode the result.
  #
  # There are two possibilities here
  # - either the join is non-restricting, in which case we simply throw it away
  # - it is part of the restrictions, in which case we need to collapse the outer
  #   result by tackling yet another group_by to the outside of the query

  # so first generate the outer_from, up to the substitution point
  my @outer_from;
  while (my $j = shift @$from) {
    if ($j->[0]{-alias} eq $attrs->{alias}) { # time to swap
      push @outer_from, [
        $subq_joinspec,
        @{$j}[1 .. $#$j],
      ];
      last; # we'll take care of what's left in $from below
    }
    else {
      push @outer_from, $j;
    }
  }

  # see what's left - throw away if not selecting/restricting
  # also throw in a group_by if restricting to guard against
  # cross-join explosions
  #
  while (my $j = shift @$from) {
    my $alias = $j->[0]{-alias};

    if ($select_aliases->{$alias} || $prefetch_aliases->{$alias}) {
      push @outer_from, $j;
    }
    elsif ($restrict_aliases->{$alias}) {
      push @outer_from, $j;

      # FIXME - this should be obviated by SQLA2, as I'll be able to 
      # have restrict_inner and restrict_outer... or something to that
      # effect... I think...

      # FIXME2 - I can't find a clean way to determine if a particular join
      # is a multi - instead I am just treating everything as a potential
      # explosive join (ribasushi)
      #
      # if (my $handle = $j->[0]{-source_handle}) {
      #   my $rsrc = $handle->resolve;
      #   ... need to bail out of the following if this is not a multi,
      #       as it will be much easier on the db ...

          $outer_attrs->{group_by} ||= $outer_select;
      # }
    }
  }

  # demote the outer_from head
  $outer_from[0] = $outer_from[0][0];

  # This is totally horrific - the $where ends up in both the inner and outer query
  # Unfortunately not much can be done until SQLA2 introspection arrives, and even
  # then if where conditions apply to the *right* side of the prefetch, you may have
  # to both filter the inner select (e.g. to apply a limit) and then have to re-filter
  # the outer select to exclude joins you didin't want in the first place
  #
  # OTOH it can be seen as a plus: <ash> (notes that this query would make a DBA cry ;)
  return (\@outer_from, $outer_select, $where, $outer_attrs);
}

sub _resolve_ident_sources {
  my ($self, $ident) = @_;

  my $alias2source = {};
  my $rs_alias;

  # the reason this is so contrived is that $ident may be a {from}
  # structure, specifying multiple tables to join
  if ( Scalar::Util::blessed($ident) && $ident->isa("DBIx::Class::ResultSource") ) {
    # this is compat mode for insert/update/delete which do not deal with aliases
    $alias2source->{me} = $ident;
    $rs_alias = 'me';
  }
  elsif (ref $ident eq 'ARRAY') {

    for (@$ident) {
      my $tabinfo;
      if (ref $_ eq 'HASH') {
        $tabinfo = $_;
        $rs_alias = $tabinfo->{-alias};
      }
      if (ref $_ eq 'ARRAY' and ref $_->[0] eq 'HASH') {
        $tabinfo = $_->[0];
      }

      $alias2source->{$tabinfo->{-alias}} = $tabinfo->{-source_handle}->resolve
        if ($tabinfo->{-source_handle});
    }
  }

  return ($alias2source, $rs_alias);
}

# Takes $ident, \@column_names
#
# returns { $column_name => \%column_info, ... }
# also note: this adds -result_source => $rsrc to the column info
#
# usage:
#   my $col_sources = $self->_resolve_column_info($ident, @column_names);
sub _resolve_column_info {
  my ($self, $ident, $colnames) = @_;
  my ($alias2src, $root_alias) = $self->_resolve_ident_sources($ident);

  my $sep = $self->_sql_maker_opts->{name_sep} || '.';
  $sep = "\Q$sep\E";

  my (%return, %seen_cols);

  # compile a global list of column names, to be able to properly
  # disambiguate unqualified column names (if at all possible)
  for my $alias (keys %$alias2src) {
    my $rsrc = $alias2src->{$alias};
    for my $colname ($rsrc->columns) {
      push @{$seen_cols{$colname}}, $alias;
    }
  }

  COLUMN:
  foreach my $col (@$colnames) {
    my ($alias, $colname) = $col =~ m/^ (?: ([^$sep]+) $sep)? (.+) $/x;

    unless ($alias) {
      # see if the column was seen exactly once (so we know which rsrc it came from)
      if ($seen_cols{$colname} and @{$seen_cols{$colname}} == 1) {
        $alias = $seen_cols{$colname}[0];
      }
      else {
        next COLUMN;
      }
    }

    my $rsrc = $alias2src->{$alias};
    $return{$col} = $rsrc && {
      %{$rsrc->column_info($colname)},
      -result_source => $rsrc,
      -source_alias => $alias,
    };
  }

  return \%return;
}

# Returns a counting SELECT for a simple count
# query. Abstracted so that a storage could override
# this to { count => 'firstcol' } or whatever makes
# sense as a performance optimization
sub _count_select {
  #my ($self, $source, $rs_attrs) = @_;
  return { count => '*' };
}

# Returns a SELECT which will end up in the subselect
# There may or may not be a group_by, as the subquery
# might have been called to accomodate a limit
#
# Most databases would be happy with whatever ends up
# here, but some choke in various ways.
#
sub _subq_count_select {
  my ($self, $source, $rs_attrs) = @_;
  return $rs_attrs->{group_by} if $rs_attrs->{group_by};

  my @pcols = map { join '.', $rs_attrs->{alias}, $_ } ($source->primary_columns);
  return @pcols ? \@pcols : [ 1 ];
}


sub source_bind_attributes {
  my ($self, $source) = @_;

  my $bind_attributes;
  foreach my $column ($source->columns) {

    my $data_type = $source->column_info($column)->{data_type} || '';
    $bind_attributes->{$column} = $self->bind_attribute_by_data_type($data_type)
     if $data_type;
  }

  return $bind_attributes;
}

=head2 select

=over 4

=item Arguments: $ident, $select, $condition, $attrs

=back

Handle a SQL select statement.

=cut

sub select {
  my $self = shift;
  my ($ident, $select, $condition, $attrs) = @_;
  return $self->cursor_class->new($self, \@_, $attrs);
}

sub select_single {
  my $self = shift;
  my ($rv, $sth, @bind) = $self->_select(@_);
  my @row = $sth->fetchrow_array;
  my @nextrow = $sth->fetchrow_array if @row;
  if(@row && @nextrow) {
    carp "Query returned more than one row.  SQL that returns multiple rows is DEPRECATED for ->find and ->single";
  }
  # Need to call finish() to work round broken DBDs
  $sth->finish();
  return @row;
}

=head2 sth

=over 4

=item Arguments: $sql

=back

Returns a L<DBI> sth (statement handle) for the supplied SQL.

=cut

sub _dbh_sth {
  my ($self, $dbh, $sql) = @_;

  # 3 is the if_active parameter which avoids active sth re-use
  my $sth = $self->disable_sth_caching
    ? $dbh->prepare($sql)
    : $dbh->prepare_cached($sql, {}, 3);

  # XXX You would think RaiseError would make this impossible,
  #  but apparently that's not true :(
  $self->throw_exception($dbh->errstr) if !$sth;

  $sth;
}

sub sth {
  my ($self, $sql) = @_;
  $self->dbh_do('_dbh_sth', $sql);  # retry over disconnects
}

sub _dbh_columns_info_for {
  my ($self, $dbh, $table) = @_;

  if ($dbh->can('column_info')) {
    my %result;
    eval {
      my ($schema,$tab) = $table =~ /^(.+?)\.(.+)$/ ? ($1,$2) : (undef,$table);
      my $sth = $dbh->column_info( undef,$schema, $tab, '%' );
      $sth->execute();
      while ( my $info = $sth->fetchrow_hashref() ){
        my %column_info;
        $column_info{data_type}   = $info->{TYPE_NAME};
        $column_info{size}      = $info->{COLUMN_SIZE};
        $column_info{is_nullable}   = $info->{NULLABLE} ? 1 : 0;
        $column_info{default_value} = $info->{COLUMN_DEF};
        my $col_name = $info->{COLUMN_NAME};
        $col_name =~ s/^\"(.*)\"$/$1/;

        $result{$col_name} = \%column_info;
      }
    };
    return \%result if !$@ && scalar keys %result;
  }

  my %result;
  my $sth = $dbh->prepare($self->sql_maker->select($table, undef, \'1 = 0'));
  $sth->execute;
  my @columns = @{$sth->{NAME_lc}};
  for my $i ( 0 .. $#columns ){
    my %column_info;
    $column_info{data_type} = $sth->{TYPE}->[$i];
    $column_info{size} = $sth->{PRECISION}->[$i];
    $column_info{is_nullable} = $sth->{NULLABLE}->[$i] ? 1 : 0;

    if ($column_info{data_type} =~ m/^(.*?)\((.*?)\)$/) {
      $column_info{data_type} = $1;
      $column_info{size}    = $2;
    }

    $result{$columns[$i]} = \%column_info;
  }
  $sth->finish;

  foreach my $col (keys %result) {
    my $colinfo = $result{$col};
    my $type_num = $colinfo->{data_type};
    my $type_name;
    if(defined $type_num && $dbh->can('type_info')) {
      my $type_info = $dbh->type_info($type_num);
      $type_name = $type_info->{TYPE_NAME} if $type_info;
      $colinfo->{data_type} = $type_name if $type_name;
    }
  }

  return \%result;
}

sub columns_info_for {
  my ($self, $table) = @_;
  $self->_dbh_columns_info_for ($self->_get_dbh, $table);
}

=head2 last_insert_id

Return the row id of the last insert.

=cut

sub _dbh_last_insert_id {
    # All Storage's need to register their own _dbh_last_insert_id
    # the old SQLite-based method was highly inappropriate

    my $self = shift;
    my $class = ref $self;
    $self->throw_exception (<<EOE);

No _dbh_last_insert_id() method found in $class.
Since the method of obtaining the autoincrement id of the last insert
operation varies greatly between different databases, this method must be
individually implemented for every storage class.
EOE
}

sub last_insert_id {
  my $self = shift;
  $self->_dbh_last_insert_id ($self->_dbh, @_);
}

=head2 _native_data_type

=over 4

=item Arguments: $type_name

=back

This API is B<EXPERIMENTAL>, will almost definitely change in the future, and
currently only used by L<::AutoCast|DBIx::Class::Storage::DBI::AutoCast> and
L<::Sybase|DBIx::Class::Storage::DBI::Sybase>.

The default implementation returns C<undef>, implement in your Storage driver if
you need this functionality.

Should map types from other databases to the native RDBMS type, for example
C<VARCHAR2> to C<VARCHAR>.

Types with modifiers should map to the underlying data type. For example,
C<INTEGER AUTO_INCREMENT> should become C<INTEGER>.

Composite types should map to the container type, for example
C<ENUM(foo,bar,baz)> becomes C<ENUM>.

=cut

sub _native_data_type {
  #my ($self, $data_type) = @_;
  return undef
}

# Check if placeholders are supported at all
sub _placeholders_supported {
  my $self = shift;
  my $dbh  = $self->_get_dbh;

  # some drivers provide a $dbh attribute (e.g. Sybase and $dbh->{syb_dynamic_supported})
  # but it is inaccurate more often than not
  eval {
    local $dbh->{PrintError} = 0;
    local $dbh->{RaiseError} = 1;
    $dbh->do('select ?', {}, 1);
  };
  return $@ ? 0 : 1;
}

# Check if placeholders bound to non-string types throw exceptions
#
sub _typeless_placeholders_supported {
  my $self = shift;
  my $dbh  = $self->_get_dbh;

  eval {
    local $dbh->{PrintError} = 0;
    local $dbh->{RaiseError} = 1;
    # this specifically tests a bind that is NOT a string
    $dbh->do('select 1 where 1 = ?', {}, 1);
  };
  return $@ ? 0 : 1;
}

=head2 sqlt_type

Returns the database driver name.

=cut

sub sqlt_type {
  my ($self) = @_;

  if (not $self->_driver_determined) {
    $self->_determine_driver;
    goto $self->can ('sqlt_type');
  }

  $self->_get_dbh->{Driver}->{Name};
}

=head2 bind_attribute_by_data_type

Given a datatype from column info, returns a database specific bind
attribute for C<< $dbh->bind_param($val,$attribute) >> or nothing if we will
let the database planner just handle it.

Generally only needed for special case column types, like bytea in postgres.

=cut

sub bind_attribute_by_data_type {
    return;
}

=head2 is_datatype_numeric

Given a datatype from column_info, returns a boolean value indicating if
the current RDBMS considers it a numeric value. This controls how
L<DBIx::Class::Row/set_column> decides whether to mark the column as
dirty - when the datatype is deemed numeric a C<< != >> comparison will
be performed instead of the usual C<eq>.

=cut

sub is_datatype_numeric {
  my ($self, $dt) = @_;

  return 0 unless $dt;

  return $dt =~ /^ (?:
    numeric | int(?:eger)? | (?:tiny|small|medium|big)int | dec(?:imal)? | real | float | double (?: \s+ precision)? | (?:big)?serial
  ) $/ix;
}


=head2 create_ddl_dir (EXPERIMENTAL)

=over 4

=item Arguments: $schema \@databases, $version, $directory, $preversion, \%sqlt_args

=back

Creates a SQL file based on the Schema, for each of the specified
database engines in C<\@databases> in the given directory.
(note: specify L<SQL::Translator> names, not L<DBI> driver names).

Given a previous version number, this will also create a file containing
the ALTER TABLE statements to transform the previous schema into the
current one. Note that these statements may contain C<DROP TABLE> or
C<DROP COLUMN> statements that can potentially destroy data.

The file names are created using the C<ddl_filename> method below, please
override this method in your schema if you would like a different file
name format. For the ALTER file, the same format is used, replacing
$version in the name with "$preversion-$version".

See L<SQL::Translator/METHODS> for a list of values for C<\%sqlt_args>.
The most common value for this would be C<< { add_drop_table => 1 } >>
to have the SQL produced include a C<DROP TABLE> statement for each table
created. For quoting purposes supply C<quote_table_names> and
C<quote_field_names>.

If no arguments are passed, then the following default values are assumed:

=over 4

=item databases  - ['MySQL', 'SQLite', 'PostgreSQL']

=item version    - $schema->schema_version

=item directory  - './'

=item preversion - <none>

=back

By default, C<\%sqlt_args> will have

 { add_drop_table => 1, ignore_constraint_names => 1, ignore_index_names => 1 }

merged with the hash passed in. To disable any of those features, pass in a
hashref like the following

 { ignore_constraint_names => 0, # ... other options }


Note that this feature is currently EXPERIMENTAL and may not work correctly
across all databases, or fully handle complex relationships.

WARNING: Please check all SQL files created, before applying them.

=cut

sub create_ddl_dir {
  my ($self, $schema, $databases, $version, $dir, $preversion, $sqltargs) = @_;

  if(!$dir || !-d $dir) {
    carp "No directory given, using ./\n";
    $dir = "./";
  }
  $databases ||= ['MySQL', 'SQLite', 'PostgreSQL'];
  $databases = [ $databases ] if(ref($databases) ne 'ARRAY');

  my $schema_version = $schema->schema_version || '1.x';
  $version ||= $schema_version;

  $sqltargs = {
    add_drop_table => 1,
    ignore_constraint_names => 1,
    ignore_index_names => 1,
    %{$sqltargs || {}}
  };

  $self->throw_exception("Can't create a ddl file without SQL::Translator: " . $self->_sqlt_version_error)
    if !$self->_sqlt_version_ok;

  my $sqlt = SQL::Translator->new( $sqltargs );

  $sqlt->parser('SQL::Translator::Parser::DBIx::Class');
  my $sqlt_schema = $sqlt->translate({ data => $schema })
    or $self->throw_exception ($sqlt->error);

  foreach my $db (@$databases) {
    $sqlt->reset();
    $sqlt->{schema} = $sqlt_schema;
    $sqlt->producer($db);

    my $file;
    my $filename = $schema->ddl_filename($db, $version, $dir);
    if (-e $filename && ($version eq $schema_version )) {
      # if we are dumping the current version, overwrite the DDL
      carp "Overwriting existing DDL file - $filename";
      unlink($filename);
    }

    my $output = $sqlt->translate;
    if(!$output) {
      carp("Failed to translate to $db, skipping. (" . $sqlt->error . ")");
      next;
    }
    if(!open($file, ">$filename")) {
      $self->throw_exception("Can't open $filename for writing ($!)");
      next;
    }
    print $file $output;
    close($file);

    next unless ($preversion);

    require SQL::Translator::Diff;

    my $prefilename = $schema->ddl_filename($db, $preversion, $dir);
    if(!-e $prefilename) {
      carp("No previous schema file found ($prefilename)");
      next;
    }

    my $difffile = $schema->ddl_filename($db, $version, $dir, $preversion);
    if(-e $difffile) {
      carp("Overwriting existing diff file - $difffile");
      unlink($difffile);
    }

    my $source_schema;
    {
      my $t = SQL::Translator->new($sqltargs);
      $t->debug( 0 );
      $t->trace( 0 );

      $t->parser( $db )
        or $self->throw_exception ($t->error);

      my $out = $t->translate( $prefilename )
        or $self->throw_exception ($t->error);

      $source_schema = $t->schema;

      $source_schema->name( $prefilename )
        unless ( $source_schema->name );
    }

    # The "new" style of producers have sane normalization and can support
    # diffing a SQL file against a DBIC->SQLT schema. Old style ones don't
    # And we have to diff parsed SQL against parsed SQL.
    my $dest_schema = $sqlt_schema;

    unless ( "SQL::Translator::Producer::$db"->can('preprocess_schema') ) {
      my $t = SQL::Translator->new($sqltargs);
      $t->debug( 0 );
      $t->trace( 0 );

      $t->parser( $db )
        or $self->throw_exception ($t->error);

      my $out = $t->translate( $filename )
        or $self->throw_exception ($t->error);

      $dest_schema = $t->schema;

      $dest_schema->name( $filename )
        unless $dest_schema->name;
    }

    my $diff = SQL::Translator::Diff::schema_diff($source_schema, $db,
                                                  $dest_schema,   $db,
                                                  $sqltargs
                                                 );
    if(!open $file, ">$difffile") {
      $self->throw_exception("Can't write to $difffile ($!)");
      next;
    }
    print $file $diff;
    close($file);
  }
}

=head2 deployment_statements

=over 4

=item Arguments: $schema, $type, $version, $directory, $sqlt_args

=back

Returns the statements used by L</deploy> and L<DBIx::Class::Schema/deploy>.

The L<SQL::Translator> (not L<DBI>) database driver name can be explicitly
provided in C<$type>, otherwise the result of L</sqlt_type> is used as default.

C<$directory> is used to return statements from files in a previously created
L</create_ddl_dir> directory and is optional. The filenames are constructed
from L<DBIx::Class::Schema/ddl_filename>, the schema name and the C<$version>.

If no C<$directory> is specified then the statements are constructed on the
fly using L<SQL::Translator> and C<$version> is ignored.

See L<SQL::Translator/METHODS> for a list of values for C<$sqlt_args>.

=cut

sub deployment_statements {
  my ($self, $schema, $type, $version, $dir, $sqltargs) = @_;
  $type ||= $self->sqlt_type;
  $version ||= $schema->schema_version || '1.x';
  $dir ||= './';
  my $filename = $schema->ddl_filename($type, $version, $dir);
  if(-f $filename)
  {
      my $file;
      open($file, "<$filename")
        or $self->throw_exception("Can't open $filename ($!)");
      my @rows = <$file>;
      close($file);
      return join('', @rows);
  }

  $self->throw_exception("Can't deploy without either SQL::Translator or a ddl_dir: " . $self->_sqlt_version_error )
    if !$self->_sqlt_version_ok;

  # sources needs to be a parser arg, but for simplicty allow at top level
  # coming in
  $sqltargs->{parser_args}{sources} = delete $sqltargs->{sources}
      if exists $sqltargs->{sources};

  my $tr = SQL::Translator->new(
    producer => "SQL::Translator::Producer::${type}",
    %$sqltargs,
    parser => 'SQL::Translator::Parser::DBIx::Class',
    data => $schema,
  );
  return $tr->translate;
}

sub deploy {
  my ($self, $schema, $type, $sqltargs, $dir) = @_;
  my $deploy = sub {
    my $line = shift;
    return if($line =~ /^--/);
    return if(!$line);
    # next if($line =~ /^DROP/m);
    return if($line =~ /^BEGIN TRANSACTION/m);
    return if($line =~ /^COMMIT/m);
    return if $line =~ /^\s+$/; # skip whitespace only
    $self->_query_start($line);
    eval {
      # do a dbh_do cycle here, as we need some error checking in
      # place (even though we will ignore errors)
      $self->dbh_do (sub { $_[1]->do($line) });
    };
    if ($@) {
      carp qq{$@ (running "${line}")};
    }
    $self->_query_end($line);
  };
  my @statements = $self->deployment_statements($schema, $type, undef, $dir, { %{ $sqltargs || {} }, no_comments => 1 } );
  if (@statements > 1) {
    foreach my $statement (@statements) {
      $deploy->( $statement );
    }
  }
  elsif (@statements == 1) {
    foreach my $line ( split(";\n", $statements[0])) {
      $deploy->( $line );
    }
  }
}

=head2 datetime_parser

Returns the datetime parser class

=cut

sub datetime_parser {
  my $self = shift;
  return $self->{datetime_parser} ||= do {
    $self->build_datetime_parser(@_);
  };
}

=head2 datetime_parser_type

Defines (returns) the datetime parser class - currently hardwired to
L<DateTime::Format::MySQL>

=cut

sub datetime_parser_type { "DateTime::Format::MySQL"; }

=head2 build_datetime_parser

See L</datetime_parser>

=cut

sub build_datetime_parser {
  if (not $_[0]->_driver_determined) {
    $_[0]->_determine_driver;
    goto $_[0]->can('build_datetime_parser');
  }

  my $self = shift;
  my $type = $self->datetime_parser_type(@_);
  $self->ensure_class_loaded ($type);
  return $type;
}


=head2 is_replicating

A boolean that reports if a particular L<DBIx::Class::Storage::DBI> is set to
replicate from a master database.  Default is undef, which is the result
returned by databases that don't support replication.

=cut

sub is_replicating {
    return;

}

=head2 lag_behind_master

Returns a number that represents a certain amount of lag behind a master db
when a given storage is replicating.  The number is database dependent, but
starts at zero and increases with the amount of lag. Default in undef

=cut

sub lag_behind_master {
    return;
}

# SQLT version handling 
{
  my $_sqlt_version_ok;     # private 
  my $_sqlt_version_error;  # private 

  sub _sqlt_version_ok {
    if (!defined $_sqlt_version_ok) {
      eval "use SQL::Translator $minimum_sqlt_version";
      if ($@) {
        $_sqlt_version_ok = 0;
        $_sqlt_version_error = $@;
      }
      else {
        $_sqlt_version_ok = 1;
      }
    }
    return $_sqlt_version_ok;
  }

  sub _sqlt_version_error {
    shift->_sqlt_version_ok unless defined $_sqlt_version_ok;
    return $_sqlt_version_error;
  }

  sub _sqlt_minimum_version { $minimum_sqlt_version };
}

sub DESTROY {
  my $self = shift;

  $self->_verify_pid if $self->_dbh;

  # some databases need this to stop spewing warnings
  if (my $dbh = $self->_dbh) {
    local $@;
    eval { $dbh->disconnect };
  }

  $self->_dbh(undef);
}

1;

=head1 USAGE NOTES

=head2 DBIx::Class and AutoCommit

DBIx::Class can do some wonderful magic with handling exceptions,
disconnections, and transactions when you use C<< AutoCommit => 1 >>
(the default) combined with C<txn_do> for transaction support.

If you set C<< AutoCommit => 0 >> in your connect info, then you are always
in an assumed transaction between commits, and you're telling us you'd
like to manage that manually.  A lot of the magic protections offered by
this module will go away.  We can't protect you from exceptions due to database
disconnects because we don't know anything about how to restart your
transactions.  You're on your own for handling all sorts of exceptional
cases if you choose the C<< AutoCommit => 0 >> path, just as you would
be with raw DBI.


=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

Andy Grundman <andy@hybridized.org>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut
