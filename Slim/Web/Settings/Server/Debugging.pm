package Slim::Web::Settings::Server::Debugging;

# $Id$

# SlimServer Copyright (c) 2001-2006 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Log;
use Slim::Utils::Strings qw(string);

sub name {
	return 'DEBUGGING_SETTINGS';
}

sub page {
	return 'settings/server/debugging.html';
}

sub handler {
	my ($class, $client, $paramRef, $pageSetup) = @_;

	# If this is a settings update
	if ($paramRef->{'saveSettings'}) {

		my $categories = Slim::Utils::Log->allCategories;

		for my $category (keys %{$categories}) {

			Slim::Utils::Log->setLogLevelForCategory(
				$category, $paramRef->{$category}
			);
		}

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
			'label'   => string($string),
			'name'    => $debugCategory,
			'current' => $debugCategories->{$debugCategory},
		};
	}

	#$paramRef->{'categories'} = [ sort { $a->{'label'} cmp $b->{'label'} } @categories ];
	$paramRef->{'categories'} = \@categories;
	$paramRef->{'logLevels'}  = \@validLogLevels;

	$paramRef->{'debugServerLog'}  = Slim::Utils::Log->serverLogFile;
	$paramRef->{'debugScannerLog'} = Slim::Utils::Log->scannerLogFile;

	return $class->SUPER::handler($client, $paramRef, $pageSetup);
}

1;

__END__
