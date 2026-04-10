package Slim::Plugin::AudioAddict::Plugin;

# Logitech Media Server Copyright 2001-2024 Logitech.
# Lyrion Music Server Copyright 2024 Lyrion Community.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use base qw(Slim::Plugin::OPMLBased);
use File::Spec::Functions qw(catfile);

use Slim::Plugin::AudioAddict::API;
use Slim::Formats::RemoteMetadata;
use Slim::Utils::Prefs;

use constant BACKOFF_BASE => 2.5;

our $pluginDir;
BEGIN {
	$pluginDir = $INC{"Slim/Plugin/AudioAddict/Plugin.pm"};
	$pluginDir =~ s/Plugin.pm$//;
}

my $log = Slim::Utils::Log->addLogCategory( {
	category     => 'plugin.audioaddict',
	defaultLevel => 'ERROR',
	description  => 'PLUGIN_AUDIO_ADDICT_DESC',
} );

my $prefs = preferences('plugin.audioaddict');

my %channelIds;

sub initPlugin {
	my ($class) = @_;

	Slim::Utils::Strings::loadFile(catfile($pluginDir, 'strings.txt'));

	$class->SUPER::initPlugin(
		feed   => sub {
			my ($client, $cb, $args) = @_;
			$class->channelList($client, $cb, $args);
		},
		tag    => $class->network,
		menu   => 'radios',
	);

	my $network = $class->network;
	Slim::Formats::RemoteMetadata->registerParser(
		match => qr{audioaddict\.com/v1/\Q$network\E/listen/\w+/([^.?/]+)|prem\d+\.\Q$network\E\.(?:com|fm)/([^?/]+)}i,
		func  => sub {
			$class->_handleArtwork(@_);
 		}
	);

	if ( main::WEBUI ) {
		my ($package) = $class =~ /(.*)::Plugin$/;
		$package .= '::Settings';
		my $nameToken = $class->_pluginDataFor('name');
		my $servicePageLinkToken = $class->servicePageLink();
		my $network = $class->network;

		# dynamically create settings module
		eval qq{
			package ${package};
			use base qw(Slim::Plugin::AudioAddict::Settings);

			sub name { Slim::Web::HTTP::CSRF->protectName('${nameToken}') }
			sub servicePageLink { '$servicePageLinkToken' }
			sub network { '$network' }
		};

		if ( $@ ) {
			$log->error( "Unable to dynamically create settings class $package: $@" );
		}
		else {
			$package->new();
		}
	}
}

# needs to be set to the station's ID
sub network { '' }

sub servicePageLink { '' }

sub _fixCoverUrl {
	my ($cover) = @_;

	return '' unless $cover;

	$cover = 'https:' . $cover if $cover =~ m{^//};
	$cover .= '?size=1000x1000&quality=90' if $cover && $cover !~ /\?/;

	return $cover;
}

sub _handleArtwork {
	my ($class, $client, $url, $metadata) = @_;

	my $channelId = $class->_channelIdFromUrl($url);

	if ($channelId) {
		return _fetchAndSetArtwork($client, $url, $class->network, $channelId, $metadata);
	}

	$class->channelList($client, sub {
		my $id = $class->_channelIdFromUrl($url) or return;
		_fetchAndSetArtwork($client, $url, $class->network, $id, $metadata);
	});
}

sub _fetchAndSetArtwork {
	my ($client, $url, $network, $channelId, $metadata, $forceUpdate) = @_;

	Slim::Utils::Timers::killTimers($client, \&_fetchAndSetArtwork);

	Slim::Plugin::AudioAddict::API->nowPlaying($network, $channelId, $metadata, $forceUpdate, sub {
		my $entry = shift or return;

		main::INFOLOG && $log->is_info && $log->info(Data::Dump::dump($entry));

		return unless ref $entry eq 'HASH';

		my $startedSAgo = time() - $entry->{started};
		my $duration = $entry->{duration} || 0;

		if ($startedSAgo > $duration || $duration - $startedSAgo < 15) {
			my $backOff = $client->pluginData('backOff') || 0;
			$backOff = ($backOff || 0) + BACKOFF_BASE;
			$client->pluginData( backOff => $backOff );

			main::INFOLOG && $log->is_info && $log->info("Track started $startedSAgo seconds ago, but is $duration seconds long - force refresh in $backOff seconds");

			Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + $backOff, \&_fetchAndSetArtwork, $url, $network, $channelId, $metadata, 1);
		}
		else {
			$client->pluginData( backOff => 0 );
		}

		my $cover  = $entry->{art_url} || return;
		my $title  = $entry->{title}  || '';
		my $artist = $entry->{artist} || '';
		my $album  = $entry->{release} || '';

		$cover = _fixCoverUrl($cover);

		if ( my $song = $client->playingSong() ) {
			$song->pluginData( httpCover => $cover );
			$song->pluginData( wmaMeta => {
				icon   => $cover,
				cover  => $cover,
				artist => $artist,
				album  => $album,
				title  => $title,
			} );
		}

		Slim::Control::Request::notifyFromArray($client, ['newmetadata']);

		return {
			artist  => $artist,
			album   => $album,
			title   => $title,
			cover   => $cover,
		};
	});

	return 1;
}

sub _channelIdFromUrl {
	my ($class, $url) = @_;

	my $channelKey = $class->_channelKeyFromUrl($url) or return;
	return $channelIds{$class->network}{$channelKey};
}

sub _channelKeyFromUrl {
	my ($class, $url) = @_;
	my $network = $class->network;

	return $1 if $url =~ m{audioaddict\.com/v1/\Q$network\E/listen/\w+/([^.?/]+)}i;
	return $1 if $url =~ m{prem\d+\.\Q$network\E\.(?:com|fm)/([^?/]+)}i;
	return undef;
}

sub channelList {
	my ($class, $client, $cb, $args) = @_;

	if (!$prefs->get('listen_key') || !$prefs->get('subscriptions')) {
		return $cb->([{
			type => 'text',
			name => Slim::Utils::Strings::cstring($client, $class->missingCredsString),
		}]);
	}

	Slim::Plugin::AudioAddict::API->channelFilters($class->network, sub {
		my $filters = shift;

		my $items = [];
		for my $filter ( @{$filters} ) {
			my $channels = [];
			for my $channel ( @{ $filter->{channels} } ) {
				my $image = _fixCoverUrl($channel->{asset_url});

				$channelIds{$class->network}{ $channel->{key} } = $channel->{id};

				push @{$channels}, {
					type    => 'audio',
					bitrate => 320,
					name    => $channel->{name},
					line1   => $channel->{name},
					line2   => $channel->{description},
					image   => $image,
					url     => Slim::Plugin::AudioAddict::API::API_URL . sprintf(
						'%s/listen/premium_high/%s.pls?listen_key=%s',
						$class->network,
						$channel->{key},
						$prefs->get('listen_key')
					),
				};
			}

			push @$items, {
				type  => 'playlist',
				name  => $filter->{name},
				items => $channels,
			};
		}

		main::DEBUGLOG && $log->is_debug && $log->debug("ChannelList:" . Data::Dump::dump($items));

		$cb->($items);
	});
}

sub missingCredsString {
	'PLUGIN_' . uc($_[0]->network) . '_MISSING_CREDS';
}

1;
