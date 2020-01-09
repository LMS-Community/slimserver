package Slim::Buttons::TrackInfo;

# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

# Displays the extra track information screen that is got into by pressing right on an item 
# in the now playing screen.

=head1 NAME

Slim::Buttons::TrackInfo

=head1 DESCRIPTION

L<Slim::Buttons::TrackInfo> is a module to handle the player UI for 
a list of information about a track in the local library.

=cut

use strict;
use Scalar::Util qw(blessed);

use Slim::Buttons::Common;
use Slim::Buttons::Playlist;
use Slim::Menu::TrackInfo;
use Slim::Utils::Log;
use Slim::Utils::Favorites;

our %functions = ();

# button functions for track info screens
sub init {

	Slim::Buttons::Common::addMode('trackinfo', undef, \&setMode);
	
	%functions = (

		'play' => sub  {
			my $client = shift;
			my $button = shift;
			my $addOrInsert = shift;

			playOrAdd($client,$addOrInsert);
		},
	);
}

sub setMode {
	my $client = shift;
	my $method = shift;

	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}
	
	my $track = $client->modeParam('track');
	my $url   = blessed($track) ? $track->url : $track;
	
	my $getMenu = sub {
		my ( $client, $callback ) = @_;
		
		my $menu = Slim::Menu::TrackInfo->menu( $client, $url, $track );
		
		if ( $callback ) {
			# Callback is used during a menu refresh
			# Will not work if URL is returned instead of OPML
			$callback->( $menu );
		}
		else {
			return $menu;
		}
	};
	
	my %params = (
		modeName  => 'TrackInfo',
		onRefresh => $getMenu,
		timeout   => 35,
	);
	
	my $feed = $getMenu->( $client );
	$params{ref $feed eq 'HASH' ? 'opml' : 'url'} = $feed;
	
	Slim::Buttons::Common::pushMode( $client, 'xmlbrowser', \%params );
	
	$client->modeParam( 'handledTransition', 1 );
}

=head1 SEE ALSO

L<Slim::Buttons::Common>

=cut

1;

__END__
