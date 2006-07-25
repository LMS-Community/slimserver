package DBIx::Class::Storage::DBI;
# -*- mode: cperl; cperl-indent-level: 2 -*-

use base 'DBIx::Class::Storage';

use strict;
use warnings;
use DBI;
use SQL::Abstract::Limit;
use DBIx::Class::Storage::DBI::Cursor;
use DBIx::Class::Storage::Statistics;
use IO::File;
use Carp::Clan qw/DBIx::Class/;
BEGIN {

package DBIC::SQL::Abstract; # Would merge upstream, but nate doesn't reply :(

use base qw/SQL::Abstract::Limit/;

# This prevents the caching of $dbh in S::A::L, I believe
sub new {
  my $self = shift->SUPER::new(@_);

  # If limit_dialect is a ref (like a $dbh), go ahead and replace
  #   it with what it resolves to:
  $self->{limit_dialect} = $self->_find_syntax($self->{limit_dialect})
    if ref $self->{limit_dialect};

  $self;
}

# While we're at it, this should make LIMIT queries more efficient,
#  without digging into things too deeply
sub _find_syntax {
  my ($self, $syntax) = @_;
  $self->{_cached_syntax} ||= $self->SUPER::_find_syntax($syntax);
}

sub select {
  my ($self, $table, $fields, $where, $order, @rest) = @_;
  $table = $self->_quote($table) unless ref($table);
  local $self->{rownum_hack_count} = 1
    if (defined $rest[0] && $self->{limit_dialect} eq 'RowNum');
  @rest = (-1) unless defined $rest[0];
  die "LIMIT 0 Does Not Compute" if $rest[0] == 0;
    # and anyway, SQL::Abstract::Limit will cause a barf if we don't first
  local $self->{having_bind} = [];
  my ($sql, @ret) = $self->SUPER::select(
    $table, $self->_recurse_fields($fields), $where, $order, @rest
  );
  return wantarray ? ($sql, @ret, @{$self->{having_bind}}) : $sql;
}

sub insert {
  my $self = shift;
  my $table = shift;
  $table = $self->_quote($table) unless ref($table);
  $self->SUPER::insert($table, @_);
}

sub update {
  my $self = shift;
  my $table = shift;
  $table = $self->_quote($table) unless ref($table);
  $self->SUPER::update($table, @_);
}

sub delete {
  my $self = shift;
  my $table = shift;
  $table = $self->_quote($table) unless ref($table);
  $self->SUPER::delete($table, @_);
}

sub _emulate_limit {
  my $self = shift;
  if ($_[3] == -1) {
    return $_[1].$self->_order_by($_[2]);
  } else {
    return $self->SUPER::_emulate_limit(@_);
  }
}

sub _recurse_fields {
  my ($self, $fields) = @_;
  my $ref = ref $fields;
  return $self->_quote($fields) unless $ref;
  return $$fields if $ref eq 'SCALAR';

  if ($ref eq 'ARRAY') {
    return join(', ', map {
      $self->_recurse_fields($_)
      .(exists $self->{rownum_hack_count}
         ? ' AS col'.$self->{rownum_hack_count}++
         : '')
     } @$fields);
  } elsif ($ref eq 'HASH') {
    foreach my $func (keys %$fields) {
      return $self->_sqlcase($func)
        .'( '.$self->_recurse_fields($fields->{$func}).' )';
    }
  }
}

sub _order_by {
  my $self = shift;
  my $ret = '';
  my @extra;
  if (ref $_[0] eq 'HASH') {
    if (defined $_[0]->{group_by}) {
      $ret = $self->_sqlcase(' group by ')
               .$self->_recurse_fields($_[0]->{group_by});
    }
    if (defined $_[0]->{having}) {
      my $frag;
      ($frag, @extra) = $self->_recurse_where($_[0]->{having});
      push(@{$self->{having_bind}}, @extra);
      $ret .= $self->_sqlcase(' having ').$frag;
    }
    if (defined $_[0]->{order_by}) {
      $ret .= $self->_order_by($_[0]->{order_by});
    }
  } elsif (ref $_[0] eq 'SCALAR') {
    $ret = $self->_sqlcase(' order by ').${ $_[0] };
  } elsif (ref $_[0] eq 'ARRAY' && @{$_[0]}) {
    my @order = @{+shift};
    $ret = $self->_sqlcase(' order by ')
          .join(', ', map {
                        my $r = $self->_order_by($_, @_);
                        $r =~ s/^ ?ORDER BY //i;
                        $r;
                      } @order);
  } else {
    $ret = $self->SUPER::_order_by(@_);
  }
  return $ret;
}

sub _order_directions {
  my ($self, $order) = @_;
  $order = $order->{order_by} if ref $order eq 'HASH';
  return $self->SUPER::_order_directions($order);
}

sub _table {
  my ($self, $from) = @_;
  if (ref $from eq 'ARRAY') {
    return $self->_recurse_from(@$from);
  } elsif (ref $from eq 'HASH') {
    return $self->_make_as($from);
  } else {
    return $from; # would love to quote here but _table ends up getting called
                  # twice during an ->select without a limit clause due to
                  # the way S::A::Limit->select works. should maybe consider
                  # bypassing this and doing S::A::select($self, ...) in
                  # our select method above. meantime, quoting shims have
                  # been added to select/insert/update/delete here
  }
}

sub _recurse_from {
  my ($self, $from, @join) = @_;
  my @sqlf;
  push(@sqlf, $self->_make_as($from));
  foreach my $j (@join) {
    my ($to, $on) = @$j;

    # check whether a join type exists
    my $join_clause = '';
    my $to_jt = ref($to) eq 'ARRAY' ? $to->[0] : $to;
    if (ref($to_jt) eq 'HASH' and exists($to_jt->{-join_type})) {
      $join_clause = ' '.uc($to_jt->{-join_type}).' JOIN ';
    } else {
      $join_clause = ' JOIN ';
    }
    push(@sqlf, $join_clause);

    if (ref $to eq 'ARRAY') {
      push(@sqlf, '(', $self->_recurse_from(@$to), ')');
    } else {
      push(@sqlf, $self->_make_as($to));
    }
    push(@sqlf, ' ON ', $self->_join_condition($on));
  }
  return join('', @sqlf);
}

sub _make_as {
  my ($self, $from) = @_;
  return join(' ', map { (ref $_ eq 'SCALAR' ? $$_ : $self->_quote($_)) }
                     reverse each %{$self->_skip_options($from)});
}

sub _skip_options {
  my ($self, $hash) = @_;
  my $clean_hash = {};
  $clean_hash->{$_} = $hash->{$_}
    for grep {!/^-/} keys %$hash;
  return $clean_hash;
}

sub _join_condition {
  my ($self, $cond) = @_;
  if (ref $cond eq 'HASH') {
    my %j;
    for (keys %$cond) {
      my $x = '= '.$self->_quote($cond->{$_}); $j{$_} = \$x;
    };
    return $self->_recurse_where(\%j);
  } elsif (ref $cond eq 'ARRAY') {
    return join(' OR ', map { $self->_join_condition($_) } @$cond);
  } else {
    die "Can't handle this yet!";
  }
}

sub _quote {
  my ($self, $label) = @_;
  return '' unless defined $label;
  return "*" if $label eq '*';
  return $label unless $self->{quote_char};
  if(ref $self->{quote_char} eq "ARRAY"){
    return $self->{quote_char}->[0] . $label . $self->{quote_char}->[1]
      if !defined $self->{name_sep};
    my $sep = $self->{name_sep};
    return join($self->{name_sep},
        map { $self->{quote_char}->[0] . $_ . $self->{quote_char}->[1]  }
       split(/\Q$sep\E/,$label));
  }
  return $self->SUPER::_quote($label);
}

sub limit_dialect {
    my $self = shift;
    $self->{limit_dialect} = shift if @_;
    return $self->{limit_dialect};
}

sub quote_char {
    my $self = shift;
    $self->{quote_char} = shift if @_;
    return $self->{quote_char};
}

sub name_sep {
    my $self = shift;
    $self->{name_sep} = shift if @_;
    return $self->{name_sep};
}

} # End of BEGIN block

