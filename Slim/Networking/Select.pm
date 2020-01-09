package Slim::Networking::Select;


# Logitech Media Server Copyright 2003-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;

use Slim::Networking::IO::Select;
use Slim::Utils::Errno;
use Slim::Utils::Log;
use Slim::Utils::Misc;

=head1 NAME

Slim::Networking::Select

=head1 SYNOPSIS

Slim::Utils::Select::addRead( $socket, \&callback )

=head1 DESCRIPTION

This module encapsulates all select() related code, handled by Logitech Media Server's main loop.

Usually, you'll want to use higher such as L<Slim::Networking::Async::HTTP>.

=head1 FUNCTIONS

=cut

my $log = logger('server.select');

our %writeQueue = ();

=head2 writeNoBlock( $socket, $chunkRef )

Send a chunk of data out on $socket without blocking.

If multiple syswrites are required to send out the entire $chunkRef, multiple
calls to L<Slim::Networking::Select::select()> will handle it.

=cut

sub writeNoBlock {
	my $socket = shift;
	my $chunkRef = shift;

	return unless ($socket && $socket->opened());

	push @{$writeQueue{$socket}}, {
		'data'   => $chunkRef,
		'offset' => 0,
		'length' => length($$chunkRef)
	};

	_writeNoBlock($socket);
}

sub _writeNoBlock {
	my $socket = shift;

	my $segment = shift(@{$writeQueue{$socket}});
	
	if (!defined $segment) {
		removeWrite($socket);
		return;
	}

	if ( main::INFOLOG && $log->is_info ) {
		$log->info(sprintf("fileno: [%d] Wrote $segment->{'length'} bytes", fileno($socket)));
	}

	my $sentbytes = syswrite($socket, ${$segment->{'data'}}, $segment->{'length'}, $segment->{'offset'});

	if ($! == EWOULDBLOCK) {

		if ( main::INFOLOG && $log->is_info ) {
			$log->info(sprintf("fileno: [%d] Would block while sending.", fileno($socket)));
		}

		$sentbytes = 0 unless defined $sentbytes;
	}

	if (!defined($sentbytes)) {

		if ( main::INFOLOG && $log->is_info ) {
			$log->info(sprintf("fileno: [%d] Send to socket had error, aborting.", fileno($socket)));
		}

		removeWrite($socket);
		removeWriteNoBlockQ($socket);
		return;
	}

	# sent incomplete message
	if ($sentbytes < $segment->{'length'}) {

		if ( main::INFOLOG && $log->is_info ) {
			$log->info(sprintf("fileno: [%d] Incomplete message, sent only: $sentbytes", fileno($socket)));
		}

		$segment->{'length'} -= $sentbytes;
		$segment->{'offset'} += $sentbytes;

		unshift @{$writeQueue{$socket}}, $segment;

		addWrite($socket, \&_writeNoBlock, 1);
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
		
		if ( main::INFOLOG && $log->is_info ) {
			$log->info(sprintf("fileno: [%d] removing writeNoBlock queue", fileno($socket)));
		}

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
