package Class::DBI::Column;

=head1 NAME

Class::DBI::Column - A column in a table

=head1 SYNOPSIS

	my $column = Class::DBI::Column->new($name);

	my $name  = $column->name;

	my @groups = $column->groups;
	my $pri_col = $colg->primary;

	if ($column->in_database) { ... }

=head1 DESCRIPTION

Each Class::DBI class maintains a list of its columns as class data.
This provides an interface to those columns. You probably shouldn't be
dealing with this directly.

=head1 METHODS

=cut

use strict;
use base 'Class::Accessor';

__PACKAGE__->mk_accessors(
	qw/name accessor mutator placeholder
		is_constrained/
);

use overload
	'""'     => sub { shift->name_lc },
	fallback => 1;

=head2 new

	my $column = Class::DBI::Column->new($column)

A new object for this column.

=cut

sub new {
	my ($class, $name) = @_;
	return $class->SUPER::new(
		{
			name        => $name,
			_groups     => {},
			placeholder => '?'
		}
	);
}

sub name_lc { lc shift->name }

sub add_group {
	my ($self, $group) = @_;
	$self->{_groups}->{$group} = 1;
}

sub groups {
	my $self   = shift;
	my %groups = %{ $self->{_groups} };
	delete $groups{All} if keys %groups > 1;
	return keys %groups;
}

sub in_database {
	return !scalar grep $_ eq "TEMP", shift->groups;
}

1;
