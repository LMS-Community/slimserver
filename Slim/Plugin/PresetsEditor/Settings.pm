package Slim::Plugin::PresetsEditor::Settings;

# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use base qw(Slim::Web::Settings);
use JSON::XS::VersionOneAndTwo;

use Slim::Utils::Alarm;
use Slim::Utils::Log;
use Slim::Utils::Prefs;

my $prefs = preferences('server');
my $log   = logger('plugin.presetseditor');

sub name {
	return Slim::Web::HTTP::CSRF->protectName('PLUGIN_PRESETS_EDITOR');
}

sub needsClient { 1 }

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('settings/presets.html');
}

sub handler {
	my ($class, $client, $params) = @_;

	if ($params->{'saveSettings'}) {
		my $presets = $prefs->client($client)->get('presets');

		foreach (1..10) {
			my $text = $params->{'preset_text_' . $_};
			my $url = $params->{'preset_url_' . $_};

			if ($url ne $presets->[$_-1]->{URL} || ($text && $text ne $presets->[$_-1]->{text})) {
				$text = '' if !$url;
				$presets->[$_-1] = {
					URL => $url,
					text => $text || '',
					type => 'audio'
				};

				$prefs->client($client)->set('presets', $presets);
			}
		}
	}

	$params->{presets} = $client ? $prefs->client($client)->get('presets') : [];

	my $playlistOptions = Slim::Utils::Alarm->getPlaylists($client);
	my %urlToName;

	foreach my $category (@$playlistOptions) {
		my $items = [ grep { 
			$urlToName{$_->{url}} = $_->{title};
			$_->{url} ;
		} @{$category->{items}} ];
		$category->{items} = $items;
	}

	$params->{playlistOptions} = [ grep {
		$_->{items} && scalar @{$_->{items}}
	} @$playlistOptions ];

	$params->{urlToName} = to_json(\%urlToName);

	return $class->SUPER::handler( $client, $params );
}

1;