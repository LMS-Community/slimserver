package Slim::Utils::ServiceManager::Win32;

# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use base qw(Slim::Utils::ServiceManager);

use File::Spec::Functions qw(catdir);
use FindBin qw($Bin);
use Win32::Process qw(DETACHED_PROCESS CREATE_NO_WINDOW NORMAL_PRIORITY_CLASS);
use Win32::Process::List;
use Win32::Service;
use Win32::TieRegistry ('Delimiter' => '/');

use constant SC_USER_REGISTRY_KEY => 'CUser/Software/Logitech/SqueezeCenter';
use constant SB_USER_REGISTRY_KEY => 'CUser/Software/Logitech/Squeezebox';
use constant SC_SERVICE_NAME => 'squeezesvc';

use Slim::Utils::OSDetect;
use Slim::Utils::ServiceManager;

my $os = Slim::Utils::OSDetect::getOS();
my $svcHelper;

sub init {
	my $class = shift;
	$class = $class->SUPER::init();
	$svcHelper = catdir( Win32::GetShortPathName( scalar $os->dirsFor('base') ), 'server', 'squeezesvc.exe' );

	return $class;
}

# Determine how the user wants to start Logitech Media Server
sub getStartupType {
	my %services;

	Win32::Service::GetServices('', \%services);

	if (grep {$services{$_} =~ /squeezesvc/} keys %services) {
		return SC_STARTUP_TYPE_SERVICE;
	}

	if ($Registry->{SB_USER_REGISTRY_KEY . '/StartAtLogin'}) {
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

sub getStartupOptions {
	my $class = shift;

	if (!$os->get('isVista') && !Win32::IsAdminUser()) {
		return ('CONTROLPANEL_NEED_ADMINISTRATOR', 'RUN_NEVER', 'RUN_AT_LOGIN');
	}

	return $class->SUPER::getStartupOptions();
}

sub setStartupType {
	my ($class, $type, $username, $password) = @_;
	$username = '' unless defined $username;

	$Registry->{SB_USER_REGISTRY_KEY . '/StartAtLogin'} = ($type == SC_STARTUP_TYPE_LOGIN || 0);

	# enable service mode
	if ($type == SC_STARTUP_TYPE_SERVICE) {
		my @args;

		push @args, "--username=$username" if $username;
		push @args, "--password=$password" if $password;
		push @args, '--install';

		system($svcHelper, @args);
	}
	else {
		system($svcHelper, "--remove");
	}

	return 1;
}

sub initStartupType {
	my $class = shift;

	# preset atLogin if it isn't defined yet
	my $atLogin = $Registry->{SB_USER_REGISTRY_KEY . '/StartAtLogin'};

	if ($atLogin !~ /[01]/) {

		# make sure our Key does exist before we can write to it
		if (! (my $regKey = $Registry->{SB_USER_REGISTRY_KEY . ''})) {
			$Registry->{'CUser/Software/Logitech/'} = {
				'Squeezebox/' => {}
			};
		}

		# migrate startup setting
		if (defined $Registry->{SC_USER_REGISTRY_KEY . '/StartAtLogin'}) {
			$Registry->{SB_USER_REGISTRY_KEY . '/StartAtLogin'} = $Registry->{SC_USER_REGISTRY_KEY . '/StartAtLogin'};
			delete $Registry->{SC_USER_REGISTRY_KEY . '/StartAtLogin'};
		}

		$class->setStartupType(SC_STARTUP_TYPE_LOGIN);
	}
}

sub canStart {
	canSetStartupType();
}

sub start {
	my ($class, $params) = @_;

	if (!$params && $class->getStartupType() == SC_STARTUP_TYPE_SERVICE) {

		`$svcHelper --start`;
	}

	else {

		my $appExe = Win32::GetShortPathName( catdir( scalar $os->dirsFor('base'), 'server', 'SqueezeSvr.exe' ) );

		if ($params) {
			$params = "$appExe $params";
		}
		else {
			$params = '';
		}

		# start as background job
		my $processObj;
		Win32::Process::Create(
			$processObj,
			$appExe,
			$params,
			0,
			DETACHED_PROCESS | CREATE_NO_WINDOW | NORMAL_PRIORITY_CLASS,
			'.'
		) if $appExe;

	}

	$class->{checkHTTP} = 1;
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

			# it could happen SC has been started as an app, even though
			# it's configured to be running as a service
			if (getProcessID() != -1) {

				$class->{status} = SC_STATE_RUNNING;
			}
		}

		elsif ($status{'CurrentState'} == 0x03) {

			$class->{status} = SC_STATE_STOPPING;
		}

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
	my $pid = ($p->GetProcessPid(qr/^squeez(esvr|~\d).exe$/i))[1];

	return $pid || -1;
}

1;
