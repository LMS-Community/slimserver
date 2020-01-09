package Slim::Schema::Debug;


# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

# DBIx::Class::Storage debugobj class to add debugging and perfmon for database queries

use strict;

use Slim::Utils::Log;

my $log = logger('database.sql');

my $start;

sub query_start {
    my ($self, $string, @bind) = @_;

	main::INFOLOG && $log->info( "$string: " . join(', ', @bind) );

	main::PERFMON && ($start = AnyEvent->time);
}

sub query_end {
    my ($self, $string, @bind) = @_;

	main::PERFMON && Slim::Utils::PerfMon->check('dbaccess', AnyEvent->time - $start, sub { "$string: ".join(', ', @bind) });
}

sub debugfh {}

sub txn_begin {
	main::INFOLOG && $log->info('BEGIN WORK');
}

sub txn_rollback {
	main::INFOLOG && $log->info('ROLLBACK');
}

sub txn_commit {
	main::INFOLOG && $log->info('COMMIT');
}

1;

__END__
