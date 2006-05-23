package Slim::Formats::Parse;

# $Id$

# SlimServer Copyright (c) 2001-2006 Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;

use Slim::Formats::Playlists;
use Slim::Player::ProtocolHandlers;
use Slim::Utils::Misc;

sub registerParser {

	msg("Warning! - Slim::Formats::Parse::registerParser is deprecated!\n");
	msg("Please update your code to use: Slim::Formats::Playlists->registerParser(\$type, \$playlistClass)\n");
	msg("Make sure your \$playlistClass has a ->read() method, and an optional ->write() method\n");
	bt();
}

sub parseList {

	msg("Warning! - Slim::Formats::Parse::parseList is deprecated!\n");
	msg("Please update your call to be Slim::Formats::Playlists->parseList()\n");
	bt();

	return Slim::Formats::Playlists->parseList(@_);
}

sub writeList {

	msg("Warning! - Slim::Formats::Parse::writeList is deprecated!\n");
	msg("Please update your call to be Slim::Formats::Playlists->writeList()\n");
	bt();

	return Slim::Formats::Playlists->writeList(@_);
}

sub _updateMetaData {

	msg("Warning! - Slim::Formats::Parse::_updateMetaData is deprecated!\n");
	msg("Please update your code to inherit from Slim::Formats::Playlists::Base\n");
	bt();

	return Slim::Formats::Playlists::Base->_updateMetaData(@_);
}

sub readM3U {
	msg("Warning! - Slim::Formats::Parse::readM3U is deprecated!\n");
	msg("Please update your code to call Slim::Formats::Playlists::M3U->read()\n");
	bt();

	return Slim::Formats::Playlists::M3U->read(@_);
}

sub readPLS {
	msg("Warning! - Slim::Formats::Parse::readPLS is deprecated!\n");
	msg("Please update your code to call Slim::Formats::Playlists::PLS->read()\n");
	bt();

	return Slim::Formats::Playlists::PLS->read(@_);
}

sub writeM3U {
	msg("Warning! - Slim::Formats::Parse::writeM3U is deprecated!\n");
	msg("Please update your code to call Slim::Formats::Playlists::M3U->write()\n");
	bt();

	return Slim::Formats::Playlists::M3U->write(@_);
}

1;

__END__
