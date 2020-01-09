package Slim::Web::Settings::Server::Debugging;


# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Log;
use Slim::Utils::Strings qw(string);

sub name {
	return Slim::Web::HTTP::CSRF->protectName('DEBUGGING_SETTINGS');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('settings/server/debugging.html');
}

sub handler {
	my ($class, $client, $paramRef, $pageSetup) = @_;

	# If this is a settings update
	if ($paramRef->{'saveSettings'}) {

		my $categories = Slim::Utils::Log->allCategories;

		if ($paramRef->{'logging_group'}) {

			Slim::Utils::Log->setLogGroup($paramRef->{'logging_group'});

		}

		else {

			for my $category (keys %{$categories}) {
	
				Slim::Utils::Log->setLogLevelForCategory(
					$category, $paramRef->{$category}
				);
			}
		}

		Slim::Utils::Log->persist($paramRef->{'persist'} ? 1 : 0);

		# $paramRef might have the overwriteCustomConfig flag.
		Slim::Utils::Log->reInit($paramRef);
	}

	# Pull in the dynamic debugging levels.
	my $debugCategories = Slim::Utils::Log->allCategories;
	my @validLogLevels  = Slim::Utils::Log->validLevels;
	my @categories      = (); 

	for my $debugCategory (sort keys %{$debugCategories}) {

		my $string = Slim::Utils::Log->descriptionForCategory($debugCategory);

		push @categories, {
			'label'   => Slim::Utils::Strings::getString($string),
			'name'    => $debugCategory,
			'current' => $debugCategories->{$debugCategory},
		};
	}
	
	$paramRef->{'logging_groups'} = Slim::Utils::Log->logGroups();

	$paramRef->{'categories'} = \@categories;
	$paramRef->{'logLevels'}  = \@validLogLevels;
	$paramRef->{'persist'}    = Slim::Utils::Log->persist;

	$paramRef->{'logs'} = Slim::Utils::Log->getLogFiles();

	return $class->SUPER::handler($client, $paramRef, $pageSetup);
}

1;

__END__
