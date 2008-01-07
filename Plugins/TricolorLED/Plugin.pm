#	TricolorLED.pm
#
#	Author: Felix Mueller <felix(dot)mueller(at)gwendesign(dot)com>
#
#	Copyright (c) 2003-2008 by GWENDESIGN
#	All rights reserved.
#
#	----------------------------------------------------------------------
#	Tricolor LED
#	----------------------------------------------------------------------
#	Function:
#
#	----------------------------------------------------------------------
#	History:
#
#	2007/12/22 v0.2 - Only for Ray
#	2007/08/12 v0.1	- Initial version
#	---------------------------------------------------------------------
#	To do:
#
#	- Clean up code
#
# This code is derived from code with the following copyright message:
#
# SqueezeCenter Copyright (c) 2001-2008 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

package Plugins::TricolorLED::Plugin;
use base qw(Slim::Plugin::Base);
use strict;

use Slim::Utils::Strings qw(string);
use Slim::Utils::Log;
use Slim::Utils::Prefs;

use File::Spec::Functions qw(:ALL);
use FindBin qw($Bin);

use Plugins::TricolorLED::Settings;


# ----------------------------------------------------------------------------
# Global variables
# ----------------------------------------------------------------------------

# ----------------------------------------------------------------------------
# References to other classes
my $classPlugin = undef;

# ----------------------------------------------------------------------------
my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.tricolorled',
	'defaultLevel' => 'OFF',
	'description'  => 'PLUGIN_TRICOLORLED_MODULE_NAME',
});

# ----------------------------------------------------------------------------
my $prefs = preferences( 'plugin.tricolorled');

# ----------------------------------------------------------------------------
sub getDisplayName {
	return 'PLUGIN_TRICOLORLED_MODULE_NAME';
}

# ----------------------------------------------------------------------------
sub initPlugin {
	$classPlugin = shift;

	# Initialize settings classes
	my $classSettings = Plugins::TricolorLED::Settings->new( $classPlugin);

# Not calling our parent class prevents us from getting added in the player UI
#	$classPlugin->SUPER::initPlugin();
}

# ----------------------------------------------------------------------------
sub shutdownPlugin {

}

my %g_rgb;

# ----------------------------------------------------------------------------
sub setColorRed {
	my $class = shift;
	my $client = shift;
	my $value = shift;

	$g_rgb{$client} = $g_rgb{$client} & 0x0000FFFF;
	$g_rgb{$client} = $g_rgb{$client} | ( hex( $value) << 16);
}

# ----------------------------------------------------------------------------
sub setColorGreen {
	my $class = shift;
	my $client = shift;
	my $value = shift;

	$g_rgb{$client} = $g_rgb{$client} & 0x00FF00FF;
	$g_rgb{$client} = $g_rgb{$client} | ( hex( $value) << 8);
}

# ----------------------------------------------------------------------------
sub setColorBlue {
	my $class = shift;
	my $client = shift;
	my $value = shift;

	$g_rgb{$client} = $g_rgb{$client} & 0x00FFFF00;
	$g_rgb{$client} = $g_rgb{$client} | ( hex( $value) << 0);
}

# ----------------------------------------------------------------------------
sub sendColor {
	my $class = shift;
	my $client = shift;
	my $transition = shift;

	my $cmd = pack( 'N', $g_rgb{$client});
	$cmd .= pack( 'n', 0x0000);	# on time	= -> do not blink
	$cmd .= pack( 'n', 0x00FF);	# off time
	$cmd .= pack( 'C', 0x0A);	# times		0 -> blink forever
	$cmd .= pack( 'C', $transition);	# transition
	$client->sendFrame( 'ledc', \$cmd);
}

# ----------------------------------------------------------------------------
sub getColorRed {
	my $class = shift;
	my $client = shift;

	return sprintf( "%X", ( $g_rgb{$client} & 0x00FF0000) >> 16);
}

# ----------------------------------------------------------------------------
sub getColorGreen {
	my $class = shift;
	my $client = shift;

	return sprintf( "%X", ( $g_rgb{$client} & 0x0000FF00) >> 8);
}

# ----------------------------------------------------------------------------
sub getColorBlue {
	my $class = shift;
	my $client = shift;

	return sprintf( "%X", ( $g_rgb{$client} & 0x000000FF) >> 0);
}

1;

__END__

