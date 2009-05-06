package Slim::GUI::ControlPanel::Settings;

# SqueezeCenter Copyright 2001-2009 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use base 'Wx::Panel';

use Encode;
use Wx qw(:everything);
use Wx::Event qw(EVT_BUTTON EVT_CHOICE);
use File::Spec::Functions qw(catfile);
use LWP::Simple;

use Slim::GUI::ControlPanel;
use Slim::Utils::Light;
use Slim::Utils::ServiceManager;
use Slim::Utils::OSDetect;

my $os = Slim::Utils::OSDetect::getOS();
my $updateUrl;
my $versionFile = catfile( scalar($os->dirsFor('updates')), 'squeezecenter.version' );

if ($os->name eq 'win') {
	require Win32::Process;
}

sub new {
	my ($self, $nb, $parent) = @_;

	$self = $self->SUPER::new($nb);

	my $svcMgr = Slim::Utils::ServiceManager->new();

	my $mainSizer = Wx::BoxSizer->new(wxVERTICAL);

	# startup mode
	my ($noAdminWarning, @startupOptions) = $svcMgr->getStartupOptions();

	if ($noAdminWarning) {
		my $string = string($noAdminWarning);
		$string    =~ s/\\n/\n/g;
		
		$mainSizer->Add(Wx::StaticText->new($self, -1, $string), 0, wxALL, 10);
	}

	my $startupBox = Wx::StaticBox->new($self, -1, string('CONTROLPANEL_STARTUP_OPTIONS'));
	my $startupSizer = Wx::StaticBoxSizer->new( $startupBox, wxVERTICAL );

	@startupOptions = map { string($_) } @startupOptions;	
	
	my $lbStartupMode = Wx::Choice->new($self, -1, [-1, -1], [-1, -1], \@startupOptions);
	$lbStartupMode->SetSelection($svcMgr->getStartupType() || 0);
	$lbStartupMode->Enable($svcMgr->canSetStartupType());
	
	$parent->addApplyHandler($lbStartupMode, sub {
		$svcMgr->setStartupType($lbStartupMode->GetSelection());
	});
		
	$startupSizer->Add($lbStartupMode, 0, wxLEFT | wxRIGHT | wxTOP, 10);
	
	if ($os->name eq 'win') {
		
		my $credentialsSizer = Wx::FlexGridSizer->new(2, 2, 5, 10);
		$credentialsSizer->AddGrowableCol(1, 1);
		$credentialsSizer->SetFlexibleDirection(wxHORIZONTAL);
	
		$credentialsSizer->Add(Wx::StaticText->new($self, -1, string('SETUP_USERNAME') . string('COLON')));
		my $username = Wx::TextCtrl->new($self, -1, '', [-1, -1], [150, -1]);
		$credentialsSizer->Add($username);
	
		$credentialsSizer->Add(Wx::StaticText->new($self, -1, string('SETUP_PASSWORD') . string('COLON')));
		my $password = Wx::TextCtrl->new($self, -1, '', [-1, -1], [150, -1], wxTE_PASSWORD);
		$credentialsSizer->Add($password);
	
		$startupSizer->Add($credentialsSizer, 0, wxALL, 10);
		
		my $handler = sub {
			$username->Enable($lbStartupMode->GetSelection() == 2);
			$password->Enable($lbStartupMode->GetSelection() == 2);
		};
		
		&$handler();
		EVT_CHOICE($self, $lbStartupMode, $handler);

		# overwrite action handler for startup mode
		$parent->addApplyHandler($lbStartupMode, sub {
			$svcMgr->setStartupType(
				$lbStartupMode->GetSelection(),
				$username->GetValue(),
				$password->GetValue(),
			);
		});
			
	}


	my $startBtnSizer = Wx::BoxSizer->new(wxHORIZONTAL);

	# Start/Stop button
	my $btnStartStop = Wx::Button->new($self, -1, string('STOP_SQUEEZECENTER'));
	EVT_BUTTON( $self, $btnStartStop, sub {
		if ($svcMgr->checkServiceState() == SC_STATE_RUNNING) {
			Slim::GUI::ControlPanel->serverRequest('stopserver');
		}
		
		# starting SC is heavily platform dependant
		else {
			$svcMgr->start();
			$parent->checkServiceStatus();
		}
	});

	$parent->addStatusListener($btnStartStop, sub {
		$btnStartStop->SetLabel($_[0] == SC_STATE_RUNNING ? string('STOP_SQUEEZECENTER') :  string('START_SQUEEZECENTER'));
		$btnStartStop->Enable( ($_[0] == SC_STATE_RUNNING || $_[0] == SC_STATE_STOPPED || $_[0] == SC_STATE_UNKNOWN) && ($_[0] == SC_STATE_STOPPED ? $svcMgr->canStart : 1) );
	});
	$startBtnSizer->Add($btnStartStop, 0);

	my $btnStartSafeMode = Wx::Button->new($self, -1, string('RUN_FAILSAFE'));
	EVT_BUTTON( $self, $btnStartSafeMode, sub {
		$svcMgr->start('--failsafe');
		$parent->checkServiceStatus();
	});

	$parent->addStatusListener($btnStartSafeMode, sub {
		$btnStartSafeMode->Enable(  $_[0] == SC_STATE_STOPPED );
	});
	$startBtnSizer->Add($btnStartSafeMode, 0, wxLEFT, 10);

	$startupSizer->Add($startBtnSizer, 0, wxALL | wxGROW, 10);
	$mainSizer->Add($startupSizer, 0, wxALL | wxGROW, 10);
	
	my $logBox = Wx::StaticBox->new($self, -1, string('DEBUGGING_SETTINGS'));
	my $logSizer = Wx::StaticBoxSizer->new($logBox, wxVERTICAL);	
	
	$logSizer->Add(Slim::GUI::Settings::LogLink->new($self, $parent, 'server.log'), 0, wxLEFT | wxRIGHT | wxTOP, 10);
	$logSizer->Add(Slim::GUI::Settings::LogLink->new($self, $parent, 'scanner.log'), 0, wxALL, 10);
	
	$mainSizer->Add($logSizer, 0, wxALL | wxGROW, 10);
	
	
	if ($os->name eq 'win') {

		# check for SC updates
		my $updateBox = Wx::StaticBox->new($self, -1, string('SETUP_CHECKVERSION')); 
		my $updateSizer = Wx::StaticBoxSizer->new($updateBox, wxVERTICAL);
	
		my $ready = $self->_checkForUpdate();

		my $updateLabel = Wx::StaticText->new($self, -1, string($ready ? 'CONTROLPANEL_UPDATE_AVAILABLE' : 'CONTROLPANEL_NO_UPDATE_AVAILABLE'));	
		$updateSizer->Add($updateLabel, 0, wxLEFT | wxRIGHT | wxTOP, 10);
	
		# update button
		my $btnUpdate = Wx::Button->new($self, -1, string($ready ? 'CONTROLPANEL_INSTALL_UPDATE' : 'CONTROLPANEL_CHECK_UPDATE'));

		EVT_BUTTON( $self, $btnUpdate, sub {
			
			if (my $installer = _checkForUpdate()) {

				my $processObj;
				Win32::Process::Create(
					$processObj,
					$installer,
					'',
					0,
					Win32::Process::DETACHED_PROCESS() | Win32::Process::CREATE_NO_WINDOW() | Win32::Process::NORMAL_PRIORITY_CLASS(),
					'.'
				) && exit;				
				
			}

			elsif ($updateUrl) {
				Wx::LaunchDefaultBrowser($updateUrl);
				exit;
			}

			else {

				my $check = get( sprintf(
					"http://update.squeezenetwork.com/update/?version=%s&lang=%s&os=%s",
					$::VERSION,
					$os->getSystemLanguage(),
					$os->installerOS(),
				));
				chomp($check) if $check;

				if ($check) {
					my @parts = split /\. /, $check;
					
					if (@parts > 1 && $parts[1] =~ /href="(.*?)"/) {
						$updateUrl = $1;
						
						$updateLabel->SetLabel( decode("utf8", $parts[0]) );
						$btnUpdate->SetLabel(string('CONTROLPANEL_DOWNLOAD_UPDATE'));
					}
				}
				
				else {
					$updateLabel->SetLabel(string('CONTROLPANEL_NO_UPDATE_AVAILABLE'));
					$btnUpdate->SetLabel(string('CONTROLPANEL_CHECK_UPDATE'));
				}
			}
		});
			
		$updateSizer->Add($btnUpdate, 0, wxALL, 10);
		
		$mainSizer->Add($updateSizer, 0, wxALL | wxGROW, 10);	
	}
	
	$mainSizer->AddStretchSpacer();
	
	my $webButtonsSizer = Wx::StdDialogButtonSizer->new();
	
	$webButtonsSizer->Add(Slim::GUI::Settings::WebButton->new($self, $parent, '/settings/index.html', 'ADVANCED_SETTINGS'), 0, wxRIGHT, 10);
	$webButtonsSizer->Add(Slim::GUI::Settings::WebButton->new($self, $parent, '/', 'WEB_CONTROL'));
	
	$mainSizer->Add($webButtonsSizer, 0, wxALIGN_BOTTOM | wxALIGN_RIGHT | wxALL, 10);
	
	$self->SetSizer($mainSizer);	
	
	return $self;
}

