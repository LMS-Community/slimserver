package Slim::Plugin::JazzRadio::Plugin;

# Logitech Media Server Copyright 2001-2024 Logitech.
# Lyrion Music Server Copyright 2024 Lyrion Community.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Plugin::AudioAddict::Plugin);

sub network { 'jazzradio' }
sub servicePageLink { 'PLUGIN_JAZZRADIO_LINK' }

1;
