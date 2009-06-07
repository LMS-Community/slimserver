package Slim::GUI::ControlPanel::InitialSettings;

# Squeezebox Server Copyright 2001-2009 Logitech.
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
	
	my $musicLibraryBox = Wx::StaticBox->new($self, -1, string('SETUP_LIBRARY_NAME'));
	my $musicLibrarySizer = Wx::StaticBoxSizer->new($musicLibraryBox, wxVERTICAL);
	
	$musicLibrarySizer->Add(Wx::StaticText->new($self, -1, string('SETUP_LIBRARY_NAME_DESC')), 0, wxLEFT, 10);
	$musicLibrarySizer->AddSpacer(10);
	my $libraryname = Wx::TextCtrl->new($self, -1, Slim::GUI::ControlPanel->getPref('libraryname') || '', [-1, -1], [300, -1]);
	$musicLibrarySizer->Add($libraryname, 0, wxLEFT | wxBOTTOM | wxGROW, 10);

	$mainSizer->Add($musicLibrarySizer, 0, wxALL | wxGROW, 10);		
	
	
	my $credentialsBox = Wx::StaticBox->new($self, -1, string('CONTROLPANEL_SN_CREDENTIALS'));
	my $snSizer = Wx::StaticBoxSizer->new( $credentialsBox, wxVERTICAL );

	$snSizer->Add(Wx::StaticText->new($self, -1, string('SETUP_SN_EMAIL') . string('COLON')), 0, wxTOP, 3);
	my $username = Wx::TextCtrl->new($self, -1, Slim::GUI::ControlPanel->getPref('sn_email') || '', [-1, -1], [350, -1]);
	$snSizer->Add($username);
	$parent->addStatusListener($username);

	$snSizer->Add(Wx::StaticText->new($self, -1, string('SETUP_SN_PASSWORD') . string('COLON')), 0, wxTOP, 3);
	my $password = Wx::TextCtrl->new($self, -1, Slim::GUI::ControlPanel->getPref('sn_password_sha') ? 'SN_PASSWORD_PLACEHOLDER' : '', [-1, -1], [350, -1], wxTE_PASSWORD);
	$snSizer->Add($password);
	$parent->addStatusListener($password);


	$snSizer->Add(Wx::HyperlinkCtrl->new(
		$self, 
		-1, 
		string('SETUP_SN_NEED_ACCOUNT'), 
		'http://www.mysqueezebox.com/',
		[-1, -1], 
		[-1, -1], 
		wxHL_DEFAULT_STYLE,
	), 0, wxTOP, 3);

	$snSizer->Add(Wx::HyperlinkCtrl->new(
		$self, 
		-1, 
		string('SETUP_SN_FORGOT_PASSWORD'), 
		'http://www.mysqueezebox.com/user/forgotPassword',
		[-1, -1], 
		[-1, -1], 
		wxHL_DEFAULT_STYLE,
	), 0, wxTOP, 3);

	$parent->addApplyHandler($username, sub {
		
		return unless $username->GetValue() && $password->GetValue();
		
		return if $password->GetValue() eq 'SN_PASSWORD_PLACEHOLDER';
		
		my $validated = Slim::GUI::ControlPanel->serverRequest(
			'setsncredentials',
			$username->GetValue(),
			$password->GetValue(),
		);

		# validation failed
		if (!$validated || !$validated->{validated}) {
			my $msgbox = Wx::MessageDialog->new($self, $validated->{warning} || 'Failed', string('SQUEEZENETWORK'), wxOK | wxICON_EXCLAMATION);
			$msgbox->ShowModal();
		}
	});

	my $statsDesc = string('SETUP_SN_REPORT_STATS_DESC');
	$statsDesc =~ s/<.*?>//g;
	
	my ($width) = $parent->GetSizeWH();
	$width -= 80;
	$statsDesc = Wx::StaticText->new($self, -1, $statsDesc);
	$statsDesc->Wrap($width);
	$snSizer->Add($statsDesc, 0, wxEXPAND | wxLEFT | wxTOP, 10);

	my $lbStatsSN = Wx::Choice->new($self, -1, [-1, -1], [-1, -1], [ string('SETUP_SN_REPORT_STATS_ENABLE'), string('SETUP_SN_REPORT_STATS_DISABLE') ]);
	$lbStatsSN->SetSelection(Slim::GUI::ControlPanel->getPref('sn_disable_stats') ? 1 : 0);
	
	$parent->addStatusListener($lbStatsSN);
	$parent->addApplyHandler($lbStatsSN, sub {
		Slim::GUI::ControlPanel->setPref('sn_disable_stats', $lbStatsSN->GetSelection());
	});
	
	$snSizer->Add($lbStatsSN, 0, wxALL, 10);
		
	$mainSizer->Add($snSizer, 0, wxALL | wxGROW, 10);
	

	$self->SetSizer($mainSizer);
	
	return $self;
}


1;