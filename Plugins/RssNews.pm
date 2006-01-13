# RssNews Ticker v1.0
# $Id$
# Copyright (c) 2004 Slim Devices, Inc. (www.slimdevices.com)

# Based on BBCTicker 1.3 which had this copyright...
# Copyright (c) 2002-2004 Gordon Johnston (gordonj@newswall.org.uk)
# http://newswall.org.uk/~slimp3/news_ticker.html

# Also based on Vidur Apparao's Yahoo News plugin.

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

package Plugins::RssNews;

use strict;

# plugin state variables.
our %feed_urls;
our %feed_names;
our @feed_order;
our %context;

# in screensaver mode, number of items to display per channel before switching
my $screensaver_items_per_feed;

# we need to limit the number of characters we add to the ticker, because the server could crash rendering on pre-SqueezeboxG displays.
my $screensaver_chars_per_item = 1024;

# How to display items shown by screen saver.
# %1\$s is item 'number'
# %2\$s is item title
# %3\%s is item description
my $screensaver_item_format = "%2\$s -- %3\$s";
# if user is running perl 5.6, we're going to run into trouble.
# first the sprintf format defined above will not work.
if ($] < 5.008) {
	# perl version < 5.8 does not support the sprintf syntax above
	$screensaver_item_format = "%s) %s -- %s";
}

# defaults only if file not found...
use constant FEEDS_VERSION => 1.0;
our %default_feeds = (
					 'BBC News World Edition' => 'http://news.bbc.co.uk/rss/newsonline_world_edition/front_page/rss.xml',
					 'CNET News.com' => 'http://news.com.com/2547-1_3-0-5.xml',
					 'New York Times Home Page' => 'http://www.nytimes.com/services/xml/rss/nyt/HomePage.xml',
					 'RollingStone.com Music News' => 'http://www.rollingstone.com/rssxml/music_news.xml',
					 'Slashdot' => 'http://slashdot.org/index.rss',
					 'Yahoo! News: Business' => 'http://rss.news.yahoo.com/rss/business',
);




######
# CHANGELOG
######
#
# Initial version based in part on Yahoo News plugin and BbcNews.pm version 1.3
# 

######
# TODO
######
#
#
######

# INTERNAL VARIABLES and STUFF!. Do not edit.
use Slim::Buttons::Common;
use Slim::Control::Request;
use Slim::Player::Source;
use Slim::Utils::Timers;
use Slim::Utils::Misc;
use Socket;
use vars qw($VERSION);

use XML::Simple;
use File::Spec::Functions qw(:ALL);

use Slim::Utils::Prefs;

$VERSION = substr(q$Revision: 1.17 $,10);
our %thenews = ();
my $state = "wait";
# $refresh_sec is the minimum time in seconds between refreshes of the ticker from the RSS.
# Please do not lower this value. It prevents excessive queries to the RSS.
my $refresh_sec = 60 * 60;


