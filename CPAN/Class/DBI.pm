package Class::DBI::__::Base;

require 5.00502;

use Class::Trigger 0.07;
use base qw(Class::Accessor Class::Data::Inheritable Ima::DBI);

package Class::DBI;

use strict;

use base "Class::DBI::__::Base";

use vars qw($VERSION);
$VERSION = '0.96';

use Class::DBI::ColumnGrouper;
use Class::DBI::Query;
use Carp ();
use List::Util;
use UNIVERSAL::moniker;

use vars qw($Weaken_Is_Available);

BEGIN {
	$Weaken_Is_Available = 1;
	eval {
		require Scalar::Util;
		import Scalar::Util qw(weaken);
	};
	if ($@) {
		$Weaken_Is_Available = 0;
	}
}

use overload
	'""'     => sub { shift->stringify_self },
	bool     => sub { not shift->_undefined_primary },
	fallback => 1;

sub stringify_self {
	my $self = shift;
	return (ref $self || $self) unless $self;    # empty PK
	my @cols = $self->columns('Stringify');
	@cols = $self->primary_columns unless @cols;
	return join "/", $self->get(@cols);
}

sub _undefined_primary {
	my $self = shift;
	return grep !defined, $self->_attrs($self->primary_columns);
}

{
	my %deprecated = (
		croak            => "_croak",               # 0.89
		carp             => "_carp",                # 0.89
		min              => "minimum_value_of",     # 0.89
		max              => "maximum_value_of",     # 0.89
		normalize_one    => "_normalize_one",       # 0.89
		_primary         => "primary_column",       # 0.90
		primary          => "primary_column",       # 0.89
		primary_key      => "primary_column",       # 0.90
		essential        => "_essential",           # 0.89
		column_type      => "has_a",                # 0.90
		associated_class => "has_a",                # 0.90
		is_column        => "find_column",          # 0.90
		has_column       => "find_column",          # 0.94
		add_hook         => "add_trigger",          # 0.90
		run_sql          => "retrieve_from_sql",    # 0.90
		rollback         => "discard_changes",      # 0.91
		commit           => "update",               # 0.91
		autocommit       => "autoupdate",           # 0.91
		new              => 'create',               # 0.93
		_commit_vals     => '_update_vals',         # 0.91
		_commit_line     => '_update_line',         # 0.91
		make_filter      => 'add_constructor',      # 0.93
	);

	no strict 'refs';
	while (my ($old, $new) = each %deprecated) {
		*$old = sub {
			my @caller = caller;
			warn
				"Use of '$old' is deprecated at $caller[1] line $caller[2]. Use '$new' instead\n";
			goto &$new;
		};
	}
}

sub normalize      { shift->_carp("normalize is deprecated") }         # 0.94
sub normalize_hash { shift->_carp("normalize_hash is deprecated") }    # 0.94

#----------------------------------------------------------------------
# Our Class Data
#----------------------------------------------------------------------
__PACKAGE__->mk_classdata('__AutoCommit');
__PACKAGE__->mk_classdata('__hasa_list');
__PACKAGE__->mk_classdata('_table');
__PACKAGE__->mk_classdata('_table_alias');
__PACKAGE__->mk_classdata('sequence');
__PACKAGE__->mk_classdata('__grouper');
__PACKAGE__->mk_classdata('__data_type');
__PACKAGE__->mk_classdata('__driver');
__PACKAGE__->__data_type({});

__PACKAGE__->mk_classdata('iterator_class');
__PACKAGE__->iterator_class('Class::DBI::Iterator');
__PACKAGE__->__grouper(Class::DBI::ColumnGrouper->new());

__PACKAGE__->mk_classdata('purge_object_index_every');
__PACKAGE__->purge_object_index_every(1000);

__PACKAGE__->add_relationship_type(
	has_a      => "Class::DBI::Relationship::HasA",
	has_many   => "Class::DBI::Relationship::HasMany",
	might_have => "Class::DBI::Relationship::MightHave",
);
__PACKAGE__->mk_classdata('__meta_info');
__PACKAGE__->__meta_info({});

#----------------------------------------------------------------------
# SQL we'll need
#----------------------------------------------------------------------
__PACKAGE__->set_sql(MakeNewObj => <<'');
INSERT INTO __TABLE__ (%s)
VALUES (%s)

__PACKAGE__->set_sql(update => <<"");
UPDATE __TABLE__
SET    %s
WHERE  __IDENTIFIER__

__PACKAGE__->set_sql(Nextval => <<'');
SELECT NEXTVAL ('%s')

__PACKAGE__->set_sql(SearchSQL => <<'');
SELECT %s
FROM   %s
WHERE  %s

__PACKAGE__->set_sql(RetrieveAll => <<'');
SELECT __ESSENTIAL__
FROM   __TABLE__

__PACKAGE__->set_sql(Retrieve => <<'');
SELECT __ESSENTIAL__
FROM   __TABLE__
WHERE  %s

__PACKAGE__->set_sql(Flesh => <<'');
SELECT %s
FROM   __TABLE__
WHERE  __IDENTIFIER__

__PACKAGE__->set_sql(single => <<'');
SELECT %s
FROM   __TABLE__

__PACKAGE__->set_sql(DeleteMe => <<"");
DELETE
FROM   __TABLE__
WHERE  __IDENTIFIER__


# Override transform_sql from Ima::DBI to provide some extra
# transformations
sub transform_sql {
	my ($self, $sql, @args) = @_;

	my %cmap;
	my $expand_table = sub {
		my ($class, $alias) = split /=/, shift, 2;
		my $table = $class ? $class->table : $self->table;
		$cmap{ $alias || $table } = $class || ref $self || $self;
		($alias ||= "") &&= " AS $alias";
		return $table . $alias;
	};

	my $expand_join = sub {
		my $joins  = shift;
		my @table  = split /\s+/, $joins;
		my %tojoin = map { $table[$_] => $table[ $_ + 1 ] } 0 .. $#table - 1;
		my @sql;
		while (my ($t1, $t2) = each %tojoin) {
			my ($c1, $c2) = map $cmap{$_}
				|| $self->_croak("Don't understand table '$_' in JOIN"), ($t1, $t2);

			my $join_col = sub {
				my ($c1, $c2) = @_;
				my $meta = $c1->meta_info('has_a');
				my ($col) = grep $meta->{$_}->foreign_class eq $c2, keys %$meta;
				$col;
			};

			my $col = $join_col->($c1 => $c2) || do {
				($c1, $c2) = ($c2, $c1);
				($t1, $t2) = ($t2, $t1);
				$join_col->($c1 => $c2);
			};

			$self->_croak("Don't know how to join $c1 to $c2") unless $col;
			push @sql, sprintf " %s.%s = %s.%s ", $t1, $col, $t2,
				$c2->primary_column;
		}
		return join " AND ", @sql;
	};

	$sql =~ s/__TABLE\(?(.*?)\)?__/$expand_table->($1)/eg;
	$sql =~ s/__JOIN\((.*?)\)__/$expand_join->($1)/eg;
	$sql =~ s/__ESSENTIAL__/join ", ", $self->_essential/eg;
	$sql =~
		s/__ESSENTIAL\((.*?)\)__/join ", ", map "$1.$_", $self->_essential/eg;
	if ($sql =~ /__IDENTIFIER__/) {
		my $key_sql = join " AND ", map "$_=?", $self->primary_columns;
		$sql =~ s/__IDENTIFIER__/$key_sql/g;
	}
	return $self->SUPER::transform_sql($sql => @args);
}

#----------------------------------------------------------------------
# EXCEPTIONS
#----------------------------------------------------------------------

sub _carp {
	my ($self, $msg) = @_;
	Carp::carp($msg || $self);
	return;
}

sub _croak {
	my ($self, $msg) = @_;
	Carp::croak($msg || $self);
}

#----------------------------------------------------------------------
# SET UP
#----------------------------------------------------------------------

sub connection {
	my $class = shift;
	$class->set_db(Main => @_);
}

{
	my %Per_DB_Attr_Defaults = (
		pg     => { AutoCommit => 0 },
		oracle => { AutoCommit => 0 },
	);

	sub _default_attributes {
		my $class = shift;
		return (
			$class->SUPER::_default_attributes,
			FetchHashKeyName   => 'NAME_lc',
			ShowErrorStatement => 1,
			AutoCommit         => 1,
			ChopBlanks         => 1,
			%{ $Per_DB_Attr_Defaults{ lc $class->__driver } || {} },
		);
	}
}

sub set_db {
	my ($class, $db_name, $data_source, $user, $password, $attr) = @_;

	# 'dbi:Pg:dbname=foo' we want 'Pg'. I think this is enough.
	my ($driver) = $data_source =~ /^dbi:(\w+)/i;
	$class->__driver($driver);
	$class->SUPER::set_db('Main', $data_source, $user, $password, $attr);
}

sub table {
	my ($proto, $table, $alias) = @_;
	my $class = ref $proto || $proto;
	$class->_table($table)      if $table;
	$class->table_alias($alias) if $alias;
	return $class->_table || $class->_table($class->table_alias);
}

sub table_alias {
	my ($proto, $alias) = @_;
	my $class = ref $proto || $proto;
	$class->_table_alias($alias) if $alias;
	return $class->_table_alias || $class->_table_alias($class->moniker);
}

sub columns {
	my $proto = shift;
	my $class = ref $proto || $proto;
	my $group = shift || "All";
	return $class->_set_columns($group => @_) if @_;
	return $class->all_columns    if $group eq "All";
	return $class->primary_column if $group eq "Primary";
	return $class->_essential     if $group eq "Essential";
	return $class->__grouper->group_cols($group);
}

sub _set_columns {
	my ($class, $group, @columns) = @_;

	# Careful to take copy
	$class->__grouper(Class::DBI::ColumnGrouper->clone($class->__grouper)
			->add_group($group => @columns));
	$class->_mk_column_accessors(@columns);
	return @columns;
}

sub all_columns { shift->__grouper->all_columns }

sub id {
	my $self  = shift;
	my $class = ref($self)
		or return $self->_croak("Can't call id() as a class method");

	# we don't use get() here because all objects should have
	# exisitng values for PK columns, or else loop endlessly
	my @pk_values = $self->_attrs($self->primary_columns);
	return @pk_values if wantarray;
	$self->_croak(
		"id called in scalar context for class with multiple primary key columns")
		if @pk_values > 1;
	return $pk_values[0];
}

sub primary_column {
	my $self            = shift;
	my @primary_columns = $self->__grouper->primary;
	return @primary_columns if wantarray;
	$self->_carp(
		ref($self)
			. " has multiple primary columns, but fetching in scalar context")
		if @primary_columns > 1;
	return $primary_columns[0];
}
*primary_columns = \&primary_column;

sub _essential { shift->__grouper->essential }

sub find_column {
	my ($class, $want) = @_;
	return $class->__grouper->find_column($want);
}

sub _find_columns {
	my $class = shift;
	my $cg    = $class->__grouper;
	return map $cg->find_column($_), @_;
}

sub has_real_column {    # is really in the database
	my ($class, $want) = @_;
	return ($class->find_column($want) || return)->in_database;
}

sub data_type {
	my $class    = shift;
	my %datatype = @_;
	while (my ($col, $type) = each %datatype) {
		$class->_add_data_type($col, $type);
	}
}

sub _add_data_type {
	my ($class, $col, $type) = @_;
	my $datatype = $class->__data_type;
	$datatype->{$col} = $type;
	$class->__data_type($datatype);
}

# Make a set of accessors for each of a list of columns. We construct
# the method name by calling accessor_name() and mutator_name() with the
# normalized column name.

# mutator_name will be the same as accessor_name unless you override it.

