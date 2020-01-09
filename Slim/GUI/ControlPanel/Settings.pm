package Slim::GUI::ControlPanel::Settings;

# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use base 'Wx::Panel';

use Encode;
use Wx qw(:everything);
use Wx::Event qw(EVT_BUTTON EVT_CHOICE EVT_TEXT);

use Slim::GUI::ControlPanel;
use Slim::Utils::Light;
use Slim::Utils::ServiceManager;

my ($progressPoll, $btnRescan, $setStartupMode, $setStartupModeHandler);

sub new {
	my ($self, $nb, $parent) = @_;

	$self = $self->SUPER::new($nb);

	my $svcMgr = Slim::Utils::ServiceManager->new();

	my $mainSizer = Wx::BoxSizer->new(wxVERTICAL);

	my ($noAdminWarning, @startupOptions) = $svcMgr->getStartupOptions();

	if ($noAdminWarning) {
		my $string = string($noAdminWarning);
		$string    =~ s/\\n/\n/g;
		
		my $warning = Wx::StaticText->new($self, -1, $string);
		$warning->SetForegroundColour(wxRED);
		my ($width) = $parent->GetSizeWH();
		$warning->Wrap($width - 70) if $width && $width > 200;
		$mainSizer->Add($warning, 0, wxALL, 10);
	}


	my $statusSizer = Wx::StaticBoxSizer->new( 
		Wx::StaticBox->new($self, -1, string('CONTROLPANEL_SERVERSTATUS')),
		wxVERTICAL
	);

	my $statusLabel = Wx::StaticText->new($self, -1, '');
	$statusSizer->Add($statusLabel, 0, wxALL, 10);
	
	$parent->addStatusListener($statusLabel, sub {
		my $state = shift;
		
		if ($state == SC_STATE_STOPPED) {
			$statusLabel->SetLabel(string('CONTROLPANEL_STATUS_STOPPED'));
		}
		elsif ($state == SC_STATE_RUNNING) {
			$statusLabel->SetLabel(string('CONTROLPANEL_STATUS_RUNNING'));
		}
		elsif ($state == SC_STATE_STARTING) {
			$statusLabel->SetLabel(string('CONTROLPANEL_STATUS_STARTING'));
		}
		
	});

	# Start/Stop button
	my $btnStartStop = Wx::Button->new($self, -1, string('STOP_SQUEEZEBOX_SERVER'));

	$parent->addStatusListener($btnStartStop, sub {
		$btnStartStop->SetLabel($_[0] == SC_STATE_RUNNING ? string('STOP_SQUEEZEBOX_SERVER') :  string('START_SQUEEZEBOX_SERVER'));
		$btnStartStop->Enable( ($_[0] == SC_STATE_RUNNING || $_[0] == SC_STATE_STOPPED || $_[0] == SC_STATE_UNKNOWN) && ($_[0] == SC_STATE_STOPPED ? $svcMgr->canStart : 1) );
		$btnStartStop->SetSize( $btnStartStop->GetBestSize() );
	});
	$statusSizer->Add($btnStartStop, 0, wxLEFT, 10);

	my $cbStartSafeMode = Wx::CheckBox->new($self, -1, string('RUN_FAILSAFE'));
	$parent->addStatusListener($cbStartSafeMode, sub {
		$cbStartSafeMode->Enable(  $_[0] == SC_STATE_STOPPED );
	});
	$statusSizer->Add($cbStartSafeMode, 0, wxLEFT | wxTOP | wxBOTTOM, 10);

	# check box if server is running in failsafe mode
	$cbStartSafeMode->SetValue( $svcMgr->checkServiceState() == SC_STATE_RUNNING && Slim::GUI::ControlPanel->getPref('failsafe') );

	@startupOptions = map { string($_) } @startupOptions;
	my $lbStartupMode = Wx::Choice->new($self, -1, [-1, -1], [-1, -1], \@startupOptions);

	EVT_CHOICE($self, $lbStartupMode, sub {
		$setStartupMode = 1;
	});

	EVT_BUTTON( $self, $btnStartStop, sub {
		if ($svcMgr->checkServiceState() == SC_STATE_RUNNING) {
			Slim::GUI::ControlPanel->serverRequest('stopserver');
		}
		
		# starting SC is heavily platform dependant
		else {
			&$setStartupModeHandler() if $setStartupModeHandler;
			$svcMgr->start($cbStartSafeMode->IsChecked() ? '--failsafe --debug server=debug,server.plugins=debug --d_startup' : undef);
			$parent->checkServiceStatus();
		}
	});

	$mainSizer->Add($statusSizer, 0, wxALL | wxGROW, 10);


	my $startupSizer = Wx::StaticBoxSizer->new( 
		Wx::StaticBox->new($self, -1, string('CONTROLPANEL_STARTUP_OPTIONS')),
		wxVERTICAL
	);
	
	$lbStartupMode->SetSelection($svcMgr->getStartupType() || 0);
	$lbStartupMode->Enable($svcMgr->canSetStartupType());
	
	$setStartupModeHandler = sub {
		$svcMgr->setStartupType($lbStartupMode->GetSelection()) if $setStartupMode;
		$setStartupMode = 0;
	};

	# use dummy listener to allow setting startup mode whether server is running or not
	$parent->addStatusListener($lbStartupMode, sub {});
		
	$startupSizer->Add($lbStartupMode, 0, wxLEFT | wxRIGHT | wxTOP, 10);
	
	if (main::ISWINDOWS) {
		require Win32::TieRegistry;
		$Win32::TieRegistry::Registry->Delimiter('/');
		my $serviceUser = $Win32::TieRegistry::Registry->{'LMachine/SYSTEM/CurrentControlSet/Services/squeezesvc/ObjectName'} || '';
		$serviceUser = '' if $serviceUser =~ /^(?:LocalSystem)$/i;
		
		my $credentialsSizer = Wx::FlexGridSizer->new(2, 2, 5, 10);
		$credentialsSizer->AddGrowableCol(1, 1);
		$credentialsSizer->SetFlexibleDirection(wxHORIZONTAL);
	
		$credentialsSizer->Add(Wx::StaticText->new($self, -1, string('SETUP_USERNAME') . string('COLON')));
		my $username = Wx::TextCtrl->new($self, -1, $serviceUser, [-1, -1], [150, -1]);
		$credentialsSizer->Add($username);
		EVT_TEXT($self, $username, sub {
			$setStartupMode = 1;
		});
	
		$credentialsSizer->Add(Wx::StaticText->new($self, -1, string('SETUP_PASSWORD') . string('COLON')));
		my $password = Wx::TextCtrl->new($self, -1, '', [-1, -1], [150, -1], wxTE_PASSWORD);
		$credentialsSizer->Add($password);
		EVT_TEXT($self, $password, sub {
			$setStartupMode = 1;
		});
	
		$startupSizer->Add($credentialsSizer, 0, wxALL, 10);
		
		my $handler = sub {
			$username->Enable($lbStartupMode->GetSelection() == 2);
			$password->Enable($lbStartupMode->GetSelection() == 2);
		};
		
		&$handler();
		EVT_CHOICE($self, $lbStartupMode, sub {
			$setStartupMode = 1;
			&$handler();
		});

		# overwrite action handler for startup mode
		$setStartupModeHandler = sub {
		
			if ($setStartupMode) {

				$svcMgr->setStartupType(
					$lbStartupMode->GetSelection(),
					$username->GetValue(),
					$password->GetValue(),
				);
			}

			$setStartupMode = 0;
		};
		
		# doubleclick action for tray icon
		my $lbDoubleClickHandler = Wx::Choice->new($self, -1, [-1, -1], [-1, -1], [ string('CONTROLPANEL_TRAY_DOUBLECLICK_CONTROLPANEL'), string('CONTROLPANEL_TRAY_DOUBLECLICK_WEB') ]);
		$lbDoubleClickHandler->SetSelection($Win32::TieRegistry::Registry->{'CUser/Software/Logitech/Squeezebox/DefaultToWebUI'} || 0);
		
		$parent->addApplyHandler($lbDoubleClickHandler, sub {
			$Win32::TieRegistry::Registry->{'CUser/Software/Logitech/Squeezebox/DefaultToWebUI'} = $lbDoubleClickHandler->GetSelection() ? '1' : '0'; 
		});
		$startupSizer->Add($lbDoubleClickHandler, 0, wxLEFT | wxRIGHT | wxBOTTOM, 10);
	}
		
	$parent->addApplyHandler($lbStartupMode, $setStartupModeHandler);

	$mainSizer->Add($startupSizer, 0, wxALL | wxGROW, 10);


	my $rescanSizer = Wx::StaticBoxSizer->new(
		Wx::StaticBox->new($self, -1, string('INFORMATION_MENU_SCAN')),
		wxVERTICAL
	);

	my $rescanBtnSizer = Wx::BoxSizer->new(wxHORIZONTAL);
	
	my $rescanMode = Wx::Choice->new($self, -1, [-1, -1], [-1, -1], [
		string('SETUP_STANDARDRESCAN'),
		string('SETUP_WIPEDB'),
		string('SETUP_PLAYLISTRESCAN'),
	]);
	$rescanMode->SetSelection(0);
	$rescanBtnSizer->Add($rescanMode);
	$parent->addStatusListener($rescanMode);
	
	$btnRescan = Wx::Button->new($self, -1, string('SETUP_RESCAN_BUTTON'));
	$rescanBtnSizer->Add($btnRescan, 0, wxLEFT, 5);
	$parent->addStatusListener($btnRescan);
	
	EVT_BUTTON($self, $btnRescan, sub {
		if ($btnRescan->GetLabel() eq string('ABORT_SCAN')) {
			Slim::GUI::ControlPanel->serverRequest('abortscan');
		}
		
		elsif ($rescanMode->GetSelection == 0) {
			Slim::GUI::ControlPanel->serverRequest('rescan');
		}

		elsif ($rescanMode->GetSelection == 1) {
			Slim::GUI::ControlPanel->serverRequest('wipecache');
		}

		elsif ($rescanMode->GetSelection == 2) {
			Slim::GUI::ControlPanel->serverRequest('rescan', 'playlists');
		}
		
		$progressPoll->Start(100, wxTIMER_CONTINUOUS, 10) if $progressPoll && $btnRescan->GetLabel() ne string('ABORT_SCAN');
	});
	
	$rescanSizer->Add($rescanBtnSizer, 0, wxALL | wxGROW, 10);

	my $progressPanel = Wx::Panel->new($self);
	$progressPoll = Slim::GUI::ControlPanel::ScanPoll->new($progressPanel);
	$parent->addStatusListener($progressPanel);
	
	$rescanSizer->Add($progressPanel, 1, wxLEFT | wxRIGHT | wxGROW, 10);
	
	$mainSizer->Add($rescanSizer, 0, wxALL | wxGROW, 10);


	$self->SetSizer($mainSizer);	
	
	return $self;
}