sub strings { return q!
PLUGIN_RSSNEWS
	EN	RSS News Ticker
	ES	Ticker de Noticias RSS
	NL	RSS nieuws tikker
	
PLUGIN_RSSNEWS_ADD_NEW
	DE	Neuer Newsfeed -->
	EN	Add new feed -->
	ES	Añadir nuevo feed -->
	NL	Voeg nieuwe feed toe -->
	
PLUGIN_RSSNEWS_WAIT
	DE	Bitte warten...
	EN	Please wait requesting...
	ES	Por favor esperar, solicitando...
	NL	even wachten, opvragen...

PLUGIN_RSSNEWS_ERROR
	DE	Fehler beim Laden des RSS Feeds
	EN	Failed to retrieve RSS feed
	ES	Fallo al recuperar feed de RSS
	NL	Ophalen RSS feed niet gelukt

PLUGIN_RSSNEWS_NO_DESCRIPTION
	DE	Keine Beschreibung verfügbar
	EN	Description not available
	ES	Descripción no disponible
	NL	Beschrijving niet beschikbaar

PLUGIN_RSSNEWS_NO_TITLE
	CZ	Název není dostupný
	DE	Kein Titel verfübar
	EN	Title not available
	ES	Título no disponible
	NL	Titel niet beschikbaar

PLUGIN_RSSNEWS_SCREENSAVER
	EN	RSS News Ticker
	ES	Ticker de Noticias RSS
	NL	RSS nieuws tikker

PLUGIN_RSSNEWS_NAME
	EN	RSS News Ticker
	ES	Ticker de Noticias RSS
	NL	RSS nieuws tikker

PLUGIN_RSSNEWS_SCREENSAVER_SETTINGS
	DE	RSS News Bildschirmschoner Einstellunge
	EN	RSS News Screensaver Settings
	ES	Confugarión de Salvapantallas de Noticias RSS
	NL	RSS nieuws schermbeveiliger instellingen

PLUGIN_RSSNEWS_SCREENSAVER_ACTIVATE
	DE	Diesen Bildschirmschoner wählen
	EN	Select Current Screensaver
	ES	Elegir Salvapantallas Actual
	NL	Selecteer huidige schermbeveiliger

PLUGIN_RSSNEWS_SCREENSAVER_ACTIVATE_TITLE
	CZ	Aktuální spořič
	DE	Dieser Bildschirmschoner
	EN	Current Screensaver
	ES	Salvapantallas actual
	NL	Huidige schermbeveiliger

PLUGIN_RSSNEWS_SCREENSAVER_ACTIVATED
	CZ	Použít RSS News jako aktuální spořič
	DE	RSS News als Bildschirmschoner verwenden
	EN	Use RSS News as current screensaver
	ES	Utilizar Noticias RSS como el Salvapantallas actual
	NL	Gebruik RSS nieuws als de huidige schermbeveiliger

PLUGIN_RSSNEWS_SCREENSAVER_DEFAULT
	DE	Standard Bildschirmschoner verwenden (nicht RSS News)
	EN	Use default screensaver (not RSS News)
	ES	Utilizar salvapantallas por defecto (No el de Noticias RSS)
	NL	Gebruik standaard schermbeveiliger (niet RSS nieuws)

PLUGIN_RSSNEWS_SCREENSAVER_ENABLE
	DE	Newsticker als Bildschirmschoner verwenden
	EN	Activating ticker as current screensaver
	ES	Activando ticker como nuevo salvapantallas
	NL	Activeren van de RSS tikker als huidige schermbeveiliger

PLUGIN_RSSNEWS_SCREENSAVER_DISABLE
	DE	Standard Bildschirmschoner wird verwendet
	EN	Returning to default screensaver
	ES	Volviendo al Salvapantallas por defecto
	NL	Instellen van standaard schermbeveiliger

PLUGIN_RSSNEWS_ERROR_IN_FEED
	DE	Fehler beim Parsen dess RSS Feeds
	EN	Error parsing RSS feed
	ES	Error analizando feed de RSS
	NL	Fout bij analyseren RSS feed

PLUGIN_RSSNEWS_LOADING_FEED
	DE	RSS Feed wird geladen...
	EN	Loading RSS feed...
	ES	Cargando feed de RSS
	NL	Laden RSS feed...

SETUP_GROUP_PLUGIN_RSSNEWS
	EN	RSS News Ticker
	ES	Ticker de noticias de RSS
	NL	RSS nieuws tikker

SETUP_GROUP_PLUGIN_RSSNEWS_DESC
	DE	Das RSS News Ticker Plugin kann verwendet werden, um RSS Feeds zu durchsuchen und lesen. Die folgenden Einstellungen helfen ihnen beim Definieren der anzuzeigenden RSS Feeds, und wie diese dargestellt werden sollen. Klicken Sie auf Ändern, um die Änderungen zu aktivieren.
	EN	The RSS News Ticker plugin can be used to browse and display items from RSS Feeds. The preferences below can be used to determine which RSS Feeds to use and control how they are displayed. Click on the Change button when you are done.
	ES	El plugin de Ticker de Noticias RSS puede utilizarse para buscar y mostrar artículos de feeds de RSS. Las preferencias debajo pueden utilizarse para elegir que feed utilizar y controlar como se muestra. Presionar el botón Cambiar cuando se haya finalizado.
	NL	Je kunt de RSS nieuws tikker plugin gebruiken om RSS feeds te bekijken. Met de instellingen hieronder kun je RSS feeds selecteren en aangeven hoe ze getoond moeten worden. Klik op de knop Veranderen om de wijzigingen te bewaren.

SETUP_PLUGIN_RSSNEWS_FEEDS
	DE	RSS Feeds ändern
	EN	Modify RSS feeds
	ES	Modificar feeds de RSS
	NL	Pas RSS feeds aan

SETUP_PLUGIN_RSSNEWS_FEEDS_DESC
	DE	Dies ist die Liste der anzuzeigenden RSS Feeds. Um einen neuen zu abonnieren, tippen Sie einfach dessen URL in eine leere Zeile. Um einen Feed zu entfernen, löschen Sie dessen URL. Bestehende URLs können im entsprechenden Feld bearbeitet werden. Klicken Sie auf Ändern, um die Änderungen zu aktivieren.
	EN	This is the list of RSS Feeds to display. To add a new one, just type its URL into the empty line. To remove one, simply delete the URL from the corresponding line. To change the URL of an existing feed, edit its text value. Click on the Change button when you are done.
	ES	Esta es la lista de feeds de RSS. Para añadir un nuevo feed, escribir la URL en la línea vacía. Para elminar uno, simplemente borrar la URL de la línea correspondiente. Para cambiar la URL de un feed existente, editar el texto correspondiente. Hacer click en Cambiar cuando se haya finalizado.
	NL	Dit is de te tonen lijst met RSS feeds. Om een nieuwe toe te voegen voer je de URL toe in het lege invoerveld. Om een RSS feed te weg te halen verwijder je de tekst. Om een RSS feed te wijzigen pas je de tekst aan. Klik op de knop Veranderen om de wijzigingen te bewaren.

SETUP_PLUGIN_RSSNEWS_RESET
	DE	Standard Feeds wieder herstellen
	EN	Reset default RSS feeds
	ES	Reestablecer feeds de RSS por defecto
	NL	Herstel standaard RSS feeds

SETUP_PLUGIN_RSSNEWS_RESET_DESC
	DE	Klicken Sie auf den Reset Knopf, um die Standard RSS Feeds zu reaktivieren.
	EN	Click the Reset button to revert to the default set of RSS Feeds.
	ES	Presionar el botón de Restablecer para volver al conjunto de valores por defecto de feeds de RSS.
	NL	Klik op de herstel knop om de standaard RSS feeds opnieuw in te stellen.

PLUGIN_RSSNEWS_RESETTING
	DE	RSS Feeds wurden auf Standardwerte zurückgesetzt.
	EN	Resetting to default RSS Feeds.
	ES	Reestableciendo el feed  de RSS por defecto
	NL	Herstellen standaard RSS feeds.

SETUP_PLUGIN_RSSNEWS_RESET_BUTTON
	CZ	Resetovat
	DE	Zurücksetzen
	EN	Reset
	ES	Reestablecer
	NL	Herstel

SETUP_PLUGIN_RSSNEWS_ITEMS_PER_FEED
	DE	Anzahl Einträge pro Feed
	EN	Items displayed per channel
	ES	Elementos mostrados por canal
	NL	Items getoond kanaal

SETUP_PLUGIN_RSSNEWS_ITEMS_PER_FEED_DESC
	DE	Definieren Sie die Anzahl Einträge, die im Bildschirmschonermodus pro Feed angezeigt werden sollen. Eine grössere Anzahl hat zur Folge, dass mehr Einträge angezeigt werden, bevor der nächste Feed angezeigt wird.
	EN	The maximum number of items displayed for each feed while the screensaver is active. A larger value implies that the screensaver will display more items before switching to the next feed.
	ES	El número máximo de elementos mostrados, para cada feed, mientras el salvapantallas está activo. Un valor más alto implica que el salvapantal>las mostrará más elementos antes de pasar al próximo feed.
	NL	Het maximum aantal te tonen items voor elke feed wanneer de schermbeveiliger actief is. Een hogere waarde zorgt ervoor dat de schermbeveiliger meer items toont voor door te gaan naar de volgende feed.

SETUP_PLUGIN_RSSNEWS_ITEMS_PER_FEED_CHOOSE
	CZ	Položek na kanál
	DE	Einträge pro Feed
	EN	Items per channel
	ES	Elementos por canal
	NL	Items per kanaal

SETUP_PLUGIN_RSSNEWS_FEEDS_CHANGE
	DE	RSS Feed Liste wurde geändert.
	EN	RSS Feeds list changed.
	ES	Lista de feeds de RSS modificada.
	NL	RSS feeds lijst gewijzigd.
!};

