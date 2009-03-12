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

sub new {
	my ($self, $nb, $parent) = @_;

	$self = $self->SUPER::new($nb);

	my $mainSizer = Wx::BoxSizer->new(wxVERTICAL);
	
	my $settingsBox = Wx::StaticBox->new($self, -1, string('MUSICSOURCE'));
	my $settingsSizer = Wx::StaticBoxSizer->new( $settingsBox, wxVERTICAL );
	
	# folder selectors
	$settingsSizer->Add(Slim::GUI::ControlPanel::DirPicker->new($self, $parent, 'audiodir'), 0, wxEXPAND | wxALL, 5);
	$settingsSizer->Add(Slim::GUI::ControlPanel::DirPicker->new($self, $parent, 'playlistdir'), 0, wxEXPAND | wxALL, 5);

	# get the "Use iTunes" string through CLI
	# if it's empty, then the plugin is disabled
	my $useItunesStr = Slim::GUI::ControlPanel->serverRequest('getstring', 'USE_ITUNES');

	if ($useItunesStr->{USE_ITUNES}) {

		my $useItunes = Wx::CheckBox->new($self, -1, $useItunesStr->{USE_ITUNES});
		$settingsSizer->Add($useItunes, 0, wxEXPAND | wxALL, 5);
		$parent->addStatusListener($useItunes);

		$parent->addApplyHandler($self, sub {

			if (shift == SC_STATE_RUNNING) {
				Slim::GUI::ControlPanel->setPref('plugin.itunes:itunes', $useItunes->IsChecked() ? 1 : 0);
			}

		});
	}

	$mainSizer->Add($settingsSizer, 0, wxALL | wxGROW, 10);
	
	my $rescanSizer = Wx::BoxSizer->new(wxHORIZONTAL);
	
	my $rescanMode = Wx::Choice->new($self, -1, [-1, -1], [-1, -1], [
		string('SETUP_STANDARDRESCAN'),
		string('SETUP_PLAYLISTRESCAN'),
		string('SETUP_WIPEDB'),
	]);
	$rescanMode->SetSelection(0);
	$rescanSizer->Add($rescanMode);
	$parent->addStatusListener($rescanMode);
	
	my $btnRescan = Wx::Button->new($self, -1, string('SETUP_RESCAN_BUTTON'));
	$rescanSizer->Add($btnRescan, 0, wxLEFT, 5);
	$parent->addStatusListener($btnRescan);
	
	EVT_BUTTON($self, $btnRescan, sub {
		if ($rescanMode->GetSelection == 0) {
			Slim::GUI::ControlPanel->serverRequest('rescan');
		}

		elsif ($rescanMode->GetSelection == 1) {
			Slim::GUI::ControlPanel->serverRequest('rescan', 'playlists');
		}

		elsif ($rescanMode->GetSelection == 2) {
			Slim::GUI::ControlPanel->serverRequest('wipecache');
		}
	});
	
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
		getPref($pref) || '',
		string('SETUP_PLAYLISTDIR'),
		wxDefaultPosition, wxDefaultSize, wxPB_USE_TEXTCTRL | wxDIRP_DIR_MUST_EXIST
	);

	$parent->addApplyHandler($self, sub {
		my $running = (shift == SC_STATE_RUNNING);

		my $path = $self->GetPath;
		if ($running && $path ne getPref($pref)) {
			$path =~ s/\\/\\\\/g if Slim::Utils::OSDetect->isWindows();
			Slim::GUI::ControlPanel->setPref($pref, $path);
		}
	});

	$parent->addStatusListener($self);

	return $self;
}

1;
