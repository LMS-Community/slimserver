package Slim::GUI::ControlPanel::Advanced;

# SqueezeCenter Copyright 2001-2009 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use base 'Wx::Panel';

use Wx qw(:everything);
use Wx::Event qw(EVT_BUTTON);
use File::Spec::Functions qw(catfile);
use LWP::Simple;

use Slim::Utils::Light;
use Slim::Utils::ServiceManager;
use Slim::Utils::OSDetect;

my $os = Slim::Utils::OSDetect::getOS();
my $updateUrl;
my $versionFile = catfile( scalar($os->dirsFor('updates')), 'squeezecenter.version' );

if ($os->name eq 'win') {
	require Win32::Process;
}

my %checkboxes;

sub new {
	my ($self, $nb, $parent, $args) = @_;

	$self = $self->SUPER::new($nb);
	$self->{args} = $args;

	my $mainSizer = Wx::BoxSizer->new(wxVERTICAL);
	
	if ($os->name eq 'win') {

		# check for SC updates
		my $updateBox = Wx::StaticBox->new($self, -1, string('SETUP_CHECKVERSION')); 
		my $updateSizer = Wx::StaticBoxSizer->new($updateBox, wxVERTICAL);
	
		my $ready = $self->_checkForUpdate();

		my $updateLabel = Wx::StaticText->new($self, -1, string($ready ? 'CONTROLPANEL_UPDATE_AVAILABLE' : 'CONTROLPANEL_NO_UPDATE_AVAILABLE'));	
		$updateSizer->Add($updateLabel, 0, wxLEFT | wxRIGHT | wxTOP, 10);
	
		# update button
		my $btnsizer = Wx::StdDialogButtonSizer->new();
		my $btnUpdate = Wx::Button->new($self, -1, string($ready ? 'CONTROLPANEL_INSTALL_UPDATE' : 'CONTROLPANEL_CHECK_UPDATE'));
		$btnsizer->SetAffirmativeButton($btnUpdate);
		$btnsizer->Realize();

		EVT_BUTTON( $self, $btnUpdate, sub {
			
			if (my $installer = _checkForUpdate()) {

				my $processObj;
				Win32::Process::Create(
					$processObj,
					$installer,
					'',
					0,
					Win32::Process::DETACHED_PROCESS() | Win32::Process::CREATE_NO_WINDOW() | Win32::Process::NORMAL_PRIORITY_CLASS(),
					'.'
				) && exit;				
				
			}

			elsif ($updateUrl) {
				Wx::LaunchDefaultBrowser($updateUrl);
				exit;
			}

			else {

				my $check = get( sprintf(
					"http://update.squeezenetwork.com/update/?version=%s&lang=%s&os=%s",
					$::VERSION,
					$os->getSystemLanguage(),
					$os->installerOS(),
				));
				chomp($check) if $check;

				if ($check) {
					my @parts = split /\. /, $check;
					
					if (@parts > 1 && $parts[1] =~ /href="(.*?)"/) {
						$updateUrl = $1;
						
						$updateLabel->SetLabel( decode("utf8", $parts[0]) );
						$btnUpdate->SetLabel(string('CONTROLPANEL_DOWNLOAD_UPDATE'));
					}
				}
				
				else {
					$updateLabel->SetLabel(string('CONTROLPANEL_NO_UPDATE_AVAILABLE'));
					$btnUpdate->SetLabel(string('CONTROLPANEL_CHECK_UPDATE'));
				}
			}
		});
			
		$updateSizer->Add($btnsizer, 0, wxALL | wxGROW, 10);
		
		$mainSizer->Add($updateSizer, 0, wxALL | wxGROW, 10);	
	}
	
	
	my $webBox = Wx::StaticBox->new($self, -1, string('CONTROLPANEL_WEB_UI')); 
	my $webSizer = Wx::StaticBoxSizer->new($webBox, wxVERTICAL);

	$webSizer->Add(Wx::HyperlinkCtrl->new(
		$self, 
		-1, 
		string('CONTROLPANEL_WEB_CONTROL_DESC'), 
		Slim::GUI::ControlPanel->getBaseUrl() . '/',
		[-1, -1], 
		[-1, -1], 
		wxHL_DEFAULT_STYLE,
	), 0, wxALL, 10);

	$webSizer->Add(Wx::HyperlinkCtrl->new(
		$self, 
		-1, 
		string('CONTROLPANEL_ADVANCED_SETTINGS_DESC'), 
		Slim::GUI::ControlPanel->getBaseUrl() . '/settings/index.html',
		[-1, -1], 
		[-1, -1], 
		wxHL_DEFAULT_STYLE,
	), 0, wxLEFT | wxRIGHT | wxBOTTOM, 10);
	
	$mainSizer->Add($webSizer, 0, wxALL | wxGROW, 10);
	

	my $cleanupBox = Wx::StaticBox->new($self, -1, string('CLEANUP'));
	my $cleanupSizer = Wx::StaticBoxSizer->new($cleanupBox, wxVERTICAL);

	$cleanupSizer->Add(Slim::GUI::Settings::LogLink->new($self, $parent, 'server.log'), 0, wxLEFT | wxRIGHT | wxTOP, 10);
	$cleanupSizer->Add(Slim::GUI::Settings::LogLink->new($self, $parent, 'scanner.log'), 0, wxALL, 10);

	my $cbSizer = Wx::BoxSizer->new(wxVERTICAL);

	foreach (@{ $args->{options} }) {
		
		# support only wants these three options
		next unless $_->{name} =~ /^(?:prefs|cache|all)$/;
		
		$checkboxes{$_->{name}} = Wx::CheckBox->new( $self, -1, $_->{title}, $_->{position});
		$cbSizer->Add( $checkboxes{$_->{name}}, 0, wxTOP | wxGROW, $_->{margin} || 5 );
	}

	$cleanupSizer->Add($cbSizer, 1, wxALL, 5);

	my $hint = Wx::StaticText->new($self, -1, string('CLEANUP_PLEASE_STOP_SC'));
	$parent->addStatusListener($hint);
	$cleanupSizer->Add($hint, 0, wxALL, 5);

	my $btnsizer = Wx::StdDialogButtonSizer->new();

	my $btnCleanup = Wx::Button->new( $self, -1, string('CLEANUP_DO') );
	EVT_BUTTON( $self, $btnCleanup, \&doCleanup );
	
	$btnsizer->SetAffirmativeButton($btnCleanup);
	
	$btnsizer->Realize();

	$cleanupSizer->Add($btnsizer, 0, wxALIGN_BOTTOM | wxALL | wxALIGN_RIGHT, 10);
	$mainSizer->Add($cleanupSizer, 0, wxALL | wxGROW, 10);	
	
	$self->SetSizer($mainSizer);

	return $self;
}

