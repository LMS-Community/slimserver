# TODO: during installation we need to have Vista elevate the service helper:
# [HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers]
# "C:\\Program Files\\SqueezeCenter\\server\\svchelper.exe"="RUNASADMIN"

package Slim::Utils::ServiceManager::Win32;

use base qw(Slim::Utils::ServiceManager);

use File::Spec::Functions qw(catdir);
use FindBin qw($Bin);
use Win32::Process qw(DETACHED_PROCESS CREATE_NO_WINDOW NORMAL_PRIORITY_CLASS);
use Win32::Process::List;
use Win32::Service;
use Win32::TieRegistry ('Delimiter' => '/');

use constant SC_USER_REGISTRY_KEY => 'CUser/Software/Logitech/SqueezeCenter';
use constant SC_SERVICE_NAME => 'squeezesvc';

use Slim::Utils::OSDetect;
use Slim::Utils::ServiceManager;

my $os = Slim::Utils::OSDetect::getOS();

# Determine how the user wants to start SqueezeCenter
sub getStartupType {
	my %services;

	Win32::Service::GetServices('', \%services);

	if (grep {$services{$_} =~ /squeezesvc/} keys %services) {
		return SC_STARTUP_TYPE_SERVICE;
	}

	if ($Registry->{SC_USER_REGISTRY_KEY . '/StartAtLogin'}) {
		return SC_STARTUP_TYPE_LOGIN;
	}

	return SC_STARTUP_TYPE_NONE;
}

sub canSetStartupType {

	# on Vista+ we can elevate privileges	
	if ($os->get('isVista')) {
		return 1;
	}
	
	# on other Windows versions we have to be member of the administrators group to be able to manage the service
	# only return true if SC isn't configured to be run as a background service, OR if the user is an admin 
	else {

		my $isService = (getStartupType() == SC_STARTUP_TYPE_SERVICE);
		return ($isService && Win32::IsAdminUser()) || !$isService;
	}
}

sub getNonAdminOptions {
	if ($os->get('isVista') || Win32::IsAdminUser()) {
		return ('', 'RUN_NEVER', 'RUN_AT_LOGIN', 'RUN_AT_BOOT');
	}
	
	else {	
		return ('CLEANUP_NEED_ADMINISTRATOR', 'RUN_NEVER', 'RUN_AT_LOGIN');
	}	
}

sub setStartupType {
	my ($class, $type) = @_;
	
	my $oldType = getStartupType();
	$Registry->{SC_USER_REGISTRY_KEY . '/StartAtLogin'} = ($type == SC_STARTUP_TYPE_LOGIN || 0);

	my $svcHelper = qq("$Bin/svchelper.exe");
	
	# enable service mode
	if ($type == SC_STARTUP_TYPE_SERVICE && $oldType != SC_STARTUP_TYPE_SERVICE) {
		system($svcHelper, "--install");
	}
	elsif ($type != SC_STARTUP_TYPE_SERVICE && $oldType == SC_STARTUP_TYPE_SERVICE) {
		system($svcHelper, "--remove");
	}
	
	return 1;
}

sub initStartupType {
	my $class = shift;

	# preset atLogin if it isn't defined yet
	my $atLogin = $Registry->{SC_USER_REGISTRY_KEY . '/StartAtLogin'};
	$class->setStartupType(SC_STARTUP_TYPE_LOGIN) if ($atLogin != SC_STARTUP_TYPE_NONE && $atLogin != SC_STARTUP_TYPE_LOGIN);
}

sub canStart {
	canSetStartupType();
}

sub start {
	my ($class) = @_;
	
	return if $class->getStartupType() == SC_STARTUP_TYPE_SERVICE;
	
	my $appExe = Win32::GetShortPathName( catdir( $class->installDir, 'server', 'squeezecenter.exe' ) );
	
	$class->{checkHTTP} = 1;

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
	
	if ($class->getStartupType() == SC_STARTUP_TYPE_SERVICE) {

		my %status = ();

		Win32::Service::GetStatus('', SC_SERVICE_NAME, \%status);

		if ($status{'CurrentState'} == 0x04) {

			$class->{status} = SC_STATE_RUNNING;
		}

		elsif ($status{'CurrentState'} == 0x02) {

			$class->{status} = SC_STATE_STARTING;
		}

		elsif ($status{'CurrentState'} == 0x01) {

			$class->{status} = SC_STATE_STOPPED;
		}

#		elsif ($status{'CurrentState'} == 0x0???) {
#
#			$class->{status} = SC_STATE_STOPPING;
#		}

	} else {

		if (getProcessID() != -1) {

			$class->{status} = SC_STATE_RUNNING;
		}
		
		else {
			
			$class->{status} = SC_STATE_STOPPED;
		}
		
	}

	if ($class->{status} == SC_STATE_RUNNING) {

		if ($class->{checkHTTP} && !$class->checkForHTTP()) {

			$class->{status} = SC_STATE_STARTING;
		}

		else {

			$class->{checkHTTP} = 0;
		}
	}
	
	return $class->{status};
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
