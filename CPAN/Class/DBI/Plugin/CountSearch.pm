package Class::DBI::Plugin::CountSearch;

our $VERSION = 1.02;

use strict;
use warnings;

=head1 NAME

Class::DBI::Plugin::CountSearch - get COUNT(*) results from the database with search functionality

=head1 SYNOPSIS

	use base 'Class::DBI';
	use Class::DBI::Plugin::CountSearch;
	
	my $count = My::Class->count_search('year' => '1994');
	
=head1 DESCRIPTION

This plugin adds support for COUNT(*) results directly from the database
without having to load the records into an iterator or array.  It provides
'count_search' and 'count_search_like' which take arguments exactly like
Class::DBI::search().

=head1 METHODS

=head2 count_search

	my $count = My::Movies->count_search('year' => '1994');
	
This method will be exported into the calling class, and allows for
retrieving a count of records using the Class::DBI::search() interface. 
The count is done using COUNT(*).

=head2 count_search_like

	my $count = My::Movies->count_search_like('title' => 'Jaws%');

This method will be exported into the calling class, and allows for
retrieving a count of records using the Class::DBI::search_like() interface. 
The count is done using COUNT(*).

=cut

sub import {
	my ($self, @pairs) = @_;
	my $caller = caller();
	no strict 'refs';

	$caller->set_sql(count_search => <<'');
		SELECT COUNT(*)
		FROM __TABLE__
		%s

	
	*{"$caller\::count_search"} =      sub { shift->_do_count_search('='    => @_) };
	*{"$caller\::count_search_like"} = sub { shift->_do_count_search('LIKE' => @_) };

	# Mostly stolen from Class::DBI::search (0.96)

	*{"$caller\::_do_count_search"} = sub {
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

		defined($frag) && $frag ne '' and
			$frag = " WHERE $frag";

		return $class->sql_count_search($frag)->select_val(@vals);
	};
	
}

=head1 AUTHOR

Todd Holbrook, E<lt>tholbroo@sfu.caE<gt>.

Plugin importing and _do_count_search borrowed from Tony Bowden's Class::DBI
and Class::DBI::Plugin::RetrieveAll.

=head1 COPYRIGHT

Copyright (C) 2004 Todd Holbrook, Simon Fraser University. All rights reserved.

This module is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
