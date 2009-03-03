
package SFrame;

use strict;
use base 'Wx::Frame';

use LWP::Simple;
use LWP::UserAgent;
use JSON::XS qw(to_json from_json);

use Wx qw(:everything);
use Wx::Event qw(EVT_BUTTON EVT_NOTEBOOK_PAGE_CHANGED);
use Wx::Html;
use Slim::Utils::OSDetect;
use Slim::Utils::Light;

my %checkboxes;

sub new {
	my $ref = shift;
	my $args = shift;

	my $self = $ref->SUPER::new(
		undef,
		-1,
		string('CLEANUP_TITLE'),
		[-1, -1],
		[570, 550],
		wxMINIMIZE_BOX | wxCAPTION | wxCLOSE_BOX | wxSYSTEM_MENU | wxRESIZE_BORDER,
		string('CLEANUP_TITLE'),
	);

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
	
	$notebook->AddPage(settingsPage($notebook, $args), "Settings", 1);
	$notebook->AddPage(maintenancePage($notebook, $args, $self), "Maintenance", 1);
	$notebook->AddPage(statusPage($notebook, $args), "Information");
	
	EVT_NOTEBOOK_PAGE_CHANGED( $self, $notebook, sub {
		my( $self, $event ) = @_;

		# Wx on Windows will return the old selection - always update
		if ($event->GetSelection == 2) {

			if (my $page = $notebook->GetPage($event->GetSelection)) {

				my $htmlPage = $page->GetChildren();
				if ( $htmlPage && $htmlPage->isa('Wx::HtmlWindow') ) {
					$htmlPage->SetPage(get(getBaseUrl() . '/EN/settings/server/status.html?simple=1') || "No status information available");
				}
			}
		}
	});
	
	my $mainSizer = Wx::BoxSizer->new(wxVERTICAL);
	
	$mainSizer->Add($notebook, 1, wxALL | wxGROW, 10);
	
	my $btnsizer = Wx::StdDialogButtonSizer->new();

	my $btnOk = Wx::Button->new( $panel, wxID_OK, string('OK') );
	EVT_BUTTON( $self, $btnOk, sub {
		# Save settings & whatever
		$_[0]->Destroy;
	} );
	$btnsizer->SetAffirmativeButton($btnOk);
	
	my $btnCancel = Wx::Button->new( $panel, wxID_CANCEL, string('CANCEL') );
	EVT_BUTTON( $self, $btnCancel, sub {
		$_[0]->Destroy;
	} );
	$btnsizer->SetCancelButton($btnCancel);

	$btnsizer->Realize();

	$mainSizer->Add($btnsizer, 0, wxALL | wxALIGN_RIGHT, 5);

	$panel->SetSizer($mainSizer);	

	return $self;
}

sub settingsPage {
	my ($parent, $args) = @_;
	
	my $panel = Wx::Panel->new($parent, -1);

	my $mainSizer = Wx::BoxSizer->new(wxVERTICAL);
	
	my $label = Wx::StaticText->new($panel, -1, "Start/Stop SC\nStartup behaviour\nmusic/playlist folder location\nuse iTunes\nrescan, automatic, timed?");
	$mainSizer->Add($label, 0, wxALL, 10);
	
	return $panel;
}

sub maintenancePage {
	my ($parent, $args, $self) = @_;
	
	my $panel = Wx::Panel->new($parent, -1);
	my $mainSizer = Wx::BoxSizer->new(wxVERTICAL);
	
	my $label = Wx::StaticText->new($panel, -1, string('CLEANUP_DESC'));
	$mainSizer->Add($label, 0, wxALL, 5);

	my $cbSizer = Wx::BoxSizer->new(wxVERTICAL);
	my $options = $args->{options};

	foreach (@$options) {
		$checkboxes{$_->{name}} = Wx::CheckBox->new( $panel, -1, $_->{title}, $_->{position}, [-1, -1]);
		$cbSizer->Add( $checkboxes{$_->{name}}, 0, wxTOP | wxGROW, $_->{margin} || 5 );
	}

	$mainSizer->Add($cbSizer, 1, wxALL, 5);

	my $btnsizer = Wx::StdDialogButtonSizer->new();

	my $btnCleanup = Wx::Button->new( $panel, -1, string('CLEANUP_DO') );
	EVT_BUTTON( $self, $btnCleanup, sub {
		my( $self, $event ) = @_;
	
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
	} );
	$btnsizer->SetAffirmativeButton($btnCleanup);
	
	$btnsizer->Realize();

	$mainSizer->Add($btnsizer, 0, wxALIGN_BOTTOM | wxALL | wxALIGN_RIGHT, 10);
	
	$panel->SetSizer($mainSizer);

	return $panel;
}

# basically display Settings/Information - either new, blank skin, or CLI query result
sub statusPage {
	my ($parent, $args) = @_;
	
	my $panel = Wx::Panel->new($parent, -1);
	$panel->SetAutoLayout(1);
	
	my $mainSizer = Wx::BoxSizer->new(wxVERTICAL);

	my $info = Wx::HtmlWindow->new(
		$panel, 
		-1,
		[-1, -1],
		[-1, -1],
		wxSUNKEN_BORDER
	);
	
	$mainSizer->Add($info, 1, wxALL | wxGROW, 10);
	$panel->SetSizer($mainSizer);
	
	return $panel;
}

#sub _serverRequest {
#	my $postdata = shift;
#
#	my $req = HTTP::Request->new( 
#		'POST',
#		'http://192.168.0.70:9000/jsonrpc.js',
#	);
#	$req->header('Content-Type' => 'text/plain');
#
#	$req->content($postdata);	
#
#	my $response = LWP::UserAgent->new()->request($req);
#	
#	my $content = $response->decoded_content;
#	
#	return from_json($content) if $content;
#}

sub getBaseUrl {
	return 'http://127.0.0.1:' . getPref('httpport');
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
	$frame->Show( 1 );
}

1;