package Slim::Utils::Prefs::Migration::ClientV2;

use strict;

use Slim::Player::Player;

sub init {
	my ($class, $prefs) = @_;
	
	# migrate client prefs to version 2 - sync prefs changed
	$prefs->migrateClient(2, sub {
		my $cprefs = shift;
		my $defaults = $Slim::Player::Player::defaultPrefs;
		$cprefs->set( minSyncAdjust       => $defaults->{'minSyncAdjust'}      ) if (defined $cprefs->get('minSyncAdjust') && $cprefs->get('minSyncAdjust') < 1);
		$cprefs->set( packetLatency       => $defaults->{'packetLatency'}      ) if (defined $cprefs->get('packetLatency') && $cprefs->get('packetLatency') < 1);
		1;
	});
}

1;