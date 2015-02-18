package Slim::Utils::Prefs::Migration::V9;

use strict;

use base qw(Slim::Utils::Prefs::Migration);

sub migrate {
	my ($class, $prefs) = @_;
	
	# use new default values for dbhighmem, using more memory on x86 CPUs, Windows etc.
	# new features like the full text search are rather hungry, and today's boxes often have enough RAM
	$prefs->migrate( 9, sub {
		# don't change if it's already on more than the old default
		return 1 if $prefs->get('dbhighmem');
		
		$prefs->set( dbhighmem => Slim::Utils::OSDetect->getOS()->canDBHighMem() );

		1;
	} );
}

1;
