
package SFrame;

use strict;
use base 'Wx::Frame';

use LWP::Simple;
use LWP::UserAgent;
use JSON::XS qw(to_json from_json);
use File::Spec::Functions;

use Wx qw(:everything);
use Wx::Event qw(EVT_BUTTON EVT_NOTEBOOK_PAGE_CHANGED);
use Wx::Html;
use Slim::Utils::OSDetect;
use Slim::Utils::Light;

my %checkboxes;
my $os = Slim::Utils::OSDetect::getOS();

sub new {
	my $ref = shift;
	my $args = shift;

	my $self = $ref->SUPER::new(
		undef,
		-1,
		string('CLEANUP_TITLE'),
		[-1, -1],
		[570, 550],
		wxMINIMIZE_BOX | wxMAXIMIZE_BOX | wxCAPTION | wxCLOSE_BOX | wxSYSTEM_MENU | wxRESIZE_BORDER,
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
	
	$notebook->AddPage(settingsPage($notebook, $args), string('SETTINGS'), 1);
	$notebook->AddPage(maintenancePage($notebook, $args, $self), string('CLEANUP_MAINTENANCE'));
	$notebook->AddPage(statusPage($notebook, $args), string('INFORMATION'));
	
	EVT_NOTEBOOK_PAGE_CHANGED( $self, $notebook, sub {
		my( $self, $event ) = @_;

		# Wx on Windows will return the old selection - always update
		if ($event->GetSelection == 2) {

			if (my $page = $notebook->GetPage($event->GetSelection)) {

				my $htmlPage = $page->GetChildren();
				if ( $htmlPage && $htmlPage->isa('Wx::HtmlWindow') ) {
					$htmlPage->SetPage(get(getBaseUrl() . '/EN/settings/server/status.html?simple=1') || string('CLEANUP_NO_STATUS'));
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

	my $btnStartStop = Wx::Button->new($panel, -1, $args->{checkCB}() ? string('STOP_SQUEEZECENTER') :  string('START_SQUEEZECENTER'));
	EVT_BUTTON( $panel, $btnStartStop, sub {
		if ($args->{checkCB}()) {
			serverRequest('{"id":1,"method":"slim.request","params":["",["stopserver"]]}');
		}
	});
	$mainSizer->Add($btnStartStop, 0, wxALL, 10);
	
	my $btnAudioDir = Wx::DirPickerCtrl->new($panel, -1, getPref('audiodir') || '', string('SETUP_AUDIODIR'), [-1, -1], [-1, -1], wxPB_USE_TEXTCTRL | wxDIRP_DIR_MUST_EXIST);
	$mainSizer->Add($btnAudioDir, 0, wxALL, 10);

	my $btnPlaylistDir = Wx::DirPickerCtrl->new($panel, -1, getPref('playlistdir') || '', string('SETUP_PLAYLISTDIR'), [-1, -1], [-1, -1], wxPB_USE_TEXTCTRL | wxDIRP_DIR_MUST_EXIST);
	$mainSizer->Add($btnPlaylistDir, 0, wxALL, 10);
	
	my $log = catdir($os->dirsFor('log'), 'server.log');
	my $serverlogLink = Wx::HyperlinkCtrl->new(
		$panel, 
		-1, 
		$log, 
		$os->name eq 'mac' ? getBaseUrl() . '/server.log?lines=500' : 'file://' . $log, 
		[-1, -1], 
		[-1, -1], 
		wxHL_ALIGN_LEFT
	);
	$mainSizer->Add($serverlogLink, 0, wxALL, 10);

	$log = catdir($os->dirsFor('log'), 'scanner.log');
	my $scannerlogLink = Wx::HyperlinkCtrl->new(
		$panel, 
		-1, 
		$log, 
		$os->name eq 'mac' ? getBaseUrl() . '/scanner.log?lines=500' : 'file://' . $log, 
		[-1, -1], 
		[-1, -1], 
		wxHL_ALIGN_LEFT
	);
	$mainSizer->Add($scannerlogLink, 0, wxALL, 10);

	$panel->SetSizer($mainSizer);	
	
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
		
		if ($args->{checkCB}()) {
			my $msg = Wx::MessageDialog->new($self, string('CLEANUP_PLEASE_STOP_SC'), string('CLEANUP_TITLE'), wxOK | wxICON_INFORMATION);
			$msg->ShowModal();
			return;
		}
	
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
			
			my $msg = Wx::MessageDialog->new($self, string('CLEANUP_PLEASE_RESTART_SC'), string('CLEANUP_TITLE'), wxOK | wxICON_INFORMATION);
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

sub serverRequest {
	my $postdata = shift;

	my $req = HTTP::Request->new( 
		'POST',
		'http://127.0.0.1:9000/jsonrpc.js',
	);
	$req->header('Content-Type' => 'text/plain');

	$req->content($postdata);	

	my $response = LWP::UserAgent->new()->request($req);
	
	my $content;
	$content = $response->decoded_content if ($response);

	if ($content) {
		eval {
			$content = from_json($content); 
		}
	}
	
	return $content;
}

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