package Slim::Web::Settings::Server::FileSelector;

# SlimServer Copyright (c) 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;
use Slim::Utils::Filesystem;

sub page {
	return 'settings/server/fileselector.html';
}

sub handler {
	my ($class, $client, $paramRef, $pageSetup) = @_;

	$paramRef->{'folders'} = Slim::Utils::Filesystem::getChildren($paramRef->{'currDir'}, $paramRef->{'foldersonly'} ? sub { -d } : undef);

	return Slim::Web::HTTP::filltemplatefile($class->page, $paramRef);
}

1;

__END__
