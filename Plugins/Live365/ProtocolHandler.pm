# vim: foldmethod=marker
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

#  Plugins::Live365::ProtocolHandler

package Plugins::Live365::ProtocolHandler;

use strict;
use Slim::Utils::Misc qw( msg );
use Slim::Utils::Timers;
use Slim::Player::Playlist;
use Slim::Player::Source;
use base qw( Slim::Player::Protocols::HTTP );
use IO::Socket;
use XML::Simple;

# Need this to create a new API object
use Plugins::Live365::Live365API;

use vars qw( $VERSION );
$VERSION = 1.20;

# XXX: I don't believe new() is called at all when direct streaming
sub new {
	my $class = shift;
	my $args = shift;
	
	my $url = $args->{'url'};
	my $client = $args->{'client'};
	my $self = $args->{'self'};

	my $api = new Plugins::Live365::Live365API();

	if( my( $station, $handle ) = $url =~ m{live365://(www.live365.com/play/([^/?]+).*)$} ) {
		$::d_plugins && msg( "Live365.protocolHandler requested: $url ($handle)\n" );	

		my $realURL = $url;
		$realURL =~ s/live365\:/http\:/;

		$self = $class->SUPER::new({ 
				'url' => $realURL, 
				'client' => $client, 
				'infoUrl' => $url,
				'create' => 1,
			});

		if( $handle =~ /[a-zA-Z]/ ) {  # if our URL doesn't look like a handle, don't try to get a playlist
			my $isVIP = Slim::Utils::Prefs::get( 'plugin_live365_memberstatus' );
			Slim::Utils::Timers::setTimer(
				$client,
				Time::HiRes::time() + 5,
				\&getPlaylist,
				( $self, $handle, $url, $isVIP )
			);
		}
	} else {
		$::d_plugins && msg( "Not a Live365 station URL: $url\n" );
	}

	return $self;
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
	
	my( $station, $handle ) = $url =~ m{live365://(www.live365.com/play/([^/?]+).*)$};
	$::d_plugins && msg( "Live365.protocolHandler requested: $url ($handle)\n" );	

	# a fake $self for getPlaylist
	$self = IO::Socket->new;

	if( $handle =~ /[a-zA-Z]/ ) {  # if our URL doesn't look like a handle, don't try to get a playlist
		my $isVIP = Slim::Utils::Prefs::get( 'plugin_live365_memberstatus' );
		
		$::d_plugins && msg("Live365.protocolHandler: Setting getPlaylist timer\n");
		
		Slim::Utils::Timers::setTimer(
			$client,
			Time::HiRes::time() + 5,
			\&getPlaylist,
			( $self, $handle, $url, $isVIP )
		);
	}

	return $realURL;
}

sub getPlaylist {
	my ( $client, $self, $handle, $url, $isVIP ) = @_;

	return unless (defined($client));

	my $currentSong = Slim::Player::Playlist::url($client);
	my $currentMode = Slim::Player::Source::playmode($client);
	 
	return if ($currentSong !~ /^live365:/ || $currentMode ne 'play');

	# store the original title as a fallback, once.
	${*$self}{live365_original_title} ||= Slim::Music::Info::getCurrentTitle( $client, $currentSong );

	my $api = ${*$self}{live365_api};
	unless (defined($api)) {
		$api = new Plugins::Live365::Live365API();
		${*$self}{live365_api} = $api;
	}

	$api->GetLive365Playlist( $isVIP, $handle, \&playlistLoaded, {
		client => $client,
		self => $self,
		url => $url,
		handle => $handle,
		isVIP => $isVIP
	});
}

sub isAudioURL {
	my ( $class, $url ) = @_;
	
	if ( $url =~ m{^live365://www.live365.com/play/[^/?]+.*$} ) {
	    return 1;
	}
	
	return;
}

sub playlistLoaded {
	my ( $playlist, $args ) = @_;

	my $client = $args->{client};
	my $self = $args->{self};
	my $url = $args->{url};
	my $handle = $args->{handle};
	my $isVIP = $args->{isVIP};

	my $newTitle = '';
	my $nowPlaying;
	my $nextRefresh;

	if (defined($playlist)) {

		$::d_plugins && msg( "Got playlist response: $playlist\n" );

		$nowPlaying = eval { XMLin(\$playlist, ForceContent => 1, ForceArray => [ "PlaylistEntry" ]) };

		if ($@) {
			 errorMsg( "Live365 playlist didn't parse: '$@'\n" );
		}
	}

	if( defined $nowPlaying && defined $nowPlaying->{PlaylistEntry} && defined $nowPlaying->{Refresh} ) {

		$nextRefresh = $nowPlaying->{Refresh}->{content} || 60;
		my @titleComponents = ();
		if ($nowPlaying->{PlaylistEntry}->[0]->{Title}->{content}) {
			push @titleComponents, $nowPlaying->{PlaylistEntry}->[0]->{Title}->{content};
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
		$::d_plugins && msg( "Playlist handler returned an invalid response, falling back to the station title" );
		$newTitle = ${*$self}{live365_original_title};
	}

	if ( $newTitle and $newTitle ne Slim::Music::Info::getCurrentTitle( $client, Slim::Player::Playlist::url($client) ) ) {
		$::d_plugins && msg( "Live365 Now Playing: $newTitle\n" );
		$::d_plugins && msg( "Live365 next update: $nextRefresh seconds\n" );
		
		$client->killAnimation();
		Slim::Music::Info::setCurrentTitle( $url, $newTitle);
		
		#XXX Fixme $client->songDuration doesn't exist any more, need
		# a different way to set the time. perhaps changing setTitle above
		# to setInfo and accept an args hash.
		#$::d_plugins && msg( "Live365 setting songtime: $nextRefresh\n" );
		$client->remoteStreamStartTime(Time::HiRes::time());
		#$client->songduration($nextRefresh) if $nextRefresh;
	}

	my $currentSong = Slim::Player::Playlist::url($client);
	my $currentMode = Slim::Player::Source::playmode($client);
	 
	return if ($currentSong !~ /^live365:/ || $currentMode ne 'play');

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

	$::d_plugins && msg( ref($self) . " shutting down\n" );

	Slim::Utils::Timers::killTimers( ${*$self}{client}, \&getPlaylist )
		or $::d_plugins && msg( "Live365 failed to kill playlist job timer.\n" );

	my $api = ${*$self}{live365_api};
	if (defined($api)) {
		$api->stopLoading();
	}
}

1;

