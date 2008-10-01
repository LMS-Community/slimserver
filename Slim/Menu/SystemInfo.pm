package Slim::Menu::SystemInfo;

# $Id: $

# SqueezeCenter Copyright 2001-2008 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

# Provides OPML-based extensible menu for system information

=head1 NAME

Slim::Menu::SystemInfo

=head1 DESCRIPTION

Provides a dynamic OPML-based system (server, players, controllers)
info menu to all UIs and allows plugins to register additional menu items.

=cut

use strict;
use Config;

use base qw(Slim::Menu::Base);

use Slim::Player::Client;
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(cstring);
use Slim::Utils::Network;

my $log = logger('menu.systeminfo');
my $prefs = preferences('server');

# some SN values
my $_ss_version = 'r0';
my $_sn_version = 'r0';
my $_versions_mtime = 0;
my $_versions_last_checked = 0;

sub init {
	my $class = shift;
	$class->SUPER::init();
	
	Slim::Control::Request::addDispatch(
		[ 'systeminfo', 'items', '_index', '_quantity' ],
		[ 0, 1, 1, \&cliQuery ]
	);
}


sub name {
	return 'INFORMATION';
}

##
# Register all the information providers that we provide.
# This order is defined at http://wiki.slimdevices.com/index.php/UserInterfaceHierarchy
#
sub registerDefaultInfoProviders {
	my $class = shift;

	$class->SUPER::registerDefaultInfoProviders();
	
	if ( main::SLIM_SERVICE ) {
		$class->registerInfoProvider( squeezenetwork => (
			after => 'top',
			func  => \&infoSqueezeNetwork,
		) );
	
		$class->registerInfoProvider( player => (
			after => 'squeezenetwork',
			func  => \&infoPlayer,
		) );
	}
	
	else {		
		$class->registerInfoProvider( server => (
			after => 'top',
			func  => \&infoServer,
		) );
	
		$class->registerInfoProvider( library => (
			after => 'server',
			func  => \&infoLibrary,
		) );
		
		$class->registerInfoProvider( players => (
			after => 'library',
			func  => \&infoPlayers,
		) );
		
		$class->registerInfoProvider( dirs => (
			after => 'players',
			func  => \&infoDirs,
		) );
		
		$class->registerInfoProvider( logs => (
			after => 'dirs',
			func  => \&infoLogs,
		) );
	}
	
}

sub infoPlayers {
	my $client = shift;
	
	my $players = Slim::Player::Client::clients();
	return {} if !$players;
	
	my $item = {
		name  => cstring($client, 'INFORMATION_MENU_PLAYER'),
		items => []
	};
	
	for my $player (main::SLIM_SERVICE ? qw($client) : Slim::Player::Client::clients()) {
		
		my $info = [
#			{ INFORMATION_PLAYER_NAME_ABBR       => $player->name },
			{ INFORMATION_PLAYER_MODEL           => Slim::Buttons::Information::playerModel($player) },
			{ INFORMATION_FIRMWARE_ABBR          => $player->revision },
			{ INFORMATION_PLAYER_IP              => $player->ip },
			{ INFORMATION_PLAYER_PORT            => $player->port },
			{ INFORMATION_PLAYER_MAC             => $player->macaddress },
			{ INFORMATION_PLAYER_SIGNAL_STRENGTH => $player->signalStrength },
			{ INFORMATION_PLAYER_VOLTAGE         => $player->voltage },
		];

		my @details;
		foreach (@$info) {
			my ($key, $value) = each %{$_};
			
			next unless $value;
			
			if (Slim::Utils::Strings::stringExists($key . '_ABBR')) {
				$key = $key . '_ABBR'
			}
			
			push @details, {
				type => 'text',
				name => cstring($client, $key) . cstring($client, 'COLON') . ' ' . $value,
			};
		}
			
		push @{ $item->{items} }, {
			name  => $player->name,
			items => \@details,
			web   => {
				name  => $player->name,
				items => $info,
			} 
		}
	}
	
	# don't create hierarchical menu if there's only one player
	if (scalar @{ $item->{items} } <= 1) {
		$item = $item->{items}->[0];
	}
	
	return $item;
}