# Plugin descriptions

sub getDisplayName {
	return 'PLUGIN_RSSNEWS';
}

# advance to next RSS feed
sub nextTopic {
	my $client = shift;
	my $display_current;
	
	my $display_stack = $client->param('PLUGIN.RssNews.display_stack');
	#if there are no topics left then wrap around if selected (always wrap when running as screensaver)
	if((!$display_stack) ||
	   (scalar(@$display_stack) == 0)) {
		my @display_stack_copy = @feed_order;
		$display_stack = \@display_stack_copy;
		$client->param('PLUGIN.RssNews.display_stack', $display_stack);
	}
	
	#Move up the list of topics
	if($display_stack) {
		$display_current=shift @{$display_stack};
		if (!$display_current) {
			$::d_plugins && msg("RssNews: display_current not set!\n");
			$::d_plugins && msg("RssNews: feed order:\n" . 
								join('\n', @feed_order) . "\n");
		} else {
			$d::plugins && msg("RssNews: display_current is $display_current\n");
		}
		$client->param('PLUGIN.RssNews.display_current', $display_current);
	} else {
		assert(0, 'display stack empty');
	}
	# returns a feed name (not the URL)
	return $display_current;
}

sub enabled {
	return ($::VERSION ge '6.1');
}


# initialize the list of channels (feeds) to display
sub initPlugin {
	my @feedURLPrefs = Slim::Utils::Prefs::getArray("plugin_RssNews_feeds");
	my @feedNamePrefs = Slim::Utils::Prefs::getArray("plugin_RssNews_names");
	my $feedsModified = Slim::Utils::Prefs::get("plugin_RssNews_feeds_modified");
	my $version = Slim::Utils::Prefs::get("plugin_RssNews_feeds_version");

	# No prefs set or we've had a version change and they weren't modified, 
	# so we'll use the defaults
	if (scalar(@feedURLPrefs) == 0 || 
		(!$feedsModified && (!$version  || $version != FEEDS_VERSION))) {
		my @default_names = sort(keys (%default_feeds));
		@feedURLPrefs = map $default_feeds{$_}, @default_names;
		Slim::Utils::Prefs::set("plugin_RssNews_feeds", \@feedURLPrefs);
		@feedNamePrefs = @default_names;
		Slim::Utils::Prefs::set("plugin_RssNews_names", \@feedNamePrefs);
		Slim::Utils::Prefs::set("plugin_RssNews_feeds_version", FEEDS_VERSION);
	}

	@feed_urls{@feedNamePrefs} = @feedURLPrefs;
	%feed_names = reverse %feed_urls;
	@feed_order = @feedNamePrefs;

	if ($::d_plugins) {
		msg("RSS Feed Info:\n");
		foreach (@feed_order) {
			msg("$_, $feed_urls{$_} \n");
		}
		msg("\n");
	}

	$screensaver_items_per_feed = Slim::Utils::Prefs::get('plugin_RssNews_items_per_feed');
	unless (defined $screensaver_items_per_feed) {
		$screensaver_items_per_feed = 3;
		Slim::Utils::Prefs::set('plugin_RssNews_items_per_feed', 
								$screensaver_items_per_feed);
	}
}

