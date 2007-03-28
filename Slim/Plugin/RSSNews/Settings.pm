package Slim::Plugin::RSSNews::Settings;

# SlimServer Copyright (C) 2001-2006 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

sub name {
        return 'PLUGIN_RSSNews';
}

sub page {
        return 'plugins/RSSNews/settings/basic.html';
}

sub handler {
	my ($class, $client, $params) = @_;

	my @prefs = qw(
		plugin_RssNews_items_per_feed
	);

	if ($params->{'reset'}) {
		Slim::Plugin::RSSNews::Plugin::revertToDefaults();
	}

	if ($params->{'saveSettings'}) {

		# Remove empty feeds.
		my @feeds = grep { $_ ne '' } @{$params->{'plugin_RssNews_feeds'}};

		Slim::Utils::Prefs::set('plugin_RssNews_feeds', \@feeds);

		Slim::Plugin::RSSNews::Plugin::updateFeedNames();

		for my $pref (@prefs) {

			Slim::Utils::Prefs::set($pref, $params->{$pref});
		}
	}

	my @feeds = Slim::Utils::Prefs::getArray('plugin_RssNews_feeds');
	my @names = Slim::Utils::Prefs::getArray('plugin_RssNews_names');

	for (my $i = 0; $i < @feeds; $i++) {

		push @{$params->{'prefs'}->{'feeds'}}, [ $feeds[$i], $names[$i] ];
	}

	for my $pref (@prefs) {

		$params->{'prefs'}->{$pref} = Slim::Utils::Prefs::get($pref);
	}

	return $class->SUPER::handler($client, $params);
}

1;

__END__
