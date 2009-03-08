package Slim::Utils::ServiceManager::Win32;

use base qw(Slim::Utils::ServiceManager);

use File::Spec::Functions qw(catdir);
use Win32::Process qw(DETACHED_PROCESS CREATE_NO_WINDOW NORMAL_PRIORITY_CLASS);
use Win32::Process::List;
use Win32::Service;
use Win32::TieRegistry ('Delimiter' => '/');

use constant SC_USER_REGISTRY_KEY => 'CUser/Software/Logitech/SqueezeCenter';
use constant SC_SERVICE_NAME => 'squeezesvc';

use Slim::Utils::ServiceManager;

my $atLogin = $Registry->{SC_USER_REGISTRY_KEY . '/StartAtLogin'};

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

sub initStartupType {
	my $class = shift;

	# preset $atLogin if it isn't defined yet
	$class->setStartupType(SC_STARTUP_TYPE_LOGIN) if ($atLogin != SC_STARTUP_TYPE_NONE && $atLogin != SC_STARTUP_TYPE_LOGIN);
}


sub start {
	my ($class) = @_;
	
	return if $class->startupTypeIsService();
	
	my $appExe = Win32::GetShortPathName( catdir( $class->installDir, 'server', 'squeezecenter.exe' ) );
	
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
	my $class = shift;
	
	if ($class->startupTypeIsService()) {

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

		if ($checkHTTP && !$class->checkForHTTP()) {

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

1;
