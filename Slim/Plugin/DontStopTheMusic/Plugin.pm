package Slim::Plugin::DontStopTheMusic::Plugin;

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

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(cstring);

use constant MIN_TRACKS_LEFT => 2;		# minimum number of tracks left before we add our own

my $prefs = preferences('plugin.dontstopthemusic');
my $serverprefs = preferences('server');

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.dontstopthemusic',
	'defaultLevel' => 'ERROR',
	'description'  => 'PLUGIN_DSTM',
});

use constant MENU => 'plugins/DontStopTheMusic/menu.html';
use constant ICON => 'plugins/DontStopTheMusic/html/images/icon.png';

my %handlers;

sub initPlugin {

	if ( main::WEBUI ) {
		require Slim::Plugin::DontStopTheMusic::Settings;
		Slim::Plugin::DontStopTheMusic::Settings->new;

		# add settings page to main menu, but set flag to use different layout
		Slim::Web::Pages->addPageFunction(qr/^\Q@{[MENU]}\E/, sub {
			my $params = $_[1];
			$params->{mainMenuItem} = 1;
			$params->{pageicon} = ICON;
			$params->{pageURL} = MENU;
			Slim::Plugin::DontStopTheMusic::Settings->handler(@_);
		});
		
		Slim::Web::Pages->addPageLinks('plugins', { 'PLUGIN_DSTM' => MENU });
		Slim::Web::Pages->addPageLinks('icons',   { 'PLUGIN_DSTM' => ICON });
	}

	# register a settings item. I don't like that, but we can't hook in to the mysb.com delivered menu.
	Slim::Control::Request::addDispatch(['dontstopthemusicsetting'],[1, 0, 1, \&dontStopTheMusicSetting]);
	
	Slim::Control::Jive::registerPluginMenu([{
		text    => 'PLUGIN_DSTM',
		id      => 'settingsDontStopTheMusic',
		node    => 'settings',
		window  => { 
			'icon-id' => ICON,
		},
		weight  => 1,
		actions => {
			go => {
				cmd => ['dontstopthemusicsetting'],
				player => 0
			},
		},
	}]);

	# listen to playlist change events so we know when our own playlist ends
	Slim::Control::Request::subscribe(\&onPlaylistChange, [['playlist'], ['cant_open', 'newsong', 'delete', 'resume']]);
	Slim::Control::Request::subscribe(\&registerFavorites, [['favorites'], ['changed']]);
}

sub postinitPlugin {
	registerFavorites();
}

sub registerHandler {
	my ($class, $id, $handler) = @_;
	$handlers{$id} = $handler;
}

sub getHandler {
	my ($class, $client) = @_;
	return unless $client;
	return $handlers{$prefs->client($client)->get('provider')};
}

sub getHandlers {
	return \%handlers;
}

sub dontStopTheMusicSetting {
	my $request = shift;
	my $client  = $request->client();

	my $provider = $prefs->client($client)->get('provider') || '';

	$request->addResult('offset', 0);

	$request->setResultLoopHash('item_loop', 0, {
		text => $client->string('DISABLED'),
		radio => $provider ? 0 : 1,
		actions => {
			do => {
				player => 0,
				cmd => [ 'playerpref', 'plugin.dontstopthemusic:provider', 0 ]
			},
		},
	});
	
	my $i = 1;
	
	foreach (sort {
		lc(getString($a, $client)) cmp lc(getString($b, $client));
	} keys %handlers) {
		$request->setResultLoopHash('item_loop', $i, {
			text => getString($_),
			radio => ($_ eq $provider) ? 1 : 0,
			actions => {
				do => {
					player => 0,
					cmd => [ 'playerpref', 'plugin.dontstopthemusic:provider', $_ ]
				},
			},
		});
		
		$i++;
	}
	
	$request->addResult('count', $i);
	$request->setStatusDone()
}

sub getString {
	my ($token, $client) = @_;
	return Slim::Utils::Strings::stringExists($token) 
			? cstring($client, $token) 
			: $token;
};

sub onPlaylistChange {
	my $request = shift;
	my $client  = $request->client();

	return if !defined $client;
	$client = $client->master;
	return if $request->source && $request->source eq __PACKAGE__;
	return if !$prefs->client($client)->get('provider');

	Slim::Utils::Timers::killTimers($client, \&dontStopTheMusic);

	# Spotify sometimes fails to load tracks and is skipping them without us getting the 'newsong' event
	if ( $request->isCommand( [['playlist'], ['cant_open']] ) ) {
		# return unless this is a "103: not available in your country" Spotify error
		return if $request->getParam('_url') !~ /^spotify/ || $request->getParam('_error') !~ /^103/;
	}

	# don't interfere with the automatically adding RandomPlay and SugarCube plugins
	# stop smart mixing when a new RandomPlay mode is started or SugarCube is at work
	if (
		( Slim::Utils::PluginManager->isEnabled('Slim::Plugin::RandomPlay::Plugin') && Slim::Plugin::RandomPlay::Plugin::active($client) )
		|| ( Slim::Utils::PluginManager->isEnabled('Plugins::SugarCube::Plugin') && preferences('plugin.SugarCube')->client($client)->get('sugarcube_status') )
	) {
		return;
	}

	my $songIndex = Slim::Player::Source::streamingSongIndex($client) || 0;
	
	if ( main::INFOLOG && $log->is_info ) {
		$log->info(sprintf("Received command %s", $request->getRequestString));
	}

	if ( $request->isCommand( [['playlist'], ['newsong', 'delete', 'cant_open']] ) ) {
		
		# create mix based on last few tracks if we near the end, repeat is off and neverStopTheMusic is set
		if ( !Slim::Player::Playlist::repeat($client) ) {
			
			# Delay start of the mix if we're called while we're playing one single track only.
			# We might be in the middle of adding new tracks.
			if ($songIndex == 0) {
				my $delay = (Slim::Player::Source::playingSongDuration($client) - Slim::Player::Source::songTime($client)) / 2;
				$delay = 0 if $delay < 0;
				Slim::Utils::Timers::setTimer($client, time + $delay, \&dontStopTheMusic);
			}
			else {
				dontStopTheMusic($client);
			}
			
		}
	} 
}

