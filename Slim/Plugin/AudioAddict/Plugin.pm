package Slim::Plugin::AudioAddict::Plugin;

use strict;

use base qw(Slim::Plugin::OPMLBased);

use Slim::Plugin::AudioAddict::API;
use Slim::Utils::Prefs;

my $log = Slim::Utils::Log->addLogCategory( {
	category     => 'plugin.audioaddict',
	defaultLevel => 'ERROR',
	description  => 'PLUGIN_AUDIO_ADDICT_DESC',
} );

my $prefs = preferences('plugin.audioaddict');

sub initPlugin {
	my ($class) = @_;

	$class->SUPER::initPlugin(
		feed   => sub {
			my ($client, $cb, $args) = @_;
			$class->channelList($client, $cb, $args);
		},
		tag    => $class->network,
		menu   => 'radios',
	);
}

# needs to be set to the station's ID
sub network { '' }

sub channelList {
	my ($class, $client, $cb, $args) = @_;

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

1;