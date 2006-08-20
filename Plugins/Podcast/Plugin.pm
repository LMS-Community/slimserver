package Plugins::Podcast::Plugin;

# $Id$

# Copyright (c) 2005-2006 Slim Devices, Inc. (www.slimdevices.com)

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use constant FEEDS_VERSION => 1;

use HTML::Entities;
use XML::Simple;

use Slim::Formats::XML;
use Slim::Utils::Cache;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);

# default can be overridden by prefs.  See initPlugin()
# TODO: come up with a better list of defaults.
our @default_feeds = (
	{
		name => 'Odeo',
		value => 'http://content.us.squeezenetwork.com:8080/opml/odeo.opml',
	},
	{
		name => 'PodcastAlley Top 50',
		value => 'http://podcastalley.com/PodcastAlleyTop50.opml'
	},
	{
		name => 'PodcastAlley 10 Newest',
		value => 'http://podcastalley.com/PodcastAlley10Newest.opml'
	},
);

our @feeds = ();
our %feed_names; # cache of feed names

sub enabled {
	return ($::VERSION ge '6.3');
}

sub initPlugin {
	$::d_plugins && msg("Podcast Plugin initializing.\n");

	Slim::Buttons::Common::addMode('PLUGIN.Podcast', getFunctions(), \&setMode);

	my @feedURLPrefs = Slim::Utils::Prefs::getArray("plugin_podcast_feeds");
	my @feedNamePrefs = Slim::Utils::Prefs::getArray("plugin_podcast_names");
	my $feedsModified = Slim::Utils::Prefs::get("plugin_podcast_feeds_modified");
	my $version = Slim::Utils::Prefs::get("plugin_podcast_feeds_version");

	@feeds = ();

#        |requires Client
#        |  |is a Query
#        |  |  |has Tags
#        |  |  |  |Function to call
#        C  Q  T  F
	Slim::Control::Request::addDispatch(['podcast', 'items', '_index', '_quantity'],
        [0, 1, 1, \&cliQuery]);
	Slim::Control::Request::addDispatch(['podcast', 'playlist', '_method' ],
		[1, 1, 1, \&cliQuery]);


	# No prefs set or we've had a version change and they weren't modified, 
	# so we'll use the defaults
	if (scalar(@feedURLPrefs) == 0 ||
		(!$feedsModified && (!$version  || $version != FEEDS_VERSION))) {
		# use defaults
		# set the prefs so the web interface will work.
		revertToDefaults();
	} else {
		# use prefs
		my $i = 0;
		while ($i < scalar(@feedNamePrefs)) {

			push @feeds, {
				name  => $feedNamePrefs[$i],
				value => $feedURLPrefs[$i],
				type  => 'link',
			};
			$i++;
		}
	}

	if ($::d_plugins) {
		msg("Podcast Feed Info:\n");

		foreach (@feeds) {
			msg($_->{'name'} . ", " . $_->{'value'} . "\n");
		}

		msg("\n");
	}

	# feed_names should reflect current names
	%feed_names = ();

	map { $feed_names{$_->{'value'} } = $_->{'name'}} @feeds;
	
	updateOPMLCache( \@feeds );
}

sub revertToDefaults {
	@feeds = @default_feeds;

	my @urls  = map { $_->{'value'}} @feeds;
	my @names = map { $_->{'name'}} @feeds;

	Slim::Utils::Prefs::set('plugin_podcast_feeds', \@urls);
	Slim::Utils::Prefs::set('plugin_podcast_names', \@names);
	Slim::Utils::Prefs::set('plugin_podcast_feeds_version', FEEDS_VERSION);

	# feed_names should reflect current names
	%feed_names = ();

	map { $feed_names{$_->{'value'}} = $_->{'name'} } @feeds;
	
	updateOPMLCache( \@feeds );
}

sub getDisplayName {
	return 'PLUGIN_PODCAST';
}

sub getFunctions {
	return {};
}

