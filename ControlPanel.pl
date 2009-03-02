#!/usr/bin/wxPerl

use Wx;

package TabbedPanel;

use strict;
use Wx qw(:everything);

use base 'Wx::PropertySheetDialog';

sub new {
	my $ref = shift;
	my $self = $ref->SUPER::new(
		undef,
		-1,
		'Control Panel',
		[-1, -1],
		[500, 280],
		wxMINIMIZE_BOX | wxCAPTION | wxCLOSE_BOX | wxSYSTEM_MENU | wxRESIZE_BORDER,
		'Control Panel',
	);

	$self->CreateButtons(wxOK|wxCANCEL);
	
	return $self;
}

package ControlPanel;

use strict;
use Wx qw(:everything);

use base 'Wx::App';

sub OnInit {
	my $frame = TabbedPanel->new();
	
	$frame->Show(1);	
}



package main;

my $app = ControlPanel->new;
$app->MainLoop;