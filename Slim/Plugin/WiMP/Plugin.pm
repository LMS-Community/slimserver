package Slim::Plugin::WiMP::Plugin;

# Logitech Media Server Copyright 2003-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Plugin::OPMLBased);
use URI::Escape qw(uri_escape_utf8);

use Slim::Utils::Strings qw(cstring);

use Slim::Plugin::WiMP::ProtocolHandler;

my $log = Slim::Utils::Log->addLogCategory( {
	category     => 'plugin.tidal',
	defaultLevel => 'ERROR',
	description  => 'PLUGIN_WIMP_MODULE_NAME',
} );

sub initPlugin {
	my $class = shift;

	Slim::Player::ProtocolHandlers->registerHandler(
		wimp => 'Slim::Plugin::WiMP::ProtocolHandler'
	);

	Slim::Player::ProtocolHandlers->registerIconHandler(
		qr/mysqueezebox\.com.*\/wimp\//,
		sub { return $class->_pluginDataFor('icon'); }
	);

	$class->SUPER::initPlugin(
		feed   => Slim::Networking::SqueezeNetwork->url( '/api/wimp/v1/opml' ),
		tag    => 'wimp',
		menu   => 'music_services',
		weight => 35,
		is_app => 1,
	);

	# Track Info item
	Slim::Menu::TrackInfo->registerInfoProvider( wimp => (
		after => 'middle',
		func  => \&trackInfoMenu,
	) );

	if ( main::WEBUI ) {
		# Add a function to view trackinfo in the web
		Slim::Web::Pages->addPageFunction(
			'plugins/wimp/trackinfo.html',
			sub {
				my $client = $_[0];
				my $params = $_[1] || {};

				my $url;

				my $id = $params->{sess} || $params->{item};

				if ( $id ) {
					# The user clicked on a different URL than is currently playing
					if ( my $track = Slim::Schema->find( Track => $id ) ) {
						$url = $track->url;
					}

					# Pass-through track ID as sess param
					$params->{sess} = $id;
				}
				else {
					$url = Slim::Player::Playlist::url($client);
				}

				Slim::Web::XMLBrowser->handleWebIndex( {
					client  => $client,
					feed    => Slim::Plugin::WiMP::ProtocolHandler->trackInfoURL( $client, $url ),
					path    => 'plugins/wimp/trackinfo.html',
					title   => 'TIDAL Track Info',
					timeout => 35,
					args    => \@_
				} );
			},
		);
	}
}

sub postinitPlugin {
	my $class = shift;

	if ( Slim::Utils::PluginManager->isEnabled('Slim::Plugin::OnlineLibrary::Plugin') ) {
		require Slim::Plugin::WiMP::API;
		Slim::Plugin::OnlineLibrary::Plugin->addLibraryIconProvider('wimp', '/plugins/WiMP/html/images/tidal.png');

		Slim::Plugin::OnlineLibrary::BrowseArtist->registerBrowseArtistItem( tidal => sub {
			my ( $client ) = @_;

			return {
				name => cstring($client, 'BROWSE_ON_SERVICE', 'TIDAL'),
				type => 'link',
				icon => $class->_pluginDataFor('icon'),
				url  => \&browseArtistMenu,
			};
		} );
	}
}

sub browseArtistMenu {
	my ($client, $cb, $params, $args) = @_;

	my $items = [];

	my $artistId = $params->{artist_id} || $args->{artist_id};
	if ( defined($artistId) && $artistId =~ /^\d+$/ && (my $artistObj = Slim::Schema->resultset("Contributor")->find($artistId))) {
		my $searchParams = {
			name => $artistObj->name
		};

		if (my ($extId) = grep /wimp:artist:(\d+)/, @{$artistObj->extIds}) {
			my ($id) = $extId =~ /wimp:artist:(\d+)/;
			$searchParams->{id} = $id;
		}

		Slim::Plugin::WiMP::API->getArtistMenu($client, $searchParams, sub {
			my $result = shift || [];
			
			my $transform = sub {
				return [ map { {
					name => $_->{text},
					url  => $_->{URL}
				} } @{$_[0] || []} ]
			};
			
			my $items = [];
			if (scalar @$result == 1) {
				$items = $transform->($result->[0]->{outline});
			}
			else {
				$items = [ grep {
					Slim::Utils::Text::ignoreCase($_->{text} ) eq $artistObj->namesearch
				} @$result ];

				if (scalar @$result == 1) {
					$items = $transform->($items);
				}
				elsif (scalar @$items < 1) {
					$items = [ map { {
						name => $_->{text},
						image => $_->{image},
						items => $transform->($_->{outline}),
					} } @$result ];
				}
				else {
					$items = [ map { {
						name => $_->{text},
						image => $_->{image},
						items => $transform->($_->{outline}),
					} } @$items ];
				}
			}

			$cb->($items);
		});

		return;
	}

	$cb->([{
		type  => 'text',
		title => cstring($client, 'EMPTY'),
	}]);
}

sub onlineLibraryNeedsUpdate {
	my $class = shift;
	require Slim::Plugin::WiMP::Importer;
	return Slim::Plugin::WiMP::Importer->needsUpdate(@_);
}

sub trackInfoMenu {
	my ( $client, $url, $track, $remoteMeta ) = @_;

	return unless $client;

	# Only show if in the app list
	return unless $client->isAppEnabled('wimp');

	my $artist = $track->remote ? $remoteMeta->{artist} : $track->artistName;
	my $album  = $track->remote ? $remoteMeta->{album}  : ( $track->album ? $track->album->name : undef );
	my $title  = $track->remote ? $remoteMeta->{title}  : $track->title;

	if ( $artist || $album || $title ) {

		my $snURL = Slim::Networking::SqueezeNetwork->url(
			'/api/wimp/v1/opml/context?artist=' . uri_escape_utf8($artist)
			. '&album=' . uri_escape_utf8($album)
			. '&track='	. uri_escape_utf8($title)
		);

		return {
			type      => 'link',
			name      => $client->string('PLUGIN_WIMP_ON_WIMP'),
			url       => $snURL,
			favorites => 0,
		};
	}
}

sub getDisplayName {
	return 'PLUGIN_WIMP_MODULE_NAME';
}

# Don't add this item to any menu
sub playerMenu { }

1;