sub registerFavorites {
	if (my $favsObject = Slim::Utils::Favorites->new()) {
		foreach my $fav (@{$favsObject->all}) {
			__PACKAGE__->registerHandler($fav->{title}, sub {
				$_[1]->($_[0], [$fav->{url}]);
			});
		}
	}
}

sub dontStopTheMusic {
	my ($client) = @_;
	
	my $class = __PACKAGE__;
	
	my $songIndex = Slim::Player::Source::streamingSongIndex($client) || 0;
	my $songsRemaining = Slim::Player::Playlist::count($client) - $songIndex - 1;

	main::INFOLOG && $log->info("$songsRemaining songs remaining, songIndex = $songIndex");

	my $numTracks = $prefs->get('newtracks') || MIN_TRACKS_LEFT;
	
	if ($songsRemaining < $numTracks) {

		# don't continue if the last item in the queue is a radio station or similar
		if ( my $handler = Slim::Player::ProtocolHandlers->handlerForURL( $client->playingSong()->track->url ) ) {
			if ($handler->can('isRepeatingStream')) {
				return if $handler->isRepeatingStream($client->playingSong());
			}
		}
		
		my $playlist = Slim::Player::Playlist::playList($client);
		my $lastTrack = $playlist->[-1];

		my (undef, undef, $duration) = $class->getMixablePropertiesFromTrack($client, $lastTrack);
		
		if (!$duration) {
			main::INFOLOG && $log->is_info && $log->info("Found radio station last in the queue - don't start a mix.");
			return;
		}
		
		my $handler = $class->getHandler($client);
		
		$handler->( $client, sub {
			my ($client, $tracks) = @_;
			
			if ( $tracks && scalar @$tracks ) {
				
				if ( Slim::Player::Playlist::count($client) + scalar(@$tracks) > preferences('server')->get('maxPlaylistLength') ) {
					# Delete tracks before this one on the playlist
					for (my $i = 0; $i < scalar(@$tracks); $i++) {
						my $request = $client->execute(['playlist', 'delete', 0]);
						$request->source($class);
					}
				}
				
				# "playlist addtracks" can only handle single tracks, but not eg. playlists or db://... urls
				my $request = (scalar @$tracks == 1) 
					? $client->execute(['playlist', 'add', $tracks->[0] ]) 
					: $client->execute(['playlist', 'addtracks', 'listRef', $tracks ]);
				$request->source($class);
			}
			elsif ( $prefs->client($client)->get('provider') !~ /^PLUGIN_RANDOM/ && Slim::Utils::PluginManager->isEnabled('Slim::Plugin::RandomPlay::Plugin') ) {
				$log->warn("I'm sorry, we couldn't create any reasonable result with your current playlist. We'll just play something instead.");
				
				my $request = $client->execute(['playlist', 'addtracks', 'listRef', ['randomplay://track'] ]);
				$request->source($class);
			}
			elsif ( main::INFOLOG && $log->is_info ) {
				$log->info("No matching tracks found for current playlist!");
			}
		} ) if $handler;

	}
}

sub getMixableProperties {
	my ($class, $client, $count) = @_;
	
	return unless $client;

	my ($trackId, $artist, $title, $duration, $tracks);
	
	foreach (@{ Slim::Player::Playlist::playList($client) }) {
		($artist, $title, $duration, $trackId) = $class->getMixablePropertiesFromTrack($client, $_);
		
		next unless defined $artist && defined $title;

		push @$tracks, {
			id => $trackId,
			artist => $artist,
			title => $title
		};
	}

	if ($tracks && ref $tracks && scalar @$tracks && $duration) {
		main::INFOLOG && $log->info("Auto-mixing from random tracks in current playlist");

		# pick five random tracks from the playlist
		if ($count && scalar @$tracks > $count) {
			Slim::Player::Playlist::fischer_yates_shuffle($tracks);
			splice(@$tracks, $count);
		}
		
		return $tracks;
	}
	elsif (main::INFOLOG && $log->is_info) {
		if (!$duration) {
			$log->info("Found radio station last in the queue - don't start a mix.");
		}
		else {
			$log->info("No mixable items found in current playlist!");
		}
	}
	
	return;
}

sub getMixablePropertiesFromTrack {
	my ($class, $client, $track) = @_;
	
	return unless blessed $track;

	my $url    = $track->url;
	my $id     = $track->id;
	my $artist = $track->artistName;
	my $title  = $track->title;
	my $duration = $track->duration;
				
	# we might have to look up titles for remote sources
	if ( !($artist && $title && $duration) && $track && $track->remote && $url ) {
		my $handler = Slim::Player::ProtocolHandlers->handlerForURL($url);
		if ( $handler && $handler->can('getMetadataFor') ) {
			my $remoteMeta = $handler->getMetadataFor( $client, $url );
			$artist   ||= $remoteMeta->{artist};
			$title    ||= $remoteMeta->{title};
			$duration ||= $remoteMeta->{duration};
		}
	}
	
	return ($artist, $title, $duration, $id);
}


1;