use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/AccessorGroup/);

__PACKAGE__->mk_group_accessors('simple' =>
  qw/_connect_info _dbh _sql_maker _sql_maker_opts _conn_pid _conn_tid
     debug debugobj cursor on_connect_do transaction_depth/);

=head1 NAME

DBIx::Class::Storage::DBI - DBI storage handler

=head1 SYNOPSIS

=head1 DESCRIPTION

This class represents the connection to the database

=head1 METHODS

=head2 new

=cut

sub new {
  my $new = bless({}, ref $_[0] || $_[0]);
  $new->cursor("DBIx::Class::Storage::DBI::Cursor");
  $new->transaction_depth(0);

  $new->debugobj(new DBIx::Class::Storage::Statistics());

  my $fh;

  my $debug_env = $ENV{DBIX_CLASS_STORAGE_DBI_DEBUG}
                  || $ENV{DBIC_TRACE};

  if (defined($debug_env) && ($debug_env =~ /=(.+)$/)) {
    $fh = IO::File->new($1, 'w')
      or $new->throw_exception("Cannot open trace file $1");
  } else {
    $fh = IO::File->new('>&STDERR');
  }
  $new->debugfh($fh);
  $new->debug(1) if $debug_env;
  $new->_sql_maker_opts({});
  return $new;
}

