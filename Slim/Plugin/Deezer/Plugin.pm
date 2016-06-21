package Slim::Plugin::Deezer::Plugin;

# Logitech Media Server Copyright 2001-2016 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

use strict;
use base qw(Slim::Plugin::OPMLBased);

use JSON::XS::VersionOneAndTwo;
use URI::Escape qw(uri_escape_utf8);

use Slim::Plugin::Deezer::ProtocolHandler;

my $log = Slim::Utils::Log->addLogCategory( {
	category     => 'plugin.deezer',
	defaultLevel => 'ERROR',
	description  => 'PLUGIN_DEEZER_MODULE_NAME',
} );

sub initPlugin {
	my $class = shift;
	
	Slim::Player::ProtocolHandlers->registerHandler(
		deezer => 'Slim::Plugin::Deezer::ProtocolHandler'
	);

	$class->SUPER::initPlugin(
		feed   => Slim::Networking::SqueezeNetwork->url( '/api/deezer/v1/opml' ),
		tag    => 'deezer',
		menu   => 'music_services',
		weight => 35,
		is_app => 1,
	);
	
	if ( main::WEBUI ) {
		# Add a function to view trackinfo in the web
		Slim::Web::Pages->addPageFunction( 
			'plugins/deezer/trackinfo.html',
			sub {
				my $client = $_[0];
				my $params = $_[1];
				
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
					feed    => Slim::Plugin::Deezer::ProtocolHandler->trackInfoURL( $client, $url ),
					path    => 'plugins/deezer/trackinfo.html',
					title   => 'Deezer Track Info',
					timeout => 35,
					args    => \@_
				} );
			},
		);
	}
}

sub postinitPlugin {
	my $class = shift;
	
	# if user has the Don't Stop The Music plugin enabled, register ourselves
	if ( Slim::Utils::PluginManager->isEnabled('Slim::Plugin::DontStopTheMusic::Plugin') ) {
		Slim::Plugin::DontStopTheMusic::Plugin->registerHandler('PLUGIN_DEEZER_SMART_RADIO', sub {
			my ($client, $cb) = @_;
		
			my $seedTracks = Slim::Plugin::DontStopTheMusic::Plugin->getMixableProperties($client, 50);
		
			# don't seed from radio stations - only do if we're playing from some track based source
			if ($seedTracks && ref $seedTracks && scalar @$seedTracks) {
				main::INFOLOG && $log->info("Creating Deezer Smart Radio from random items in current playlist");
				
				# get the most frequent artist in our list
				my %artists;
				
				foreach (@$seedTracks) {
					$artists{$_->{artist}}++;
				}
				
				# split "feat." etc. artists
				my @artists;
				foreach (keys %artists) {
					if ( my ($a1, $a2) = split(/\s*(?:\&|and|feat\S*)\s*/i, $_) ) {
						push @artists, $a1, $a2;
					}
				} 
				
				unshift @artists, sort { $artists{$b} <=> $artists{$a} } keys %artists;
				
				dontStopTheMusic($client, $cb, @artists);
			}
			else {
				$cb->($client);
			}
		});

		Slim::Plugin::DontStopTheMusic::Plugin->registerHandler('PLUGIN_DEEZER_FLOW', sub {
			$_[1]->($_[0], ['deezer://flow.dzr']);
		});
	}
}

sub dontStopTheMusic {
	my $client  = shift;
	my $cb      = shift;
	my $nextArtist = shift;
	my @artists = @_;
	
	if ($nextArtist) {
		Slim::Networking::SqueezeNetwork->new(
			sub {
				my $http = shift;
				my $client = $http->params->{client};
				my $artistRE = $http->params->{artistRE};

				my $content = eval { from_json( $http->content ) };
				my @tracks;

				if ( $@ || ($content && $content->{error}) ) {
					if ( main::DEBUGLOG && $log->is_debug ) {
						$log->debug( 'Smart Mix failed: ' . ($@ || $content->{error}) );
					}
					$http->error( $@ || $content->{error} );

					dontStopTheMusic($client, $http->params->{cb}, @{$http->params->{artists}});
				}
				elsif ( $content && ref $content && $content->{body} && (my $items = $content->{body}->{outline}) ) {
					push @tracks, $items->[0]->{URL} if scalar @$items;
				}
				
				if (scalar @tracks) {
					$cb->($client, \@tracks);
				}
				else {
					dontStopTheMusic($client, $http->params->{cb}, @{$http->params->{artists}});
				}
			},
			sub {
				my $http = shift;
				my $client = $http->params->{client};

				if ( main::DEBUGLOG && $log->is_debug ) {
					$log->debug( 'Smart Mix failed: ' . $http->error );
				}
				
				if (scalar @{$http->params->{artists}}) {
					dontStopTheMusic($client, $http->params->{cb}, @{$http->params->{artists}});
				}
				else {
					$http->params->{cb}->($client);
				}
			},
			{
				client  => $client,
				artists => \@artists,
				artistRE=> qr/^$nextArtist/i,
				cb      => $cb,
				timeout => 15,
			},
		)->get( Slim::Networking::SqueezeNetwork->url( '/api/deezer/v1/opml/smart_radio?q=' . uri_escape_utf8($nextArtist) ) );
	}
	else {
		main::INFOLOG && $log->is_info && $log->info("No matching Smart Radio found for current playlist!");
		$cb->($client);
	}
}

sub getDisplayName {
	return 'PLUGIN_DEEZER_MODULE_NAME';
}

# Don't add this item to any menu
sub playerMenu { }

1;
