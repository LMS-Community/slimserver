package Slim::GUI::ControlPanel::Music;

# SqueezeCenter Copyright 2001-2009 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use base 'Wx::Panel';

use Wx qw(:everything);
use Wx::Event qw(EVT_BUTTON EVT_CHOICE);

use Slim::Utils::Light;
use Slim::Utils::ServiceManager;

my ($progressPoll, $btnRescan);

sub new {
	my ($self, $nb, $parent) = @_;

	$self = $self->SUPER::new($nb);

	my $svcMgr = Slim::Utils::ServiceManager->new();
	my $os     = Slim::Utils::OSDetect->getOS();

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

	
	my $settingsBox = Wx::StaticBox->new($self, -1, string('MUSICSOURCE'));
	my $settingsSizer = Wx::StaticBoxSizer->new( $settingsBox, wxVERTICAL );
	
	# folder selectors
	$settingsSizer->Add(Wx::StaticText->new($self, -1, string('SETUP_AUDIODIR')), 0, wxLEFT, 10);
	$settingsSizer->Add(Slim::GUI::ControlPanel::DirPicker->new($self, $parent, 'audiodir'), 0, wxEXPAND | wxLEFT | wxRIGHT, 5);
	$settingsSizer->Add(Wx::StaticText->new($self, -1, string('SETUP_PLAYLISTDIR')), 0, wxLEFT | wxTOP, 10);
	$settingsSizer->Add(Slim::GUI::ControlPanel::DirPicker->new($self, $parent, 'playlistdir'), 0, wxEXPAND | wxLEFT | wxBOTTOM | wxRIGHT, 5);

	# get the "Use iTunes" string through CLI
	# if it's empty, then the plugin is disabled
	my $useItunesStr = Slim::GUI::ControlPanel->serverRequest('getstring', 'USE_ITUNES');

	if ($useItunesStr->{USE_ITUNES}) {

		my $useItunes = Wx::CheckBox->new($self, -1, $useItunesStr->{USE_ITUNES});
		$settingsSizer->Add($useItunes, 0, wxEXPAND | wxALL, 10);
		$parent->addStatusListener($useItunes);
		$useItunes->SetValue(Slim::GUI::ControlPanel->getPref('itunes', 'itunes.prefs'));

		$parent->addApplyHandler($useItunes, sub {
			if (shift == SC_STATE_RUNNING) {
				Slim::GUI::ControlPanel->setPref('plugin.itunes:itunes', $useItunes->IsChecked() ? 1 : 0);
			}
		});
	}

	$mainSizer->Add($settingsSizer, 0, wxALL | wxGROW, 10);
	
	my $rescanBox = Wx::StaticBox->new($self, -1, string('INFORMATION_MENU_SCAN'));
	my $rescanSizer = Wx::StaticBoxSizer->new($rescanBox, wxVERTICAL);

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
		
		$progressPoll->Start(1000, wxTIMER_CONTINUOUS) if $progressPoll;
	});
	
	$rescanSizer->Add($rescanBtnSizer, 0, wxALL | wxGROW, 10);

	my $progressPanel = Wx::Panel->new($self);
	$progressPoll = Slim::GUI::ControlPanel::ScanPoll->new($progressPanel);
	$parent->addStatusListener($progressPanel);
	
	$rescanSizer->Add($progressPanel, 1, wxALL | wxGROW, 10);
	
	$mainSizer->Add($rescanSizer, 0, wxALL | wxGROW, 10);

	$self->SetSizer($mainSizer);
	
	return $self;
}

1;


package Slim::GUI::ControlPanel::DirPicker;

use base 'Wx::DirPickerCtrl';

use Wx qw(:everything);

use Slim::Utils::Light;
use Slim::Utils::OSDetect;
use Slim::Utils::ServiceManager;

