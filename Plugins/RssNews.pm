package Plugins::RssNews;

# RSS News Browser
# Copyright (c) 2006 Slim Devices, Inc. (www.slimdevices.com)
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.
#
# This is a reimplementation of the old RssNews plugin based on
# the Podcast Browser plugin.
#
# $Id$

use strict;

use constant FEEDS_VERSION => 1.0;

use HTML::Entities;
use XML::Simple;

use Slim::Buttons::XMLBrowser;
use Slim::Formats::XML;
use Slim::Utils::Cache;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);

# Default feed list
my @default_feeds = (
	{
		name  => 'BBC News World Edition',
		value => 'http://news.bbc.co.uk/rss/newsonline_world_edition/front_page/rss.xml',
	},
	{
		name  => 'CNET News.com',
		value => 'http://news.com.com/2547-1_3-0-5.xml',
	},
	{
		name  => 'New York Times Home Page',
		value => 'http://www.nytimes.com/services/xml/rss/nyt/HomePage.xml',
	},
	{
		name  => 'RollingStone.com Music News',
		value => 'http://www.rollingstone.com/rssxml/music_news.xml',
	},
	{
		name  => 'Slashdot',
		value => 'http://rss.slashdot.org/Slashdot/slashdot',
	},
	{
		name  => 'Yahoo! News: Business',
		value => 'http://rss.news.yahoo.com/rss/business',
	},
);

my @feeds = ();
my %feed_names; # cache of feed names

# in screensaver mode, number of items to display per channel before switching
my $screensaver_items_per_feed;

# $refresh_sec is the minimum time in seconds between refreshes of the ticker from the RSS.
# Please do not lower this value. It prevents excessive queries to the RSS.
my $refresh_sec = 60 * 60;

sub enabled {
	return ($::VERSION ge '6.3');
}

sub initPlugin {
	$::d_plugins && msg("RSS Plugin initializing.\n");

	Slim::Buttons::Common::addMode('PLUGIN.RSS', getFunctions(), \&setMode);

	my @feedURLPrefs  = Slim::Utils::Prefs::getArray("plugin_RssNews_feeds");
	my @feedNamePrefs = Slim::Utils::Prefs::getArray("plugin_RssNews_names");
	my $feedsModified = Slim::Utils::Prefs::get("plugin_RssNews_feeds_modified");
	my $version       = Slim::Utils::Prefs::get("plugin_RssNews_feeds_version");
	
	$screensaver_items_per_feed = Slim::Utils::Prefs::get('plugin_RssNews_items_per_feed');
	if (!defined $screensaver_items_per_feed) {

		$screensaver_items_per_feed = 3;
		Slim::Utils::Prefs::set('plugin_RssNews_items_per_feed', $screensaver_items_per_feed);
	}

	@feeds = ();

#        |requires Client
#        |  |is a Query
#        |  |  |has Tags
#        |  |  |  |Function to call
#        C  Q  T  F
    Slim::Control::Request::addDispatch(['rss', 'items', '_index', '_quantity'],
        [0, 1, 1, \&cliQuery]);


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
		msg("RSS Feed Info:\n");

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

	my @urls  = map { $_->{'value'} } @feeds;
	my @names = map { $_->{'name'}  } @feeds;

	Slim::Utils::Prefs::set('plugin_RssNews_feeds', \@urls);
	Slim::Utils::Prefs::set('plugin_RssNews_names', \@names);
	Slim::Utils::Prefs::set('plugin_RssNews_feeds_version', FEEDS_VERSION);

	# feed_names should reflect current names
	%feed_names = ();

	map { $feed_names{$_->{'value'}} = $_->{'name'} } @feeds;
	
	updateOPMLCache( \@feeds );
}

sub getDisplayName {
	return 'PLUGIN_RSSNEWS';
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
		header => '{PLUGIN_RSSNEWS} {count}',
		listRef => \@feeds,
		modeName => 'RSS Plugin',
		onRight => sub {
			my $client = shift;
			my $item = shift;
			my %params = (
				url     => $item->{'value'},
				title   => $item->{'name'},
				expires => $refresh_sec,
			);
			Slim::Buttons::Common::pushMode($client, 'xmlbrowser', \%params);
		},

		overlayRef => [
			undef,
			Slim::Display::Display::symbol('rightarrow') 
		],
	);

	Slim::Buttons::Common::pushMode($client, 'INPUT.Choice', \%params);
}

