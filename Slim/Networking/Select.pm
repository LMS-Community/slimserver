package Slim::Networking::Select;

# $Id$

# SlimServer Copyright (c) 2003-2006 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use warnings;
use IO::Select;

use Slim::Utils::Errno;
use Slim::Utils::Misc;
use Slim::Utils::PerfMon;

=head1 NAME

Slim::Networking::Select

=head1 SYNOPSIS

Slim::Utils::Select::addRead( $socket, \&callback )

=head1 DESCRIPTION

This module encapsulates all select() related code, handled by SlimServer's main loop.

Usually, you'll want to use higher such as L<Slim::Networking::Async::HTTP>.

=head1 FUNCTIONS

=cut

our $callbacks  = {};
our %writeQueue = ();

our $selects = {
	'read'     => IO::Select->new, # vectors used for normal select
	'write'    => IO::Select->new,
	'error'    => IO::Select->new,
	'is_read'  => IO::Select->new, # alternatives for select within idleStreams
	'is_write' => IO::Select->new,
	'is_error' => IO::Select->new,
};

our $responseTime = Slim::Utils::PerfMon->new('Response Time', [0.002, 0.005, 0.010, 0.015, 0.025, 0.050, 0.1, 0.5, 1, 5]);
our $selectTask = Slim::Utils::PerfMon->new('Select Task', [0.002, 0.005, 0.010, 0.015, 0.025, 0.050, 0.1, 0.5, 1, 5], 1);

my $endSelectTime;

my $selectInstance = 0;

=head2 addRead( $sock, $callback )

Add a socket to the select loop for reading.

$callback will be notified when the socket is readable.

=cut

sub addRead {

	_updateSelect('read', @_);
}

=head2 removeRead( $sock )

Remove a socket from the select loop and callback notification for reading.

=cut

sub removeRead {
	
	_updateSelect('read', shift);
}

=head2 addWrite( $sock, $callback )

Add a socket to the select loop for writing.

$callback will be notified when the socket is writable..

=cut

sub addWrite {

	_updateSelect('write', @_);
}

=head2 removeWrite( $sock )

Remove a socket from the select loop and callback notification for write.

=cut

sub removeWrite {
	
	_updateSelect('write', shift);
}

=head2 addError( $sock, $callback )

Add a socket to the select loop for error checking.

$callback will be notified when the socket has an error.

=cut

sub addError {

	_updateSelect('error', @_);
}

=head2 removeError( $sock )

Remove a socket from the select loop and callback notification for errors.

=cut

sub removeError {
	
	_updateSelect('error', shift);
}

sub _updateSelect {
	my ($type, $sock, $callback, $idle) = @_;
	
	return unless defined $sock;

	if ($callback) {

		$callbacks->{$type}->{$sock} = $callback;

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

		delete $callbacks->{$type}->{$sock};

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

=head2 select( $selectTime, [ $idleStreams ] )

Services all sockets currently in the select loop. Callbacks will be notified
when a socket is readable, writable or has an error.

The only callers are slimserver.pl::idle() and slimserver.pl::idleStreams()

=cut

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

			my $callback = $callbacks->{$type}->{$sock};

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

=head2 writeNoBlock( $socket, $chunkRef )

Send a chunk of data out on $socket without blocking.

If multiple syswrites are required to send out the entire $chunkRef, multiple
calls to L<Slim::Networking::Select::select()> will handle it.

=cut

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

=head2 writeNoBlockQLen( $socket )

Returns the number of chunks in the queue which have not been written out to
$socket.

Returns -1 if there are no chunks to be written.

=cut

sub writeNoBlockQLen {
	my $socket = shift;

	if (defined $socket && defined $writeQueue{$socket} && ref($writeQueue{$socket}) eq 'ARRAY') {

		return scalar @{$writeQueue{$socket}};
	}

	return -1;
}

=head2 removeWriteNoBlockQ( $socket )

Remove $socket and any associated chunks from being sent.

=cut

sub removeWriteNoBlockQ {
	my $socket = shift;
	
	if ( exists($writeQueue{$socket}) ) {
		
		$::d_select && msgf("Select: [%s] removing writeNoBlock queue\n", $socket);

		delete($writeQueue{$socket});
	}
}

=head1 SEE ALSO

L<IO::Select>

L<Slim::Networking::Async::HTTP>

L<Slim::Networking::Slimproto>

=cut

1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
