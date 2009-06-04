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
use LWP::Simple qw($ua get);

$ua->timeout(10);

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
	
	
	my $webSizer = Wx::StaticBoxSizer->new(
		Wx::StaticBox->new($self, -1, string('CONTROLPANEL_WEB_UI')),
		wxVERTICAL
	);
	
	$webSizer->Add( Slim::GUI::WebButton->new($self, $parent, '/', 'CONTROLPANEL_WEB_CONTROL_DESC', 250) , 0, wxALL, 10 );
	$webSizer->Add( Slim::GUI::WebButton->new($self, $parent, '/settings/index.html', 'CONTROLPANEL_ADVANCED_SETTINGS_DESC', 250) , 0, wxALL, 10 );

	$mainSizer->Add($webSizer, 0, wxALL | wxGROW, 10);


	my $logSizer = Wx::StaticBoxSizer->new(
		Wx::StaticBox->new($self, -1, string('CONTROLPANEL_LOGFILES')),
		wxVERTICAL
	);

	my $logBtnSizer = Wx::BoxSizer->new(wxHORIZONTAL);

	$logBtnSizer->Add(Slim::GUI::Settings::LogLink->new($self, $parent, 'server.log', 'CONTROLPANEL_SHOW_SERVER_LOG'));
	$logBtnSizer->Add(Slim::GUI::Settings::LogLink->new($self, $parent, 'scanner.log', 'CONTROLPANEL_SHOW_SCANNER_LOG'), 0, wxLEFT, 10);

	$logSizer->Add($logBtnSizer);
	$mainSizer->Add($logSizer, 0, wxALL | wxGROW, 10);
	

	my $cleanupBox = Wx::StaticBox->new($self, -1, string('CLEANUP'));
	my $cleanupSizer = Wx::StaticBoxSizer->new($cleanupBox, wxVERTICAL);

	my $cbSizer = Wx::BoxSizer->new(wxVERTICAL);

	foreach (@{ $args->{options} }) {
		
		# support only wants these three options
		next unless $_->{name} =~ /^(?:prefs|cache)$/;
		
		$checkboxes{$_->{name}} = Wx::CheckBox->new( $self, -1, $_->{title}, $_->{position});
		$cbSizer->Add( $checkboxes{$_->{name}}, 0, wxTOP, 5 );
	}

	$cleanupSizer->Add($cbSizer, 1, wxALL, 5);

	my $btnCleanup = Wx::Button->new( $self, -1, string('CLEANUP_DO') );
	EVT_BUTTON( $self, $btnCleanup, \&doCleanup );
	
	$cleanupSizer->Add($btnCleanup, 0, wxALL , 10);
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


package Slim::GUI::Settings::LogLink;

use base 'Wx::Button';

use Wx qw(:everything);
use Wx::Event qw(EVT_BUTTON);
use File::Spec::Functions qw(catfile);

use Slim::GUI::ControlPanel;
use Slim::Utils::Light;

sub new {
	my ($self, $page, $parent, $file, $label, $width) = @_;

	$self = $self->SUPER::new($page, -1, string($label), [-1, -1], [$width || -1, -1]);

	EVT_BUTTON( $page, $self, sub {
		Wx::LaunchDefaultBrowser('file://' . $os->dirsFor('log') . "/$file");
	});

	return $self;
}

1;
