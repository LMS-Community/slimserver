package Plugins::RadioIO::Plugin;

# $Id: Plugin.pm 7196 2006-04-28 22:00:45Z andy $

# SlimServer Copyright (c) 2001-2004 Vidur Apparao, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

use strict;

use MIME::Base64;

use Slim::Buttons::Common;
use Slim::Buttons::XMLBrowser;
use Slim::Player::ProtocolHandlers;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw( string );
use Slim::Web::XMLBrowser;

use Plugins::RadioIO::ProtocolHandler;

my $FEED = 'http://www.radioio.com/opml/channelsLOGIN.php?device=Squeezebox&speed=high';
my $cli_next;

sub enabled {
	return ($::VERSION ge '6.3');
}                             

sub initPlugin {
	$::d_plugins && msg("RadioIO Plugin initializing.\n");
	
	# Backwards-compat with radioio:// protocol links
	Slim::Player::ProtocolHandlers->registerHandler('radioio', 'Plugins::RadioIO::ProtocolHandler');

	Slim::Buttons::Common::addMode('PLUGIN.RadioIO', getFunctions(), \&setMode);

#        |requires Client
#        |  |is a Query
#        |  |  |has Tags
#        |  |  |  |Function to call
#        C  Q  T  F
    Slim::Control::Request::addDispatch(['radioio', 'items', '_index', '_quantity'],
        [0, 1, 1, \&cliQuery]);
	Slim::Control::Request::addDispatch(['radioio', 'playlist', '_method' ],
		[1, 1, 1, \&cliQuery]);
	$cli_next=Slim::Control::Request::addDispatch(['radios', '_index', '_quantity' ],
		[0, 1, 1, \&cliRadiosQuery]);
}

sub addMenu {
	return 'RADIO';
}

sub getDisplayName {
	return 'PLUGIN_RADIOIO_MODULE_NAME';
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
		header   => 'PLUGIN_RADIOIO_LOADING',
		modeName => 'RadioIO Plugin',
		url      => radioIOURL($client),
		title    => $client->string(getDisplayName()),
	);

	Slim::Buttons::Common::pushMode($client, 'xmlbrowser', \%params);

	# we'll handle the push in a callback
	$client->param('handledTransition',1);
}

sub radioIOURL {
	my $client = shift;
	
	my ($username, $password);
	
	if ( $ENV{SLIM_SERVICE} ) {
		$username = $client->prefGet('plugin_radioio_username', undef, 1);
		$password = $client->prefGet('plugin_radioio_password', undef, 1);
	}
	else {
		$username = Slim::Utils::Prefs::get('plugin_radioio_username');
		$password = Slim::Utils::Prefs::get('plugin_radioio_password');
	}
	
	my $url = $FEED;
	
	if ( $username && $password ) {
		$url .= "&membername=$username&pw=" . decode_base64( $password );
	}
	
	return $url;
}

# Web pages

sub webPages {
	my $title = 'PLUGIN_RADIOIO_MODULE_NAME';
	
	if (grep {$_ eq 'RadioIO::Plugin'} Slim::Utils::Prefs::getArray('disabledplugins')) {
		Slim::Web::Pages->addPageLinks('radio', { $title => undef });
	} else {
		Slim::Web::Pages->addPageLinks('radio', { $title => 'plugins/RadioIO/index.html' });
	}
	
	my %pages = ( 
		'index.html' => sub {
			my $client = $_[0];
			my $url = radioIOURL($client);
			Slim::Web::XMLBrowser->handleWebIndex( {
				feed   => $url,
				title  => $title,
				args   => \@_
			} );
		},
	);
	
	return \%pages;
}

sub cliQuery {
	my $request = shift;
	
	$::d_plugins && msg("RadioIO: cliQuery()\n");
	
	Slim::Buttons::XMLBrowser::cliQuery('radioio', radioIOURL(), $request);
}

