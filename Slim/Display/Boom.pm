package Slim::Display::Boom;

# SqueezeCenter Copyright 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

# $Id$

=head1 NAME

Slim::Display::Squeezebox2

=head1 DESCRIPTION

L<Slim::Display::Boom>
 Display class for Boom class display
  - 160 x 32 pixel display
  - client side animations

=cut

use strict;

use base qw(Slim::Display::Squeezebox2);

use Slim::Utils::Prefs;

my $prefs = preferences('server');

# FIXME: Use correct display modes
our $defaultPrefs = {
	'idleBrightness'      => 2,
	'playingDisplayMode'  => 5,
	'playingDisplayModes' => [0..11]
};

our $defaultFontPrefs = {
	'activeFont'          => [qw(light_n standard_n full_n)],
	'activeFont_curr'     => 1,
	'idleFont'            => [qw(light_n standard_n full_n)],
	'idleFont_curr'       => 1,
};

sub init {
	my $display = shift;

	# load fonts for this display if not already loaded and remember to load at startup in future
	if (!$prefs->get('loadFontsSqueezebox2')) {
		$prefs->set('loadFontsSqueezebox2', 1);
		Slim::Display::Lib::Fonts::loadFonts(1);
	}

	$prefs->client($display->client)->init($defaultPrefs);
	$prefs->client($display->client)->init($defaultFontPrefs);

	$display->SUPER::init();

	$display->validateFonts($defaultFontPrefs);
}

sub displayWidth {
	return shift->widthOverride(@_) || 160;
}

sub vfdmodel {
	return 'graphic-160x32';
}

=head1 SEE ALSO

L<Slim::Display::Graphics>

=cut

1;

