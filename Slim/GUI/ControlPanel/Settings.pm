package Slim::GUI::ControlPanel::Settings;

# SqueezeCenter Copyright 2001-2009 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use base 'Wx::Panel';

use Wx qw(:everything);
use Wx::Event qw(EVT_BUTTON);
use File::Spec::Functions qw(catfile);

use Slim::GUI::ControlPanel;
use Slim::Utils::Light;
use Slim::Utils::ServiceManager;

sub new {
	my ($self, $nb, $parent) = @_;

	$self = $self->SUPER::new($nb);

	my $svcMgr = Slim::Utils::ServiceManager->new();

	my $mainSizer = Wx::BoxSizer->new(wxVERTICAL);

	# startup mode
	my ($noAdminWarning, @startupOptions) = $svcMgr->getStartupOptions();

	if ($noAdminWarning) {
		my $string = string($noAdminWarning);
		$string    =~ s/\\n/\n/g;
		
		$mainSizer->Add(Wx::StaticText->new($self, -1, $string), 0, wxALL, 10);
	}

	my $startupBox = Wx::StaticBox->new($self, -1, string('CLEANUP_STARTUP_OPTIONS'));
	my $startupSizer = Wx::StaticBoxSizer->new( $startupBox, wxVERTICAL );

	@startupOptions = map { string($_) } @startupOptions;	
	
	my $lbStartupMode = Wx::Choice->new($self, -1, [-1, -1], [-1, -1], \@startupOptions);
	$lbStartupMode->SetSelection($svcMgr->getStartupType() || 0);
	$lbStartupMode->Enable($svcMgr->canSetStartupType());
	
	$parent->addApplyHandler($lbStartupMode, sub {
		$svcMgr->setStartupType($lbStartupMode->GetSelection());
	});
		
	$startupSizer->Add($lbStartupMode, 0, wxALL, 10);

	# Start/Stop button
	my $btnStartStop = Wx::Button->new($self, -1, string('STOP_SQUEEZECENTER'));
	EVT_BUTTON( $self, $btnStartStop, sub {
		if ($svcMgr->checkServiceState() == SC_STATE_RUNNING) {
			Slim::GUI::ControlPanel->serverRequest('{"id":1,"method":"slim.request","params":["",["stopserver"]]}');
		}
		
		# starting SC is heavily platform dependant
		else {
			$svcMgr->start();
			$parent->checkServiceStatus();
		}
	});

	$parent->addStatusListener($btnStartStop, sub {
		$btnStartStop->SetLabel($_[0] == SC_STATE_RUNNING ? string('STOP_SQUEEZECENTER') :  string('START_SQUEEZECENTER'));
		$btnStartStop->Enable( ($_[0] == SC_STATE_RUNNING || $_[0] == SC_STATE_STOPPED || $_[0] == SC_STATE_UNKNOWN) && ($_[0] == SC_STATE_STOPPED ? $svcMgr->canStart : 1) );
	});
	
	$startupSizer->Add($btnStartStop, 0, wxALL, 10);

	$mainSizer->Add($startupSizer, 0, wxALL | wxGROW, 10);
	
	my $logBox = Wx::StaticBox->new($self, -1, string('DEBUGGING_SETTINGS'));
	my $logSizer = Wx::StaticBoxSizer->new($logBox, wxVERTICAL);	
	
	$logSizer->Add(Slim::GUI::Settings::LogLink->new($self, $parent, 'server.log'), 0, wxALL, 10);
	$logSizer->Add(Slim::GUI::Settings::LogLink->new($self, $parent, 'scanner.log'), 0, wxALL, 10);
	
	$mainSizer->Add($logSizer, 0, wxALL | wxGROW, 10);
	
	$self->SetSizer($mainSizer);	
	
	return $self;
}

1;


package Slim::GUI::Settings::LogLink;

use base 'Wx::HyperlinkCtrl';

use Wx qw(:everything);
use File::Spec::Functions qw(catfile);

use Slim::GUI::ControlPanel;
use Slim::Utils::OSDetect;

my $os = Slim::Utils::OSDetect::getOS();

sub new {
	my ($self, $page, $parent, $file) = @_;

	my $log = catfile($os->dirsFor('log'), $file);
		
	$self = $self->SUPER::new(
		$page,
		-1, 
		$log, 
		$os->name eq 'mac' ? Slim::GUI::ControlPanel::getBaseUrl() . "/$file?lines=500" : 'file://' . $log, 
		[-1, -1], 
		[-1, -1], 
		wxHL_DEFAULT_STYLE,
	);
	
	$parent->addStatusListener($self) if $os->name eq 'mac';

	return $self;
}

1;
