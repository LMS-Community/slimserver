package Class::DBI::Query::Base;

use strict;

use base 'Class::Accessor';
use Storable 'dclone';

sub new {
	my ($class, $fields) = @_;
	my $self = $class->SUPER::new();
	foreach my $key (keys %{ $fields || {} }) {
		$self->set($key => $fields->{$key});
	}
	$self;
}

sub get {
	my ($self, $key) = @_;
	my @vals = @{ $self->{$key} || [] };
	return wantarray ? @vals : $vals[0];
}

sub set {
	my ($self, $key, @args) = @_;
	@args = map { ref $_ eq "ARRAY" ? @$_ : $_ } @args;
	$self->{$key} = [@args];
}

sub clone { dclone shift }

package Class::DBI::Query;

use base 'Class::DBI::Query::Base';

__PACKAGE__->mk_accessors(
	qw/
		owner essential sqlname where_clause restrictions order_by kings
		/
);

=head1 NAME

Class::DBI::Query - Deprecated SQL manager for Class::DBI

=head1 SYNOPSIS

	my $sth = Class::DBI::Query
		->new({ 
			owner => $class, 
			sqlname => $type, 
			essential => \@columns, 
			where_columns => \@where_cols,
		})
		->run($val);


=head1 DESCRIPTION

This abstracts away many of the details of the Class::DBI underlying SQL
mechanism. For the most part you probably don't want to be interfacing
directly with this.

The underlying mechanisms are not yet stable, and are subject to change
at any time.

=cut

=head1 OPTIONS

A Query can have many options set before executing. Most can either be
passed as an option to new(), or set later if you are building the query
up dynamically:

=head2 owner

The Class::DBI subclass that 'owns' this query. In the vast majority
of cases a query will return objects - the owner is the class of
which instances will be returned. 

=head2 sqlname

This should be the name of a query set up using set_sql.

=head2 where_clause

This is the raw SQL that will substituted into the 'WHERE %s' in your
query. If you have multiple %s's in your query then you should supply
a listref of where_clauses. This SQL can include placeholders, which will be 
used when you call run().

=head2 essential

When retrieving rows from the database that match the WHERE clause of
the query, these are the columns that we fetch back and pre-load the
resulting objects with. By default this is the Essential column group
of the owner class.

=head1 METHODS

=head2 where()

	$query->where($match, @columns);

This will extend your 'WHERE' clause by adding a 'AND $column = ?' (or
whatever $match is, isntead of "=") for each column passed. If you have
multiple WHERE clauses this will extend the last one.

=cut

sub new {
	my ($class, $self) = @_;
	require Carp;
	Carp::carp "Class::DBI::Query deprecated";
	$self->{owner}     ||= caller;
	$self->{kings}     ||= $self->{owner};
	$self->{essential} ||= [ $self->{owner}->_essential ];
	$self->{sqlname}   ||= 'SearchSQL';
	return $class->SUPER::new($self);
}

sub _essential_string {
	my $self  = shift;
	my $table = $self->owner->table_alias;
	join ", ", map "$table.$_", $self->essential;
}

sub where {
	my ($self, $type, @cols) = @_;
	my @where = $self->where_clause;
	my $last = pop @where || "";
	$last .= join " AND ", $self->restrictions;
	$last .= " ORDER BY " . $self->order_by if $self->order_by;
	push @where, $last;
	return @where;
}

sub add_restriction {
	my ($self, $sql) = @_;
	$self->restrictions($self->restrictions, $sql);
}

sub tables {
	my $self = shift;
	join ", ", map { join " ", $_->table, $_->table_alias } $self->kings;
}

# my $sth = $query->run(@vals);
# Runs the SQL set up in $sqlname, e.g.
#
# SELECT %s (Essential)
# FROM   %s (Table)
# WHERE  %s = ? (SelectCol = @vals)
#
# substituting the relevant values via sprintf, and then executing with $select_val.

sub run {
	my $self = shift;
	my $owner = $self->owner or Class::DBI->_croak("Query has no owner");
	$owner = ref $owner || $owner;
	$owner->can('db_Main') or $owner->_croak("No database connection defined");
	my $sql_name = $self->sqlname or $owner->_croak("Query has no SQL");

	my @sel_vals = @_
		? ref $_[0] eq "ARRAY" ? @{ $_[0] } : (@_)
		: ();
	my $sql_method = "sql_$sql_name";

	my $sth;
	eval {
		$sth =
			$owner->$sql_method($self->_essential_string, $self->tables,
			$self->where);
		$sth->execute(@sel_vals);
	};
	if ($@) {
		$owner->_croak(
			"Can't select for $owner using '$sth->{Statement}' ($sql_name): $@",
			err => $@);
		return;
	}
	return $sth;
}

1;
