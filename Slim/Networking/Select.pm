package Slim::Networking::Select;

# $Id$

# SlimServer Copyright (c) 2003-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use IO::Select;
use Slim::Utils::Misc;

BEGIN {
	if ($^O =~ /Win32/) {
		*EWOULDBLOCK = sub () { 10035 };
		*EINPROGRESS = sub () { 10036 };
	} else {
		require Errno;
		import Errno qw(EWOULDBLOCK EINPROGRESS);
	}
}

our %readSockets;
our %readCallbacks;

our %writeSockets;
our %writeCallbacks;

our %errorSockets;
our %errorCallbacks;

our %writeQueue;

our $readSelects  = IO::Select->new();
our $writeSelects = IO::Select->new();
our $errorSelects  = IO::Select->new();

sub addRead {
	my $r = shift;
	my $callback = shift;

	if (!$callback) {

		delete $readSockets{"$r"};
		delete $readCallbacks{"$r"};
		$::d_select && msg("removing select read $r\n");

	} else {

		$readSockets{"$r"} = $r;
		$readCallbacks{"$r"} = $callback;
		$::d_select && msg("adding select read $r $callback\n");
	}

	$readSelects = IO::Select->new(map {$readSockets{$_}} (keys %readSockets));
}

sub addWrite {
	my $w = shift;
	my $callback = shift;
	
	$::d_select && msg("before: " . scalar(keys %writeSockets) . "/" . $writeSelects->count . "\n");

	if (!$callback) {
		delete $writeSockets{"$w"};
		delete $writeCallbacks{"$w"};	
		$::d_select && msg("removing select write $w\n");
	} else {
		$writeSockets{"$w"} = $w;
		$writeCallbacks{"$w"} = $callback;
		$::d_select && msg("adding select write $w $callback\n");
	}

	$writeSelects = IO::Select->new(map {$writeSockets{$_}} (keys %writeSockets));

	$::d_select && msg("now: " . scalar(keys %writeSockets) . "/" . $writeSelects->count . "\n");
}

sub addError {
      my $e = shift;
      my $callback = shift;

      if (!$callback) {

              delete $errorSockets{"$e"};
              delete $errorCallbacks{"$e"};
              $::d_select && msg("removing select error $e\n");

      } else {

              $errorSockets{"$e"} = $e;
              $errorCallbacks{"$e"} = $callback;
              $::d_select && msg("adding select error $e $callback\n");
      }

      $errorSelects = IO::Select->new(map {$errorSockets{$_}} (keys %errorSockets));
}


sub select {
	my $select_time = shift;
	
	my ($r, $w, $e) = IO::Select->select($readSelects,$writeSelects,$errorSelects,$select_time);

	$::d_select && msg("select returns ($select_time): reads: " . 
		(defined($r) && scalar(@$r)) . " of " . $readSelects->count .
		" writes: " . (defined($w) && scalar(@$w)) . " of " . $writeSelects->count .
		" errors: " . (defined($e) && scalar(@$e)) . " of " . $errorSelects->count . "\n");
	
	my $count = 0;

	foreach my $sock (@$r) {
		my $readsub = $readCallbacks{"$sock"};
		$readsub->($sock) if $readsub;
		$count++;

		# Conditionally readUDP if there are SLIMP3's connected.
		Slim::Networking::Protocol::readUDP() if $Slim::Player::SLIMP3::SLIMP3Connected;
	}
	
	foreach my $sock (@$w) {
		my $writesub = $writeCallbacks{"$sock"};
		$writesub->($sock) if $writesub;
		$count++;

		Slim::Networking::Protocol::readUDP() if $Slim::Player::SLIMP3::SLIMP3Connected;
	}

	foreach my $sock (@$e) {
		my $errorsub = $errorCallbacks{"$sock"};
		$errorsub->($sock) if $errorsub;
		$count++;

		Slim::Networking::Protocol::readUDP() if $Slim::Player::SLIMP3::SLIMP3Connected;
	}

	return $count;
}

sub writeNoBlock {
	my $socket = shift;
	my $chunkRef = shift;

	return unless ($socket && $socket->opened());
	
	if (defined $chunkRef) {	
		push @{$writeQueue{"$socket"}}, {
			'data'   => $chunkRef,
			'offset' => 0,
			'length' => length($$chunkRef)
		};
	}
	
	my $segment = shift(@{$writeQueue{"$socket"}});
	
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
		# Treat $httpClient with suspicion
		$::d_select && msg("writeNoBlock: Send to socket had error, aborting.\n");
		delete($writeQueue{"$socket"});
		return;
	}

	# sent incomplete message
	if ($sentbytes < $segment->{'length'}) {
		$::d_select && msg("writeNoBlock: incomplete message, sent only: $sentbytes\n");
		$segment->{'length'} -= $sentbytes;
		$segment->{'offset'} += $sentbytes;
		unshift @{$writeQueue{"$socket"}}, $segment;
		addWrite($socket, \&writeNoBlock);
	} 
}

sub writeNoBlockQLen {
	my $socket = shift;

	if (defined $socket && defined $writeQueue{"$socket"} && ref($writeQueue{"$socket"}) eq 'ARRAY') {

		return scalar @{$writeQueue{"$socket"}};
	}

	return -1;
}

1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
