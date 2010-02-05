package DBIx::Class::Schema;

use strict;
use warnings;

use DBIx::Class::Exception;
use Carp::Clan qw/^DBIx::Class/;
use Scalar::Util qw/weaken/;
use File::Spec;
use Sub::Name ();

use base qw/DBIx::Class/;

__PACKAGE__->mk_classdata('class_mappings' => {});
__PACKAGE__->mk_classdata('source_registrations' => {});
__PACKAGE__->mk_classdata('storage_type' => '::DBI');
__PACKAGE__->mk_classdata('storage');
__PACKAGE__->mk_classdata('exception_action');
__PACKAGE__->mk_classdata('stacktrace' => $ENV{DBIC_TRACE} || 0);
__PACKAGE__->mk_classdata('default_resultset_attributes' => {});

=head1 NAME

DBIx::Class::Schema - composable schemas

=head1 SYNOPSIS

  package Library::Schema;
  use base qw/DBIx::Class::Schema/;

  # load all Result classes in Library/Schema/Result/
  __PACKAGE__->load_namespaces();

  package Library::Schema::Result::CD;
  use base qw/DBIx::Class/;
  __PACKAGE__->load_components(qw/Core/); # for example
  __PACKAGE__->table('cd');

  # Elsewhere in your code:
  my $schema1 = Library::Schema->connect(
    $dsn,
    $user,
    $password,
    { AutoCommit => 1 },
  );

  my $schema2 = Library::Schema->connect($coderef_returning_dbh);

  # fetch objects using Library::Schema::Result::DVD
  my $resultset = $schema1->resultset('DVD')->search( ... );
  my @dvd_objects = $schema2->resultset('DVD')->search( ... );

=head1 DESCRIPTION

Creates database classes based on a schema. This is the recommended way to
use L<DBIx::Class> and allows you to use more than one concurrent connection
with your classes.

NB: If you're used to L<Class::DBI> it's worth reading the L</SYNOPSIS>
carefully, as DBIx::Class does things a little differently. Note in
particular which module inherits off which.

=head1 SETUP METHODS

=head2 load_namespaces

=over 4

=item Arguments: %options?

=back

  __PACKAGE__->load_namespaces();

  __PACKAGE__->load_namespaces(
   result_namespace => 'Res',
   resultset_namespace => 'RSet',
   default_resultset_class => '+MyDB::Othernamespace::RSet',
 );

With no arguments, this method uses L<Module::Find> to load all your
Result classes from a sub-namespace F<Result> under your Schema class'
namespace. Eg. With a Schema of I<MyDB::Schema> all files in
I<MyDB::Schema::Result> are assumed to be Result classes.

It also finds all ResultSet classes in the namespace F<ResultSet> and
loads them into the appropriate Result classes using for you. The
matching is done by assuming the package name of the ResultSet class
is the same as that of the Result class.

You will be warned if ResultSet classes are discovered for which there
are no matching Result classes like this:

  load_namespaces found ResultSet class $classname with no corresponding Result class

If a Result class is found to already have a ResultSet class set using
L</resultset_class> to some other class, you will be warned like this:

  We found ResultSet class '$rs_class' for '$result', but it seems 
  that you had already set '$result' to use '$rs_set' instead

Both of the sub-namespaces are configurable if you don't like the defaults,
via the options C<result_namespace> and C<resultset_namespace>.

If (and only if) you specify the option C<default_resultset_class>, any found
Result classes for which we do not find a corresponding
ResultSet class will have their C<resultset_class> set to
C<default_resultset_class>.

All of the namespace and classname options to this method are relative to
the schema classname by default.  To specify a fully-qualified name, prefix
it with a literal C<+>.

Examples:

  # load My::Schema::Result::CD, My::Schema::Result::Artist,
  #    My::Schema::ResultSet::CD, etc...
  My::Schema->load_namespaces;

  # Override everything to use ugly names.
  # In this example, if there is a My::Schema::Res::Foo, but no matching
  #   My::Schema::RSets::Foo, then Foo will have its
  #   resultset_class set to My::Schema::RSetBase
  My::Schema->load_namespaces(
    result_namespace => 'Res',
    resultset_namespace => 'RSets',
    default_resultset_class => 'RSetBase',
  );

  # Put things in other namespaces
  My::Schema->load_namespaces(
    result_namespace => '+Some::Place::Results',
    resultset_namespace => '+Another::Place::RSets',
  );

