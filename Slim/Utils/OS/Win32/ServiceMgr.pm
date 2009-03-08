package Slim::Utils::OS::Win32::ServiceMgr;

use Exporter::Lite;
@ISA = qw(Exporter);

our @EXPORT = qw( getStartupType getServiceState
	SC_STARTUP_TYPE_LOGIN SC_STARTUP_TYPE_NONE SC_STARTUP_TYPE_SERVICE
	SC_STATE_STOPPED SC_STATE_RUNNING SC_STATE_STARTING SC_STATE_STOPPING
);

use File::Spec::Functions qw(catdir);
use Socket;
use Win32::Process qw(DETACHED_PROCESS CREATE_NO_WINDOW NORMAL_PRIORITY_CLASS);
use Win32::Process::List;
use Win32::Service;
use Win32::TieRegistry ('Delimiter' => '/');

use Slim::Utils::OSDetect;
use Slim::Utils::Light;

use constant SC_USER_REGISTRY_KEY => 'CUser/Software/Logitech/SqueezeCenter';
use constant SC_SERVICE_NAME => 'squeezesvc';

use constant SC_STARTUP_TYPE_NONE    => 0;
use constant SC_STARTUP_TYPE_LOGIN   => 1;
use constant SC_STARTUP_TYPE_SERVICE => 2;

use constant SC_STATE_STOPPED  => 0;
use constant SC_STATE_RUNNING  => 1;
use constant SC_STATE_STARTING => -1;
use constant SC_STATE_STOPPING => -2;

Slim::Utils::OSDetect::init();

my $atLogin = $Registry->{SC_USER_REGISTRY_KEY . '/StartAtLogin'};
my $installDir = Slim::Utils::OSDetect::dirsFor('base');
my $appExe  = Win32::GetShortPathName( catdir( $installDir, 'server', 'squeezecenter.exe' ) );

my $processState;
my $starting  = 0;
my $checkHTTP = 0;

# Determine how the user wants to start SqueezeCenter
sub getStartupType {
	my %services;

	Win32::Service::GetServices('', \%services);

	if (grep {$services{$_} =~ /SC_SERVICE_NAME/} keys %services) {
		return SC_STARTUP_TYPE_SERVICE;
	}

	if ($atLogin) {
		return SC_STARTUP_TYPE_LOGIN;
	}

	return SC_STARTUP_TYPE_NONE;
}

sub setStartAtLogin {
	my ($class, $type) = @_;

	$Registry->{SC_USER_REGISTRY_KEY . '/StartAtLogin'} = $atLogin = ($type || 0);
}

sub startupTypeIsService {
	return (getStartupType() == SC_STARTUP_TYPE_SERVICE);
}

sub startupTypeIsLogin {
	return (getStartupType() == SC_STARTUP_TYPE_LOGIN);
}

sub initStartupType {
	# preset $atLogin if it isn't defined yet
	setStartupType(SC_STARTUP_TYPE_LOGIN) if ($atLogin != SC_STARTUP_TYPE_NONE && $atLogin != SC_STARTUP_TYPE_LOGIN);
}


sub start {
	my ($class) = @_;
	
	return if startupTypeIsService();
	
	$checkHTTP = 1;

	# start as background job
	my $processObj;
	Win32::Process::Create(
		$processObj,
		$appExe,
		'',
		0,
		DETACHED_PROCESS | CREATE_NO_WINDOW | NORMAL_PRIORITY_CLASS,
		'.'
	);
}


sub checkServiceState {
	if (startupTypeIsService()) {

		my %status = ();

		Win32::Service::GetStatus('', SC_SERVICE_NAME, \%status);

		if ($status{'CurrentState'} == 0x04) {

			$processState = SC_STATE_RUNNING;
		}

		elsif ($status{'CurrentState'} == 0x02) {

			$processState = SC_STATE_STARTING;
		}

		elsif ($status{'CurrentState'} == 0x01) {

			$processState = SC_STATE_STOPPED;
		}

#		elsif ($status{'CurrentState'} == 0x0???) {
#
#			$processState = SC_STATE_STOPPING;
#		}

	} else {

		if (getProcessID() != -1) {

			$processState = SC_STATE_RUNNING;
		}
		
		else {
			
			$processState = SC_STATE_STOPPED;
		}
		
	}

	if ($processState == SC_STATE_RUNNING) {

		if ($checkHTTP && !checkForHTTP()) {

			$processState = SC_STATE_STARTING;
		}

		else {

			$checkHTTP = 0;
		}
	}
	
	return $processState;
}

sub getServiceState {
	return $processState;
}

sub isRunning {
	return getServiceState() == SC_STATE_RUNNING;
}

sub getProcessID {

	my $p = Win32::Process::List->new;

	if ($p->IsError == 1) {

		return $p->GetErrorText;
	}

	# Windows sometimes only displays squeez~1.exe or similar
	my $pid = ($p->GetProcessPid(qr/^squeez(ecenter|~\d).exe$/i))[1];

	return $pid if defined $pid;
	return -1;
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
		return "http://$raddr:$httpPort";
	}

	return 0;
}

sub installDir {
	return $installDir;
}

1;
