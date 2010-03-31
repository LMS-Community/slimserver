package DBIx::Class::Storage::DBI::Replicated;

BEGIN {
  use Carp::Clan qw/^DBIx::Class/;

  ## Modules required for Replication support not required for general DBIC
  ## use, so we explicitly test for these.

  my %replication_required = (
    'Moose' => '0.87',
    'MooseX::AttributeHelpers' => '0.21',
    'MooseX::Types' => '0.16',
    'namespace::clean' => '0.11',
    'Hash::Merge' => '0.11'
  );

  my @didnt_load;

  for my $module (keys %replication_required) {
    eval "use $module $replication_required{$module}";
    push @didnt_load, "$module $replication_required{$module}"
      if $@;
  }

  croak("@{[ join ', ', @didnt_load ]} are missing and are required for Replication")
    if @didnt_load;
}

use Moose;
use DBIx::Class::Storage::DBI;
use DBIx::Class::Storage::DBI::Replicated::Pool;
use DBIx::Class::Storage::DBI::Replicated::Balancer;
use DBIx::Class::Storage::DBI::Replicated::Types qw/BalancerClassNamePart DBICSchema DBICStorageDBI/;
use MooseX::Types::Moose qw/ClassName HashRef Object/;
use Scalar::Util 'reftype';
use Hash::Merge 'merge';

use namespace::clean -except => 'meta';

=head1 NAME

DBIx::Class::Storage::DBI::Replicated - BETA Replicated database support

=head1 SYNOPSIS

The Following example shows how to change an existing $schema to a replicated
storage type, add some replicated (readonly) databases, and perform reporting
tasks.

You should set the 'storage_type attribute to a replicated type.  You should
also define your arguments, such as which balancer you want and any arguments
that the Pool object should get.

  $schema->storage_type( ['::DBI::Replicated', {balancer=>'::Random'}] );

Next, you need to add in the Replicants.  Basically this is an array of 
arrayrefs, where each arrayref is database connect information.  Think of these
arguments as what you'd pass to the 'normal' $schema->connect method.

  $schema->storage->connect_replicants(
    [$dsn1, $user, $pass, \%opts],
    [$dsn2, $user, $pass, \%opts],
    [$dsn3, $user, $pass, \%opts],
  );

Now, just use the $schema as you normally would.  Automatically all reads will
be delegated to the replicants, while writes to the master.

  $schema->resultset('Source')->search({name=>'etc'});

You can force a given query to use a particular storage using the search
attribute 'force_pool'.  For example:

  my $RS = $schema->resultset('Source')->search(undef, {force_pool=>'master'});

Now $RS will force everything (both reads and writes) to use whatever was setup
as the master storage.  'master' is hardcoded to always point to the Master, 
but you can also use any Replicant name.  Please see:
L<DBIx::Class::Storage::DBI::Replicated::Pool> and the replicants attribute for more.

Also see transactions and L</execute_reliably> for alternative ways to
force read traffic to the master.  In general, you should wrap your statements
in a transaction when you are reading and writing to the same tables at the
same time, since your replicants will often lag a bit behind the master.

See L<DBIx::Class::Storage::DBI::Replicated::Instructions> for more help and
walkthroughs.

=head1 DESCRIPTION

Warning: This class is marked BETA.  This has been running a production
website using MySQL native replication as its backend and we have some decent
test coverage but the code hasn't yet been stressed by a variety of databases.
Individual DB's may have quirks we are not aware of.  Please use this in first
development and pass along your experiences/bug fixes.

This class implements replicated data store for DBI. Currently you can define
one master and numerous slave database connections. All write-type queries
(INSERT, UPDATE, DELETE and even LAST_INSERT_ID) are routed to master
database, all read-type queries (SELECTs) go to the slave database.

Basically, any method request that L<DBIx::Class::Storage::DBI> would normally
handle gets delegated to one of the two attributes: L</read_handler> or to
L</write_handler>.  Additionally, some methods need to be distributed
to all existing storages.  This way our storage class is a drop in replacement
for L<DBIx::Class::Storage::DBI>.

Read traffic is spread across the replicants (slaves) occuring to a user
selected algorithm.  The default algorithm is random weighted.

=head1 NOTES

