
package SFrame;

use strict;
use base 'Wx::Frame';
use Wx qw(:everything);
use Wx::Event qw(EVT_BUTTON);


sub new {
	my $ref = shift;
	my $args = shift;

	my $self = $ref->SUPER::new(
		undef,
		-1,
		$args->{title},
		[50, 50],
		[500, 280],
		Wx::wxMINIMIZE_BOX | Wx::wxCAPTION | Wx::wxCLOSE_BOX,
		$args->{title},
	);

	my $panel = Wx::Panel->new( 
		$self, 
		-1, 
	);

	my $mainSizer = Wx::BoxSizer->new(Wx::wxVERTICAL);
	my $cbSizer = Wx::BoxSizer->new(Wx::wxVERTICAL);
	my %checkboxes;
	my $options = $args->{options};

	foreach (@$options) {
		$checkboxes{$_->{name}} = Wx::CheckBox->new( $panel, -1, $_->{title}, $_->{position}, [-1, -1]);
		$cbSizer->Add( $checkboxes{$_->{name}}, 0, Wx::wxTOP, $_->{margin} || 5 );
	}

	$mainSizer->Add($cbSizer, 0, Wx::wxALL, 15);


	my $btnsizer = Wx::StdDialogButtonSizer->new();

	my $btnCleanup = Wx::Button->new( $panel, -1, $args->{cleanup} );
	EVT_BUTTON( $self, $btnCleanup, \&OnClick );
	$btnsizer->SetAffirmativeButton($btnCleanup);
	
	my $btnCancel = Wx::Button->new( $panel, -1, $args->{cancel} );
	EVT_BUTTON( $self, $btnCancel, sub {
		$self->Destroy();
	} );
	$btnsizer->SetCancelButton($btnCancel);

	$btnsizer->Realize();

	$mainSizer->Add($btnsizer, 0, Wx::wxALIGN_BOTTOM | Wx::wxALL | Wx::wxALIGN_RIGHT, 20);
	
	$panel->SetSizer($mainSizer);

	return $self;
}

sub OnClick {
	my( $self, $event ) = @_;

	$self->SetTitle( 'Clicked' );
}


package Slim::Utils::CleanupGUI;

use base 'Wx::App';

my $args;

sub new {
	my $self = shift;
	$args = shift;

	$self->SUPER::new();
}

sub OnInit {
	my $frame = SFrame->new($args);
	$frame->Show( 1 );
}

1;