sub new {
	my ($self, $page, $parent, $pref) = @_;

	$self = $self->SUPER::new(
		$page,
		-1,
		Slim::GUI::ControlPanel->getPref($pref) || '',
		string('SETUP_PLAYLISTDIR'),
		wxDefaultPosition, wxDefaultSize, wxPB_USE_TEXTCTRL | wxDIRP_DIR_MUST_EXIST
	);

	$parent->addApplyHandler($self, sub {
		my $running = (shift == SC_STATE_RUNNING);

		my $path = $self->GetPath;
		if ($running && $path ne Slim::GUI::ControlPanel->getPref($pref)) {
			$path =~ s/\\/\\\\/g if Slim::Utils::OSDetect->isWindows();
			Slim::GUI::ControlPanel->setPref($pref, $path);
		}
	});

	$parent->addStatusListener($self);

	return $self;
}

1;


package Slim::GUI::ControlPanel::ScanPoll;

use base 'Wx::Timer';

use Wx qw(:everything);

use Slim::Utils::Light;
use Slim::Utils::ServiceManager;

my $svcMgr = Slim::Utils::ServiceManager->new();
my $isScanning;

my ($parent, $progressBar, $progressLabel, $progressInfo);

sub new {
	my $self = shift;
	$parent  = shift;
	
	$self = $self->SUPER::new();
	$self->Start(250);
	
	my $sizer = Wx::BoxSizer->new(wxVERTICAL);
	
	$progressLabel = Wx::StaticText->new($parent, -1, '');
	$sizer->Add($progressLabel, 0, wxEXPAND | wxTOP | wxBOTTOM, 5);

	$progressBar = Wx::Gauge->new($parent, -1, 100, [-1, -1], [-1, Slim::Utils::OSDetect->isWindows() ? 20 : -1]);
	$sizer->Add($progressBar, 0, wxEXPAND);

# re-enable ellipsizing once we're running Wx 2.9.x
#	$progressInfo = Wx::StaticText->new($parent, -1, '', [-1, -1], [-1, -1], wxST_ELLIPSIZE_MIDDLE);
	$progressInfo = Wx::StaticText->new($parent, -1, '');
	$sizer->Add($progressInfo, 0, wxEXPAND | wxTOP | wxBOTTOM, 5);

	$parent->SetSizer($sizer);
		
	return $self;
}

sub Notify {
	my $self = shift;
	
	$progressInfo->SetLabel('');
	
	if ($svcMgr->checkServiceState() == SC_STATE_RUNNING) {
		
		my $progress = Slim::GUI::ControlPanel->serverRequest('rescanprogress');

		if ($progress && $progress->{steps} && $progress->{rescan}) {
			$isScanning = 1;
			
			my @steps = split(/,/, $progress->{steps});

			if (@steps && $progress->{$steps[-1]}) {
				
				my $step = $steps[-1];
				$progressBar->SetValue($progress->{$step});
				$progressLabel->SetLabel( @steps . '. ' . string(uc($step) . '_PROGRESS') );
				
			}
			
			if (defined $progress->{info}) {
				
				$progressInfo->SetLabel($progress->{info});
				
			}

			$btnRescan->SetLabel(string('ABORT_SCAN'));
			$self->Start(2000, wxTIMER_CONTINUOUS);
			$self->Layout();
			
			return;
		}
		
		elsif ($progress && $progress->{lastscanfailed}) {
			$progressLabel->SetLabel($progress->{lastscanfailed});
		}
	}
	
	if ($isScanning) {
		$progressBar->SetValue(100);
		$progressLabel->SetLabel(string('PROGRESS_IMPORTER_COMPLETE_DESC'));
		$self->Start(10000, wxTIMER_CONTINUOUS);
	}

	$btnRescan->SetLabel(string('SETUP_RESCAN_BUTTON'));
	$self->Layout();
	
	# don't poll that often when no scan is running
	$isScanning = 0;
}

sub Layout {
	my $self = shift;
	
	my ($width) = $parent->GetSizeWH();
	$progressLabel->Wrap($width);
	$parent->Layout();
}

1;