If you'd like to use multiple namespaces of each type, simply use an arrayref
of namespaces for that option.  In the case that the same result
(or resultset) class exists in multiple namespaces, the latter entries in
your list of namespaces will override earlier ones.

  My::Schema->load_namespaces(
    # My::Schema::Results_C::Foo takes precedence over My::Schema::Results_B::Foo :
    result_namespace => [ 'Results_A', 'Results_B', 'Results_C' ],
    resultset_namespace => [ '+Some::Place::RSets', 'RSets' ],
  );

=cut

# Pre-pends our classname to the given relative classname or
#   class namespace, unless there is a '+' prefix, which will
#   be stripped.
sub _expand_relative_name {
  my ($class, $name) = @_;
  return if !$name;
  $name = $class . '::' . $name if ! ($name =~ s/^\+//);
  return $name;
}

# Finds all modules in the supplied namespace, or if omitted in the
# namespace of $class. Untaints all findings as they can be assumed
# to be safe
sub _findallmod {
  my $proto = shift;
  my $ns = shift || ref $proto || $proto;

  require Module::Find;
  my @mods = Module::Find::findallmod($ns);

  # try to untaint module names. mods where this fails
  # are left alone so we don't have to change the old behavior
  no locale; # localized \w doesn't untaint expression
  return map { $_ =~ m/^( (?:\w+::)* \w+ )$/x ? $1 : $_ } @mods;
}

# returns a hash of $shortname => $fullname for every package
# found in the given namespaces ($shortname is with the $fullname's
# namespace stripped off)
sub _map_namespaces {
  my ($class, @namespaces) = @_;

  my @results_hash;
  foreach my $namespace (@namespaces) {
    push(
      @results_hash,
      map { (substr($_, length "${namespace}::"), $_) }
      $class->_findallmod($namespace)
    );
  }

  @results_hash;
}

# returns the result_source_instance for the passed class/object,
# or dies with an informative message (used by load_namespaces)
sub _ns_get_rsrc_instance {
  my $class = shift;
  my $rs = ref ($_[0]) || $_[0];

  if ($rs->can ('result_source_instance') ) {
    return $rs->result_source_instance;
  }
  else {
    $class->throw_exception (
      "Attempt to load_namespaces() class $rs failed - are you sure this is a real Result Class?"
    );
  }
}

sub load_namespaces {
  my ($class, %args) = @_;

  my $result_namespace = delete $args{result_namespace} || 'Result';
  my $resultset_namespace = delete $args{resultset_namespace} || 'ResultSet';
  my $default_resultset_class = delete $args{default_resultset_class};

  $class->throw_exception('load_namespaces: unknown option(s): '
    . join(q{,}, map { qq{'$_'} } keys %args))
      if scalar keys %args;

  $default_resultset_class
    = $class->_expand_relative_name($default_resultset_class);

  for my $arg ($result_namespace, $resultset_namespace) {
    $arg = [ $arg ] if !ref($arg) && $arg;

    $class->throw_exception('load_namespaces: namespace arguments must be '
      . 'a simple string or an arrayref')
        if ref($arg) ne 'ARRAY';

    $_ = $class->_expand_relative_name($_) for (@$arg);
  }

  my %results = $class->_map_namespaces(@$result_namespace);
  my %resultsets = $class->_map_namespaces(@$resultset_namespace);

  my @to_register;
  {
    no warnings 'redefine';
    local *Class::C3::reinitialize = sub { };
    use warnings 'redefine';

    # ensure classes are loaded and attached in inheritance order
    $class->ensure_class_loaded($_) foreach(values %results);
    my %inh_idx;
    my @subclass_last = sort {

      ($inh_idx{$a} ||=
        scalar @{mro::get_linear_isa( $results{$a} )}
      )

          <=>

      ($inh_idx{$b} ||=
        scalar @{mro::get_linear_isa( $results{$b} )}
      )

    } keys(%results);

    foreach my $result (@subclass_last) {
      my $result_class = $results{$result};

      my $rs_class = delete $resultsets{$result};
      my $rs_set = $class->_ns_get_rsrc_instance ($result_class)->resultset_class;

      if($rs_set && $rs_set ne 'DBIx::Class::ResultSet') {
        if($rs_class && $rs_class ne $rs_set) {
          carp "We found ResultSet class '$rs_class' for '$result', but it seems "
             . "that you had already set '$result' to use '$rs_set' instead";
        }
      }
      elsif($rs_class ||= $default_resultset_class) {
        $class->ensure_class_loaded($rs_class);
        $class->_ns_get_rsrc_instance ($result_class)->resultset_class($rs_class);
      }

      my $source_name = $class->_ns_get_rsrc_instance ($result_class)->source_name || $result;

      push(@to_register, [ $source_name, $result_class ]);
    }
  }

  foreach (sort keys %resultsets) {
    carp "load_namespaces found ResultSet class $_ with no "
      . 'corresponding Result class';
  }

  Class::C3->reinitialize;
  $class->register_class(@$_) for (@to_register);

  return;
}

=head2 load_classes

=over 4

=item Arguments: @classes?, { $namespace => [ @classes ] }+

=back

L</load_classes> is an alternative method to L</load_namespaces>, both of
which serve similar purposes, each with different advantages and disadvantages.
In the general case you should use L</load_namespaces>, unless you need to
be able to specify that only specific classes are loaded at runtime.

With no arguments, this method uses L<Module::Find> to find all classes under
the schema's namespace. Otherwise, this method loads the classes you specify
(using L<use>), and registers them (using L</"register_class">).

It is possible to comment out classes with a leading C<#>, but note that perl
will think it's a mistake (trying to use a comment in a qw list), so you'll
need to add C<no warnings 'qw';> before your load_classes call.

If any classes found do not appear to be Result class files, you will
get the following warning:

   Failed to load $comp_class. Can't find source_name method. Is 
   $comp_class really a full DBIC result class? Fix it, move it elsewhere,
   or make your load_classes call more specific.

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
    my @comp = map { substr $_, length "${class}::"  }
                 $class->_findallmod;
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

        my $snsub = $comp_class->can('source_name');
        if(! $snsub ) {
          carp "Failed to load $comp_class. Can't find source_name method. Is $comp_class really a full DBIC result class? Fix it, move it elsewhere, or make your load_classes call more specific.";
          next;
        }
        $comp = $snsub->($comp_class) || $comp;

        push(@to_register, [ $comp, $comp_class ]);
      }
    }
  }
  Class::C3->reinitialize;

  foreach my $to (@to_register) {
    $class->register_class(@$to);
    #  if $class->can('result_source_instance');
  }
}

