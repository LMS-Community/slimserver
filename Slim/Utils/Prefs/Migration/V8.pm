package Slim::Utils::Prefs::Migration::V8;

use strict;

use base qw(Slim::Utils::Prefs::Migration);

sub migrate {
	my ($class, $prefs) = @_;
	
	# on Windows we don't provide a means to disable the autoprefs value any longer
	# disable automatic scanning automatically, in case user had been using an earlier beta where it was enabled
	$prefs->migrate( 8, sub {
		if (main::ISWINDOWS && $prefs->get('autorescan')) {
			$prefs->set( autorescan => 0 );
		}
		1;
	} );
}

1;
