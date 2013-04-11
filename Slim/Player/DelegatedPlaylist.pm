package Slim::Player::DelegatedPlaylist;

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use Scalar::Util qw(blessed);
use JSON::XS::VersionOneAndTwo;

use Slim::Utils::Compress;
use Slim::Utils::Log;
use Slim::Utils::Prefs;

my $log = logger('player.playlist');
my $prefs = preferences('server');

#
# accessors for playlist information
#

sub new {
	my ($class, $client) = @_;
	my $self = {
	};
	
	bless $self, $class;
	return $self;
}


# $client
sub count {logBacktrace('Unexpected call');}

# $client
sub shuffleType {logBacktrace('Unexpected call');}

# $client, $index, $refresh, $useShuffled
sub song {logBacktrace('Unexpected call');}

# $client, $start, $end
sub songs {logBacktrace('Unexpected call');}

# Refresh track(s) in a client playlist from the database
# $client, $url
sub refreshTrack {logBacktrace('Unexpected call');}

# $client
sub url {logBacktrace('Unexpected call');}

# $client
sub shuffleList {logBacktrace('Unexpected call');}

# $client
sub playList {logBacktrace('Unexpected call');}

# $client, $tracksRef, $position, $jumpIndex, $request
sub addTracks {
	my ($self, $client, $tracksRef, $position, $jumpIndex, $request, $text, $icon, $callback) = @_;
	
	my $urlprefix = 'lms://' . $prefs->get('server_uuid') . '/music/';
	
	# Use $_ here to support perl's magic in-place replacement
	foreach (@$tracksRef) {
		next unless $_;
		
		if ( !blessed($_) ) {
			my $t = Slim::Schema->objectForUrl({'url' => $_, 'create' => 1, 'readTags' => 1,});
			if (defined $t) {
				$_ = $t;
			} else {
				$log->warn('Cannot get Track object for: ', $_);
			}
		}
	}
	
	my $tags = 'uoaltiqydrTIHYKgAcE';

	my $tracks = Slim::Control::Queries::getTagDataForTracks($request, $tags, $tracksRef);
	
	foreach (@$tracks) {
		my $id = delete $_->{'id'};
		
		if ($_->{'url'} =~ m|^file://|) {
			$_->{'url'} = $urlprefix . $id . '/download/file.' . $_->{'type'};
		}
		
		if (my $coverid = delete $_->{'coverid'}) {
			$_->{'coverurl'} = $urlprefix . $coverid . '/cover';
		}
	}
	
	my $cmd;
	if ($position == -1) {
		$cmd = 'inserttracks';
	} elsif ($position == -2) {
		$cmd = 'playtracks';
	} elsif ($position == -3) {
		$cmd = 'addtracks';
	} else {
		$cmd = 'addtracks';
		$log->warn('Unsupported playlist position: ', $position);
	}
	
	my @infoTags;
	push @infoTags, 'infoText:' . $text if $text;
	if ($icon) {
		if ($icon =~ /^https?:/) {
			push @infoTags, 'infoIcon:'. $icon;
		} elsif ($icon =~ /^[a-f0-9]+$/) {
			push @infoTags, 'infoIcon:'. $urlprefix . $icon . '/cover';
		}
	}
	
	my $playCommand = [ 'playlist', $cmd, 'dataRef', $tracks, undef, $jumpIndex, @infoTags ];
	
	my $json = to_json({
		  		id            => 1,
				method        => "slim.request",
				params        => [ $client->id, $playCommand ],
				client        => $client->id,
			});
	
	my $cb = sub {
		my ($http) = @_;
		
		my $error = $http->error;
		
		if (!$error) {
			my $res = eval { from_json( $http->content ) };
			$error = $res->{'error'} if $res;
		}
		
		$log->error("Problem sending playlist request to ", $http->url, ": $error") if $error;
		$callback->($error) if $callback;
	};
	
	my ($http, $url);
	
	if (my $server = $client->server()) {
		$url = 'http://' . $server . '/jsonrpc.js';
	}

	# Find server for player
	elsif (my $player = Slim::Networking::Discovery::Players::getPlayerList()->{$client->id}) {
		$url = Slim::Networking::Discovery::Server::getWebHostAddress($player->{server}) . 'jsonrpc.js';
	}
	
	# Otherwise assume player is on SN - XXX should get this data from request
	else {
		$http = Slim::Networking::SqueezeNetwork->new(
			$cb,
			$cb,
		);
		$url = $http->url('/jsonrpc.js');
	}
	
	$http ||= Slim::Networking::SimpleAsyncHTTP->new(
		$cb,
		$cb,
		{ timeout => 10, client => $client }
	);
	
	main::INFOLOG && $log->info("Sending playlist to ", $url);
	
	$request->setStatusProcessing() if $request;

	# Always gzip this data, we know SN can handle it
	my $output = '';
	if ( Slim::Utils::Compress::gzip( { in => \$json, out => \$output } ) ) {
		$http->post(
			$url,
			'X-UEML-Auth'      => $client->authenticator,
			'Content-Encoding' => 'gzip',
			$output,
		);
	}
	else {
		$http->post(
			$url,
			'X-UEML-Auth' => $client->authenticator,
			$json,
		);
	}
}

# $client, $shuffle
sub shuffle {0;}

# $client, $dontpreservecurrsong
sub reshuffle {}

# $client, $repeat
sub repeat {0;}

# $toClient, $fromClient, $noQueueReset
sub copyPlaylist {logBacktrace('Unexpected call');}

# $client, $tracknum, $nTracks
sub removeTrack {logBacktrace('Unexpected call');}

# $client, $tracks
sub removeMultipleTracks {logBacktrace('Expected call - unimplemented');}

# $client, $index
sub refreshPlaylist {}

# $client, $src, $dest, $size
sub moveSong {logBacktrace('Unexpected call');}

# $client
sub stopAndClear {}

# $client, $playlistObj
sub scheduleWriteOfPlaylist {logBacktrace('Unexpected call');}

# restore the old playlist if we aren't already synced with somebody (that has a playlist)
# $client, $callback
sub loadClientPlaylist {logBacktrace('Unexpected call');}

# $request
sub newSongPlaylistCallback {logBacktrace('Unexpected call');}

# $playlistObj
sub removePlaylistFromDisk {logBacktrace('Unexpected call');}

# $request
sub modifyPlaylistCallback {logBacktrace('Unexpected call');}


1;
