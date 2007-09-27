package Slim::Schema::Debug;

# $Id$

# SqueezeCenter Copyright (c) 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

# DBIx::Class::Storage debugobj class to add debugging and perfmon for database queries

use strict;

use Slim::Utils::Log;
use Slim::Utils::PerfMon;

my $log = logger('database.sql');

our $dbAccess = Slim::Utils::PerfMon->new('Database Access', [0.002, 0.005, 0.01, 0.02, 0.05, 0.1, 0.5, 1, 5]);

my $start;

sub query_start {
    my ($self, $string, @bind) = @_;

	$log->info(sub { "$string: ".join(', ', @bind) });

	$::perfmon && ($start = Time::HiRes::time());
}

sub query_end {
    my ($self, $string, @bind) = @_;

	$::perfmon && $dbAccess->log(Time::HiRes::time() - $start, sub { "$string: ".join(', ', @bind) });
}

sub debugfh {}
sub txn_begin {}
sub txn_rollback {}
sub txn_commit {}

1;

__END__