sub doCleanup {
	my( $self, $event ) = @_;

	# return if no option was selected
	return unless grep { $checkboxes{$_}->GetValue() } keys %checkboxes;
	
	my $svcMgr = Slim::Utils::ServiceManager->new();
	
	if ($svcMgr->checkServiceState() == SC_STATE_RUNNING) {
		
		my $msg = Wx::MessageDialog->new($self, string('CLEANUP_WANT_TO_STOP_SC'), string('CLEANUP_DO'), wxYES_NO | wxNO_DEFAULT | wxICON_QUESTION);
		
		if ($msg->ShowModal() == wxID_YES) {
			# stop SC before continuing
			Slim::GUI::ControlPanel->serverRequest('stopserver');
			
			# wait while SC is being shut down
			my $wait = 59;
			while ($svcMgr->checkServiceState != SC_STATE_STOPPED && $wait > 0) {
				sleep 5;
				$wait -= 5;
			}
		}
		else {
			# don't do anything
			return;
		}
	}
		
	my $params = {};
	my $selected = 0;
		
	foreach (@{ $self->{args}->{options} }) {
		
		next unless $checkboxes{$_->{name}};
		
		$params->{$_->{name}} = $checkboxes{$_->{name}}->GetValue();
		$selected ||= $checkboxes{$_->{name}}->GetValue();
	}
	
	if ($selected) {
		Wx::BusyCursor->new();
			
		my $folders = $self->{args}->{folderCB}($params);

		$self->{args}->{cleanCB}($folders) if $folders;
	}
}

sub _checkForUpdate {
	
	open(UPDATEFLAG, $versionFile) || return '';
	
	my $installer = '';
	
	while ( <UPDATEFLAG> ) {

		chomp;
		
		if (/SqueezeCenter.*/) {
			$installer = $_;
			last;
		}
	}
		
	close UPDATEFLAG;
	
	return $installer && -e $installer ? $installer : 0;
}

1;


package Slim::GUI::Settings::WebButton;

use base 'Wx::Button';

use Wx qw(:everything);
use Wx::Event qw(EVT_BUTTON);

use Slim::GUI::ControlPanel;
use Slim::Utils::Light;

sub new {
	my ($self, $page, $parent, $url, $label) = @_;
	
	$self = $self->SUPER::new($page, -1, string($label));
	
	$parent->addStatusListener($self);
	
	$url = Slim::GUI::ControlPanel->getBaseUrl() . $url;

	EVT_BUTTON( $page, $self, sub {
		Wx::LaunchDefaultBrowser($url);
	});

	return $self;
}

1;


package Slim::GUI::Settings::LogLink;

use base 'Wx::HyperlinkCtrl';

use Wx qw(:everything);
use File::Spec::Functions qw(catfile);

use Slim::GUI::ControlPanel;

sub new {
	my ($self, $page, $parent, $file) = @_;

	my $log = catfile($os->dirsFor('log'), $file);
		
	$self = $self->SUPER::new(
		$page,
		-1, 
		$log, 
		$os->name eq 'mac' ? Slim::GUI::ControlPanel->getBaseUrl() . "/$file?lines=500" : 'file://' . $log, 
		[-1, -1], 
		[-1, -1], 
		wxHL_DEFAULT_STYLE,
	);
	
	$parent->addStatusListener($self) if $os->name eq 'mac';

	return $self;
}

1;
