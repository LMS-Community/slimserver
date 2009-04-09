package Slim::GUI::ControlPanel::Music;

# SqueezeCenter Copyright 2001-2009 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use base 'Wx::Panel';

use Wx qw(:everything);
use Wx::Event qw(EVT_BUTTON);

use Slim::Utils::Light;
use Slim::Utils::ServiceManager;

my $progressPoll;

sub new {
	my ($self, $nb, $parent) = @_;

	$self = $self->SUPER::new($nb);

	my $mainSizer = Wx::BoxSizer->new(wxVERTICAL);
	
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

		$parent->addApplyHandler($self, sub {

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
	
	my $btnRescan = Wx::Button->new($self, -1, string('SETUP_RESCAN_BUTTON'));
	$rescanBtnSizer->Add($btnRescan, 0, wxLEFT, 5);
	$parent->addStatusListener($btnRescan);
	
	EVT_BUTTON($self, $btnRescan, sub {
		if ($rescanMode->GetSelection == 0) {
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

my ($parent, $progressBar, $progressLabel);

sub new {
	my $self = shift;
	$parent  = shift;
	
	$self = $self->SUPER::new();
	$self->Start(250);
	
	my $sizer = Wx::BoxSizer->new(wxVERTICAL);
	
	$progressLabel = Wx::StaticText->new($parent, -1, '');
	$sizer->Add($progressLabel, 0, wxEXPAND | wxTOP | wxBOTTOM, 5);

	$progressBar = Wx::Gauge->new($parent, -1, 100, [-1, -1], [-1, Slim::Utils::OSDetect->isWindows() ? 20 : -1]);
	$sizer->Add($progressBar, 0, wxEXPAND | wxBOTTOM, 5);
	
	$parent->SetSizer($sizer);
		
	return $self;
}

sub Notify {
	my $self = shift;
	
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