sub cliRadiosQuery {
	my $request = shift;
	
	$::d_plugins && msg("RadioIO: cliRadiosQuery()\n");
	
	# what we want the query to report about ourself
	my $data = {
		'cmd' => 'radioio',                    # cmd label
		'name' => Slim::Utils::Strings::string(getDisplayName()),  # nice name
		'type' => 'xmlbrowser',              # type
	};
	
	# let our super duper function do all the hard work
	Slim::Control::Queries::dynamicAutoQuery($request, 'radios', $cli_next, $data);
}

sub setupGroup {
	my %Group = (
		PrefOrder => [
			'plugin_radioio_username',
			'plugin_radioio_password',
		],
		GroupHead => string( 'PLUGIN_RADIOIO_MODULE_NAME' ),
		GroupDesc => string( 'SETUP_GROUP_PLUGIN_RADIOIO_DESC' ),
		GroupLine => 1,
		GroupSub  => 1,
		Suppress_PrefSub  => 1,
		Suppress_PrefLine => 1,
	);

	my %Prefs = (
		plugin_radioio_username => {},
		plugin_radioio_password => { 
			onChange => sub {
				my $encoded = encode_base64( $_[1]->{plugin_radioio_password}->{new} );
				chomp $encoded;
				Slim::Utils::Prefs::set( 'plugin_radioio_password', $encoded );
			},
			inputTemplate => 'setup_input_passwd.html',
			changeMsg     => string('SETUP_PLUGIN_RADIOIO_PASSWORD_CHANGED')
		},
	);

	return( \%Group, \%Prefs );
}

###
# The below code for backwards-compat with old-style radioio:// protocol links

our %stations = (
	'radioio70s'       => '3765',			
	'radioio70sPOP'    => '3910',			
	'radioio80s'       => '3795',
	'radioio80sPOP'    => '3935',	
	'radioio90s'       => '3860',
	'radioioACOUSTIC'  => '3675',
	'radioioAMBIENT'   => '3605',
	'radioioBEAT'      => '3725',
	'radioioCLASSICAL' => '3635',
	'radioioCOUNTRY'   => '3055',				 
	'radioioECLECTIC'  => '3586',
	'radioioEDGE'      => '3995',
	'radioioHISTORY'   => '3845',
	'radioioJAM'       => '3970',
	'radioioJAZZ'      => '3545',
	'radioioONE'       => '3900',
	'radioioPOP'       => '3965',
	'radioioROCK'      => '3515',
	'radioioWORLD'     => '3820',
);

our @station_names = sort keys %stations;

# Just so we don't have plain text URLs in the code.
sub decrypt {
	my $str = shift;
	
	$str =~ tr/a-zA-Z/n-za-mN-ZA-M/;
	$str =~ tr/0-9/5-90-4/;

	return $str;
}

sub getHTTPURL {
	my $key = shift;
	my $port = $stations{$key};
	my $url = "http://" . decrypt("enqvbvb.fp.yyajq.arg") . ":" . decrypt($port);
	return $url;
}

sub getRadioIOURL {
	my $num = shift;

	my $key = $station_names[$num];
	my $url = "radioio://" . $key . ".mp3";

	my %cacheEntry = (
		'TITLE' => $key,
		'CT'    => 'mp3',
		'VALID' => 1,
	);

	Slim::Music::Info::updateCacheEntry($url, \%cacheEntry);

	return $url;
}

# End backwards-compat
###

