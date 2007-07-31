package Slim::Web::Settings::Server::FileSelector;

# SlimServer Copyright (c) 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;
use Slim::Utils::Filesystem;

my $pages = {
	'autocomplete' => 'settings/server/fileselector_autocomplete.html',
	'fileselector' => 'settings/server/fileselector.html'
};

sub new {
	my $class = shift;

	Slim::Web::HTTP::addPageFunction($pages->{'autocomplete'}, \&autoCompleteHandler);

	$class->SUPER::new($class);
}

sub page {
	return $pages->{'fileselector'};
}

sub handler {
	my ($class, $client, $paramRef, $pageSetup) = @_;

	$paramRef->{'folders'} = Slim::Utils::Filesystem::getChildren($paramRef->{'currDir'}, $paramRef->{'foldersonly'} ? sub { -d } : undef);

	return Slim::Web::HTTP::filltemplatefile($class->page, $paramRef);
}

sub autoCompleteHandler {
	my ($client, $paramRef) = @_;

	$paramRef->{'folders'} = Slim::Utils::Filesystem::getChildren($paramRef->{'currDir'}, $paramRef->{'foldersonly'} ? sub { -d } : undef);

	return Slim::Web::HTTP::filltemplatefile($pages->{'autocomplete'}, $paramRef);	
}

1;

__END__
