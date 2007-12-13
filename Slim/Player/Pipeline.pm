package Slim::Player::Pipeline;

# $Id$

# SqueezeCenter Copyright 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use base qw(IO::Handle);
use bytes;

use IPC::Open2;
use IO::Handle;
use POSIX qw(:sys_wait_h);

use Slim::Utils::Errno;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Network;
use Slim::Utils::OSDetect;

my $log = logger('player.source');

sub new {
	my $class   = shift;
	my $source  = shift;
	my $command = shift;
	my $local = shift;  # flag to indicate that pipeline is used for transcoding of local files and pipeline should not close on pause

	my $self = $class->SUPER::new();
	my ($reader, $writer);

	if ($^O =~ /Win32/) {

		my $listenReader = IO::Socket::INET->new(

			LocalAddr => 'localhost',
			Listen    => 5

		) || do {

			logError("Couldn't create listen socket for reader: $!");
			return undef;
		};

		my $readerPort = $listenReader->sockport;
		
		my ($listenWriter, $writerPort);

		if ($source) {

			$listenWriter = IO::Socket::INET->new(

				LocalAddr => 'localhost',
				Listen    => 5

			) || do {

				logError("Couldn't create listen socket for writer: $!");
				return undef;
			};

			$writerPort = $listenWriter->sockport;
		}

		$command =~ s/"/\\"/g;

		my $newcommand = '"' . Slim::Utils::Misc::findbin('socketwrapper') .  '" ';

		my $createMode = Win32::Process::NORMAL_PRIORITY_CLASS() | Win32::Process::CREATE_NO_WINDOW();

		if ($log->is_info || $log->is_debug) {

			$newcommand .= $log->is_debug ? ' -D ' : ' -d ';       # socketwrapper debugging (-D = verbose)

			$createMode = Win32::Process::NORMAL_PRIORITY_CLASS(); # create window so it is seen
		}


		if ($listenWriter) {
			$newcommand .= '-i ' . $writerPort . ' ';
		}

		if (!$local) {
			$newcommand .= ' -w ';                                 # enable checking of stream in socketwrapper
		}

		$newcommand .=  '-o ' . $readerPort . ' -c "' .  $command . '"';

		$log->info("Launching process with command: $newcommand");

		my $processObj;

		Slim::bootstrap::tryModuleLoad('Win32::Process');

		if ($@ || !Win32::Process::Create(
			$processObj,
			Slim::Utils::Misc::findbin("socketwrapper"),
			$newcommand,
			0,
			$createMode,
			".")
		) {

			logError("Couldn't create socketwrapper process");

			$listenReader->close();

			if ($listenWriter) {
				$listenWriter->close();
			}

			return undef;
		}

		${*$listenReader}{'pipeline'} = $self;
		${*$self}{'pipeline_listen_reader'} = $listenReader;
		Slim::Networking::Select::addRead($listenReader, \&acceptReader);
		Slim::Networking::Select::addError($listenReader, \&selectError);

		if ($listenWriter) {
			${*$listenWriter}{'pipeline'} = $self;
			${*$self}{'pipeline_listen_writer'} = $listenWriter;	
			Slim::Networking::Select::addRead($listenWriter, \&acceptWriter);
			Slim::Networking::Select::addError($listenWriter, \&selectError);
		}
	}
	else {
		$reader = IO::Handle->new();
		$writer = IO::Handle->new();

		open2($reader, $writer, $command);

		if (!defined(Slim::Utils::Network::blocking($reader, 0))) {

			logError("Cannot set pipe line reader to nonblocking");

			$reader->close();
			$writer->close();

			return undef;
		}
		
		if (!defined(Slim::Utils::Network::blocking($writer, 0))) {

			logError("Cannot set pipe line writer to nonblocking");

			$reader->close();
			$writer->close();

			return undef;
		}
		
		binmode($reader);
		binmode($writer);
	}

	if (defined($source)) {
		binmode($source);
	}

	${*$self}{'pipeline_reader'} = $reader;
	${*$self}{'pipeline_writer'} = $writer;
	${*$self}{'pipeline_source'} = $source;
	${*$self}{'pipeline_pending_bytes'} = '';
	${*$self}{'pipeline_pending_size'} = 0;
	${*$self}{'pipeline_error'} = 0;

	return $self;
}