# If both the accessor and mutator are to have the same method name,
# (which will always be true unless you override mutator_name), a read-write
# method is constructed for it. If they differ we create both a read-only
# accessor and a write-only mutator.

sub _mk_column_accessors {
	my $class = shift;
	foreach my $obj ($class->_find_columns(@_)) {
		my %method = (
			ro => $obj->accessor($class->accessor_name($obj->name)),
			wo => $obj->mutator($class->mutator_name($obj->name)),
		);
		my $both = ($method{ro} eq $method{wo});
		foreach my $type (keys %method) {
			my $name     = $method{$type};
			my $acc_type = $both ? "make_accessor" : "make_${type}_accessor";
			my $accessor = $class->$acc_type($obj->name_lc);
			$class->_make_method($_, $accessor) for ($name, "_${name}_accessor");
		}
	}
}

sub _make_method {
	my ($class, $name, $method) = @_;
	return if defined &{"$class\::$name"};
	$class->_carp("Column '$name' in $class clashes with built-in method")
		if Class::DBI->can($name)
		and not($name eq "id" and join(" ", $class->primary_columns) eq "id");
	no strict 'refs';
	*{"$class\::$name"} = $method;
	$class->_make_method(lc $name => $method);
}

sub accessor_name {
	my ($class, $column) = @_;
	return $column;
}

sub mutator_name {
	my ($class, $column) = @_;
	return $class->accessor_name($column);
}

sub autoupdate {
	my $proto = shift;
	ref $proto ? $proto->_obj_autoupdate(@_) : $proto->_class_autoupdate(@_);
}

sub _obj_autoupdate {
	my ($self, $set) = @_;
	my $class = ref $self;
	$self->{__AutoCommit} = $set if defined $set;
	defined $self->{__AutoCommit}
		? $self->{__AutoCommit}
		: $class->_class_autoupdate;
}

sub _class_autoupdate {
	my ($class, $set) = @_;
	$class->__AutoCommit($set) if defined $set;
	return $class->__AutoCommit;
}

sub make_read_only {
	my $proto = shift;
	$proto->add_trigger("before_$_" => sub { _croak "$proto is read only" })
		foreach qw/create delete update/;
	return $proto;
}

sub find_or_create {
	my $class    = shift;
	my $hash     = ref $_[0] eq "HASH" ? shift: {@_};
	my ($exists) = $class->search($hash);
	return defined($exists) ? $exists : $class->create($hash);
}

sub create {
	my $class = shift;
	return $class->_croak("create needs a hashref") unless ref $_[0] eq 'HASH';
	my $info = { %{ +shift } };    # make sure we take a copy

	my $data;
	while (my ($k, $v) = each %$info) {
		my $col = $class->find_column($k)
			|| (List::Util::first { $_->mutator  eq $k } $class->columns)
			|| (List::Util::first { $_->accessor eq $k } $class->columns)
			|| $class->_croak("$k is not a column of $class");
		$data->{$col} = $v;
	}

	$class->normalize_column_values($data);
	$class->validate_column_values($data);
	return $class->_create($data);
}

sub _attrs {
	my ($self, @atts) = @_;
	return @{$self}{@atts};
}
*_attr = \&_attrs;

sub _attribute_store {
	my $self   = shift;
	my $vals   = @_ == 1 ? shift: {@_};
	my (@cols) = keys %$vals;
	@{$self}{@cols} = @{$vals}{@cols};
}

# If you override this method, you must use the same mechanism to log changes
# for future updates, as other parts of Class::DBI depend on it.
sub _attribute_set {
	my $self = shift;
	my $vals = @_ == 1 ? shift: {@_};

	# We increment instead of setting to 1 because it might be useful to
	# someone to know how many times a value has changed between updates.
	for my $col (keys %$vals) { $self->{__Changed}{$col}++; }
	$self->_attribute_store($vals);
}

sub _attribute_delete {
	my ($self, @attributes) = @_;
	delete @{$self}{@attributes};
}

sub _attribute_exists {
	my ($self, $attribute) = @_;
	exists $self->{$attribute};
}

# keep an index of live objects using weak refs
my %Live_Objects;
my $Init_Count = 0;

sub _init {
	my $class = shift;
	my $data = shift || {};
	my $obj;
	my $obj_key = "";

	my @primary_columns = $class->primary_columns;
	if (@primary_columns == grep defined, @{$data}{@primary_columns}) {

		# create single unique key for this object
		$obj_key = join "|", $class, map { $_ . '=' . $data->{$_} }
			sort @primary_columns;
	}

	unless (defined($obj = $Live_Objects{$obj_key})) {

		# not in the object_index, or we don't have all keys yet
		$obj = bless {}, $class;
		$obj->_attribute_store(%$data);

		# don't store it unless all keys are present
		if ($obj_key && $Weaken_Is_Available) {
			weaken($Live_Objects{$obj_key} = $obj);

			# time to clean up your room?
			$class->purge_dead_from_object_index
				if ++$Init_Count % $class->purge_object_index_every == 0;
		}
	}

	return $obj;
}

sub purge_dead_from_object_index {
	delete @Live_Objects{ grep !defined $Live_Objects{$_}, keys %Live_Objects };
}

sub remove_from_object_index {
	my $self            = shift;
	my @primary_columns = $self->primary_columns;
	my %data;
	@data{@primary_columns} = $self->get(@primary_columns);
	my $obj_key = join "|", ref $self, map $_ . '=' . $data{$_},
		sort @primary_columns;
	delete $Live_Objects{$obj_key};
}

sub clear_object_index {
	%Live_Objects = ();
}

sub _prepopulate_id {
	my $self            = shift;
	my @primary_columns = $self->primary_columns;
	return $self->_croak(
		sprintf "Can't create %s object with null primary key columns (%s)",
		ref $self, $self->_undefined_primary)
		if @primary_columns > 1;
	$self->_attribute_store($primary_columns[0] => $self->_next_in_sequence)
		if $self->sequence;
}

sub _create {
	my ($proto, $data) = @_;
	my $class = ref $proto || $proto;

	my $self = $class->_init($data);
	$self->call_trigger('before_create');
	$self->call_trigger('deflate_for_create');

	$self->_prepopulate_id if $self->_undefined_primary;

	# Reinstate data
	my ($real, $temp) = ({}, {});
	foreach my $col (grep $self->_attribute_exists($_), $self->all_columns) {
		($class->has_real_column($col) ? $real : $temp)->{$col} =
			$self->_attrs($col);
	}
	$self->_insert_row($real);

	my @primary_columns = $class->primary_columns;
	$self->_attribute_store(
		$primary_columns[0] => $real->{ $primary_columns[0] })
		if @primary_columns == 1;

	delete $self->{__Changed};

	my %primary_columns;
	@primary_columns{@primary_columns} = ();
	my @discard_columns = grep !exists $primary_columns{$_}, keys %$real;
	$self->call_trigger('create', discard_columns => \@discard_columns);   # XXX

	# Empty everything back out again!
	$self->_attribute_delete(@discard_columns);
	$self->call_trigger('after_create');
	return $self;
}

sub _next_in_sequence {
	my $self = shift;
	return $self->sql_Nextval($self->sequence)->select_val;
}

sub _auto_increment_value {
	my $self = shift;
	my $dbh  = $self->db_Main;

	# the DBI will provide a standard attribute soon, meanwhile...
	my $id = $dbh->{mysql_insertid}    # mysql
		|| eval { $dbh->func('last_insert_rowid') };    # SQLite
	$self->_croak("Can't get last insert id") unless defined $id;
	return $id;
}

sub _insert_row {
	my $self = shift;
	my $data = shift;
	eval {
		my @columns = keys %$data;
		my $sth     = $self->sql_MakeNewObj(
			join(', ', @columns),
			join(', ', map $self->_column_placeholder($_), @columns),
		);
		$self->_bind_param($sth, \@columns);
		$sth->execute(values %$data);
		my @primary_columns = $self->primary_columns;
		$data->{ $primary_columns[0] } = $self->_auto_increment_value
			if @primary_columns == 1
			&& !defined $data->{ $primary_columns[0] };
	};
	if ($@) {
		my $class = ref $self;
		return $self->_croak(
			"Can't insert new $class: $@",
			err    => $@,
			method => 'create'
		);
	}
	return 1;
}

sub _bind_param {
	my ($class, $sth, $keys) = @_;
	my $datatype = $class->__data_type or return;
	for my $i (0 .. $#$keys) {
		if (my $type = $datatype->{ $keys->[$i] }) {
			$sth->bind_param($i + 1, undef, $type);
		}
	}
}

sub retrieve {
	my $class           = shift;
	my @primary_columns = $class->primary_columns
		or return $class->_croak(
		"Can't retrieve unless primary columns are defined");
	my %key_value;
	if (@_ == 1 && @primary_columns == 1) {
		my $id = shift;
		return unless defined $id;
		return $class->_croak("Can't retrieve a reference") if ref($id);
		$key_value{ $primary_columns[0] } = $id;
	} else {
		%key_value = @_;
		$class->_croak(
			"$class->retrieve(@_) parameters don't include values for all primary key columns (@primary_columns)"
			)
			if keys %key_value < @primary_columns;
	}
	my @rows = $class->search(%key_value);
	$class->_carp("$class->retrieve(@_) selected " . @rows . " rows")
		if @rows > 1;
	return $rows[0];
}

# Get the data, as a hash, but setting certain values to whatever
# we pass. Used by copy() and move().
# This can take either a primary key, or a hashref of all the columns
# to change.
sub _data_hash {
	my $self    = shift;
	my @columns = $self->all_columns;
	my %data;
	@data{@columns} = $self->get(@columns);
	my @primary_columns = $self->primary_columns;
	delete @data{@primary_columns};
	if (@_) {
		my $arg = shift;
		unless (ref $arg) {
			$self->_croak("Need hash-ref to edit copied column values")
				unless @primary_columns == 1;
			$arg = { $primary_columns[0] => $arg };
		}
		@data{ keys %$arg } = values %$arg;
	}
	return \%data;
}

sub copy {
	my $self = shift;
	return $self->create($self->_data_hash(@_));
}

#----------------------------------------------------------------------
# CONSTRUCT
#----------------------------------------------------------------------

sub construct {
	my ($proto, $data) = @_;
	my $class = ref $proto || $proto;
	my $self = $class->_init($data);
	$self->call_trigger('select');
	return $self;
}

sub move {
	my ($class, $old_obj, @data) = @_;
	$class->_carp("move() is deprecated. If you really need it, "
			. "you should tell me quickly so I can abandon my plan to remove it.");
	return $old_obj->_croak("Can't move to an unrelated class")
		unless $class->isa(ref $old_obj)
		or $old_obj->isa($class);
	return $class->create($old_obj->_data_hash(@data));
}

sub delete {
	my $self = shift;
	return $self->_search_delete(@_) if not ref $self;
	$self->call_trigger('before_delete');

	eval { $self->sql_DeleteMe->execute($self->id) };
	if ($@) {
		return $self->_croak("Can't delete $self: $@", err => $@);
	}
	$self->call_trigger('after_delete');
	undef %$self;
	bless $self, 'Class::DBI::Object::Has::Been::Deleted';
	return 1;
}

sub _search_delete {
	my ($class, @args) = @_;
	$class->_carp(
		"Delete as class method is deprecated. Use search and delete_all instead."
	);
	my $it = $class->search_like(@args);
	while (my $obj = $it->next) { $obj->delete }
	return 1;
}

# Return the placeholder to be used in UPDATE and INSERT queries.
# Overriding this is deprecated in favour of
#   __PACKAGE__->find_column('entered')->placeholder('IF(1, CURDATE(), ?));

sub _column_placeholder {
	my ($self, $column) = @_;
	return $self->find_column($column)->placeholder;
}

