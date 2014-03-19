package Slim::Utils::Prefs::Migration::ClientV4;

use strict;
use Slim::Utils::Prefs;

sub init {
	my ($class, $prefs) = @_;

	# migrate 'play other songs' pref from server to per-player
	$prefs->migrateClient( 4, sub {
		my ( $cprefs, $client ) = @_;
		my $playtrackalbum = preferences('server')->get('playtrackalbum');
	
		# copy server pref as a default client pref
		unless (defined $cprefs->get( 'playtrackalbum' )) {
			$cprefs->set( 'playtrackalbum', $playtrackalbum );
		}
		1;
	} );	
}

1;