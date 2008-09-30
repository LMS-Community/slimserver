package Slim::Buttons::Information;

#	$Id$
#
#	Author: Kevin Walsh <kevin@cursor.biz>
#	Copyright (c) 2003-2007 Logitech, Cursor Software Limited.
#	All rights reserved.
#
#	This program is free software; you can redistribute it and/or modify
#	it under the terms of the GNU General Public License as published by
#	the Free Software Foundation; either version 2 of the License, or
#	(at your option) any later version.
#
#	This program is distributed in the hope that it will be useful,
#	but WITHOUT ANY WARRANTY; without even the implied warranty of
#	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#	GNU General Public License for more details.
#
#	You should have received a copy of the GNU General Public License
#	along with this program; if not, write to the Free Software
#	Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA
#	02111-1307 USA
#

=head1 NAME

Slim::Buttons::Information

=head1 DESCRIPTION

L<Slim::Buttons::Information> is a SqueezeCenter module to display player library
and module information.

Displays various bits of information relating to the SqueezeCenter,
the current player, the music library and the installed plug-in
modules.

Scroll through the information items using the up/down buttons.
If you see a "->" symbol then you may press RIGHT to move into
a sub-menu.  Press LEFT to move out of a sub-menu.

=cut

use strict;

use File::Spec::Functions qw(catdir);

use Slim::Buttons::Common;
use Slim::Utils::Misc;
use Slim::Utils::Network;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string cstring);

sub init {
	Slim::Buttons::Common::addMode('information', undef, \&setMode);

	Slim::Buttons::Home::addSubMenu('SETTINGS', 'INFORMATION', {
		'useMode'   => 'information',
		'condition' => sub { 1 },
	});
}

# Standard button mode subs follow
sub setMode {
	my $client = shift;
	my $method = shift;

	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}
	
	my $getMenu = sub {
		my ( $client, $callback ) = @_;

		my $menu = Slim::Menu::SystemInfo->menu( $client );
		
		if ( $callback ) {
			# Callback is used during a menu refresh
			$callback->( $menu );
		}
		else {
			return $menu;
		}
	};
	
	my %params = (
		modeName  => 'SystemInfo',
		opml      => $getMenu->( $client ),
		onRefresh => $getMenu,
	);
	
	Slim::Buttons::Common::pushMode( $client, 'xmlbrowser', \%params );
	
	$client->modeParam( 'handledTransition', 1 );
}

sub playerModel {
	my $client = shift;
	
	# special case for squeezebox v3 (can't use in $client->model due to some images
	# expecting "squeezebox" for v1-3)
	if ($client->model =~ /squeezebox/ && $client->macaddress =~ /^00:04:20((:\w\w){3})/) {
		my $id = $1;
		$id =~ s/://g;
		if ($id gt "060000") {
			return "Squeezebox v3";
		}
	}

	return $client->model;
}

# don't know yet how to do this in the new Slim::Menu::SystemInfo world order
#sub updateClientStatus {
#	my $client = shift;
#
#	if (Slim::Buttons::Common::mode($client) eq 'INPUT.List' &&
#	    Slim::Buttons::Common::param($client, 'parentMode') eq 'information' &&
#	    (${Slim::Buttons::Common::param($client, 'valueRef')} eq 'PLAYER_SIGNAL_STRENGTH' ||
#	     ${Slim::Buttons::Common::param($client, 'valueRef')} eq 'PLAYER_VOLTAGE')) {
#		$client->requestStatus();
#	
#		$client->update();
#	}
#
#	Slim::Utils::Timers::setTimer($client,Time::HiRes::time() + 1,\&updateClientStatus);
#}

1;

__END__
