#
#	$Id: Information.pm,v 1.3 2003/11/25 04:03:50 grotus Exp $
#
#	Author: Kevin Walsh <kevin@cursor.biz>
#
#	Copyright (c) 2003 Cursor Software Limited.
#	All rights reserved.
#
#	----------------------------------------------------------------------
#
#	SLIMP3 server, player library and module information.
#
#	Displays various bits of information relating to the SLIMP3 server,
#	the current player, the music library and the installed plug-in
#	modules.
#
#	Scroll through the information items using the up/down buttons.
#	If you see a "->" symbol then you may press RIGHT to move into
#	a sub-menu.  Press LEFT to move out of a sub-menu.
#
#	This module incorporates the code from the "Plugins::Statistics"
#	and "Plugins::PluginInfo" modules, which you may now delete.
#
#	----------------------------------------------------------------------
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
#

package Slim::Buttons::Information;

use POSIX qw(strftime);
use File::Spec::Functions qw(catdir);
use Slim::Utils::Strings qw(string);
use strict;

use vars qw($VERSION);
$VERSION = substr(q$Revision: 1.3 $,10);

my $modules;
my %enabled;

Slim::Buttons::Common::addMode('information', getFunctions(), \&Slim::Buttons::Information::setMode);

sub module_list {
	return undef unless $modules;
	return [sort { $modules->{$a} cmp $modules->{$b} } keys %$modules];
}

sub timeFormat {
	my $time = shift || 0;

	sprintf(
	    "%d:%02d:%02d",
	    ($time / 3600),
	    ($time / 60) % 60,
	    $time % 60,
	);
}

# since we just jump into INPUT.List, we don't need any functions of our own
my %functions = ();

# array for internal values of the player submenu
my @player_list = ('PLAYER_NAME','PLAYER_MODEL','FIRMWARE','PLAYER_IP','PLAYER_PORT','PLAYER_MAC');

# hash of parameters for the various menus, these will be passed to INPUT.List
# Some of the parameters aren't used by INPUT.List, but it is handy to let them be
# stored in the mode stack.
my %menuParams = (
	'main' => {
		'header' => \&mainHeader
		,'headerArgs' => 'C'
		,'externRef' => sub {return string('INFORMATION_MENU_' . uc($_[0]));}
		,'externRefArgs' => 'V'
		,'listRef' => ['library','player','server','module']
		,'overlayRef' => sub {return (undef,Slim::Hardware::VFD::symbol('rightarrow'));}
		,'overlayRefArgs' => ''
		,'callback' => \&mainExitHandler
	}
	,catdir('main','library') => {
		'header' => \&infoHeader
		,'headerArgs' => 'C'
		,'listRef' => ['TIME','ALBUMS','TRACKS','ARTISTS','GENRES']
		,'externRef' => \&infoDisplay
		,'externRefArgs' => 'CV'
		,'formatRef' => [\&timeFormat
				,\&Slim::Utils::Misc::delimitThousands
				,\&Slim::Utils::Misc::delimitThousands
				,\&Slim::Utils::Misc::delimitThousands
				,\&Slim::Utils::Misc::delimitThousands
				]
		,'valueFunctRef' => [\&Slim::Music::Info::total_time
					,sub { Slim::Music::Info::albumCount([],[],[],[]) }
					,sub { Slim::Music::Info::songCount([],[],[],[]) }
					,sub { Slim::Music::Info::artistCount([],[],[],[]) }
					,sub { Slim::Music::Info::genreCount([],[],[],[]) }
					]
		,'menuName' => 'library'
		}
	,catdir('main','player') => {
		'header' => \&infoHeader
		,'headerArgs' => 'C'
		,'listRef' => \@player_list
		,'externRef' => \&infoDisplay
		,'externRefArgs' => 'CV'
		,'valueFunctRef' => [sub { shift->name }
					,sub { shift->model() }
					,sub { shift->revision }
					,sub { shift->ip }
					,sub { shift->port }
					,sub { uc(shift->macaddress) }
					,sub { return (shift->signalStrength() . '%'); }]
		,'menuName' => 'player'
		}
	,catdir('main','server') => {
		'header' => \&infoHeader
		,'headerArgs' => 'C'
		,'listRef' => ['VERSION','SERVER_PORT','SERVER_HTTP','CLIENTS']
		,'externRef' => \&infoDisplay
		,'externRefArgs' => 'CV'
		,'formatRef' => [undef,undef,undef,\&Slim::Utils::Misc::delimitThousands]
		,'valueFunctRef' => [sub { $::VERSION }
					, sub { 3483 }
					, sub { Slim::Utils::Prefs::get('httpport') }
					, \&Slim::Player::Client::clientCount ]
		,'menuName' => 'server'
	}
		,catdir('main','module') => {
		'header' => \&infoHeader
		,'headerArgs' => 'C'
		,'listRef' => undef #filled in setMode
		,'externRef' => \&moduleDisplay
		,'externRefArgs' => 'V'
		,'menuName' => 'module'
	}

);


