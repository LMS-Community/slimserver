package Slim::GUI::ControlPanel::Account;

# Logitech Media Server Copyright 2001-2011 Logitech.
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

	my $snSizer = Wx::StaticBoxSizer->new( 
		Wx::StaticBox->new($self, -1, string('CONTROLPANEL_SN_CREDENTIALS')), 
		wxVERTICAL
	);

	$self->snCredentials($parent, $snSizer);

	my $statsSizer = Wx::StaticBoxSizer->new( 
		Wx::StaticBox->new($self, -1, string('SETUP_SN_REPORT_STATS')),
		wxVERTICAL
	);

	$self->snStats($parent, $statsSizer);
		
	$mainSizer->Add($snSizer, 0, wxALL | wxGROW, 10);
	$mainSizer->Add($statsSizer, 0, wxALL | wxGROW, 10);

	$self->SetSizer($mainSizer);	
	
	
	return $self;
}

sub snCredentials {
	my ($self, $parent, $snSizer) = @_;
	
	$snSizer->Add(Wx::StaticText->new($self, -1, string('SETUP_SN_EMAIL') . string('COLON')), 0, wxTOP | wxLEFT, 10);
	$snSizer->AddSpacer(5);
	my $username = Wx::TextCtrl->new($self, -1, Slim::GUI::ControlPanel->getPref('sn_email') || '', [-1, -1], [350, -1]);
	$snSizer->Add($username, 0, wxLEFT, 10);
	$parent->addStatusListener($username);

	$snSizer->Add(Wx::StaticText->new($self, -1, string('SETUP_SN_PASSWORD') . string('COLON')), 0, wxTOP | wxLEFT, 10);
	$snSizer->AddSpacer(5);
	my $password = Wx::TextCtrl->new($self, -1, Slim::GUI::ControlPanel->getPref('sn_password_sha') ? 'SN_PASSWORD_PLACEHOLDER' : '', [-1, -1], [350, -1], wxTE_PASSWORD);
	$snSizer->Add($password, 0, wxLEFT, 10);
	$parent->addStatusListener($password);

	$snSizer->Add(Wx::HyperlinkCtrl->new(
		$self, 
		-1, 
		string('SETUP_SN_NEED_ACCOUNT'), 
		'http://www.mysqueezebox.com/',
		[-1, -1], 
		[-1, -1], 
		wxHL_DEFAULT_STYLE,
	), 0, wxTOP | wxLEFT, 10);

	$snSizer->AddSpacer(5);
	$snSizer->Add(Wx::HyperlinkCtrl->new(
		$self, 
		-1, 
		string('SETUP_SN_FORGOT_PASSWORD'), 
		'http://www.mysqueezebox.com/user/forgotPassword',
		[-1, -1], 
		[-1, -1], 
		wxHL_DEFAULT_STYLE,
	), 0, wxLEFT | wxBOTTOM, 10);

	$parent->addApplyHandler($username, sub {
		
		if ( $username->GetValue() && $username->GetValue() ne Slim::GUI::ControlPanel->getPref('sn_email')
			|| ($password->GetValue() && $password->GetValue() ne 'SN_PASSWORD_PLACEHOLDER') )
		{
			my $validated = Slim::GUI::ControlPanel->serverRequest(
				'setsncredentials',
				$username->GetValue(),
				$password->GetValue(),
			);
	
			# validation failed
			if (!$validated || !$validated->{validated}) {
				my $msgbox = Wx::MessageDialog->new($self, $validated->{warning} || string('SETUP_SN_VALIDATION_FAILED'), string('SQUEEZENETWORK'), wxOK | wxICON_EXCLAMATION);
				$msgbox->ShowModal();
			}
		}
	});
}

sub snStats {
	my ($self, $parent, $statsSizer) = @_;

	my $statsDesc = string('SETUP_SN_REPORT_STATS_DESC');
	$statsDesc =~ s/<.*?>//g;
	
	my ($width) = $parent->GetSizeWH();
	$width -= 80;
	$statsDesc = Wx::StaticText->new($self, -1, $statsDesc);
	$statsDesc->Wrap($width);
	$statsSizer->Add($statsDesc, 0, wxEXPAND | wxLEFT | wxTOP, 10);


	my $lbStatsSN = Wx::Choice->new($self, -1, [-1, -1], [-1, -1], [
		string('SETUP_SN_REPORT_STATS_ENABLE'), 
		string('SETUP_SN_REPORT_STATS_DISABLE')
	]);
	$lbStatsSN->SetSelection(Slim::GUI::ControlPanel->getPref('sn_disable_stats') ? 1 : 0);
	
	$parent->addStatusListener($lbStatsSN);
	$parent->addApplyHandler($lbStatsSN, sub {
		Slim::GUI::ControlPanel->setPref('sn_disable_stats', $lbStatsSN->GetSelection());
	});
	
	$statsSizer->Add($lbStatsSN, 0, wxALL, 10);

}

1;
