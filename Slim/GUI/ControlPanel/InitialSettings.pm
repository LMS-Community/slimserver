package Slim::GUI::ControlPanel::InitialSettings;

# Logitech Media Server Copyright 2001-2011 Logitech.
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
	my ($self, $panel, $parent) = @_;

	Slim::Utils::OSDetect::init();

	$self = $self->SUPER::new($panel);
	

	my $mainSizer = Wx::BoxSizer->new(wxVERTICAL);

	$mainSizer->Add(Slim::GUI::ControlPanel::Music::getLibraryName($self, $parent), 0, wxALL | wxGROW, 10);
	
	my $credentialsBox = Wx::StaticBox->new($self, -1, string('CONTROLPANEL_SN_CREDENTIALS'));
	my $snSizer = Wx::StaticBoxSizer->new( $credentialsBox, wxVERTICAL );

	Slim::GUI::ControlPanel::Account::snCredentials($self, $parent, $snSizer);
	Slim::GUI::ControlPanel::Account::snStats($self, $parent, $snSizer);
	
	$mainSizer->Add($snSizer, 0, wxALL | wxGROW, 10);	

	$self->SetSizer($mainSizer);
	
	return $self;
}


1;