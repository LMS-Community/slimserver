package Slim::GUI::ControlPanel::Status;

# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use base 'Wx::Panel';

use Encode;
use Wx qw(:everything);
use Wx::Event qw(EVT_CHILD_FOCUS);
use Wx::Html;
use LWP::Simple qw($ua get);

$ua->timeout(10);

use Slim::Utils::Light;
use Slim::Utils::ServiceManager;

sub new {
	my ($self, $nb, $parent) = @_;
	
	$self = $self->SUPER::new($nb);
	
	$self->{loaded} = 0;
	$self->{serviceState} = 0;

	$self->SetAutoLayout(1);
	
	my $mainSizer = Wx::BoxSizer->new(wxVERTICAL);

	$mainSizer->Add(Wx::HtmlWindow->new(
		$self, 
		-1,
		[-1, -1],
		[-1, -1],
		wxSUNKEN_BORDER
	), 1, wxALL | wxGROW, 10);
	
	$self->SetSizer($mainSizer);


	EVT_CHILD_FOCUS($self, sub {
		my ($self, $event) = @_;
		$self->_update($event);
	});
	
	
	$parent->addStatusListener('statusUpdater', sub {
		my $state = shift;
		
		if ($state != $self->{serviceState}) {
			$self->_update();
		}
	});
	

	return $self;
}

sub _update {
	my ($self, $event) = @_;

	my $child = $self->GetChildren();

	if ( $child && $child->isa('Wx::HtmlWindow') && !$self->{loaded} ) {

		my $svcMgr = Slim::Utils::ServiceManager->new();
		
		if ($svcMgr->isRunning()) {

			my $status = get(Slim::GUI::ControlPanel->getBaseUrl(1) . '/EN/settings/server/status.html?simple=1');
			$status = decode("utf8", $status) if $status;
	
			$child->SetPage($status || string('CONTROLPANEL_NO_STATUS'));
			$self->{loaded} = 1;

		}
		else {
	
			$child->SetPage(string('CONTROLPANEL_NO_STATUS'));
			$self->{loaded} = 1;

		}
		
		$self->{serviceState} = $svcMgr->getServiceState();
	}
	else {
		$self->{loaded} = 0;
	}

	$event->Skip() if $event;
}

1;