sub infoLibrary {
	my $client = shift;
	
	return Slim::Music::Import->stillScanning 
	? {
		name => cstring($client, 'RESCANNING_SHORT')		
	} 
	: {
		name => cstring($client, 'INFORMATION_MENU_LIBRARY'),

		items => [
			{
				type => 'text',
				name => cstring($client, 'INFORMATION_TRACKS') . cstring($client, 'COLON') . ' '
							. Slim::Utils::Misc::delimitThousands(Slim::Schema->count('Track', { 'me.audio' => 1 })),
			},

			{
				type => 'text',
				name => cstring($client, 'INFORMATION_ALBUMS') . cstring($client, 'COLON') . ' '
							. Slim::Utils::Misc::delimitThousands(Slim::Schema->count('Album')),
			},

			{
				type => 'text',
				name => cstring($client, 'INFORMATION_ARTISTS') . cstring($client, 'COLON') . ' '
							. Slim::Utils::Misc::delimitThousands(Slim::Schema->rs('Contributor')->browse->count),
			},

			{
				type => 'text',
				name => cstring($client, 'INFORMATION_ARTISTS') . cstring($client, 'COLON') . ' '
							. Slim::Utils::Misc::delimitThousands(Slim::Schema->count('Genre')),
			},

			{
				type => 'text',
				name => cstring($client, 'INFORMATION_TIME') . cstring($client, 'COLON') . ' '
							. Slim::Utils::DateTime::timeFormat(Slim::Schema->totalTime),
			},
		],

		web  => {
			group  => 'library',
			unfold => 1,
		},

	};
}

sub infoServer {
	my $client = shift;
		
	my $osDetails = Slim::Utils::OSDetect::details();

	return {
		name => cstring($client, 'INFORMATION_MENU_SERVER'),
		items => [
			{
				type => 'text',
				name => sprintf("%s%s %s - %s @ %s",
							cstring($client, 'INFORMATION_VERSION'),
							cstring($client, 'COLON'),
							$::VERSION,
							$::REVISION,
							$::BUILDDATE),
			},
			
			{
				type => 'text',
				name => cstring($client, 'INFORMATION_HOSTNAME') . cstring($client, 'COLON') . ' '
							. Slim::Utils::Network::hostName(),
			}, 
			
			{
				type => 'text',
				name => cstring($client, 'INFORMATION_SERVER_IP') . cstring($client, 'COLON') . ' '
							. Slim::Utils::Network::serverAddr(),
			}, 
			
			{
				type => 'text',
				name => cstring($client, 'INFORMATION_SERVER_HTTP') . cstring($client, 'COLON') . ' '
							. $prefs->get('httpport'),
			}, 
		
			{
				type => 'text',
				name => sprintf("%s%s %s - %s - %s ", 
							cstring($client, 'INFORMATION_OPERATINGSYSTEM'),
							cstring($client, 'COLON'),
							$osDetails->{'osName'},
							$prefs->get('language'),
							Slim::Utils::Unicode::currentLocale()),
			},
			
			{
				type => 'text',
				name => cstring($client, 'INFORMATION_ARCHITECTURE') . cstring($client, 'COLON') . ' '
							. ($osDetails->{'osArch'} ? $osDetails->{'osArch'} : 'unknown'),
			},
			
			{
				type => 'text',
				name => cstring($client, 'PERL_VERSION') . cstring($client, 'COLON') . ' '
							. $Config{'version'} . ' - ' . $Config{'archname'},
			},

			{
				type => 'text',
				name => cstring($client, 'MYSQL_VERSION') . cstring($client, 'COLON') . ' '
							. Slim::Utils::MySQLHelper->mysqlVersionLong( Slim::Schema->storage->dbh ),
			},

			{
				type => 'text',
				name => cstring($client, 'INFORMATION_CLIENTS') . cstring($client, 'COLON') . ' '
							. Slim::Player::Client::clientCount,
			},
		]
	};
}

