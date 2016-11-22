package Slim::Web::Pages::Home;

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;

use Data::URIEncode qw(complex_to_query);
use Digest::MD5 qw(md5_hex);
use HTTP::Status qw(RC_MOVED_TEMPORARILY);

use Slim::Utils::Cache;
use Slim::Utils::Prefs;
use Slim::Utils::Strings;
use Slim::Networking::Discovery::Server;
use Slim::Plugin::Base;

my $prefs = preferences('server');
my $cache = Slim::Utils::Cache->new;

# known skins which don't need all the overhead of DB related variables in index.html
my %lightIndex = (
	Default => 1,
	EN => 1,
	Classic => 1,
);

sub init {
	Slim::Web::Pages->addPageFunction(qr/^$/, \&home);
	Slim::Web::Pages->addPageFunction(qr/^home\.(?:htm|xml)/, \&home);
	Slim::Web::Pages->addPageFunction(qr/^index\.(?:htm|xml)/, \&home);
	Slim::Web::Pages->addPageFunction(qr/^switchserver\.(?:htm|xml)/, \&switchServer);
	Slim::Web::Pages->addPageFunction(qr/^updateinfo\.htm/, \&updateInfo);
	
	Slim::Web::Pages->addPageLinks('my_apps', {'PLUGIN_APP_GALLERY_MODULE_NAME' => Slim::Networking::SqueezeNetwork->url('/appgallery') }) if !main::NOMYSB;

	Slim::Web::Pages->addPageLinks("help", { 'HELP_REMOTE' => "html/docs/remote.html" });
	Slim::Web::Pages->addPageLinks("help", { 'REMOTE_STREAMING' => "html/docs/remotestreaming.html" });
	Slim::Web::Pages->addPageLinks("help", { 'TECHNICAL_INFORMATION' => "html/docs/index.html" });
	Slim::Web::Pages->addPageLinks("help", { 'COMMUNITY_FORUM' =>	"http://forums.slimdevices.com" });
	Slim::Web::Pages->addPageLinks("help", { 'SOFTSQUEEZE' => "html/softsqueeze/index.html"});

	Slim::Web::Pages->addPageLinks("plugins", { 'MUSICSOURCE' => "switchserver.html"});

	Slim::Web::Pages->addPageLinks('icons', { 'MUSICSOURCE' => 'html/images/ServiceProviders/squeezenetwork.png' });
	Slim::Web::Pages->addPageLinks('icons', { 'RADIO_TUNEIN' => 'html/images/ServiceProviders/tuneinurl.png' });
	Slim::Web::Pages->addPageLinks('icons', { 'SOFTSQUEEZE' => 'html/images/softsqueeze.png' });
}