=head2 throw_exception

Throws an exception - croaks.

=cut

sub throw_exception {
  my ($self, $msg) = @_;
  croak($msg);
}

=head2 connect_info

The arguments of C<connect_info> are always a single array reference.

This is normally accessed via L<DBIx::Class::Schema/connection>, which
encapsulates its argument list in an arrayref before calling
C<connect_info> here.

The arrayref can either contain the same set of arguments one would
normally pass to L<DBI/connect>, or a lone code reference which returns
a connected database handle.

In either case, if the final argument in your connect_info happens
to be a hashref, C<connect_info> will look there for several
connection-specific options:

=over 4

=item on_connect_do

This can be set to an arrayref of literal sql statements, which will
be executed immediately after making the connection to the database
every time we [re-]connect.

=item limit_dialect 

Sets the limit dialect. This is useful for JDBC-bridge among others
where the remote SQL-dialect cannot be determined by the name of the
driver alone.

=item quote_char

Specifies what characters to use to quote table and column names. If 
you use this you will want to specify L<name_sep> as well.

quote_char expects either a single character, in which case is it is placed
on either side of the table/column, or an arrayref of length 2 in which case the
table/column name is placed between the elements.

For example under MySQL you'd use C<quote_char =E<gt> '`'>, and user SQL Server you'd 
use C<quote_char =E<gt> [qw/[ ]/]>.

=item name_sep

This only needs to be used in conjunction with L<quote_char>, and is used to 
specify the charecter that seperates elements (schemas, tables, columns) from 
each other. In most cases this is simply a C<.>.

=back

These options can be mixed in with your other L<DBI> connection attributes,
or placed in a seperate hashref after all other normal L<DBI> connection
arguments.

Every time C<connect_info> is invoked, any previous settings for
these options will be cleared before setting the new ones, regardless of
whether any options are specified in the new C<connect_info>.

Examples:

  # Simple SQLite connection
  ->connect_info([ 'dbi:SQLite:./foo.db' ]);

  # Connect via subref
  ->connect_info([ sub { DBI->connect(...) } ]);

  # A bit more complicated
  ->connect_info(
    [
      'dbi:Pg:dbname=foo',
      'postgres',
      'my_pg_password',
      { AutoCommit => 0 },
      { quote_char => q{"}, name_sep => q{.} },
    ]
  );

  # Equivalent to the previous example
  ->connect_info(
    [
      'dbi:Pg:dbname=foo',
      'postgres',
      'my_pg_password',
      { AutoCommit => 0, quote_char => q{"}, name_sep => q{.} },
    ]
  );

  # Subref + DBIC-specific connection options
  ->connect_info(
    [
      sub { DBI->connect(...) },
      {
          quote_char => q{`},
          name_sep => q{@},
          on_connect_do => ['SET search_path TO myschema,otherschema,public'],
      },
    ]
  );

