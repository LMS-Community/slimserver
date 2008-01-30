package Slim::Plugin::Sounds::Plugin;

# $Id$

# Browse Sounds & Effects

use strict;
use base qw(Slim::Plugin::OPMLBased);

use Slim::Networking::SqueezeNetwork;
use Slim::Player::ProtocolHandlers;
use Slim::Plugin::Sounds::ProtocolHandler;

sub initPlugin {
	my $class = shift;
	
	Slim::Player::ProtocolHandlers->registerHandler(
		loop => 'Slim::Plugin::Sounds::ProtocolHandler'
	);

	my @item = ({
			text           => Slim::Utils::Strings::string(getDisplayName()),
			weight         => 30,
			id             => 'sounds',
			node           => 'extras',
			'icon-id'      => $class->_pluginDataFor('icon'),
			displayWhenOff => 0,
			window         => { titleStyle => 'album' },
			actions => {
				go =>          {
							cmd => [ 'sounds', 'items' ],
							params => {
								menu => 'sounds',
							},
				},
			},
		});

	Slim::Control::Jive::registerPluginMenu(\@item);

	$class->SUPER::initPlugin(
		feed => Slim::Networking::SqueezeNetwork->url( '/api/sounds/v1/opml' ),
		tag  => 'sounds',
		menu => 'plugins',
	);
}

sub getDisplayName {
	return 'PLUGIN_SOUNDS_MODULE_NAME';
}

1;