The consistancy betweeen master and replicants is database specific.  The Pool
gives you a method to validate its replicants, removing and replacing them
when they fail/pass predefined criteria.  Please make careful use of the ways
to force a query to run against Master when needed.

=head1 REQUIREMENTS

Replicated Storage has additional requirements not currently part of L<DBIx::Class>

  Moose => '0.87',
  MooseX::AttributeHelpers => '0.20',
  MooseX::Types => '0.16',
  namespace::clean => '0.11',
  Hash::Merge => '0.11'

You will need to install these modules manually via CPAN or make them part of the
Makefile for your distribution.

=head1 ATTRIBUTES

This class defines the following attributes.

=head2 schema

The underlying L<DBIx::Class::Schema> object this storage is attaching

=cut

has 'schema' => (
    is=>'rw',
    isa=>DBICSchema,
    weak_ref=>1,
    required=>1,
);

=head2 pool_type

Contains the classname which will instantiate the L</pool> object.  Defaults 
to: L<DBIx::Class::Storage::DBI::Replicated::Pool>.

=cut

has 'pool_type' => (
  is=>'rw',
  isa=>ClassName,
  default=>'DBIx::Class::Storage::DBI::Replicated::Pool',
  handles=>{
    'create_pool' => 'new',
  },
);

=head2 pool_args

Contains a hashref of initialized information to pass to the Balancer object.
See L<DBIx::Class::Storage::DBI::Replicated::Pool> for available arguments.

=cut

has 'pool_args' => (
  is=>'rw',
  isa=>HashRef,
  lazy=>1,
  default=>sub { {} },
);


=head2 balancer_type

The replication pool requires a balance class to provider the methods for
choose how to spread the query load across each replicant in the pool.

=cut

has 'balancer_type' => (
  is=>'rw',
  isa=>BalancerClassNamePart,
  coerce=>1,
  required=>1,
  default=> 'DBIx::Class::Storage::DBI::Replicated::Balancer::First',
  handles=>{
    'create_balancer' => 'new',
  },
);

=head2 balancer_args

Contains a hashref of initialized information to pass to the Balancer object.
See L<DBIx::Class::Storage::DBI::Replicated::Balancer> for available arguments.

=cut

has 'balancer_args' => (
  is=>'rw',
  isa=>HashRef,
  lazy=>1,
  required=>1,
  default=>sub { {} },
);

=head2 pool

Is a <DBIx::Class::Storage::DBI::Replicated::Pool> or derived class.  This is a
container class for one or more replicated databases.

=cut

has 'pool' => (
  is=>'ro',
  isa=>'DBIx::Class::Storage::DBI::Replicated::Pool',
  lazy_build=>1,
  handles=>[qw/
    connect_replicants
    replicants
    has_replicants
  /],
);

=head2 balancer

Is a <DBIx::Class::Storage::DBI::Replicated::Balancer> or derived class.  This 
is a class that takes a pool (<DBIx::Class::Storage::DBI::Replicated::Pool>)

=cut

has 'balancer' => (
  is=>'rw',
  isa=>'DBIx::Class::Storage::DBI::Replicated::Balancer',
  lazy_build=>1,
  handles=>[qw/auto_validate_every/],
);

=head2 master

The master defines the canonical state for a pool of connected databases.  All
the replicants are expected to match this databases state.  Thus, in a classic
Master / Slaves distributed system, all the slaves are expected to replicate
the Master's state as quick as possible.  This is the only database in the
pool of databases that is allowed to handle write traffic.

=cut

has 'master' => (
  is=> 'ro',
  isa=>DBICStorageDBI,
  lazy_build=>1,
);

=head1 ATTRIBUTES IMPLEMENTING THE DBIx::Storage::DBI INTERFACE

The following methods are delegated all the methods required for the 
L<DBIx::Class::Storage::DBI> interface.

=head2 read_handler

Defines an object that implements the read side of L<BIx::Class::Storage::DBI>.

=cut

has 'read_handler' => (
  is=>'rw',
  isa=>Object,
  lazy_build=>1,
  handles=>[qw/
    select
    select_single
    columns_info_for
  /],
);

=head2 write_handler

Defines an object that implements the write side of L<BIx::Class::Storage::DBI>.

=cut