=head2 on_connect_do

This method is deprecated in favor of setting via L</connect_info>.

=head2 debug

Causes SQL trace information to be emitted on the C<debugobj> object.
(or C<STDERR> if C<debugobj> has not specifically been set).

This is the equivalent to setting L</DBIC_TRACE> in your
shell environment.

=head2 debugfh

Set or retrieve the filehandle used for trace/debug output.  This should be
an IO::Handle compatible ojbect (only the C<print> method is used.  Initially
set to be STDERR - although see information on the
L<DBIC_TRACE> environment variable.

=cut

sub debugfh {
    my $self = shift;

    if ($self->debugobj->can('debugfh')) {
        return $self->debugobj->debugfh(@_);
    }
}

=head2 debugobj

Sets or retrieves the object used for metric collection. Defaults to an instance
of L<DBIx::Class::Storage::Statistics> that is campatible with the original
method of using a coderef as a callback.  See the aforementioned Statistics
class for more information.

=head2 debugcb

Sets a callback to be executed each time a statement is run; takes a sub
reference.  Callback is executed as $sub->($op, $info) where $op is
SELECT/INSERT/UPDATE/DELETE and $info is what would normally be printed.

See L<debugobj> for a better way.

=cut

sub debugcb {
    my $self = shift;

    if ($self->debugobj->can('callback')) {
        return $self->debugobj->callback(@_);
    }
}

=head2 disconnect

Disconnect the L<DBI> handle, performing a rollback first if the
database is not in C<AutoCommit> mode.

=cut

sub disconnect {
  my ($self) = @_;

  if( $self->connected ) {
    $self->_dbh->rollback unless $self->_dbh->{AutoCommit};
    $self->_dbh->disconnect;
    $self->_dbh(undef);
  }
}

=head2 connected

Check if the L<DBI> handle is connected.  Returns true if the handle
is connected.

=cut

sub connected { my ($self) = @_;

  if(my $dbh = $self->_dbh) {
      if(defined $self->_conn_tid && $self->_conn_tid != threads->tid) {
          return $self->_dbh(undef);
      }
      elsif($self->_conn_pid != $$) {
          $self->_dbh->{InactiveDestroy} = 1;
          return $self->_dbh(undef);
      }
      return ($dbh->FETCH('Active') && $dbh->ping);
  }

  return 0;
}

=head2 ensure_connected

Check whether the database handle is connected - if not then make a
connection.

=cut

sub ensure_connected {
  my ($self) = @_;

  unless ($self->connected) {
    $self->_populate_dbh;
  }
}

=head2 dbh

Returns the dbh - a data base handle of class L<DBI>.

=cut

sub dbh {
  my ($self) = @_;

  $self->ensure_connected;
  return $self->_dbh;
}

sub _sql_maker_args {
    my ($self) = @_;
    
    return ( limit_dialect => $self->dbh, %{$self->_sql_maker_opts} );
}

=head2 sql_maker

Returns a C<sql_maker> object - normally an object of class
C<DBIC::SQL::Abstract>.

=cut

sub sql_maker {
  my ($self) = @_;
  unless ($self->_sql_maker) {
    $self->_sql_maker(new DBIC::SQL::Abstract( $self->_sql_maker_args ));
  }
  return $self->_sql_maker;
}

sub connect_info {
  my ($self, $info_arg) = @_;

  if($info_arg) {
    # Kill sql_maker/_sql_maker_opts, so we get a fresh one with only
    #  the new set of options
    $self->_sql_maker(undef);
    $self->_sql_maker_opts({});

    my $info = [ @$info_arg ]; # copy because we can alter it
    my $last_info = $info->[-1];
    if(ref $last_info eq 'HASH') {
      if(my $on_connect_do = delete $last_info->{on_connect_do}) {
        $self->on_connect_do($on_connect_do);
      }
      for my $sql_maker_opt (qw/limit_dialect quote_char name_sep/) {
        if(my $opt_val = delete $last_info->{$sql_maker_opt}) {
          $self->_sql_maker_opts->{$sql_maker_opt} = $opt_val;
        }
      }

      # Get rid of any trailing empty hashref
      pop(@$info) if !keys %$last_info;
    }

    $self->_connect_info($info);
  }

  $self->_connect_info;
}

sub _populate_dbh {
  my ($self) = @_;
  my @info = @{$self->_connect_info || []};
  $self->_dbh($self->_connect(@info));

  if(ref $self eq 'DBIx::Class::Storage::DBI') {
    my $driver = $self->_dbh->{Driver}->{Name};
    if ($self->load_optional_class("DBIx::Class::Storage::DBI::${driver}")) {
      bless $self, "DBIx::Class::Storage::DBI::${driver}";
      $self->_rebless() if $self->can('_rebless');
    }
  }

  # if on-connect sql statements are given execute them
  foreach my $sql_statement (@{$self->on_connect_do || []}) {
    $self->debugobj->query_start($sql_statement) if $self->debug();
    $self->_dbh->do($sql_statement);
    $self->debugobj->query_end($sql_statement) if $self->debug();
  }

  $self->_conn_pid($$);
  $self->_conn_tid(threads->tid) if $INC{'threads.pm'};
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
    $dbh = ref $info[0] eq 'CODE'
         ? &{$info[0]}
         : DBI->connect(@info);
  };

  $DBI::connect_via = $old_connect_via if $old_connect_via;

  if (!$dbh || $@) {
    $self->throw_exception("DBI Connection failed: " . ($@ || $DBI::errstr));
  }

  $dbh;
}

