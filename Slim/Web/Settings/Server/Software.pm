package Slim::Web::Settings::Server::Software;

# $Id: Software.pm 15258 2007-12-13 15:29:14Z mherger $

# SqueezeCenter Copyright 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;
use Slim::Utils::OSDetect;

sub name {
	return Slim::Web::HTTP::protectName('SETUP_CHECKVERSION');
}

sub page {
	return Slim::Web::HTTP::protectURI('settings/server/software.html');
}

sub prefs {
	my @prefs = qw(checkVersion);
	
	if (Slim::Utils::OSDetect->getOS()->canAutoUpdate()) {
		push @prefs, 'autoDownloadUpdate';
	}
	return (preferences('server'), qw(checkVersion));
}

sub handler {
	my ($class, $client, $paramRef) = @_;
	
	$paramRef->{canAutoUpdate} = Slim::Utils::OSDetect->getOS()->canAutoUpdate();

	return $class->SUPER::handler($client, $paramRef);
}

1;

__END__
