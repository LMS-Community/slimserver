package Slim::Plugin::Podcast::Provider;

# Logitech Media Server Copyright 2005-2020 Logitech.

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use base qw(Slim::Utils::Accessor);

__PACKAGE__->mk_accessor('rw', qw(result title feed image description author language));

sub new {
	return shift->SUPER::new;
}

sub getItems { [ { } ] }


1;