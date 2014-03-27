package Slim::Utils::Prefs::Migration::ClientV10;

use strict;

use Slim::Music::Info;
use Slim::Utils::Favorites;

sub init {
	my ($class, $prefs) = @_;
	
	# Bug 13248, migrate global presets to per-player presets
	# Note this has a bug and does not migrate presets that defaulted from favorites
	# That is handled below in #12
	$prefs->migrateClient( 10, sub {
		my ( $cprefs, $client ) = @_;

		if ( Slim::Utils::Favorites->enabled ) {
			my $fav = Slim::Utils::Favorites->new($client);

			my $uuid    = $prefs->get('server_uuid');
			my $presets = [];

			for my $hotkey ( @{ $fav->hotkeys } ) {
				my $preset;
				if ( $hotkey->{used} ) {
					my $item = $fav->entry( $hotkey->{index} );

					my $isRemote = Slim::Music::Info::isRemoteURL( $item->{URL} );

					$preset = {
						URL    => $item->{URL},
						text   => $item->{text},
						type   => $item->{type},
						server => $isRemote ? undef : $uuid,
					};
					$preset->{parser} = $item->{parser} if $item->{parser};
				}
				push @{$presets}, $preset;
			}
			$prefs->client($client)->set( presets => $presets );
		}
		
		1;
	} );
	
}

1;