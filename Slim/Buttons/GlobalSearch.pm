package Slim::Buttons::GlobalSearch;

#	$Id: Information.pm 26931 2009-06-07 03:53:36Z michael $
#
#	Copyright (c) 2003-2020 Logitech, Cursor Software Limited.
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

Slim::Buttons::GlobalSearch

=head1 DESCRIPTION

L<Slim::Buttons::GlobalSearch> is a Logitech Media Server module to easily
search content in any search provider available to the server

=cut

use strict;

use Slim::Buttons::Common;
use Slim::Utils::Log;

sub init {
	Slim::Buttons::Common::addMode('globalsearch', undef, \&setMode);

	Slim::Buttons::Home::addMenuOption('GLOBAL_SEARCH', {
		useMode   => 'globalsearch',
		condition => sub { 1 },
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
	
	Slim::Buttons::Common::pushMode( $client, 'INPUT.Text', {
		'useMode' => 'INPUT.Text',
		'header' => 'GLOBAL_SEARCH',
		'stringHeader' => 1,
		'cursorPos' => 0,
		'charsRef' => 'UPPER',
		'numberLetterRef' => 'UPPER',
		'callback' => \&searchHandler,
	});
	
	$client->update();
}

sub searchHandler {
	my ($client, $exitType, @rest) = @_;

	$exitType = uc($exitType);

	my $search = ${ $client->modeParam('valueRef') };

	if ($exitType eq 'BACKSPACE') {
		Slim::Buttons::Common::popModeRight($client);
	}
	elsif ( $exitType eq 'NEXTCHAR' && defined $search && $search ne '' ) {
		
		my $tags = {
			search => $search,
		};
	
		my $getMenu = sub {
			my ( $client, $callback ) = @_;
	
			my $menu = Slim::Menu::GlobalSearch->menu( $client, $tags );
			
			if ( $callback ) {
				# Callback is used during a menu refresh
				$callback->( $menu );
			}
			else {
				return $menu;
			}
		};

		Slim::Buttons::Common::pushMode( $client, 'xmlbrowser', {
			modeName  => 'GlobalSearch',
			opml      => $getMenu->( $client ),
		});
	}
	else {
		$client->bumpRight();
	}
}

1;

__END__