has 'write_handler' => (
  is=>'ro',
  isa=>Object,
  lazy_build=>1,
  handles=>[qw/
    on_connect_do
    on_disconnect_do
    connect_info
    throw_exception
    sql_maker
    sqlt_type
    create_ddl_dir
    deployment_statements
    datetime_parser
    datetime_parser_type
    build_datetime_parser
    last_insert_id
    insert
    insert_bulk
    update
    delete
    dbh
    txn_begin
    txn_do
    txn_commit
    txn_rollback
    txn_scope_guard
    sth
    deploy
    with_deferred_fk_checks
    dbh_do
    reload_row
    with_deferred_fk_checks
    _prep_for_execute

    backup
    is_datatype_numeric
    _count_select
    _subq_count_select
    _subq_update_delete
    svp_rollback
    svp_begin
    svp_release
  /],
);

has _master_connect_info_opts =>
  (is => 'rw', isa => HashRef, default => sub { {} });

=head2 around: connect_info

Preserve master's C<connect_info> options (for merging with replicants.)
Also set any Replicated related options from connect_info, such as
C<pool_type>, C<pool_args>, C<balancer_type> and C<balancer_args>.

=cut

around connect_info => sub {
  my ($next, $self, $info, @extra) = @_;

  my $wantarray = wantarray;

  my %opts;
  for my $arg (@$info) {
    next unless (reftype($arg)||'') eq 'HASH';
    %opts = %{ merge($arg, \%opts) };
  }
  delete $opts{dsn};

  if (@opts{qw/pool_type pool_args/}) {
    $self->pool_type(delete $opts{pool_type})
      if $opts{pool_type};

    $self->pool_args(
      merge((delete $opts{pool_args} || {}), $self->pool_args)
    );

    $self->pool($self->_build_pool)
      if $self->pool;
  }

  if (@opts{qw/balancer_type balancer_args/}) {
    $self->balancer_type(delete $opts{balancer_type})
      if $opts{balancer_type};

    $self->balancer_args(
      merge((delete $opts{balancer_args} || {}), $self->balancer_args)
    );

    $self->balancer($self->_build_balancer)
      if $self->balancer;
  }

  $self->_master_connect_info_opts(\%opts);

  my (@res, $res);
  if ($wantarray) {
    @res = $self->$next($info, @extra);
  } else {
    $res = $self->$next($info, @extra);
  }

  # Make sure master is blessed into the correct class and apply role to it.
  my $master = $self->master;
  $master->_determine_driver;
  Moose::Meta::Class->initialize(ref $master);
  DBIx::Class::Storage::DBI::Replicated::WithDSN->meta->apply($master);

  $wantarray ? @res : $res;
};

=head1 METHODS

This class defines the following methods.

=head2 BUILDARGS

L<DBIx::Class::Schema> when instantiating its storage passed itself as the
first argument.  So we need to massage the arguments a bit so that all the
bits get put into the correct places.

=cut

sub BUILDARGS {
  my ($class, $schema, $storage_type_args, @args) = @_;	

  return {
    schema=>$schema,
    %$storage_type_args,
    @args
  }
}

=head2 _build_master

Lazy builder for the L</master> attribute.

=cut

sub _build_master {
  my $self = shift @_;
  my $master = DBIx::Class::Storage::DBI->new($self->schema);
  $master
}

=head2 _build_pool

Lazy builder for the L</pool> attribute.

=cut

sub _build_pool {
  my $self = shift @_;
  $self->create_pool(%{$self->pool_args});
}

=head2 _build_balancer

Lazy builder for the L</balancer> attribute.  This takes a Pool object so that
the balancer knows which pool it's balancing.

=cut

sub _build_balancer {
  my $self = shift @_;
  $self->create_balancer(
    pool=>$self->pool,
    master=>$self->master,
    %{$self->balancer_args},
  );
}

=head2 _build_write_handler

Lazy builder for the L</write_handler> attribute.  The default is to set this to
the L</master>.

=cut

sub _build_write_handler {
  return shift->master;
}

=head2 _build_read_handler

Lazy builder for the L</read_handler> attribute.  The default is to set this to
the L</balancer>.

=cut

sub _build_read_handler {
  return shift->balancer;
}

=head2 around: connect_replicants

All calls to connect_replicants needs to have an existing $schema tacked onto
top of the args, since L<DBIx::Storage::DBI> needs it, and any C<connect_info>
options merged with the master, with replicant opts having higher priority.