=head2 txn_begin

Calls begin_work on the current dbh.

See L<DBIx::Class::Schema> for the txn_do() method, which allows for
an entire code block to be executed transactionally.

=cut

sub txn_begin {
  my $self = shift;
  if ($self->{transaction_depth}++ == 0) {
    my $dbh = $self->dbh;
    if ($dbh->{AutoCommit}) {
      $self->debugobj->txn_begin()
        if ($self->debug);
      $dbh->begin_work;
    }
  }
}

=head2 txn_commit

Issues a commit against the current dbh.

=cut

sub txn_commit {
  my $self = shift;
  my $dbh = $self->dbh;
  if ($self->{transaction_depth} == 0) {
    unless ($dbh->{AutoCommit}) {
      $self->debugobj->txn_commit()
        if ($self->debug);
      $dbh->commit;
    }
  }
  else {
    if (--$self->{transaction_depth} == 0) {
      $self->debugobj->txn_commit()
        if ($self->debug);
      $dbh->commit;
    }
  }
}

=head2 txn_rollback

Issues a rollback against the current dbh. A nested rollback will
throw a L<DBIx::Class::Storage::NESTED_ROLLBACK_EXCEPTION> exception,
which allows the rollback to propagate to the outermost transaction.

=cut

sub txn_rollback {
  my $self = shift;

  eval {
    my $dbh = $self->dbh;
    if ($self->{transaction_depth} == 0) {
      unless ($dbh->{AutoCommit}) {
        $self->debugobj->txn_rollback()
          if ($self->debug);
        $dbh->rollback;
      }
    }
    else {
      if (--$self->{transaction_depth} == 0) {
        $self->debugobj->txn_rollback()
          if ($self->debug);
        $dbh->rollback;
      }
      else {
        die DBIx::Class::Storage::NESTED_ROLLBACK_EXCEPTION->new;
      }
    }
  };

  if ($@) {
    my $error = $@;
    my $exception_class = "DBIx::Class::Storage::NESTED_ROLLBACK_EXCEPTION";
    $error =~ /$exception_class/ and $self->throw_exception($error);
    $self->{transaction_depth} = 0;          # ensure that a failed rollback
    $self->throw_exception($error);          # resets the transaction depth
  }
}