sub update {
	my $self  = shift;
	my $class = ref($self)
		or return $self->_croak("Can't call update as a class method");

	$self->call_trigger('before_update');
	return 1 unless my @changed_cols = $self->is_changed;
	$self->call_trigger('deflate_for_update');
	my @primary_columns = $self->primary_columns;
	my $sth             = $self->sql_update($self->_update_line);
	$class->_bind_param($sth, \@changed_cols);
	my $rows = eval { $sth->execute($self->_update_vals, $self->id); };
	return $self->_croak("Can't update $self: $@", err => $@) if $@;

	# enable this once new fixed DBD::SQLite is released:
	if (0 and $rows != 1) {    # should always only update one row
		$self->_croak("Can't update $self: row not found") if $rows == 0;
		$self->_croak("Can't update $self: updated more than one row");
	}

	$self->call_trigger('after_update', discard_columns => \@changed_cols);

	# delete columns that changed (in case adding to DB modifies them again)
	$self->_attribute_delete(@changed_cols);
	delete $self->{__Changed};
	return 1;
}

sub _update_line {
	my $self = shift;
	join(', ', map "$_ = " . $self->_column_placeholder($_), $self->is_changed);
}

sub _update_vals {
	my $self = shift;
	$self->_attrs($self->is_changed);
}

sub DESTROY {
	my ($self) = shift;
	if (my @changed = $self->is_changed) {
		my $class = ref $self;
		$self->_carp("$class $self destroyed without saving changes to "
				. join(', ', @changed));
	}
}

sub discard_changes {
	my $self = shift;
	return $self->_croak("Can't discard_changes while autoupdate is on")
		if $self->autoupdate;
	$self->_attribute_delete($self->is_changed);
	delete $self->{__Changed};
	return 1;
}

# We override the get() method from Class::Accessor to fetch the data for
# the column (and associated) columns from the database, using the _flesh()
# method. We also allow get to be called with a list of keys, instead of
# just one.

sub get {
	my $self = shift;
	return $self->_croak("Can't fetch data as class method") unless ref $self;

	my @cols = $self->_find_columns(@_);
	return $self->_croak("Can't get() nothing!") unless @cols;

	if (my @fetch_cols = grep !$self->_attribute_exists($_), @cols) {
		$self->_flesh($self->__grouper->groups_for(@fetch_cols));
	}

	return $self->_attrs(@cols);
}

sub _flesh {
	my ($self, @groups) = @_;
	my @real = grep $_ ne "TEMP", @groups;
	if (my @want = grep !$self->_attribute_exists($_),
		$self->__grouper->columns_in(@real)) {
		my %row;
		@row{@want} = $self->sql_Flesh(join ", ", @want)->select_row($self->id);
		$self->_attribute_store(\%row);
		$self->call_trigger('select');
	}
	return 1;
}

# We also override set() from Class::Accessor so we can keep track of
# changes, and either write to the database now (if autoupdate is on),
# or when update() is called.
sub set {
	my $self          = shift;
	my $column_values = {@_};

	$self->normalize_column_values($column_values);
	$self->validate_column_values($column_values);

	while (my ($column, $value) = each %$column_values) {
		my $col = $self->find_column($column) or die "No such column: $column\n";
		$self->_attribute_set($col => $value);

		# $self->SUPER::set($column, $value);

		eval { $self->call_trigger("after_set_$column") };    # eg inflate
		if ($@) {
			$self->_attribute_delete($column);
			return $self->_croak("after_set_$column trigger error: $@", err => $@);
		}
	}

	$self->update if $self->autoupdate;
	return 1;
}

sub is_changed {
	my $self = shift;
	grep $self->has_real_column($_), keys %{ $self->{__Changed} };
}

sub any_changed { keys %{ shift->{__Changed} } }

# By default do nothing. Subclasses should override if required.
#
# Given a hash ref of column names and proposed new values,
# edit the values in the hash if required.
# For create $self is the class name (not an object ref).
sub normalize_column_values {
	my ($self, $column_values) = @_;
}

# Given a hash ref of column names and proposed new values
# validate that the whole set of new values in the hash
# is valid for the object in relation to its current values
# For create $self is the class name (not an object ref).
sub validate_column_values {
	my ($self, $column_values) = @_;
	my @errors;
	foreach my $column (keys %$column_values) {
		eval {
			$self->call_trigger("before_set_$column", $column_values->{$column},
				$column_values);
		};
		push @errors, $column => $@ if $@;
	}
	return unless @errors;
	$self->_croak(
		"validate_column_values error: " . join(" ", @errors),
		method => 'validate_column_values',
		data   => {@errors}
	);
}

# We override set_sql() from Ima::DBI so it has a default database connection.
sub set_sql {
	my ($class, $name, $sql, $db, @others) = @_;
	$db ||= 'Main';
	$class->SUPER::set_sql($name, $sql, $db, @others);
	$class->_generate_search_sql($name) if $sql =~ /select/i;
	return 1;
}

sub _generate_search_sql {
	my ($class, $name) = @_;
	my $method = "search_$name";
	defined &{"$class\::$method"}
		and return $class->_carp("$method() already exists");
	my $sql_method = "sql_$name";
	no strict 'refs';
	*{"$class\::$method"} = sub {
		my ($class, @args) = @_;
		return $class->sth_to_objects($name, \@args);
	};
}

sub dbi_commit   { my $proto = shift; $proto->SUPER::commit(@_); }
sub dbi_rollback { my $proto = shift; $proto->SUPER::rollback(@_); }

#----------------------------------------------------------------------
# Constraints / Triggers
#----------------------------------------------------------------------

sub constrain_column {
	my $class = shift;
	my $col   = $class->find_column(+shift)
		or return $class->_croak("constraint_column needs a valid column");
	my $how = shift
		or return $class->_croak("constrain_column needs a constraint");
	if (ref $how eq "ARRAY") {
		my %hash = map { $_ => 1 } @$how;
		$class->add_constraint(list => $col => sub { exists $hash{ +shift } });
	} elsif (ref $how eq "Regexp") {
		$class->add_constraint(regexp => $col => sub { shift =~ $how });
	} else {
		my $try_method = sprintf '_constrain_by_%s', $how->moniker;
		if (my $dispatch = $class->can($try_method)) {
			$class->$dispatch($col => ($how, @_));
		} else {
			$class->_croak("Don't know how to constrain $col with $how");
		}
	}
}

sub add_constraint {
	my $class = shift;
	$class->_invalid_object_method('add_constraint()') if ref $class;
	my $name = shift or return $class->_croak("Constraint needs a name");
	my $column = $class->find_column(+shift)
		or return $class->_croak("Constraint $name needs a valid column");
	my $code = shift
		or return $class->_croak("Constraint $name needs a code reference");
	return $class->_croak("Constraint $name '$code' is not a code reference")
		unless ref($code) eq "CODE";

	$column->is_constrained(1);
	$class->add_trigger(
		"before_set_$column" => sub {
			my ($self, $value, $column_values) = @_;
			$code->($value, $self, $column, $column_values)
				or return $self->_croak(
				"$class $column fails '$name' constraint with '$value'");
		}
	);
}

sub add_trigger {
	my ($self, $name, @args) = @_;
	return $self->_croak("on_setting trigger no longer exists")
		if $name eq "on_setting";
	$self->_carp(
		"$name trigger deprecated: use before_$name or after_$name instead")
		if ($name eq "create" or $name eq "delete");
	$self->SUPER::add_trigger($name => @args);
}

#----------------------------------------------------------------------
# Inflation
#----------------------------------------------------------------------

sub add_relationship_type {
	my ($self, %rels) = @_;
	while (my ($name, $class) = each %rels) {
		$self->_require_class($class);
		no strict 'refs';
		*{"$self\::$name"} = sub {
			my $proto = shift;
			$class->set_up($name => $proto => @_);
		};
	}
}

sub _extend_meta {
	my ($class, $type, $subtype, $val) = @_;
	my %hash = %{ $class->__meta_info || {} };
	$hash{$type}->{$subtype} = $val;
	$class->__meta_info(\%hash);
}

sub meta_info {
	my ($class, $type, $subtype) = @_;
	my $meta = $class->__meta_info;
	return $meta          unless $type;
	return $meta->{$type} unless $subtype;
	return $meta->{$type}->{$subtype};
}

sub _simple_bless {
	my ($class, $pri) = @_;
	return $class->_init({ $class->primary_column => $pri });
}

sub _deflated_column {
	my ($self, $col, $val) = @_;
	$val ||= $self->_attrs($col) if ref $self;
	return $val unless ref $val;
	my $meta = $self->meta_info(has_a => $col) or return $val;
	my ($a_class, %meths) = ($meta->foreign_class, %{ $meta->args });
	if (my $deflate = $meths{'deflate'}) {
		$val = $val->$deflate(ref $deflate eq 'CODE' ? $self : ());
		return $val unless ref $val;
	}
	return $self->_croak("Can't deflate $col: $val is not a $a_class")
		unless UNIVERSAL::isa($val, $a_class);
	return $val->id if UNIVERSAL::isa($val => 'Class::DBI');
	return "$val";
}

#----------------------------------------------------------------------
# SEARCH
#----------------------------------------------------------------------

sub retrieve_all { shift->sth_to_objects('RetrieveAll') }

sub retrieve_from_sql {
	my ($class, $sql, @vals) = @_;
	$sql =~ s/^\s*(WHERE)\s*//i;
	return $class->sth_to_objects($class->sql_Retrieve($sql), \@vals);
}

sub search_like { shift->_do_search(LIKE => @_) }
sub search      { shift->_do_search("="  => @_) }

sub _do_search {
	my ($proto, $search_type, @args) = @_;
	my $class = ref $proto || $proto;

	@args = %{ $args[0] } if ref $args[0] eq "HASH";
	my (@cols, @vals);
	my $search_opts = @args % 2 ? pop @args : {};
	while (my ($col, $val) = splice @args, 0, 2) {
		my $column = $class->find_column($col)
			|| (List::Util::first { $_->accessor eq $col } $class->columns)
			|| $class->_croak("$col is not a column of $class");
		push @cols, $column;
		push @vals, $class->_deflated_column($column, $val);
	}

	my $frag = join " AND ",
		map defined($vals[$_]) ? "$cols[$_] $search_type ?" : "$cols[$_] IS NULL",
		0 .. $#cols;
	$frag .= " ORDER BY $search_opts->{order_by}"
		if $search_opts->{order_by};
	return $class->sth_to_objects($class->sql_Retrieve($frag),
		[ grep defined, @vals ]);

}

#----------------------------------------------------------------------
# CONSTRUCTORS
#----------------------------------------------------------------------

sub add_constructor {
	my ($class, $method, $fragment) = @_;
	return $class->_croak("constructors needs a name") unless $method;
	no strict 'refs';
	my $meth = "$class\::$method";
	return $class->_carp("$method already exists in $class")
		if *$meth{CODE};
	*$meth = sub {
		my $self = shift;
		$self->sth_to_objects($self->sql_Retrieve($fragment), \@_);
	};
}

sub sth_to_objects {
	my ($class, $sth, $args) = @_;
	$class->_croak("sth_to_objects needs a statement handle") unless $sth;
	unless (UNIVERSAL::isa($sth => "DBI::st")) {
		my $meth = "sql_$sth";
		$sth = $class->$meth();
	}
	my (%data, @rows);
	eval {
		$sth->execute(@$args) unless $sth->{Active};
		$sth->bind_columns(\(@data{ @{ $sth->{NAME_lc} } }));
		push @rows, {%data} while $sth->fetch;
	};
	return $class->_croak("$class can't $sth->{Statement}: $@", err => $@)
		if $@;
	return $class->_ids_to_objects(\@rows);
}
*_sth_to_objects = \&sth_to_objects;

