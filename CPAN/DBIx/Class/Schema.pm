package DBIx::Class::Schema;

use strict;
use warnings;

use Carp::Clan qw/^DBIx::Class/;
use Scalar::Util qw/weaken/;

use base qw/DBIx::Class/;

__PACKAGE__->mk_classdata('class_mappings' => {});
__PACKAGE__->mk_classdata('source_registrations' => {});
__PACKAGE__->mk_classdata('storage_type' => '::DBI');
__PACKAGE__->mk_classdata('storage');

=head1 NAME

DBIx::Class::Schema - composable schemas

=head1 SYNOPSIS

  package Library::Schema;
  use base qw/DBIx::Class::Schema/;

  # load Library::Schema::CD, Library::Schema::Book, Library::Schema::DVD
  __PACKAGE__->load_classes(qw/CD Book DVD/);

  package Library::Schema::CD;
  use base qw/DBIx::Class/;
  __PACKAGE__->load_components(qw/PK::Auto Core/); # for example
  __PACKAGE__->table('cd');

  # Elsewhere in your code:
  my $schema1 = Library::Schema->connect(
    $dsn,
    $user,
    $password,
    { AutoCommit => 0 },
  );

  my $schema2 = Library::Schema->connect($coderef_returning_dbh);

  # fetch objects using Library::Schema::DVD
  my $resultset = $schema1->resultset('DVD')->search( ... );
  my @dvd_objects = $schema2->resultset('DVD')->search( ... );

=head1 DESCRIPTION

Creates database classes based on a schema. This is the recommended way to
use L<DBIx::Class> and allows you to use more than one concurrent connection
with your classes.

NB: If you're used to L<Class::DBI> it's worth reading the L</SYNOPSIS>
carefully, as DBIx::Class does things a little differently. Note in
particular which module inherits off which.

=head1 METHODS

=head2 register_class

=over 4

=item Arguments: $moniker, $component_class

=back

Registers a class which isa DBIx::Class::ResultSourceProxy. Equivalent to
calling:

  $schema->register_source($moniker, $component_class->result_source_instance);

=cut

sub register_class {
  my ($self, $moniker, $to_register) = @_;
  $self->register_source($moniker => $to_register->result_source_instance);
}

=head2 register_source

=over 4

=item Arguments: $moniker, $result_source

=back

Registers the L<DBIx::Class::ResultSource> in the schema with the given
moniker.

=cut

sub register_source {
  my ($self, $moniker, $source) = @_;
  my %reg = %{$self->source_registrations};
  $reg{$moniker} = $source;
  $self->source_registrations(\%reg);
  $source->schema($self);
  weaken($source->{schema}) if ref($self);
  if ($source->result_class) {
    my %map = %{$self->class_mappings};
    $map{$source->result_class} = $moniker;
    $self->class_mappings(\%map);
  }
}

=head2 class

=over 4

=item Arguments: $moniker

=item Return Value: $classname

=back

Retrieves the result class name for the given moniker. For example:

  my $class = $schema->class('CD');

=cut

sub class {
  my ($self, $moniker) = @_;
  return $self->source($moniker)->result_class;
}

=head2 source

=over 4

=item Arguments: $moniker

=item Return Value: $result_source

=back

  my $source = $schema->source('Book');

Returns the L<DBIx::Class::ResultSource> object for the registered moniker.

=cut

sub source {
  my ($self, $moniker) = @_;
  my $sreg = $self->source_registrations;
  return $sreg->{$moniker} if exists $sreg->{$moniker};

  # if we got here, they probably passed a full class name
  my $mapped = $self->class_mappings->{$moniker};
  $self->throw_exception("Can't find source for ${moniker}")
    unless $mapped && exists $sreg->{$mapped};
  return $sreg->{$mapped};
}

=head2 sources

=over 4

=item Return Value: @source_monikers

=back

Returns the source monikers of all source registrations on this schema.
For example:

  my @source_monikers = $schema->sources;

=cut

sub sources { return keys %{shift->source_registrations}; }

=head2 resultset

=over 4

=item Arguments: $moniker

=item Return Value: $result_set

=back

  my $rs = $schema->resultset('DVD');

Returns the L<DBIx::Class::ResultSet> object for the registered moniker.

=cut

sub resultset {
  my ($self, $moniker) = @_;
  return $self->source($moniker)->resultset;
}

=head2 load_classes

=over 4

=item Arguments: @classes?, { $namespace => [ @classes ] }+

=back

With no arguments, this method uses L<Module::Find> to find all classes under
the schema's namespace. Otherwise, this method loads the classes you specify
(using L<use>), and registers them (using L</"register_class">).

It is possible to comment out classes with a leading C<#>, but note that perl
will think it's a mistake (trying to use a comment in a qw list), so you'll
need to add C<no warnings 'qw';> before your load_classes call.

