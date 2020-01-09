package Slim::GUI::ControlPanel::Music;

# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use base 'Wx::Panel';

use Wx qw(:everything);
use Wx::Event qw(EVT_BUTTON EVT_CHOICE);

use Slim::Utils::Light;
use Slim::Utils::ServiceManager;

sub new {
	my ($self, $nb, $parent) = @_;

	$self = $self->SUPER::new($nb);

	my $svcMgr = Slim::Utils::ServiceManager->new();

	my $mainSizer = Wx::BoxSizer->new(wxVERTICAL);

	$mainSizer->Add($self->getLibraryName($parent), 0, wxALL | wxGROW, 10);		
	
	my $settingsSizer = Wx::StaticBoxSizer->new(
		Wx::StaticBox->new($self, -1, string('MEDIASOURCE')),
		wxVERTICAL
	);
	
	# folder selectors
	$settingsSizer->Add(Wx::StaticText->new($self, -1, string('SETUP_MEDIADIRS')), 0, wxLEFT | wxTOP, 10);
	
	my $mediaDirsSizer = Wx::BoxSizer->new(wxVERTICAL);
	my $dirsBtnSizer   = Wx::BoxSizer->new(wxHORIZONTAL);
	 
	my $dirsList = Wx::ListBox->new($self, -1, wxDefaultPosition, wxDefaultSize, [], wxLB_EXTENDED);
	my $mediadirs = Slim::GUI::ControlPanel->getPref('mediadirs');
	if ($mediadirs && ref $mediadirs eq 'ARRAY') {
		$dirsList->InsertItems($mediadirs, 0);
	}
	$mediaDirsSizer->Add($dirsList, 0, wxGROW, 10);
	
	my $btnAdd = Wx::Button->new($self, -1, string('ADD'));
	$parent->addStatusListener($btnAdd);
	$dirsBtnSizer->Add($btnAdd, 0);
	$dirsBtnSizer->AddSpacer(5);
	
	my $btnRemove = Wx::Button->new($self, -1, string('DELETE'));
	$parent->addStatusListener($btnRemove);
	$dirsBtnSizer->Add($btnRemove, 0);

	$mediaDirsSizer->Add($dirsBtnSizer, 0, wxTOP, 5);
	$settingsSizer->AddSpacer(5);
	$settingsSizer->Add($mediaDirsSizer, 0, wxGROW | wxLEFT | wxRIGHT, 10);
	
	EVT_BUTTON($self, $btnAdd, sub {
		my $dirsSelector = Wx::DirDialog->new($self);
		if ($dirsSelector->ShowModal() == wxID_OK) {
			if (my $path = $dirsSelector->GetPath()) {
				$dirsList->Append($path);
			}
		}
	});
	
	EVT_BUTTON($self, $btnRemove, sub {
		my @selected = $dirsList->GetSelections();
		foreach (reverse sort @selected) {
			$dirsList->Delete($_);
		}
	});
	
	$parent->addApplyHandler($self, sub {
		my $running = (shift == SC_STATE_RUNNING);

		my @mediaDirs = $dirsList->GetStrings();
		
		if ($running && scalar @mediaDirs) {
			Slim::GUI::ControlPanel->setPref('mediadirs', \@mediaDirs);
		}
	});


	$settingsSizer->Add(Wx::StaticText->new($self, -1, string('SETUP_PLAYLISTDIR')), 0, wxLEFT | wxTOP, 10);
	$settingsSizer->AddSpacer(5);
	$settingsSizer->Add(
		Slim::GUI::ControlPanel::DirPicker->new($self, $parent, 'playlistdir', 'SETUP_PLAYLISTDIR'),
		0, wxEXPAND | wxLEFT | wxBOTTOM | wxRIGHT, 10
	);
	
	my $iTunes = getPref('iTunes', 'state.prefs');
	my $useItunesStr = ($svcMgr->checkServiceState() == SC_STATE_RUNNING)
		? Slim::GUI::ControlPanel->serverRequest('getstring', 'USE_ITUNES')
		: {};
	
	if ($useItunesStr && $useItunesStr->{USE_ITUNES} && (!$iTunes || $iTunes !~ /disabled/i)) {

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

	$mainSizer->Add($settingsSizer, 0, wxALL | wxEXPAND, 10);
	
	$self->SetSizer($mainSizer);
	
	return $self;
}


sub getLibraryName {
	my ($self, $parent) = @_;
	
	my $musicLibrarySizer = Wx::StaticBoxSizer->new(
		Wx::StaticBox->new($self, -1, string('SETUP_LIBRARY_NAME')),
		wxVERTICAL
	);
	
	$musicLibrarySizer->Add(Wx::StaticText->new($self, -1, string('SETUP_LIBRARY_NAME_DESC')), 0, wxLEFT | wxTOP, 10);
	$musicLibrarySizer->AddSpacer(5);
	my $libraryname = Wx::TextCtrl->new($self, -1, Slim::GUI::ControlPanel->getPref('libraryname') || '', [-1, -1], [300, -1]);
	$musicLibrarySizer->Add($libraryname, 0, wxLEFT | wxBOTTOM | wxRIGHT | wxGROW, 10);
	
	$parent->addStatusListener($libraryname);
	$parent->addApplyHandler($libraryname, sub {
		if (shift == SC_STATE_RUNNING) {
			Slim::GUI::ControlPanel->setPref('libraryname', $libraryname->GetValue());
		}
	});
	
	return $musicLibrarySizer;
}

1;


package Slim::GUI::ControlPanel::DirPicker;

use base 'Wx::DirPickerCtrl';

use Wx qw(:everything);

use Slim::Utils::Light;
use Slim::Utils::OSDetect;
use Slim::Utils::ServiceManager;

sub new {
	my ($self, $page, $parent, $pref, $title) = @_;

	$self = $self->SUPER::new(
		$page,
		-1,
		Slim::GUI::ControlPanel->getPref($pref) || '',
		string($title),
		wxDefaultPosition, wxDefaultSize, wxPB_USE_TEXTCTRL | wxDIRP_DIR_MUST_EXIST
	);

	$parent->addApplyHandler($self, sub {
		my $running = (shift == SC_STATE_RUNNING);

		my $path = $self->GetPath;
		if ($running && $path ne Slim::GUI::ControlPanel->getPref($pref)) {
			Slim::GUI::ControlPanel->setPref($pref, $path);
		}
	});

	$parent->addStatusListener($self);

	return $self;
}

1;