1;


package Slim::GUI::ControlPanel::ScanPoll;

use base 'Wx::Timer';

use Wx qw(:everything);

use Slim::Utils::Light;
use Slim::Utils::ServiceManager;

my $svcMgr = Slim::Utils::ServiceManager->new();
my $isScanning = 0;

my ($parent, $progressBar, $progressTime, $progressLabel, $progressInfo);

sub new {
	my $self = shift;
	$parent  = shift;
	
	$self = $self->SUPER::new();
	$self->Start(250);
	
	my $sizer = Wx::BoxSizer->new(wxVERTICAL);
	
	$progressLabel = Wx::StaticText->new($parent, -1, '');
	$sizer->Add($progressLabel, 0, wxEXPAND | wxTOP | wxBOTTOM, 5);
	
	my $progressSizer = Wx::BoxSizer->new(wxHORIZONTAL);

	$progressBar = Wx::Gauge->new($parent, -1, 100, [-1, -1], [-1, main::ISWINDOWS ? 20 : -1]);
	$progressSizer->Add($progressBar, 1, wxGROW);

	$progressTime = Wx::StaticText->new($parent, -1, '00:00:00');
	$progressSizer->AddSpacer(10);
	$progressSizer->Add($progressTime, 0, wxTOP, 3);
	
	$sizer->Add($progressSizer, 0, wxEXPAND);

# re-enable ellipsizing once we're running Wx 2.9.x
#	$progressInfo = Wx::StaticText->new($parent, -1, '', [-1, -1], [-1, -1], wxST_ELLIPSIZE_MIDDLE);
	$progressInfo = Wx::StaticText->new($parent, -1, '');
	$sizer->Add($progressInfo, 0, wxEXPAND | wxTOP | wxBOTTOM, 5);

	$sizer->AddSpacer(15);

	$parent->SetSizer($sizer);
		
	return $self;
}