=head2 storage_type

=over 4

=item Arguments: $storage_type|{$storage_type, \%args}

=item Return value: $storage_type|{$storage_type, \%args}

=item Default value: DBIx::Class::Storage::DBI

=back

Set the storage class that will be instantiated when L</connect> is called.
If the classname starts with C<::>, the prefix C<DBIx::Class::Storage> is
assumed by L</connect>.  

You want to use this to set subclasses of L<DBIx::Class::Storage::DBI>
in cases where the appropriate subclass is not autodetected, such as
when dealing with MSSQL via L<DBD::Sybase>, in which case you'd set it
to C<::DBI::Sybase::MSSQL>.

If your storage type requires instantiation arguments, those are
defined as a second argument in the form of a hashref and the entire
value needs to be wrapped into an arrayref or a hashref.  We support
both types of refs here in order to play nice with your
Config::[class] or your choice. See
L<DBIx::Class::Storage::DBI::Replicated> for an example of this.

=head2 exception_action

=over 4

=item Arguments: $code_reference

=item Return value: $code_reference

=item Default value: None

=back

If C<exception_action> is set for this class/object, L</throw_exception>
will prefer to call this code reference with the exception as an argument,
rather than L<DBIx::Class::Exception/throw>.

Your subroutine should probably just wrap the error in the exception
object/class of your choosing and rethrow.  If, against all sage advice,
you'd like your C<exception_action> to suppress a particular exception
completely, simply have it return true.

