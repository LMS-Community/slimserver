#
#	$Id: Information.pm,v 1.4 2003/08/09 16:23:43 dean Exp $
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

package Plugins::Information;
use POSIX qw(strftime);
use File::Spec::Functions qw(catfile);
use Slim::Utils::Strings qw(string);
use strict;

use vars qw($VERSION);
$VERSION = substr(q$Revision: 1.4 $,10);

my @main_list = qw(
    library
    player
    server
    module
);

my @library_list = (
    [ 'TIME',         'time',    0,  \&Slim::Music::Info::total_time ],
    [ 'ALBUMS',       'int',     0,  sub { Slim::Music::Info::albumCount([],[],[],[]) } ],
    [ 'TRACKS',       'int',     0,  sub { Slim::Music::Info::songCount([],[],[],[]) } ],
    [ 'ARTISTS',      'int',     0,  sub { Slim::Music::Info::artistCount([],[],[],[]) } ],
    [ 'GENRES',       'int',     0,  sub { Slim::Music::Info::genreCount([],[],[],[]) } ],
);

my @player_list = (
    [ 'PLAYER_NAME',  'string',  1,  sub { Slim::Utils::Prefs::clientGet(shift,'playername') } ],
    [ 'PLAYER_MODEL', 'string',  1,  sub { shift->model() } ],
    [ 'FIRMWARE',     'string',  1,  sub { shift->revision } ],
    [ 'PLAYER_IP',    'string',  1,  sub { (split(':',shift->ipaddress))[0] } ],
    [ 'PLAYER_PORT',  'string',  1,  sub { (split(':',shift->ipaddress))[1] } ],
    [ 'PLAYER_MAC',   'string',  1,  sub { uc(shift->macaddress) } ],
);

my @server_list = (
    [ 'VERSION',      'string',  0,  sub { $::VERSION } ],
    [ 'SERVER_PORT',  'string',  0,  sub { 3483 } ],
    [ 'SERVER_HTTP',  'string',  0,  sub { Slim::Utils::Prefs::get('httpport') } ],
    [ 'CLIENTS',      'int',     1,  \&Slim::Player::Client::clientCount ],
);

my @module_list;

my %menu = (
    main => {
	lines => \&main_lines,
	list => \@main_list,
    },
    library => {
	lines => \&info_lines,
	list => \@library_list,
    },
    player => {
	lines => \&info_lines,
	list => \@player_list,
    },
    player => {
	lines => \&info_lines,
	list => \@player_list,
    },
    server => {
	lines => \&info_lines,
	list => \@server_list,
    },
    module => {
	lines => \&module_lines,
	list => \@module_list,
    },
);

my %format = (
    'int' => sub {
	Slim::Utils::Misc::delimitThousands(shift);
    },
    'time' => sub {
	my $time = shift || 0;

	sprintf(
	    "%d:%02d:%02d",
	    ($time / 3600),
	    ($time / 60) % 60,
	    $time % 60,
	);
    },
    'string' => sub {
	shift;
    },
);

my $modes_set;
my $modules;
my %enabled;
my %context;