sub acceptReader {
	my $listener = shift;
	my $pipeline = ${*$listener}{'pipeline'};

	my $reader = $listener->accept();

	if (!defined($reader)) {

		logError("Accepting on reader listener: $!");

		${*$pipeline}{'pipeline_error'} = 1;

		return;		
	}

	if (!defined(Slim::Utils::Network::blocking($reader, 0))) {

		logError("Cannot set pipe line reader to nonblocking");

		${*$pipeline}{'pipeline_error'} = 1;

		return;		
	}

	$log->info("Pipeline reader connected");

	binmode($reader);

	${*$pipeline}{'pipeline_reader'} = $reader;
}

sub acceptWriter {
	my $listener = shift;
	my $pipeline = ${*$listener}{'pipeline'};

	my $writer = $listener->accept();

	if (!defined($writer)) {

		logError("Accepting on writer listener: $!");

		${*$pipeline}{'pipeline_error'} = 1;

		return;
	}

	if (!defined(Slim::Utils::Network::blocking($writer, 0))) {

		logError("Cannot set pipe line writer to nonblocking");

		${*$pipeline}{'pipeline_error'} = 1;

		return;
	}

	$log->info("Pipeline writer connected");

	binmode($writer);

	${*$pipeline}{'pipeline_writer'} = $writer;
}

sub selectError {
	my $listener = shift;
	my $pipeline = ${*$listener}{'pipeline'};

	logError("From select on pipeline listeners.");

	${*$pipeline}{'pipeline_error'} = 1;
}

sub sysread {
	my $self = $_[0];
	my $chunksize = $_[2];
	my $readlen;

	my $error = ${*$self}{'pipeline_error'};

	if ($error) {
		$! = -1;
		return undef;
	}

	my $reader = ${*$self}{'pipeline_reader'};
	my $writer = ${*$self}{'pipeline_writer'};
	my $source = ${*$self}{'pipeline_source'};

	unless (defined($reader) && (!defined($source) || defined($writer))) {
		$! = EWOULDBLOCK;
		return undef;
	}

	my $loop;
	do {
		$loop = 0;
		$readlen = $reader->sysread($_[1], $chunksize);

		# We'd block on the reader, so see if we can write more
		if (!defined($readlen) && ($! == EWOULDBLOCK) && defined($source)) {

			my $pendingBytes = ${*$self}{'pipeline_pending_bytes'};
			my $pendingSize  = ${*$self}{'pipeline_pending_size'};

			if ($pendingSize) {

				$log->debug("Pipeline has some pending bytes");

			}
			else {

				$log->debug("Pipeline doesn't have pending bytes - trying to get some from source");

				my $socketReadlen = $source->sysread($pendingBytes, $chunksize);

				if (!$socketReadlen) {
					return $socketReadlen;
				}

				$pendingSize = $socketReadlen;
			}

			$log->debug("Attempting to write to pipeline writer");

			my $writelen = $writer->syswrite($pendingBytes, $pendingSize);

			if ($writelen) {

				$log->debug("Wrote $writelen bytes to pipeline writer");

				if ($writelen != $pendingSize) {
					${*$self}{'pipeline_pending_bytes'} = substr($pendingBytes, $writelen);
					${*$self}{'pipeline_pending_size'}  = $pendingSize - $writelen;
				}
				else {
					${*$self}{'pipeline_pending_bytes'} = '';
					${*$self}{'pipeline_pending_size'}  = 0;
				}
			}
			else {

				${*$self}{'pipeline_pending_bytes'} = $pendingBytes;
				${*$self}{'pipeline_pending_size'}  = $pendingSize;
				return $writelen;
			}

			$loop = 1;
		}

	} while ($loop);
	
	return $readlen;
}

sub sysseek {
	my $self = shift;

	return 0;
}

sub close {
	my $self = shift;

	my $reader = ${*$self}{'pipeline_reader'};

	if (defined($reader)) {
		$reader->close();
	}

	my $writer = ${*$self}{'pipeline_writer'};

	if (defined($writer)) {
		$writer->close();
	}

	my $listenReader = ${*$self}{'pipeline_listen_reader'};

	if (defined($listenReader)) {

		Slim::Networking::Select::addRead($listenReader, undef);
		Slim::Networking::Select::addError($listenReader, undef);

		${*$listenReader}{'pipeline'} = undef;

		$listenReader->close();
	}

	my $listenWriter = ${*$self}{'pipeline_listen_writer'};

	if (defined($listenWriter)) {

		Slim::Networking::Select::addRead($listenWriter, undef);
		Slim::Networking::Select::addError($listenWriter, undef);

		${*$listenWriter}{'pipeline'} = undef;

		$listenWriter->close();
	}

	my $source = ${*$self}{'pipeline_source'};

	if (defined($source)) {
		$source->close();
	}
}

1;

__END__
