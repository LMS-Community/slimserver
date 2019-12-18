package Slim::Networking::IO::Select;

# $Id$

# Logitech Media Server Copyright 2003-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;

use EV;
use Exporter::Lite;

use Slim::Utils::Errno;
use Slim::Utils::Log;
use Slim::Utils::Misc;

our @EXPORT = qw(addRead addWrite addError removeRead removeWrite removeError);

my $depth = 0;

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

=head2 addRead( $sock, $callback )

Add a socket to the select loop for reading.

$callback will be notified when the socket is readable.

=cut

sub addRead {
	_add( EV::READ() => @_ );
}

=head2 removeRead( $sock )

Remove a socket from the select loop and callback notification for reading.

=cut

sub removeRead {
	_remove( EV::READ() => shift );
}

=head2 addWrite( $sock, $callback )

Add a socket to the select loop for writing.

$callback will be notified when the socket is writable..

=cut

sub addWrite {
	_add( EV::WRITE() => @_ );
}

=head2 removeWrite( $sock )

Remove a socket from the select loop and callback notification for write.

=cut

sub removeWrite {
	_remove( EV::WRITE() => shift );
}

sub addError {}
sub removeError {}

sub _add {
	my ( $mode, $fh, $cb, $idle ) = @_;
	
	if(main::DEBUGLOG && $log->is_debug) {
		$log->debug(
			sprintf('fh=>%s(%d), mode=%s, cb=%s, idle=%d',
				defined($fh) ? $fh : 'undef', defined($fh) ? fileno($fh) : -1,
				$mode == EV::READ ? 'READ' : $mode == EV::WRITE ? 'WRITE' : "??-$mode",
				Slim::Utils::PerlRunTime::realNameForCodeRef($cb),
				$idle || -1));
		if (!defined $fh || !fileno($fh)) {
			logBacktrace('Invalid FH');
		}
	}
	
	return unless defined $fh && defined fileno($fh);
	
	my $w = EV::io(
		fileno($fh),
		$mode,
		sub {
			# If we've recursed into the loop via idleStreams, ignore
			# non-idle filehandles
			if ( $depth == 2 && !$idle ) {
				return;
			}

			main::PERFMON && (my $now = AnyEvent->time);
					
			eval { 
				# This die handler lets us get a correct backtrace if callback crashes
				local $SIG{__DIE__} = 'DEFAULT';
				
				$cb->( $fh, @{ ${*$fh}{passthrough} || [] } );
			};

			main::PERFMON && Slim::Utils::PerfMon->check('io', AnyEvent->time - $now, undef, $cb);
			
			if ( $@ ) {
				my $error = "$@";
				my $func = main::DEBUGLOG ? Slim::Utils::PerlRunTime::realNameForCodeRef($cb) : 'unk';
				logError("Select task failed calling $func: $error; fh=$fh");
			}
		},
	);

	my $slot = $mode == EV::READ ? '_ev_r' : '_ev_w';
	
	${*$fh}{$slot} = $w;
}

sub _remove {
	my ( $mode, $fh ) = @_;
	
	main::DEBUGLOG && $log->is_debug && $log->debug(
		sprintf('fh=>%s(%d), mode=%s',
			defined($fh) ? $fh : 'undef', defined($fh) ? fileno($fh) : -1,
			$mode == EV::READ ? 'READ' : $mode == EV::WRITE ? 'WRITE' : "??-$mode"));
	
	return unless defined $fh;

	my $slot = $mode == EV::READ ? '_ev_r' : '_ev_w';
	
	my $w = ${*$fh}{$slot} || return;
	
	$w->stop;
	
	delete ${*$fh}{$slot};
}

sub loop {
	my $type = shift;
	
	# Don't recurse more than once into the loop
	return if $depth == 2;
	
	$depth++;
	
	EV::loop( $type );
	
	$depth--;
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