Example:

   package My::Schema;
   use base qw/DBIx::Class::Schema/;
   use My::ExceptionClass;
   __PACKAGE__->exception_action(sub { My::ExceptionClass->throw(@_) });
   __PACKAGE__->load_classes;

   # or:
   my $schema_obj = My::Schema->connect( .... );
   $schema_obj->exception_action(sub { My::ExceptionClass->throw(@_) });

   # suppress all exceptions, like a moron:
   $schema_obj->exception_action(sub { 1 });

=head2 stacktrace

=over 4

=item Arguments: boolean

=back

Whether L</throw_exception> should include stack trace information.
Defaults to false normally, but defaults to true if C<$ENV{DBIC_TRACE}>
is true.

=head2 sqlt_deploy_hook

=over

=item Arguments: $sqlt_schema

=back

An optional sub which you can declare in your own Schema class that will get 
passed the L<SQL::Translator::Schema> object when you deploy the schema via
L</create_ddl_dir> or L</deploy>.

For an example of what you can do with this, see 
L<DBIx::Class::Manual::Cookbook/Adding Indexes And Functions To Your SQL>.

Note that sqlt_deploy_hook is called by L</deployment_statements>, which in turn
is called before L</deploy>. Therefore the hook can be used only to manipulate
the L<SQL::Translator::Schema> object before it is turned into SQL fed to the
database. If you want to execute post-deploy statements which can not be generated
by L<SQL::Translator>, the currently suggested method is to overload L</deploy>
and use L<dbh_do|DBIx::Class::Storage::DBI/dbh_do>.

=head1 METHODS

=head2 connect

=over 4

=item Arguments: @connectinfo

=item Return Value: $new_schema

=back

Creates and returns a new Schema object. The connection info set on it
is used to create a new instance of the storage backend and set it on
the Schema object.

See L<DBIx::Class::Storage::DBI/"connect_info"> for DBI-specific
syntax on the C<@connectinfo> argument, or L<DBIx::Class::Storage> in
general.

Note that C<connect_info> expects an arrayref of arguments, but
C<connect> does not. C<connect> wraps its arguments in an arrayref
before passing them to C<connect_info>.

=head3 Overloading

C<connect> is a convenience method. It is equivalent to calling
$schema->clone->connection(@connectinfo). To write your own overloaded
version, overload L</connection> instead.

=cut

sub connect { shift->clone->connection(@_) }

=head2 resultset

=over 4

=item Arguments: $source_name

=item Return Value: $resultset

=back

  my $rs = $schema->resultset('DVD');

Returns the L<DBIx::Class::ResultSet> object for the registered source
name.

=cut

sub resultset {
  my ($self, $moniker) = @_;
  $self->throw_exception('resultset() expects a source name')
    unless defined $moniker;
  return $self->source($moniker)->resultset;
}

=head2 sources

=over 4

=item Return Value: @source_names

=back

  my @source_names = $schema->sources;

Lists names of all the sources registered on this Schema object.

=cut

sub sources { return keys %{shift->source_registrations}; }

=head2 source

=over 4

=item Arguments: $source_name

=item Return Value: $result_source

=back

  my $source = $schema->source('Book');

Returns the L<DBIx::Class::ResultSource> object for the registered
source name.

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

=head2 class

=over 4

=item Arguments: $source_name

=item Return Value: $classname

=back

  my $class = $schema->class('CD');

Retrieves the Result class name for the given source name.

=cut

sub class {
  my ($self, $moniker) = @_;
  return $self->source($moniker)->result_class;
}

=head2 txn_do

=over 4

=item Arguments: C<$coderef>, @coderef_args?

=item Return Value: The return value of $coderef

=back

Executes C<$coderef> with (optional) arguments C<@coderef_args> atomically,
returning its result (if any). Equivalent to calling $schema->storage->txn_do.
See L<DBIx::Class::Storage/"txn_do"> for more information.

This interface is preferred over using the individual methods L</txn_begin>,
L</txn_commit>, and L</txn_rollback> below.

WARNING: If you are connected with C<AutoCommit => 0> the transaction is
considered nested, and you will still need to call L</txn_commit> to write your
changes when appropriate. You will also want to connect with C<auto_savepoint =>
1> to get partial rollback to work, if the storage driver for your database
supports it.

