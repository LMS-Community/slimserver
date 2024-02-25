package Slim::GUI::ControlPanel::MainFrame;

# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base 'Wx::Frame';

use Slim::Utils::Light;
use File::Spec::Functions;
use File::Slurp;

use Wx qw(:everything);
use Wx::Event qw(EVT_BUTTON EVT_NOTEBOOK_PAGE_CHANGED);

use Slim::GUI::ControlPanel::Settings;
use Slim::GUI::ControlPanel::Music;
use Slim::GUI::ControlPanel::Advanced;
use Slim::GUI::ControlPanel::Status;
use Slim::GUI::ControlPanel::Diagnostics;
use Slim::Utils::OSDetect;
use Slim::Utils::ServiceManager;

use constant PAGE_STATUS => 3;
use constant PAGE_SCAN   => 1;

my $pollTimer;
my $btnOk;

my $svcMgr = Slim::Utils::ServiceManager->new();

sub new {
	my $ref = shift;
	my $args = shift;

	Slim::Utils::OSDetect::init();

	# if we're running for the first time, show the SN page
	my $initialSetup = $svcMgr->isRunning() && !Slim::GUI::ControlPanel->getPref('wizardDone');

	my $self = $ref->SUPER::new(
		undef,
		-1,
		$initialSetup ? string('WELCOME_TO_SQUEEZEBOX_SERVER') : string('CONTROLPANEL_TITLE'),
		[-1, -1],
		main::ISWINDOWS ? [550, 610] : [700, 700],
		wxMINIMIZE_BOX | wxMAXIMIZE_BOX | wxCAPTION | wxCLOSE_BOX | wxSYSTEM_MENU | wxRESIZE_BORDER,
		'WELCOME_TO_SQUEEZEBOX_SERVER'
	);

	my $file = $self->_fixIcon('SqueezeCenter.ico');
	if ($file  && (my $icon = Wx::Icon->new($file, wxBITMAP_TYPE_ICO)) ) {
		$self->SetIcon($icon);
	}

	my $panel     = Wx::Panel->new($self);
	my $mainSizer = Wx::BoxSizer->new(wxVERTICAL);

	$pollTimer = Slim::GUI::ControlPanel::Timer->new();

	$btnOk = Slim::GUI::ControlPanel::OkButton->new( $panel, wxID_OK, string('OK') );
	EVT_BUTTON( $self, $btnOk, sub {
		$btnOk->do($svcMgr->checkServiceState());
		Slim::Utils::OS::Win32->cleanupTempDirs() if main::ISWINDOWS;
		$_[0]->Destroy;
	} );

	my $notebook = Wx::Notebook->new($panel);

	EVT_NOTEBOOK_PAGE_CHANGED($self, $notebook, sub {
		my ($self, $event) = @_;

		eval {
			my $child = $notebook->GetPage($notebook->GetSelection());
			if ($child && $child->can('_update')) {
				$child->_update($event);
			};
		}
	});

	$notebook->AddPage(Slim::GUI::ControlPanel::Settings->new($notebook, $self), string('CONTROLPANEL_SERVERSTATUS'), 1);
	$notebook->AddPage(Slim::GUI::ControlPanel::Music->new($notebook, $self), string('CONTROLPANEL_MUSIC_LIBRARY'));
	$notebook->AddPage(Slim::GUI::ControlPanel::Advanced->new($notebook, $self, $args), string('ADVANCED_SETTINGS'));
	$notebook->AddPage(Slim::GUI::ControlPanel::Diagnostics->new($notebook, $self, $args), string('CONTROLPANEL_DIAGNOSTICS'));
	$notebook->AddPage(Slim::GUI::ControlPanel::Status->new($notebook, $self), string('INFORMATION'));

	$mainSizer->Add($notebook, 1, wxALL | wxGROW, 10);

	my $footerSizer = Wx::BoxSizer->new(wxHORIZONTAL);

	if ($file = $self->_fixIcon('logitech-logo.png')) {
		Wx::Image::AddHandler(Wx::PNGHandler->new());
		my $icon = Wx::StaticBitmap->new( $panel, -1, Wx::Bitmap->new($file, wxBITMAP_TYPE_PNG) );
		$footerSizer->Add($icon, 0, wxLEFT | wxBOTTOM, 5);
	}

	my $btnsizer = Wx::StdDialogButtonSizer->new();
	$btnsizer->AddButton($btnOk);

	if (!$initialSetup) {
		my $btnApply = Wx::Button->new( $panel, wxID_APPLY, string('APPLY') );
		EVT_BUTTON( $self, $btnApply, sub {
			$btnOk->do($svcMgr->checkServiceState());
		} );

		$btnsizer->AddButton($btnApply);
	}

	my $btnCancel = Wx::Button->new( $panel, wxID_CANCEL, string('CANCEL') );

	EVT_BUTTON( $self, $btnCancel, sub {
		Slim::Utils::OS::Win32->cleanupTempDirs() if main::ISWINDOWS;
		$_[0]->Destroy;
	} );

	$btnsizer->AddButton($btnCancel);

	$btnsizer->Realize();

	my $footerSizer2 = Wx::BoxSizer->new(wxVERTICAL);
	$footerSizer2->Add($btnsizer, 0, wxEXPAND);
	$footerSizer2->AddSpacer(7);
	$footerSizer2->Add(Wx::StaticText->new($panel, -1, string('COPYRIGHT_LOGITECH')), 0, wxALIGN_RIGHT | wxRIGHT, 3);

	my ($version) = parseRevision();
	$version = sprintf(string('VERSION'), $version);
	$footerSizer2->Add(Wx::StaticText->new($panel, -1, $version), 0, wxALIGN_RIGHT | wxRIGHT, 3);

	$footerSizer->Add($footerSizer2, wxEXPAND);
	$mainSizer->Add($footerSizer, 0, wxLEFT | wxRIGHT | wxGROW, 8);

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
	my $iconFile = shift;

	return unless main::ISWINDOWS;

	# bug 12904 - Windows 2000 can't read hires icon file...
    return if $iconFile =~ /.ico$/i && Slim::Utils::OSDetect::details->{osName} =~ /Windows 2000/i;

	# set the application icon
	my $file = "../platforms/win32/res/$iconFile";

	if (main::ISACTIVEPERL && defined $PerlApp::VERSION && !-f $file) {
		$file = PerlApp::extract_bound_file($iconFile);
	}

	else {
		$file = $iconFile;
	}

	return $file if -f $file;
}

