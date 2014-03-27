package Slim::Utils::Prefs::Migration::ClientV12;

use strict;

use Slim::Music::Info;
use Slim::Utils::Favorites;

sub init {
	my ($class, $prefs) = @_;
	
	# Bug 14406, fill out missing presets from favorites, if necessary
	$prefs->migrateClient( 12, sub {
		my ( $cprefs, $client ) = @_;
		
		if ( Slim::Utils::Favorites->enabled ) {
			my $fav = Slim::Utils::Favorites->new($client);

			my $uuid    = $prefs->get('server_uuid');
			my $presets = $cprefs->get('presets') || [];
			
			my $index = 0;
			for my $preset ( @{$presets} ) {
				if ( !$preset ) {
					# Fill in empty preset slot from favorites
					my $item = $fav->entry( $index );
					if ( $item && $item->{URL} ) {
						my $isRemote = Slim::Music::Info::isRemoteURL( $item->{URL} );

						$preset = {
							URL    => $item->{URL},
							text   => $item->{text},
							type   => $item->{type},
							server => $isRemote ? undef : $uuid,
						};
						$preset->{parser} = $item->{parser} if $item->{parser};
					}
				}
				$index++;
			}
			
			$cprefs->set( presets => $presets );
		}
		
		1;
	} );
	
}

1;