Connecting with C<AutoCommit => 1> is recommended.

=cut

sub txn_do {
  my $self = shift;

  $self->storage or $self->throw_exception
    ('txn_do called on $schema without storage');

  $self->storage->txn_do(@_);
}

=head2 txn_scope_guard

Runs C<txn_scope_guard> on the schema's storage. See 
L<DBIx::Class::Storage/txn_scope_guard>.

=cut

sub txn_scope_guard {
  my $self = shift;

  $self->storage or $self->throw_exception
    ('txn_scope_guard called on $schema without storage');

  $self->storage->txn_scope_guard(@_);
}

=head2 txn_begin

Begins a transaction (does nothing if AutoCommit is off). Equivalent to
calling $schema->storage->txn_begin. See
L<DBIx::Class::Storage::DBI/"txn_begin"> for more information.

=cut

sub txn_begin {
  my $self = shift;

  $self->storage or $self->throw_exception
    ('txn_begin called on $schema without storage');

  $self->storage->txn_begin;
}

=head2 txn_commit

Commits the current transaction. Equivalent to calling
$schema->storage->txn_commit. See L<DBIx::Class::Storage::DBI/"txn_commit">
for more information.

=cut

sub txn_commit {
  my $self = shift;

  $self->storage or $self->throw_exception
    ('txn_commit called on $schema without storage');

  $self->storage->txn_commit;
}

=head2 txn_rollback

Rolls back the current transaction. Equivalent to calling
$schema->storage->txn_rollback. See
L<DBIx::Class::Storage::DBI/"txn_rollback"> for more information.

=cut

sub txn_rollback {
  my $self = shift;

  $self->storage or $self->throw_exception
    ('txn_rollback called on $schema without storage');

  $self->storage->txn_rollback;
}

=head2 storage

  my $storage = $schema->storage;

Returns the L<DBIx::Class::Storage> object for this Schema. Grab this
if you want to turn on SQL statement debugging at runtime, or set the
quote character. For the default storage, the documentation can be
found in L<DBIx::Class::Storage::DBI>.

=head2 populate

=over 4

=item Arguments: $source_name, \@data;

=item Return value: \@$objects | nothing

=back

Pass this method a resultsource name, and an arrayref of
arrayrefs. The arrayrefs should contain a list of column names,
followed by one or many sets of matching data for the given columns. 

In void context, C<insert_bulk> in L<DBIx::Class::Storage::DBI> is used
to insert the data, as this is a fast method. However, insert_bulk currently
assumes that your datasets all contain the same type of values, using scalar
references in a column in one row, and not in another will probably not work.

Otherwise, each set of data is inserted into the database using
L<DBIx::Class::ResultSet/create>, and a arrayref of the resulting row
objects is returned.

i.e.,

  $schema->populate('Artist', [
    [ qw/artistid name/ ],
    [ 1, 'Popular Band' ],
    [ 2, 'Indie Band' ],
    ...
  ]);

Since wantarray context is basically the same as looping over $rs->create(...) 
you won't see any performance benefits and in this case the method is more for
convenience. Void context sends the column information directly to storage
using <DBI>s bulk insert method. So the performance will be much better for 
storages that support this method.

Because of this difference in the way void context inserts rows into your 
database you need to note how this will effect any loaded components that
override or augment insert.  For example if you are using a component such 
as L<DBIx::Class::UUIDColumns> to populate your primary keys you MUST use 
wantarray context if you want the PKs automatically created.

=cut

sub populate {
  my ($self, $name, $data) = @_;
  if(my $rs = $self->resultset($name)) {
    if(defined wantarray) {
        return $rs->populate($data);
    } else {
        $rs->populate($data);
    }
  } else {
      $self->throw_exception("$name is not a resultset"); 
  }
}

=head2 connection

=over 4

=item Arguments: @args

=item Return Value: $new_schema

=back

Similar to L</connect> except sets the storage object and connection
data in-place on the Schema class. You should probably be calling
L</connect> to get a proper Schema object instead.

=head3 Overloading

Overload C<connection> to change the behaviour of C<connect>.

=cut