sub updateFeedNames {
	my @feedURLPrefs = Slim::Utils::Prefs::getArray("plugin_RssNews_feeds");
	my @names = ();

	for my $feed (@feedURLPrefs) {
		if ($feed) {
			my $name = $feed_names{$feed};
			if ($name && $name !~ /^(?:http|file)\:/) {
				push @names, $name;
			} elsif ($feed =~ /^(?:http|file)\:/) {
				my $xml = getFeedXml($feed);
				if ($xml && exists $xml->{channel}->{title}) {
					# trim required to remove leading newlines
					push @names, trim($xml->{channel}->{title});
				}
				else {
					push @names, trim($feed);
				}
			}
		}
	}

	# No prefs set, so we'll use the defaults
	if (scalar(@names) == 0) {
		my @default_names = sort(keys (%default_feeds));
		@feedURLPrefs = map {$default_feeds{$_}} @default_names;
		Slim::Utils::Prefs::set("plugin_RssNews_feeds", \@feedURLPrefs);
		Slim::Utils::Prefs::set("plugin_RssNews_names", \@default_names);
		@names = @default_names;
	}
	elsif (join('', sort @feedURLPrefs) ne join('', sort values %default_feeds)) {
		Slim::Utils::Prefs::set("plugin_RssNews_feeds_modified", 1);
	}

	Slim::Utils::Prefs::set("plugin_RssNews_names", \@names);
	@feed_urls{@names} = @feedURLPrefs;
	%feed_names = reverse %feed_urls;
	@feed_order = @names;	
}

sub unescape {
	my $data = shift;

	return '' unless(defined($data));

	use utf8; # required for 5.6
	
	$data =~ s/&amp;/&/sg;
	$data =~ s/&lt;/</sg;
	$data =~ s/&gt;/>/sg;
	$data =~ s/&quot;/\"/sg;
	$data =~ s/&bull;/\*/sg;
	$data =~ s/&pound;/\xa3/sg;
	$data =~ s/&mdash;/-/sg;
	$data =~ s/&\#(\d+);/chr($1)/gse;

	return $data;
}

sub trim {
	my $data = shift;
	return '' unless(defined($data));
	use utf8; # important for regexps that follow

	$data =~ s/\s+/ /g; # condense multiple spaces
	$data =~ s/^\s//g; # remove leading space
	$data =~ s/\s$//g; # remove trailing spaces

	return $data;
}

# unescape and also remove unnecesary spaces
# also get rid of markup tags
sub unescapeAndTrim {
	my $data = shift;
	return '' unless(defined($data));
	use utf8; # important for regexps that follow
	my $olddata = $data;
	
	$data = unescape($data);

	$data = trim($data);
	
	# strip all markup tags
	$data =~ s/<[a-zA-Z\/][^>]*>//gi;

	# apparently utf8::decode is not available in perl 5.6.
	# (Some characters may not appear correctly in perl < 5.8 !)
	if ($] >= 5.008) {
		utf8::decode($data);
	}

	return $data;
}

# see bug 1307
# avoid deep recursion
my $getFeedXml_semaphore = 0;

sub getFeedXml {
	my $feed_url = shift;

	$::d_plugins && msg("RssNews: getting feed from $feed_url\n");

	# bug 1307.  Avoid recursion.
	if ($getFeedXml_semaphore) {
		return 0;
	} else {
		$getFeedXml_semaphore = 1;
	}

    if ($feed_url =~ /^file/)
    {
		my $feed_file = $feed_url;
		$feed_file =~ s/^file://;
		$feed_file =~ s/^\/+/\//;
		#accomodate windows drive letter suckiness
		$feed_file =~ s/^\/([a-z]:)/$1/i;

		open (DIN, $feed_file);
        if ($@) {
			$::d_plugins && msg("RssNews failed to parse feed <$feed_url> because:\n$@");
			$getFeedXml_semaphore = 0;
			return 0;
        }
		my @content = <DIN>;
		close DIN;
		my $content = join ("\n", @content);

        my $xml = eval { XMLin($content, forcearray => ["item"], keyattr => []) };
		$getFeedXml_semaphore = 0;

        if ($@) {
			$::d_plugins && msg("RssNews failed to parse feed <$feed_url> because:\n$@");
			return 0;
        }
		return ($xml);	
    }

	my $http = Slim::Player::Protocols::HTTP->new({
		'url'    => $feed_url,
		'create' => 0,
	});

	if (defined $http) {

		my $content = $http->content();

		$http->close();

		return 0 unless defined $content;

		# very verbose debugging
		#$::d_plugins && msg("RssNews: $feed_url\n");
		#$::d_plugins && msg("\n$content\n\n");

		# forcearray to treat items as array,
		# keyattr => [] prevents id attrs from overriding
		my $xml = eval { XMLin($content, forcearray => ["item"], keyattr => []) };

		$getFeedXml_semaphore = 0;

		if ($@) {
			$::d_plugins && msg("RssNews failed to parse feed <$feed_url> because:\n$@");
			return 0;
		}

		return $xml;
	}

	$getFeedXml_semaphore = 0;
	return 0;
}