sub Start {
	my ($self, $milliseconds, $oneShot, $scanInit) = @_;
	
	$isScanning = $scanInit if $scanInit;
	
	$self->SUPER::Start($milliseconds, $oneShot);
}

sub Notify {
	my $self = shift;
	
	$progressInfo->SetLabel('');
	
	if ($svcMgr->isRunning()) {
		
		my $progress = Slim::GUI::ControlPanel->serverRequest('rescanprogress');

		if ($progress && $progress->{rescan}) {
			$self->showProgress($progress);
			return;
		}
		
		elsif ($progress && $progress->{lastscanfailed}) {
			$progressLabel->SetLabel($progress->{lastscanfailed});
		}

		elsif (!$isScanning) {
			$self->showStats();		
		}
		
		elsif ($isScanning) {
			$progressLabel->SetLabel('');
		}
	}

	# don't poll that often when no scan is running
	$self->Start(10000, wxTIMER_CONTINUOUS);
	
	if ($isScanning) {
		$progressBar->SetValue(100);
		$self->Start(1000, wxTIMER_CONTINUOUS);
		
		$isScanning--;
	}

	$btnRescan->SetLabel(string($isScanning ? 'ABORT_SCAN' : 'SETUP_RESCAN_BUTTON'));
	$btnRescan->SetSize( $btnRescan->GetBestSize() );
}

