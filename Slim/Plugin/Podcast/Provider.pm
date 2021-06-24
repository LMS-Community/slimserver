package Slim::Plugin::Podcast::Provider;

# Logitech Media Server Copyright 2005-2020 Logitech.

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

sub new {
	return bless { }, shift;
}

sub getMenuItems { [ { } ] }

sub parseStart {
	return {
		index => 0,
		feeds => $_[1],
	};
}


1;