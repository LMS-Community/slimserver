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

		if ($class->needsClient) {
			Slim::Web::Pages->addPageLinks('playersetup', { $class->name => $class->page });
		} else {
			Slim::Web::Pages->addPageLinks('setup', { $class->name => $class->page });
		}
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

sub needsClient {
	my $class = shift;
	
	return 0;
}

sub handler {
	my ($class, $client, $paramRef, $pageSetup) = @_;

	$paramRef->{'page'} = $class->name;

	# Needed to generate the drop down settings chooser list.
	$paramRef->{'additionalLinks'} = \%Slim::Web::Pages::additionalLinks;
	
	if (defined $client) {
		$paramRef->{'playername'} = $client->name();
	}

	return Slim::Web::HTTP::filltemplatefile($class->page, $paramRef);
}

sub _handleChanges {
	my ($class, $client, $prefs, $paramRef) = @_;
	
	$paramRef->{'warning'} = Slim::Utils::Strings::string('SETTINGS_CHANGED').'<br>'.join('<br>',@{$prefs});
}

1;

__END__
