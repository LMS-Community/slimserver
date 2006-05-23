package DBIx::Class::Storage::DBI;

use base 'DBIx::Class::Storage';

use strict;
use warnings;
use DBI;
use SQL::Abstract::Limit;
use DBIx::Class::Storage::DBI::Cursor;
use IO::File;
use Carp::Clan qw/DBIx::Class/;

BEGIN {

package DBIC::SQL::Abstract; # Would merge upstream, but nate doesn't reply :(

use base qw/SQL::Abstract::Limit/;

sub select {
  my ($self, $table, $fields, $where, $order, @rest) = @_;
  $table = $self->_quote($table) unless ref($table);
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
    return join(', ', map { $self->_recurse_fields($_) } @$fields);
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
      $ret .= $self->SUPER::_order_by($_[0]->{order_by});
    }
  } elsif(ref $_[0] eq 'SCALAR') {
    $ret = $self->_sqlcase(' order by ').${ $_[0] };
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
    if (ref($to) eq 'HASH' and exists($to->{-join_type})) {
      $join_clause = ' '.uc($to->{-join_type}).' JOIN ';
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

sub _RowNum {
   my $self = shift;
   my $c;
   $_[0] =~ s/SELECT (.*?) FROM/
     'SELECT '.join(', ', map { $_.' AS col'.++$c } split(', ', $1)).' FROM'/e;
   $self->SUPER::_RowNum(@_);
}

# Accessor for setting limit dialect. This is useful
# for JDBC-bridge among others where the remote SQL-dialect cannot
# be determined by the name of the driver alone.
#
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




package DBIx::Class::Storage::DBI::DebugCallback;

sub print {
  my ($self, $string) = @_;
  $string =~ m/^(\w+)/;
  ${$self}->($1, $string);
}

} # End of BEGIN block

use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/AccessorGroup/);

__PACKAGE__->mk_group_accessors('simple' =>
  qw/connect_info _dbh _sql_maker _conn_pid _conn_tid debug debugfh
     cursor on_connect_do transaction_depth/);

sub new {
  my $new = bless({}, ref $_[0] || $_[0]);
  $new->cursor("DBIx::Class::Storage::DBI::Cursor");
  $new->transaction_depth(0);
  if (defined($ENV{DBIX_CLASS_STORAGE_DBI_DEBUG}) &&
     ($ENV{DBIX_CLASS_STORAGE_DBI_DEBUG} =~ /=(.+)$/)) {
    $new->debugfh(IO::File->new($1, 'w'))
      or $new->throw_exception("Cannot open trace file $1");
  } else {
    $new->debugfh(IO::File->new('>&STDERR'));
  }
  $new->debug(1) if $ENV{DBIX_CLASS_STORAGE_DBI_DEBUG};
  return $new;
}

sub throw_exception {
  my ($self, $msg) = @_;
  croak($msg);
}

=head1 NAME

DBIx::Class::Storage::DBI - DBI storage handler

=head1 SYNOPSIS

=head1 DESCRIPTION

This class represents the connection to the database

=head1 METHODS

=cut

=head2 on_connect_do

Executes the sql statements given as a listref on every db connect.

=head2 debug

Causes SQL trace information to be emitted on C<debugfh> filehandle
(or C<STDERR> if C<debugfh> has not specifically been set).

=head2 debugfh

Sets or retrieves the filehandle used for trace/debug output.  This
should be an IO::Handle compatible object (only the C<print> method is
used).  Initially set to be STDERR - although see information on the
L<DBIX_CLASS_STORAGE_DBI_DEBUG> environment variable.

=head2 debugcb

Sets a callback to be executed each time a statement is run; takes a sub
reference. Overrides debugfh. Callback is executed as $sub->($op, $info)
where $op is SELECT/INSERT/UPDATE/DELETE and $info is what would normally
be printed.

=cut

sub debugcb {
  my ($self, $cb) = @_;
  my $cb_obj = bless(\$cb, 'DBIx::Class::Storage::DBI::DebugCallback');
  $self->debugfh($cb_obj);
}

sub disconnect {
  my ($self) = @_;

  if( $self->connected ) {
    $self->_dbh->rollback unless $self->_dbh->{AutoCommit};
    $self->_dbh->disconnect;
    $self->_dbh(undef);
  }
}

sub connected {
  my ($self) = @_;

  if(my $dbh = $self->_dbh) {
      if(defined $self->_conn_tid && $self->_conn_tid != threads->tid) {
          $self->_sql_maker(undef);
          return $self->_dbh(undef);
      }
      elsif($self->_conn_pid != $$) {
          $self->_dbh->{InactiveDestroy} = 1;
          $self->_sql_maker(undef);
          return $self->_dbh(undef)
      }
      return ($dbh->FETCH('Active') && $dbh->ping);
  }

  return 0;
}

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

sub sql_maker {
  my ($self) = @_;
  unless ($self->_sql_maker) {
    $self->_sql_maker(new DBIC::SQL::Abstract( limit_dialect => $self->dbh ));
  }
  return $self->_sql_maker;
}

