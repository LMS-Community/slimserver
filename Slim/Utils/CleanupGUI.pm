
package SFrame;

use strict;
use base 'Wx::Frame';
use Wx qw(:everything);
use Wx::Event qw(EVT_BUTTON);
use Slim::Utils::OSDetect;

my %checkboxes;

sub new {
	my $ref = shift;
	my $args = shift;

	my $self = $ref->SUPER::new(
		undef,
		-1,
		$args->{title},
		[-1, -1],
		[570, 550],
		wxMINIMIZE_BOX | wxCAPTION | wxCLOSE_BOX | wxSYSTEM_MENU | wxRESIZE_BORDER,
		$args->{title},
	);

	# shortcut if SC is running - only display warning
	if ($args->{running}) {
		return $self;
	}

	my $panel = Wx::Panel->new( 
		$self, 
		-1, 
	);

	my $notebook = Wx::Notebook->new(
		$panel,
		-1,
		[-1, -1],
		[-1, -1],
	);
	
#	$notebook->AddPage(_settingsPage($notebook, $args), "Settings", 1);
	$notebook->AddPage(_maintenancePage($notebook, $args, $self), "Maintenance", 1);
#	$notebook->AddPage(_statusPage($notebook, $args), "Information", 1);
	
	my $mainSizer = Wx::BoxSizer->new(wxVERTICAL);
	
	$mainSizer->Add($notebook, 1, wxRIGHT | wxBOTTOM | wxLEFT | wxGROW, 10);
	
	my $btnsizer = Wx::StdDialogButtonSizer->new();

	my $btnOk = Wx::Button->new( $panel, wxID_OK, $args->{ok} );
	EVT_BUTTON( $self, $btnOk, sub {
		# Save settings & whatever
		$_[0]->Destroy;
	} );
	$btnsizer->SetAffirmativeButton($btnOk);
	
	my $btnCancel = Wx::Button->new( $panel, wxID_CANCEL, $args->{cancel} );
	EVT_BUTTON( $self, $btnCancel, sub {
		$_[0]->Destroy;
	} );
	$btnsizer->SetCancelButton($btnCancel);

	$btnsizer->Realize();

	$mainSizer->Add($btnsizer, 0, wxALL | wxALIGN_RIGHT, 5);

	$panel->SetSizer($mainSizer);	

	return $self;
}

sub _settingsPage {
	my ($parent, $args) = @_;
	
	my $panel = Wx::Panel->new($parent, -1);
	
	return $panel;
}

sub _maintenancePage {
	my ($parent, $args, $self) = @_;
	
	my $panel = Wx::Panel->new($parent, -1);
	my $mainSizer = Wx::BoxSizer->new(wxVERTICAL);
	
	my $label = Wx::StaticText->new($panel, -1, $args->{desc});
	$mainSizer->Add($label, 0, wxALL, 5);

	my $cbSizer = Wx::BoxSizer->new(wxVERTICAL);
	my $options = $args->{options};

	foreach (@$options) {
		$checkboxes{$_->{name}} = Wx::CheckBox->new( $panel, -1, $_->{title}, $_->{position}, [-1, -1]);
		$cbSizer->Add( $checkboxes{$_->{name}}, 0, wxTOP, $_->{margin} || 5 );
	}

	$mainSizer->Add($cbSizer, 1, wxALL, 5);

	my $btnsizer = Wx::StdDialogButtonSizer->new();

	my $btnCleanup = Wx::Button->new( $panel, -1, $args->{cleanup} );
	EVT_BUTTON( $self, $btnCleanup, sub {
		OnCleanupClick(@_, $args);
	} );
	$btnsizer->SetAffirmativeButton($btnCleanup);
	
	$btnsizer->Realize();

	$mainSizer->Add($btnsizer, 0, wxALIGN_BOTTOM | wxALL | wxALIGN_RIGHT, 5);
	
	$panel->SetSizer($mainSizer);

	return $panel;
}

sub _statusPage {
	my ($parent, $args) = @_;
	
	my $panel = Wx::Panel->new($parent, -1);

	my $mainSizer = Wx::BoxSizer->new(wxVERTICAL);
	
	my $label = Wx::StaticText->new($panel, -1, "Number of SBs, player information\nversion, computer name, IP address, http port\nLibrary info");
	$mainSizer->Add($label, 0, wxALL, 5);
	
	return $panel;
}

sub OnCleanupClick {
	my( $self, $event, $args ) = @_;

	my $params = {};
	my $selected = 0;
	
	foreach (@{ $args->{options} }) {
		$params->{$_->{name}} = $checkboxes{$_->{name}}->GetValue();
		$selected ||= $checkboxes{$_->{name}}->GetValue();
	}

	if ($selected) {
		Wx::BusyCursor->new();
		
		my $folders = $args->{folderCB}($params);
		$args->{cleanCB}($folders);
		
		my $msg = Wx::MessageDialog->new($self, $args->{msg}, $args->{msgCap}, wxOK | wxICON_INFORMATION);
		$msg->ShowModal();
	}
}


package Slim::Utils::CleanupGUI;

use base 'Wx::App';
use Wx qw(:everything);

my $args;

sub new {
	my $self = shift;
	$args = shift;

	$self->SUPER::new();
}

sub OnInit {
	my $frame = SFrame->new($args);
	
	if ($args->{running}) {
		my $msg = Wx::MessageDialog->new($frame, $args->{running}, $args->{title}, wxOK | wxICON_INFORMATION);
		$msg->ShowModal();
		$frame->Destroy();
	}
	else {		
		$frame->Show( 1 );
	}	
}

1;