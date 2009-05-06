package Slim::GUI::ControlPanel::SqueezeNetwork;

# SqueezeCenter Copyright 2001-2009 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use base 'Wx::Panel';

use Wx qw(:everything);
use Wx::Event qw(EVT_BUTTON);

use Slim::Utils::Light;
use Slim::Utils::ServiceManager;

sub new {
	my ($self, $nb, $parent, $args) = @_;

	$self = $self->SUPER::new($nb);
	$self->{args} = $args;

	my $mainSizer = Wx::BoxSizer->new(wxVERTICAL);
	
	my $credentialsTitle = string('SETUP_SN_PASSWORD_DESC');
	$credentialsTitle =~ s/\.$//;
	
	my $credentialsBox = Wx::StaticBox->new($self, -1, $credentialsTitle);
	my $outerCredentialsSizer = Wx::StaticBoxSizer->new( $credentialsBox, wxVERTICAL );

	my $credentialsSizer = Wx::FlexGridSizer->new(2, 3, 5, 10);
	$credentialsSizer->AddGrowableCol(1, 1);
	$credentialsSizer->SetFlexibleDirection(wxHORIZONTAL);

	$credentialsSizer->Add(Wx::StaticText->new($self, -1, string('SETUP_SN_EMAIL') . string('COLON')), 0, wxTOP, 3);
	my $username = Wx::TextCtrl->new($self, -1, Slim::GUI::ControlPanel->getPref('sn_email') || '', [-1, -1], [150, -1]);
	$credentialsSizer->Add($username);
	$parent->addStatusListener($username);

	$credentialsSizer->Add(Wx::HyperlinkCtrl->new(
		$self, 
		-1, 
		string('SETUP_SN_NEED_ACCOUNT'), 
		'http://www.squeezenetwork.com/',
		[-1, -1], 
		[-1, -1], 
		wxHL_DEFAULT_STYLE,
	), 0, wxTOP, 3);

	$credentialsSizer->Add(Wx::StaticText->new($self, -1, string('SETUP_SN_PASSWORD') . string('COLON')), 0, wxTOP, 3);
	my $password = Wx::TextCtrl->new($self, -1, '', [-1, -1], [150, -1], wxTE_PASSWORD);
	$credentialsSizer->Add($password);
	$parent->addStatusListener($password);

	$credentialsSizer->Add(Wx::HyperlinkCtrl->new(
		$self, 
		-1, 
		string('SETUP_SN_FORGOT_PASSWORD'), 
		'http://www.squeezenetwork.com/user/forgotPassword',
		[-1, -1], 
		[-1, -1], 
		wxHL_DEFAULT_STYLE,
	), 0, wxTOP, 3);

	$parent->addApplyHandler($username, sub {
		
		return unless $username->GetValue() && $password->GetValue();
		
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

	$outerCredentialsSizer->Add($credentialsSizer, 0, wxALL, 10);
	
	$mainSizer->Add($outerCredentialsSizer, 0, wxALL | wxGROW, 10);

	
	my $optionsBox = Wx::StaticBox->new($self, -1, string('SETUP_SN_SYNC'));
	my $optionsSizer = Wx::StaticBoxSizer->new($optionsBox, wxVERTICAL);	
	
	my $syncDesc = string('SETUP_SN_SYNC_DESC');
	$syncDesc = Wx::StaticText->new($self, -1, $syncDesc);
	my ($width) = $parent->GetSizeWH();
	$width -= 80;
	$syncDesc->Wrap($width);
	$optionsSizer->Add($syncDesc, 0, wxEXPAND | wxLEFT | wxTOP, 10);
	
	my $lbSyncSN = Wx::Choice->new($self, -1, [-1, -1], [-1, -1], [ string('SETUP_SN_SYNC_ENABLE'), string('SETUP_SN_SYNC_DISABLE') ]);
	$lbSyncSN->SetSelection(Slim::GUI::ControlPanel->getPref('sn_sync') ? 0 : 1);
	
	$parent->addStatusListener($lbSyncSN);
	$parent->addApplyHandler($lbSyncSN, sub {
		Slim::GUI::ControlPanel->setPref('sn_sync', $lbSyncSN->GetSelection() == 0 ? 1 : 0);
	});
	
	$optionsSizer->Add($lbSyncSN, 0, wxALL, 10);

	
	my $statsDesc = string('SETUP_SN_REPORT_STATS_DESC');
	$statsDesc =~ s/<.*?>//g;
	
	$statsDesc = Wx::StaticText->new($self, -1, $statsDesc);
	$statsDesc->Wrap($width);
	$optionsSizer->Add($statsDesc, 0, wxEXPAND | wxLEFT | wxTOP, 10);


	my $lbStatsSN = Wx::Choice->new($self, -1, [-1, -1], [-1, -1], [ string('SETUP_SN_REPORT_STATS_ENABLE'), string('SETUP_SN_REPORT_STATS_DISABLE') ]);
	$lbStatsSN->SetSelection(Slim::GUI::ControlPanel->getPref('sn_disable_stats') ? 1 : 0);
	
	$parent->addStatusListener($lbStatsSN);
	$parent->addApplyHandler($lbStatsSN, sub {
		Slim::GUI::ControlPanel->setPref('sn_disable_stats', $lbStatsSN->GetSelection());
	});
	
	$optionsSizer->Add($lbStatsSN, 0, wxALL, 10);
	
	
	$mainSizer->Add($optionsSizer, 0, wxALL | wxGROW, 10);
	
	$self->SetSizer($mainSizer);

	return $self;
}



1;