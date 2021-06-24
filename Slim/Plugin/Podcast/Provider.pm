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
	my ($self, $content) = @_;
	return {
		index => 0,
		feeds => $content,
	};
}

sub parseStop { }


1;