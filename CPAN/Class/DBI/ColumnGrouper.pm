package Class::DBI::ColumnGrouper;

=head1 NAME

Class::DBI::ColumnGrouper - Columns and Column Groups

=head1 SYNOPSIS

	my $colg = Class::DBI::ColumnGrouper->new;
	   $colg->add_group(People => qw/star director producer/);

	my @cols = $colg->group_cols($group);

	my @all            = $colg->all_columns;
	my @pri_col        = $colg->primary;
	my @essential_cols = $colg->essential;

=head1 DESCRIPTION

Each Class::DBI class maintains a list of its columns as class data.
This provides an interface to that. You probably don't want to be dealing
with this directly.

=head1 METHODS

=cut

use strict;

use Carp;
use Storable 'dclone';
use Class::DBI::Column;

sub _unique {
	my %seen;
	map { $seen{$_}++ ? () : $_ } @_;
}

sub _uniq {
	my %tmp;
	return grep !$tmp{$_}++, @_;
}

=head2 new

	my $colg = Class::DBI::ColumnGrouper->new;

A new blank ColumnnGrouper object.

=head2 clone

	my $colg2 = $colg->clone;

Clone an existing ColumnGrouper.

=cut

sub new {
	my $class = shift;
	bless {
		_groups => {},
		_cols   => {},
	}, $class;
}

sub clone {
	my ($class, $prev) = @_;
	return dclone $prev;
}

=head2 add_column / find_column 

	$colg->add_column($name);
	my Class::DBI::Column $col = $colg->find_column($name);

Add or return a Column object for the given column name.

=cut

sub add_column {
	my ($self, $name) = @_;
	return $name if ref $name;
	$self->{_allcol}->{ lc $name } ||= Class::DBI::Column->new($name);
}

sub find_column {
	my ($self, $name) = @_;
	return $name if ref $name;
	return unless $self->{_allcol}->{ lc $name };
}

=head2 add_group

	$colg->add_group(People => qw/star director producer/);

This adds a list of columns as a column group.

=cut

sub add_group {
	my ($self, $group, @names) = @_;
	$self->add_group(Primary => $names[0])
		if ($group eq "All" or $group eq "Essential")
		and not $self->group_cols('Primary');
	$self->add_group(Essential => @names)
		if $group eq "All"
		and !$self->essential;
	@names = _unique($self->primary, @names) if $group eq "Essential";

	my @cols = map $self->add_column($_), @names;
	$_->add_group($group) foreach @cols;
	$self->{_groups}->{$group} = \@cols;
	return $self;
}

=head2 group_cols / groups_for

	my @colg = $cols->group_cols($group);
	my @groups = $cols->groups_for(@cols);

This returns a list of all columns which are in the given group, or the
groups a given column is in.

=cut

sub group_cols {
	my ($self, $group) = @_;
	return $self->all_columns if $group eq "All";
	@{ $self->{_groups}->{$group} || [] };
}

sub groups_for {
	my ($self, @cols) = @_;
	return _uniq(map $_->groups, @cols);
}

=head2 columns_in

	my @cols = $colg->columns_in(@groups);

This returns a list of all columns which are in the given groups.

=cut

sub columns_in {
	my ($self, @groups) = @_;
	return _uniq(map $self->group_cols($_), @groups);
}

=head2 all_columns

	my @all = $colg->all_columns;

This returns a list of all the real columns.

=head2 primary

	my $pri_col = $colg->primary;

This returns a list of the columns in the Primary group.

=head2 essential

	my @essential_cols = $colg->essential;

This returns a list of the columns in the Essential group.

=cut

sub all_columns {
	my $self = shift;
	return grep $_->in_database, values %{ $self->{_allcol} };
}

sub primary {
	my @cols = shift->group_cols('Primary');
	if (!wantarray && @cols > 1) {
		local ($Carp::CarpLevel) = 1;
		confess(
			"Multiple columns in Primary group (@cols) but primary called in scalar context"
		);
		return $cols[0];
	}
	return @cols;
}

sub essential {
	my $self = shift;
	my @cols = $self->group_cols('Essential');
	@cols = $self->primary unless @cols;
	return @cols;
}

1;
