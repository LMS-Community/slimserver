package Slim::Plugin::SN::ProtocolHandler;

# $Id

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

use strict;

use Time::HiRes;

use JSON::XS::VersionOneAndTwo;
use Slim::Utils::Timers;
use Slim::Utils::Log;

my $log = logger('plugin.sn');

sub overridePlayback {
	my ( $class, $client, $url ) = @_;

	main::INFOLOG && $log->info($client->id);

	if ($client->isPlaying('really')) {
		# wait until playout is complete - we will get called again then
		main::DEBUGLOG && $log->debug('Waiting for playout to complete');
		return 1;
	}
	
	my @players = $client->syncGroupActiveMembers();
	my @playerIds = map($_->id, @players);
	
	# Show-briefly to each player saying is being switched
	my $line = $client->string('SQUEEZENETWORK_CONNECTING');
	foreach (@players) {
		$_->showBriefly( {
			line => [ $line ],
			jive => { type => 'popupplay', text => [ $line ]},
		}, {
			scroll    => 1,
			firstline => 1,
			block     => 1,
		} );
	}
	
	# If we have a multi-item playlist, then copy as much over as possible
	my ($playlist, $index);
	my $count = Slim::Player::Playlist::count($client);
	if ($count > 1) {
		my $shufflelist = Slim::Player::Playlist::shuffleList($client);
		my $oldplaylist = Slim::Player::Playlist::playList($client);
		my $ix          = $client->streamingSong()->index();
		my @tracks;
		
		for (my $i = 0; $i < $count; $i++) {
			my $objectOrUrl = defined $shufflelist->[$i]
				? $oldplaylist->[$shufflelist->[$i]]
				: $oldplaylist->[$i];
			if (my $itemUrl = Slim::Plugin::SN::Plugin::filterTrack($objectOrUrl)) {
				push @tracks, $itemUrl;
			} else {
				if (@tracks < $ix) {
					$ix--;
				}
			}
		}
		
		if (!@tracks > 1 || $ix < 0 || $ix >= @tracks) {
			# Something silly here
			main::INFOLOG && $ix < 0 && $log->info("Filtered track list invalid: index=$ix");
		} else {
			$playlist = \@tracks;
			$index = $ix;
			main::INFOLOG && $log->is_info && $log->info("play track index $index of ", scalar @tracks);
		}
	}
	
	# Give various notifications the chance to fire.
	Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + 0.3, 
		sub {shift->execute(["connect", Slim::Networking::SqueezeNetwork->get_server('sn')]);}
	);
	
	# We don't need to poke S::N::SN::Players->fetch_players() because it will automatically 
	# fetch the up-to-date list after a few seconds when it sees the 'client forget'
	# from the above command.
	Slim::Utils::Timers::setTimer(undef, Time::HiRes::time() + 3, \&_checkAndPlay, {
		playerIds  => \@playerIds,
		retryCount => 0,
		url        => $url,
		playlist   => $playlist,
		index      => $index,
	});

	return 1;
}

use constant RETRY_LIMIT => 10;

sub _checkAndPlay {
	my $args = $_[1];
	
	my @snPlayers = Slim::Networking::SqueezeNetwork::Players->get_players();

	main::DEBUGLOG && $log->is_debug && $log->debug(Data::Dump::dump($args));
	
	my $foundPlayer = undef;
	my $foundPlayers = 0;
	foreach my $id (@{$args->{'playerIds'}}) {
		if (grep {$id eq $_->{'mac'}} @snPlayers) {
			$foundPlayer = $id;
			$foundPlayers++;
		}
	}
	
	if ($foundPlayers < scalar @{$args->{'playerIds'}}) {
		if ($args->{'retryCount'}++ > RETRY_LIMIT) {
			$log->warn("At least one player did not yet make it to mysqueezebox.com");
			# give up waiting
		} else {
			Slim::Networking::SqueezeNetwork::Players->fetch_players();
			Slim::Utils::Timers::setTimer(undef, Time::HiRes::time() + 1, \&_checkAndPlay, $args);
			return;
		}
	}	
	
	if ($foundPlayer) {	# at least one player made it
		my $http = Slim::Networking::SqueezeNetwork->new(
			\&_checkResult,
			\&_error,
		);
		my $playCommand = defined $args->{'playlist'}
			? [ 'playlist', 'playtracks', 'listref', $args->{'playlist'}, undef, $args->{'index'} ]
			: [ 'playlist', 'play', $args->{'url'} ];
		$http->post( $http->url( '/jsonrpc.js' ), 
			to_json({
		  		id => 1,
				method => "slim.request",
				params => [ $foundPlayer, $playCommand ],
			})
		);
	} else {
		$log->error('no players made it to mysqueezebox.com: ', join(', ', @{$args->{'playerIds'}}));
	}
}

sub _checkResult {
	my $http = shift;

	my $res = eval { from_json( $http->content ) };

	if ( $@ || ref $res ne 'HASH' || $res->{error} ) {
		$http->error( $@ || (ref $res eq 'HASH' ? $res->{error} : ('Invalid JSON response: ' . $http->content)) );
		_error( $http );
		return 0;
	} else {
		return 1;
	}
}

sub _error {
	my $http  = shift;
	my $error = $http->error;
	
	main::DEBUGLOG && $log->is_debug && $log->debug($error, ': ', Data::Dump::dump($http));
}

sub canDirectStream { return $_[2]; }

sub isRemote { 1 }

1;