sub connection {
  my ($self, @info) = @_;
  return $self if !@info && $self->storage;

  my ($storage_class, $args) = ref $self->storage_type ? 
    ($self->_normalize_storage_type($self->storage_type),{}) : ($self->storage_type, {});

  $storage_class = 'DBIx::Class::Storage'.$storage_class
    if $storage_class =~ m/^::/;
  eval { $self->ensure_class_loaded ($storage_class) };
  $self->throw_exception(
    "No arguments to load_classes and couldn't load ${storage_class} ($@)"
  ) if $@;
  my $storage = $storage_class->new($self=>$args);
  $storage->connect_info(\@info);
  $self->storage($storage);
  return $self;
}

sub _normalize_storage_type {
  my ($self, $storage_type) = @_;
  if(ref $storage_type eq 'ARRAY') {
    return @$storage_type;
  } elsif(ref $storage_type eq 'HASH') {
    return %$storage_type;
  } else {
    $self->throw_exception('Unsupported REFTYPE given: '. ref $storage_type);
  }
}

=head2 compose_namespace

=over 4

=item Arguments: $target_namespace, $additional_base_class?

=item Retur Value: $new_schema

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

# this might be oversimplified
# sub compose_namespace {
#   my ($self, $target, $base) = @_;

#   my $schema = $self->clone;
#   foreach my $moniker ($schema->sources) {
#     my $source = $schema->source($moniker);
#     my $target_class = "${target}::${moniker}";
#     $self->inject_base(
#       $target_class => $source->result_class, ($base ? $base : ())
#     );
#     $source->result_class($target_class);
#     $target_class->result_source_instance($source)
#       if $target_class->can('result_source_instance');
#     $schema->register_source($moniker, $source);
#   }
#   return $schema;
# }

sub compose_namespace {
  my ($self, $target, $base) = @_;
  my $schema = $self->clone;
  {
    no warnings qw/redefine/;
#    local *Class::C3::reinitialize = sub { };
    foreach my $moniker ($schema->sources) {
      my $source = $schema->source($moniker);
      my $target_class = "${target}::${moniker}";
      $self->inject_base(
        $target_class => $source->result_class, ($base ? $base : ())
      );
      $source->result_class($target_class);
      $target_class->result_source_instance($source)
        if $target_class->can('result_source_instance');
     $schema->register_source($moniker, $source);
    }
  }
#  Class::C3->reinitialize();
  {
    no strict 'refs';
    no warnings 'redefine';
    foreach my $meth (qw/class source resultset/) {
      *{"${target}::${meth}"} =
        sub { shift->schema->$meth(@_) };
    }
  }
  return $schema;
}

sub setup_connection_class {
  my ($class, $target, @info) = @_;
  $class->inject_base($target => 'DBIx::Class::DB');
  #$target->load_components('DB');
  $target->connection(@info);
}

=head2 svp_begin

Creates a new savepoint (does nothing outside a transaction). 
Equivalent to calling $schema->storage->svp_begin.  See
L<DBIx::Class::Storage::DBI/"svp_begin"> for more information.

=cut

sub svp_begin {
  my ($self, $name) = @_;

  $self->storage or $self->throw_exception
    ('svp_begin called on $schema without storage');

  $self->storage->svp_begin($name);
}

=head2 svp_release

Releases a savepoint (does nothing outside a transaction). 
Equivalent to calling $schema->storage->svp_release.  See
L<DBIx::Class::Storage::DBI/"svp_release"> for more information.

=cut

sub svp_release {
  my ($self, $name) = @_;

  $self->storage or $self->throw_exception
    ('svp_release called on $schema without storage');

  $self->storage->svp_release($name);
}

=head2 svp_rollback

Rollback to a savepoint (does nothing outside a transaction). 
Equivalent to calling $schema->storage->svp_rollback.  See
L<DBIx::Class::Storage::DBI/"svp_rollback"> for more information.

=cut

sub svp_rollback {
  my ($self, $name) = @_;

  $self->storage or $self->throw_exception
    ('svp_rollback called on $schema without storage');

  $self->storage->svp_rollback($name);
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
  my $clone = { (ref $self ? %$self : ()) };
  bless $clone, (ref $self || $self);

  $clone->class_mappings({ %{$clone->class_mappings} });
  $clone->source_registrations({ %{$clone->source_registrations} });
  foreach my $moniker ($self->sources) {
    my $source = $self->source($moniker);
    my $new = $source->new($source);
    # we use extra here as we want to leave the class_mappings as they are
    # but overwrite the source_registrations entry with the new source
    $clone->register_extra_source($moniker => $new);
  }
  $clone->storage->set_schema($clone) if $clone->storage;
  return $clone;
}