sub infoDirs {
	my $client = shift;
	
	my $folders = [
		{ INFORMATION_CACHEDIR   => $prefs->get('cachedir') },
		{ INFORMATION_PREFSDIR   => Slim::Utils::Prefs::dir() },
		{ INFORMATION_PLUGINDIRS => join(", ",Slim::Utils::OSDetect::dirsFor('Plugins')) },
	];
	
	my $item = {
		name  => cstring($client, 'FOLDERS'),
		items => [],
		
		web   => {
			name  => 'FOLDERS',
			items => $folders,
		}
	};
	
	foreach (@$folders) {
		my ($key, $value) = each %{$_};
		push @{ $item->{items} }, {
			type => 'text',
			name => cstring($client, $key) . cstring($client, 'COLON') . ' ' . $value,
		}
	}
	
	return $item;
}


sub infoLogs {
	my $client = shift;
	
	my $logs = Slim::Web::Settings::Server::Debugging::getLogs();
	
	my $item = {
		name  => cstring($client, 'SETUP_DEBUG_SERVER_LOG'),
		items => [],
		
		web   => {
			name  => 'SETUP_DEBUG_SERVER_LOG',
			items => $logs,
		}
	};
	
	foreach (@$logs) {
		my ($key, $value) = each %{$_};
		
		next unless $value;
		
		push @{ $item->{items} }, {
			type => 'text',
			name => cstring($client, "SETUP_DEBUG_${key}_LOG") . cstring($client, 'COLON') . ' ' . $value
		}
	}
	
	return $item;
}

sub infoSqueezeNetwork {
	my $client = shift;
	my $item;
	
	if ( main::SLIM_SERVICE ) {

		my $time = time();

		if ( ($time - $_versions_last_checked) > 60 ) {
			$_versions_last_checked = $time;

			my @stats = stat('/etc/sn/versions');
			my $mtime = $stats[9] || -1;

			if ( $mtime != $_versions_mtime ) {
				$_versions_mtime = $mtime;

				my $ok = open(my $vfile, '<', '/etc/sn/versions');
				
				if ($ok) {
					
					while(<$vfile>) {
						chomp;
						next unless /^(S[NS]):([^:]+)$/;
						$_sn_version = $2 if $1 eq 'SN';

						# SS version is only read once because this instance may
						# be running an older version than the server has
						if ( $_ss_version eq 'r0' ) {
							$_ss_version = $2 if $1 eq 'SS';
						}
					}
					
					close($vfile);
				}
			}
		}

		my $config = SDI::Util::SNConfig::get_config();
		my $dcname = $config->{dcname};

		$item = {
			name  => cstring($client, 'INFORMATION_MENU_SERVER'),
			items => [
				{
					type => 'text',
					name => sprintf('%s SS%s %s, SN%s %s',
						cstring($client, 'VERSION'),
						cstring($client, 'COLON'),
						$_ss_version,
						cstring($client, 'COLON'),
						$_sn_version					
					)
				},
				
				{
					type => 'text',
					name => cstring($client, 'DATACENTER') . cstring($client, 'COLON') . ' '					
								. $dcname eq 'sv'  ? 'Sunnyvale, CA'
								: $dcname eq 'dc'  ? 'Ashburn, VA'
								: $dcname eq 'de'  ? 'Frankfurt, Germany'
								: $dcname eq 'okc' ? 'Oklahoma City (Test)'
								: $dcname eq 'dfw' ? 'Dallas (Test)'
								:                    'Unknown'					
				},
				
				{
					type => 'text',
					name => cstring($client, 'SN_ACCOUNT') . cstring($client, 'COLON') . ' ' . $client->playerData->userid->email,	  
				},
			]
		};
		
	}
	
	return $item;
}

sub cliQuery {
	my $request = shift;
	
	my $client  = $request->client;
	my $tags    = {
		menuMode => $request->getParam('menu') || 0,
	};
	my $feed    = Slim::Menu::SystemInfo->menu( $client, $tags );

	Slim::Buttons::XMLBrowser::cliQuery('systeminfo', $feed, $request );
}

1;