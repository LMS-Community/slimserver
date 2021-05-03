package Slim::GUI::ControlPanel::Advanced;

# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base 'Wx::Panel';

use Wx qw(:everything);
use Wx::Event qw(EVT_BUTTON EVT_TIMER);
use File::Spec::Functions qw(catfile);

use Slim::Utils::Light;
use Slim::Utils::ServiceManager;
use Slim::Utils::OSDetect;

my $os = Slim::Utils::OSDetect::getOS();

if (main::ISWINDOWS) {
	require Win32::Process;

	if (0) {
		require 'auto/Win32/Process/List/autosplit.ix';
	}
}

my %checkboxes;

sub new {
	my ($self, $nb, $parent, $args) = @_;

	$self = $self->SUPER::new($nb);
	$self->{args} = $args;

	my $mainSizer = Wx::BoxSizer->new(wxVERTICAL);

	if (main::ISWINDOWS) {

		# check for SC updates
		my $updateSizer = Wx::StaticBoxSizer->new(
			Wx::StaticBox->new($self, -1, string('SETUP_CHECKVERSION')),
			wxVERTICAL
		);

		my $updateLabel = Wx::StaticText->new($self, -1, '');
		$updateSizer->Add($updateLabel, 0, wxLEFT | wxRIGHT | wxTOP | wxGROW, 10);

		# update button
		my $btnUpdate = Wx::Button->new($self, -1, string('CONTROLPANEL_INSTALL_UPDATE'));

		EVT_BUTTON( $self, $btnUpdate, sub {

			if (my $installer = Slim::Utils::Light->checkForUpdate()) {

				Slim::Utils::Light->resetUpdateCheck();

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

		});

		$updateSizer->Add($btnUpdate, 0, wxALL, 10);

		$mainSizer->Add($updateSizer, 0, wxALL | wxGROW, 10);

		my $updateChecker = Wx::Timer->new($self, 1);
		EVT_TIMER( $self, 1, sub {
			my $ready = Slim::Utils::Light->checkForUpdate();
			$updateLabel->SetLabel( string($ready ? 'CONTROLPANEL_UPDATE_AVAILABLE' : 'CONTROLPANEL_NO_UPDATE_AVAILABLE') );
			$btnUpdate->Enable($ready);

			# check every five minutes
			$updateChecker->Start(0.5 * 60 * 1000);
		});
		$updateChecker->Start(500);
	}


	my $webSizer = Wx::StaticBoxSizer->new(
		Wx::StaticBox->new($self, -1, string('CONTROLPANEL_WEB_UI')),
		wxVERTICAL
	);

	$webSizer->Add( Slim::GUI::WebButton->new($self, $parent, '/', 'CONTROLPANEL_WEB_CONTROL_DESC', 250) , 0, wxLEFT | wxTOP, 10 );
	$webSizer->Add( Slim::GUI::WebButton->new($self, $parent, '/settings/index.html', 'CONTROLPANEL_ADVANCED_SETTINGS_DESC', 250) , 0, wxALL, 10 );

	$mainSizer->Add($webSizer, 0, wxALL | wxGROW, 10);


	my $logSizer = Wx::StaticBoxSizer->new(
		Wx::StaticBox->new($self, -1, string('CONTROLPANEL_LOGFILES')),
		wxVERTICAL
	);

	my $logBtnSizer = Wx::BoxSizer->new(wxHORIZONTAL);

	$logBtnSizer->Add(Slim::GUI::ControlPanel::LogLink->new($self, $parent, 'server.log', 'CONTROLPANEL_SHOW_SERVER_LOG'));
	$logBtnSizer->Add(Slim::GUI::ControlPanel::LogLink->new($self, $parent, 'scanner.log', 'CONTROLPANEL_SHOW_SCANNER_LOG'), 0, wxLEFT, 10);

	$logSizer->Add($logBtnSizer, 0, wxALL, 10);

	$logSizer->Add(Slim::GUI::ControlPanel::LogOptions->new($self, $parent), 0, wxLEFT | wxBOTTOM, 10);

	$mainSizer->Add($logSizer, 0, wxALL | wxGROW, 10);


	my $cleanupSizer = Wx::StaticBoxSizer->new(
		Wx::StaticBox->new($self, -1, string('CLEANUP')),
		wxVERTICAL
	);

	$cleanupSizer->AddSpacer(5);

	foreach (@{ $args->{options} }) {

		# support only wants these three options
		next unless $_->{name} =~ /^(?:prefs|cache)$/;

		$checkboxes{$_->{name}} = Wx::CheckBox->new( $self, -1, $_->{title}, $_->{position});
		$cleanupSizer->AddSpacer(5);
		$cleanupSizer->Add($checkboxes{$_->{name}}, 0, wxLEFT, 10);
	}

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

1;


package Slim::GUI::ControlPanel::LogLink;

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


package Slim::GUI::ControlPanel::LogOptions;

use base 'Wx::Choice';

use Wx qw(:everything);
use File::Spec::Functions qw(catfile);

use Slim::GUI::ControlPanel;
use Slim::Utils::Light;
use Slim::Utils::Log;
use Slim::Utils::ServiceManager;

my $logGroups;

sub new {
	my ($self, $page, $parent) = @_;

	$logGroups = Slim::Utils::Log->logGroups();

	my @logOptions = (string('DEBUG_DEFAULT'));

	my $x = 1;
	foreach my $group (keys %$logGroups) {

		$logGroups->{$group}->{index} = $x;
		push @logOptions, string($logGroups->{$group}->{label});

		$x++;
	}

	$parent->addApplyHandler($self, sub {
		$self->save(@_);
	});

	$self = $self->SUPER::new($page, -1, [-1, -1], [-1, -1], \@logOptions);

	return $self;
}


sub save {
	my $self = shift;
	my $state = shift;

	my $selected = $self->GetSelection();
	my ($group) = grep { $logGroups->{$_}->{index} == $selected } keys %$logGroups;

	$group ||= 'default';

	if ($state == SC_STATE_RUNNING) {
		Slim::GUI::ControlPanel->serverRequest('logging', "group:$group");
	}
	else {
		Slim::Utils::Log->init({
			'logconf' => catfile(scalar Slim::Utils::OSDetect::dirsFor('prefs'), 'log.conf'),
			'logtype' => 'server',
		}) unless Slim::Utils::Log->isInitialized();

		Slim::Utils::Log->setLogGroup($group, 1);

		Slim::Utils::Log->writeConfig();
	}
}

1;