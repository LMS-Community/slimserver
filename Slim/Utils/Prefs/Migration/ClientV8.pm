package Slim::Utils::Prefs::Migration::ClientV8;

use strict;

sub init {
	my ($class, $prefs) = @_;

	# Add Music Stores menu item after Music Services
	$prefs->migrateClient( 8, sub {
		my ( $cprefs, $client ) = @_;
		my $menuItem = $cprefs->get('menuItem');
		
		# Ignore if MUSIC_STORES is already present
		return 1 if grep /MUSIC_STORES/, @{$menuItem};
		
		my $done = 0;
		my $i = 0;
		for my $item ( @{$menuItem} ) {
			$i++;
			if ( $item eq 'MUSIC_SERVICES' ) {
				splice @{$menuItem}, $i, 0, 'MUSIC_STORES';
				$done = 1;
				last;
			}
		}
		
		if ( !$done ) {
			# Just add the item at the end
			push @{$menuItem}, 'MUSIC_STORES';
		}
	
		$cprefs->set( menuItem => $menuItem );
		
		1;
	} );
}

1;