sub strings
{
	return "
PLUGIN_RADIOIO_MODULE_NAME
	EN	radioio.com - no boundaries.
	ES	radioio.com - sin límites.
	HE	רדיו אינטרנט ללא גבולות
	NL	radioio.com - geen grenzen.

PLUGIN_RADIOIO_MODULE_TITLE
	EN	radioio.com
	
PLUGIN_RADIOIO_LOADING
	DE	Lade RadioIO...
	EN	Loading RadioIO...
	FR	Chargement RadioIO...
	NL	Laden RadioIO...
	
SETUP_GROUP_PLUGIN_RADIOIO_DESC
	DE	Falls Sie einen RadioIO Account besitzen, so können Sie hier Benutzername und Passwort eingeben. <a href='http://www.radioio.com/registration.php' target='_new'>Registrierte Benutzer</a> erhalten qualitativ hochwertige 128k Streams, <a href='http://www.radioio.com/membership.php' target='_new'>SoundPass Mitglieder</a> haben Zugriff auf werbefreie Streams.
	EN	If you have a RadioIO account, enter your username and password. <a href='http://www.radioio.com/registration.php' target='_new'>Registered members</a> get high quality 128k streams, and <a href='http://www.radioio.com/membership.php' target='_new'>SoundPass members</a> have access to high quality, commercial-free streams.
	FR	Le module d'extension Aggrégateur RSS vous permet de parcourir et d'afficher le contenu de flux RSS. Les paramètres ci-dessous permettent de sélectionner les flux RSS et de modifier leur affichage sur la platine. Cliquez sur Modifier une fois les changements effectués.
	NL	Indien je een RadioIO abonnement hebt: vul je gebruikersnaam en wachtwoord in. <a href='http://www.radioio.com/registration.php' target='_new'>Geregistreerde abonnees</a> krijgen hoge kwaliteits 128k audio. <a href='http://www.radioio.com/membership.php' target='_new'>SoundPass abonnees</a> hebben toegang tot hoge kwaliteits audio zonder advertenties.

SETUP_PLUGIN_RADIOIO_USERNAME
	DE	RadioIO Benutzername
	EN	RadioIO Username
	ES	Usuario de RadioIO
	FR	Nom d'utilisateur RadioIO
	IT	Codice utente RadioIO
	NL	RadioIO gebruikersnaam

SETUP_PLUGIN_RADIOIO_USERNAME_DESC
	DE	Ihr RadioIO Benutzername, besuche <a href='http://www.radioio.com/registration.php' target='_new'>radioio.com</a> zum Einschreiben
	EN	Your RadioIO username, visit <a href='http://www.radioio.com/registration.php' target='_new'>radioio.com</a> to sign up
	ES	Tu nombre de usuario de RadioIO,  visitar <a href='http://www.radioio.com/registration.php' target='_new'>radioio.com</a> para registrarse
	FR	Si vous avez un compte RadioIO, entrez votre nom d'utilisateur et votre mot de passe pour bénéficier des flux haute qualité 128K et des flux sans publicité si vous êtes membre SoundPass.
	FR	Votre nom d'utilisateur RadioIO (visitez radioio.com pour vous inscrire) :
	IT	Il tuo codice utente su RadioIO, visita <a href='http://www.radioio.com/registration.php' target='_new'>radioio.com</a> per registrarti
	NL	Je RadioIO gebruikersnaam, bezoek <a href='http://www.radioio.com/registration.php' target='_new'>radioio.com</a> om aan te melden

SETUP_PLUGIN_RADIOIO_PASSWORD
	DE	RadioIO Passwort
	EN	RadioIO Password
	ES	Contraseña para RadioIO
	FR	Mot de passe RadioIO
	NL	RadioIO wachtwoord

SETUP_PLUGIN_RADIOIO_PASSWORD_DESC
	DE	Dein RadioIO Passwort
	EN	Your RadioIO password
	ES	Tu contraseña para RadioIO
	FR	Votre mot de passe RadioIO
	IT	La tua password RadioIO
	NL	Je RadioIO wachtwoord

SETUP_PLUGIN_RADIOIO_PASSWORD_CHANGED
	DE	Dein RadioIO Passwort wurde geändert
	EN	Your RadioIO password has been changed
	ES	La contraseña para RadioIO ha sido cambiada
	FR	Votre mot de passe RadioIO a été modifié
	IT	La tua password RadioIO e' stata cambiata
	NL	Je RadioIO wachtwoord is gewijzigd	
";}

1;
