package Slim::Schema::Storage;

# $Id$

# SlimServer Copyright (c) 2001-2006 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

# Shim to get a backtrace out of throw_exception

use strict;
use base qw(DBIx::Class::Storage::DBI::mysql);

use Slim::Utils::Misc;

our $dbAccess = Slim::Utils::PerfMon->new('Database Access', [0.002, 0.005, 0.01, 0.015, 0.025, 0.05, 0.1, 0.5, 1, 5], 1);

sub throw_exception {
	my ($self, $msg) = @_;

	errorMsg($msg);
	errorMsg("Backtrace follows:\n");
	bt();
}

# XXXX - hack to work around a bug in DBIx::Class 0.06xxx
sub _populate_dbh {
	my $self  = shift;
	my $class = ref($self);

	$self->next::method(@_);
	bless($self, $class);

	return;
}

sub select { 
	my $self = shift;

	$::perfmon && (my $now = Time::HiRes::time());

	my @ret = $self->next::method(@_);

	$::perfmon && $dbAccess->log(Time::HiRes::time() - $now) && msg("    DBIx select\n", undef, 1);

	return wantarray ? @ret : $ret[0];
}

sub select_single { 
	my $self = shift;

	$::perfmon && (my $now = Time::HiRes::time());

	my @ret = $self->next::method(@_);

	$::perfmon && $dbAccess->log(Time::HiRes::time() - $now) && msg("    DBIx select_single\n", undef, 1);

	return wantarray ? @ret : $ret[0];
}

1;

__END__