sub retrieveNews {
	my $client = shift;
	my $feedname = shift;

	my $now = time();
    
	my $must_get_news = 0;
	my $display_current = $client->param('PLUGIN.RssNews.display_current');

	if (!$display_current) {
		# should never be here, but just in case...
		$display_current = nextTopic($client);
	}
	
	if (!$feedname) {
		$feedname = $display_current;
	}
    
	if (!$thenews{$feedname}) {
		$must_get_news = 1;
	} elsif ($now - $thenews{$feedname}{"refresh_last"} > $refresh_sec) {
		$must_get_news = 1;
	}

	if ($must_get_news) {
		$thenews{$feedname} = ();
		if (!$client->param('PLUGIN.RssNews.screensaver_mode')){
			$client->block( {
				'line1' => $client->string('PLUGIN_RSSNEWS_LOADING_FEED'),
			});
		}

		my $xml = getFeedXml($feed_urls{$feedname});

		if (!$client->param('PLUGIN.RssNews.screensaver_mode')) {
			$client->unblock();
		}

		my $show_error = 0;
		if ($xml) {
			if ($xml->{channel}) {
				$thenews{$feedname} = $xml->{channel};
				# slashdot needs this, yahoo doesn't
				if ($xml->{item}) {
					$thenews{$feedname}->{item} = $xml->{item};
				}
			} else {
				# TODO: better error handling
				$::d_plugins && msg("RssNews: failed to parse from $feed_urls{$feedname}. \n");
				$::d_plugins && msg("RssNews: Here's the xml:\n\n$xml\n\n");
				$show_error = 1;
			}
		} else {
			# TODO: better error handling
			$::d_plugins && msg("RssNews.pm failed to retrieve news from $feed_urls{$feedname}.\n");
			$show_error = 1;
		}
		if ($show_error) {
			# we did not get the news
			$client->showBriefly( {
				'line1' => $client->string('PLUGIN_RSSNEWS_ERROR_IN_FEED'),
			});
		} else {
			# record the time we last got the news
			$thenews{$feedname}{"refresh_last"} = $now;
		}
	}
	
	return $thenews{$feedname};
}

sub setupGroup {
	my %Group = (
		PrefOrder => [
			'plugin_RssNews_items_per_feed', 'plugin_RssNews_reset', 'plugin_RssNews_feeds', 
		],
		GroupHead => Slim::Utils::Strings::string('SETUP_GROUP_PLUGIN_RSSNEWS'),
		GroupDesc => Slim::Utils::Strings::string('SETUP_GROUP_PLUGIN_RSSNEWS_DESC'),
		GroupLine => 1,
		GroupSub => 1,
		Suppress_PrefSub  => 1,
		Suppress_PrefLine => 1,
	);

	my %Prefs = (
		plugin_RssNews_items_per_feed => {
			'validate' => \&Slim::Web::Setup::validateInt
			,'validateArgs' => [1,undef,1]
			,'onChange' => sub {
				$screensaver_items_per_feed = $_[1]->{plugin_RssNews_items_per_feed}->{new};
				Slim::Utils::Prefs::set('plugin_RssNews_items_per_feed', 
										$screensaver_items_per_feed);
			}
		},
		plugin_RssNews_reset => {
			'validate' => \&Slim::Web::Setup::validateAcceptAll
			,'onChange' => sub {
				Slim::Utils::Prefs::set("plugin_RssNews_feeds_modified", undef);
				Slim::Utils::Prefs::set("plugin_RssNews_feeds_version", undef);
				initPlugin();
			}
			,'inputTemplate' => 'setup_input_submit.html'
			,'changeIntro' => Slim::Utils::Strings::string('PLUGIN_RSSNEWS_RESETTING')
			,'ChangeButton' => Slim::Utils::Strings::string('SETUP_PLUGIN_RSSNEWS_RESET_BUTTON')
			,'dontSet' => 1
			,'changeMsg' => ''
		},
		plugin_RssNews_feeds => { 
			'isArray' => 1
			,'arrayAddExtra' => 1
			,'arrayDeleteNull' => 1
			,'arrayDeleteValue' => ''
			,'arrayBasicValue' => 0
			,'PrefSize' => 'large'
			,'inputTemplate' => 'setup_input_array_txt.html'
			,'PrefInTable' => 1
			,'showTextExtValue' => 1
			,'externalValue' => sub {
				my ($client, $value, $key) = @_;
				
				if ($key =~ /^(\D*)(\d+)$/ && ($2 < scalar(@feed_order))) {
					return $feed_order[$2];
				}

				return '';
			}
			,'onChange' => sub {
				my ($client,$changeref,$paramref,$pageref) = @_;
				if (exists($changeref->{'plugin_RssNews_feeds'}{'Processed'})) {
					return;
				}
				Slim::Web::Setup::processArrayChange($client, 'plugin_RssNews_feeds', $paramref, $pageref);
				updateFeedNames();

				$changeref->{'plugin_RssNews_feeds'}{'Processed'} = 1;
			}
			,'changeMsg' => Slim::Utils::Strings::string('SETUP_PLUGIN_RSSNEWS_FEEDS_CHANGE')
		},
	);

	return( \%Group, \%Prefs );
}


################################
# ScreenSaver Mode
#

sub tickerUpdate {
	my $client = shift;

	if ($client->param('PLUGIN.RssNews.newfeed')) {
		# fetch new feed
		my $display_current = &nextTopic($client);
		# retrieveNews will only really get new news after refresh_sec time
		retrieveNews($client, $display_current);
		$client->param('PLUGIN.RssNews.line1', 0);
	}

	# add item to ticker
	$client->update(tickerLines($client));
		
	my ($complete, $queue) = $client->scrollTickerTimeLeft();
	my $newfeed = $client->param('PLUGIN.RssNews.newfeed');

	# schedule for next item as soon as queue drains if same feed or after ticker completes if new feed
	my $next = $newfeed ? $complete : $queue;
	Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + (($next > 1) ? $next : 1), \&tickerUpdate);
}

