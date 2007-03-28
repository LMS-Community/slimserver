package Slim::Plugin::Podcast::Settings;

# SlimServer Copyright (C) 2001-2006 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

sub name {
	return 'PLUGIN_PODCAST';
}

sub page {
	return 'plugins/Podcast/settings/basic.html';
}

sub handler {
	my ($class, $client, $params) = @_;

	if ($params->{'reset'}) {
		Slim::Plugin::Podcast::Plugin::revertToDefaults();
	}

	if ($params->{'saveSettings'}) {

		# Remove empty feeds.
		my @feeds = grep { $_ ne '' } @{$params->{'plugin_podcast_feeds'}};

		Slim::Utils::Prefs::set('plugin_podcast_feeds', \@feeds);

		Slim::Plugin::Podcast::Plugin::updateFeedNames();
	}

	my @feeds = Slim::Utils::Prefs::getArray('plugin_podcast_feeds');
	my @names = Slim::Utils::Prefs::getArray('plugin_podcast_names');

	for (my $i = 0; $i < @feeds; $i++) {

		push @{$params->{'prefs'}}, [ $feeds[$i], $names[$i] ];
	}

	return $class->SUPER::handler($client, $params);
}

1;

__END__