sub _my_iterator {
	my $self  = shift;
	my $class = $self->iterator_class;
	$self->_require_class($class);
	return $class;
}

sub _ids_to_objects {
	my ($class, $data) = @_;
	return $#$data + 1 unless defined wantarray;
	return map $class->construct($_), @$data if wantarray;
	return $class->_my_iterator->new($class => $data);
}

#----------------------------------------------------------------------
# SINGLE VALUE SELECTS
#----------------------------------------------------------------------

sub _single_row_select {
	my ($self, $sth, @args) = @_;
	Carp::confess("_single_row_select is deprecated in favour of select_row");
	return $sth->select_row(@args);
}

sub _single_value_select {
	my ($self, $sth, @args) = @_;
	$self->_carp("_single_value_select is deprecated in favour of select_val");
	return $sth->select_val(@args);
}

sub count_all { shift->sql_single("COUNT(*)")->select_val }

sub maximum_value_of {
	my ($class, $col) = @_;
	$class->sql_single("MAX($col)")->select_val;
}

sub minimum_value_of {
	my ($class, $col) = @_;
	$class->sql_single("MIN($col)")->select_val;
}

sub _unique_entries {
	my ($class, %tmp) = shift;
	return grep !$tmp{$_}++, @_;
}

sub _invalid_object_method {
	my ($self, $method) = @_;
	$self->_carp(
		"$method should be called as a class method not an object method");
}

#----------------------------------------------------------------------
# misc stuff
#----------------------------------------------------------------------

sub _extend_class_data {
	my ($class, $struct, $key, $value) = @_;
	my %hash = %{ $class->$struct() || {} };
	$hash{$key} = $value;
	$class->$struct(\%hash);
}

my %required_classes; # { required_class => class_that_last_required_it, ... }

sub _require_class {
	my ($self, $load_class) = @_;
	$required_classes{$load_class} ||= my $for_class = ref($self) || $self;

	# return quickly if class already exists
	no strict 'refs';
	return if exists ${"$load_class\::"}{ISA};
	(my $load_module = $load_class) =~ s!::!/!g;
	return if eval { require "$load_module.pm" };

	# Only ignore "Can't locate" errors for the specific module we're loading
	return if $@ =~ /^Can't locate \Q$load_module\E\.pm /;

	# Other fatal errors (syntax etc) must be reported (as per base.pm).
	chomp $@;

	# This error message prefix is especially handy when dealing with
	# classes that are being loaded by other classes recursively.
	# The final message shows the path, e.g.:
	# Foo can't load Bar: Bar can't load Baz: syntax error at line ...
	$self->_croak("$for_class can't load $load_class: $@");
}

sub _check_classes {    # may automatically call from CHECK block in future
	while (my ($load_class, $by_class) = each %required_classes) {
		next if $load_class->isa("Class::DBI");
		$by_class->_croak(
			"Class $load_class used by $by_class has not been loaded");
	}
}

#----------------------------------------------------------------------
# Deprecations
#----------------------------------------------------------------------

__PACKAGE__->mk_classdata('__hasa_rels');
__PACKAGE__->__hasa_rels({});

sub ordered_search {
	shift->_croak(
		"Ordered search no longer exists. Pass order_by to search instead.");
}

sub hasa {
	my ($class, $f_class, $f_col) = @_;
	$class->_carp(
		"hasa() is deprecated in favour of has_a(). Using it instead.");
	$class->has_a($f_col => $f_class);
}

sub hasa_list {
	my $class = shift;
	$class->_carp("hasa_list() is deprecated in favour of has_many()");
	$class->has_many(@_[ 2, 0, 1 ], { nohasa => 1 });
}

1;

__END__

=head1 NAME

	Class::DBI - Simple Database Abstraction

=head1 SYNOPSIS

	package Music::DBI;
	use base 'Class::DBI';
	Music::DBI->connection('dbi:mysql:dbname', 'username', 'password');

	package Music::Artist;
	use base 'Music::DBI';
	Music::Artist->table('artist');
	Music::Artist->columns(All => qw/artistid name/);
	Music::Artist->has_many(cds => 'Music::CD');

	package Music::CD;
	use base 'Music::DBI';
	Music::CD->table('cd');
	Music::CD->columns(All => qw/cdid artist title year/);
	Music::CD->has_many(tracks => 'Music::Track');
	Music::CD->has_a(artist => 'Music::Artist');
	Music::CD->has_a(reldate => 'Time::Piece',
		inflate => sub { Time::Piece->strptime(shift, "%Y-%m-%d") },
		deflate => 'ymd',
	);

	Music::CD->might_have(liner_notes => LinerNotes => qw/notes/);

	package Music::Track;
	use base 'Music::DBI';
	Music::Track->table('track');
	Music::Track->columns(All => qw/trackid cd position title/); 

	#-- Meanwhile, in a nearby piece of code! --#

	my $artist = Music::Artist->create({ artistid => 1, name => 'U2' });

	my $cd = $artist->add_to_cds({ 
		cdid   => 1,
		title  => 'October',
		year   => 1980,
	});

	# Oops, got it wrong.
	$cd->year(1981);
	$cd->update;

	# etc.

	foreach my $track ($cd->tracks) {
		print $track->position, $track->title
	}

	$cd->delete; # also deletes the tracks

	my $cd  = Music::CD->retrieve(1);
	my @cds = Music::CD->retrieve_all;
	my @cds = Music::CD->search(year => 1980);
	my @cds = Music::CD->search_like(title => 'October%');

=head1 INTRODUCTION

Class::DBI provides a convenient abstraction layer to a database.

It not only provides a simple database to object mapping layer, but can
be used to implement several higher order database functions (triggers,
referential integrity, cascading delete etc.), at the application level,
rather than at the database.

This is particularly useful when using a database which doesn't support
these (such as MySQL), or when you would like your code to be portable
across multiple databases which might implement these things in different
ways.

In short, Class::DBI aims to make it simple to introduce 'best
practice' when dealing with data stored in a relational database.

=head2 How to set it up

=over 4

=item I<Set up a database.>

You must have an existing database set up, have DBI.pm installed and
the necessary DBD:: driver module for that database.  See L<DBI> and
the documentation of your particular database and driver for details.

=item I<Set up a table for your objects to be stored in.>

Class::DBI works on a simple one class/one table model.  It is your
responsibility to have your database tables already set up. Automating that
process is outside the scope of Class::DBI.

Using our CD example, you might declare a table something like this:

	CREATE TABLE cd (
		cdid   INTEGER   PRIMARY KEY,
		artist INTEGER, # references 'artist'
		title  VARCHAR(255),
		year   CHAR(4),
	);

=item I<Set up an application base class>

It's usually wise to set up a "top level" class for your entire
application to inherit from, rather than have each class inherit
directly from Class::DBI.  This gives you a convenient point to
place system-wide overrides and enhancements to Class::DBI's behavior.

	package Music::DBI;
	use base 'Class::DBI';

=item I<Give it a database connection>

Class::DBI needs to know how to access the database.  It does this
through a DBI connection which you set up by calling the connection()
method.

	Music::DBI->connection('dbi:mysql:dbname', 'user', 'password');

By setting the connection up in your application base class all the
table classes that inherit from it will share the same connection.

=item I<Set up each Class>

	package Music::CD;
	use base 'Music::DBI';

Each class will inherit from your application base class, so you don't
need to repeat the information on how to connect to the database.

=item I<Declare the name of your table>

Inform Class::DBI what table you are using for this class:

	Music::CD->table('cd');

=item I<Declare your columns.>

This is done using the columns() method. In the simplest form, you tell
it the name of all your columns (with the single primary key first):

	Music::CD->columns(All => qw/cdid artist title year/);

If the primary key of your table spans multiple columns then
declare them using a separate call to columns() like this:

	Music::CD->columns(Primary => qw/pk1 pk2/);
	Music::CD->columns(Others => qw/foo bar baz/);

For more information about how you can more efficiently use subsets of
your columns, see L</"LAZY POPULATION">

=item I<Done.>

That's it! You now have a class with methods to L<\create>(),
L<\retrieve>(), L<\search>() for, L<\update>() and L<\delete>() objects
from your table, as well as accessors and mutators for each of the
columns in that object (row).

=back

Let's look at all that in more detail:

=head1 CLASS METHODS

=head2 connection 

	__PACKAGE__->connection($data_source, $user, $password, \%attr);

This sets up a database connection with the given information. 

This uses Ima::DBI to set up an inheritable connection (named Main). It is 
therefore usual to only set up a connection() in your application base class 
and let the 'table' classes inherit from it.

	package Music::DBI;
	use base 'Class::DBI';

	Music::DBI->connection('dbi:foo:dbname', 'user', 'password');

	package My::Other::Table;
	use base 'Music::DBI';

Class::DBI helps you along a bit to set up the database connection.
connection() provides its own default attributes depending on the driver
name in the data_source parameter. The connection() method provides defaults
for these attributes:

	FetchHashKeyName   => 'NAME_lc',
	ShowErrorStatement => 1,
	ChopBlanks         => 1,
	AutoCommit         => 1,

(Except for Oracle and Pg, where AutoCommit defaults 0, placing the
database in transactional mode).

