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
	'read'    => IO::Select->new, # vectors used for normal select
	'write'   => IO::Select->new,
	'error'   => IO::Select->new,
	'is_read'  => IO::Select->new, # alternatives for select within idleStreams
	'is_write' => IO::Select->new,
	'is_error' => IO::Select->new,
};

our $responseTime = Slim::Utils::PerfMon->new('Response Time', [0.002, 0.005, 0.010, 0.015, 0.025, 0.050, 0.1, 0.5, 1, 5]);
our $selectTask = Slim::Utils::PerfMon->new('Select Task', [0.002, 0.005, 0.010, 0.015, 0.025, 0.050, 0.1, 0.5, 1, 5], 1);

my $endSelectTime;

my $selectInstance = 0;

sub addRead {

	_updateSelect('read', @_);
}

sub removeRead {
	
	_updateSelect('read', shift);
}

sub addWrite {

	_updateSelect('write', @_);
}

sub removeWrite {
	
	_updateSelect('write', shift);
}

sub addError {

	_updateSelect('error', @_);
}

sub removeError {
	
	_updateSelect('error', shift);
}

sub _updateSelect {
	my ($type, $sock, $callback, $idle) = @_;

	my $fileno = fileno($sock);

	if ($callback) {

		$callbacks->{$type}->{$fileno} = $callback;

		if (!$selects->{$type}->exists($sock)) {

			$selects->{$type}->add($sock);

			$selects->{'is_'.$type}->add($sock) if $idle;

			$::d_select && msgf("Select: [%s] Adding %s -> %s\n",
				$sock,
				$type,
				Slim::Utils::PerlRunTime::realNameForCodeRef($callback),
			);
		}
		else {
			$::d_select && msgf("Select: [%s] Not adding %s -> %s, already exists\n",
				$sock,
				$type,
				Slim::Utils::PerlRunTime::realNameForCodeRef($callback),
			);
		}

	} else {

		delete $callbacks->{$type}->{$fileno};

		if ($selects->{$type}->exists($sock)) {

			$selects->{$type}->remove($sock);
		}

		if ($selects->{'is_'.$type}->exists($sock)) {

			$selects->{'is_'.$type}->remove($sock);
		}
		
		$::d_select && msgf("Select: [%s] Removing %s\n",
			$sock,
			$type,
		);
	}
}

sub select {
	my $select_time = shift;
	my $idleStreams = shift; # called from idleStreams

	$::perfmon && $endSelectTime && $responseTime->log(Time::HiRes::time() - $endSelectTime);

	my ($r, $w, $e) = ( $idleStreams )
		? IO::Select->select($selects->{'is_read'}, $selects->{'is_write'}, $selects->{'is_error'}, $select_time)
		: IO::Select->select($selects->{'read'}, $selects->{'write'}, $selects->{'error'}, $select_time);

	$::perfmon && ($endSelectTime = Time::HiRes::time());

	$selectInstance = ($selectInstance + 1) % 1000;

	my $thisInstance = $selectInstance;

	my $count   = 0;

	my %handles = (
		'read'  => $r,
		'write' => $w,
		'error' => $e,
	);

	while (my ($type, $handle) = each %handles) {

		foreach my $sock (@$handle) {

			my $callback = $callbacks->{$type}->{fileno($sock)};

			if (defined $callback && ref($callback) eq 'CODE') {
				
				$::perfmon && (my $now = Time::HiRes::time());
				
				$::d_select && msgf("Select: [%s] %s, calling %s\n",
					$sock,
					$type,
					Slim::Utils::PerlRunTime::realNameForCodeRef($callback),
				);

				# the socket may have passthrough arguments set
				my $passthrough = ${*$sock}{'passthrough'} || [];
				
				$callback->( $sock, @{$passthrough} );

				$::perfmon && $now && $selectTask->log(Time::HiRes::time() - $now) &&
					msg(sprintf("    %s\n", Slim::Utils::PerlRunTime::realNameForCodeRef($callback)), undef, 1);
			}

			$count++;

			# Conditionally readUDP if there are SLIMP3's connected.
			Slim::Networking::UDP::readUDP() if $Slim::Player::SLIMP3::SLIMP3Connected;

			# return if select has been run more recently than thisInstance (if run inside callback)
			return $count if ($thisInstance != $selectInstance);
		}
	}

	return $count;
}

sub writeNoBlock {
	my $socket = shift;
	my $chunkRef = shift;

	return unless ($socket && $socket->opened());
	
	if (defined $chunkRef) {	

		push @{$writeQueue{$socket}}, {
			'data'   => $chunkRef,
			'offset' => 0,
			'length' => length($$chunkRef)
		};
	}
	
	my $segment = shift(@{$writeQueue{$socket}});
	
	if (!defined $segment) {
		removeWrite($socket);
		return;
	}

	$::d_select && msgf("Select: [%s] Wrote %d bytes\n",
		$socket,
		$segment->{'length'},
	);
	
	my $sentbytes = syswrite($socket, ${$segment->{'data'}}, $segment->{'length'}, $segment->{'offset'});

	if ($! == EWOULDBLOCK) {
		$::d_select && msg("Select: Would block while sending.\n");
		$sentbytes = 0 unless defined $sentbytes;
	}

	if (!defined($sentbytes)) {

		$::d_select && msg("Select: Send to socket had error, aborting.\n");
		removeWrite($socket);
		removeWriteNoBlockQ($socket);
		return;
	}

	# sent incomplete message
	if ($sentbytes < $segment->{'length'}) {

		$::d_select && msg("Select: incomplete message, sent only: $sentbytes\n");

		$segment->{'length'} -= $sentbytes;
		$segment->{'offset'} += $sentbytes;

		unshift @{$writeQueue{$socket}}, $segment;

		addWrite($socket, \&writeNoBlock, 1);
	} 
}

sub writeNoBlockQLen {
	my $socket = shift;

	if (defined $socket && defined $writeQueue{$socket} && ref($writeQueue{$socket}) eq 'ARRAY') {

		return scalar @{$writeQueue{$socket}};
	}

	return -1;
}

sub removeWriteNoBlockQ {
	my $socket = shift;
	
	if ( exists($writeQueue{$socket}) ) {
		
		$::d_select && msgf("Select: [%s] removing writeNoBlock queue\n", $socket);

		delete($writeQueue{$socket});
	}
}

1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