sub home {
	my ($client, $params, undef, $httpClient, $response) = @_;

	my $template = $params->{"path"} =~ /home\.(htm|xml)/ ? 'home.html' : 'index.html';
	my $checksum;
	
	# allow the setup wizard to be skipped in case the user's using an old browser (eg. Safari 1.x)
	if ($params->{skipWizard}) {
		$prefs->set('wizardDone', 1);
		if ($params->{skinOverride}){
			$prefs->set('skin', $params->{skinOverride});
		}
	}

	# redirect to the setup wizard if it has never been run before 
	if (!$prefs->get('wizardDone')) {
		$response->code(RC_MOVED_TEMPORARILY);
		$response->header('Location' => '/settings/server/wizard.html');
		return Slim::Web::HTTP::filltemplatefile($template, $params);
	}

	$params->{'nosetup'}  = 1 if $::nosetup;
	$params->{'noserver'} = 1 if $::noserver;
	$params->{'newVersion'} = $::newVersion if $::newVersion;
	$params->{'newPlugins'} = Slim::Utils::PluginManager->message;

	if (Slim::Schema::hasLibrary()) {
		$params->{'hasLibrary'} = 1;
	} else {
		$params->{'hasLibrary'} = 0;
	}

	# we don't need all of the heavy lifting for many index.html files. They are basically framesets.
	if ( $template ne 'index.html' || !$lightIndex{$params->{systemSkin}} ) {
		# More leakage from the DigitalInput 'plugin'
		#
		# If our current player has digital inputs, show the menu.
		if ($client && Slim::Utils::PluginManager->isEnabled('Slim::Plugin::DigitalInput::Plugin')) {
			Slim::Plugin::DigitalInput::Plugin->webPages($client->hasDigitalIn);
		}
	
		# More leakage from the LineIn/Out 'plugins'
		#
		# If our current player has line, show the menu.
		if ($client && Slim::Utils::PluginManager->isEnabled('Slim::Plugin::LineIn::Plugin')) {
			Slim::Plugin::LineIn::Plugin->webPages($client);
		}
	
		if ($client && Slim::Utils::PluginManager->isEnabled('Slim::Plugin::LineOut::Plugin')) {
			Slim::Plugin::LineOut::Plugin->webPages($client);
		}
	
		if (my $favs = Slim::Utils::Favorites->new($client)) {
			$params->{'favorites'} = $favs->toplevel;
		}
	
		# Bug 4125, sort all additionalLinks submenus properly
		$params->{additionalLinkOrder} = {};
		$params->{additionalLinks} = {};
		
		# Get sort order for plugins
		my $pluginWeights = Slim::Plugin::Base->getWeights();
		
		my $conditions = \%Slim::Web::Pages::pageConditions;
		
		my $cmpStrings = {};
		while (my ($menu, $menuItems) = each %Slim::Web::Pages::additionalLinks ) {
			
			next if $menu eq 'apps' && !main::NOMYSB;
	
			$params->{additionalLinks}->{ $menu } = {
				map {
					$_ => $menuItems->{ $_ };
				}
				# Filter out items that don't match condition
				grep {
					!$conditions->{$_}
					||
					$conditions->{$_}->( $client )
				}
				keys %$menuItems
			};
	
			$params->{additionalLinkOrder}->{ $menu } = [ sort {
				(
					$menu !~ /(?:my_apps)/ &&
					( $pluginWeights->{$a} || $prefs->get("rank-$a") || 0 ) <=>
					( $pluginWeights->{$b} || $prefs->get("rank-$b") || 0 )
				)
				|| 
				(
					!main::NOMYSB && $menu =~ /(?:my_apps)/ && $a eq 'PLUGIN_APP_GALLERY_MODULE_NAME' && -1
				)
				|| 
				(
					!main::NOMYSB && $menu =~ /(?:my_apps)/ && $b eq 'PLUGIN_APP_GALLERY_MODULE_NAME'
				)
				|| 
				(
					( $cmpStrings->{$a} ||= lc(Slim::Buttons::Home::cmpString($client, $a)) ) cmp
					( $cmpStrings->{$b} ||= lc(Slim::Buttons::Home::cmpString($client, $b)) )
				)
			} keys %{ $params->{additionalLinks}->{ $menu } } ];
		}
	
		if (main::NOMYSB) {
			$params->{additionalLinks}->{my_apps} = delete $params->{additionalLinks}->{apps};
			$params->{additionalLinkOrder}->{my_apps} = delete $params->{additionalLinkOrder}->{apps};
		}
	
		if ( !($params->{page} && $params->{page} eq 'help') ) {
			Slim::Web::Pages::Common->addPlayerList($client, $params);
			Slim::Web::Pages::Common->addLibraryStats($params, $client);
		}
	
		if ( my $library_id = Slim::Music::VirtualLibraries->getLibraryIdForClient($client) ) {
			$params->{library_id}   = $library_id;
			$params->{library_name} = Slim::Music::VirtualLibraries->getNameForId($library_id, $client);
		}
	
		if (!main::NOBROWSECACHE && $template eq 'home.html') {
			$checksum = md5_hex(Slim::Utils::Unicode::utf8off(join(':', 
				($client ? $client->id : ''),
				$params->{newVersion} || '',
				$params->{newPlugins} || '',
				$params->{hasLibrary} || '',
				$prefs->get('language'),
				$params->{library_id} || '',
				complex_to_query($params->{additionalLinks} || {}),
				complex_to_query($params->{additionalLinkOrder} || {}),
				complex_to_query($params->{cookies} || {}),
				complex_to_query($params->{favorites} || {}),
				$params->{'skinOverride'} || $prefs->get('skin') || '',
				$template || '',
				$params->{song_count} || 0,
				$params->{album_count} || 0,
				$params->{artist_count} || 0,
			)));

			if (my $cached = $cache->get($checksum)) {
				return $cached;
			}
		}
	}

	my $page = Slim::Web::HTTP::filltemplatefile($template, $params);
	$cache->set($checksum, $page, 3600) if $checksum && !main::NOBROWSECACHE;
	
	return $page;
}

sub updateInfo {
	my ($client, $params, $callback) = @_;

	my $current = {};

	my $request = Slim::Control::Request->new(undef, ['appsquery']);

	$request->addParam(args => {
		type    => 'plugin',
		details => 1,
		current => $current,
	});
	
	$params->{pt} = {
		request => $request,
	};

	$request->callbackParameters(\&_updateInfoCB, [ @_ ]);
	$request->execute();

	return;
}

sub _updateInfoCB {
	my ($client, $params, $callback, $httpClient, $response) = @_;
	
	my $request = $params->{pt}->{request};
	
	$params->{'newVersion'} = $::newVersion;
	
	my $newPlugins = $request->getResult('updates') || {};
	$params->{'newPlugins'} = $request && [ map { $_->{info} } grep { $_ } values %$newPlugins ];
	
	if ($params->{installerFile}) {
		$params->{'newVersion'} = ${Slim::Web::HTTP::filltemplatefile('html/docs/linux-update.html', $params)};
	}
	
	$callback->($client, $params, Slim::Web::HTTP::filltemplatefile('update_software.html', $params), $httpClient, $response);
}

sub switchServer {
	my ($client, $params) = @_;

	if ( !main::NOMYSB && ( lc($params->{'switchto'}) eq 'squeezenetwork' 
		|| $params->{'switchto'} eq Slim::Utils::Strings::string('SQUEEZENETWORK') ) ) {

		if ( _canSwitch($client) ) {
			Slim::Utils::Timers::setTimer(
				$client,
				time() + 1,
				sub {
					my $client = shift;
					Slim::Buttons::Common::pushModeLeft( $client, 'squeezenetwork.connect' );
				},
			);

			$params->{'switchto'} = 'http://' . Slim::Networking::SqueezeNetwork->get_server("sn");
		}

	}

	elsif ($params->{'switchto'}) {

		Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + 1,
			sub {

				my ($client, $server) = @_;
				$client->execute(['connect', Slim::Networking::Discovery::Server::getServerAddress($server)]);

			}, $params->{'switchto'});

		$params->{'switchto'} = Slim::Networking::Discovery::Server::getWebHostAddress($params->{'switchto'});
	}

	else {
		$params->{servers} = Slim::Networking::Discovery::Server::getServerList();

		if ( !main::NOMYSB && _canSwitch($client) ) {
			$params->{servers}->{'SQUEEZENETWORK'} = {
				NAME => Slim::Utils::Strings::string('SQUEEZENETWORK')	
			}; 
		}
	
		my @servers = keys %{Slim::Networking::Discovery::Server::getServerList()};
		$params->{serverlist} = \@servers;
	}
	
	return Slim::Web::HTTP::filltemplatefile('switchserver.html', $params);
}

# Bug 7254, don't tell Ray to reconnect to SN unless it's known to be attached to the user's account
sub _canSwitch { if (!main::NOMYSB) {
	my $client = shift;
	
	return ( ($client->deviceid != 7) || Slim::Networking::SqueezeNetwork::Players->is_known_player($client) );
} }

1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