sub tickerUpdateCheck {
	# check to see if ticker is empty and schedule immediate ticker update if so
	my $client = shift;
	my ($complete, $queue) = $client->scrollTickerTimeLeft();

	if ($queue == 0 && Slim::Utils::Timers::killTimers($client, \&tickerUpdate)) {
		tickerUpdate($client);
	}
}

sub blankLines {
	# lines when called by server - e.g. on screensaver start or change of font size
	# add undef line2 item to ticker, schedule tickerUpdate to add to ticker if necessary
	my $client = shift;

	my $parts = {
		'line1' => $client->param('PLUGIN.RssNews.line1') || '',
		'line2' => undef,
		'scrollmode' => 'ticker'
	};

	# check after the update calling this function is complete to see if ticker is empty
	# (to refill ticker on font size change as this clears current ticker)
	Slim::Utils::Timers::killTimers($client, \&tickerUpdateCheck);	
	Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + 0.1, \&tickerUpdateCheck);

	return $parts;
}

sub tickerLines {
	# lines for tickerUpdate to add to ticker
	my $client = shift;

	my $parts;
	my $new_feed_next = 0; # use new feed next call

	# the current RSS feed
	my $display_current = $client->param('PLUGIN.RssNews.display_current');
	assert($display_current, "current rss feed not set\n");

	# the current item within each feed.
	my $display_current_items = $client->param('PLUGIN.RssNews.display_current_items');

	if (!defined ($display_current_items)) {
		$display_current_items = {$display_current => {'next_item' => 0, 'first_item' => 0}};
	} elsif (!defined($display_current_items->{$display_current})) {
		$display_current_items->{$display_current} = {'next_item' => 0, 'first_item' => 0};
	}
	
	# add item to ticker or display error and wait for tickerUpdate to retrieve news
	if (defined($thenews{$display_current})) {
	
		my $line1 = unescapeAndTrim($thenews{$display_current}->{title});
		my $i = $display_current_items->{$display_current}->{'next_item'};
		my $description;

		if ((!($thenews{$display_current}->{item}[$i]->{description})) ||
			ref ($thenews{$display_current}->{item}[$i]->{description})) {
			# description not available, just show title
			$description = "";
		} else {
			$description = $thenews{$display_current}->{item}[$i]->{description};
		}

		my $line2 = sprintf($screensaver_item_format,
						   $i + 1,
						   unescapeAndTrim($thenews{$display_current}->{item}[$i]->{title}),
						   unescapeAndTrim($description));

		if (length($line2) > $screensaver_chars_per_item) {
			$line2 = substr($line2, 0, $screensaver_chars_per_item);
			$::d_plugins && msg("RssNews screensaver character limit exceeded - truncating.\n");
		}

		$display_current_items->{$display_current}->{'next_item'} = $i + 1;
		if (!exists($thenews{$display_current}->{item}[$display_current_items->{$display_current}->{'next_item'}])) {
			$display_current_items->{$display_current}->{'next_item'} = 0;
			$display_current_items->{$display_current}->{'first_item'} -= ($i + 1);
			if ($screensaver_items_per_feed >= ($i + 1)) {
				$new_feed_next = 1;
				$display_current_items->{$display_current}->{'first_item'} = 0;
			}
		}

		if (($display_current_items->{$display_current}->{'next_item'} - $display_current_items->{$display_current}->{'first_item'}) >= $screensaver_items_per_feed) {
			# displayed $screensaver_items_per_feed of this feed, move on to next saving position
			$new_feed_next = 1;
			$display_current_items->{$display_current}->{'first_item'} = $display_current_items->{$display_current}->{'next_item'};
		}

		$parts = {
			'line1' => $line1,
			'line2' => $line2,
			'scrollmode' => 'ticker',
		};
		$client->param('PLUGIN.RssNews.line1', $line1);
		$client->param('PLUGIN.RssNews.display_current_items', $display_current_items);

	} else {

		$parts = {
			'line1' => "RSS News - ".$display_current,
			'line2' => ($state eq 'wait') ? $client->string('PLUGIN_RSSNEWS_WAIT') : $client->string('PLUGIN_RSSNEWS_ERROR'),
		};
		$new_feed_next = 1;
	}

	$client->param('PLUGIN.RssNews.newfeed', $new_feed_next);

	return $parts;
}

sub screenSaver {
	Slim::Utils::Strings::addStrings(&strings());

	Slim::Buttons::Common::addSaver(
		'SCREENSAVER.rssnews',
		getScreensaverRssNews(),
		\&setScreensaverRssNewsMode,
		\&leaveScreenSaverRssNews,
		'PLUGIN_RSSNEWS_SCREENSAVER'
	);
}

our %screensaverRssNewsFunctions = (
	'done' => sub  {
		my ($client, $funct, $functarg) = @_;
		Slim::Buttons::Common::popMode($client);
		$client->update();
		#pass along ir code to new mode if requested
		if (defined $functarg && $functarg eq 'passback') {
			Slim::Hardware::IR::resendButton($client);
		}
	}
);

sub getScreensaverRssNews {
        return \%screensaverRssNewsFunctions;
}