sub setMode {
	my $client = shift;
	my $method = shift;

	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}

	# use INPUT.Choice to display the list of feeds
	my %params = (
		header => '{PLUGIN_PODCAST} {count}',
		listRef => \@feeds,
		modeName => 'Podcast Plugin',
		onRight => sub {
			my $client = shift;
			my $item = shift;
			my %params = (
				url => $item->{'value'},
				title => $item->{'name'},
			);
			Slim::Buttons::Common::pushMode($client, 'xmlbrowser', \%params);
		},
		onPlay => sub {
			my $client = shift;
			my $item = shift;
			# url is also a playlist
			$client->execute(['playlist', 'play', $item->{'value'}, $item->{'name'}]);
		},
		onAdd => sub {
			my $client = shift;
			my $item = shift;
			# url is also a playlist
			$client->execute(['playlist', 'add', $item->{'value'}, $item->{'name'}]);
		},

		overlayRef => [
			undef,
			Slim::Display::Display::symbol('notesymbol') .
			Slim::Display::Display::symbol('rightarrow') 
		],
	);

	Slim::Buttons::Common::pushMode($client, 'INPUT.Choice', \%params);
}

sub webPages {
	my $title = 'PLUGIN_PODCAST';
	
	if (grep {$_ eq 'Podcast::Plugin'} Slim::Utils::Prefs::getArray('disabledplugins')) {
		Slim::Web::Pages->addPageLinks('radio', { $title => undef });
	} else {
		Slim::Web::Pages->addPageLinks('radio', { $title => 'plugins/Podcast/index.html' });
	}

	my %pages = ( 
		'index.html' => sub {
			# Get OPML list of feeds from cache
			my $cache = Slim::Utils::Cache->new();
			my $opml = $cache->get( 'podcasts_opml' );
			Slim::Web::XMLBrowser->handleWebIndex( {
				feed   => $opml,
				title  => $title,
				args   => \@_
			} );
		},
	);
	
	return \%pages;
}

sub cliQuery {
	my $request = shift;
	
	$::d_plugins && msg("Podcast: cliQuery()\n");
	
	# Get OPML list of feeds from cache
	my $cache = Slim::Utils::Cache->new();
	my $opml = $cache->get( 'podcasts_opml' );
	Slim::Buttons::XMLBrowser::cliQuery('podcast', $opml, $request);
}


# Update the hashref of podcast feeds for use with the web UI
sub updateOPMLCache {
	my $feeds = shift;
	
	my $outline = [];
	for my $item ( @{$feeds} ) {
		push @{$outline}, {
			'name'  => $item->{'name'},
			'url'   => $item->{'value'},
			'value' => $item->{'value'},
			'type'  => $item->{'type'},
			'items' => [],
		};
	}
	
	my $opml = {
		'title' => string('PLUGIN_PODCAST'),
		'url'   => 'podcasts_opml',			# Used so XMLBrowser can look this up in cache
		'type'  => 'opml',
		'items' => $outline,
	};
		
	my $cache = Slim::Utils::Cache->new();
	$cache->set( 'podcasts_opml', $opml );
}

# for configuring via web interface
sub setupGroup {
	my %Group = (
		PrefOrder => [
			'plugin_podcast_reset',
			'plugin_podcast_feeds',
		],
		GroupHead => 'PLUGIN_PODCAST',
		GroupDesc => 'PODCAST_GROUP_DESC',
		GroupLine => 1,
		GroupSub => 1,
		Suppress_PrefSub  => 1,
		Suppress_PrefLine => 1,
	);

	my %Prefs = (
		plugin_podcast_reset => {
			'onChange' => sub {
				Slim::Utils::Prefs::set("plugin_podcast_feeds_modified", undef);
				Slim::Utils::Prefs::set("plugin_podcast_feeds_version", undef);
				revertToDefaults();
			},
			'inputTemplate' => 'setup_input_submit.html',
			'changeIntro' => 'PODCAST_RESETTING',
			'ChangeButton' => 'PODCAST_RESET_BUTTON',
			'dontSet' => 1,
			'changeMsg' => '',
		},

		plugin_podcast_feeds => {
			'isArray' => 1,
			'arrayAddExtra' => 1,
			'arrayDeleteNull' => 1,
			'arrayDeleteValue' => '',
			'arrayBasicValue' => 0,
			'PrefSize' => 'large',
			'inputTemplate' => 'setup_input_array_txt.html',
			'PrefInTable' => 1,
			'showTextExtValue' => 1,
			'externalValue' => sub {
				my ($client, $value, $key) = @_;

				if ($key =~ /^(\D*)(\d+)$/ && ($2 < scalar(@feeds))) {
					return $feeds[$2]->{'name'};
				}

				return '';
			},
			'onChange' => \&updateFeedNames,
			'changeMsg' => 'PODCAST_FEEDS_CHANGE',
		},
	);

	return (\%Group, \%Prefs);
}

