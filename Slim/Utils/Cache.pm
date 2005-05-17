# Runtime Cache
# Copyright (c) 2005 Slim Devices, Inc. (www.slimdevices.com)

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

# A simple cache for arbitrary data.
# Each entry has an expiration time (Time::HiRes).
# TODO: use timers to periodically clean up expired entries. (currently does lazy cleanup)
# TODO: persist this cache on filesystem or database

package Slim::Utils::Cache;
use strict;

use Time::HiRes;

sub new {
	my %cache = ();
	return bless \%cache;
}

sub put {
	my $self = shift;
	my $key = shift;
	my $value = shift;
	my $expiration = shift;

	my @entry;
	$entry[0] = $value;
	$entry[1] = $expiration;

	$self->{$key} = \@entry;
	return;
}

sub get {
	my $self = shift;
	my $key = shift;

	my $returnMe = undef;
	my $entry = $self->{$key};
	if ($entry) {
		if (!expired($entry)) {
			$returnMe = $entry->[0];
		} else {
			# entry has expired
			delete $self->{$key};
		}
	}
	return $returnMe;
}

sub expired {
	my $entry = shift;
	my $now = Time::HiRes::time();

	my $expiration = $entry->[1];

	if (defined($expiration) && ($expiration <= 0)) {
		# expiration 0 or -1 means never expire
		return 0;
	} elsif (defined($expiration) && ($expiration > $now)) {
		return 0;
	} else {
		return 1;
	}
}


1;
