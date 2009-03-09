package Slim::Utils::CleanupGUI::MainFrame;

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
use Slim::Utils::ServiceManager;

my %checkboxes;
my $os = Slim::Utils::OSDetect::getOS();
my $pollTimer;
my $btnOk;

my $svcMgr = Slim::Utils::ServiceManager->new();

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

	# set the application icon
	if (Slim::Utils::OSDetect::isWindows()) {
		if (my $icon = Wx::Icon->new('../platforms/win32/res/SqueezeCenter.ico', wxBITMAP_TYPE_ICO)) {
			
			$self->SetIcon($icon);
		}
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

	$pollTimer = Slim::Utils::CleanupGUI::Timer->new();

	$btnOk = Slim::Utils::CleanupGUI::OkButton->new( $panel, wxID_OK, string('OK') );
	$btnOk->SetDefault();
	EVT_BUTTON( $self, $btnOk, sub {
		$btnOk->do($svcMgr->checkServiceState());
		$_[0]->Destroy;
	} );

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
	$btnsizer->AddButton($btnOk);

	# Windows users like to have an Apply button which doesn't close the dialog
	if (Slim::Utils::OSDetect::isWindows()) {
		my $btnApply = Wx::Button->new( $panel, wxID_APPLY, string('APPLY') );
		EVT_BUTTON( $self, $btnApply, sub {
			$btnOk->do($svcMgr->checkServiceState());
		} );
		$btnsizer->AddButton($btnApply);
	}
	
	my $btnCancel = Wx::Button->new( $panel, wxID_CANCEL, string('CANCEL') );
	EVT_BUTTON( $self, $btnCancel, sub {
		$_[0]->Destroy;
	} );
	$btnsizer->AddButton($btnCancel);

	$btnsizer->Realize();

	$mainSizer->Add($btnsizer, 0, wxALL | wxALIGN_RIGHT, 5);

	$panel->SetSizer($mainSizer);	
	
	$pollTimer->Start(5000, wxTIMER_CONTINUOUS);
	$pollTimer->Notify();

	return $self;
}