=head2 throw_exception

=over 4

=item Arguments: $message

=back

Throws an exception. Defaults to using L<Carp::Clan> to report errors from
user's perspective.  See L</exception_action> for details on overriding
this method's behavior.  If L</stacktrace> is turned on, C<throw_exception>'s
default behavior will provide a detailed stack trace.

=cut

sub throw_exception {
  my $self = shift;

  DBIx::Class::Exception->throw($_[0], $self->stacktrace)
    if !$self->exception_action || !$self->exception_action->(@_);
}

=head2 deploy

=over 4

=item Arguments: \%sqlt_args, $dir

=back

Attempts to deploy the schema to the current storage using L<SQL::Translator>.

See L<SQL::Translator/METHODS> for a list of values for C<\%sqlt_args>.
The most common value for this would be C<< { add_drop_table => 1 } >>
to have the SQL produced include a C<DROP TABLE> statement for each table
created. For quoting purposes supply C<quote_table_names> and
C<quote_field_names>.

Additionally, the DBIx::Class parser accepts a C<sources> parameter as a hash 
ref or an array ref, containing a list of source to deploy. If present, then 
only the sources listed will get deployed. Furthermore, you can use the
C<add_fk_index> parser parameter to prevent the parser from creating an index for each
FK.

=cut

sub deploy {
  my ($self, $sqltargs, $dir) = @_;
  $self->throw_exception("Can't deploy without storage") unless $self->storage;
  $self->storage->deploy($self, undef, $sqltargs, $dir);
}

=head2 deployment_statements

=over 4

=item Arguments: See L<DBIx::Class::Storage::DBI/deployment_statements>

=item Return value: $listofstatements

=back

A convenient shortcut to
C<< $self->storage->deployment_statements($self, @args) >>.
Returns the SQL statements used by L</deploy> and
L<DBIx::Class::Schema::Storage/deploy>.

=cut

sub deployment_statements {
  my $self = shift;

  $self->throw_exception("Can't generate deployment statements without a storage")
    if not $self->storage;

  $self->storage->deployment_statements($self, @_);
}

=head2 create_ddl_dir (EXPERIMENTAL)

=over 4

=item Arguments: See L<DBIx::Class::Storage::DBI/create_ddl_dir>

=back

A convenient shortcut to 
C<< $self->storage->create_ddl_dir($self, @args) >>.

Creates an SQL file based on the Schema, for each of the specified
database types, in the given directory.

=cut

sub create_ddl_dir {
  my $self = shift;

  $self->throw_exception("Can't create_ddl_dir without storage") unless $self->storage;
  $self->storage->create_ddl_dir($self, @_);
}

=head2 ddl_filename

=over 4

=item Arguments: $database-type, $version, $directory, $preversion

=item Return value: $normalised_filename

=back

  my $filename = $table->ddl_filename($type, $version, $dir, $preversion)

This method is called by C<create_ddl_dir> to compose a file name out of
the supplied directory, database type and version number. The default file
name format is: C<$dir$schema-$version-$type.sql>.

You may override this method in your schema if you wish to use a different
format.

 WARNING

 Prior to DBIx::Class version 0.08100 this method had a different signature:

    my $filename = $table->ddl_filename($type, $dir, $version, $preversion)

 In recent versions variables $dir and $version were reversed in order to
 bring the signature in line with other Schema/Storage methods. If you 
 really need to maintain backward compatibility, you can do the following
 in any overriding methods:

    ($dir, $version) = ($version, $dir) if ($DBIx::Class::VERSION < 0.08100);

=cut

sub ddl_filename {
  my ($self, $type, $version, $dir, $preversion) = @_;

  my $filename = ref($self);
  $filename =~ s/::/-/g;
  $filename = File::Spec->catfile($dir, "$filename-$version-$type.sql");
  $filename =~ s/$version/$preversion-$version/ if($preversion);

  return $filename;
}