sub _checkForUpdate {
	
	open(UPDATEFLAG, $versionFile) || return '';
	
	my $installer = '';
	
	while ( <UPDATEFLAG> ) {

		chomp;
		
		if (/SqueezeCenter.*/) {
			$installer = $_;
			last;
		}
	}
		
	close UPDATEFLAG;
	
	return $installer && -e $installer ? $installer : 0;
}

1;


package Slim::GUI::Settings::LogLink;

use base 'Wx::HyperlinkCtrl';

use Wx qw(:everything);
use File::Spec::Functions qw(catfile);

use Slim::GUI::ControlPanel;

sub new {
	my ($self, $page, $parent, $file) = @_;

	my $log = catfile($os->dirsFor('log'), $file);
		
	$self = $self->SUPER::new(
		$page,
		-1, 
		$log, 
		$os->name eq 'mac' ? Slim::GUI::ControlPanel->getBaseUrl() . "/$file?lines=500" : 'file://' . $log, 
		[-1, -1], 
		[-1, -1], 
		wxHL_DEFAULT_STYLE,
	);
	
	$parent->addStatusListener($self) if $os->name eq 'mac';

	return $self;
}

1;


package Slim::GUI::Settings::WebButton;

use base 'Wx::Button';

use Wx qw(:everything);
use Wx::Event qw(EVT_BUTTON);

use Slim::GUI::ControlPanel;
use Slim::Utils::Light;

sub new {
	my ($self, $page, $parent, $url, $label) = @_;
	
	$self = $self->SUPER::new($page, -1, string($label));
	
	$parent->addStatusListener($self);
	
	$url = Slim::GUI::ControlPanel->getBaseUrl() . $url;

	EVT_BUTTON( $page, $self, sub {
		Wx::LaunchDefaultBrowser($url);
	});

	return $self;
}

1;