=cut

around connect_replicants => sub {
  my ($next, $self, @args) = @_;

  for my $r (@args) {
    $r = [ $r ] unless reftype $r eq 'ARRAY';

    $self->throw_exception('coderef replicant connect_info not supported')
      if ref $r->[0] && reftype $r->[0] eq 'CODE';

# any connect_info options?
    my $i = 0;
    $i++ while $i < @$r && (reftype($r->[$i])||'') ne 'HASH';

# make one if none
    $r->[$i] = {} unless $r->[$i];

# merge if two hashes
    my @hashes = @$r[$i .. $#{$r}];

    $self->throw_exception('invalid connect_info options')
      if (grep { reftype($_) eq 'HASH' } @hashes) != @hashes;

    $self->throw_exception('too many hashrefs in connect_info')
      if @hashes > 2;

    my %opts = %{ merge(reverse @hashes) };

# delete them
    splice @$r, $i+1, ($#{$r} - $i), ();

# make sure master/replicants opts don't clash
    my %master_opts = %{ $self->_master_connect_info_opts };
    if (exists $opts{dbh_maker}) {
        delete @master_opts{qw/dsn user password/};
    }
    delete $master_opts{dbh_maker};

# merge with master
    %opts = %{ merge(\%opts, \%master_opts) };

# update
    $r->[$i] = \%opts;
  }

  $self->$next($self->schema, @args);
};

=head2 all_storages

Returns an array of of all the connected storage backends.  The first element
in the returned array is the master, and the remainings are each of the
replicants.

=cut

sub all_storages {
  my $self = shift @_;
  return grep {defined $_ && blessed $_} (
     $self->master,
     values %{ $self->replicants },
  );
}

=head2 execute_reliably ($coderef, ?@args)

Given a coderef, saves the current state of the L</read_handler>, forces it to
use reliable storage (ie sets it to the master), executes a coderef and then
restores the original state.

Example:

  my $reliably = sub {
    my $name = shift @_;
    $schema->resultset('User')->create({name=>$name});
    my $user_rs = $schema->resultset('User')->find({name=>$name}); 
    return $user_rs;
  };

  my $user_rs = $schema->storage->execute_reliably($reliably, 'John');

Use this when you must be certain of your database state, such as when you just
inserted something and need to get a resultset including it, etc.

=cut

sub execute_reliably {
  my ($self, $coderef, @args) = @_;

  unless( ref $coderef eq 'CODE') {
    $self->throw_exception('Second argument must be a coderef');
  }

  ##Get copy of master storage
  my $master = $self->master;

  ##Get whatever the current read hander is
  my $current = $self->read_handler;

  ##Set the read handler to master
  $self->read_handler($master);

  ## do whatever the caller needs
  my @result;
  my $want_array = wantarray;

  eval {
    if($want_array) {
      @result = $coderef->(@args);
    } elsif(defined $want_array) {
      ($result[0]) = ($coderef->(@args));
    } else {
      $coderef->(@args);
    }
  };

  ##Reset to the original state
  $self->read_handler($current);

  ##Exception testing has to come last, otherwise you might leave the 
  ##read_handler set to master.

  if($@) {
    $self->throw_exception("coderef returned an error: $@");
  } else {
    return $want_array ? @result : $result[0];
  }
}

=head2 set_reliable_storage

Sets the current $schema to be 'reliable', that is all queries, both read and
write are sent to the master

=cut

sub set_reliable_storage {
  my $self = shift @_;
  my $schema = $self->schema;
  my $write_handler = $self->schema->storage->write_handler;

  $schema->storage->read_handler($write_handler);
}

=head2 set_balanced_storage

Sets the current $schema to be use the </balancer> for all reads, while all
writea are sent to the master only

=cut

sub set_balanced_storage {
  my $self = shift @_;
  my $schema = $self->schema;
  my $balanced_handler = $self->schema->storage->balancer;

  $schema->storage->read_handler($balanced_handler);
}

=head2 connected

Check that the master and at least one of the replicants is connected.

=cut

sub connected {
  my $self = shift @_;
  return
    $self->master->connected &&
    $self->pool->connected_replicants;
}

=head2 ensure_connected

Make sure all the storages are connected.

=cut

sub ensure_connected {
  my $self = shift @_;
  foreach my $source ($self->all_storages) {
    $source->ensure_connected(@_);
  }
}

=head2 limit_dialect

Set the limit_dialect for all existing storages

=cut

sub limit_dialect {
  my $self = shift @_;
  foreach my $source ($self->all_storages) {
    $source->limit_dialect(@_);
  }
  return $self->master->quote_char;
}

=head2 quote_char

Set the quote_char for all existing storages

=cut

sub quote_char {
  my $self = shift @_;
  foreach my $source ($self->all_storages) {
    $source->quote_char(@_);
  }
  return $self->master->quote_char;
}

=head2 name_sep

Set the name_sep for all existing storages

=cut

sub name_sep {
  my $self = shift @_;
  foreach my $source ($self->all_storages) {
    $source->name_sep(@_);
  }
  return $self->master->name_sep;
}

=head2 set_schema

Set the schema object for all existing storages

=cut

sub set_schema {
  my $self = shift @_;
  foreach my $source ($self->all_storages) {
    $source->set_schema(@_);
  }
}

=head2 debug

set a debug flag across all storages

=cut

sub debug {
  my $self = shift @_;
  if(@_) {
    foreach my $source ($self->all_storages) {
      $source->debug(@_);
    }
  }
  return $self->master->debug;
}

=head2 debugobj

set a debug object across all storages

=cut

sub debugobj {
  my $self = shift @_;
  if(@_) {
    foreach my $source ($self->all_storages) {
      $source->debugobj(@_);
    }
  }
  return $self->master->debugobj;
}

=head2 debugfh

set a debugfh object across all storages

=cut

sub debugfh {
  my $self = shift @_;
  if(@_) {
    foreach my $source ($self->all_storages) {
      $source->debugfh(@_);
    }
  }
  return $self->master->debugfh;
}

=head2 debugcb

set a debug callback across all storages

=cut

sub debugcb {
  my $self = shift @_;
  if(@_) {
    foreach my $source ($self->all_storages) {
      $source->debugcb(@_);
    }
  }
  return $self->master->debugcb;
}

=head2 disconnect

disconnect everything

=cut

sub disconnect {
  my $self = shift @_;
  foreach my $source ($self->all_storages) {
    $source->disconnect(@_);
  }
}

=head2 cursor_class

set cursor class on all storages, or return master's

=cut

sub cursor_class {
  my ($self, $cursor_class) = @_;

  if ($cursor_class) {
    $_->cursor_class($cursor_class) for $self->all_storages;
  }
  $self->master->cursor_class;
}

=head1 GOTCHAS

Due to the fact that replicants can lag behind a master, you must take care to
make sure you use one of the methods to force read queries to a master should
you need realtime data integrity.  For example, if you insert a row, and then
immediately re-read it from the database (say, by doing $row->discard_changes)
or you insert a row and then immediately build a query that expects that row
to be an item, you should force the master to handle reads.  Otherwise, due to
the lag, there is no certainty your data will be in the expected state.

For data integrity, all transactions automatically use the master storage for
all read and write queries.  Using a transaction is the preferred and recommended
method to force the master to handle all read queries.

Otherwise, you can force a single query to use the master with the 'force_pool'
attribute:

  my $row = $resultset->search(undef, {force_pool=>'master'})->find($pk);

This attribute will safely be ignore by non replicated storages, so you can use
the same code for both types of systems.

Lastly, you can use the L</execute_reliably> method, which works very much like
a transaction.

For debugging, you can turn replication on/off with the methods L</set_reliable_storage>
and L</set_balanced_storage>, however this operates at a global level and is not
suitable if you have a shared Schema object being used by multiple processes,
such as on a web application server.  You can get around this limitation by
using the Schema clone method.

  my $new_schema = $schema->clone;
  $new_schema->set_reliable_storage;

  ## $new_schema will use only the Master storage for all reads/writes while
  ## the $schema object will use replicated storage.

=head1 AUTHOR

  John Napiorkowski <john.napiorkowski@takkle.com>

Based on code originated by:

  Norbert Csongrádi <bert@cpan.org>
  Peter Siklósi <einon@einon.hu>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

__PACKAGE__->meta->make_immutable;

1;
