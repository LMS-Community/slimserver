package Slim::Utils::Prefs::Migration::ClientV9;

use strict;

use Slim::Hardware::IR;

sub init {
	my ($class, $prefs) = @_;

	$prefs->migrateClient(9, sub {
		my $cprefs = shift;
		$cprefs->set('irmap' => Slim::Hardware::IR::defaultMapFile()) if $cprefs->get('irmap') =~ /SqueezeCenter/i;
		1;
	});
}

1;