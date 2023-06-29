package Slim::Plugin::ZenRadio::Plugin;

# Logitech Media Server Copyright 2001-2023 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Plugin::AudioAddict::Plugin);

sub network { 'zenradio' }
sub servicePageLink { 'PLUGIN_ZENRADIO_LINK' }

1;