package Slim::Networking::Select;

# $Id$

# SlimServer Copyright (c) 2003-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use IO::Select;

use Slim::Utils::Misc;
use Slim::Utils::PerfMon;

BEGIN {
	if ($^O =~ /Win32/) {
		*EWOULDBLOCK = sub () { 10035 };
		*EINPROGRESS = sub () { 10036 };
	} else {
		require Errno;
		import Errno qw(EWOULDBLOCK EINPROGRESS);
	}
}

our $callbacks  = {};
our %writeQueue = ();

our $selects = {
	'read'  => IO::Select->new,
	'write' => IO::Select->new,
	'error' => IO::Select->new,
};

my $selectPerf = Slim::Utils::PerfMon->new('Response Time', [0.002, 0.005, 0.010, 0.015, 0.025, 0.050, 0.1, 0.5, 1, 5]);
my $endSelectTime;

sub addRead {

	_updateSelect('read', @_);
}

sub addWrite {

	_updateSelect('write', @_);
}

sub addError {

	_updateSelect('error', @_);
}

sub _updateSelect {
	my ($type, $sock, $callback) = @_;

	my $fileno = fileno($sock);

	if ($callback) {

		$callbacks->{$type}->{$fileno} = $callback;

		if (!$selects->{$type}->exists($sock)) {

			$selects->{$type}->add($sock);

			$::d_select && msg("adding select $type $fileno $callback\n");
		}

	} else {

		delete $callbacks->{$type}->{$fileno};

		if ($selects->{$type}->exists($sock)) {

			$selects->{$type}->remove($sock);

			$::d_select && msg("removing select $type $fileno\n");
		}
	}
}

sub select {
	my $select_time = shift;

	$::perfmon && $endSelectTime && $selectPerf->log(Time::HiRes::time() - $endSelectTime);
	
	my ($r, $w, $e) = IO::Select->select($selects->{'read'}, $selects->{'write'}, $selects->{'error'}, $select_time);

	$::perfmon && ($endSelectTime = Time::HiRes::time());

	my $count   = 0;

	my %handles = (
		'read'  => $r,
		'write' => $w,
		'error' => $e,
	);

	$::d_select && msgf("select returns (%s):\n", $select_time);

	while (my ($type, $handle) = each %handles) {

		$::d_select && msgf("\t%ss: %d of %d\n",
			$type, (defined($handle) && scalar(@$handle)), $selects->{$type}->count
		);

		foreach my $sock (@$handle) {

			my $callback = $callbacks->{$type}->{fileno($sock)};

			if (defined $callback && ref($callback) eq 'CODE') {

				$callback->($sock);
			}

			$count++;

			# Conditionally readUDP if there are SLIMP3's connected.
			Slim::Networking::Protocol::readUDP() if $Slim::Player::SLIMP3::SLIMP3Connected;
		}
	}

	return $count;
}

sub writeNoBlock {
	my $socket = shift;
	my $chunkRef = shift;

	return unless ($socket && $socket->opened());
	
	if (defined $chunkRef) {	
		use bytes;

		push @{$writeQueue{$socket}}, {
			'data'   => $chunkRef,
			'offset' => 0,
			'length' => length($$chunkRef)
		};
	}
	
	my $segment = shift(@{$writeQueue{$socket}});
	
	if (!defined $segment) {
		addWrite($socket);
		return;
	}
	
	$::d_select && msg("writeNoBlock: writing a segment of length: " . $segment->{'length'} . "\n");
	
	my $sentbytes = syswrite($socket, ${$segment->{'data'}}, $segment->{'length'}, $segment->{'offset'});

	if ($! == EWOULDBLOCK) {
		$::d_select && msg("writeNoBlock: Would block while sending.\n");
		$sentbytes = 0 unless defined $sentbytes;
	}

	if (!defined($sentbytes)) {

		$::d_select && msg("writeNoBlock: Send to socket had error, aborting.\n");
		delete($writeQueue{$socket});
		return;
	}

	# sent incomplete message
	if ($sentbytes < $segment->{'length'}) {

		$::d_select && msg("writeNoBlock: incomplete message, sent only: $sentbytes\n");

		$segment->{'length'} -= $sentbytes;
		$segment->{'offset'} += $sentbytes;

		unshift @{$writeQueue{$socket}}, $segment;

		addWrite($socket, \&writeNoBlock);
	} 
}

sub writeNoBlockQLen {
	my $socket = shift;

	if (defined $socket && defined $writeQueue{$socket} && ref($writeQueue{$socket}) eq 'ARRAY') {

		return scalar @{$writeQueue{$socket}};
	}

	return -1;
}

1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
