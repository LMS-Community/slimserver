package Slim::GUI::ControlPanel::Music;

use base 'Wx::Panel';

use Wx qw(:everything);

sub new {
	my ($self, $nb, $parent) = @_;

	$self = $self->SUPER::new($nb);

	my $mainSizer = Wx::BoxSizer->new(wxVERTICAL);	
	
	# folder selectors
	$mainSizer->Add(Slim::GUI::ControlPanel::DirPicker->new($self, $parent, 'audiodir'), 0, wxEXPAND | wxALL, 10);
	$mainSizer->Add(Slim::GUI::ControlPanel::DirPicker->new($self, $parent, 'playlistdir'), 0, wxEXPAND | wxALL, 10);

	$self->SetSizer($mainSizer);
	
	return $self;
}

1;


package Slim::GUI::ControlPanel::DirPicker;

use base 'Wx::DirPickerCtrl';

use Wx qw(:everything);

use Slim::Utils::Light;
use Slim::Utils::OSDetect;
use Slim::Utils::ServiceManager;

sub new {
	my ($self, $page, $parent, $pref) = @_;

	$self = $self->SUPER::new(
		$page,
		-1,
		getPref($pref) || '',
		string('SETUP_PLAYLISTDIR'),
		wxDefaultPosition, wxDefaultSize, wxPB_USE_TEXTCTRL | wxDIRP_DIR_MUST_EXIST
	);

	$parent->addApplyHandler($self, sub {
		my $running = (shift == SC_STATE_RUNNING);

		my $path = $self->GetPath;
		if ($running && $path ne getPref($pref)) {
			$path =~ s/\\/\\\\/g if Slim::Utils::OSDetect->isWindows();
			Slim::GUI::ControlPanel->setPref($pref, $path);
		}
	});

	$parent->addStatusListener($self);

	return $self;
}

1;