sub _execute {
  my ($self, $op, $extra_bind, $ident, @args) = @_;
  my ($sql, @bind) = $self->sql_maker->$op($ident, @args);
  unshift(@bind, @$extra_bind) if $extra_bind;
  if ($self->debug) {
      my @debug_bind = map { defined $_ ? qq{'$_'} : q{'NULL'} } @bind;
      $self->debugobj->query_start($sql, @debug_bind);
  }
  my $sth = eval { $self->sth($sql,$op) };

  if (!$sth || $@) {
    $self->throw_exception(
      'no sth generated via sql (' . ($@ || $self->_dbh->errstr) . "): $sql"
    );
  }
  @bind = map { ref $_ ? ''.$_ : $_ } @bind; # stringify args
  my $rv;
  if ($sth) {
    my $time = time();
    $rv = eval { $sth->execute(@bind) };

    if ($@ || !$rv) {
      $self->throw_exception("Error executing '$sql': ".($@ || $sth->errstr));
    }
  } else {
    $self->throw_exception("'$sql' did not generate a statement.");
  }
  if ($self->debug) {
      my @debug_bind = map { defined $_ ? qq{`$_'} : q{`NULL'} } @bind;
      $self->debugobj->query_end($sql, @debug_bind);
  }
  return (wantarray ? ($rv, $sth, @bind) : $rv);
}

sub insert {
  my ($self, $ident, $to_insert) = @_;
  $self->throw_exception(
    "Couldn't insert ".join(', ',
      map "$_ => $to_insert->{$_}", keys %$to_insert
    )." into ${ident}"
  ) unless ($self->_execute('insert' => [], $ident, $to_insert));
  return $to_insert;
}

sub update {
  return shift->_execute('update' => [], @_);
}

sub delete {
  return shift->_execute('delete' => [], @_);
}

sub _select {
  my ($self, $ident, $select, $condition, $attrs) = @_;
  my $order = $attrs->{order_by};
  if (ref $condition eq 'SCALAR') {
    $order = $1 if $$condition =~ s/ORDER BY (.*)$//i;
  }
  if (exists $attrs->{group_by} || $attrs->{having}) {
    $order = {
      group_by => $attrs->{group_by},
      having => $attrs->{having},
      ($order ? (order_by => $order) : ())
    };
  }
  my @args = ('select', $attrs->{bind}, $ident, $select, $condition, $order);
  if ($attrs->{software_limit} ||
      $self->sql_maker->_default_limit_syntax eq "GenericSubQ") {
        $attrs->{software_limit} = 1;
  } else {
    $self->throw_exception("rows attribute must be positive if present")
      if (defined($attrs->{rows}) && !($attrs->{rows} > 0));
    push @args, $attrs->{rows}, $attrs->{offset};
  }
  return $self->_execute(@args);
}

=head2 select

Handle a SQL select statement.

=cut

sub select {
  my $self = shift;
  my ($ident, $select, $condition, $attrs) = @_;
  return $self->cursor->new($self, \@_, $attrs);
}

=head2 select_single

Performs a select, fetch and return of data - handles a single row
only.

=cut

# Need to call finish() to work round broken DBDs

sub select_single {
  my $self = shift;
  my ($rv, $sth, @bind) = $self->_select(@_);
  my @row = $sth->fetchrow_array;
  $sth->finish();
  return @row;
}

=head2 sth

Returns a L<DBI> sth (statement handle) for the supplied SQL.

=cut

sub sth {
  my ($self, $sql) = @_;
  # 3 is the if_active parameter which avoids active sth re-use
  return $self->dbh->prepare_cached($sql, {}, 3);
}

=head2 columns_info_for

Returns database type info for a given table columns.

=cut

sub columns_info_for {
  my ($self, $table) = @_;

  my $dbh = $self->dbh;

  if ($dbh->can('column_info')) {
    my %result;
    my $old_raise_err = $dbh->{RaiseError};
    my $old_print_err = $dbh->{PrintError};
    $dbh->{RaiseError} = 1;
    $dbh->{PrintError} = 0;
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
    $dbh->{RaiseError} = $old_raise_err;
    $dbh->{PrintError} = $old_print_err;
    return \%result if !$@;
  }

  my %result;
  my $sth = $dbh->prepare("SELECT * FROM $table WHERE 1=0");
  $sth->execute;
  my @columns = @{$sth->{NAME_lc}};
  for my $i ( 0 .. $#columns ){
    my %column_info;
    my $type_num = $sth->{TYPE}->[$i];
    my $type_name;
    if(defined $type_num && $dbh->can('type_info')) {
      my $type_info = $dbh->type_info($type_num);
      $type_name = $type_info->{TYPE_NAME} if $type_info;
    }
    $column_info{data_type} = $type_name ? $type_name : $type_num;
    $column_info{size} = $sth->{PRECISION}->[$i];
    $column_info{is_nullable} = $sth->{NULLABLE}->[$i] ? 1 : 0;

    if ($column_info{data_type} =~ m/^(.*?)\((.*?)\)$/) {
      $column_info{data_type} = $1;
      $column_info{size}    = $2;
    }

    $result{$columns[$i]} = \%column_info;
  }

  return \%result;
}

=head2 last_insert_id

Return the row id of the last insert.

=cut

sub last_insert_id {
  my ($self, $row) = @_;
    
  return $self->dbh->func('last_insert_rowid');

}

=head2 sqlt_type

Returns the database driver name.

=cut

sub sqlt_type { shift->dbh->{Driver}->{Name} }

=head2 create_ddl_dir (EXPERIMENTAL)

=over 4

=item Arguments: $schema \@databases, $version, $directory, $sqlt_args

=back

Creates an SQL file based on the Schema, for each of the specified
database types, in the given directory.

Note that this feature is currently EXPERIMENTAL and may not work correctly
across all databases, or fully handle complex relationships.

=cut

sub create_ddl_dir
{
  my ($self, $schema, $databases, $version, $dir, $sqltargs) = @_;

  if(!$dir || !-d $dir)
  {
    warn "No directory given, using ./\n";
    $dir = "./";
  }
  $databases ||= ['MySQL', 'SQLite', 'PostgreSQL'];
  $databases = [ $databases ] if(ref($databases) ne 'ARRAY');
  $version ||= $schema->VERSION || '1.x';
  $sqltargs = { ( add_drop_table => 1 ), %{$sqltargs || {}} };

  eval "use SQL::Translator";
  $self->throw_exception("Can't deploy without SQL::Translator: $@") if $@;

  my $sqlt = SQL::Translator->new($sqltargs);
  foreach my $db (@$databases)
  {
    $sqlt->reset();
    $sqlt->parser('SQL::Translator::Parser::DBIx::Class');
#    $sqlt->parser_args({'DBIx::Class' => $schema);
    $sqlt->data($schema);
    $sqlt->producer($db);

    my $file;
    my $filename = $schema->ddl_filename($db, $dir, $version);
    if(-e $filename)
    {
      $self->throw_exception("$filename already exists, skipping $db");
      next;
    }
    open($file, ">$filename") 
      or $self->throw_exception("Can't open $filename for writing ($!)");
    my $output = $sqlt->translate;
#use Data::Dumper;
#    print join(":", keys %{$schema->source_registrations});
#    print Dumper($sqlt->schema);
    if(!$output)
    {
      $self->throw_exception("Failed to translate to $db. (" . $sqlt->error . ")");
      next;
    }
    print $file $output;
    close($file);
  }

}

=head2 deployment_statements

Create the statements for L</deploy> and
L<DBIx::Class::Schema/deploy>.

=cut

sub deployment_statements {
  my ($self, $schema, $type, $version, $dir, $sqltargs) = @_;
  # Need to be connected to get the correct sqlt_type
  $self->ensure_connected() unless $type;
  $type ||= $self->sqlt_type;
  $version ||= $schema->VERSION || '1.x';
  $dir ||= './';
  eval "use SQL::Translator";
  if(!$@)
  {
    eval "use SQL::Translator::Parser::DBIx::Class;";
    $self->throw_exception($@) if $@;
    eval "use SQL::Translator::Producer::${type};";
    $self->throw_exception($@) if $@;
    my $tr = SQL::Translator->new(%$sqltargs);
    SQL::Translator::Parser::DBIx::Class::parse( $tr, $schema );
    return "SQL::Translator::Producer::${type}"->can('produce')->($tr);
  }

  my $filename = $schema->ddl_filename($type, $dir, $version);
  if(!-f $filename)
  {
#      $schema->create_ddl_dir([ $type ], $version, $dir, $sqltargs);
      $self->throw_exception("No SQL::Translator, and no Schema file found, aborting deploy");
      return;
  }
  my $file;
  open($file, "<$filename") 
      or $self->throw_exception("Can't open $filename ($!)");
  my @rows = <$file>;
  close($file);

  return join('', @rows);
  
}

=head2 deploy

Sends the appropriate statements to create or modify tables to the
db. This would normally be called through
L<DBIx::Class::Schema/deploy>.

=cut

sub deploy {
  my ($self, $schema, $type, $sqltargs) = @_;
  foreach my $statement ( $self->deployment_statements($schema, $type, undef, undef, { no_comments => 1, %{ $sqltargs || {} } } ) ) {
    for ( split(";\n", $statement)) {
      next if($_ =~ /^--/);
      next if(!$_);
#      next if($_ =~ /^DROP/m);
      next if($_ =~ /^BEGIN TRANSACTION/m);
      next if($_ =~ /^COMMIT/m);
      next if $_ =~ /^\s+$/; # skip whitespace only
      $self->debugobj->query_start($_) if $self->debug;
      $self->dbh->do($_) or warn "SQL was:\n $_";
      $self->debugobj->query_end($_) if $self->debug;
    }
  }
}

=head2 datetime_parser

Returns the datetime parser class

=cut

sub datetime_parser {
  my $self = shift;
  return $self->{datetime_parser} ||= $self->build_datetime_parser(@_);
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
  my $self = shift;
  my $type = $self->datetime_parser_type(@_);
  eval "use ${type}";
  $self->throw_exception("Couldn't load ${type}: $@") if $@;
  return $type;
}

sub DESTROY { shift->disconnect }

1;

=head1 SQL METHODS

The module defines a set of methods within the DBIC::SQL::Abstract
namespace.  These build on L<SQL::Abstract::Limit> to provide the
SQL query functions.

The following methods are extended:-

=over 4

=item delete

=item insert

=item select

=item update

=item limit_dialect

See L</connect_info> for details.
For setting, this method is deprecated in favor of L</connect_info>.

=item quote_char

See L</connect_info> for details.
For setting, this method is deprecated in favor of L</connect_info>.

=item name_sep

See L</connect_info> for details.
For setting, this method is deprecated in favor of L</connect_info>.

=back

=head1 ENVIRONMENT VARIABLES

=head2 DBIC_TRACE

If C<DBIC_TRACE> is set then SQL trace information
is produced (as when the L<debug> method is set).

If the value is of the form C<1=/path/name> then the trace output is
written to the file C</path/name>.

This environment variable is checked when the storage object is first
created (when you call connect on your schema).  So, run-time changes 
to this environment variable will not take effect unless you also 
re-connect on your schema.

=head2 DBIX_CLASS_STORAGE_DBI_DEBUG

Old name for DBIC_TRACE

=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

Andy Grundman <andy@hybridized.org>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

