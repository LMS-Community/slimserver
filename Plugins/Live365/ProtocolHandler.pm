# Live365 tuner plugin for Slim Devices SlimServer
# Copyright (C) 2004  Jim Knepley
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
#

# $Id$

package Plugins::Live365::ProtocolHandler;

use strict;
use base qw( Slim::Player::Protocols::HTTP );

use IO::Socket;
use XML::Simple;

use Slim::Player::Playlist;
use Slim::Player::Source;
use Slim::Utils::Cache;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Timers;

# Need this to create a new API object
use Plugins::Live365::Live365API;

my $log = logger('plugin.live365');

# XXX: I don't believe new() is called at all when direct streaming
sub new {
	my $class = shift;
	my $args  = shift;
	
	my $url    = $args->{'url'};
	my $client = $args->{'client'};
	my $self   = $args->{'self'};

	my $api = Plugins::Live365::Live365API->new;

	if (my ($station, $handle) = $url =~ m{live365://(www.live365.com/play/([^/?]+).*)$}) {

		$log->info("Requested: $url ($handle)");

		my $realURL = $url;
		$realURL =~ s/live365\:/http\:/;

		$self = $class->SUPER::new({ 
			'url'     => $realURL, 
			'client'  => $client, 
			'infoUrl' => $url,
			'create'  => 1,
		});

		# if our URL doesn't look like a handle, don't try to get a playlist
		if ($handle =~ /[a-zA-Z]/) {

			my $isVIP = Slim::Utils::Prefs::get( 'plugin_live365_memberstatus' );

			Slim::Utils::Timers::setTimer(
				$client,
				Time::HiRes::time() + 5,
				\&getPlaylist,
				( $self, $handle, $url, $isVIP )
			);
		}

	} else {

		$log->info("Not a Live365 station URL: $url");
	}

	return $self;
}

sub notifyOnRedirect {
	my ($self, $originalURL, $redirURL) = @_;
	
	# Live365 redirects like so:
	# http://www.live365.com/play/rocklandusa?sessionid=foo:bar ->
	# http://216.235.81.102:15072/play?membername=foo&session=...
	
	# Scanner calls this method with the new URL so we can cache it
	# for use in canDirectStream
	
	$log->debug("Caching redirect URL: $redirURL");
	
	Slim::Utils::Cache->new->set( "live365_$originalURL", $redirURL, '1 hour' );
}

sub canDirectStream {
	my ($self, $client, $url) = @_;

	if ($url !~ m{^live365://(www.live365.com/play/([^/?]+).*)$}) {
	    return undef;
	}

	my $realURL = $url;
	$realURL =~ s/live365\:/http\:/;
	
	if ( $client->playmode eq 'stop' ) {

		# playmode stop means we were called from S::P::Squeezebox to check if
		# direct streaming is supported, not to actually direct stream
		return 1;
	}
	
	my ($station, $handle) = $url =~ m{live365://(www.live365.com/play/([^/?]+).*)$};

	$log->debug("Requested: $url ($handle)");

	# a fake $self for getPlaylist
	$self = IO::Socket->new;

	# if our URL doesn't look like a handle, don't try to get a playlist
	if ($handle =~ /[a-zA-Z]/) {

		my $isVIP = Slim::Utils::Prefs::get( 'plugin_live365_memberstatus' );
		
		$log->debug("Setting getPlaylist timer.");
		
		Slim::Utils::Timers::setTimer(
			$client,
			Time::HiRes::time() + 5,
			\&getPlaylist,
			( $self, $handle, $url, $isVIP )
		);
	}
	
	# Get the real URL from cache
	if ( my $cachedURL = Slim::Utils::Cache->new->get( "live365_$url" ) ) {
		$realURL = $cachedURL;
	}

	return $realURL;
}

sub getPlaylist {
	my ($client, $self, $handle, $url, $isVIP) = @_;

	if (!defined $client) {
		return;
	}

	my $currentSong = Slim::Player::Playlist::url($client);
	my $currentMode = Slim::Player::Source::playmode($client);
	 
	if ($currentSong ne $url || $currentMode ne 'play') {
		return;
	}

	# store the original title as a fallback, once.
	${*$self}{live365_original_title} ||= Slim::Music::Info::getCurrentTitle( $client, $currentSong );

	my $api = ${*$self}{live365_api} ||= Plugins::Live365::Live365API->new;

	$api->GetLive365Playlist($isVIP, $handle, \&playlistLoaded, {
		client => $client,
		self   => $self,
		url    => $url,
		handle => $handle,
		isVIP  => $isVIP
	});
}

sub playlistLoaded {
	my ($playlist, $args) = @_;

	my $client = $args->{client};
	my $self   = $args->{self};
	my $url    = $args->{url};
	my $handle = $args->{handle};
	my $isVIP  = $args->{isVIP};

	my $newTitle = '';
	my $nowPlaying;
	my $nextRefresh;

	if (defined $playlist) {

		$log->info("Got playlist response: $playlist");

		$nowPlaying = eval { XMLin(\$playlist, ForceContent => 1, ForceArray => [ "PlaylistEntry" ]) };

		if ($@) {
			 logError("Live365 playlist didn't parse: '$@'");
		}
	}

	if( defined $nowPlaying && defined $nowPlaying->{PlaylistEntry} && defined $nowPlaying->{Refresh} ) {

		$nextRefresh = $nowPlaying->{Refresh}->{content} || 60;

		my @titleComponents = ();

		if ( my $title = $nowPlaying->{PlaylistEntry}->[0]->{Title}->{content} ) {

			if ( $title eq 'NONE' ) {
				# no title, it's probably an ad, so display the description
				push @titleComponents, $nowPlaying->{PlaylistEntry}->[0]->{desc}->{content};
			}
			else {
				push @titleComponents, $title;
			}
		}

		if ($nowPlaying->{PlaylistEntry}->[0]->{Artist}->{content}) {

			push @titleComponents, $nowPlaying->{PlaylistEntry}->[0]->{Artist}->{content};
		}

		if ($nowPlaying->{PlaylistEntry}->[0]->{Album}->{content}) {

			push @titleComponents, $nowPlaying->{PlaylistEntry}->[0]->{Album}->{content};
		}

		$newTitle = join(" - ", @titleComponents);
	}
	else {

		$log->warn("Warning: Playlist handler returned an invalid response, falling back to the station title");

		$newTitle = ${*$self}{live365_original_title};
	}

	if ( $newTitle and $newTitle ne Slim::Music::Info::getCurrentTitle( $client, Slim::Player::Playlist::url($client) ) ) {

		$log->info("Now Playing: $newTitle");
		$log->info("Next update: $nextRefresh seconds");
		
		$client->killAnimation();

		Slim::Music::Info::setCurrentTitle( $url, $newTitle);
		
		#XXX Fixme $client->songDuration doesn't exist any more, need
		# a different way to set the time. perhaps changing setTitle above
		# to setInfo and accept an args hash.
		#$$log->debug("Setting songtime: $nextRefresh");
		$client->remoteStreamStartTime(Time::HiRes::time());
		#$client->songduration($nextRefresh) if $nextRefresh;
	}

	my $currentSong = Slim::Player::Playlist::url($client);
	my $currentMode = Slim::Player::Source::playmode($client);
	 
	return if ($currentSong ne $url || $currentMode ne 'play');

	if ( $nextRefresh and $currentSong =~ /^live365:/ and $currentMode eq 'play' ) {

		Slim::Utils::Timers::setTimer(
			$client,
			Time::HiRes::time() + $nextRefresh,
			\&getPlaylist,
			( $self, $handle, $url, $isVIP )
		);
	}
}

sub DESTROY {
	my $self = shift;

	$log->info(ref($self) . " shutting down");

	Slim::Utils::Timers::killTimers( ${*$self}{client}, \&getPlaylist ) || do {

		logWarning("Live365 failed to kill playlist job timer.");
	};

	my $api = ${*$self}{live365_api};

	if (defined $api) {

		$api->stopLoading;
	}
}

1;
