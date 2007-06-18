package Slim::Web::Settings;

# $Id$

# SlimServer Copyright (c) 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

# This is a base class for all the server settings pages.

use strict;

use Slim::Utils::Log;
use Slim::Web::HTTP;
use Slim::Web::Pages;

use Scalar::Util qw(blessed);

sub new {
	my $class = shift;

	if ($class->can('page') && $class->can('handler') && $class->page) {

		Slim::Web::HTTP::addPageFunction($class->page, $class);
	}

	if ($class->can('page') && $class->can('name') && $class->page && $class->name) {

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

sub prefs {
	return ();
}

sub handler {
	my ($class, $client, $paramRef, $pageSetup) = @_;

	# Handle the simple case where validation is done by prefs obj.
	my ($prefsClass, @prefs) = $class->prefs($client);

	my (@valid);

	for my $pref (@prefs) {

		if ($paramRef->{'saveSettings'}) {

			my (undef, $ok) = $prefsClass->set($pref, $paramRef->{$pref});

			if ($ok) {
				$paramRef->{'validated'}->{$pref} = 1; 
			}
			else { 
				$paramRef->{'warning'} .= sprintf(Slim::Utils::Strings::string('SETTINGS_INVALIDVALUE'), $paramRef->{$pref}, $pref) . '<br/>';
				$paramRef->{'validated'}->{$pref} = 0;
			}
		}

		$paramRef->{'validate'}->{$pref} = $prefsClass->hasValidator($pref);			
		$paramRef->{'prefs'}->{$pref} = $prefsClass->get($pref);
	}

	if ($prefsClass) {
		$paramRef->{'namespace'} = $prefsClass->namespace;
	}

	if ($paramRef->{'saveSettings'} && !$paramRef->{'warning'}) {
		$paramRef->{'warning'} = Slim::Utils::Strings::string('SETUP_CHANGES_SAVED');
	}	

	# Common values
	$paramRef->{'page'} = $class->name;

	# Needed to generate the drop down settings chooser list.
	$paramRef->{'additionalLinks'} = \%Slim::Web::Pages::additionalLinks;

	if (defined $client) {
		$paramRef->{'playername'} = $client->name();
	}

	return Slim::Web::HTTP::filltemplatefile($paramRef->{'useAJAX'} ? 'settings/ajaxSettings.txt' : $class->page, $paramRef);
}

1;

__END__