# hash of current locations in the menu structure
# This is keyed by the $client object, then the second level
# is keyed by the menu.  When entering any menu, the valueRef parameter
# passed to INPUT.List refers back to here.
my %current;

# function providing the second line of the display for the
# library, server, and player menus
sub infoDisplay {
	my ($client,$value) = @_;
	my $listIndex = Slim::Buttons::Common::param($client,'listIndex');
	my $formatRef = Slim::Buttons::Common::param($client,'formatRef');
	my $valueFunctRef = Slim::Buttons::Common::param($client,'valueFunctRef');
	if (defined($formatRef) && defined($formatRef->[$listIndex])) {
		return string('INFORMATION_' . uc($value)) . ': '
		. $formatRef->[$listIndex]->($valueFunctRef->[$listIndex]->($client));
	} else {
		return string('INFORMATION_' . uc($value)) . ': '
		. $valueFunctRef->[$listIndex]->($client);
	}
}

# function providing the second line of the display for the module menu
sub moduleDisplay {
	my $item = shift;
	my @info;
	push(@info,$modules->{$item});
	push(@info,string('INFORMATION_DISABLED')) unless $enabled{$item};

	my $version = eval {
		no strict 'refs';
		${"Plugins::${item}::VERSION"};
	};
	if ($@ || !$version) {
		push(@info,string('INFORMATION_NO_VERSION'));
	}
	else {
		$version =~ s/^\s+//;
		$version =~ s/\s+$//;
		push(@info,string('INFORMATION_VERSION') . ": $version");
	}

	return join(' ' . Slim::Hardware::VFD::symbol('rightarrow') . ' ',@info);

}	

# function providing the top line of the display for all submenus
sub infoHeader {
	my $client = shift;
	return string('INFORMATION_MENU_' . uc(Slim::Buttons::Common::param($client,'menuName')))
		. ' ('
		. (Slim::Buttons::Common::param($client,'listIndex') + 1)
		. ' ' . string('OF') . ' '
		. scalar(@{Slim::Buttons::Common::param($client,'listRef')})
		. ')'
}

# function providing the top line of the display for the main menu
sub mainHeader {
	my $client = shift;
	return string('INFORMATION') 
		. ' (' 
		. (Slim::Buttons::Common::param($client,'listIndex') + 1)
		. ' ' . string('OF') . ' '
		. scalar(@{Slim::Buttons::Common::param($client,'listRef')})
		. ')';
}

# callback function for the main menu, handles descending into the submenus
sub mainExitHandler {
	my ($client,$exittype) = @_;
	$exittype = uc($exittype);
	if ($exittype eq 'LEFT') {
		Slim::Buttons::Common::popModeRight($client);
	} elsif ($exittype eq 'RIGHT') {
		my $nextmenu = catdir('main',$current{$client}{'main'});
		if (exists($menuParams{$nextmenu})) {
			my %nextParams = %{$menuParams{$nextmenu}};
			$current{$client}{$nextmenu} = $menuParams{$nextmenu}{'listRef'}[0] unless exists($current{$client}{$nextmenu});
			$nextParams{'valueRef'} = \$current{$client}{$nextmenu};
			if ($nextmenu eq catdir('main','player')) {
				my @nextList = @player_list;
				push @nextList, 'PLAYER_SIGNAL_STRENGTH' if defined($client->signalStrength());
				$nextParams{'listRef'} = \@nextList;
			}
			Slim::Buttons::Common::pushModeLeft(
				$client,
				"INPUT.List",
				\%nextParams
			);
		} else {
			Slim::Display::Animation::bumpRight($client);
		}
	} else {
		return;
	}
}

# Standard button mode subs follow
sub setMode {
	my $client = shift;
	my $method = shift;
	if ($method eq 'pop') {
		Slim::Buttons::Common::popModeRight($client);
		return;
	}
	unless (ref($modules)) {
		$modules = Slim::Buttons::Plugins::installedPlugins();
		$enabled{$_} = 1 for (Slim::Buttons::Plugins::enabledPlugins($client));
		$menuParams{catdir('main','module')}{'listRef'} = module_list();
	}

	$current{$client}{main} = 'library' unless exists($current{$client}{main});
	my %params = %{$menuParams{'main'}};
	$params{'valueRef'} = \$current{$client}{main};
	Slim::Buttons::Common::pushMode($client,'INPUT.List',\%params);
	$client->update();
}

sub getFunctions {
	\%functions;
}

1;