The defaults can always be extended (or overridden if you know what
you're doing) by supplying your own \%attr parameter. For example:

	Music::DBI->connection(dbi:foo:dbname','user','pass',{ChopBlanks=>0});

We use the inherited RootClass of DBIx::ContextualFetch from Ima::DBI,
and you should be very careful not to change this unless you know what
you're doing!

=head3 Dynamic Database Connections / db_Main

It is sometimes desirable to generate your database connection information
dynamically, for example, to allow multiple databases with the same
schema to not have to duplicate an entire class hierarchy.

The preferred method for doing this is to supply your own db_Main()
method rather than calling L<connection>(). This method should return a
valid database handle, and should ensure it sets the standard attributes
described above, preferably by combining $class->_default_attributes()
with your own. 

Note that connection information is class data, and that changing it
at run time may have unexpected behaviour for instances of the class
already in existence.

=head2 table

	__PACKAGE__->table($table);

	$table = Class->table;
	$table = $obj->table;

An accessor to get/set the name of the database table in which this
class is stored.  It -must- be set.

Table information is inherited by subclasses, but can be overridden.

=head2 table_alias

	package Shop::Order;
	__PACKAGE__->table('orders');
	__PACKAGE__->table_alias('orders');

When Class::DBI constructs SQL, it aliases your table name to a name
representing your class. However, if your class's name is an SQL reserved
word (such as 'Order') this will cause SQL errors. In such cases you
should supply your own alias for your table name (which can, of course,
be the same as the actual table name).

This can also be passed as a second argument to 'table':

	__PACKAGE__-->table('orders', 'orders');

As with table, this is inherited but can be overriden.

=head2 sequence / auto_increment

	__PACKAGE__->sequence($sequence_name);

	$sequence_name = Class->sequence;
	$sequence_name = $obj->sequence;

If you are using a database which supports sequences and you want to use
a sequence to automatically supply values for the primary key of a table,
then you should declare this using the sequence() method:

	__PACKAGE__->columns(Primary => 'id');
	__PACKAGE__->sequence('class_id_seq');

Class::DBI will use the sequence to generate a primary key value when
objects are created without one.

*NOTE* This method does not work for Oracle. However, Class::DBI::Oracle
(which can be downloaded separately from CPAN) provides a suitable
replacement sequence() method.

If you are using a database with AUTO_INCREMENT (e.g. MySQL) then you do
not need this, and any call to create() without a primary key specified
will fill this in automagically.

Sequence and auto-increment mechanisms only apply to tables that have
a single column primary key. For tables with multi-column primary keys
you need to supply the key values manually.

=head1 CONSTRUCTORS and DESTRUCTORS

The following are methods provided for convenience to create, retrieve
and delete stored objects.  It's not entirely one-size fits all and you
might find it necessary to override them.

=head2 create

	my $obj = Class->create(\%data);

This is a constructor to create a new object and store it in the database.

%data consists of the initial information to place in your object and
the database.  The keys of %data match up with the columns of your
objects and the values are the initial settings of those fields.

	my $cd = Music::CD->create({ 
		cdid   => 1,
		artist => $artist,
		title  => 'October',
		year   => 1980,
	});

If the table has a single primary key column and that column value
is not defined in %data, create() will assume it is to be generated.
If a sequence() has been specified for this Class, it will use that.
Otherwise, it will assume the primary key can be generated by
AUTO_INCREMENT and attempt to use that.

The C<before_create> trigger is invoked directly after storing the
supplied values into the new object and before inserting the record
into the database. The object stored in $self may not have all the
functionality of the final object after_creation, particularly if the
database is going to be providing the primary key value.

For tables with multi-column primary keys you need to supply all
the key values, either in the arguments to the create() method, or
by setting the values in a C<before_create> trigger.

If the class has declared relationships with foreign classes via
has_a(), you can pass an object to create() for the value of that key.
Class::DBI will Do The Right Thing.

After the new record has been inserted into the database the data
for non-primary key columns is discarded from the object. If those
columns are accessed again they'll simply be fetched as needed.
This ensures that the data in the application is consistent with
what the database I<actually> stored.

The C<after_create> trigger is invoked after the database insert
has executed.

=head2 find_or_create

	my $cd = Music::CD->find_or_create({ artist => 'U2', title => 'Boy' });

This checks if a CD can be found to match the information passed, and
if not creates it. 

=head2 delete

	$obj->delete;
	Music::CD->search(year => 1980, title => 'Greatest %')->delete_all;

Deletes this object from the database and from memory. If you have set up
any relationships using has_many, this will delete the foreign elements
also, recursively (cascading delete).  $obj is no longer usable after
this call.

Multiple objects can be deleted by calling delete_all on the Iterator
returned from a search. Each object found will be deleted in turn,
so cascading delete and other triggers will be honoured.

The C<before_delete> trigger is when an object instance is about to be
deleted. It is invoked before any cascaded deletes.  The C<after_delete>
trigger is invoked after the record has been deleted from the database
and just before the contents in memory are discarded.

=head1 RETRIEVING OBJECTS

We provide a few simple search methods, more to show the potential of
the class than to be serious search methods.

=head2 retrieve

	$obj = Class->retrieve( $id );
	$obj = Class->retrieve( %key_values );

Given key values it will retrieve the object with that key from the
database.  For tables with a single column primary key a single
parameter can be used, otherwise a hash of key-name key-value pairs
must be given.

	my $cd = Music::CD->retrieve(1) or die "No such cd";

=head2 retrieve_all

	my @objs = Class->retrieve_all;
	my $iterator = Class->retrieve_all;

Retrieves objects for all rows in the database. This is probably a
bad idea if your table is big, unless you use the iterator version.

=head2 search

	@objs = Class->search(column1 => $value, column2 => $value ...);

This is a simple search for all objects where the columns specified are
equal to the values specified e.g.:

	@cds = Music::CD->search(year => 1990);
	@cds = Music::CD->search(title => "Greatest Hits", year => 1990);

You may also specify the sort order of the results by adding a final
hash of arguments with the key 'order_by':

	@cds = Music::CD->search(year => 1990, { order_by=>'artist' });

=head2 search_like

	@objs = Class->search_like(column1 => $like_pattern, ....);

This is a simple search for all objects where the columns specified are
like the values specified.  $like_pattern is a pattern given in SQL LIKE
predicate syntax.  '%' means "any one or more characters", '_' means
"any single character". 

	@cds = Music::CD->search_like(title => 'October%');
	@cds = Music::CD->search_like(title => 'Hits%', artist => 'Various%');

You can also use 'order_by' with these, as with search().

=head1 ITERATORS

	my $it = Music::CD->search_like(title => 'October%');
	while (my $cd = $it->next) {
		print $cd->title;
	}

Any of the above searches (as well as those defined by has_many) can also
be used as an iterator.  Rather than creating a list of objects matching
your criteria, this will return a Class::DBI::Iterator instance, which
can return the objects required one at a time.

Currently the iterator initially fetches all the matching row data into
memory, and defers only the creation of the objects from that data until
the iterator is asked for the next object. So using an iterator will
only save significant memory if your objects will inflate substantially
when used.

In the case of has_many relationships with a mapping method, the mapping
method is not called until each time you call 'next'. This means that
if your mapping is not a one-to-one, the results will probably not be
what you expect.

=head2 Subclassing the Iterator

	Music::CD->iterator_class('Music::CD::Iterator');

You can also subclass the default iterator class to override its
functionality.  This is done via class data, and so is inherited into
your subclasses.

=head2 QUICK RETRIEVAL

	my $obj = Class->construct(\%data);

This is used to turn data from the database into objects, and should
thus only be used when writing constructors. It is very handy for
cheaply setting up lots of objects from data for without going back to
the database.

For example, instead of doing one SELECT to get a bunch of IDs and then
feeding those individually to retrieve() (and thus doing more SELECT
calls), you can do one SELECT to get the essential data of many objects
and feed that data to construct():

	 return map $class->construct($_), $sth->fetchall_hash;

The construct() method creates a new empty object, loads in the column
values, and then invokes the C<select> trigger.

=head1 COPY AND MOVE

=head2 copy

	$new_obj = $obj->copy;
	$new_obj = $obj->copy($new_id);
	$new_obj = $obj->copy({ title => 'new_title', rating => 18 });

This creates a copy of the given $obj, removes the primary key,
sets any supplied column values and calls create() to insert a new
record in the database.

For tables with a single column primary key, copy() can be called
with no parameters and the new object will be assigned a key
automatically.  Or a single parameter can be supplied and will be
used as the new key.

For tables with a multi-olumn primary key, copy() must be called with
parameters which supply new values for all primary key columns, unless
a C<before_create> trigger will supply them. The create() method will
fail if any primary key columns are not defined.

	my $blrunner_dc = $blrunner->copy("Bladerunner: Director's Cut");
	my $blrunner_unrated = $blrunner->copy({
		Title => "Bladerunner: Director's Cut",
		Rating => 'Unrated',
	});

=head2 move

	my $new_obj = Sub::Class->move($old_obj);
	my $new_obj = Sub::Class->move($old_obj, $new_id);
	my $new_obj = Sub::Class->move($old_obj, \%changes);

For transferring objects from one class to another. Similar to copy(), an
instance of Sub::Class is created using the data in $old_obj (Sub::Class
is a subclass of $old_obj's subclass). Like copy(), you can supply
$new_id as the primary key of $new_obj (otherwise the usual sequence or
autoincrement is used), or a hashref of multiple new values.

=head1 TRIGGERS

	__PACKAGE__->add_trigger(trigger_point_name => \&code_to_execute);

	# e.g.

	__PACKAGE__->add_trigger(after_create  => \&call_after_create);

It is possible to set up triggers that will be called at various
points in the life of an object. Valid trigger points are:

	before_create       (also used for deflation)
	after_create
	before_set_$column  (also used by add_constraint)
	after_set_$column   (also used for inflation and by has_a)
	before_update       (also used for deflation and by might_have)
	after_update
	before_delete
	after_delete
	select              (also used for inflation and by construct and _flesh)

You can create any number of triggers for each point, but you cannot
specify the order in which they will be run. Each will be passed the
object being dealt with (whose values you may change if required),
and return values will be ignored.

All triggers are passed the object they are being fired for.
Some triggers are also passed extra parameters as name-value pairs.
The individual triggers are documented with the methods that trigger them.

=head1 CONSTRAINTS

	__PACKAGE__->add_constraint('name', column => \&check_sub);

	# e.g.

	__PACKAGE__->add_constraint('over18', age => \&check_age);

	# Simple version
	sub check_age { 
		my ($value) = @_;
		return $value >= 18;
	}

	# Cross-field checking - must have SSN if age < 18
	sub check_age { 
		my ($value, $self, $column_name, $changing) = @_;
		return 1 if $value >= 18;     # We're old enough. 
		return 1 if $changing->{SSN}; # We're also being given an SSN
		return 0 if !ref($self);      # This is a create, so we can't have an SSN
		return 1 if $self->ssn;       # We already have one in the database
		return 0;                     # We can't find an SSN anywhere
	}

It is also possible to set up constraints on the values that can be set
on a column. The constraint on a column is triggered whenever an object
is created and whenever the value in that column is being changed.

The constraint code is called with four parameters:

	- The new value to be assigned
	- The object it will be assigned to
	(or class name when initially creating an object)
	- The name of the column
	(useful if many constraints share the same code)
	- A hash ref of all new column values being assigned
	(useful for cross-field validation)

The constraints are applied to all the columns being set before the
object data is changed. Attempting to create or modify an object
where one or more constraint fail results in an exception and the object
remains unchanged.

Note 1: Constraints are implemented using before_set_$column triggers.
This will only prevent you from setting these values through a
the provided create() or set() methods. It will always be possible to
bypass this if you try hard enough.

Note 2: When an object is created constraints are currently only
checked for column names included in the parameters to create().
This is probably a bug and is likely to change in future.

=head2 constrain_column

	Film->constrain_column(year => qr/\d{4}/);
	Film->constrain_column(rating => [qw/U Uc PG 12 15 18/]);

Simple anonymous constraints can also be added to a column using the
constrain_column() method.  By default this takes either a regex which
must match, or a reference to a list of possible values.

However, this behaviour can be extended (or replaced) by providing a
constraint handler for the type of argument passed to constrain_column.
This behavior should be provided in a method named "_constrain_by_$type",
where $type is the moniker of the argument. For example, the
two shown above would be provided by _constrain_by_array() and
_constrain_by_regexp().

=head1 DATA NORMALIZATION

Before an object is assigned data from the application (via create or
a set accessor) the normalize_column_values() method is called with
a reference to a hash containing the column names and the new values
which are to be assigned (after any validation and constraint checking,
as described below).

Currently Class::DBI does not offer any per-column mechanism here.
The default method is empty.  You can override it in your own classes
to normalize (edit) the data in any way you need. For example the values
in the hash for certain columns could be made lowercase.

The method is called as an instance method when the values of an existing
object are being changed, and as a class method when a new object is
being created.

=head1 DATA VALIDATION

Before an object is assigned data from the application (via create or
a set accessor) the validate_column_values() method is called with a
reference to a hash containing the column names and the new values which
are to be assigned.

The method is called as an instance method when the values of an existing
object are being changed, and as a class method when a new object is
being created.

The default method calls the before_set_$column trigger for each column
name in the hash. Each trigger is called inside an eval.  Any failures
result in an exception after all have been checked.  The exception data
is a reference to a hash which holds the column name and error text for
each trigger error.

When using this mechanism for form data validation, for example,
this exception data can be stored in an exception object, via a
custom _croak() method, and then caught and used to redisplay the
form with error messages next to each field which failed validation.

=head1 EXCEPTIONS

All errors that are generated, or caught and propagated, by Class::DBI
are handled by calling the _croak() method (as an instance method
if possible, or else as a class method).

The _croak() method is passed an error message and in some cases
some extra information as described below. The default behaviour
is simply to call Carp::croak($message).

Applications that require custom behaviour should override the
_croak() method in their application base class (or table classes
for table-specific behaviour). For example:

	use Error;

	sub _croak {
		my ($self, $message, %info) = @_;
		# convert errors into exception objects
		# except for duplicate insert errors which we'll ignore
		Error->throw(-text => $message, %info)
			unless $message =~ /^Can't insert .* duplicate/;
		return;
	}

The _croak() method is expected to trigger an exception and not
return. If it does return then it should use C<return;> so that an
undef or empty list is returned as required depending on the calling
context. You should only return other values if you are prepared to
deal with the (unsupported) consequences. 

For exceptions that are caught and propagated by Class::DBI, $message
includes the text of $@ and the original $@ value is available in $info{err}.
That allows you to correctly propagate exception objects that may have
been thrown 'below' Class::DBI (using Exception::Class::DBI for example). 

Exceptions generated by some methods may provide additional data in
$info{data} and, if so, also store the method name in $info{method}.
For example, the validate_column_values() method stores details of
failed validations in $info{data}. See individual method documentation
for what additional data they may store, if any.

=head1 WARNINGS

All warnings are handled by calling the _carp() method (as
an instance method if possible, or else as a class method).
The default behaviour is simply to call Carp::carp().

=head1 INSTANCE METHODS

=head2 accessors

Class::DBI inherits from Class::Accessor and thus provides individual
accessor methods for every column in your subclass.  It also overrides
the get() and set() methods provided by Accessor to automagically handle
database reading and writing. (Note that as it doesn't make sense to
store a list of values in a column, set() takes a hash of column =>
value pairs, rather than the single key => values of Class::Accessor).

=head2 the fundamental set() and get() methods

	$value = $obj->get($column_name);
	@values = $obj->get(@column_names);

	$obj->set($column_name => $value);
	$obj->set($col1 => $value1, $col2 => $value2 ... );

These methods are the fundamental entry points for getting and setting
column values.  The extra accessor methods automatically generated for
each column of your table are simple wrappers that call these get()
and set() methods.

The set() method calls normalize_column_values() then
validate_column_values() before storing the values.  The
C<before_set_$column> trigger is invoked by validate_column_values(),
checking any constraints that may have been set up. The
C<after_set_$column> trigger is invoked after the new value has been
stored.

It is possible for an object to not have all its column data in memory
(due to lazy inflation).  If the get() method is called for such a column
then it will select the corresponding group of columns and then invoke
the C<select> trigger.

=head2 Changing Your Column Accessor Method Names

=head2 accessor_name / mutator_name

If you want to change the name of your accessors, you need to provide an
accessor_name() method, which will convert a column name to a method name.

e.g: if your local naming convention was to prepend the word 'customer'
to each column in the 'customer' table, so that you had the columns
'customerid', 'customername' and 'customerage', you would end up with
code filled with calls to $customer->customerid, $customer->customername,
$customer->customerage etc. By creating an accessor_name method like:

	sub accessor_name {
		my ($class, $column) = @_;
		$column =~ s/^customer//;
		return $column;
	}

Your methods would now be the simpler $customer->id, $customer->name and
$customer->age etc.

Similarly, if you want to have distinct accessor and mutator methods,
you would provide a mutator_name() method which would return the name
of the method to change the value:

	sub mutator_name {
		my ($class, $column) = @_;
		return "set_$column";
	}

If you override the mutator_name, then the accessor method will be
enforced as read-only, and the mutator as write-only.

=head2 update vs auto update

There are two modes for the accessors to work in: manual update and
autoupdate. When in autoupdate mode, every time one calls an accessor
to make a change an UPDATE will immediately be sent to the database.
Otherwise, if autoupdate is off, no changes will be written until update()
is explicitly called.

This is an example of manual updating:

	# The calls to NumExplodingSheep() and Rating() will only make the
	# changes in memory, not in the database.  Once update() is called
	# it writes to the database in one swell foop.
	$gone->NumExplodingSheep(5);
	$gone->Rating('NC-17');
	$gone->update;

And of autoupdating:

	# Turn autoupdating on for this object.
	$gone->autoupdate(1);

	# Each accessor call causes the new value to immediately be written.
	$gone->NumExplodingSheep(5);
	$gone->Rating('NC-17');

Manual updating is probably more efficient than autoupdating and
it provides the extra safety of a discard_changes() option to clear out all
unsaved changes.  Autoupdating can be more convenient for the programmer.
Autoupdating is I<off> by default.

If changes are left un-updated or not rolledback when the object is
destroyed (falls out of scope or the program ends) then Class::DBI's
DESTROY method will print a warning about unsaved changes.

=head2 autoupdate

	__PACKAGE__->autoupdate($on_or_off);
	$update_style = Class->autoupdate;

	$obj->autoupdate($on_or_off);
	$update_style = $obj->autoupdate;

This is an accessor to the current style of auto-updating.  When called
with no arguments it returns the current auto-updating state, true for on,
false for off.  When given an argument it turns auto-updating on and off:
a true value turns it on, a false one off.

When called as a class method it will control the updating style for
every instance of the class.  When called on an individual object it
will control updating for just that object, overriding the choice for
the class.

	__PACKAGE__->autoupdate(1);     # Autoupdate is now on for the class.

	$obj = Class->retrieve('Aliens Cut My Hair');
	$obj->autoupdate(0);      # Shut off autoupdating for this object.

The update setting for an object is not stored in the database.

=head2 update

	$obj->update;

If L</autoupdate> is not enabled then changes you make to your object are
not reflected in the database until you call update().  It is harmless
to call update() if there are no changes to be saved.  (If autoupdate
is on there'll never be anything to save.)

Note: If you have transactions turned on for your database (but see
L<"TRANSACTIONS"> below) you will also need to call dbi_commit(), as
update() merely issues the UPDATE to the database).

After the database update has been executed, the data for columns
that have been updated are deleted from the object. If those columns
are accessed again they'll simply be fetched as needed. This ensures
that the data in the application is consistent with what the database
I<actually> stored.

When update() is called the C<before_update>($self) trigger is
always invoked immediately.

If any columns have been updated then the C<after_update> trigger
is invoked after the database update has executed and is passed:
	($self, discard_columns => \@discard_columns, rows => $rows)

(where rows is the return value from the DBI execute() method).

The trigger code can modify the discard_columns array to affect
which columns are discarded.

For example:

	Class->add_trigger(after_update => sub {
		my ($self, %args) = @_;
		my $discard_columns = $args{discard_columns};
		# discard the md5_hash column if any field starting with 'foo'
		# has been updated - because the md5_hash will have been changed
		# by a trigger.
		push @$discard_columns, 'md5_hash' if grep { /^foo/ } @$discard_columns;
	});

Take care to not delete a primary key column unless you know what
you're doing.

The update() method returns the number of rows updated, which should
always be 1, or else -1 if no update was needed. If the record in the
database has been deleted, or its primary key value changed, then the
update will not affect any records and so the update() method will
return 0.

=head2 discard_changes

	$obj->discard_changes;

Removes any changes you've made to this object since the last update.
Currently this simply discards the column values from the object.

If you're using autoupdate this method will throw an exception.

=head2 is_changed

	my $changed = $obj->is_changed;
	my @changed_keys = $obj->is_changed;

Indicates if the given $obj has changes since the last update. Returns
a list of keys which have changed. (If autoupdate is on, this method
will return an empty list, unless called inside a before_update or
after_set_$column trigger)

=head2 id

	$id = $obj->id;

Returns a unique identifier for this object.  It's the equivalent of
$obj->get($self->columns('Primary'));  A warning will be generated
if this method is used on a table with a multi-column primary key.

=head2 LOW-LEVEL DATA ACCESS

On some occasions, such as when you're writing triggers or constraint
routines, you'll want to manipulate data in a Class::DBI object without
using the usual get() and set() accessors, which may themselves call
triggers, fetch information from the database, and the like. Rather than
intereacting directly with the hash that makes up a Class::DBI object
(the exact implementation of which may change in a future release) you
should use Class::DBI's low-level accessors. These appear 'private' to
make you think carefully about using them - they should not be a common
means of dealing with the object.

The object is modelled as a set of key-value pairs, where the keys are
normalized column names (returned by find_column()), and the values are
the data from the database row represented by the object.  Access is
via these functions:

=over 4

=item _attrs

	@values = $object->_attrs(@cols);

Returns the values for one or more keys.

=item _attribute_store

	$object->_attribute_store( { $col0 => $val0, $col1 => $val1 } );
	$object->_attribute_store($col0, $val0, $col1, $val1);

Stores values in the object.  They key-value pairs may be passed in
either as a simple list or as a hash reference.  This only updates
values in the object itself; changes will not be propagated to the
database.

=item _attribute_set

	$object->_attribute_set( { $col0 => $val0, $col1 => $val1 } );
	$object->_attribute_set($col0, $val0, $col1, $val1);

Updates values in the object via _attribute_store(), but also logs
the changes so that they are propagated to the database with the next
update.  (Unlike set(), however, _attribute_set() will not trigger an
update if autoupdate is turned on.)

=item _attribute_delete

	@values = $object->_attribute_delete(@cols);

Deletes values from the object, and returns the deleted values.

=item _attribute_exists

	$bool = $object->_attribute_exists($col);

Returns a true value if the object contains a value for the specified
column, and a false value otherwise.

=back

By default, Class::DBI uses simple hash references to store object
data, but all access is via these routines, so if you want to
implement a different data model, just override these functions.

=head2 OVERLOADED OPERATORS

Class::DBI and its subclasses overload the perl builtin I<stringify>
and I<bool> operators. This is a significant convenience.

The perl builtin I<bool> operator is overloaded so that a Class::DBI
object reference is true so long as all its key columns have defined
values.  (This means an object with an id() of zero is not considered
false.)

When a Class::DBI object reference is used in a string context it will,
by default, return the value of the primary key. (Composite primary key
values will be separated by a slash).

You can also specify the column(s) to be used for stringification via
the special 'Stringify' column group. So, for example, if you're using
an auto-incremented primary key, you could use this to provide a more
meaningful display string:

	Widget->columns(Stringify => qw/name/);

If you need to do anything more complex, you can provide an stringify_self()
method which stringification will call:

	sub stringify_self { 
		my $self = shift;
		return join ":", $self->id, $self->name;
	}

This overloading behaviour can be useful for columns that have has_a()
relationships.  For example, consider a table that has price and currency
fields:

	package Widget;
	use base 'My::Class::DBI';
	Widget->table('widget');
	Widget->columns(All => qw/widgetid name price currency_code/);

	$obj = Widget->retrieve($id);
	print $obj->price . " " . $obj->currency_code;

The would print something like "C<42.07 USD>".  If the currency_code
field is later changed to be a foreign key to a new currency table then
$obj->currency_code will return an object reference instead of a plain
string. Without overloading the stringify operator the example would now
print something like "C<42.07 Widget=HASH(0x1275}>" and the fix would
be to change the code to add a call to id():

	print $obj->price . " " . $obj->currency_code->id;

However, with overloaded stringification, the original code continues
to work as before, with no code changes needed.

This makes it much simpler and safer to add relationships to exisiting
applications, or remove them later.

=head1 TABLE RELATIONSHIPS

Databases are all about relationships. And thus Class::DBI provides a
way for you to set up descriptions of your relationhips.

Currently we provide three such methods: 'has_a', 'has_many', and
'might_have'.

=head2 has_a

	Music::CD->has_a(artist => 'Music::Artist');
	print $cd->artist->name;

We generally use 'has_a' to supply lookup information for a foreign
key, i.e. we declare that the value we have stored in the column is
the primary key of another table.  Thus, when we access the 'artist'
method we don't just want that ID returned, but instead we inflate it
to this other object.

However, we can also use has_a to inflate the data value to any
other object.  A common usage would be to inflate a date field to a
Time::Piece object:

	Music::CD->has_a(reldate => 'Date::Simple');
	print $cd->reldate->format("%d %b, %Y");

	Music::CD->has_a(reldate => 'Time::Piece',
		inflate => sub { Time::Piece->strptime(shift, "%Y-%m-%d") },
		deflate => 'ymd',
	);
	print $cd->reldate->strftime("%d %b, %Y");

If the foreign class is another Class::DBI representation we will
call retrieve() on that class with our value. Any other object will be
instantiated either by calling new($value) or using the given 'inflate'
method. If the inflate method name is a subref, it will be executed,
and will be passed the value and the Class::DBI object as arguments.

When the object is being written to the database the object will be
deflated either by calling the 'deflate' method (if given), or by
attempting to stringify the object. If the deflate method is a subref,
it will be passed the Class::DBI object as an argument.

*NOTE* You should not attempt to make your primary key column inflate
using has_a() as bad things will happen. If you have two tables which
share a primary key, consider using might_have() instead.

=head2 has_many

	Class->has_many(method_to_create => "Foreign::Class");

	Music::CD->has_many(tracks => 'Music::Track');

	my @tracks = $cd->tracks;

	my $track6 = $cd->add_to_tracks({ 
		position => 6,
		title    => 'Tomorrow',
	});

This method declares that another table is referencing us (i.e. storing
our primary key in its table).

It creates a named accessor method in our class which returns a list of
all the matching Foreign::Class objects.

In addition it creates another method which allows a new associated object
to be constructed, taking care of the linking automatically. This method
is the same as the accessor method with "add_to_" prepended.

The add_to_tracks example above is exactly equivalent to:

	my $track6 = Music::Track->create({
		cd       => $cd,
		position => 6,
		title    => 'Tomorrow',
	});

When setting up the relationship we examine the foreign class's has_a()
declarations to discover which of its columns reference our class. (Note
that because this happens at compile time, if the foreign class is defined
in the same file, the class with the has_a() must be defined earlier than
the class with the has_many(). If the classes are in different files,
Class::DBI should be able to do the right thing). If no such has_a()
declarations can be found, or none link to us, we assume that it is linking
to us via a column named after the moniker() of our class. If this is
not true you can pass an additional third argument to the has_many()
declaration stating which column of the foreign class references us.

=head3 Limiting

	Music::Artist->has_many(cds => 'Music::CD');
	my @cds = $artist->cds(year => 1980);

When calling the method created by has_many, you can also supply any
additional key/value pairs for restricting the search. The above example
will only return the CDs with a year of 1980.

=head3 Ordering

	Music::CD->has_many(tracks => 'Music::Track', { order_by => 'playorder' });

Often you wish to order the values returned from has_many. This can be
done by passing a hash ref containing a 'order_by' value of the column by
which you want to order.

=head3 Mapping

	Music::CD->has_many(styles => [ 'Music::StyleRef' => 'style' ]);

Sometimes we don't want to return an instance of the Foreign::Class,
but instead the result of calling a method on that object. We can do
this by changing the Foreign::Class declaration to a listref of the
Foreign::Class and the method to call on that class.

The above is exactly equivalent to:

	Music::CD->has_many(_style_refs => 'Music::StyleRef');

	sub styles { 
		my $self = shift;
		return map $_->style, $self->_style_refs;
	}

For an example of where this is useful see L</"MANY TO MANY RELATIONSHIPS">
below.

=head2 might_have

	Music::CD->might_have(method_name => Class => (@fields_to_import));

	Music::CD->might_have(liner_notes => LinerNotes => qw/notes/);

	my $liner_notes_object = $cd->liner_notes;
	my $notes = $cd->notes; # equivalent to $cd->liner_notes->notes;

might_have() is similar to has_many() for relationships that can have
at most one associated objects. For example, if you have a CD database
to which you want to add liner notes information, you might not want
to add a 'liner_notes' column to your main CD table even though there
is no multiplicity of relationship involved (each CD has at most one
'liner notes' field). So, we create another table with the same primary
key as this one, with which we can cross-reference.

But you don't want to have to keep writing methods to turn the the
'list' of liner_notes objects you'd get back from has_many into the
single object you'd need. So, might_have() does this work for you. It
creates you an accessor to fetch the single object back if it exists,
and it also allows you import any of its methods into your namespace. So,
in the example above, the LinerNotes class can be mostly invisible -
you can just call $cd->notes and it will call the notes method on the
correct LinerNotes object transparently for you.

Making sure you don't have namespace clashes is up to you, as is correctly
creating the objects, but I may make these simpler in later versions.
(Particularly if someone asks for them!)

=head2 Notes

has_a(), might_have() and has_many() check that the relevant class has
already been loaded. If it hasn't then they try to load the module of
the same name using require.  If the require fails because it can't
find the module then it will assume it's not a simple require (i.e.,
Foreign::Class isn't in Foreign/Class.pm) and that you will take care
of it and ignore the warning. Any other error, such as a syntax error,
triggers an exception.

NOTE: The two classes in a relationship do not have to be in the same
database, on the same machine, or even in the same type of database! It
is quite acceptable for a table in a MySQL database to be connected to
a different table in an Oracle database, and for cascading delete etc
to work across these. This should assist greatly if you need to migrate
a database gradually.

=head1 MANY TO MANY RELATIONSHIPS

Class::DBI does not currently support Many to Many relationships, per se.
However, by combining the relationships that already exist it is possible
to set these up.

Consider the case of Films and Actors, with a linking Role table. First
of all we'll set up our Role class:

	Role->table('role');
	Role->columns(Primary => qw/film actor/);
	Role->has_a(film => 'Film');
	Role->has_a(actor => 'Actor');

We have a multi-column primary key, with each column pointing to another class. 

Then, we need to set up our Film and Actor class to use this linking table:

	Film->table('film');
	Film->columns(All => qw/id title rating/);
	Film->has_many(stars => [ Role => 'actor' ]);

	Actor->table('actor');
	Actor->columns(All => qw/id name/);
	Actor->has_many(films => [ Role => 'film' ]);

In each case we use the 'mapping method' variation of has_many() to say
that we don't want an instance of the Role class, but rather the result
of calling a method on that instance. As we have set up those methods
in Role to inflate to the actual Actor and Film objects, this gives us a
cheap many-to-many relationship. In the case of Film, this is equivalent
to the more long-winded:

	Film->has_many(roles => "Role");

	sub actors { 
		my $self = shift;
		return map $_->actor, $self->roles 
	}

As this is almost exactly what is created internally, add_to_stars and
add_to_films will generally do the right thing as they are actually
doing the equivalent of add_to_roles:

	$film->add_to_actors({ actor => $actor });

Similarly a cascading delete will also do the right thing as it will
only delete the relationship from the linking table.

If the Role table were to contain extra information, such as the name
of the character played, then you would usually need to skip these
short-cuts and set up each of the relationships, and associated helper
methods, manually.

=head1 ADDING NEW RELATIONSHIP TYPES

=head2 add_relationship_type

The relationships described above are implemented through
Class::DBI::Relationship subclasses.  These are then plugged into
Class::DBI through an add_relationship_type() call:

	__PACKAGE__->add_relationship_type(
		has_a      => "Class::DBI::Relationship::HasA",
		has_many   => "Class::DBI::Relationship::HasMany",
		might_have => "Class::DBI::Relationship::MightHave",
	);

If is thus possible to add new relationship types, or modify the behaviour
of the existing types.  See L<Class::DBI::Relationship> for more information
on what is required.

=head1 DEFINING SQL STATEMENTS

There are several main approaches to setting up your own SQL queries:

For queries which could be used to create a list of matching objects
you can create a constructor method associated with this SQL and let
Class::DBI do the work for you, or just inline the entire query.

For more complex queries you need to fall back on the underlying Ima::DBI
query mechanism. (Caveat: since Ima::DBI uses sprintf-style interpolation,
you need to be careful to double any "wildcard" % signs in your queries).

=head2 add_constructor

	__PACKAGE__->add_constructor(method_name => 'SQL_where_clause');

The SQL can be of arbitrary complexity and will be turned into:
	SELECT (essential columns)
	  FROM (table name)
	 WHERE <your SQL>

This will then create a method of the name you specify, which returns
a list of objects as with any built in query.

For example:

	Music::CD->add_constructor(new_music => 'year > 2000');
	my @recent = Music::CD->new_music;

You can also supply placeholders in your SQL, which must then be
specified at query time:

	Music::CD->add_constructor(new_music => 'year > ?');
	my @recent = Music::CD->new_music(2000);

=head2 retrieve_from_sql

On occasions where you want to execute arbitrary SQL, but don't want
to go to the trouble of setting up a constructor method, you can inline
the entire WHERE clause, and just get the objects back directly:

	my @cds = Music::CD->retrieve_from_sql(qq{
		artist = 'Ozzy Osbourne' AND
		title like "%Crazy"      AND
		year <= 1986
		ORDER BY year
		LIMIT 2,3
	});

=head2 Ima::DBI queries

When you can't use 'add_constructor', e.g. when using aggregate functions,
you can fall back on the fact that Class::DBI inherits from Ima::DBI
and prefers to use its style of dealing with statements, via set_sql().

The Class::DBI set_sql() method defaults to using prepare_cached()
unless the $cache parameter is defined and false (see Ima::DBI docs for
more information).

To assist with writing SQL that is inheritable into subclasses, several
additional substitutions are available here: __TABLE__, __ESSENTIAL__
and __IDENTIFIER__.  These represent the table name associated with the
class, its essential columns, and the primary key of the current object,
in the case of an instance method on it.

For example, the SQL for the internal 'update' method is implemented as:

	__PACKAGE__->set_sql('update', <<"");
		UPDATE __TABLE__
		SET    %s
		WHERE  __IDENTIFIER__

The 'longhand' version of the new_music constructor shown above would
similarly be:

	Music::CD->set_sql(new_music => qq{
		SELECT __ESSENTIAL__
		  FROM __TABLE__
		 WHERE year > ?
	};

We also extend the Ima::DBI set_sql() to create a helper shortcut method,
named by prefixing the name of your SQL fragment with search_. Thus,
the above call to set_sql() will automatically set up the method
Music::CD->search_new_music(), which will execute this search and
return the relevant objects or Iterator.  (If you have placeholders
in your query, you must pass the relevant arguments when calling your
search method.)

This does the equivalent of:

	sub search_new_music {
		my ($class, @args) = @_;
		my $sth = $class->sql_new_music;
		$sth->execute(@args);
		return $class->sth_to_objects($sth);
	}

The $sth which we use to return the objects here is a normal DBI-style
statement handle, so if your results can't even be turned into objects
easily, you can still call $sth->fetchrow_array etc and return whatever
data you choose.

Of course, any query can be added via set_sql, including joins.  So,
to add a query that returns the 10 Artists with the most CDs, you could
write (with MySQL):

	Music::Artist->set_sql(most_cds => qq{
		SELECT artist.id, COUNT(cd.id) AS cds
		  FROM artist, cd
		 WHERE artist.id = cd.artist
		 GROUP BY artist.id
		 ORDER BY cds DESC
		 LIMIT 10
	});

	my @artists = Music::Artist->search_most_cds();

If you also need to access the 'cds' value returned from this query,
the best approach is to declare 'cds' to be a TEMP column. (See
L</"Non-Persistent Fields"> below).

=head2 Class::DBI::AbstractSearch

	my @music = Music::CD->search_where(
		artist => [ 'Ozzy', 'Kelly' ],
		status => { '!=', 'outdated' },
	);

The L<Class::DBI::AbstractSearch> module, available from CPAN, is a
plugin for Class::DBI that allows you to write arbitrarily complex
searches using perl data structures, rather than SQL.

=head2 Single Value SELECTs

Selects which only return a single value can take advantage of Ima::DBI's
$sth->select_val() call, coupled with Class::DBI's sql_single SQL.

head3 select_val

Selects which only return a single value can take advantage of Ima::DBI's
$sth->select_val() call. For example,

	__PACKAGE__->set_sql(count_all => "SELECT COUNT(*) FROM __TABLE__");
	# .. then ..
	my $count = $class->sql_count_all->select_val;

=head3 sql_single

Internally we define a very simple SQL fragment: "SELECT %s FROM __TABLE__".
Using this we implement the above Class->count_all(), as

	$class->sql_single("COUNT(*)")->select_val;

This interpolates the COUNT(*) into the %s of the SQL, and then executes
the query, returning a single value.

Any SQL set up via set_sql() can of course be supplied here, and
select_val can take arguments for any placeholders there.

Internally we define several helper methods using this approach:

=over 4

=item - count_all

=item - maximum_value_of($column)

=item - minimum_value_of($column)

=back

=head1 LAZY POPULATION

In the tradition of Perl, Class::DBI is lazy about how it loads your
objects.  Often, you find yourself using only a small number of the
available columns and it would be a waste of memory to load all of them
just to get at two, especially if you're dealing with large numbers of
objects simultaneously.

You should therefore group together your columns by typical usage, as
fetching one value from a group can also pre-fetch all the others in
that group for you, for more efficient access.

So for example, if we usually fetch the artist and title, but don't use
the 'year' so much, then we could say the following:

	Music::CD->columns(Primary   => qw/cdid/);
	Music::CD->columns(Essential => qw/artist title/);
	Music::CD->columns(Others    => qw/year runlength/);

Now when you fetch back a CD it will come pre-loaded with the 'cdid',
'artist' and 'title' fields. Fetching the 'year' will mean another visit
to the database, but will bring back the 'runlength' whilst it's there.

This can potentially increase performance.

If you don't like this behavior, then just add all your non-primary key
columns to the one group, and Class::DBI will load everything at once.

=head2 columns

	my @all_columns  = $class->columns;
	my @columns      = $class->columns($group);

	my @primary      = $class->primary_columns;
	my $primary      = $class->primary_column;
	my @essential    = $class->_essential;

There are four 'reserved' groups: 'All', 'Essential', 'Primary' and
'TEMP'.

B<'All'> are all columns used by the class. If not set it will be
created from all the other groups.

B<'Primary'> is the primary key columns for this class. It I<must>
be set before objects can be used.

If 'All' is given but not 'Primary' it will assume the first column in
'All' is the primary key.

B<'Essential'> are the minimal set of columns needed to load and use
the object. Only the columns in this group will be loaded when an object
is retrieve()'d. It is typically used to save memory on a class that has
a lot of columns but where we mostly only use a few of them. It will
automatically be set to B<'All'> if you don't set it yourself.
The 'Primary' column is always part of your 'Essential' group and
Class::DBI will put it there if you don't.

For simplicity we provide primary_columns(), primary_column(), and
_essential() methods which return these. The primary_column() method
should only be used for tables that have a single primary key column.

=head2 Non-Persistent Fields

	Music::CD->columns(TEMP => qw/nonpersistent/);

If you wish to have fields that act like columns in every other way, but
that don't actually exist in the database (and thus will not persist),
you can declare them as part of a column group of 'TEMP'.

=head2 find_column

	Class->find_column($column);
	$obj->find_column($column);

The columns of a class are stored as Class::DBI::Column objects. This
method will return you the object for the given column, if it exists.
This is most useful either in a boolean context to discover if the column
exists, or to 'normalize' a user-entered column name to an actual Column.

The interface of the Column object itself is still under development,
so you shouldn't really rely on anything internal to it.

=head1 TRANSACTIONS

Class::DBI suffers from the usual problems when dealing with transactions.
In particular, you should be very wary when committing your changes that
you may actually be in a wider scope than expected and that your caller
may not be expecting you to commit.

However, as long as you are aware of this, and try to keep the scope
of your transactions small, ideally always within the scope of a single
method, you should be able to work with transactions with few problems.

=head2 dbi_commit / dbi_rollback

	$obj->dbi_commit();
	$obj->dbi_rollback();

We provide these thin aliases through to the DBI's commit() and rollback()
commands to commit or rollback all changes to this object. 

=head2 Localised Transactions

A nice idiom for turning on a transaction locally (with AutoCommit turned
on globally) (courtesy of Dominic Mitchell) is:

	sub do_transaction {
		my $class = shift;
		my ( $code ) = @_;
		# Turn off AutoCommit for this scope.
		# A commit will occur at the exit of this block automatically,
		# when the local AutoCommit goes out of scope.
		local $class->db_Main->{ AutoCommit };

		# Execute the required code inside the transaction.
		eval { $code->() };
		if ( $@ ) {
			my $commit_error = $@;
			eval { $class->dbi_rollback }; # might also die!
			die $commit_error;
		}
	}

	And then you just call:

	Music::DBI->do_transaction( sub {
		my $artist = Music::Artist->create({ name => 'Pink Floyd' });
		my $cd = $artist->add_to_cds({ 
			title => 'Dark Side Of The Moon', 
			year => 1974,
		});
	});

Now either both will get added, or the entire transaction will be
rolled back.

=head1 UNIQUENESS OF OBJECTS IN MEMORY

Class::DBI supports uniqueness of objects in memory. In a given perl
interpreter there will only be one instance of any given object at
one time. Many variables may reference that object, but there can be
only one.

Here's an example to illustrate:

	my $artist1 = Music::Artist->create({ artistid => 7, name => 'Polysics' });
	my $artist2 = Music::Artist->retrieve(7);
	my $artist3 = Music::Artist->search( name => 'Polysics' )->first;

Now $artist1, $artist2, and $artist3 all point to the same object. If you
update a property on one of them, all of them will reflect the update.

This is implemented using a simple object lookup index for all live
objects in memory. It is not a traditional cache - when your objects
go out of scope, they will be destroyed normally, and a future retrieve
will instantiate an entirely new object.

The ability to perform this magic for you replies on your perl having
access to the Scalar::Util::weaken function. Although this is part of
the core perl distribution, some vendors do not compile support for it.
To find out if your perl has support for it, you can run this on the
command line:

	perl -e 'use Scalar::Util qw(weaken)'

If you get an error message about weak references not being implemented,
Class::DBI will not maintain this lookup index, but give you a separate
instances for each retrieve.

A few new tools are offered for adjusting the behavior of the object
index. These are still somewhat experimental and may change in a
future release.

=head2 remove_from_object_index

	$artist->remove_from_object_index();

This is an object method for removing a single object from the live
objects index. You can use this if you want to have multiple distinct
copies of the same object in memory.

=head2 clear_object_index

	Music::DBI->clear_object_index();

You can call this method on any class or instance of Class::DBI, but
the effect is universal: it removes all objects from the index.

=head2 purge_object_index_every

	Music::Artist->purge_object_index_every(2000);

Weak references are not removed from the index when an object goes
out of scope. This means that over time the index will grow in memory.
This is really only an issue for long-running environments like mod_perl,
but every so often we go through and clean out dead references to prevent
it. By default, this happens evey 1000 object loads, but you can change
that default for your class by calling the purge_object_index_every
method with a number.

Eventually this may handled in the DESTROY method instead.

As a final note, keep in mind that you can still have multiple distinct
copies of an object in memory if you have multiple perl interpreters
running. CGI, mod_perl, and many other common usage situations run
multiple interpreters, meaning that each one of them may have an instance
of an object representing the same data. However, this is no worse
than it was before, and is entirely normal for database applications in
multi-process environments.

=head1 SUBCLASSING

The preferred method of interacting with Class::DBI is for you to write
a subclass for your database connection, with each table-class inheriting
in turn from it. 

As well as encapsulating the connection information in one place,
this also allows you to override default behaviour or add additional
functionality across all of your classes.

As the innards of Class::DBI are still in flux, you must exercise extreme
caution in overriding private methods of Class::DBI (those starting with
an underscore), unless they are explicitly mentioned in this documentation
as being safe to override. If you find yourself needing to do this,
then I would suggest that you ask on the mailing list about it, and
we'll see if we can either come up with a better approach, or provide
a new means to do whatever you need to do.

=head1 CAVEATS

=head2 Multi-Column Foreign Keys are not supported

=head2 Don't change or inflate the value of your primary columns

Altering your primary key column currently causes Bad Things to happen.
I should really protect against this.

=head1 SUPPORTED DATABASES

Theoretically Class::DBI should work with almost any standard RDBMS. Of
course, in the real world, we know that that's not true. We know that
it works with MySQL, PostgrSQL, Oracle and SQLite, each of which have
their own additional subclass on CPAN that you should explore if you're
using them.

	L<Class::DBI::mysql>, L<Class::DBI::Pg>, L<Class::DBI::Oracle>,
	L<Class::DBI::SQLite>

For the most part it's been reported to work with Sybase, although there
are some issues with multi-case column/table names. Beyond that lies
The Great Unknown(tm). If you have access to other databases, please
give this a test run, and let me know the results.

This is known not to work with DBD::RAM. As a minimum it requires a
database that supports table aliasing, and a DBI driver that supports
placeholders.

=head1 CURRENT AUTHOR

Tony Bowden <classdbi@tmtm.com>

=head1 AUTHOR EMERITUS

Michael G Schwern <schwern@pobox.com>

=head1 THANKS TO

Tim Bunce, Tatsuhiko Miyagawa, Perrin Hawkins, Alexander Karelas, Barry
Hoggard, Bart Lateur, Boris Mouzykantskii, Brad Bowman, Brian Parker,
Casey West, Charles Bailey, Christopher L. Everett Damian Conway, Dan
Thill, Dave Cash, David Jack Olrik, Dominic Mitchell, Drew Taylor,
Drew Wilson, Jay Strauss, Jesse Sheidlower, Jonathan Swartz, Marty
Pauley, Michael Styer, Mike Lambert, Paul Makepeace, Phil Crow, Richard
Piacentini, Simon Cozens, Simon Wilcox, Thomas Klausner, Tom Renfro,
Uri Gutman, William McKee, the Class::DBI mailing list, the POOP group,
and all the others who've helped, but that I've forgetten to mention.

=head1 SUPPORT

Support for Class::DBI is via the mailing list. The list is used for
general queries on the use of Class::DBI, bug reports, patches, and
suggestions for improvements or new features.

To join the list visit http://groups.kasei.com/mail/info/cdbi-talk

You can also report bugs through the CPAN RT interface, but I'll
proabably also forward those to the mailing list for discussion (and
often bounce mailing list bug reports to the RT interface so I don't
forget about them!)

When submitting patches I quite like the 'diff -Bub' format. Bug fixes
also get applied much quicker if you supply a failing test case (even
in preference to a fix!)

The interface to Class::DBI is fairly stable, but there are still
occasions when we need to break backwards compatability. Such issues
will be raised on the list before release, so if you use Class::DBI in
a production environment, it's probably a good idea to keep a watch on
the list (and definitely on the CHANGES file of a new release).

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

There is a Class::DBI wiki at:
	http://www.class-dbi.com/cgi-bin/wiki/index.cgi?HomePage

Amongst other things it provides the beginnings of a Cookbook of typical
tricks and tips. Please contribute!

There are lots of 3rd party subclasses and plugins available.
For a full list see:
	http://search.cpan.org/search?query=Class%3A%3ADBI&mode=module

An article on Class::DBI was published on Perl.com a while ago. It's
slightly out of date already, but it's a good introduction:
	http://www.perl.com/pub/a/2002/11/27/classdbi.html

http://poop.sourceforge.net/ provides a document comparing a variety
of different approaches to database persistence, such as Class::DBI,
Alazabo, Tangram, SPOPS etc.

Class::DBI is built on top of L<Ima::DBI>, L<Class::Accessor> and
L<Class::Data::Inheritable>.

=cut

