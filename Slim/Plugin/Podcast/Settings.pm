package Slim::Plugin::Podcast::Settings;

# SlimServer Copyright (C) 2001-2006 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Log;
use Slim::Utils::Prefs;

my $log   = logger('plugin.podcast');
my $prefs = preferences('plugin.podcast');

use constant FEED_VERSION => 2; # bump this number when changing the defaults below

our @default_feeds = (
	{
		name  => 'Odeo',
		value => 'http://content.us.squeezenetwork.com:8080/opml/odeo.opml',
	},
	{
		name  => 'PodcastAlley Top 50',
		value => 'http://podcastalley.com/PodcastAlleyTop50.opml'
	},
	{
		name  => 'PodcastAlley 10 Newest',
		value => 'http://podcastalley.com/PodcastAlley10Newest.opml'
	},
);

# migrate old prefs across
$prefs->migrate(1, sub {
	my @names  = @{Slim::Utils::Prefs::OldPrefs->get('plugin_podcast_names') || [] };
	my @values = @{Slim::Utils::Prefs::OldPrefs->get('plugin_podcast_feeds') || [] };
	my @feeds;

	for my $name (@names) {
		push @feeds, { 'name' => $name, 'value' => shift @values };
	}

	if (@feeds) {
		$prefs->set('feeds', \@feeds);
		$prefs->set('modified', 1);
	}

	1;
});

# migrate to latest version of default feeds if they have not been modified
$prefs->migrate(FEED_VERSION, sub {
	$prefs->set('feeds', \@default_feeds) unless $prefs->get('modified');
	1;
});

sub name {
	return 'PLUGIN_PODCAST';
}

sub page {
	return 'plugins/Podcast/settings/basic.html';
}

sub handler {
	my ($class, $client, $params) = @_;

	if ($params->{'reset'}) {

		$prefs->set('feeds', \@default_feeds);
		$prefs->set('modified', 0);

		Slim::Plugin::Podcast::Plugin::updateOPMLCache(\@default_feeds);
	}

	if ($params->{'saveSettings'}) {

		my @feeds       = @{ $prefs->get('feeds') };
		my $newFeedUrl  = $params->{'newfeed'};
		my $newFeedName = validateFeed($newFeedUrl);

		if ($newFeedUrl && $newFeedName) {

			push @feeds, {
				'name'  => $newFeedName,
				'value' => $newFeedUrl,
			};

		} elsif ($newFeedUrl) {

			$params->{'warning'} .= sprintf Slim::Utils::Strings::string('SETUP_PLUGIN_PODCAST_INVALID_FEED'), $newFeedUrl;
			$params->{'newfeedval'} = $params->{'newfeed'};
		}

		my @delete = @{ ref $params->{'delete'} eq 'ARRAY' ? $params->{'delete'} : [ $params->{'delete'} ] };

		for my $deleteItem (@delete) {
			my $i = 0;
			while ($i < scalar @feeds) {
				if ($deleteItem eq $feeds[$i]->{'value'}) {
					splice @feeds, $i, 1;
					next;
				}
				$i++;
			}
		}

		$prefs->set('feeds', \@feeds);
		$prefs->set('modified', 1);

		Slim::Plugin::Podcast::Plugin::updateOPMLCache(\@feeds);
	}

	for my $feed (@{ $prefs->get('feeds') }) {

		push @{$params->{'prefs'}}, [ $feed->{'value'}, $feed->{'name'} ];
	}

	return $class->SUPER::handler($client, $params);
}

sub validateFeed {
	my $url = shift || return undef;

	$log->info("validating $url");

	# this is synchronous at present
	my $xml = Slim::Formats::XML->getFeedSync($url);

	if ($xml && exists $xml->{'channel'}->{'title'}) {

		# here for podcasts and RSS
		return Slim::Formats::XML::unescapeAndTrim($xml->{'channel'}->{'title'});

	} elsif ($xml && exists $xml->{'head'}->{'title'}) {

		# here for OPML
		return Slim::Formats::XML::unescapeAndTrim($xml->{'head'}->{'title'});

	} elsif ($xml) {

		# got xml but can't find title - use url
		return $url;
	}

	$log->warn("unable to connect to $url");

	return undef;
}

1;

__END__
