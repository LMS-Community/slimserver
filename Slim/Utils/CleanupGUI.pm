package Slim::Utils::CleanupGUI::MainFrame;

use strict;
use base 'Wx::Frame';

use File::Spec::Functions;

use Wx qw(:everything);
use Wx::Event qw(EVT_BUTTON EVT_NOTEBOOK_PAGE_CHANGED);
use Slim::Utils::OSDetect;
use Slim::Utils::Light;
use Slim::Utils::ServiceManager;

use constant PAGE_STATUS => 3;
use constant PAGE_SCAN   => 1;

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
		my $file = '../platforms/win32/res/SqueezeCenter.ico';
		
		if (!-f $file && defined $PerlApp::VERSION) {
			$file = PerlApp::extract_bound_file('SqueezeCenter.ico');
		}

		if ( -f $file && (my $icon = Wx::Icon->new($file, wxBITMAP_TYPE_ICO)) ) {
			
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
	EVT_BUTTON( $self, $btnOk, sub {
		$btnOk->do($svcMgr->checkServiceState());
		$_[0]->Destroy;
	} );


	$notebook->AddPage(Slim::Utils::CleanupGUI::SettingsPage->new($notebook, -1), string('SETTINGS'), 1);
	$notebook->AddPage(Slim::Utils::CleanupGUI::ScanPage->new($notebook, -1), string('CLEANUP_MUSIC_LIBRARY'));
	$notebook->AddPage(maintenancePage($notebook, $args, $self), string('CLEANUP_MAINTENANCE'));
	$notebook->AddPage(Slim::Utils::CleanupGUI::StatusPage->new($notebook, -1), string('INFORMATION'));
	
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

1;


# settings page with start options etc.
package Slim::Utils::CleanupGUI::SettingsPage;

use base 'Wx::Panel';

use Wx qw(:everything);
use Wx::Event qw(EVT_BUTTON);
use File::Spec::Functions qw(catfile);

use Slim::Utils::Light;
use Slim::Utils::ServiceManager;

sub new {
	my $self = shift;

	$self = $self->SUPER::new(@_);

	my $mainSizer = Wx::BoxSizer->new(wxVERTICAL);	
	$mainSizer->Add(
		Wx::StaticText->new($self, -1, "Start/Stop SC\nStartup behaviour\nmusic/playlist folder location\nuse iTunes\nrescan, automatic, timed?"),
		0, wxALL, 10
	);

	# startup mode
	my ($noAdminWarning, @startupOptions) = $svcMgr->getStartupOptions();

	if ($noAdminWarning) {
		my $string = string($noAdminWarning);
		$string    =~ s/\\n/\n/g;
		
		$mainSizer->Add(Wx::StaticText->new($self, -1, $string), 0, wxALL, 10);
	}

	@startupOptions = map { string($_) } @startupOptions;	
	my $lbStartupMode = Wx::Choice->new($self, -1, [-1, -1], [-1, -1], \@startupOptions);
	$lbStartupMode->SetSelection($svcMgr->getStartupType() || 0);
	$lbStartupMode->Enable($svcMgr->canSetStartupType());
	
	$btnOk->addActionHandler($lbStartupMode, sub {

		$svcMgr->setStartupType($lbStartupMode->GetSelection());

	});
		
	$mainSizer->Add($lbStartupMode, 0, wxALL, 10);

	# Start/Stop button
	my $btnStartStop = Wx::Button->new($self, -1, string('STOP_SQUEEZECENTER'));
	EVT_BUTTON( $self, $btnStartStop, sub {
		if ($svcMgr->checkServiceState() == SC_STATE_RUNNING) {
			Slim::Utils::CleanupGUI->serverRequest('{"id":1,"method":"slim.request","params":["",["stopserver"]]}');
		}
		
		# starting SC is heavily platform dependant
		else {
			$svcMgr->start();
		}
	});

	$pollTimer->addListener($btnStartStop, sub {
		$btnStartStop->SetLabel($_[0] == SC_STATE_RUNNING ? string('STOP_SQUEEZECENTER') :  string('START_SQUEEZECENTER'));
		$btnStartStop->Enable( ($_[0] == SC_STATE_RUNNING || $_[0] == SC_STATE_STOPPED || $_[0] == SC_STATE_UNKNOWN) && ($_[0] == SC_STATE_STOPPED ? $svcMgr->canStart : 1) );
	});
	
	$mainSizer->Add($btnStartStop, 0, wxALL, 10);
	
	# links to log files
	# on OSX we can't "start" the log files, but need to use some trickery to get an URL
	my $log = catfile($os->dirsFor('log'), 'server.log');
	my $serverlogLink = Wx::HyperlinkCtrl->new(
		$self, 
		-1, 
		$log, 
		$os->name eq 'mac' ? Slim::Utils::CleanupGUI::getBaseUrl() . '/server.log?lines=500' : 'file://' . $log, 
		[-1, -1], 
		[-1, -1], 
		wxHL_DEFAULT_STYLE,
	);
	$pollTimer->addListener($serverlogLink) if $os->name eq 'mac';
	$mainSizer->Add($serverlogLink, 0, wxALL, 10);

	$log = catfile($os->dirsFor('log'), 'scanner.log');
	my $scannerlogLink = Wx::HyperlinkCtrl->new(
		$self, 
		-1, 
		$log, 
		$os->name eq 'mac' ? Slim::Utils::CleanupGUI::getBaseUrl() . '/scanner.log?lines=500' : 'file://' . $log, 
		[-1, -1], 
		[-1, -1], 
		wxHL_DEFAULT_STYLE,
	);
	$pollTimer->addListener($scannerlogLink) if $os->name eq 'mac';
	$mainSizer->Add($scannerlogLink, 0, wxALL, 10);

	$self->SetSizer($mainSizer);	
	
	return $self;
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

sub new {
	my $self = shift;
		
	$self = $self->SUPER::new(@_);
	$self->{actionHandlers} = {};
	$self->SetDefault();
	
	return $self;
}

sub addActionHandler {
	my ($self, $item, $callback) = @_;
	$self->{actionHandlers}->{$item} = $callback;
}

sub do {
	my ($self, $status) = @_;
	
	foreach my $actionHandler (keys %{ $self->{actionHandlers} }) {
		
		if (my $action = $self->{actionHandlers}->{$actionHandler}) {
			&$action($status);
		}
	}
}

1;


package Slim::Utils::CleanupGUI::ScanPage;

use base 'Wx::Panel';

use Wx qw(:everything);
use Wx::Event qw(EVT_CHILD_FOCUS EVT_SET_FOCUS);
use Slim::Utils::Light;
use Slim::Utils::ServiceManager;

sub new {
	my $self = shift;
	
	$self = $self->SUPER::new(@_);

	my $mainSizer = Wx::BoxSizer->new(wxVERTICAL);	
	
	# folder selectors
	my $btnAudioDir = Wx::DirPickerCtrl->new($self, -1, getPref('audiodir') || '', string('SETUP_AUDIODIR'), wxDefaultPosition, wxDefaultSize, wxPB_USE_TEXTCTRL | wxDIRP_DIR_MUST_EXIST);
	$pollTimer->addListener($btnAudioDir);

	$btnOk->addActionHandler($btnAudioDir, sub {
		my $running = (shift == SC_STATE_RUNNING);

		my $path = $btnAudioDir->GetPath;
		if ($running && $path ne getPref('audiodir')) {
			$path =~ s/\\/\\\\/g if Slim::Utils::OSDetect->isWindows();
			Slim::Utils::CleanupGUI->setPref("audiodir", $path);
		}
	});

	$mainSizer->Add($btnAudioDir, 0, wxEXPAND | wxALL, 10);

	my $btnPlaylistDir = Wx::DirPickerCtrl->new($self, -1, getPref('playlistdir') || '', string('SETUP_PLAYLISTDIR'), wxDefaultPosition, wxDefaultSize, wxPB_USE_TEXTCTRL | wxDIRP_DIR_MUST_EXIST);
	$pollTimer->addListener($btnPlaylistDir);

	$btnOk->addActionHandler($btnPlaylistDir, sub {
		my $running = (shift == SC_STATE_RUNNING);

		my $path = $btnPlaylistDir->GetPath;
		if ($running && $path ne getPref('playlistdir')) {
			$path =~ s/\\/\\\\/g if Slim::Utils::OSDetect->isWindows();
			Slim::Utils::CleanupGUI->setPref("playlistdir", $path);
		}
	});
	$mainSizer->Add($btnPlaylistDir, 0, wxEXPAND | wxALL, 10);

	$self->SetSizer($mainSizer);
	
	return $self;
}

1;


# basically display Settings/Information from the web UI
package Slim::Utils::CleanupGUI::StatusPage;

use base 'Wx::Panel';

use Wx qw(:everything);
use Wx::Event qw(EVT_CHILD_FOCUS);
use Wx::Html;
use LWP::Simple;

use Slim::Utils::Light;

sub new {
	my $self = shift;
	
	$self = $self->SUPER::new(@_);
	
	$self->{loaded} = 0;

	EVT_CHILD_FOCUS($self, sub {
		my ($self, $event) = @_;

		my $child = $event->GetWindow();
		if ( $child && $child->isa('Wx::HtmlWindow') && !$self->{loaded} ) {
			$child->SetPage(get(Slim::Utils::CleanupGUI::getBaseUrl() . '/EN/settings/server/status.html?simple=1') || string('CLEANUP_NO_STATUS'));
			$self->{loaded} = 1;
		}
		else {
			$self->{loaded} = 0;
		}

		$event->Skip();
	});

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

	return $self;
}

1;


# The CleanupGUI main class
package Slim::Utils::CleanupGUI;

use base 'Wx::App';
use LWP::UserAgent;
use JSON::XS qw(to_json from_json);

use Slim::Utils::Light;
my $args;

sub new {
	my $self = shift;
	$args    = shift;

	$self = $self->SUPER::new();

	return $self;
}

sub OnInit {
	my $self = shift;
	my $frame = Slim::Utils::CleanupGUI::MainFrame->new($args);
	$frame->Show( 1 );
}

sub getBaseUrl {
	return 'http://127.0.0.1:' . getPref('httpport');
}

sub setPref {
	my ($self, $pref, $value) = @_;
	$self->serverRequest('{"id":1,"method":"slim.request","params":["",["pref", "' . $pref . '", "' . $value . '"]]}');
}

sub serverRequest {
	my $self     = shift;
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


1;