sub _populate_dbh {
  my ($self) = @_;
  my @info = @{$self->connect_info || []};
  $self->_dbh($self->_connect(@info));
  my $driver = $self->_dbh->{Driver}->{Name};
  eval "require DBIx::Class::Storage::DBI::${driver}";
  unless ($@) {
    bless $self, "DBIx::Class::Storage::DBI::${driver}";
  }
  # if on-connect sql statements are given execute them
  foreach my $sql_statement (@{$self->on_connect_do || []}) {
    $self->_dbh->do($sql_statement);
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
    if(ref $info[0] eq 'CODE') {
        $dbh = &{$info[0]};
    }
    else {
        $dbh = DBI->connect(@info);
    }
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
      $self->debugfh->print("BEGIN WORK\n")
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
      $self->debugfh->print("COMMIT\n")
        if ($self->debug);
      $dbh->commit;
    }
  }
  else {
    if (--$self->{transaction_depth} == 0) {
      $self->debugfh->print("COMMIT\n")
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
        $self->debugfh->print("ROLLBACK\n")
          if ($self->debug);
        $dbh->rollback;
      }
    }
    else {
      if (--$self->{transaction_depth} == 0) {
        $self->debugfh->print("ROLLBACK\n")
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
    my $bind_str = join(', ', map {
      defined $_ ? qq{`$_'} : q{`NULL'}
    } @bind);
    $self->debugfh->print("$sql ($bind_str)\n");
  }
  my $sth = eval { $self->sth($sql,$op) };

  if (!$sth || $@) {
    $self->throw_exception(
      'no sth generated via sql (' . ($@ || $self->_dbh->errstr) . "): $sql"
    );
  }
  @bind = map { ref $_ ? ''.$_ : $_ } @bind; # stringify args
  my $rv = eval { $sth->execute(@bind) };
  if ($@ || !$rv) {
    my $bind_str = join(', ', map {
      defined $_ ? qq{`$_'} : q{`NULL'}
    } @bind);
    $self->throw_exception(
      "Error executing '$sql' ($bind_str): ".($@ || $sth->errstr)
    );
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

sub select {
  my $self = shift;
  my ($ident, $select, $condition, $attrs) = @_;
  return $self->cursor->new($self, \@_, $attrs);
}

# Need to call finish() to work round broken DBDs

sub select_single {
  my $self = shift;
  my ($rv, $sth, @bind) = $self->_select(@_);
  my @row = $sth->fetchrow_array;
  $sth->finish();
  return @row;
}

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
      my $sth = $dbh->column_info( undef, undef, $table, '%' );
      $sth->execute();
      while ( my $info = $sth->fetchrow_hashref() ){
        my %column_info;
        $column_info{data_type}   = $info->{TYPE_NAME};
        $column_info{size}      = $info->{COLUMN_SIZE};
        $column_info{is_nullable}   = $info->{NULLABLE} ? 1 : 0;
        $column_info{default_value} = $info->{COLUMN_DEF};

        $result{$info->{COLUMN_NAME}} = \%column_info;
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

sub last_insert_id {
  my ($self, $row) = @_;
    
  return $self->dbh->func('last_insert_rowid');

}

sub sqlt_type { shift->dbh->{Driver}->{Name} }

sub deployment_statements {
  my ($self, $schema, $type, $sqltargs) = @_;
  $type ||= $self->sqlt_type;
  eval "use SQL::Translator";
  $self->throw_exception("Can't deploy without SQL::Translator: $@") if $@;
  eval "use SQL::Translator::Parser::DBIx::Class;";
  $self->throw_exception($@) if $@;
  eval "use SQL::Translator::Producer::${type};";
  $self->throw_exception($@) if $@;
  my $tr = SQL::Translator->new(%$sqltargs);
  SQL::Translator::Parser::DBIx::Class::parse( $tr, $schema );
  return "SQL::Translator::Producer::${type}"->can('produce')->($tr);
}

sub deploy {
  my ($self, $schema, $type, $sqltargs) = @_;
  foreach my $statement ( $self->deployment_statements($schema, $type, $sqltargs) ) {
    for ( split(";\n", $statement)) {
      $self->debugfh->print("$_\n") if $self->debug;
      $self->dbh->do($_) or warn "SQL was:\n $_";
    }
  }
}

sub DESTROY { shift->disconnect }

1;

=head1 ENVIRONMENT VARIABLES

=head2 DBIX_CLASS_STORAGE_DBI_DEBUG

If C<DBIX_CLASS_STORAGE_DBI_DEBUG> is set then SQL trace information
is produced (as when the L<debug> method is set).

If the value is of the form C<1=/path/name> then the trace output is
written to the file C</path/name>.

This environment variable is checked when the storage object is first
created (when you call connect on your schema).  So, run-time changes 
to this environment variable will not take effect unless you also 
re-connect on your schema.

=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

Andy Grundman <andy@hybridized.org>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

