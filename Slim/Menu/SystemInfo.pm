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

use base qw(Slim::Menu::Base);

use Slim::Utils::Log;
use Slim::Utils::Strings qw(cstring);

my $log = logger('menu.systeminfo');


sub title {
	return 'INFORMATION';
}

##
# Register all the information providers that we provide.
# This order is defined at http://wiki.slimdevices.com/index.php/UserInterfaceHierarchy
#
sub registerDefaultInfoProviders {
	my $class = shift;

	$class->SUPER::registerDefaultInfoProviders();
	
	$class->registerInfoProvider( server => (
		after => 'top',
		func  => \&infoServer,
	) );

	$class->registerInfoProvider( library => (
		after => 'top',
		func  => \&infoLibrary,
	) );
	
	$class->registerInfoProvider( scan => (
		after => 'top',
		func  => \&infoScan,
	) );
	
}

sub infoLibrary {
	my ( $client, $url ) = @_;
	
	return {
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
							. Slim::Buttons::Information::timeFormat(Slim::Schema->totalTime),
			},
		],

		web  => {
			group  => 'library',
			unfold => 1,
		},

	};
}

sub infoScan {
	my ( $client, $url ) = @_;
	
	return {
		name => cstring($client, 'INFORMATION_MENU_SCAN'),

		web  => {
			group  => 'scan',
			unfold => 1,
		},

	};
}

sub infoServer {
	my ( $client, $url ) = @_;
	
	return {
		name => cstring($client, 'INFORMATION_MENU_SERVER'),

		web  => {
			group  => 'server',
			unfold => 1,
		},

	};
}
