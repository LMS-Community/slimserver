package Slim::Web::Settings;

# $Id$

# SlimServer Copyright (c) 2001-2006 Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

# This is a base class for all the server settings pages.

use strict;

use Slim::Utils::Log;
use Slim::Web::HTTP;
use Slim::Web::Pages;

sub new {
	my $class = shift;

	if ($class->can('page') && $class->can('handler')) {

		Slim::Web::HTTP::addPageFunction($class->page, $class);
	}

	if ($class->can('page') && $class->can('name')) {

		Slim::Web::Pages->addPageLinks('setup', { $class->name => $class->page });
	}
}

sub name {
	my $class = shift;

	return '';
}

sub page {
	my $class = shift;

	return '';
}

sub handler {
	my ($class, $client, $paramRef, $pageSetup) = @_;

	$paramRef->{'page'} = $class->name;

        # Needed to generate the drop down settings chooser list.
        $paramRef->{'additionalLinks'} = \%Slim::Web::Pages::additionalLinks;

	return Slim::Web::HTTP::filltemplatefile($class->page, $paramRef);
}

1;

__END__