sub updateFeedNames {
	my @feedURLPrefs = Slim::Utils::Prefs::getArray("plugin_podcast_feeds");
	my @feedNamePrefs;

	# verbose debug
	if ($::d_plugins) {

		require Data::Dumper;
		msg("Podcast: updateFeedNames urls:\n");
		msg(Data::Dumper::Dumper(\@feedURLPrefs));
	}

	# case 1: we're reverting to default
	if (scalar(@feedURLPrefs) == 0) {
		revertToDefaults();
	} else {
		# case 2: url list edited

		my $i = 0;
		while ($i < scalar(@feedURLPrefs)) {

			my $url = $feedURLPrefs[$i];
			my $name = $feed_names{$url};

			if ($name && $name !~ /^http\:/) {

				# no change
				$feedNamePrefs[$i] = $name;

			} elsif ($url =~ /^http\:/) {

				# does a synchronous get
				my $xml = Slim::Formats::XML->getFeedSync($url);

				if ($xml && exists $xml->{'channel'}->{'title'}) {

					# here for podcasts and RSS
					$feedNamePrefs[$i] = Slim::Formats::XML::unescapeAndTrim($xml->{'channel'}->{'title'});

				} elsif ($xml && exists $xml->{'head'}->{'title'}) {

					# here for OPML
					$feedNamePrefs[$i] = Slim::Formats::XML::unescapeAndTrim($xml->{'head'}->{'title'});

				} else {
					# use url as title since we have nothing else
					$feedNamePrefs[$i] = $url;
				}

			} else {
				# use url as title since we have nothing else
				$feedNamePrefs[$i] = $url;
			}

			$i++;
		}

		# if names array contains more than urls, delete the extras
		while ($feedNamePrefs[$i]) {
			delete $feedNamePrefs[$i];
			$i++;
		}

		# save updated names to prefs
		Slim::Utils::Prefs::set('plugin_podcast_names', \@feedNamePrefs);

		# runtime list must reflect changes
		@feeds = ();
		$i = 0;

		while ($i < scalar(@feedNamePrefs)) {

			push @feeds, {
				name => $feedNamePrefs[$i],
				value => $feedURLPrefs[$i]
			};

			$i++;
		}

		# feed_names should reflect current names
		%feed_names = ();

		map { $feed_names{$_->{'value'}} = $_->{'name'} } @feeds;
		
		updateOPMLCache( \@feeds );
	}

}

sub strings { return q!
PLUGIN_PODCAST
	EN	Podcasts

PODCAST_NOTHING_TO_PLAY
	DE	Nichts zu spielen
	EN	Nothing to play
	ES	Nada para escuchar
	FR	Rien à lire
	IT	Niente da riprodurre
	NL	Niets om af te spelen

PODCAST_GROUP_DESC
	DE	Der Podcast Browser erlaubt es, Podcasts anzusehen und abzuspielen.
	EN	The Podcast Browser plugin allows you to view and listen to podcasts.
	ES	El plugin Navegador de Podcasts permite ver y escuchar podcasts.
	FR	Le module d'extension Podcast vous permet d'afficher et d'écouter des podcasts.
	NL	Met de Podcast browser plugin kun je podcasts bekijken en beluisteren.

PODCAST_RESET_BUTTON
	DE	Zurücksetzen
	EN	Reset
	ES	Reinicializar
	FR	Défaut
	NL	Herstel

PODCAST_RESETTING
	DE	Setze Podcasts zurück
	EN	Resetting to default podcasts
	ES	Reestableciendo podcasts por defecto
	FR	Liste des podcasts par défaut rétablie
	NL	Herstellen van de standaard podcasts

PODCAST_FEEDS_CHANGE
	DE	Die Podcast Liste wurde geändert.
	EN	Podcast list changed.
	ES	Lista de Podcast modificada.
	FR	Liste des podcasts modifiée.
	NL	Podcast lijst gewijzigd.

SETUP_PLUGIN_PODCAST_FEEDS
	EN	Podcasts

SETUP_PLUGIN_PODCAST_RESET
	DE	Podcasts zurücksetzen
	EN	Reset default Podcasts
	ES	Reinicializar Podcasts por defecto
	FR	Rétablir la liste des podcasts par défaut
	NL	Herstel default podcasts
!};

1;
