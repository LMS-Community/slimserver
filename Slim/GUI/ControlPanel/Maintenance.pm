package Slim::GUI::ControlPanel::Maintenance;

use base 'Wx::Panel';

use Wx qw(:everything);
use Wx::Event qw(EVT_BUTTON);

use Slim::Utils::Light;
use Slim::Utils::ServiceManager;

my %checkboxes;

sub new {
	my ($self, $nb, $parent, $args) = @_;

	$self = $self->SUPER::new($nb);
	$self->{args} = $args;

	my $mainSizer = Wx::BoxSizer->new(wxVERTICAL);
	
	$mainSizer->Add(Wx::StaticText->new($self, -1, string('CLEANUP_DESC')), 0, wxALL, 5);

	my $cbSizer = Wx::BoxSizer->new(wxVERTICAL);

	foreach (@{ $args->{options} }) {
		$checkboxes{$_->{name}} = Wx::CheckBox->new( $self, -1, $_->{title}, $_->{position});
		$cbSizer->Add( $checkboxes{$_->{name}}, 0, wxTOP | wxGROW, $_->{margin} || 5 );
	}

	$mainSizer->Add($cbSizer, 1, wxALL, 5);

	my $hint = Wx::StaticText->new($self, -1, string('CLEANUP_PLEASE_STOP_SC'));
	$parent->addStatusListener($hint);
	$mainSizer->Add($hint, 0, wxALL, 5);

	my $btnsizer = Wx::StdDialogButtonSizer->new();

	my $btnCleanup = Wx::Button->new( $self, -1, string('CLEANUP_DO') );
	EVT_BUTTON( $self, $btnCleanup, \&doCleanup );
	
	$parent->addStatusListener($btnCleanup, sub {
		$btnCleanup->Enable($_[0] != SC_STATE_RUNNING && $_[0] != SC_STATE_STARTING);
	});

	$btnsizer->SetAffirmativeButton($btnCleanup);
	
	$btnsizer->Realize();

	$mainSizer->Add($btnsizer, 0, wxALIGN_BOTTOM | wxALL | wxALIGN_RIGHT, 10);
	
	$self->SetSizer($mainSizer);

	return $self;
}

sub doCleanup {
	my( $self, $event ) = @_;
	
	my $svcMgr = Slim::Utils::ServiceManager->new();
		
	my $params = {};
	my $selected = 0;
		
	foreach (@{ $self->{args}->{options} }) {
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