# stolen from Slim::Utils::Misc
sub parseRevision {
	# The revision file may not exist for svn copies.
	my $tempBuildInfo = eval { File::Slurp::read_file(
		catdir(scalar Slim::Utils::OSDetect::dirsFor('revision'), 'revision.txt')
	) } || "TRUNK\nUNKNOWN";

	# Once we've read the file, split it up so we have the Revision and Build Date
	return split (/\n/, $tempBuildInfo);
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

	Slim::GUI::ControlPanel->setPref('wizardDone', 1);

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
use Wx qw(:everything);
use LWP::UserAgent;
use JSON::XS::VersionOneAndTwo;

use Slim::Utils::ServiceManager;

my $args;

my $credentials = {};
my $needAuthentication;

sub new {
	my $self = shift;
	$args    = shift;

	$self = $self->SUPER::new();

	return $self;
}

sub OnInit {
	my $self = shift;
	my $frame;

	$frame = Slim::GUI::ControlPanel::MainFrame->new($args);

	$frame->Show( 1 );
}

# the following subs are static methods to deliver some commonly used services
my $baseUrl;
sub getBaseUrl {
	my $self = shift;
	my $update = shift;

	if ($update || !$baseUrl || time() > $baseUrl->{ttl}) {
		$baseUrl = {
			url => 'http://' . (
				$credentials && $credentials->{username} && $credentials->{password}
				? $credentials->{username} . ':' . $credentials->{password} . '@'
				: ''
			) . '127.0.0.1:' . (Slim::Utils::Light::getPref('httpport') || 9000),
			ttl => time() + 15,
		};
	}

	return $baseUrl->{url};
}

sub setPref {
	my ($self, $pref, $value) = @_;

	$self->serverRequest('pref', $pref, $value);
}

sub getPref {
	my ($self, $pref, $file) = @_;
	$file ||= '';

	my $value;

	# if SC is running, use the CLI, otherwise read the prefs file from disk
	if ($svcMgr->isRunning()) {

		if ($file) {
			$file =~ s/\.prefs$//;
			$file = "plugin.$file:";
		}

		$value = $self->serverRequest('pref', $file . $pref, '?');

		if (ref $value eq 'HASH' && $value->{msg} && $value->{msg} =~ /^500/i) {
			$value = Slim::Utils::Light::getPref($pref, $file);
		}
		elsif (ref $value eq 'HASH') {
			$value = $value->{'_p2'};
		}
	}

	else {
		$value = Slim::Utils::Light::getPref($pref, $file);
	}

	return $value;
}

sub string {
	my ($self, $stringToken) = @_;

	my $string = Slim::Utils::Light::string($stringToken);

	# if SC is running, use the CLI, otherwise read the prefs file from disk
	if ($string eq $stringToken && $svcMgr->isRunning()) {

		my $response = $self->serverRequest('getstring', $stringToken);

		if (ref $response eq 'HASH' && $response->{$stringToken} && $response->{$stringToken} ne $stringToken) {
			$string = $response->{$stringToken};
			Slim::Utils::Light::setString($stringToken, $string);
		}
	}

	return $string;
}

sub serverRequest {
	my $self = shift;
	my $postdata;

	return unless $svcMgr->isRunning();

	eval { $postdata = '{"id":1,"method":"slim.request","params":["",' . to_json(\@_) . ']}' };

	return if $@ || !$postdata;

	my $baseUrl = $self->getBaseUrl();
	$baseUrl =~ s|^http://||;

	my $req = HTTP::Request->new(
		'POST' => "http://$baseUrl/jsonrpc.js",
	);
	$req->header('Content-Type' => 'text/plain');

	$req->content($postdata);

	my $ua = LWP::UserAgent->new();
	$ua->timeout(2);

	if ($credentials && $credentials->{username} && $credentials->{password}) {
		$ua->credentials($baseUrl, Slim::Utils::Light::string('SQUEEZEBOX_SERVER'), $credentials->{username}, $credentials->{password});
	}

	return if $needAuthentication;

	my $response = $ua->request($req);

	# check whether authentication is needed
	while ($response->code == 401) {

		$needAuthentication = 1;

		my $loginDialog = Slim::GUI::ControlPanel::LoginDialog->new();

		if ($loginDialog->ShowModal() == wxID_OK) {

			$credentials = {
				username => $loginDialog->username,
				password => $loginDialog->password,
			};

			$ua->credentials($baseUrl, Slim::Utils::Light::string('SQUEEZEBOX_SERVER'), $credentials->{username}, $credentials->{password});

			$response = $ua->request($req);
		}

		else {
			exit;
		}

		$loginDialog->Destroy();
	}

	$needAuthentication = 0;

	my $content;
	$content = $response->decoded_content if ($response);

	if ($content) {
		eval {
			$content = from_json($content);
			$content = $content->{result};
		}
	}

	return ref $content eq 'HASH' ? $content : { msg => $content };
}

1;


# Ok button will apply our changes
package Slim::GUI::ControlPanel::LoginDialog;

use base 'Wx::Dialog';
use Wx qw(:everything);
use Slim::Utils::Light;

my ($username, $password);

sub new {
	my $self = shift;

	$self = $self->SUPER::new(undef, -1, string('LOGIN'), [-1, -1], [350, 220], wxDEFAULT_DIALOG_STYLE);

	my $mainSizer = Wx::BoxSizer->new(wxVERTICAL);

	$mainSizer->Add(Wx::StaticText->new($self, -1, string('CONTROLPANEL_AUTHENTICATION_REQUIRED')), 0, wxALL, 10);

	$mainSizer->Add(Wx::StaticText->new($self, -1, string('SETUP_USERNAME') . string('COLON')), 0, wxLEFT | wxRIGHT, 10);
	$username = Wx::TextCtrl->new($self, -1, '', [-1, -1], [320, -1]);
	$mainSizer->Add($username, 0, wxALL, 10);

	$mainSizer->Add(Wx::StaticText->new($self, -1, string('SETUP_PASSWORD') . string('COLON')), 0, wxLEFT | wxRIGHT, 10);
	$password = Wx::TextCtrl->new($self, -1, '', [-1, -1], [320, -1], wxTE_PASSWORD);
	$mainSizer->Add($password, 0, wxALL, 10);

	$mainSizer->AddStretchSpacer();

	my $btnsizer = Wx::StdDialogButtonSizer->new();
	$btnsizer->AddButton(Wx::Button->new($self, wxID_OK, string('OK')));
	$btnsizer->AddButton(Wx::Button->new($self, wxID_CANCEL, string('CANCEL')));
	$btnsizer->Realize();
	$mainSizer->Add($btnsizer, 0, wxALL | wxGROW, 10);

	$self->SetSizer($mainSizer);

	$self->Centre();

	return $self;
}

sub username {
	return $username->GetValue();
}


sub password {
	return $password->GetValue();
}

1;


package Slim::GUI::WebButton;

use base 'Wx::Button';

use Wx qw(:everything);
use Wx::Event qw(EVT_BUTTON);

use Slim::GUI::ControlPanel;
use Slim::Utils::Light;

sub new {
	my ($self, $page, $parent, $url, $label, $width) = @_;

	$self = $self->SUPER::new($page, -1, string($label), [-1, -1], [$width || -1, -1]);

	$parent->addStatusListener($self);

	$url = Slim::GUI::ControlPanel->getBaseUrl() . $url;

	EVT_BUTTON( $page, $self, sub {
		Wx::LaunchDefaultBrowser($url);
	});

	return $self;
}

1;
