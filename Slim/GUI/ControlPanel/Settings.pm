package Slim::GUI::ControlPanel::Settings;

# SqueezeCenter Copyright 2001-2009 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use base 'Wx::Panel';

use Encode;
use Wx qw(:everything);
use Wx::Event qw(EVT_BUTTON);

use Slim::GUI::ControlPanel;
use Slim::Utils::Light;
use Slim::Utils::ServiceManager;


sub new {
	my ($self, $nb, $parent) = @_;

	$self = $self->SUPER::new($nb);

	my $mainSizer = Wx::BoxSizer->new(wxVERTICAL);

	my $musicLibraryBox = Wx::StaticBox->new($self, -1, string('SETUP_LIBRARY_NAME'));
	my $musicLibrarySizer = Wx::StaticBoxSizer->new( $musicLibraryBox, wxVERTICAL );
	
	$musicLibrarySizer->Add(Wx::StaticText->new($self, -1, string('SETUP_LIBRARY_NAME_DESC')), 0, wxLEFT, 10);
	$musicLibrarySizer->AddSpacer(10);
	my $libraryname = Wx::TextCtrl->new($self, -1, Slim::GUI::ControlPanel->getPref('libraryname') || '', [-1, -1], [300, -1]);
	$musicLibrarySizer->Add($libraryname, 0, wxLEFT | wxBOTTOM | wxGROW, 10);
	
	$parent->addStatusListener($libraryname);
	$parent->addApplyHandler($libraryname, sub {
		if (shift == SC_STATE_RUNNING) {
			Slim::GUI::ControlPanel->setPref('libraryname', $libraryname->GetValue());
		}
	});

	$mainSizer->Add($musicLibrarySizer, 0, wxALL | wxGROW, 10);		

	$self->SetSizer($mainSizer);	
	
	
	return $self;
}

1;