sub showProgress {
	my $self = shift;
	my $progress = shift;

	$isScanning = 1;
			
	$progressBar->Show();
	$progressLabel->SetLabel('');
						
	my @steps = split(/,/, $progress->{steps} || 'directory');

	if (@steps) {
				
		my $step = $steps[-1];
		$progressBar->SetValue($progress->{$step}) if $progress->{$steps[-1]};
		$progressLabel->SetLabel( @steps . '. ' . Slim::GUI::ControlPanel->string(uc($step) . '_PROGRESS') );
		$progressTime->SetLabel($progress->{totaltime});
				
	}
			
	if (defined $progress->{info}) {
		$progressInfo->SetLabel($progress->{info});
	}

	$btnRescan->SetLabel(string('ABORT_SCAN'));
	$btnRescan->SetSize( $btnRescan->GetBestSize() );
	$self->Start(2100, wxTIMER_CONTINUOUS);
	$self->Layout();
}

sub showStats {
	my $self = shift;
	
	my $libraryStats = Slim::GUI::ControlPanel->serverRequest('systeminfo', 'items', 0, 999);
			
	if ($libraryStats && $libraryStats->{loop_loop}) {
		my $libraryName = string('INFORMATION_MENU_LIBRARY');
		my $x = 0;
				
		foreach my $item (@{$libraryStats->{loop_loop}}) {

			last if ($item->{name} && $item->{name} eq $libraryName);

			$x++;

		}
				
		if ($x < scalar @{$libraryStats->{loop_loop}}) {
			$libraryStats = Slim::GUI::ControlPanel->serverRequest('systeminfo', 'items', 0, 999, "item_id:$x");

			if ($libraryStats && $libraryStats->{loop_loop}) {
				my $newLabel = '';

				foreach my $item (@{$libraryStats->{loop_loop}}) {
							
					if ($item->{name}) {
						$newLabel .= $item->{name} . "\n";
					}
	
				}
						
				if ($newLabel) {
					$progressBar->Hide();
					$progressTime->SetLabel('');
					$progressLabel->SetLabel($newLabel);
				}
			}
		}
	}
}

sub Layout {
	my $self = shift;
	
	my ($width) = $parent->GetSizeWH();
	$progressLabel->Wrap($width);
	$parent->Layout();
}

1;

