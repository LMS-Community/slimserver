package Slim::Web::RemoteStream;

# $Id: RemoteStream.pm,v 1.28 2004/09/23 21:59:04 vidur Exp $

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;

use Slim::Utils::Misc;

# Kept around for compatibility with older plugins

sub openRemoteStream {
    return Slim::Player::Source::openRemoteStream(@_);
}

1;
__END__