my %functions = (
    'left' => sub {
	my $client = shift;

	Slim::Buttons::Common::popModeRight($client);
    },
    'right' => sub {
	my $client = shift;
	my $nextmode = find_nextmode($client);

	if ($nextmode && ref($menu{$nextmode}->{list})) {
	    Slim::Buttons::Common::pushModeLeft(
		$client,
		"plugins-information-$nextmode",
	    );
	}
	else {
	    Slim::Display::Animation::bumpRight($client);
	}
    },
    'up' => sub {
	my $client = shift;
	my $ref = $context{$client};

	$ref->{$ref->{current}} = Slim::Buttons::Common::scroll(
	    $client,
	    -1,
	    ($#{$ref->{list}} + 1),
	    $ref->{$ref->{current}},
	);
	$client->update();
    },
    'down' => sub {
	my $client = shift;
	my $ref = $context{$client};

	$ref->{$ref->{current}} = Slim::Buttons::Common::scroll(
	    $client,
	    1,
	    ($#{$ref->{list}} + 1),
	    $ref->{$ref->{current}},
	);
	$client->update();
    },
);

#
#	find_nextmode()
#	---------------
#	Return the name of the next mode when moving from the current
#	list to a sub-list.
#
#	Context keys used:
#
#	    current	The name of the current list
#	    (menuname)  Used as $ref->{$ref->{current}} which is the current
#			position within the current list, numbered from zero
#	    list	The current list data, stored as an arrayref
#
sub find_nextmode {
    my $ref = $context{(shift)};
    my $nextmode = $ref->{list}->[$ref->{$ref->{current}}];

    return ref($nextmode) ? undef : $nextmode;
}

#
#	main_lines()
#	------------
#	Create and return the two-line display for the main menu.
#
sub main_lines {
    my $client = shift;
    my $ref = $context{$client};
    my $current = $ref->{$ref->{current}};
    my $list = $ref->{list};

    return (
    	(
	    string('PLUGIN_INFORMATION_MODULE_NAME') .
	    ' (' .
	    ($current + 1) .
	    ' ' .
	    string('OF') .
	    ' ' .
	    ($#$list + 1) .
	    ')'
	),
	string(
	    'PLUGIN_INFORMATION_MENU_' .
	    uc($list->[$current])
	),
	undef,
	Slim::Hardware::VFD::symbol('rightarrow'),
    );
}	

#
#	info_lines()
#	------------
#	Create and return the two-line display for the various information
#	items (except module information).
#
sub info_lines {
    my $client = shift;
    my $ref = $context{$client};
    my $current = $ref->{$ref->{current}};
    my $item = $ref->{list}->[$current];

    return (
	(
	    string('PLUGIN_INFORMATION_MENU_' . uc($ref->{current})) .
	    ' (' .
	    ($current + 1) .
	    ' ' .
	    string('OF') .
	    ' ' .
	    ($#{$ref->{list}} + 1) .
	    ')'
	),
	(
	    string('PLUGIN_INFORMATION_' . uc($item->[0])) .
	    ': ' .
	    $format{$item->[1]}->($item->[3]->($item->[2] ? $client : undef))
	)
    );
}	

#
#	module_lines()
#	--------------
#	Create and return the two-line display for the module information.
#
sub module_lines {
    my $client = shift;
    my $ref = $context{$client};
    my $current = $ref->{$ref->{current}};
    my $item = $ref->{list}->[$current];
    my @lines;
    my @info;

    $lines[0] = (
	string('PLUGIN_INFORMATION_MENU_' . uc($ref->{current})) .
	' (' .
	($current + 1) .
	' ' .
	string('OF') .
	' ' .
	($#{$ref->{list}} + 1) .
	') ' .
	"${item}"
    );

    push(@info,$modules->{$item});
    push(@info,string('PLUGIN_INFORMATION_DISABLED')) unless $enabled{$item};

    my $version = eval {
	no strict 'refs';
	${"Plugins::${item}::VERSION"};
    };
    if ($@ || !$version) {
	push(@info,string('PLUGIN_INFORMATION_NO_VERSION'));
    }
    else {
    	$version =~ s/^\s+//;
    	$version =~ s/\s+$//;
	push(@info,string('PLUGIN_INFORMATION_VERSION') . ": $version");
    }

# disabling, since we don't have all the plugins in one folder.
if (0) {
    my $filename = catfile(
        Slim::Buttons::Plugins::pluginDir(),
	"${item}.pm"
    );

    my $date = Slim::Utils::Strings::string('PLUGIN_INFORMATION_DATE_FORMAT');
    $date =~ s/\${(\w+?)}/Slim::Utils::Prefs::get($1)/eg;
    $date =~ s/:%S//;
    $date = strftime($date,localtime((stat($filename))[9] || 0)),
    $date =~ s/\|0?(\d+)/$1/g;

    push(@info,string('PLUGIN_INFORMATION_INSTALLED') . ": $date");
}

    $lines[1] = join(' ' . Slim::Hardware::VFD::symbol('rightarrow') . ' ',@info);
    @lines;
}	

#
#	strings()
#	---------
#	Read the string localisation data.
#
sub strings {
    local $/ = undef;
    <DATA>;
}

sub setmode_submenu {
    my $client = shift;
    my $ref = $context{$client};

    $ref->{current} = $ref->{list}->[$ref->{$ref->{current}}];
    $ref->{list} = $menu{$ref->{current}}->{list};
    $ref->{$ref->{current}} ||= 0;

    $client->lines($menu{$ref->{current}}->{lines});
    $client->update();
}

sub setMode {
    my $client = shift;

    unless ($modes_set) {
    	$modes_set = 1;
	foreach (keys %menu) {
	    next if $_ eq 'main';

	    Slim::Buttons::Common::addMode(
		"plugins-information-$_",
		\%functions,
		\&setmode_submenu,
	    );
	}
    }
    unless (ref($modules)) {
	$modules = Slim::Buttons::Plugins::installedPlugins();
	@module_list = sort { $modules->{$a} cmp $modules->{$b} } keys %$modules;
	$enabled{$_} = 1 for (Slim::Buttons::Plugins::enabledPlugins($client));
    }

    $context{$client}->{current} = 'main';
    $context{$client}->{list} = \@main_list,
    $context{$client}->{main} ||= 0;

    $client->lines(\&main_lines);
    $client->update();
}

sub getFunctions {
    \%functions;
}

sub getDisplayName {
    string('PLUGIN_INFORMATION_MODULE_NAME');
}

1;

__DATA__

PLUGIN_INFORMATION_MODULE_NAME
	EN	SLIMP3 Information
	FR	Infos SLIMP3

PLUGIN_INFORMATION_MENU_PLAYER
	EN	Player Information
	FR	Infos lecteur

PLUGIN_INFORMATION_MENU_SERVER
	EN	Server Information
	FR	Infos serveur

PLUGIN_INFORMATION_MENU_LIBRARY
	EN	Library statistics
	FR	Statistiques

PLUGIN_INFORMATION_MENU_MODULE
	EN	Plugin Modules
	FR	Modules plugins

PLUGIN_INFORMATION_PLAYER_NAME
	EN	Player Name
	FR	Nom lecteur

PLUGIN_INFORMATION_PLAYER_MODEL
	EN	Player Model
	FR	Modele lecteur

PLUGIN_INFORMATION_FIRMWARE
	EN	Player Firmware Version
	FR	Version firmware lecteur

PLUGIN_INFORMATION_PLAYER_IP
	EN	Player IP Address
	FR	Adresse IP lecteur

PLUGIN_INFORMATION_PLAYER_PORT
	EN	Player UDP Port Number
	FR	Port UDP lecteur

PLUGIN_INFORMATION_PLAYER_MAC
	EN	Player MAC Address
	FR	Adresse MAC lecteur

PLUGIN_INFORMATION_VERSION
	EN	Server Version
	FR	Version serveur

PLUGIN_INFORMATION_CLIENTS
	EN	Total Players Recognised
	FR	Lecteur(s) identifié(s)

PLUGIN_INFORMATION_SERVER_IP
	EN	Server IP Address
	FR	Adresse IP serveur

PLUGIN_INFORMATION_SERVER_PORT
	EN	Server UDP Port Number
	FR	Port UDP serveur

PLUGIN_INFORMATION_SERVER_HTTP
	EN	Server HTTP Port Number
	FR	Port HTTP serveur

PLUGIN_INFORMATION_ALBUMS
	EN	Total Albums
	FR	Albums

PLUGIN_INFORMATION_ARTISTS
	EN	Total Artists
	FR	Artistes

PLUGIN_INFORMATION_GENRES
	EN	Total Genres
	FR	Genres

PLUGIN_INFORMATION_TRACKS
	EN	Total Tracks
	FR	Morceaux

PLUGIN_INFORMATION_TIME
	EN	Total Playing Time
	FR	Durée totale

PLUGIN_INFORMATION_VERSION
	EN	Version
	FR	Version

PLUGIN_INFORMATION_INSTALLED
	EN	Installed
	FR	Installé

PLUGIN_INFORMATION_DISABLED
	EN	DISABLED
	FR	DESACTIVE

PLUGIN_INFORMATION_NO_VERSION
	EN	No version number
	FR	Pas de version

PLUGIN_INFORMATION_DATE_FORMAT
	EN	${shortdateFormat} at ${timeFormat}
	FR	${shortdateFormat} à ${timeFormat}