Example:

  My::Schema->load_classes(); # loads My::Schema::CD, My::Schema::Artist,
                              # etc. (anything under the My::Schema namespace)

  # loads My::Schema::CD, My::Schema::Artist, Other::Namespace::Producer but
  # not Other::Namespace::LinerNotes nor My::Schema::Track
  My::Schema->load_classes(qw/ CD Artist #Track /, {
    Other::Namespace => [qw/ Producer #LinerNotes /],
  });

=cut

sub load_classes {
  my ($class, @params) = @_;

  my %comps_for;

  if (@params) {
    foreach my $param (@params) {
      if (ref $param eq 'ARRAY') {
        # filter out commented entries
        my @modules = grep { $_ !~ /^#/ } @$param;

        push (@{$comps_for{$class}}, @modules);
      }
      elsif (ref $param eq 'HASH') {
        # more than one namespace possible
        for my $comp ( keys %$param ) {
          # filter out commented entries
          my @modules = grep { $_ !~ /^#/ } @{$param->{$comp}};

          push (@{$comps_for{$comp}}, @modules);
        }
      }
      else {
        # filter out commented entries
        push (@{$comps_for{$class}}, $param) if $param !~ /^#/;
      }
    }
  } else {
    eval "require Module::Find;";
    $class->throw_exception(
      "No arguments to load_classes and couldn't load Module::Find ($@)"
    ) if $@;
    my @comp = map { substr $_, length "${class}::"  }
                 Module::Find::findallmod($class);
    $comps_for{$class} = \@comp;
  }

  my @to_register;
  {
    no warnings qw/redefine/;
    local *Class::C3::reinitialize = sub { };
    foreach my $prefix (keys %comps_for) {
      foreach my $comp (@{$comps_for{$prefix}||[]}) {
        my $comp_class = "${prefix}::${comp}";
        $class->ensure_class_loaded($comp_class);
        $comp_class->source_name($comp) unless $comp_class->source_name;

        push(@to_register, [ $comp_class->source_name, $comp_class ]);
      }
    }
  }
  Class::C3->reinitialize;

  foreach my $to (@to_register) {
    $class->register_class(@$to);
    #  if $class->can('result_source_instance');
  }
}

=head2 compose_connection

=over 4

=item Arguments: $target_namespace, @db_info

=item Return Value: $new_schema

=back

Calls L<DBIx::Class::Schema/"compose_namespace"> to the target namespace,
calls L<DBIx::Class::Schema/connection> with @db_info on the new schema,
then injects the L<DBix::Class::ResultSetProxy> component and a
resultset_instance classdata entry on all the new classes, in order to support
$target_namespaces::$class->search(...) method calls.

This is primarily useful when you have a specific need for class method access
to a connection. In normal usage it is preferred to call
L<DBIx::Class::Schema/connect> and use the resulting schema object to operate
on L<DBIx::Class::ResultSet> objects with L<DBIx::Class::Schema/resultset> for
more information.

=cut

sub compose_connection {
  my ($self, $target, @info) = @_;
  my $base = 'DBIx::Class::ResultSetProxy';
  eval "require ${base};";
  $self->throw_exception
    ("No arguments to load_classes and couldn't load ${base} ($@)")
      if $@;

  if ($self eq $target) {
    # Pathological case, largely caused by the docs on early C::M::DBIC::Plain
    foreach my $moniker ($self->sources) {
      my $source = $self->source($moniker);
      my $class = $source->result_class;
      $self->inject_base($class, $base);
      $class->mk_classdata(resultset_instance => $source->resultset);
      $class->mk_classdata(class_resolver => $self);
    }
    $self->connection(@info);
    return $self;
  }

  my $schema = $self->compose_namespace($target, $base);
  {
    no strict 'refs';
    *{"${target}::schema"} = sub { $schema };
  }

  $schema->connection(@info);
  foreach my $moniker ($schema->sources) {
    my $source = $schema->source($moniker);
    my $class = $source->result_class;
    #warn "$moniker $class $source ".$source->storage;
    $class->mk_classdata(result_source_instance => $source);
    $class->mk_classdata(resultset_instance => $source->resultset);
    $class->mk_classdata(class_resolver => $schema);
  }
  return $schema;
}

=head2 compose_namespace

=over 4

=item Arguments: $target_namespace, $additional_base_class?

=item Return Value: $new_schema

=back

For each L<DBIx::Class::ResultSource> in the schema, this method creates a
class in the target namespace (e.g. $target_namespace::CD,
$target_namespace::Artist) that inherits from the corresponding classes
attached to the current schema.

It also attaches a corresponding L<DBIx::Class::ResultSource> object to the
new $schema object. If C<$additional_base_class> is given, the new composed
classes will inherit from first the corresponding classe from the current
schema then the base class.

For example, for a schema with My::Schema::CD and My::Schema::Artist classes,

  $schema->compose_namespace('My::DB', 'Base::Class');
  print join (', ', @My::DB::CD::ISA) . "\n";
  print join (', ', @My::DB::Artist::ISA) ."\n";

will produce the output

  My::Schema::CD, Base::Class
  My::Schema::Artist, Base::Class

=cut

sub compose_namespace {
  my ($self, $target, $base) = @_;
  my %reg = %{ $self->source_registrations };
  my %target;
  my %map;
  my $schema = $self->clone;
  {
    no warnings qw/redefine/;
    local *Class::C3::reinitialize = sub { };
    foreach my $moniker ($schema->sources) {
      my $source = $schema->source($moniker);
      my $target_class = "${target}::${moniker}";
      $self->inject_base(
        $target_class => $source->result_class, ($base ? $base : ())
      );
      $source->result_class($target_class);
      $target_class->result_source_instance($source)
        if $target_class->can('result_source_instance');
    }
  }
  Class::C3->reinitialize();
  {
    no strict 'refs';
    foreach my $meth (qw/class source resultset/) {
      *{"${target}::${meth}"} =
        sub { shift->schema->$meth(@_) };
    }
  }
  return $schema;
}

=head2 setup_connection_class

=over 4

=item Arguments: $target, @info

=back

Sets up a database connection class to inject between the schema and the
subclasses that the schema creates.

=cut

sub setup_connection_class {
  my ($class, $target, @info) = @_;
  $class->inject_base($target => 'DBIx::Class::DB');
  #$target->load_components('DB');
  $target->connection(@info);
}

=head2 connection

=over 4

=item Arguments: @args

=item Return Value: $new_schema

=back

Instantiates a new Storage object of type
L<DBIx::Class::Schema/"storage_type"> and passes the arguments to
$storage->connect_info. Sets the connection in-place on the schema. See
L<DBIx::Class::Storage::DBI/"connect_info"> for more information.

=cut

sub connection {
  my ($self, @info) = @_;
  return $self if !@info && $self->storage;
  my $storage_class = $self->storage_type;
  $storage_class = 'DBIx::Class::Storage'.$storage_class
    if $storage_class =~ m/^::/;
  eval "require ${storage_class};";
  $self->throw_exception(
    "No arguments to load_classes and couldn't load ${storage_class} ($@)"
  ) if $@;
  my $storage = $storage_class->new;
  $storage->connect_info(\@info);
  $self->storage($storage);
  return $self;
}

=head2 connect

=over 4

=item Arguments: @info

=item Return Value: $new_schema

=back

This is a convenience method. It is equivalent to calling
$schema->clone->connection(@info). See L</connection> and L</clone> for more
information.

=cut

sub connect { shift->clone->connection(@_) }

=head2 txn_begin

Begins a transaction (does nothing if AutoCommit is off). Equivalent to
calling $schema->storage->txn_begin. See
L<DBIx::Class::Storage::DBI/"txn_begin"> for more information.

=cut

sub txn_begin { shift->storage->txn_begin }

=head2 txn_commit

Commits the current transaction. Equivalent to calling
$schema->storage->txn_commit. See L<DBIx::Class::Storage::DBI/"txn_commit">
for more information.

=cut

sub txn_commit { shift->storage->txn_commit }

=head2 txn_rollback

Rolls back the current transaction. Equivalent to calling
$schema->storage->txn_rollback. See
L<DBIx::Class::Storage::DBI/"txn_rollback"> for more information.

=cut

sub txn_rollback { shift->storage->txn_rollback }

=head2 txn_do

=over 4

=item Arguments: C<$coderef>, @coderef_args?

=item Return Value: The return value of $coderef

=back

Executes C<$coderef> with (optional) arguments C<@coderef_args> atomically,
returning its result (if any). If an exception is caught, a rollback is issued
and the exception is rethrown. If the rollback fails, (i.e. throws an
exception) an exception is thrown that includes a "Rollback failed" message.

For example,

  my $author_rs = $schema->resultset('Author')->find(1);
  my @titles = qw/Night Day It/;

  my $coderef = sub {
    # If any one of these fails, the entire transaction fails
    $author_rs->create_related('books', {
      title => $_
    }) foreach (@titles);

    return $author->books;
  };

  my $rs;
  eval {
    $rs = $schema->txn_do($coderef);
  };

  if ($@) {                                  # Transaction failed
    die "something terrible has happened!"   #
      if ($@ =~ /Rollback failed/);          # Rollback failed

    deal_with_failed_transaction();
  }

In a nested transaction (calling txn_do() from within a txn_do() coderef) only
the outermost transaction will issue a L<DBIx::Class::Schema/"txn_commit"> on
the Schema's storage, and txn_do() can be called in void, scalar and list
context and it will behave as expected.

=cut

sub txn_do {
  my ($self, $coderef, @args) = @_;

  $self->storage or $self->throw_exception
    ('txn_do called on $schema without storage');
  ref $coderef eq 'CODE' or $self->throw_exception
    ('$coderef must be a CODE reference');

  my (@return_values, $return_value);

  $self->txn_begin; # If this throws an exception, no rollback is needed

  my $wantarray = wantarray; # Need to save this since the context
                             # inside the eval{} block is independent
                             # of the context that called txn_do()
  eval {

    # Need to differentiate between scalar/list context to allow for
    # returning a list in scalar context to get the size of the list
    if ($wantarray) {
      # list context
      @return_values = $coderef->(@args);
    } elsif (defined $wantarray) {
      # scalar context
      $return_value = $coderef->(@args);
    } else {
      # void context
      $coderef->(@args);
    }
    $self->txn_commit;
  };

  if ($@) {
    my $error = $@;

    eval {
      $self->txn_rollback;
    };

    if ($@) {
      my $rollback_error = $@;
      my $exception_class = "DBIx::Class::Storage::NESTED_ROLLBACK_EXCEPTION";
      $self->throw_exception($error)  # propagate nested rollback
        if $rollback_error =~ /$exception_class/;

      $self->throw_exception(
        "Transaction aborted: $error. Rollback failed: ${rollback_error}"
      );
    } else {
      $self->throw_exception($error); # txn failed but rollback succeeded
    }
  }

  return $wantarray ? @return_values : $return_value;
}

=head2 clone

=over 4

=item Return Value: $new_schema

=back

Clones the schema and its associated result_source objects and returns the
copy.

=cut

sub clone {
  my ($self) = @_;
  my $clone = bless({ (ref $self ? %$self : ()) }, ref $self || $self);
  foreach my $moniker ($self->sources) {
    my $source = $self->source($moniker);
    my $new = $source->new($source);
    $clone->register_source($moniker => $new);
  }
  return $clone;
}

=head2 populate

=over 4

=item Arguments: $moniker, \@data;

=back

Populates the source registered with the given moniker with the supplied data.
@data should be a list of listrefs -- the first containing column names, the
second matching values.

i.e.,

  $schema->populate('Artist', [
    [ qw/artistid name/ ],
    [ 1, 'Popular Band' ],
    [ 2, 'Indie Band' ],
    ...
  ]);

=cut

sub populate {
  my ($self, $name, $data) = @_;
  my $rs = $self->resultset($name);
  my @names = @{shift(@$data)};
  my @created;
  foreach my $item (@$data) {
    my %create;
    @create{@names} = @$item;
    push(@created, $rs->create(\%create));
  }
  return @created;
}

=head2 throw_exception

=over 4

=item Arguments: $message

=back

Throws an exception. Defaults to using L<Carp::Clan> to report errors from
user's perspective.

=cut

sub throw_exception {
  my ($self) = shift;
  croak @_;
}

=head2 deploy (EXPERIMENTAL)

=over 4

=item Arguments: $sqlt_args

=back

Attempts to deploy the schema to the current storage using L<SQL::Translator>.

Note that this feature is currently EXPERIMENTAL and may not work correctly
across all databases, or fully handle complex relationships.

See L<SQL::Translator/METHODS> for a list of values for C<$sqlt_args>. The most
common value for this would be C<< { add_drop_table => 1, } >> to have the SQL
produced include a DROP TABLE statement for each table created.

=cut

sub deploy {
  my ($self, $sqltargs) = @_;
  $self->throw_exception("Can't deploy without storage") unless $self->storage;
  $self->storage->deploy($self, undef, $sqltargs);
}

=head2 create_ddl_dir (EXPERIMENTAL)

=over 4

=item Arguments: \@databases, $version, $directory, $sqlt_args

=back

Creates an SQL file based on the Schema, for each of the specified
database types, in the given directory.

Note that this feature is currently EXPERIMENTAL and may not work correctly
across all databases, or fully handle complex relationships.

=cut

sub create_ddl_dir
{
  my $self = shift;

  $self->throw_exception("Can't create_ddl_dir without storage") unless $self->storage;
  $self->storage->create_ddl_dir($self, @_);
}

=head2 ddl_filename (EXPERIMENTAL)

  my $filename = $table->ddl_filename($type, $dir, $version)

Creates a filename for a SQL file based on the table class name.  Not
intended for direct end user use.

=cut

sub ddl_filename
{
    my ($self, $type, $dir, $version) = @_;

    my $filename = ref($self);
    $filename =~ s/::/-/;
    $filename = "$dir$filename-$version-$type.sql";

    return $filename;
}

1;

=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

