package Slim::Utils::ServiceManager;

use Exporter::Lite;
@ISA = qw(Exporter);

our @EXPORT = qw(
	SC_STARTUP_TYPE_LOGIN SC_STARTUP_TYPE_NONE SC_STARTUP_TYPE_SERVICE
	SC_STATE_STOPPED SC_STATE_RUNNING SC_STATE_STARTING SC_STATE_STOPPING
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

my $installDir = Slim::Utils::OSDetect::dirsFor('base');

sub new {
	my $class = shift;

	my $svcMgr;
	my $os = Slim::Utils::OSDetect::getOS();

	if ($os->name eq 'win') {

		require Slim::Utils::ServiceManager::Win32;
		$svcMgr = Slim::Utils::ServiceManager::Win32->init();

	}

	return $svcMgr;
}

sub init {
	my $class = shift;

	my $self = {
		starting  => 0,
		checkHTTP => 0,
	};
	
	return bless $self, $class;
}

# Determine how the user wants to start SqueezeCenter
sub getStartupType {
	return SC_STARTUP_TYPE_NONE;
}

sub setStartAtLogin {}

sub startupTypeIsService {
	return (getStartupType() == SC_STARTUP_TYPE_SERVICE);
}

sub startupTypeIsLogin {
	return (getStartupType() == SC_STARTUP_TYPE_LOGIN);
}

sub initStartupType {}
sub start {}
sub checkServiceState {}

sub getServiceState {
	return SC_STATE_UNKNOWN;
}

sub isRunning {
	return getServiceState() == SC_STATE_RUNNING;
}

sub getProcessID {}

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
		return "http://$raddr:$httpPort";
	}

	return 0;
}

sub installDir {
	return $installDir;
}

1;