sub cliQuery {
	my $request = shift;
	
	$::d_plugins && msg("RSS: cliQuery()\n");
	
	# Get OPML list of feeds from cache
	my $cache = Slim::Utils::Cache->new();
	my $opml = $cache->get( 'rss_opml' );
	Slim::Buttons::XMLBrowser::cliQuery('rss', $opml, $request, $refresh_sec);
}


# Update the hashref of RSS feeds for use with the web UI
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
		'title' => string('PLUGIN_RSSNEWS'),
		'url'   => 'rss_opml',			# Used so XMLBrowser can look this up in cache
		'type'  => 'opml',
		'items' => $outline,
	};
		
	my $cache = Slim::Utils::Cache->new();
	$cache->set( 'rss_opml', $opml );
}

# for configuring via web interface
sub setupGroup {
	my %Group = (
		PrefOrder => [
			'plugin_RssNews_items_per_feed',
			'plugin_RssNews_reset',
			'plugin_RssNews_feeds',
		],
		GroupHead => 'PLUGIN_RSSNEWS',
		GroupDesc => 'SETUP_GROUP_PLUGIN_RSSNEWS_DESC',
		GroupLine => 1,
		GroupSub  => 1,
		Suppress_PrefSub  => 1,
		Suppress_PrefLine => 1,
	);

	my %Prefs = (
		
		plugin_RssNews_items_per_feed => {
			'validate'       => \&Slim::Utils::Validate::isInt,
			'validateArgs'  => [1,undef,1],
			'onChange'      => sub {
				$screensaver_items_per_feed = $_[1]->{plugin_RssNews_items_per_feed}->{new};
				Slim::Utils::Prefs::set('plugin_RssNews_items_per_feed', $screensaver_items_per_feed);
			},
		},
		
		plugin_RssNews_reset => {
			'onChange'      => sub {
				Slim::Utils::Prefs::set("plugin_RssNews_feeds_modified", undef);
				Slim::Utils::Prefs::set("plugin_RssNews_feeds_version", undef);
				revertToDefaults();
			},
			'inputTemplate' => 'setup_input_submit.html',
			'changeIntro'   => 'PLUGIN_RSSNEWS_RESETTING',
			'ChangeButton'  => 'SETUP_PLUGIN_RSSNEWS_RESET_BUTTON',
			'dontSet'       => 1,
			'changeMsg'     => '',
		},

		plugin_RssNews_feeds => { 
			'isArray'          => 1,
			'arrayAddExtra'    => 1,
			'arrayDeleteNull'  => 1,
			'arrayDeleteValue' => '',
			'arrayBasicValue'  => 0,
			'PrefSize'         => 'large',
			'inputTemplate'    => 'setup_input_array_txt.html',
			'PrefInTable'      => 1,
			'showTextExtValue' => 1,
			'externalValue'    => sub {
				my ($client, $value, $key) = @_;

				if ($key =~ /^(\D*)(\d+)$/ && ($2 < scalar(@feeds))) {
					return $feeds[$2]->{'name'};
				}

				return '';
			},
			'onChange'         => \&updateFeedNames,
			'changeMsg'        => 'SETUP_PLUGIN_RSSNEWS_FEEDS_CHANGE',
		},
	);

	return (\%Group, \%Prefs);
}

