package Class::DBI::Plugin::RetrieveAll;

our $VERSION = '1.01';

use strict;
use warnings;

=head1 NAME

Class::DBI::Plugin::RetrieveAll - more complex retrieve_all() for Class::DBI

=head1 SYNOPSIS

	use base 'Class::DBI';
	use Class::DBI::Plugin::RetrieveAll;

	my @by_date = My::Class->retrieve_all_sorted_by("date");

	# or

	__PACKAGE__->retrieve_all_sort_field('date');

	my @by_date = My::Class->retrieve_all;

=head1 DESCRIPTION

This is a simple plugin to a Class::DBI subclass which allows for simple
sorting of retrieve_all calls. There are two main ways to use this.
Firstly, we create a new method 'retrieve_all_sorted_by' which takes an
argument of how to sort. We also add a way to set a default field that
any retrieve_all() should use to sort by.

=head1 METHODS

=head2 retrieve_all_sorted_by

	my @by_date = My::Class->retrieve_all_sorted_by("date");

This method will be exported into the calling class, and allows for
retrieving all the objects of the class, sorted by the given column.

The argument given will be passed straight through to the database 'as
is', and is not checked in any way, so an error here will probably result
in an error from the database, rather than Class::DBI itself. However,
because of this it is possible to pass more complex ORDER BY clauses
through:

	my @by_date = My::Class->retrieve_all_sorted_by("date DESC, reference_no");

=head2 retrieve_all_sort_field

  __PACKAGE__->retrieve_all_sort_field('date');

This method changes the default retrieve_all() in the Class to be
auto-sorted by the field given. Again this will be passed through
directly, so you can have complex ORDER BY clauses. 

=cut

sub import {
	my $caller = caller();
	no strict 'refs';

	$caller->set_sql(retrieve_all_sorted => <<'');
		SELECT __ESSENTIAL__
		FROM __TABLE__
		ORDER BY %s

	*{"$caller\::retrieve_all_sorted_by"} = sub {
		my ($class, $order_by) = @_;
		return $class->sth_to_objects($class->sql_retrieve_all_sorted($order_by));
	};

	$caller->mk_classdata('__plugin_retall_sortfield');

	*{"$caller\::retrieve_all_sort_field"} = sub {
		my ($class, $field) = @_;
		$class->__plugin_retall_sortfield($field);
	};

	# I hate that SUPER means *my* SUPER *now* - not $class->SUPER then
	my $super = $caller->can('retrieve_all');
	*{"$caller\::retrieve_all"} = sub {
		my $class = shift;
		my $field = $class->__plugin_retall_sortfield 
			or return $super->($class);
		return $class->retrieve_all_sorted_by($field);
	};
}

=head1 AUTHOR

Tony Bowden, E<lt>kasei@tmtm.comE<gt>.

=head1 COPYRIGHT

Copyright (C) 2004 Kasei. All rights reserved.

This module is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;