sub settingsPage {
	my ($parent, $args) = @_;
	
	my $panel = Wx::Panel->new($parent, -1);

	my $mainSizer = Wx::BoxSizer->new(wxVERTICAL);
	
	my $label = Wx::StaticText->new($panel, -1, "Start/Stop SC\nStartup behaviour\nmusic/playlist folder location\nuse iTunes\nrescan, automatic, timed?");
	$mainSizer->Add($label, 0, wxALL, 10);

	# startup mode
	if ($svcMgr->canSetStartupType()) {
		
		my $lbStartupMode = Wx::Choice->new($panel, -1, [-1, -1], [-1, -1], [ string('RUN_NEVER'), string('RUN_AT_LOGIN'), string('RUN_AT_BOOT') ]);
		$lbStartupMode->SetSelection($svcMgr->getStartupType() || 0);
	
		$btnOk->addActionHandler($lbStartupMode, sub {
			my $newStartupType = $lbStartupMode->GetSelection();
	
			if ($newStartupType != $svcMgr->getStartupType()) {
				$svcMgr->setStartupType($newStartupType);
			}
		});
		
		$mainSizer->Add($lbStartupMode, 0, wxALL, 10);
	}	

	# Start/Stop button
	my $btnStartStop = Wx::Button->new($panel, -1, string('STOP_SQUEEZECENTER'));
	EVT_BUTTON( $panel, $btnStartStop, sub {
		my ($self, $event) = @_;
		btnStartStopHandler($self, $event, $svcMgr->checkServiceState());
	});
	
	$pollTimer->addListener($btnStartStop, sub {
		$btnStartStop->SetLabel($_[0] == SC_STATE_RUNNING ? string('STOP_SQUEEZECENTER') :  string('START_SQUEEZECENTER'));
		$btnStartStop->Enable($_[0] == SC_STATE_RUNNING || $_[0] == SC_STATE_STOPPED || $_[0] == SC_STATE_UNKNOWN)
	});
	
	$mainSizer->Add($btnStartStop, 0, wxALL, 10);
	
	# folder selectors
	my $btnAudioDir = Wx::DirPickerCtrl->new($panel, -1, getPref('audiodir') || '', string('SETUP_AUDIODIR'), wxDefaultPosition, wxDefaultSize, wxPB_USE_TEXTCTRL | wxDIRP_DIR_MUST_EXIST);
	$pollTimer->addListener($btnAudioDir);

	$btnOk->addActionHandler($btnAudioDir, sub {
		my $running = (shift == SC_STATE_RUNNING);

		my $path = $btnAudioDir->GetPath;
		if ($running && $path ne getPref('audiodir')) {
			$path =~ s/\\/\\\\/g if Slim::Utils::OSDetect->isWindows();
			setPref("audiodir", $path);
		}
	});

	$mainSizer->Add($btnAudioDir, 0, wxEXPAND | wxALL, 10);

	my $btnPlaylistDir = Wx::DirPickerCtrl->new($panel, -1, getPref('playlistdir') || '', string('SETUP_PLAYLISTDIR'), wxDefaultPosition, wxDefaultSize, wxPB_USE_TEXTCTRL | wxDIRP_DIR_MUST_EXIST);
	$pollTimer->addListener($btnPlaylistDir);

	$btnOk->addActionHandler($btnPlaylistDir, sub {
		my $running = (shift == SC_STATE_RUNNING);

		my $path = $btnPlaylistDir->GetPath;
		if ($running && $path ne getPref('playlistdir')) {
			$path =~ s/\\/\\\\/g if Slim::Utils::OSDetect->isWindows();
			setPref("playlistdir", $path);
		}
	});
	$mainSizer->Add($btnPlaylistDir, 0, wxEXPAND | wxALL, 10);
	
	# links to log files
	# on OSX we can't "start" the log files, but need to use some trickery to get an URL
	my $log = catfile($os->dirsFor('log'), 'server.log');
	my $serverlogLink = Wx::HyperlinkCtrl->new(
		$panel, 
		-1, 
		$log, 
		$os->name eq 'mac' ? getBaseUrl() . '/server.log?lines=500' : 'file://' . $log, 
		[-1, -1], 
		[-1, -1], 
		wxHL_DEFAULT_STYLE,
	);
	$pollTimer->addListener($serverlogLink) if $os->name eq 'mac';
	$mainSizer->Add($serverlogLink, 0, wxALL, 10);

	$log = catfile($os->dirsFor('log'), 'scanner.log');
	my $scannerlogLink = Wx::HyperlinkCtrl->new(
		$panel, 
		-1, 
		$log, 
		$os->name eq 'mac' ? getBaseUrl() . '/scanner.log?lines=500' : 'file://' . $log, 
		[-1, -1], 
		[-1, -1], 
		wxHL_DEFAULT_STYLE,
	);
	$pollTimer->addListener($scannerlogLink) if $os->name eq 'mac';
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

	my $hint = Wx::StaticText->new($panel, -1, string('CLEANUP_PLEASE_STOP_SC'));
	$pollTimer->addListener($hint);
	$mainSizer->Add($hint, 0, wxALL, 5);

	my $btnsizer = Wx::StdDialogButtonSizer->new();

	my $btnCleanup = Wx::Button->new( $panel, -1, string('CLEANUP_DO') );
	EVT_BUTTON( $self, $btnCleanup, sub {
		my( $self, $event ) = @_;
		
		if ($svcMgr->checkServiceState()) {
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
	$pollTimer->addListener($btnCleanup, sub {
		$btnCleanup->Enable($_[0] != SC_STATE_RUNNING && $_[0] != SC_STATE_STARTING);
	});
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

sub btnStartStopHandler {
	my ($self, $event, $status) = @_;
	
	if ($status == SC_STATE_RUNNING) {
		serverRequest('{"id":1,"method":"slim.request","params":["",["stopserver"]]}');
	}
	
	# starting SC is heavily platform dependant
	else {
		$svcMgr->start();
	}
}

sub setPref {
	my ($pref, $value) = @_;
	serverRequest('{"id":1,"method":"slim.request","params":["",["pref", "' . $pref . '", "' . $value . '"]]}');
}

sub serverRequest {
	my $postdata = shift;
	my $httpPort = getPref('httpport') || 9000;

	my $req = HTTP::Request->new( 
		'POST',
		"http://127.0.0.1:$httpPort/jsonrpc.js",
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

1;


# Our own timer object, checking for SC availability
package Slim::Utils::CleanupGUI::Timer;

use base 'Wx::Timer';
use Slim::Utils::ServiceManager;

my %listeners;

sub addListener {
	my ($self, $item, $callback) = @_;
	
	# if no callback is given, then enable the element if SC is running, or disable otherwise
	$listeners{$item} = $callback || sub { $item->Enable($_[0] == SC_STATE_RUNNING) };
}

sub Notify {
	my $status = $svcMgr->checkServiceState();

	foreach my $listener (keys %listeners) {

		if (my $callback = $listeners{$listener}) {
			&$callback($status);
		}
	}
}

1;


# Ok button will apply our changes
package Slim::Utils::CleanupGUI::OkButton;

use base 'Wx::Button';

my %actionHandlers;

sub addActionHandler {
	my ($self, $item, $callback) = @_;
	$actionHandlers{$item} = $callback if $callback;
}

sub do {
	my ($self, $status) = @_;
	
	foreach my $actionHandler (keys %actionHandlers) {
		
		if (my $action = $actionHandlers{$actionHandler}) {
			&$action($status);
		}
	}
}

1;


# The CleanupGUI main class
package Slim::Utils::CleanupGUI;

use base 'Wx::App';

my $args;

sub new {
	my $self = shift;
	$args = shift;
	
	$self->SUPER::new();
}

sub OnInit {
	my $frame = Slim::Utils::CleanupGUI::MainFrame->new($args);
	$frame->Show( 1 );
}

1;