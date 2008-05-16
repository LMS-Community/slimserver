#    Copyright (c) 2008 Erland Isaksson (erland_i@hotmail.com)
# 
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program; if not, write to the Free Software
#    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
package Slim::Plugin::ABTester::Settings;

use strict;
use base qw(Slim::Web::Settings);

use File::Basename;
use File::Next;

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Misc;
use Slim::Utils::Strings;

my $prefs = preferences('plugin.abtester');

my $plugin; # reference to main plugin

sub new {
	my $class = shift;
	$plugin   = shift;

	Slim::Web::HTTP::addPageFunction($class->page, $class);
	$class->SUPER::new();
}

sub name {
	return 'PLUGIN_ABTESTER';
}

sub page {
	return 'plugins/ABTester/settings/basic.html';
}

sub prefs {
        return ($prefs, qw(restrictedtohardware autoupdate defaultimage scriptdir));
}
sub handler {
	my ($class, $client, $paramRef) = @_;
	return $class->SUPER::handler($client, $paramRef);
}

		
1;