=head2 thaw

Provided as the recommended way of thawing schema objects. You can call 
C<Storable::thaw> directly if you wish, but the thawed objects will not have a
reference to any schema, so are rather useless

=cut

sub thaw {
  my ($self, $obj) = @_;
  local $DBIx::Class::ResultSourceHandle::thaw_schema = $self;
  return Storable::thaw($obj);
}

=head2 freeze

This doesn't actualy do anything more than call L<Storable/freeze>, it is just
provided here for symetry.

=cut

sub freeze {
  return Storable::freeze($_[1]);
}

=head2 dclone

Recommeneded way of dcloning objects. This is needed to properly maintain
references to the schema object (which itself is B<not> cloned.)

=cut

sub dclone {
  my ($self, $obj) = @_;
  local $DBIx::Class::ResultSourceHandle::thaw_schema = $self;
  return Storable::dclone($obj);
}

=head2 schema_version

Returns the current schema class' $VERSION in a normalised way.

=cut

sub schema_version {
  my ($self) = @_;
  my $class = ref($self)||$self;

  # does -not- use $schema->VERSION
  # since that varies in results depending on if version.pm is installed, and if
  # so the perl or XS versions. If you want this to change, bug the version.pm
  # author to make vpp and vxs behave the same.

  my $version;
  {
    no strict 'refs';
    $version = ${"${class}::VERSION"};
  }
  return $version;
}


=head2 register_class

=over 4

=item Arguments: $moniker, $component_class

=back

This method is called by L</load_namespaces> and L</load_classes> to install the found classes into your Schema. You should be using those instead of this one. 

You will only need this method if you have your Result classes in
files which are not named after the packages (or all in the same
file). You may also need it to register classes at runtime.

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

This method is called by L</register_class>.

Registers the L<DBIx::Class::ResultSource> in the schema with the given
moniker.

=cut

sub register_source {
  my $self = shift;

  $self->_register_source(@_);
}

=head2 register_extra_source

=over 4

=item Arguments: $moniker, $result_source

=back

As L</register_source> but should be used if the result class already 
has a source and you want to register an extra one.

=cut

sub register_extra_source {
  my $self = shift;

  $self->_register_source(@_, { extra => 1 });
}

sub _register_source {
  my ($self, $moniker, $source, $params) = @_;

  my $orig_source = $source;

  $source = $source->new({ %$source, source_name => $moniker });
  $source->schema($self);
  weaken($source->{schema}) if ref($self);

  my $rs_class = $source->result_class;

  my %reg = %{$self->source_registrations};
  $reg{$moniker} = $source;
  $self->source_registrations(\%reg);

  return if ($params->{extra});
  return unless defined($rs_class) && $rs_class->can('result_source_instance');

  my %map = %{$self->class_mappings};
  if (
    exists $map{$rs_class}
      and
    $map{$rs_class} ne $moniker
      and
    $rs_class->result_source_instance ne $orig_source
  ) {
    carp "$rs_class already has a source, use register_extra_source for additional sources";
  }
  $map{$rs_class} = $moniker;
  $self->class_mappings(\%map);
}

sub _unregister_source {
    my ($self, $moniker) = @_;
    my %reg = %{$self->source_registrations}; 

    my $source = delete $reg{$moniker};
    $self->source_registrations(\%reg);
    if ($source->result_class) {
        my %map = %{$self->class_mappings};
        delete $map{$source->result_class};
        $self->class_mappings(\%map);
    }
}


=head2 compose_connection (DEPRECATED)

=over 4

=item Arguments: $target_namespace, @db_info

=item Return Value: $new_schema

=back

DEPRECATED. You probably wanted compose_namespace.

Actually, you probably just wanted to call connect.

=begin hidden

(hidden due to deprecation)

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

=end hidden

=cut

{
  my $warn;

  sub compose_connection {
    my ($self, $target, @info) = @_;

    carp "compose_connection deprecated as of 0.08000"
      unless ($INC{"DBIx/Class/CDBICompat.pm"} || $warn++);

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
      my $name = join '::', $target, 'schema';
      *$name = Sub::Name::subname $name, sub { $schema };
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
}

1;

=head1 AUTHORS

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut
