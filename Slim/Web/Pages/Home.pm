package Slim::Web::Pages::Home;

# $Id$

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;

use POSIX ();
use HTTP::Status qw(RC_MOVED_TEMPORARILY);

use base qw(Slim::Web::Pages);

use Slim::Utils::Prefs;
use Slim::Utils::Strings;
use Slim::Networking::Discovery::Server;
use Slim::Networking::SqueezeNetwork;

require Slim::Plugin::Base;

my $prefs = preferences('server');

sub init {
	my $class = shift;
	
	Slim::Web::Pages->addPageFunction(qr/^$/, sub {$class->home(@_)});
	Slim::Web::Pages->addPageFunction(qr/^home\.(?:htm|xml)/, sub {$class->home(@_)});
	Slim::Web::Pages->addPageFunction(qr/^index\.(?:htm|xml)/, sub {$class->home(@_)});
	Slim::Web::Pages->addPageFunction(qr/^switchserver\.(?:htm|xml)/, sub {$class->switchServer(@_)});

	$class->addPageLinks("help", { 'HELP_REMOTE' => "html/docs/remote.html"});
	$class->addPageLinks("help", { 'REMOTE_STREAMING' => "html/docs/remotestreaming.html"});
#	$class->addPageLinks("help", { 'FAQ' => "http://mysqueezebox.com/support"},1);
	$class->addPageLinks("help", { 'TECHNICAL_INFORMATION' => "html/docs/index.html"});
	$class->addPageLinks("help", { 'COMMUNITY_FORUM' =>	"http://forums.slimdevices.com"});

	$class->addPageLinks("plugins", { 'MUSICSOURCE' => "switchserver.html"});

	$class->addPageLinks('icons', { 'MUSICSOURCE' => 'html/images/ServiceProviders/squeezenetwork.png' });
	$class->addPageLinks('icons', { 'RADIO_TUNEIN' => 'html/images/ServiceProviders/tuneinurl.png' });
	$class->addPageLinks('icons', { 'SOFTSQUEEZE' => 'html/images/softsqueeze.png' });
}

sub home {
	my ($class, $client, $params, $gugus, $httpClient, $response) = @_;

	my $template = $params->{"path"} =~ /home\.(htm|xml)/ ? 'home.html' : 'index.html';

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

	my %listform = %$params;

	$params->{'nosetup'}  = 1 if $::nosetup;
	$params->{'noserver'} = 1 if $::noserver;
	$params->{'newVersion'} = $::newVersion if $::newVersion;
	$params->{'newPlugins'} = Slim::Utils::PluginManager->message;

	if (Slim::Schema::hasLibrary()) {
		$params->{'hasLibrary'} = 1;
	} else {
		$params->{'hasLibrary'} = 0;
	}

	if (!exists $Slim::Web::Pages::additionalLinks{"help"}) {
		$class->addPageLinks("help", {'HELP_REMOTE' => "html/docs/remote.html"});
		$class->addPageLinks("help", {'REMOTE_STREAMING' => "html/docs/remotestreaming.html"});
		$class->addPageLinks("help", {'FAQ' => "html/docs/faq.html"});
		$class->addPageLinks("help", {'SOFTSQUEEZE' => "html/softsqueeze/index.html"});
		$class->addPageLinks("help", {'TECHNICAL_INFORMATION' => "html/docs/index.html"});
	}
	
	$class->addPageLinks( 'my_apps', {'PLUGIN_APP_GALLERY_MODULE_NAME' => Slim::Networking::SqueezeNetwork->url( '/appgallery' )} );

	# fill out the client setup choices
	for my $player (sort { $a->name() cmp $b->name() } Slim::Player::Client::clients()) {

		# every player gets a page.
		# next if (!$player->isPlayer());
		$listform{'playername'}   = $player->name();
		$listform{'playerid'}     = $player->id();
		$listform{'player'}       = $params->{'player'};
		$listform{'skinOverride'} = $params->{'skinOverride'};
		$params->{'player_list'} .= ${Slim::Web::HTTP::filltemplatefile("homeplayer_list.html", \%listform)};
	}

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
	# XXX: non-Default templates will need to be updated to use this sort order
	$params->{additionalLinkOrder} = {};
	
	$params->{additionalLinks} = {};
	
	# Get sort order for plugins
	my $pluginWeights = Slim::Plugin::Base->getWeights();
	
	my $conditions = \%Slim::Web::Pages::pageConditions;
	
	for my $menu ( keys %Slim::Web::Pages::additionalLinks ) {
		
		next if $menu eq 'apps';

		my @sorted = sort {
			(
				$menu !~ /(?:my_apps)/ &&
				( $pluginWeights->{$a} || $prefs->get("rank-$a") || 0 ) <=>
				( $pluginWeights->{$b} || $prefs->get("rank-$b") || 0 )
			)
			|| 
			(
				$menu =~ /(?:my_apps)/ && $a eq 'PLUGIN_APP_GALLERY_MODULE_NAME' && -1
			)
			|| 
			(
				$menu =~ /(?:my_apps)/ && $b eq 'PLUGIN_APP_GALLERY_MODULE_NAME'
			)
			|| 
			(
				lc( Slim::Buttons::Home::cmpString($client, $a) ) cmp
				lc( Slim::Buttons::Home::cmpString($client, $b) )
			)
		}
		keys %{ $Slim::Web::Pages::additionalLinks{ $menu } };

		$params->{additionalLinkOrder}->{ $menu } = \@sorted;
		
		$params->{additionalLinks}->{ $menu } = {
			map {
				$_ => $Slim::Web::Pages::additionalLinks{ $menu }->{ $_ },
			}
			# Filter out items that don't match condition
			grep {
				!$conditions->{$_}
				||
				$conditions->{$_}->( $client )
			}
			keys %{ $Slim::Web::Pages::additionalLinks{ $menu } }
		};
	}

	Slim::Web::Pages::Common->addPlayerList($client, $params);
	Slim::Web::Pages::Common->addLibraryStats($params);
	
	return Slim::Web::HTTP::filltemplatefile($template, $params);
}

sub switchServer {
	my ($class, $client, $params) = @_;

	if (lc($params->{'switchto'}) eq 'squeezenetwork' 
		|| $params->{'switchto'} eq Slim::Utils::Strings::string('SQUEEZENETWORK')) {

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

		if ( _canSwitch($client) ) {
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
sub _canSwitch {
	my $client = shift;
	
	return ( ($client->deviceid != 7) || Slim::Networking::SqueezeNetwork::Players->is_known_player($client) );
}

1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