sub setScreensaverRssNewsMode() {
	my $client = shift;

	# init params
	$client->param('PLUGIN.RssNews.newfeed', 1);
	$client->param('PLUGIN.RssNews.line1', 0);
	$client->param('PLUGIN.RssNews.screensaver_mode', 1);
	$client->lines(\&blankLines);

	# start tickerUpdate in future after updates() caused by server mode change
	Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + 0.5, \&tickerUpdate);
}

sub leaveScreenSaverRssNews {
	# kill tickerUpdate
	my $client = shift;
	Slim::Utils::Timers::killTimers($client, \&tickerUpdate);
	Slim::Utils::Timers::killTimers($client, \&tickerUpdateCheck);
	$client->param('PLUGIN.RssNews.screensaver_mode', 0);
}


#############################
# Screensaver Settings Mode
#

my @screensaverSettingsMenu = ('PLUGIN_RSSNEWS_SCREENSAVER_ACTIVATE');
our %current;
our %menuParams = (
				  'rssnews' => {
					  'listRef' => \@screensaverSettingsMenu
						  ,'stringExternRef' => 1
						  ,'header' => 'PLUGIN_RSSNEWS_SCREENSAVER_SETTINGS'
						  ,'stringHeader' => 1
						  ,'headerAddCount' => 1
						  ,'callback' => \&screensaverSettingsCallback
						  ,'overlayRef' => sub {return (undef,Slim::Display::Display::symbol('rightarrow'));}
					  ,'overlayRefArgs' => ''
					  }
				  ,catdir('rssnews','PLUGIN_RSSNEWS_SCREENSAVER_ACTIVATE') => {
					  'useMode' => 'INPUT.List'
						  ,'listRef' => [0,1]
						  ,'externRef' => ['PLUGIN_RSSNEWS_SCREENSAVER_DEFAULT', 'PLUGIN_RSSNEWS_SCREENSAVER_ACTIVATED']
						  ,'stringExternRef' => 1
						  ,'header' => 'PLUGIN_RSSNEWS_SCREENSAVER_ACTIVATE_TITLE'
						  ,'stringHeader' => 1
						  ,'onChange' => sub { $_[0]->prefSet('screensaver',$_[1]?'SCREENSAVER.rssnews':'screensaver'); }
					  ,'onChangeArgs' => 'CV'
						  ,'initialValue' => sub { ($_[0]->prefGet('screensaver') eq 'SCREENSAVER.rssnews' ? 1 : 0); }
				  }
				  );

sub screensaverSettingsCallback {
	my ($client,$exittype) = @_;
	$exittype = uc($exittype);
	if ($exittype eq 'LEFT') {
		Slim::Buttons::Common::popModeRight($client);
	} elsif ($exittype eq 'RIGHT') {
		my $nextmenu = catdir('rssnews',$current{$client});
		if (exists($menuParams{$nextmenu})) {
			my %nextParams = %{$menuParams{$nextmenu}};
			if ($nextParams{'useMode'} eq 'INPUT.List' && exists($nextParams{'initialValue'})) {
				#set up valueRef for current pref
				my $value;
				if (ref($nextParams{'initialValue'}) eq 'CODE') {
					$value = $nextParams{'initialValue'}->($client);
				} else {
					$value = $client->prefGet($nextParams{'initialValue'});
				}
				$nextParams{'valueRef'} = \$value;
			}
			Slim::Buttons::Common::pushModeLeft(
												$client
												,$nextParams{'useMode'}
												,\%nextParams
												);
		} else {
			$client->bumpRight();
		}
	} else {
		return;
	}
}

sub screensaverSettingsSetMode {
	my $client = shift;
	my $method = shift;
	
	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}
	my %params = %{$menuParams{'rssnews'}};
	$params{'valueRef'} = \$current{$client};
	
	Slim::Buttons::Common::pushMode($client,'INPUT.List',\%params);
}

our %noModeFunctions = ();

Slim::Buttons::Common::addMode('PLUGIN.RssNews.screensaversettings', 
                               \%noModeFunctions, 
                               \&screensaverSettingsSetMode);






#############################
# Main mode
# 

sub mainModeCallback {
	my ($client,$exittype) = @_;
    
	$exittype = uc($exittype);
	if ($exittype eq 'LEFT') {
		Slim::Buttons::Common::popModeRight($client);
	} 
	elsif ($exittype eq 'RIGHT') {
		my $listIndex = $client->param('listIndex');
		my $feedname = $feed_order[$listIndex];
        
		retrieveNews($client, $feedname);
		
		if ($thenews{$feedname} &&
			$thenews{$feedname}) {
			Slim::Buttons::Common::pushModeLeft($client, 
                                                'PLUGIN.RssNews.headlines',
                                                { feed => unescapeAndTrim($thenews{$feedname}->{title}),
                                                  feedItems => $thenews{$feedname}->{item} });
		} else {
			$client->showBriefly( {
				'line1' => $client->string('PLUGIN_RSSNEWS_ERROR'),
			});
			return;  
		}
	}
}

sub setMode {
	my $client = shift;
	my $method = shift;

	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}
        
	my %params = (
				  stringHeader => 1,
				  header => 'PLUGIN_RSSNEWS_NAME',
				  listRef => \@feed_order,
				  callback => \&mainModeCallback,
				  valueRef => \$context{$client}->{mainModeIndex},
				  headerAddCount => 1,
				  overlayRef => sub {return (undef,Slim::Display::Display::symbol('rightarrow'));},
				  parentMode => Slim::Buttons::Common::mode($client),		  
				  );
        
	Slim::Buttons::Common::pushMode($client,'INPUT.List',\%params);
}

