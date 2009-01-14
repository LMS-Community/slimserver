package Slim::Networking::IO::EV;

# $Id$

# SqueezeCenter Copyright 2003-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

# EV-based replacement for Select

use strict;

use Exporter::Lite;

# Force poll backend on Linux
BEGIN {
	if ( $^O =~ /linux/ ) {
		$ENV{LIBEV_FLAGS} = 2;
	}
}

use EV;

use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::PerfMon;

our @EXPORT = qw(addRead addWrite addError removeRead removeWrite removeError select);

my $log = logger('server.select');

my $watcher_timer;
my @fileno_watcher;
my %callbacks;

my $selectInstance = 0;

if ( $log->is_debug ) {
	my $methods = {
        EV::BACKEND_SELECT()  => 'select',
        EV::BACKEND_POLL()    => 'poll',
        EV::BACKEND_EPOLL()   => 'epoll',
        EV::BACKEND_KQUEUE()  => 'kqueue',
        EV::BACKEND_DEVPOLL() => 'devpoll',
        EV::BACKEND_PORT()    => 'port',
    };

    warn "EV is using method: " . $methods->{ EV::backend() } . "\n";
}

sub addRead {
	_add( EV::READ => @_ );
}

sub removeRead {
	_remove( EV::READ => shift );
}

sub addError {}

sub addWrite {
	_add( EV::WRITE => @_ );
}

sub removeWrite {
	_remove( EV::WRITE => shift );
}

sub removeError {}

sub _add {
	my ( $ev_mode, $sock, $callback, $idle ) = @_;
	
	return unless defined $sock;
	
	my $fileno = fileno($sock);
	
	$callbacks{ $sock }->[ $ev_mode ] = $callback;
	
	$fileno_watcher[ $fileno ]->[ $ev_mode ] = EV::io(
        $sock,
        $ev_mode,
        \&_io_callback,
    );

	if ( $log->is_info ) {
		$log->info( sprintf("fileno: [%s] Adding %s -> %s",
			$fileno,
			( $ev_mode & EV::READ ) ? 'read' : 'write',
			Slim::Utils::PerlRunTime::realNameForCodeRef($callback),
		) );
	}
}

sub _remove {
	my ( $ev_mode, $sock ) = @_;
	
	return unless defined $sock;
	
	my $fileno = fileno($sock);
	
	my $watcher = $fileno_watcher[ $fileno ]->[ $ev_mode ];
	
	return unless defined $watcher;
	
	$watcher->stop();
	
	undef $fileno_watcher[ $fileno ]->[ $ev_mode ];
	
	if ( $log->is_info ) {
		$log->info( sprintf("fileno: [%d] Removing %s",
			$fileno,
			( $ev_mode & EV::READ ) ? 'read' : 'write',
		) );
	}
}

sub select {
	my $timeout = shift;
	my $idle    = shift || 0;
	
	$selectInstance = ($selectInstance + 1) % 1000;
	
	if ( $log->is_info ) {
		$log->info( "select( $timeout, $idle )" );
	}
	
	# Use an EV timer to implement the timeout
	if ( $timeout ) {
		$watcher_timer = EV::timer( $timeout, 0, sub {} );
	
		EV::loop( EV::LOOP_ONESHOT );
	}
	else {
		# don't wait, just check
		EV::loop( EV::LOOP_NONBLOCK );
	}
}

sub _io_callback {
	my ( $watcher, $ev_mode ) = @_;
	
	my $sock = $watcher->fh;
	
	my $callback = $callbacks{ $sock }->[ $ev_mode ];
	
	if ( defined $callback && ref $callback eq 'CODE' ) {
		if ( $log->is_info ) {
			$log->info(sprintf("fileno [%s] %s, calling %s",
				fileno($sock),
				( $ev_mode & EV::READ ) ? 'read' : 'write',
				Slim::Utils::PerlRunTime::realNameForCodeRef($callback),
			));
		}
		
		# Need to detect if the callback called idleStreams
		my $thisInstance = $selectInstance;
		
		# the socket may have passthrough arguments set
		my $passthrough = ${*$sock}{passthrough} || [];
		
		eval {
			# This die handler lets us get a correct backtrace if callback crashes
			local $SIG{__DIE__} = sub {
				my $msg = shift;
				
				if ( main::SLIM_SERVICE ) {
					# Only notify if eval_depth is 2, this avoids emailing for errors inside
					# nested evals
					if ( eval_depth() == 2 ) {
						my $func = Slim::Utils::PerlRunTime::realNameForCodeRef($callback);
						SDI::Service::Control->mailError( "IO callback crash: $func", $msg );
					}
				}
			};
			
			$callback->( $sock, @{$passthrough} );
		};
		
		if ( $@ ) {
			my $func = Slim::Utils::PerlRunTime::realNameForCodeRef($callback);
			logError("Select task failed calling $func: $@");
		}
		
		# Conditionally readUDP if there are SLIMP3's connected.
		Slim::Networking::UDP::readUDP() if $Slim::Player::SLIMP3::SLIMP3Connected;
		
		# Exit loop if the callback called idleStreams
		if ( $thisInstance != $selectInstance ) {
			EV::unloop;
		}
	}
}

sub eval_depth {
	my $eval_depth = 0;
	my $frame      = 0;
	
	while ( my @caller_info = caller( $frame++ ) ) {
		if ( $caller_info[3] eq '(eval)' ) {
			$eval_depth++;
		}
	}
	
	return $eval_depth;
}

1;
    