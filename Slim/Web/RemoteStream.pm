package Slim::Web::RemoteStream;

# $Id$

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;

use Slim::Player::Source;
use Slim::Utils::Misc;

# Kept around for compatibility with older plugins

sub openRemoteStream {

	warn "Please update your plugin! Use Slim::Player::Source::openRemoteStream() instead.";

	Slim::Utils::Misc::bt();

	return Slim::Player::Source::openRemoteStream(@_);
}

1;
__END__
