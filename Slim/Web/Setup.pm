package Slim::Web::Setup;

# $Id$

# SqueezeCenter Copyright 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use Slim::Utils::Log;

sub initSetup {

	eval "
		use Slim::Web::Settings::Player::Alarm;
		use Slim::Web::Settings::Player::Audio;
		use Slim::Web::Settings::Player::Basic;
		use Slim::Web::Settings::Player::Display;
		use Slim::Web::Settings::Player::Menu;
		use Slim::Web::Settings::Player::Remote;
		use Slim::Web::Settings::Player::Synchronization;
		
		use Slim::Web::Settings::Server::Basic;
		use Slim::Web::Settings::Server::Behavior;
		use Slim::Web::Settings::Server::Debugging;
		use Slim::Web::Settings::Server::FileSelector;
		use Slim::Web::Settings::Server::FileTypes;
		use Slim::Web::Settings::Server::Index;
		use Slim::Web::Settings::Server::Network;
		use Slim::Web::Settings::Server::Performance;
		use Slim::Web::Settings::Server::Plugins;
		use Slim::Web::Settings::Server::Security;
		use Slim::Web::Settings::Server::Software;
		use Slim::Web::Settings::Server::SqueezeNetwork;
		use Slim::Web::Settings::Server::Status;
		use Slim::Web::Settings::Server::TextFormatting;
		use Slim::Web::Settings::Server::UserInterface;
		use Slim::Web::Settings::Server::Wizard;
	";

	if (!$@) {

		$class->new;

	} else {

		logError ("can't load $class - $@");
	}
}

1;

__END__
