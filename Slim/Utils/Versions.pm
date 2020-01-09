package Slim::Utils::Versions;


# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License, version 2.

=head1 NAME

Slim::Utils::Versions

=head1 SYNOPSIS

if (Slim::Utils::Versions->checkVersion($toCheck, $min, $max)) {

	print "ok!";
}

=head1 DESCRIPTION

This module implements the Mozilla Toolkit Version Format, as found in Firefox 1.5 and later.

See L<http://developer.mozilla.org/en/docs/Toolkit_version_format> for more information.

=head1 METHODS

=cut

use strict;
use POSIX qw(INT_MAX);

sub _parseVersionPart {
	my ($part, $result) = @_;

	if (!$part) {
		return $part;
	}

	my $rest = undef;

	if ($part =~ /^(.+?)\.(.*)$/) {
		$part = $1;
		$rest = $2;
	}

	if ($part eq '*') {

		$result->[0] = POSIX::INT_MAX();
		$result->[1] = '';

	} elsif ($part =~ s/^(-?\d+)//) {

		$result->[0] = $1;
	}

	if ($part && $part eq '+') {

		$result->[0]++;
		$result->[1] = 'pre';

	} elsif ($part && $part =~ /^([A-Za-z]+)?([+-]?\d+)?([A-Za-z]+)?/) {

		$result->[1] = $1 || undef;
		$result->[2] = $2 || 0;
		$result->[3] = $3 || undef;
	}

	return $rest;
}

sub _string_cmp {
	my ($n1, $n2) = @_;

	if (!$n1) {
		return defined $n2;
	}

	if (!$n2) {
		return -1;
	}

	return $n1 cmp $n2;
}

sub _compareVersionPart {
	my ($left, $right) = @_;

	my $ret = $left->[0] <=> $right->[0];

	if ($ret) {
		return $ret;
	}

	$ret = _string_cmp($left->[1], $right->[1]);

	if ($ret) {
		return $ret;
	}

	$ret = $left->[2] <=> $right->[2];

	if ($ret) {
		return $ret;
	}

	return _string_cmp($left->[3], $right->[3]);
}

=head2 compareVersions( $left, $right )

Returns: 1 if $left > $right, 0 if $left == $right, -1 if $left < $right

=cut

sub compareVersions {
	my ($class, $left, $right) = @_;

	my $result;

	if (!$left || !$right) {
		return 1;
	}

	my ($a, $b) = ($left, $right);

	while ($a || $b) {

		my $va = [ 0, undef, 0, undef ];
		my $vb = [ 0, undef, 0, undef ];

		$a = _parseVersionPart($a, $va);
		$b = _parseVersionPart($b, $vb);

		$result = _compareVersionPart($va, $vb);

		if ($result) {
			last;
		}
	}

	return $result || 0;
}

=head2 checkVersion( $toCheck, $min, $max )

Returns true if the version string in $toCheck falls within the $min & $max range.

Returns false otherwise.

=cut

sub checkVersion {
	my ($class, $toCheck, $min, $max) = @_;

	if ($class->compareVersions($toCheck, $min) < 0) {

		return 0;
	}

	if ($class->compareVersions($toCheck, $max) > 0) {

		return 0;
	}

	return 1;
}

1;

__END__
# Tests follow

use Test::More qw(no_plan);

is(compareVersions('1.1b', '1.1ab'), 1, '1.1b > 1.1ab');

is(compareVersions('2.0', '1.*.1'), 1, '2.0 > 1.*.1');
is(compareVersions('1.*.1', '1.*'), 1, '1.*.1 > 1.*');
is(compareVersions('1.*', '1.10'), 1, '1.* > 1.10');
is(compareVersions('1.10', '1.1.00'), 1, '1.10 > 1.1.00');

is(compareVersions('1.1.00', '1.1.0'), 0, '1.1.00 == 1.1.0');
is(compareVersions('1.1.0', '1.1'), 0, '1.1.0 == 1.1');
is(compareVersions('1.1.00', '1.1'), 0, '1.1.00 == 1.1');

is(compareVersions('1.1', '1.1.-1'), 1, '1.1 > 1.1-1');

is(compareVersions('1.1.-1', '1.1pre10'), 1, '1.1-1 > 1.1pre10');
is(compareVersions('1.1pre10', '1.1pre2'), 1, '1.1pre10 > 1.1pre2');
is(compareVersions('1.1pre2', '1.1pre1'), 1, '1.1pre2 > 1.1pre1');
is(compareVersions('1.1pre1', '1.1pre1b'), 1, '1.1pre1 > 1.1pre1b');
is(compareVersions('1.1pre1b', '1.1pre1aa'), 1, '1.1pre1b > 1.1pre1aa');
is(compareVersions('1.1pre1aa', '1.1pre1a'), 1, '1.1pre1aa > 1.1pre1a');
is(compareVersions('1.1pre1a', '1.0+'), 1, '1.1pre1a > 1.0+');

is(compareVersions('1.0+', '1.1pre0'), 0, '1.0+ == 1.1pre0');
is(compareVersions('1.0+', '1.1pre'), 0, '1.0+ == 1.1pre');
is(compareVersions('1.1pre0', '1.1pre'), 0, '1.1pre0 == 1.1pre');

is(compareVersions('1.1pre', '1.1whatever'), -1, '1.1pre < 1.1whatever');
is(compareVersions('1.1whatever', '1.1c'), 1, '1.1whatever > 1.1c');

is(compareVersions('1.1c', '1.1b'), 1, '1.1c > 1.1b');
is(compareVersions('1.1b', '1.1ab'), 1, '1.1b > 1.1ab');
is(compareVersions('1.1ab', '1.1aa'), 1, '1.1ab > 1.1aa');
is(compareVersions('1.1aa', '1.1a'), 1, '1.1aa > 1.1a');
is(compareVersions('1.1a', '1.0.0'), 1, '1.1a > 1.0.0');

is(compareVersions('1.0.0', '1.0'), 0, '1.0.0 == 1.0');
is(compareVersions('1.0', '1.'), 0, '1.0 == 1.');
is(compareVersions('1.', '1'), 0, '1. == 1');
is(compareVersions('1.0.0', '1.'), 0, '1.0.0 == 1.');
is(compareVersions('1.0.0', '1'), 0, '1.0.0 == 1');

is(compareVersions('1', '1.-1'), 1, '1 > 1.-1');
