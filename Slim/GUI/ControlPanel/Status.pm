# basically display Settings/Information from the web UI
package Slim::GUI::ControlPanel::Status;

use base 'Wx::Panel';

use Wx qw(:everything);
use Wx::Event qw(EVT_CHILD_FOCUS);
use Wx::Html;
use LWP::Simple;

use Slim::Utils::Light;

sub new {
	my ($self, $nb) = @_;
	
	$self = $self->SUPER::new($nb);
	
	$self->{loaded} = 0;

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


	EVT_CHILD_FOCUS($self, sub {
		my ($self, $event) = @_;

		my $child = $event->GetWindow();
		if ( $child && $child->isa('Wx::HtmlWindow') && !$self->{loaded} ) {
			$child->SetPage(
				get(Slim::GUI::ControlPanel::getBaseUrl() . '/EN/settings/server/status.html?simple=1') || string('CLEANUP_NO_STATUS')
			);
			$self->{loaded} = 1;
		}
		else {
			$self->{loaded} = 0;
		}

		$event->Skip();
	});

	return $self;
}

1;