sub updateFeedNames {
	my @feedURLPrefs = Slim::Utils::Prefs::getArray("plugin_RssNews_feeds");
	my @feedNamePrefs;

	# verbose debug
	if ($::d_plugins) {

		require Data::Dumper;
		msg("RSS: updateFeedNames urls:\n");
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
				# XXX: This should use async instead, but not a very high priority 
				# as this code is not used very much
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
		Slim::Utils::Prefs::set('plugin_RssNews_names', \@feedNamePrefs);

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

################################
# ScreenSaver Mode

sub screenSaver {
	Slim::Utils::Strings::addStrings(strings());

	Slim::Buttons::Common::addSaver(
		'SCREENSAVER.rssnews',
		getScreensaverRssNews(),
		\&setScreensaverRssNewsMode,
		\&leaveScreenSaverRssNews,
		'PLUGIN_RSSNEWS_SCREENSAVER'
	);
}

sub getScreensaverRssNews {

	return {
		'done' => sub  {
			my ($client, $funct, $functarg) = @_;

			Slim::Buttons::Common::popMode($client);
			$client->update;

			# pass along ir code to new mode if requested
			if (defined $functarg && $functarg eq 'passback') {
				Slim::Hardware::IR::resendButton($client);
			}
		}
	};
}

sub setScreensaverRssNewsMode {
	my $client = shift;

	# init params
	$client->param('PLUGIN.RssNews.newfeed', 1);
	$client->param('PLUGIN.RssNews.line1', 0);
	$client->param('PLUGIN.RssNews.screensaver_mode', 1);
	$client->lines(\&blankLines);

	# start tickerUpdate in future after updates() caused by server mode change
	Slim::Utils::Timers::setTimer(
		$client, 
		Time::HiRes::time() + 0.5,
		\&tickerUpdate
	);
}

# kill tickerUpdate
sub leaveScreenSaverRssNews {
	my $client = shift;

	Slim::Utils::Timers::killTimers($client, \&tickerUpdate);
	Slim::Utils::Timers::killTimers($client, \&tickerUpdateCheck);

	$client->param('PLUGIN.RssNews.screensaver_mode', 0);
}

sub tickerUpdate {
	my $client = shift;

	if ( $client->param('PLUGIN.RssNews.newfeed') ) {
		# we need to fetch the next feed
		getNextFeed( $client );
	}
	else {
		tickerUpdateContinue( $client );
	}
}

sub getNextFeed {
	my $client = shift;
	
	# select the next feed and fetch it
	my $index = $client->param('PLUGIN.RssNews.feed_index') || 0;
	$index++;
	
	if ( $index > scalar @feeds ) {
		$index = 1;
		# reset error count after looping around to the beginning
		$client->param( 'PLUGIN.RssNews.feed_error', 0 );
	}
	
	$client->param( 'PLUGIN.RssNews.feed_index', $index );
	
	my $url = $feeds[$index - 1]->{'value'};
	
	$::d_plugins && msg("RSS: Fetching next feed: $url\n");
	
	if ( !$client->param( 'PLUGIN.RssNews.current_feed' ) ) {
		$client->update( {
			'line1' => $client->string('PLUGIN_RSSNEWS'),
			'line2' => $client->string('PLUGIN_RSSNEWS_WAIT'),
		} );
	}
	
	Slim::Formats::XML->getFeedAsync( 
		\&gotNextFeed,
		\&gotError,
		{
			'url'     => $url,
			'client'  => $client,
			'expires' => $refresh_sec,
		},
	);
}

sub gotNextFeed {
	my ( $feed, $params ) = @_;
	my $client = $params->{'client'};
	
	$client->param( 'PLUGIN.RssNews.current_feed', $feed );
	
	tickerUpdateContinue( $client );
}

sub gotError {
	my ( $error, $params ) = @_;
	my $client = $params->{'client'};
	
	# Bug 1664, skip broken feeds in screensaver mode
	
	$::d_plugins && msg("RSS: Error loading feed: $error, skipping\n");
	
	my $errors = $client->param( 'PLUGIN.RssNews.feed_error' ) || 0;
	$errors++;
	$client->param( 'PLUGIN.RssNews.feed_error', $errors );
	
	if ( $errors == scalar @feeds ) {
		$::d_plugins && msg("RSS: All feeds failed, giving up\n");
		
		if ( $client->param('PLUGIN.RssNews.screensaver_mode') ) {
			$client->update( {
				'line1' => $client->string('PLUGIN_RSSNEWS'),
				'line2' => $client->string('PLUGIN_RSSNEWS_ERROR'),
			} );
		}
	}
	else {	
		getNextFeed( $client );
	}
}

sub tickerUpdateContinue {
	my $client = shift;
			
	$client->param('PLUGIN.RssNews.line1', 0);

	# add item to ticker
	$client->update( tickerLines($client) );

	my ($complete, $queue) = $client->scrollTickerTimeLeft();
	my $newfeed = $client->param('PLUGIN.RssNews.newfeed');

	# schedule for next item as soon as queue drains if same feed or after ticker completes if new feed
	my $next = $newfeed ? $complete : $queue;

	Slim::Utils::Timers::setTimer(
		$client, 
		Time::HiRes::time() + ( ($next > 1) ? $next : 1),
		\&tickerUpdate
	);
}

# check to see if ticker is empty and schedule immediate ticker update if so
sub tickerUpdateCheck {
	my $client = shift;

	my ($complete, $queue) = $client->scrollTickerTimeLeft();

	if ( $queue == 0 && Slim::Utils::Timers::killTimers($client, \&tickerUpdate) ) {
		tickerUpdate($client);
	}
}

# lines when called by server - e.g. on screensaver start or change of font size
# add undef line2 item to ticker, schedule tickerUpdate to add to ticker if necessary
sub blankLines {
	my $client = shift;

	my $parts = {
		'line'   => [ $client->param('PLUGIN.RssNews.line1') || '' ],
		'ticker' => [],
	};

	# check after the update calling this function is complete to see if ticker is empty
	# (to refill ticker on font size change as this clears current ticker)
	Slim::Utils::Timers::killTimers( $client, \&tickerUpdateCheck );	
	Slim::Utils::Timers::setTimer(
		$client, 
		Time::HiRes::time() + 0.1,
		\&tickerUpdateCheck
	);

	return $parts;
}

# lines for tickerUpdate to add to ticker
sub tickerLines {
	my $client = shift;

	my $parts         = {};
	my $new_feed_next = 0; # use new feed next call

	# the current RSS feed
	my $feed = $client->param('PLUGIN.RssNews.current_feed');

	assert( ref $feed eq 'HASH', "current rss feed not set\n");

	# the current item within each feed.
	my $current_items = $client->param('PLUGIN.RssNews.current_items');

	if ( !defined $current_items ) {

		$current_items = {
			$feed => {
				'next_item'  => 0,
				'first_item' => 0,
			},
		};

	}
	elsif ( !defined $current_items->{$feed} ) {

		$current_items->{$feed} = {
			'next_item'  => 0,
			'first_item' => 0
		};
	}
	
	# add item to ticker or display error and wait for tickerUpdate to retrieve news
	if ( defined $feed ) {
	
		my $line1 = Slim::Formats::XML::unescapeAndTrim( $feed->{'title'} );
		my $i     = $current_items->{$feed}->{'next_item'};
		
		my $title       = $feed->{'items'}->[$i]->{'title'};
		my $description = $feed->{'items'}->[$i]->{'description'} || '';

		# How to display items shown by screen saver.
		# %1\$s is item 'number'	XXX: number not used?
		# %2\$s is item title
		# %3\%s is item description
		my $screensaver_item_format = "%2\$s -- %3\$s";
		
		# we need to limit the number of characters we add to the ticker, 
		# because the server could crash rendering on pre-SqueezeboxG displays.
		my $screensaver_chars_per_item = 1024;
		
		my $line2 = sprintf(
			$screensaver_item_format,
			$i + 1,
			Slim::Formats::XML::unescapeAndTrim($title),
			Slim::Formats::XML::unescapeAndTrim($description)
		);

		if ( length $line2 > $screensaver_chars_per_item ) {

			$line2 = substr $line2, 0, $screensaver_chars_per_item;

			$::d_plugins && msg("RSS: screensaver character limit exceeded - truncating.\n");
		}

		$current_items->{$feed}->{'next_item'} = $i + 1;

		if ( !exists( $feed->{'items'}->[ $current_items->{$feed}->{'next_item'} ] ) ) {

			$current_items->{$feed}->{'next_item'}  = 0;
			$current_items->{$feed}->{'first_item'} -= ($i + 1);

			if ( $screensaver_items_per_feed >= ($i + 1) ) {

				$new_feed_next = 1;

				$current_items->{$feed}->{'first_item'} = 0;
			}
		}

		if ( ($current_items->{$feed}->{'next_item'} - 
		      $current_items->{$feed}->{'first_item'}) >= $screensaver_items_per_feed ) {

			# displayed $screensaver_items_per_feed of this feed, move on to next saving position
			$new_feed_next = 1;
			$current_items->{$feed}->{'first_item'} = $current_items->{$feed}->{'next_item'};
		}

		$parts = {
			'line'   => [ $line1 ],
			'ticker' => [ undef, $line2 ],
		};

		$client->param( 'PLUGIN.RssNews.line1', $line1 );
		$client->param( 'PLUGIN.RssNews.current_items', $current_items );
	}
	else {

		$parts = {
			'line' => [ "RSS News - ". $feed->{'title'}, $client->string('PLUGIN_RSSNEWS_WAIT') ]
		};

		$new_feed_next = 1;
	}

	$client->param( 'PLUGIN.RssNews.newfeed', $new_feed_next );

	return $parts;
}

sub strings {

	return q!
PLUGIN_RSSNEWS
	EN	RSS News Ticker
	ES	Ticker de Noticias RSS
	FR	Aggrégateur RSS
	NL	RSS nieuwsberichten

PLUGIN_RSSNEWS_ADD_NEW
	DE	Neuer Newsfeed -->
	EN	Add new feed -->
	ES	Añadir nuevo feed -->
	FR	Ajouter flux -->
	IT	Aggiungi un nuovo feed -->
	NL	Voeg nieuwe feed toe -->

PLUGIN_RSSNEWS_WAIT
	DE	Bitte warten...
	EN	Please wait, requesting feed...
	ES	Por favor esperar, solicitando...
	FR	Patientez, connexion au flux...
	NL	Bezig met ophalen...

PLUGIN_RSSNEWS_ERROR
	DE	Fehler beim Laden des RSS Feeds
	EN	Failed to retrieve RSS feed
	ES	Fallo al recuperar feed de RSS
	FR	Impossible de charger le flux
	IT	Errore nella ricerca di feed RSS
	NL	Fout bij ophalen RSS feed

PLUGIN_RSSNEWS_NO_DESCRIPTION
	DE	Keine Beschreibung verfügbar
	EN	Description not available
	ES	Descripción no disponible
	FR	Pas de description
	IT	Descrizione non disponibile
	NL	Beschrijving niet aanwezig

PLUGIN_RSSNEWS_NO_TITLE
	CS	Název není dostupný
	DE	Kein Titel verfübar
	EN	Title not available
	ES	Título no disponible
	FR	Pas de titre
	IT	Titolo non disponibile
	NL	Titel niet beschikbaar

PLUGIN_RSSNEWS_SCREENSAVER
	EN	RSS News Ticker
	ES	Ticker de Noticias RSS
	FR	Aggrégateur RSS
	NL	RSS nieuwsberichten

PLUGIN_RSSNEWS_NAME
	EN	RSS News Ticker
	ES	Ticker de Noticias RSS
	FR	Aggrégateur RSS
	NL	RSS nieuwsberichten

PLUGIN_RSSNEWS_SCREENSAVER_SETTINGS
	DE	RSS News Bildschirmschoner Einstellunge
	EN	RSS News Screensaver Settings
	ES	Confugarión de Salvapantallas de Noticias RSS
	FR	Paramètres Ecran de veille Aggrégateur RSS
	NL	Instellingen RSS nieuws schermbeveiliger

PLUGIN_RSSNEWS_SCREENSAVER_ACTIVATE
	DE	Diesen Bildschirmschoner wählen
	EN	Select Current Screensaver
	ES	Elegir Salvapantallas Actual
	IT	Seleziona il salvaschermo attuale
	NL	Selecteer huidige schermbeveiliger

PLUGIN_RSSNEWS_SCREENSAVER_ACTIVATE_TITLE
	CS	Aktuální spořič
	DE	Dieser Bildschirmschoner
	EN	Current Screensaver
	ES	Salvapantallas actual
	IT	Salvaschermo attuale
	NL	Huidige schermbeveiliger

PLUGIN_RSSNEWS_SCREENSAVER_ACTIVATED
	CS	Použít RSS News jako aktuální spořič
	DE	RSS News als Bildschirmschoner verwenden
	EN	Use RSS News as current screensaver
	ES	Utilizar Noticias RSS como el Salvapantallas actual
	IT	Usa RSS News come salvaschermo
	NL	Gebruik RSS nieuws als huidige schermbeveiliger

PLUGIN_RSSNEWS_SCREENSAVER_DEFAULT
	DE	Standard Bildschirmschoner verwenden (nicht RSS News)
	EN	Use default screensaver (not RSS News)
	ES	Utilizar salvapantallas por defecto (No el de Noticias RSS)
	IT	Usa il salvaschermo di default (non RSS News)
	NL	Gebruik standaard schermbeveiliger (niet RSS nieuws)

PLUGIN_RSSNEWS_SCREENSAVER_ENABLE
	DE	Newsticker als Bildschirmschoner verwenden
	EN	Activating ticker as current screensaver
	ES	Activando ticker como nuevo salvapantallas
	IT	Attivo ticker come salvaschermo in uso
	NL	Activeren RSS berichten als schermbeveiliger

PLUGIN_RSSNEWS_SCREENSAVER_DISABLE
	DE	Standard Bildschirmschoner wird verwendet
	EN	Returning to default screensaver
	ES	Volviendo al Salvapantallas por defecto
	IT	Ritorna al salvaschermo di default
	NL	Terug naar standaard schermbeveiliger

PLUGIN_RSSNEWS_ERROR_IN_FEED
	DE	Fehler beim Parsen dess RSS Feeds
	EN	Error parsing RSS feed
	ES	Error analizando feed de RSS
	FR	Erreur de lecture du flux
	NL	Fout bij decoderen RSS feed

PLUGIN_RSSNEWS_LOADING_FEED
	DE	RSS Feed wird geladen...
	EN	Loading RSS feed...
	ES	Cargando feed de RSS
	FR	Chargement flux...
	NL	Laden RSS feed...

SETUP_GROUP_PLUGIN_RSSNEWS_DESC
	DE	Das RSS News Ticker Plugin kann verwendet werden, um RSS Feeds zu durchsuchen und lesen. Die folgenden Einstellungen helfen ihnen beim Definieren der anzuzeigenden RSS Feeds, und wie diese dargestellt werden sollen. Klicken Sie auf Ändern, um die Änderungen zu aktivieren.
	EN	The RSS News Ticker plugin can be used to browse and display items from RSS Feeds. The preferences below can be used to determine which RSS Feeds to use and control how they are displayed. Click on the Change button when you are done.
	ES	El plugin de Ticker de Noticias RSS puede utilizarse para buscar y mostrar artículos de feeds de RSS. Las preferencias debajo pueden utilizarse para elegir que feed utilizar y controlar como se muestra. Presionar el botón Cambiar cuando se haya finalizado.
	FR	Le module d'extension Aggrégateur RSS vous permet de parcourir et d'afficher le contenu de flux RSS. Les paramètres ci-dessous permettent de sélectionner les flux RSS et de modifier leur affichage sur la platine. Cliquez sur Modifier une fois les changements effectués.
	IT	Il plugin RSS News Ticker puo' essere usato per sfogliare e visualizzare argomenti dai feed RSS. Le preferenze piu' sotto possono essere usate per determinare quali feed RSS usare e controllare come vengono visualizzati. Premi il bottone Cambia quando hai finito.
	NL	De RSS nieuwsberichten plugin gebruik je voor het koppensnellen van RSS feeds en het bekijken van RSS feeds. De instellingen gebruik je om te bepalen welke RSS feeds je wilt zien en hoe ze getoond worden. Klik op veranderen wanneer je klaar bent.

SETUP_PLUGIN_RSSNEWS_FEEDS
	DE	RSS Feeds ändern
	EN	Modify RSS feeds
	ES	Modificar feeds de RSS
	FR	Modifier les flux RSS
	IT	Modifica i feed RSS
	NL	Wijzig RSS feeds

SETUP_PLUGIN_RSSNEWS_FEEDS_DESC
	DE	Dies ist die Liste der anzuzeigenden RSS Feeds. Um einen neuen zu abonnieren, tippen Sie einfach dessen URL in eine leere Zeile. Um einen Feed zu entfernen, löschen Sie dessen URL. Bestehende URLs können im entsprechenden Feld bearbeitet werden. Klicken Sie auf Ändern, um die Änderungen zu aktivieren.
	EN	This is the list of RSS Feeds to display. To add a new one, just type its URL into the empty line. To remove one, simply delete the URL from the corresponding line. To change the URL of an existing feed, edit its text value. Click on the Change button when you are done.
	ES	Esta es la lista de feeds de RSS. Para añadir un nuevo feed, escribir la URL en la línea vacía. Para elminar uno, simplemente borrar la URL de la línea correspondiente. Para cambiar la URL de un feed existente, editar el texto correspondiente. Hacer click en Cambiar cuando se haya finalizado.
	FR	Ceci est la liste des flux RSS à afficher. Pour ajouter un flux, tapez son URL sur une ligne vide. Pour supprimer un flux, effacer l'URL de la ligne correspondante. Pour changer l'URL d'un flux existant, modifiez la ligne correspondante. Cliquez sur Modifier une fois les changements effectués.
	IT	Questa e' la lista dei feed RSS da visualizzare. Per aggiungerne uno nuovo, digita la sua URL in una linea vuota. Per rimuoverne uno, cancella semplicemente la URL dalla linea corrispondente. Per cambiare la URL di un feed esistente, modifica il contenuto del testo. Premi il bottone Cambia quando hai finito.
	NL	Dit is de lijst van RSS feeds. Om een nieuwe toe te voegen type je de URL op een lege regel. Om een RSS feed te verwijderen maak je de regel leeg. Om een URL te wijzigen wijzig je de tekst. Klik op Veranderen als de wijzigingen compleet zijn.

SETUP_PLUGIN_RSSNEWS_RESET
	DE	Standard Feeds wieder herstellen
	EN	Reset default RSS feeds
	ES	Reestablecer feeds de RSS por defecto
	FR	Rétablir les flux RSS par défaut
	IT	Reimposta i feed RSS di default
	NL	Herstel standaard RSS feeds

SETUP_PLUGIN_RSSNEWS_RESET_DESC
	DE	Klicken Sie auf den Reset Knopf, um die Standard RSS Feeds zu reaktivieren.
	EN	Click the Reset button to revert to the default set of RSS Feeds.
	ES	Presionar el botón de Restablecer para volver al conjunto de valores por defecto de feeds de RSS.
	FR	Cliquez sur Défaut pour rétablir la liste par défaut des flux RSS.
	IT	Premi il bottone Reset per ritornare al set iniziale di feed RSS.
	NL	Klik op Herstel om de standaard RSS feeds te herstellen.

PLUGIN_RSSNEWS_RESETTING
	DE	RSS Feeds wurden auf Standardwerte zurückgesetzt.
	EN	Resetting to default RSS Feeds.
	ES	Reestableciendo el feed  de RSS por defecto
	NL	Standaard RSS feeds herstellen.

SETUP_PLUGIN_RSSNEWS_RESET_BUTTON
	CS	Resetovat
	DE	Zurücksetzen
	EN	Reset
	ES	Reestablecer
	FR	Défaut
	NL	Herstel

SETUP_PLUGIN_RSSNEWS_ITEMS_PER_FEED
	DE	Anzahl Einträge pro Feed
	EN	Items displayed per channel
	ES	Elementos mostrados por canal
	FR	Nombre d'éléments par flux
	IT	Argomenti visualizzati per canale
	NL	Aantal items per kanaal om te laten zien

SETUP_PLUGIN_RSSNEWS_ITEMS_PER_FEED_DESC
	DE	Definieren Sie die Anzahl Einträge, die im Bildschirmschonermodus pro Feed angezeigt werden sollen. Eine grössere Anzahl hat zur Folge, dass mehr Einträge angezeigt werden, bevor der nächste Feed angezeigt wird.
	EN	The maximum number of items displayed for each feed while the screensaver is active. A larger value implies that the screensaver will display more items before switching to the next feed.
	ES	El número máximo de elementos mostrados, para cada feed, mientras el salvapantallas está activo. Un valor más alto implica que el salvapantal>las mostrará más elementos antes de pasar al próximo feed.
	FR	Le nombre maximum d'éléments affichés pour chaque flux RSS lorsque l'écran de veille est actif. Un nombre plus élevé signifie que l'écran de veille affichera plus d'éléments avant de passer au flux suivant.
	IT	E' il numero massimo di argomenti visualizzati per ogni feed mentre il salvaschermo e' attivo. Un valore piu' grande implica che il salvaschermo visualizzera' piu' argomenti prima di passare al prossimo feed.
	NL	Het maximum aantal te tonen items per feed terwijl de schermbeveiliger actief is. Een hogere waarde laat meer items van een feed zien voordat naar het volgende kanaal gesprongen wordt.

SETUP_PLUGIN_RSSNEWS_ITEMS_PER_FEED_CHOOSE
	CS	Položek na kanál
	DE	Einträge pro Feed
	EN	Items per channel
	ES	Elementos por canal
	FR	Eléments par flux
	IT	Argomenti per canale
	NL	Items per kanaal

SETUP_PLUGIN_RSSNEWS_FEEDS_CHANGE
	DE	RSS Feed Liste wurde geändert.
	EN	RSS Feeds list changed.
	ES	Lista de feeds de RSS modificada.
	FR	Liste des flux RSS modifiée.
	IT	Lista dei feed RSS cambiata.
	NL	RSS feeds lijst gewijzigd.
!

}

1;