# needed in getFunctions
our %mainModeFunctions = ();

# The server will call this subroutine
sub getFunctions() {
	return \%mainModeFunctions;
}


#############################
# Headlines mode
# 

sub headlinesModeCallback {
	my ($client,$exittype) = @_;

	$exittype = uc($exittype);
	if ($exittype eq 'LEFT') {
		Slim::Buttons::Common::popModeRight($client);
	} 
	elsif ($exittype eq 'RIGHT') {
		my $listIndex = $client->param('listIndex');
		my $items = $client->param('feedItems');

		my $item = $items->[$listIndex];
		my $description;
		if (!$item->{description} ||
			ref($item->{description})) {
			$description = $client->string('PLUGIN_RSSNEWS_NO_DESCRIPTION');
			# we could show them an error message about no description found, but instead just bump.
			$client->bumpRight();
			return;
		} else {
			$description = $item->{description};
		}
		my $title;
		if ($item->{title}) {
			$title = $item->{title};
		} else {
			$title = $client->string('PLUGIN_RSSNEWS_NO_TITLE');
		}
		my $feed = $client->param('feed');
        
		Slim::Buttons::Common::pushModeLeft($client, 
                                            'PLUGIN.RssNews.description',
                                            { feed => $feed,
                                              title => "$title",
                                              description => "$description" });
	}
}

our %headlinesModeFunctions = ();

sub headlinesSetMode {
	my $client = shift;
	my $method = shift;
    
	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}
    
	my $feed = $client->param('feed');
	my $items = $client->param('feedItems');
    
	my @lines = map unescapeAndTrim($_->{title}), @$items;
    
	my %params = (
                  header => $feed,
                  listRef => \@lines,
                  callback => \&headlinesModeCallback,
                  valueRef => \$context{$client}->{headlinesModeIndex},
                  headerAddCount => 1,
				  # show right arrow only if list not empty
                  overlayRef => scalar(@lines) ? sub {return (undef,Slim::Display::Display::symbol('rightarrow'));} : undef,
                  parentMode => Slim::Buttons::Common::mode($client),		  
                  feed => $feed,		  
                  feedItems => $items,
                  );
    
	Slim::Buttons::Common::pushMode($client,'INPUT.List',\%params);
}

Slim::Buttons::Common::addMode('PLUGIN.RssNews.headlines', 
                               \%headlinesModeFunctions, 
                               \&headlinesSetMode);


#############################
# Descriptions mode
# 

sub descriptionModeCallback {
	my ($client,$exittype) = @_;
    
    $exittype = uc($exittype);
	if ($exittype eq 'LEFT') {
		Slim::Buttons::Common::popModeRight($client);
	} 
	elsif ($exittype eq 'RIGHT') {
		$client->bumpRight();
	}
}

our %descriptionModeFunctions = ();

sub descriptionSetMode {
	my $client = shift;
	my $method = shift;
    
	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}
    
	my $feed = $client->param('feed');
	my $title = unescapeAndTrim($client->param('title'));
	my $description = unescapeAndTrim($client->param('description'));
    
	my @lines;
	my $curline = '';
	# break story up into lines.
	while ($description =~ /(\S+)/g) {
		my $newline = $curline . ' ' . $1;
		if ($client->measureText($newline, 2) > $client->displayWidth) {
			push @lines, trim($curline);
			$curline = $1;
		}
		else {
			$curline = $newline;
		}
	}
	if ($curline) {
		push @lines, trim($curline);
	}
    
	# also shorten title to fit
	# leave a bunch of extra pixels to display the (n out of M) text
	my $titleline = '';
	while ($title =~ /(\S+)/g) {
		my $newline = $titleline . ' ' . $1;
		if ($client->measureText($newline . "... (?? of ??)", 1) > ($client->displayWidth)) {
			$titleline .= '...';
			last;
		} else {
			$titleline = $newline;
		}
	}
    
	my %params = (
                  header => trim($titleline),
                  listRef => \@lines,
                  callback => \&descriptionModeCallback,
                  valueRef => \$context{$client}->{descriptionModeIndex},
                  headerAddCount => 1,
                  parentMode => Slim::Buttons::Common::mode($client),		  
                  );
    
	Slim::Buttons::Common::pushMode($client,'INPUT.List',\%params);
    
}

Slim::Buttons::Common::addMode('PLUGIN.RssNews.description', 
                               \%descriptionModeFunctions, 
                               \&descriptionSetMode);

sub addMenu {
	# some questionable code follows... This method is designed to simply
	# return the name of a menu.  But this plugin wants to appear both
	# in plugins and screensavers.

	# it would be nice if the plugin code gave us a clean way to do
	# this.  Until it does, we do the following hack.

	if (grep {$_ eq 'RssNews'} Slim::Utils::Prefs::getArray('disabledplugins')) {
		Slim::Buttons::Home::addSubMenu("SCREENSAVERS","PLUGIN_RSSNEWS_SCREENSAVER", undef);
	} else {
		# add a mode to the screensaver submenu...
		my %params = ('useMode' => "PLUGIN.RssNews.screensaversettings",
					  'header' => "PLUGIN_RSSNEWS_SCREENSAVER");
		Slim::Buttons::Home::addSubMenu("SCREENSAVERS","PLUGIN_RSSNEWS_SCREENSAVER", \%params);
	}

	# also add ourselves to the plugins menu
	return "PLUGINS";
}


1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
