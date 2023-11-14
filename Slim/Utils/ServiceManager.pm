package Slim::Utils::ServiceManager;

# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use Exporter::Lite;
@ISA = qw(Exporter);

our @EXPORT = qw(
	SC_STARTUP_TYPE_LOGIN SC_STARTUP_TYPE_NONE SC_STARTUP_TYPE_SERVICE
	SC_STATE_STOPPED SC_STATE_RUNNING SC_STATE_STARTING SC_STATE_STOPPING SC_STATE_UNKNOWN
);

use File::Spec::Functions qw(catdir);
use Socket;

use Slim::Utils::OSDetect;
use Slim::Utils::Light;

use constant SC_STARTUP_TYPE_NONE    => 0;
use constant SC_STARTUP_TYPE_LOGIN   => 1;
use constant SC_STARTUP_TYPE_SERVICE => 2;

use constant SC_STATE_STOPPED  => 0;
use constant SC_STATE_RUNNING  => 1;
use constant SC_STATE_STARTING => -1;
use constant SC_STATE_STOPPING => -2;
use constant SC_STATE_UNKNOWN  => -99;

Slim::Utils::OSDetect::init();

sub new {
	my $class = shift;

	my $svcMgr;

	if (Slim::Utils::OSDetect::isWindows()) {

		require Slim::Utils::ServiceManager::Win32;
		$svcMgr = Slim::Utils::ServiceManager::Win32->init();

	}

	elsif (Slim::Utils::OSDetect::isMac()) {

		require Slim::Utils::ServiceManager::OSX;
		$svcMgr = Slim::Utils::ServiceManager::OSX->init();

	}

	return $svcMgr || $class->init();
}

sub init {
	my $class = shift;

	my $self = {
		checkHTTP => 0,
		status    => SC_STATE_UNKNOWN,
	};

	return bless $self, $class;
}

# Determine how the user wants to start Logitech Media Server
sub getStartupType {
	return SC_STARTUP_TYPE_NONE;
}

sub canSetStartupType { 0 }
sub setStartupType {}
sub initStartupType {}
sub canStart {}

sub getStartupOptions {
	return ('', 'RUN_NEVER', 'RUN_AT_LOGIN', 'RUN_AT_BOOT');
}

sub start {}

sub checkServiceState {
	return SC_STATE_UNKNOWN;
}

# we're called often - cache results for a second
my %isRunning;
sub isRunning {

	if (!defined $isRunning{state} || $isRunning{ttl} < time()) {

		%isRunning = (
			ttl => time() + 1,
			state => $_[0]->checkServiceState() == SC_STATE_RUNNING
		);

	}

	return $isRunning{state};
}

sub getServiceState {
	return defined $_[0]->{status} ? $_[0]->{status} : SC_STATE_UNKNOWN;
}

sub checkForHTTP {
	my $httpPort = getPref('httpport') || 9000;

	# Use low-level socket code. IO::Socket returns a 'Invalid Descriptor'
	# erorr. It also sucks more memory than it should.
	my $rport = $httpPort;

	my $iaddr = inet_aton('127.0.0.1');
	my $paddr = sockaddr_in($rport, $iaddr);

	socket(SSERVER, PF_INET, SOCK_STREAM, getprotobyname('tcp'));

	if (connect(SSERVER, $paddr)) {

		close(SSERVER);
		return "http://127.0.0.1:$httpPort";
	}

	return 0;
}

1;
