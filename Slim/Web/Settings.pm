package Slim::Web::Settings;

# $Id$

# SlimServer Copyright (c) 2001-2006 Logitech.
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

	# Handle the simple case where no validation is needed. Or we can do
	# programatic validation via the prefs rework.
	my @prefs = $class->needsClient ? $class->prefs($client) : $class->prefs;

	my $prefsClass = shift @prefs if (@prefs && blessed($prefs[0]));

	for my $pref (@prefs) {

		if ($paramRef->{'saveSettings'}) {

			if ($prefsClass) {

				my (undef, $ok) = $prefsClass->set($pref, $paramRef->{$pref});

				if (!$ok) {
					$paramRef->{'warning'} .= sprintf(Slim::Utils::Strings::string('SETTINGS_INVALIDVALUE'), $paramRef->{$pref}, $pref);
				}

			} else {

				Slim::Utils::Prefs::set($pref, $paramRef->{$pref});
			}
		}

		if ($prefsClass) {

			$paramRef->{'prefs'}->{$pref} = $prefsClass->get($pref);

		} else {

			$paramRef->{'prefs'}->{$pref} = Slim::Utils::Prefs::get($pref);
		}
	}

	# Common values
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
	
	$paramRef->{'warning'} .= Slim::Utils::Strings::string('SETTINGS_CHANGED').'<br>'.join('<br>',@{$prefs});
}

1;

__END__
