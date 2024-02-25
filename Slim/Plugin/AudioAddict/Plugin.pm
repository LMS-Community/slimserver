package Slim::Plugin::AudioAddict::Plugin;

# Logitech Media Server Copyright 2001-2023 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use base qw(Slim::Plugin::OPMLBased);
use File::Spec::Functions qw(catfile);

use Slim::Plugin::AudioAddict::API;
use Slim::Utils::Prefs;

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
				my $image = $channel->{asset_url} . '?size=1000x1000&quality=90';
				$image = 'https:' . $image if $image =~ m|^//|;

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