package Slim::GUI::ControlPanel::MainFrame;

# SqueezeCenter Copyright 2001-2009 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use base 'Wx::Frame';

use File::Spec::Functions;

use Wx qw(:everything);
use Wx::Event qw(EVT_BUTTON);

use Slim::GUI::ControlPanel::Maintenance;
use Slim::GUI::ControlPanel::Music;
use Slim::GUI::ControlPanel::Settings;
use Slim::GUI::ControlPanel::Status;
use Slim::Utils::OSDetect;
use Slim::Utils::Light;
use Slim::Utils::ServiceManager;

use constant PAGE_STATUS => 3;
use constant PAGE_SCAN   => 1;

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

	Slim::Utils::OSDetect::init();
	$self->_fixIcon();

	my $panel    = Wx::Panel->new($self);
	my $notebook = Wx::Notebook->new($panel);

	$pollTimer = Slim::GUI::ControlPanel::Timer->new();

	$btnOk = Slim::GUI::ControlPanel::OkButton->new( $panel, wxID_OK, string('OK') );
	EVT_BUTTON( $self, $btnOk, sub {
		$btnOk->do($svcMgr->checkServiceState());
		$_[0]->Destroy;
	} );


	$notebook->AddPage(Slim::GUI::ControlPanel::Settings->new($notebook, $self), string('SETTINGS'), 1);
	$notebook->AddPage(Slim::GUI::ControlPanel::Music->new($notebook, $self), string('CLEANUP_MUSIC_LIBRARY'));
	$notebook->AddPage(Slim::GUI::ControlPanel::Maintenance->new($notebook, $self, $args), string('CLEANUP_MAINTENANCE'));
	$notebook->AddPage(Slim::GUI::ControlPanel::Status->new($notebook), string('INFORMATION'));
	
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

sub addApplyHandler {
	my $self = shift;
	$btnOk->addActionHandler(@_);
}

sub addStatusListener {
	my $self = shift;
	$pollTimer->addListener(@_);
}

sub checkServiceStatus {
	$pollTimer->Notify();
}

sub _fixIcon {
	my $self = shift;

	return unless Slim::Utils::OSDetect::isWindows();

	# set the application icon
	my $file = '../platforms/win32/res/SqueezeCenter.ico';
		
	if (!-f $file && defined $PerlApp::VERSION) {
		$file = PerlApp::extract_bound_file('SqueezeCenter.ico');
	}

	if ( -f $file && (my $icon = Wx::Icon->new($file, wxBITMAP_TYPE_ICO)) ) {
		
		$self->SetIcon($icon);
	}
}

1;


# Our own timer object, checking for SC availability
package Slim::GUI::ControlPanel::Timer;

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
package Slim::GUI::ControlPanel::OkButton;

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


# The CleanupGUI main class
package Slim::GUI::ControlPanel;

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
	my $frame = Slim::GUI::ControlPanel::MainFrame->new($args);
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